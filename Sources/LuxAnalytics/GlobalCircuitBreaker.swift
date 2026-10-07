import Foundation

/// Global circuit breaker manager that handles circuit breakers per URL
actor GlobalCircuitBreaker {
    static let shared = GlobalCircuitBreaker()

    /// Circuit breakers per URL
    private var circuitBreakers: [URL: CircuitBreaker] = [:]

    /// When a URL may be sent to again, after the server asked the client to back off
    /// (a 429 or 503 with `Retry-After`). This is separate from the breaker: the
    /// server is up and has said when to come back.
    private var notBefore: [URL: Date] = [:]

    /// Default configuration for new circuit breakers
    private let defaultConfig = (
        failureThreshold: 5,
        resetTimeout: TimeInterval(60),
        halfOpenMaxAttempts: 3
    )

    private init() {}

    /// Check if circuit breaker is open for a given URL
    func isOpen(for url: URL) async -> Bool {
        let breaker = getOrCreateBreaker(for: url)
        // Use shouldAllowRequest() rather than reading currentState directly:
        // it applies the resetTimeout and transitions open -> halfOpen, which is
        // what enables automatic recovery. Reading currentState would latch open forever.
        return await !breaker.shouldAllowRequest()
    }

    /// Hold requests to a URL until `date`. A later date replaces an earlier one, never the reverse.
    func deferRequests(for url: URL, until date: Date) {
        if let existing = notBefore[url], existing >= date { return }
        notBefore[url] = date
    }

    /// Whether requests to a URL are being held for a server-requested back-off.
    func isDeferred(for url: URL, now: Date = Date()) -> Bool {
        guard let until = notBefore[url] else { return false }
        if now < until { return true }
        notBefore.removeValue(forKey: url)
        return false
    }

    /// Record a successful request for a URL
    func recordSuccess(for url: URL) async {
        let breaker = getOrCreateBreaker(for: url)
        await breaker.recordSuccess()
    }

    /// Record a failed request for a URL
    func recordFailure(for url: URL) async {
        let breaker = getOrCreateBreaker(for: url)
        await breaker.recordFailure()
    }

    /// Get metrics for a specific URL
    func getMetrics(for url: URL) async -> CircuitBreakerMetrics {
        let breaker = getOrCreateBreaker(for: url)
        return await breaker.getMetrics()
    }

    /// Get metrics for all URLs
    func getAllMetrics() async -> [URL: CircuitBreakerMetrics] {
        var metrics: [URL: CircuitBreakerMetrics] = [:]
        for (url, breaker) in circuitBreakers {
            metrics[url] = await breaker.getMetrics()
        }
        return metrics
    }

    /// Reset circuit breaker for a specific URL
    func reset(for url: URL) async {
        notBefore.removeValue(forKey: url)
        let breaker = getOrCreateBreaker(for: url)
        await breaker.reset()
    }

    /// Reset all circuit breakers
    func resetAll() async {
        notBefore.removeAll()
        for breaker in circuitBreakers.values {
            await breaker.reset()
        }
    }

    /// Remove circuit breaker for a URL
    func remove(for url: URL) {
        notBefore.removeValue(forKey: url)
        circuitBreakers.removeValue(forKey: url)
    }

    /// Clear all circuit breakers
    func clear() {
        notBefore.removeAll()
        circuitBreakers.removeAll()
    }

    private func getOrCreateBreaker(for url: URL) -> CircuitBreaker {
        if let existing = circuitBreakers[url] {
            return existing
        }

        let newBreaker = CircuitBreaker(
            failureThreshold: defaultConfig.failureThreshold,
            resetTimeout: defaultConfig.resetTimeout,
            halfOpenMaxAttempts: defaultConfig.halfOpenMaxAttempts
        )
        circuitBreakers[url] = newBreaker
        return newBreaker
    }
}

// MARK: - Public extension for LuxAnalytics

extension LuxAnalytics {
    /// Get circuit breaker status for the configured endpoint
    public static func getCircuitBreakerStatus() async -> CircuitBreakerMetrics? {
        guard let config = await LuxAnalyticsStorage.shared.getConfiguration() else {
            return nil
        }
        return await GlobalCircuitBreaker.shared.getMetrics(for: config.apiURL)
    }

    /// Reset circuit breaker for the configured endpoint
    public static func resetCircuitBreaker() async {
        guard let config = await LuxAnalyticsStorage.shared.getConfiguration() else {
            return
        }
        await GlobalCircuitBreaker.shared.reset(for: config.apiURL)
    }
}
