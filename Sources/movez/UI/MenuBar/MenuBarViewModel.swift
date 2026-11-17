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
    /// Told when a mode request needs a setup shown instead of switching.
    private let onModeAction: (ModeSwitchAction) -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(
        coordinator: AppCoordinator,
        onModeAction: @escaping (ModeSwitchAction) -> Void = MenuBarViewModel.openSetup
    ) {
        self.coordinator = coordinator
        self.onModeAction = onModeAction
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

    /// The dropdown's actions. `closeMenu` dismisses the dropdown; it is handed in by the view
    /// that hosts it, because only SwiftUI knows how to close a `MenuBarExtra` window.
    func actions(closingWith closeMenu: @escaping () -> Void = {}) -> MenuBarActions {
        MenuBarActions(
            takeBreakNow: { [weak self] in self?.takeBreakNow() },
            makeDue: { [weak self] minutes in self?.makeDue(minutes) },
            pause: { [weak self] option in self?.pause(option) },
            resume: { [weak self] in self?.resume() },
            extendPause: { [weak self] option in self?.extendPause(option) },
            startSession: { [weak self] in self?.startSession() },
            endSession: { [weak self] in self?.endSession() },
            selectMode: { [weak self] id in self?.selectMode(id, closeMenu: closeMenu) },
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

    /// The mode row's click, through the same switch Settings uses.
    ///
    /// A mode that is ready switches at once, from the next break. One that still needs its setup
    /// (Strength, the first time) leaves the mode where it was, closes the dropdown and asks for
    /// Settings to open at the setup: the setup is a sheet in the settings window, and a dropdown
    /// left open over it would sit on top of the question being asked.
    func selectMode(_ id: String, closeMenu: () -> Void) {
        guard let mode = BreakMode(rawValue: id), mode != coordinator.settings.mode else { return }
        if let action = ModeSwitch.request(mode, in: coordinator.settings) {
            closeMenu()
            onModeAction(action)
        } else {
            coordinator.settingsChanged()
            refresh()
        }
    }

    /// Asks the settings window to open at a mode's setup. The window opens on the notification
    /// the "Settings…" row posts; the mode rides along so the window can show its setup sheet.
    nonisolated static func openSetup(_ action: ModeSwitchAction) {
        switch action {
        case let .openSetup(mode):
            NotificationCenter.default.post(
                name: .movezOpenSettings,
                object: nil,
                userInfo: [Notification.Name.modeSetupKey: mode.rawValue]
            )
        }
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
        next.breakMode = coordinator.menuState.breakMode
        next.isAdHocSession = coordinator.scheduler.snapshot.adHocSession
        next.isBreaking = coordinator.scheduler.state.isBreakSurfaceVisible
        next.breakLabel = Self.breakLabel(for: coordinator.scheduler.state)

        switch next.mode {
        case .sitting: applySitting(to: &next, now: now)
        case .paused: applyPaused(to: &next, now: now)
        case .offHours: applyOffHours(to: &next, now: now)
        case .away: applyAway(to: &next, now: now)
        }
        // The coordinator publishes every two seconds; the menu bar only changes once a minute.
        // Assigning an identical state would redraw the menu-bar item for nothing.
        guard next != state else { return }
        state = next
    }

    private func applySitting(to next: inout MenuBarState, now: Date) {
        let sitSeconds = coordinator.settings.schedulerConfig.sitSeconds
        let remaining = coordinator.scheduler.snapshot.secondsUntilFullBreak(at: now) ?? 0
        next.minutesRemaining = Self.minutes(remaining)
        next.elapsedFraction = sitSeconds > 0 ? 1 - Double(remaining) / Double(sitSeconds) : 0
        next.title = MenuBarState.title(mode: .sitting, minutesRemaining: next.minutesRemaining)
        // Movement routines have no names to preview, and the title already says when the break
        // is. A mode that plans its day names where in the day the next break falls.
        next.subtitle = coordinator.menuState.dayProgress?.menuSubtitle ?? ""
        applyStats(to: &next, day: "Today", stats: coordinator.history.stats(on: now))
    }

    /// Away, the countdown on show would be counting down an interval nobody is sitting through,
    /// and it reached zero and stayed there while the user was gone. The absence is the number
    /// worth showing instead.
    private func applyAway(to next: inout MenuBarState, now: Date) {
        let away = coordinator.menuState.awaySeconds ?? 0
        next.minutesRemaining = Self.minutes(away)
        next.elapsedFraction = 0
        next.title = MenuBarState.awayTitle(seconds: away)
        if let progress = coordinator.menuState.dayProgress {
            // What the pause setting is holding: the countdown as it stood when the user went.
            let held = coordinator.scheduler.snapshot.remainingAtAwaySeconds
                ?? coordinator.scheduler.snapshot.secondsUntilFullBreak(at: now)
                ?? coordinator.scheduler.config.sitSeconds
            next.subtitle = progress.awaySubtitle(
                behaviour: coordinator.scheduler.config.awayBehaviour,
                minutesLeft: Self.minutes(held)
            )
        } else {
            next.subtitle = MenuBarState.awaySubtitle
        }
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
        case .away: return .away
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

    /// The `userInfo` key, on `movezOpenSettings`, naming the mode whose setup to show.
    static let modeSetupKey = "modeSetup"
}
