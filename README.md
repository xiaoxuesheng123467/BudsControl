# BudsControl

BudsControl is an unofficial iPhone controller for Galaxy Buds3 Pro. It reproduces the useful parts of Samsung's One UI settings screen and sends real control packets through a small Mac bridge.

![BudsControl running on an iPhone](Screenshots/buds-control-iphone.png)

The current build has been tested on a physical SM-R630. The earbuds acknowledged noise-control and equalizer commands, and the app read the left, right, and case battery levels. This is a personal Xcode build, not an App Store release.

## Working features

| Feature | Status |
| --- | --- |
| Active noise cancelling | Hardware verified |
| Ambient sound | Hardware verified |
| Noise control off | Implemented with the same verified command path |
| Normal, bass, soft, dynamic, clear, and treble EQ presets | Hardware verified |
| Left, right, and case battery | Read from Samsung status packets |
| Mac discovery | Bonjour on the local network |
| Bridge authentication | TLS 1.2 PSK with a rotating 128-bit secret |
| CoreBluetooth diagnostics | Manual, read-only probe with exportable logs |

Adaptive noise control, the 9-band custom EQ, gestures, Blade Light, voice detection, firmware updates, and Samsung account features remain locked. Their screens are present so the app can grow without pretending those controls work today.

## Why the Mac bridge exists

Galaxy Buds3 Pro exposes its settings protocol through Bluetooth Classic SPP/RFCOMM. A normal iOS app cannot open an arbitrary RFCOMM service with Apple's public SDK. CoreBluetooth only helps when a device exposes a suitable GATT service, and ExternalAccessory requires manufacturer participation in Apple's accessory program.

BudsBridge handles the RFCOMM connection on macOS. The iPhone discovers the bridge with Bonjour and sends encrypted local-network requests. The Mac must remain awake while the controls are in use.

```text
iPhone app == TLS-PSK over LAN ==> BudsBridge == RFCOMM channel 27 ==> Buds3 Pro
```

## Install

Requirements:

- Xcode 16 or newer
- iOS 18 or newer
- macOS 14 or newer
- Galaxy Buds3 Pro paired with the Mac
- iPhone and Mac on the same local network

Open `BudsControl.xcodeproj` in Xcode. Select the `BudsBridge` scheme, choose `My Mac`, and run it. The Xcode console prints a 32-character pairing secret. Copy it to the iPhone with Universal Clipboard or another local method.

Switch to the `BudsControl` scheme, choose the iPhone, select a development team if Xcode asks, and run. Allow local-network access, then enter the code shown by BudsBridge. The controls unlock after the Mac opens the Samsung RFCOMM channel.

The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After editing `project.yml`, regenerate it with:

```sh
xcodegen generate
```

## Validation

The packet verifier checks the CRC and byte layout for ANC, ambient sound, noise control off, dynamic EQ, and the state request:

```sh
xcrun swiftc BudsControl/Sources/BudsProtocol.swift Tools/ProtocolVerifier/main.swift -o /tmp/BudsProtocolVerifier
/tmp/BudsProtocolVerifier
```

Build both targets without signing:

```sh
xcodebuild -project BudsControl.xcodeproj -scheme BudsBridge build CODE_SIGNING_ALLOWED=NO
xcodebuild -project BudsControl.xcodeproj -scheme BudsControl -sdk iphoneos build CODE_SIGNING_ALLOWED=NO
```

The bridge also contains a local TLS probe for development builds:

```sh
BudsBridge --probe-port <port> --pairing-code <secret>
```

## Protocol notes

Samsung messages use the frame below. CRC is CRC-16/CCITT with polynomial `0x1021` and initial value `0`, calculated over the message ID and payload.

```text
FD | size (little endian) | message ID | payload | CRC16 (little endian) | DD
```

The implementation was written for this project from observed protocol behavior and published protocol documentation. [GalaxyBudsClient](https://github.com/timschneeb/GalaxyBudsClient) was an important reference for service UUIDs and message semantics. No source file from that GPL-3.0 project is included here.

Samsung's official Buds3 Pro manual and compatibility notes describe the original controls and the lack of Buds3 Pro support in Samsung's iOS app:

- [Galaxy Buds3 Pro user manual](https://downloadcenter.samsung.com/content/UM/202410/20241031153230962/R530_R630_UG_CA_ENG_D4.pdf)
- [Samsung iOS compatibility guidance](https://www.samsung.com/us/support/answer/ANS10001319/)

## Security and privacy

BudsBridge accepts TLS-PSK connections only. It generates a 128-bit random pairing secret for each run, derives a 256-bit key with SHA-256, and restricts the TLS session to an authenticated PSK cipher. The HTTP layer checks the same secret and limits request sizes and timeouts.

The app has no analytics or cloud backend. See [PRIVACY.md](PRIVACY.md) for the optional Bluetooth diagnostic log.

## License and trademark

The source code is available under the MIT License. Galaxy Buds, Galaxy Wearable, Samsung, and One UI are trademarks of Samsung Electronics. This project is independent and is not endorsed by Samsung or Apple.
