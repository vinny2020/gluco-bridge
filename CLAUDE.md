# GlucoBridge — Claude Code Task Manifest

## Project Overview

GlucoBridge is a lightweight native iOS app that bridges Freestyle Libre glucose data from LibreLinkUp into Apple Health. It runs silently in the background, reads glucose readings from the LibreLinkUp cloud API, and writes them to Apple Health as HKQuantityType.bloodGlucose samples.

Once glucose is in Apple Health, Health Auto Export picks it up automatically and pushes it to the Health as Wealth dashboard on Mac via the REST ingest server.

**Personal sideload only — NOT for App Store distribution**.No FDA compliance concerns. No App Store review. Sideloaded via Xcode.

---

## Reference Code

`~/Documents/FLwatch (local checkout)` — open-source FLwatch app (MIT license). Study these files before writing any code. Reimplement cleanly — do NOT copy verbatim.

- `SharedPhoneWatch/Models/AppleHealthExportManager.swift` — HealthKit write logic
- `SharedPhoneWatch/Models/LibreLinkUpService.swift` — LibreLinkUp API client
- `SharedPhoneWatch/Models/LibreLinkUpGlucose.swift` — glucose data models
- `SharedPhoneWatch/Models/AuthTicket.swift` — auth token handling
- `SharedPhoneWatch/Models/PasswordKeychain.swift` — secure credential storage
- `SharedPhoneWatch/Models/LLUHeaders.swift` — required API request headers

HealthBridge only needs the glucose bridge — no Watch app, no insulin tracking, no widgets, no Live Activities, no internationalization.

---

## Stack

- **Language:** Swift 6
- **UI Framework:** SwiftUI (iPhone only — no Watch target)
- **HealthKit:** Native HealthKit framework
- **Networking:** URLSession (no third-party libraries)
- **Credential storage:** Keychain via Security framework
- **Background execution:** BGAppRefreshTask
- **Minimum iOS:** 17.0
- **Bundle ID:** com.xaymaca.healthbridge

---

## Privacy & Security Rules

- NEVER log glucose values to console in production builds
- NEVER store credentials in UserDefaults — Keychain only
- NEVER transmit data to any server except LibreLinkUp's official API
- No analytics, no crash reporting SDKs, no third-party dependencies
- No internationalization needed — personal use, English only
- Dates and units use system locale automatically via Swift APIs

---

## Architecture

```
LibreLinkUp API (Abbott's cloud)
    → LibreLinkUpService.swift (URLSession)
        → GlucoseSample model
            → HealthKitManager.swift (HKHealthStore)
                → Apple Health (blood glucose entries)
                    → Health Auto Export REST push to Mac
                        → Health as Wealth dashboard SQLite
```

Background sync via BGAppRefreshTask — iOS wakes app every \~15–30 min.

---

## App Structure

```
HealthBridge/
  HealthBridgeApp.swift           ← entry point, register background tasks
  Views/
    ContentView.swift             ← main status screen
    ConnectView.swift             ← LibreLinkUp credential entry
  Models/
    LibreLinkUpService.swift      ← API client (login, fetch readings)
    LibreLinkUpModels.swift       ← Codable response structs
    HealthKitManager.swift        ← HealthKit authorization + write
    KeychainHelper.swift          ← secure credential storage
    SyncManager.swift             ← orchestrates fetch → write flow
    SensorRegistry.swift          ← data-driven sensor type management
  Background/
    BackgroundTaskManager.swift   ← BGAppRefreshTask registration + handler
  Resources/
    sensors.json                  ← sensor definitions (updatable without rebuild)
```

---

## Task List

### TASK 1 — Xcode Project Setup

- \[ \] Create new Xcode project: iOS App, SwiftUI, Swift 6, bundle ID `com.xaymaca.healthbridge`
- \[ \] Target: iPhone only (no iPad, no Mac, no Watch)
- \[ \] Minimum deployment: iOS 17.0
- \[ \] Add HealthKit capability in Signing & Capabilities
- \[ \] Add Background Modes: enable "Background fetch" and "Background processing"
- \[ \] Add to Info.plist:
  - `NSHealthShareUsageDescription` → "HealthBridge reads nothing from Apple Health."
  - `NSHealthUpdateUsageDescription` → "HealthBridge writes your Libre glucose readings to Apple Health."
  - `BGTaskSchedulerPermittedIdentifiers` → `["com.xaymaca.healthbridge.sync"]`
- \[ \] Create folder structure per architecture above
- \[ \] No third-party Swift packages — pure Apple frameworks only
- \[ \] Add `HealthBridgeTests` unit test target

---

### TASK 2 — Sensor Registry (`Models/SensorRegistry.swift` + `Resources/sensors.json`)

Sensor definitions are data-driven — adding a new Libre generation requires only a JSON edit, no Swift code changes.

`Resources/sensors.json` (bundle with app):

```json
[
  { "id": "libre2",     "name": "FreeStyle Libre 2",      "durationDays": 14 },
  { "id": "libre3plus", "name": "FreeStyle Libre 3 Plus", "durationDays": 15 }
]
```

`Models/SensorRegistry.swift`:

```swift
struct SensorDefinition: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let durationDays: Int
}

class SensorRegistry {
    static let shared = SensorRegistry()
    private(set) var sensors: [SensorDefinition] = []

    func load()           // loads bundled sensors.json on startup
    func refresh(from url: URL) async  // future hook for remote updates
}
```

Store selected sensor ID in `UserDefaults` (not sensitive data — not Keychain). Use `SensorRegistry.shared.sensors` to populate the picker in `ConnectView`.

---

### TASK 3 — Keychain Helper (`Models/KeychainHelper.swift`)

```swift
struct KeychainHelper {
    static func save(key: String, value: String)
    static func load(key: String) -> String?
    static func delete(key: String)
    static func clearAll()  // called on disconnect
}
```

Keys to store (service: `"com.xaymaca.healthbridge"`):

- `"llu.email"` — LibreLinkUp account email
- `"llu.password"` — LibreLinkUp password
- `"llu.authToken"` — auth token from login response
- `"llu.tokenExpires"` — token expiry Unix timestamp (as String)
- `"llu.patientId"` — selected patient ID

Use `kSecClassGenericPassword`. All values encrypted at rest by iOS Keychain.

---

### TASK 4 — LibreLinkUp Models (`Models/LibreLinkUpModels.swift`)

Codable structs matching the LibreLinkUp API response format. Reference `FLwatch/SharedPhoneWatch/Models/LibreLinkUpGlucose.swift` for field names.

```swift
struct LLULoginRequest: Encodable      // email, password
struct LLULoginResponse: Decodable     // authTicket, user
struct LLUAuthTicket: Decodable        // token: String, expires: Int
struct LLUConnectionsResponse: Decodable  // list of patients
struct LLUPatient: Decodable           // patientId, firstName, lastName
struct LLUGraphResponse: Decodable     // glucoseMeasurement, graphData
struct LLUGlucoseMeasurement: Decodable   // value, timestamp, trendArrow
```

API base URL: `https://api.libreview.io`Required headers (reference `FLwatch/SharedPhoneWatch/Models/LLUHeaders.swift`):

- `product: llu.ios`
- `version: 4.7.0`
- `Content-Type: application/json`
- `Authorization: Bearer <token>` (after login)

---

### TASK 5 — LibreLinkUp API Service (`Models/LibreLinkUpService.swift`)

Protocol-based for testability (mock URLSession in tests):

```swift
protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
extension URLSession: URLSessionProtocol {}

actor LibreLinkUpService {
    init(session: URLSessionProtocol = URLSession.shared)

    func login(email: String, password: String) async throws -> LLUAuthTicket
    func fetchConnections(token: String) async throws -> [LLUPatient]
    func fetchGlucoseGraph(token: String, patientId: String) async throws -> [LLUGlucoseMeasurement]
}
```

- `login` → POST `/llu/auth/login`
- `fetchConnections` → GET `/llu/connections`
- `fetchGlucoseGraph` → GET `/llu/connections/{patientId}/graph`
- Check `tokenExpires` before each call — re-login if expired
- Throw typed errors: `.unauthorized`, `.networkError`, `.noData`, `.decodingError`

---

### TASK 6 — HealthKit Manager (`Models/HealthKitManager.swift`)

```swift
@MainActor
class HealthKitManager: ObservableObject {
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined

    func requestAuthorization() async throws
    func isAuthorized() -> Bool
    func saveGlucoseSamples(_ readings: [LLUGlucoseMeasurement]) async throws -> Int
    private func existingSyncIdentifiers(from: Date, to: Date) async throws -> Set<String>
}
```

Implementation details:

- Request write-only access to `.bloodGlucose` — no read permission needed
- Convert: `reading.value` mg/dL → `HKQuantity(unit: HKUnit(from: "mg/dL"), doubleValue:)`
- Sync identifier format: `"healthbridge.glucose.\(Int(timestamp)).\(value)"`
- Set `HKMetadataKeySyncIdentifier` and `HKMetadataKeySyncVersion: 1`
- Query existing samples before writing — skip already-written readings
- Return count of newly written samples (0 is valid — not an error)

---

### TASK 7 — Sync Manager (`Models/SyncManager.swift`)

```swift
@MainActor
class SyncManager: ObservableObject {
    @Published var lastSyncDate: Date?
    @Published var lastSyncCount: Int = 0
    @Published var syncError: String?
    @Published var isSyncing: Bool = false
    @Published var totalSynced: Int = 0  // persisted in UserDefaults

    func sync() async           // regular incremental sync
    func fullHistorySync() async // first-run: last 14 days
}
```

`sync()` flow:

1. Load token from Keychain — re-login if expired
2. Load patientId from Keychain
3. Fetch glucose graph from LibreLinkUp
4. Call `HealthKitManager.saveGlucoseSamples()`
5. Update `lastSyncDate`, `lastSyncCount`, `totalSynced`
6. Handle all errors — never crash, update `syncError` instead

`fullHistorySync()`:

- Called once on first successful connection
- Iterates over last 14 days to backfill Apple Health
- Shows progress in ContentView

---

### TASK 8 — Background Task Manager (`Background/BackgroundTaskManager.swift`)

```swift
class BackgroundTaskManager {
    static let taskIdentifier = "com.xaymaca.healthbridge.sync"

    static func registerTasks()        // call in HealthBridgeApp.init()
    static func scheduleNextSync()     // request next BGAppRefreshTask
    static func handleSyncTask(_ task: BGAppRefreshTask)
}
```

- Register before first view appears
- Schedule next sync 15 minutes from now (iOS controls actual timing)
- `handleSyncTask`: call `SyncManager().sync()`, mark task complete
- Schedule next sync at end of each successful execution
- Set `task.expirationHandler` to mark task expired if time runs out

---

### TASK 9 — Connect View (`Views/ConnectView.swift`)

Shown on first launch when no auth token in Keychain:

- Sensor type picker (populated from `SensorRegistry.shared.sensors`)
- Email field + SecureField for password
- "Connect" button → `LibreLinkUpService.login()` → save to Keychain
- On success → show patient name, trigger `fullHistorySync()`
- On failure → show inline error message
- No glucose values displayed anywhere in this app

---

### TASK 10 — Content View (`Views/ContentView.swift`)

Main status screen after connection:

```
HealthBridge

● Connected — Vincent Stoessel
  FreeStyle Libre 3 Plus

Last sync: 2 minutes ago
Readings written today: 8
Total synced: 847

[Sync Now]

Background sync  ●  Active
Apple Health     ●  Authorized

Next sensor change: Apr 24 (6 days)
```

- Green dot = ok, red dot = error/unauthorized
- "Sync Now" calls `SyncManager.sync()` directly
- Shows `syncError` if last sync failed
- Sensor change countdown uses `SensorDefinition.durationDays`
- Tapping Apple Health status row opens Health app settings if not authorized

---

### TASK 11 — App Entry Point (`HealthBridgeApp.swift`)

```swift
@main
struct HealthBridgeApp: App {
    @StateObject private var syncManager = SyncManager()
    @StateObject private var healthKit = HealthKitManager()

    init() {
        SensorRegistry.shared.load()
        BackgroundTaskManager.registerTasks()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if KeychainHelper.load(key: "llu.authToken") != nil {
                    ContentView()
                } else {
                    ConnectView()
                }
            }
            .environmentObject(syncManager)
            .environmentObject(healthKit)
        }
    }
}
```

---

### TASK 12 — Unit & Swift Tests (`HealthBridgeTests/`)

**Test classes:**

`KeychainHelperTests`

- `testSaveAndLoad` — save value, load back, assert equal
- `testDelete` — save, delete, assert nil
- `testOverwrite` — save twice, assert latest value
- `testLoadNonExistent` — assert nil without crash

`LibreLinkUpModelsTests`

- `testLoginResponseDecoding` — decode mock JSON, assert token parsed
- `testGlucoseDecoding` — decode mock reading, assert value + timestamp
- `testConnectionsDecoding` — decode mock connections, assert patientId
- `testMalformedJSON` — assert graceful failure, no crash

`SyncManagerTests`

- `testSyncIdentifierFormat` — assert `"healthbridge.glucose.\(ts).\(val)"`
- `testDeduplication` — readings with one duplicate → only unique written
- `testEmptyReadings` — zero readings completes without error

`LibreLinkUpServiceTests` (using MockURLSession)

- `testLoginSuccess` — mock 200 + valid JSON → token returned
- `testLoginFailure401` — mock 401 → auth error thrown
- `testNetworkError` — mock failure → error propagated
- `testTokenExpiry` — expired timestamp → re-login triggered

**Mock strategy:**

```swift
struct MockURLSession: URLSessionProtocol {
    var responseData: Data
    var statusCode: Int = 200

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode,
            httpVersion: nil, headerFields: nil)!
        return (responseData, response)
    }
}
```

**Test fixtures** in `HealthBridgeTests/Fixtures/`:

- `login_success.json` — valid login response with token
- `login_failure.json` — 401 error response
- `connections_success.json` — one patient connection
- `glucose_graph.json` — 5 glucose readings with timestamps

**Coverage goals:**

- `KeychainHelper` → 100%
- `LibreLinkUpModels` → 100%
- `SyncManager` deduplication logic → 100%
- `LibreLinkUpService` (with mock) → 80%+
- `HealthKitManager` → skip (requires real HealthKit — test on device)
- `BackgroundTaskManager` → skip (requires BGTaskScheduler — test on device)

**Run tests:**

```bash
xcodebuild test \
  -scheme HealthBridge \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -resultBundlePath TestResults.xcresult
```

All tests must pass in Simulator before building to physical device.

---

### TASK 13 — Device Testing & Sideload

- \[ \] Build and run in iOS Simulator — verify HealthKit mock writes work
- \[ \] Connect with real LibreLinkUp credentials
- \[ \] Verify glucose samples appear in Health app: Health → Browse → Body Measurements → Blood Glucose
- \[ \] Build to physical iPhone via Xcode + Apple Developer account
- \[ \] Leave app in background 30 min — confirm BGAppRefreshTask fires
- \[ \] Verify Health Auto Export picks up `blood_glucose` in next REST push
- \[ \] Confirm real glucose reading appears in Health as Wealth dashboard

---

## Notes for Claude Code

- Reference FLwatch at `~/Documents/FLwatch (local checkout)` — guide only
- Reimplement cleanly — HealthBridge is intentionally minimal
- No glucose values in UI — avoids any appearance of being a medical device
- All networking goes to LibreLinkUp only — never send health data elsewhere
- Test HealthKit writes in Simulator before running on device
- BGAppRefreshTask timing is iOS-controlled — 15 min is a hint, not a guarantee
- First launch: connect → `fullHistorySync()` → background sync takes over
- App icon and launch screen: basic/default is fine for personal sideload
- No internationalization — English only, system locale for dates/units

---

## Parked Work / Future Polish (2026-04-26 handoff, revised 2026-08-03)

The data path is end-to-end working on simulator and a real iPhone — Libre 3 Plus glucose is flowing into Apple Health. **However (2026-08-03 discovery): every sync so far has been manually triggered.** Background sync never runs — see item 0 / GitHub Issue #1. The remaining items are non-blocking polish.

### 0. Layered sync triggers — ALL LAYERS IMPLEMENTED 2026-08-03 (GitHub Issue #1)

**Status:** Layers 1–2 landed in commit 91d0b40; layers 3–4, honest indicator, and README docs landed 2026-08-03. All 18 unit tests pass in simulator. Still pending: on-device verification (BG task firing overnight, Shortcuts automation end-to-end) and closing Issue #1. Implementation notes: `SyncGlucoseIntent` + `AppShortcutsProvider` in `HealthBridge/Intents/`; backfill task `com.xaymaca.healthbridge.backfill` (BGProcessingTask, requires power + network, earliest next 2 AM); `lastSyncDate` now persisted in UserDefaults (`healthbridge.lastSyncDate`) so the debounce and indicator work across process launches; both BG handlers share a `TaskCompletionGuard` so the expiration handler and sync task can't double-complete — the auto-retry work (item 1) can rely on that.

**Discovery:** `scheduleNextSync()` is only called from inside `handleSyncTask()` — nothing ever submits the FIRST `BGAppRefreshTaskRequest`, so the handler never fires and background sync has been dead since the first commit. The "Background sync: Active" indicator in ContentView is hardcoded. There is also no launch/foreground sync — `ContentView.onAppear` only refreshes HealthKit auth. The manual Sync Now button is currently the only trigger in the app.

**Fix plan** (full details + task checklist in https://github.com/vinny2020/gluco-bridge/issues/1). LLU is poll-only, so the architecture stays pull-based with layered wake-up triggers. All layers work on a free Apple ID — deliberate constraint, keeps the project fully DIY-buildable:

1. **Layer 2 first — auto-sync on foreground.** Watch `scenePhase` in `HealthBridgeApp`; on `.active`, run `sync()` debounced (skip if `lastSyncDate` < 5 min old). Smallest diff, kills the manual-button requirement.
2. **Layer 1 — fix the scheduler.** Call `scheduleNextSync()` at launch and on `scenePhase == .background`.
3. **Layer 3 — `SyncGlucoseIntent` (App Intents).** Runs sync in background without opening the app; enables Shortcuts Personal Automations ("when [daily-use app] opens → Sync Glucose", notifications off — phone guaranteed awake, the app-open-trigger pattern from the Wousp/@qi9098 Shortcuts-export article). Time-of-day automations also supported.
4. **Layer 4 — nightly `BGProcessingTask` backfill.** `processing` mode already declared in Info.plist, unused. Full-history pull while charging heals missed days.
5. **Honest status indicator.** Replace hardcoded "Active" with `BGTaskScheduler.shared.getPendingTaskRequests` + last-sync recency.
6. **Docs.** README section: Shortcuts automation setup + realistic background-reliability expectations.

**Interaction warning:** item 1 below (auto-retry) must respect the ~30s `BGAppRefreshTask` runway — retry sleeps inside a BG task must cooperate with the expiration handler or the task dies mid-write.

**Distribution posture (decided 2026-08-03):** DIY-build stays the primary and only public path — same liability posture as Loop/Nightscout (no distributed binaries). TestFlight is possible (paid dev account in hand) but deliberately not offered publicly for now.

### 1. Auto-retry on first-fetch null data ⭐ (highest value)

**Symptom:** Right after a fresh login, `fetchGlucoseGraph` reliably returns `{"data": null}` once, surfacing as the red "No glucose data returned." line. A second tap of Sync Now (or any later background fetch) succeeds. Likely cause: LLU server-side propagation delay between issuing the auth token and the graph endpoint accepting it for that account.

**Fix:** in `HealthBridge/Models/LibreLinkUpService.swift`, wrap the `fetchGlucoseGraph` retry loop so that an `LLUError.apiError` or `LLUError.noData` from the first attempt triggers ONE silent retry after a short sleep (\~2s) before propagating to the UI. Don't retry on `.unauthorized`, `.redirectRequired`, or `.networkError` — those need to fail fast.

**Sketch:**

```swift
for attempt in 0...2 {  // current loop is 0...1 for redirect handling — bump to allow retry
    // ... existing fetch + decode ...
    do {
        guard let graphData = decoded.data else {
            if attempt == 0 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }
            throw LLUError.apiError(...)
        }
        // success path
    }
}
```

Be careful: the existing `attempt == 0` branch is already used for regional redirect handling. The retry-on-null-data needs its own counter, or the loop ceiling needs to bump to 2 with both branches respected.

### 2. `SyncManager.disconnect()` doesn't clear UserDefaults

Currently only wipes keychain. Leaves stale `selectedSensorId`, `patientDisplayName`, `sensorStartDate`, `healthbridge.totalSynced` in UserDefaults. Harmless because they're overwritten on next connect, but a fresh disconnect should be a clean slate. Add:

```swift
let defaults = UserDefaults.standard
["selectedSensorId", "patientDisplayName", "sensorStartDate",
 "healthbridge.totalSynced"].forEach { defaults.removeObject(forKey: $0) }
```

### 3. In-app sensor switcher on `ContentView`

Right now the only way to change sensor type after connecting is to tap Disconnect → re-enter creds → pick new sensor. A `Picker` or settings sheet on ContentView's connection card would let the user switch (e.g., when they upgrade from Libre 3 Plus to a future sensor) without losing their session. The `onAppear` saved-value logic in ConnectView (fixed this session) already supports this cleanly.

### 4. Free-provisioning re-sign reminder

Personal Apple ID provisioning profiles expire every 7 days. When the app stops launching on the real iPhone with "could not be verified", plug in and `⌘R` from Xcode again. Eventually consider: paid Apple Developer account ($99/yr) bumps to a year, or App Store Connect TestFlight for self-distribution. Not urgent.

### 5. Status code coverage

The new `LLUError.apiError(status:snippet:)` surfaces the status field from LLU responses. Worth eventually mapping known codes (`2`, `4`, `911`, etc.) to human-readable messages similar to how status `920` is already handled in `checkMinimumVersionResponse`. Currently anything non-zero just shows the raw number plus body snippet — better than before, but could be friendlier.

### Diagnostic hooks added this session

- `os_log` subsystem `com.xaymaca.healthbridge`, category `LLU` — stream via Console.app (Window → Devices → iPhone → filter on subsystem)
- `LLUError.apiError(status: Int?, snippet: String)` — surfaces LLU status code + first 400 chars of response body in the UI
- `Self.describeDecodingError(_:endpoint:)` — endpoint-aware decoding error messages without leaking payload values
