# Best Practices

Recommended patterns and practices for using LuxAnalytics effectively.

## Initialization

### ✅ Initialize Early and Asynchronously

```swift
@main
struct MyApp: App {
    init() {
        // Initialize SDK early but don't block app launch
        Task.detached {
            do {
                try await LuxAnalytics.quickStart(
                    dsn: "your-dsn",
                    debugLogging: false  // Disable in production
                )
            } catch {
                print("Failed to initialize analytics: \(error)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### ✅ Environment-Based Configuration

```swift
extension Bundle {
    var luxAnalyticsDSN: String? {
        #if DEBUG
        return "https://dev-key@dev.analytics.example.com/api/v1/events/dev-project"
        #else
        return object(forInfoDictionaryKey: "LuxAnalyticsDSN") as? String
        #endif
    }
}
```

## Event Tracking

### ✅ Use Descriptive Event Names

```swift
// ❌ Vague names
try await analytics.track("click")
try await analytics.track("action")

// ✅ Descriptive names
try await analytics.track("purchase_completed")
try await analytics.track("signup_button_tapped")
try await analytics.track("video_playback_started")
```

### ✅ Consistent Naming Convention

```swift
// Choose a convention and stick to it
// Example: verb_noun_location pattern

try await analytics.track("button_tapped_home_screen")
try await analytics.track("form_submitted_signup_page")
try await analytics.track("video_started_tutorial_section")
```

### ✅ Include Relevant Context

```swift
try await analytics.track("purchase_completed", metadata: [
    "product_id": "abc123",
    "amount": "49.99",
    "currency": "USD",
    "payment_method": "credit_card",
    "category": "premium_subscription"
])
```

### ✅ Privacy-Conscious Data

```swift
// ❌ Include PII
try await analytics.track("user_registered", metadata: [
    "email": "user@example.com",  // Don't include email
    "phone": "+1234567890"        // Don't include phone
])

// ✅ Use aggregated/anonymized data
try await analytics.track("user_registered", metadata: [
    "registration_method": "email",
    "user_type": "premium",
    "referral_source": "google_ads"
])
```

## Error Handling

### ✅ Graceful Error Handling

```swift
func trackEvent(_ name: String, metadata: [String: Any] = [:]) async {
    do {
        let analytics = await LuxAnalytics.shared
        try await analytics.track(name, metadata: metadata)
    } catch {
        // Log error but don't crash app
        print("Analytics tracking failed: \(error)")
        
        // Optional: Track analytics failures
        #if DEBUG
        print("Failed to track '\(name)': \(error)")
        #endif
    }
}
```

### ✅ Conditional Tracking

```swift
func trackEventIfEnabled(_ name: String, metadata: [String: Any] = [:]) async {
    // Respect user privacy preferences
    guard UserDefaults.standard.bool(forKey: "analytics_enabled") else {
        return
    }
    
    // Only track if SDK is initialized
    guard LuxAnalytics.isInitialized else {
        print("Analytics not initialized, skipping event: \(name)")
        return
    }
    
    await trackEvent(name, metadata: metadata)
}
```

## App Architecture Integration

### ✅ Create App-Specific Analytics Layer

```swift
@MainActor
class AppAnalytics: ObservableObject {
    static let shared = AppAnalytics()
    
    private init() {}
    
    func trackScreenView(_ screenName: String) async {
        await trackEvent("screen_viewed", metadata: [
            "screen_name": screenName,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
    }
    
    func trackUserAction(_ action: String, on screen: String) async {
        await trackEvent("user_action", metadata: [
            "action": action,
            "screen": screen,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
    }
    
    func trackPurchase(productId: String, amount: Double, currency: String) async {
        // Sanitize amount for privacy
        let amountRange = categorizeAmount(amount)
        
        await trackEvent("purchase_completed", metadata: [
            "product_id": productId,
            "amount_range": amountRange,
            "currency": currency
        ])
    }
    
    private func categorizeAmount(_ amount: Double) -> String {
        switch amount {
        case ..<10: return "$0-10"
        case 10..<50: return "$10-50"
        case 50..<100: return "$50-100"
        case 100..<500: return "$100-500"
        default: return "$500+"
        }
    }
    
    private func trackEvent(_ name: String, metadata: [String: Any] = [:]) async {
        guard UserDefaults.standard.bool(forKey: "analytics_enabled") else { return }
        
        do {
            let analytics = await LuxAnalytics.shared
            try await analytics.track(name, metadata: metadata)
        } catch {
            print("Analytics error: \(error)")
        }
    }
}
```

### ✅ SwiftUI Integration

```swift
extension View {
    func trackScreenView(_ screenName: String) -> some View {
        self.task {
            await AppAnalytics.shared.trackScreenView(screenName)
        }
    }
    
    func trackButtonTap(_ buttonName: String) -> some View {
        self.onTapGesture {
            Task {
                await AppAnalytics.shared.trackUserAction(
                    "button_tapped", 
                    metadata: ["button_name": buttonName]
                )
            }
        }
    }
}

// Usage
struct HomeView: View {
    var body: some View {
        VStack {
            Button("Get Started") {
                // Handle button action
            }
            .trackButtonTap("get_started_home")
        }
        .trackScreenView("home")
    }
}
```

## Performance Optimization

### ✅ Batch Related Events

```swift
// ❌ Track each item separately
for item in cartItems {
    try await analytics.track("item_added_to_cart", metadata: ["item_id": item.id])
}

// ✅ Track as single event with batch data
try await analytics.track("items_added_to_cart", metadata: [
    "item_count": cartItems.count,
    "total_value": cartItems.reduce(0) { $0 + $1.price },
    "item_categories": Set(cartItems.map(\.category)).joined(separator: ",")
])
```

### ✅ Efficient Queue Management

```swift
// Monitor queue health
Task {
    while true {
        let stats = await LuxAnalytics.getQueueStats()
        
        if stats.totalEvents > 400 {
            await LuxAnalytics.flush()  // Proactive flush
        }
        
        try await Task.sleep(for: .seconds(30))
    }
}
```

### ✅ Conditional Detailed Tracking

```swift
func trackDetailedUserBehavior(_ action: String) async {
    #if DEBUG
    // Detailed tracking in development
    await trackEvent("detailed_user_behavior", metadata: [
        "action": action,
        "timestamp": ISO8601DateFormatter().string(from: Date()),
        "app_version": Bundle.main.appVersion,
        "ios_version": UIDevice.current.systemVersion
    ])
    #else
    // Simplified tracking in production
    await trackEvent("user_behavior", metadata: ["action": action])
    #endif
}
```

## Privacy and Security

### ✅ Respect User Preferences

```swift
class AnalyticsPreferences: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "analytics_enabled")
        }
    }
    
    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "analytics_enabled")
    }
    
    func requestPermission() -> Bool {
        // Show user-friendly dialog explaining analytics
        // Return user's choice
        return true
    }
}
```

### ✅ Data Minimization

```swift
func trackPurchaseEvent(purchase: Purchase) async {
    // Only track necessary data
    await trackEvent("purchase_completed", metadata: [
        "category": purchase.category,           // ✅ Useful for analytics
        "amount_range": categorize(purchase.amount), // ✅ Privacy-safe
        "payment_method": purchase.paymentMethod,    // ✅ Useful insights
        // "user_email": purchase.userEmail,        // ❌ PII - don't include
        // "exact_amount": purchase.amount,         // ❌ Too specific
    ])
}
```

### ✅ Secure Configuration

```swift
// Store DSN securely
extension Bundle {
    var luxAnalyticsDSN: String? {
        // Try environment variable first
        if let envDSN = ProcessInfo.processInfo.environment["LUX_ANALYTICS_DSN"] {
            return envDSN
        }
        
        // Fall back to Info.plist
        return object(forInfoDictionaryKey: "LuxAnalyticsDSN") as? String
    }
}
```

## Testing

### ✅ Analytics Testing Strategy

```swift
#if DEBUG
extension LuxAnalytics {
    static func configureForTesting() async throws {
        try await quickStart(
            dsn: "https://test-key@test-server:8000/api/v1/events/test-project",
            debugLogging: true
        )
    }
    
    static func printQueueForDebugging() async {
        await LuxAnalyticsDebug.printQueue()
    }
}
#endif
```

### ✅ Mock Analytics for Unit Tests

```swift
protocol AnalyticsProtocol {
    func track(_ name: String, metadata: [String: Any]) async throws
}

extension LuxAnalytics: AnalyticsProtocol {}

class MockAnalytics: AnalyticsProtocol {
    var trackedEvents: [(name: String, metadata: [String: Any])] = []
    
    func track(_ name: String, metadata: [String: Any]) async throws {
        trackedEvents.append((name: name, metadata: metadata))
    }
}

// In your app code, use dependency injection
class ViewModel {
    private let analytics: AnalyticsProtocol
    
    init(analytics: AnalyticsProtocol = LuxAnalytics.shared) {
        self.analytics = analytics
    }
    
    func handleUserAction() async {
        try await analytics.track("user_action")
    }
}
```

## Monitoring and Debugging

### ✅ Real-time Event Monitoring

```swift
#if DEBUG
Task {
    for await notification in LuxAnalyticsEvents.eventStream {
        switch notification {
        case .eventQueued(let event):
            print("📤 Queued: \(event.name)")
        case .eventsSent(let events):
            print("✅ Sent \(events.count) events")
        case .eventsFailed(let events, let error):
            print("❌ Failed \(events.count) events: \(error)")
        case .eventsDropped(let count, let reason):
            print("⚠️ Dropped \(count) events: \(reason)")
        case .eventsExpired(let events):
            print("⏰ Expired \(events.count) events")
        }
    }
}
#endif
```

### ✅ Health Monitoring

```swift
func monitorAnalyticsHealth() {
    Task {
        while true {
            let isHealthy = await LuxAnalytics.healthCheck()
            let stats = await LuxAnalytics.getQueueStats()
            
            print("Analytics Health: \(isHealthy ? "✅" : "❌")")
            print("Queue: \(stats.totalEvents) events")
            
            if !isHealthy {
                // Alert development team
                print("⚠️ Analytics SDK unhealthy!")
            }
            
            try await Task.sleep(for: .minutes(5))
        }
    }
}
```

## Common Patterns

### ✅ User Journey Tracking

```swift
class UserJourneyTracker {
    private var journeyStart: Date?
    private var currentStep: String?
    
    func startJourney(_ journeyName: String) async {
        journeyStart = Date()
        currentStep = "started"
        
        await trackEvent("journey_started", metadata: [
            "journey_name": journeyName
        ])
    }
    
    func completeStep(_ stepName: String) async {
        let previousStep = currentStep
        currentStep = stepName
        
        await trackEvent("journey_step_completed", metadata: [
            "step_name": stepName,
            "previous_step": previousStep ?? "none",
            "time_since_start": Date().timeIntervalSince(journeyStart ?? Date())
        ])
    }
    
    func completeJourney(_ journeyName: String) async {
        let totalTime = Date().timeIntervalSince(journeyStart ?? Date())
        
        await trackEvent("journey_completed", metadata: [
            "journey_name": journeyName,
            "total_time": totalTime,
            "final_step": currentStep ?? "unknown"
        ])
        
        // Reset
        journeyStart = nil
        currentStep = nil
    }
}
```

### ✅ A/B Testing Integration

```swift
func trackVariantExposure(_ experimentName: String, variant: String) async {
    await trackEvent("experiment_exposure", metadata: [
        "experiment_name": experimentName,
        "variant": variant,
        "user_segment": getCurrentUserSegment()
    ])
}

func trackVariantOutcome(_ experimentName: String, variant: String, outcome: String) async {
    await trackEvent("experiment_outcome", metadata: [
        "experiment_name": experimentName,
        "variant": variant,
        "outcome": outcome
    ])
}
```

## Next Steps

- [API Reference](API-Reference.md) - Complete API documentation
- [Configuration Guide](Configuration.md) - Detailed configuration options
- [Troubleshooting](Troubleshooting.md) - Common issues and solutions