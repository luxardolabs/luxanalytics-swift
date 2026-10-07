import Foundation

/// Reusable JSON encoder/decoder instances for better performance
enum JSONCoders {
    
    /// Shared JSON encoder for events
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Use compact encoding to save space
        encoder.outputFormatting = []
        return encoder
    }()
    
    /// Shared JSON decoder for events
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
    /// Pretty-printed encoder for diagnostics/debugging
    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

// MARK: - Safe encoding/decoding helpers

extension JSONCoders {
    
    /// Safely encode a value to JSON data
    static func encode<T: Encodable>(_ value: T) -> Data? {
        do {
            return try encoder.encode(value)
        } catch {
            SecureLogger.log("JSON encoding failed: \(error)", category: .error, level: .error)
            return nil
        }
    }
    
    /// Safely decode JSON data to a value
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            SecureLogger.log("JSON decoding failed: \(error)", category: .error, level: .error)
            return nil
        }
    }
    
    /// Encode for pretty printing (diagnostics)
    static func encodePretty<T: Encodable>(_ value: T) -> Data? {
        do {
            return try prettyEncoder.encode(value)
        } catch {
            SecureLogger.log("JSON pretty encoding failed: \(error)", category: .error, level: .error)
            return nil
        }
    }
}