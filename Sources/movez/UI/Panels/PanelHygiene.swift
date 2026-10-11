import AppKit
import Foundation

/// One panel's worth of evidence: where it landed, and what it did to the app in front.
struct PanelObservation {
    var name: String
    var frame: NSRect
    var visible: NSRect
    var screen: CGSize
    var frontmostBefore: String
    var frontmostAfter: String
    var nonactivating: Bool

    /// The line `--panel-hygiene` prints, in the order the phase spec asks for.
    var line: String {
        [
            "panel=\(name)",
            "frame=\(PanelHygiene.rect(frame))",
            "screen=\(PanelHygiene.number(screen.width)),\(PanelHygiene.number(screen.height))",
            "frontmostBefore=\(frontmostBefore)",
            "frontmostAfter=\(frontmostAfter)",
            "nonactivating=\(nonactivating)",
            "visible=\(PanelHygiene.rect(visible))"
        ].joined(separator: " ")
    }

    /// The one thing a floating panel must never do.
    var focusFailures: [String] {
        var failures: [String] = []
        if frontmostAfter != frontmostBefore {
            failures.append("\(name): focus moved from \(frontmostBefore) to \(frontmostAfter)")
        }
        if !nonactivating { failures.append("\(name): the panel activated movez") }
        return failures
    }
}

/// `movez --panel-hygiene`: shows each floating panel for a second and reports where it landed
/// and — the thing that actually matters — that putting it on screen took nothing away from the
/// app the user was in.
///
/// None of this can be unit tested: it is AppKit window placement on real screens against a real
/// frontmost application. The harness is the evidence instead.
///
/// Cleanliness note: the prints below are the output of a command-line tool, not logging.
@MainActor
enum PanelHygiene {
    static let presentSeconds: TimeInterval = 1
    /// Placement is in points and everything is rounded, so a point of slack is the tolerance.
    static let tolerance: CGFloat = 1

    static func run(completion: @escaping (Int32) -> Void) {
        MovezFont.register()
        let controller = PanelWindowController()
        var failures: [String] = []

        for (name, model) in panelFixtures() {
            failures += showPanel(name: name, model: model, controller: controller)
        }
        failures += showToast(controller: controller)

        guard failures.isEmpty else {
            for failure in failures { FileHandle.standardError.write(Data("FAIL \(failure)\n".utf8)) }
            return completion(2)
        }
        emit("panel hygiene ok")
        completion(0)
    }

    // MARK: - The panels

    private static func panelFixtures() -> [(String, PanelViewModel)] {
        [
            ("headsup", SnapshotFixtures.headsUp()),
            ("headsup-deferred", SnapshotFixtures.headsUp(deferred: true)),
            ("micro-countin", SnapshotFixtures.microCountIn()),
            ("micro-running", SnapshotFixtures.microRunning())
        ]
    }

    private static func showPanel(
        name: String,
        model: PanelViewModel,
        controller: PanelWindowController
    ) -> [String] {
        let before = frontmost()
        controller.present(panel: model)
        SnapshotRenderer.pumpRunLoop(seconds: presentSeconds)

        let observation = observe(
            name: name,
            frame: controller.panelShellFrame ?? .zero,
            nonactivating: controller.isNonActivating(controller.panelWindow),
            before: before
        )
        let centreDelta = abs(observation.frame.midX - observation.visible.midX)
        let topDelta = abs(observation.frame.maxY - (observation.visible.maxY - PanelWindowController.topInset))
        emit("\(observation.line) centreDelta=\(number(centreDelta)) topDelta=\(number(topDelta))")

        var failures = observation.focusFailures
        if centreDelta > tolerance { failures.append("\(name): off centre by \(number(centreDelta)) pt") }
        if topDelta > tolerance { failures.append("\(name): top off by \(number(topDelta)) pt") }

        controller.hidePanel(animated: false)
        SnapshotRenderer.pumpRunLoop(seconds: 0.2)
        return failures
    }

    private static func showToast(controller: PanelWindowController) -> [String] {
        let before = frontmost()
        controller.present(toast: SnapshotFixtures.awayToast())
        SnapshotRenderer.pumpRunLoop(seconds: presentSeconds)

        let observation = observe(
            name: "toast",
            frame: controller.toastShellFrame ?? .zero,
            nonactivating: controller.isNonActivating(controller.toastWindow),
            before: before
        )
        let rightInset = observation.visible.maxX - observation.frame.maxX
        let topInset = observation.visible.maxY - observation.frame.maxY
        emit("\(observation.line) rightInset=\(number(rightInset)) topInset=\(number(topInset))")

        var failures = observation.focusFailures
        if abs(rightInset - PanelWindowController.toastInset) > tolerance {
            failures.append("toast: right inset \(number(rightInset))")
        }
        if abs(topInset - PanelWindowController.topInset) > tolerance {
            failures.append("toast: top inset \(number(topInset))")
        }

        controller.hideToast(animated: false)
        SnapshotRenderer.pumpRunLoop(seconds: 0.2)
        return failures
    }

    private static func observe(
        name: String,
        frame: NSRect,
        nonactivating: Bool,
        before: String
    ) -> PanelObservation {
        let screen = PanelWindowController.activeScreen()
        return PanelObservation(
            name: name,
            frame: frame,
            visible: screen.visibleFrame,
            screen: screen.frame.size,
            frontmostBefore: before,
            frontmostAfter: frontmost(),
            nonactivating: nonactivating
        )
    }

    // MARK: - Formatting

    nonisolated static func rect(_ rect: NSRect) -> String {
        "\(number(rect.minX)),\(number(rect.minY)),\(number(rect.width)),\(number(rect.height))"
    }

    nonisolated static func number(_ value: CGFloat) -> String {
        String(format: "%g", Double(value))
    }

    private static func frontmost() -> String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"
    }

    private static func emit(_ line: String) {
        print(line)
        fflush(stdout)
    }
}
