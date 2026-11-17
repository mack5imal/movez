import XCTest
@testable import movez

/// S24: a third mode is a new definition, not new branches through the code that serves two.
@MainActor
final class ModeExtensibilityTests: XCTestCase {
    /// A mode that exists only in the test target, with its own badge and library.
    private static let hundreds = ModeDefinition(
        id: "hundreds",
        displayName: "100s",
        eyebrowWord: "100s",
        badgeGlyph: "mode.hundreds",
        menuBarGlyph: "mode.hundreds",
        libraryKind: ModeLibraryKind(resourceName: "bodyweight-fixture"),
        settingsGroup: ModeSettingsGroup(id: "hundreds", title: "100S"),
        isSetUp: nil
    )

    func testEveryRealModeHasADefinitionInTheStandardTable() {
        XCTAssertEqual(ModeDefinitionTable.standard.ids, BreakMode.allCases.map(\.rawValue))
        for mode in BreakMode.allCases {
            XCTAssertEqual(mode.definition.id, mode.rawValue)
        }
        XCTAssertEqual(BreakMode.movement.definition.breakEyebrow, "MOVEMENT BREAK")
        XCTAssertEqual(BreakMode.strength.definition.microBreakEyebrow, "STRENGTH MICRO-BREAK")
        XCTAssertNil(BreakMode.movement.definition.isSetUp)
        XCTAssertNotNil(BreakMode.strength.definition.isSetUp)
    }

    func testAThirdDefinitionIsLookedUpAndListedWithoutProductionChanges() {
        let table = ModeDefinitionTable(definitions: ModeDefinitionTable.standard.definitions + [Self.hundreds])

        XCTAssertEqual(table.definition(for: "hundreds"), Self.hundreds)
        XCTAssertEqual(table.ids, ["movement", "strength", "hundreds"])
        XCTAssertEqual(table.definitions.map(\.displayName), ["Movement", "Strength", "100s"])
        XCTAssertEqual(table.definition(for: "hundreds")?.breakEyebrow, "100s BREAK")
        XCTAssertEqual(table.definition(for: "movement"), .movement)
        XCTAssertNil(ModeDefinitionTable.standard.definition(for: "hundreds"))
    }

    /// The test-only mode's builder: a hundred seconds on each movement of a fixture library of
    /// its own. It is nothing the app ships, which is the point: it reaches the coordinator through
    /// the builder table alone.
    private struct HundredsBuilder: ModeBreakBuilding {
        let fixture: [Movement]

        func previewKeyParts(for coordinator: AppCoordinator, at now: Date) -> [String] { ["hundreds"] }

        func fullBreak(for coordinator: AppCoordinator, at now: Date) -> PlannedBreak {
            let seed = SplitMix64.seed(day: coordinator.scheduler.snapshot.dayKey, index: coordinator.breakIndexToday(at: now))
            let blocks = fixture.map { RoutineBlock(movement: $0, seconds: 100) }
            return .movement(Routine(id: UUID.seeded(seed, salt: 100), blocks: blocks))
        }

        func microBreak(for coordinator: AppCoordinator, at now: Date, nextFullBreakIds: Set<String>) -> PlannedMicro {
            .movement(MicroBreak(id: UUID.seeded(0, salt: 101), blocks: fixture.prefix(1).map { RoutineBlock(movement: $0, seconds: 60) }))
        }

        func dayProgress(for coordinator: AppCoordinator, at now: Date) -> ModeDayProgress? { nil }
    }

    func testAThirdModeBuildsABreakThroughTheCoordinatorsBuildPath() {
        let fixture = Array(RoutineTestSupport.library.movements.filter { $0.bucket == .str }.prefix(3))
        let table = ModeBuilderTable
            .standard(strengthLibrary: RoutineTestSupport.strengthLibrary, movementLibrary: RoutineTestSupport.library)
            .adding(HundredsBuilder(fixture: fixture), for: Self.hundreds.id)
        let harness = CoordinatorHarness(modeBuilders: table)

        let planned = harness.coordinator.plannedBreak(modeId: Self.hundreds.id, at: harness.now)
        XCTAssertEqual(planned.movementIds, fixture.map(\.id))
        XCTAssertEqual(planned.parts.map(\.seconds), [100, 100, 100])
        XCTAssertEqual(planned.plannedSeconds, 3 * (100 + Routine.leadInSeconds))
        XCTAssertEqual(planned, harness.coordinator.plannedBreak(modeId: Self.hundreds.id, at: harness.now))

        // The two real modes come out of the same path, and a mode with no builder is served by
        // the fallback mode's rather than not at all.
        XCTAssertEqual(harness.coordinator.plannedBreak(modeId: BreakMode.movement.rawValue, at: harness.now).kind, .movement)
        XCTAssertEqual(harness.coordinator.plannedBreak(modeId: BreakMode.strength.rawValue, at: harness.now).kind, .strengthA)
        XCTAssertNotNil(harness.coordinator.plannedBreak(modeId: "unknown", at: harness.now).routine)
    }

    /// The same check as
    /// `git grep -nE 'case \.strength|== \.strength|\.movement \?' Sources/ | grep -v '^Sources/movez/Modes/'`,
    /// run over the files directly so it needs no git in the test host.
    func testModeBranchingLivesOnlyInTheModesFolder() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let modes = sources.appendingPathComponent("movez/Modes").standardizedFileURL.path
        let pattern = try NSRegularExpression(pattern: #"case \.strength|== \.strength|\.movement \?"#)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))

        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard !url.standardizedFileURL.path.hasPrefix(modes + "/") else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            if pattern.firstMatch(in: text, range: range) != nil { offenders.append(url.lastPathComponent) }
        }
        XCTAssertEqual(offenders, [], "only Sources/movez/Modes/ may branch on a mode")
    }
}
