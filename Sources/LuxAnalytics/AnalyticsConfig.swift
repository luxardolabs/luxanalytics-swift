import Foundation

public struct AnalyticsConfig: Sendable {
    public static var endpoint: URL {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "LUX_API_URL") as? String,
              let url = URL(string: urlString) else {
            fatalError("Missing LUX_API_URL in Info.plist")
        }
        return url
    }

    public static var hmacSecret: String {
        guard let secret = Bundle.main.object(forInfoDictionaryKey: "LUX_HMAC_SECRET") as? String else {
            fatalError("Missing LUX_HMAC_SECRET in Info.plist")
        }
        return secret
    }

    public static var keyId: String {
        guard let keyId = Bundle.main.object(forInfoDictionaryKey: "LUX_KEY_ID") as? String else {
            fatalError("Missing LUX_KEY_ID in Info.plist")
        }
        return keyId
    }
}
