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

    func matches(bundleIds running: Set<String>, processNames processes: Set<String>) -> Bool {
        guard enabled else { return false }

        let processHit = processNames.contains { candidate in
            processes.contains { CaptureSignature.namesMatch($0, candidate) }
        }
        guard !bundleIds.isEmpty else { return processHit }

        let bundleHit = bundleIds.contains { running.contains($0.lowercased()) }
        guard bundleHit else { return false }
        return requireProcessName ? processHit : true
    }

    /// `proc_name` truncates to sixteen characters, so "Microsoft Teams (Screen Share)" arrives
    /// clipped. Treat a prefix match in either direction as a hit.
    static func namesMatch(_ running: String, _ candidate: String) -> Bool {
        let running = running.lowercased()
        let candidate = candidate.lowercased()
        return running == candidate || candidate.hasPrefix(running) || running.hasPrefix(candidate)
    }
}

struct CaptureSignatures: Codable, Equatable {
    var note: String
    var signatures: [CaptureSignature]

    static func bundled() -> CaptureSignatures? {
        guard let url = MovezBundle.resources.url(forResource: "capture-signatures", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CaptureSignatures.self, from: data)
    }

    /// Which signature, if any, is currently satisfied.
    func firstMatch(bundleIds: Set<String>, processNames: Set<String>) -> CaptureSignature? {
        let lowered = Set(bundleIds.map { $0.lowercased() })
        return signatures.first { $0.matches(bundleIds: lowered, processNames: processNames) }
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
    static func runningProcessNames() -> Set<String> {
        var pids = [pid_t](repeating: 0, count: 8192)
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard byteCount > 0 else { return [] }

        var names: Set<String> = []
        // PROC_PIDPATHINFO_MAXSIZE (4 * MAXPATHLEN) is not imported into Swift.
        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(Int(byteCount) / MemoryLayout<pid_t>.size) where pid > 0 {
            if proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 {
                let path = String(cString: pathBuffer)
                if !path.isEmpty { names.insert((path as NSString).lastPathComponent) }
            }
        }
        return names
    }
}
