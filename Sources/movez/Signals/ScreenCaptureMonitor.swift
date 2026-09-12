import AppKit
import Darwin
import Foundation

/// One tool that, when running in the right shape, means the screen is being shared or recorded.
struct CaptureSignature: Codable, Equatable {
    var name: String
    var bundleIds: [String]
    var processNames: [String]
    /// Zoom and Teams are running all day; only their share helper means a share is live.
    var requireProcessName: Bool
    /// Some listed tools sit in the menu bar all day. They stay in the file, documented, but do
    /// not suppress anything — see `disabledReason`.
    var enabled: Bool = true
    var disabledReason: String?

    /// `running` and `processes` arrive already lowercased; this is on the two-second poll path
    /// and lowercasing a thousand process names per comparison is most of what the app would do.
    ///
    /// The bundle check comes first because it is a hash lookup and the process check is a scan:
    /// Zoom and Teams are only worth looking for a helper of when they are running at all.
    func matches(bundleIds running: Set<String>, processNames processes: Set<String>) -> Bool {
        guard enabled else { return false }

        if !bundleIds.isEmpty {
            guard bundleIds.contains(where: running.contains) else { return false }
            guard requireProcessName else { return true }
        }
        return processNames.contains { processes.contains($0) || matchesTruncated($0, in: processes) }
    }

    /// The slow half, reached only for a candidate that no running name matches outright.
    private func matchesTruncated(_ candidate: String, in processes: Set<String>) -> Bool {
        guard candidate.count > CaptureSignature.nameLimit else { return false }
        return processes.contains { CaptureSignature.namesMatch($0, candidate) }
    }

    /// `proc_name` fills a fixed buffer, so an unusually long executable name arrives clipped.
    /// A clipped name is one that filled the buffer, and it matches a candidate it is a prefix of.
    /// Anything shorter has to match exactly.
    ///
    /// Matching a *longer* running name against a shorter candidate is what this deliberately
    /// does not do: `screencaptureui` — the overlay ⌘⇧5 leaves running — would otherwise satisfy
    /// the `screencapture` signature and suppress every break for as long as it lingered.
    static let nameLimit = 31

    static func namesMatch(_ running: String, _ candidate: String) -> Bool {
        let running = running.lowercased()
        let candidate = candidate.lowercased()
        if running == candidate { return true }
        guard running.count >= nameLimit else { return false }
        return candidate.hasPrefix(running)
    }
}

struct CaptureSignatures: Codable, Equatable {
    var note: String
    var signatures: [CaptureSignature]

    /// The signatures with every id and name already lowercased, computed once rather than on
    /// every poll.
    private var lowercased: [CaptureSignature] {
        signatures.map { signature in
            var lowered = signature
            lowered.bundleIds = signature.bundleIds.map { $0.lowercased() }
            lowered.processNames = signature.processNames.map { $0.lowercased() }
            return lowered
        }
    }

    static func bundled() -> CaptureSignatures? {
        guard let url = MovezBundle.resources.url(forResource: "capture-signatures", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CaptureSignatures.self, from: data)
    }

    /// Which signature, if any, is currently satisfied.
    func firstMatch(bundleIds: Set<String>, processNames: Set<String>) -> CaptureSignature? {
        let loweredBundles = Set(bundleIds.map { $0.lowercased() })
        let loweredProcesses = Set(processNames.map { $0.lowercased() })
        guard let index = lowercased.firstIndex(where: {
            $0.matches(bundleIds: loweredBundles, processNames: loweredProcesses)
        }) else { return nil }
        return signatures[index]
    }
}

/// Heuristic screen-capture detection.
///
/// macOS exposes no public API that says "the screen is being recorded", so this watches for the
/// tools people actually use. It is deliberately conservative — a false positive quietly
/// postpones a break, which is worse than missing one share. The limitation is documented in the
/// README so nobody mistakes it for a guarantee.
final class ScreenCaptureMonitor: CaptureSource {
    private let signatures: CaptureSignatures
    private let processLister: () -> Set<String>

    init(
        signatures: CaptureSignatures? = nil,
        processLister: (() -> Set<String>)? = nil
    ) {
        self.signatures = signatures ?? CaptureSignatures.bundled() ?? CaptureSignatures(note: "", signatures: [])
        self.processLister = processLister ?? ScreenCaptureMonitor.runningProcessNames
    }

    func isCaptured() -> Bool {
        matchedSignature() != nil
    }

    func matchedSignature() -> CaptureSignature? {
        let bundleIds = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return signatures.firstMatch(bundleIds: bundleIds, processNames: processLister())
    }

    var signatureCount: Int { signatures.signatures.count }
    var enabledSignatureCount: Int { signatures.signatures.filter(\.enabled).count }

    /// Every running process name, from libproc. Helper processes such as Zoom's `CptHost` never
    /// appear in `NSWorkspace.runningApplications`, which is exactly why this is needed.
    ///
    /// `proc_name` rather than `proc_pidpath`: this runs on every poll across ~1,200 processes,
    /// and asking each one for its full executable path costs five times as much as asking for
    /// its name. The name arrives truncated to sixteen characters, which is precisely what
    /// `CaptureSignature.namesMatch` was written to tolerate.
    static func runningProcessNames() -> Set<String> {
        var pids = [pid_t](repeating: 0, count: 8192)
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard byteCount > 0 else { return [] }

        var names: Set<String> = []
        var nameBuffer = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(Int(byteCount) / MemoryLayout<pid_t>.size) where pid > 0 {
            if proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 {
                let name = String(cString: nameBuffer)
                if !name.isEmpty { names.insert(name) }
            }
        }
        return names
    }
}
