# User Management Guide

Complete guide to managing user identity and sessions in LuxAnalytics.

## Overview

LuxAnalytics provides flexible user and session management that respects privacy while enabling meaningful analytics. All user management APIs are async and thread-safe.

## User Identification

### Setting User Identity

```swift
let analytics = await LuxAnalytics.shared

// Set user ID when user logs in
await analytics.setUser("user_12345")

// Clear user ID when user logs out
await analytics.setUser(nil)

// Get current user ID
let currentUser = await analytics.getCurrentUser()
print("Current user: \(currentUser ?? "anonymous")")
```

### User ID Best Practices

**✅ Good user IDs:**
```swift
// Internal user IDs (not PII)
await analytics.setUser("user_12345")
await analytics.setUser("account_67890")
await analytics.setUser(UUID().uuidString)

// Hashed identifiers
let hashedEmail = userEmail.sha256Hash
await analytics.setUser(hashedEmail)
```

**❌ Avoid PII as user IDs:**
```swift
// Don't use email addresses
await analytics.setUser("john@example.com")  // ❌ PII

// Don't use names
await analytics.setUser("John Smith")  // ❌ PII

// Don't use phone numbers
await analytics.setUser("+1234567890")  // ❌ PII
```

### Anonymous vs Identified Users

```swift
class UserManager {
    static func handleLogin(_ userAccount: UserAccount) async {
        // Set identified user
        let analytics = await LuxAnalytics.shared
        await analytics.setUser(userAccount.analyticsId)
        
        // Track login event
        try? await analytics.track("user_logged_in", metadata: [
            "login_method": userAccount.loginMethod,
            "account_type": userAccount.type,
            "days_since_registration": userAccount.daysSinceRegistration
        ])
    }
    
    static func handleLogout() async {
        let analytics = await LuxAnalytics.shared
        
        // Track logout before clearing user
        try? await analytics.track("user_logged_out")
        
        // Clear user identity
        await analytics.setUser(nil)
    }
    
    static func handleRegistration(_ newUser: UserAccount) async {
        let analytics = await LuxAnalytics.shared
        
        // Set new user ID
        await analytics.setUser(newUser.analyticsId)
        
        // Track registration
        try? await analytics.track("user_registered", metadata: [
            "registration_method": newUser.registrationMethod,
            "account_type": newUser.type,
            "referral_source": newUser.referralSource
        ])
    }
}
```

## Session Management

### Session Lifecycle

```swift
class SessionManager {
    static func startSession() async {
        let sessionId = UUID().uuidString
        let analytics = await LuxAnalytics.shared
        
        await analytics.setSession(sessionId)
        
        try? await analytics.track("session_started", metadata: [
            "session_id": sessionId,
            "app_version": Bundle.main.appVersion,
            "device_model": UIDevice.current.model,
            "ios_version": UIDevice.current.systemVersion
        ])
    }
    
    static func endSession() async {
        let analytics = await LuxAnalytics.shared
        
        guard let sessionId = await analytics.getCurrentSession() else { return }
        
        try? await analytics.track("session_ended", metadata: [
            "session_id": sessionId,
            "session_duration": getSessionDuration()
        ])
        
        await analytics.setSession(nil)
    }
    
    private static func getSessionDuration() -> TimeInterval {
        // Calculate session duration
        return Date().timeIntervalSince(sessionStartTime)
    }
}
```

### Automatic Session Management

```swift
@main
struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        Task {
            try await LuxAnalytics.quickStart(dsn: "your-dsn")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { phase in
            Task {
                switch phase {
                case .active:
                    await SessionManager.startSession()
                case .background, .inactive:
                    await SessionManager.endSession()
                @unknown default:
                    break
                }
            }
        }
    }
}
```

### Session Context in Events

All events automatically include current user and session context:

```swift
// When you track an event
try await analytics.track("purchase_completed", metadata: [
    "product_id": "premium_plan",
    "amount": "9.99"
])

// The SDK automatically adds:
// {
//   "name": "purchase_completed",
//   "user_id": "user_12345",        // Current user
//   "session_id": "session_abc123", // Current session
//   "metadata": {
//     "product_id": "premium_plan",
//     "amount": "9.99"
//   },
//   "timestamp": "2025-07-13T12:00:00Z"
// }
```

## Advanced User Management

### User Properties

Track user attributes without using them as identifiers:

```swift
extension LuxAnalytics {
    static func updateUserProperties(_ properties: [String: Any]) async {
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("user_properties_updated", metadata: properties)
    }
}

// Usage
await LuxAnalytics.updateUserProperties([
    "subscription_tier": "premium",
    "account_age_days": 45,
    "preferred_language": "en",
    "notification_preferences": ["email", "push"],
    "feature_flags": ["new_ui", "beta_features"]
])
```

### User Segmentation

Track user segments for analytics without storing PII:

```swift
class UserSegmentation {
    static func trackUserSegment() async {
        let analytics = await LuxAnalytics.shared
        
        let segment = await determineUserSegment()
        
        try? await analytics.track("user_segment_identified", metadata: [
            "segment": segment,
            "segment_criteria": getSegmentCriteria(segment),
            "confidence_score": getSegmentConfidence(segment)
        ])
    }
    
    private static func determineUserSegment() async -> String {
        // Determine segment based on user behavior, not PII
        let daysSinceInstall = await getDaysSinceInstall()
        let purchaseHistory = await getPurchaseHistory()
        let engagementLevel = await getEngagementLevel()
        
        switch (daysSinceInstall, purchaseHistory.count, engagementLevel) {
        case (0...7, 0, _):
            return "new_user"
        case (8...30, 0, .high):
            return "engaged_free_user"
        case (_, 1..., .high):
            return "active_customer"
        case (31..., 0, .low):
            return "dormant_user"
        default:
            return "casual_user"
        }
    }
}
```

### Cross-Device User Tracking

Handle users across multiple devices:

```swift
class CrossDeviceTracking {
    static func linkUserAccount(_ accountId: String) async {
        let analytics = await LuxAnalytics.shared
        
        // Generate device-specific identifier
        let deviceId = await getOrCreateDeviceId()
        
        await analytics.setUser(accountId)
        
        try? await analytics.track("account_linked_to_device", metadata: [
            "account_id": accountId,
            "device_id": deviceId,
            "link_method": "login",
            "previous_user_id": await getPreviousUserId(),
            "device_type": UIDevice.current.model
        ])
    }
    
    static func unlinkUserAccount() async {
        let analytics = await LuxAnalytics.shared
        let currentUser = await analytics.getCurrentUser()
        
        if let userId = currentUser {
            try? await analytics.track("account_unlinked_from_device", metadata: [
                "account_id": userId,
                "device_id": await getOrCreateDeviceId(),
                "unlink_method": "logout"
            ])
        }
        
        await analytics.setUser(nil)
    }
    
    private static func getOrCreateDeviceId() async -> String {
        if let existingId = UserDefaults.standard.string(forKey: "analytics_device_id") {
            return existingId
        }
        
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "analytics_device_id")
        return newId
    }
}
```

## Privacy-Compliant User Tracking

### GDPR Compliance

```swift
class PrivacyCompliantUserManager {
    static func requestTrackingConsent() async -> Bool {
        // Show privacy consent UI
        let consent = await showConsentDialog()
        
        UserDefaults.standard.set(consent, forKey: "analytics_consent")
        
        if consent {
            await enableAnalytics()
        } else {
            await disableAnalytics()
        }
        
        return consent
    }
    
    static func enableAnalytics() async {
        // Initialize with user consent
        try? await LuxAnalytics.quickStart(dsn: "your-dsn")
        
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("analytics_consent_granted")
    }
    
    static func disableAnalytics() async {
        // Disable and clear data
        await AnalyticsSettings.shared.setEnabled(false)
        await LuxAnalytics.clearQueue()
        
        UserDefaults.standard.removeObject(forKey: "analytics_consent")
    }
    
    static func handleDataDeletionRequest() async {
        let analytics = await LuxAnalytics.shared
        let currentUser = await analytics.getCurrentUser()
        
        if let userId = currentUser {
            // Track deletion request (before clearing)
            try? await analytics.track("user_data_deletion_requested", metadata: [
                "user_id": userId,
                "request_timestamp": ISO8601DateFormatter().string(from: Date())
            ])
            
            // Clear local data
            await analytics.setUser(nil)
            await analytics.setSession(nil)
            await LuxAnalytics.clearQueue()
        }
    }
}
```

### User Data Export

Provide user data export capabilities:

```swift
class UserDataExporter {
    static func exportUserData() async -> [String: Any] {
        let analytics = await LuxAnalytics.shared
        let currentUser = await analytics.getCurrentUser()
        let currentSession = await analytics.getCurrentSession()
        let queueStats = await LuxAnalytics.getQueueStats()
        
        return [
            "user_id": currentUser ?? NSNull(),
            "session_id": currentSession ?? NSNull(),
            "events_queued": queueStats.totalEvents,
            "queue_size_bytes": queueStats.totalSizeBytes,
            "export_timestamp": ISO8601DateFormatter().string(from: Date()),
            "sdk_version": LuxAnalyticsVersion.current
        ]
    }
    
    static func generateUserDataReport() async -> String {
        let data = await exportUserData()
        
        let report = """
        LuxAnalytics User Data Report
        Generated: \(data["export_timestamp"] ?? "unknown")
        
        User Information:
        - User ID: \(data["user_id"] ?? "none")
        - Current Session: \(data["session_id"] ?? "none")
        
        Analytics Data:
        - Queued Events: \(data["events_queued"] ?? 0)
        - Data Size: \(data["queue_size_bytes"] ?? 0) bytes
        
        SDK Information:
        - Version: \(data["sdk_version"] ?? "unknown")
        
        Note: This report shows only local device data.
        For complete analytics data, contact your analytics provider.
        """
        
        return report
    }
}
```

## User Lifecycle Tracking

### Onboarding Journey

```swift
class OnboardingTracker {
    private static var onboardingStartTime: Date?
    private static var completedSteps: [String] = []
    
    static func startOnboarding() async {
        onboardingStartTime = Date()
        completedSteps = []
        
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("onboarding_started", metadata: [
            "user_type": await analytics.getCurrentUser() != nil ? "returning" : "new",
            "start_time": ISO8601DateFormatter().string(from: Date())
        ])
    }
    
    static func completeOnboardingStep(_ stepName: String) async {
        completedSteps.append(stepName)
        
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("onboarding_step_completed", metadata: [
            "step_name": stepName,
            "step_number": completedSteps.count,
            "time_since_start": Date().timeIntervalSince(onboardingStartTime ?? Date()),
            "steps_completed": completedSteps
        ])
    }
    
    static func completeOnboarding(success: Bool) async {
        let totalTime = Date().timeIntervalSince(onboardingStartTime ?? Date())
        
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("onboarding_completed", metadata: [
            "success": success,
            "total_steps": completedSteps.count,
            "total_time": totalTime,
            "completion_rate": Double(completedSteps.count) / 5.0, // Assuming 5 total steps
            "steps_completed": completedSteps
        ])
        
        // Reset
        onboardingStartTime = nil
        completedSteps = []
    }
}
```

### User Retention Tracking

```swift
class RetentionTracker {
    static func trackUserReturn() async {
        let analytics = await LuxAnalytics.shared
        
        let lastActiveDate = UserDefaults.standard.object(forKey: "last_active_date") as? Date
        let now = Date()
        
        if let lastActive = lastActiveDate {
            let daysSinceLastActive = Calendar.current.dateComponents([.day], from: lastActive, to: now).day ?? 0
            
            try? await analytics.track("user_returned", metadata: [
                "days_since_last_active": daysSinceLastActive,
                "return_category": categorizeReturn(daysSinceLastActive),
                "total_app_opens": getTotalAppOpens()
            ])
        } else {
            try? await analytics.track("user_first_session")
        }
        
        UserDefaults.standard.set(now, forKey: "last_active_date")
    }
    
    private static func categorizeReturn(_ days: Int) -> String {
        switch days {
        case 0: return "same_day"
        case 1: return "next_day"
        case 2...7: return "within_week"
        case 8...30: return "within_month"
        default: return "long_term_return"
        }
    }
    
    private static func getTotalAppOpens() -> Int {
        let current = UserDefaults.standard.integer(forKey: "total_app_opens")
        let updated = current + 1
        UserDefaults.standard.set(updated, forKey: "total_app_opens")
        return updated
    }
}
```

## Testing User Management

### User Flow Testing

```swift
#if DEBUG
class UserManagementTester {
    static func runUserFlowTest() async {
        print("🧪 Testing user management flow...")
        
        let analytics = await LuxAnalytics.shared
        
        // Test anonymous user
        let initialUser = await analytics.getCurrentUser()
        print("Initial user: \(initialUser ?? "anonymous")")
        
        // Test user login
        await analytics.setUser("test_user_123")
        let loggedInUser = await analytics.getCurrentUser()
        print("After login: \(loggedInUser ?? "none")")
        
        // Test session
        await analytics.setSession("test_session_456")
        let session = await analytics.getCurrentSession()
        print("Session: \(session ?? "none")")
        
        // Test event with user context
        try? await analytics.track("test_event")
        
        // Test logout
        await analytics.setUser(nil)
        await analytics.setSession(nil)
        
        let loggedOutUser = await analytics.getCurrentUser()
        print("After logout: \(loggedOutUser ?? "anonymous")")
        
        print("✅ User management test completed")
    }
}

// Run test during development
#if DEBUG
Task {
    await UserManagementTester.runUserFlowTest()
}
#endif
```

## Best Practices Summary

### ✅ Do

- Use internal user IDs, not PII
- Clear user data on logout
- Respect user privacy preferences
- Track user lifecycle events
- Use sessions to group related events
- Implement proper consent management

### ❌ Don't

- Store email addresses as user IDs
- Track users without consent
- Keep user data after deletion requests
- Use PII in user identification
- Track across devices without disclosure
- Ignore privacy regulations

## Next Steps

- [📊 Event Tracking](Event-Tracking.md) - Track user actions effectively
- [🔒 Privacy & Security](Privacy-Security.md) - Protect user data
- [💡 Best Practices](Best-Practices.md) - Production-ready patterns
- [🐛 Troubleshooting](Troubleshooting.md) - Debug user management issues