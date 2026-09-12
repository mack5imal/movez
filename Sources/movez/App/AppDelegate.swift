import AppKit
import SwiftUI

/// Owns process-level concerns: font registration, accessory activation policy, and the
/// head-less command-line entry points used by the build and verification harnesses.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let arguments = LaunchArguments.current

    func applicationWillFinishLaunching(_ notification: Notification) {
        MovezFont.register()
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard arguments.isHeadless else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [arguments] in
            if arguments.smoke {
                // Intentional stdout line: the build harness asserts on it.
                print("movez smoke ok")
                fflush(stdout)
            }
            exit(0)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
