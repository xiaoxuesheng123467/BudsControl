package com.qiao.budscontrol;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;
import android.os.Handler;
import android.os.Looper;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Arrays;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

final class BudsConnectionManager {
    enum State {
        DISCONNECTED,
        CONNECTING,
        CONNECTED
    }

    interface Listener {
        void onConnectionState(State state, String detail);
        void onBattery(int left, int right, int chargingCase);
        void onExtendedStatus(byte[] payload);
        void onFitResult(int left, int right);
        void onFindStopped();
    }

    interface CommandCallback {
        void onComplete(boolean success, boolean acknowledged, String detail);
    }

    private final BluetoothAdapter adapter;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService connectionExecutor = Executors.newSingleThreadExecutor();
    private final ExecutorService readerExecutor = Executors.newSingleThreadExecutor();
    private final Object socketLock = new Object();
    private final Object writeLock = new Object();
    private final Object pendingLock = new Object();

    private volatile Listener listener;
    private volatile State state = State.DISCONNECTED;
    private volatile BluetoothSocket socket;
    private volatile OutputStream outputStream;
    private volatile boolean closed;
    private byte[] receiveBuffer = new byte[0];

    private int pendingMessageId = -1;
    private byte[] pendingPrefix;
    private CountDownLatch pendingLatch;
    private boolean pendingMatched;

    BudsConnectionManager(BluetoothAdapter adapter) {
        this.adapter = adapter;
    }

    void setListener(Listener listener) {
        this.listener = listener;
    }

    State getState() {
        return state;
    }

    @SuppressLint("MissingPermission")
    void connect(BluetoothDevice device) {
        if (closed) return;
        closeSocket(false);
        updateState(State.CONNECTING, "正在连接 " + safeName(device));
        connectionExecutor.execute(() -> {
            BluetoothSocket candidate = null;
            try {
                candidate = device.createRfcommSocketToServiceRecord(BudsProtocol.SAMSUNG_SERVICE_UUID);
                synchronized (socketLock) {
                    if (closed) {
                        candidate.close();
                        return;
                    }
                    socket = candidate;
                }
                candidate.connect();
                InputStream input = candidate.getInputStream();
                outputStream = candidate.getOutputStream();
                receiveBuffer = new byte[0];
                updateState(State.CONNECTED, "已直连 " + safeName(device));
                startReader(candidate, input);
                writePacket(BudsProtocol.stateRequest());
            } catch (SecurityException error) {
                closeQuietly(candidate);
                closeSocket(false);
                updateState(State.DISCONNECTED, "缺少附近设备权限");
            } catch (IOException error) {
                closeQuietly(candidate);
                closeSocket(false);
                updateState(State.DISCONNECTED, "RFCOMM 连接失败：" + safeMessage(error));
            }
        });
    }

    void disconnect() {
        closeSocket(true);
    }

    void send(BudsProtocol.Command command, CommandCallback callback) {
        connectionExecutor.execute(() -> {
            if (state != State.CONNECTED || outputStream == null) {
                postCommand(callback, false, false, "耳机未连接");
                return;
            }

            CountDownLatch latch = command.requiresAcknowledgement ? new CountDownLatch(1) : null;
            if (latch != null) {
                synchronized (pendingLock) {
                    pendingMessageId = command.messageId;
                    pendingPrefix = command.expectedAcknowledgementPrefix == null
                            ? null : command.expectedAcknowledgementPrefix.clone();
                    pendingMatched = false;
                    pendingLatch = latch;
                }
            }

            try {
                writePacket(command.packet());
                if (latch == null) {
                    writePacket(BudsProtocol.stateRequest());
                    postCommand(callback, true, false, "命令已写入，等待状态包确认");
                    return;
                }

                boolean signalled = latch.await(2, TimeUnit.SECONDS);
                boolean acknowledged;
                synchronized (pendingLock) {
                    acknowledged = signalled && pendingMatched;
                    if (pendingLatch == latch) clearPendingLocked();
                }
                if (acknowledged) {
                    writePacket(BudsProtocol.stateRequest());
                    postCommand(callback, true, true, "耳机已确认命令");
                } else {
                    postCommand(callback, false, false, "耳机未在 2 秒内确认命令");
                }
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
                synchronized (pendingLock) {
                    if (pendingLatch == latch) clearPendingLocked();
                }
                postCommand(callback, false, false, "命令等待被中断");
            } catch (IOException error) {
                synchronized (pendingLock) {
                    if (pendingLatch == latch) clearPendingLocked();
                }
                closeSocket(false);
                updateState(State.DISCONNECTED, "蓝牙写入失败：" + safeMessage(error));
                postCommand(callback, false, false, "蓝牙写入失败");
            }
        });
    }

    void shutdown() {
        closed = true;
        closeSocket(false);
        connectionExecutor.shutdownNow();
        readerExecutor.shutdownNow();
    }

    private void startReader(BluetoothSocket activeSocket, InputStream input) {
        readerExecutor.execute(() -> {
            byte[] chunk = new byte[1024];
            try {
                while (!closed && activeSocket == socket) {
                    int count = input.read(chunk);
                    if (count < 0) throw new IOException("连接已关闭");
                    if (count > 0) appendAndProcess(chunk, count);
                }
            } catch (IOException error) {
                if (!closed && activeSocket == socket) {
                    closeSocket(false);
                    updateState(State.DISCONNECTED, "耳机已断开");
                }
            }
        });
    }

    private void appendAndProcess(byte[] bytes, int count) {
        byte[] combined = Arrays.copyOf(receiveBuffer, receiveBuffer.length + count);
        System.arraycopy(bytes, 0, combined, receiveBuffer.length, count);
        receiveBuffer = combined;

        while (receiveBuffer.length >= 7) {
            if ((receiveBuffer[0] & 0xFF) != 0xFD) {
                int start = 1;
                while (start < receiveBuffer.length && (receiveBuffer[start] & 0xFF) != 0xFD) start++;
                receiveBuffer = Arrays.copyOfRange(receiveBuffer, start, receiveBuffer.length);
                continue;
            }

            int messageSize = (receiveBuffer[1] & 0xFF) | ((receiveBuffer[2] & 0x03) << 8);
            int frameLength = messageSize + 4;
            if (frameLength < 7 || frameLength > 4096) {
                receiveBuffer = Arrays.copyOfRange(receiveBuffer, 1, receiveBuffer.length);
                continue;
            }
            if (receiveBuffer.length < frameLength) return;

            byte[] frame = Arrays.copyOfRange(receiveBuffer, 0, frameLength);
            receiveBuffer = Arrays.copyOfRange(receiveBuffer, frameLength, receiveBuffer.length);
            if (BudsProtocol.hasValidCrc(frame)) processFrame(frame);
        }
    }

    private void processFrame(byte[] frame) {
        int messageId = frame[3] & 0xFF;
        int payloadLength = frame.length - 7;
        if (messageId == BudsProtocol.MESSAGE_ACK && payloadLength >= 1) {
            int commandId = frame[4] & 0xFF;
            byte[] parameters = Arrays.copyOfRange(frame, 5, frame.length - 3);
            synchronized (pendingLock) {
                if (pendingLatch != null && pendingMessageId == commandId && prefixMatches(parameters, pendingPrefix)) {
                    pendingMatched = true;
                    pendingLatch.countDown();
                }
            }
            return;
        }

        Listener current = listener;
        if (current == null) return;
        if (messageId == BudsProtocol.MESSAGE_STATUS && frame.length >= 14) {
            int left = validBattery(frame[5]);
            int right = validBattery(frame[6]);
            int chargingCase = validBattery(frame[10]);
            mainHandler.post(() -> current.onBattery(left, right, chargingCase));
        } else if (messageId == BudsProtocol.MESSAGE_EXTENDED_STATUS && payloadLength >= 8) {
            byte[] payload = Arrays.copyOfRange(frame, 4, frame.length - 3);
            int left = validBattery(frame[6]);
            int right = validBattery(frame[7]);
            int chargingCase = validBattery(frame[11]);
            mainHandler.post(() -> {
                current.onBattery(left, right, chargingCase);
                current.onExtendedStatus(payload);
            });
        } else if (messageId == BudsProtocol.MESSAGE_FIT_RESULT && payloadLength >= 2) {
            int left = frame[4] & 0xFF;
            int right = frame[5] & 0xFF;
            mainHandler.post(() -> current.onFitResult(left, right));
            send(BudsProtocol.fitTest(false), null);
        } else if (messageId == BudsProtocol.MESSAGE_FIND_STOPPED) {
            mainHandler.post(current::onFindStopped);
        }
    }

    private void writePacket(byte[] packet) throws IOException {
        synchronized (writeLock) {
            OutputStream output = outputStream;
            if (output == null) throw new IOException("输出流不可用");
            output.write(packet);
            output.flush();
        }
    }

    private void closeSocket(boolean notify) {
        BluetoothSocket previous;
        synchronized (socketLock) {
            previous = socket;
            socket = null;
            outputStream = null;
        }
        closeQuietly(previous);
        synchronized (pendingLock) {
            if (pendingLatch != null) pendingLatch.countDown();
            clearPendingLocked();
        }
        if (notify) updateState(State.DISCONNECTED, "已断开");
    }

    private void updateState(State newState, String detail) {
        state = newState;
        Listener current = listener;
        if (current != null) mainHandler.post(() -> current.onConnectionState(newState, detail));
    }

    private void postCommand(CommandCallback callback, boolean success, boolean acknowledged, String detail) {
        if (callback != null) mainHandler.post(() -> callback.onComplete(success, acknowledged, detail));
    }

    private void clearPendingLocked() {
        pendingMessageId = -1;
        pendingPrefix = null;
        pendingLatch = null;
        pendingMatched = false;
    }

    private static boolean prefixMatches(byte[] parameters, byte[] expected) {
        if (expected == null || expected.length == 0) return true;
        if (parameters.length < expected.length) return false;
        for (int index = 0; index < expected.length; index++) {
            if (parameters[index] != expected[index]) return false;
        }
        return true;
    }

    @SuppressLint("MissingPermission")
    private static String safeName(BluetoothDevice device) {
        try {
            String name = device.getName();
            return name == null || name.isBlank() ? device.getAddress() : name;
        } catch (SecurityException ignored) {
            return "Galaxy Buds";
        }
    }

    private static int validBattery(byte value) {
        int battery = value & 0xFF;
        return battery <= 100 ? battery : -1;
    }

    private static String safeMessage(Exception error) {
        String message = error.getMessage();
        return message == null || message.isBlank() ? error.getClass().getSimpleName() : message;
    }

    private static void closeQuietly(BluetoothSocket socket) {
        if (socket == null) return;
        try {
            socket.close();
        } catch (IOException ignored) {
        }
    }
}

