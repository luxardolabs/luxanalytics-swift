import Foundation
import Testing
import zlib

@testable import LuxAnalytics

// MARK: - Wire payload

@Suite
struct WirePayloadTests {
    private func queued(_ name: String) -> QueuedEvent {
        QueuedEvent(
            event: AnalyticsEvent(
                name: name, timestamp: "2026-01-01T00:00:00Z", userId: "u1", sessionId: nil, metadata: ["k": "v"]))
    }

    @Test func singleEventIsSentBare() throws {
        let data = try LuxAnalytics.encodePayload([queued("screen_view")])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["name"] as? String == "screen_view")
        #expect(object["user_id"] as? String == "u1")
        #expect(object["session_id"] == nil)
        #expect(object["events"] == nil)
    }

    @Test func severalEventsAreWrappedInEvents() throws {
        let data = try LuxAnalytics.encodePayload([queued("a"), queued("b")])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let events = try #require(object["events"] as? [[String: Any]])
        #expect(events.map { $0["name"] as? String } == ["a", "b"])
    }

    @Test func keysAreSorted() throws {
        let data = try LuxAnalytics.encodePayload([queued("a")])
        let json = try #require(String(data: data, encoding: .utf8))
        let keys = ["\"id\"", "\"metadata\"", "\"name\"", "\"timestamp\"", "\"user_id\""]
        let offsets = keys.compactMap { json.range(of: $0)?.lowerBound }
        #expect(offsets.count == keys.count)
        #expect(offsets == offsets.sorted())
    }

    // The event id is the server's idempotency key: a retried event must carry the
    // same id it was first sent with, or the server can't drop the duplicate.
    @Test func idIsSentOnTheWire() throws {
        let event = queued("a")
        let data = try LuxAnalytics.encodePayload([event])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["id"] as? String == event.event.id)
    }

    @Test func idSurvivesARetry() throws {
        var event = queued("a")
        let original = event.event.id
        event.recordFailedAttempt()
        event.recordFailedAttempt()
        let data = try LuxAnalytics.encodePayload([event, queued("b")])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let events = try #require(object["events"] as? [[String: Any]])
        #expect(events.first?["id"] as? String == original)
    }

    @Test func idSurvivesQueuePersistence() throws {
        let event = queued("a")
        let restored = try JSONDecoder().decode(QueuedEvent.self, from: JSONEncoder().encode(event))
        #expect(restored.event.id == event.event.id)
    }

    @Test func compressionIsZlibWrapped() throws {
        let original = Data(String(repeating: "{\"name\":\"screen_view\"}", count: 64).utf8)
        let compressed = try #require(original.zlibCompressed())
        #expect(compressed.count < original.count)
        // RFC 1950 header: CM = 8 (deflate), and CMF*256 + FLG is a multiple of 31.
        #expect(compressed[0] & 0x0F == 8)
        #expect((UInt16(compressed[0]) << 8 | UInt16(compressed[1])).isMultiple(of: 31))
        // zlib's uncompress() only accepts the wrapped format, so it rejects raw DEFLATE.
        var restoredSize = uLong(original.count)
        var restored = Data(count: original.count)
        let status = restored.withUnsafeMutableBytes { output in
            compressed.withUnsafeBytes { input in
                uncompress(
                    output.bindMemory(to: Bytef.self).baseAddress, &restoredSize,
                    input.bindMemory(to: Bytef.self).baseAddress, uLong(compressed.count))
            }
        }
        #expect(status == Z_OK)
        #expect(restored.prefix(Int(restoredSize)) == original)
    }

    @Test func incompressibleDataStillCompresses() throws {
        // The old Compression-framework path sized its buffer to the input, so data
        // that grows under compression failed outright.
        var generator = SystemRandomNumberGenerator()
        let random = Data((0..<256).map { _ in UInt8.random(in: 0...255, using: &generator) })
        #expect(random.zlibCompressed() != nil)
    }

    @Test func emptyDataDoesNotCompress() {
        #expect(Data().zlibCompressed() == nil)
    }
}

// MARK: - Server responses: status outcomes and Retry-After

@Suite
struct SendOutcomeTests {
    @Test(arguments: [200, 201, 204])
    func successIsSent(status: Int) {
        #expect(LuxAnalytics.outcome(forStatus: status) == .sent)
    }

    @Test func rateLimitIsKeptForRetry() {
        #expect(LuxAnalytics.outcome(forStatus: 429) == .rateLimited)
    }

    @Test(arguments: [408, 500, 502, 503, 504])
    func transientFailuresAreRetried(status: Int) {
        #expect(LuxAnalytics.outcome(forStatus: status) == .retry)
    }

    @Test(arguments: [400, 401, 403, 404, 413, 422])
    func badRequestsAreDropped(status: Int) {
        #expect(LuxAnalytics.outcome(forStatus: status) == .drop)
    }
}

@Suite
struct RetryAfterParsingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func parsesDelaySeconds() {
        #expect(NetworkTransport.retryDelay(fromRetryAfter: "120", now: now) == 120)
        #expect(NetworkTransport.retryDelay(fromRetryAfter: " 0 ", now: now) == 0)
    }

    @Test func parsesAnHTTPDate() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let value = formatter.string(from: now.addingTimeInterval(90))
        #expect(NetworkTransport.retryDelay(fromRetryAfter: value, now: now) == 90)
    }

    @Test func aPastDateMeansNoWait() {
        #expect(NetworkTransport.retryDelay(fromRetryAfter: "Thu, 01 Jan 1970 00:00:00 GMT", now: now) == 0)
    }

    @Test func capsAHugeDelay() {
        #expect(NetworkTransport.retryDelay(fromRetryAfter: "999999", now: now) == NetworkTransport.maxRetryAfter)
    }

    @Test(arguments: ["", "soon", "-5", "1.5"])
    func rejectsGarbage(value: String) {
        #expect(NetworkTransport.retryDelay(fromRetryAfter: value, now: now) == nil)
    }
}

extension GlobalStateTests {
    @Suite(.serialized)
    struct BackOffTests {
        private let url = URL(string: "https://backoff.test.example.com/api/v1/events")!

        @Test func holdsRequestsUntilTheDeadline() async {
            await GlobalCircuitBreaker.shared.clear()
            let now = Date()
            await GlobalCircuitBreaker.shared.deferRequests(for: url, until: now.addingTimeInterval(30))
            #expect(await GlobalCircuitBreaker.shared.isDeferred(for: url, now: now))
            #expect(await !GlobalCircuitBreaker.shared.isDeferred(for: url, now: now.addingTimeInterval(31)))
        }

        @Test func anEarlierDeadlineNeverShortensTheWait() async {
            await GlobalCircuitBreaker.shared.clear()
            let now = Date()
            await GlobalCircuitBreaker.shared.deferRequests(for: url, until: now.addingTimeInterval(60))
            await GlobalCircuitBreaker.shared.deferRequests(for: url, until: now.addingTimeInterval(5))
            #expect(await GlobalCircuitBreaker.shared.isDeferred(for: url, now: now.addingTimeInterval(10)))
        }

        @Test func resetClearsTheHold() async {
            await GlobalCircuitBreaker.shared.clear()
            await GlobalCircuitBreaker.shared.deferRequests(for: url, until: Date().addingTimeInterval(60))
            await GlobalCircuitBreaker.shared.reset(for: url)
            #expect(await !GlobalCircuitBreaker.shared.isDeferred(for: url))
        }
    }
}
