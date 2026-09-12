import XCTest
@testable import movez

final class PersistenceTests: XCTestCase {
    private let minute: TimeInterval = 60

    func testSnapshotRoundTripsThroughJSON() throws {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        harness.clock.advance(4)
        harness.send(.userSnooze)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(harness.snapshot)
        let decoded = try decoder.decode(SchedulerSnapshot.self, from: data)
        XCTAssertEqual(decoded, harness.snapshot)
        XCTAssertTrue(decoded.state.isSnoozed)
        XCTAssertEqual(decoded.transitions.count, harness.snapshot.transitions.count)
    }

    func testRelaunchingFromASnapshotResumesTheSameDueTimes() {
        let harness = SchedulerHarness()
        harness.run(seconds: 20 * minute)
        let saved = harness.snapshot

        var resumed = Scheduler(snapshot: saved, config: SchedulerConfig())
        XCTAssertEqual(resumed.snapshot.nextFullDueAt, saved.nextFullDueAt)
        XCTAssertEqual(resumed.snapshot.nextMicroDueAt, saved.nextMicroDueAt)
        XCTAssertEqual(resumed.snapshot.boutStartedAt, saved.boutStartedAt)

        _ = resumed.handle(.tick, now: harness.now)
        XCTAssertEqual(resumed.snapshot.nextFullDueAt, saved.nextFullDueAt)
        XCTAssertTrue(resumed.state.isSitting)
    }

    func testInMemoryStoreRecordsEverySave() throws {
        let store = InMemorySnapshotStore()
        let harness = SchedulerHarness()
        harness.run(until: { $0.isHeadsUp }, limit: 60 * minute)
        for effect in harness.effects where effect == .persist {
            try store.save(harness.snapshot)
        }
        let persists = harness.effects.filter { $0 == .persist }.count
        XCTAssertEqual(store.saveCount, persists)
        XCTAssertGreaterThanOrEqual(persists, 2, "every transition persists")
        XCTAssertEqual(try store.load(), harness.snapshot)
    }

    func testEveryTransitionEmitsPersist() {
        let harness = SchedulerHarness()
        harness.run(until: { $0.isPendingFull })
        harness.send(.input(lastEventAgeSeconds: 12))
        harness.run(until: { $0.isFullBreak })
        harness.clock.advance(5 * minute)
        harness.send(.breakEnded(completedBlocks: 4, totalBlocks: 4, elapsed: 300))

        let transitions = harness.snapshot.transitions.count
        let persists = harness.effects.filter { $0 == .persist }.count
        XCTAssertEqual(persists, transitions, "one persist per transition")
    }

    func testFileStoreWritesAtomicallyAndOwnerOnly() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("movez-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileSnapshotStore(url: directory.appendingPathComponent("state.json"))
        XCTAssertNil(try store.load(), "no state file yet on first launch")

        let harness = SchedulerHarness()
        harness.run(seconds: 5 * minute)
        try store.save(harness.snapshot)

        let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600, "the state file records desk presence; keep it owner-only")

        XCTAssertEqual(try store.load(), harness.snapshot)

        // A second save replaces the file rather than appending or leaving a temp behind.
        harness.run(seconds: 5 * minute)
        try store.save(harness.snapshot)
        XCTAssertEqual(try store.load(), harness.snapshot)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(leftovers, ["state.json"], "no temporary files left behind")
    }

    func testCorruptStateFileSurfacesAnError() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("movez-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("state.json")
        try Data("{ not json".utf8).write(to: url)
        let store = FileSnapshotStore(url: url)
        XCTAssertThrowsError(try store.load())
    }

    func testApplicationSupportDirectoryIsCreated() throws {
        let directory = try FileSnapshotStore.applicationSupportDirectory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(directory.lastPathComponent, "movez")
    }
}
