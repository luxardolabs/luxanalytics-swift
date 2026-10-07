# UIKit Integration Guide

Complete guide to integrating LuxAnalytics with UIKit applications using proven patterns and best practices.

## UIKit App Setup

### AppDelegate Integration

```swift
import UIKit
import LuxAnalytics

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // Initialize analytics early but don't block app launch
        Task.detached {
            await initializeAnalytics()
        }
        
        // Setup lifecycle tracking
        setupAnalyticsLifecycleTracking()
        
        return true
    }
    
    private func initializeAnalytics() async {
        do {
            let dsn = Bundle.main.luxAnalyticsDSN ?? "fallback-dsn"
            try await LuxAnalytics.quickStart(
                dsn: dsn,
                debugLogging: Bundle.main.isDebugMode
            )
            
            print("✅ Analytics initialized successfully")
            
            // Track app launch
            let analytics = await LuxAnalytics.shared
            try await analytics.track("app_launched", metadata: [
                "launch_type": "normal",
                "app_version": Bundle.main.appVersion ?? "unknown"
            ])
            
        } catch {
            print("❌ Analytics initialization failed: \(error)")
        }
    }
    
    private func setupAnalyticsLifecycleTracking() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        Task {
            let analytics = await LuxAnalytics.shared
            try? await analytics.track("app_backgrounded")
            
            // Flush events before backgrounding
            await LuxAnalytics.flush()
        }
    }
    
    @objc private func appWillEnterForeground() {
        Task {
            let analytics = await LuxAnalytics.shared
            try? await analytics.track("app_foregrounded")
        }
    }
    
    @objc private func appWillTerminate() {
        Task {
            let analytics = await LuxAnalytics.shared
            try? await analytics.track("app_terminated")
            
            // Final flush
            await LuxAnalytics.flush()
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
    
    var appVersion: String? {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}
```

### SceneDelegate Integration (iOS 13+)

```swift
import UIKit
import LuxAnalytics

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // Setup window and root view controller
        window = UIWindow(windowScene: windowScene)
        setupRootViewController()
        window?.makeKeyAndVisible()
        
        // Track scene connection
        Task {
            await trackSceneConnection(session: session, options: connectionOptions)
        }
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        Task {
            let analytics = await LuxAnalytics.shared
            try? await analytics.track("scene_backgrounded")
            await LuxAnalytics.flush()
        }
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {
        Task {
            let analytics = await LuxAnalytics.shared
            try? await analytics.track("scene_foregrounded")
        }
    }
    
    private func setupRootViewController() {
        let mainViewController = MainViewController()
        let navigationController = UINavigationController(rootViewController: mainViewController)
        window?.rootViewController = navigationController
    }
    
    private func trackSceneConnection(session: UISceneSession, options: UIScene.ConnectionOptions) async {
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("scene_connected", metadata: [
            "scene_configuration": session.configuration.name ?? "default",
            "connection_options": options.urlContexts.isEmpty ? "normal" : "url_context"
        ])
    }
}
```

## View Controller Integration

### Base Analytics View Controller

```swift
import UIKit
import LuxAnalytics

class AnalyticsViewController: UIViewController {
    
    // Screen identification
    var screenName: String {
        return String(describing: type(of: self))
    }
    
    var screenMetadata: [String: Any] {
        return [:]
    }
    
    // Timing
    private var viewDidLoadTime: Date?
    private var viewWillAppearTime: Date?
    private var viewDidAppearTime: Date?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        viewDidLoadTime = Date()
        
        Task {
            await trackViewDidLoad()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewWillAppearTime = Date()
        
        Task {
            await trackViewWillAppear(animated: animated)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppearTime = Date()
        
        Task {
            await trackViewDidAppear(animated: animated)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        Task {
            await trackViewWillDisappear(animated: animated)
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        Task {
            await trackViewDidDisappear(animated: animated)
        }
    }
    
    // MARK: - Analytics Methods
    
    private func trackViewDidLoad() async {
        let analytics = await LuxAnalytics.shared
        
        var metadata = screenMetadata
        metadata["screen_name"] = screenName
        metadata["view_controller"] = String(describing: type(of: self))
        
        try? await analytics.track("view_did_load", metadata: metadata)
    }
    
    private func trackViewWillAppear(animated: Bool) async {
        let analytics = await LuxAnalytics.shared
        
        var metadata = screenMetadata
        metadata["screen_name"] = screenName
        metadata["animated"] = animated
        
        if let loadTime = viewDidLoadTime {
            metadata["load_to_appear_duration"] = Date().timeIntervalSince(loadTime)
        }
        
        try? await analytics.track("view_will_appear", metadata: metadata)
    }
    
    private func trackViewDidAppear(animated: Bool) async {
        let analytics = await LuxAnalytics.shared
        
        var metadata = screenMetadata
        metadata["screen_name"] = screenName
        metadata["animated"] = animated
        
        if let willAppearTime = viewWillAppearTime {
            metadata["will_appear_to_did_appear_duration"] = Date().timeIntervalSince(willAppearTime)
        }
        
        if let loadTime = viewDidLoadTime {
            metadata["total_load_duration"] = Date().timeIntervalSince(loadTime)
        }
        
        try? await analytics.track("screen_viewed", metadata: metadata)
    }
    
    private func trackViewWillDisappear(animated: Bool) async {
        let analytics = await LuxAnalytics.shared
        
        var metadata = screenMetadata
        metadata["screen_name"] = screenName
        metadata["animated"] = animated
        
        if let didAppearTime = viewDidAppearTime {
            metadata["screen_time"] = Date().timeIntervalSince(didAppearTime)
        }
        
        try? await analytics.track("view_will_disappear", metadata: metadata)
    }
    
    private func trackViewDidDisappear(animated: Bool) async {
        let analytics = await LuxAnalytics.shared
        
        var metadata = screenMetadata
        metadata["screen_name"] = screenName
        metadata["animated"] = animated
        
        try? await analytics.track("view_did_disappear", metadata: metadata)
    }
    
    // Helper method for child classes to track custom events
    func trackEvent(_ eventName: String, metadata: [String: Any] = [:]) async {
        let analytics = await LuxAnalytics.shared
        
        var enrichedMetadata = metadata
        enrichedMetadata["screen_name"] = screenName
        enrichedMetadata["view_controller"] = String(describing: type(of: self))
        
        try? await analytics.track(eventName, metadata: enrichedMetadata)
    }
}
```

### Specific View Controller Examples

```swift
class HomeViewController: AnalyticsViewController {
    
    override var screenName: String {
        return "home"
    }
    
    override var screenMetadata: [String: Any] {
        return [
            "screen_category": "main",
            "user_type": getCurrentUserType()
        ]
    }
    
    @IBOutlet weak var featuredContentView: UIView!
    @IBOutlet weak var getStartedButton: UIButton!
    @IBOutlet weak var profileButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupAnalyticsTracking()
    }
    
    private func setupAnalyticsTracking() {
        // Track button taps
        getStartedButton.addTarget(
            self,
            action: #selector(getStartedTapped),
            for: .touchUpInside
        )
        
        profileButton.addTarget(
            self,
            action: #selector(profileButtonTapped),
            for: .touchUpInside
        )
    }
    
    @objc private func getStartedTapped() {
        Task {
            await trackEvent("get_started_button_tapped", metadata: [
                "button_location": "home_center",
                "user_segment": getCurrentUserSegment()
            ])
        }
        
        // Handle button action
        navigateToOnboarding()
    }
    
    @objc private func profileButtonTapped() {
        Task {
            await trackEvent("profile_button_tapped", metadata: [
                "button_location": "home_top_right"
            ])
        }
        
        // Handle button action
        navigateToProfile()
    }
    
    private func getCurrentUserType() -> String {
        // Determine user type based on app state
        return "returning_user"
    }
    
    private func getCurrentUserSegment() -> String {
        // Determine user segment
        return "free_tier"
    }
    
    private func navigateToOnboarding() {
        let onboardingVC = OnboardingViewController()
        navigationController?.pushViewController(onboardingVC, animated: true)
    }
    
    private func navigateToProfile() {
        let profileVC = ProfileViewController()
        navigationController?.pushViewController(profileVC, animated: true)
    }
}
```

## Navigation Tracking

### Navigation Controller Integration

```swift
class AnalyticsNavigationController: UINavigationController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
    }
}

extension AnalyticsNavigationController: UINavigationControllerDelegate {
    
    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        Task {
            await trackNavigationWillShow(viewController, animated: animated)
        }
    }
    
    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        Task {
            await trackNavigationDidShow(viewController, animated: animated)
        }
    }
    
    private func trackNavigationWillShow(_ viewController: UIViewController, animated: Bool) async {
        let analytics = await LuxAnalytics.shared
        
        let screenName = (viewController as? AnalyticsViewController)?.screenName 
                         ?? String(describing: type(of: viewController))
        
        try? await analytics.track("navigation_will_show", metadata: [
            "destination_screen": screenName,
            "navigation_stack_depth": viewControllers.count,
            "animated": animated
        ])
    }
    
    private func trackNavigationDidShow(_ viewController: UIViewController, animated: Bool) async {
        let analytics = await LuxAnalytics.shared
        
        let screenName = (viewController as? AnalyticsViewController)?.screenName 
                         ?? String(describing: type(of: viewController))
        
        try? await analytics.track("navigation_completed", metadata: [
            "current_screen": screenName,
            "navigation_stack_depth": viewControllers.count,
            "animated": animated
        ])
    }
}
```

### Tab Bar Controller Integration

```swift
class AnalyticsTabBarController: UITabBarController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
    }
}

extension AnalyticsTabBarController: UITabBarControllerDelegate {
    
    func tabBarController(
        _ tabBarController: UITabBarController,
        shouldSelect viewController: UIViewController
    ) -> Bool {
        Task {
            await trackTabSelection(viewController)
        }
        return true
    }
    
    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelect viewController: UIViewController
    ) {
        Task {
            await trackTabDidSelect(viewController)
        }
    }
    
    private func trackTabSelection(_ viewController: UIViewController) async {
        let analytics = await LuxAnalytics.shared
        
        let tabIndex = viewControllers?.firstIndex(of: viewController) ?? -1
        let tabTitle = viewController.tabBarItem.title ?? "unknown"
        
        try? await analytics.track("tab_selected", metadata: [
            "tab_index": tabIndex,
            "tab_title": tabTitle,
            "previous_tab_index": selectedIndex
        ])
    }
    
    private func trackTabDidSelect(_ viewController: UIViewController) async {
        let analytics = await LuxAnalytics.shared
        
        let tabIndex = viewControllers?.firstIndex(of: viewController) ?? -1
        let tabTitle = viewController.tabBarItem.title ?? "unknown"
        
        try? await analytics.track("tab_navigation_completed", metadata: [
            "tab_index": tabIndex,
            "tab_title": tabTitle,
            "total_tabs": viewControllers?.count ?? 0
        ])
    }
}
```

## UI Component Integration

### Analytics-Aware Table View

```swift
class AnalyticsTableViewController: AnalyticsViewController {
    
    @IBOutlet weak var tableView: UITableView!
    
    private var visibleCells: Set<IndexPath> = []
    private var cellInteractions: [IndexPath: Int] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.delegate = self
        tableView.dataSource = self
        
        // Track table view setup
        Task {
            await trackEvent("table_view_loaded", metadata: [
                "item_count": numberOfItems(),
                "table_style": tableView.style.rawValue
            ])
        }
    }
    
    private func numberOfItems() -> Int {
        // Override in subclasses
        return 0
    }
}

extension AnalyticsTableViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        visibleCells.insert(indexPath)
        
        Task {
            await trackEvent("table_cell_appeared", metadata: [
                "section": indexPath.section,
                "row": indexPath.row,
                "visible_cells_count": visibleCells.count
            ])
        }
    }
    
    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        visibleCells.remove(indexPath)
        
        Task {
            await trackEvent("table_cell_disappeared", metadata: [
                "section": indexPath.section,
                "row": indexPath.row,
                "visible_cells_count": visibleCells.count
            ])
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        cellInteractions[indexPath, default: 0] += 1
        
        Task {
            await trackEvent("table_cell_selected", metadata: [
                "section": indexPath.section,
                "row": indexPath.row,
                "interaction_count": cellInteractions[indexPath] ?? 1,
                "total_items": numberOfItems()
            ])
        }
        
        // Handle selection
        handleCellSelection(at: indexPath)
    }
    
    private func handleCellSelection(at indexPath: IndexPath) {
        // Override in subclasses
    }
}

extension AnalyticsTableViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return numberOfItems()
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Override in subclasses
        return UITableViewCell()
    }
}
```

### Analytics-Aware Collection View

```swift
class AnalyticsCollectionViewController: AnalyticsViewController {
    
    @IBOutlet weak var collectionView: UICollectionView!
    
    private var scrollStartTime: Date?
    private var lastScrollPosition: CGFloat = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        collectionView.delegate = self
        collectionView.dataSource = self
        
        setupScrollTracking()
        
        Task {
            await trackEvent("collection_view_loaded", metadata: [
                "item_count": numberOfItems(),
                "layout_type": "grid"
            ])
        }
    }
    
    private func setupScrollTracking() {
        // Add pan gesture to track scroll interactions
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        collectionView.addGestureRecognizer(panGesture)
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            scrollStartTime = Date()
            lastScrollPosition = collectionView.contentOffset.y
            
        case .ended, .cancelled:
            if let startTime = scrollStartTime {
                let scrollDuration = Date().timeIntervalSince(startTime)
                let scrollDistance = abs(collectionView.contentOffset.y - lastScrollPosition)
                
                Task {
                    await trackEvent("collection_view_scrolled", metadata: [
                        "scroll_duration": scrollDuration,
                        "scroll_distance": scrollDistance,
                        "scroll_direction": collectionView.contentOffset.y > lastScrollPosition ? "down" : "up"
                    ])
                }
            }
            
        default:
            break
        }
    }
    
    private func numberOfItems() -> Int {
        // Override in subclasses
        return 0
    }
}

extension AnalyticsCollectionViewController: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Task {
            await trackEvent("collection_item_selected", metadata: [
                "section": indexPath.section,
                "item": indexPath.item,
                "total_items": numberOfItems()
            ])
        }
        
        handleItemSelection(at: indexPath)
    }
    
    private func handleItemSelection(at indexPath: IndexPath) {
        // Override in subclasses
    }
}

extension AnalyticsCollectionViewController: UICollectionViewDataSource {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return numberOfItems()
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // Override in subclasses
        return UICollectionViewCell()
    }
}
```

## User Input Tracking

### Form Analytics

```swift
class AnalyticsFormViewController: AnalyticsViewController {
    
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var submitButton: UIButton!
    
    private var formStartTime: Date?
    private var fieldInteractions: [String: Int] = [:]
    private var fieldFocusTimes: [String: Date] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupFormTracking()
        
        formStartTime = Date()
        Task {
            await trackEvent("form_started", metadata: [
                "form_type": getFormType()
            ])
        }
    }
    
    private func setupFormTracking() {
        // Text field delegates
        emailTextField.delegate = self
        passwordTextField.delegate = self
        
        // Add editing change events
        emailTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        passwordTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        
        // Submit button
        submitButton.addTarget(self, action: #selector(submitButtonTapped), for: .touchUpInside)
    }
    
    @objc private func textFieldDidChange(_ textField: UITextField) {
        let fieldName = getFieldName(for: textField)
        
        Task {
            await trackEvent("form_field_changed", metadata: [
                "field_name": fieldName,
                "field_length": textField.text?.count ?? 0,
                "form_type": getFormType()
            ])
        }
    }
    
    @objc private func submitButtonTapped() {
        let formDuration = Date().timeIntervalSince(formStartTime ?? Date())
        
        Task {
            await trackEvent("form_submit_attempted", metadata: [
                "form_type": getFormType(),
                "form_duration": formDuration,
                "fields_interacted": fieldInteractions.count,
                "total_interactions": fieldInteractions.values.reduce(0, +)
            ])
        }
        
        // Handle form submission
        handleFormSubmission()
    }
    
    private func getFieldName(for textField: UITextField) -> String {
        switch textField {
        case emailTextField: return "email"
        case passwordTextField: return "password"
        default: return "unknown"
        }
    }
    
    private func getFormType() -> String {
        // Override in subclasses
        return "generic_form"
    }
    
    private func handleFormSubmission() {
        // Implement form submission logic
        // Track success/failure afterwards
    }
    
    func trackFormCompletion(success: Bool, errorMessage: String? = nil) async {
        let formDuration = Date().timeIntervalSince(formStartTime ?? Date())
        
        var metadata: [String: Any] = [
            "form_type": getFormType(),
            "success": success,
            "form_duration": formDuration,
            "fields_completed": getCompletedFieldsCount()
        ]
        
        if let error = errorMessage {
            metadata["error_message"] = error
        }
        
        await trackEvent("form_completed", metadata: metadata)
    }
    
    private func getCompletedFieldsCount() -> Int {
        var count = 0
        if !(emailTextField.text?.isEmpty ?? true) { count += 1 }
        if !(passwordTextField.text?.isEmpty ?? true) { count += 1 }
        return count
    }
}

extension AnalyticsFormViewController: UITextFieldDelegate {
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        let fieldName = getFieldName(for: textField)
        fieldInteractions[fieldName, default: 0] += 1
        fieldFocusTimes[fieldName] = Date()
        
        Task {
            await trackEvent("form_field_focused", metadata: [
                "field_name": fieldName,
                "focus_count": fieldInteractions[fieldName] ?? 1,
                "form_type": getFormType()
            ])
        }
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        let fieldName = getFieldName(for: textField)
        
        if let focusTime = fieldFocusTimes[fieldName] {
            let focusDuration = Date().timeIntervalSince(focusTime)
            
            Task {
                await trackEvent("form_field_unfocused", metadata: [
                    "field_name": fieldName,
                    "focus_duration": focusDuration,
                    "field_length": textField.text?.count ?? 0,
                    "form_type": getFormType()
                ])
            }
        }
    }
}
```

### Button Interaction Tracking

```swift
extension UIButton {
    
    func addAnalyticsTracking(eventName: String, metadata: [String: Any] = [:]) {
        addTarget(
            AnalyticsButtonTarget.shared,
            action: #selector(AnalyticsButtonTarget.buttonTapped(_:)),
            for: .touchUpInside
        )
        
        // Store analytics data
        setAnalyticsEventName(eventName)
        setAnalyticsMetadata(metadata)
    }
    
    private func setAnalyticsEventName(_ name: String) {
        objc_setAssociatedObject(self, &AssociatedKeys.eventName, name, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    private func setAnalyticsMetadata(_ metadata: [String: Any]) {
        objc_setAssociatedObject(self, &AssociatedKeys.metadata, metadata, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    var analyticsEventName: String? {
        return objc_getAssociatedObject(self, &AssociatedKeys.eventName) as? String
    }
    
    var analyticsMetadata: [String: Any]? {
        return objc_getAssociatedObject(self, &AssociatedKeys.metadata) as? [String: Any]
    }
}

private struct AssociatedKeys {
    static var eventName = "analytics_event_name"
    static var metadata = "analytics_metadata"
}

class AnalyticsButtonTarget {
    static let shared = AnalyticsButtonTarget()
    
    @objc func buttonTapped(_ button: UIButton) {
        guard let eventName = button.analyticsEventName else { return }
        
        let metadata = button.analyticsMetadata ?? [:]
        
        Task {
            let analytics = await LuxAnalytics.shared
            try? await analytics.track(eventName, metadata: metadata)
        }
    }
}

// Usage
class SampleViewController: AnalyticsViewController {
    
    @IBOutlet weak var actionButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        actionButton.addAnalyticsTracking(
            eventName: "action_button_tapped",
            metadata: [
                "button_location": "center",
                "screen_name": screenName
            ]
        )
    }
}
```

## Performance Considerations

### Efficient UIKit Analytics

```swift
class PerformantAnalyticsViewController: UIViewController {
    
    private let analyticsQueue = DispatchQueue(label: "analytics", qos: .utility)
    private var pendingEvents: [(String, [String: Any])] = []
    private var batchTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupBatchedAnalytics()
    }
    
    private func setupBatchedAnalytics() {
        // Batch analytics events to avoid overwhelming the SDK
        batchTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.flushPendingEvents()
        }
    }
    
    deinit {
        batchTimer?.invalidate()
        flushPendingEvents()
    }
    
    func trackEventBatched(_ eventName: String, metadata: [String: Any] = [:]) {
        analyticsQueue.async {
            self.pendingEvents.append((eventName, metadata))
            
            // Auto-flush if batch gets large
            if self.pendingEvents.count >= 10 {
                DispatchQueue.main.async {
                    self.flushPendingEvents()
                }
            }
        }
    }
    
    private func flushPendingEvents() {
        analyticsQueue.async {
            let eventsToFlush = self.pendingEvents
            self.pendingEvents.removeAll()
            
            Task {
                let analytics = await LuxAnalytics.shared
                
                for (eventName, metadata) in eventsToFlush {
                    try? await analytics.track(eventName, metadata: metadata)
                }
            }
        }
    }
}
```

## Testing UIKit Analytics

### Unit Testing

```swift
import XCTest
@testable import YourApp

class UIKitAnalyticsTests: XCTestCase {
    
    var viewController: HomeViewController!
    
    override func setUp() {
        super.setUp()
        viewController = HomeViewController()
        viewController.loadViewIfNeeded()
    }
    
    func testScreenTracking() async {
        // Test that view controller tracks screen view
        viewController.viewWillAppear(true)
        viewController.viewDidAppear(true)
        
        // Wait for analytics processing
        try? await Task.sleep(for: .milliseconds(100))
        
        // Verify analytics events were tracked
        // This would require SDK support for testing
    }
    
    func testButtonAnalytics() {
        // Test button analytics integration
        let button = viewController.getStartedButton
        XCTAssertNotNil(button?.analyticsEventName)
        XCTAssertEqual(button?.analyticsEventName, "get_started_button_tapped")
    }
}
```

### Integration Testing

```swift
class UIKitAnalyticsIntegrationTests: XCTestCase {
    
    func testFullUserFlow() async {
        // Test complete user flow with analytics
        let app = XCUIApplication()
        app.launch()
        
        // Navigate through app
        app.buttons["Get Started"].tap()
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("test@example.com")
        app.buttons["Submit"].tap()
        
        // Wait for analytics processing
        sleep(2)
        
        // Verify analytics were tracked (requires test backend)
    }
}
```

## Best Practices for UIKit

### ✅ Do

- Use base classes for consistent analytics implementation
- Track view controller lifecycle events automatically
- Implement navigation tracking with delegates
- Use associated objects for button analytics
- Batch events for performance
- Handle analytics errors gracefully
- Test analytics integration thoroughly
- Use background queues for heavy analytics work

### ❌ Don't

- Block the main thread with analytics calls
- Track every single UI interaction
- Forget to handle view controller deinitialization
- Create retain cycles with analytics observers
- Skip error handling for analytics failures
- Ignore performance impact of analytics
- Track sensitive user input data
- Create memory leaks with delegates

## Migration from Legacy Analytics

### Gradual Migration Strategy

```swift
// Legacy analytics wrapper for gradual migration
class LegacyAnalyticsAdapter {
    
    static func track(_ eventName: String, parameters: [String: Any] = [:]) {
        // Map to new LuxAnalytics
        Task {
            let analytics = await LuxAnalytics.shared
            try? await analytics.track(eventName, metadata: parameters)
        }
        
        // Also send to legacy system during transition
        // LegacyAnalyticsSDK.track(eventName, parameters: parameters)
    }
    
    static func setUserId(_ userId: String) {
        Task {
            let analytics = await LuxAnalytics.shared
            await analytics.setUser(userId)
        }
        
        // Also update legacy system
        // LegacyAnalyticsSDK.setUserId(userId)
    }
}

// Replace legacy calls gradually
// Old: LegacyAnalyticsSDK.track("event")
// New: LegacyAnalyticsAdapter.track("event")
// Final: await analytics.track("event")
```

## Next Steps

- [🏗️ Architecture Patterns](Architecture-Patterns.md) - App architecture patterns
- [📱 SwiftUI Integration](SwiftUI-Integration.md) - Compare with SwiftUI patterns
- [🧪 Testing Guide](Testing.md) - Advanced testing strategies
- [💡 Best Practices](Best-Practices.md) - Production-ready patterns