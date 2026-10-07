# Troubleshooting Guide

Common issues and solutions when using LuxAnalytics.

## Installation Issues

### "Cannot find 'LuxAnalytics' in scope"

**Problem:** Xcode can't find the LuxAnalytics module.

**Solutions:**
1. **Check import statement:**
   ```swift
   import LuxAnalytics  // Make sure this is at the top of your file
   ```

2. **Verify Package.swift dependency:**
   ```swift
   dependencies: [
       .package(url: "https://github.com/luxardolabs/LuxAnalytics", from: "1.0.0")
   ],
   targets: [
       .target(
           name: "YourTarget",
           dependencies: ["LuxAnalytics"]  // Make sure this is included
       )
   ]
   ```

3. **Clean and rebuild:**
   - Product → Clean Build Folder
   - File → Packages → Reset Package Caches

### "Package dependency is not supported on this platform"

**Problem:** Platform version is too old.

**Solution:** LuxAnalytics requires iOS 18.0+. Update your deployment target:

```swift
// Package.swift
platforms: [
    .iOS(.v18)  // Must be iOS 18 or later
]
```

## Initialization Issues

### "LuxAnalyticsError.notInitialized"

**Problem:** Trying to use SDK before initialization.

**Solution:** Always initialize before using:

```swift
@main
struct MyApp: App {
    init() {
        Task {
            // Initialize first
            try await LuxAnalytics.quickStart(dsn: "your-dsn")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Now safe to use
                    let analytics = await LuxAnalytics.shared
                    try? await analytics.track("app_launched")
                }
        }
    }
}
```

### "LuxAnalyticsError.alreadyInitialized"

**Problem:** Trying to initialize SDK multiple times.

**Solution:** Check initialization status:

```swift
if !LuxAnalytics.isInitialized {
    try await LuxAnalytics.quickStart(dsn: "your-dsn")
}
```

### "LuxAnalyticsError.invalidConfiguration"

**Problem:** Invalid DSN format.

**Common Issues:**
- Missing `@` symbol in DSN
- Missing project ID at the end
- Invalid URL format

**Solution:** Verify DSN format:
```
https://PUBLIC_ID@DOMAIN/api/v1/events/PROJECT_ID
```

**Example:**
```swift
// ❌ Invalid
"analytics.example.com/events/123"

// ✅ Valid  
"https://abc123@analytics.example.com/api/v1/events/project456"
```

## Async/Await Issues

### "'async' property access in a function that does not support concurrency"

**Problem:** Calling async APIs from non-async context.

**Solutions:**

1. **Use Task for one-off calls:**
   ```swift
   Button("Track Event") {
       Task {
           let analytics = await LuxAnalytics.shared
           try await analytics.track("button_tapped")
       }
   }
   ```

2. **Make your function async:**
   ```swift
   // ❌ Non-async function
   func handleAction() {
       let analytics = await LuxAnalytics.shared  // Error!
   }
   
   // ✅ Async function
   func handleAction() async {
       let analytics = await LuxAnalytics.shared  // Works!
       try await analytics.track("action_handled")
   }
   ```

3. **Use .task modifier in SwiftUI:**
   ```swift
   .task {
       let analytics = await LuxAnalytics.shared
       try await analytics.track("view_appeared")
   }
   ```

### "Expression is 'async' but is not marked with 'await'"

**Problem:** Forgetting `await` keyword.

**Solution:** All LuxAnalytics APIs require `await`:

```swift
// ❌ Missing await
let analytics = LuxAnalytics.shared
analytics.track("event")

// ✅ Correct
let analytics = await LuxAnalytics.shared
try await analytics.track("event")
```

## Event Tracking Issues

### Events not appearing in analytics dashboard

**Debugging Steps:**

1. **Check initialization:**
   ```swift
   print("SDK initialized: \(LuxAnalytics.isInitialized)")
   ```

2. **Enable debug logging:**
   ```swift
   try await LuxAnalytics.quickStart(
       dsn: "your-dsn",
       debugLogging: true  // Enable debug logs
   )
   ```

3. **Check queue stats:**
   ```swift
   let stats = await LuxAnalytics.getQueueStats()
   print("Events in queue: \(stats.totalEvents)")
   print("Events sent: \(stats.retriableEvents)")
   ```

4. **Monitor event flow:**
   ```swift
   Task {
       for await notification in LuxAnalyticsEvents.eventStream {
           print("Analytics event: \(notification)")
       }
   }
   ```

5. **Manual flush:**
   ```swift
   await LuxAnalytics.flush()
   ```

### "LuxAnalyticsError.queueFull"

**Problem:** Event queue has reached capacity.

**Solutions:**

1. **Increase queue size:**
   ```swift
   let config = try LuxAnalyticsConfiguration(
       dsn: "your-dsn",
       maxQueueSize: 1000  // Increase from default 500
   )
   ```

2. **More frequent flushing:**
   ```swift
   let config = try LuxAnalyticsConfiguration(
       dsn: "your-dsn",
       autoFlushInterval: 15.0  // Flush every 15 seconds
   )
   ```

3. **Manual queue management:**
   ```swift
   let stats = await LuxAnalytics.getQueueStats()
   if stats.totalEvents > 400 {
       await LuxAnalytics.flush()  // Proactive flush
   }
   ```

## Network Issues

### Events queued but not sending

**Debugging Steps:**

1. **Check network connectivity:**
   ```swift
   let isConnected = await LuxAnalytics.isNetworkAvailable()
   print("Network available: \(isConnected)")
   ```

2. **Check circuit breaker:**
   ```swift
   let status = await LuxAnalytics.getCircuitBreakerStatus()
   print("Circuit breaker: \(status)")
   ```

3. **Verify DSN endpoint:**
   - Test DSN URL in browser/Postman
   - Check for SSL certificate issues
   - Verify authentication

4. **Check SDK health:**
   ```swift
   let isHealthy = await LuxAnalytics.healthCheck()
   print("SDK healthy: \(isHealthy)")
   ```

### "SSL certificate verification failed"

**Problem:** Certificate validation issues.

**Solutions:**

1. **Check server SSL configuration**
2. **Implement certificate pinning** (for self-signed certificates):
   ```swift
   let config = try LuxAnalyticsConfiguration(
       dsn: "your-dsn",
       certificatePinning: CertificatePinningConfiguration(
           certificates: [yourCertificate],
           enforceOnFailure: true,
           validateCertificateChain: true
       )
   )
   ```

## Performance Issues

### App launch delay

**Problem:** SDK initialization blocking app launch.

**Solution:** Initialize asynchronously:

```swift
@main
struct MyApp: App {
    init() {
        // Don't wait for initialization
        Task.detached {
            try? await LuxAnalytics.quickStart(dsn: "your-dsn")
        }
    }
    
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### High memory usage

**Solutions:**

1. **Reduce queue size:**
   ```swift
   let config = try LuxAnalyticsConfiguration(
       dsn: "your-dsn",
       maxQueueSize: 100  // Smaller queue
   )
   ```

2. **More frequent flushing:**
   ```swift
   let config = try LuxAnalyticsConfiguration(
       dsn: "your-dsn",
       autoFlushInterval: 10.0  // Flush more often
   )
   ```

3. **Enable compression:**
   ```swift
   let config = try LuxAnalyticsConfiguration(
       dsn: "your-dsn",
       compressionEnabled: true,
       compressionThreshold: 512  // Compress smaller payloads
   )
   ```

## SwiftUI Integration Issues

### State updates on background thread

**Problem:** SwiftUI warnings about main thread updates.

**Solution:** Use proper async patterns:

```swift
struct ContentView: View {
    @State private var isTracking = false
    
    var body: some View {
        Button("Track Event") {
            isTracking = true
            Task {
                defer { isTracking = false }
                let analytics = await LuxAnalytics.shared
                try await analytics.track("button_tapped")
            }
        }
        .disabled(isTracking)
    }
}
```

## Debug Mode

### Enable comprehensive debugging

```swift
try await LuxAnalytics.quickStart(
    dsn: "your-dsn",
    debugLogging: true
)

// Enable diagnostic mode
await LuxAnalytics.enableDiagnosticMode()

// Validate setup
await LuxAnalyticsDebug.validateSetup()

// Print current status
await LuxAnalyticsDebug.status()
```

## Getting Help

If you're still having issues:

1. **Check logs** - Enable debug logging for detailed information
2. **Review configuration** - Verify all settings are correct
3. **Test with minimal example** - Isolate the issue
4. **Create reproducible example** - Minimal code that demonstrates the problem

### Support Channels

- 🐛 [GitHub Issues](https://github.com/luxardolabs/LuxAnalytics/issues) - Bug reports
- 💬 [GitHub Discussions](https://github.com/luxardolabs/LuxAnalytics/discussions) - Questions
- 📧 support@luxardolabs.com - Direct support

### Information to Include

When reporting issues, please include:

- iOS version and device model
- Xcode version
- LuxAnalytics SDK version
- Minimal code example
- Debug logs (with sensitive data removed)
- Expected vs actual behavior

## Next Steps

- [API Reference](API-Reference.md) - Complete API documentation
- [Configuration Guide](Configuration.md) - Detailed configuration options
- [Best Practices](Best-Practices.md) - Recommended usage patterns