import Foundation

protocol HistoryPersisting: AnyObject {
    func save(_ data: HistoryData) throws
    func load() throws -> HistoryData?
    /// Moves a history that could not be read out of the way of the next save, and says where it
    /// went. Nil where there is nothing to move, as in memory.
    func setAsideUnreadable() -> URL?
}

extension HistoryPersisting {
    func setAsideUnreadable() -> URL? { nil }
}

/// `~/Library/Application Support/movez/history.json`, written atomically and owner-only for the
/// same reason the state file is: it is a record of when someone is at their desk.
final class FileHistoryStore: HistoryPersisting {
    let url: URL
    private(set) var saveCount = 0
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL) {
        self.url = url
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    static func historyFile() throws -> FileHistoryStore {
        FileHistoryStore(url: try FileSnapshotStore.applicationSupportDirectory().appendingPathComponent("history.json"))
    }

    func save(_ data: HistoryData) throws {
        let encoded = try encoder.encode(data)
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        try encoded.write(to: temporary, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: FileSnapshotStore.fileProtectionMode],
            ofItemAtPath: temporary.path
        )
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        try? FileManager.default.setAttributes(
            [.posixPermissions: FileSnapshotStore.fileProtectionMode],
            ofItemAtPath: url.path
        )
        saveCount += 1
    }

    func load() throws -> HistoryData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(HistoryData.self, from: Data(contentsOf: url))
    }

    /// `history.json.unreadable-20261116T093000Z`, beside the file it was. The next save would
    /// otherwise replace the only copy of a record a newer build, or a second try, could read.
    func setAsideUnreadable() -> URL? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "")
        let aside = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).unreadable-\(stamp)")
        do {
            try FileManager.default.moveItem(at: url, to: aside)
            return aside
        } catch {
            return nil
        }
    }
}

final class InMemoryHistoryStore: HistoryPersisting {
    private(set) var saved: HistoryData?
    private(set) var saveCount = 0

    init(seed: HistoryData? = nil) {
        saved = seed
    }

    func save(_ data: HistoryData) throws {
        saved = data
        saveCount += 1
    }

    func load() throws -> HistoryData? { saved }
}
