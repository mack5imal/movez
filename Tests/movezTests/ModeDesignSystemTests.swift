import AppKit
import SwiftUI
import XCTest
@testable import movez

/// The mode design system: glyphs looked up through the definition, the badge, the menu-bar icon,
/// the rep meter's two looks and the new type styles.
@MainActor
final class ModeDesignSystemTests: XCTestCase {
    /// A mode that exists only here. Its glyph ids are the design's, its definition is not in the
    /// standard table, and nothing in the app was changed to serve it.
    private static let hundreds = ModeDefinition(
        id: "hundreds-test",
        displayName: "100s",
        eyebrowWord: "100s",
        badgeGlyph: "mode.hundreds",
        menuBarGlyph: "mode.pt",
        settingsGroup: ModeSettingsGroup(id: "hundreds-test", title: "100s"),
        isSetUp: nil
    )

    override func setUp() {
        super.setUp()
        MovezFont.register()
    }

    // MARK: - Glyphs come from the definition

    func testEachModesBadgeAndMenuBarGlyphComeFromItsDefinition() {
        for definition in ModeDefinition.all + [Self.hundreds] {
            XCTAssertEqual(ModeBadge(definition: definition).glyph?.id, definition.badgeGlyph, definition.id)
            XCTAssertEqual(ModeGlyph.menuBar(for: definition)?.id, definition.menuBarGlyph, definition.id)
        }
        XCTAssertEqual(ModeBadge(definition: BreakMode.movement.definition).glyph?.id, "mode.movement")
        XCTAssertEqual(ModeBadge(definition: BreakMode.strength.definition).glyph?.id, "mode.strength")
        // The two glyphs are separate fields, so the test mode wears different ones.
        XCTAssertEqual(ModeBadge(definition: Self.hundreds).glyph?.id, "mode.hundreds")
        XCTAssertEqual(ModeGlyph.menuBar(for: Self.hundreds)?.id, "mode.pt")
        XCTAssertNil(ModeGlyph.named("mode.unknown"))
    }

    func testTheMenuBarIconDrawsTheGlyphOfTheModeInTheState() throws {
        var movement = MenuBarState()
        movement.elapsedFraction = 0.42
        var strength = movement
        strength.breakMode = .strength

        let movementPixels = try XCTUnwrap(MenuBarIcon.image(for: movement).tiffRepresentation)
        let strengthPixels = try XCTUnwrap(MenuBarIcon.image(for: strength).tiffRepresentation)
        XCTAssertNotEqual(movementPixels, strengthPixels, "modes differ by glyph")
    }

    func testAThirdTestOnlyDefinitionRendersABadge() throws {
        XCTAssertNil(ModeDefinitionTable.standard.definition(for: Self.hundreds.id))

        let overlay = ModeBadge(definition: Self.hundreds, size: .overlay, label: .breakEyebrow)
        XCTAssertEqual(overlay.text, "100s BREAK")
        XCTAssertFalse(overlay.resolvedStyle.uppercase, "the eyebrow keeps 100s' lowercase s")
        let panel = ModeBadge(definition: Self.hundreds, size: .panel, label: .microBreakEyebrow)
        XCTAssertEqual(panel.text, "100s MICRO-BREAK")
        XCTAssertNotNil(overlay.glyph)

        let renderer = ImageRenderer(content: overlay)
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.width, ModeBadge.Size.overlay.glyph)
        XCTAssertGreaterThanOrEqual(image.size.height, ModeBadge.Size.overlay.glyph)
    }

    func testANameInACapitalsStyleUsesTheEyebrowWord() {
        let hundreds = ModeBadge(definition: Self.hundreds, size: .overlay, label: .name, style: MovezType.eyebrowOverlay)
        XCTAssertEqual(hundreds.text, "100s", "uppercasing the name would read 100S")
        XCTAssertFalse(hundreds.resolvedStyle.uppercase)
        let strength = ModeBadge(
            definition: BreakMode.strength.definition, size: .overlay, label: .name, style: MovezType.eyebrowOverlay
        )
        XCTAssertEqual(strength.text, "STRENGTH")
        // Outside a capitals style the name stays as the definition writes it.
        XCTAssertEqual(ModeBadge(definition: BreakMode.strength.definition, size: .dropdown, label: .name).text, "Strength")
    }

    func testEyebrowsReadAsTheDesignWritesThem() {
        XCTAssertEqual(ModeBadge.text(for: BreakMode.movement.definition, label: .breakEyebrow), "MOVEMENT BREAK")
        XCTAssertEqual(ModeBadge.text(for: BreakMode.movement.definition, label: .microBreakEyebrow), "MOVEMENT MICRO-BREAK")
        XCTAssertEqual(ModeBadge.text(for: BreakMode.strength.definition, label: .breakEyebrow), "STRENGTH BREAK")
        XCTAssertEqual(ModeBadge.text(for: BreakMode.strength.definition, label: .name), "Strength")
        XCTAssertEqual(ModeBadge.text(for: SnapshotFixtures.hundredsMode, label: .microBreakEyebrow), "100s MICRO-BREAK")
        XCTAssertEqual(ModeBadge.text(for: SnapshotFixtures.personalTrainingMode, label: .breakEyebrow), "PT BREAK")
        XCTAssertEqual(ModeBadge.text(for: SnapshotFixtures.personalTrainingMode, label: .microBreakEyebrow), "PT MICRO-BREAK")
        XCTAssertEqual(ModeBadge.text(for: SnapshotFixtures.personalTrainingMode, label: .name), "PT")
        // The sheet-only modes never reach the app's table.
        for fixture in [SnapshotFixtures.hundredsMode, SnapshotFixtures.personalTrainingMode] {
            XCTAssertNil(ModeDefinitionTable.standard.definition(for: fixture.id))
        }
    }

    func testTheDropdownCollapsesInactiveModesOnlyPastTwo() {
        XCTAssertFalse(ModeSegmentedControl.collapsesInactive(.dropdown, modeCount: 2))
        XCTAssertTrue(ModeSegmentedControl.collapsesInactive(.dropdown, modeCount: 3))
        XCTAssertFalse(ModeSegmentedControl.collapsesInactive(.settings, modeCount: 4))
    }

    // MARK: - Menu-bar icon states

    func testTheIconStatesUseTheDesignsOpacities() {
        XCTAssertEqual(MenuBarIcon.pointSize, 18)
        XCTAssertEqual(MenuBarIcon.ringAlpha(for: .sitting), 0.35, accuracy: 0.001)
        XCTAssertEqual(MenuBarIcon.ringAlpha(for: .paused), 0.75, accuracy: 0.001)
        XCTAssertEqual(MenuBarIcon.ringAlpha(for: .offHours), 0.55, accuracy: 0.001)
        XCTAssertEqual(MenuBarIcon.ringAlpha(for: .away), 0.60, accuracy: 0.001)
        XCTAssertEqual(MenuBarIcon.glyphAlpha(for: .offHours), 0.55, accuracy: 0.001)
        for mode in [MenuBarState.Mode.sitting, .paused, .away] {
            XCTAssertEqual(MenuBarIcon.glyphAlpha(for: mode), 1, mode.rawValue)
        }
        XCTAssertTrue(MenuBarIcon.showsProgress(.sitting))
        XCTAssertFalse(MenuBarIcon.showsProgress(.paused))
        XCTAssertFalse(MenuBarIcon.showsProgress(.away))
    }

    func testOnlyThePausedRingIsDashedSixOnFiveInAHundred() throws {
        let dashes = try XCTUnwrap(MenuBarIcon.dashPattern(for: .paused))
        let circumference = 2 * CGFloat.pi * 8
        XCTAssertEqual(dashes[0], circumference * 6 / 100, accuracy: 0.001)
        XCTAssertEqual(dashes[1], circumference * 5 / 100, accuracy: 0.001)
        XCTAssertNil(MenuBarIcon.dashPattern(for: .sitting))
        XCTAssertNil(MenuBarIcon.dashPattern(for: .offHours))
        XCTAssertNil(MenuBarIcon.dashPattern(for: .away))
    }

    func testTheSittingIconDrawsTheSpentArcAtFullStrengthOverTheTrack() {
        // Drawn ten times over so a pixel sits squarely on the stroke: ring r 80, stroke 16.
        let image = MenuBarIcon.image(mode: .sitting, fraction: 0.42, size: 180)
        XCTAssertEqual(alpha(of: image, x: 95, y: 10), 1, accuracy: 0.05, "the arc starts at twelve")
        XCTAssertEqual(alpha(of: image, x: 10, y: 90), 0.35, accuracy: 0.05, "nine o'clock is unspent")

        let offHours = MenuBarIcon.image(mode: .offHours, fraction: 0.42, size: 180)
        XCTAssertEqual(alpha(of: offHours, x: 95, y: 10), 0.55, accuracy: 0.05, "no progress off hours")
        // The middle of the wave is the glyph's centre.
        XCTAssertEqual(alpha(of: offHours, x: 90, y: 90), 0.55, accuracy: 0.05)
        XCTAssertEqual(alpha(of: image, x: 90, y: 90), 1, accuracy: 0.05)
    }

    // MARK: - Rep meter

    func testTheRepMeterIsSteppedUnderReduceMotionAndSmoothOtherwiseFromOneState() throws {
        let pacer = try XCTUnwrap(RepPacer(reps: 8, perSide: false, holdSeconds: nil, paceSeconds: 3, switchSidesSeconds: 3))
        // Rep 3, a quarter of the way up.
        let state = pacer.state(at: 6.75)
        XCTAssertEqual(state.rep, 3)

        guard case let .stepped(segments) = RepMeter(state: state, reduceMotion: true).look else {
            return XCTFail("Reduce Motion draws the ladder")
        }
        XCTAssertEqual(segments.count, 8)
        XCTAssertEqual(segments, [.done, .done, .current, .later, .later, .later, .later, .later])

        guard case let .smooth(fillHeight, chevron) = RepMeter(state: state, reduceMotion: false).look else {
            return XCTFail("the default draws the fill")
        }
        guard case let .smooth(fraction) = state.level else { return XCTFail("a smooth pacer reading") }
        XCTAssertEqual(fillHeight, 64 + 200 * CGFloat(fraction), accuracy: 0.001)
        XCTAssertEqual(chevron, .up)

        // The pacer's own stepped reading gives the same ladder.
        let stepped = pacer.state(at: 6.75, stepped: true)
        XCTAssertEqual(RepMeterLook.make(for: stepped, reduceMotion: true), .stepped(segments: segments))
    }

    func testTheRepMeterFillRunsFromOnePillToTheWholeTrack() {
        XCTAssertEqual(RepMeterLook.fillHeight(for: 0), 64)
        XCTAssertEqual(RepMeterLook.fillHeight(for: 1), 264)
        XCTAssertEqual(RepMeterLook.fillHeight(for: 0.5), 164)
    }

    func testTheSwitchCueEmptiesTheMeterInEitherLook() throws {
        let pacer = try XCTUnwrap(RepPacer(reps: 4, perSide: true, holdSeconds: nil, paceSeconds: 3, switchSidesSeconds: 3))
        let cue = pacer.state(at: 13)
        XCTAssertEqual(cue.counter, "Switch sides")
        XCTAssertEqual(RepMeterLook.make(for: cue, reduceMotion: false), .switchCue)
        XCTAssertEqual(RepMeterLook.make(for: cue, reduceMotion: true), .switchCue)
    }

    // MARK: - Type

    func testTheDoseStylesAreBoldAtTheirSizes() {
        XCTAssertEqual(MovezType.dose.size, 28)
        XCTAssertEqual(MovezType.dose.weight, .bold)
        XCTAssertEqual(MovezType.panelDose.size, 20)
        XCTAssertEqual(MovezType.panelDose.weight, .bold)
        XCTAssertEqual(MovezType.dose.nsFont.pointSize, 28, accuracy: 0.01)
        XCTAssertEqual(MovezType.panelDose.nsFont.pointSize, 20, accuracy: 0.01)
    }

    // MARK: - By badge, not colour (S12)

    /// Modes tell themselves apart by glyph and word, so every accent element wears the same
    /// `Tokens.accent` whichever mode it shows, and the menu-bar icon is a template the system tints.
    func testTheAccentIsTheSameInEveryMode() {
        for mode in BreakMode.allCases {
            let badge = ModeBadge(definition: mode.definition)
            XCTAssertEqual(badge.textColor, Tokens.accent, "\(mode) badge words")
            XCTAssertEqual(badge.glyphColor, Tokens.accent, "\(mode) badge glyph")
            XCTAssertEqual(ModeGlyphView(glyph: ModeGlyph.badge(for: mode.definition), size: 12).color, Tokens.accent, "\(mode) glyph")
            var state = MenuBarState()
            state.breakMode = mode
            XCTAssertTrue(MenuBarIcon.image(for: state).isTemplate, "\(mode) menu-bar icon is tinted by the system")
        }
        XCTAssertEqual(PanelHeader.doseColor, Tokens.accent, "the panel dose line")
    }

    /// No colour is read through a mode-dependent path: the mode definitions name no colour, and
    /// the tokens know nothing of modes. Run over the files directly, as
    /// `ModeExtensibilityTests.testModeBranchingLivesOnlyInTheModesFolder` is.
    func testNoColourIsReadThroughAModeDependentPath() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/movez")
        let modes = sources.appendingPathComponent("Modes")
        let files = try FileManager.default.contentsOfDirectory(at: modes, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "the mode definitions were found")

        let colour = try NSRegularExpression(pattern: #"Tokens\.|MovezColor|Color"#)
        var offenders: [String] = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            if colour.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                offenders.append(url.lastPathComponent)
            }
        }
        XCTAssertEqual(offenders, [], "a mode definition names a colour")

        let tokens = try String(contentsOf: sources.appendingPathComponent("UI/DesignSystem/Tokens.swift"), encoding: .utf8)
        XCTAssertTrue(tokens.contains("static let accent"), "Tokens.swift was read")
        XCTAssertNil(tokens.range(of: "mode", options: .caseInsensitive), "Tokens.swift refers to a mode")
    }

    // MARK: - Helpers

    /// The alpha of one pixel, counted from the top-left, with the image drawn at one pixel a point.
    private func alpha(of image: NSImage, x column: Int, y row: Int) -> CGFloat {
        let side = Int(image.size.width)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return -1 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return rep.colorAt(x: column, y: row)?.alphaComponent ?? -1
    }
}
