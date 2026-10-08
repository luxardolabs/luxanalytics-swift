import Foundation
import Testing

@testable import LuxAnalytics

// Real HTTP from the simulator to the LuxAnalytics dev server, through the SDK's own
// NetworkTransport: no stubs. `make integration` supplies the environment (from
// Makefile.local, since the dev host is private) and refuses to run without it.
//   LUXANALYTICS_DEV_URL  the dev server's base URL, e.g. https://<dev-host>:4000
//   LUXANALYTICS_DEV_DSN  a DSN for the dev "sdk-integration" app (LUXANALYTI-73)
// In a plain `make test` neither is set, and the suites report themselves skipped.
private enum DevServer {
    static let baseURL = ProcessInfo.processInfo.environment["LUXANALYTICS_DEV_URL"].flatMap {
        $0.isEmpty ? nil : $0
    }
    static let dsn = ProcessInfo.processInfo.environment["LUXANALYTICS_DEV_DSN"].flatMap {
        $0.isEmpty ? nil : $0
    }
    /// A DSN the server doesn't know: any HTTP response proves the TLS handshake passed.
    static func unknownDSN(_ base: String) -> String {
        base.replacingOccurrences(of: "://", with: "://sdk-integration-unknown-key@")
            + "/api/v1/events/0000000000000000"
    }

    static func event(_ name: String) -> QueuedEvent {
        QueuedEvent(
            event: AnalyticsEvent(
                name: name,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                userId: "sdk-integration",
                sessionId: UUID().uuidString,
                metadata: ["suite": "DevServerIntegrationTests"]))
    }

    /// The JSON body of an ingest response.
    static func json(_ body: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}

@Suite(.enabled(if: DevServer.baseURL != nil, "LUXANALYTICS_DEV_URL not set; run `make integration`"))
struct DevServerRejectionTests {
    @Test func unknownCredentialsAreRefusedAndDropped() async throws {
        let base = try #require(DevServer.baseURL)
        let config = try LuxAnalyticsConfiguration(dsn: DevServer.unknownDSN(base))
        let response = try await NetworkTransport.send(
            LuxAnalytics.encodePayload([DevServer.event("rejected")]), deflated: false, config: config)
        #expect([401, 403, 404].contains(response.statusCode), "got \(response.statusCode)")
        #expect(LuxAnalytics.outcome(forStatus: response.statusCode) == .drop)
    }
}

@Suite(.enabled(if: DevServer.dsn != nil, "LUXANALYTICS_DEV_DSN not set; see LUXANALYTI-73"))
struct DevServerIngestTests {
    private var config: LuxAnalyticsConfiguration {
        get throws { try LuxAnalyticsConfiguration(dsn: try #require(DevServer.dsn)) }
    }

    @Test func aSingleEventIsAccepted() async throws {
        let response = try await NetworkTransport.send(
            LuxAnalytics.encodePayload([DevServer.event("single")]), deflated: false, config: config)
        #expect(LuxAnalytics.outcome(forStatus: response.statusCode) == .sent, "got \(response.statusCode)")
        #expect(try DevServer.json(response.body)["events_received"] as? Int == 1)
    }

    @Test func aCompressedBatchIsAccepted() async throws {
        let json = try LuxAnalytics.encodePayload((1...5).map { DevServer.event("batch-\($0)") })
        let body = try #require(json.zlibCompressed())
        let response = try await NetworkTransport.send(body, deflated: true, config: config)
        #expect(LuxAnalytics.outcome(forStatus: response.statusCode) == .sent, "got \(response.statusCode)")
        #expect(try DevServer.json(response.body)["events_received"] as? Int == 5)
    }

    @Test func resendingAnEventIdIsAcknowledgedAsADuplicate() async throws {
        let payload = try LuxAnalytics.encodePayload([DevServer.event("idempotent")])
        let first = try await NetworkTransport.send(payload, deflated: false, config: config)
        let second = try await NetworkTransport.send(payload, deflated: false, config: config)
        #expect(LuxAnalytics.outcome(forStatus: first.statusCode) == .sent)
        #expect(LuxAnalytics.outcome(forStatus: second.statusCode) == .sent, "a duplicate must still be a 2xx")
        #expect(try DevServer.json(first.body)["duplicates"] as? Int == 0)
        #expect(try DevServer.json(second.body)["duplicates"] as? Int == 1)
    }

    @Test func anEmptyEventNameIsRejectedAndDropped() async throws {
        let payload = try LuxAnalytics.encodePayload([DevServer.event("")])
        let response = try await NetworkTransport.send(payload, deflated: false, config: config)
        #expect(response.statusCode == 422, "got \(response.statusCode)")
        #expect(LuxAnalytics.outcome(forStatus: response.statusCode) == .drop)
    }
}

extension GlobalStateTests {
    @Suite(
        .serialized,
        .enabled(if: DevServer.dsn != nil, "LUXANALYTICS_DEV_DSN not set; see LUXANALYTI-73"))
    struct DevServerEndToEndTests {
        @Test func trackThenFlushDeliversAndEmptiesTheQueue() async throws {
            await LuxAnalyticsTestHelper.reset()
            let config = try LuxAnalyticsConfiguration(
                dsn: try #require(DevServer.dsn), autoFlushInterval: 3600)
            try await LuxAnalytics.initialize(with: config)
            defer { Task { await LuxAnalyticsTestHelper.reset() } }

            try await LuxAnalytics.shared.track("end_to_end", metadata: ["suite": "DevServerEndToEndTests"])
            #expect(await LuxAnalyticsQueue.shared.queueSize == 1)

            await LuxAnalytics.flush()
            #expect(await LuxAnalyticsQueue.shared.queueSize == 0)
            let metrics = try #require(await LuxAnalytics.getMetrics())
            #expect(metrics.networkStats.totalEventsSent == 1)
            #expect(metrics.networkStats.totalBatchesSent == 1)
            #expect(metrics.networkStats.averagePayloadSize > 0)
            #expect(metrics.performanceStats.averageFlushDuration > 0)
        }
    }

    // Runs with only LUXANALYTICS_DEV_URL: the real server refuses unknown credentials,
    // which exercises the whole track -> flush -> drop path and its metrics today.
    @Suite(
        .serialized,
        .enabled(if: DevServer.baseURL != nil, "LUXANALYTICS_DEV_URL not set; run `make integration`"))
    struct DevServerEndToEndRejectionTests {
        @Test func aRefusedBatchIsDroppedAndRecorded() async throws {
            await LuxAnalyticsTestHelper.reset()
            let base = try #require(DevServer.baseURL)
            let config = try LuxAnalyticsConfiguration(dsn: DevServer.unknownDSN(base), autoFlushInterval: 3600)
            try await LuxAnalytics.initialize(with: config)
            defer { Task { await LuxAnalyticsTestHelper.reset() } }

            try await LuxAnalytics.shared.track("refused", metadata: ["suite": "DevServerEndToEndRejectionTests"])
            await LuxAnalytics.flush()

            // A refusal is not retryable: the event is dropped, not requeued.
            #expect(await LuxAnalyticsQueue.shared.queueSize == 0)
            let metrics = try #require(await LuxAnalytics.getMetrics())
            #expect(metrics.networkStats.totalEventsSent == 0)
            #expect(metrics.networkStats.totalEventsFailed == 1)
            #expect(metrics.networkStats.totalBatchesFailed == 1)
            #expect(metrics.networkStats.averagePayloadSize > 0)
            #expect(metrics.performanceStats.averageFlushDuration > 0)
            // Refusals don't trip the breaker: it's a client error, not an outage.
            #expect(await !GlobalCircuitBreaker.shared.isOpen(for: config.apiURL))
        }
    }
}
