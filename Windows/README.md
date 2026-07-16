# BudsControl for Windows

BudsControl Windows 是 Galaxy Buds3 Pro 的非官方原生桌面控制器。它直接打开耳机的 Samsung Bluetooth Classic RFCOMM 服务，不需要三星电脑、三星账号、手机中转、Mac 桥接或云服务。

```text
Windows PC -> Bluetooth Classic RFCOMM -> Galaxy Buds3 Pro
```

当前版本为 `0.1.0` 真机验证预览版。协议帧、CRC、状态解析、设置记忆和离线流程均有本地验证，但这台开发 Mac 无法运行 WPF 或连接 Windows 蓝牙适配器，因此 Windows RFCOMM 链路和实际耳机命令仍需在 Windows 电脑上逐项确认。

## 系统要求

- Windows 10 版本 2004（build 19041）或更新版本
- 支持 Bluetooth Classic 的蓝牙适配器
- Galaxy Buds3 Pro 已先在 Windows“设置 > 蓝牙和设备”中完成配对
- 从源码运行需要 .NET 9 SDK；框架依赖发布包需要 .NET 9 Desktop Runtime

应用只读取已经配对的设备，不主动扫描附近设备，也不请求管理员权限。

## 功能

- 直连已配对的 Buds3 Pro，并读取左耳、右耳和充电盒电量
- 降噪、环境声、关闭、自适应四种噪音控制模式
- 六组均衡器预设
- 环境声级别、超高环境声、强降噪和左右耳环境声定制
- 语音检测、恢复时间和单耳噪音控制
- 触控锁、各类捏合手势、左右长捏动作、噪音模式循环和双击耳边音量
- 左右平衡、360 音频、清晰通话、无缝连接、通话路径、侧音、游戏模式和自动暂停
- 耳塞贴合度测试、查找耳机和左右耳单独静音
- 上次成功设置记忆、上次设备自动连接、离线演示模式
- 实验命令单独授权、最多 100 条命令记录和可保存的验证报告

Blade Light 写入、9 段自定义 EQ、固件更新和三星账号功能没有可靠且安全的协议格式，因此不开放。Blade Light、免唤醒语音和 Adapt Sound 的已知状态只读展示。

## 构建与测试

在仓库根目录执行：

```powershell
dotnet restore Windows/BudsControl.slnx
dotnet test Windows/BudsControl.Tests/BudsControl.Tests.csproj -c Release
dotnet build Windows/BudsControl.Windows/BudsControl.Windows.csproj -c Release
```

生成可分发的 64 位框架依赖目录：

```powershell
dotnet publish Windows/BudsControl.Windows/BudsControl.Windows.csproj `
  -c Release -r win-x64 --self-contained false
```

输出位于：

```text
Windows/BudsControl.Windows/bin/Release/net9.0-windows10.0.19041.0/win-x64/publish/
```

Windows ARM64 电脑可把运行时标识替换成 `win-arm64`。若要生成不依赖已安装 Desktop Runtime 的目录，将 `--self-contained` 改为 `true`；文件体积会显著增大。

## 首次连接

1. 在 Windows 系统蓝牙设置中配对 Buds3 Pro。
2. 启动 BudsControl，等待“直连耳机”列表出现设备。
3. 选择设备并点击“连接”。应用会打开 UUID `2E73A4AD-332D-41FC-90E2-16BEF06523F2` 对应的 RFCOMM 服务。
4. 首次真机测试先验证电量、降噪、环境声和 EQ，再进入“验证中心”按顺序测试扩展功能。
5. 测试结束后保存验证记录。每条记录会区分 `耳机 ACK`、`已写入`、`失败` 和 `离线模拟`。

Windows 或音频系统仍负责标准的音乐与通话连接；BudsControl 打开的 RFCOMM 通道仅用于耳机设置协议。

## 配置与隐私

配置默认保存在：

```text
%LOCALAPPDATA%\BudsControl\settings.json
```

文件包含用户选择的设置、离线/实验开关和最后一次设备地址。关闭“记住上次设置”后，耳机设置不会在下一次启动时恢复。应用没有分析 SDK、广告、账号体系、网络接口或云端后端；验证记录只有在用户主动复制或保存时才离开进程。

## 实现说明

- `BudsControl.Core`：协议命令、CRC、分帧解析、扩展状态和 JSON 设置存储
- `BudsControl.Windows`：WPF 界面、状态仓库、Windows Bluetooth Classic 传输和验证报告
- `BudsControl.Tests`：共享命令向量、CRC、分帧、扩展状态和设置持久化测试

Bluetooth Classic 访问使用 NuGet 包 `InTheHand.Net.Bluetooth`（32feet.NET）。Samsung、Galaxy Buds 和 Galaxy Wearable 是 Samsung Electronics 的商标；本项目与 Samsung 无隶属或认可关系。
