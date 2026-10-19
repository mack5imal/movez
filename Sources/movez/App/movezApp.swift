import SwiftUI

@main
struct MovezApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarRoot(delegate: appDelegate)
        } label: {
            MenuBarLabelRoot(delegate: appDelegate)
        }
        .menuBarExtraStyle(.window)
        .commands { MovezCommands() }
    }
}

/// The delegate builds the coordinator a beat after launch, so both menu-bar surfaces start out
/// with nothing to show. The wait is held here, in a `View`, rather than in the `Scene` above:
/// `@NSApplicationDelegateAdaptor` re-runs a view body when the delegate publishes but not a
/// scene body, so a scene that branches on `menuBar` keeps the placeholder it built at launch for
/// as long as the app runs.
struct MenuBarRoot: View {
    @ObservedObject var delegate: AppDelegate

    var body: some View {
        if let menuBar = delegate.menuBar {
            MenuBarContent(viewModel: menuBar)
        } else {
            MovezText("Movez is starting…", MovezType.menuRow, color: Tokens.text2)
                .padding(12)
        }
    }
}

/// The glyph, with the same wait. Until the coordinator exists there is no countdown to draw, so
/// it shows the off-hours ring.
struct MenuBarLabelRoot: View {
    @ObservedObject var delegate: AppDelegate

    var body: some View {
        if let menuBar = delegate.menuBar {
            MenuBarLabel(viewModel: menuBar)
        } else {
            Image(nsImage: MenuBarIcon.image(mode: .offHours, fraction: 0))
        }
    }
}

/// The dropdown. Window-style `MenuBarExtra` rebuilds its content every time it opens, so the
/// view holds nothing — the view model owns which rows are expanded.
struct MenuBarContent: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        MenuBarView(state: viewModel.state, actions: viewModel.actions)
    }
}

/// The ring and its countdown, redrawn whenever the coordinator publishes.
struct MenuBarLabel: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        Label {
            Text(viewModel.labelText)
        } icon: {
            Image(nsImage: viewModel.iconImage)
        }
    }
}

/// ⌘, and ⌘Q, registered at the app level so they work from the overlay and the settings window
/// too — not only while the dropdown happens to be open.
struct MovezCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                NotificationCenter.default.post(name: .movezOpenSettings, object: nil)
            }
            .keyboardShortcut(MenuShortcutSpec.settings.keyEquivalent, modifiers: .command)
        }
        CommandGroup(replacing: .appTermination) {
            Button("Quit Movez") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut(MenuShortcutSpec.quit.keyEquivalent, modifiers: .command)
        }
    }
}
