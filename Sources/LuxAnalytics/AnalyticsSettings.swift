import Foundation

/// Actor-based analytics settings for thread-safe access
public actor AnalyticsSettings {
    public static let shared = AnalyticsSettings()
    private let key = "com.luxardolabs.LuxAnalytics.enabled"
    private let userDefaults: UserDefaults
    
    /// Current enabled state (cached)
    private var cachedIsEnabled: Bool
    
    public var isEnabled: Bool {
        get {
            return cachedIsEnabled
        }
    }
    
    public func setEnabled(_ enabled: Bool) {
        cachedIsEnabled = enabled
        userDefaults.set(enabled, forKey: key)
    }
    
    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.cachedIsEnabled = userDefaults.object(forKey: key) as? Bool ?? true
    }
}