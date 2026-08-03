# GlucoBridge

A personal sideload iOS app that bridges **FreeStyle Libre 3 Plus** glucose sensor data from the [LibreLinkUp](https://www.librelinkup.com/) cloud API into **Apple Health** via `BGAppRefreshTask`.

> ⚠️ **Disclaimer:** This project is unofficial and not affiliated with, endorsed by, or supported by Abbott Laboratories or any of its subsidiaries. Use of the LibreLinkUp API is unofficial, undocumented, and subject to Abbott's Terms of Service. Use this software at your own risk.

---

## What It Does

- Authenticates with the LibreLinkUp (LLU) API using your existing LibreLink credentials
- Fetches blood glucose readings from your FreeStyle Libre 3 Plus sensor
- Writes readings to Apple Health as `HKQuantityTypeIdentifierBloodGlucose` samples
- Keeps Health data current via layered sync triggers: sync on app open, opportunistic `BGAppRefreshTask`, a **Sync Glucose** Shortcuts action for automations, and a nightly full-history backfill while charging
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

## Background Sync — How It Works and What to Expect

LibreLinkUp is a poll-only API, so the app has to wake up to pull readings. iOS makes no guarantees about when (or whether) background tasks run — especially on a locked phone — so GlucoBridge layers several independent triggers. Any single successful sync backfills ~14 days from the LLU graph endpoint, so gaps self-heal. All of this works on a free Apple ID.

| Layer | Trigger | Reliability |
|---|---|---|
| Open the app | `scenePhase` foreground sync (debounced to 5 min) | Guaranteed — opening the app *is* the sync |
| Sync Now button | Manual | Guaranteed |
| Shortcuts automation | **Sync Glucose** App Intent | Very good — see setup below |
| `BGAppRefreshTask` | iOS opportunistic refresh (~15 min hint) | Best-effort; at Apple's discretion |
| Nightly backfill | `BGProcessingTask`, runs while charging | Good overnight; heals missed days |

The **Background sync** row in the app shows real scheduler state: green **Active** (a background task is queued and a sync landed within the last hour), yellow **Scheduled** (queued but no recent sync), or red **Not scheduled**.

### Recommended: Shortcuts automation (the big reliability win)

`BGAppRefreshTask` alone will disappoint you — iOS budgets it aggressively. The fix is to piggyback on apps you already open, using the **Sync Glucose** action, which syncs in the background without opening GlucoBridge:

1. Open **Shortcuts** → **Automation** tab → **+** (New Automation)
2. Choose **App** → select an app you open many times a day (Messages, Instagram, your mail app…) → **Is Opened**
3. Select **Run Immediately** and turn **Notify When Run** off
4. **Next** → **New Blank Automation** → **Add Action** → search **Sync Glucose**
5. Done. Every time you open that app, glucose syncs silently in the background.

Time-of-day automations (e.g. 8 AM / 1 PM / 6 PM / 10 PM) also work, but iOS only honors them reliably when the phone is unlocked or shortly after — the app-open trigger is the dependable one, because the phone is guaranteed awake at that moment.

### Realistic expectations

- With just the app installed and never opened: expect sparse, irregular syncs (whatever iOS grants `BGAppRefreshTask`, plus the nightly charge-time backfill).
- With one app-open automation on a daily-driver app: near-continuous coverage in practice.
- Every sync pulls the full ~14-day graph, so even a phone left in a drawer for a week catches up completely on the next sync.

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
