import Foundation

/// What the notice window is showing and what its buttons do.
///
/// Two modes. At launch, before anything is scheduled, the notice has to be accepted: Quit is
/// always there, and "I understand and agree" only comes alive once the end of the notice has
/// been on screen, so nobody can accept a page they never saw. From Settings it is read-only.
@MainActor
final class NoticeViewModel: ObservableObject {
    enum Mode: Equatable {
        case accept
        case read
    }

    let notice: HealthNotice
    let mode: Mode
    private let settings: SettingsStore
    private let now: () -> Date
    private let onAgree: () -> Void
    private let onQuit: () -> Void
    private let onClose: () -> Void

    /// Set once the end of the notice has scrolled into view, and never unset.
    @Published private(set) var reachedEnd = false
    private var agreed = false

    init(
        notice: HealthNotice,
        mode: Mode,
        settings: SettingsStore,
        now: @escaping () -> Date = Date.init,
        onAgree: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        self.notice = notice
        self.mode = mode
        self.settings = settings
        self.now = now
        self.onAgree = onAgree
        self.onQuit = onQuit
        self.onClose = onClose
    }

    var canAgree: Bool { mode == .accept && reachedEnd && !agreed }

    func endReached() {
        reachedEnd = true
    }

    /// Records this version as accepted, now, and lets the app start. Only once: a second press
    /// while the window fades must not start a second coordinator.
    func agree() {
        guard canAgree else { return }
        agreed = true
        settings.acceptNotice(version: notice.version, at: now())
        onAgree()
    }

    func quit() { onQuit() }

    func close() { onClose() }

    /// "Notice version 1.0 · Effective October 19, 2026"
    var versionLine: String {
        let effective = notice.effective.isEmpty ? "" : " · \(notice.effective)"
        return "Notice version \(notice.version)\(effective)"
    }

    /// Under the buttons: why agree is not available yet.
    var hint: String? {
        mode == .accept && !reachedEnd ? "Scroll to the end to continue." : nil
    }

    /// Read mode's footer: "You accepted version 1.0 on 26 Oct 2026."
    var acceptedLine: String? {
        guard mode == .read, let version = settings.acceptedNoticeVersion,
              let date = settings.acceptedNoticeAt else { return nil }
        return "You accepted version \(version) on \(Self.dateText(date))."
    }

    /// "26 Oct 2026", the same in Settings and here.
    static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
