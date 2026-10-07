import Foundation

/// SDK metrics for monitoring analytics health
public struct LuxAnalyticsMetrics: Codable, Sendable {
    public let timestamp: Date
    public let queueStats: QueueStats
    public let networkStats: NetworkStats
    public let performanceStats: PerformanceStats
    public let configurationInfo: ConfigurationInfo
    public let circuitBreakerStatus: CircuitBreakerStatus?
    
    public struct NetworkStats: Codable, Sendable {
        public let totalEventsSent: Int
        public let totalEventsFailed: Int
        public let totalBatchesSent: Int
        public let totalBatchesFailed: Int
        public let lastSuccessfulSend: Date?
        public let lastFailedSend: Date?
        public let averagePayloadSize: Int
        public let compressionRatio: Double
    }
    
    public struct PerformanceStats: Codable, Sendable {
        public let averageFlushDuration: TimeInterval
        public let averageCompressionTime: TimeInterval
        public let memoryUsage: Int
        public let diskUsage: Int
    }
    
    public struct ConfigurationInfo: Codable, Sendable {
        public let sdkVersion: String
        public let configuredEndpoint: String
        public let autoFlushInterval: TimeInterval
        public let maxQueueSize: Int
        public let compressionEnabled: Bool
        public let debugLoggingEnabled: Bool
    }
    
    public struct CircuitBreakerStatus: Codable, Sendable {
        public let state: String
        public let failureCount: Int
        public let successRate: Double
        public let timeInCurrentState: TimeInterval
    }
}

/// Diagnostics manager for monitoring SDK health
public actor LuxAnalyticsDiagnostics {
    public static let shared = LuxAnalyticsDiagnostics()
    
    // Metrics tracking
    private var totalEventsSent = 0
    private var totalEventsFailed = 0
    private var totalBatchesSent = 0
    private var totalBatchesFailed = 0
    private var lastSuccessfulSend: Date?
    private var lastFailedSend: Date?
    private var payloadSizes: [Int] = []
    private var compressionRatios: [Double] = []
    private var flushDurations: [TimeInterval] = []
    private var compressionTimes: [TimeInterval] = []
    
    private init() {}
    
    // MARK: - Metric Recording
    
    func recordEventsSent(count: Int) {
        totalEventsSent += count
        lastSuccessfulSend = Date()
    }
    
    func recordEventsFailed(count: Int, error: Error) {
        totalEventsFailed += count
        lastFailedSend = Date()
    }
    
    func recordBatchSent() {
        totalBatchesSent += 1
    }
    
    func recordBytesTransmitted(bytes: Int) {
        // Track bytes sent for bandwidth monitoring
        recordPayloadSize(bytes, compressedSize: bytes)
    }
    
    func recordBatchFailed() {
        totalBatchesFailed += 1
    }
    
    func recordPayloadSize(_ size: Int, compressedSize: Int?) {
        payloadSizes.append(size)
        // Keep only last 100 sizes
        if payloadSizes.count > 100 {
            payloadSizes.removeFirst()
        }
        
        if let compressed = compressedSize {
            let ratio = Double(compressed) / Double(size)
            compressionRatios.append(ratio)
            if compressionRatios.count > 100 {
                compressionRatios.removeFirst()
            }
        }
    }
    
    func recordFlushDuration(_ duration: TimeInterval) {
        flushDurations.append(duration)
        if flushDurations.count > 100 {
            flushDurations.removeFirst()
        }
    }
    
    func recordCompressionTime(_ duration: TimeInterval) {
        compressionTimes.append(duration)
        if compressionTimes.count > 100 {
            compressionTimes.removeFirst()
        }
    }
    
    // MARK: - Metrics Retrieval
    
    public func getMetrics() async -> LuxAnalyticsMetrics {
        let queueStats = await LuxAnalyticsQueue.shared.getQueueStats()
        
        let networkStats = LuxAnalyticsMetrics.NetworkStats(
            totalEventsSent: totalEventsSent,
            totalEventsFailed: totalEventsFailed,
            totalBatchesSent: totalBatchesSent,
            totalBatchesFailed: totalBatchesFailed,
            lastSuccessfulSend: lastSuccessfulSend,
            lastFailedSend: lastFailedSend,
            averagePayloadSize: payloadSizes.isEmpty ? 0 : payloadSizes.reduce(0, +) / payloadSizes.count,
            compressionRatio: compressionRatios.isEmpty ? 1.0 : compressionRatios.reduce(0, +) / Double(compressionRatios.count)
        )
        
        let performanceStats = LuxAnalyticsMetrics.PerformanceStats(
            averageFlushDuration: flushDurations.isEmpty ? 0 : flushDurations.reduce(0, +) / Double(flushDurations.count),
            averageCompressionTime: compressionTimes.isEmpty ? 0 : compressionTimes.reduce(0, +) / Double(compressionTimes.count),
            memoryUsage: getMemoryUsage(),
            diskUsage: getDiskUsage()
        )
        
        let config = await LuxAnalyticsStorage.shared.getConfiguration()
        let configInfo = LuxAnalyticsMetrics.ConfigurationInfo(
            sdkVersion: LuxAnalyticsVersion.current,
            configuredEndpoint: config?.apiURL.absoluteString ?? "Not configured",
            autoFlushInterval: config?.autoFlushInterval ?? 0,
            maxQueueSize: config?.maxQueueSize ?? 0,
            compressionEnabled: config?.compressionEnabled ?? false,
            debugLoggingEnabled: config?.debugLogging ?? false
        )
        
        // Get circuit breaker status
        let circuitBreakerMetrics = await LuxAnalytics.getCircuitBreakerStatus()
        let circuitBreakerStatus = LuxAnalyticsMetrics.CircuitBreakerStatus(
            state: String(describing: circuitBreakerMetrics?.currentState ?? .closed),
            failureCount: circuitBreakerMetrics?.failureCount ?? 0,
            successRate: circuitBreakerMetrics?.successRate ?? 0.0,
            timeInCurrentState: circuitBreakerMetrics?.timeInCurrentState ?? 0.0
        )
        
        return LuxAnalyticsMetrics(
            timestamp: Date(),
            queueStats: queueStats,
            networkStats: networkStats,
            performanceStats: performanceStats,
            configurationInfo: configInfo,
            circuitBreakerStatus: circuitBreakerStatus
        )
    }
    
    public func reset() {
        totalEventsSent = 0
        totalEventsFailed = 0
        totalBatchesSent = 0
        totalBatchesFailed = 0
        lastSuccessfulSend = nil
        lastFailedSend = nil
        payloadSizes.removeAll()
        compressionRatios.removeAll()
        flushDurations.removeAll()
        compressionTimes.removeAll()
    }
    
    // MARK: - Private Helpers
    
    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
    
    private func getDiskUsage() -> Int {
        // Estimate disk usage from UserDefaults
        let key = "com.luxardolabs.LuxAnalytics.eventQueue.v2"
        if let data = UserDefaults.standard.data(forKey: key) {
            return data.count
        }
        return 0
    }
}

// MARK: - Diagnostic Mode

public extension LuxAnalytics {
    
    /// Enable diagnostic mode for debugging
    static func enableDiagnosticMode() async {
        // Enable debug logging synchronously
        SecureLogger.updateDebugLogging(true)
    }
    
    /// Get current SDK metrics
    static func getDiagnostics() async -> LuxAnalyticsMetrics {
        return await LuxAnalyticsDiagnostics.shared.getMetrics()
    }
    
    /// Export diagnostics as JSON
    static func exportDiagnostics() async -> String? {
        let metrics = await getDiagnostics()
        guard let data = JSONCoders.encodePretty(metrics) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Reset diagnostic metrics
    static func resetDiagnostics() async {
        await LuxAnalyticsDiagnostics.shared.reset()
    }
}