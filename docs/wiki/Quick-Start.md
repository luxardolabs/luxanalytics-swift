# Quick Start Tutorial

Get LuxAnalytics running in your iOS app in under 5 minutes.

## Prerequisites

Before starting, ensure you have:
- iOS 18.0+ project
- Swift 6.0+ enabled
- Xcode 16.0+
- Analytics DSN from your provider

## Step 1: Installation

Add LuxAnalytics to your project using Swift Package Manager:

1. **File** → **Add Package Dependencies...**
2. Enter URL: `https://github.com/luxardolabs/LuxAnalytics`
3. Select version: `1.0.0` or later
4. Click **Add Package**

## Step 2: Basic Setup

### SwiftUI App

```swift
import SwiftUI
import LuxAnalytics

@main
struct MyApp: App {
    init() {
        Task {
            try await LuxAnalytics.quickStart(
                dsn: "https://your-public-id@analytics.example.com/api/v1/events/your-project-id"
            )
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### UIKit App

```swift
import UIKit
import LuxAnalytics

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        Task {
            try await LuxAnalytics.quickStart(
                dsn: "https://your-public-id@analytics.example.com/api/v1/events/your-project-id"
            )
        }
        
        return true
    }
}
```

## Step 3: Track Your First Event

### Simple Event

```swift
import LuxAnalytics

struct ContentView: View {
    var body: some View {
        Button("Get Started") {
            Task {
                let analytics = await LuxAnalytics.shared
                try await analytics.track("get_started_button_tapped")
            }
        }
        .task {
            let analytics = await LuxAnalytics.shared
            try await analytics.track("home_screen_viewed")
        }
    }
}
```

### Event with Metadata

```swift
Button("Complete Purchase") {
    Task {
        let analytics = await LuxAnalytics.shared
        try await analytics.track("purchase_completed", metadata: [
            "product_id": "premium_subscription",
            "amount": "9.99",
            "currency": "USD",
            "payment_method": "apple_pay"
        ])
    }
}
```

## Step 4: User Identification

Track user context for better analytics:

```swift
// Set user ID (when user logs in)
let analytics = await LuxAnalytics.shared
await analytics.setUser("user_12345")

// Set session ID (for grouping related events)
await analytics.setSession("session_abc123")

// Clear user data (when user logs out)
await analytics.setUser(nil)
```

## Step 5: Test Your Integration

### Enable Debug Mode

```swift
// During development, enable debug logging
try await LuxAnalytics.quickStart(
    dsn: "your-dsn",
    debugLogging: true  // Enable detailed logs
)
```

### Monitor Events

```swift
// Watch events in real-time during development
Task {
    for await notification in LuxAnalyticsEvents.eventStream {
        switch notification {
        case .eventQueued(let event):
            print("📤 Event queued: \(event.name)")
        case .eventsSent(let events):
            print("✅ Sent \(events.count) events")
        case .eventsFailed(let events, let error):
            print("❌ Failed to send \(events.count) events: \(error)")
        }
    }
}
```

### Check Queue Status

```swift
// Verify events are being queued and sent
let stats = await LuxAnalytics.getQueueStats()
print("Events in queue: \(stats.totalEvents)")
print("Queue size: \(stats.totalSizeBytes) bytes")

// Manual flush for testing
await LuxAnalytics.flush()
```

## Common First-Day Usage Patterns

### Screen Tracking

```swift
struct ScreenTracker: ViewModifier {
    let screenName: String
    
    func body(content: Content) -> some View {
        content
            .task {
                let analytics = await LuxAnalytics.shared
                try? await analytics.track("screen_viewed", metadata: [
                    "screen_name": screenName
                ])
            }
    }
}

extension View {
    func trackScreen(_ name: String) -> some View {
        modifier(ScreenTracker(screenName: name))
    }
}

// Usage
struct HomeView: View {
    var body: some View {
        Text("Welcome Home")
            .trackScreen("home")
    }
}
```

### Button Tracking

```swift
extension View {
    func trackButtonTap(_ eventName: String, metadata: [String: Any] = [:]) -> some View {
        self.onTapGesture {
            Task {
                let analytics = await LuxAnalytics.shared
                try? await analytics.track(eventName, metadata: metadata)
            }
        }
    }
}

// Usage
Button("Sign Up") {
    // Handle signup
}
.trackButtonTap("signup_button_tapped", metadata: [
    "source": "home_screen"
])
```

### Form Tracking

```swift
struct SignupForm: View {
    @State private var email = ""
    @State private var name = ""
    
    var body: some View {
        VStack {
            TextField("Email", text: $email)
            TextField("Name", text: $name)
            
            Button("Create Account") {
                Task {
                    let analytics = await LuxAnalytics.shared
                    
                    // Track form submission
                    try? await analytics.track("signup_form_submitted", metadata: [
                        "form_completion_time": "45.2",
                        "signup_method": "email"
                    ])
                    
                    // Handle actual signup
                    await handleSignup()
                }
            }
        }
        .task {
            let analytics = await LuxAnalytics.shared
            try? await analytics.track("signup_form_viewed")
        }
    }
    
    private func handleSignup() async {
        // Signup logic...
        
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("account_created", metadata: [
            "user_type": "free_tier"
        ])
        
        await analytics.setUser("new_user_id")
    }
}
```

## Error Handling Best Practices

### Graceful Degradation

```swift
func trackEvent(_ name: String, metadata: [String: Any] = [:]) async {
    do {
        let analytics = await LuxAnalytics.shared
        try await analytics.track(name, metadata: metadata)
    } catch LuxAnalyticsError.notInitialized {
        print("Analytics not initialized - event will be lost")
    } catch LuxAnalyticsError.queueFull {
        print("Analytics queue full - trying to flush")
        await LuxAnalytics.flush()
        // Optionally retry the event
    } catch {
        print("Analytics error: \(error)")
        // Don't crash the app for analytics failures
    }
}
```

### Safe Async Patterns

```swift
// ✅ Good: Handle async properly
Button("Track Event") {
    Task {
        await trackEvent("button_tapped")
    }
}

// ❌ Bad: Blocking UI
Button("Track Event") {
    // This would cause a compiler error - good!
    // await trackEvent("button_tapped")
}

// ✅ Good: Background tracking
Task.detached {
    await trackEvent("background_process_completed")
}
```

## Configuration for Production

### Environment-Based Setup

```swift
extension Bundle {
    var analyticsConfiguration: (dsn: String, debugLogging: Bool) {
        #if DEBUG
        return (
            dsn: "https://dev-key@dev.analytics.com/api/v1/events/dev-project",
            debugLogging: true
        )
        #else
        return (
            dsn: object(forInfoDictionaryKey: "LuxAnalyticsDSN") as? String ?? "",
            debugLogging: false
        )
        #endif
    }
}

// Usage
let config = Bundle.main.analyticsConfiguration
try await LuxAnalytics.quickStart(
    dsn: config.dsn,
    debugLogging: config.debugLogging
)
```

### Info.plist Configuration

For production apps, use Info.plist configuration:

**Info.plist**:
```xml
<key>LuxAnalyticsDSN</key>
<string>https://your-prod-key@analytics.example.com/api/v1/events/prod-project</string>

<key>LuxAnalyticsDebugLogging</key>
<false/>
```

**Code**:
```swift
// Initialize from Info.plist
try await LuxAnalytics.initializeFromPlist()
```

## Testing Your Integration

### Verification Checklist

- [ ] Events appear in debug logs
- [ ] No compilation warnings
- [ ] App doesn't crash on analytics errors  
- [ ] Events are queued when offline
- [ ] Events are sent when online
- [ ] User/session IDs are properly set

### Debug Commands

```swift
// Print current status
await LuxAnalyticsDebug.status()

// Validate setup
await LuxAnalyticsDebug.validateSetup()

// Check health
let isHealthy = await LuxAnalytics.healthCheck()
print("Analytics healthy: \(isHealthy)")
```

## Next Steps

Now that you have basic tracking working:

1. **[📊 Event Tracking Guide](Event-Tracking.md)** - Design effective events
2. **[🔧 Configuration Guide](Configuration.md)** - Optimize for your app
3. **[💡 Best Practices](Best-Practices.md)** - Production-ready patterns
4. **[🔒 Privacy & Security](Privacy-Security.md)** - Protect user data
5. **[🐛 Troubleshooting](Troubleshooting.md)** - Common issues and solutions

## Example Project

Check out our complete example project:

```swift
// Complete minimal app
import SwiftUI
import LuxAnalytics

@main
struct ExampleApp: App {
    init() {
        Task {
            try await LuxAnalytics.quickStart(
                dsn: "https://example@analytics.example.com/api/v1/events/example",
                debugLogging: true
            )
        }
    }
    
    var body: some Scene {
        WindowGroup {
            NavigationView {
                List {
                    NavigationLink("Home") { HomeView() }
                    NavigationLink("Profile") { ProfileView() }
                    NavigationLink("Settings") { SettingsView() }
                }
                .navigationTitle("Example App")
                .trackScreen("main_menu")
            }
        }
    }
}

struct HomeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome Home!")
            
            Button("Get Started") {
                Task {
                    await trackEvent("get_started_tapped")
                }
            }
            
            Button("Learn More") {
                Task {
                    await trackEvent("learn_more_tapped")
                }
            }
        }
        .trackScreen("home")
    }
}

extension View {
    func trackScreen(_ name: String) -> some View {
        self.task {
            let analytics = await LuxAnalytics.shared
            try? await analytics.track("screen_viewed", metadata: [
                "screen_name": name
            ])
        }
    }
}

func trackEvent(_ name: String, metadata: [String: Any] = [:]) async {
    do {
        let analytics = await LuxAnalytics.shared
        try await analytics.track(name, metadata: metadata)
    } catch {
        print("Analytics error: \(error)")
    }
}
```

**Congratulations!** 🎉 You now have LuxAnalytics successfully integrated and tracking events in your iOS app.