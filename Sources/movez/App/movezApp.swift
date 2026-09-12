import SwiftUI

@main
struct MovezApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("movez", systemImage: "figure.walk") {
            Text("movez · placeholder")
                .padding(12)
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}
