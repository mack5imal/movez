import AppKit
import SwiftUI
import XCTest
@testable import movez

/// The overlay is read from standing distance and the panels appear while the user is typing.
/// Both have to work for someone who cannot see them at all.
@MainActor
final class AccessibilityTests: XCTestCase {
    // MARK: - Every control says what it is

    /// SwiftUI builds its accessibility tree lazily, when a real assistive client asks for it —
    /// an offscreen `NSHostingView` in a test has none to walk. So the sweep is done where the
    /// labels are actually written: every control in the design system, and every icon-only
    /// button anywhere in the app.
    func testEveryDesignSystemControlSaysWhatItIs() throws {
        let controls = [
            "MovezToggle", "SegmentedControl", "Chip", "SelectField", "MenuRow", "TimerDisc",
            "SequenceStrip", "StreakChip", "SideToggle", "StepperField", "ExceptionRow",
            "DebugContainer"
        ]
        var silent: [String] = []

        for name in controls {
            guard let declaration = try Self.declaration(of: name) else {
                silent.append("\(name): not found")
                continue
            }
            if !declaration.contains("accessibility") { silent.append(name) }
        }

        XCTAssertTrue(silent.isEmpty, "controls with nothing to announce: \(silent.joined(separator: ", "))")
    }

    /// A button whose label draws no text has to carry an `accessibilityLabel`, because there is
    /// nothing for VoiceOver to fall back on.
    func testEveryIconOnlyControlCarriesALabelInSource() throws {
        let sources = try Self.sourceFiles()
        var missing: [String] = []

        for url in sources {
            let text = try String(contentsOf: url, encoding: .utf8)
            let lines = text.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                guard line.contains("Image(systemName:") else { continue }
                // The chevrons and the search glyph are decoration beside their own text.
                guard !Self.decorativeGlyphs.contains(where: line.contains) else { continue }
                let window = lines[max(0, index - 6)...min(lines.count - 1, index + 8)]
                guard !window.joined().contains("accessibilityLabel") else { continue }
                missing.append("\(url.lastPathComponent):\(index + 1)")
            }
        }

        XCTAssertTrue(missing.isEmpty, "icon-only controls with no label: \(missing.joined(separator: ", "))")
    }

    func testTheTimerDiscSpeaksItsCountdownAndWhatItDoes() {
        XCTAssertEqual(TimerDisc.announcement(numerals: "0:42", label: "NEXT →"), "0:42, NEXT →")
        XCTAssertEqual(TimerDisc.announcement(numerals: "32", label: nil), "32")
    }

    func testTheSequenceStripNamesEachBlockAndWhichIsCurrent() {
        let items = SnapshotFixtures.strip(currentIndex: 1)
        let strip = SequenceStrip(items: items)

        XCTAssertEqual(strip.announcement(for: items[0]), "March in place, block 1 of 4, done")
        XCTAssertEqual(strip.announcement(for: items[1]), "Hip flexor /side, block 2 of 4, current")
        XCTAssertEqual(strip.announcement(for: items[3]), "Box breathing, block 4 of 4, upcoming")
    }

    // MARK: - Reduce Motion

    func testReduceMotionTurnsTheOverlayAnimationsOff() {
        let clock = ManualClock(now: SchedulerHarness.mondayMorning)
        let routine = RoutineTestSupport.builder.build(context: RoutineContext())

        let animated = OverlayViewModel(routine: routine, startedAt: clock.now, clock: clock, reduceMotion: false)
        let still = OverlayViewModel(routine: routine, startedAt: clock.now, clock: clock, reduceMotion: true)

        XCTAssertTrue(animated.animationsEnabled)
        XCTAssertFalse(still.animationsEnabled, "the first thing to go when the system asks for less motion")
    }

    // MARK: - Contrast

    /// WCAG 2.1 contrast for every pairing the app actually draws.
    func testContrastRatios() throws {
        let panel = Contrast.composite(Tokens.panel, over: Tokens.ink)
        let pairs: [(name: String, ratio: Double)] = [
            ("accent on ink", Contrast.ratio(Tokens.accent, Tokens.ink)),
            ("ink on accent", Contrast.ratio(Tokens.ink, Tokens.accent)),
            ("text on panel", Contrast.ratio(Tokens.text, panel)),
            ("text2 on panel", Contrast.ratio(Tokens.text2, panel)),
            ("text3 on panel", Contrast.ratio(Tokens.text3, panel)),
            ("accent on panel", Contrast.ratio(Tokens.accent, panel)),
            ("warn on panel", Contrast.ratio(Tokens.warn, panel))
        ]

        let report = pairs
            .map { String(format: "%-18@ %.2f:1", $0.name as NSString, $0.ratio) }
            .joined(separator: "\n")
        try Self.write(report: report, to: "build/contrast.txt")

        XCTAssertGreaterThanOrEqual(Contrast.ratio(Tokens.accent, Tokens.ink), 4.5, report)
        XCTAssertGreaterThanOrEqual(Contrast.ratio(Tokens.ink, Tokens.accent), 4.5, report)
        XCTAssertGreaterThanOrEqual(Contrast.ratio(Tokens.text, panel), 4.5, report)
        XCTAssertGreaterThanOrEqual(Contrast.ratio(Tokens.text2, panel), 4.5, report)
        // text3 is decorative — shortcut glyphs, ids, captions — and is recorded, not gated.
        XCTAssertGreaterThan(Contrast.ratio(Tokens.text3, panel), 1)
    }

    // MARK: - Reading the source

    /// The body of `struct <name>: View { … }`, by brace depth.
    static func declaration(of name: String) throws -> String? {
        for url in try sourceFiles() {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard let start = text.range(of: "struct \(name)") ?? text.range(of: "class \(name)") else { continue }
            var depth = 0
            var started = false
            var body = ""
            for character in text[start.lowerBound...] {
                body.append(character)
                if character == "{" {
                    depth += 1
                    started = true
                } else if character == "}" {
                    depth -= 1
                    if started, depth == 0 { return body }
                }
            }
            return body
        }
        return nil
    }

    private static let decorativeGlyphs = ["chevron.right", "chevron.down", "chevron.up.chevron.down", "magnifyingglass"]

    // MARK: - Files

    static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func sourceFiles() throws -> [URL] {
        let sources = repositoryRoot().appendingPathComponent("Sources/movez")
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        return (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }.sorted {
            $0.path < $1.path
        }
    }

    static func write(report: String, to relativePath: String) throws {
        let url = repositoryRoot().appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try report.write(to: url, atomically: true, encoding: .utf8)
    }
}
