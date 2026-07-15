# BudsControl for Android

BudsControl Android is a native controller for Galaxy Buds3 Pro aimed at users who do not own a Samsung phone. It talks directly to the Samsung Bluetooth Classic RFCOMM service, so it does not require Galaxy Wearable, a Samsung account, a Mac bridge, a cloud service, or root access.

## Preview status

Version 0.1.0 is a hardware-validation preview. Protocol unit tests, Android lint, a release build, and the complete offline UI flow have been exercised. A physical Buds3 Pro has not yet been available for the Android transport test, so every real-earbud command remains pending until the validation report is captured on hardware.

Offline demonstration results are always labelled `离线模拟`; they are never presented as an earbud acknowledgement.

## Requirements

- Android 8.0 (API 26) or newer
- Galaxy Buds3 Pro already paired in Android system Bluetooth settings
- Nearby devices permission on Android 12 or newer

The app lists only already paired devices whose names match Galaxy Buds, Buds3 Pro, or SM-R630. It does not request location permission, perform discovery scans, upload device identifiers, or use Samsung services.

## Install the preview APK

1. Download `BudsControl-Android-v0.1.0-preview.apk` from the [GitHub release](https://github.com/xiaoxuesheng123467/BudsControl/releases/tag/android-v0.1.0).
2. Allow APK installation for the browser or file manager when Android asks.
3. Install and open BudsControl.
4. Grant Nearby devices access.
5. Pair Buds3 Pro in system Bluetooth settings first, then return to BudsControl and select it.

The preview APK uses a local test signing key. A later store-signed build may require uninstalling this preview first.

## Build from source

Open `Android/` in Android Studio, or use JDK 17 and an installed Android SDK from the terminal:

```sh
cd Android
./gradlew clean testDebugUnitTest assembleDebug lintDebug
```

The installable debug APK is written to:

```text
app/build/outputs/apk/debug/app-debug.apk
```

The project uses Android Gradle Plugin 9.2.1, Gradle 9.4.1, compile SDK 36, target SDK 36, and minimum SDK 26.

## Validate with Buds3 Pro

1. Open **验证中心** and leave **离线演示模式** off.
2. Connect the paired Buds3 Pro from the home screen.
3. Test battery, noise control, EQ, ambient, touch, audio, fit test, and Find My Earbuds in that order.
4. Confirm each log line says `耳机 ACK` or `已写入`; treat `失败` as unverified.
5. Tap **导出验证记录** and retain the report before disconnecting.

Find My Earbuds can play a loud sound. Remove both earbuds before starting it.

## Protocol and privacy

The RFCOMM service UUID is `2E73A4AD-332D-41FC-90E2-16BEF06523F2`. Frames use the same CRC-checked Samsung protocol as the iOS bridge. Settings are stored in private Android application preferences only after a successful command, and incoming status packets take precedence over remembered values. Command history remains in memory unless the user opens Android's share sheet.

The transport follows Android's official guidance for [Bluetooth permissions](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions) and [RFCOMM connections](https://developer.android.com/develop/connectivity/bluetooth/connect-bluetooth-devices): connection work runs off the main thread and Android 12+ access is gated by `BLUETOOTH_CONNECT`.

See the repository [README](../README.md) for protocol attribution, unsupported features, license, and trademark information, and [PRIVACY.md](../PRIVACY.md) for the full privacy statement.
