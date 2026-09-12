import AppKit
import SwiftUI

/// Owns process-level concerns: font registration, accessory activation policy, the coordinator's
/// lifetime, and the head-less command-line entry points used by the build and verification
/// harnesses.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let arguments = LaunchArguments.current
    private(set) var coordinator: AppCoordinator?

    func applicationWillFinishLaunching(_ notification: Notification) {
        MovezFont.register()
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard arguments.isHeadless else {
            startCoordinator()
            return
        }
        if arguments.probeSignals {
            SignalProbe.run { exit($0) }
            return
        }
        if arguments.overlayHygiene {
            OverlayHygiene.run(outPath: arguments.out) { exit($0) }
            return
        }
        if arguments.panelHygiene {
            PanelHygiene.run { exit($0) }
            return
        }
        if let surface = arguments.snapshot {
            SnapshotRenderer.runCLI(surface: surface, out: arguments.out) { exit($0) }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [arguments] in
            if arguments.smoke {
                // Intentional stdout line: the build harness asserts on it.
                print("movez smoke ok")
                fflush(stdout)
            }
            exit(0)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Builds the coordinator from the bundled library and the user's saved state. A library that
    /// will not load is fatal and loud: an app that quietly serves no movements is worse than one
    /// that says why it cannot.
    private func startCoordinator() {
        do {
            let library = try LibraryLoader.loadBundled()
            let settings = SettingsStore()
            let historyStore = try? FileHistoryStore.historyFile()
            let snapshotStore = try? FileSnapshotStore.stateFile()
            let coordinator = AppCoordinator(
                library: library,
                settings: settings,
                history: historyStore.map { HistoryStore(store: $0) } ?? HistoryStore(),
                clock: SystemClock(),
                snapshotStore: snapshotStore
            )
            coordinator.attachSystemSignals()
            attachUI(to: coordinator, settings: settings)
            coordinator.start()
            self.coordinator = coordinator
        } catch {
            presentFatal(error)
        }
    }

    /// Registers the surfaces that turn scheduler effects into windows and sound.
    private func attachUI(to coordinator: AppCoordinator, settings: SettingsStore) {
        let chimes = AudioChimePlayer(isEnabled: { settings.soundsEnabled })
        let sink = CompositeEffectSink([
            OverlayEffectSink(controller: OverlayWindowController(), chimes: chimes),
            PanelEffectSink(controller: PanelWindowController())
        ])
        coordinator.register(sink: sink)
    }

    private func presentFatal(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "movez could not start"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }
}
