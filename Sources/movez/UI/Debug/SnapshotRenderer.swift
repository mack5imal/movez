import AppKit
import SwiftUI

/// Every surface `movez --snapshot` can render.
///
/// This is the evidence mechanism for the UI: each screen can be produced offscreen, at 2×, with
/// fixture data, and looked at — by a person or by a build — without waiting an hour for a break.
enum SnapshotSurface: String, CaseIterable {
    case gallery
    case overlayFull = "overlay-full"
    case overlayLeadIn = "overlay-leadin"
    case overlayPaused = "overlay-paused"
    case overlaySide = "overlay-side"
    case overlayLongName = "overlay-long-name"
    case overlayStrengthSet = "overlay-strength-set"
    case overlayStrengthWarmUp = "overlay-strength-warmup"
    case overlayStrengthLeadIn = "overlay-strength-leadin"
    case overlayStrengthRest = "overlay-strength-rest"
    case overlayStrengthCoolDown = "overlay-strength-cooldown"
    case overlayStrengthSide = "overlay-strength-side"
    case overlayStrengthHold = "overlay-strength-hold"
    case overlayStrengthPaused = "overlay-strength-paused"
    case overlayStrengthReducedMotion = "overlay-strength-reduced-motion"
    case overlayStrengthLongDose = "overlay-strength-long-dose"
    case overlayStrengthRelaxed = "overlay-strength-relaxed"
    case overlayEndRange = "overlay-endrange"
    case overlayEndRangeLeadIn = "overlay-endrange-leadin"
    case overlayEndRangeSide = "overlay-endrange-side"
    case overlayEndRangePaused = "overlay-endrange-paused"
    case headsUp = "headsup"
    case headsUpDeferred = "headsup-deferred"
    case microCountIn = "micro-countin"
    case microFirstLeadIn = "micro-first-leadin"
    case microRunning = "micro-running"
    case microLeadIn = "micro-leadin"
    case microSecond = "micro-second"
    case microSide = "micro-side"
    case headsUpStrength = "headsup-strength"
    case headsUpStrengthEndRange = "headsup-strength-endrange"
    case headsUpStrengthDeferred = "headsup-strength-deferred"
    case microStrengthCountIn = "micro-strength-countin"
    case microStrengthLeadIn = "micro-strength-leadin"
    case microStrengthRunning = "micro-strength-running"
    case microStrengthSide = "micro-strength-side"
    case microStrengthSecond = "micro-strength-second"
    case microStrengthLongText = "micro-strength-long-text"
    case toast
    case menuSitting = "menu-sitting"
    case menuPaused = "menu-paused"
    case menuOffHours = "menu-offhours"
    case menuAway = "menu-away"
    case menuStrength = "menu-strength"
    case menuStrengthPaused = "menu-strength-paused"
    case menuStrengthOffHours = "menu-strength-offhours"
    case menuStrengthAway = "menu-strength-away"
    case menuIcon = "menu-icon"
    case menuIconStrength = "menu-icon-strength"
    case menuIcons = "menu-icons"
    case menuIconsPaused = "menu-icons-paused"
    case menuIconsOffHours = "menu-icons-offhours"
    case modeBadges = "mode-badges"
    case menuNotice = "menu-notice"
    case settings
    case settingsHours = "settings-hours"
    case settingsLibrary = "settings-library"
    case settingsExceptions = "settings-exceptions"
    case settingsCustom = "settings-custom"
    case settingsStrength = "settings-strength"
    case settingsStrengthLibrary = "settings-strength-library"
    case settingsStrengthSetup = "settings-strength-setup"
    case debug
    case notice
    case noticeEnd = "notice-end"
    case noticeRead = "notice-read"

    /// A 1440×900 display, which is what the handoff's overlay screenshots are drawn on.
    static let screen = CGSize(width: 1440, height: 900)
    /// Enough of a desktop around a floating panel to show where on it the panel sits.
    static let panelCanvas = CGSize(width: 680, height: 420)
    static let toastCanvas = CGSize(width: 680, height: 320)
    /// Enough desktop to show the menu hanging from its bar.
    static let menuCanvas = CGSize(width: 560, height: 460)

    /// The point size the surface is rendered at.
    var size: CGSize {
        switch self {
        case .gallery: return CGSize(width: 1400, height: 2900)
        case .headsUp, .headsUpDeferred, .microCountIn, .microFirstLeadIn, .microRunning, .microLeadIn, .microSecond, .microSide,
             .headsUpStrength, .headsUpStrengthEndRange, .headsUpStrengthDeferred, .microStrengthCountIn,
             .microStrengthLeadIn, .microStrengthRunning, .microStrengthSide, .microStrengthSecond,
             .microStrengthLongText:
            return Self.panelCanvas
        case .toast: return Self.toastCanvas
        case .menuSitting, .menuPaused, .menuOffHours, .menuAway, .menuNotice,
             .menuStrength, .menuStrengthPaused, .menuStrengthOffHours, .menuStrengthAway:
            return Self.menuCanvas
        case .menuIcon, .menuIconStrength: return CGSize(width: 880, height: 260)
        case .menuIcons, .menuIconsPaused, .menuIconsOffHours: return MenuIconSheet.size
        case .modeBadges: return ModeBadgeSheet.size
        case .settings, .settingsHours, .settingsLibrary, .settingsExceptions, .settingsCustom,
             .settingsStrength, .settingsStrengthLibrary, .settingsStrengthSetup:
            return SettingsScreen.size
        case .debug:
            return CGSize(width: SettingsScreen.size.width, height: 1_500)
        case .notice, .noticeEnd, .noticeRead:
            return NoticeScreen.size
        case .overlayFull, .overlayLeadIn, .overlayPaused, .overlaySide, .overlayLongName:
            return Self.screen
        case .overlayStrengthSet, .overlayStrengthWarmUp, .overlayStrengthLeadIn, .overlayStrengthRest,
             .overlayStrengthCoolDown, .overlayStrengthSide, .overlayStrengthHold, .overlayStrengthPaused,
             .overlayStrengthReducedMotion, .overlayStrengthLongDose, .overlayStrengthRelaxed, .overlayEndRange, .overlayEndRangeLeadIn,
             .overlayEndRangeSide, .overlayEndRangePaused:
            return Self.screen
        }
    }

    /// The colour behind the surface, so panels are legible against something.
    var backdrop: MovezColor { Tokens.panelSolid }
}

enum SnapshotError: LocalizedError {
    case unknownSurface(String)
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownSurface(let name):
            let known = SnapshotSurface.allCases.map(\.rawValue).joined(separator: ", ")
            return "Unknown surface \"\(name)\". Known surfaces: \(known)"
        case .renderFailed(let reason):
            return "Could not render the surface: \(reason)"
        }
    }
}

/// Renders a SwiftUI surface to a PNG without ever showing it to anyone.
@MainActor
enum SnapshotRenderer {
    /// Snapshots are written at 2× so text can actually be read in the PNG.
    static let scale: CGFloat = 2

    static func view(for surface: SnapshotSurface) -> AnyView {
        strengthPanelView(for: surface) ?? panelView(for: surface) ?? menuView(for: surface)
            ?? settingsView(for: surface) ?? noticeView(for: surface)
            ?? strengthOverlayView(for: surface) ?? overlayView(for: surface)
    }

    /// The strength and end-range break, each state from `StrengthSnapshotFixtures`.
    private static func strengthOverlayView(for surface: SnapshotSurface) -> AnyView? {
        guard let fixture = strengthOverlayFixtures[surface] else { return nil }
        return AnyView(StrengthOverlaySnapshot(state: fixture()))
    }

    private static let strengthOverlayFixtures: [SnapshotSurface: () -> StrengthOverlayState] = [
        .overlayStrengthSet: SnapshotFixtures.strengthSet,
        .overlayStrengthWarmUp: SnapshotFixtures.strengthWarmUp,
        .overlayStrengthLeadIn: SnapshotFixtures.strengthLeadIn,
        .overlayStrengthRest: SnapshotFixtures.strengthRest,
        .overlayStrengthCoolDown: SnapshotFixtures.strengthCoolDown,
        .overlayStrengthSide: SnapshotFixtures.strengthSide,
        .overlayStrengthHold: SnapshotFixtures.strengthHold,
        .overlayStrengthPaused: SnapshotFixtures.strengthPaused,
        .overlayStrengthReducedMotion: SnapshotFixtures.strengthReducedMotion,
        .overlayStrengthLongDose: SnapshotFixtures.strengthLongDose,
        .overlayStrengthRelaxed: SnapshotFixtures.strengthRelaxed,
        .overlayEndRange: SnapshotFixtures.endRange,
        .overlayEndRangeLeadIn: SnapshotFixtures.endRangeLeadIn,
        .overlayEndRangeSide: SnapshotFixtures.endRangeSide,
        .overlayEndRangePaused: SnapshotFixtures.endRangePaused
    ]

    private static let settingsFixtures: [SnapshotSurface: () -> SettingsViewModel?] = [
        .settings: { SnapshotFixtures.settingsViewModel() },
        .settingsHours: { SnapshotFixtures.settingsViewModel(sheet: .workingHours) },
        .settingsLibrary: { SnapshotFixtures.settingsViewModel(sheet: .library, search: "hip") },
        .settingsExceptions: { SnapshotFixtures.settingsViewModel(sheet: .exceptions) },
        .settingsCustom: { SnapshotFixtures.settingsViewModel(preset: .custom) },
        .settingsStrength: { SnapshotFixtures.strengthSettingsViewModel() },
        .settingsStrengthLibrary: { SnapshotFixtures.strengthSettingsViewModel(sheet: .modeLibrary) },
        .settingsStrengthSetup: { SnapshotFixtures.strengthSetupViewModel() },
        .debug: { SnapshotFixtures.debugSettingsViewModel() }
    ]

    /// The settings window, the sheets that open over it, and its Strength states.
    private static func settingsView(for surface: SnapshotSurface) -> AnyView? {
        guard let fixture = settingsFixtures[surface] else { return nil }
        guard let viewModel = fixture() else {
            return AnyView(MovezText("The bundled movement library did not load.", MovezType.panelTitle))
        }
        return AnyView(SettingsScreen(viewModel: viewModel, height: surface.size.height))
    }

    /// The health and safety notice: waiting to be accepted, scrolled to its end, and reopened
    /// from Settings.
    private static func noticeView(for surface: SnapshotSurface) -> AnyView? {
        let viewModel: NoticeViewModel?
        switch surface {
        case .notice: viewModel = SnapshotFixtures.noticeViewModel(mode: .accept)
        case .noticeEnd: viewModel = SnapshotFixtures.noticeViewModel(mode: .accept, reachedEnd: true)
        case .noticeRead: viewModel = SnapshotFixtures.noticeViewModel(mode: .read)
        default: return nil
        }
        guard let viewModel else {
            return AnyView(MovezText("The bundled notice did not load.", MovezType.panelTitle))
        }
        return AnyView(NoticeScreen(viewModel: viewModel))
    }

    /// The gallery and the floating panels.
    private static func panelView(for surface: SnapshotSurface) -> AnyView? {
        switch surface {
        case .gallery:
            return AnyView(GalleryView())
        case .headsUp:
            return AnyView(PanelSnapshot(viewModel: SnapshotFixtures.headsUp()))
        case .headsUpDeferred:
            return AnyView(PanelSnapshot(viewModel: SnapshotFixtures.headsUp(deferred: true)))
        case .toast:
            return AnyView(PanelSnapshot(viewModel: SnapshotFixtures.awayToast(), placement: .topRight))
        default:
            return microView(for: surface)
        }
    }

    /// The strength heads-up and micro-break panels, each state from `StrengthPanelFixtures`.
    private static func strengthPanelView(for surface: SnapshotSurface) -> AnyView? {
        guard let fixture = strengthPanelFixtures[surface] else { return nil }
        return AnyView(PanelSnapshot(viewModel: fixture()))
    }

    private static let strengthPanelFixtures: [SnapshotSurface: () -> PanelViewModel] = [
        .headsUpStrength: { SnapshotFixtures.strengthHeadsUp() },
        .headsUpStrengthEndRange: { SnapshotFixtures.strengthHeadsUp(announced: .endRange) },
        .headsUpStrengthDeferred: { SnapshotFixtures.strengthHeadsUp(deferred: true) },
        .microStrengthCountIn: { SnapshotFixtures.strengthMicroCountIn() },
        .microStrengthLeadIn: { SnapshotFixtures.strengthMicroRunning(elapsed: SnapshotFixtures.microFirstLeadInElapsed) },
        .microStrengthRunning: { SnapshotFixtures.strengthMicroRunning() },
        .microStrengthSide: {
            SnapshotFixtures.strengthMicroRunning(elapsed: SnapshotFixtures.microSideElapsed, perSide: true)
        },
        .microStrengthSecond: { SnapshotFixtures.strengthMicroRunning(elapsed: SnapshotFixtures.microLeadInElapsed) },
        .microStrengthLongText: { SnapshotFixtures.strengthMicroLongText() }
    ]

    /// The micro-break panel at each of its moments.
    private static func microView(for surface: SnapshotSurface) -> AnyView? {
        switch surface {
        case .microCountIn:
            return AnyView(PanelSnapshot(viewModel: SnapshotFixtures.microCountIn()))
        case .microFirstLeadIn:
            return AnyView(PanelSnapshot(viewModel: SnapshotFixtures.microRunning(elapsed: SnapshotFixtures.microFirstLeadInElapsed)))
        case .microRunning:
            return AnyView(PanelSnapshot(viewModel: SnapshotFixtures.microRunning()))
        case .microLeadIn:
            return AnyView(PanelSnapshot(viewModel: SnapshotFixtures.microRunning(elapsed: SnapshotFixtures.microLeadInElapsed)))
        case .microSecond:
            return AnyView(PanelSnapshot(viewModel: SnapshotFixtures.microRunning(elapsed: SnapshotFixtures.microSecondElapsed)))
        case .microSide:
            return AnyView(PanelSnapshot(viewModel: SnapshotFixtures.microRunning(
                elapsed: SnapshotFixtures.microSideElapsed,
                micro: MicroPanelBreak(SnapshotFixtures.microSideBreak())
            )))
        default:
            return nil
        }
    }

    /// The menu-bar dropdown in each of its three moods, and the glyph itself.
    private static func menuView(for surface: SnapshotSurface) -> AnyView? {
        switch surface {
        case .menuSitting:
            return AnyView(MenuSnapshot(state: SnapshotFixtures.menuSitting()))
        case .menuPaused:
            return AnyView(MenuSnapshot(state: SnapshotFixtures.menuPaused()))
        case .menuOffHours:
            return AnyView(MenuSnapshot(state: SnapshotFixtures.menuOffHours()))
        case .menuAway:
            return AnyView(MenuSnapshot(state: SnapshotFixtures.menuAway()))
        case .menuNotice:
            return AnyView(MenuSnapshot(state: SnapshotFixtures.menuOffHours(), pendingNotice: true))
        case .menuStrength:
            return AnyView(MenuSnapshot(state: SnapshotFixtures.menuStrength()))
        case .menuStrengthPaused:
            return AnyView(MenuSnapshot(state: SnapshotFixtures.menuStrengthPaused()))
        case .menuStrengthOffHours:
            return AnyView(MenuSnapshot(state: SnapshotFixtures.menuStrengthOffHours()))
        case .menuStrengthAway:
            return AnyView(MenuSnapshot(state: SnapshotFixtures.menuStrengthAway()))
        default:
            return modeSheetView(for: surface)
        }
    }

    /// The menu-bar icon on its own, and the sheets that draw every mode's icon and badge.
    private static func modeSheetView(for surface: SnapshotSurface) -> AnyView? {
        switch surface {
        case .menuIcon:
            return AnyView(MenuIconStrip())
        case .menuIconStrength:
            return AnyView(MenuIconStrip(definition: SnapshotFixtures.strengthMode))
        case .menuIcons:
            return AnyView(MenuIconSheet(mode: .sitting))
        case .menuIconsPaused:
            return AnyView(MenuIconSheet(mode: .paused))
        case .menuIconsOffHours:
            return AnyView(MenuIconSheet(mode: .offHours))
        case .modeBadges:
            return AnyView(ModeBadgeSheet())
        default:
            return nil
        }
    }

    private static func overlayView(for surface: SnapshotSurface) -> AnyView {
        switch surface {
        case .overlayLeadIn:
            return AnyView(OverlaySnapshot(state: SnapshotFixtures.overlayLeadIn()))
        case .overlayPaused:
            return AnyView(OverlaySnapshot(state: SnapshotFixtures.overlayPaused()))
        case .overlaySide:
            return AnyView(OverlaySnapshot(state: SnapshotFixtures.overlaySide()))
        case .overlayLongName:
            return AnyView(OverlaySnapshot(state: SnapshotFixtures.overlayLongName()))
        default:
            return AnyView(OverlaySnapshot(state: SnapshotFixtures.overlayRunning()))
        }
    }

    /// Renders one surface and writes it as a PNG.
    static func render(_ surface: SnapshotSurface, to url: URL) throws {
        let size = surface.size
        let content = ZStack {
            surface.backdrop.color
            view(for: surface)
        }
        .frame(width: size.width, height: size.height)

        let hosting = NSHostingView(rootView: content)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        // SwiftUI needs a window before it will lay text out at its real metrics. The window is
        // parked far offscreen so nothing flashes on a real display.
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -30_000, y: -30_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        pumpRunLoop(seconds: 0.35)

        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw SnapshotError.renderFailed("could not allocate a \(Int(size.width * scale)) px bitmap")
        }
        bitmap.size = size

        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.renderFailed("could not encode PNG")
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    /// Lets SwiftUI settle before the pixels are taken.
    static func pumpRunLoop(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// The `--snapshot` command-line entry point.
    ///
    /// Cleanliness note: the prints below are the output of a command-line tool, not logging.
    static func runCLI(surface name: String, out path: String?, completion: @escaping (Int32) -> Void) {
        MovezFont.register()

        if name == "list" {
            for surface in SnapshotSurface.allCases { print(surface.rawValue) }
            fflush(stdout)
            return completion(0)
        }

        let destination = path ?? "build/snapshots"
        do {
            if name == "all" {
                for surface in SnapshotSurface.allCases {
                    let url = URL(fileURLWithPath: destination).appendingPathComponent("\(surface.rawValue).png")
                    try render(surface, to: url)
                    print(url.path)
                }
            } else {
                guard let surface = SnapshotSurface(rawValue: name) else {
                    throw SnapshotError.unknownSurface(name)
                }
                let url = URL(fileURLWithPath: destination)
                let target = url.pathExtension.lowercased() == "png"
                    ? url
                    : url.appendingPathComponent("\(surface.rawValue).png")
                try render(surface, to: target)
                print(target.path)
            }
            fflush(stdout)
            completion(0)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            completion(2)
        }
    }
}
