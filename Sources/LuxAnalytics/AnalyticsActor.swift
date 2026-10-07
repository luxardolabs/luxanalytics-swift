@preconcurrency import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

/// Actor that handles all analytics operations in a thread-safe manner
actor AnalyticsActor {
    private let configuration: LuxAnalyticsConfiguration
    private var currentUserId: String?
    private var currentSessionId: String?
    private var flushTask: Task<Void, Never>?
    private var notificationObservers: [NSObjectProtocol] = []
    
    init(configuration: LuxAnalyticsConfiguration) {
        self.configuration = configuration
    }
    
    func setUser(_ userId: String?) {
        self.currentUserId = userId
        SecureLogger.log("User set: \(userId ?? "nil")", category: .general, level: .debug)
    }
    
    func setSession(_ sessionId: String?) {
        self.currentSessionId = sessionId
        SecureLogger.log("Session set: \(sessionId ?? "nil")", category: .general, level: .debug)
    }
    
    func getUserId() -> String? {
        return currentUserId
    }
    
    func getSessionId() -> String? {
        return currentSessionId
    }
    
    func setupAutoFlush() {
        flushTask?.cancel()
        flushTask = Task {
            for await _ in AsyncTimer.schedule(every: .seconds(configuration.autoFlushInterval)) {
                await LuxAnalytics.flush()
            }
        }
    }
    
    func setupAppLifecycleObservers() {
        #if canImport(UIKit)
        Task { @MainActor in
            await self.registerNotificationObservers()
        }
        #endif
    }
    
    #if canImport(UIKit)
    @MainActor
    private func registerNotificationObservers() async {
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleAppBackground()
            }
        }
        await self.addNotificationObserver(backgroundObserver)
        
        let terminateObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await LuxAnalytics.flush()
            }
        }
        await self.addNotificationObserver(terminateObserver)
        
        // Memory warning handling
        let memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleMemoryWarning()
            }
        }
        await self.addNotificationObserver(memoryObserver)
    }
    #endif
    
    func cleanup() {
        flushTask?.cancel()
        flushTask = nil
        removeLifecycleObservers()
    }
    
    func debugLog(_ message: String) {
        SecureLogger.log(message, category: .general, level: .debug)
    }
    
    
    private func handleMemoryWarning() async {
        debugLog("Received memory warning")
        
        // Get current queue stats
        let stats = await LuxAnalyticsQueue.shared.getQueueStats()
        
        // If queue is large, flush it
        if stats.totalEvents > (configuration.maxQueueSize / 2) {
            debugLog("Flushing \(stats.totalEvents) events due to memory warning")
            await LuxAnalytics.flush()
        }
        
        // Clear any cached data
        // Note: Our current implementation doesn't have much in-memory cache
        // but this is where you'd clear it if needed
    }
    
    private func removeLifecycleObservers() {
        #if canImport(UIKit)
        unregisterNotificationObservers()
        #endif
    }

    private func addNotificationObserver(_ observer: NSObjectProtocol) {
        notificationObservers.append(observer)
    }
    
    private func unregisterNotificationObservers() {
        // NotificationCenter.removeObserver is thread-safe — no need to hop to MainActor
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }
    
    private func handleAppBackground() async {
        debugLog("App entering background - triggering flush")
        
        #if canImport(UIKit)
        // Request background task
        await BackgroundTaskManager.shared.runBackgroundTask { [weak self] in
            guard let self = self else { return }
            
            // Flush events
            await LuxAnalytics.flush()
            await self.debugLog("Background flush completed")
        }
        #else
        // On non-iOS platforms, just flush immediately
        await LuxAnalytics.flush()
        #endif
    }
    
    deinit {
        // Ensure cleanup happens
        #if canImport(UIKit)
        let observers = notificationObservers
        observers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
        SecureLogger.log("AnalyticsActor deinit", category: .general, level: .debug)
    }
}