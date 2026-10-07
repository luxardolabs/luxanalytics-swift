import Compression
import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Main analytics tracking class
/// This class must be initialized with a configuration before use
public final class LuxAnalytics: Sendable {
    private let analyticsActor: AnalyticsActor
    private let configuration: LuxAnalyticsConfiguration

    /// Shared instance - only available after initialization
    /// Note: This is now an async property due to actor-based storage
    public static var shared: LuxAnalytics {
        get async {
            guard let instance = await LuxAnalyticsStorage.shared.getInstance() else {
                // Provide helpful debugging info
                let callStack = Thread.callStackSymbols.prefix(10).joined(separator: "\n")
                fatalError(
                    """

                    ⚠️ LuxAnalytics.initialize() must be called before accessing shared instance.

                    This usually happens when:
                    1. A view model's initializer uses LuxAnalytics
                    2. A static property initializes before your App.init()
                    3. A singleton's init() method tracks analytics

                    Fix: Move LuxAnalytics.initialize() earlier in your app lifecycle.
                    See: https://github.com/luxardolabs/luxanalytics-swift#initialization-order

                    Call stack:
                    \(callStack)
                    """)
            }
            return instance
        }
    }

    /// Internal access for extensions
    internal static var _shared: LuxAnalytics? {
        get async {
            return await LuxAnalyticsStorage.shared.getInstance()
        }
    }

    /// Initialize LuxAnalytics with configuration
    /// - Parameter configuration: The analytics configuration
    /// - Throws: Throws if already initialized
    public static func initialize(with configuration: LuxAnalyticsConfiguration) async throws {
        guard await !LuxAnalyticsStorage.shared.isInitialized() else {
            throw LuxAnalyticsError.alreadyInitialized
        }

        // Update debug logging flag synchronously
        SecureLogger.updateDebugLogging(configuration.debugLogging)

        await LuxAnalyticsStorage.shared.setConfiguration(configuration)
        let instance = LuxAnalytics(configuration: configuration)
        await LuxAnalyticsStorage.shared.setInstance(instance)

        // Setup after storing instance
        await instance.analyticsActor.setupAutoFlush()
        await instance.analyticsActor.setupAppLifecycleObservers()
    }

    /// Check if LuxAnalytics is initialized
    public static var isInitialized: Bool {
        get async {
            return await LuxAnalyticsStorage.shared.isInitialized()
        }
    }

    private init(configuration: LuxAnalyticsConfiguration) {
        self.configuration = configuration
        self.analyticsActor = AnalyticsActor(configuration: configuration)
    }

    deinit {
        // Cleanup is handled by the actor's own lifecycle
        SecureLogger.log("LuxAnalytics instance deinit", category: .general, level: .debug)
    }

    // MARK: - Public API

    public func setUser(_ userId: String?) async {
        await analyticsActor.setUser(userId)
    }

    public func setSession(_ sessionId: String?) async {
        await analyticsActor.setSession(sessionId)
    }

    public func track(_ name: String, metadata: [String: String] = [:]) async throws {
        guard await AnalyticsSettings.shared.isEnabled else {
            await analyticsActor.debugLog("Analytics disabled, skipping event: \(name)")
            throw LuxAnalyticsError.analyticsDisabled
        }

        guard let config = await LuxAnalyticsStorage.shared.getConfiguration() else {
            await analyticsActor.debugLog("No configuration set, skipping event: \(name)")
            throw LuxAnalyticsError.notInitialized
        }

        var merged = await AppAnalyticsContext.shared.current()
        metadata.forEach { merged[$0] = $1 }

        let event = AnalyticsEvent(
            name: name,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            userId: await analyticsActor.getUserId(),
            sessionId: await analyticsActor.getSessionId(),
            metadata: merged
        )

        await analyticsActor.debugLog("Tracking event: \(name) - queuing for batch")

        // Always queue events for batching - never send immediately
        await LuxAnalyticsQueue.shared.enqueue(event)

        // Notify via async stream
        await LuxAnalytics.notifyEventQueued(event)

        // Auto-flush if queue is getting full
        if await LuxAnalyticsQueue.shared.queueSize >= config.maxQueueSize {
            await analyticsActor.debugLog("Queue size reached max, flushing batch")
            await Self.flush()
        }
    }

    // MARK: - Flush Methods

    /// Manually flush queued events to the server
    public static func flush() async {
        guard let instance = await _shared else { return }
        guard await AnalyticsSettings.shared.isEnabled else { return }
        guard let config = await LuxAnalyticsStorage.shared.getConfiguration() else { return }

        await instance.analyticsActor.debugLog("Starting flush...")

        // Check network connectivity first
        guard await NetworkMonitor.shared.isConnected else {
            await instance.analyticsActor.debugLog("No network connection, skipping flush")
            return
        }

        // Don't flush if circuit breaker is open for this endpoint
        if await GlobalCircuitBreaker.shared.isOpen(for: config.apiURL) {
            await instance.analyticsActor.debugLog("Circuit breaker open for \(config.apiURL), skipping flush")
            return
        }

        let eventsToSend = await LuxAnalyticsQueue.shared.dequeue(limit: config.batchSize)
        guard !eventsToSend.isEmpty else {
            await instance.analyticsActor.debugLog("No events to flush")
            return
        }

        await instance.analyticsActor.debugLog("Flushing \(eventsToSend.count) events...")

        await instance.sendBatch(eventsToSend)
    }

    // MARK: - Clear Queue

    public static func clearQueue() async {
        await LuxAnalyticsQueue.shared.clear()
    }

    // MARK: - Network Management

    public static func isNetworkAvailable() async -> Bool {
        return await NetworkMonitor.shared.isConnected
    }

    // MARK: - Queue Stats

    public static func getQueueStats() async -> QueueStats {
        return await LuxAnalyticsQueue.shared.getQueueStats()
    }

    // MARK: - Health Check
    public static func healthCheck() async -> Bool {
        guard await isInitialized else { return false }
        guard let config = await LuxAnalyticsStorage.shared.getConfiguration() else { return false }

        // Basic connectivity check
        let isConnected = await NetworkMonitor.shared.isConnected
        let circuitBreakerOpen = await GlobalCircuitBreaker.shared.isOpen(for: config.apiURL)

        return isConnected && !circuitBreakerOpen
    }
}

// MARK: - Batch Sending

extension LuxAnalytics {
    /// The batch wire shape, `{"events": [...]}`. A single event is sent bare.
    struct BatchPayload: Encodable {
        let events: [AnalyticsEvent]
    }

    private func sendBatch(_ events: [QueuedEvent]) async {
        guard let config = await LuxAnalyticsStorage.shared.getConfiguration() else { return }

        do {
            let json = try Self.encodePayload(events)
            let deflated = config.compressionEnabled && json.count >= config.compressionThreshold
            let payload = deflated ? try Self.deflate(json) : json
            if deflated {
                await analyticsActor.debugLog("Compressed payload: \(json.count) -> \(payload.count) bytes")
            }

            let (statusCode, body) = try await NetworkTransport.send(payload, deflated: deflated, config: config)
            switch statusCode {
            case 200...299:
                await handleSent(events, bytes: payload.count, config: config)
            case 400...499:
                // Client error: a retry would fail the same way, so the events are dropped.
                let error = Self.serverError(statusCode: statusCode, body: body)
                await analyticsActor.debugLog("Client error: \(error)")
                for queuedEvent in events {
                    await LuxAnalytics.notifyEventsFailed([queuedEvent.event], error: error)
                }
                await LuxAnalyticsDiagnostics.shared.recordEventsFailed(count: events.count, error: error)
            default:
                let error = Self.serverError(statusCode: statusCode, body: body)
                await analyticsActor.debugLog("Server error: \(error)")
                await handleRetryableFailure(events, error: error, cause: error, config: config)
            }
        } catch {
            await analyticsActor.debugLog("Failed to send batch: \(error)")
            let luxError = (error as? LuxAnalyticsError) ?? .networkError(error)
            await handleRetryableFailure(events, error: luxError, cause: error, config: config)
        }
    }

    private func handleSent(_ events: [QueuedEvent], bytes: Int, config: LuxAnalyticsConfiguration) async {
        await analyticsActor.debugLog("Successfully sent \(events.count) events")
        await GlobalCircuitBreaker.shared.recordSuccess(for: config.apiURL)
        for queuedEvent in events {
            await LuxAnalytics.notifyEventsSent([queuedEvent.event])
        }
        await LuxAnalyticsDiagnostics.shared.recordEventsSent(count: events.count)
        await LuxAnalyticsDiagnostics.shared.recordBytesTransmitted(bytes: bytes)
    }

    /// A 5xx or a transport failure: count it against the circuit breaker, report it,
    /// and requeue every event that still has retries left.
    private func handleRetryableFailure(
        _ events: [QueuedEvent],
        error: LuxAnalyticsError,
        cause: any Error,
        config: LuxAnalyticsConfiguration
    ) async {
        await GlobalCircuitBreaker.shared.recordFailure(for: config.apiURL)
        for queuedEvent in events {
            await LuxAnalytics.notifyEventsFailed([queuedEvent.event], error: error)
        }
        for queuedEvent in events {
            guard queuedEvent.shouldRetry(maxRetries: config.maxRetryAttempts) else {
                await LuxAnalytics.notifyEventsDropped(count: 1, reason: .dropOldest)
                continue
            }
            var retry = queuedEvent
            retry.retryCount += 1
            retry.lastAttemptAt = Date()
            await LuxAnalyticsQueue.shared.enqueue(retry)
        }
        await LuxAnalyticsDiagnostics.shared.recordEventsFailed(count: events.count, error: cause)
    }

    /// The request body: one event bare, several wrapped as `{"events": [...]}`.
    static func encodePayload(_ events: [QueuedEvent]) throws -> Data {
        if events.count == 1 {
            return try JSONCoders.wireEncoder.encode(events[0].event)
        }
        return try JSONCoders.wireEncoder.encode(BatchPayload(events: events.map(\.event)))
    }

    private static func deflate(_ json: Data) throws -> Data {
        guard let compressed = json.zlibCompressed() else {
            let reason = [NSLocalizedDescriptionKey: "Compression failed"]
            throw LuxAnalyticsError.encodingError(NSError(domain: "LuxAnalytics", code: -1, userInfo: reason))
        }
        return compressed
    }

    /// Redacts the response body before it enters the public error: it can reach
    /// SDK consumers via eventsFailed and may contain PII.
    private static func serverError(statusCode: Int, body: Data) -> LuxAnalyticsError {
        let response = String(data: body, encoding: .utf8).map(SecureLogger.redact)
        return .serverError(statusCode: statusCode, response: response)
    }
}

// MARK: - Compression

extension Data {
    /// Raw DEFLATE (RFC 1951). Apple's COMPRESSION_ZLIB writes no zlib header,
    /// so the server inflates it with its raw-deflate fallback.
    func zlibCompressed() -> Data? {
        guard !isEmpty else { return nil }
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        defer { destination.deallocate() }

        let compressedSize = withUnsafeBytes { source -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(destination, count, base, count, nil, COMPRESSION_ZLIB)
        }
        guard compressedSize > 0 else { return nil }
        return Data(bytes: destination, count: compressedSize)
    }
}
