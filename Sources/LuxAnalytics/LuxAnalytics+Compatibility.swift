import Foundation

// Convenience initialization helpers
extension LuxAnalytics {
    
    /// Configure and initialize LuxAnalytics in one call
    /// Useful for simple configurations
    public static func quickStart(
        dsn: String,
        debugLogging: Bool = false
    ) async throws {
        let config = try LuxAnalyticsConfiguration(
            dsn: dsn,
            debugLogging: debugLogging
        )
        try await initialize(with: config)
    }
    
    /// Initialize LuxAnalytics from Info.plist configuration
    /// Reads LuxAnalyticsDSN and optional configuration from Info.plist
    /// - Parameter bundle: The bundle to read from (defaults to main bundle)
    /// - Throws: LuxAnalyticsError if DSN is not found or already initialized
    public static func initializeFromPlist(bundle: Bundle = .main) async throws {
        let config = try LuxAnalyticsConfiguration(bundle: bundle)
        try await initialize(with: config)
    }
}