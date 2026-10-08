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
        let config = try LuxAnalyticsConfiguration(
            dsn: base.replacingOccurrences(of: "://", with: "://sdk-integration-unknown-key@")
                + "/api/v1/events/0000000000000000")
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
        }
    }
}
