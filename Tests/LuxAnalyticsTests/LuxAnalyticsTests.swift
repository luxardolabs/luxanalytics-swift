import Testing
import Foundation
import Security
@testable import LuxAnalytics

// MARK: - Shared test helpers

private let validDSN = "https://testpublic@test.example.com/api/v1/events/testproject"

/// Probes whether the Keychain is usable in the current test environment.
/// A SwiftPM test bundle has no app host, so Keychain access is unentitled
/// (errSecMissingEntitlement) and the encryption-key tests must skip rather
/// than report a false failure. They run normally with a host app / on device.
private func keychainIsAvailable() -> Bool {
    let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "LuxAnalyticsTests",
        kSecAttrAccount as String: "com.luxardolabs.LuxAnalytics.keychainProbe"
    ]
    SecItemDelete(base as CFDictionary)
    var add = base
    add[kSecValueData as String] = Data("probe".utf8)
    let status = SecItemAdd(add as CFDictionary, nil)
    SecItemDelete(base as CFDictionary)
    return status == errSecSuccess
}

private func makeEvent(_ name: String) -> AnalyticsEvent {
    AnalyticsEvent(
        name: name,
        timestamp: ISO8601DateFormatter().string(from: Date()),
        userId: nil,
        sessionId: nil,
        metadata: [:]
    )
}

// MARK: - Configuration

@Suite(.serialized)
struct ConfigurationTests {
    init() async { await LuxAnalyticsTestHelper.reset() }

    @Test func parsesDSN() throws {
        let dsn = "https://a1b2c3d4e5f6@analytics.example.com/api/v1/events/1234567890123456"
        let config = try LuxAnalyticsConfiguration(dsn: dsn)
        #expect(config.dsn == dsn)
        #expect(config.publicId == "a1b2c3d4e5f6")
        #expect(config.projectId == "1234567890123456")
        #expect(config.apiURL.absoluteString == "https://analytics.example.com/api/v1/events/")
    }

    @Test func invalidDSNThrows() {
        #expect(throws: LuxAnalyticsError.self) {
            try LuxAnalyticsConfiguration(dsn: "not-a-url")
        }
    }

    @Test func usesDefaults() throws {
        let config = try LuxAnalyticsConfiguration(dsn: validDSN)
        #expect(config.autoFlushInterval == LuxAnalyticsDefaults.autoFlushInterval)
        #expect(config.maxQueueSize == LuxAnalyticsDefaults.maxQueueSize)
        #expect(config.batchSize == LuxAnalyticsDefaults.batchSize)
        #expect(config.maxRetryAttempts == LuxAnalyticsDefaults.maxRetryAttempts)
        #expect(config.overflowStrategy == LuxAnalyticsDefaults.overflowStrategy)
    }

    @Test func appliesCustomValues() throws {
        let config = try LuxAnalyticsConfiguration(
            dsn: validDSN,
            autoFlushInterval: 60,
            maxQueueSize: 200,
            batchSize: 20,
            debugLogging: true,
            requestTimeout: 30,
            maxQueueSizeHard: 1000,
            eventTTL: 86400,
            maxRetryAttempts: 3,
            overflowStrategy: .dropNewest
        )
        #expect(config.autoFlushInterval == 60)
        #expect(config.maxQueueSize == 200)
        #expect(config.batchSize == 20)
        #expect(config.debugLogging == true)
        #expect(config.overflowStrategy == .dropNewest)
    }

    @Test func initializeSetsInitialized() async throws {
        let config = try LuxAnalyticsConfiguration(dsn: validDSN)
        try await LuxAnalytics.initialize(with: config)
        #expect(await LuxAnalytics.isInitialized == true)
    }

    @Test func doubleInitializeThrows() async throws {
        let config = try LuxAnalyticsConfiguration(dsn: validDSN)
        try await LuxAnalytics.initialize(with: config)
        do {
            try await LuxAnalytics.initialize(with: config)
            Issue.record("Expected the second initialize to throw .alreadyInitialized")
        } catch let error as LuxAnalyticsError {
            #expect(error == .alreadyInitialized)
        }
    }
}

// MARK: - Circuit breaker (validates the auto-recovery fix)

@Suite
struct CircuitBreakerTests {
    @Test func startsClosedAndAllowsRequests() async {
        let breaker = CircuitBreaker(failureThreshold: 3, resetTimeout: 60, halfOpenMaxAttempts: 1)
        #expect(await breaker.shouldAllowRequest() == true)
    }

    @Test func opensAfterReachingFailureThreshold() async {
        let breaker = CircuitBreaker(failureThreshold: 3, resetTimeout: 60, halfOpenMaxAttempts: 1)
        for _ in 0..<3 { await breaker.recordFailure() }
        #expect(await breaker.shouldAllowRequest() == false)
    }

    /// The bug fixed in 1.0.2: an open breaker must transition back to half-open
    /// once resetTimeout elapses, rather than latching open forever.
    @Test func recoversToHalfOpenAfterResetTimeout() async throws {
        let breaker = CircuitBreaker(failureThreshold: 2, resetTimeout: 0.2, halfOpenMaxAttempts: 1)
        for _ in 0..<2 { await breaker.recordFailure() }
        #expect(await breaker.shouldAllowRequest() == false)

        try await Task.sleep(for: .milliseconds(300))
        #expect(await breaker.shouldAllowRequest() == true)
    }
}

@Suite(.serialized)
struct GlobalCircuitBreakerTests {
    @Test func opensAfterFailuresAndResetClears() async {
        let url = URL(string: "https://cb-test.example.com/api")!
        await GlobalCircuitBreaker.shared.remove(for: url)

        for _ in 0..<5 { await GlobalCircuitBreaker.shared.recordFailure(for: url) }
        #expect(await GlobalCircuitBreaker.shared.isOpen(for: url) == true)

        await GlobalCircuitBreaker.shared.reset(for: url)
        #expect(await GlobalCircuitBreaker.shared.isOpen(for: url) == false)

        await GlobalCircuitBreaker.shared.remove(for: url)
    }
}

// MARK: - SecureLogger redaction (validates redaction used by the server-response fix)

@Suite
struct SecureLoggerTests {
    @Test func redactsEmailAddresses() {
        #expect(SecureLogger.redact("reach me at john.doe@example.com today").contains("<email>"))
        #expect(SecureLogger.redact("reach me at john.doe@example.com today").contains("@") == false)
    }

    @Test func redactsIPAddresses() {
        #expect(SecureLogger.redact("host 192.168.1.42 is down").contains("<ip>"))
    }

    @Test func redactsUUIDs() {
        #expect(SecureLogger.redact("id 550e8400-e29b-41d4-a716-446655440000").contains("<uuid>"))
    }

    @Test func leavesNonSensitiveTextUnchanged() {
        #expect(SecureLogger.redact("just a normal log line") == "just a normal log line")
    }

    @Test func updateDebugLoggingIsSynchronousAndSafe() {
        // Exercises the Atomic<Bool> path that replaced the dead actor stub.
        SecureLogger.updateDebugLogging(true)
        SecureLogger.updateDebugLogging(false)
        SecureLogger.log("noop", category: .general, level: .debug)
    }
}

// MARK: - Queue encryption (validates round-trip + cached-key reset)

@Suite(.serialized)
struct QueueEncryptionTests {
    @Test(.enabled(if: keychainIsAvailable()))
    func encryptDecryptRoundTrips() throws {
        let original = Data("sensitive payload \u{1F510}".utf8)
        let encrypted = try #require(QueueEncryption.encrypt(original))
        #expect(encrypted != original)
        let decrypted = try #require(QueueEncryption.decrypt(encrypted))
        #expect(decrypted == original)
    }

    @Test(.enabled(if: keychainIsAvailable()))
    func regeneratesUsableKeyAfterDeletion() throws {
        _ = QueueEncryption.encrypt(Data("warm up".utf8))
        QueueEncryption.deleteKey()  // clears Keychain entry AND the in-memory cache

        let data = Data("after reset".utf8)
        let encrypted = try #require(QueueEncryption.encrypt(data))
        let decrypted = try #require(QueueEncryption.decrypt(encrypted))
        #expect(decrypted == data)
    }
}

// MARK: - Event stream (validates the synchronous-registration race fix)

@Suite(.serialized)
struct EventStreamTests {
    @Test func deliversEventEmittedRightAfterSubscription() async {
        // Accessing eventStream registers the observer synchronously (the 1.0.2 fix),
        // so an event emitted immediately afterward is not lost.
        var iterator = LuxAnalyticsEvents.eventStream.makeAsyncIterator()
        await LuxAnalytics.notifyEventsSent([makeEvent("stream_probe_event")])

        let received = await iterator.next()
        guard case .eventsSent(let events)? = received else {
            Issue.record("Expected .eventsSent, got \(String(describing: received))")
            return
        }
        #expect(events.first?.name == "stream_probe_event")
    }
}

// MARK: - LuxAnalyticsError (validates explicit Sendable + equality)

@Suite
struct LuxAnalyticsErrorTests {
    @Test func serverErrorEqualityConsidersCodeAndResponse() {
        #expect(LuxAnalyticsError.serverError(statusCode: 500, response: "x")
                == LuxAnalyticsError.serverError(statusCode: 500, response: "x"))
        #expect(LuxAnalyticsError.serverError(statusCode: 500, response: "x")
                != LuxAnalyticsError.serverError(statusCode: 500, response: "y"))
    }

    @Test func errorDescriptionIncludesStatusCode() {
        let desc = LuxAnalyticsError.serverError(statusCode: 503, response: nil).errorDescription
        #expect(desc?.contains("503") == true)
    }

    /// Compile-time proof of the explicit Sendable conformance: the value is
    /// captured by a Task closure, which requires Sendable.
    @Test func isSendableAcrossConcurrencyBoundary() async {
        let error = LuxAnalyticsError.notInitialized
        let roundTripped = await Task { error }.value
        #expect(roundTripped == .notInitialized)
    }
}

// MARK: - Analytics event model

@Suite
struct AnalyticsEventTests {
    @Test func storesProvidedValues() {
        let event = AnalyticsEvent(
            name: "test_event",
            timestamp: "2024-01-01T00:00:00Z",
            userId: "user123",
            sessionId: "session123",
            metadata: ["key": "value"]
        )
        #expect(event.name == "test_event")
        #expect(event.timestamp == "2024-01-01T00:00:00Z")
        #expect(event.userId == "user123")
        #expect(event.sessionId == "session123")
        #expect(event.metadata["key"] == "value")
        #expect(event.id.isEmpty == false)
    }

    @Test func roundTripsThroughCodable() throws {
        let event = AnalyticsEvent(
            name: "test_event",
            timestamp: "2024-01-01T00:00:00Z",
            userId: "user123",
            sessionId: "session123",
            metadata: ["key": "value"]
        )
        let encoded = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AnalyticsEvent.self, from: encoded)
        #expect(decoded.id == event.id)
        #expect(decoded.name == event.name)
        #expect(decoded.metadata["key"] == "value")
    }
}

// MARK: - Queued event retry logic

@Suite
struct QueuedEventTests {
    @Test func freshEventIsNotExpired() {
        let queued = QueuedEvent(event: makeEvent("test"))
        #expect(queued.isExpired(ttlSeconds: 3600) == false)
    }

    @Test func retryDelayGrowsWithRetryCount() {
        var queued = QueuedEvent(event: makeEvent("test"))

        queued.retryCount = 0
        let first = queued.nextRetryDelay()
        #expect(first > 0.75)
        #expect(first < 1.25)

        queued.retryCount = 1
        let second = queued.nextRetryDelay()
        #expect(second > 1.5)
        #expect(second < 2.5)

        queued.retryCount = 100
        #expect(queued.nextRetryDelay() <= 375)
    }

    @Test func shouldRetryRespectsMaxAttempts() {
        var queued = QueuedEvent(event: makeEvent("test"))
        #expect(queued.shouldRetry(maxRetries: 3) == true)
        queued.retryCount = 3
        #expect(queued.shouldRetry(maxRetries: 3) == false)
    }
}

// MARK: - Queue behavior

@Suite(.serialized)
struct QueueTests {
    init() async throws {
        try await LuxAnalyticsTestHelper.initializeForTesting()
        await LuxAnalyticsQueue.shared.clear()
    }

    @Test func enqueueIncrementsSize() async {
        let before = await LuxAnalyticsQueue.shared.queueSize
        await LuxAnalyticsQueue.shared.enqueue(makeEvent("e"))
        #expect(await LuxAnalyticsQueue.shared.queueSize == before + 1)
    }

    @Test func clearEmptiesQueue() async {
        await LuxAnalyticsQueue.shared.enqueue(makeEvent("a"))
        await LuxAnalyticsQueue.shared.enqueue(makeEvent("b"))
        await LuxAnalyticsQueue.shared.clear()
        #expect(await LuxAnalyticsQueue.shared.queueSize == 0)
    }

    @Test func statsReflectQueuedEvents() async {
        await LuxAnalyticsQueue.shared.clear()
        for i in 0..<5 { await LuxAnalyticsQueue.shared.enqueue(makeEvent("e\(i)")) }
        let stats = await LuxAnalyticsQueue.shared.getQueueStats()
        #expect(stats.totalEvents == 5)
        #expect(stats.failedBatchCount == 0)
        if let age = stats.oldestEventAge {
            #expect(age < 5)
        }
    }
}

// MARK: - Settings

@Suite(.serialized)
struct AnalyticsSettingsTests {
    @Test func enableThenDisableIsReflected() async {
        await AnalyticsSettings.shared.setEnabled(true)
        #expect(await AnalyticsSettings.shared.isEnabled == true)

        await AnalyticsSettings.shared.setEnabled(false)
        #expect(await AnalyticsSettings.shared.isEnabled == false)

        await AnalyticsSettings.shared.setEnabled(true)  // restore default
    }
}

// MARK: - Network monitor

@Suite
struct NetworkMonitorTests {
    @Test func sharedReturnsSingleton() {
        #expect(NetworkMonitor.shared === NetworkMonitor.shared)
    }

    @Test func exposesConnectionProperties() async {
        _ = await NetworkMonitor.shared.isConnected
        _ = await NetworkMonitor.shared.isExpensive
    }
}
