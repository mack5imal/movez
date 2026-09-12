import Combine
import Foundation

/// The debug tools: a clock that runs fast, signals that can be held on by hand, and a window
/// into the scheduler.
///
/// A sleep-or-idle bug in this category of app takes a working day to reproduce. At 60× it takes
/// a minute, and the inspector says what actually happened rather than what should have.
@MainActor
final class DebugViewModel: ObservableObject {
    @Published private(set) var state = DebugState()

    private let coordinator: AppCoordinator
    private var cancellables: Set<AnyCancellable> = []

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        coordinator.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    var actions: DebugActions {
        DebugActions(
            setTimeScale: { [weak self] scale in self?.setTimeScale(scale) },
            fire: { [weak self] injector in self?.fire(injector) }
        )
    }

    // MARK: - Time scale

    func setTimeScale(_ scale: Double) {
        coordinator.settings.debugTimeScale = scale
        // settingsChanged re-anchors the clock and re-plans, which is what makes the faster clock
        // take effect without the bout jumping.
        coordinator.settingsChanged()
        refresh()
    }

    // MARK: - Injectors

    func fire(_ injector: SignalInjector) {
        injector.hold?.apply(to: coordinator.signalOverrides)

        if injector == .fireMicro {
            fireMicroBreak()
        } else if let event = injector.event(now: coordinator.clock.now) {
            coordinator.inject(event)
        }
        refresh()
    }

    /// The micro-break has no event of its own: it is due when the clock says so, so the debug
    /// button moves the clock's opinion rather than inventing a new path into the state machine.
    private func fireMicroBreak() {
        coordinator.scheduler.snapshot.nextMicroDueAt = coordinator.clock.now
        coordinator.tick()
    }

    // MARK: - The inspector

    func refresh() {
        var next = DebugState()
        next.timeScale = coordinator.settings.debugTimeScale
        next.rows = Self.rows(InspectorInput(
            snapshot: coordinator.scheduler.snapshot,
            now: coordinator.clock.now,
            snoozesLeft: coordinator.scheduler.snoozesLeft,
            polling: coordinator.scheduler.pollingRequired,
            pollCount: coordinator.aggregator?.pollCount,
            overrides: coordinator.signalOverrides.summary
        ))
        next.transitions = coordinator.scheduler.snapshot.transitions.newestFirst
            .map { $0.line(formatter: TransitionLog.timeFormatter) }
        state = next
    }

    /// The field labels, kept here so the view and the tests read the same list.
    enum Field {
        static let state = "state"
        static let boutStartedAt = "bout started"
        static let lastCompletedBreakAt = "last break"
        static let nextFullDueAt = "next full"
        static let nextMicroDueAt = "next micro"
        static let pauseUntil = "pause until"
        static let snoozesLeft = "snoozes left"
        static let skipsToday = "skips today"
        static let doneToday = "done today"
        static let snoozedToday = "snoozed today"
        static let postLunchPending = "post-lunch"
        static let polling = "polling"
        static let adHocSession = "ad-hoc session"
        static let overrides = "overrides"

        static let all = [
            state, boutStartedAt, lastCompletedBreakAt, nextFullDueAt, nextMicroDueAt, pauseUntil,
            snoozesLeft, skipsToday, doneToday, snoozedToday, postLunchPending, polling,
            adHocSession, overrides
        ]
    }

    /// Everything the inspector reports, gathered in one value so the rendering is a pure
    /// function of it — which is what lets a fixture draw a populated inspector.
    struct InspectorInput {
        var snapshot: SchedulerSnapshot
        var now: Date
        var snoozesLeft: Int
        var polling: Bool
        var pollCount: Int?
        var overrides: String
    }

    static func rows(_ input: InspectorInput) -> [InspectorRow] {
        let snapshot = input.snapshot
        return [
            InspectorRow(label: Field.state, value: snapshot.state.name),
            InspectorRow(label: Field.boutStartedAt, value: time(snapshot.boutStartedAt)),
            InspectorRow(label: Field.lastCompletedBreakAt, value: time(snapshot.lastCompletedBreakAt)),
            InspectorRow(label: Field.nextFullDueAt, value: countdown(snapshot.nextFullDueAt, from: input.now)),
            InspectorRow(label: Field.nextMicroDueAt, value: countdown(snapshot.nextMicroDueAt, from: input.now)),
            InspectorRow(label: Field.pauseUntil, value: time(pauseUntil(snapshot.state))),
            InspectorRow(label: Field.snoozesLeft, value: "\(input.snoozesLeft)"),
            InspectorRow(label: Field.skipsToday, value: "\(snapshot.skipsToday)"),
            InspectorRow(label: Field.doneToday, value: "\(snapshot.doneToday)"),
            InspectorRow(label: Field.snoozedToday, value: "\(snapshot.snoozedToday)"),
            InspectorRow(label: Field.postLunchPending, value: yesNo(snapshot.postLunchPending)),
            InspectorRow(label: Field.polling, value: pollingValue(input.polling, pollCount: input.pollCount)),
            InspectorRow(label: Field.adHocSession, value: yesNo(snapshot.adHocSession)),
            InspectorRow(label: Field.overrides, value: input.overrides)
        ]
    }

    private static func pauseUntil(_ state: SchedulerState) -> Date? {
        guard case .paused(let until) = state else { return nil }
        return until
    }

    private static func pollingValue(_ polling: Bool, pollCount: Int?) -> String {
        let onOff = polling ? "on" : "off"
        guard let pollCount else { return onOff }
        return "\(onOff) · \(pollCount) polls"
    }

    private static func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

    private static func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return TransitionLog.timeFormatter.string(from: date)
    }

    /// "09:55:00 (in 32 min)" — the absolute time, and the thing anyone actually wants from it.
    private static func countdown(_ date: Date?, from now: Date) -> String {
        guard let date else { return "—" }
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded())
        let relative = minutes >= 0 ? "in \(minutes) min" : "\(-minutes) min ago"
        return "\(TransitionLog.timeFormatter.string(from: date)) (\(relative))"
    }
}
