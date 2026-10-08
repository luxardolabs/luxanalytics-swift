import Foundation
import Testing

@testable import LuxAnalytics

// Breaks found by the 1.1.0 adversarial pass, each reproduced before its fix. Network cases
// use the real dev server; the rest drive the SDK's own code paths. No stub server.

private func smallEvent(_ name: String) -> AnalyticsEvent {
    AnalyticsEvent(name: name, timestamp: ISO8601DateFormatter().string(from: Date()), userId: nil, sessionId: nil, metadata: [:])
}

/// F5: the server trims with Python's str.strip(), which also removes U+001C-U+001F.
@Suite
struct ServerWhitespaceTests {
    @Test(arguments: ["\u{1C}", "\u{1D}", "\u{1E}", "\u{1F}", " \u{1F} ", "\u{1C}\n"])
    func aNameTheServerTrimsToEmptyIsInvalid(name: String) {
        #expect(smallEvent(name).validationProblem == "the name is empty")
    }

    @Test func aNameWithASeparatorInsideIsStillValid() {
        #expect(smallEvent("a\u{1F}b").validationProblem == nil)
    }
}

/// F7: the debug log never carries a user or session id. Redaction only catches pattern-shaped
/// data, so a plain id like a username would otherwise be logged as is.
@Suite
struct IdentityLoggingTests {
    @Test func theLogLineSaysWhetherAnIdIsSetButNotWhichOne() {
        let line = AnalyticsActor.identityLogMessage("User", "jane_doe_1987")
        #expect(!line.contains("jane_doe_1987"))
        #expect(line == "User set")
        #expect(AnalyticsActor.identityLogMessage("Session", nil) == "Session cleared")
    }
}

extension GlobalStateTests {
    @Suite(.serialized)
    struct ReleaseHardeningQueueTests {
        init() async {
            await LuxAnalyticsTestHelper.reset()
        }

        private func restoreDefaults() async {
            await LuxAnalyticsQueue.shared.configure(
                maxSizeHard: LuxAnalyticsDefaults.maxQueueSizeHard,
                overflowStrategy: LuxAnalyticsDefaults.overflowStrategy,
                eventTTL: LuxAnalyticsDefaults.eventTTL)
            await LuxAnalyticsQueue.shared.clear()
        }

        /// F2: a batch returned after a 413 or 429 can't push the queue past its hard limit.
        @Test(arguments: [QueueOverflowStrategy.dropNewest, .dropOldest])
        func returnedEventsRespectTheHardLimit(strategy: QueueOverflowStrategy) async {
            let queue = LuxAnalyticsQueue.shared
            await queue.configure(maxSizeHard: 5, overflowStrategy: strategy, eventTTL: 3_600)
            for i in 0..<5 { await queue.enqueue(smallEvent("tracked-\(i)")) }
            let returned = (0..<3).map { QueuedEvent(event: smallEvent("returned-\($0)")) }
            await queue.returnToFront(returned)
            #expect(await queue.queueSize == 5)
            let names = await queue.dequeue(limit: 100, now: Date()).map(\.event.name)
            switch strategy {
            case .dropNewest: #expect(names == ["returned-0", "returned-1", "returned-2", "tracked-0", "tracked-1"])
            default: #expect(names == ["tracked-0", "tracked-1", "tracked-2", "tracked-3", "tracked-4"])
            }
            await restoreDefaults()
        }

        /// F1: one oversized batch doesn't throttle the session; the cap doubles back on success.
        @Test func theBatchCapRecoversAfterSuccess() async {
            let queue = LuxAnalyticsQueue.shared
            await queue.configure(maxSizeHard: 100, overflowStrategy: .dropOldest, eventTTL: 3_600)
            await queue.capBatchSize(at: 1)
            await queue.relaxBatchSizeCap()
            #expect(await queue.batchSizeCap == 2)
            await queue.relaxBatchSizeCap()
            #expect(await queue.batchSizeCap == 4)
            await queue.resetBatchSizeCap()
            #expect(await queue.batchSizeCap == Int.max)
            await queue.relaxBatchSizeCap()
            #expect(await queue.batchSizeCap == Int.max, "doubling saturates, never overflows")
            await restoreDefaults()
        }

        /// F3: a 429 is "retry after the reset", not a failed attempt. Six in a row (more than
        /// maxRetryAttempts) must leave the event queued, unspent, and never abandoned.
        @Test func rateLimitedEventsAreNeverAbandoned() async throws {
            let config = try LuxAnalyticsConfiguration(
                dsn: "https://rate-limit@test.example.com/api/v1/events/ratelimit", autoFlushInterval: 3_600)
            try await LuxAnalytics.initialize(with: config)
            defer { Task { await LuxAnalyticsTestHelper.reset() } }
            let analytics = await LuxAnalytics.shared
            var batch = [QueuedEvent(event: smallEvent("rate_limited"))]
            for _ in 0..<(config.maxRetryAttempts + 1) {
                await analytics.handleResponse(statusCode: 429, body: Data(), events: batch, config: config)
                batch = await LuxAnalyticsQueue.shared.dequeue(limit: 10, now: Date())
                #expect(batch.map(\.event.name) == ["rate_limited"], "the event left the queue")
            }
            #expect(batch.first?.retryCount == 0, "a 429 spent the retry budget")
            await LuxAnalyticsQueue.shared.clear()
        }
    }

    /// F1 and F5 against the real dev server.
    @Suite(
        .serialized,
        .enabled(
            if: ProcessInfo.processInfo.environment["LUXANALYTICS_DEV_DSN"].map { !$0.isEmpty } ?? false,
            "LUXANALYTICS_DEV_DSN not set; see LUXANALYTI-73"))
    struct ReleaseHardeningDevServerTests {
        private var dsn: String {
            get throws { try #require(ProcessInfo.processInfo.environment["LUXANALYTICS_DEV_DSN"]) }
        }

        /// F5: a control-character name used to pass track() and 422 the whole batch, losing the
        /// valid event beside it.
        @Test func aSeparatorOnlyNameNoLongerLosesItsBatch() async throws {
            await LuxAnalyticsTestHelper.reset()
            try await LuxAnalytics.initialize(with: try LuxAnalyticsConfiguration(dsn: try dsn, autoFlushInterval: 3_600))
            defer { Task { await LuxAnalyticsTestHelper.reset() } }
            try await LuxAnalytics.shared.track("hardening_valid_neighbour")
            await #expect(throws: LuxAnalyticsError.invalidEvent("the name is empty")) {
                try await LuxAnalytics.shared.track("\u{1F}")
            }
            await LuxAnalytics.flush()
            let metrics = try #require(await LuxAnalytics.getMetrics())
            #expect(metrics.networkStats.totalEventsSent == 1)
            #expect(metrics.networkStats.totalEventsFailed == 0)
        }

        /// F1: an oversized event splits its batch down to itself and is dropped; after that the
        /// remaining events go out together again, not one per flush.
        @Test func afterAnOversizedEventIsDroppedBatchesAreFullSizeAgain() async throws {
            await LuxAnalyticsTestHelper.reset()
            try await LuxAnalytics.initialize(with: try LuxAnalyticsConfiguration(dsn: try dsn, autoFlushInterval: 3_600))
            defer { Task { await LuxAnalyticsTestHelper.reset() } }
            let queue = LuxAnalyticsQueue.shared
            await queue.enqueue(
                AnalyticsEvent(
                    name: "hardening_oversized", timestamp: ISO8601DateFormatter().string(from: Date()), userId: nil,
                    sessionId: nil, metadata: ["blob": String(repeating: "x", count: 11 * 1_024 * 1_024)]))
            await queue.enqueue(smallEvent("hardening_small_1"))
            await queue.enqueue(smallEvent("hardening_small_2"))

            await LuxAnalytics.flush()  // 3 events, 413: split, cap 1
            await LuxAnalytics.flush()  // the oversized event alone, 413: dropped, cap reset
            await LuxAnalytics.flush()  // both small events, in one request
            #expect(await queue.queueSize == 0, "the cap stayed pinned after the oversized event was gone")
            let metrics = try #require(await LuxAnalytics.getMetrics())
            #expect(metrics.networkStats.totalEventsSent == 2)
        }
    }
}
