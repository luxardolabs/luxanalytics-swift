import Foundation

/// Debug utilities for LuxAnalytics troubleshooting
public struct LuxAnalyticsDebug {
    
    /// Check current status of LuxAnalytics
    public static func status() async {
        print("""
            
            ========== LuxAnalytics Status ==========
            
            🔹 Initialization:
               Initialized: \(await LuxAnalytics.isInitialized)
            
            🔹 Queue Stats:
               \(await queueDescription())
            
            🔹 Network:
               Available: \(await NetworkMonitor.shared.isConnected)
               Is Expensive: \(await NetworkMonitor.shared.isExpensive)
            
            🔹 Analytics Enabled:
               \(await AnalyticsSettings.shared.isEnabled)
            
            =========================================
            
            """)
    }
    
    private static func queueDescription() async -> String {
        guard await LuxAnalytics.isInitialized else {
            return "Not initialized"
        }
        
        let stats = await LuxAnalytics.getQueueStats()
        return """
               Total Events: \(stats.totalEvents)
               Oldest Event: \(stats.oldestEventAge.map { "\($0)s ago" } ?? "None")
               Total Size: \(ByteCountFormatter.string(fromByteCount: Int64(stats.totalSizeBytes), countStyle: .file))
               """
    }
    
    /// Validate common setup issues
    public static func validateSetup() async {
        print("""
            
            ========== LuxAnalytics Setup Validation ==========
            ✓ Checking initialization status...
              - Initialized: \(await LuxAnalytics.isInitialized)
            
            ✓ Checking configuration...
              - Has current config: \(await LuxAnalyticsStorage.shared.getConfiguration() != nil)
            
            ✓ Checking queue status...
              - Queue accessible: \(await LuxAnalytics.sharedIfInitialized != nil)
            
            ✓ Common issues to check:
              1. Is LuxAnalytics.initialize() called in App.init()?
              2. Is the initialization method static?
              3. Are StateObjects created AFTER initialization?
              4. Check console for any error messages
            
            ✓ Next steps:
              - Enable debug logging in configuration
              - Check network connectivity
              - Verify DSN format is correct
            ===================================================
            
            """)
    }
    
    /// Print sample initialization code
    public static func printSampleCode() {
        print("""
            
            ========== Sample LuxAnalytics Setup ==========
            
            // In your App struct:
            
            @main
            struct MyApp: App {
                init() {
                    // Option 1: From Info.plist
                    Task {
                        try? await LuxAnalytics.initializeFromPlist()
                    }
                    
                    // Option 2: Direct configuration
                    Task {
                        let config = try? LuxAnalyticsConfiguration(
                            dsn: "https://your-id@analytics.example.com/api/v1/events/project-id"
                        )
                        if let config = config {
                            try? await LuxAnalytics.initialize(with: config)
                        }
                    }
                }
                
                var body: some Scene {
                    WindowGroup {
                        ContentView()
                    }
                }
            }
            
            // In your views:
            
            Task {
                try? await LuxAnalytics.shared.track("button_tapped")
            }
            
            ==============================================
            
            """)
    }
}

// MARK: - Development Helpers

extension LuxAnalytics {
    
    /// Force a flush (for testing)
    public static func forceFlush() async {
        await flush()
    }
    
    /// Get current metrics
    public static func getMetrics() async -> LuxAnalyticsMetrics? {
        guard await isInitialized else { return nil }
        return await LuxAnalyticsDiagnostics.shared.getMetrics()
    }
}