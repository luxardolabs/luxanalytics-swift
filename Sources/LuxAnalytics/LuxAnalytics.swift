import Foundation
import zlib

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
                    See: https://github.com/luxardolabs/luxanalytics-swift/blob/main/docs/TROUBLESHOOTING.md#the-app-crashes-at-startup-in-luxanalyticsshared

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
        await LuxAnalyticsQueue.shared.configure(
            maxSizeHard: configuration.maxQueueSizeHard,
            overflowStrategy: configuration.overflowStrategy,
            eventTTL: configuration.eventTTL)
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
        if await GlobalCircuitBreaker.shared.isDeferred(for: config.apiURL) {
            await instance.analyticsActor.debugLog("Server asked to back off from \(config.apiURL), skipping flush")
            return
        }

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

        let started = Date()
        await instance.sendBatch(eventsToSend)
        await LuxAnalyticsDiagnostics.shared.recordFlushDuration(Date().timeIntervalSince(started))
    }

    // MARK: - Device Identity

    /// Replace this device's analytics ID with a new random one.
    ///
    /// The device ID lives in the Keychain, so by default it survives the app being
    /// deleted and reinstalled. Call this when the user should get a fresh identity,
    /// for example after they withdraw analytics consent or ask to reset their data.
    /// Events already queued keep the old ID; events tracked afterwards carry the new one.
    public static func resetDeviceID() async {
        await AppAnalyticsContext.shared.resetDeviceID()
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
            let (payload, deflated) = try await preparePayload(events, config: config)
            let response = try await NetworkTransport.send(payload, deflated: deflated, config: config)
            let statusCode = response.statusCode
            let body = response.body
            if let retryAfter = response.retryAfter {
                await GlobalCircuitBreaker.shared.deferRequests(
                    for: config.apiURL, until: Date().addingTimeInterval(retryAfter))
            }
            switch Self.outcome(forStatus: statusCode) {
            case .sent:
                await handleSent(events, config: config)
            case .rateLimited:
                // The server is up and asked us to slow down: keep the events, and
                // don't count it against the circuit breaker.
                let error = Self.serverError(statusCode: statusCode, body: body)
                await analyticsActor.debugLog("Rate limited: \(error)")
                await handleRetryableFailure(events, error: error, cause: error, config: config, tripsBreaker: false)
            case .retry:
                let error = Self.serverError(statusCode: statusCode, body: body)
                await analyticsActor.debugLog("Retryable server response: \(error)")
                await handleRetryableFailure(events, error: error, cause: error, config: config)
            case .drop:
                // A retry would fail the same way, so the events are dropped.
                let error = Self.serverError(statusCode: statusCode, body: body)
                await analyticsActor.debugLog("Client error: \(error)")
                for queuedEvent in events {
                    await LuxAnalytics.notifyEventsFailed([queuedEvent.event], error: error)
                }
                await LuxAnalyticsDiagnostics.shared.recordEventsFailed(count: events.count, error: error)
                await LuxAnalyticsDiagnostics.shared.recordBatchFailed()
            }
        } catch {
            await analyticsActor.debugLog("Failed to send batch: \(error)")
            let luxError = (error as? LuxAnalyticsError) ?? .networkError(error)
            await handleRetryableFailure(events, error: luxError, cause: error, config: config)
        }
    }

    /// What a batch's HTTP status means for its events.
    enum SendOutcome: Equatable {
        /// 2xx: delivered.
        case sent
        /// 429: rate limited. Requeue without tripping the circuit breaker.
        case rateLimited
        /// 408 or any 5xx (and anything unrecognised): requeue, and count it against the breaker.
        case retry
        /// Any other 4xx: the request itself is wrong (400, 401, 404, 422), so retrying can't help.
        case drop
    }

    static func outcome(forStatus statusCode: Int) -> SendOutcome {
        switch statusCode {
        case 200...299: .sent
        case 429: .rateLimited
        case 408: .retry
        case 400...499: .drop
        default: .retry
        }
    }

    /// Encode the batch and compress it when it's over the threshold, recording its
    /// size and the compression time in the diagnostics.
    private func preparePayload(
        _ events: [QueuedEvent],
        config: LuxAnalyticsConfiguration
    ) async throws -> (payload: Data, deflated: Bool) {
        let json = try Self.encodePayload(events)
        guard config.compressionEnabled && json.count >= config.compressionThreshold else {
            await LuxAnalyticsDiagnostics.shared.recordPayloadSize(json.count, compressedSize: nil)
            return (json, false)
        }
        let started = Date()
        let compressed = try Self.deflate(json)
        await LuxAnalyticsDiagnostics.shared.recordCompressionTime(Date().timeIntervalSince(started))
        await LuxAnalyticsDiagnostics.shared.recordPayloadSize(json.count, compressedSize: compressed.count)
        await analyticsActor.debugLog("Compressed payload: \(json.count) -> \(compressed.count) bytes")
        return (compressed, true)
    }

    private func handleSent(_ events: [QueuedEvent], config: LuxAnalyticsConfiguration) async {
        await analyticsActor.debugLog("Successfully sent \(events.count) events")
        await GlobalCircuitBreaker.shared.recordSuccess(for: config.apiURL)
        for queuedEvent in events {
            await LuxAnalytics.notifyEventsSent([queuedEvent.event])
        }
        await LuxAnalyticsDiagnostics.shared.recordEventsSent(count: events.count)
        await LuxAnalyticsDiagnostics.shared.recordBatchSent()
    }

    /// A 5xx, 408, 429 or transport failure: report it and requeue every event that
    /// still has retries left. Everything but a rate limit also counts against the
    /// circuit breaker.
    private func handleRetryableFailure(
        _ events: [QueuedEvent],
        error: LuxAnalyticsError,
        cause: any Error,
        config: LuxAnalyticsConfiguration,
        tripsBreaker: Bool = true
    ) async {
        if tripsBreaker {
            await GlobalCircuitBreaker.shared.recordFailure(for: config.apiURL)
        }
        for queuedEvent in events {
            await LuxAnalytics.notifyEventsFailed([queuedEvent.event], error: error)
        }
        for queuedEvent in events {
            guard queuedEvent.shouldRetry(maxRetries: config.maxRetryAttempts) else {
                await LuxAnalytics.notifyEventsDropped(count: 1, reason: .dropOldest)
                continue
            }
            var retry = queuedEvent
            retry.recordFailedAttempt()
            await LuxAnalyticsQueue.shared.enqueue(retry)
        }
        await LuxAnalyticsDiagnostics.shared.recordEventsFailed(count: events.count, error: cause)
        await LuxAnalyticsDiagnostics.shared.recordBatchFailed()
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
    /// zlib format (RFC 1950): what HTTP `Content-Encoding: deflate` means (RFC 9110 §8.4.1.2).
    ///
    /// Uses the system zlib, not the Compression framework: its COMPRESSION_ZLIB
    /// writes raw DEFLATE (RFC 1951) with no zlib wrapper, which doesn't match the header.
    func zlibCompressed() -> Data? {
        guard !isEmpty else { return nil }
        var compressedSize = compressBound(uLong(count))
        var destination = Data(count: Int(compressedSize))

        let status = destination.withUnsafeMutableBytes { output -> Int32 in
            withUnsafeBytes { input -> Int32 in
                guard let target = output.bindMemory(to: Bytef.self).baseAddress,
                    let source = input.bindMemory(to: Bytef.self).baseAddress
                else { return Z_BUF_ERROR }
                return compress2(target, &compressedSize, source, uLong(count), Z_DEFAULT_COMPRESSION)
            }
        }
        guard status == Z_OK else { return nil }
        destination.count = Int(compressedSize)
        return destination
    }
}
