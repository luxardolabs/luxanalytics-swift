# API Reference

The public API of LuxAnalytics 1.1.0. Each signature listing below is checked against the compiler-emitted public interface by `make docs-check`, so it matches the code. For how the pieces fit together, see the [Guide](GUIDE.md).

## LuxAnalytics

The entry point. Everything is `async`; the class is `Sendable`.

### Setup

```swift interface
public static func quickStart(dsn: String, debugLogging: Bool = false) async throws
public static func initialize(with configuration: LuxAnalyticsConfiguration) async throws
public static func initializeFromPlist(bundle: Bundle = .main) async throws
public static func setPendingConfiguration(_ config: LuxAnalyticsConfiguration) async
public static var isInitialized: Bool // get async
```

- `initialize` throws `alreadyInitialized` on a second call.
- `initializeFromPlist` reads the keys listed in [Configuration](CONFIGURATION.md#infoplist).

### The instance

```swift interface
public static var shared: LuxAnalytics // get async
public static var sharedIfInitialized: LuxAnalytics? // get async
public static var lazyShared: LuxAnalytics // get async
```

- `shared` stops the app with `fatalError` if the SDK isn't initialized.
- `sharedIfInitialized` returns nil instead.
- `lazyShared` initializes from a pending configuration first, and calls `fatalError` if there isn't one.

### Tracking

```swift interface
public func track(_ name: String, metadata: [String : String] = [:]) async throws
public func trackSanitized(_ name: String, metadata: [String : String] = [:]) async throws
public func trackWithRedaction(_ name: String, metadata: [String : String], redactFields: Set<String>) async throws
public func trackWithRedaction(_ name: String, redactFields: Set<String>) async throws
public func setUser(_ userId: String?) async
public func setSession(_ sessionId: String?) async
```

- `track` queues the event; it throws `analyticsDisabled` or `notInitialized`.
- `trackSanitized` runs `PIIFilter.sanitizeMetadata` over the metadata first.
- `trackWithRedaction` replaces the named fields with `"[REDACTED]"`.
- `setUser` and `setSession` apply to later events. Pass nil to clear.

### Queue and sending

```swift interface
public static func flush() async
public static func forceFlush() async
public static func clearQueue() async
public static func getQueueStats() async -> QueueStats
public static func isNetworkAvailable() async -> Bool
public static func healthCheck() async -> Bool
```

- `flush` sends one batch now, if a flush is allowed (see [When events are sent](GUIDE.md#when-events-are-sent)). `forceFlush` is the same call.
- `healthCheck` is true when the SDK is initialized, online, and the circuit breaker is closed.

### Device, diagnostics, background

```swift interface
public static func resetDeviceID() async
public static func getMetrics() async -> LuxAnalyticsMetrics?
public static func getDiagnostics() async -> LuxAnalyticsMetrics
public static func exportDiagnostics() async -> String?
public static func resetDiagnostics() async
public static func enableDiagnosticMode() async
public static func getCircuitBreakerStatus() async -> CircuitBreakerMetrics?
public static func resetCircuitBreaker() async
public static func enableBackgroundProcessing()
```

- `resetDeviceID` replaces the device ID with a random one ([Privacy](PRIVACY.md#the-device-id)).
- `getMetrics` returns nil before initialization; `getDiagnostics` always returns metrics.
- `exportDiagnostics` is the metrics as pretty-printed JSON.
- `enableDiagnosticMode` turns on debug logging.
- `enableBackgroundProcessing` is `@MainActor`; see [Background flushing](GUIDE.md#background-flushing).

## LuxAnalyticsConfiguration

```swift interface
public struct LuxAnalyticsConfiguration : Sendable {
  public init(dsn: String, autoFlushInterval: TimeInterval = LuxAnalyticsDefaults.autoFlushInterval, maxQueueSize: Int = LuxAnalyticsDefaults.maxQueueSize, batchSize: Int = LuxAnalyticsDefaults.batchSize, debugLogging: Bool = LuxAnalyticsDefaults.debugLogging, requestTimeout: TimeInterval = LuxAnalyticsDefaults.requestTimeout, maxQueueSizeHard: Int = LuxAnalyticsDefaults.maxQueueSizeHard, eventTTL: TimeInterval = LuxAnalyticsDefaults.eventTTL, maxRetryAttempts: Int = LuxAnalyticsDefaults.maxRetryAttempts, overflowStrategy: QueueOverflowStrategy = LuxAnalyticsDefaults.overflowStrategy, compressionEnabled: Bool = LuxAnalyticsDefaults.compressionEnabled, compressionThreshold: Int = LuxAnalyticsDefaults.compressionThreshold) throws
  public init(bundle: Bundle = .main) throws
  public let dsn: String
  public let apiURL: URL
  public let publicId: String
  public let projectId: String
  public let autoFlushInterval: TimeInterval
  public let maxQueueSize: Int
  public let batchSize: Int
  public let debugLogging: Bool
  public let requestTimeout: TimeInterval
  public let maxQueueSizeHard: Int
  public let eventTTL: TimeInterval
  public let maxRetryAttempts: Int
  public let overflowStrategy: QueueOverflowStrategy
  public let compressionEnabled: Bool
  public let compressionThreshold: Int
}

public enum QueueOverflowStrategy : String, Codable, Sendable {
  case dropOldest
  case dropNewest
  case dropAll
}
```

The defaults are the constants of `LuxAnalyticsDefaults`, listed with what each option does in [Configuration](CONFIGURATION.md#options).

## Events

```swift interface
public struct AnalyticsEvent : Codable, Sendable {
  public let id: String
  public let name: String
  public let timestamp: String
  public let userId: String?
  public let sessionId: String?
  public let metadata: [String : String]
  public init(name: String, timestamp: String, userId: String?, sessionId: String?, metadata: [String : String])
}

public struct LuxAnalyticsEvents : Sendable {
  public static var eventStream: AsyncStream<AnalyticsEventNotification> // get
}

public enum AnalyticsEventNotification : Sendable {
  case eventQueued(AnalyticsEvent)
  case eventsSent([AnalyticsEvent])
  case eventsFailed([AnalyticsEvent], error: LuxAnalyticsError)
  case eventsDropped(count: Int, reason: QueueOverflowStrategy)
  case eventsExpired([AnalyticsEvent])
  case eventsAbandoned([AnalyticsEvent], lastError: LuxAnalyticsError)
}
```

Each access to `eventStream` returns a new stream that receives every notification from then on. When notifications arrive is described in [Observing events](GUIDE.md#observing-events).

## Errors

```swift interface
public enum LuxAnalyticsError : LocalizedError, Equatable, Sendable {
  case alreadyInitialized
  case notInitialized
  case invalidConfiguration(String)
  case networkError(any Error)
  case serverError(statusCode: Int, response: String?)
  case encodingError(any Error)
  case queueError(String)
  case analyticsDisabled
}
```

| Case | When |
|---|---|
| `alreadyInitialized` | `initialize` called twice |
| `notInitialized` | `track` before a configuration is set |
| `invalidConfiguration` | Malformed DSN, or no `LuxAnalyticsDSN` in Info.plist |
| `analyticsDisabled` | `track` while the user has opted out |
| `serverError` | In `eventsFailed`: the server answered with a non-2xx status. `response` is the body, with sensitive values redacted. |
| `networkError` | In `eventsFailed`: the request failed (TLS failure, timeout, connection lost), or the batch couldn't be JSON-encoded |
| `encodingError` | In `eventsFailed`: a batch couldn't be compressed |
| `queueError` | Not currently produced |

## Queue stats and metrics

```swift interface
public struct QueueStats : Sendable, Codable {
  public let totalEvents: Int
  public let totalSizeBytes: Int
  public let oldestEventAge: TimeInterval?
  public let newestEventAge: TimeInterval?
  public let retryingEvents: Int
}

public struct LuxAnalyticsMetrics : Codable, Sendable {
  public let timestamp: Date
  public let queueStats: QueueStats
  public let networkStats: LuxAnalyticsMetrics.NetworkStats
  public let performanceStats: LuxAnalyticsMetrics.PerformanceStats
  public let configurationInfo: LuxAnalyticsMetrics.ConfigurationInfo
  public let circuitBreakerStatus: LuxAnalyticsMetrics.CircuitBreakerStatus?
  public struct NetworkStats : Codable, Sendable {
    public let totalEventsSent: Int
    public let totalEventsFailed: Int
    public let totalBatchesSent: Int
    public let totalBatchesFailed: Int
    public let lastSuccessfulSend: Date?
    public let lastFailedSend: Date?
    public let averagePayloadSize: Int
    public let compressionRatio: Double
  }
  public struct PerformanceStats : Codable, Sendable {
    public let averageFlushDuration: TimeInterval
    public let averageCompressionTime: TimeInterval
    public let memoryUsage: Int
    public let diskUsage: Int
  }
  public struct ConfigurationInfo : Codable, Sendable {
    public let sdkVersion: String
    public let configuredEndpoint: String
    public let autoFlushInterval: TimeInterval
    public let maxQueueSize: Int
    public let compressionEnabled: Bool
    public let debugLoggingEnabled: Bool
  }
  public struct CircuitBreakerStatus : Codable, Sendable {
    public let state: String
    public let failureCount: Int
    public let successRate: Double
    public let timeInCurrentState: TimeInterval
  }
}
```

- `retryingEvents` counts queued events that have failed at least once.
- Network and performance stats count since launch, or since `resetDiagnostics()`. Averages cover the last 100 samples.
- `averagePayloadSize` is the uncompressed JSON size; `compressionRatio` is compressed size over original size, averaged over compressed batches only (1.0 if none).
- `memoryUsage` is the app's resident memory in bytes; `diskUsage` is the size of the saved queue.

```swift interface
public struct CircuitBreakerMetrics : Sendable {
  public let currentState: CircuitBreakerState
  public let failureCount: Int
  public let totalFailures: Int
  public let totalSuccesses: Int
  public let lastFailureTime: Date?
  public let lastStateChange: Date
  public var successRate: Double // get
  public var timeInCurrentState: TimeInterval // get
}

public enum CircuitBreakerState : Sendable {
  case closed
  case open
  case halfOpen
}
```

## Privacy and settings

```swift interface
public enum PIIFilter {
  public static func sanitize(_ text: String) -> String
  public static func sanitizeMetadata(_ metadata: [String : String]) -> [String : String]
  public static func containsPII(_ text: String) -> Bool
  public static func redactFields(_ metadata: [String : String], fields: Set<String>) -> [String : String]
  public static let commonPIIFields: Set<String>
}

public actor AnalyticsSettings {
  public static let shared: AnalyticsSettings
  public var isEnabled: Bool // get
  public func setEnabled(_ enabled: Bool)
}
```

See [Privacy](PRIVACY.md#personal-data-in-event-metadata) for what `PIIFilter` matches.

## Debugging and version

```swift interface
public enum LuxAnalyticsDebug {
  public static func status() async
  public static func validateSetup() async
  public static func printSampleCode()
}

public enum LuxAnalyticsVersion {
  public static let current: String
  public static let name: String
  public static var fullVersion: String // get
}
```

`LuxAnalyticsDebug` writes to the unified log at notice level. `LuxAnalyticsVersion.fullVersion` is `"LuxAnalytics/1.1.0"`, which the SDK also sends as its `User-Agent`.

## Defaults

```swift interface
public enum LuxAnalyticsDefaults {
  public static let autoFlushInterval: Double
  public static let maxQueueSize: Int
  public static let batchSize: Int
  public static let debugLogging: Bool
  public static let requestTimeout: Double
  public static let maxQueueSizeHard: Int
  public static let eventTTL: Double
  public static let maxRetryAttempts: Int
  public static let overflowStrategy: QueueOverflowStrategy
  public static let compressionEnabled: Bool
  public static let compressionThreshold: Int
}
```

The default value of each `LuxAnalyticsConfiguration` option; the values are listed in [Configuration](CONFIGURATION.md#options).

Everything else in the SDK (the queue, logger, circuit breaker, background task manager and so on) is internal.
