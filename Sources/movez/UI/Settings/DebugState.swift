import Foundation

/// One line of the state inspector.
struct InspectorRow: Equatable, Identifiable {
    var label: String
    var value: String

    var id: String { label }

    /// "state            sitting" — padded so the values line up in a monospaced block.
    func rendered(labelWidth: Int) -> String {
        let padding = String(repeating: " ", count: max(1, labelWidth - label.count))
        return "\(label)\(padding)\(value)"
    }
}

/// Everything the debug section draws, as plain values.
struct DebugState: Equatable {
    /// The three speeds the debug section offers.
    static let timeScales: [Double] = [1, 10, 60]
    static let timeScaleOptions: [(value: Double, label: String)] = timeScales.map { ($0, "\(Int($0))×") }

    var timeScale: Double = 1
    var rows: [InspectorRow] = []
    /// Newest first, already formatted, capped at the log's twenty.
    var transitions: [String] = []

    /// The width the labels are padded to, so every value starts in the same column.
    var labelWidth: Int { (rows.map(\.label.count).max() ?? 0) + 2 }

    /// The whole inspector as one block of text — what the view draws and the tests read.
    var inspectorText: String {
        let width = labelWidth
        let fields = rows.map { $0.rendered(labelWidth: width) }.joined(separator: "\n")
        guard !transitions.isEmpty else { return fields }
        return "\(fields)\n\n\(DebugState.transitionsHeading)\n\(transitions.joined(separator: "\n"))"
    }

    static let transitionsHeading = "transitions (newest first)"

    /// The signal injectors, in the order the section lays them out.
    static var signalInjectors: [SignalInjector] {
        SignalInjector.allCases.filter { !$0.isSchedulerAction }
    }

    static var schedulerActions: [SignalInjector] {
        SignalInjector.allCases.filter(\.isSchedulerAction)
    }
}

/// What the debug section can ask the app to do.
struct DebugActions {
    var setTimeScale: (Double) -> Void = { _ in }
    var fire: (SignalInjector) -> Void = { _ in }
}
