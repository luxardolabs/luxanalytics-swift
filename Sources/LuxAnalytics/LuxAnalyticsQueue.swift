import Foundation

/// Statistics about the event queue
public struct QueueStats: Sendable, Codable {
    public let totalEvents: Int
    public let totalSizeBytes: Int
    public let oldestEventAge: TimeInterval?
    public let newestEventAge: TimeInterval?
    /// Queued events that have failed at least once and are waiting to be retried.
    public let retryingEvents: Int
}

/// Actor-based queue for thread-safe event management with retry logic
actor LuxAnalyticsQueue {
    static let shared = LuxAnalyticsQueue()
    private let queueKey = "com.luxardolabs.LuxAnalytics.eventQueue.v2"
    private let userDefaults: UserDefaults

    /// In-memory cache of the queue. Read it through `events`, which loads the
    /// persisted queue first.
    private var queueCache: [QueuedEvent] = []
    private var isLoaded = false

    /// Limits from the active configuration (see `configure(maxSizeHard:overflowStrategy:eventTTL:)`).
    private var maxSizeHard = LuxAnalyticsDefaults.maxQueueSizeHard
    private var overflowStrategy = LuxAnalyticsDefaults.overflowStrategy
    private var eventTTL = LuxAnalyticsDefaults.eventTTL

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// The queue, loading the persisted events on first use. Loading lazily (rather
    /// than in a Task started from init) means an enqueue can never run before the
    /// load and overwrite the previous session's events.
    private var events: [QueuedEvent] {
        get {
            if !isLoaded {
                isLoaded = true
                queueCache = (loadQueue() ?? []) + queueCache
            }
            return queueCache
        }
        set {
            isLoaded = true
            queueCache = newValue
        }
    }

    /// Apply the configuration's queue limits, and drop anything already past its TTL.
    func configure(maxSizeHard: Int, overflowStrategy: QueueOverflowStrategy, eventTTL: TimeInterval) {
        self.maxSizeHard = max(1, maxSizeHard)
        self.overflowStrategy = overflowStrategy
        self.eventTTL = eventTTL
        cleanExpiredEvents()
    }

    var queueSize: Int {
        return events.count
    }

    func enqueue(_ event: AnalyticsEvent) {
        enqueue(QueuedEvent(event: event))
    }

    /// Append an event, applying the overflow strategy when the queue is at its hard limit.
    func enqueue(_ queuedEvent: QueuedEvent) {
        guard makeRoom() else {
            notifyDropped(1, reason: .dropNewest)
            return
        }
        events.append(queuedEvent)
        saveQueue()
    }

    /// Dequeue up to `limit` events that are ready to send, in queue order.
    /// Events still inside their retry backoff stay queued.
    func dequeue(limit: Int) -> [QueuedEvent] {
        dequeue(limit: limit, now: Date())
    }

    func dequeue(limit: Int, now: Date) -> [QueuedEvent] {
        cleanExpiredEvents(now: now)
        var eventsToSend: [QueuedEvent] = []
        var remaining: [QueuedEvent] = []
        for queuedEvent in events {
            if eventsToSend.count < limit && queuedEvent.isReady(at: now) {
                eventsToSend.append(queuedEvent)
            } else {
                remaining.append(queuedEvent)
            }
        }
        if !eventsToSend.isEmpty {
            events = remaining
            saveQueue()
        }
        return eventsToSend
    }

    // MARK: - Queue Management

    /// Drop events older than the configured TTL and report them as expired.
    private func cleanExpiredEvents(now: Date = Date()) {
        let expired = events.filter { now.timeIntervalSince($0.queuedAt) > eventTTL }
        guard !expired.isEmpty else { return }
        events.removeAll { now.timeIntervalSince($0.queuedAt) > eventTTL }
        saveQueue()
        SecureLogger.log("Dropped \(expired.count) expired events from the queue", category: .queue, level: .info)
        let expiredEvents = expired.map(\.event)
        Task { await LuxAnalytics.notifyEventsExpired(expiredEvents) }
    }

    /// Make room for one more event under the hard limit.
    /// - Returns: false when the strategy is `.dropNewest` and the new event should be dropped.
    private func makeRoom() -> Bool {
        guard events.count >= maxSizeHard else { return true }
        SecureLogger.log(
            "Queue at its limit (\(maxSizeHard) events), applying \(overflowStrategy)", category: .queue, level: .warning)
        switch overflowStrategy {
        case .dropNewest:
            return false
        case .dropOldest:
            let toRemove = events.count - maxSizeHard + 1
            events.removeFirst(toRemove)
            notifyDropped(toRemove, reason: .dropOldest)
        case .dropAll:
            let toRemove = events.count
            events.removeAll()
            notifyDropped(toRemove, reason: .dropAll)
        }
        return true
    }

    private func notifyDropped(_ count: Int, reason: QueueOverflowStrategy) {
        Task { await LuxAnalytics.notifyEventsDropped(count: count, reason: reason) }
    }

    // MARK: - Persistence

    private func loadQueue() -> [QueuedEvent]? {
        // Try to load encrypted queue first
        if let encryptedData = userDefaults.data(forKey: queueKey),
            let decrypted = QueueEncryption.decrypt(encryptedData),
            let events = try? JSONDecoder().decode([QueuedEvent].self, from: decrypted)
        {
            return events
        }

        // Fall back to legacy unencrypted queue
        let legacyKey = "com.luxardolabs.LuxAnalytics.eventQueue"
        if let data = userDefaults.data(forKey: legacyKey),
            let events = try? JSONDecoder().decode([QueuedEvent].self, from: data)
        {
            // Migrate to encrypted storage
            saveQueue()
            userDefaults.removeObject(forKey: legacyKey)
            return events
        }

        return nil
    }

    private func saveQueue() {
        do {
            let data = try JSONEncoder().encode(events)
            if let encrypted = QueueEncryption.encrypt(data) {
                userDefaults.set(encrypted, forKey: queueKey)
            }
        } catch {
            SecureLogger.log("Failed to save queue: \(error)", category: .queue, level: .error)
        }
    }

    // MARK: - Public API

    func getQueueStats() -> QueueStats {
        let now = Date()
        let queued = events
        let oldestEvent = queued.first
        let newestEvent = queued.last
        let oldestEventAge = oldestEvent.map { now.timeIntervalSince($0.queuedAt) }
        let newestEventAge = newestEvent.map { now.timeIntervalSince($0.queuedAt) }

        // Calculate total size
        let totalSizeBytes = queued.reduce(0) { total, event in
            total + ((try? JSONEncoder().encode(event).count) ?? 0)
        }

        return QueueStats(
            totalEvents: queued.count,
            totalSizeBytes: totalSizeBytes,
            oldestEventAge: oldestEventAge,
            newestEventAge: newestEventAge,
            retryingEvents: queued.filter { $0.retryCount > 0 }.count
        )
    }

    func clear() {
        events.removeAll()
        saveQueue()
        SecureLogger.log("Queue cleared", category: .queue, level: .info)
    }
}
