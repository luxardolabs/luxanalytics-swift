import Foundation

public struct AnalyticsEvent: Codable, Sendable {
    public let id: String
    public let name: String
    public let timestamp: String
    public let userId: String?
    public let sessionId: String?
    public let metadata: [String: String]

    public init(name: String, timestamp: String, userId: String?, sessionId: String?, metadata: [String: String]) {
        self.id = UUID().uuidString
        self.name = name
        self.timestamp = timestamp
        self.userId = userId
        self.sessionId = sessionId
        self.metadata = metadata
    }

    /// The server's limits for a string field, in Unicode code points (the server counts
    /// with Python's `len`, which Swift's `String.count` doesn't match).
    static let maxFieldLength = 255

    /// Why the server would reject this event, or nil if it's valid. Mirrors the server's
    /// EventCreate rules: a name of 1-255 characters that isn't blank, user and session ids of
    /// at most 255, and no NUL character in the name, ids, or metadata keys and values. One
    /// invalid event makes the server reject its whole batch (422), so `track` checks first.
    var validationProblem: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "the name is empty"
        }
        let limited = [("name", name), ("user id", userId), ("session id", sessionId)]
        for (field, value) in limited {
            guard let value else { continue }
            if value.unicodeScalars.count > Self.maxFieldLength {
                return "the \(field) is longer than \(Self.maxFieldLength) characters"
            }
            if value.contains("\0") {
                return "the \(field) contains a NUL character"
            }
        }
        if metadata.contains(where: { $0.key.contains("\0") || $0.value.contains("\0") }) {
            return "the metadata contains a NUL character"
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, name, timestamp, metadata
        case userId = "user_id"
        case sessionId = "session_id"
    }
}
