import Foundation

/// LuxAnalytics SDK version information
public struct LuxAnalyticsVersion {
    /// Current SDK version
    public static let current = "1.0.2"
    
    /// SDK name
    public static let name = "LuxAnalytics"
    
    /// Full version string
    public static var fullVersion: String {
        "\(name)/\(current)"
    }
}