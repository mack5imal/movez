import Foundation

/// Where the scheduler snapshot lives between launches.
protocol SnapshotStore: AnyObject {
    func save(_ snapshot: SchedulerSnapshot) throws
    func load() throws -> SchedulerSnapshot?
}

enum PersistenceError: LocalizedError, Equatable {
    case directoryUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .directoryUnavailable(let reason): return "movez could not open its data directory: \(reason)"
        }
    }
}

/// Atomic, owner-only JSON on disk.
///
/// The snapshot is written to a sibling temp file and renamed into place, so a crash mid-write
/// never leaves a half-written state file behind. The file is created 0600: it records when the
/// user is at their desk, which is nobody else's business.
final class FileSnapshotStore: SnapshotStore {
    static let fileProtectionMode: Int = 0o600

    let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL) {
        self.url = url
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// `~/Library/Application Support/movez`, created if missing.
    static func applicationSupportDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else { throw PersistenceError.directoryUnavailable("no Application Support directory") }
        let directory = base.appendingPathComponent("movez", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    static func stateFile() throws -> FileSnapshotStore {
        FileSnapshotStore(url: try applicationSupportDirectory().appendingPathComponent("state.json"))
    }

    func save(_ snapshot: SchedulerSnapshot) throws {
        let data = try encoder.encode(snapshot)
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        try data.write(to: temporary, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.fileProtectionMode],
            ofItemAtPath: temporary.path
        )
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        try? FileManager.default.setAttributes(
            [.posixPermissions: Self.fileProtectionMode],
            ofItemAtPath: url.path
        )
    }

    func load() throws -> SchedulerSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(SchedulerSnapshot.self, from: data)
    }
}

/// The store the tests use.
final class InMemorySnapshotStore: SnapshotStore {
    private(set) var saved: SchedulerSnapshot?
    private(set) var saveCount = 0

    init(seed: SchedulerSnapshot? = nil) {
        saved = seed
    }

    func save(_ snapshot: SchedulerSnapshot) throws {
        saved = snapshot
        saveCount += 1
    }

    func load() throws -> SchedulerSnapshot? { saved }
}
