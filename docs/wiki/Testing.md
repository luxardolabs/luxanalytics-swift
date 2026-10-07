# Testing Guide

Complete guide to testing LuxAnalytics integration in your iOS applications with proven strategies and patterns.

## Testing Philosophy

LuxAnalytics testing follows these principles:

- **Non-intrusive**: Analytics should not interfere with app functionality
- **Verifiable**: Analytics events should be testable and measurable
- **Isolated**: Tests should not depend on external analytics services
- **Performance-aware**: Testing should validate performance impact
- **Privacy-compliant**: Test data should respect privacy requirements

## Testing Strategies

### Unit Testing Analytics Integration

```swift
import XCTest
@testable import LuxAnalytics

class LuxAnalyticsUnitTests: XCTestCase {
    
    var analytics: LuxAnalytics!
    var mockNetworkClient: MockNetworkClient!
    var testConfiguration: LuxAnalyticsConfiguration!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Reset global state
        await LuxAnalyticsStorage.shared.setInstance(nil)
        await LuxAnalyticsStorage.shared.setConfiguration(nil)
        
        // Setup mock network client
        mockNetworkClient = MockNetworkClient()
        
        // Create test configuration
        testConfiguration = try LuxAnalyticsConfiguration(
            dsn: "https://test@localhost:8000/api/v1/events/test",
            debugLogging: true,
            requestTimeout: 5.0,
            batchSize: 5,
            maxQueueSize: 100
        )
        
        // Initialize with mock client
        analytics = try await LuxAnalytics.initializeForTesting(
            configuration: testConfiguration,
            networkClient: mockNetworkClient
        )
    }
    
    override func tearDown() async throws {
        // Clean up
        await LuxAnalyticsStorage.shared.setInstance(nil)
        await LuxAnalyticsStorage.shared.setConfiguration(nil)
        try await super.tearDown()
    }
    
    func testEventTracking() async throws {
        // Track an event
        try await analytics.track("test_event", metadata: [
            "key": "value",
            "number": 42
        ])
        
        // Verify event was queued
        let stats = await analytics.getQueueStats()
        XCTAssertEqual(stats.totalEvents, 1)
        
        // Verify event content
        let queuedEvents = await analytics.getQueuedEventsForTesting()
        XCTAssertEqual(queuedEvents.count, 1)
        
        let event = queuedEvents[0]
        XCTAssertEqual(event.name, "test_event")
        XCTAssertEqual(event.metadata["key"] as? String, "value")
        XCTAssertEqual(event.metadata["number"] as? Int, 42)
        XCTAssertNotNil(event.timestamp)
    }
    
    func testUserAndSessionTracking() async throws {
        // Set user and session
        await analytics.setUser("test_user_123")
        await analytics.setSession("test_session_456")
        
        // Track event
        try await analytics.track("user_event")
        
        // Verify user and session are included
        let queuedEvents = await analytics.getQueuedEventsForTesting()
        XCTAssertEqual(queuedEvents.count, 1)
        
        let event = queuedEvents[0]
        XCTAssertEqual(event.userId, "test_user_123")
        XCTAssertEqual(event.sessionId, "test_session_456")
    }
    
    func testBatchingBehavior() async throws {
        // Track multiple events
        for i in 1...10 {
            try await analytics.track("batch_test_\(i)")
        }
        
        // Verify all events are queued
        let stats = await analytics.getQueueStats()
        XCTAssertEqual(stats.totalEvents, 10)
        
        // Trigger flush
        await analytics.flush()
        
        // Wait for network request
        try await Task.sleep(for: .milliseconds(100))
        
        // Verify network requests were made
        XCTAssertEqual(mockNetworkClient.requestCount, 2) // 2 batches of 5
        XCTAssertEqual(mockNetworkClient.totalEventsSent, 10)
    }
    
    func testOfflineBehavior() async throws {
        // Simulate offline
        mockNetworkClient.isOnline = false
        
        // Track events while offline
        for i in 1...5 {
            try await analytics.track("offline_event_\(i)")
        }
        
        // Events should be queued
        let offlineStats = await analytics.getQueueStats()
        XCTAssertEqual(offlineStats.totalEvents, 5)
        
        // No network requests should be made
        XCTAssertEqual(mockNetworkClient.requestCount, 0)
        
        // Simulate going back online
        mockNetworkClient.isOnline = true
        await analytics.flush()
        
        // Wait for network request
        try await Task.sleep(for: .milliseconds(100))
        
        // Verify events were sent
        XCTAssertEqual(mockNetworkClient.requestCount, 1)
        XCTAssertEqual(mockNetworkClient.totalEventsSent, 5)
    }
    
    func testErrorHandling() async throws {
        // Simulate network error
        mockNetworkClient.shouldFailRequests = true
        
        // Track event
        try await analytics.track("error_test_event")
        
        // Trigger flush
        await analytics.flush()
        
        // Wait for network attempt
        try await Task.sleep(for: .milliseconds(100))
        
        // Event should still be in queue due to retry
        let stats = await analytics.getQueueStats()
        XCTAssertEqual(stats.totalEvents, 1)
        
        // Verify retry was attempted
        XCTAssertGreaterThan(mockNetworkClient.requestCount, 0)
    }
    
    func testQueueLimits() async throws {
        // Fill queue beyond soft limit
        for i in 1...150 { // Exceeds maxQueueSize of 100
            try await analytics.track("queue_limit_test_\(i)")
        }
        
        let stats = await analytics.getQueueStats()
        
        // Should trigger automatic flush
        XCTAssertLessThanOrEqual(stats.totalEvents, 100)
        XCTAssertGreaterThan(mockNetworkClient.requestCount, 0)
    }
    
    func testConfigurationValidation() async throws {
        // Test invalid DSN
        XCTAssertThrowsError(try LuxAnalyticsConfiguration(dsn: "invalid-dsn")) { error in
            XCTAssertTrue(error is LuxAnalyticsError)
        }
        
        // Test valid DSN formats
        let validConfigs = [
            try LuxAnalyticsConfiguration(dsn: "https://key@domain.com/api/v1/events/project"),
            try LuxAnalyticsConfiguration(dsn: "http://key@localhost:8000/api/v1/events/test"),
            try LuxAnalyticsConfiguration(dsn: "https://key@subdomain.domain.com:443/api/v1/events/project-123")
        ]
        
        for config in validConfigs {
            XCTAssertNotNil(config.endpoint)
            XCTAssertNotNil(config.publicId)
            XCTAssertNotNil(config.projectId)
        }
    }
}

// MARK: - Mock Network Client

class MockNetworkClient: NetworkClientProtocol {
    var isOnline = true
    var shouldFailRequests = false
    var requestCount = 0
    var totalEventsSent = 0
    var receivedRequests: [(endpoint: String, events: [[String: Any]])] = []
    
    func sendEvents(_ events: [AnalyticsEvent], to endpoint: URL, with authHeader: String) async throws {
        requestCount += 1
        
        guard isOnline else {
            throw NetworkError.offline
        }
        
        guard !shouldFailRequests else {
            throw NetworkError.serverError(500)
        }
        
        // Simulate processing time
        try await Task.sleep(for: .milliseconds(50))
        
        totalEventsSent += events.count
        
        // Store request for verification
        let eventDicts = events.map { event in
            var dict: [String: Any] = [
                "name": event.name,
                "timestamp": event.timestamp
            ]
            
            if let userId = event.userId {
                dict["user_id"] = userId
            }
            
            if let sessionId = event.sessionId {
                dict["session_id"] = sessionId
            }
            
            if !event.metadata.isEmpty {
                dict["metadata"] = event.metadata
            }
            
            return dict
        }
        
        receivedRequests.append((endpoint.absoluteString, eventDicts))
    }
    
    func checkConnectivity() async -> Bool {
        return isOnline
    }
}

enum NetworkError: Error {
    case offline
    case serverError(Int)
}

// MARK: - Testing Extensions

extension LuxAnalytics {
    static func initializeForTesting(
        configuration: LuxAnalyticsConfiguration,
        networkClient: NetworkClientProtocol
    ) async throws -> LuxAnalytics {
        let analyticsActor = AnalyticsActor(
            configuration: configuration,
            networkClient: networkClient
        )
        
        let instance = LuxAnalytics(actor: analyticsActor)
        await LuxAnalyticsStorage.shared.setInstance(instance)
        await LuxAnalyticsStorage.shared.setConfiguration(configuration)
        
        return instance
    }
    
    func getQueuedEventsForTesting() async -> [AnalyticsEvent] {
        return await actor.getQueuedEvents()
    }
}
```

### Integration Testing with Mock Server

```swift
import XCTest
import Network
@testable import LuxAnalytics

class LuxAnalyticsIntegrationTests: XCTestCase {
    
    var mockServer: MockAnalyticsServer!
    var analytics: LuxAnalytics!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Start mock server
        mockServer = MockAnalyticsServer(port: 8001)
        try mockServer.start()
        
        // Wait for server to start
        try await Task.sleep(for: .milliseconds(100))
        
        // Initialize analytics with mock server
        let config = try LuxAnalyticsConfiguration(
            dsn: "https://test@localhost:8001/api/v1/events/integration-test"
        )
        
        try await LuxAnalytics.initialize(with: config)
        analytics = await LuxAnalytics.shared
    }
    
    override func tearDown() async throws {
        mockServer.stop()
        await LuxAnalyticsStorage.shared.setInstance(nil)
        try await super.tearDown()
    }
    
    func testEndToEndEventDelivery() async throws {
        // Track events
        try await analytics.track("integration_test_1", metadata: ["test": true])
        try await analytics.track("integration_test_2", metadata: ["value": 42])
        
        // Flush events
        await analytics.flush()
        
        // Wait for delivery
        try await Task.sleep(for: .seconds(1))
        
        // Verify server received events
        XCTAssertEqual(mockServer.receivedEvents.count, 1) // Should be batched
        XCTAssertEqual(mockServer.receivedEvents[0].events.count, 2)
        
        let events = mockServer.receivedEvents[0].events
        XCTAssertEqual(events[0]["name"] as? String, "integration_test_1")
        XCTAssertEqual(events[1]["name"] as? String, "integration_test_2")
    }
    
    func testNetworkFailureRecovery() async throws {
        // Stop server to simulate failure
        mockServer.stop()
        
        // Track events
        try await analytics.track("failure_test_1")
        try await analytics.track("failure_test_2")
        
        // Attempt flush (should fail)
        await analytics.flush()
        
        // Wait for retry attempts
        try await Task.sleep(for: .seconds(2))
        
        // Events should still be queued
        let stats = await analytics.getQueueStats()
        XCTAssertEqual(stats.totalEvents, 2)
        
        // Restart server
        try mockServer.start()
        
        // Trigger retry
        await analytics.flush()
        
        // Wait for delivery
        try await Task.sleep(for: .seconds(1))
        
        // Verify events were delivered
        XCTAssertEqual(mockServer.receivedEvents.count, 1)
        XCTAssertEqual(mockServer.receivedEvents[0].events.count, 2)
    }
    
    func testCompressionAndSerialization() async throws {
        // Track large event with metadata
        let largeMetadata = [
            "description": String(repeating: "A", count: 1000),
            "data": Array(1...100).map { "item_\($0)" },
            "nested": [
                "level1": [
                    "level2": [
                        "level3": "deep_value"
                    ]
                ]
            ]
        ] as [String: Any]
        
        try await analytics.track("large_event", metadata: largeMetadata)
        
        // Flush with compression
        await analytics.flush()
        
        // Wait for delivery
        try await Task.sleep(for: .seconds(1))
        
        // Verify server received compressed data
        XCTAssertEqual(mockServer.receivedEvents.count, 1)
        
        let receivedEvent = mockServer.receivedEvents[0].events[0]
        XCTAssertEqual(receivedEvent["name"] as? String, "large_event")
        
        // Verify metadata was properly serialized
        let metadata = receivedEvent["metadata"] as? [String: Any]
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?["description"] as? String, largeMetadata["description"] as? String)
    }
}

// MARK: - Mock Analytics Server

@available(iOS 13.0, *)
class MockAnalyticsServer {
    private var listener: NWListener?
    private let port: UInt16
    
    var receivedEvents: [(endpoint: String, events: [[String: Any]])] = []
    
    init(port: UInt16 = 8000) {
        self.port = port
    }
    
    func start() throws {
        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(port)!)
        
        listener?.newConnectionHandler = { connection in
            self.handleConnection(connection)
        }
        
        listener?.start(queue: .global())
    }
    
    func stop() {
        listener?.cancel()
        receivedEvents.removeAll()
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self.processRequest(data, connection: connection)
            }
            
            if isComplete {
                connection.cancel()
            } else if error == nil {
                self.handleConnection(connection)
            }
        }
    }
    
    private func processRequest(_ data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else { return }
        
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }
        
        let components = requestLine.components(separatedBy: " ")
        guard components.count >= 2 else { return }
        
        let method = components[0]
        let path = components[1]
        
        if method == "POST" && path.contains("/api/v1/events/") {
            handleEventsRequest(request, connection: connection)
        } else {
            sendResponse(connection: connection, status: 404, body: "Not Found")
        }
    }
    
    private func handleEventsRequest(_ request: String, connection: NWConnection) {
        // Extract headers and body
        guard let bodyRange = request.range(of: "\r\n\r\n") else {
            sendResponse(connection: connection, status: 400, body: "Bad Request")
            return
        }
        
        let headersPart = String(request[..<bodyRange.lowerBound])
        let bodyPart = String(request[bodyRange.upperBound...])
        
        // Check for compression
        let isCompressed = headersPart.contains("Content-Encoding: deflate")
        
        var jsonData: Data
        if isCompressed {
            // Decompress the body
            jsonData = try! Data(bodyPart.utf8).decompressed()
        } else {
            jsonData = Data(bodyPart.utf8)
        }
        
        // Parse JSON
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) else {
            sendResponse(connection: connection, status: 400, body: "Invalid JSON")
            return
        }
        
        // Process events
        if let eventDict = json as? [String: Any] {
            // Single event
            receivedEvents.append((endpoint: "", events: [eventDict]))
        } else if let eventsDict = json as? [String: Any],
                  let events = eventsDict["events"] as? [[String: Any]] {
            // Batch events
            receivedEvents.append((endpoint: "", events: events))
        }
        
        sendResponse(connection: connection, status: 200, body: "OK")
    }
    
    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let response = """
        HTTP/1.1 \(status) OK\r
        Content-Type: text/plain\r
        Content-Length: \(body.count)\r
        \r
        \(body)
        """
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

extension Data {
    func decompressed() throws -> Data {
        return try (self as NSData).decompressed(using: .zlib) as Data
    }
}
```

### Performance Testing

```swift
import XCTest
@testable import LuxAnalytics

class LuxAnalyticsPerformanceTests: XCTestCase {
    
    var analytics: LuxAnalytics!
    
    override func setUp() async throws {
        try await super.setUp()
        
        let config = try LuxAnalyticsConfiguration(
            dsn: "https://test@localhost:8000/api/v1/events/perf-test",
            batchSize: 100,
            maxQueueSize: 1000
        )
        
        try await LuxAnalytics.initialize(with: config)
        analytics = await LuxAnalytics.shared
    }
    
    func testEventTrackingPerformance() async throws {
        let eventCount = 1000
        
        measure {
            let expectation = XCTestExpectation(description: "Track events")
            
            Task {
                for i in 0..<eventCount {
                    try? await analytics.track("performance_test_\(i)", metadata: [
                        "iteration": i,
                        "timestamp": Date().timeIntervalSince1970
                    ])
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    func testMemoryUsageUnderLoad() async throws {
        let initialMemory = getMemoryUsage()
        
        // Track many events
        for i in 0..<5000 {
            try await analytics.track("memory_test_\(i)", metadata: [
                "data": String(repeating: "x", count: 100) // 100 bytes each
            ])
        }
        
        let afterTrackingMemory = getMemoryUsage()
        
        // Flush queue
        await analytics.flush()
        
        // Wait for processing
        try await Task.sleep(for: .seconds(2))
        
        let afterFlushMemory = getMemoryUsage()
        
        // Memory should not grow excessively
        let memoryGrowth = afterTrackingMemory - initialMemory
        let memoryAfterFlush = afterFlushMemory - initialMemory
        
        print("Initial memory: \(initialMemory) bytes")
        print("After tracking: \(afterTrackingMemory) bytes (+\(memoryGrowth))")
        print("After flush: \(afterFlushMemory) bytes (+\(memoryAfterFlush))")
        
        // Memory growth should be reasonable (less than 10MB)
        XCTAssertLessThan(memoryGrowth, 10 * 1024 * 1024)
        
        // Memory should decrease after flush
        XCTAssertLessThan(memoryAfterFlush, memoryGrowth)
    }
    
    func testConcurrentEventTracking() async throws {
        let eventCount = 100
        let concurrentTasks = 10
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        await withTaskGroup(of: Void.self) { group in
            for taskId in 0..<concurrentTasks {
                group.addTask {
                    for i in 0..<eventCount {
                        try? await self.analytics.track("concurrent_test_\(taskId)_\(i)")
                    }
                }
            }
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        let totalEvents = eventCount * concurrentTasks
        let eventsPerSecond = Double(totalEvents) / totalTime
        
        print("Tracked \(totalEvents) events in \(totalTime)s (\(eventsPerSecond) events/sec)")
        
        // Should be able to track at least 1000 events per second
        XCTAssertGreaterThan(eventsPerSecond, 1000)
        
        // Verify all events were tracked
        let stats = await analytics.getQueueStats()
        XCTAssertEqual(stats.totalEvents, totalEvents)
    }
    
    func testQueuePerformanceUnderPressure() async throws {
        // Fill queue rapidly
        let eventCount = 2000
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<eventCount {
            try await analytics.track("pressure_test_\(i)")
        }
        
        let trackingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Measure flush performance
        let flushStartTime = CFAbsoluteTimeGetCurrent()
        await analytics.flush()
        let flushTime = CFAbsoluteTimeGetCurrent() - flushStartTime
        
        print("Tracking time: \(trackingTime)s")
        print("Flush time: \(flushTime)s")
        
        // Performance should be reasonable
        XCTAssertLessThan(trackingTime, 5.0) // Less than 5 seconds to track 2000 events
        XCTAssertLessThan(flushTime, 10.0)   // Less than 10 seconds to flush
    }
    
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}
```

### UI Testing with Analytics

```swift
import XCTest

class LuxAnalyticsUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        
        app = XCUIApplication()
        
        // Set launch arguments for testing
        app.launchArguments = [
            "-LUX_ANALYTICS_TEST_MODE", "YES",
            "-LUX_ANALYTICS_DSN", "https://test@localhost:8000/api/v1/events/ui-test"
        ]
        
        app.launch()
    }
    
    func testScreenTrackingFlow() throws {
        // Navigate through screens
        XCTAssertTrue(app.staticTexts["Home"].waitForExistence(timeout: 5))
        
        // Tap "Get Started" button
        app.buttons["Get Started"].tap()
        
        // Verify navigation to onboarding
        XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 5))
        
        // Complete onboarding flow
        app.buttons["Next"].tap()
        app.buttons["Next"].tap()
        app.buttons["Get Started"].tap()
        
        // Verify navigation to main screen
        XCTAssertTrue(app.staticTexts["Dashboard"].waitForExistence(timeout: 5))
        
        // Test tab navigation
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 5))
        
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
    }
    
    func testFormInteractionTracking() throws {
        // Navigate to login form
        app.buttons["Login"].tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 5))
        
        // Interact with form fields
        let emailField = app.textFields["Email"]
        emailField.tap()
        emailField.typeText("test@example.com")
        
        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText("password123")
        
        // Submit form
        app.buttons["Sign In"].tap()
        
        // Verify success (or error handling)
        XCTAssertTrue(app.staticTexts["Dashboard"].waitForExistence(timeout: 10))
    }
    
    func testErrorScenarios() throws {
        // Test network error handling
        app.buttons["Settings"].tap()
        app.buttons["Analytics Settings"].tap()
        app.buttons["Test Network Error"].tap()
        
        // Verify error is handled gracefully
        XCTAssertTrue(app.alerts["Network Error"].waitForExistence(timeout: 5))
        app.alerts["Network Error"].buttons["OK"].tap()
        
        // Test offline behavior
        app.buttons["Simulate Offline"].tap()
        app.buttons["Track Test Event"].tap()
        
        // Verify offline indicator
        XCTAssertTrue(app.staticTexts["Offline"].waitForExistence(timeout: 5))
        
        // Go back online
        app.buttons["Simulate Online"].tap()
        XCTAssertTrue(app.staticTexts["Online"].waitForExistence(timeout: 5))
    }
    
    func testAnalyticsPreferences() throws {
        // Navigate to privacy settings
        app.buttons["Settings"].tap()
        app.buttons["Privacy"].tap()
        
        // Toggle analytics
        let analyticsToggle = app.switches["Analytics"]
        XCTAssertTrue(analyticsToggle.exists)
        
        if analyticsToggle.value as? String == "1" {
            analyticsToggle.tap() // Turn off
            XCTAssertEqual(analyticsToggle.value as? String, "0")
        }
        
        analyticsToggle.tap() // Turn on
        XCTAssertEqual(analyticsToggle.value as? String, "1")
        
        // Test data clearing
        app.buttons["Clear Analytics Data"].tap()
        XCTAssertTrue(app.alerts["Confirm"].waitForExistence(timeout: 5))
        app.alerts["Confirm"].buttons["Clear"].tap()
    }
}

// MARK: - Test Utilities

extension XCUIApplication {
    func enableAnalyticsTestMode() {
        launchArguments.append("-LUX_ANALYTICS_TEST_MODE")
        launchArguments.append("YES")
    }
    
    func setAnalyticsEndpoint(_ endpoint: String) {
        launchArguments.append("-LUX_ANALYTICS_DSN")
        launchArguments.append(endpoint)
    }
    
    func waitForAnalyticsReady(timeout: TimeInterval = 5) -> Bool {
        return staticTexts["Analytics Ready"].waitForExistence(timeout: timeout)
    }
}
```

### Testing Analytics Components

```swift
// MARK: - SwiftUI Component Testing

import XCTest
import SwiftUI
@testable import LuxAnalytics

class SwiftUIAnalyticsComponentTests: XCTestCase {
    
    func testScreenTrackingModifier() throws {
        let expectation = XCTestExpectation(description: "Screen tracking")
        
        struct TestView: View {
            var body: some View {
                Text("Test Screen")
                    .trackScreen("test_screen", metadata: ["test": true])
                    .onAppear {
                        expectation.fulfill()
                    }
            }
        }
        
        let hostingController = UIHostingController(rootView: TestView())
        hostingController.viewDidLoad()
        hostingController.viewDidAppear(false)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testButtonTrackingModifier() throws {
        let expectation = XCTestExpectation(description: "Button tracking")
        
        struct TestView: View {
            var body: some View {
                Button("Test Button") {
                    // Button action
                }
                .trackButtonTap("button_tapped") {
                    expectation.fulfill()
                }
            }
        }
        
        let hostingController = UIHostingController(rootView: TestView())
        
        // Simulate button tap
        let button = hostingController.view.subviews.first { $0 is UIButton } as? UIButton
        button?.sendActions(for: .touchUpInside)
        
        wait(for: [expectation], timeout: 5.0)
    }
}

// MARK: - UIKit Component Testing

class UIKitAnalyticsComponentTests: XCTestCase {
    
    func testAnalyticsViewController() throws {
        let viewController = TestAnalyticsViewController()
        viewController.loadViewIfNeeded()
        
        // Test view lifecycle tracking
        viewController.viewWillAppear(true)
        viewController.viewDidAppear(true)
        
        // Verify screen name
        XCTAssertEqual(viewController.screenName, "test_screen")
        
        // Test event tracking
        let expectation = XCTestExpectation(description: "Event tracked")
        
        Task {
            await viewController.trackEvent("test_event")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testButtonAnalyticsExtension() throws {
        let button = UIButton(type: .system)
        button.setTitle("Test Button", for: .normal)
        
        // Add analytics tracking
        button.addAnalyticsTracking(
            eventName: "test_button_tapped",
            metadata: ["location": "test"]
        )
        
        // Verify analytics properties
        XCTAssertEqual(button.analyticsEventName, "test_button_tapped")
        XCTAssertEqual(button.analyticsMetadata?["location"] as? String, "test")
        
        // Simulate tap
        button.sendActions(for: .touchUpInside)
    }
}

class TestAnalyticsViewController: AnalyticsViewController {
    override var screenName: String {
        return "test_screen"
    }
    
    override var screenMetadata: [String: Any] {
        return ["test_mode": true]
    }
}
```

### Testing Best Practices

```swift
// MARK: - Test Helpers and Utilities

class AnalyticsTestHelper {
    
    static func createTestConfiguration() throws -> LuxAnalyticsConfiguration {
        return try LuxAnalyticsConfiguration(
            dsn: "https://test@localhost:8000/api/v1/events/test",
            debugLogging: true,
            requestTimeout: 5.0,
            batchSize: 5,
            maxQueueSize: 100,
            autoFlushInterval: 1.0
        )
    }
    
    static func resetAnalyticsState() async {
        // Reset global state between tests
        await LuxAnalyticsStorage.shared.setInstance(nil)
        await LuxAnalyticsStorage.shared.setConfiguration(nil)
        
        // Clear any cached data
        try? await LuxAnalyticsQueue.shared.clear()
        await GlobalCircuitBreaker.shared.reset()
    }
    
    static func waitForQueueEmpty(timeout: TimeInterval = 5.0) async -> Bool {
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < timeout {
            let stats = await LuxAnalytics.getQueueStats()
            if stats.totalEvents == 0 {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        return false
    }
    
    static func createMockEvents(count: Int) -> [AnalyticsEvent] {
        return (0..<count).map { i in
            AnalyticsEvent(
                name: "test_event_\(i)",
                timestamp: Date(),
                userId: "test_user",
                sessionId: "test_session",
                metadata: ["index": i, "test": true]
            )
        }
    }
    
    static func verifyEventStructure(_ event: [String: Any]) -> Bool {
        guard let name = event["name"] as? String,
              let timestamp = event["timestamp"] as? String,
              !name.isEmpty,
              !timestamp.isEmpty else {
            return false
        }
        
        // Verify timestamp format
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: timestamp) != nil
    }
}

// MARK: - Test Data Builders

struct AnalyticsEventBuilder {
    private var name = "test_event"
    private var timestamp = Date()
    private var userId: String?
    private var sessionId: String?
    private var metadata: [String: Any] = [:]
    
    func withName(_ name: String) -> AnalyticsEventBuilder {
        var builder = self
        builder.name = name
        return builder
    }
    
    func withTimestamp(_ timestamp: Date) -> AnalyticsEventBuilder {
        var builder = self
        builder.timestamp = timestamp
        return builder
    }
    
    func withUser(_ userId: String) -> AnalyticsEventBuilder {
        var builder = self
        builder.userId = userId
        return builder
    }
    
    func withSession(_ sessionId: String) -> AnalyticsEventBuilder {
        var builder = self
        builder.sessionId = sessionId
        return builder
    }
    
    func withMetadata(_ metadata: [String: Any]) -> AnalyticsEventBuilder {
        var builder = self
        builder.metadata = metadata
        return builder
    }
    
    func build() -> AnalyticsEvent {
        return AnalyticsEvent(
            name: name,
            timestamp: timestamp,
            userId: userId,
            sessionId: sessionId,
            metadata: metadata
        )
    }
}

// Usage
let testEvent = AnalyticsEventBuilder()
    .withName("user_signup")
    .withUser("test_user_123")
    .withSession("test_session_456")
    .withMetadata(["method": "email", "source": "app"])
    .build()
```

## Testing Configuration

### Test-Specific Configuration

```swift
// Info.plist for testing
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LuxAnalyticsDSN</key>
    <string>https://test@localhost:8000/api/v1/events/test</string>
    <key>LuxAnalyticsDebugLogging</key>
    <true/>
    <key>LuxAnalyticsBatchSize</key>
    <integer>5</integer>
    <key>LuxAnalyticsAutoFlushInterval</key>
    <integer>1</integer>
    <key>LuxAnalyticsRequestTimeout</key>
    <integer>5</integer>
</dict>
</plist>
```

### Test Schemes

```xml
<!-- XCTest scheme configuration -->
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.8">
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      codeCoverageEnabled = "YES">
      <Testables>
         <TestableReference
            skipped = "NO"
            testExecutionOrdering = "random">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "LuxAnalyticsTests"
               BuildableName = "LuxAnalyticsTests.xctest"
               BlueprintName = "LuxAnalyticsTests"
               ReferencedContainer = "container:LuxAnalytics.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
      <CommandLineArguments>
         <CommandLineArgument
            argument = "-LUX_ANALYTICS_TEST_MODE YES"
            isEnabled = "YES">
         </CommandLineArgument>
      </CommandLineArguments>
   </TestAction>
</Scheme>
```

## Continuous Integration Testing

### GitHub Actions Workflow

```yaml
name: Analytics Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: macos-latest
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: '16.0'
    
    - name: Cache dependencies
      uses: actions/cache@v3
      with:
        path: .build
        key: ${{ runner.os }}-spm-${{ hashFiles('Package.swift') }}
    
    - name: Start mock server
      run: |
        python3 -m http.server 8000 &
        echo $! > server.pid
    
    - name: Run unit tests
      run: swift test --enable-code-coverage
    
    - name: Run integration tests
      run: |
        xcodebuild test \
          -scheme LuxAnalytics \
          -destination 'platform=iOS Simulator,name=iPhone 16' \
          -testPlan IntegrationTests
    
    - name: Run performance tests
      run: |
        xcodebuild test \
          -scheme LuxAnalytics \
          -destination 'platform=iOS Simulator,name=iPhone 16' \
          -testPlan PerformanceTests
    
    - name: Stop mock server
      run: |
        if [ -f server.pid ]; then
          kill $(cat server.pid)
          rm server.pid
        fi
    
    - name: Generate coverage report
      run: |
        xcrun llvm-cov export \
          .build/debug/LuxAnalyticsPackageTests.xctest/Contents/MacOS/LuxAnalyticsPackageTests \
          -instr-profile .build/debug/codecov/default.profdata \
          -format lcov > coverage.lcov
    
    - name: Upload coverage
      uses: codecov/codecov-action@v3
      with:
        file: coverage.lcov
        fail_ci_if_error: true
```

## Testing Checklist

### Pre-Release Testing Checklist

- [ ] **Unit Tests**
  - [ ] Event tracking functionality
  - [ ] Configuration validation
  - [ ] User and session management
  - [ ] Queue management
  - [ ] Network error handling
  - [ ] Retry logic
  - [ ] Compression and serialization

- [ ] **Integration Tests**
  - [ ] End-to-end event delivery
  - [ ] Network failure recovery
  - [ ] Offline behavior
  - [ ] Server compatibility
  - [ ] Performance under load

- [ ] **UI Tests**
  - [ ] Screen tracking flow
  - [ ] Form interaction tracking
  - [ ] Navigation tracking
  - [ ] Error scenario handling
  - [ ] Privacy settings

- [ ] **Performance Tests**
  - [ ] Event tracking performance
  - [ ] Memory usage validation
  - [ ] Concurrent access testing
  - [ ] Queue performance under pressure

- [ ] **Privacy Tests**
  - [ ] Data collection compliance
  - [ ] User preference respect
  - [ ] Data encryption validation
  - [ ] PII filtering verification

- [ ] **Cross-Platform Tests**
  - [ ] iOS 18.0+ compatibility
  - [ ] Device-specific testing
  - [ ] Network condition variations
  - [ ] App lifecycle scenarios

## Best Practices

### ✅ Do

- Test analytics integration early and often
- Use mock servers for integration testing
- Validate performance impact with load testing
- Test offline and network error scenarios
- Verify privacy compliance with test data
- Use test helpers for consistent setup
- Run tests in CI/CD pipeline
- Monitor test coverage metrics

### ❌ Don't

- Skip testing analytics error handling
- Test with production analytics endpoints
- Ignore performance test failures
- Test with real user data
- Skip testing offline behavior
- Forget to test privacy preferences
- Rely only on unit tests
- Test analytics in isolation from app flow

## Next Steps

- [💡 Best Practices](Best-Practices.md) - Production-ready patterns
- [🐛 Troubleshooting](Troubleshooting.md) - Debug common issues
- [🏗️ Custom Extensions](Custom-Extensions.md) - Extend SDK functionality
- [⚡ Performance Optimization](Performance.md) - Advanced performance tuning