import Foundation

/// Centralized default values for LuxAnalytics configuration
public enum LuxAnalyticsDefaults {
    /// Auto-flush interval in seconds
    public static let autoFlushInterval: TimeInterval = 30.0
    
    /// Maximum queue size before forced flush (soft limit)
    public static let maxQueueSize: Int = 500
    
    /// Number of events per batch
    public static let batchSize: Int = 50
    
    /// Enable debug logging
    public static let debugLogging: Bool = false
    
    /// Network request timeout in seconds
    public static let requestTimeout: TimeInterval = 60.0
    
    /// Maximum queue size before dropping events (hard limit)
    public static let maxQueueSizeHard: Int = 10000
    
    /// Event time-to-live in seconds (7 days)
    public static let eventTTL: TimeInterval = 604800
    
    /// Maximum retry attempts for failed events
    public static let maxRetryAttempts: Int = 5
    
    /// Queue overflow strategy when hard limit is reached
    public static let overflowStrategy: QueueOverflowStrategy = .dropOldest
    
    /// Enable compression for large payloads
    public static let compressionEnabled: Bool = true
    
    /// Minimum payload size for compression (in bytes)
    public static let compressionThreshold: Int = 1024 // 1KB
}