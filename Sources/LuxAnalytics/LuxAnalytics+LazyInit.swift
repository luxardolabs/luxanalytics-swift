import Foundation

// Alternative initialization pattern to prevent crashes
extension LuxAnalytics {
    
    /// Set configuration for lazy initialization
    /// This allows configuration to be set early without full initialization
    public static func setPendingConfiguration(_ config: LuxAnalyticsConfiguration) async {
        await LuxAnalyticsStorage.shared.setConfiguration(config)
    }
    
    /// Alternative shared accessor with auto-initialization
    public static var lazyShared: LuxAnalytics {
        get async {
            if let instance = await LuxAnalyticsStorage.shared.getInstance() {
                return instance
            }
            
            // Try to auto-initialize with pending config
            if let config = await LuxAnalyticsStorage.shared.getConfiguration() {
                do {
                    try await initialize(with: config)
                    return await shared
                } catch {
                    fatalError("LuxAnalytics auto-initialization failed: \(error)")
                }
            }
            
            fatalError("LuxAnalytics.initialize() or setPendingConfiguration() must be called before accessing shared instance")
        }
    }
    
    /// Safe shared accessor that returns nil if not initialized
    public static var sharedIfInitialized: LuxAnalytics? {
        get async {
            return await LuxAnalyticsStorage.shared.getInstance()
        }
    }
}

// Example usage in README:
/*
 
 // Option 1: Set pending config early
 await LuxAnalytics.setPendingConfiguration(config)
 // Later access will auto-initialize
 await LuxAnalytics.lazyShared.track(...)
 
 // Option 2: Safe optional access
 await LuxAnalytics.sharedIfInitialized?.track(...)
 
 */