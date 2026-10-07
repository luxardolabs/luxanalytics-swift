# Configuration Guide

Complete guide to configuring LuxAnalytics for your application.

## Overview

LuxAnalytics supports multiple configuration methods:
1. **Quick Start** - Minimal setup for most apps
2. **Info.plist** - Configuration via app bundle
3. **Programmatic** - Full control with Swift code

## DSN Format

All configuration methods require a **Data Source Name (DSN)**:

```
https://PUBLIC_ID@DOMAIN/api/v1/events/PROJECT_ID
```

### DSN Components

| Component | Description | Example |
|-----------|-------------|---------|
| `PUBLIC_ID` | Your public API key | `a1b2c3d4e5f6` |
| `DOMAIN` | Analytics server domain | `analytics.example.com` |
| `PROJECT_ID` | Your project identifier | `1234567890123456` |

**Example DSN:**
```
https://a1b2c3d4e5f6@analytics.example.com/api/v1/events/1234567890123456
```

## Configuration Methods

### 1. Quick Start (Recommended)

Perfect for most applications:

```swift
import LuxAnalytics

@main
struct MyApp: App {
    init() {
        Task {
            try await LuxAnalytics.quickStart(
                dsn: "https://your-public-id@analytics.example.com/api/v1/events/your-project-id",
                debugLogging: true  // Optional: enable for development
            )
        }
    }
    
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### 2. Info.plist Configuration

Add configuration to your app's `Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required -->
    <key>LuxAnalyticsDSN</key>
    <string>https://your-public-id@analytics.example.com/api/v1/events/your-project-id</string>
    
    <!-- Optional Settings -->
    <key>LuxAnalyticsDebugLogging</key>
    <false/>
    
    <key>LuxAnalyticsAutoFlushInterval</key>
    <real>30.0</real>
    
    <key>LuxAnalyticsMaxQueueSize</key>
    <integer>500</integer>
    
    <key>LuxAnalyticsBatchSize</key>
    <integer>50</integer>
    
    <key>LuxAnalyticsRequestTimeout</key>
    <real>60.0</real>
    
    <key>LuxAnalyticsCompressionEnabled</key>
    <true/>
</dict>
</plist>
```

Then initialize from plist:

```swift
@main
struct MyApp: App {
    init() {
        Task {
            try await LuxAnalytics.initializeFromPlist()
        }
    }
    
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### 3. Programmatic Configuration

For complete control over all settings:

```swift
let config = try LuxAnalyticsConfiguration(
    // Required
    dsn: "https://your-public-id@analytics.example.com/api/v1/events/your-project-id",
    
    // Performance Settings
    autoFlushInterval: 30.0,        // Auto-flush every 30 seconds
    maxQueueSize: 500,              // Trigger flush at 500 events
    batchSize: 50,                  // Send 50 events per request
    
    // Network Settings
    requestTimeout: 60.0,           // 60 second network timeout
    maxRetryAttempts: 5,            // Retry failed requests 5 times
    
    // Queue Management
    maxQueueSizeHard: 10000,        // Hard limit: drop events beyond 10K
    eventTTL: 604800,               // Events expire after 7 days
    overflowStrategy: .dropOldest,  // Drop oldest events when full
    
    // Compression
    compressionEnabled: true,       // Enable zlib compression
    compressionThreshold: 1024,     // Compress payloads > 1KB
    
    // Development
    debugLogging: false,            // Enable console logging
    
    // Security (Advanced)
    certificatePinning: nil         // Optional: SSL certificate pinning
)

try await LuxAnalytics.initialize(with: config)
```

## Configuration Options Reference

### Performance Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `autoFlushInterval` | `TimeInterval` | `30.0` | Seconds between automatic flushes |
| `maxQueueSize` | `Int` | `500` | Events to queue before forcing flush |
| `batchSize` | `Int` | `50` | Events per network request |

### Network Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `requestTimeout` | `TimeInterval` | `60.0` | Network request timeout in seconds |
| `maxRetryAttempts` | `Int` | `5` | Max retry attempts for failed requests |

### Queue Management

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `maxQueueSizeHard` | `Int` | `10000` | Hard limit before dropping events |
| `eventTTL` | `TimeInterval` | `604800` | Event time-to-live (7 days) |
| `overflowStrategy` | `OverflowStrategy` | `.dropOldest` | What to do when queue is full |

#### Overflow Strategies

| Strategy | Description |
|----------|-------------|
| `.dropOldest` | Remove oldest events to make room |
| `.dropNewest` | Reject new events when queue is full |
| `.dropAll` | Clear entire queue when full |

### Compression Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `compressionEnabled` | `Bool` | `true` | Enable zlib compression |
| `compressionThreshold` | `Int` | `1024` | Minimum bytes to trigger compression |

### Development Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `debugLogging` | `Bool` | `false` | Enable detailed console logging |

## Environment-Specific Configuration

### Development vs Production

```swift
#if DEBUG
let debugEnabled = true
let flushInterval = 10.0  // Faster flushing for testing
#else
let debugEnabled = false
let flushInterval = 30.0  // Normal production interval
#endif

try await LuxAnalytics.quickStart(
    dsn: "your-dsn",
    debugLogging: debugEnabled
)
```

### Configuration Validation

```swift
do {
    try await LuxAnalytics.quickStart(dsn: "your-dsn")
    print("✅ LuxAnalytics initialized successfully")
} catch {
    switch error {
    case LuxAnalyticsError.invalidConfiguration(let message):
        print("❌ Configuration error: \(message)")
    case LuxAnalyticsError.alreadyInitialized:
        print("⚠️ LuxAnalytics already initialized")
    default:
        print("❌ Initialization failed: \(error)")
    }
}
```

## Security Considerations

### DSN Security

- **Never commit DSNs to source control**
- Store production DSNs in:
  - Xcode build configuration files
  - Environment variables
  - Secure configuration management systems

### Example: Environment-based DSN

```swift
extension Bundle {
    var luxAnalyticsDSN: String? {
        return object(forInfoDictionaryKey: "LuxAnalyticsDSN") as? String
    }
}

// In your app initialization:
guard let dsn = Bundle.main.luxAnalyticsDSN else {
    fatalError("LuxAnalyticsDSN not configured in Info.plist")
}

try await LuxAnalytics.quickStart(dsn: dsn)
```

## Next Steps

- [Event Tracking Guide](Event-Tracking.md) - Learn how to track events
- [Performance Optimization](Performance.md) - Tune for your app's needs
- [API Reference](API-Reference.md) - Complete API documentation