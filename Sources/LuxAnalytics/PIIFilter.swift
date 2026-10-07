import Foundation

/// Utilities for filtering and sanitizing PII from analytics data
public enum PIIFilter {
    
    // MARK: - Common PII Patterns
    
    /// Email pattern
    private static let emailPattern = #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b"#
    
    /// Phone number patterns (US and international)
    private static let phonePatterns = [
        #"\b\d{3}[-.]?\d{3}[-.]?\d{4}\b"#,                    // US: 123-456-7890
        #"\b\(\d{3}\)\s*\d{3}[-.]?\d{4}\b"#,                  // US: (123) 456-7890
        #"\b\+\d{1,3}\s?\d{1,14}\b"#,                         // International
        #"\b\d{10,15}\b"#                                      // Long numbers
    ]
    
    /// Credit card pattern
    private static let creditCardPattern = #"\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b"#
    
    /// SSN pattern
    private static let ssnPattern = #"\b\d{3}-\d{2}-\d{4}\b"#
    
    /// IP address patterns
    private static let ipPatterns = [
        #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#,                      // IPv4
        #"\b(?:[A-Fa-f0-9]{1,4}:){7}[A-Fa-f0-9]{1,4}\b"#      // IPv6
    ]
    
    // MARK: - Sanitization Methods
    
    /// Sanitize a string by replacing PII with placeholders
    public static func sanitize(_ text: String) -> String {
        var result = text
        
        // Replace emails
        result = result.replacingOccurrences(
            of: emailPattern,
            with: "[EMAIL]",
            options: .regularExpression
        )
        
        // Replace phone numbers
        for pattern in phonePatterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "[PHONE]",
                options: .regularExpression
            )
        }
        
        // Replace credit cards
        result = result.replacingOccurrences(
            of: creditCardPattern,
            with: "[CARD]",
            options: .regularExpression
        )
        
        // Replace SSNs
        result = result.replacingOccurrences(
            of: ssnPattern,
            with: "[SSN]",
            options: .regularExpression
        )
        
        // Replace IP addresses
        for pattern in ipPatterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "[IP]",
                options: .regularExpression
            )
        }
        
        return result
    }
    
    /// Sanitize a dictionary of metadata
    public static func sanitizeMetadata(_ metadata: [String: String]) -> [String: String] {
        var sanitized: [String: String] = [:]
        
        for (key, value) in metadata {
            // Sanitize both keys and values
            let sanitizedKey = sanitize(key)
            let sanitizedValue = sanitize(value)
            sanitized[sanitizedKey] = sanitizedValue
        }
        
        return sanitized
    }
    
    /// Check if a string contains potential PII
    public static func containsPII(_ text: String) -> Bool {
        // Check email
        if text.range(of: emailPattern, options: .regularExpression) != nil {
            return true
        }
        
        // Check phone numbers
        for pattern in phonePatterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        // Check credit cards
        if text.range(of: creditCardPattern, options: .regularExpression) != nil {
            return true
        }
        
        // Check SSNs
        if text.range(of: ssnPattern, options: .regularExpression) != nil {
            return true
        }
        
        // Check IP addresses
        for pattern in ipPatterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        return false
    }
    
    /// Redact specific fields from metadata
    public static func redactFields(_ metadata: [String: String], fields: Set<String>) -> [String: String] {
        var redacted = metadata
        
        for field in fields {
            if redacted[field] != nil {
                redacted[field] = "[REDACTED]"
            }
        }
        
        return redacted
    }
    
    /// Common fields that often contain PII
    public static let commonPIIFields: Set<String> = [
        "email", "e-mail", "email_address",
        "phone", "phone_number", "telephone", "mobile",
        "name", "full_name", "first_name", "last_name", "username",
        "address", "street", "city", "state", "zip", "postal_code",
        "ssn", "social_security", "tax_id",
        "credit_card", "card_number", "cvv",
        "password", "pin", "passcode",
        "date_of_birth", "dob", "birthday",
        "ip", "ip_address", "user_agent"
    ]
}

// MARK: - Convenience Extensions

public extension LuxAnalytics {
    
    /// Track an event with automatic PII filtering
    func trackSanitized(_ name: String, metadata: [String: String] = [:]) async throws {
        let sanitizedMetadata = PIIFilter.sanitizeMetadata(metadata)
        try await track(name, metadata: sanitizedMetadata)
    }
    
    /// Track an event with specific fields redacted
    func trackWithRedaction(_ name: String, metadata: [String: String] = [:], redactFields: Set<String>) async throws {
        let redactedMetadata = PIIFilter.redactFields(metadata, fields: redactFields)
        try await track(name, metadata: redactedMetadata)
    }
}