import Foundation
import Testing

@testable import LuxAnalytics

private let setupDSN = "https://setup-test@test.example.com/api/v1/events/setupproject"

extension GlobalStateTests {
    @Suite(.serialized)
    struct SetupTests {
        init() async {
            await LuxAnalyticsTestHelper.reset()
        }

        @Test func quickStartInitializes() async throws {
            try await LuxAnalytics.quickStart(dsn: setupDSN)
            #expect(await LuxAnalytics.isInitialized)
            #expect(await LuxAnalytics.sharedIfInitialized != nil)
            await LuxAnalyticsTestHelper.reset()
        }

        @Test func quickStartRejectsAMalformedDSN() async {
            await #expect(throws: LuxAnalyticsError.self) {
                try await LuxAnalytics.quickStart(dsn: "not a dsn")
            }
            #expect(await !LuxAnalytics.isInitialized)
        }

        @Test func quickStartTwiceThrowsAlreadyInitialized() async throws {
            try await LuxAnalytics.quickStart(dsn: setupDSN)
            await #expect(throws: LuxAnalyticsError.alreadyInitialized) {
                try await LuxAnalytics.quickStart(dsn: setupDSN)
            }
            await LuxAnalyticsTestHelper.reset()
        }

        @Test func initializeFromPlistWithoutADSNThrows() async {
            // The test runner's Info.plist has no LuxAnalyticsDSN.
            await #expect(throws: LuxAnalyticsError.self) {
                try await LuxAnalytics.initializeFromPlist()
            }
            #expect(await !LuxAnalytics.isInitialized)
        }

        @Test func sharedIfInitializedIsNilUntilInitialized() async throws {
            #expect(await LuxAnalytics.sharedIfInitialized == nil)
            try await LuxAnalytics.quickStart(dsn: setupDSN)
            #expect(await LuxAnalytics.sharedIfInitialized != nil)
            await LuxAnalyticsTestHelper.reset()
        }

        @Test func lazySharedInitializesFromAPendingConfiguration() async throws {
            await LuxAnalytics.setPendingConfiguration(try LuxAnalyticsConfiguration(dsn: setupDSN))
            #expect(await !LuxAnalytics.isInitialized)
            _ = await LuxAnalytics.lazyShared
            #expect(await LuxAnalytics.isInitialized)
            await LuxAnalyticsTestHelper.reset()
        }
    }

    @Suite(.serialized)
    struct DiagnosticsTests {
        init() async {
            await LuxAnalyticsDiagnostics.shared.reset()
        }

        @Test func recordedValuesAppearInTheMetrics() async {
            let diagnostics = LuxAnalyticsDiagnostics.shared
            await diagnostics.recordEventsSent(count: 3)
            await diagnostics.recordEventsFailed(count: 1, error: URLError(.timedOut))
            await diagnostics.recordBatchSent()
            await diagnostics.recordBatchSent()
            await diagnostics.recordBatchFailed()
            await diagnostics.recordPayloadSize(1000, compressedSize: 250)
            await diagnostics.recordPayloadSize(500, compressedSize: nil)
            await diagnostics.recordFlushDuration(0.2)
            await diagnostics.recordFlushDuration(0.4)
            await diagnostics.recordCompressionTime(0.01)

            let metrics = await diagnostics.getMetrics()
            #expect(metrics.networkStats.totalEventsSent == 3)
            #expect(metrics.networkStats.totalEventsFailed == 1)
            #expect(metrics.networkStats.totalBatchesSent == 2)
            #expect(metrics.networkStats.totalBatchesFailed == 1)
            #expect(metrics.networkStats.lastSuccessfulSend != nil)
            #expect(metrics.networkStats.lastFailedSend != nil)
            #expect(metrics.networkStats.averagePayloadSize == 750)
            // Only compressed payloads count toward the ratio.
            #expect(metrics.networkStats.compressionRatio == 0.25)
            #expect(abs(metrics.performanceStats.averageFlushDuration - 0.3) < 0.000_001)
            #expect(metrics.performanceStats.averageCompressionTime == 0.01)
        }

        @Test func averagesUseOnlyTheLast100Samples() async {
            for size in 1...150 {
                await LuxAnalyticsDiagnostics.shared.recordPayloadSize(size, compressedSize: nil)
            }
            // Mean of 51...150.
            #expect(await LuxAnalyticsDiagnostics.shared.getMetrics().networkStats.averagePayloadSize == 100)
        }

        @Test func resetClearsEverything() async {
            await LuxAnalyticsDiagnostics.shared.recordBatchSent()
            await LuxAnalyticsDiagnostics.shared.recordPayloadSize(10, compressedSize: 5)
            await LuxAnalytics.resetDiagnostics()
            let stats = await LuxAnalyticsDiagnostics.shared.getMetrics().networkStats
            #expect(stats.totalBatchesSent == 0)
            #expect(stats.averagePayloadSize == 0)
            #expect(stats.compressionRatio == 1.0)
            #expect(stats.lastSuccessfulSend == nil)
        }

        @Test func exportIsPrettyJSONOfTheMetrics() async throws {
            await LuxAnalyticsDiagnostics.shared.recordBatchSent()
            let export = try #require(await LuxAnalytics.exportDiagnostics())
            let object = try #require(
                try JSONSerialization.jsonObject(with: Data(export.utf8)) as? [String: Any])
            let network = try #require(object["networkStats"] as? [String: Any])
            #expect(network["totalBatchesSent"] as? Int == 1)
            #expect(export.contains("\n"))
        }
    }
}
