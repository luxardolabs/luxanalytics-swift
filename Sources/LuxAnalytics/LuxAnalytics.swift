import Foundation
import Compression
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
                fatalError("""
                    
                    ⚠️ LuxAnalytics.initialize() must be called before accessing shared instance.
                    
                    This usually happens when:
                    1. A @StateObject initializer uses LuxAnalytics
                    2. A static property initializes before your App.init()
                    3. A singleton's init() method tracks analytics
                    
                    Fix: Move LuxAnalytics.initialize() earlier in your app lifecycle.
                    See: https://github.com/luxardolabs/LuxAnalytics#initialization-order
                    
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
        
        let urlSession = URLSession.analyticsSession(with: config.certificatePinning)
        await instance.sendBatch(eventsToSend, using: urlSession)
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

// MARK: - Event Stream Notifications


// MARK: - Batch Sending

extension LuxAnalytics {
    
    private func sendBatch(_ events: [QueuedEvent], using session: URLSession) async {
        guard let config = await LuxAnalyticsStorage.shared.getConfiguration() else { return }
        
        do {
            // Prepare the payload
            let batchPayload: [String: Any]
            if events.count == 1 {
                // Single event - send as is
                batchPayload = try events[0].event.toDictionary()
            } else {
                // Multiple events - wrap in batch
                let eventDicts = try events.map { try $0.event.toDictionary() }
                batchPayload = ["events": eventDicts]
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: batchPayload, options: .sortedKeys)
            
            // Check compression
            let shouldCompress = config.compressionEnabled && jsonData.count >= config.compressionThreshold
            let payloadData: Data
            
            if shouldCompress {
                guard let compressed = jsonData.zlibCompressed() else {
                    throw LuxAnalyticsError.encodingError(NSError(domain: "LuxAnalytics", code: -1, userInfo: [NSLocalizedDescriptionKey: "Compression failed"]))
                }
                payloadData = compressed
                await analyticsActor.debugLog("Compressed payload: \(jsonData.count) -> \(compressed.count) bytes")
            } else {
                payloadData = jsonData
            }
            
            // Create the request
            var request = URLRequest(url: config.apiURL.appendingPathComponent(config.projectId))
            request.httpMethod = "POST"
            request.httpBody = payloadData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(LuxAnalyticsVersion.fullVersion, forHTTPHeaderField: "User-Agent")
            
            if shouldCompress {
                request.setValue("deflate", forHTTPHeaderField: "Content-Encoding")
            }
            
            // Add Basic Auth header
            let authString = "\(config.publicId):"
            if let authData = authString.data(using: .utf8) {
                let base64Auth = authData.base64EncodedString()
                request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            }
            
            request.timeoutInterval = config.requestTimeout
            
            // Send the request
            let (data, response) = try await session.data(for: request)
            
            // Handle response
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    await analyticsActor.debugLog("Successfully sent \(events.count) events")
                    await GlobalCircuitBreaker.shared.recordSuccess(for: config.apiURL)
                    
                    // Notify success for each event
                    for queuedEvent in events {
                        await LuxAnalytics.notifyEventsSent([queuedEvent.event])
                    }
                    
                    // Update diagnostics
                    await LuxAnalyticsDiagnostics.shared.recordEventsSent(count: events.count)
                    await LuxAnalyticsDiagnostics.shared.recordBytesTransmitted(bytes: payloadData.count)
                    
                case 400...499:
                    // Client error - don't retry
                    // Redact the response body before it enters the public error:
                    // it can reach SDK consumers via eventsFailed and may contain PII.
                    let responseString = String(data: data, encoding: .utf8).map(SecureLogger.redact)
                    let error = LuxAnalyticsError.serverError(statusCode: httpResponse.statusCode, response: responseString)
                    await analyticsActor.debugLog("Client error: \(error)")
                    
                    // Drop events as they won't succeed
                    for queuedEvent in events {
                        let luxError = error
                        await LuxAnalytics.notifyEventsFailed([queuedEvent.event], error: luxError)
                    }
                    
                    await LuxAnalyticsDiagnostics.shared.recordEventsFailed(count: events.count, error: error)
                    
                default:
                    // Server error - will retry
                    // Redact the response body before it enters the public error:
                    // it can reach SDK consumers via eventsFailed and may contain PII.
                    let responseString = String(data: data, encoding: .utf8).map(SecureLogger.redact)
                    let error = LuxAnalyticsError.serverError(statusCode: httpResponse.statusCode, response: responseString)
                    await analyticsActor.debugLog("Server error: \(error)")

                    await GlobalCircuitBreaker.shared.recordFailure(for: config.apiURL)

                    // Notify failure for all events in this batch
                    for queuedEvent in events {
                        await LuxAnalytics.notifyEventsFailed([queuedEvent.event], error: error)
                    }

                    // Requeue events for retry if under max attempts
                    for queuedEvent in events {
                        if queuedEvent.shouldRetry(maxRetries: config.maxRetryAttempts) {
                            var updatedEvent = queuedEvent
                            updatedEvent.retryCount += 1
                            updatedEvent.lastAttemptAt = Date()
                            await LuxAnalyticsQueue.shared.enqueue(updatedEvent)
                        } else {
                            await LuxAnalytics.notifyEventsDropped(count: 1, reason: .dropOldest)
                        }
                    }

                    await LuxAnalyticsDiagnostics.shared.recordEventsFailed(count: events.count, error: error)
                }
            }
            
        } catch {
            let luxError = (error as? LuxAnalyticsError) ?? .networkError(error)
            await analyticsActor.debugLog("Failed to send batch: \(error)")
            await GlobalCircuitBreaker.shared.recordFailure(for: config.apiURL)

            // Notify failure for all events in this batch
            for queuedEvent in events {
                await LuxAnalytics.notifyEventsFailed([queuedEvent.event], error: luxError)
            }

            // Requeue events for retry
            for queuedEvent in events {
                if queuedEvent.shouldRetry(maxRetries: config.maxRetryAttempts) {
                    var updatedEvent = queuedEvent
                    updatedEvent.retryCount += 1
                    updatedEvent.lastAttemptAt = Date()
                    await LuxAnalyticsQueue.shared.enqueue(updatedEvent)
                } else {
                    await LuxAnalytics.notifyEventsDropped(count: 1, reason: .dropOldest)
                }
            }
            
            await LuxAnalyticsDiagnostics.shared.recordEventsFailed(count: events.count, error: error)
        }
    }
}

// MARK: - Compression

extension Data {
    func zlibCompressed() -> Data? {
        return self.withUnsafeBytes { bytes in
            let buffer = UnsafeBufferPointer<UInt8>(start: bytes.bindMemory(to: UInt8.self).baseAddress, count: self.count)
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
            defer { destinationBuffer.deallocate() }
            
            let compressedSize = compression_encode_buffer(
                destinationBuffer, count,
                buffer.baseAddress!, count,
                nil, COMPRESSION_ZLIB
            )
            
            guard compressedSize > 0 else { return nil }
            return Data(bytes: destinationBuffer, count: compressedSize)
        }
    }
}