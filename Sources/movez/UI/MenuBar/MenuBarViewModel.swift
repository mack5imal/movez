import AppKit
import Combine
import Foundation

/// Turns the coordinator into the two things the menu bar needs: the glyph and its countdown, and
/// the dropdown behind them.
///
/// It reads the coordinator and never writes to it except through the intents, which is what
/// keeps the menu honest — every number it shows is the scheduler's, not its own.
@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published private(set) var state = MenuBarState()

    private let coordinator: AppCoordinator
    private var cancellables: Set<AnyCancellable> = []

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        // objectWillChange fires before the coordinator's own state settles, so the rebuild waits
        // for the next turn of the run loop.
        coordinator.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    var iconImage: NSImage { MenuBarIcon.image(for: state) }
    var labelText: String { state.labelText }

    var actions: MenuBarActions {
        MenuBarActions(
            takeBreakNow: { [weak self] in self?.takeBreakNow() },
            makeDue: { [weak self] minutes in self?.makeDue(minutes) },
            pause: { [weak self] option in self?.pause(option) },
            resume: { [weak self] in self?.resume() },
            extendPause: { [weak self] option in self?.extendPause(option) },
            startSession: { [weak self] in self?.startSession() },
            endSession: { [weak self] in self?.endSession() },
            togglePauseOptions: { [weak self] in self?.togglePauseOptions() },
            toggleExtendOptions: { [weak self] in self?.toggleExtendOptions() },
            openSettings: { [weak self] in self?.openSettings() },
            quit: { [weak self] in self?.quit() }
        )
    }

    // MARK: - Intents

    func takeBreakNow() {
        coordinator.takeBreakNow()
        collapseRows()
    }

    func makeDue(_ minutes: Int) {
        coordinator.makeDue(inSeconds: minutes * 60)
        refresh()
    }

    func pause(_ option: PauseOption) {
        coordinator.pause(forSeconds: option.seconds)
        collapseRows()
    }

    func resume() {
        coordinator.resume()
        collapseRows()
    }

    func extendPause(_ option: PauseOption) {
        coordinator.extendPause(bySeconds: option.seconds ?? 0)
        refresh()
    }

    func startSession() {
        coordinator.startSession()
        collapseRows()
    }

    func endSession() {
        coordinator.endSession()
        collapseRows()
    }

    func togglePauseOptions() {
        state.pauseExpanded.toggle()
        state.extendExpanded = false
    }

    func toggleExtendOptions() {
        state.extendExpanded.toggle()
        state.pauseExpanded = false
    }

    /// Phase 12 owns the settings window; this is the seam it plugs into.
    func openSettings() {
        NotificationCenter.default.post(name: .movezOpenSettings, object: nil)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func collapseRows() {
        state.pauseExpanded = false
        state.extendExpanded = false
        refresh()
    }

    // MARK: - Building the state

    func refresh() {
        let now = coordinator.clock.now
        var next = MenuBarState()
        next.pauseExpanded = state.pauseExpanded
        next.extendExpanded = state.extendExpanded
        next.mode = Self.mode(for: coordinator.menuState.mode)
        next.isAdHocSession = coordinator.scheduler.snapshot.adHocSession
        next.isBreaking = coordinator.scheduler.state.isBreakSurfaceVisible
        next.breakLabel = Self.breakLabel(for: coordinator.scheduler.state)

        switch next.mode {
        case .sitting: applySitting(to: &next, now: now)
        case .paused: applyPaused(to: &next, now: now)
        case .offHours: applyOffHours(to: &next, now: now)
        }
        state = next
    }

    private func applySitting(to next: inout MenuBarState, now: Date) {
        let sitSeconds = coordinator.settings.schedulerConfig.sitSeconds
        let remaining = coordinator.scheduler.snapshot.secondsUntilFullBreak(at: now) ?? 0
        next.minutesRemaining = Self.minutes(remaining)
        next.elapsedFraction = sitSeconds > 0 ? 1 - Double(remaining) / Double(sitSeconds) : 0
        next.title = MenuBarState.title(mode: .sitting, minutesRemaining: next.minutesRemaining)
        next.subtitle = coordinator.nextRoutinePreview?.subtitle ?? ""
        applyStats(to: &next, day: "Today", stats: coordinator.history.stats(on: now))
    }

    private func applyPaused(to next: inout MenuBarState, now: Date) {
        let until = coordinator.menuState.pausedUntil
        let pauseLeft = until.map { max(0, Int($0.timeIntervalSince(now))) } ?? 0
        let held = coordinator.scheduler.snapshot.remainingAtPauseSeconds
            ?? coordinator.settings.schedulerConfig.sitSeconds
        next.minutesRemaining = Self.minutes(pauseLeft)
        next.title = MenuBarState.title(
            mode: .paused,
            minutesRemaining: next.minutesRemaining,
            indefinite: until == nil
        )
        next.subtitle = MenuBarState.pausedSubtitle(resumesAt: until, remainingMinutes: Self.minutes(held))
        applyStats(to: &next, day: "Today", stats: coordinator.history.stats(on: now))
    }

    /// Off hours the numbers on show are the last working day's, not an empty today.
    private func applyOffHours(to next: inout MenuBarState, now: Date) {
        let config = coordinator.settings.schedulerConfig
        next.title = MenuBarState.title(mode: .offHours, minutesRemaining: 0)
        next.subtitle = MenuBarState.offHoursSubtitle(
            nextStart: coordinator.scheduler.nextWorkingStart(after: now),
            now: now,
            calendar: config.calendar
        )
        let last = coordinator.history.lastRecordedDay()
        let day = last.map { MenuBarState.dayPhrase($0.date, now: now, calendar: config.calendar).capitalized } ?? "Today"
        applyStats(to: &next, day: day, stats: last?.stats ?? coordinator.history.stats(on: now))
    }

    private func applyStats(to next: inout MenuBarState, day: String, stats: DailyStats) {
        next.stats = MenuBarState.statsLine(day: day, stats: stats)
        next.longestBout = MenuBarState.longestBoutLine(seconds: stats.longestBoutSeconds)
    }

    /// A break on screen is still the sitting menu — there is nothing else the user would want
    /// from the menu bar while one is running.
    static func mode(for menuMode: MenuMode) -> MenuBarState.Mode {
        switch menuMode {
        case .paused: return .paused
        case .offHours: return .offHours
        case .sitting, .breaking: return .sitting
        }
    }

    static func breakLabel(for state: SchedulerState) -> String {
        switch state {
        case .microCountIn, .microRunning: return "micro"
        case .headsUp, .fullBreak: return "break"
        default: return ""
        }
    }

    /// Minutes, rounded up, so a countdown never shows "0 min" while it is still running.
    static func minutes(_ seconds: Int) -> Int {
        Int((Double(max(0, seconds)) / 60).rounded(.up))
    }
}

extension Notification.Name {
    /// Posted by the menu's "Settings…" row. The settings window listens for it.
    static let movezOpenSettings = Notification.Name("movez.openSettings")
}
