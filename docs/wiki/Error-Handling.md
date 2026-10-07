# Error Handling Guide

Comprehensive guide to error handling, recovery strategies, and resilience patterns in LuxAnalytics.

## Error Philosophy

LuxAnalytics follows a **graceful degradation** approach to errors:
- **Never crash the host app** due to analytics failures
- **Fail silently** for non-critical errors
- **Retry intelligently** for recoverable errors
- **Preserve data** when possible
- **Provide diagnostics** for debugging

## Error Types

### LuxAnalyticsError Enum

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
    case analyticsDisabled
    case circuitBreakerOpen
    case rateLimitExceeded
    case diskSpaceError
    case memoryPressure
}

// Error categorization
extension LuxAnalyticsError {
    var isRecoverable: Bool {
        switch self {
        case .networkError, .queueFull, .circuitBreakerOpen, .rateLimitExceeded:
            return true
        case .notInitialized, .invalidConfiguration, .invalidEvent, .serializationError:
            return false
        case .alreadyInitialized, .eventExpired, .analyticsDisabled:
            return false
        case .encryptionError, .diskSpaceError, .memoryPressure:
            return true // May be temporary
        }
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .notInitialized, .invalidConfiguration:
            return .critical
        case .networkError, .queueFull, .encryptionError:
            return .warning
        case .eventExpired, .analyticsDisabled:
            return .info
        default:
            return .error
        }
    }
}

enum ErrorSeverity {
    case info
    case warning
    case error
    case critical
}
```

## Basic Error Handling

### Simple Error Handling

```swift
// Basic try-catch pattern
func trackEventWithBasicErrorHandling() async {
    do {
        let analytics = await LuxAnalytics.shared
        try await analytics.track("user_action")
    } catch {
        print("Analytics error: \(error)")
        // App continues normally - analytics never crashes the app
    }
}

// Ignore errors for non-critical tracking
func trackEventIgnoringErrors() async {
    let analytics = await LuxAnalytics.shared
    try? await analytics.track("optional_event")
    // Errors are silently ignored
}
```

### Comprehensive Error Handling

```swift
func trackEventWithComprehensiveHandling() async {
    do {
        let analytics = await LuxAnalytics.shared
        try await analytics.track("important_event", metadata: [
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
    } catch LuxAnalyticsError.notInitialized {
        print("Analytics not initialized - deferring event")
        await deferEventUntilInitialized()
        
    } catch LuxAnalyticsError.queueFull {
        print("Queue full - flushing and retrying")
        await handleQueueFullError()
        
    } catch LuxAnalyticsError.networkError(let underlyingError) {
        print("Network error - event will retry automatically: \(underlyingError)")
        
    } catch LuxAnalyticsError.invalidEvent(let message) {
        print("Invalid event data: \(message)")
        // Log for debugging but don't retry
        
    } catch LuxAnalyticsError.analyticsDisabled {
        print("Analytics disabled by user - respecting privacy choice")
        
    } catch {
        print("Unexpected analytics error: \(error)")
        await reportUnexpectedError(error)
    }
}
```

## Error Recovery Strategies

### Initialization Error Recovery

```swift
class InitializationErrorRecovery {
    private static var initializationAttempts = 0
    private static let maxInitializationAttempts = 3
    
    static func safelyInitializeAnalytics() async {
        do {
            try await LuxAnalytics.quickStart(dsn: "your-dsn")
            print("✅ Analytics initialized successfully")
            initializationAttempts = 0
            
        } catch LuxAnalyticsError.invalidConfiguration(let message) {
            print("❌ Configuration error: \(message)")
            // Don't retry - fix configuration
            
        } catch LuxAnalyticsError.alreadyInitialized {
            print("ℹ️ Analytics already initialized")
            
        } catch {
            await handleInitializationFailure(error)
        }
    }
    
    private static func handleInitializationFailure(_ error: Error) async {
        initializationAttempts += 1
        
        if initializationAttempts < maxInitializationAttempts {
            print("⚠️ Initialization failed (attempt \(initializationAttempts)): \(error)")
            print("🔄 Retrying in \(initializationAttempts * 2) seconds...")
            
            try? await Task.sleep(for: .seconds(initializationAttempts * 2))
            await safelyInitializeAnalytics()
        } else {
            print("❌ Analytics initialization failed after \(maxInitializationAttempts) attempts")
            await reportInitializationFailure(error)
        }
    }
    
    private static func reportInitializationFailure(_ error: Error) async {
        // Report to your error tracking system
        print("🚨 Analytics initialization permanently failed: \(error)")
    }
}
```

### Queue Error Recovery

```swift
class QueueErrorRecovery {
    static func handleQueueFullError() async {
        print("📦 Queue full - attempting recovery")
        
        // Strategy 1: Force flush
        await LuxAnalytics.flush()
        
        // Strategy 2: Check if flush was successful
        let stats = await LuxAnalytics.getQueueStats()
        if stats.totalEvents > 400 { // Still nearly full
            print("📦 Queue still full after flush - enabling aggressive mode")
            await enableAggressiveQueueManagement()
        }
    }
    
    private static func enableAggressiveQueueManagement() async {
        // More frequent flushes
        Task {
            while true {
                let stats = await LuxAnalytics.getQueueStats()
                if stats.totalEvents > 100 {
                    await LuxAnalytics.flush()
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
    
    static func handleQueueCorruption() async {
        print("🔧 Queue corruption detected - attempting recovery")
        
        // Last resort: clear queue
        print("⚠️ Clearing corrupted queue - data will be lost")
        await LuxAnalytics.clearQueue()
        
        // Reinitialize if needed
        if !LuxAnalytics.isInitialized {
            await InitializationErrorRecovery.safelyInitializeAnalytics()
        }
    }
}
```

### Network Error Recovery

```swift
class NetworkErrorRecovery {
    static func handleNetworkErrors() {
        Task {
            for await event in LuxAnalyticsEvents.eventStream {
                switch event {
                case .eventsFailed(let events, let error):
                    await handleFailedEvents(events, error: error)
                    
                case .eventsDropped(let count, let reason):
                    await handleDroppedEvents(count, reason: reason)
                    
                default:
                    break
                }
            }
        }
    }
    
    private static func handleFailedEvents(_ events: [AnalyticsEvent], error: Error) async {
        print("❌ Failed to send \(events.count) events: \(error)")
        
        if let luxError = error as? LuxAnalyticsError {
            switch luxError {
            case .networkError(let underlyingError):
                await handleNetworkFailure(underlyingError, eventCount: events.count)
                
            case .circuitBreakerOpen:
                await handleCircuitBreakerFailure(events.count)
                
            case .rateLimitExceeded:
                await handleRateLimitFailure(events.count)
                
            default:
                print("🔄 Events will retry automatically with exponential backoff")
            }
        }
    }
    
    private static func handleNetworkFailure(_ error: Error, eventCount: Int) async {
        print("📡 Network failure for \(eventCount) events: \(error)")
        
        // Check if device is offline
        let isOnline = await LuxAnalytics.isNetworkAvailable()
        if !isOnline {
            print("📱 Device offline - events will retry when connection restored")
        } else {
            print("📡 Network error despite connection - server may be down")
        }
    }
    
    private static func handleCircuitBreakerFailure(_ eventCount: Int) async {
        print("🔌 Circuit breaker open - \(eventCount) events blocked")
        
        let status = await LuxAnalytics.getCircuitBreakerStatus()
        print("🔌 Circuit breaker will retry at: \(status.nextRetryTime)")
        
        // Monitor for recovery
        await monitorCircuitBreakerRecovery()
    }
    
    private static func handleRateLimitFailure(_ eventCount: Int) async {
        print("🚦 Rate limit exceeded - \(eventCount) events delayed")
        
        // Events will automatically retry with exponential backoff
        // Consider reducing event frequency temporarily
        await temporarilyReduceEventFrequency()
    }
    
    private static func handleDroppedEvents(_ count: Int, reason: String) async {
        print("💀 Dropped \(count) events: \(reason)")
        
        if reason.contains("expired") {
            print("⏰ Events expired - consider reducing TTL or improving connectivity")
        } else if reason.contains("queue overflow") {
            print("📦 Queue overflow - consider increasing queue size or flush frequency")
        } else if reason.contains("max retries") {
            print("🔄 Max retries exceeded - server may be having persistent issues")
            await reportPersistentServerIssues()
        }
    }
    
    private static func monitorCircuitBreakerRecovery() async {
        Task {
            while true {
                let status = await LuxAnalytics.getCircuitBreakerStatus()
                if status.state == .closed {
                    print("✅ Circuit breaker recovered - normal operation resumed")
                    break
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
    
    private static func temporarilyReduceEventFrequency() async {
        print("🐌 Temporarily reducing event frequency due to rate limits")
        // Implementation would depend on your app's event tracking patterns
    }
    
    private static func reportPersistentServerIssues() async {
        print("🚨 Persistent server issues detected - alerting monitoring systems")
        // Alert your monitoring/ops team
    }
}
```

## Error Monitoring and Diagnostics

### Error Tracking

```swift
class ErrorTracker: ObservableObject {
    @Published var recentErrors: [TrackedError] = []
    @Published var errorCounts: [String: Int] = [:]
    @Published var criticalErrors: [TrackedError] = []
    
    private let maxRecentErrors = 50
    
    func startTracking() {
        Task {
            for await event in LuxAnalyticsEvents.eventStream {
                switch event {
                case .eventsFailed(let events, let error):
                    await trackError(error, context: "Event sending failed", eventCount: events.count)
                    
                case .eventsDropped(let count, let reason):
                    await trackError(
                        LuxAnalyticsError.queueFull, 
                        context: "Events dropped: \(reason)", 
                        eventCount: count
                    )
                    
                default:
                    break
                }
            }
        }
    }
    
    private func trackError(_ error: Error, context: String, eventCount: Int = 1) async {
        let trackedError = TrackedError(
            error: error,
            context: context,
            timestamp: Date(),
            eventCount: eventCount
        )
        
        await MainActor.run {
            // Add to recent errors
            recentErrors.insert(trackedError, at: 0)
            if recentErrors.count > maxRecentErrors {
                recentErrors.removeLast()
            }
            
            // Update error counts
            let errorType = String(describing: type(of: error))
            errorCounts[errorType, default: 0] += 1
            
            // Track critical errors
            if let luxError = error as? LuxAnalyticsError,
               luxError.severity == .critical {
                criticalErrors.insert(trackedError, at: 0)
            }
        }
        
        // Log error details
        print("🔍 Error tracked: \(context) - \(error)")
    }
    
    func getErrorSummary() -> ErrorSummary {
        let totalErrors = recentErrors.count
        let criticalCount = criticalErrors.count
        let mostCommonError = errorCounts.max(by: { $0.value < $1.value })?.key ?? "None"
        
        return ErrorSummary(
            totalErrors: totalErrors,
            criticalErrors: criticalCount,
            mostCommonError: mostCommonError,
            recentErrorRate: calculateRecentErrorRate()
        )
    }
    
    private func calculateRecentErrorRate() -> Double {
        let recentErrors = recentErrors.filter { 
            $0.timestamp.timeIntervalSinceNow > -3600 // Last hour
        }
        return Double(recentErrors.count) / 60.0 // Errors per minute
    }
}

struct TrackedError: Identifiable {
    let id = UUID()
    let error: Error
    let context: String
    let timestamp: Date
    let eventCount: Int
}

struct ErrorSummary {
    let totalErrors: Int
    let criticalErrors: Int
    let mostCommonError: String
    let recentErrorRate: Double
}
```

### Error Diagnostics

```swift
class ErrorDiagnostics {
    static func performComprehensiveDiagnostics() async -> DiagnosticReport {
        print("🔍 Performing comprehensive error diagnostics...")
        
        let report = DiagnosticReport()
        
        // Check initialization state
        report.initializationState = await checkInitializationState()
        
        // Check queue health
        report.queueHealth = await checkQueueHealth()
        
        // Check network connectivity
        report.networkHealth = await checkNetworkHealth()
        
        // Check circuit breaker state
        report.circuitBreakerState = await checkCircuitBreakerState()
        
        // Check system resources
        report.systemHealth = await checkSystemHealth()
        
        // Generate recommendations
        report.recommendations = generateRecommendations(report)
        
        return report
    }
    
    private static func checkInitializationState() async -> InitializationDiagnostic {
        let isInitialized = LuxAnalytics.isInitialized
        
        if isInitialized {
            return InitializationDiagnostic(
                status: .healthy,
                message: "Analytics properly initialized"
            )
        } else {
            return InitializationDiagnostic(
                status: .error,
                message: "Analytics not initialized - call LuxAnalytics.initialize() first"
            )
        }
    }
    
    private static func checkQueueHealth() async -> QueueDiagnostic {
        let stats = await LuxAnalytics.getQueueStats()
        
        if stats.totalEvents == 0 {
            return QueueDiagnostic(
                status: .healthy,
                message: "Queue empty",
                eventCount: 0,
                queueSize: 0
            )
        }
        
        let healthRatio = Double(stats.retriableEvents) / Double(stats.totalEvents)
        
        if healthRatio > 0.8 {
            return QueueDiagnostic(
                status: .healthy,
                message: "Queue healthy with \(stats.totalEvents) events",
                eventCount: stats.totalEvents,
                queueSize: stats.totalSizeBytes
            )
        } else {
            return QueueDiagnostic(
                status: .warning,
                message: "Queue health poor: \(Int(healthRatio * 100))% retriable",
                eventCount: stats.totalEvents,
                queueSize: stats.totalSizeBytes
            )
        }
    }
    
    private static func checkNetworkHealth() async -> NetworkDiagnostic {
        let isConnected = await LuxAnalytics.isNetworkAvailable()
        let metrics = await LuxAnalytics.getPerformanceMetrics()
        
        if !isConnected {
            return NetworkDiagnostic(
                status: .error,
                message: "No network connectivity",
                successRate: 0.0
            )
        }
        
        if metrics.requestSuccessRate > 0.9 {
            return NetworkDiagnostic(
                status: .healthy,
                message: "Network performing well",
                successRate: metrics.requestSuccessRate
            )
        } else {
            return NetworkDiagnostic(
                status: .warning,
                message: "Poor network performance: \(Int(metrics.requestSuccessRate * 100))% success rate",
                successRate: metrics.requestSuccessRate
            )
        }
    }
    
    private static func checkCircuitBreakerState() async -> CircuitBreakerDiagnostic {
        let status = await LuxAnalytics.getCircuitBreakerStatus()
        
        switch status.state {
        case .closed:
            return CircuitBreakerDiagnostic(
                status: .healthy,
                message: "Circuit breaker closed - normal operation",
                state: status.state,
                failureCount: status.failureCount
            )
            
        case .open:
            return CircuitBreakerDiagnostic(
                status: .error,
                message: "Circuit breaker open - server issues detected",
                state: status.state,
                failureCount: status.failureCount
            )
            
        case .halfOpen:
            return CircuitBreakerDiagnostic(
                status: .warning,
                message: "Circuit breaker testing recovery",
                state: status.state,
                failureCount: status.failureCount
            )
        }
    }
    
    private static func checkSystemHealth() async -> SystemDiagnostic {
        let metrics = await LuxAnalytics.getPerformanceMetrics()
        
        var issues: [String] = []
        
        if metrics.memoryFootprint > 20_000_000 { // 20MB
            issues.append("High memory usage: \(metrics.memoryFootprint / 1_000_000)MB")
        }
        
        if metrics.cpuUsagePercentage > 15.0 {
            issues.append("High CPU usage: \(String(format: "%.1f", metrics.cpuUsagePercentage))%")
        }
        
        if metrics.averageTrackingLatency > 0.01 { // 10ms
            issues.append("High tracking latency: \(String(format: "%.2f", metrics.averageTrackingLatency * 1000))ms")
        }
        
        if issues.isEmpty {
            return SystemDiagnostic(
                status: .healthy,
                message: "System resources optimal",
                issues: []
            )
        } else {
            return SystemDiagnostic(
                status: .warning,
                message: "System resource issues detected",
                issues: issues
            )
        }
    }
    
    private static func generateRecommendations(_ report: DiagnosticReport) -> [String] {
        var recommendations: [String] = []
        
        if report.initializationState.status == .error {
            recommendations.append("Initialize LuxAnalytics before using")
        }
        
        if report.queueHealth.status == .warning {
            recommendations.append("Consider flushing queue more frequently")
        }
        
        if report.networkHealth.status == .error {
            recommendations.append("Check network connectivity")
        } else if report.networkHealth.status == .warning {
            recommendations.append("Monitor network quality and consider compression")
        }
        
        if report.circuitBreakerState.status == .error {
            recommendations.append("Check server status - circuit breaker is open")
        }
        
        if !report.systemHealth.issues.isEmpty {
            recommendations.append("Monitor system resource usage")
        }
        
        return recommendations
    }
}

// Diagnostic data structures
struct DiagnosticReport {
    var initializationState: InitializationDiagnostic!
    var queueHealth: QueueDiagnostic!
    var networkHealth: NetworkDiagnostic!
    var circuitBreakerState: CircuitBreakerDiagnostic!
    var systemHealth: SystemDiagnostic!
    var recommendations: [String] = []
    
    func printReport() {
        print("🔍 LuxAnalytics Diagnostic Report")
        print("═══════════════════════════════════")
        print("Initialization: \(initializationState.status) - \(initializationState.message)")
        print("Queue: \(queueHealth.status) - \(queueHealth.message)")
        print("Network: \(networkHealth.status) - \(networkHealth.message)")
        print("Circuit Breaker: \(circuitBreakerState.status) - \(circuitBreakerState.message)")
        print("System: \(systemHealth.status) - \(systemHealth.message)")
        
        if !recommendations.isEmpty {
            print("\n💡 Recommendations:")
            for recommendation in recommendations {
                print("  • \(recommendation)")
            }
        }
    }
}

struct InitializationDiagnostic {
    let status: DiagnosticStatus
    let message: String
}

struct QueueDiagnostic {
    let status: DiagnosticStatus
    let message: String
    let eventCount: Int
    let queueSize: Int
}

struct NetworkDiagnostic {
    let status: DiagnosticStatus
    let message: String
    let successRate: Double
}

struct CircuitBreakerDiagnostic {
    let status: DiagnosticStatus
    let message: String
    let state: CircuitBreakerState
    let failureCount: Int
}

struct SystemDiagnostic {
    let status: DiagnosticStatus
    let message: String
    let issues: [String]
}

enum DiagnosticStatus {
    case healthy
    case warning
    case error
}
```

## Production Error Handling

### Error Reporting Integration

```swift
class ProductionErrorHandler {
    static func setupErrorReporting() {
        Task {
            for await event in LuxAnalyticsEvents.eventStream {
                switch event {
                case .eventsFailed(let events, let error):
                    await reportAnalyticsError(error, context: "Event sending failed", eventCount: events.count)
                    
                case .eventsDropped(let count, let reason):
                    await reportDataLoss(count: count, reason: reason)
                    
                default:
                    break
                }
            }
        }
    }
    
    private static func reportAnalyticsError(_ error: Error, context: String, eventCount: Int) async {
        // Report to your error tracking service (Crashlytics, Sentry, etc.)
        let errorInfo: [String: Any] = [
            "error_type": String(describing: type(of: error)),
            "error_message": error.localizedDescription,
            "context": context,
            "event_count": eventCount,
            "sdk_version": LuxAnalyticsVersion.current,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        // Example integration with error reporting service
        // Crashlytics.crashlytics().record(error: error, userInfo: errorInfo)
        print("ERROR_REPORT: \(errorInfo)")
    }
    
    private static func reportDataLoss(count: Int, reason: String) async {
        // Special handling for data loss events
        let lossInfo: [String: Any] = [
            "event_type": "data_loss",
            "events_lost": count,
            "reason": reason,
            "severity": "high",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        print("DATA_LOSS: \(lossInfo)")
        
        // Alert monitoring systems for data loss
        if count > 100 {
            await alertOpsTeam(lossInfo)
        }
    }
    
    private static func alertOpsTeam(_ info: [String: Any]) async {
        // Send alert to operations team
        print("🚨 ALERT: Significant data loss detected: \(info)")
    }
}
```

### Health Monitoring

```swift
class HealthMonitor {
    static func startHealthMonitoring() {
        Task {
            while true {
                await performHealthCheck()
                try? await Task.sleep(for: .minutes(5))
            }
        }
    }
    
    private static func performHealthCheck() async {
        let health = await assessOverallHealth()
        
        // Log health status
        print("HEALTH_CHECK status=\(health.status) score=\(health.score) issues=\(health.issues.count)")
        
        // Take action based on health
        switch health.status {
        case .healthy:
            // All good
            break
            
        case .degraded:
            print("⚠️ Analytics health degraded - monitoring closely")
            await handleDegradedHealth(health)
            
        case .unhealthy:
            print("🚨 Analytics unhealthy - taking corrective action")
            await handleUnhealthyState(health)
        }
    }
    
    private static func assessOverallHealth() async -> HealthStatus {
        var score = 100.0
        var issues: [String] = []
        
        // Check initialization
        if !LuxAnalytics.isInitialized {
            score -= 50
            issues.append("Not initialized")
        }
        
        // Check queue health
        let stats = await LuxAnalytics.getQueueStats()
        let queueHealthRatio = Double(stats.retriableEvents) / max(Double(stats.totalEvents), 1.0)
        if queueHealthRatio < 0.8 {
            score -= 20
            issues.append("Poor queue health")
        }
        
        // Check network health
        let metrics = await LuxAnalytics.getPerformanceMetrics()
        if metrics.requestSuccessRate < 0.9 {
            score -= 15
            issues.append("Poor network success rate")
        }
        
        // Check circuit breaker
        let circuitStatus = await LuxAnalytics.getCircuitBreakerStatus()
        if circuitStatus.state == .open {
            score -= 25
            issues.append("Circuit breaker open")
        }
        
        // Check resource usage
        if metrics.memoryFootprint > 20_000_000 {
            score -= 10
            issues.append("High memory usage")
        }
        
        let status: HealthLevel
        if score >= 80 {
            status = .healthy
        } else if score >= 60 {
            status = .degraded
        } else {
            status = .unhealthy
        }
        
        return HealthStatus(status: status, score: score, issues: issues)
    }
    
    private static func handleDegradedHealth(_ health: HealthStatus) async {
        // Take preventive measures
        if health.issues.contains("Poor queue health") {
            await LuxAnalytics.flush()
        }
        
        if health.issues.contains("High memory usage") {
            await optimizeMemoryUsage()
        }
    }
    
    private static func handleUnhealthyState(_ health: HealthStatus) async {
        print("🚨 Taking emergency measures for unhealthy analytics")
        
        // Emergency flush
        await LuxAnalytics.flush()
        
        // If still unhealthy, consider clearing queue
        let newHealth = await assessOverallHealth()
        if newHealth.score < 50 {
            print("🚨 Emergency queue clear")
            await LuxAnalytics.clearQueue()
        }
        
        // Alert operations team
        await alertOpsTeamOfUnhealthyState(health)
    }
    
    private static func optimizeMemoryUsage() async {
        await LuxAnalytics.flush()
        // Additional memory optimization could go here
    }
    
    private static func alertOpsTeamOfUnhealthyState(_ health: HealthStatus) async {
        print("🚨 ALERT: Analytics in unhealthy state - score: \(health.score), issues: \(health.issues)")
    }
}

struct HealthStatus {
    let status: HealthLevel
    let score: Double
    let issues: [String]
}

enum HealthLevel {
    case healthy
    case degraded
    case unhealthy
}
```

## Best Practices

### ✅ Do

- Handle all errors gracefully without crashing
- Use appropriate error recovery strategies
- Monitor error rates and patterns
- Log errors for debugging but don't expose sensitive data
- Implement circuit breaker patterns for failing services
- Use exponential backoff for retries
- Fail silently for non-critical analytics
- Provide diagnostics for debugging

### ❌ Don't

- Let analytics errors crash your app
- Retry indefinitely without backoff
- Ignore error patterns and trends
- Block the main thread handling errors
- Expose sensitive information in error messages
- Retry non-recoverable errors
- Overwhelm logs with verbose error details
- Ignore memory pressure during error handling

## Testing Error Scenarios

```swift
#if DEBUG
class ErrorScenarioTester {
    static func testErrorHandling() async {
        print("🧪 Testing error handling scenarios...")
        
        await testInitializationErrors()
        await testNetworkErrors()
        await testQueueErrors()
        await testInvalidEventErrors()
    }
    
    private static func testInitializationErrors() async {
        print("🧪 Testing initialization errors...")
        
        // Test invalid DSN
        do {
            let _ = try LuxAnalyticsConfiguration(dsn: "invalid-dsn")
            print("❌ Expected error for invalid DSN")
        } catch {
            print("✅ Correctly caught invalid DSN error: \(error)")
        }
        
        // Test double initialization
        // This would be tested in actual scenarios
    }
    
    private static func testNetworkErrors() async {
        print("🧪 Testing network error handling...")
        
        // Monitor network errors
        Task {
            for await event in LuxAnalyticsEvents.eventStream {
                switch event {
                case .eventsFailed(let events, let error):
                    print("✅ Network error handled: \(events.count) events failed with \(error)")
                    break // Exit after first error for test
                default:
                    continue
                }
            }
        }
        
        // Generate events that might fail
        let analytics = await LuxAnalytics.shared
        for i in 0..<5 {
            try? await analytics.track("test_network_error_\(i)")
        }
        
        await LuxAnalytics.flush()
    }
    
    private static func testQueueErrors() async {
        print("🧪 Testing queue error handling...")
        
        // Fill queue to test overflow
        let analytics = await LuxAnalytics.shared
        for i in 0..<1000 {
            try? await analytics.track("test_queue_overflow_\(i)")
        }
        
        let stats = await LuxAnalytics.getQueueStats()
        print("✅ Queue test completed - \(stats.totalEvents) events in queue")
    }
    
    private static func testInvalidEventErrors() async {
        print("🧪 Testing invalid event handling...")
        
        let analytics = await LuxAnalytics.shared
        
        // Test extremely large metadata
        let largeMetadata = [
            "large_data": String(repeating: "x", count: 100_000) // 100KB
        ]
        
        do {
            try await analytics.track("test_large_event", metadata: largeMetadata)
            print("✅ Large event handled")
        } catch {
            print("✅ Large event error handled: \(error)")
        }
    }
}
#endif
```

## Next Steps

- [🛡️ Best Practices](Best-Practices.md) - Production-ready error handling patterns
- [📦 Queue Management](Queue-Management.md) - Queue error recovery strategies
- [📡 Network & Offline](Network-Offline.md) - Network error handling
- [⚡ Performance](Performance.md) - Performance-aware error handling