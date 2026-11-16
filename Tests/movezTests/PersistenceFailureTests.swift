import XCTest
@testable import movez

/// What happens when the state and history cannot be written. Every test works in a temporary
/// folder; none touches the real Application Support (APP-3).
@MainActor
final class PersistenceFailureTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("movez-persistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A plain file named `movez` where the folder should be: nothing can be saved, and the app
    /// says so instead of running a whole session that is lost at quit.
    func testAStoreFolderThatCannotBeCreatedIsReported() throws {
        let base = try temporaryDirectory()
        try "in the way".write(to: base.appendingPathComponent("movez"), atomically: true, encoding: .utf8)

        let stores = Launch.openStores(base: base)
        XCTAssertNil(stores.snapshotStore)
        XCTAssertNotNil(stores.problem)
    }

    func testAStoreFolderThatOpensReportsNothing() throws {
        let stores = Launch.openStores(base: try temporaryDirectory())
        XCTAssertNotNil(stores.snapshotStore)
        XCTAssertNil(stores.problem)
    }

    func testTheMenuShowsAStoreProblem() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        harness.coordinator.storageProblem = "Movez cannot save."
        let menu = MenuBarViewModel(coordinator: harness.coordinator)
        XCTAssertEqual(menu.state.storageWarning, "Movez cannot save.")
    }

    // MARK: - A failed save leaves nothing behind

    /// A file that cannot be replaced: the temp file is written, and the final swap fails.
    private func immutableFile(named name: String) throws -> (directory: URL, url: URL) {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent(name)
        try "{}".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: url.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: url.path) }
        return (directory, url)
    }

    func testAFailedStateSaveLeavesNoTemporaryFile() throws {
        let (directory, url) = try immutableFile(named: "state.json")

        let store = FileSnapshotStore(url: url)
        XCTAssertThrowsError(try store.save(SchedulerSnapshot(now: SchedulerHarness.mondayMorning, dayKey: "2026-09-07")))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".") }
        XCTAssertEqual(leftovers, [])
    }

    func testAFailedHistorySaveLeavesNoTemporaryFile() throws {
        let (directory, url) = try immutableFile(named: "history.json")

        let store = FileHistoryStore(url: url)
        XCTAssertThrowsError(try store.save(HistoryData()))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".") }
        XCTAssertEqual(leftovers, [])
    }
}
