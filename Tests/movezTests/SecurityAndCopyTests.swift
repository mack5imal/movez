import XCTest
@testable import movez

/// Two things that are easy to promise and easy to let slip: that movez never talks to the
/// network, and that it never raises its voice.
@MainActor
final class SecurityAndCopyTests: XCTestCase {
    private func sources() throws -> [(url: URL, text: String)] {
        try AccessibilityTests.sourceFiles().map { ($0, try String(contentsOf: $0, encoding: .utf8)) }
    }

    // MARK: - Security

    /// movez has no account, no sync and nothing to send. Any of these appearing in app code
    /// would mean that had changed.
    func testTheAppCodeCannotReachTheNetworkOrRunAProcess() throws {
        // Word-boundary patterns, so SwiftUI's `.system(size:)` is not mistaken for libc's.
        let banned = [
            "URLSession", "NSURLConnection", "Process\\(\\)", "NSTask",
            "(?<![.\\w])system\\(", "(?<![.\\w])popen\\("
        ]
        var hits: [String] = []

        for (url, text) in try sources() {
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let code = line.components(separatedBy: "//").first ?? line
                for needle in banned where code.range(of: needle, options: .regularExpression) != nil {
                    hits.append("\(url.lastPathComponent):\(index + 1) \(needle)")
                }
            }
        }

        XCTAssertTrue(hits.isEmpty, hits.joined(separator: ", "))
    }

    func testTheStateAndHistoryFilesAreOwnerOnly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("movez.tests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let state = FileSnapshotStore(url: directory.appendingPathComponent("state.json"))
        try state.save(SchedulerSnapshot(now: SchedulerHarness.mondayMorning))
        let history = FileHistoryStore(url: directory.appendingPathComponent("history.json"))
        try history.save(HistoryData())

        for url in [state.url, history.url] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
            XCTAssertEqual(permissions, 0o600, "\(url.lastPathComponent) records when someone is at their desk")
        }
    }

    func testTheEntitlementsClaimNothingBeyondWhatIsUsed() throws {
        let url = AccessibilityTests.repositoryRoot().appendingPathComponent("Sources/movez/movez.entitlements")
        let text = try String(contentsOf: url, encoding: .utf8)

        XCTAssertFalse(text.contains("com.apple.security.network"), "movez never talks to the network")
        XCTAssertFalse(text.contains("com.apple.security.files.user-selected"), "and never opens the user's files")
    }

    // MARK: - Copy

    /// One string literal, and where it came from.
    private struct UserString {
        var file: String
        var line: Int
        var text: String

        var location: String { "\(file):\(line) \(text)" }
    }

    /// Every string the user can read, with interpolations removed — the literal's actual words.
    private func userStrings() throws -> [UserString] {
        var found: [UserString] = []
        for (url, text) in try sources() {
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                for literal in Self.literals(in: line) {
                    found.append(UserString(file: url.lastPathComponent, line: index + 1, text: literal))
                }
            }
        }
        return found
    }

    private static func literals(in line: String) -> [String] {
        guard let pattern = try? NSRegularExpression(pattern: "\"((?:[^\"\\\\]|\\\\.)*)\"") else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return pattern.matches(in: line, range: range).compactMap { match in
            guard let captured = Range(match.range(at: 1), in: line) else { return nil }
            // Interpolated values are code, not copy.
            return String(line[captured]).replacingOccurrences(
                of: "\\\\\\([^)]*\\)",
                with: "",
                options: .regularExpression
            )
        }
    }

    func testNoStringRaisesItsVoice() throws {
        let shouting = try userStrings().filter { $0.text.contains("!") }
        XCTAssertTrue(
            shouting.isEmpty,
            "movez is calm: \(shouting.map(\.location).joined(separator: ", "))"
        )
    }

    func testNoPlaceholderCopySurvived() throws {
        let banned = ["Lorem", "TODO", "FIXME", "Shoulder rolls", "placeholder", "coming soon"]
        let hits = try userStrings().filter { candidate in
            banned.contains { candidate.text.localizedCaseInsensitiveContains($0) }
        }
        XCTAssertTrue(hits.isEmpty, hits.map(\.location).joined(separator: ", "))
    }

    func testNoSourceFileCarriesAnUnfinishedNote() throws {
        var hits: [String] = []
        for (url, text) in try sources() {
            for (index, line) in text.components(separatedBy: .newlines).enumerated()
            where line.contains("TODO") || line.contains("FIXME") {
                hits.append("\(url.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertTrue(hits.isEmpty, hits.joined(separator: ", "))
    }

    /// Sentence case, not Title Case. Proper nouns and sentence starts are the only capitals.
    func testUserCopyIsSentenceCase() throws {
        let properNouns = [
            "Focus", "Application", "Support", "Manrope", "Calf", "Ankle", "Foot", "Shin",
            "L-spine", "Core", "Wrist", "Forearm", "Next", "Known", "Diff", "Movez",
            "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun", "Beginner", "Moderate", "Advanced",
            "Band", "Kettlebell", "Roller", "Ball", "Debug", "Rest", "Idle", "Sleep", "Wake",
            "Lock", "Unlock", "Mic", "Capture", "Fullscreen", "Fire", "Simulate", "Cancel",
            "Apply", "Done", "Skip", "Snooze", "Start", "Resume", "Extend", "Quit", "Settings",
            "Away", "Sitting", "Paused", "Off", "Movement", "Breaks", "Count", "Working", "Equipment",
            "Excluded", "Wait", "Sounds", "Launch", "Search", "Add", "Browse", "Edit", "Time",
            "Signals", "Scheduler", "Preset", "Difficulty", "Micro", "Hip", "Hips", "One", "Two",
            "Three", "Four", "Five", "Six", "Arm", "Half", "Standing", "Wall", "Box", "March", "Stand",
            "I'm"
        ]
        var violations: [String] = []

        for candidate in try userStrings() {
            guard candidate.text.uppercased() != candidate.text else { continue }
            for sentence in candidate.text.components(separatedBy: CharacterSet(charactersIn: ".?·—\n")) {
                let words = sentence.split(separator: " ").map(String.init)
                    .compactMap { $0.trimmingCharacters(in: CharacterSet.letters.inverted) }
                    .filter { $0.count >= 3 }
                guard words.count >= 2 else { continue }
                let capitalised = words.dropFirst().filter { word in
                    guard let first = word.first, first.isUppercase else { return false }
                    // An all-caps word is an acronym (PNG, CIR), not Title Case.
                    guard word.uppercased() != word else { return false }
                    return !properNouns.contains(word)
                }
                if !capitalised.isEmpty { violations.append(candidate.location) }
            }
        }

        XCTAssertTrue(violations.isEmpty, violations.joined(separator: " | "))
    }
}
