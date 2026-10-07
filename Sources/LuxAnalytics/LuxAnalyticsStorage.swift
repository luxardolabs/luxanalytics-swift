import Foundation

/// Thread-safe storage for LuxAnalytics singleton and configuration
actor LuxAnalyticsStorage {
    static let shared = LuxAnalyticsStorage()
    
    private var instance: LuxAnalytics?
    private var configuration: LuxAnalyticsConfiguration?
    
    private init() {}
    
    func getInstance() -> LuxAnalytics? {
        return instance
    }
    
    func setInstance(_ value: LuxAnalytics?) {
        instance = value
    }
    
    func getConfiguration() -> LuxAnalyticsConfiguration? {
        return configuration
    }
    
    func setConfiguration(_ value: LuxAnalyticsConfiguration?) {
        configuration = value
    }
    
    func isInitialized() -> Bool {
        return instance != nil
    }
}