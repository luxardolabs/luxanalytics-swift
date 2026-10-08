import CryptoKit
import Foundation
import Security

#if canImport(UIKit)
import UIKit
#endif

actor AppAnalyticsContext {
    static let shared = AppAnalyticsContext()

    // Cached context - only changes on app restart
    private var cachedContext: [String: String]?
    private var deviceID: String?

    private init() {}

    /// Get current analytics context (cached)
    func current() async -> [String: String] {
        if let cached = cachedContext {
            return cached
        }

        // Generate context once and cache it
        let context = await generateContext()
        cachedContext = context
        return context
    }

    /// Force refresh the cached context (rarely needed)
    func refresh() async {
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
            let screenSize =
                UIApplication.shared.connectedScenes
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
                "platform": "ios",
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
            "platform": "ios",
        ]
        #endif
    }

    /// The device ID attached to events. Created on first use.
    func currentDeviceID() async -> String {
        await getOrCreateDeviceID()
    }

    /// Replace the device ID with a new random one and persist it.
    ///
    /// The new ID is seeded from a random UUID, not `identifierForVendor`:
    /// the vendor ID doesn't change within an install, so re-deriving from it
    /// would hand back the same ID and the reset would do nothing.
    /// - Returns: The new device ID.
    @discardableResult
    func resetDeviceID() -> String {
        let id = Self.makeDeviceID(seed: UUID().uuidString)
        Self.writeToKeychain(id)
        deviceID = id
        // The cached context carries the old ID.
        cachedContext = nil
        return id
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

        let id = Self.makeDeviceID(seed: seed)

        // Persist to Keychain
        Self.writeToKeychain(id)

        deviceID = id
        return id
    }

    /// A device ID is the hex SHA-256 of its seed, so the seed itself is never sent.
    private static func makeDeviceID(seed: String) -> String {
        SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
            let data = result as? Data,
            let id = String(data: data, encoding: .utf8)
        else {
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
            kSecAttrService as String: keychainService,
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = Data(id.utf8)
        // After-first-unlock keeps analytics working while the device is locked; the
        // device ID is a non-secret hash, so it needs no stronger protection.
        // This-device-only keeps it out of backups and off other devices, but a
        // Keychain item still survives uninstall/reinstall on the same device.
        // That is why the ID persists across reinstalls (see resetDeviceID()).
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
    nonisolated static func modelCode() -> String {
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
