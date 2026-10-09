import AppKit
import Foundation

/// `movez --overlay-hygiene`: opens a real break overlay on every display for three seconds and
/// reports the window properties that the complaints in this category of app are all about.
///
/// None of it can be unit tested — it is AppKit window state on real screens — so the harness is
/// the evidence instead.
///
/// Cleanliness note: the prints below are the output of a command-line tool, not logging.
@MainActor
enum OverlayHygiene {
    static let presentSeconds: TimeInterval = 3

    /// The report is also written here, because Launch Services gives a double-clicked app no
    /// stdout — and launching through Launch Services is the only way to test activation
    /// faithfully.
    static let reportPath = "build/overlay-hygiene.txt"
    nonisolated(unsafe) private static var report: [String] = []

    private static func emit(_ line: String) {
        print(line)
        fflush(stdout)
        report.append(line)
    }

    /// An app opened through Launch Services starts with "/" as its working directory, so the
    /// report goes to Application Support as well as to the relative path a shell run can use.
    private static func writeReport(to explicitPath: String?) {
        let text = report.joined(separator: "\n") + "\n"
        var destinations: [URL] = []
        if let explicitPath { destinations.append(URL(fileURLWithPath: explicitPath)) }
        destinations.append(URL(fileURLWithPath: reportPath))
        if let support = try? FileSnapshotStore.applicationSupportDirectory() {
            destinations.append(support.appendingPathComponent("overlay-hygiene.txt"))
        }
        for url in destinations {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func run(outPath: String? = nil, completion: @escaping (Int32) -> Void) {
        MovezFont.register()
        report.removeAll()

        guard let library = try? LibraryLoader.loadBundled() else {
            FileHandle.standardError.write(Data("could not load the movement library\n".utf8))
            return completion(2)
        }

        let clock = SystemClock()
        let routine = RoutineBuilder(library: library).build(context: fixtureContext())
        let chimes = RecordingChimePlayer()
        let controller = OverlayWindowController()
        let frontmostBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"

        let viewModel = OverlayViewModel(
            routine: routine,
            startedAt: clock.now,
            clock: clock,
            chimes: chimes,
            skipsToday: 1,
            streak: 2,
            nextBreakAt: clock.now.addingTimeInterval(3300)
        )
        // How long the break takes to actually appear. A break that arrives a second late has
        // already interrupted whatever the user was doing, twice.
        let presentStart = Date()
        controller.present(viewModel)
        while controller.visibleWindowCount == 0, Date().timeIntervalSince(presentStart) < 2 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
        let presentMs = Date().timeIntervalSince(presentStart) * 1000

        SnapshotRenderer.pumpRunLoop(seconds: presentSeconds)

        emit([
            "screens=\(NSScreen.screens.count)",
            "windows=\(controller.windowCount)",
            "level=\(controller.windowLevel)",
            "shielding=\(Int(CGShieldingWindowLevel()))",
            "behaviors=\(controller.collectionBehaviourNames.joined(separator: "+"))",
            "key=\(controller.hasKeyWindow)",
            "frontmostBefore=\(frontmostBefore)",
            "appActive=\(NSApp.isActive)",
            "canBecomeKey=\(controller.windowsCanBecomeKey)",
            "keyWindowOwner=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none")",
            "visible=\(controller.visibleWindowCount)",
            "presentMs=\(String(format: "%.0f", presentMs))",
            "policy=\(NSApp.activationPolicy().rawValue)"
        ].joined(separator: " "))

        // Sleep must take the overlay down at once, with nothing left behind.
        controller.dismiss(animated: false)
        SnapshotRenderer.pumpRunLoop(seconds: 0.5)

        let frontmostAfter = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"
        emit([
            "windowsAfterSleep=\(controller.windowCount)",
            "monitorRemoved=\(!controller.hasKeyMonitor)",
            "frontmostAfter=\(frontmostAfter)",
            "focusRestored=\(frontmostAfter == frontmostBefore)"
        ].joined(separator: " "))
        emit("overlay hygiene ok")
        writeReport(to: outPath)
        completion(0)
    }

    private static func fixtureContext() -> RoutineContext {
        var context = RoutineContext()
        context.seed = 2_026
        return context
    }
}
