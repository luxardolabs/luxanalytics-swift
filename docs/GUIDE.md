# Guide

How to set up LuxAnalytics, track events, and what the SDK does with them. Every example compiles against the SDK (`make docs-check`).

## Initialize

Initialize once, as early as possible, with your project's DSN (see [Configuration](CONFIGURATION.md#the-dsn)):

```swift
func startAnalytics() async throws {
    try await LuxAnalytics.quickStart(
        dsn: "https://your-public-id@analytics.example.com/api/v1/events/your-project-id",
        debugLogging: false
    )
}
```

`quickStart` is shorthand for building a configuration with the defaults and calling `initialize(with:)`. To change other options, build the configuration yourself:

```swift
func startAnalytics() async throws {
    let config = try LuxAnalyticsConfiguration(
        dsn: "https://your-public-id@analytics.example.com/api/v1/events/your-project-id",
        autoFlushInterval: 60,
        batchSize: 100
    )
    try await LuxAnalytics.initialize(with: config)
}
```

Or read the DSN from Info.plist (key `LuxAnalyticsDSN`; see [Configuration](CONFIGURATION.md#infoplist)):

```swift
func startAnalytics() async throws {
    try await LuxAnalytics.initializeFromPlist()
}
```

Initializing twice throws `LuxAnalyticsError.alreadyInitialized`. A malformed DSN throws `LuxAnalyticsError.invalidConfiguration`.

### Accessing the instance

`LuxAnalytics.shared` returns the instance, and **stops the app with a `fatalError` if `initialize` hasn't completed**. That usually happens when something tracks during app start-up, before the `Task` that initializes has run. Where that's possible, use the optional accessor instead:

```swift
func trackIfReady(_ name: String) async {
    guard let analytics = await LuxAnalytics.sharedIfInitialized else { return }
    try? await analytics.track(name)
}
```

You can also store a configuration early and let the first access initialize:

```swift
func prepareAnalytics() async throws {
    let config = try LuxAnalyticsConfiguration(
        dsn: "https://your-public-id@analytics.example.com/api/v1/events/your-project-id")
    await LuxAnalytics.setPendingConfiguration(config)

    // Later: initializes with the pending configuration on first access.
    try await LuxAnalytics.lazyShared.track("app_opened")
}
```

`lazyShared` also calls `fatalError` if neither `initialize` nor `setPendingConfiguration` has run.

## Track events

```swift
func trackPurchase(plan: String, seats: Int, trial: Bool) async throws {
    try await LuxAnalytics.shared.track(
        "purchase_completed",
        metadata: [
            "plan": plan,
            "seats": String(seats),
            "trial": String(trial),
        ]
    )
}
```

- **Metadata is `[String: String]`.** The server stores a string-to-string map, so convert numbers and booleans yourself.
- **`track` doesn't send anything.** It adds the event to the on-device queue; see [When events are sent](#when-events-are-sent).
- **It throws** `analyticsDisabled` if the user has opted out (see [Opting out](#opting-out)), and `notInitialized` if no configuration is set.

Each event also records:

- an `id` (a UUID) that stays the same through retries, so the server can drop a duplicate delivery
- a `timestamp` (ISO 8601, taken when `track` is called)
- the current user and session ids, if set
- device and app context, merged under your metadata (your keys win): `device_model`, `device_type`, `screen_resolution`, `system_version`, `app_version`, `build_number`, `locale`, `timezone`, `device_id`, `is_testflight`, `platform`. See [Privacy](PRIVACY.md#what-is-collected).

## Users and sessions

```swift
func didSignIn(userID: String) async {
    let analytics = await LuxAnalytics.shared
    await analytics.setUser(userID)
    await analytics.setSession(UUID().uuidString)
}

func didSignOut() async {
    let analytics = await LuxAnalytics.shared
    await analytics.setUser(nil)
    await analytics.setSession(nil)
}
```

Both apply to events tracked afterwards. They are held in memory only, so set them again after each launch. The SDK has no getters for them; keep your own copy if you need to read them back.

## SwiftUI and UIKit

There are no special view helpers; call `track` where it fits. A screen view in SwiftUI:

```swift
struct SettingsView: View {
    var body: some View {
        Form {
            Text("Settings")
        }
        .task {
            try? await LuxAnalytics.shared.track("screen_view", metadata: ["screen": "settings"])
        }
    }
}
```

And in UIKit:

```swift
final class SettingsViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            try? await LuxAnalytics.shared.track("screen_view", metadata: ["screen": "settings"])
        }
    }
}
```

## When events are sent

Events wait in an on-device queue. A **flush** sends the oldest ready events (up to `batchSize`, default 50) in one request. One event is sent on its own; two or more are wrapped as `{"events": [...]}`. Bodies of 1 KB or more are zlib-compressed (`Content-Encoding: deflate`).

A flush happens:

- every `autoFlushInterval` (default 30 s)
- after `track`, when the queue holds `maxQueueSize` (default 500) or more events
- when the app enters the background (inside a `UIApplication` background task) and when it terminates
- on a memory warning, if the queue holds more than half of `maxQueueSize`
- when you call `LuxAnalytics.flush()`

A flush is skipped, and events stay queued, when:

- analytics is disabled, or the SDK isn't initialized
- the device is offline
- the server asked the SDK to back off with `Retry-After`, and that time hasn't passed
- the circuit breaker is open: after **5 consecutive failures** it stops sending for **60 seconds**, then lets requests through again; 3 successes close it, and another failure reopens it

### What happens to a batch

| Server response | Result |
|---|---|
| 2xx | Sent. Removed from the queue. |
| 429 Too Many Requests | Kept and retried. Doesn't count against the circuit breaker. |
| 408, 5xx, or a network error | Kept and retried, and counts against the circuit breaker. |
| Any other 4xx (400, 401, 404, 422, …) | Dropped: retrying would fail the same way. |

A retried event waits 2ⁿ seconds after its n-th failure (±25% jitter, at most 5 minutes) before it is sent again. It is retried up to `maxRetryAttempts` times (default 5, so six attempts in all), then dropped. A `Retry-After` header (seconds or an HTTP date, capped at one hour) holds every flush to that server until it passes.

### Queue limits

- The queue is saved on the device, encrypted, so events survive app restarts (see [Privacy](PRIVACY.md#storage-on-the-device)).
- Events older than `eventTTL` (default 7 days) are dropped before each flush and at initialization.
- At `maxQueueSizeHard` events (default 10,000), `overflowStrategy` decides what goes: `.dropOldest` (default) removes the oldest events, `.dropNewest` rejects the new event, `.dropAll` empties the queue first.

### Background flushing

Flushing on entering the background needs no setup. To also let iOS run a flush later, while the app is suspended, opt in to a `BGProcessingTask`:

1. Add `com.luxardolabs.LuxAnalytics.flush` to `BGTaskSchedulerPermittedIdentifiers` in your Info.plist, and enable the **Background processing** mode.
2. Register before the app finishes launching:

```swift
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LuxAnalytics.enableBackgroundProcessing()
        return true
    }
}
```

iOS decides when the task runs (the SDK asks for no earlier than an hour later, with network). Call it **once**: iOS kills an app that registers the same task identifier twice. If the identifier isn't in `BGTaskSchedulerPermittedIdentifiers`, registration fails and the task never runs.

## Opting out

```swift
func setAnalyticsConsent(_ granted: Bool) async {
    await AnalyticsSettings.shared.setEnabled(granted)
    if !granted {
        await LuxAnalytics.clearQueue()
        await LuxAnalytics.resetDeviceID()
    }
}
```

The setting is saved in `UserDefaults` and defaults to enabled. While disabled, `track` throws `analyticsDisabled` and nothing is sent. `resetDeviceID()` gives the device a new random analytics ID; see [Privacy](PRIVACY.md#the-device-id).

## Observing events

`LuxAnalyticsEvents.eventStream` reports what happens to events:

```swift
func observeAnalytics() async {
    for await notification in LuxAnalyticsEvents.eventStream {
        switch notification {
        case .eventQueued(let event):
            print("queued \(event.name)")
        case .eventsSent(let events):
            print("sent \(events.count)")
        case .eventsFailed(let events, let error):
            print("failed \(events.count): \(error.localizedDescription)")
        case .eventsDropped(let count, let reason):
            print("dropped \(count) (\(reason))")
        case .eventsExpired(let events):
            print("expired \(events.count)")
        }
    }
}
```

- `eventsSent` and `eventsFailed` arrive once per event, not once per batch.
- `eventsFailed` is reported for every failed attempt, including ones that will be retried.
- `eventsDropped` reports queue overflow with the strategy that applied. An event that runs out of retries is also reported as `eventsDropped(count: 1, reason: .dropOldest)`.

## Diagnostics

```swift
func printAnalyticsHealth() async {
    let healthy = await LuxAnalytics.healthCheck()
    let queue = await LuxAnalytics.getQueueStats()
    print("healthy: \(healthy), queued: \(queue.totalEvents), retrying: \(queue.retryingEvents)")

    if let metrics = await LuxAnalytics.getMetrics() {
        print("sent: \(metrics.networkStats.totalEventsSent)")
        print("failed: \(metrics.networkStats.totalEventsFailed)")
        print("compression ratio: \(metrics.networkStats.compressionRatio)")
    }
    if let json = await LuxAnalytics.exportDiagnostics() {
        print(json)
    }
}
```

- `healthCheck()` is true when the SDK is initialized, the device is online and the circuit breaker is closed.
- The metrics count since launch, or since `LuxAnalytics.resetDiagnostics()`.
- `LuxAnalyticsDebug.status()` and `LuxAnalyticsDebug.validateSetup()` write a readable summary to the console.
- With `debugLogging: true`, or after `LuxAnalytics.enableDiagnosticMode()`, the SDK logs to the unified log under subsystem `com.luxardolabs.LuxAnalytics`, with sensitive values redacted ([Privacy](PRIVACY.md#logs)).
