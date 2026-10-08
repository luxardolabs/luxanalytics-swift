import Foundation

/// Reusable JSON encoder/decoder instances, so the queue doesn't build a new coder for
/// every save, load and stats pass.
enum JSONCoders {

    /// Encoder for the persisted queue. Dates use JSONEncoder's default format; `decoder` must
    /// match it, or a queue saved before a relaunch can't be read back and is lost.
    static let encoder = JSONEncoder()

    /// Decoder for the persisted queue, in the same date format as `encoder`.
    static let decoder = JSONDecoder()

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

    /// Encode with the shared `encoder`. Returns nil, and logs, if encoding fails.
    static func encode<T: Encodable>(_ value: T) -> Data? {
        do {
            return try encoder.encode(value)
        } catch {
            SecureLogger.log("JSON encoding failed: \(error)", category: .error, level: .error)
            return nil
        }
    }

    /// Decode with the shared `decoder`. Returns nil, and logs, if decoding fails.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            SecureLogger.log("JSON decoding failed: \(error)", category: .error, level: .error)
            return nil
        }
    }

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
