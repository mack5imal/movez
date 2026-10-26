import AppKit
import SwiftUI

/// The window the notice is read and accepted in.
///
/// One window, reused. At launch it is the only thing Movez shows, and closing it means Quit:
/// nothing runs until the notice is accepted. From Settings, closing it just closes it.
@MainActor
final class NoticeWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow?
    private var viewModel: NoticeViewModel?

    var isOpen: Bool { window?.isVisible ?? false }

    func show(_ viewModel: NoticeViewModel) {
        self.viewModel = viewModel
        let window = self.window ?? makeWindow()
        self.window = window
        window.contentView = NSHostingView(rootView: NoticeScreen(viewModel: viewModel))
        window.setContentSize(NoticeScreen.size)
        window.center()
        // An accessory app is never frontmost by default, so the window would open behind
        // whatever the user was in.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Brings an open window back to the front, from the menu's "Show notice".
    func bringForward() {
        guard let window, window.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if viewModel?.mode == .accept {
            viewModel?.quit()
            return false
        }
        return true
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NoticeScreen.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Health, safety and terms"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = Tokens.panelSolid.nsColor
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
