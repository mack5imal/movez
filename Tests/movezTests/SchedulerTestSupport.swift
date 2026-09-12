import Foundation
@testable import movez

/// Drives a `Scheduler` the way the coordinator will: a manual clock, a 2 s tick, and a
/// recording of every effect so tests can assert on the order they arrive in.
final class SchedulerHarness {
    static let tickSeconds: TimeInterval = 2

    let clock = ManualClock()
    var scheduler: Scheduler
    private(set) var effects: [SchedulerEffect] = []

    init(config: SchedulerConfig = SchedulerConfig()) {
        scheduler = Scheduler(config: config, now: clock.now)
    }

    var state: SchedulerState { scheduler.state }
    var snapshot: SchedulerSnapshot { scheduler.snapshot }
    var start: Date { scheduler.snapshot.boutStartedAt }
    var now: Date { clock.now }

    @discardableResult
    func send(_ event: SchedulerEvent) -> [SchedulerEffect] {
        let produced = scheduler.handle(event, now: clock.now)
        effects += produced
        return produced
    }

    /// Advances in 2 s ticks, optionally reporting continuous typing to each tick.
    func run(seconds: TimeInterval, inputAge: Int? = nil) {
        var elapsed: TimeInterval = 0
        while elapsed < seconds {
            clock.advance(Self.tickSeconds)
            elapsed += Self.tickSeconds
            if let inputAge { send(.input(lastEventAgeSeconds: inputAge)) }
            send(.tick)
        }
    }

    /// Advances until `predicate` holds or the budget runs out.
    @discardableResult
    func run(until predicate: (SchedulerState) -> Bool, limit: TimeInterval = 4 * 3600) -> Bool {
        var elapsed: TimeInterval = 0
        while elapsed < limit {
            if predicate(scheduler.state) { return true }
            clock.advance(Self.tickSeconds)
            elapsed += Self.tickSeconds
            send(.tick)
        }
        return predicate(scheduler.state)
    }

    func clearEffects() { effects.removeAll() }

    func contains(_ effect: SchedulerEffect) -> Bool { effects.contains(effect) }

    var effectNames: [String] { effects.map(\.name) }
}

extension SchedulerState {
    var isHeadsUp: Bool { if case .headsUp = self { return true } else { return false } }
    var isFullBreak: Bool { if case .fullBreak = self { return true } else { return false } }
    var isPendingFull: Bool { if case .pendingFull = self { return true } else { return false } }
    var isSnoozed: Bool { if case .snoozed = self { return true } else { return false } }
    var isMicroCountIn: Bool { if case .microCountIn = self { return true } else { return false } }
    var isMicroRunning: Bool { if case .microRunning = self { return true } else { return false } }
    var isSitting: Bool { self == .sitting }
}
