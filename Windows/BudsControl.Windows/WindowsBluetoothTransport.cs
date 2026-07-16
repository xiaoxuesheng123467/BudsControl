using BudsControl.Core;
using InTheHand.Net;
using InTheHand.Net.Sockets;
using System.IO;

namespace BudsControl.Windows;

public sealed class WindowsBluetoothTransport : IAsyncDisposable
{
    private sealed record PendingAcknowledgement(
        long Generation,
        byte MessageId,
        byte[] Prefix,
        TaskCompletionSource<bool> Completion);

    private static readonly TimeSpan ConnectionTimeout = TimeSpan.FromSeconds(15);
    private static readonly TimeSpan AcknowledgementTimeout = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan LateAcknowledgementDrain = TimeSpan.FromSeconds(1);

    private readonly SemaphoreSlim _sendGate = new(1, 1);
    private readonly object _stateLock = new();
    private BluetoothClient? _client;
    private Stream? _stream;
    private CancellationTokenSource? _readCancellation;
    private PendingAcknowledgement? _pendingAcknowledgement;
    private long _connectionGeneration;
    private bool _disposed;

    public event EventHandler<(BluetoothConnectionState State, string Detail)>? ConnectionChanged;
    public event EventHandler<BatteryReading>? BatteryReceived;
    public event EventHandler<byte[]>? ExtendedStatusReceived;
    public event EventHandler<FitResult>? FitResultReceived;
    public event EventHandler? FindStopped;

    public BluetoothConnectionState State { get; private set; } = BluetoothConnectionState.Disconnected;

    public async Task<IReadOnlyList<BluetoothDeviceOption>> GetPairedBudsAsync(CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        return await Task.Run(() =>
        {
            using BluetoothClient discoveryClient = new();
            return discoveryClient.PairedDevices
                .Where(device => IsBudsName(device.DeviceName))
                .Select(device => new BluetoothDeviceOption(
                    string.IsNullOrWhiteSpace(device.DeviceName) ? "Galaxy Buds" : device.DeviceName,
                    device.DeviceAddress.ToString()))
                .OrderBy(device => device.Name, StringComparer.CurrentCultureIgnoreCase)
                .ToArray();
        }, cancellationToken);
    }

    public async Task ConnectAsync(BluetoothDeviceOption device, CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        CloseResources();
        BluetoothClient client = new();
        long generation = BeginConnection(client, $"正在连接 {device.Name}");
        Task? connectionTask = null;

        try
        {
            BluetoothAddress address = BluetoothAddress.Parse(device.Address);
            connectionTask = client.ConnectAsync(address, BudsProtocol.SamsungServiceUuid);
            await connectionTask.WaitAsync(ConnectionTimeout, cancellationToken);
            Stream? stream = client.GetStream();
            if (stream is null)
            {
                throw new IOException("RFCOMM 服务未提供可用数据流");
            }

            CancellationTokenSource readCancellation = new();
            if (!ActivateConnection(generation, client, stream, readCancellation, $"已直连 {device.Name}"))
            {
                readCancellation.Dispose();
                stream.Dispose();
                throw new OperationCanceledException("连接已被新的会话替代", cancellationToken);
            }

            _ = ReadLoopAsync(stream, generation, readCancellation.Token);
            await WritePacketAsync(stream, BudsProtocol.StateRequest(), cancellationToken);
        }
        catch (TimeoutException error)
        {
            CloseResources(generation, BluetoothConnectionState.Disconnected, "RFCOMM 连接超时，请确认耳机已配对且在附近");
            _ = CloseClientAfterConnectionAttemptAsync(connectionTask, client);
            throw new TimeoutException("RFCOMM 连接在 15 秒内未完成", error);
        }
        catch (OperationCanceledException)
        {
            CloseResources(generation, BluetoothConnectionState.Disconnected, "连接已取消");
            _ = CloseClientAfterConnectionAttemptAsync(connectionTask, client);
            throw;
        }
        catch (Exception error)
        {
            CloseResources(generation, BluetoothConnectionState.Disconnected, $"RFCOMM 连接失败：{SafeMessage(error)}");
            throw;
        }
    }

    public Task DisconnectAsync()
    {
        CloseResources(finalState: BluetoothConnectionState.Disconnected, detail: "已断开");
        return Task.CompletedTask;
    }

    public async Task<CommandResult> SendAsync(BudsCommand command, CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        await _sendGate.WaitAsync(cancellationToken);
        try
        {
            Stream? stream;
            long generation;
            PendingAcknowledgement? pending = null;
            lock (_stateLock)
            {
                if (State != BluetoothConnectionState.Connected || _stream is null)
                {
                    return new CommandResult(false, false, "耳机未连接");
                }

                stream = _stream;
                generation = _connectionGeneration;
                if (command.RequiresAcknowledgement)
                {
                    pending = new PendingAcknowledgement(
                        generation,
                        command.MessageId,
                        command.ExpectedAcknowledgementPrefix ?? [],
                        new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously));
                    _pendingAcknowledgement = pending;
                }
            }

            try
            {
                await WritePacketAsync(stream, command.Packet, cancellationToken);
                if (pending is null)
                {
                    await WritePacketAsync(stream, BudsProtocol.StateRequest(), cancellationToken);
                    return new CommandResult(true, false, "命令已写入，等待状态包确认");
                }

                bool acknowledged;
                bool timedOut = false;
                try
                {
                    acknowledged = await pending.Completion.Task.WaitAsync(AcknowledgementTimeout, cancellationToken);
                }
                catch (TimeoutException)
                {
                    acknowledged = false;
                    timedOut = true;
                }

                ClearPendingAcknowledgement(pending);
                if (!acknowledged)
                {
                    if (!IsCurrentSession(stream, generation))
                    {
                        return new CommandResult(false, false, "等待确认时耳机连接已关闭");
                    }

                    await WritePacketAsync(stream, BudsProtocol.StateRequest(), cancellationToken);
                    if (timedOut)
                    {
                        await Task.Delay(LateAcknowledgementDrain, cancellationToken);
                    }
                    return new CommandResult(false, false, "耳机未在 2 秒内确认命令，已重新读取状态");
                }

                await WritePacketAsync(stream, BudsProtocol.StateRequest(), cancellationToken);
                return new CommandResult(true, true, "耳机已确认命令");
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception error)
            {
                CloseResources(generation, BluetoothConnectionState.Disconnected, $"蓝牙写入失败：{SafeMessage(error)}");
                return new CommandResult(false, false, $"蓝牙写入失败：{SafeMessage(error)}");
            }
            finally
            {
                ClearPendingAcknowledgement(pending);
            }
        }
        finally
        {
            _sendGate.Release();
        }
    }

    private async Task ReadLoopAsync(Stream stream, long generation, CancellationToken cancellationToken)
    {
        byte[] buffer = new byte[1024];
        BudsFrameParser parser = new();
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                int count = await stream.ReadAsync(buffer.AsMemory(), cancellationToken);
                if (count == 0)
                {
                    throw new IOException("连接已关闭");
                }

                if (!IsCurrentSession(stream, generation))
                {
                    return;
                }

                IReadOnlyList<byte[]> frames = parser.Append(buffer.AsSpan(0, count));
                foreach (byte[] frame in frames)
                {
                    if (!IsCurrentSession(stream, generation))
                    {
                        return;
                    }
                    ProcessFrame(frame, generation);
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception error)
        {
            if (!_disposed)
            {
                CloseResources(generation, BluetoothConnectionState.Disconnected, $"耳机已断开：{SafeMessage(error)}");
            }
        }
    }

    private void ProcessFrame(byte[] frame, long generation)
    {
        byte messageId = frame[3];
        ReadOnlySpan<byte> payload = frame.AsSpan(4, frame.Length - 7);
        if (messageId == BudsProtocol.MessageAcknowledgement && payload.Length >= 1)
        {
            PendingAcknowledgement? pending;
            lock (_stateLock)
            {
                pending = _pendingAcknowledgement;
            }
            if (pending is not null &&
                pending.Generation == generation &&
                BudsTransportSemantics.MatchesAcknowledgement(payload, pending.MessageId, pending.Prefix))
            {
                pending.Completion.TrySetResult(true);
            }
            return;
        }

        if (messageId == BudsProtocol.MessageStatus && frame.Length >= 14)
        {
            BatteryReceived?.Invoke(this, new BatteryReading(
                BudsTransportSemantics.BatteryLevel(frame[5]),
                BudsTransportSemantics.BatteryLevel(frame[6]),
                BudsTransportSemantics.BatteryLevel(frame[10])));
        }
        else if (messageId == BudsProtocol.MessageExtendedStatus && payload.Length >= 8)
        {
            BatteryReceived?.Invoke(this, new BatteryReading(
                BudsTransportSemantics.BatteryLevel(frame[6]),
                BudsTransportSemantics.BatteryLevel(frame[7]),
                BudsTransportSemantics.BatteryLevel(frame[11], zeroMeansUnavailable: true)));
            ExtendedStatusReceived?.Invoke(this, payload.ToArray());
        }
        else if (messageId == BudsProtocol.MessageFitResult && payload.Length >= 2)
        {
            FitResultReceived?.Invoke(this, new FitResult(payload[0], payload[1]));
            _ = StopFitTestAfterResultAsync();
        }
        else if (messageId == BudsProtocol.MessageFindStopped)
        {
            FindStopped?.Invoke(this, EventArgs.Empty);
        }
    }

    private static async Task WritePacketAsync(Stream stream, byte[] packet, CancellationToken cancellationToken)
    {
        await stream.WriteAsync(packet.AsMemory(), cancellationToken);
        await stream.FlushAsync(cancellationToken);
    }

    private long BeginConnection(BluetoothClient client, string detail)
    {
        long generation;
        lock (_stateLock)
        {
            generation = ++_connectionGeneration;
            _client = client;
            State = BluetoothConnectionState.Connecting;
        }
        ConnectionChanged?.Invoke(this, (BluetoothConnectionState.Connecting, detail));
        return generation;
    }

    private bool ActivateConnection(
        long generation,
        BluetoothClient client,
        Stream stream,
        CancellationTokenSource readCancellation,
        string detail)
    {
        lock (_stateLock)
        {
            if (_connectionGeneration != generation || !ReferenceEquals(_client, client))
            {
                return false;
            }

            _stream = stream;
            _readCancellation = readCancellation;
            State = BluetoothConnectionState.Connected;
        }
        ConnectionChanged?.Invoke(this, (BluetoothConnectionState.Connected, detail));
        return true;
    }

    private bool CloseResources(
        long? expectedGeneration = null,
        BluetoothConnectionState? finalState = null,
        string? detail = null)
    {
        BluetoothClient? client;
        Stream? stream;
        CancellationTokenSource? cancellation;
        PendingAcknowledgement? pending;
        lock (_stateLock)
        {
            if (expectedGeneration is not null && _connectionGeneration != expectedGeneration.Value)
            {
                return false;
            }

            _connectionGeneration++;
            client = _client;
            stream = _stream;
            cancellation = _readCancellation;
            pending = _pendingAcknowledgement;
            _client = null;
            _stream = null;
            _readCancellation = null;
            _pendingAcknowledgement = null;
            if (finalState is not null)
            {
                State = finalState.Value;
            }
        }

        pending?.Completion.TrySetResult(false);
        IgnoreCleanupErrors(() => cancellation?.Cancel());
        IgnoreCleanupErrors(() => stream?.Dispose());
        IgnoreCleanupErrors(() => client?.Close());
        IgnoreCleanupErrors(() => cancellation?.Dispose());
        if (finalState is not null && detail is not null)
        {
            ConnectionChanged?.Invoke(this, (finalState.Value, detail));
        }
        return true;
    }

    private void ClearPendingAcknowledgement(PendingAcknowledgement? pending)
    {
        if (pending is null)
        {
            return;
        }

        lock (_stateLock)
        {
            if (ReferenceEquals(_pendingAcknowledgement, pending))
            {
                _pendingAcknowledgement = null;
            }
        }
    }

    private static bool IsBudsName(string? name)
    {
        string normalized = name?.ToLowerInvariant() ?? string.Empty;
        return normalized.Contains("galaxy buds", StringComparison.Ordinal) ||
               normalized.Contains("buds3 pro", StringComparison.Ordinal) ||
               normalized.Contains("sm-r630", StringComparison.Ordinal);
    }

    private static string SafeMessage(Exception error) =>
        string.IsNullOrWhiteSpace(error.Message) ? error.GetType().Name : error.Message;

    private static void IgnoreCleanupErrors(Action cleanup)
    {
        try
        {
            cleanup();
        }
        catch (Exception)
        {
        }
    }

    private bool IsCurrentSession(Stream stream, long generation)
    {
        lock (_stateLock)
        {
            return _connectionGeneration == generation && ReferenceEquals(_stream, stream);
        }
    }

    private async Task StopFitTestAfterResultAsync()
    {
        try
        {
            await SendAsync(BudsProtocol.FitTest(false));
        }
        catch (Exception error) when (error is OperationCanceledException or ObjectDisposedException)
        {
        }
    }

    private static async Task CloseClientAfterConnectionAttemptAsync(Task? connectionTask, BluetoothClient client)
    {
        if (connectionTask is not null)
        {
            try
            {
                await connectionTask;
            }
            catch (Exception)
            {
            }
        }
        try
        {
            client.Close();
        }
        catch (Exception)
        {
        }
    }

    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(_disposed, this);

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        CloseResources();
        await _sendGate.WaitAsync();
        _sendGate.Release();
        _sendGate.Dispose();
    }
}
