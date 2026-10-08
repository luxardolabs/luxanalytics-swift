import BackgroundTasks
import Foundation
import UIKit

// Checks that only run inside a real app on the simulator: Keychain access, persistence
// across launches and reinstalls, app lifecycle notifications, BGTaskScheduler. Built
// together with the SDK's sources (so internals are visible) by scripts/host-check.sh,
// which launches it once per phase and fails on any FAIL line.
//
// Phases (the first launch argument):
//   migrate    a queue saved by SDK <= 1.0.x (plaintext, legacy key) is migrated to the
//              encrypted store, and the plaintext copy is removed
//   migrated   relaunch: the migrated events are still there (before 1.1.0 they were lost)
//   first      fresh install: encryption, persist a queue, reset the device ID,
//              lifecycle flush, background task registration
//   relaunch   same install: the queue loads before the first enqueue, device ID kept
//   reinstall  after uninstall + reinstall: device ID kept (Keychain), queue gone

@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let arguments = CommandLine.arguments
        let phase = arguments.count > 1 ? arguments[1] : "first"
        let expectedID = arguments.count > 2 ? arguments[2] : ""
        // BGTaskScheduler registration must finish before launch does.
        if phase == "first" {
            LuxAnalytics.enableBackgroundProcessing()
        }
        Task {
            await HostChecks(phase: phase, expectedDeviceID: expectedID).run()
            exit(0)
        }
        return true
    }
}

@MainActor
struct HostChecks {
    let phase: String
    let expectedDeviceID: String
    private static var counts = (pass: 0, fail: 0, skip: 0)

    func run() async {
        switch phase {
        case "migrate": await migrate()
        case "migrated": await migrated()
        case "first": await first()
        case "relaunch": await relaunch()
        case "reinstall": await reinstall()
        default: check(false, "phase", "unknown phase \(phase)")
        }
        emit("HOSTCHECK DONE phase=\(phase) pass=\(Self.counts.pass) fail=\(Self.counts.fail) skip=\(Self.counts.skip)")
    }

    private func skip(_ name: String, _ reason: String) {
        Self.counts.skip += 1
        emit("HOSTCHECK SKIP \(phase)/\(name): \(reason)")
    }

    private func check(_ condition: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if condition {
            Self.counts.pass += 1
            emit("HOSTCHECK PASS \(phase)/\(name)")
        } else {
            Self.counts.fail += 1
            emit("HOSTCHECK FAIL \(phase)/\(name): \(detail())")
        }
    }

    private func event(_ name: String) -> AnalyticsEvent {
        AnalyticsEvent(name: name, timestamp: "2026-01-01T00:00:00Z", userId: nil, sessionId: nil, metadata: [:])
    }

    // MARK: - Phases

    private func migrate() async {
        let legacy = (0..<3).map { QueuedEvent(event: event("legacy-\($0)")) }
        guard let plaintext = try? JSONEncoder().encode(legacy) else {
            check(false, "seed a legacy queue", "encode failed")
            return
        }
        // Must run before anything touches the queue: the first access loads (and migrates) it.
        UserDefaults.standard.removeObject(forKey: "com.luxardolabs.LuxAnalytics.eventQueue.v2")
        UserDefaults.standard.set(plaintext, forKey: LuxAnalyticsQueue.legacyKey)
        check(await LuxAnalyticsQueue.shared.queueSize == 3, "legacy queue loaded")
        check(
            UserDefaults.standard.data(forKey: LuxAnalyticsQueue.legacyKey) == nil,
            "plaintext copy removed once the encrypted save succeeded")
    }

    private func migrated() async {
        let names = await LuxAnalyticsQueue.shared.dequeue(limit: 100, now: Date()).map(\.event.name)
        check(
            names == ["legacy-0", "legacy-1", "legacy-2"],
            "migrated queue survives a relaunch", "got \(names)")
    }

    private func first() async {
        let plain = Data("queue-encryption-roundtrip".utf8)
        let sealed = QueueEncryption.encrypt(plain)
        check(sealed != nil, "keychain-backed encryption", "encrypt returned nil (no Keychain key)")
        check(sealed.flatMap(QueueEncryption.decrypt) == plain, "decrypt round trip")

        let queue = LuxAnalyticsQueue.shared
        await queue.clear()
        for name in ["persisted-1", "persisted-2", "persisted-3"] {
            await queue.enqueue(event(name))
        }
        check(await queue.queueSize == 3, "queue holds 3 events before exit")

        let id = await AppAnalyticsContext.shared.resetDeviceID()
        emit("HOSTCHECK DEVICE_ID \(id)")

        await lifecycleFlush()
        await backgroundRequestSubmitted()
        // Leave the persisted events for the relaunch phase: the lifecycle check used its own.
    }

    private func relaunch() async {
        let queue = LuxAnalyticsQueue.shared
        // Enqueue FIRST: before 1.1.0, an enqueue that beat the async load overwrote the
        // saved queue. The three events from the first launch must still be there.
        await queue.enqueue(event("relaunch-1"))
        let names = await queue.dequeue(limit: 100, now: Date()).map(\.event.name)
        check(
            names == ["persisted-1", "persisted-2", "persisted-3", "relaunch-1"],
            "queue survives relaunch and loads before the first enqueue", "got \(names)")
        let id = await AppAnalyticsContext.shared.currentDeviceID()
        check(id == expectedDeviceID, "device ID kept across relaunch", "\(id) != \(expectedDeviceID)")
    }

    private func reinstall() async {
        let id = await AppAnalyticsContext.shared.currentDeviceID()
        check(id == expectedDeviceID, "device ID kept across reinstall (Keychain)", "\(id) != \(expectedDeviceID)")
        check(await LuxAnalyticsQueue.shared.queueSize == 0, "queue does not survive reinstall (UserDefaults)")
    }

    // MARK: - Lifecycle and background

    /// Entering the background must trigger a flush. The DSN points at 127.0.0.1:9 (nothing
    /// listens), so the flush shows up as an eventsFailed notification.
    private func lifecycleFlush() async {
        let queue = LuxAnalyticsQueue.shared
        let saved = await queue.dequeue(limit: 100, now: Date())
        do {
            let config = try LuxAnalyticsConfiguration(
                dsn: "https://host-check@127.0.0.1:9/api/v1/events/hostcheck",
                autoFlushInterval: 3_600, maxRetryAttempts: 0)
            try await LuxAnalytics.initialize(with: config)
            // The lifecycle observers are registered on the main actor shortly after initialize.
            try await Task.sleep(for: .milliseconds(300))
            let stream = LuxAnalyticsEvents.eventStream
            try await LuxAnalytics.shared.track("lifecycle")
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            let failedName = await firstFailure(in: stream)
            check(failedName == "lifecycle", "entering the background flushes", "no flush attempt seen")
        } catch {
            check(false, "entering the background flushes", "setup failed: \(error)")
        }
        for queued in saved {
            await queue.enqueue(queued)
        }
    }

    private func firstFailure(in stream: AsyncStream<AnalyticsEventNotification>) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                for await notification in stream {
                    if case .eventsFailed(let events, _) = notification { return events.first?.name }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let first = await group.next().flatMap { $0 }
            group.cancelAll()
            return first
        }
    }

    /// enableBackgroundProcessing() must leave a pending BGProcessingTask request. The
    /// simulator can't schedule background work (BGTaskSchedulerErrorCodeUnavailable: "The app
    /// is running on Simulator which doesn't support background processing", BGTaskScheduler.h),
    /// so there the check reports SKIP with that reason; it can't pass on a simulator.
    private func backgroundRequestSubmitted() async {
        let name = "background flush request submitted"
        let pending = await BGTaskScheduler.shared.pendingTaskRequests().map(\.identifier)
        if pending.contains("com.luxardolabs.LuxAnalytics.flush") {
            check(true, name)
            return
        }
        do {
            try BGTaskScheduler.shared.submit(
                BGProcessingTaskRequest(identifier: "com.luxardolabs.LuxAnalytics.flush"))
            check(false, name, "nothing pending, though a direct submit works: the SDK didn't submit")
        } catch let error as BGTaskScheduler.Error where error.code == .unavailable {
            skip(name, "BGTaskScheduler is unavailable here (simulator); verify on a device")
        } catch {
            check(false, name, "direct submit failed: \(error)")
        }
    }
}

/// The runner (scripts/host-check.sh) reads this app's stdout through `simctl launch
/// --console-pty`; os.Logger output doesn't reach stdout, so results must be printed.
func emit(_ line: String) {
    // stdout is the host-check protocol: the runner can't read the unified log
    // swiftlint:disable:next no_print_statements
    print(line)
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
