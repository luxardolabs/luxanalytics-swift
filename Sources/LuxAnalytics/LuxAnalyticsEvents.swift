import Foundation
import Synchronization

/// Modern async event stream for monitoring analytics events
public struct LuxAnalyticsEvents: Sendable {

    /// Stream of analytics events as they occur
    public static var eventStream: AsyncStream<AnalyticsEventNotification> {
        AsyncStream { continuation in
            let observer = EventObserver { notification in
                continuation.yield(notification)
            }

            // Register synchronously before returning the stream so events emitted
            // immediately after subscription aren't lost to an actor-hop gap.
            EventManager.shared.addObserver(observer)

            continuation.onTermination = { _ in
                EventManager.shared.removeObserver(observer)
            }
        }
    }
}

/// Notification types for analytics events
public enum AnalyticsEventNotification: Sendable {
    case eventQueued(AnalyticsEvent)
    case eventsSent([AnalyticsEvent])
    case eventsFailed([AnalyticsEvent], error: LuxAnalyticsError)
    case eventsDropped(count: Int, reason: QueueOverflowStrategy)
    case eventsExpired([AnalyticsEvent])
}

/// Internal event manager
///
/// Backed by a Mutex (not an actor) so observer registration and notification
/// are synchronous — this closes the subscription race in `eventStream` where
/// events emitted before an async `addObserver` completed would be dropped.
final class EventManager: Sendable {
    static let shared = EventManager()

    private let observers = Mutex<[EventObserver]>([])

    func addObserver(_ observer: EventObserver) {
        observers.withLock { $0.append(observer) }
    }

    func removeObserver(_ observer: EventObserver) {
        observers.withLock { $0.removeAll { $0.id == observer.id } }
    }

    func notify(_ notification: AnalyticsEventNotification) {
        // Copy under the lock, then call handlers outside it to avoid
        // re-entrancy if a handler touches the manager.
        let current = observers.withLock { $0 }
        for observer in current {
            observer.handler(notification)
        }
    }
}

/// Internal observer wrapper
final class EventObserver: Sendable {
    let id = UUID()
    let handler: @Sendable (AnalyticsEventNotification) -> Void
    
    init(handler: @escaping @Sendable (AnalyticsEventNotification) -> Void) {
        self.handler = handler
    }
}

/// Extension for internal notifications from LuxAnalytics
extension LuxAnalyticsEvents {
    internal static let shared = LuxAnalyticsEvents()
    
    func notifyQueued(_ event: AnalyticsEvent) async {
        EventManager.shared.notify(.eventQueued(event))
    }
    
    func notifySent(_ event: AnalyticsEvent) async {
        EventManager.shared.notify(.eventsSent([event]))
    }
    
    func notifyFailed(_ event: AnalyticsEvent, error: Error) async {
        let luxError = error as? LuxAnalyticsError ?? .networkError(error)
        EventManager.shared.notify(.eventsFailed([event], error: luxError))
    }
    
    func notifyDropped(_ event: AnalyticsEvent, reason: String) async {
        // Convert reason to overflow strategy (default to dropOldest)
        EventManager.shared.notify(.eventsDropped(count: 1, reason: .dropOldest))
    }
    
    func notifyExpired(_ event: AnalyticsEvent) async {
        EventManager.shared.notify(.eventsExpired([event]))
    }
}

/// Public API for event notifications
extension LuxAnalytics {
    
    /// Monitor analytics events using async/await
    /// 
    /// Example:
    /// ```swift
    /// Task {
    ///     for await event in LuxAnalyticsEvents.eventStream {
    ///         switch event {
    ///         case .eventQueued(let event):
    ///             print("Event queued: \(event.name)")
    ///         case .eventsSent(let events):
    ///             print("Sent \(events.count) events")
    ///         default:
    ///             break
    ///         }
    ///     }
    /// }
    /// ```
    public static func notifyEventQueued(_ event: AnalyticsEvent) async {
        EventManager.shared.notify(.eventQueued(event))
    }
    
    public static func notifyEventsSent(_ events: [AnalyticsEvent]) async {
        EventManager.shared.notify(.eventsSent(events))
    }
    
    public static func notifyEventsFailed(_ events: [AnalyticsEvent], error: LuxAnalyticsError) async {
        EventManager.shared.notify(.eventsFailed(events, error: error))
    }
    
    public static func notifyEventsDropped(count: Int, reason: QueueOverflowStrategy) async {
        EventManager.shared.notify(.eventsDropped(count: count, reason: reason))
    }
    
    public static func notifyEventsExpired(_ events: [AnalyticsEvent]) async {
        EventManager.shared.notify(.eventsExpired(events))
    }
}

// MARK: - Single Event Convenience Methods
extension LuxAnalyticsEvents {
    /// Convenience method for single event drop notification
    public static func notifyEventDropped(_ event: AnalyticsEvent, reason: String) async {
        EventManager.shared.notify(.eventsDropped(count: 1, reason: .dropOldest))
    }
    
    /// Convenience method for single event expiry notification
    public static func notifyEventExpired(_ event: AnalyticsEvent) async {
        EventManager.shared.notify(.eventsExpired([event]))
    }
}