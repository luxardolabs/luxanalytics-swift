import Foundation
#if canImport(UIKit)
import UIKit
#endif
import CryptoKit
import Security

public actor AppAnalyticsContext {
    static let shared = AppAnalyticsContext()
    
    // Cached context - only changes on app restart
    private var cachedContext: [String: String]?
    private var deviceID: String?
    
    private init() {}
    
    /// Get current analytics context (cached)
    public func current() async -> [String: String] {
        if let cached = cachedContext {
            return cached
        }
        
        // Generate context once and cache it
        let context = await generateContext()
        cachedContext = context
        return context
    }
    
    /// Force refresh the cached context (rarely needed)
    public func refresh() async {
        cachedContext = await generateContext()
    }
    
    /// Modern TestFlight detection for iOS 18+
    private static func isTestFlightBuild() -> Bool {
        // Fallback: Check for embedded.mobileprovision (indicates development/TestFlight)
        return Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil
    }
    
    private func generateContext() async -> [String: String] {
        let deviceId = await getOrCreateDeviceID()
        
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let systemVersion = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        #if canImport(UIKit)
        return await MainActor.run {
            let screenSize = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.screen.bounds.size ?? .zero
            return [
                "device_model": UIDevice.modelCode(),
                "device_type": UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone",
                "screen_resolution": "\(Int(screenSize.width))x\(Int(screenSize.height))",
                "system_version": systemVersion,
                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "build_number": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
                "locale": Locale.current.identifier,
                "timezone": TimeZone.current.identifier,
                "device_id": deviceId,
                "is_testflight": Self.isTestFlightBuild() ? "true" : "false",
                "platform": "ios"
            ]
        }
        #else
        // Non-iOS platforms
        return [
            "device_model": "Unknown",
            "device_type": "Unknown",
            "screen_resolution": "Unknown",
            "system_version": systemVersion,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build_number": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier,
            "device_id": deviceId,
            "is_testflight": "false",
            "platform": "ios"
        ]
        #endif
    }

    private static let keychainAccount = "com.luxardolabs.LuxAnalytics.deviceID"
    private static let keychainService = "LuxAnalytics"

    private func getOrCreateDeviceID() async -> String {
        if let cached = deviceID {
            return cached
        }

        // Try to read existing ID from Keychain (survives app reinstalls)
        if let stored = Self.readFromKeychain() {
            deviceID = stored
            return stored
        }

        // Generate a new device ID
        #if canImport(UIKit)
        let seed = await MainActor.run { UIDevice.current.identifierForVendor?.uuidString } ?? UUID().uuidString
        #else
        let seed = UUID().uuidString
        #endif

        let hash = SHA256.hash(data: Data(seed.utf8))
        let id = hash.map { String(format: "%02x", $0) }.joined()

        // Persist to Keychain
        Self.writeToKeychain(id)

        deviceID = id
        return id
    }

    private static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let id = String(data: data, encoding: .utf8) else {
            return nil
        }
        return id
    }

    private static func writeToKeychain(_ id: String) {
        // Delete any existing entry first: a bare SecItemAdd fails with
        // errSecDuplicateItem when one already exists, so a rotated ID would
        // silently never persist. Delete-then-add makes the write idempotent.
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrService as String: keychainService
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = Data(id.utf8)
        // After-first-unlock (this-device-only) keeps analytics working while the
        // device is locked; the device ID is a non-secret SHA256 of identifierForVendor.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            SecureLogger.log(
                "Failed to persist device ID to Keychain (status \(status))",
                category: .security,
                level: .warning
            )
        }
    }
}

#if canImport(UIKit)
extension UIDevice {
    /// Get device model code
    /// This is safe to call from any thread as it doesn't access UIKit
    nonisolated public static func modelCode() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
#endif
