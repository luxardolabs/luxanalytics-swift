import Foundation

/// Reusable JSON encoders.
enum JSONCoders {

    /// Encoder for request bodies sent to the server. Sorted keys keep the bytes
    /// stable for the same event.
    static let wireEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// Pretty-printed encoder for diagnostics exports.
    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// Encode for pretty printing (diagnostics). Returns nil, and logs, if encoding fails.
    static func encodePretty<T: Encodable>(_ value: T) -> Data? {
        do {
            return try prettyEncoder.encode(value)
        } catch {
            SecureLogger.log("JSON pretty encoding failed: \(error)", category: .error, level: .error)
            return nil
        }
    }
}
