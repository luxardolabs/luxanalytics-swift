import Foundation
import Testing

@testable import LuxAnalytics

/// The server rejects a whole batch (422) for one invalid event, so the SDK checks the
/// server's EventCreate rules before queueing. Lengths are Unicode code points, as the server
/// (Python `len`) counts them.
@Suite
struct EventValidationTests {
    private func event(
        name: String = "ok", userId: String? = nil, sessionId: String? = nil, metadata: [String: String] = [:]
    ) -> AnalyticsEvent {
        AnalyticsEvent(name: name, timestamp: "2026-01-01T00:00:00Z", userId: userId, sessionId: sessionId, metadata: metadata)
    }

    @Test func aNormalEventIsValid() {
        #expect(event(name: "screen_view", userId: "u", sessionId: "s", metadata: ["k": "v"]).validationProblem == nil)
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func aBlankNameIsInvalid(name: String) {
        #expect(event(name: name).validationProblem == "the name is empty")
    }

    @Test func lengthIsCountedInCodePointsLikeTheServer() {
        // 👨‍👩‍👧 is one Swift Character but 5 code points.
        let family = "👨‍👩‍👧"
        #expect(family.count == 1)
        #expect(family.unicodeScalars.count == 5)
        let fits = String(repeating: "a", count: 250) + family  // 255 code points
        let over = String(repeating: "a", count: 251) + family  // 256 code points
        #expect(event(name: fits).validationProblem == nil)
        #expect(event(name: over).validationProblem == "the name is longer than 255 characters")
    }

    @Test func longIdsAreInvalid() {
        let long = String(repeating: "x", count: 256)
        #expect(event(userId: long).validationProblem == "the user id is longer than 255 characters")
        #expect(event(sessionId: long).validationProblem == "the session id is longer than 255 characters")
        #expect(event(userId: String(repeating: "x", count: 255)).validationProblem == nil)
    }

    @Test func nulCharactersAreInvalid() {
        #expect(event(name: "a\0b").validationProblem == "the name contains a NUL character")
        #expect(event(userId: "a\0b").validationProblem == "the user id contains a NUL character")
        #expect(event(metadata: ["k\0": "v"]).validationProblem == "the metadata contains a NUL character")
        #expect(event(metadata: ["k": "v\0"]).validationProblem == "the metadata contains a NUL character")
    }
}

extension GlobalStateTests {
    @Suite(.serialized)
    struct TrackValidationTests {
        @Test func trackRejectsAnInvalidEventWithoutQueueingIt() async throws {
            try await LuxAnalyticsTestHelper.initializeForTesting()
            await LuxAnalyticsQueue.shared.clear()
            await #expect(throws: LuxAnalyticsError.invalidEvent("the name is empty")) {
                try await LuxAnalytics.shared.track("  ")
            }
            #expect(await LuxAnalyticsQueue.shared.queueSize == 0)
            await LuxAnalyticsTestHelper.reset()
        }

        /// The server accepts at most 1,000 events per request. A real failure (nothing
        /// listens on 127.0.0.1:9) with maxRetryAttempts 0 abandons exactly what one flush sent.
        @Test func oneFlushSendsAtMost1000Events() async throws {
            await LuxAnalyticsTestHelper.reset()
            let config = try LuxAnalyticsConfiguration(
                dsn: "https://cap-test@127.0.0.1:9/api/v1/events/cap",
                autoFlushInterval: 3_600, maxQueueSize: 100_000, batchSize: 5_000, maxRetryAttempts: 0)
            try await LuxAnalytics.initialize(with: config)
            defer { Task { await LuxAnalyticsTestHelper.reset() } }
            for i in 0..<1_200 {
                await LuxAnalyticsQueue.shared.enqueue(
                    AnalyticsEvent(name: "e\(i)", timestamp: "2026-01-01T00:00:00Z", userId: nil, sessionId: nil, metadata: [:]))
            }

            let stream = LuxAnalyticsEvents.eventStream
            await LuxAnalytics.flush()
            let abandoned = await firstAbandonedCount(in: stream)
            #expect(abandoned == 1_000)
            #expect(await LuxAnalyticsQueue.shared.queueSize == 200)
        }

        private func firstAbandonedCount(in stream: AsyncStream<AnalyticsEventNotification>) async -> Int? {
            await withTaskGroup(of: Int?.self) { group in
                group.addTask {
                    for await notification in stream {
                        if case .eventsAbandoned(let events, _) = notification { return events.count }
                    }
                    return nil
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(10))
                    return nil
                }
                let first = await group.next().flatMap { $0 }
                group.cancelAll()
                return first
            }
        }
    }
}
