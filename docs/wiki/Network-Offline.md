# Network & Offline Guide

Comprehensive guide to LuxAnalytics' network handling, offline support, and connectivity optimization.

## Network Architecture

LuxAnalytics is designed as an **offline-first** analytics solution that gracefully handles all network conditions:

- **Online**: Efficient batching and real-time delivery
- **Offline**: Persistent storage with automatic retry
- **Intermittent**: Smart retry logic with circuit breaker protection
- **Slow networks**: Compression and adaptive batching

## Network Components

### Network Monitor

```swift
// Check current network status
let isConnected = await LuxAnalytics.isNetworkAvailable()
print("Network available: \(isConnected)")

// Monitor network changes
class NetworkStatusMonitor {
    static func startMonitoring() {
        Task {
            var previousStatus = await LuxAnalytics.isNetworkAvailable()
            
            while true {
                let currentStatus = await LuxAnalytics.isNetworkAvailable()
                
                if currentStatus != previousStatus {
                    await handleNetworkStatusChange(
                        from: previousStatus,
                        to: currentStatus
                    )
                    previousStatus = currentStatus
                }
                
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
    
    private static func handleNetworkStatusChange(from: Bool, to: Bool) async {
        if !from && to {
            print("📡 Network restored - triggering flush")
            await LuxAnalytics.flush()
        } else if from && !to {
            print("📱 Network lost - events will queue offline")
        }
    }
}
```

### Circuit Breaker Protection

```swift
// Monitor circuit breaker status
let circuitStatus = await LuxAnalytics.getCircuitBreakerStatus()
print("Circuit breaker state: \(circuitStatus.state)")
print("Failure count: \(circuitStatus.failureCount)")
print("Next retry at: \(circuitStatus.nextRetryTime)")

// Circuit breaker states:
// - .closed: Normal operation
// - .open: Too many failures, requests blocked
// - .halfOpen: Testing if service recovered
```

## Offline Support

### Automatic Offline Handling

```swift
// Events are automatically queued when offline
func trackEventOffline() async {
    let analytics = await LuxAnalytics.shared
    
    // This works whether online or offline
    try await analytics.track("user_action_offline", metadata: [
        "action_type": "button_tap",
        "screen": "home"
    ])
    
    // Event is queued locally if offline
    // Automatically sent when connectivity returns
}
```

### Offline Queue Management

```swift
class OfflineQueueManager {
    static func configureOfflineSettings() -> LuxAnalyticsConfiguration {
        return try! LuxAnalyticsConfiguration(
            dsn: "your-dsn",
            
            // Offline-optimized settings
            maxQueueSize: 5000,           // Large queue for offline storage
            maxQueueSizeHard: 100000,     // Very large hard limit
            batchSize: 200,               // Large batches when online
            eventTTL: 86400 * 14,         // 2 weeks retention
            overflowStrategy: .dropOldest, // Drop old events when full
            
            // Network settings
            requestTimeout: 60.0,         // Longer timeout for poor networks
            maxRetryAttempts: 10,         // More retries for offline scenarios
            compressionEnabled: true      // Essential for large offline queues
        )
    }
    
    static func monitorOfflineQueue() async {
        let stats = await LuxAnalytics.getQueueStats()
        let isOnline = await LuxAnalytics.isNetworkAvailable()
        
        if !isOnline {
            print("📱 Offline mode:")
            print("  Events queued: \(stats.totalEvents)")
            print("  Queue size: \(ByteCountFormatter.string(fromByteCount: Int64(stats.totalSizeBytes), countStyle: .file))")
            print("  Oldest event: \(formatAge(stats.oldestEventAge))")
            
            // Warn if queue getting large
            if stats.totalEvents > 10000 {
                print("⚠️ Large offline queue - consider user notification")
            }
        }
    }
    
    private static func formatAge(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        return "\(hours)h ago"
    }
}
```

### Offline User Experience

```swift
// Provide user feedback about offline state
class OfflineUserInterface: ObservableObject {
    @Published var isOnline = true
    @Published var queuedEventsCount = 0
    @Published var showOfflineIndicator = false
    
    func startMonitoring() {
        Task {
            while true {
                let online = await LuxAnalytics.isNetworkAvailable()
                let stats = await LuxAnalytics.getQueueStats()
                
                await MainActor.run {
                    self.isOnline = online
                    self.queuedEventsCount = stats.totalEvents
                    self.showOfflineIndicator = !online && stats.totalEvents > 0
                }
                
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
}

// SwiftUI view showing offline status
struct OfflineIndicatorView: View {
    @StateObject private var offlineMonitor = OfflineUserInterface()
    
    var body: some View {
        VStack {
            if offlineMonitor.showOfflineIndicator {
                HStack {
                    Image(systemName: "wifi.slash")
                    Text("Offline - \(offlineMonitor.queuedEventsCount) events queued")
                    Spacer()
                }
                .foregroundColor(.orange)
                .padding(.horizontal)
                .background(Color.orange.opacity(0.1))
            }
            
            // Your main content
            ContentView()
        }
        .onAppear {
            offlineMonitor.startMonitoring()
        }
    }
}
```

## Network Optimization

### Adaptive Batching

```swift
class AdaptiveBatchingManager {
    static func optimizeBatchingForNetwork() async {
        let isOnline = await LuxAnalytics.isNetworkAvailable()
        let stats = await LuxAnalytics.getQueueStats()
        let networkQuality = await assessNetworkQuality()
        
        if isOnline {
            await handleOnlineBatching(stats: stats, quality: networkQuality)
        } else {
            await handleOfflineBatching(stats: stats)
        }
    }
    
    private static func handleOnlineBatching(stats: QueueStats, quality: NetworkQuality) async {
        switch quality {
        case .excellent:
            // Fast network - large batches
            if stats.totalEvents > 100 {
                await LuxAnalytics.flush() // Send large batch
            }
            
        case .good:
            // Good network - moderate batches
            if stats.totalEvents > 50 {
                await LuxAnalytics.flush()
            }
            
        case .poor:
            // Slow network - small batches
            if stats.totalEvents > 10 {
                await LuxAnalytics.flush()
            }
            
        case .veryPoor:
            // Very slow - minimal batches
            if stats.totalEvents > 5 {
                await LuxAnalytics.flush()
            }
        }
    }
    
    private static func handleOfflineBatching(stats: QueueStats) async {
        // When offline, just monitor queue size
        if stats.totalEvents > 5000 {
            print("📱 Large offline queue: \(stats.totalEvents) events")
        }
    }
    
    private static func assessNetworkQuality() async -> NetworkQuality {
        // In a real implementation, you might measure:
        // - Network latency
        // - Bandwidth
        // - Connection type (WiFi vs cellular)
        
        let isConnected = await LuxAnalytics.isNetworkAvailable()
        return isConnected ? .good : .offline
    }
}

enum NetworkQuality {
    case excellent  // WiFi, low latency
    case good      // WiFi or strong cellular
    case poor      // Weak cellular
    case veryPoor  // Very weak connection
    case offline   // No connection
}
```

### Compression Optimization

```swift
class NetworkCompressionManager {
    static func optimizeCompressionForNetwork() async -> (enabled: Bool, threshold: Int) {
        let networkQuality = await assessNetworkQuality()
        let stats = await LuxAnalytics.getQueueStats()
        
        switch networkQuality {
        case .excellent:
            // Fast network - compression may not be needed
            return (enabled: stats.averageEventSize > 2048, threshold: 2048)
            
        case .good:
            // Good network - standard compression
            return (enabled: true, threshold: 1024)
            
        case .poor, .veryPoor:
            // Slow network - aggressive compression
            return (enabled: true, threshold: 256)
            
        case .offline:
            // Offline - prepare for when online with compression
            return (enabled: true, threshold: 512)
        }
    }
    
    static func monitorCompressionEffectiveness() async {
        let metrics = await LuxAnalytics.getPerformanceMetrics()
        
        print("📦 Compression ratio: \(String(format: "%.2f", metrics.compressionEfficiency))")
        
        if metrics.compressionEfficiency > 0.8 {
            print("✅ Excellent compression - saving significant bandwidth")
        } else if metrics.compressionEfficiency < 0.3 {
            print("⚠️ Poor compression - consider disabling for small events")
        }
        
        // Estimate bandwidth savings
        let originalSize = Double(metrics.bytesTransmitted) / metrics.compressionEfficiency
        let savings = originalSize - Double(metrics.bytesTransmitted)
        print("💾 Bandwidth saved: \(ByteCountFormatter.string(fromByteCount: Int64(savings), countStyle: .file))")
    }
}
```

## Retry Logic and Resilience

### Exponential Backoff

```swift
// LuxAnalytics implements automatic exponential backoff
// This is how it works internally:

class RetryLogicExample {
    static func demonstrateRetryBehavior() {
        print("🔄 Retry Logic:")
        print("  Attempt 1: Immediate")
        print("  Attempt 2: 2s + jitter")
        print("  Attempt 3: 4s + jitter")
        print("  Attempt 4: 8s + jitter")
        print("  Attempt 5: 16s + jitter")
        print("  Max delay: 300s (5 minutes)")
        print("  Jitter: ±25% to prevent thundering herd")
    }
    
    // Monitor retry behavior
    static func monitorRetryBehavior() {
        Task {
            for await event in LuxAnalyticsEvents.eventStream {
                switch event {
                case .eventsFailed(let events, let error):
                    print("🔄 Failed batch of \(events.count) events: \(error)")
                    print("   Will retry with exponential backoff")
                    
                case .eventsDropped(let count, let reason):
                    if reason.contains("max retries") {
                        print("💀 Dropped \(count) events after max retries")
                    }
                    
                default:
                    break
                }
            }
        }
    }
}
```

### Circuit Breaker Management

```swift
class CircuitBreakerManager {
    static func monitorCircuitBreaker() {
        Task {
            while true {
                let status = await LuxAnalytics.getCircuitBreakerStatus()
                
                switch status.state {
                case .closed:
                    // Normal operation
                    break
                    
                case .open:
                    print("🔌 Circuit breaker OPEN")
                    print("   Failure count: \(status.failureCount)")
                    print("   Next retry: \(formatTime(status.nextRetryTime))")
                    await handleCircuitBreakerOpen(status)
                    
                case .halfOpen:
                    print("🔌 Circuit breaker HALF-OPEN (testing recovery)")
                    await handleCircuitBreakerHalfOpen(status)
                }
                
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
    
    private static func handleCircuitBreakerOpen(_ status: CircuitBreakerStatus) async {
        // Circuit breaker is open - server is having issues
        // Events will be queued locally until recovery
        
        let stats = await LuxAnalytics.getQueueStats()
        print("📱 Events queuing locally: \(stats.totalEvents) in queue")
        
        // Optionally notify user if queue gets very large
        if stats.totalEvents > 1000 {
            await notifyUserOfNetworkIssues()
        }
    }
    
    private static func handleCircuitBreakerHalfOpen(_ status: CircuitBreakerStatus) async {
        // Circuit breaker is testing recovery
        // Next request will determine if circuit closes (recovery) or opens again
        print("🧪 Testing server recovery...")
    }
    
    private static func notifyUserOfNetworkIssues() async {
        // Show user-friendly notification about connectivity issues
        print("📱 User notification: 'Analytics data will sync when connection improves'")
    }
    
    private static func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
```

## Advanced Network Scenarios

### Cellular Data Optimization

```swift
class CellularDataManager {
    static func optimizeForCellularData() async {
        let networkType = await detectNetworkType()
        
        switch networkType {
        case .wifi:
            await configureForWiFi()
            
        case .cellular:
            await configureForCellular()
            
        case .unknown:
            await configureForUnknownNetwork()
        }
    }
    
    private static func configureForWiFi() async {
        print("📶 WiFi detected - normal operation")
        // Use standard settings
    }
    
    private static func configureForCellular() async {
        print("📱 Cellular detected - optimizing for data usage")
        
        // More aggressive compression
        // Larger batches to reduce request count
        // Longer intervals between flushes
        
        let stats = await LuxAnalytics.getQueueStats()
        if stats.totalEvents > 100 {
            print("📱 Large queue on cellular - flushing to save data")
            await LuxAnalytics.flush()
        }
    }
    
    private static func configureForUnknownNetwork() async {
        print("❓ Unknown network - conservative settings")
        // Use conservative settings that work on slow connections
    }
    
    private static func detectNetworkType() async -> NetworkType {
        // This would use Network framework to detect connection type
        // For now, simplified implementation
        let isConnected = await LuxAnalytics.isNetworkAvailable()
        return isConnected ? .wifi : .unknown
    }
}

enum NetworkType {
    case wifi
    case cellular
    case unknown
}
```

### Bandwidth Monitoring

```swift
class BandwidthMonitor {
    static func monitorBandwidthUsage() async {
        let metrics = await LuxAnalytics.getPerformanceMetrics()
        
        print("📊 Network Usage:")
        print("  Total bytes transmitted: \(ByteCountFormatter.string(fromByteCount: Int64(metrics.bytesTransmitted), countStyle: .file))")
        print("  Average request duration: \(String(format: "%.2f", metrics.averageRequestDuration))s")
        print("  Request success rate: \(String(format: "%.1f", metrics.requestSuccessRate * 100))%")
        
        // Calculate bandwidth efficiency
        let efficiency = calculateBandwidthEfficiency(metrics)
        print("  Bandwidth efficiency: \(String(format: "%.1f", efficiency)) events/KB")
        
        if efficiency < 1.0 {
            print("⚠️ Low bandwidth efficiency - consider optimization")
            await suggestOptimizations(metrics)
        }
    }
    
    private static func calculateBandwidthEfficiency(_ metrics: LuxAnalyticsMetrics) -> Double {
        guard metrics.bytesTransmitted > 0 else { return 0 }
        
        let stats = await LuxAnalytics.getQueueStats()
        let totalEventsSent = stats.totalEvents - stats.retriableEvents
        
        return Double(totalEventsSent) / (Double(metrics.bytesTransmitted) / 1024.0)
    }
    
    private static func suggestOptimizations(_ metrics: LuxAnalyticsMetrics) async {
        let stats = await LuxAnalytics.getQueueStats()
        
        if stats.averageEventSize > 2048 {
            print("💡 Suggestion: Enable compression for large events")
        }
        
        if metrics.compressionEfficiency < 0.5 {
            print("💡 Suggestion: Review event metadata size")
        }
        
        if metrics.averageRequestDuration > 10.0 {
            print("💡 Suggestion: Use larger batch sizes to reduce request frequency")
        }
    }
}
```

## Network Security

### TLS and Certificate Validation

```swift
// LuxAnalytics automatically uses TLS 1.2+ (iOS enforced)
// Optional certificate pinning for enhanced security

class NetworkSecurityManager {
    static func configureCertificatePinning() -> LuxAnalyticsConfiguration? {
        guard let certificateData = loadCertificateFromBundle() else {
            print("⚠️ Certificate not found in bundle")
            return nil
        }
        
        let certificate = SecCertificateCreateWithData(nil, certificateData)!
        
        let config = try? LuxAnalyticsConfiguration(
            dsn: "your-dsn",
            certificatePinning: CertificatePinningConfiguration(
                certificates: [certificate],
                enforceOnFailure: true,
                validateCertificateChain: true
            )
        )
        
        return config
    }
    
    private static func loadCertificateFromBundle() -> Data? {
        guard let path = Bundle.main.path(forResource: "analytics-server", ofType: "cer"),
              let certificateData = NSData(contentsOfFile: path) as Data? else {
            return nil
        }
        
        return certificateData
    }
    
    static func monitorCertificateValidation() {
        Task {
            for await event in LuxAnalyticsEvents.eventStream {
                switch event {
                case .eventsFailed(_, let error):
                    if error.localizedDescription.contains("certificate") {
                        print("🔒 Certificate validation failed: \(error)")
                        await handleCertificateValidationFailure()
                    }
                    
                default:
                    break
                }
            }
        }
    }
    
    private static func handleCertificateValidationFailure() async {
        print("🔒 Certificate validation failed - checking certificate status")
        
        // In production, you might:
        // 1. Alert monitoring systems
        // 2. Fall back to standard validation
        // 3. Notify security team
        // 4. Queue events for manual review
    }
}
```

## Network Testing and Debugging

### Network Condition Simulation

```swift
#if DEBUG
class NetworkTestingUtils {
    static func simulateNetworkConditions() async {
        print("🧪 Simulating various network conditions...")
        
        // Test 1: Normal operation
        await testNormalNetwork()
        
        // Test 2: Slow network
        await testSlowNetwork()
        
        // Test 3: Intermittent connectivity
        await testIntermittentConnectivity()
        
        // Test 4: Complete offline
        await testOfflineMode()
        
        // Test 5: Server errors
        await testServerErrors()
    }
    
    private static func testNormalNetwork() async {
        print("✅ Testing normal network conditions")
        
        let analytics = await LuxAnalytics.shared
        for i in 0..<10 {
            try? await analytics.track("test_normal_\(i)")
        }
        
        await LuxAnalytics.flush()
        print("✅ Normal network test completed")
    }
    
    private static func testSlowNetwork() async {
        print("🐌 Testing slow network conditions")
        
        // Generate events that would test slow network handling
        let analytics = await LuxAnalytics.shared
        
        // Create larger events to test compression
        for i in 0..<5 {
            try? await analytics.track("test_slow_\(i)", metadata: [
                "large_data": String(repeating: "x", count: 5000) // 5KB
            ])
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        await LuxAnalytics.flush()
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        print("🐌 Slow network flush took: \(String(format: "%.2f", duration))s")
    }
    
    private static func testIntermittentConnectivity() async {
        print("📶 Testing intermittent connectivity")
        
        // This would require network simulation tools in a real test
        // For now, just demonstrate the pattern
        
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("test_intermittent")
        
        // Events should queue and retry automatically
        print("📶 Intermittent connectivity test completed")
    }
    
    private static func testOfflineMode() async {
        print("📱 Testing offline mode")
        
        let analytics = await LuxAnalytics.shared
        
        // Create events while "offline"
        for i in 0..<20 {
            try? await analytics.track("test_offline_\(i)")
        }
        
        let stats = await LuxAnalytics.getQueueStats()
        print("📱 Offline queue size: \(stats.totalEvents) events")
        
        // Simulate coming back online
        await LuxAnalytics.flush()
        print("📱 Offline mode test completed")
    }
    
    private static func testServerErrors() async {
        print("🚨 Testing server error handling")
        
        // Monitor for errors during normal operation
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("test_server_error")
        
        // Check circuit breaker status
        let circuitStatus = await LuxAnalytics.getCircuitBreakerStatus()
        print("🚨 Circuit breaker state: \(circuitStatus.state)")
    }
}
#endif
```

### Network Performance Profiling

```swift
#if DEBUG
class NetworkProfiler {
    static func profileNetworkPerformance() async {
        print("📊 Profiling network performance...")
        
        let iterations = 10
        var flushTimes: [TimeInterval] = []
        
        for i in 0..<iterations {
            // Create test events
            let analytics = await LuxAnalytics.shared
            for j in 0..<20 {
                try? await analytics.track("profile_test_\(i)_\(j)")
            }
            
            // Measure flush time
            let startTime = CFAbsoluteTimeGetCurrent()
            await LuxAnalytics.flush()
            let flushTime = CFAbsoluteTimeGetCurrent() - startTime
            
            flushTimes.append(flushTime)
            print("📊 Flush \(i + 1): \(String(format: "%.2f", flushTime))s")
            
            // Wait between tests
            try? await Task.sleep(for: .seconds(2))
        }
        
        // Calculate statistics
        let averageTime = flushTimes.reduce(0, +) / Double(flushTimes.count)
        let minTime = flushTimes.min() ?? 0
        let maxTime = flushTimes.max() ?? 0
        
        print("📊 Network Performance Profile:")
        print("   Average flush time: \(String(format: "%.2f", averageTime))s")
        print("   Min flush time: \(String(format: "%.2f", minTime))s")
        print("   Max flush time: \(String(format: "%.2f", maxTime))s")
    }
}
#endif
```

## Production Network Monitoring

```swift
class ProductionNetworkMonitor {
    static func setupNetworkMonitoring() {
        Task {
            while true {
                await performNetworkCheck()
                try? await Task.sleep(for: .minutes(5))
            }
        }
    }
    
    private static func performNetworkCheck() async {
        let isOnline = await LuxAnalytics.isNetworkAvailable()
        let metrics = await LuxAnalytics.getPerformanceMetrics()
        let circuitStatus = await LuxAnalytics.getCircuitBreakerStatus()
        let stats = await LuxAnalytics.getQueueStats()
        
        // Log network status
        print("NETWORK_STATUS online=\(isOnline) success_rate=\(metrics.requestSuccessRate) circuit_state=\(circuitStatus.state) queue_size=\(stats.totalEvents)")
        
        // Check for issues
        if !isOnline {
            await handleOfflineStatus(stats)
        }
        
        if metrics.requestSuccessRate < 0.8 {
            await handlePoorConnectivity(metrics)
        }
        
        if circuitStatus.state == .open {
            await handleCircuitBreakerOpen(circuitStatus)
        }
    }
    
    private static func handleOfflineStatus(_ stats: QueueStats) async {
        print("📱 Device offline - monitoring queue growth")
        
        if stats.totalEvents > 5000 {
            print("⚠️ Large offline queue: \(stats.totalEvents) events")
        }
    }
    
    private static func handlePoorConnectivity(_ metrics: LuxAnalyticsMetrics) async {
        print("📶 Poor connectivity detected: \(String(format: "%.1f", metrics.requestSuccessRate * 100))% success rate")
        
        // Maybe adjust batching strategy
        if metrics.averageRequestDuration > 30.0 {
            print("🐌 Very slow requests - consider smaller batches")
        }
    }
    
    private static func handleCircuitBreakerOpen(_ status: CircuitBreakerStatus) async {
        print("🔌 Circuit breaker open - server issues detected")
        print("   Failure count: \(status.failureCount)")
        print("   Next retry: \(status.nextRetryTime)")
        
        // Alert monitoring systems
    }
}
```

## Best Practices

### ✅ Do

- Design for offline-first operation
- Monitor network conditions and adapt
- Use compression for slow networks
- Implement proper retry logic with exponential backoff
- Monitor circuit breaker status
- Provide user feedback for offline state
- Test with various network conditions
- Consider cellular data usage

### ❌ Don't

- Assume network is always available
- Ignore network quality when batching
- Disable retry logic for "faster" operation
- Overwhelm slow networks with large requests
- Forget to test offline scenarios
- Ignore circuit breaker state
- Block user interface on network operations
- Retry indefinitely without backoff

## Next Steps

- [🛡️ Error Handling](Error-Handling.md) - Handle network errors gracefully
- [📦 Queue Management](Queue-Management.md) - Optimize offline queue storage
- [⚡ Performance](Performance.md) - Network performance optimization
- [💡 Best Practices](Best-Practices.md) - Production network strategies