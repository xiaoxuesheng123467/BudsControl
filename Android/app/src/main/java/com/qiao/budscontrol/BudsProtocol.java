package com.qiao.budscontrol;

import java.io.ByteArrayOutputStream;
import java.util.Locale;
import java.util.UUID;

final class BudsProtocol {
    static final UUID SAMSUNG_SERVICE_UUID = UUID.fromString("2E73A4AD-332D-41FC-90E2-16BEF06523F2");

    static final int MESSAGE_ACK = 0x42;
    static final int MESSAGE_STATUS = 0x60;
    static final int MESSAGE_EXTENDED_STATUS = 0x61;
    static final int MESSAGE_FIT_RESULT = 0x9E;
    static final int MESSAGE_FIND_STOPPED = 0xA1;

    enum Verification {
        HARDWARE_VERIFIED,
        PROTOCOL_MAPPED,
        EXPERIMENTAL
    }

    static final class Command {
        final String key;
        final String title;
        final int messageId;
        final byte[] payload;
        final boolean requiresAcknowledgement;
        final byte[] expectedAcknowledgementPrefix;
        final Verification verification;

        Command(
                String key,
                String title,
                int messageId,
                byte[] payload,
                boolean requiresAcknowledgement,
                byte[] expectedAcknowledgementPrefix,
                Verification verification
        ) {
            this.key = key;
            this.title = title;
            this.messageId = messageId;
            this.payload = payload.clone();
            this.requiresAcknowledgement = requiresAcknowledgement;
            this.expectedAcknowledgementPrefix = expectedAcknowledgementPrefix == null
                    ? null : expectedAcknowledgementPrefix.clone();
            this.verification = verification;
        }

        byte[] packet() {
            return encode(messageId, payload);
        }
    }

    private BudsProtocol() {}

    static Command noiseControl(int mode) {
        requireRange(mode, 0, 3, "noise mode");
        return command(
                "noiseControl",
                "噪音控制：" + new String[]{"关闭", "降噪", "环境声", "自适应"}[mode],
                0x78,
                bytes(mode),
                true,
                bytes(mode),
                mode == 3 ? Verification.PROTOCOL_MAPPED : Verification.HARDWARE_VERIFIED
        );
    }

    static Command equalizer(int preset) {
        requireRange(preset, 0, 5, "equalizer preset");
        return command(
                "equalizer",
                "均衡器：" + new String[]{"正常", "低音增强", "柔和", "动态", "清晰", "高音增强"}[preset],
                0x86,
                bytes(preset),
                true,
                bytes(preset),
                Verification.HARDWARE_VERIFIED
        );
    }

    static Command ambientVolume(int level) {
        requireRange(level, 0, 2, "ambient volume");
        return mapped("ambientVolume", "环境声级别", 0x84, bytes(level), true, bytes(level));
    }

    static Command ambientCustomization(boolean enabled, int left, int right, int tone) {
        requireRange(left, 0, 2, "left ambient volume");
        requireRange(right, 0, 2, "right ambient volume");
        requireRange(tone, 0, 4, "ambient tone");
        byte[] payload = bytes(enabled, left, right, tone);
        return mapped("ambientCustomization", enabled ? "自定义环境声" : "关闭自定义环境声", 0x82, payload, true, payload);
    }

    static Command noiseReductionLevel(boolean high) {
        return mapped("noiseReductionLevel", high ? "强降噪" : "标准降噪", 0x83, bytes(high), true, bytes(high));
    }

    static Command voiceDetect(boolean enabled) {
        return mapped("voiceDetect", enabled ? "开启语音检测" : "关闭语音检测", 0x7A, bytes(enabled), true, bytes(enabled));
    }

    static Command voiceDetectTimeout(int timeout) {
        requireRange(timeout, 0, 2, "voice detect timeout");
        return mapped("voiceDetectTimeout", "语音检测恢复时间", 0x7B, bytes(timeout), true, bytes(timeout));
    }

    static Command oneEarNoiseControl(boolean enabled) {
        return mapped("noiseControlWithOneEarbud", "单耳噪音控制", 0x6F, bytes(enabled), true, bytes(enabled));
    }

    static Command touchLock(
            boolean locked,
            boolean singleTap,
            boolean doubleTap,
            boolean tripleTap,
            boolean touchAndHold,
            boolean doubleTapCall,
            boolean touchAndHoldCall
    ) {
        byte[] payload = bytes(
                !locked,
                singleTap,
                doubleTap,
                tripleTap,
                touchAndHold,
                doubleTapCall,
                touchAndHoldCall
        );
        return mapped("touchLock", locked ? "锁定耳机控制" : "更新耳机手势", 0x90, payload, true, new byte[0]);
    }

    static Command touchActions(int left, int right) {
        requireRange(left, 1, 4, "left touch action");
        requireRange(right, 1, 4, "right touch action");
        byte[] payload = bytes(left, right);
        return mapped("touchActions", "左右长捏动作", 0x92, payload, true, payload);
    }

    static Command touchNoiseCycle(int left, int right) {
        requireCycle(left);
        requireCycle(right);
        return mapped("touchNoiseCycle", "左右噪音循环", 0x79, bytes(left, right), true, new byte[0]);
    }

    static Command edgeDoubleTap(boolean enabled) {
        return mapped("edgeDoubleTapVolume", "双击耳边调节音量", 0x95, bytes(enabled), true, bytes(enabled));
    }

    static Command stereoBalance(int value) {
        requireRange(value, 0, 32, "stereo balance");
        return mapped("stereoBalance", "左右声音平衡", 0x8F, bytes(value), true, bytes(value));
    }

    static Command seamlessConnection(boolean enabled) {
        byte wire = (byte) (enabled ? 0 : 1);
        byte semantic = (byte) (enabled ? 1 : 0);
        return mapped("seamlessConnection", "无缝耳机连接", 0xAF, new byte[]{wire}, true, new byte[]{semantic});
    }

    static Command sidetone(boolean enabled) {
        return mapped("sidetone", "通话期间使用环境声", 0x8B, bytes(enabled), true, bytes(enabled));
    }

    static Command callPathControl(boolean enabled) {
        byte wire = (byte) (enabled ? 0 : 1);
        byte semantic = (byte) (enabled ? 1 : 0);
        return mapped("callPathControl", "摘下双耳时切回手机", 0x6E, new byte[]{wire}, true, new byte[]{semantic});
    }

    static Command extraClearCall(boolean enabled) {
        return mapped("extraClearCall", "清晰通话", 0x48, bytes(enabled), true, bytes(enabled));
    }

    static Command extraHighAmbient(boolean enabled) {
        return mapped("extraHighAmbient", "超高环境声", 0x96, bytes(enabled), true, bytes(enabled));
    }

    static Command spatialAudio(boolean enabled) {
        return mapped("spatialAudio", "360 音频", 0x7C, bytes(enabled), false, null);
    }

    static Command gamingMode(boolean enabled) {
        return mapped("gamingMode", "游戏模式", 0x87, bytes(enabled), false, null);
    }

    static Command autoPauseResume(boolean enabled) {
        return mapped("autoPauseResume", "摘下耳机自动暂停", 0x6C, bytes(enabled), false, null);
    }

    static Command fitTest(boolean active) {
        return mapped("fitTest", active ? "开始耳塞贴合度测试" : "停止耳塞贴合度测试", 0x9D, bytes(active), false, null);
    }

    static Command adaptiveVolume(boolean enabled) {
        return experimental("adaptiveVolume", "自适应音量", 0xC5, bytes(enabled));
    }

    static Command sirenDetect(boolean enabled) {
        return experimental("sirenDetect", "警笛检测", 0xDE, bytes(enabled));
    }

    static Command findStart() {
        return mapped("findEarbudsStart", "开始查找耳机", 0xA6, new byte[0], false, null);
    }

    static Command findStop() {
        return mapped("findEarbudsStop", "停止查找耳机", 0xA1, new byte[0], false, null);
    }

    static Command muteEarbuds(boolean left, boolean right) {
        byte[] payload = bytes(left, right);
        return mapped("muteEarbuds", "设置左右耳查找响铃", 0xA2, payload, true, payload);
    }

    static byte[] stateRequest() {
        return encode(0x26, new byte[0]);
    }

    static byte[] encode(int messageId, byte[] payload) {
        int messageSize = 1 + payload.length + 2;
        ByteArrayOutputStream output = new ByteArrayOutputStream(payload.length + 7);
        output.write(0xFD);
        output.write(messageSize & 0xFF);
        output.write((messageSize >> 8) & 0xFF);
        output.write(messageId & 0xFF);
        output.write(payload, 0, payload.length);

        byte[] checksumInput = new byte[payload.length + 1];
        checksumInput[0] = (byte) messageId;
        System.arraycopy(payload, 0, checksumInput, 1, payload.length);
        int crc = crc16Ccitt(checksumInput);
        output.write(crc & 0xFF);
        output.write((crc >> 8) & 0xFF);
        output.write(0xDD);
        return output.toByteArray();
    }

    static int crc16Ccitt(byte[] data) {
        int crc = 0;
        for (byte value : data) {
            crc ^= (value & 0xFF) << 8;
            for (int bit = 0; bit < 8; bit++) {
                crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
                crc &= 0xFFFF;
            }
        }
        return crc;
    }

    static boolean hasValidCrc(byte[] frame) {
        if (frame.length < 7 || (frame[frame.length - 1] & 0xFF) != 0xDD) return false;
        byte[] checksumInput = new byte[frame.length - 6];
        System.arraycopy(frame, 3, checksumInput, 0, checksumInput.length);
        int expected = crc16Ccitt(checksumInput);
        int actual = (frame[frame.length - 3] & 0xFF) | ((frame[frame.length - 2] & 0xFF) << 8);
        return expected == actual;
    }

    static String hex(byte[] data) {
        StringBuilder builder = new StringBuilder(data.length * 3);
        for (int index = 0; index < data.length; index++) {
            if (index > 0) builder.append(' ');
            builder.append(String.format(Locale.ROOT, "%02X", data[index] & 0xFF));
        }
        return builder.toString();
    }

    private static Command command(
            String key,
            String title,
            int messageId,
            byte[] payload,
            boolean requiresAcknowledgement,
            byte[] expectedAcknowledgementPrefix,
            Verification verification
    ) {
        return new Command(
                key,
                title,
                messageId,
                payload,
                requiresAcknowledgement,
                expectedAcknowledgementPrefix,
                verification
        );
    }

    private static Command mapped(
            String key,
            String title,
            int messageId,
            byte[] payload,
            boolean requiresAcknowledgement,
            byte[] expectedAcknowledgementPrefix
    ) {
        return command(
                key,
                title,
                messageId,
                payload,
                requiresAcknowledgement,
                expectedAcknowledgementPrefix,
                Verification.PROTOCOL_MAPPED
        );
    }

    private static Command experimental(String key, String title, int messageId, byte[] payload) {
        return command(key, title, messageId, payload, false, null, Verification.EXPERIMENTAL);
    }

    private static byte[] bytes(boolean... values) {
        byte[] result = new byte[values.length];
        for (int index = 0; index < values.length; index++) result[index] = (byte) (values[index] ? 1 : 0);
        return result;
    }

    private static byte[] bytes(int... values) {
        byte[] result = new byte[values.length];
        for (int index = 0; index < values.length; index++) {
            requireRange(values[index], 0, 255, "byte");
            result[index] = (byte) values[index];
        }
        return result;
    }

    private static byte[] bytes(boolean first, int second, int third, int fourth) {
        return new byte[]{(byte) (first ? 1 : 0), (byte) second, (byte) third, (byte) fourth};
    }

    private static void requireCycle(int value) {
        if (value != 4 && value != 8 && value != 12) {
            throw new IllegalArgumentException("noise cycle must be 4, 8, or 12");
        }
    }

    private static void requireRange(int value, int minimum, int maximum, String label) {
        if (value < minimum || value > maximum) {
            throw new IllegalArgumentException(label + " out of range: " + value);
        }
    }
}
