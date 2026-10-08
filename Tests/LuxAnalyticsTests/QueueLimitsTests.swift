import Foundation
import Testing

@testable import LuxAnalytics

extension GlobalStateTests {
    /// The configuration's queue limits are enforced: maxQueueSizeHard + overflowStrategy on
    /// enqueue, eventTTL before each dequeue. Before 1.1.0 all three were accepted and ignored.
    @Suite(.serialized)
    struct QueueLimitsTests {
        private let queue = LuxAnalyticsQueue.shared

        init() async {
            await LuxAnalyticsTestHelper.reset()
        }

        private func restoreDefaults() async {
            await queue.configure(
                maxSizeHard: LuxAnalyticsDefaults.maxQueueSizeHard,
                overflowStrategy: LuxAnalyticsDefaults.overflowStrategy,
                eventTTL: LuxAnalyticsDefaults.eventTTL)
            await queue.clear()
        }

        private func fill(_ names: [String]) async {
            for name in names {
                await queue.enqueue(makeLimitsEvent(name))
            }
        }

        private func queuedNames() async -> [String] {
            await queue.dequeue(limit: 1_000, now: Date()).map(\.event.name)
        }

        @Test func dropOldestKeepsTheNewestEvents() async {
            await queue.configure(maxSizeHard: 3, overflowStrategy: .dropOldest, eventTTL: 3_600)
            await fill(["a", "b", "c", "d", "e"])
            #expect(await queuedNames() == ["c", "d", "e"])
            await restoreDefaults()
        }

        @Test func dropNewestRejectsEventsOnceFull() async {
            await queue.configure(maxSizeHard: 3, overflowStrategy: .dropNewest, eventTTL: 3_600)
            await fill(["a", "b", "c", "d", "e"])
            #expect(await queuedNames() == ["a", "b", "c"])
            await restoreDefaults()
        }

        @Test func dropAllEmptiesTheQueueThenKeepsTheNewEvent() async {
            await queue.configure(maxSizeHard: 3, overflowStrategy: .dropAll, eventTTL: 3_600)
            await fill(["a", "b", "c", "d"])
            #expect(await queuedNames() == ["d"])
            await restoreDefaults()
        }

        @Test func overflowIsReportedWithTheStrategyUsed() async {
            await queue.configure(maxSizeHard: 2, overflowStrategy: .dropAll, eventTTL: 3_600)
            let stream = LuxAnalyticsEvents.eventStream
            await fill(["a", "b", "c"])
            let dropped = await firstDrop(in: stream)
            #expect(dropped?.count == 2)
            #expect(dropped?.reason == .dropAll)
            await restoreDefaults()
        }

        @Test func eventsPastTheConfiguredTTLAreNotSent() async throws {
            await queue.configure(maxSizeHard: 100, overflowStrategy: .dropOldest, eventTTL: 60)
            await fill(["fresh"])
            // Two minutes later, the 60-second TTL has passed.
            let later = Date().addingTimeInterval(120)
            #expect(await queue.dequeue(limit: 10, now: later).isEmpty)
            #expect(await queue.queueSize == 0)
            await restoreDefaults()
        }

        @Test func initializeAppliesTheConfiguredLimits() async throws {
            let config = try LuxAnalyticsConfiguration(
                dsn: "https://limits@test.example.com/api/v1/events/limits",
                autoFlushInterval: 3_600, maxQueueSizeHard: 2, overflowStrategy: .dropOldest)
            try await LuxAnalytics.initialize(with: config)
            await fill(["a", "b", "c"])
            #expect(await queue.queueSize == 2)
            await LuxAnalyticsTestHelper.reset()
            await restoreDefaults()
        }

        private func firstDrop(
            in stream: AsyncStream<AnalyticsEventNotification>
        ) async -> (count: Int, reason: QueueOverflowStrategy)? {
            await withTaskGroup(of: (count: Int, reason: QueueOverflowStrategy)?.self) { group in
                group.addTask {
                    for await notification in stream {
                        if case .eventsDropped(let count, let reason) = notification {
                            return (count, reason)
                        }
                    }
                    return nil
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(2))
                    return nil
                }
                let first = await group.next().flatMap { $0 }
                group.cancelAll()
                return first
            }
        }
    }
}

private func makeLimitsEvent(_ name: String) -> AnalyticsEvent {
    AnalyticsEvent(name: name, timestamp: "2026-01-01T00:00:00Z", userId: nil, sessionId: nil, metadata: [:])
}
