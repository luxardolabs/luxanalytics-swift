import Foundation
@testable import LuxAnalytics

/// Test helper to reset LuxAnalytics state between tests
struct LuxAnalyticsTestHelper {
    static func reset() async {
        // Clear the storage through the actor
        await LuxAnalyticsStorage.shared.setInstance(nil)
        await LuxAnalyticsStorage.shared.setConfiguration(nil)
        
        // Clear any queued events
        await LuxAnalyticsQueue.shared.clear()
        
        // Reset circuit breakers
        await GlobalCircuitBreaker.shared.clear()
        
        // Reset diagnostics
        await LuxAnalyticsDiagnostics.shared.reset()
    }
    
    static func initializeForTesting() async throws {
        await reset()
        let config = try LuxAnalyticsConfiguration(
            dsn: "https://test-public-id@test.com/api/v1/events/test-project-id",
            debugLogging: true
        )
        try await LuxAnalytics.initialize(with: config)
    }
}