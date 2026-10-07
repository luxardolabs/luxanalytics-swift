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
    
    enum CodingKeys: String, CodingKey {
        case id, name, timestamp, metadata
        case userId = "user_id"
        case sessionId = "session_id"
    }
    
    func toDictionary() throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        let json = try JSONSerialization.jsonObject(with: data)
        return json as! [String: Any]
    }
}
