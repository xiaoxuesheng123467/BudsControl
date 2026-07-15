# Changelog

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
