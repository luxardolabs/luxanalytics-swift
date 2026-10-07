# SwiftUI Integration Guide

Complete guide to integrating LuxAnalytics with SwiftUI applications using modern patterns and best practices.

## SwiftUI-Specific Patterns

### App Initialization

```swift
import SwiftUI
import LuxAnalytics

@main
struct MySwiftUIApp: App {
    @StateObject private var analyticsManager = AnalyticsManager()
    
    init() {
        // Initialize analytics early but don't block app launch
        Task.detached {
            await AnalyticsManager.initializeAnalytics()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(analyticsManager)
                .task {
                    // Ensure analytics is ready when UI appears
                    await analyticsManager.ensureInitialized()
                }
        }
    }
}

@MainActor
class AnalyticsManager: ObservableObject {
    @Published var isInitialized = false
    @Published var queueStats: QueueStats?
    @Published var isOnline = true
    
    static func initializeAnalytics() async {
        do {
            try await LuxAnalytics.quickStart(
                dsn: Bundle.main.luxAnalyticsDSN ?? "fallback-dsn",
                debugLogging: Bundle.main.isDebugMode
            )
        } catch {
            print("Analytics initialization failed: \(error)")
        }
    }
    
    func ensureInitialized() async {
        while !LuxAnalytics.isInitialized {
            try? await Task.sleep(for: .milliseconds(100))
        }
        isInitialized = true
        startMonitoring()
    }
    
    private func startMonitoring() {
        Task {
            while true {
                let stats = await LuxAnalytics.getQueueStats()
                let online = await LuxAnalytics.isNetworkAvailable()
                
                await MainActor.run {
                    self.queueStats = stats
                    self.isOnline = online
                }
                
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}

extension Bundle {
    var luxAnalyticsDSN: String? {
        object(forInfoDictionaryKey: "LuxAnalyticsDSN") as? String
    }
    
    var isDebugMode: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
```

## View Modifiers for Analytics

### Screen Tracking Modifier

```swift
struct ScreenTrackingModifier: ViewModifier {
    let screenName: String
    let metadata: [String: Any]
    
    func body(content: Content) -> some View {
        content
            .task {
                await trackScreenView()
            }
            .onAppear {
                // Track screen appearance
                Task {
                    await trackScreenAppearance()
                }
            }
            .onDisappear {
                // Track screen exit
                Task {
                    await trackScreenDisappearance()
                }
            }
    }
    
    private func trackScreenView() async {
        let analytics = await LuxAnalytics.shared
        var trackingMetadata = metadata
        trackingMetadata["screen_name"] = screenName
        trackingMetadata["view_timestamp"] = ISO8601DateFormatter().string(from: Date())
        
        try? await analytics.track("screen_viewed", metadata: trackingMetadata)
    }
    
    private func trackScreenAppearance() async {
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("screen_appeared", metadata: [
            "screen_name": screenName
        ])
    }
    
    private func trackScreenDisappearance() async {
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("screen_disappeared", metadata: [
            "screen_name": screenName
        ])
    }
}

extension View {
    func trackScreen(_ name: String, metadata: [String: Any] = [:]) -> some View {
        modifier(ScreenTrackingModifier(screenName: name, metadata: metadata))
    }
}
```

### Button Tracking Modifier

```swift
struct ButtonTrackingModifier: ViewModifier {
    let eventName: String
    let metadata: [String: Any]
    let onTap: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                Task {
                    await trackButtonTap()
                }
                onTap()
            }
    }
    
    private func trackButtonTap() async {
        let analytics = await LuxAnalytics.shared
        var trackingMetadata = metadata
        trackingMetadata["tap_timestamp"] = Date().timeIntervalSince1970
        
        try? await analytics.track(eventName, metadata: trackingMetadata)
    }
}

extension View {
    func trackButtonTap(
        _ eventName: String,
        metadata: [String: Any] = [:],
        onTap: @escaping () -> Void = {}
    ) -> some View {
        modifier(ButtonTrackingModifier(
            eventName: eventName,
            metadata: metadata,
            onTap: onTap
        ))
    }
}
```

### Form Tracking Modifier

```swift
struct FormTrackingModifier: ViewModifier {
    let formName: String
    @State private var formStartTime = Date()
    @State private var fieldInteractions: [String: Int] = [:]
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                formStartTime = Date()
                Task {
                    await trackFormStart()
                }
            }
    }
    
    private func trackFormStart() async {
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("form_started", metadata: [
            "form_name": formName,
            "start_time": ISO8601DateFormatter().string(from: formStartTime)
        ])
    }
    
    func trackFieldInteraction(_ fieldName: String) {
        fieldInteractions[fieldName, default: 0] += 1
        
        Task {
            let analytics = await LuxAnalytics.shared
            try? await analytics.track("form_field_interacted", metadata: [
                "form_name": formName,
                "field_name": fieldName,
                "interaction_count": fieldInteractions[fieldName] ?? 1
            ])
        }
    }
    
    func trackFormSubmission(success: Bool) async {
        let completionTime = Date().timeIntervalSince(formStartTime)
        
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("form_submitted", metadata: [
            "form_name": formName,
            "completion_time": completionTime,
            "success": success,
            "field_interactions": fieldInteractions.count,
            "total_interactions": fieldInteractions.values.reduce(0, +)
        ])
    }
}

extension View {
    func trackForm(_ name: String) -> some View {
        modifier(FormTrackingModifier(formName: name))
    }
}
```

## SwiftUI Component Integration

### Analytics-Aware TextField

```swift
struct AnalyticsTextField: View {
    let title: String
    @Binding var text: String
    let fieldName: String
    let formName: String
    
    @State private var hasInteracted = false
    @State private var focusCount = 0
    
    var body: some View {
        TextField(title, text: $text)
            .onTapGesture {
                if !hasInteracted {
                    hasInteracted = true
                    focusCount += 1
                    Task {
                        await trackFirstInteraction()
                    }
                } else {
                    focusCount += 1
                    Task {
                        await trackFocusEvent()
                    }
                }
            }
            .onChange(of: text) { oldValue, newValue in
                Task {
                    await trackTextChange(from: oldValue, to: newValue)
                }
            }
    }
    
    private func trackFirstInteraction() async {
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("form_field_first_interaction", metadata: [
            "form_name": formName,
            "field_name": fieldName,
            "field_type": "text"
        ])
    }
    
    private func trackFocusEvent() async {
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("form_field_focused", metadata: [
            "form_name": formName,
            "field_name": fieldName,
            "focus_count": focusCount
        ])
    }
    
    private func trackTextChange(from oldValue: String, to newValue: String) async {
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("form_field_changed", metadata: [
            "form_name": formName,
            "field_name": fieldName,
            "old_length": oldValue.count,
            "new_length": newValue.count,
            "change_type": newValue.count > oldValue.count ? "addition" : "deletion"
        ])
    }
}
```

### Analytics-Aware NavigationLink

```swift
struct AnalyticsNavigationLink<Destination: View>: View {
    let destination: Destination
    let title: String
    let eventName: String
    let metadata: [String: Any]
    
    var body: some View {
        NavigationLink(destination: destination) {
            Text(title)
        }
        .trackButtonTap(eventName, metadata: metadata)
    }
}

// Usage
AnalyticsNavigationLink(
    destination: ProfileView(),
    title: "View Profile",
    eventName: "navigation_link_tapped",
    metadata: [
        "destination": "profile",
        "source_screen": "home"
    ]
)
```

### Analytics-Aware List

```swift
struct AnalyticsList<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let data: Data
    let content: (Data.Element) -> Content
    let listName: String
    
    @State private var scrollPosition: CGFloat = 0
    @State private var visibleItems: Set<Data.Element.ID> = []
    
    var body: some View {
        List(data, id: \.id) { item in
            content(item)
                .onAppear {
                    Task {
                        await trackItemAppeared(item)
                    }
                }
                .onDisappear {
                    Task {
                        await trackItemDisappeared(item)
                    }
                }
        }
        .onAppear {
            Task {
                await trackListViewed()
            }
        }
    }
    
    private func trackListViewed() async {
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("list_viewed", metadata: [
            "list_name": listName,
            "item_count": data.count
        ])
    }
    
    private func trackItemAppeared(_ item: Data.Element) async {
        guard !visibleItems.contains(item.id) else { return }
        visibleItems.insert(item.id)
        
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("list_item_appeared", metadata: [
            "list_name": listName,
            "item_id": String(describing: item.id),
            "visible_items_count": visibleItems.count
        ])
    }
    
    private func trackItemDisappeared(_ item: Data.Element) async {
        visibleItems.remove(item.id)
        
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("list_item_disappeared", metadata: [
            "list_name": listName,
            "item_id": String(describing: item.id),
            "visible_items_count": visibleItems.count
        ])
    }
}
```

## State Management Integration

### Analytics State Management

```swift
@MainActor
class AnalyticsViewModel: ObservableObject {
    @Published var currentScreen: String = ""
    @Published var userJourney: [String] = []
    @Published var sessionEvents: [String] = []
    @Published var isTrackingEnabled = true
    
    private var sessionStartTime = Date()
    
    func setCurrentScreen(_ screen: String) {
        let previousScreen = currentScreen
        currentScreen = screen
        userJourney.append(screen)
        
        Task {
            await trackScreenNavigation(from: previousScreen, to: screen)
        }
    }
    
    func trackEvent(_ eventName: String, metadata: [String: Any] = [:]) async {
        guard isTrackingEnabled else { return }
        
        sessionEvents.append(eventName)
        
        var enrichedMetadata = metadata
        enrichedMetadata["current_screen"] = currentScreen
        enrichedMetadata["session_duration"] = Date().timeIntervalSince(sessionStartTime)
        enrichedMetadata["session_event_count"] = sessionEvents.count
        enrichedMetadata["user_journey_position"] = userJourney.count
        
        let analytics = await LuxAnalytics.shared
        try? await analytics.track(eventName, metadata: enrichedMetadata)
    }
    
    private func trackScreenNavigation(from: String, to: String) async {
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("screen_navigation", metadata: [
            "from_screen": from,
            "to_screen": to,
            "journey_step": userJourney.count,
            "navigation_type": "swiftui_navigation"
        ])
    }
    
    func startNewSession() {
        sessionStartTime = Date()
        sessionEvents.removeAll()
        userJourney.removeAll()
        
        Task {
            let analytics = await LuxAnalytics.shared
            try? await analytics.track("session_started", metadata: [
                "session_start_time": ISO8601DateFormatter().string(from: sessionStartTime)
            ])
        }
    }
    
    func endSession() async {
        let sessionDuration = Date().timeIntervalSince(sessionStartTime)
        
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("session_ended", metadata: [
            "session_duration": sessionDuration,
            "total_events": sessionEvents.count,
            "screens_visited": Set(userJourney).count,
            "user_journey": userJourney
        ])
    }
}
```

### Environment Integration

```swift
// Environment key for analytics
private struct AnalyticsEnvironmentKey: EnvironmentKey {
    static let defaultValue: AnalyticsViewModel = AnalyticsViewModel()
}

extension EnvironmentValues {
    var analytics: AnalyticsViewModel {
        get { self[AnalyticsEnvironmentKey.self] }
        set { self[AnalyticsEnvironmentKey.self] = newValue }
    }
}

// App setup with environment
@main
struct MyApp: App {
    @StateObject private var analyticsViewModel = AnalyticsViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.analytics, analyticsViewModel)
                .onAppear {
                    analyticsViewModel.startNewSession()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    Task {
                        await analyticsViewModel.endSession()
                    }
                }
        }
    }
}

// Usage in views
struct ContentView: View {
    @Environment(\.analytics) var analytics
    
    var body: some View {
        VStack {
            Text("Welcome")
            
            Button("Get Started") {
                Task {
                    await analytics.trackEvent("get_started_tapped")
                }
            }
        }
        .onAppear {
            analytics.setCurrentScreen("home")
        }
    }
}
```

## Advanced SwiftUI Patterns

### Analytics-Driven UI

```swift
struct AnalyticsDashboardView: View {
    @EnvironmentObject var analyticsManager: AnalyticsManager
    @State private var queueStats: QueueStats?
    @State private var networkStatus = true
    
    var body: some View {
        NavigationView {
            List {
                Section("Analytics Status") {
                    HStack {
                        Circle()
                            .fill(analyticsManager.isInitialized ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text("SDK Status")
                        Spacer()
                        Text(analyticsManager.isInitialized ? "Ready" : "Initializing")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Circle()
                            .fill(networkStatus ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text("Network")
                        Spacer()
                        Text(networkStatus ? "Online" : "Offline")
                            .foregroundColor(.secondary)
                    }
                }
                
                if let stats = queueStats {
                    Section("Queue Status") {
                        HStack {
                            Text("Events Queued")
                            Spacer()
                            Text("\(stats.totalEvents)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Queue Size")
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(stats.totalSizeBytes), countStyle: .file))
                                .foregroundColor(.secondary)
                        }
                        
                        if stats.totalEvents > 0 {
                            Button("Flush Queue") {
                                Task {
                                    await LuxAnalytics.flush()
                                    await updateStats()
                                }
                            }
                        }
                    }
                }
                
                Section("Actions") {
                    Button("Clear Queue") {
                        Task {
                            await LuxAnalytics.clearQueue()
                            await updateStats()
                        }
                    }
                    .foregroundColor(.red)
                    
                    Button("Test Event") {
                        Task {
                            let analytics = await LuxAnalytics.shared
                            try? await analytics.track("test_event_from_dashboard")
                            await updateStats()
                        }
                    }
                }
            }
            .navigationTitle("Analytics")
            .task {
                await updateStats()
                startPeriodicUpdates()
            }
        }
    }
    
    private func updateStats() async {
        queueStats = await LuxAnalytics.getQueueStats()
        networkStatus = await LuxAnalytics.isNetworkAvailable()
    }
    
    private func startPeriodicUpdates() {
        Task {
            while true {
                await updateStats()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}
```

### Conditional Analytics

```swift
struct ConditionalAnalyticsModifier: ViewModifier {
    let condition: () -> Bool
    let eventName: String
    let metadata: [String: Any]
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                if condition() {
                    Task {
                        let analytics = await LuxAnalytics.shared
                        try? await analytics.track(eventName, metadata: metadata)
                    }
                }
            }
    }
}

extension View {
    func trackIf(
        _ condition: @escaping () -> Bool,
        event: String,
        metadata: [String: Any] = [:]
    ) -> some View {
        modifier(ConditionalAnalyticsModifier(
            condition: condition,
            eventName: event,
            metadata: metadata
        ))
    }
}

// Usage
struct FeatureView: View {
    @AppStorage("feature_enabled") var featureEnabled = false
    
    var body: some View {
        Text("Feature Content")
            .trackIf(
                { featureEnabled },
                event: "feature_viewed",
                metadata: ["feature_name": "experimental_feature"]
            )
    }
}
```

### User Preference Integration

```swift
struct AnalyticsPreferencesView: View {
    @AppStorage("analytics_enabled") private var analyticsEnabled = true
    @AppStorage("crash_reporting_enabled") private var crashReportingEnabled = true
    @AppStorage("performance_monitoring_enabled") private var performanceMonitoringEnabled = true
    
    var body: some View {
        NavigationView {
            Form {
                Section("Privacy Settings") {
                    Toggle("Analytics", isOn: $analyticsEnabled)
                        .onChange(of: analyticsEnabled) { oldValue, newValue in
                            Task {
                                await handleAnalyticsToggle(newValue)
                            }
                        }
                    
                    Toggle("Crash Reporting", isOn: $crashReportingEnabled)
                    Toggle("Performance Monitoring", isOn: $performanceMonitoringEnabled)
                }
                
                Section("Data Management") {
                    Button("Clear Analytics Data") {
                        Task {
                            await clearAnalyticsData()
                        }
                    }
                    .foregroundColor(.red)
                    
                    Button("Export Analytics Data") {
                        Task {
                            await exportAnalyticsData()
                        }
                    }
                }
                
                Section("Information") {
                    HStack {
                        Text("SDK Version")
                        Spacer()
                        Text(LuxAnalyticsVersion.current)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Analytics Settings")
        }
    }
    
    private func handleAnalyticsToggle(_ enabled: Bool) async {
        if enabled {
            // Re-enable analytics
            await AnalyticsSettings.shared.setEnabled(true)
            
            let analytics = await LuxAnalytics.shared
            try? await analytics.track("analytics_enabled", metadata: [
                "enabled_via": "settings_toggle"
            ])
        } else {
            // Disable analytics and clear data
            let analytics = await LuxAnalytics.shared
            try? await analytics.track("analytics_disabled", metadata: [
                "disabled_via": "settings_toggle"
            ])
            
            await AnalyticsSettings.shared.setEnabled(false)
            await LuxAnalytics.clearQueue()
        }
    }
    
    private func clearAnalyticsData() async {
        await LuxAnalytics.clearQueue()
        
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("analytics_data_cleared", metadata: [
            "cleared_via": "settings_button"
        ])
    }
    
    private func exportAnalyticsData() async {
        let stats = await LuxAnalytics.getQueueStats()
        
        let exportData = [
            "export_timestamp": ISO8601DateFormatter().string(from: Date()),
            "queued_events": stats.totalEvents,
            "queue_size_bytes": stats.totalSizeBytes,
            "sdk_version": LuxAnalyticsVersion.current
        ]
        
        // In a real app, you'd present a share sheet or save to files
        print("Export data: \(exportData)")
        
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("analytics_data_exported", metadata: [
            "export_method": "settings_button",
            "events_exported": stats.totalEvents
        ])
    }
}
```

## Testing SwiftUI Analytics

### Preview Integration

```swift
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AnalyticsManager())
            .task {
                // Initialize analytics for preview
                await AnalyticsManager.initializeAnalytics()
            }
    }
}

// Mock analytics for previews
extension AnalyticsManager {
    static var preview: AnalyticsManager {
        let manager = AnalyticsManager()
        manager.isInitialized = true
        manager.isOnline = true
        return manager
    }
}

struct AnalyticsDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        AnalyticsDashboardView()
            .environmentObject(AnalyticsManager.preview)
    }
}
```

### UI Testing with Analytics

```swift
// UI Test helpers
extension XCUIApplication {
    func trackAnalyticsEvent(_ eventName: String) {
        // In UI tests, you might trigger analytics events
        // and verify they're properly queued
        
        // Example: Tap button that should trigger analytics
        buttons["trackable_button"].tap()
        
        // Wait for analytics processing
        sleep(1)
        
        // Verify analytics state (this would need SDK support for testing)
    }
}

class SwiftUIAnalyticsUITests: XCTestCase {
    func testAnalyticsIntegration() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Test screen tracking
        XCTAssertTrue(app.staticTexts["Home"].exists)
        
        // Test button tracking
        app.buttons["Get Started"].tap()
        
        // Verify navigation and analytics
        XCTAssertTrue(app.staticTexts["Welcome"].exists)
    }
}
```

## Best Practices for SwiftUI

### ✅ Do

- Use `@StateObject` for analytics managers in app root
- Leverage SwiftUI's declarative nature with view modifiers
- Use `@Environment` for passing analytics context
- Track user journeys through navigation state
- Respect user privacy preferences with `@AppStorage`
- Use `Task` for async analytics calls
- Provide visual feedback for analytics state
- Test with SwiftUI previews

### ❌ Don't

- Block SwiftUI updates with synchronous analytics calls
- Create analytics objects in view body (use `@StateObject`)
- Ignore SwiftUI's lifecycle for analytics timing
- Track every single state change (be selective)
- Forget to handle analytics errors gracefully
- Mix UIKit patterns unnecessarily in SwiftUI
- Create memory leaks with analytics observers
- Skip testing analytics integration

## Performance Considerations

### Efficient SwiftUI Analytics

```swift
// Efficient screen tracking that doesn't cause re-renders
struct PerformantScreenTracker: ViewModifier {
    let screenName: String
    
    func body(content: Content) -> some View {
        content
            .task {
                // Use task to avoid blocking view updates
                await trackScreenView()
            }
    }
    
    private func trackScreenView() async {
        // Minimize work on main thread
        Task.detached {
            let analytics = await LuxAnalytics.shared
            try? await analytics.track("screen_viewed", metadata: [
                "screen_name": screenName
            ])
        }
    }
}

// Debounced event tracking for rapid user interactions
struct DebouncedEventTracker: ViewModifier {
    let eventName: String
    let metadata: [String: Any]
    let debounceTime: TimeInterval
    
    @State private var debounceTask: Task<Void, Never>?
    
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                debouncedTrack()
            }
    }
    
    private func debouncedTrack() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(debounceTime))
            
            let analytics = await LuxAnalytics.shared
            try? await analytics.track(eventName, metadata: metadata)
        }
    }
}
```

## Next Steps

- [🎯 UIKit Integration](UIKit-Integration.md) - UIKit-specific patterns
- [🏗️ Architecture Patterns](Architecture-Patterns.md) - App architecture with analytics
- [💡 Best Practices](Best-Practices.md) - Production-ready patterns
- [🧪 Testing Guide](Testing.md) - Testing analytics integration