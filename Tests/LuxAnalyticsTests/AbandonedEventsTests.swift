import Foundation
import Testing

@testable import LuxAnalytics

extension GlobalStateTests {
    /// An event that runs out of retries is reported as eventsAbandoned, not as a queue
    /// overflow. Uses a real connection failure: nothing listens on 127.0.0.1:9.
    @Suite(.serialized)
    struct AbandonedEventsTests {
        @Test func anEventOutOfRetriesIsAbandonedWithTheLastError() async throws {
            await LuxAnalyticsTestHelper.reset()
            let config = try LuxAnalyticsConfiguration(
                dsn: "https://abandon-test@127.0.0.1:9/api/v1/events/abandon",
                autoFlushInterval: 3_600, maxRetryAttempts: 0)
            try await LuxAnalytics.initialize(with: config)
            defer { Task { await LuxAnalyticsTestHelper.reset() } }

            let stream = LuxAnalyticsEvents.eventStream
            try await LuxAnalytics.shared.track("doomed")
            await LuxAnalytics.flush()

            let outcome = await firstOutcome(in: stream)
            guard case .abandoned(let names, let error) = outcome else {
                Issue.record("expected eventsAbandoned, got \(String(describing: outcome))")
                return
            }
            #expect(names == ["doomed"])
            guard case .networkError = error else {
                Issue.record("expected a networkError, got \(error)")
                return
            }
            #expect(await LuxAnalyticsQueue.shared.queueSize == 0)
        }

        private enum Outcome {
            case abandoned([String], LuxAnalyticsError)
            case dropped(QueueOverflowStrategy)
        }

        /// The first abandon or drop notification, or nil after 5 seconds.
        private func firstOutcome(in stream: AsyncStream<AnalyticsEventNotification>) async -> Outcome? {
            await withTaskGroup(of: Outcome?.self) { group in
                group.addTask {
                    for await notification in stream {
                        switch notification {
                        case .eventsAbandoned(let events, let lastError):
                            return .abandoned(events.map(\.name), lastError)
                        case .eventsDropped(_, let reason):
                            return .dropped(reason)
                        default:
                            continue
                        }
                    }
                    return nil
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(5))
                    return nil
                }
                let first = await group.next().flatMap { $0 }
                group.cancelAll()
                return first
            }
        }
    }
}
