using System.Globalization;

namespace BudsControl.Core;

public enum VerificationLevel
{
    HardwareVerified,
    ProtocolMapped,
    Experimental,
}

public sealed record BudsCommand(
    string Key,
    string Title,
    byte MessageId,
    byte[] Payload,
    bool RequiresAcknowledgement,
    byte[]? ExpectedAcknowledgementPrefix,
    VerificationLevel Verification)
{
    public byte[] Packet => BudsProtocol.Encode(MessageId, Payload);
}

public static class BudsProtocol
{
    public static readonly Guid SamsungServiceUuid = Guid.Parse("2E73A4AD-332D-41FC-90E2-16BEF06523F2");

    public const byte MessageAcknowledgement = 0x42;
    public const byte MessageStatus = 0x60;
    public const byte MessageExtendedStatus = 0x61;
    public const byte MessageFitResult = 0x9E;
    public const byte MessageFindStopped = 0xA1;

    private static readonly string[] NoiseModeNames = ["关闭", "降噪", "环境声", "自适应"];
    private static readonly string[] EqualizerNames = ["正常", "低音增强", "柔和", "动态", "清晰", "高音增强"];

    public static BudsCommand NoiseControl(int mode)
    {
        RequireRange(mode, 0, 3, nameof(mode));
        return Command(
            "noiseControl",
            $"噪音控制：{NoiseModeNames[mode]}",
            0x78,
            Bytes(mode),
            true,
            Bytes(mode),
            mode == 3 ? VerificationLevel.ProtocolMapped : VerificationLevel.HardwareVerified);
    }

    public static BudsCommand Equalizer(int preset)
    {
        RequireRange(preset, 0, 5, nameof(preset));
        return Command(
            "equalizer",
            $"均衡器：{EqualizerNames[preset]}",
            0x86,
            Bytes(preset),
            true,
            Bytes(preset),
            VerificationLevel.HardwareVerified);
    }

    public static BudsCommand AmbientVolume(int level)
    {
        RequireRange(level, 0, 2, nameof(level));
        return Mapped("ambientVolume", "环境声级别", 0x84, Bytes(level), true, Bytes(level));
    }

    public static BudsCommand AmbientCustomization(bool enabled, int left, int right, int tone)
    {
        RequireRange(left, 0, 2, nameof(left));
        RequireRange(right, 0, 2, nameof(right));
        RequireRange(tone, 0, 4, nameof(tone));
        byte[] payload = [(byte)(enabled ? 1 : 0), (byte)left, (byte)right, (byte)tone];
        return Mapped("ambientCustomization", enabled ? "自定义环境声" : "关闭自定义环境声", 0x82, payload, true, payload);
    }

    public static BudsCommand NoiseReductionLevel(bool high) =>
        Mapped("noiseReductionLevel", high ? "强降噪" : "标准降噪", 0x83, Bytes(high), true, Bytes(high));

    public static BudsCommand VoiceDetect(bool enabled) =>
        Mapped("voiceDetect", enabled ? "开启语音检测" : "关闭语音检测", 0x7A, Bytes(enabled), true, Bytes(enabled));

    public static BudsCommand VoiceDetectTimeout(int timeout)
    {
        RequireRange(timeout, 0, 2, nameof(timeout));
        return Mapped("voiceDetectTimeout", "语音检测恢复时间", 0x7B, Bytes(timeout), true, Bytes(timeout));
    }

    public static BudsCommand OneEarNoiseControl(bool enabled) =>
        Mapped("noiseControlWithOneEarbud", "单耳噪音控制", 0x6F, Bytes(enabled), true, Bytes(enabled));

    public static BudsCommand TouchLock(
        bool locked,
        bool singleTap,
        bool doubleTap,
        bool tripleTap,
        bool touchAndHold,
        bool doubleTapCall,
        bool touchAndHoldCall)
    {
        byte[] payload =
        [
            (byte)(locked ? 0 : 1),
            (byte)(singleTap ? 1 : 0),
            (byte)(doubleTap ? 1 : 0),
            (byte)(tripleTap ? 1 : 0),
            (byte)(touchAndHold ? 1 : 0),
            (byte)(doubleTapCall ? 1 : 0),
            (byte)(touchAndHoldCall ? 1 : 0),
        ];
        return Mapped("touchLock", locked ? "锁定耳机控制" : "更新耳机手势", 0x90, payload, true, []);
    }

    public static BudsCommand TouchActions(int left, int right)
    {
        RequireRange(left, 1, 4, nameof(left));
        RequireRange(right, 1, 4, nameof(right));
        byte[] payload = Bytes(left, right);
        return Mapped("touchActions", "左右长捏动作", 0x92, payload, true, payload);
    }

    public static BudsCommand TouchNoiseCycle(int left, int right)
    {
        RequireCycle(left);
        RequireCycle(right);
        return Mapped("touchNoiseCycle", "左右噪音循环", 0x79, Bytes(left, right), true, []);
    }

    public static BudsCommand EdgeDoubleTap(bool enabled) =>
        Mapped("edgeDoubleTapVolume", "双击耳边调节音量", 0x95, Bytes(enabled), true, Bytes(enabled));

    public static BudsCommand StereoBalance(int value)
    {
        RequireRange(value, 0, 32, nameof(value));
        return Mapped("stereoBalance", "左右声音平衡", 0x8F, Bytes(value), true, Bytes(value));
    }

    public static BudsCommand SeamlessConnection(bool enabled)
    {
        byte[] wire = [(byte)(enabled ? 0 : 1)];
        byte[] semantic = [(byte)(enabled ? 1 : 0)];
        return Mapped("seamlessConnection", "无缝耳机连接", 0xAF, wire, true, semantic);
    }

    public static BudsCommand Sidetone(bool enabled) =>
        Mapped("sidetone", "通话期间使用环境声", 0x8B, Bytes(enabled), true, Bytes(enabled));

    public static BudsCommand CallPathControl(bool enabled)
    {
        byte[] wire = [(byte)(enabled ? 0 : 1)];
        byte[] semantic = [(byte)(enabled ? 1 : 0)];
        return Mapped("callPathControl", "摘下双耳时切回电脑", 0x6E, wire, true, semantic);
    }

    public static BudsCommand ExtraClearCall(bool enabled) =>
        Mapped("extraClearCall", "清晰通话", 0x48, Bytes(enabled), true, Bytes(enabled));

    public static BudsCommand ExtraHighAmbient(bool enabled) =>
        Mapped("extraHighAmbient", "超高环境声", 0x96, Bytes(enabled), true, Bytes(enabled));

    public static BudsCommand SpatialAudio(bool enabled) =>
        Mapped("spatialAudio", "360 音频", 0x7C, Bytes(enabled), false, null);

    public static BudsCommand GamingMode(bool enabled) =>
        Mapped("gamingMode", "游戏模式", 0x87, Bytes(enabled), false, null);

    public static BudsCommand AutoPauseResume(bool enabled) =>
        Mapped("autoPauseResume", "摘下耳机自动暂停", 0x6C, Bytes(enabled), false, null);

    public static BudsCommand FitTest(bool active) =>
        Mapped("fitTest", active ? "开始耳塞贴合度测试" : "停止耳塞贴合度测试", 0x9D, Bytes(active), false, null);

    public static BudsCommand AdaptiveVolume(bool enabled) =>
        Experimental("adaptiveVolume", "自适应音量", 0xC5, Bytes(enabled));

    public static BudsCommand SirenDetect(bool enabled) =>
        Experimental("sirenDetect", "警笛检测", 0xDE, Bytes(enabled));

    public static BudsCommand FindStart() => Mapped("findEarbudsStart", "开始查找耳机", 0xA6, [], false, null);
    public static BudsCommand FindStop() => Mapped("findEarbudsStop", "停止查找耳机", 0xA1, [], false, null);

    public static BudsCommand MuteEarbuds(bool left, bool right)
    {
        byte[] payload = Bytes(left, right);
        return Mapped("muteEarbuds", "设置左右耳查找响铃", 0xA2, payload, true, payload);
    }

    public static byte[] StateRequest() => Encode(0x26, []);

    public static byte[] Encode(byte messageId, ReadOnlySpan<byte> payload)
    {
        int messageSize = 1 + payload.Length + 2;
        byte[] frame = new byte[payload.Length + 7];
        frame[0] = 0xFD;
        frame[1] = (byte)(messageSize & 0xFF);
        frame[2] = (byte)((messageSize >> 8) & 0xFF);
        frame[3] = messageId;
        payload.CopyTo(frame.AsSpan(4));

        ushort crc = Crc16Ccitt(frame.AsSpan(3, payload.Length + 1));
        frame[^3] = (byte)(crc & 0xFF);
        frame[^2] = (byte)(crc >> 8);
        frame[^1] = 0xDD;
        return frame;
    }

    public static ushort Crc16Ccitt(ReadOnlySpan<byte> data)
    {
        ushort crc = 0;
        foreach (byte value in data)
        {
            crc ^= (ushort)(value << 8);
            for (int bit = 0; bit < 8; bit++)
            {
                crc = (ushort)((crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1);
            }
        }
        return crc;
    }

    public static bool HasValidCrc(ReadOnlySpan<byte> frame)
    {
        if (frame.Length < 7 || frame[^1] != 0xDD)
        {
            return false;
        }

        ushort expected = Crc16Ccitt(frame[3..^3]);
        ushort actual = (ushort)(frame[^3] | frame[^2] << 8);
        return expected == actual;
    }

    public static string Hex(ReadOnlySpan<byte> data) =>
        string.Join(' ', data.ToArray().Select(value => value.ToString("X2", CultureInfo.InvariantCulture)));

    private static BudsCommand Mapped(
        string key,
        string title,
        byte messageId,
        byte[] payload,
        bool requiresAcknowledgement,
        byte[]? expectedAcknowledgementPrefix) =>
        Command(key, title, messageId, payload, requiresAcknowledgement, expectedAcknowledgementPrefix, VerificationLevel.ProtocolMapped);

    private static BudsCommand Experimental(string key, string title, byte messageId, byte[] payload) =>
        Command(key, title, messageId, payload, false, null, VerificationLevel.Experimental);

    private static BudsCommand Command(
        string key,
        string title,
        byte messageId,
        byte[] payload,
        bool requiresAcknowledgement,
        byte[]? expectedAcknowledgementPrefix,
        VerificationLevel verification) =>
        new(key, title, messageId, [.. payload], requiresAcknowledgement, expectedAcknowledgementPrefix is null ? null : [.. expectedAcknowledgementPrefix], verification);

    private static byte[] Bytes(params bool[] values) => values.Select(value => (byte)(value ? 1 : 0)).ToArray();

    private static byte[] Bytes(params int[] values)
    {
        foreach (int value in values)
        {
            RequireRange(value, 0, 255, nameof(values));
        }
        return values.Select(value => (byte)value).ToArray();
    }

    private static void RequireCycle(int value)
    {
        if (value is not (4 or 8 or 12))
        {
            throw new ArgumentOutOfRangeException(nameof(value), value, "Noise cycle must be 4, 8, or 12.");
        }
    }

    private static void RequireRange(int value, int minimum, int maximum, string name)
    {
        if (value < minimum || value > maximum)
        {
            throw new ArgumentOutOfRangeException(name, value, $"Value must be between {minimum} and {maximum}.");
        }
    }
}
