import AppKit
import Foundation

/// Sleep, wake, lock and unlock, delivered as scheduler events.
///
/// The gap each wake reports is measured from the last time anything ticked, because the
/// notification itself carries no duration and the whole idle table hangs off how long the
/// machine was actually gone.
@MainActor
final class PowerMonitor {
    private var observers: [NSObjectProtocol] = []
    private let onEvent: (SchedulerEvent) -> Void
    private let lastActivity: () -> Date
    private let now: () -> Date

    init(
        now: @escaping () -> Date = { Date() },
        lastActivity: @escaping () -> Date,
        onEvent: @escaping (SchedulerEvent) -> Void
    ) {
        self.now = now
        self.lastActivity = lastActivity
        self.onEvent = onEvent
    }

    func start() {
        stop()
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.onEvent(.sleep) }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.onEvent(.sleep) }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.onEvent(.lock) }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.emitWake() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.emitWake() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.emitUnlock() }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.onEvent(.lock) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.emitUnlock() }
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for observer in observers {
            workspace.removeObserver(observer)
            distributed.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated(action)
        })
    }

    private func observe(
        _ center: DistributedNotificationCenter,
        _ name: Notification.Name,
        action: @escaping () -> Void
    ) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated(action)
        })
    }

    private func gapSeconds() -> Int {
        max(0, Int(now().timeIntervalSince(lastActivity())))
    }

    private func emitWake() {
        onEvent(.wake(gapSeconds: gapSeconds()))
    }

    private func emitUnlock() {
        onEvent(.unlock(gapSeconds: gapSeconds()))
    }
}
