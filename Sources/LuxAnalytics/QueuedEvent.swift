import Foundation

/// Wrapper for queued events with metadata for retry and TTL management
struct QueuedEvent: Codable, Sendable {
    let event: AnalyticsEvent
    let queuedAt: Date
    var retryCount: Int
    var lastRetryAt: Date?
    var lastAttemptAt: Date?
    /// Earliest time this event may be sent again, after a failed attempt.
    /// Nil for an event that has never failed. Decodes as nil from queues
    /// persisted before this field existed.
    var notBefore: Date?

    init(event: AnalyticsEvent) {
        self.event = event
        self.queuedAt = Date()
        self.retryCount = 0
        self.lastRetryAt = nil
        self.lastAttemptAt = nil
        self.notBefore = nil
    }

    /// Check if event has expired based on TTL
    func isExpired(ttlSeconds: TimeInterval) -> Bool {
        return Date().timeIntervalSince(queuedAt) > ttlSeconds
    }

    /// Calculate next retry delay using exponential backoff with jitter
    func nextRetryDelay() -> TimeInterval {
        let baseDelay = 2.0
        let maxDelay = 300.0  // 5 minutes max

        // Exponential backoff: 2^retryCount seconds
        let exponentialDelay = min(pow(baseDelay, Double(retryCount)), maxDelay)

        // Add jitter (±25%) to prevent thundering herd
        let jitter = exponentialDelay * 0.25
        let randomJitter = Double.random(in: -jitter...jitter)

        return exponentialDelay + randomJitter
    }

    /// Whether the event has attempts left. Timing is not checked here: the queue
    /// holds a backed-off event until `notBefore` (see `isReady(at:)`).
    func shouldRetry(maxRetries: Int) -> Bool {
        retryCount < maxRetries
    }

    /// Whether the event's backoff has elapsed.
    func isReady(at now: Date) -> Bool {
        guard let notBefore else { return true }
        return now >= notBefore
    }

    /// Record a failed send: count the attempt and schedule the next one with
    /// exponential backoff. The jittered delay is computed once, here, so a later
    /// check doesn't roll a different delay.
    mutating func recordFailedAttempt(at now: Date = Date()) {
        retryCount += 1
        lastAttemptAt = now
        lastRetryAt = now
        notBefore = now.addingTimeInterval(nextRetryDelay())
    }
}
