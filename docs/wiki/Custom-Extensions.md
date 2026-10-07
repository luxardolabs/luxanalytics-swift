# Custom Extensions Guide

Comprehensive guide to extending LuxAnalytics with custom functionality, plugins, and advanced integrations.

## Extension Architecture

LuxAnalytics provides several extension points for customization:

- **Event Processors**: Transform events before queuing
- **Network Interceptors**: Modify network requests/responses
- **Storage Adapters**: Custom queue storage implementations
- **Analytics Plugins**: Modular feature additions
- **Custom Metrics**: Application-specific measurements

## Event Processing Extensions

### Custom Event Processor

```swift
import LuxAnalytics

protocol EventProcessor {
    func processEvent(_ event: AnalyticsEvent) async -> AnalyticsEvent?
    func shouldProcessEvent(_ event: AnalyticsEvent) -> Bool
}

class EventEnrichmentProcessor: EventProcessor {
    private let deviceInfo: DeviceInfoProvider
    private let appInfo: AppInfoProvider
    
    init(deviceInfo: DeviceInfoProvider = DefaultDeviceInfoProvider(),
         appInfo: AppInfoProvider = DefaultAppInfoProvider()) {
        self.deviceInfo = deviceInfo
        self.appInfo = appInfo
    }
    
    func shouldProcessEvent(_ event: AnalyticsEvent) -> Bool {
        // Process all events except internal ones
        return !event.name.hasPrefix("_lux_")
    }
    
    func processEvent(_ event: AnalyticsEvent) async -> AnalyticsEvent? {
        var enrichedMetadata = event.metadata
        
        // Add device context
        enrichedMetadata["device_model"] = await deviceInfo.getDeviceModel()
        enrichedMetadata["device_os"] = await deviceInfo.getOSVersion()
        enrichedMetadata["device_orientation"] = await deviceInfo.getOrientation()
        enrichedMetadata["battery_level"] = await deviceInfo.getBatteryLevel()
        enrichedMetadata["network_type"] = await deviceInfo.getNetworkType()
        
        // Add app context
        enrichedMetadata["app_version"] = await appInfo.getAppVersion()
        enrichedMetadata["app_build"] = await appInfo.getBuildNumber()
        enrichedMetadata["app_install_date"] = await appInfo.getInstallDate()
        enrichedMetadata["app_session_count"] = await appInfo.getSessionCount()
        
        // Add user context
        enrichedMetadata["user_timezone"] = TimeZone.current.identifier
        enrichedMetadata["user_locale"] = Locale.current.identifier
        enrichedMetadata["user_accessibility_enabled"] = await deviceInfo.isAccessibilityEnabled()
        
        return AnalyticsEvent(
            name: event.name,
            timestamp: event.timestamp,
            userId: event.userId,
            sessionId: event.sessionId,
            metadata: enrichedMetadata
        )
    }
}

// MARK: - Device Info Provider

protocol DeviceInfoProvider {
    func getDeviceModel() async -> String
    func getOSVersion() async -> String
    func getOrientation() async -> String
    func getBatteryLevel() async -> Float
    func getNetworkType() async -> String
    func isAccessibilityEnabled() async -> Bool
}

@MainActor
class DefaultDeviceInfoProvider: DeviceInfoProvider {
    
    func getDeviceModel() async -> String {
        return UIDevice.current.model
    }
    
    func getOSVersion() async -> String {
        return UIDevice.current.systemVersion
    }
    
    func getOrientation() async -> String {
        switch UIDevice.current.orientation {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portrait_upside_down"
        case .landscapeLeft: return "landscape_left"
        case .landscapeRight: return "landscape_right"
        case .faceUp: return "face_up"
        case .faceDown: return "face_down"
        default: return "unknown"
        }
    }
    
    func getBatteryLevel() async -> Float {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        UIDevice.current.isBatteryMonitoringEnabled = false
        return level >= 0 ? level : -1
    }
    
    func getNetworkType() async -> String {
        // Implementation would use Network framework
        return "unknown"
    }
    
    func isAccessibilityEnabled() async -> Bool {
        return UIAccessibility.isVoiceOverRunning ||
               UIAccessibility.isSwitchControlRunning ||
               UIAccessibility.isAssistiveTouchRunning
    }
}

// MARK: - App Info Provider

protocol AppInfoProvider {
    func getAppVersion() async -> String
    func getBuildNumber() async -> String
    func getInstallDate() async -> Date?
    func getSessionCount() async -> Int
}

class DefaultAppInfoProvider: AppInfoProvider {
    
    func getAppVersion() async -> String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
    
    func getBuildNumber() async -> String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }
    
    func getInstallDate() async -> Date? {
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return try? FileManager.default.attributesOfItem(atPath: documentsPath.path)[.creationDate] as? Date
        }
        return nil
    }
    
    func getSessionCount() async -> Int {
        return UserDefaults.standard.integer(forKey: "lux_session_count")
    }
}
```

### A/B Testing Processor

```swift
class ABTestingProcessor: EventProcessor {
    private let abTestingService: ABTestingService
    
    init(abTestingService: ABTestingService) {
        self.abTestingService = abTestingService
    }
    
    func shouldProcessEvent(_ event: AnalyticsEvent) -> Bool {
        return true // Process all events for A/B testing context
    }
    
    func processEvent(_ event: AnalyticsEvent) async -> AnalyticsEvent? {
        var enrichedMetadata = event.metadata
        
        // Add active experiment information
        let activeExperiments = await abTestingService.getActiveExperiments()
        
        for experiment in activeExperiments {
            enrichedMetadata["experiment_\(experiment.name)"] = experiment.variant
            enrichedMetadata["experiment_\(experiment.name)_id"] = experiment.id
        }
        
        // Add user cohort information
        enrichedMetadata["user_cohort"] = await abTestingService.getUserCohort()
        enrichedMetadata["feature_flags"] = await abTestingService.getEnabledFeatureFlags()
        
        return AnalyticsEvent(
            name: event.name,
            timestamp: event.timestamp,
            userId: event.userId,
            sessionId: event.sessionId,
            metadata: enrichedMetadata
        )
    }
}

protocol ABTestingService {
    func getActiveExperiments() async -> [Experiment]
    func getUserCohort() async -> String
    func getEnabledFeatureFlags() async -> [String]
}

struct Experiment {
    let id: String
    let name: String
    let variant: String
}
```

### Privacy Filtering Processor

```swift
class PrivacyFilteringProcessor: EventProcessor {
    private let sensitiveKeywords = [
        "password", "email", "phone", "credit_card", "ssn", "api_key",
        "token", "secret", "private", "confidential"
    ]
    
    private let allowedEvents = Set([
        "screen_viewed", "button_tapped", "app_launched", "app_backgrounded",
        "session_started", "session_ended", "feature_used"
    ])
    
    func shouldProcessEvent(_ event: AnalyticsEvent) -> Bool {
        // Only allow pre-approved event types in strict privacy mode
        if isStrictPrivacyMode() {
            return allowedEvents.contains(event.name)
        }
        return true
    }
    
    func processEvent(_ event: AnalyticsEvent) async -> AnalyticsEvent? {
        let filteredMetadata = filterSensitiveData(event.metadata)
        
        return AnalyticsEvent(
            name: event.name,
            timestamp: event.timestamp,
            userId: shouldIncludeUserId() ? event.userId : nil,
            sessionId: event.sessionId,
            metadata: filteredMetadata
        )
    }
    
    private func filterSensitiveData(_ metadata: [String: Any]) -> [String: Any] {
        var filtered: [String: Any] = [:]
        
        for (key, value) in metadata {
            if containsSensitiveKeyword(key) {
                // Replace with placeholder or hash
                filtered[key] = "[FILTERED]"
            } else if let stringValue = value as? String, isEmailOrPhone(stringValue) {
                filtered[key] = "[PII_FILTERED]"
            } else {
                filtered[key] = value
            }
        }
        
        return filtered
    }
    
    private func containsSensitiveKeyword(_ key: String) -> Bool {
        let lowercaseKey = key.lowercased()
        return sensitiveKeywords.contains { lowercaseKey.contains($0) }
    }
    
    private func isEmailOrPhone(_ value: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let phoneRegex = "\\+?[1-9]\\d{1,14}"
        
        return value.range(of: emailRegex, options: .regularExpression) != nil ||
               value.range(of: phoneRegex, options: .regularExpression) != nil
    }
    
    private func isStrictPrivacyMode() -> Bool {
        return UserDefaults.standard.bool(forKey: "lux_strict_privacy_mode")
    }
    
    private func shouldIncludeUserId() -> Bool {
        return !UserDefaults.standard.bool(forKey: "lux_disable_user_tracking")
    }
}
```

## Network Extensions

### Request Interceptor

```swift
protocol NetworkInterceptor {
    func interceptRequest(_ request: URLRequest) async -> URLRequest
    func interceptResponse(_ response: URLResponse, data: Data) async -> (URLResponse, Data)
}

class HeaderEnrichmentInterceptor: NetworkInterceptor {
    private let customHeaders: [String: String]
    
    init(customHeaders: [String: String] = [:]) {
        self.customHeaders = customHeaders
    }
    
    func interceptRequest(_ request: URLRequest) async -> URLRequest {
        var modifiedRequest = request
        
        // Add custom headers
        for (key, value) in customHeaders {
            modifiedRequest.setValue(value, forHTTPHeaderField: key)
        }
        
        // Add client fingerprint
        modifiedRequest.setValue(await generateClientFingerprint(), forHTTPHeaderField: "X-Client-Fingerprint")
        
        // Add request timing
        modifiedRequest.setValue(String(Date().timeIntervalSince1970), forHTTPHeaderField: "X-Request-Time")
        
        return modifiedRequest
    }
    
    func interceptResponse(_ response: URLResponse, data: Data) async -> (URLResponse, Data) {
        // Log response for debugging
        if let httpResponse = response as? HTTPURLResponse {
            await logResponse(httpResponse, data: data)
        }
        
        return (response, data)
    }
    
    private func generateClientFingerprint() async -> String {
        let device = UIDevice.current
        let fingerprint = "\(device.model)-\(device.systemVersion)-\(Bundle.main.bundleIdentifier ?? "unknown")"
        return fingerprint.data(using: .utf8)?.base64EncodedString() ?? "unknown"
    }
    
    private func logResponse(_ response: HTTPURLResponse, data: Data) async {
        let responseSize = data.count
        let statusCode = response.statusCode
        
        print("Analytics Response: \(statusCode), Size: \(responseSize) bytes")
        
        // Track response metrics
        let analytics = await LuxAnalytics.shared
        try? await analytics.track("_lux_network_response", metadata: [
            "status_code": statusCode,
            "response_size": responseSize,
            "endpoint": response.url?.absoluteString ?? "unknown"
        ])
    }
}

class RetryInterceptor: NetworkInterceptor {
    private let maxRetries: Int
    private let retryDelay: TimeInterval
    
    init(maxRetries: Int = 3, retryDelay: TimeInterval = 1.0) {
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }
    
    func interceptRequest(_ request: URLRequest) async -> URLRequest {
        var modifiedRequest = request
        modifiedRequest.setValue("\(maxRetries)", forHTTPHeaderField: "X-Max-Retries")
        return modifiedRequest
    }
    
    func interceptResponse(_ response: URLResponse, data: Data) async -> (URLResponse, Data) {
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode >= 500 {
            // Server error - mark for retry
            var modifiedResponse = httpResponse
            // Implementation would add retry metadata
        }
        
        return (response, data)
    }
}
```

### Rate Limiting Interceptor

```swift
class RateLimitingInterceptor: NetworkInterceptor {
    private let requestsPerSecond: Double
    private var lastRequestTime: Date = Date.distantPast
    private let queue = DispatchQueue(label: "rate-limiter", qos: .utility)
    
    init(requestsPerSecond: Double = 10.0) {
        self.requestsPerSecond = requestsPerSecond
    }
    
    func interceptRequest(_ request: URLRequest) async -> URLRequest {
        await waitForRateLimit()
        return request
    }
    
    func interceptResponse(_ response: URLResponse, data: Data) async -> (URLResponse, Data) {
        return (response, data)
    }
    
    private func waitForRateLimit() async {
        await withCheckedContinuation { continuation in
            queue.async {
                let now = Date()
                let timeSinceLastRequest = now.timeIntervalSince(self.lastRequestTime)
                let minimumInterval = 1.0 / self.requestsPerSecond
                
                if timeSinceLastRequest < minimumInterval {
                    let delay = minimumInterval - timeSinceLastRequest
                    Thread.sleep(forTimeInterval: delay)
                }
                
                self.lastRequestTime = Date()
                continuation.resume()
            }
        }
    }
}
```

## Storage Extensions

### Custom Queue Storage

```swift
protocol QueueStorageAdapter {
    func saveEvents(_ events: [AnalyticsEvent]) async throws
    func loadEvents() async throws -> [AnalyticsEvent]
    func removeEvents(_ eventIds: [String]) async throws
    func clearAll() async throws
    func getEventCount() async throws -> Int
    func getTotalSize() async throws -> Int
}

class CoreDataQueueStorage: QueueStorageAdapter {
    private let container: NSPersistentContainer
    
    init() {
        container = NSPersistentContainer(name: "AnalyticsQueue")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data error: \(error)")
            }
        }
    }
    
    func saveEvents(_ events: [AnalyticsEvent]) async throws {
        let context = container.newBackgroundContext()
        
        try await context.perform {
            for event in events {
                let entity = AnalyticsEventEntity(context: context)
                entity.id = event.id
                entity.name = event.name
                entity.timestamp = event.timestamp
                entity.userId = event.userId
                entity.sessionId = event.sessionId
                entity.metadata = try JSONSerialization.data(withJSONObject: event.metadata)
            }
            
            try context.save()
        }
    }
    
    func loadEvents() async throws -> [AnalyticsEvent] {
        let context = container.newBackgroundContext()
        
        return try await context.perform {
            let request: NSFetchRequest<AnalyticsEventEntity> = AnalyticsEventEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \AnalyticsEventEntity.timestamp, ascending: true)]
            
            let entities = try context.fetch(request)
            
            return entities.compactMap { entity in
                guard let id = entity.id,
                      let name = entity.name,
                      let timestamp = entity.timestamp,
                      let metadataData = entity.metadata,
                      let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] else {
                    return nil
                }
                
                return AnalyticsEvent(
                    id: id,
                    name: name,
                    timestamp: timestamp,
                    userId: entity.userId,
                    sessionId: entity.sessionId,
                    metadata: metadata
                )
            }
        }
    }
    
    func removeEvents(_ eventIds: [String]) async throws {
        let context = container.newBackgroundContext()
        
        try await context.perform {
            let request: NSFetchRequest<AnalyticsEventEntity> = AnalyticsEventEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", eventIds)
            
            let entities = try context.fetch(request)
            for entity in entities {
                context.delete(entity)
            }
            
            try context.save()
        }
    }
    
    func clearAll() async throws {
        let context = container.newBackgroundContext()
        
        try await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = AnalyticsEventEntity.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            
            try context.execute(deleteRequest)
            try context.save()
        }
    }
    
    func getEventCount() async throws -> Int {
        let context = container.newBackgroundContext()
        
        return try await context.perform {
            let request: NSFetchRequest<AnalyticsEventEntity> = AnalyticsEventEntity.fetchRequest()
            return try context.count(for: request)
        }
    }
    
    func getTotalSize() async throws -> Int {
        let context = container.newBackgroundContext()
        
        return try await context.perform {
            let request: NSFetchRequest<AnalyticsEventEntity> = AnalyticsEventEntity.fetchRequest()
            let entities = try context.fetch(request)
            
            return entities.reduce(0) { total, entity in
                total + (entity.metadata?.count ?? 0)
            }
        }
    }
}

// Core Data model would be defined in .xcdatamodeld file
@objc(AnalyticsEventEntity)
class AnalyticsEventEntity: NSManagedObject {
    @NSManaged var id: String?
    @NSManaged var name: String?
    @NSManaged var timestamp: Date?
    @NSManaged var userId: String?
    @NSManaged var sessionId: String?
    @NSManaged var metadata: Data?
}
```

### SQLite Queue Storage

```swift
import SQLite3

class SQLiteQueueStorage: QueueStorageAdapter {
    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "sqlite-queue", qos: .utility)
    
    init(dbPath: String? = nil) {
        self.dbPath = dbPath ?? Self.defaultDatabasePath()
        Task {
            await initializeDatabase()
        }
    }
    
    private static func defaultDatabasePath() -> String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("analytics_queue.db").path
    }
    
    private func initializeDatabase() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if sqlite3_open(self.dbPath, &self.db) == SQLITE_OK {
                    self.createTables()
                    continuation.resume()
                } else {
                    fatalError("Unable to open database")
                }
            }
        }
    }
    
    private func createTables() {
        let createTableSQL = """
            CREATE TABLE IF NOT EXISTS analytics_events (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                timestamp REAL NOT NULL,
                user_id TEXT,
                session_id TEXT,
                metadata TEXT,
                created_at REAL DEFAULT (julianday('now'))
            );
            CREATE INDEX IF NOT EXISTS idx_timestamp ON analytics_events(timestamp);
            CREATE INDEX IF NOT EXISTS idx_created_at ON analytics_events(created_at);
        """
        
        if sqlite3_exec(db, createTableSQL, nil, nil, nil) != SQLITE_OK {
            fatalError("Error creating table")
        }
    }
    
    func saveEvents(_ events: [AnalyticsEvent]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.performSaveEvents(events)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func performSaveEvents(_ events: [AnalyticsEvent]) throws {
        let insertSQL = """
            INSERT INTO analytics_events (id, name, timestamp, user_id, session_id, metadata)
            VALUES (?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            for event in events {
                let metadataJSON = try JSONSerialization.data(withJSONObject: event.metadata)
                let metadataString = String(data: metadataJSON, encoding: .utf8) ?? ""
                
                sqlite3_bind_text(statement, 1, event.id, -1, nil)
                sqlite3_bind_text(statement, 2, event.name, -1, nil)
                sqlite3_bind_double(statement, 3, event.timestamp.timeIntervalSince1970)
                sqlite3_bind_text(statement, 4, event.userId, -1, nil)
                sqlite3_bind_text(statement, 5, event.sessionId, -1, nil)
                sqlite3_bind_text(statement, 6, metadataString, -1, nil)
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    throw SQLiteError.insertFailed
                }
                
                sqlite3_reset(statement)
            }
        }
        
        sqlite3_finalize(statement)
    }
    
    func loadEvents() async throws -> [AnalyticsEvent] {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let events = try self.performLoadEvents()
                    continuation.resume(returning: events)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func performLoadEvents() throws -> [AnalyticsEvent] {
        let selectSQL = """
            SELECT id, name, timestamp, user_id, session_id, metadata
            FROM analytics_events
            ORDER BY created_at ASC;
        """
        
        var statement: OpaquePointer?
        var events: [AnalyticsEvent] = []
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let name = String(cString: sqlite3_column_text(statement, 1))
                let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                
                let userId: String?
                if let userIdCString = sqlite3_column_text(statement, 3) {
                    userId = String(cString: userIdCString)
                } else {
                    userId = nil
                }
                
                let sessionId: String?
                if let sessionIdCString = sqlite3_column_text(statement, 4) {
                    sessionId = String(cString: sessionIdCString)
                } else {
                    sessionId = nil
                }
                
                let metadataString = String(cString: sqlite3_column_text(statement, 5))
                let metadata: [String: Any]
                if let data = metadataString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    metadata = json
                } else {
                    metadata = [:]
                }
                
                let event = AnalyticsEvent(
                    id: id,
                    name: name,
                    timestamp: timestamp,
                    userId: userId,
                    sessionId: sessionId,
                    metadata: metadata
                )
                
                events.append(event)
            }
        }
        
        sqlite3_finalize(statement)
        return events
    }
    
    func removeEvents(_ eventIds: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.performRemoveEvents(eventIds)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func performRemoveEvents(_ eventIds: [String]) throws {
        let placeholders = Array(repeating: "?", count: eventIds.count).joined(separator: ",")
        let deleteSQL = "DELETE FROM analytics_events WHERE id IN (\(placeholders));"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            for (index, eventId) in eventIds.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 1), eventId, -1, nil)
            }
            
            if sqlite3_step(statement) != SQLITE_DONE {
                throw SQLiteError.deleteFailed
            }
        }
        
        sqlite3_finalize(statement)
    }
    
    func clearAll() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let deleteSQL = "DELETE FROM analytics_events;"
                if sqlite3_exec(self.db, deleteSQL, nil, nil, nil) == SQLITE_OK {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SQLiteError.clearFailed)
                }
            }
        }
    }
    
    func getEventCount() async throws -> Int {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let countSQL = "SELECT COUNT(*) FROM analytics_events;"
                var statement: OpaquePointer?
                var count = 0
                
                if sqlite3_prepare_v2(self.db, countSQL, -1, &statement, nil) == SQLITE_OK {
                    if sqlite3_step(statement) == SQLITE_ROW {
                        count = Int(sqlite3_column_int(statement, 0))
                    }
                }
                
                sqlite3_finalize(statement)
                continuation.resume(returning: count)
            }
        }
    }
    
    func getTotalSize() async throws -> Int {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let sizeSQL = "SELECT SUM(LENGTH(metadata)) FROM analytics_events;"
                var statement: OpaquePointer?
                var size = 0
                
                if sqlite3_prepare_v2(self.db, sizeSQL, -1, &statement, nil) == SQLITE_OK {
                    if sqlite3_step(statement) == SQLITE_ROW {
                        size = Int(sqlite3_column_int(statement, 0))
                    }
                }
                
                sqlite3_finalize(statement)
                continuation.resume(returning: size)
            }
        }
    }
    
    deinit {
        sqlite3_close(db)
    }
}

enum SQLiteError: Error {
    case insertFailed
    case deleteFailed
    case clearFailed
}
```

## Analytics Plugins

### Performance Monitoring Plugin

```swift
protocol AnalyticsPlugin {
    var name: String { get }
    func initialize() async
    func processEvent(_ event: AnalyticsEvent) async -> AnalyticsEvent?
    func onFlush() async
    func onError(_ error: Error) async
}

class PerformanceMonitoringPlugin: AnalyticsPlugin {
    let name = "PerformanceMonitoring"
    
    private var appLaunchTime: Date?
    private var screenLoadTimes: [String: Date] = [:]
    private var memoryWarnings: [Date] = []
    
    func initialize() async {
        appLaunchTime = Date()
        setupMemoryMonitoring()
        setupPerformanceMetrics()
    }
    
    func processEvent(_ event: AnalyticsEvent) async -> AnalyticsEvent? {
        var enrichedMetadata = event.metadata
        
        // Add performance context
        enrichedMetadata["memory_usage"] = getCurrentMemoryUsage()
        enrichedMetadata["cpu_usage"] = getCurrentCPUUsage()
        enrichedMetadata["battery_level"] = getBatteryLevel()
        enrichedMetadata["thermal_state"] = getThermalState()
        
        // Track screen load times
        if event.name == "screen_viewed" {
            if let screenName = event.metadata["screen_name"] as? String {
                trackScreenLoadTime(screenName)
                
                if let loadTime = calculateScreenLoadTime(screenName) {
                    enrichedMetadata["screen_load_time"] = loadTime
                }
            }
        }
        
        // Track app launch time
        if event.name == "app_launched", let launchTime = appLaunchTime {
            enrichedMetadata["app_launch_duration"] = Date().timeIntervalSince(launchTime)
        }
        
        return AnalyticsEvent(
            name: event.name,
            timestamp: event.timestamp,
            userId: event.userId,
            sessionId: event.sessionId,
            metadata: enrichedMetadata
        )
    }
    
    func onFlush() async {
        // Send performance summary
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("_performance_summary", metadata: [
            "memory_warnings_count": memoryWarnings.count,
            "average_memory_usage": getAverageMemoryUsage(),
            "peak_memory_usage": getPeakMemoryUsage(),
            "screen_count": screenLoadTimes.count
        ])
    }
    
    func onError(_ error: Error) async {
        // Track performance during errors
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("_performance_error", metadata: [
            "error_type": String(describing: type(of: error)),
            "memory_usage_at_error": getCurrentMemoryUsage(),
            "cpu_usage_at_error": getCurrentCPUUsage()
        ])
    }
    
    private func setupMemoryMonitoring() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.memoryWarnings.append(Date())
        }
    }
    
    private func setupPerformanceMetrics() {
        // Setup timer for periodic performance sampling
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task {
                await self?.recordPerformanceMetrics()
            }
        }
    }
    
    private func recordPerformanceMetrics() async {
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("_performance_sample", metadata: [
            "memory_usage": getCurrentMemoryUsage(),
            "cpu_usage": getCurrentCPUUsage(),
            "battery_level": getBatteryLevel(),
            "thermal_state": getThermalState(),
            "disk_space_free": getDiskSpaceFree()
        ])
    }
    
    private func trackScreenLoadTime(_ screenName: String) {
        screenLoadTimes[screenName] = Date()
    }
    
    private func calculateScreenLoadTime(_ screenName: String) -> TimeInterval? {
        guard let startTime = screenLoadTimes[screenName] else { return nil }
        return Date().timeIntervalSince(startTime)
    }
    
    private func getCurrentMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
    
    private func getCurrentCPUUsage() -> Double {
        // Implementation would use system APIs to get CPU usage
        return 0.0
    }
    
    private func getBatteryLevel() -> Float {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        UIDevice.current.isBatteryMonitoringEnabled = false
        return level
    }
    
    private func getThermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
    
    private func getDiskSpaceFree() -> Int64 {
        guard let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            return 0
        }
        
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: path)
            return attributes[.systemFreeSize] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    private func getAverageMemoryUsage() -> Int {
        // Implementation would track memory usage over time
        return getCurrentMemoryUsage()
    }
    
    private func getPeakMemoryUsage() -> Int {
        // Implementation would track peak memory usage
        return getCurrentMemoryUsage()
    }
}
```

### User Behavior Plugin

```swift
class UserBehaviorPlugin: AnalyticsPlugin {
    let name = "UserBehavior"
    
    private var sessionEvents: [AnalyticsEvent] = []
    private var userJourney: [String] = []
    private var clickHeatmap: [String: Int] = [:]
    private var timeOnScreen: [String: TimeInterval] = [:]
    private var currentScreen: String?
    private var screenStartTime: Date?
    
    func initialize() async {
        // Setup behavior tracking
    }
    
    func processEvent(_ event: AnalyticsEvent) async -> AnalyticsEvent? {
        sessionEvents.append(event)
        
        var enrichedMetadata = event.metadata
        
        // Track user journey
        if event.name == "screen_viewed" {
            if let screenName = event.metadata["screen_name"] as? String {
                updateUserJourney(screenName)
                enrichedMetadata["journey_position"] = userJourney.count
                enrichedMetadata["journey_path"] = userJourney.suffix(5).joined(separator: " → ")
                
                // Calculate time on previous screen
                if let currentScreen = currentScreen,
                   let startTime = screenStartTime {
                    let timeSpent = Date().timeIntervalSince(startTime)
                    timeOnScreen[currentScreen] = timeSpent
                    enrichedMetadata["previous_screen_time"] = timeSpent
                }
                
                currentScreen = screenName
                screenStartTime = Date()
            }
        }
        
        // Track click patterns
        if event.name.contains("button_tapped") || event.name.contains("tap") {
            if let elementId = event.metadata["button_id"] as? String ?? event.metadata["element_id"] as? String {
                clickHeatmap[elementId, default: 0] += 1
                enrichedMetadata["element_total_clicks"] = clickHeatmap[elementId]
            }
        }
        
        // Add behavioral context
        enrichedMetadata["session_event_count"] = sessionEvents.count
        enrichedMetadata["user_engagement_score"] = calculateEngagementScore()
        enrichedMetadata["behavior_pattern"] = identifyBehaviorPattern()
        
        return AnalyticsEvent(
            name: event.name,
            timestamp: event.timestamp,
            userId: event.userId,
            sessionId: event.sessionId,
            metadata: enrichedMetadata
        )
    }
    
    func onFlush() async {
        // Send behavior summary
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("_user_behavior_summary", metadata: [
            "session_length": sessionEvents.count,
            "unique_screens_visited": Set(userJourney).count,
            "total_clicks": clickHeatmap.values.reduce(0, +),
            "average_time_per_screen": calculateAverageTimePerScreen(),
            "most_used_feature": getMostUsedFeature(),
            "engagement_score": calculateEngagementScore()
        ])
    }
    
    func onError(_ error: Error) async {
        // Track behavior context during errors
        let analytics = await LuxAnalytics.shared
        
        try? await analytics.track("_behavior_error_context", metadata: [
            "events_before_error": sessionEvents.count,
            "current_screen": currentScreen ?? "unknown",
            "recent_journey": userJourney.suffix(3).joined(separator: " → ")
        ])
    }
    
    private func updateUserJourney(_ screenName: String) {
        userJourney.append(screenName)
        
        // Keep journey manageable
        if userJourney.count > 50 {
            userJourney.removeFirst(10)
        }
    }
    
    private func calculateEngagementScore() -> Double {
        let screenCount = Set(userJourney).count
        let eventCount = sessionEvents.count
        let clickCount = clickHeatmap.values.reduce(0, +)
        
        // Simple engagement score based on activity
        return Double(screenCount + eventCount + clickCount) / 100.0
    }
    
    private func identifyBehaviorPattern() -> String {
        let recentEvents = sessionEvents.suffix(10).map { $0.name }
        
        if recentEvents.filter({ $0.contains("search") }).count >= 3 {
            return "search_heavy"
        } else if recentEvents.filter({ $0.contains("scroll") }).count >= 5 {
            return "browser"
        } else if recentEvents.filter({ $0.contains("button") }).count >= 4 {
            return "action_oriented"
        } else {
            return "exploring"
        }
    }
    
    private func calculateAverageTimePerScreen() -> TimeInterval {
        guard !timeOnScreen.isEmpty else { return 0 }
        return timeOnScreen.values.reduce(0, +) / Double(timeOnScreen.count)
    }
    
    private func getMostUsedFeature() -> String {
        return clickHeatmap.max(by: { $0.value < $1.value })?.key ?? "unknown"
    }
}
```

## Custom Metrics

### Business Metrics Extension

```swift
class BusinessMetricsTracker {
    private let analytics: LuxAnalytics
    
    init(analytics: LuxAnalytics) {
        self.analytics = analytics
    }
    
    // E-commerce metrics
    func trackPurchase(
        productId: String,
        productName: String,
        price: Decimal,
        currency: String,
        quantity: Int = 1,
        category: String? = nil
    ) async {
        try? await analytics.track("purchase", metadata: [
            "product_id": productId,
            "product_name": productName,
            "price": NSDecimalNumber(decimal: price).doubleValue,
            "currency": currency,
            "quantity": quantity,
            "category": category ?? "unknown",
            "revenue": NSDecimalNumber(decimal: price * Decimal(quantity)).doubleValue
        ])
    }
    
    func trackAddToCart(
        productId: String,
        productName: String,
        price: Decimal,
        currency: String,
        quantity: Int = 1
    ) async {
        try? await analytics.track("add_to_cart", metadata: [
            "product_id": productId,
            "product_name": productName,
            "price": NSDecimalNumber(decimal: price).doubleValue,
            "currency": currency,
            "quantity": quantity,
            "cart_value": await getCurrentCartValue()
        ])
    }
    
    func trackRemoveFromCart(productId: String, reason: String = "user_action") async {
        try? await analytics.track("remove_from_cart", metadata: [
            "product_id": productId,
            "reason": reason,
            "cart_value_after": await getCurrentCartValue()
        ])
    }
    
    // Subscription metrics
    func trackSubscriptionStart(
        planId: String,
        planName: String,
        price: Decimal,
        currency: String,
        billingPeriod: String,
        trialDays: Int? = nil
    ) async {
        var metadata: [String: Any] = [
            "plan_id": planId,
            "plan_name": planName,
            "price": NSDecimalNumber(decimal: price).doubleValue,
            "currency": currency,
            "billing_period": billingPeriod,
            "subscription_type": "new"
        ]
        
        if let trialDays = trialDays {
            metadata["trial_days"] = trialDays
            metadata["subscription_type"] = "trial"
        }
        
        try? await analytics.track("subscription_started", metadata: metadata)
    }
    
    func trackSubscriptionCancel(planId: String, reason: String, daysActive: Int) async {
        try? await analytics.track("subscription_cancelled", metadata: [
            "plan_id": planId,
            "cancellation_reason": reason,
            "days_active": daysActive,
            "ltv_impact": await calculateLTVImpact(planId: planId, daysActive: daysActive)
        ])
    }
    
    // Content metrics
    func trackContentView(
        contentId: String,
        contentType: String,
        contentTitle: String,
        duration: TimeInterval? = nil
    ) async {
        var metadata: [String: Any] = [
            "content_id": contentId,
            "content_type": contentType,
            "content_title": contentTitle,
            "content_category": await getContentCategory(contentId: contentId)
        ]
        
        if let duration = duration {
            metadata["view_duration"] = duration
        }
        
        try? await analytics.track("content_viewed", metadata: metadata)
    }
    
    func trackContentShare(
        contentId: String,
        shareMethod: String,
        contentType: String
    ) async {
        try? await analytics.track("content_shared", metadata: [
            "content_id": contentId,
            "share_method": shareMethod,
            "content_type": contentType,
            "viral_coefficient": await calculateViralCoefficient()
        ])
    }
    
    // User lifecycle metrics
    func trackUserOnboarding(step: String, completed: Bool, timeSpent: TimeInterval) async {
        try? await analytics.track("onboarding_step", metadata: [
            "step": step,
            "completed": completed,
            "time_spent": timeSpent,
            "total_onboarding_time": await getTotalOnboardingTime(),
            "completion_rate": await getOnboardingCompletionRate()
        ])
    }
    
    func trackFeatureAdoption(featureName: String, isFirstUse: Bool) async {
        try? await analytics.track("feature_used", metadata: [
            "feature_name": featureName,
            "is_first_use": isFirstUse,
            "adoption_rate": await getFeatureAdoptionRate(featureName),
            "time_to_adoption": isFirstUse ? await getTimeToAdoption(featureName) : nil
        ])
    }
    
    // Performance metrics
    func trackAPICall(
        endpoint: String,
        method: String,
        statusCode: Int,
        responseTime: TimeInterval,
        success: Bool
    ) async {
        try? await analytics.track("api_call", metadata: [
            "endpoint": endpoint,
            "method": method,
            "status_code": statusCode,
            "response_time": responseTime,
            "success": success,
            "api_health_score": await calculateAPIHealthScore()
        ])
    }
    
    func trackCrash(
        errorType: String,
        errorMessage: String,
        stackTrace: String,
        isFatal: Bool
    ) async {
        try? await analytics.track("app_crash", metadata: [
            "error_type": errorType,
            "error_message": errorMessage,
            "stack_trace": stackTrace,
            "is_fatal": isFatal,
            "crash_rate": await getCrashRate(),
            "session_duration_before_crash": await getSessionDuration()
        ])
    }
    
    // Helper methods (implementations would depend on your app's data layer)
    private func getCurrentCartValue() async -> Double {
        // Implementation depends on your cart system
        return 0.0
    }
    
    private func calculateLTVImpact(planId: String, daysActive: Int) async -> Double {
        // Implementation would calculate lifetime value impact
        return 0.0
    }
    
    private func getContentCategory(contentId: String) async -> String {
        // Implementation would look up content category
        return "unknown"
    }
    
    private func calculateViralCoefficient() async -> Double {
        // Implementation would calculate viral sharing metrics
        return 0.0
    }
    
    private func getTotalOnboardingTime() async -> TimeInterval {
        // Implementation would track total onboarding time
        return 0.0
    }
    
    private func getOnboardingCompletionRate() async -> Double {
        // Implementation would calculate completion rate
        return 0.0
    }
    
    private func getFeatureAdoptionRate(_ featureName: String) async -> Double {
        // Implementation would calculate adoption rate
        return 0.0
    }
    
    private func getTimeToAdoption(_ featureName: String) async -> TimeInterval? {
        // Implementation would calculate time from signup to first use
        return nil
    }
    
    private func calculateAPIHealthScore() async -> Double {
        // Implementation would calculate API health metrics
        return 1.0
    }
    
    private func getCrashRate() async -> Double {
        // Implementation would calculate crash rate
        return 0.0
    }
    
    private func getSessionDuration() async -> TimeInterval {
        // Implementation would get current session duration
        return 0.0
    }
}
```

## Extension Integration

### Plugin Manager

```swift
class AnalyticsExtensionManager {
    private var eventProcessors: [EventProcessor] = []
    private var networkInterceptors: [NetworkInterceptor] = []
    private var plugins: [AnalyticsPlugin] = []
    private var customStorageAdapter: QueueStorageAdapter?
    
    func addEventProcessor(_ processor: EventProcessor) {
        eventProcessors.append(processor)
    }
    
    func addNetworkInterceptor(_ interceptor: NetworkInterceptor) {
        networkInterceptors.append(interceptor)
    }
    
    func addPlugin(_ plugin: AnalyticsPlugin) {
        plugins.append(plugin)
        Task {
            await plugin.initialize()
        }
    }
    
    func setCustomStorage(_ adapter: QueueStorageAdapter) {
        customStorageAdapter = adapter
    }
    
    func processEvent(_ event: AnalyticsEvent) async -> AnalyticsEvent? {
        var processedEvent: AnalyticsEvent? = event
        
        for processor in eventProcessors {
            guard let currentEvent = processedEvent,
                  processor.shouldProcessEvent(currentEvent) else { continue }
            
            processedEvent = await processor.processEvent(currentEvent)
        }
        
        // Process through plugins
        for plugin in plugins {
            guard let currentEvent = processedEvent else { break }
            processedEvent = await plugin.processEvent(currentEvent)
        }
        
        return processedEvent
    }
    
    func processRequest(_ request: URLRequest) async -> URLRequest {
        var processedRequest = request
        
        for interceptor in networkInterceptors {
            processedRequest = await interceptor.interceptRequest(processedRequest)
        }
        
        return processedRequest
    }
    
    func processResponse(_ response: URLResponse, data: Data) async -> (URLResponse, Data) {
        var processedResponse = (response, data)
        
        for interceptor in networkInterceptors {
            processedResponse = await interceptor.interceptResponse(processedResponse.0, data: processedResponse.1)
        }
        
        return processedResponse
    }
    
    func onFlush() async {
        for plugin in plugins {
            await plugin.onFlush()
        }
    }
    
    func onError(_ error: Error) async {
        for plugin in plugins {
            await plugin.onError(error)
        }
    }
    
    func getCustomStorage() -> QueueStorageAdapter? {
        return customStorageAdapter
    }
}

// Usage in LuxAnalytics initialization
extension LuxAnalytics {
    static func initializeWithExtensions(
        configuration: LuxAnalyticsConfiguration,
        extensionManager: AnalyticsExtensionManager
    ) async throws {
        // Setup analytics with extensions
        let analytics = try await initialize(with: configuration)
        
        // Configure extensions
        await analytics.setExtensionManager(extensionManager)
    }
}
```

### Example Usage

```swift
// Complete extension setup example
func setupAnalyticsWithExtensions() async throws {
    let extensionManager = AnalyticsExtensionManager()
    
    // Add event processors
    extensionManager.addEventProcessor(EventEnrichmentProcessor())
    extensionManager.addEventProcessor(ABTestingProcessor(abTestingService: MyABTestingService()))
    extensionManager.addEventProcessor(PrivacyFilteringProcessor())
    
    // Add network interceptors
    extensionManager.addNetworkInterceptor(HeaderEnrichmentInterceptor(customHeaders: [
        "X-App-Version": Bundle.main.appVersion ?? "unknown",
        "X-Platform": "iOS"
    ]))
    extensionManager.addNetworkInterceptor(RateLimitingInterceptor(requestsPerSecond: 5.0))
    
    // Add plugins
    extensionManager.addPlugin(PerformanceMonitoringPlugin())
    extensionManager.addPlugin(UserBehaviorPlugin())
    
    // Use custom storage if needed
    extensionManager.setCustomStorage(SQLiteQueueStorage())
    
    // Initialize analytics with extensions
    let config = try LuxAnalyticsConfiguration(dsn: "your-dsn-here")
    try await LuxAnalytics.initializeWithExtensions(
        configuration: config,
        extensionManager: extensionManager
    )
    
    // Setup business metrics tracker
    let analytics = await LuxAnalytics.shared
    let businessMetrics = BusinessMetricsTracker(analytics: analytics)
    
    // Example business tracking
    await businessMetrics.trackPurchase(
        productId: "premium_plan",
        productName: "Premium Subscription",
        price: 9.99,
        currency: "USD",
        category: "subscription"
    )
}
```

## Best Practices for Extensions

### ✅ Do

- Keep extensions focused on single responsibilities
- Handle errors gracefully in extensions
- Use async/await for extension operations
- Test extensions thoroughly
- Document extension APIs clearly
- Respect user privacy in extensions
- Monitor extension performance impact
- Provide configuration options for extensions

### ❌ Don't

- Block the main thread in extensions
- Create circular dependencies between extensions
- Store sensitive data in extensions
- Ignore extension errors
- Make extensions too complex
- Couple extensions tightly to your app
- Skip testing extension edge cases
- Create memory leaks in extensions

## Next Steps

- [💡 Best Practices](Best-Practices.md) - Production-ready patterns
- [🧪 Testing Guide](Testing.md) - Test custom extensions
- [⚡ Performance Optimization](Performance.md) - Optimize extension performance
- [🐛 Troubleshooting](Troubleshooting.md) - Debug extension issues