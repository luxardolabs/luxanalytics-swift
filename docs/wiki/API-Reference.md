# API Reference

Complete reference for all LuxAnalytics APIs.

## Overview

All LuxAnalytics APIs are **async** and built with Swift 6 strict concurrency. This ensures thread safety and prevents data races.

## Core Classes

### LuxAnalytics

Main SDK interface - all methods are async.

#### Initialization

```swift
// Quick start
static func quickStart(
    dsn: String, 
    debugLogging: Bool = false
) async throws

// From Info.plist
static func initializeFromPlist() async throws

// Full configuration
static func initialize(with config: LuxAnalyticsConfiguration) async throws
```

#### Instance Access

```swift
// Get shared instance (async)
static var shared: LuxAnalytics { get async }

// Check if initialized
static var isInitialized: Bool { get }
```

#### Event Tracking

```swift
// Track event with metadata
func track(
    _ name: String, 
    metadata: [String: Any] = [:]
) async throws

// Track event with full control
func track(
    _ name: String,
    userId: String? = nil,
    sessionId: String? = nil, 
    metadata: [String: Any] = [:]
) async throws
```

#### User Management

```swift
// Set current user ID
func setUser(_ userId: String?) async

// Set current session ID  
func setSession(_ sessionId: String?) async

// Get current user ID
func getCurrentUser() async -> String?

// Get current session ID
func getCurrentSession() async -> String?
```

#### Queue Management

```swift
// Manual flush
static func flush() async

// Clear queue (use with caution)
static func clearQueue() async

// Get queue statistics
static func getQueueStats() async -> QueueStats

// Health check
static func healthCheck() async -> Bool
```

#### Diagnostics

```swift
// Enable diagnostic mode
static func enableDiagnosticMode() async

// Get SDK metrics
static func getMetrics() async -> AnalyticsMetrics

// Check network availability
static func isNetworkAvailable() async -> Bool

// Get circuit breaker status
static func getCircuitBreakerStatus() async -> CircuitBreakerStatus
```

### LuxAnalyticsConfiguration

Configuration object for SDK initialization.

```swift
init(
    // Required
    dsn: String,
    
    // Performance
    autoFlushInterval: TimeInterval = 30.0,
    maxQueueSize: Int = 500,
    batchSize: Int = 50,
    
    // Network
    requestTimeout: TimeInterval = 60.0,
    maxRetryAttempts: Int = 5,
    
    // Queue Management
    maxQueueSizeHard: Int = 10000,
    eventTTL: TimeInterval = 604800,
    overflowStrategy: OverflowStrategy = .dropOldest,
    
    // Compression
    compressionEnabled: Bool = true,
    compressionThreshold: Int = 1024,
    
    // Development
    debugLogging: Bool = false,
    
    // Security
    certificatePinning: CertificatePinningConfiguration? = nil
) throws
```

#### Properties

```swift
// Parsed from DSN
let publicId: String
let projectId: String  
let apiURL: URL

// Configuration values
let autoFlushInterval: TimeInterval
let maxQueueSize: Int
let batchSize: Int
let requestTimeout: TimeInterval
let maxRetryAttempts: Int
let maxQueueSizeHard: Int
let eventTTL: TimeInterval
let overflowStrategy: OverflowStrategy
let compressionEnabled: Bool
let compressionThreshold: Int
let debugLogging: Bool
let certificatePinning: CertificatePinningConfiguration?
```

## Data Types

### AnalyticsEvent

Represents a single analytics event.

```swift
struct AnalyticsEvent: Codable, Sendable {
    let id: String              // Auto-generated UUID
    let name: String            // Event name
    let timestamp: String       // ISO8601 timestamp
    let userId: String?         // Associated user ID
    let sessionId: String?      // Associated session ID
    let metadata: [String: Any] // Event metadata
}
```

### QueueStats

Statistics about the event queue.

```swift
struct QueueStats: Sendable {
    let totalEvents: Int        // Total events in queue
    let retriableEvents: Int    // Events eligible for retry
    let expiredEvents: Int      // Expired events
    let totalSizeBytes: Int     // Queue size in bytes
    let oldestEventAge: TimeInterval // Age of oldest event
}
```

### AnalyticsMetrics

SDK performance metrics.

```swift
struct AnalyticsMetrics: Sendable {
    let eventsTracked: Int      // Total events tracked
    let eventsSent: Int         // Successfully sent events
    let eventsFailed: Int       // Failed send attempts
    let eventsDropped: Int      // Dropped events
    let networkRequests: Int    // Total network requests
    let averageRequestTime: TimeInterval // Average request duration
    let queueUtilization: Double // Queue usage percentage
}
```

### LuxAnalyticsError

SDK-specific errors.

```swift
enum LuxAnalyticsError: Error, Sendable {
    case notInitialized
    case alreadyInitialized
    case invalidConfiguration(String)
    case networkError(Error)
    case queueFull
    case eventExpired
    case invalidEvent(String)
    case serializationError(Error)
    case encryptionError(String)
}
```

### OverflowStrategy

Queue overflow handling strategies.

```swift
enum OverflowStrategy: String, Codable, Sendable {
    case dropOldest  // Remove oldest events
    case dropNewest  // Reject new events  
    case dropAll     // Clear entire queue
}
```

## Event Notifications

### LuxAnalyticsEvents

AsyncStream for monitoring SDK events.

```swift
enum LuxAnalyticsEventType {
    case eventQueued(AnalyticsEvent)
    case eventsSent([AnalyticsEvent])
    case eventsFailed([AnalyticsEvent], Error)
    case eventsDropped(Int, String)
    case eventsExpired([AnalyticsEvent])
}

// Subscribe to events
for await notification in LuxAnalyticsEvents.eventStream {
    switch notification {
    case .eventQueued(let event):
        print("Event queued: \(event.name)")
    case .eventsSent(let events):
        print("Sent \(events.count) events")
    case .eventsFailed(let events, let error):
        print("Failed to send \(events.count) events: \(error)")
    case .eventsDropped(let count, let reason):
        print("Dropped \(count) events: \(reason)")
    case .eventsExpired(let events):
        print("Expired \(events.count) events")
    }
}
```

## Debug Utilities

### LuxAnalyticsDebug

Development and debugging utilities.

```swift
struct LuxAnalyticsDebug {
    // Validate current setup
    static func validateSetup() async
    
    // Print current status
    static func status() async
    
    // Print queue contents (debug builds only)
    static func printQueue() async
    
    // Simulate network failure (debug builds only)
    static func simulateNetworkFailure() async
}
```

## Certificate Pinning

### CertificatePinningConfiguration

SSL certificate pinning configuration.

```swift
struct CertificatePinningConfiguration: Sendable {
    let certificates: [SecCertificate]  // Pinned certificates
    let enforceOnFailure: Bool          // Fail on pin mismatch
    let validateCertificateChain: Bool  // Validate full chain
}

// Example usage
let config = try LuxAnalyticsConfiguration(
    dsn: "your-dsn",
    certificatePinning: CertificatePinningConfiguration(
        certificates: [yourCertificate],
        enforceOnFailure: true,
        validateCertificateChain: true
    )
)
```

## Error Handling Examples

### Basic Error Handling

```swift
do {
    try await analytics.track("user_action")
} catch LuxAnalyticsError.notInitialized {
    print("SDK not initialized")
} catch LuxAnalyticsError.queueFull {
    print("Event queue is full")
} catch LuxAnalyticsError.networkError(let underlyingError) {
    print("Network error: \(underlyingError)")
} catch {
    print("Unexpected error: \(error)")
}
```

### Comprehensive Error Handling

```swift
func trackEvent(_ name: String, metadata: [String: Any] = [:]) async {
    do {
        try await LuxAnalytics.shared.track(name, metadata: metadata)
    } catch LuxAnalyticsError.notInitialized {
        // Initialize SDK if needed
        try? await LuxAnalytics.quickStart(dsn: "your-dsn")
        try? await LuxAnalytics.shared.track(name, metadata: metadata)
    } catch LuxAnalyticsError.queueFull {
        // Queue is full - try to flush and retry
        await LuxAnalytics.flush()
        try? await LuxAnalytics.shared.track(name, metadata: metadata)
    } catch LuxAnalyticsError.networkError(_) {
        // Network error - event will be retried automatically
        print("Event queued for retry due to network error")
    } catch {
        // Log unexpected errors for debugging
        print("Failed to track event '\(name)': \(error)")
    }
}
```

## Thread Safety

All LuxAnalytics APIs are designed with Swift 6 strict concurrency:

- ✅ **Safe to call from any actor/thread**
- ✅ **No data races possible**
- ✅ **Proper actor isolation**
- ✅ **All shared state protected**

```swift
// Safe from main actor
@MainActor
func viewDidLoad() {
    Task {
        let analytics = await LuxAnalytics.shared
        try await analytics.track("view_loaded")
    }
}

// Safe from background tasks
Task.detached {
    let analytics = await LuxAnalytics.shared
    try await analytics.track("background_task")
}

// Safe from actors
actor MyActor {
    func doWork() async {
        let analytics = await LuxAnalytics.shared
        try await analytics.track("work_done")
    }
}
```

## Next Steps

- [Configuration Guide](Configuration.md) - Detailed configuration options
- [Event Tracking Guide](Event-Tracking.md) - Event tracking best practices
- [Troubleshooting](Troubleshooting.md) - Common issues and solutions