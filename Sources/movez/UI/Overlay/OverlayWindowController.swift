import AppKit
import SwiftUI

/// Puts the break on screen and — just as importantly — takes it off again.
///
/// Every complaint this category of app collects is in here: an overlay that survives sleep, one
/// that steals keystrokes into the app underneath, one that never gives focus back, one that
/// misses the second display. Each has a counterpart below.
@MainActor
final class OverlayWindowController {
    /// The break on screen: a movement routine, or a strength or end-range session.
    private enum Session {
        case routine(OverlayViewModel)
        case timeline(StrengthOverlayViewModel)
    }

    private(set) var windows: [NSWindow] = []
    private var session: Session?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var screenObserver: NSObjectProtocol?
    private var tickTimer: DispatchSourceTimer?
    /// Holds the display awake for as long as a break is on screen. The user is meant to step
    /// back from the keyboard, so the idle display-sleep timer keeps counting through a break,
    /// and on a laptop on battery it used to put the screen to sleep a minute or two in, which
    /// the scheduler takes for a closed lid and ends the break.
    private var displayAwake: NSObjectProtocol?
    /// Bumped on every presentation. A fade-out that completes after the next break has already
    /// opened would otherwise hand focus back to the app underneath — the exact keystroke leak
    /// this class exists to prevent.
    private var presentation = 0

    /// How long the dim takes to fade when a break ends well.
    static let dismissFade: TimeInterval = 0.3

    var viewModel: OverlayViewModel? {
        if case let .routine(viewModel) = session { return viewModel }
        return nil
    }

    var isPresenting: Bool { !windows.isEmpty }
    var windowCount: Int { windows.count }
    var hasKeyMonitor: Bool { keyMonitor != nil }
    var holdsDisplayAwake: Bool { displayAwake != nil }

    // MARK: - Presenting

    func present(_ viewModel: OverlayViewModel) {
        present(.routine(viewModel))
    }

    /// A strength or end-range break: the same windows, focus handling and keyboard capture, with
    /// the strength card in them.
    func present(_ viewModel: StrengthOverlayViewModel) {
        present(.timeline(viewModel))
    }

    private func present(_ session: Session) {
        dismiss(animated: false)
        presentation += 1
        self.session = session
        previousApp = NSWorkspace.shared.frontmostApplication

        build()
        installKeyMonitor()
        observeScreenChanges()
        startTicking()
        keepDisplayAwake()
    }

    private func keepDisplayAwake() {
        guard displayAwake == nil else { return }
        displayAwake = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled],
            reason: "A movement break is on screen"
        )
    }

    private func letDisplaySleep() {
        guard let displayAwake else { return }
        ProcessInfo.processInfo.endActivity(displayAwake)
        self.displayAwake = nil
    }

    private func build() {
        // Activate before the windows exist. An accessory app that asks for activation *after*
        // ordering a borderless window in is refused, and a window in an inactive app can never
        // be key — which is what lets keystrokes fall through to whatever is underneath.
        activateApp()

        // Every display shows the whole break, all driven by the one view model, so a user who
        // looks at either screen can follow it and use its buttons. The display with the cursor
        // only decides which window is key; the key monitor hears the keyboard whichever it is.
        let cursorScreen = PanelWindowController.activeScreen()
        var activeWindow: NSWindow?
        for screen in NSScreen.screens {
            let window = makeWindow(on: screen)
            windows.append(window)
            window.orderFrontRegardless()
            if screen == cursorScreen { activeWindow = window }
        }

        guard let activeWindow else { return }
        activeWindow.makeKeyAndOrderFront(nil)
        // Activation is asynchronous; ask once more on the next turn of the run loop.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.windows.contains(activeWindow) else { return }
            self.activateApp()
            activeWindow.makeKey()
        }
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    private func makeWindow(on screen: NSScreen) -> NSWindow {
        let window = OverlayWindow(
            contentRect: dimFrame(for: screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.becomesKeyOnlyIfNeeded = false
        window.worksWhenModal = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        // Above fullscreen apps, on every Space, and it does not follow the user between Spaces.
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = NSHostingView(rootView: content())
        window.setFrame(dimFrame(for: screen), display: true)
        return window
    }

    @ViewBuilder
    private func content() -> some View {
        switch session {
        case let .routine(viewModel):
            OverlayScreen(viewModel: viewModel)
        case let .timeline(viewModel):
            StrengthOverlayScreen(viewModel: viewModel)
        case nil:
            Color.clear
        }
    }

    /// The dim covers the screen but stops below the menu bar, so the movez icon stays reachable
    /// during a break — the research is explicit that a break must never trap the user.
    private func dimFrame(for screen: NSScreen) -> NSRect {
        let frame = screen.frame
        let menuBarHeight = max(0, frame.maxY - screen.visibleFrame.maxY)
        return NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - menuBarHeight)
    }

    // MARK: - Keyboard

    /// Every key is swallowed, so a break never types into whatever was underneath it; what the
    /// few it acts on do is `OverlayKeyMap`'s. Escape deliberately does nothing: snoozing should be
    /// easier than skipping, and neither should happen by reflex.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPresenting else { return event }
            // A held key repeats. Swallowed like every other key, but acted on once: holding
            // Return used to walk through the whole break and record every block as done.
            if event.isARepeat { return nil }
            switch self.session {
            case let .routine(viewModel):
                switch OverlayKeyMap.routine(event.keyCode) {
                case .next: viewModel.next()
                case .togglePause: viewModel.togglePause()
                case .disc, .ignored: break
                }
            case let .timeline(viewModel):
                viewModel.handleKey(event.keyCode)
            case nil:
                break
            }
            return nil
        }
    }

    // MARK: - Screens

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildForScreenChange() }
        }
    }

    /// A display plugged in or unplugged mid-break gets its own copy of the break rather than a gap.
    ///
    /// Keyed on the session rather than on the windows: with every display gone there are no
    /// windows, and the break must come back when a display does.
    private func rebuildForScreenChange() {
        guard session != nil else { return }
        closeWindows()
        build()
    }

    // MARK: - Ticking

    private func startTicking() {
        tickTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            switch self?.session {
            case let .routine(viewModel): viewModel.tick()
            case let .timeline(viewModel): viewModel.tick()
            case nil: break
            }
        }
        timer.resume()
        tickTimer = timer
    }

    // MARK: - Dismissing

    func dismiss(animated: Bool = true) {
        tickTimer?.cancel()
        tickTimer = nil
        letDisplaySleep()

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        guard !windows.isEmpty else {
            session = nil
            return
        }

        let generation = presentation
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.dismissFade
                for window in windows { window.animator().alphaValue = 0 }
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.finishDismiss(generation: generation) }
            }
        } else {
            finishDismiss(generation: generation)
        }
    }

    private func finishDismiss(generation: Int) {
        // A newer break took over while this one was fading; it owns the windows and the focus.
        guard generation == presentation else { return }
        closeWindows()
        session = nil
        // Give focus back to whatever the user was in.
        previousApp?.activate()
        previousApp = nil
        NSApp.deactivate()
    }

    private func closeWindows() {
        for window in windows {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

    // MARK: - Introspection, for the hygiene harness

    var collectionBehaviourNames: [String] {
        guard let behavior = windows.first?.collectionBehavior else { return [] }
        var names: [String] = []
        if behavior.contains(.canJoinAllSpaces) { names.append("canJoinAllSpaces") }
        if behavior.contains(.fullScreenAuxiliary) { names.append("fullScreenAuxiliary") }
        if behavior.contains(.stationary) { names.append("stationary") }
        return names
    }

    var windowLevel: Int { windows.first?.level.rawValue ?? 0 }
    var hasKeyWindow: Bool { windows.contains { $0.isKeyWindow } }
    var windowsCanBecomeKey: Bool { windows.contains(where: \.canBecomeKey) }
    var visibleWindowCount: Int { windows.filter(\.isVisible).count }
}

/// What a key does during a break, kept apart from the event monitor so a test can ask.
enum OverlayKeyAction: Equatable {
    /// A movement break's Next.
    case next
    /// A movement break's Space.
    case togglePause
    /// The disc of a strength or end-range break: Done on a set, Next elsewhere.
    case disc
    /// Swallowed and otherwise ignored.
    case ignored
}

/// The keys a break listens to. On a movement break → and Return advance and Space pauses; on a
/// strength break the disc is Done, so Space presses it, and → and Return press it too. A strength
/// break pauses only from its Pause button, so a Space meant as Done never parks the break.
enum OverlayKeyMap {
    static let space: UInt16 = 49
    static let rightArrow: UInt16 = 124
    static let returnKey: UInt16 = 36
    static let enter: UInt16 = 76

    static func routine(_ keyCode: UInt16) -> OverlayKeyAction {
        switch keyCode {
        case rightArrow, returnKey, enter: return .next
        case space: return .togglePause
        default: return .ignored
        }
    }

    static func timeline(_ keyCode: UInt16) -> OverlayKeyAction {
        switch keyCode {
        case space, rightArrow, returnKey, enter: return .disc
        default: return .ignored
        }
    }
}

/// One screen's worth of overlay: the dim, and the card if this is the screen the user is on.
struct OverlayScreen: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        ZStack {
            VisualEffectBackdrop()
            Tokens.dim.color

            OverlayView(state: viewModel.state, actions: actions, animated: viewModel.animationsEnabled)
                .modifier(FitsOverlayCard())
                .transition(.opacity)
        }
        .ignoresSafeArea()
    }

    private var actions: OverlayActions {
        OverlayActions(
            next: viewModel.next,
            snooze: viewModel.snooze,
            done: viewModel.done,
            skip: viewModel.skip,
            pause: viewModel.togglePause,
            chooseSide: viewModel.choose(side:)
        )
    }
}

/// The blur behind the dim. Offscreen snapshots draw a flat dim instead, because a backdrop blur
/// cannot be captured faithfully without a real compositor behind it.
struct VisualEffectBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// A borderless window cannot become key by default, and a break overlay that is not key cannot
/// swallow the keystrokes that would otherwise land in whatever is underneath it.
///
/// It is a **non-activating panel** rather than a plain window: macOS 14 will not grant an
/// accessory agent app activation it did not ask for through a user gesture, so an overlay that
/// depended on `NSApp.activate` to take keyboard focus would silently leak every keystroke into
/// the app underneath. A non-activating panel takes key status without needing the app to be
/// frontmost at all.
final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
