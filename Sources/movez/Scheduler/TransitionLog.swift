import Foundation

/// One recorded state change.
struct Transition: Codable, Equatable, Identifiable {
    let at: Date
    let from: SchedulerState
    let to: SchedulerState
    let reason: String

    var id: String { "\(at.timeIntervalSince1970)-\(from.name)-\(to.name)" }

    /// "09:55:00  sitting → pending_full  (full break due)"
    func line(formatter: DateFormatter) -> String {
        "\(formatter.string(from: at))  \(from.name) → \(to.name)  (\(reason))"
    }
}

/// The last twenty transitions, newest last. Sleep and idle bugs take a day to reproduce; this
/// ring buffer is what makes them readable after the fact.
struct TransitionLog: Codable, Equatable {
    static let capacity = 20

    private(set) var transitions: [Transition] = []

    mutating func append(_ transition: Transition) {
        transitions.append(transition)
        if transitions.count > Self.capacity {
            transitions.removeFirst(transitions.count - Self.capacity)
        }
    }

    var newestFirst: [Transition] { transitions.reversed() }
    var count: Int { transitions.count }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()

    func rendered() -> String {
        transitions.map { $0.line(formatter: Self.timeFormatter) }.joined(separator: "\n")
    }
}
