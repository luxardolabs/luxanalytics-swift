import Foundation
import os.log
import Synchronization

/// Thread-safe debug logging flag with lock-free synchronous reads.
/// `log()` is synchronous and runs from every isolation domain, so it cannot
/// `await` an actor; an Atomic<Bool> gives correct, synchronous access.
private let debugLoggingFlag = Atomic<Bool>(false)

/// Secure logger that automatically redacts sensitive information
public struct SecureLogger: Sendable {

    /// Update the cached debug logging flag
    public static func updateDebugLogging(_ enabled: Bool) {
        debugLoggingFlag.store(enabled, ordering: .relaxed)
    }

    /// Check if debug logging is enabled
    private static var debugLoggingEnabled: Bool {
        debugLoggingFlag.load(ordering: .relaxed)
    }
    
    /// Log categories
    public enum Category {
        case general
        case network
        case queue
        case error
        case security
        
        var osLog: OSLog {
            switch self {
            case .general:
                return OSLog(subsystem: "com.luxardolabs.LuxAnalytics", category: "General")
            case .network:
                return OSLog(subsystem: "com.luxardolabs.LuxAnalytics", category: "Network")
            case .queue:
                return OSLog(subsystem: "com.luxardolabs.LuxAnalytics", category: "Queue")
            case .error:
                return OSLog(subsystem: "com.luxardolabs.LuxAnalytics", category: "Error")
            case .security:
                return OSLog(subsystem: "com.luxardolabs.LuxAnalytics", category: "Security")
            }
        }
    }
    
    /// Log levels
    public enum Level {
        case debug
        case info
        case warning
        case error
        
        var osLogType: OSLogType {
            switch self {
            case .debug:
                return .debug
            case .info:
                return .info
            case .warning:
                return .default
            case .error:
                return .error
            }
        }
    }
    
    /// Patterns to redact
    private static let redactionPatterns: [(pattern: String, replacement: String)] = [
        // Email addresses
        (#"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, "<email>"),
        
        // IP addresses
        (#"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b"#, "<ip>"),
        
        // UUIDs
        (#"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#, "<uuid>"),
        
        // API keys (common patterns)
        (#"(?i)(api[_-]?key|apikey|secret|token|auth|password|pwd)[\"']?\s*[:=]\s*[\"']?[^\s\"']*"#, "$1=<redacted>"),
        
        // Credit card numbers
        (#"\b(?:\d[ -]*?){13,19}\b"#, "<card>"),
        
        // Phone numbers
        (#"(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}"#, "<phone>"),
        
        // Social Security Numbers
        (#"\b\d{3}-\d{2}-\d{4}\b"#, "<ssn>")
    ]
    
    /// Log a message with automatic redaction
    public static func log(
        _ message: String,
        category: Category = .general,
        level: Level = .debug,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let redactedMessage = redact(message)
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        
        if debugLoggingEnabled {
            os_log(
                "%{public}@ [%{public}@:%{public}d] %{public}@",
                log: category.osLog,
                type: level.osLogType,
                fileName,
                function,
                line,
                redactedMessage
            )
        }
    }
    
    /// Redact sensitive information from a string
    public static func redact(_ string: String) -> String {
        var result = string
        
        for (pattern, replacement) in redactionPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: replacement
                )
            }
        }
        
        return result
    }
}

// MARK: - PIIFilter Integration

extension PIIFilter {
    /// Filter a dictionary using SecureLogger's redaction
    public static func filter(_ dictionary: [String: String]) -> [String: String] {
        return dictionary.mapValues { SecureLogger.redact($0) }
    }
}