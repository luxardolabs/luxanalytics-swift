# Troubleshooting

## The app crashes at startup in `LuxAnalytics.shared`

`LuxAnalytics.shared` calls `fatalError` when it's accessed before `initialize` has finished. The message reads "LuxAnalytics.initialize() must be called before accessing shared instance", followed by a call stack. Usually something tracks during start-up (a view model's initializer, a static property, a singleton) before the `Task` that initializes has run.

- Initialize as early as possible, and `await` it before anything tracks.
- Where tracking can happen before initialization, use `LuxAnalytics.sharedIfInitialized` (optional) instead of `shared`. See [Guide → Accessing the instance](GUIDE.md#accessing-the-instance).

## Events aren't arriving

Work through what decides whether a flush happens ([Guide → When events are sent](GUIDE.md#when-events-are-sent)):

```swift
func diagnoseDelivery() async {
    print("enabled:", await AnalyticsSettings.shared.isEnabled)
    print("initialized:", await LuxAnalytics.isInitialized)
    print("online:", await LuxAnalytics.isNetworkAvailable())
    print("healthy:", await LuxAnalytics.healthCheck())

    let queue = await LuxAnalytics.getQueueStats()
    print("queued: \(queue.totalEvents), retrying: \(queue.retryingEvents)")

    if let breaker = await LuxAnalytics.getCircuitBreakerStatus() {
        print("circuit breaker: \(breaker.currentState), failures: \(breaker.failureCount)")
    }
}
```

- **`enabled: false`**: the user opted out; `track` throws `analyticsDisabled`.
- **Events queued, nothing sent**: flushes happen every `autoFlushInterval` (30 s by default). Call `LuxAnalytics.flush()` to send now.
- **Circuit breaker open**: five consecutive failures stop sending for 60 seconds. `LuxAnalytics.resetCircuitBreaker()` closes it.
- **Events disappear without arriving**: watch `LuxAnalyticsEvents.eventStream` for `eventsFailed`. A `serverError` with a 4xx status means the server refused the batch, and those events are dropped:
  - **401 or 403**: the DSN's public id isn't accepted. Check the DSN against your server's dashboard.
  - **404**: the project id doesn't exist on that server.
  - **422**: an event failed validation, for example an empty name.
  - **429**: rate limited. These are kept and retried, not dropped.

## Debug logging

```swift
func turnOnLogging() async {
    await LuxAnalytics.enableDiagnosticMode()
    await LuxAnalyticsDebug.status()
}
```

`enableDiagnosticMode()` turns on the same logging as `debugLogging: true`. Read it in Xcode's console, or in Console.app filtered to subsystem `com.luxardolabs.LuxAnalytics`. Sensitive values are redacted ([Privacy → Logs](PRIVACY.md#logs)).

## "Cannot convert value of type 'Int' to expected dictionary value type 'String'"

Metadata is `[String: String]`. Convert values: `["count": String(count), "premium": String(isPremium)]`.

## Events are dropped while offline for a long time

The queue holds at most `maxQueueSizeHard` events (10,000 by default) and keeps each for at most `eventTTL` (7 days by default). Beyond that, events are dropped and reported as `eventsDropped` or `eventsExpired`. Raise the limits in the configuration if your users are often offline for longer ([Configuration](CONFIGURATION.md#options)).

## The background flush never runs, or the app is killed at launch

`LuxAnalytics.enableBackgroundProcessing()` needs `com.luxardolabs.LuxAnalytics.flush` in your Info.plist's `BGTaskSchedulerPermittedIdentifiers`, and the **Background processing** mode:

- **The task never runs**: the identifier is missing from `BGTaskSchedulerPermittedIdentifiers`, so registration fails, or `enableBackgroundProcessing()` was called after the app finished launching. Apple requires registration to be complete before the end of launch. Even when registered, iOS decides when the task runs.
- **The app is killed**: `enableBackgroundProcessing()` was called more than once. iOS kills an app that registers the same task identifier twice. You don't need it for the flush that happens when the app enters the background. See [Guide → Background flushing](GUIDE.md#background-flushing).

## "SSL certificate verification failed" or `NSURLErrorDomain -1200`

The server's certificate doesn't validate.

- Use a certificate from a trusted CA (Let's Encrypt is free). Self-signed certificates aren't accepted.
- If your app pins with `NSPinnedDomains`, check that the server's current key (or CA) matches one of your pins. See [Privacy → Pinning your own server](PRIVACY.md#pinning-your-own-server).
