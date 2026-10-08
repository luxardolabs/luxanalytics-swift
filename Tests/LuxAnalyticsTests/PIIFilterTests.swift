import Foundation
import Testing

@testable import LuxAnalytics

@Suite
struct PIIFilterTests {
    @Test(arguments: [
        ("contact jane.doe@example.com today", "contact [EMAIL] today"),
        ("call 555-123-4567", "call [PHONE]"),
        ("call (555) 123-4567", "call [PHONE]"),
        ("card 4111 1111 1111 1111", "card [CARD]"),
        ("card 4111-1111-1111-1111", "card [CARD]"),
        ("card 4111111111111111", "card [CARD]"),
        ("ssn 123-45-6789", "ssn [SSN]"),
        ("from 192.168.10.200", "from [IP]"),
        ("from 2001:0db8:85a3:0000:0000:8a2e:0370:7334", "from [IP]"),
    ])
    func sanitizeReplacesEachKind(input: String, expected: String) {
        #expect(PIIFilter.sanitize(input) == expected)
    }

    @Test(arguments: ["screen_view", "home", "button_save", "level 3 of 10", "v1.2.3", "2026-10-07"])
    func sanitizeLeavesOrdinaryTextAlone(text: String) {
        #expect(PIIFilter.sanitize(text) == text)
        #expect(!PIIFilter.containsPII(text))
    }

    @Test(arguments: [
        "jane.doe@example.com", "555-123-4567", "(555) 123-4567", "4111 1111 1111 1111", "123-45-6789",
        "10.0.0.1",
    ])
    func containsPIIDetectsEachKind(text: String) {
        #expect(PIIFilter.containsPII(text))
    }

    @Test func sanitizeMetadataCleansKeysAndValues() {
        let cleaned = PIIFilter.sanitizeMetadata(["contact": "jane@example.com", "jane@example.com": "x"])
        #expect(cleaned["contact"] == "[EMAIL]")
        #expect(cleaned["[EMAIL]"] == "x")
        #expect(!cleaned.keys.contains("jane@example.com"))
    }

    @Test func redactFieldsReplacesOnlyNamedFieldsThatExist() {
        let redacted = PIIFilter.redactFields(["email": "a@b.co", "screen": "home"], fields: ["email", "phone"])
        #expect(redacted == ["email": "[REDACTED]", "screen": "home"])
    }

    @Test func commonPIIFieldsCoverTheObviousNames() {
        for field in ["email", "phone", "password", "ssn", "credit_card", "ip_address"] {
            #expect(PIIFilter.commonPIIFields.contains(field))
        }
    }
}
