import AppKit
import os

/// How movez tells the user it cannot start.
///
/// Behind a protocol because the only honest response to a missing movement library is an alert
/// and a quit, and neither is something a test can survive.
@MainActor
protocol FatalPresenter: AnyObject {
    func presentFatal(_ error: Error)
}

/// The real one: an alert, and then the app goes away.
@MainActor
final class AlertFatalPresenter: FatalPresenter {
    func presentFatal(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Movez could not start"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }
}

/// The one the tests assert against.
@MainActor
final class RecordingFatalPresenter: FatalPresenter {
    private(set) var errors: [Error] = []

    func presentFatal(_ error: Error) {
        errors.append(error)
    }
}

/// The decisions made once, at launch, before anything else exists.
@MainActor
enum Launch {
    /// The movement library is the app's content: without it there is nothing to serve, so a
    /// failure here is fatal and loud rather than an app that quietly offers no movements.
    static func loadLibrary(
        using load: () throws -> MovementLibrary = LibraryLoader.loadBundled,
        presenter: FatalPresenter
    ) -> MovementLibrary? {
        do {
            return try load()
        } catch {
            presenter.presentFatal(error)
            return nil
        }
    }
}

/// The app's one logger. Used where something went wrong that the user cannot see and must not
/// be crashed by — a state file that will not parse, most of all.
enum MovezLog {
    static let store = Logger(subsystem: "com.kylemack.movez", category: "store")
    /// Every scheduler transition, so an overnight sleep bug can be read back days later.
    static let scheduler = Logger(subsystem: "com.kylemack.movez", category: "scheduler")
}
