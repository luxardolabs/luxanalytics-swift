import Foundation

/// Strategy for handling queue overflow
public enum QueueOverflowStrategy: String, Codable, Sendable {
    /// Drop oldest events when queue is full
    case dropOldest
    
    /// Drop newest events when queue is full
    case dropNewest
    
    /// Drop all events and start fresh
    case dropAll
}

/// Configuration for LuxAnalytics initialization
public struct LuxAnalyticsConfiguration: Sendable {
    /// The Data Source Name (DSN) containing endpoint and credentials
    public let dsn: String
    
    /// The analytics API endpoint URL (parsed from DSN)
    public let apiURL: URL
    
    /// The public ID for authentication (parsed from DSN)
    public let publicId: String
    
    /// The project ID (parsed from DSN)
    public let projectId: String
    
    /// Auto-flush interval in seconds (default: see LuxAnalyticsDefaults)
    public let autoFlushInterval: TimeInterval
    
    /// Maximum queue size before forced flush (default: see LuxAnalyticsDefaults)
    public let maxQueueSize: Int
    
    /// Number of events per batch (default: see LuxAnalyticsDefaults)
    public let batchSize: Int
    
    /// Enable debug logging (default: see LuxAnalyticsDefaults)
    public let debugLogging: Bool
    
    /// Network request timeout in seconds (default: see LuxAnalyticsDefaults)
    public let requestTimeout: TimeInterval
    
    /// Maximum queue size before dropping oldest events (default: see LuxAnalyticsDefaults)
    public let maxQueueSizeHard: Int
    
    /// Event time-to-live in seconds (default: see LuxAnalyticsDefaults)
    public let eventTTL: TimeInterval
    
    /// Maximum retry attempts for failed events (default: see LuxAnalyticsDefaults)
    public let maxRetryAttempts: Int
    
    /// Queue overflow strategy when hard limit is reached
    public let overflowStrategy: QueueOverflowStrategy
    
    /// Enable compression for payloads
    public let compressionEnabled: Bool
    
    /// Minimum payload size for compression
    public let compressionThreshold: Int
    
    /// Certificate pinning configuration (optional)
    public let certificatePinning: CertificatePinningConfig?
    
    /// Initializes a new configuration with DSN
    /// - Parameters:
    ///   - dsn: The Data Source Name (DSN) string in format: https://publicId@domain.com/api/v1/events/projectId
    ///   - autoFlushInterval: Auto-flush interval in seconds
    ///   - maxQueueSize: Maximum queue size before forced flush
    ///   - batchSize: Number of events per batch
    ///   - debugLogging: Enable debug logging
    ///   - requestTimeout: Network request timeout in seconds
    ///   - maxQueueSizeHard: Maximum queue size before dropping events
    ///   - eventTTL: Event time-to-live in seconds
    ///   - maxRetryAttempts: Maximum retry attempts
    ///   - overflowStrategy: Strategy when queue is full
    ///   - compressionEnabled: Enable compression for payloads
    ///   - compressionThreshold: Minimum payload size for compression
    ///   - certificatePinning: Certificate pinning configuration
    /// - Throws: LuxAnalyticsError if DSN is invalid
    public init(
        dsn: String,
        autoFlushInterval: TimeInterval = LuxAnalyticsDefaults.autoFlushInterval,
        maxQueueSize: Int = LuxAnalyticsDefaults.maxQueueSize,
        batchSize: Int = LuxAnalyticsDefaults.batchSize,
        debugLogging: Bool = LuxAnalyticsDefaults.debugLogging,
        requestTimeout: TimeInterval = LuxAnalyticsDefaults.requestTimeout,
        maxQueueSizeHard: Int = LuxAnalyticsDefaults.maxQueueSizeHard,
        eventTTL: TimeInterval = LuxAnalyticsDefaults.eventTTL,
        maxRetryAttempts: Int = LuxAnalyticsDefaults.maxRetryAttempts,
        overflowStrategy: QueueOverflowStrategy = LuxAnalyticsDefaults.overflowStrategy,
        compressionEnabled: Bool = LuxAnalyticsDefaults.compressionEnabled,
        compressionThreshold: Int = LuxAnalyticsDefaults.compressionThreshold,
        certificatePinning: CertificatePinningConfig? = nil
    ) throws {
        // Parse DSN
        guard let urlComponents = URLComponents(string: dsn),
              urlComponents.host != nil,
              let publicId = urlComponents.user,
              let path = urlComponents.path.split(separator: "/").last.map(String.init),
              !publicId.isEmpty,
              !path.isEmpty else {
            throw LuxAnalyticsError.invalidConfiguration("Invalid DSN format. Expected: https://publicId@domain.com/api/v1/events/projectId")
        }
        
        // Reconstruct base URL without project ID for the apiURL
        var baseComponents = urlComponents
        baseComponents.user = nil
        baseComponents.password = nil
        let pathComponents = urlComponents.path.split(separator: "/").dropLast()
        baseComponents.path = "/" + pathComponents.joined(separator: "/") + "/"
        
        guard let baseURL = baseComponents.url else {
            throw LuxAnalyticsError.invalidConfiguration("Failed to construct API URL from DSN")
        }
        
        self.dsn = dsn
        self.apiURL = baseURL
        self.publicId = publicId
        self.projectId = path
        self.autoFlushInterval = autoFlushInterval
        self.maxQueueSize = maxQueueSize
        self.batchSize = batchSize
        self.debugLogging = debugLogging
        self.requestTimeout = requestTimeout
        self.maxQueueSizeHard = maxQueueSizeHard
        self.eventTTL = eventTTL
        self.maxRetryAttempts = maxRetryAttempts
        self.overflowStrategy = overflowStrategy
        self.compressionEnabled = compressionEnabled
        self.compressionThreshold = compressionThreshold
        self.certificatePinning = certificatePinning
    }
    
    /// Initializes configuration from Info.plist
    /// Looks for LuxAnalyticsDSN key in Info.plist
    /// - Parameter bundle: The bundle to read from (defaults to main bundle)
    /// - Throws: LuxAnalyticsError if DSN is not found or invalid
    public init(bundle: Bundle = .main) throws {
        guard let dsn = bundle.object(forInfoDictionaryKey: "LuxAnalyticsDSN") as? String else {
            throw LuxAnalyticsError.invalidConfiguration("LuxAnalyticsDSN not found in Info.plist")
        }
        
        // Read optional configuration from plist
        let autoFlushInterval = bundle.object(forInfoDictionaryKey: "LuxAnalyticsAutoFlushInterval") as? TimeInterval ?? LuxAnalyticsDefaults.autoFlushInterval
        let maxQueueSize = bundle.object(forInfoDictionaryKey: "LuxAnalyticsMaxQueueSize") as? Int ?? LuxAnalyticsDefaults.maxQueueSize
        let batchSize = bundle.object(forInfoDictionaryKey: "LuxAnalyticsBatchSize") as? Int ?? LuxAnalyticsDefaults.batchSize
        let debugLogging = bundle.object(forInfoDictionaryKey: "LuxAnalyticsDebugLogging") as? Bool ?? LuxAnalyticsDefaults.debugLogging
        let requestTimeout = bundle.object(forInfoDictionaryKey: "LuxAnalyticsRequestTimeout") as? TimeInterval ?? LuxAnalyticsDefaults.requestTimeout
        let compressionEnabled = bundle.object(forInfoDictionaryKey: "LuxAnalyticsCompressionEnabled") as? Bool ?? LuxAnalyticsDefaults.compressionEnabled
        
        try self.init(
            dsn: dsn,
            autoFlushInterval: autoFlushInterval,
            maxQueueSize: maxQueueSize,
            batchSize: batchSize,
            debugLogging: debugLogging,
            requestTimeout: requestTimeout,
            compressionEnabled: compressionEnabled
        )
    }
}

