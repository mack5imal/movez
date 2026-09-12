import SwiftUI

@main
struct MovezApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            if let menuBar = appDelegate.menuBar {
                MenuBarContent(viewModel: menuBar)
            } else {
                MovezText("movez is starting…", MovezType.menuRow, color: Tokens.text2)
                    .padding(12)
            }
        } label: {
            if let menuBar = appDelegate.menuBar {
                MenuBarLabel(viewModel: menuBar)
            } else {
                Image(nsImage: MenuBarIcon.image(mode: .offHours, fraction: 0))
            }
        }
        .menuBarExtraStyle(.window)
        .commands { MovezCommands() }
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
            Button("Quit movez") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut(MenuShortcutSpec.quit.keyEquivalent, modifiers: .command)
        }
    }
}
