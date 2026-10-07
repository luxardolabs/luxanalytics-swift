# Event Tracking Guide

Complete guide to effective event tracking with LuxAnalytics.

## Event Design Principles

### 1. Descriptive and Consistent Naming

Use clear, consistent event names that describe user actions:

```swift
// ✅ Good: Clear action + object + context
try await analytics.track("button_tapped_signup_form")
try await analytics.track("video_started_onboarding_tutorial")
try await analytics.track("purchase_completed_premium_subscription")

// ❌ Bad: Vague or inconsistent
try await analytics.track("click")
try await analytics.track("action_performed")
try await analytics.track("event123")
```

### 2. Naming Conventions

Choose a convention and stick to it:

**Recommended pattern**: `verb_noun_context`

```swift
// User actions
"button_tapped_home_screen"
"form_submitted_signup_page"
"link_clicked_navigation_menu"

// System events  
"screen_viewed_profile_page"
"error_occurred_payment_processing"
"session_started_app_launch"

// Business events
"purchase_completed_premium_tier"
"trial_started_free_plan"
"subscription_cancelled_user_request"
```

### 3. Event Categories

Organize events into logical categories:

```swift
// User Interface Events
"screen_viewed"
"button_tapped"
"form_submitted"
"navigation_occurred"

// Business Events
"purchase_completed"
"subscription_started"
"trial_expired"
"referral_sent"

// System Events
"app_launched"
"app_backgrounded"
"error_occurred"
"performance_measured"

// User Behavior
"feature_discovered"
"tutorial_completed"
"search_performed"
"content_shared"
```

## Core Tracking Patterns

### Screen Tracking

Track when users view different screens:

```swift
extension View {
    func trackScreen(_ screenName: String, properties: [String: Any] = [:]) -> some View {
        self.task {
            let analytics = await LuxAnalytics.shared
            var metadata = properties
            metadata["screen_name"] = screenName
            metadata["timestamp"] = ISO8601DateFormatter().string(from: Date())
            
            try? await analytics.track("screen_viewed", metadata: metadata)
        }
    }
}

// Usage
struct ProductDetailView: View {
    let product: Product
    
    var body: some View {
        VStack {
            // Product content
        }
        .trackScreen("product_detail", properties: [
            "product_id": product.id,
            "product_category": product.category,
            "price_range": product.priceRange
        ])
    }
}
```

### User Actions

Track meaningful user interactions:

```swift
// Button taps with context
Button("Add to Cart") {
    Task {
        let analytics = await LuxAnalytics.shared
        try await analytics.track("product_added_to_cart", metadata: [
            "product_id": product.id,
            "product_name": product.name,
            "product_price": product.price,
            "add_source": "product_detail_page",
            "cart_size_before": cartItems.count
        ])
        
        // Handle the actual action
        cartManager.addProduct(product)
    }
}

// Form interactions
TextField("Email", text: $email)
    .onSubmit {
        Task {
            let analytics = await LuxAnalytics.shared
            try? await analytics.track("email_field_completed", metadata: [
                "form_name": "signup_form",
                "field_order": 1,
                "input_method": "keyboard"
            ])
        }
    }
```

### Business Events

Track key business metrics:

```swift
// Purchase tracking
func trackPurchase(_ purchase: Purchase) async {
    let analytics = await LuxAnalytics.shared
    
    try? await analytics.track("purchase_completed", metadata: [
        "transaction_id": purchase.id,
        "product_ids": purchase.items.map(\.id),
        "total_amount": purchase.total,
        "currency": purchase.currency,
        "payment_method": purchase.paymentMethod,
        "discount_applied": purchase.discount > 0,
        "item_count": purchase.items.count,
        "purchase_category": purchase.category
    ])
}

// Subscription events
func trackSubscription(_ subscription: Subscription) async {
    let analytics = await LuxAnalytics.shared
    
    try? await analytics.track("subscription_started", metadata: [
        "plan_id": subscription.planId,
        "plan_name": subscription.planName,
        "billing_cycle": subscription.billingCycle,
        "trial_days": subscription.trialDays,
        "monthly_price": subscription.monthlyPrice,
        "signup_source": subscription.source
    ])
}
```

## Advanced Event Patterns

### User Journey Tracking

Track multi-step user flows:

```swift
class UserJourneyTracker: ObservableObject {
    private var currentJourney: String?
    private var journeyStartTime: Date?
    private var journeySteps: [String] = []
    
    func startJourney(_ journeyName: String) async {
        currentJourney = journeyName
        journeyStartTime = Date()
        journeySteps = []
        
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("user_journey_started", metadata: [
            "journey_name": journeyName,
            "start_time": ISO8601DateFormatter().string(from: Date())
        ])
    }
    
    func trackStep(_ stepName: String, properties: [String: Any] = [:]) async {
        guard let journey = currentJourney else { return }
        
        journeySteps.append(stepName)
        let stepNumber = journeySteps.count
        
        let analytics = await LuxAnalytics.shared
        var metadata = properties
        metadata["journey_name"] = journey
        metadata["step_name"] = stepName
        metadata["step_number"] = stepNumber
        metadata["time_since_start"] = Date().timeIntervalSince(journeyStartTime ?? Date())
        
        try? await analytics.track("user_journey_step", metadata: metadata)
    }
    
    func completeJourney(success: Bool, properties: [String: Any] = [:]) async {
        guard let journey = currentJourney,
              let startTime = journeyStartTime else { return }
        
        let analytics = await LuxAnalytics.shared
        var metadata = properties
        metadata["journey_name"] = journey
        metadata["success"] = success
        metadata["total_steps"] = journeySteps.count
        metadata["total_time"] = Date().timeIntervalSince(startTime)
        metadata["steps_completed"] = journeySteps
        
        try? await analytics.track("user_journey_completed", metadata: metadata)
        
        // Reset
        currentJourney = nil
        journeyStartTime = nil
        journeySteps = []
    }
}

// Usage
struct OnboardingFlow: View {
    @StateObject private var journeyTracker = UserJourneyTracker()
    
    var body: some View {
        // Onboarding content
        .task {
            await journeyTracker.startJourney("user_onboarding")
        }
        .onDisappear {
            Task {
                await journeyTracker.completeJourney(success: true)
            }
        }
    }
}
```

### Performance Tracking

Monitor app performance metrics:

```swift
class PerformanceTracker {
    static func trackScreenLoadTime(_ screenName: String, loadTime: TimeInterval) async {
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("screen_performance_measured", metadata: [
            "screen_name": screenName,
            "load_time_ms": Int(loadTime * 1000),
            "performance_category": categorizeLoadTime(loadTime),
            "device_model": UIDevice.current.model,
            "ios_version": UIDevice.current.systemVersion
        ])
    }
    
    static func trackNetworkRequest(_ endpoint: String, duration: TimeInterval, success: Bool) async {
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("network_request_completed", metadata: [
            "endpoint": endpoint,
            "duration_ms": Int(duration * 1000),
            "success": success,
            "performance_category": categorizeNetworkTime(duration)
        ])
    }
    
    private static func categorizeLoadTime(_ time: TimeInterval) -> String {
        switch time {
        case ..<0.1: return "instant"
        case 0.1..<0.5: return "fast"
        case 0.5..<2.0: return "acceptable"
        case 2.0..<5.0: return "slow"
        default: return "very_slow"
        }
    }
}

// Usage with timing
struct ContentView: View {
    @State private var loadStartTime = Date()
    
    var body: some View {
        Text("Content")
            .onAppear {
                loadStartTime = Date()
            }
            .task {
                // Simulate content loading
                await loadContent()
                
                let loadTime = Date().timeIntervalSince(loadStartTime)
                await PerformanceTracker.trackScreenLoadTime("content_view", loadTime: loadTime)
            }
    }
}
```

### A/B Testing Integration

Track experiment exposure and outcomes:

```swift
class ExperimentTracker {
    static func trackExperimentExposure(_ experimentName: String, variant: String) async {
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("experiment_exposure", metadata: [
            "experiment_name": experimentName,
            "variant": variant,
            "user_segment": await getUserSegment(),
            "exposure_time": ISO8601DateFormatter().string(from: Date())
        ])
    }
    
    static func trackExperimentOutcome(_ experimentName: String, variant: String, outcome: String, value: Double? = nil) async {
        let analytics = await LuxAnalytics.shared
        
        var metadata: [String: Any] = [
            "experiment_name": experimentName,
            "variant": variant,
            "outcome": outcome
        ]
        
        if let value = value {
            metadata["outcome_value"] = value
        }
        
        try? await analytics.track("experiment_outcome", metadata: metadata)
    }
    
    private static func getUserSegment() async -> String {
        // Determine user segment based on app state
        return "new_user" // or "returning_user", "premium_user", etc.
    }
}

// Usage
struct ExperimentalFeatureView: View {
    let variant: String = "variant_b"
    
    var body: some View {
        VStack {
            if variant == "variant_a" {
                OldUIComponent()
            } else {
                NewUIComponent()
            }
        }
        .task {
            await ExperimentTracker.trackExperimentExposure("new_ui_test", variant: variant)
        }
        .onAppear {
            // Track when user actually sees the variant
            Task {
                await ExperimentTracker.trackExperimentOutcome(
                    "new_ui_test",
                    variant: variant,
                    outcome: "variant_viewed"
                )
            }
        }
    }
}
```

## Event Metadata Best Practices

### Rich Context

Include relevant context in event metadata:

```swift
// ✅ Rich context
try await analytics.track("video_playback_started", metadata: [
    "video_id": "tutorial_001",
    "video_title": "Getting Started",
    "video_duration": 120,
    "video_category": "tutorial",
    "playback_quality": "1080p",
    "playback_source": "featured_content",
    "user_subscription_tier": "premium",
    "device_orientation": "landscape",
    "network_type": "wifi"
])

// ❌ Minimal context
try await analytics.track("video_started")
```

### Structured Metadata

Use consistent data types and structures:

```swift
// ✅ Structured metadata
struct EventMetadata {
    static func purchaseCompleted(
        transactionId: String,
        items: [PurchaseItem],
        total: Decimal,
        currency: String,
        paymentMethod: String
    ) -> [String: Any] {
        return [
            "transaction_id": transactionId,
            "item_count": items.count,
            "total_amount": NSDecimalNumber(decimal: total).doubleValue,
            "currency": currency,
            "payment_method": paymentMethod,
            "item_categories": Set(items.map(\.category)).sorted(),
            "has_discount": items.contains { $0.discount > 0 },
            "purchase_timestamp": ISO8601DateFormatter().string(from: Date())
        ]
    }
}

// Usage
let metadata = EventMetadata.purchaseCompleted(
    transactionId: purchase.id,
    items: purchase.items,
    total: purchase.total,
    currency: purchase.currency,
    paymentMethod: purchase.paymentMethod
)

try await analytics.track("purchase_completed", metadata: metadata)
```

### Privacy-Conscious Metadata

Avoid PII and use aggregated data:

```swift
// ✅ Privacy-conscious
try await analytics.track("user_profile_updated", metadata: [
    "profile_completion_percentage": 85,
    "fields_updated": ["bio", "interests"],
    "account_age_days": accountAgeDays,
    "subscription_tier": "premium"
])

// ❌ Contains PII
try await analytics.track("user_profile_updated", metadata: [
    "user_email": "john@example.com",  // PII
    "full_name": "John Smith",         // PII
    "phone_number": "+1234567890"      // PII
])
```

## Error and Edge Case Tracking

### Error Tracking

Track meaningful errors without exposing sensitive data:

```swift
func trackError(_ error: Error, context: String) async {
    let analytics = await LuxAnalytics.shared
    
    let errorType = String(describing: type(of: error))
    let errorDescription = error.localizedDescription
    
    try? await analytics.track("error_occurred", metadata: [
        "error_type": errorType,
        "error_context": context,
        "error_description": SecureLogger.redact(errorDescription),
        "error_domain": (error as NSError).domain,
        "error_code": (error as NSError).code,
        "app_version": Bundle.main.appVersion,
        "ios_version": UIDevice.current.systemVersion
    ])
}

// Usage
do {
    try await performNetworkRequest()
} catch {
    await trackError(error, context: "user_login_attempt")
    // Handle error appropriately
}
```

### Feature Usage Tracking

Track how users interact with features:

```swift
class FeatureUsageTracker {
    static func trackFeatureDiscovered(_ featureName: String, discoveryMethod: String) async {
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("feature_discovered", metadata: [
            "feature_name": featureName,
            "discovery_method": discoveryMethod,  // "navigation", "search", "tutorial", etc.
            "user_session_length": getCurrentSessionLength(),
            "features_used_this_session": getSessionFeatures().count
        ])
    }
    
    static func trackFeatureFirstUse(_ featureName: String) async {
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("feature_first_use", metadata: [
            "feature_name": featureName,
            "days_since_install": daysSinceInstall(),
            "user_tier": getCurrentUserTier()
        ])
    }
    
    static func trackFeatureEngagement(_ featureName: String, duration: TimeInterval, interactionCount: Int) async {
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("feature_engagement_measured", metadata: [
            "feature_name": featureName,
            "session_duration": duration,
            "interaction_count": interactionCount,
            "engagement_level": categorizeEngagement(duration: duration, interactions: interactionCount)
        ])
    }
}
```

## Testing Your Events

### Event Validation

Validate events during development:

```swift
#if DEBUG
extension LuxAnalytics {
    static func validateEvent(_ name: String, metadata: [String: Any]) {
        // Check event naming convention
        let components = name.split(separator: "_")
        guard components.count >= 2 else {
            print("⚠️ Event name should follow verb_noun pattern: \(name)")
        }
        
        // Check for PII in metadata
        for (key, value) in metadata {
            if let stringValue = value as? String {
                let filtered = PIIFilter.filterPII(from: [key: stringValue])
                if filtered[key] as? String != stringValue {
                    print("⚠️ Potential PII detected in \(key): \(stringValue)")
                }
            }
        }
        
        // Check metadata size
        do {
            let data = try JSONSerialization.data(withJSONObject: metadata)
            if data.count > 32_768 { // 32KB limit
                print("⚠️ Large metadata size: \(data.count) bytes")
            }
        } catch {
            print("⚠️ Invalid metadata format: \(error)")
        }
    }
}
#endif
```

### Event Debugging

Monitor events during development:

```swift
#if DEBUG
Task {
    for await notification in LuxAnalyticsEvents.eventStream {
        switch notification {
        case .eventQueued(let event):
            print("📤 \(event.name)")
            if !event.metadata.isEmpty {
                print("   📋 \(event.metadata)")
            }
            
        case .eventsSent(let events):
            print("✅ Sent batch of \(events.count) events")
            
        case .eventsFailed(let events, let error):
            print("❌ Failed to send \(events.count) events")
            print("   Error: \(error)")
            
        case .eventsDropped(let count, let reason):
            print("⚠️ Dropped \(count) events: \(reason)")
            
        case .eventsExpired(let events):
            print("⏰ Expired \(events.count) old events")
        }
    }
}
#endif
```

## Event Documentation

### Event Schema Documentation

Document your events for team consistency:

```swift
/**
 * Standard Events Reference
 * 
 * Screen Views:
 * - screen_viewed: User views a screen
 *   - screen_name (string): Name of the screen
 *   - screen_category (string): Category (main, settings, etc.)
 *   - previous_screen (string): Previous screen name
 *   - navigation_method (string): How user navigated (tap, swipe, etc.)
 *
 * User Actions:
 * - button_tapped: User taps a button
 *   - button_name (string): Button identifier
 *   - button_location (string): Where button is located
 *   - screen_name (string): Current screen
 *
 * Business Events:
 * - purchase_completed: User completes a purchase
 *   - transaction_id (string): Unique transaction ID
 *   - total_amount (number): Total purchase amount
 *   - currency (string): Currency code (USD, EUR, etc.)
 *   - item_count (number): Number of items purchased
 *   - payment_method (string): Payment method used
 */
```

## Next Steps

- [💡 Best Practices](Best-Practices.md) - Production-ready patterns
- [🔒 Privacy & Security](Privacy-Security.md) - Protect user data in events
- [🔧 Configuration](Configuration.md) - Optimize event processing
- [🐛 Troubleshooting](Troubleshooting.md) - Debug event tracking issues