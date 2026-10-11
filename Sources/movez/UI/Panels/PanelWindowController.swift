import AppKit
import SwiftUI

/// Puts the small panels on screen and — the whole point — never takes focus while doing it.
///
/// A heads-up panel that stole the keyboard would put a stray character into whatever the user
/// was typing, which is the fastest way to get an app like this uninstalled. Everything here is
/// in service of that: a non-activating panel, at status-bar level, that never becomes key
/// unless a control genuinely needs it.
@MainActor
final class PanelWindowController {
    /// How long a panel takes to fade in or out.
    static let fade: TimeInterval = 0.16
    /// The gap between the menu bar and the top of a panel.
    static let topInset: CGFloat = 12
    /// The toast's inset from the right edge of the working area. It sits `topInset` below the
    /// menu bar, level with the panels, in the top-right corner.
    static let toastInset: CGFloat = 20
    /// Room around the shell for its drop shadow, which would otherwise clip at the window edge.
    static let shadowMargin: CGFloat = 44
    /// Fast enough that the ring drains and the toast's hairline shrinks smoothly.
    static let tickInterval: TimeInterval = 0.1

    private(set) var panelWindow: NSPanel?
    private(set) var toastWindow: NSPanel?
    private(set) var panelModel: PanelViewModel?
    private(set) var toastModel: PanelViewModel?
    private var panelScreen: NSScreen?
    private var toastScreen: NSScreen?
    private var timer: DispatchSourceTimer?

    var isShowingPanel: Bool { panelWindow != nil }
    var isShowingToast: Bool { toastWindow != nil }

    // MARK: - Presenting

    /// The heads-up panel, or the micro-break in either of its moments.
    func present(panel model: PanelViewModel) {
        hidePanel(animated: false)
        panelModel = model
        model.actions.dismiss = { [weak self] in self?.hidePanel() }

        let screen = Self.activeScreen()
        panelScreen = screen
        let hosting = NSHostingView(rootView: PanelHost(viewModel: model).padding(Self.shadowMargin))
        let window = makeWindow(hosting: hosting)
        panelWindow = window
        layoutPanel()
        fadeIn(window)
        startTicking()
    }

    func present(toast model: PanelViewModel) {
        hideToast(animated: false)
        toastModel = model
        model.actions.dismiss = { [weak self] in self?.hideToast() }

        let screen = Self.activeScreen()
        toastScreen = screen
        let hosting = NSHostingView(rootView: AwayToastView(viewModel: model).padding(Self.shadowMargin))
        let window = makeWindow(hosting: hosting)
        toastWindow = window
        layoutToast()
        fadeIn(window)
        startTicking()
    }

    private func makeWindow(hosting: NSView) -> NSPanel {
        let window = PanelWindow(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        // Above ordinary windows, below the break overlay's shielding level.
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.isFloatingPanel = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return window
    }

    // MARK: - Placement

    /// The screen the user is looking at, which is the one the pointer is on.
    static func activeScreen() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    /// Top-centre of the working area, clear of the menu bar so the movez icon stays reachable.
    ///
    /// The working area rather than the whole display: `visibleFrame` is what excludes the menu
    /// bar, and 12 pt below *that* is what the handoff means by 12 px below the menu bar.
    static func panelFrame(shell: CGSize, visible: NSRect) -> NSRect {
        NSRect(
            x: (visible.midX - shell.width / 2).rounded(),
            y: (visible.maxY - topInset - shell.height).rounded(),
            width: shell.width,
            height: shell.height
        )
    }

    static func toastFrame(shell: CGSize, visible: NSRect) -> NSRect {
        NSRect(
            x: (visible.maxX - toastInset - shell.width).rounded(),
            y: (visible.maxY - topInset - shell.height).rounded(),
            width: shell.width,
            height: shell.height
        )
    }

    /// The window is the shell plus a margin for the shadow, so the frame the design cares about
    /// is the inset one.
    static func windowFrame(forShell shell: NSRect) -> NSRect {
        shell.insetBy(dx: -shadowMargin, dy: -shadowMargin)
    }

    /// The shell's own frame on screen — what `--panel-hygiene` reports and the design specifies.
    var panelShellFrame: NSRect? {
        panelWindow.map { $0.frame.insetBy(dx: Self.shadowMargin, dy: Self.shadowMargin) }
    }

    var toastShellFrame: NSRect? {
        toastWindow.map { $0.frame.insetBy(dx: Self.shadowMargin, dy: Self.shadowMargin) }
    }

    /// Re-measures and re-places the panel. Called every tick, because the body text — and so the
    /// height — changes as the count-in becomes the movement.
    private func layoutPanel() {
        guard let window = panelWindow, let screen = panelScreen, let hosting = window.contentView else { return }
        let fitting = hosting.fittingSize
        let shell = CGSize(
            width: fitting.width - Self.shadowMargin * 2,
            height: fitting.height - Self.shadowMargin * 2
        )
        guard shell.width > 0, shell.height > 0 else { return }
        let frame = Self.windowFrame(forShell: Self.panelFrame(shell: shell, visible: screen.visibleFrame))
        if window.frame != frame { window.setFrame(frame, display: true) }
    }

    private func layoutToast() {
        guard let window = toastWindow, let screen = toastScreen, let hosting = window.contentView else { return }
        let fitting = hosting.fittingSize
        let shell = CGSize(
            width: fitting.width - Self.shadowMargin * 2,
            height: fitting.height - Self.shadowMargin * 2
        )
        guard shell.width > 0, shell.height > 0 else { return }
        let frame = Self.windowFrame(forShell: Self.toastFrame(shell: shell, visible: screen.visibleFrame))
        if window.frame != frame { window.setFrame(frame, display: true) }
    }

    // MARK: - Ticking

    private func startTicking() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.tickInterval, repeating: Self.tickInterval)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        panelModel?.tick()
        toastModel?.tick()
        layoutPanel()
        layoutToast()
        if panelModel == nil, toastModel == nil { stopTicking() }
    }

    private func stopTicking() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Dismissing

    func hidePanel(animated: Bool = true) {
        let window = panelWindow
        panelWindow = nil
        panelModel = nil
        panelScreen = nil
        close(window, animated: animated)
        if toastModel == nil { stopTicking() }
    }

    func hideToast(animated: Bool = true) {
        let window = toastWindow
        toastWindow = nil
        toastModel = nil
        toastScreen = nil
        close(window, animated: animated)
        if panelModel == nil { stopTicking() }
    }

    func hideAll(animated: Bool = false) {
        hidePanel(animated: animated)
        hideToast(animated: animated)
    }

    private func fadeIn(_ window: NSPanel) {
        window.alphaValue = 0
        // Ordering "regardless" is what shows a window from an app that is not frontmost — and
        // this app is deliberately never frontmost.
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fade
            window.animator().alphaValue = 1
        }
    }

    private func close(_ window: NSPanel?, animated: Bool) {
        guard let window else { return }
        guard animated else { return teardown(window) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fade
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { self.teardown(window) }
        }
    }

    private func teardown(_ window: NSPanel) {
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }

    // MARK: - Introspection, for the hygiene harness

    func isNonActivating(_ window: NSPanel?) -> Bool {
        guard let window else { return false }
        return window.styleMask.contains(.nonactivatingPanel) && !NSApp.isActive
    }
}

/// A panel that goes exactly where it is put.
///
/// AppKit keeps ordinary windows from reaching up under the menu bar, and will quietly slide one
/// down until it fits. A panel that carries a transparent margin for its shadow trips that rule
/// and lands a shadow's width too low, so the constraint is declined here and the placement in
/// `PanelWindowController` — which already works in `visibleFrame` — is the only one that
/// applies.
final class PanelWindow: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Whichever panel the view model is currently being: the heads-up minute, or the micro-break.
struct PanelHost: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        if viewModel.phase == .headsUp {
            HeadsUpView(viewModel: viewModel)
        } else {
            MicroBreakView(viewModel: viewModel)
        }
    }
}
