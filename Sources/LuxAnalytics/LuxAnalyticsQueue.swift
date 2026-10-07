import Foundation

/// Statistics about the event queue
public struct QueueStats: Sendable, Codable {
    public let totalEvents: Int
    public let totalSizeBytes: Int
    public let oldestEventAge: TimeInterval?
    public let newestEventAge: TimeInterval?
    public let failedBatchCount: Int
}

/// Actor-based queue for thread-safe event management with retry logic
public actor LuxAnalyticsQueue {
    public static let shared = LuxAnalyticsQueue()
    private let queueKey = "com.luxardolabs.LuxAnalytics.eventQueue.v2"
    private let userDefaults: UserDefaults
    
    /// In-memory cache of the queue
    private var queueCache: [QueuedEvent] = []
    
    /// Track failed batch IDs to prevent infinite retries
    private var failedBatchIds: Set<String> = []
    
    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        // Queue will be loaded on first access
        self.queueCache = []
        // Clean expired events on startup
        Task {
            await loadAndCleanQueue()
        }
    }
    
    private func loadAndCleanQueue() {
        self.queueCache = loadQueue() ?? []
        cleanExpiredEvents(ttlSeconds: LuxAnalyticsDefaults.eventTTL)
    }

    public var queueSize: Int {
        return queueCache.count
    }

    public func enqueue(_ event: AnalyticsEvent) {
        let queuedEvent = QueuedEvent(event: event)
        queueCache.append(queuedEvent)
        saveQueue()
    }
    
    public func enqueue(_ queuedEvent: QueuedEvent) {
        queueCache.append(queuedEvent)
        saveQueue()
    }
    
    /// Dequeue events for sending
    public func dequeue(limit: Int) -> [QueuedEvent] {
        let eventsToSend = Array(queueCache.prefix(limit))
        if !eventsToSend.isEmpty {
            queueCache.removeFirst(min(limit, queueCache.count))
            saveQueue()
        }
        return eventsToSend
    }

    // MARK: - Queue Management
    
    private func cleanExpiredEvents(ttlSeconds: TimeInterval) {
        let before = queueCache.count
        let expiredEvents = queueCache.filter { $0.isExpired(ttlSeconds: ttlSeconds) }.map { $0.event }
        queueCache = queueCache.filter { !$0.isExpired(ttlSeconds: ttlSeconds) }
        let after = queueCache.count
        
        if before != after {
            saveQueue()
            SecureLogger.log("Cleaned \(before - after) expired events from queue", category: .queue, level: .info)
            if !expiredEvents.isEmpty {
                Task {
                    for event in expiredEvents {
                        await LuxAnalyticsEvents.notifyEventExpired(event)
                    }
                }
            }
        }
    }
    
    private func handleQueueOverflow(strategy: QueueOverflowStrategy, maxQueueSizeHard: Int) {
        SecureLogger.log("Queue overflow: \(queueCache.count) events, applying strategy: \(strategy)", category: .queue, level: .warning)
        
        switch strategy {
        case .dropOldest:
            let toRemove = queueCache.count - maxQueueSizeHard + 1
            if toRemove > 0 {
                let droppedEvents = Array(queueCache.prefix(toRemove)).map { $0.event }
                queueCache.removeFirst(toRemove)
                Task {
                    for event in droppedEvents {
                        await LuxAnalyticsEvents.notifyEventDropped(event, reason: "Queue overflow - oldest dropped")
                    }
                }
            }
            
        case .dropNewest:
            // Don't add the new event (it will be dropped by the caller)
            break
            
        case .dropAll:
            let droppedEvents = queueCache.map { $0.event }
            queueCache.removeAll()
            Task {
                for event in droppedEvents {
                    await LuxAnalyticsEvents.notifyEventDropped(event, reason: "Queue overflow - all dropped")
                }
            }
        }
        
        saveQueue()
    }
    
    // MARK: - Persistence
    
    private func loadQueue() -> [QueuedEvent]? {
        // Try to load encrypted queue first
        if let encryptedData = userDefaults.data(forKey: queueKey),
           let decrypted = QueueEncryption.decrypt(encryptedData),
           let events = try? JSONDecoder().decode([QueuedEvent].self, from: decrypted) {
            return events
        }
        
        // Fall back to legacy unencrypted queue
        let legacyKey = "com.luxardolabs.LuxAnalytics.eventQueue"
        if let data = userDefaults.data(forKey: legacyKey),
           let events = try? JSONDecoder().decode([QueuedEvent].self, from: data) {
            // Migrate to encrypted storage
            saveQueue()
            userDefaults.removeObject(forKey: legacyKey)
            return events
        }
        
        return nil
    }
    
    private func saveQueue() {
        do {
            let data = try JSONEncoder().encode(queueCache)
            if let encrypted = QueueEncryption.encrypt(data) {
                userDefaults.set(encrypted, forKey: queueKey)
            }
        } catch {
            SecureLogger.log("Failed to save queue: \(error)", category: .queue, level: .error)
        }
    }
    
    // MARK: - Public API
    
    public func getQueueStats() -> QueueStats {
        let now = Date()
        let oldestEvent = queueCache.first
        let newestEvent = queueCache.last
        let oldestEventAge = oldestEvent.map { now.timeIntervalSince($0.queuedAt) }
        let newestEventAge = newestEvent.map { now.timeIntervalSince($0.queuedAt) }
        
        _ = queueCache.filter { queuedEvent in
            queuedEvent.retryCount < LuxAnalyticsDefaults.maxRetryAttempts
        }
        _ = queueCache.filter { queuedEvent in
            queuedEvent.isExpired(ttlSeconds: LuxAnalyticsDefaults.eventTTL)
        }
        
        // Calculate total size
        let totalSizeBytes = queueCache.reduce(0) { total, event in
            total + ((try? JSONEncoder().encode(event).count) ?? 0)
        }
        
        return QueueStats(
            totalEvents: queueCache.count,
            totalSizeBytes: totalSizeBytes,
            oldestEventAge: oldestEventAge,
            newestEventAge: newestEventAge,
            failedBatchCount: failedBatchIds.count
        )
    }
    
    public func clear() {
        queueCache.removeAll()
        saveQueue()
        SecureLogger.log("Queue cleared", category: .queue, level: .info)
    }
}