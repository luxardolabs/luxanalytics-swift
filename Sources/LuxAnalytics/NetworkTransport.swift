import Foundation

/// The SDK's network layer: the only code that touches `URLSession`.
///
/// It builds the ingest request for an already-encoded payload and returns the
/// raw HTTP status and body. Deciding what a status means (retry, drop, record)
/// stays with the caller.
enum NetworkTransport {
    /// The longest `Retry-After` honoured. A larger or broken value must not park
    /// the queue indefinitely.
    static let maxRetryAfter: TimeInterval = 3600

    /// What came back from the server.
    struct Response: Sendable {
        let statusCode: Int
        let body: Data
        /// How long the server asked the client to wait, from `Retry-After`.
        let retryAfter: TimeInterval?
    }

    /// Send one payload to the project's ingest endpoint.
    /// - Parameters:
    ///   - payload: The request body, already compressed when `deflated` is true.
    ///   - deflated: Whether to mark the body `Content-Encoding: deflate`.
    ///   - config: Endpoint, credentials and timeout.
    /// - Returns: The HTTP status code, response body and any `Retry-After` delay.
    /// - Throws: A transport error, or `URLError(.badServerResponse)` when the
    ///   response is not HTTP.
    static func send(
        _ payload: Data,
        deflated: Bool,
        config: LuxAnalyticsConfiguration
    ) async throws -> Response {
        var request = URLRequest(url: config.apiURL.appendingPathComponent(config.projectId))
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(LuxAnalyticsVersion.fullVersion, forHTTPHeaderField: "User-Agent")
        if deflated {
            request.setValue("deflate", forHTTPHeaderField: "Content-Encoding")
        }
        // The DSN's public id is the Basic-auth user, with an empty password.
        let credentials = Data("\(config.publicId):".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = config.requestTimeout

        let (body, response) = try await URLSession.analytics.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { retryDelay(fromRetryAfter: $0) }
        return Response(statusCode: http.statusCode, body: body, retryAfter: retryAfter)
    }

    /// Parse a `Retry-After` value (RFC 9110 §10.2.3): delay-seconds or an HTTP-date.
    /// - Returns: The delay in seconds, capped at `maxRetryAfter`, or nil when the
    ///   value is neither form.
    static func retryDelay(fromRetryAfter value: String, now: Date = Date()) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let delay: TimeInterval
        if let seconds = Int(trimmed), seconds >= 0 {
            delay = TimeInterval(seconds)
        } else if let date = httpDateFormatter.date(from: trimmed) {
            delay = max(0, date.timeIntervalSince(now))
        } else {
            return nil
        }
        return min(delay, maxRetryAfter)
    }

    /// IMF-fixdate, e.g. "Wed, 21 Oct 2015 07:28:00 GMT".
    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

// MARK: - URLSession

extension URLSession {
    /// The SDK's session. TLS is validated by the system as usual.
    ///
    /// The SDK has no certificate pinning of its own. An app that wants to pin its
    /// server uses App Transport Security's `NSPinnedDomains` in its Info.plist, which
    /// also covers this session (see the Privacy & Security docs).
    static let analytics: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration)
    }()
}
