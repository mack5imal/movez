import Foundation
import XCTest
@testable import movez

/// Shared fixtures and the simulated-day driver used by the routine tests.
enum RoutineTestSupport {
    static let library: MovementLibrary = {
        do {
            return try LibraryLoader.loadBundled()
        } catch {
            fatalError("Bundled movement library failed to load: \(error)")
        }
    }()

    static let builder = RoutineBuilder(library: library)
    static let microBuilder = MicroBreakBuilder(library: library)

    struct DayOptions {
        var breaks = 8
        var focus: Focus = .none
        var equipment: Set<Equipment> = []
        var unavailable: Set<Requirement> = []
        var excluded: Set<String> = []
        var difficultyCap = 2
        var unlockedDiff3: Set<String> = []
        /// How recently each movement was served, as the coordinator reads it out of history.
        var recency: [String: Double] = [:]
    }

    /// Runs a day of breaks the way the coordinator will, threading the day's history forward.
    static func simulateDay(seed: UInt64, options: DayOptions = DayOptions()) -> [Routine] {
        var used: Set<String> = []
        var lastStrengthRegions: Set<Region> = []
        var routines: [Routine] = []

        for index in 0..<options.breaks {
            var context = RoutineContext()
            context.usedMovementIdsToday = used
            context.usedStrRegionsLastBreak = lastStrengthRegions
            context.equipment = options.equipment
            context.unavailable = options.unavailable
            context.excluded = options.excluded
            context.focus = options.focus
            context.difficultyCap = options.difficultyCap
            context.unlockedDiff3 = options.unlockedDiff3
            context.recency = options.recency
            context.seed = seed &+ UInt64(index &* 7919)

            let routine = builder.build(context: context)
            routines.append(routine)

            used.formUnion(routine.movementIds)
            lastStrengthRegions = routine.strengthRegions
        }
        return routines
    }

    /// A single routine with everything else left at its default.
    static func routine(
        seed: UInt64,
        configure: (inout RoutineContext) -> Void = { _ in }
    ) -> Routine {
        var context = RoutineContext()
        context.seed = seed
        configure(&context)
        return builder.build(context: context)
    }

    /// The repository's `build/` directory, so tests can drop transcript evidence next to the logs.
    static func evidenceURL(_ name: String) -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = root.appendingPathComponent("build", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }

    static func write(_ text: String, to name: String) {
        try? text.write(to: evidenceURL(name), atomically: true, encoding: .utf8)
    }

    static func describe(_ routine: Routine) -> String {
        var lines = ["\(routine.buckets.map(\.rawValue).joined(separator: " → "))  [\(routine.totalSeconds) s total]"]
        for block in routine.blocks {
            lines.append("    \(block.movement.id.padded(to: 8))\(block.movement.name.padded(to: 42))\(block.seconds) s")
        }
        return lines.joined(separator: "\n")
    }
}

extension String {
    func padded(to width: Int) -> String {
        count >= width ? self + " " : self + String(repeating: " ", count: width - count)
    }
}
