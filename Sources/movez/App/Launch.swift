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

/// The stores a launch opened, and what went wrong if they could not be.
struct LaunchStores {
    var history: HistoryStore
    var snapshotStore: SnapshotStore?
    /// What the menu says when nothing can be saved; nil when the stores opened.
    var problem: String?
}

/// The decisions made once, at launch, before anything else exists.
@MainActor
enum Launch {
    /// The sentence the menu shows when the data folder cannot be opened.
    static let storeProblem = "Movez can't save to its folder in Application Support, so nothing will be kept after quitting."

    /// Opens the history and state files in Movez's folder inside `base`. A folder that cannot be
    /// made (a plain file named `movez` in the way, or the wrong permissions) leaves the app
    /// running from memory, and says so: before, it ran a whole session that was lost at quit and
    /// logged nothing (APP-3).
    static func openStores(
        base: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    ) -> LaunchStores {
        do {
            let directory = try FileSnapshotStore.applicationSupportDirectory(base: base)
            let history = FileHistoryStore(url: directory.appendingPathComponent("history.json"))
            return LaunchStores(
                history: HistoryStore(store: history),
                snapshotStore: FileSnapshotStore(url: directory.appendingPathComponent("state.json"))
            )
        } catch {
            let reason = error.localizedDescription
            MovezLog.store.error("the data folder could not be opened, running from memory: \(reason, privacy: .public)")
            return LaunchStores(history: HistoryStore(), snapshotStore: nil, problem: storeProblem)
        }
    }

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

    /// The strength library is Strength mode's content, checked against the movement library its
    /// overlaps name. A file that will not load is as loud as a missing movement library: a mode
    /// that quietly served nothing would be worse than an app that says it cannot start.
    static func loadStrengthLibrary(
        movementLibrary: MovementLibrary,
        presenter: FatalPresenter
    ) -> StrengthLibrary? {
        do {
            return try StrengthLibraryLoader.loadBundled(movementLibrary: movementLibrary)
        } catch {
            presenter.presentFatal(error)
            return nil
        }
    }

    /// The health and safety notice has to be accepted before anything runs, so a notice that
    /// will not load is as fatal as a missing library: there would be nothing to accept.
    static func loadNotice(
        using load: () throws -> HealthNotice = HealthNotice.loadBundled,
        presenter: FatalPresenter
    ) -> HealthNotice? {
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
    /// A signal source that could not be set up, so it reads nothing.
    static let signals = Logger(subsystem: "com.kylemack.movez", category: "signals")
}
