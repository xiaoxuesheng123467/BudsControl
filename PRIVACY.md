# Privacy

BudsControl does not contain analytics, advertising SDKs, or cloud services. The iPhone app talks to BudsBridge on the local network. BudsBridge then opens the Samsung RFCOMM service on the paired earbuds. The Android app connects directly to the same service using Bluetooth Classic and does not use a Mac bridge.

The app stores the current 128-bit bridge pairing secret in `UserDefaults`. BudsBridge generates a new secret each time it starts, so an old value cannot connect to a new session. Network requests use TLS-PSK; the secret is not sent over a plaintext connection.

When “记住上次设置” is enabled, the app also stores the last successfully applied earbud settings in `UserDefaults`. A later extended-status packet from the earbuds corrects those saved values field by field. Turning the option off deletes the saved settings. The validation command log stays only in process memory unless the user explicitly opens the share sheet and chooses a destination.

On Android, the equivalent settings are stored in the app's private `SharedPreferences`. Android 12 and newer require the Nearby devices (`BLUETOOTH_CONNECT`) permission to access already paired earbuds. BudsControl does not request location permission, scan for unpaired devices, or upload Bluetooth names or addresses. The selected device address is stored privately so the app can reconnect to the last paired earbuds. Android validation history also remains in process memory unless the user explicitly opens the system share sheet.

Bluetooth diagnostics are created only after the user opens the diagnostics screen. The scan counts nearby advertisements but persists details only for Buds candidates. Those details can include the candidate identifier, device name, service UUIDs, manufacturer payload, characteristic properties, and raw characteristic values. The log leaves the phone only when the user opens the share sheet and chooses a destination. The diagnostics screen includes a clear-log action.

BudsBridge prints connection state, battery readings, transmitted commands, and acknowledgements to the current terminal. It does not create a persistent log file.
