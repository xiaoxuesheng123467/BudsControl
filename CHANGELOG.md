# Changelog

## Unreleased

### Fixed

- Made iOS bridge status polling single-flight so Bonjour updates and timed polling cannot start competing TLS requests.
- Parse a complete bridge HTTP response as soon as its declared body arrives instead of losing valid data to a later TLS close event.
- Keep an established bridge usable through one transient failure or Bonjour interface change, with actionable in-app diagnostics and retry controls.

## Windows 0.1.0 - 2026-07-16

### Added

- Native Windows 10 2004+ WPF client with direct Bluetooth Classic RFCOMM access to already paired Galaxy Buds3 Pro.
- Dashboard and secondary views for batteries, noise control, EQ, ambient customization, touch controls, connection options, fit test, Find My Earbuds, and validation reports.
- Per-connection frame parsing, command serialization, ACK matching, connection timeout, state refresh after uncertain writes, and safe reconnect handling.
- Local settings storage, last-device auto-connect, offline demonstration mode, and explicit experimental-command authorization.
- Nineteen protocol, framing, settings, and transport-semantics tests plus a framework-dependent `win-x64` preview package.

### Still Pending Hardware Validation

- WPF startup, DPI layout, Windows Bluetooth adapter behavior, the Buds3 Pro RFCOMM connection, and every real-earbud command.
- The downloadable ZIP is an unsigned preview and requires the .NET 9 Desktop Runtime.

## Android 0.1.0 - 2026-07-16

### Added

- Native Android 8+ client with direct Bluetooth Classic RFCOMM connection to already paired Galaxy Buds3 Pro.
- Dashboard for connection, left/right/case battery, ANC, ambient, adaptive noise control, and six EQ presets.
- Secondary pages for ambient customization, voice detection, touch controls, long-pinch actions, noise cycles, stereo balance, calls, and connection options.
- Fit test, Find My Earbuds with per-side mute, experimental-command gate, and validation center.
- Local last-setting memory, last-device auto-connect, offline demonstration mode, packet history, and exportable validation report.
- Android 12+ Nearby devices permission flow without location permission or discovery scanning.
- CRC/frame parser, serial command queue, acknowledgement timeout, extended-state decoding, and unit tests.

### Still Pending Hardware Validation

- The Android RFCOMM connection and every real-earbud command. Protocol/unit tests, lint, builds, and the full offline simulator flow pass, but no physical Buds3 Pro was available for this release.
- The downloadable APK is a direct-install preview build rather than a Play Store release.

## 0.2.0 - 2026-07-16

### Added

- Adaptive noise-control command and live extended-state decoding.
- Ambient volume, extra-high ambient, and independent left/right ambient customization.
- Voice detection, restore timeout, and one-ear noise control.
- Touch lock, per-gesture switches, left/right long-pinch actions, noise-control cycles, and edge double-tap volume.
- Stereo balance, seamless connection, sidetone, call-path control, clear-call sound, spatial-audio switch, gaming mode, and wear auto-pause mapping.
- Earbud fit test and Find My Earbuds with per-side mute and automatic stop.
- Local last-setting memory that is corrected by live earbud state after reconnecting.
- Offline demo mode, experimental-command gate, packet history, and exportable validation report.
- Named bridge command allowlist with strict payload validation and ACK-versus-write-only results.
- Objective-C bridge protocol self-test and broader Swift packet vectors.

### Still Pending Hardware Validation

- Every newly mapped 0.2.0 control above; the original ANC, ambient, EQ, and battery paths remain the only hardware-verified controls.
- Adaptive volume and siren detection are experimental and disabled by default.
- Blade Light writes, custom 9-band EQ, firmware updates, and Samsung account services remain unavailable.
