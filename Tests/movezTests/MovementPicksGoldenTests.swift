import Foundation
import XCTest
@testable import movez

/// Pins Movement mode's picks: a fixed list of full-break and micro-break contexts, and the ids
/// the builders served for each of them on the day this fixture was recorded.
///
/// The fixture is a safety net for the strength-mode work, which must leave Movement mode exactly
/// as it was. It is recorded once and never again. Nothing in the repo stops a re-recording: the
/// guard is that `Fixtures/movement-picks-golden.json` shows up in the diff, so a change that
/// makes this test fail has changed Movement mode, and the fix belongs in that change, not in a
/// re-recorded fixture.
///
/// Every context is derived from the bundled library (sorted ids, families, difficulty) rather
/// than from hard-coded movement ids, and built the way `AppCoordinator.routineContext(at:breakIndex:)`
/// and `beginMicro()` build theirs, so the fixture reflects what the app actually serves.
///
/// Recording: `xcodebuild` hands the test process any variable prefixed with `TEST_RUNNER_`, so
/// `TEST_RUNNER_MOVEZ_RECORD_GOLDEN=1 xcodebuild … test -only-testing:movezTests/MovementPicksGoldenTests`
/// writes the fixture instead of checking it, and then fails, so a recording run can never pass for
/// a checking one.
final class MovementPicksGoldenTests: XCTestCase {
    struct Entry: Codable, Equatable {
        var label: String
        var ids: [String]
    }

    struct Golden: Codable, Equatable {
        var full: [Entry]
        var micro: [Entry]
    }

    /// Found next to this file, so the fixture needs no bundle resource.
    static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
        .appendingPathComponent("movement-picks-golden.json")

    private var isRecording: Bool {
        ProcessInfo.processInfo.environment["MOVEZ_RECORD_GOLDEN"] == "1"
    }

    func testMovementModePicksMatchTheRecordedFixture() throws {
        let current = GoldenContexts(library: RoutineTestSupport.library).golden()
        XCTAssertGreaterThanOrEqual(current.full.count, 300)
        XCTAssertGreaterThanOrEqual(current.micro.count, 300)

        if isRecording {
            try FileManager.default.createDirectory(
                at: Self.fixtureURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(current).write(to: Self.fixtureURL, options: .atomic)
            return XCTFail("fixture recorded; run again without TEST_RUNNER_MOVEZ_RECORD_GOLDEN to check it")
        }

        let data = try Data(contentsOf: Self.fixtureURL)
        let recorded = try JSONDecoder().decode(Golden.self, from: data)
        compare(recorded.full, current.full, kind: "full")
        compare(recorded.micro, current.micro, kind: "micro")
    }

    /// The contexts that are expected to reach a fallback really do: otherwise the fixture would
    /// not be pinning the fallback at all.
    func testTheFallbackContextsLeaveASlotWithNothingEligible() {
        let contexts = GoldenContexts(library: RoutineTestSupport.library)
        let builder = RoutineTestSupport.builder
        let fallback = contexts.fullContexts().filter { $0.label.hasPrefix("used-all-but-cir") }
        XCTAssertFalse(fallback.isEmpty)
        for (_, context) in fallback {
            let pool = builder.candidates(for: context)
            XCTAssertTrue(pool.allSatisfy { $0.bucket == .cir }, "only circulation should be left before the fallback")
        }
    }

    private func compare(_ recorded: [Entry], _ current: [Entry], kind: String) {
        XCTAssertEqual(recorded.count, current.count, "\(kind): the number of contexts changed")
        for (index, pair) in zip(recorded, current).enumerated() {
            XCTAssertEqual(pair.0.label, pair.1.label, "\(kind)[\(index)]: the context list changed")
            XCTAssertEqual(pair.0.ids, pair.1.ids, "\(kind)[\(index)] \(pair.0.label): Movement mode served different movements")
        }
    }
}

/// The fixed list of contexts. Each configuration is replayed across the same seeds, so a change
/// to one rule shows up across many draws rather than in a single lucky one.
struct GoldenContexts {
    static let fullSeedCount = 20
    static let microSeedCount = 24
    static let day = "2026-09-07"

    let library: MovementLibrary
    let sortedIds: [String]

    init(library: MovementLibrary) {
        self.library = library
        self.sortedIds = library.movements.map(\.id).sorted()
    }

    func golden() -> MovementPicksGoldenTests.Golden {
        let builder = RoutineTestSupport.builder
        let microBuilder = RoutineTestSupport.microBuilder
        return MovementPicksGoldenTests.Golden(
            full: fullContexts().map { .init(label: $0.label, ids: builder.build(context: $0.context).movementIds) },
            micro: microContexts().map { .init(label: $0.label, ids: microBuilder.build(context: $0.context).movementIds) }
        )
    }

    // MARK: - Derived from the library

    private var diff3Ids: Set<String> { Set(library.movements.filter { $0.difficulty >= 3 }.map(\.id)) }

    /// Every fifth movement, a spread across every bucket.
    private var everyFifth: Set<String> { Set(sortedIds.enumerated().filter { $0.offset % 5 == 0 }.map(\.element)) }

    /// One member of each of the first few families, so its siblings are ruled out for the day.
    private var familyMembers: Set<String> {
        let grouped = Dictionary(grouping: library.movements.filter { $0.family != nil }, by: { $0.familyKey })
        let keys = grouped.keys.sorted().prefix(4)
        return Set(keys.compactMap { grouped[$0]?.map(\.id).min() })
    }

    /// Everything but circulation: the working blocks and the closer have no family left today,
    /// so each has to take a repeat.
    private var allButCirculation: Set<String> { Set(library.movements.filter { $0.bucket != .cir }.map(\.id)) }

    private var allIds: Set<String> { Set(sortedIds) }

    /// A spread of recency scores over the first forty ids, so the weighting has something to do.
    private var recencyMap: [String: Double] {
        var map: [String: Double] = [:]
        for (offset, id) in sortedIds.prefix(40).enumerated() {
            map[id] = Double(offset % 7 + 1) * 0.5
        }
        return map
    }

    // MARK: - Full breaks

    func fullContexts() -> [(label: String, context: RoutineContext)] {
        var configs: [(String, (inout RoutineContext) -> Void)] = [("base", { _ in })]
        for item in Equipment.allCases {
            configs.append(("equipment-\(item.rawValue)", { $0.equipment = [item] }))
        }
        configs.append(("equipment-all", { $0.equipment = Set(Equipment.allCases) }))
        for requirement in Requirement.allCases {
            configs.append(("unavailable-\(requirement.rawValue)", { $0.unavailable = [requirement] }))
        }
        configs.append(("unavailable-all", { $0.unavailable = Set(Requirement.allCases) }))
        for focus in Focus.allCases where focus != .none {
            configs.append(("focus-\(focus.rawValue)", { $0.focus = focus }))
        }
        let diff3 = diff3Ids
        configs.append(contentsOf: [
            ("cap-1", { $0.difficultyCap = 1 }),
            ("cap-3-locked", { $0.difficultyCap = 3 }),
            ("cap-3-unlocked", {
                $0.difficultyCap = 3
                $0.unlockedDiff3 = diff3
            })
        ])
        let fifth = everyFifth, members = familyMembers, allButCir = allButCirculation, all = allIds, recency = recencyMap
        configs.append(contentsOf: [
            ("excluded-every-fifth", { $0.excluded = fifth }),
            ("used-family-member", { $0.usedMovementIdsToday = members }),
            ("used-all-but-cir", { $0.usedMovementIdsToday = allButCir }),
            ("used-all", { $0.usedMovementIdsToday = all }),
            ("used-all-excluded-all", {
                $0.usedMovementIdsToday = all
                $0.excluded = all
            }),
            ("recency", { $0.recency = recency }),
            ("last-strength-regions", { $0.usedStrRegionsLastBreak = [.glute, .hip, .quad] }),
            ("mixed", {
                $0.focus = .moreHips
                $0.difficultyCap = 3
                $0.unlockedDiff3 = diff3
                $0.equipment = [.band]
                $0.unavailable = [.floor]
                $0.excluded = fifth
                $0.usedMovementIdsToday = members
                $0.recency = recency
            })
        ])

        var result: [(label: String, context: RoutineContext)] = []
        for (name, configure) in configs {
            for index in 0..<Self.fullSeedCount {
                var context = RoutineContext()
                context.date = Date(timeIntervalSince1970: 1_788_771_600)
                context.seed = SplitMix64.seed(day: Self.day, index: index)
                configure(&context)
                result.append(("\(name)#\(index)", context))
            }
        }
        return result
    }

    // MARK: - Micro-breaks

    func microContexts() -> [(label: String, context: MicroContext)] {
        var configs: [(String, (inout MicroContext) -> Void)] = [("base", { _ in })]
        for requirement in Requirement.allCases {
            configs.append(("unavailable-\(requirement.rawValue)", { $0.unavailable = [requirement] }))
        }
        configs.append(("unavailable-all", { $0.unavailable = Set(Requirement.allCases) }))
        configs.append(("equipment-all", { $0.equipment = Set(Equipment.allCases) }))
        let fifth = everyFifth, members = familyMembers, all = allIds, recency = recencyMap
        let micro = library.microEligible.map(\.id).sorted()
        let almostAll = Set(micro.dropLast(2))
        let lastMicro = Set(micro.prefix(2))
        let nextFull = Set(micro.dropFirst(2).prefix(5))
        configs.append(contentsOf: [
            ("excluded-every-fifth", { $0.excluded = fifth }),
            ("used-family-member", { $0.usedMovementIdsToday = members }),
            ("used-almost-all", { $0.usedMovementIdsToday = almostAll }),
            ("used-all", { $0.usedMovementIdsToday = all }),
            ("last-micro", { $0.lastMicroMovementIds = lastMicro }),
            ("next-full", { $0.nextFullRoutineIds = nextFull }),
            ("recency", { $0.recency = recency }),
            ("mixed", {
                $0.unavailable = [.wall]
                $0.excluded = fifth
                $0.usedMovementIdsToday = members
                $0.lastMicroMovementIds = lastMicro
                $0.nextFullRoutineIds = nextFull
                $0.recency = recency
            })
        ])

        var result: [(label: String, context: MicroContext)] = []
        for (name, configure) in configs {
            for index in 0..<Self.microSeedCount {
                var context = MicroContext()
                context.seed = SplitMix64.seed(day: Self.day, index: 1_000 + index)
                configure(&context)
                result.append(("\(name)#\(index)", context))
            }
        }
        return result
    }
}
