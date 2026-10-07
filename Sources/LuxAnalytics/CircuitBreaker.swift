import Foundation

/// Circuit breaker states
public enum CircuitBreakerState: Sendable {
    case closed     // Normal operation
    case open       // Failing, reject all requests
    case halfOpen   // Testing if service recovered
}

/// Circuit breaker for handling failing endpoints
public actor CircuitBreaker {
    
    // Configuration
    private let failureThreshold: Int
    private let resetTimeout: TimeInterval
    private let halfOpenMaxAttempts: Int
    
    // State tracking
    private var state: CircuitBreakerState = .closed
    private var failureCount: Int = 0
    private var lastFailureTime: Date?
    private var halfOpenAttempts: Int = 0
    
    // Metrics
    private var totalFailures: Int = 0
    private var totalSuccesses: Int = 0
    private var lastStateChange: Date
    private var stateChanges: [(from: CircuitBreakerState, to: CircuitBreakerState, at: Date)] = []
    
    /// Initialize circuit breaker with configuration
    public init(
        failureThreshold: Int = 5,
        resetTimeout: TimeInterval = 60,
        halfOpenMaxAttempts: Int = 3
    ) {
        self.failureThreshold = failureThreshold
        self.resetTimeout = resetTimeout
        self.halfOpenMaxAttempts = halfOpenMaxAttempts
        self.lastStateChange = Date()
    }
    
    /// Get current state
    public var currentState: CircuitBreakerState {
        return state
    }
    
    /// Check if requests should be allowed
    public func shouldAllowRequest() -> Bool {
        switch state {
        case .closed:
            return true
            
        case .open:
            // Check if we should transition to half-open
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) >= resetTimeout {
                transitionTo(.halfOpen)
                return true
            }
            return false
            
        case .halfOpen:
            // Allow limited requests in half-open state
            return halfOpenAttempts < halfOpenMaxAttempts
        }
    }
    
    /// Record a successful request
    public func recordSuccess() {
        totalSuccesses += 1
        
        switch state {
        case .closed:
            // Reset failure count on success
            failureCount = 0
            
        case .halfOpen:
            // Success in half-open state means service is recovering
            halfOpenAttempts += 1
            if halfOpenAttempts >= halfOpenMaxAttempts {
                // Enough successful attempts, close the circuit
                transitionTo(.closed)
                failureCount = 0
                halfOpenAttempts = 0
            }
            
        case .open:
            // Shouldn't happen, but handle gracefully
            SecureLogger.log("Success recorded in open state", category: .error, level: .info)
        }
    }
    
    /// Record a failed request
    public func recordFailure() {
        totalFailures += 1
        lastFailureTime = Date()
        
        switch state {
        case .closed:
            failureCount += 1
            if failureCount >= failureThreshold {
                transitionTo(.open)
            }
            
        case .halfOpen:
            // Failure in half-open state means service is still down
            transitionTo(.open)
            halfOpenAttempts = 0
            
        case .open:
            // Already open, just update failure time
            break
        }
    }
    
    /// Force reset the circuit breaker
    public func reset() {
        transitionTo(.closed)
        failureCount = 0
        halfOpenAttempts = 0
        lastFailureTime = nil
    }
    
    /// Get circuit breaker metrics
    public func getMetrics() -> CircuitBreakerMetrics {
        return CircuitBreakerMetrics(
            currentState: state,
            failureCount: failureCount,
            totalFailures: totalFailures,
            totalSuccesses: totalSuccesses,
            lastFailureTime: lastFailureTime,
            lastStateChange: lastStateChange,
            stateChanges: stateChanges.suffix(10) // Keep last 10 state changes
        )
    }
    
    // MARK: - Private Helpers
    
    private func transitionTo(_ newState: CircuitBreakerState) {
        let oldState = state
        state = newState
        lastStateChange = Date()
        
        // Record state change
        stateChanges.append((from: oldState, to: newState, at: lastStateChange))
        
        // Keep only last 100 state changes
        if stateChanges.count > 100 {
            stateChanges.removeFirst()
        }
        
        SecureLogger.log(
            "Circuit breaker state changed from \(oldState) to \(newState)",
            category: .network,
            level: .info
        )
    }
}

/// Circuit breaker metrics
public struct CircuitBreakerMetrics: Sendable {
    public let currentState: CircuitBreakerState
    public let failureCount: Int
    public let totalFailures: Int
    public let totalSuccesses: Int
    public let lastFailureTime: Date?
    public let lastStateChange: Date
    public let stateChanges: [(from: CircuitBreakerState, to: CircuitBreakerState, at: Date)]
    
    /// Success rate (0.0 to 1.0)
    public var successRate: Double {
        let total = totalSuccesses + totalFailures
        guard total > 0 else { return 1.0 }
        return Double(totalSuccesses) / Double(total)
    }
    
    /// Time in current state
    public var timeInCurrentState: TimeInterval {
        return Date().timeIntervalSince(lastStateChange)
    }
}

