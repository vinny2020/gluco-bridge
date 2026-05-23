# GlucoBridge

A personal sideload iOS app that bridges **FreeStyle Libre 3 Plus** glucose sensor data from the [LibreLinkUp](https://www.librelinkup.com/) cloud API into **Apple Health** via `BGAppRefreshTask`.

> ⚠️ **Disclaimer:** This project is unofficial and not affiliated with, endorsed by, or supported by Abbott Laboratories or any of its subsidiaries. Use of the LibreLinkUp API is unofficial, undocumented, and subject to Abbott's Terms of Service. Use this software at your own risk.

---

## What It Does

- Authenticates with the LibreLinkUp (LLU) API using your existing LibreLink credentials
- Fetches blood glucose readings from your FreeStyle Libre 3 Plus sensor
- Writes readings to Apple Health as `HKQuantityTypeIdentifierBloodGlucose` samples
- Runs in the background via `BGAppRefreshTask` to keep Health data current
- Displays sync status, total readings synced, and sensor info in a clean SwiftUI interface

---

## Requirements

- iPhone running **iOS 17+**
- **FreeStyle Libre 3 Plus** sensor (other Libre sensors may work but are untested)
- An active **LibreLinkUp** account with your sensor connected
- A Mac with **Xcode 15+** to build and sideload
- Free or paid Apple Developer account for signing

---

## Tech Stack

- **Swift 6 / SwiftUI**
- **HealthKit** — for writing glucose samples to Apple Health
- **BackgroundTasks** (`BGAppRefreshTask`) — for periodic background sync
- **xcodegen** — project file generation via `project.yml`
- **Keychain** — for secure credential storage

---

## Building & Sideloading

This app is designed for **personal sideloading only** — it is not available on the App Store.

### 1. Clone the repo

```bash
git clone https://github.com/vinny2020/gluco-bridge.git
cd gluco-bridge
```

### 2. Generate the Xcode project

```bash
brew install xcodegen  # if not already installed
xcodegen generate
```

### 3. Open in Xcode and configure signing

- Open `HealthBridge.xcodeproj`
- In the project settings, select your Apple ID team under **Signing & Capabilities**
- Make sure HealthKit is enabled under Capabilities

### 4. Build and run on your device

- Connect your iPhone
- Select your device as the build target
- Press **⌘R** to build and install

> **Note:** Free Apple Developer accounts require re-signing every **7 days**. Paid accounts extend this to 1 year.

---

## Architecture

```
GlucoBridge/
├── App/
│   └── HealthBridgeApp.swift       # App entry point, BGAppRefreshTask registration
├── Views/
│   ├── ContentView.swift           # Main UI, sync status display
│   └── ConnectView.swift           # LLU login and sensor selection
├── Services/
│   ├── LLUService.swift            # LibreLinkUp API client
│   ├── SyncManager.swift           # Orchestrates fetch → HealthKit write
│   └── HealthKitManager.swift      # Apple Health read/write
├── Models/
│   ├── GlucoseReading.swift
│   └── LLUModels.swift
├── Helpers/
│   └── KeychainHelper.swift        # Secure credential storage
└── Resources/
    └── sensors.json                # Supported sensor definitions
```

---

## Logging & Debugging

The app uses `os_log` for structured logging. To stream logs from a connected device or simulator:

1. Open **Console.app**
2. Select your device or simulator in the sidebar
3. Filter by subsystem: `com.xaymaca.healthbridge`
4. Filter by category: `LLU` for API-specific events

---

## Known Limitations / Roadmap

- [ ] Auto-retry on first-fetch null data (server-side propagation delay after login)
- [ ] `SyncManager.disconnect()` does not yet clear all UserDefaults keys
- [ ] In-app sensor switcher (currently requires disconnect to change sensor type)
- [ ] Map known LLU API status codes to human-readable error messages
- [ ] Re-sign reminder for free Apple ID 7-day provisioning profiles

---

## Related Projects

This app is part of a personal health data stack:

- **[health-as-wealth](https://github.com/vinny2020/health-as-wealth)** — A dashboard that consumes glucose and other data flowing through Apple Health

---

## Inspiration & Community

This project stands on the shoulders of the DIY diabetes/CGM community:

- [LibreTransmitter](https://github.com/dabear/LibreTransmitter)
- [xDrip4iOS](https://github.com/JohanDegraeve/xdrip4ios)
- [Nightscout](https://github.com/nightscout/cgm-remote-monitor)
- [Loop](https://github.com/LoopKit/Loop)

---

## License

[MIT](LICENSE)

---

## ⚠️ Medical Disclaimer

This software is **not a medical device** and is **not intended for medical use**. Do not make treatment decisions based on data from this app. Always rely on your official FreeStyle Libre reader or the LibreLink app for clinical glucose readings.
