import AppKit
import SwiftUI

/// The one settings window.
///
/// An accessory app has no Dock icon to click back to, so opening settings has to bring movez
/// forward itself — and there is only ever one window, because two copies of the same settings
/// disagreeing with each other is a bug factory.
@MainActor
final class SettingsWindowController {
    let viewModel: SettingsViewModel
    private(set) var window: NSWindow?
    private var observer: NSObjectProtocol?
    /// Built on the first open. The inspector rebuilds itself on every coordinator publish, and
    /// a window nobody has opened has no business doing that from launch until quit.
    private let makeDebug: (() -> DebugViewModel)?
    private var debug: DebugViewModel?

    init(viewModel: SettingsViewModel, debug: (() -> DebugViewModel)? = nil) {
        self.viewModel = viewModel
        makeDebug = debug
        observer = NotificationCenter.default.addObserver(
            forName: .movezOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.show() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var isOpen: Bool { window?.isVisible ?? false }

    func show() {
        if debug == nil, let makeDebug {
            let viewModel = makeDebug()
            debug = viewModel
            self.viewModel.attach(debug: viewModel)
        }
        viewModel.syncLaunchAtLogin()
        let window = self.window ?? makeWindow()
        self.window = window
        window.center()
        // An accessory app is never frontmost by default, so the window would open behind
        // whatever the user was in.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsScreen.size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Movez settings"
        // The title is drawn in the app's own type inside the content view instead.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = Tokens.panelSolid.nsColor
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsScreen(viewModel: viewModel))
        window.setContentSize(SettingsScreen.size)
        return window
    }
}
