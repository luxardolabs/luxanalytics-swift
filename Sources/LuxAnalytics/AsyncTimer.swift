import Foundation

/// Modern async timer implementation for iOS 18+
public struct AsyncTimer {
    /// Create a timer using Duration API
    /// - Parameters:
    ///   - duration: Time interval between fires
    ///   - tolerance: Timing tolerance to improve energy efficiency
    /// - Returns: An async stream of timer ticks
    public static func schedule(
        every duration: Duration,
        tolerance: Duration? = nil
    ) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let timerTask = Task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: duration, tolerance: tolerance)
                        continuation.yield()
                    } catch {
                        // Task was cancelled
                        break
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                // Cancel the inner task so it stops sleeping when the stream ends.
                timerTask.cancel()
            }
        }
    }
}