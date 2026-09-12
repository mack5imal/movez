import Foundation

/// Where scheduler effects go once the coordinator has done its own bookkeeping.
///
/// The UI layers register as sinks — the overlay controller, the panel controller, the menu bar
/// and the chime player — so the coordinator never reaches into AppKit itself.
@MainActor
protocol EffectSink: AnyObject {
    func apply(_ effect: SchedulerEffect, coordinator: AppCoordinator)
}

/// The sink used before any UI exists, and by the headless command-line modes.
final class NoopEffectSink: EffectSink {
    func apply(_ effect: SchedulerEffect, coordinator: AppCoordinator) {}
}

/// Fans one effect out to several sinks, in registration order.
final class CompositeEffectSink: EffectSink {
    private var sinks: [EffectSink]

    init(_ sinks: [EffectSink] = []) {
        self.sinks = sinks
    }

    func add(_ sink: EffectSink) {
        sinks.append(sink)
    }

    func apply(_ effect: SchedulerEffect, coordinator: AppCoordinator) {
        for sink in sinks { sink.apply(effect, coordinator: coordinator) }
    }
}

/// The sink the tests assert against.
final class RecordingEffectSink: EffectSink {
    private(set) var effects: [SchedulerEffect] = []

    func apply(_ effect: SchedulerEffect, coordinator: AppCoordinator) {
        effects.append(effect)
    }

    var names: [String] { effects.map(\.name) }

    /// The order the named effects arrived in, ignoring everything else — which is how the
    /// interesting assertions read, since persist and menuRefresh interleave everywhere.
    func order(of names: Set<String>) -> [String] {
        effects.map(\.name).filter(names.contains)
    }

    func clear() { effects.removeAll() }
}
