import XCTest

/// Throwaway `UserDefaults` for tests that need a `SettingsStore`.
///
/// A suite named like `movez.tests.<uuid>` is a real file in ~/Library/Preferences, and deleting it
/// from inside the test does not reliably get rid of it: cfprefsd writes asynchronously and often
/// puts an empty plist back after the test has removed it. Run after run, that left thousands of
/// files behind. A suite named by an absolute path keeps its plist at that path instead, so every
/// suite here lives in one scratch folder under the temporary directory. The folder goes when the
/// test bundle finishes, and cfprefsd never recreates a folder, so nothing outlives the run. A run
/// that crashes first leaves its folder in the temporary directory, which macOS clears on its own.
enum ScratchDefaults {
    static func make() -> UserDefaults {
        let path = remover.folder.appendingPathComponent(UUID().uuidString).path
        guard let defaults = UserDefaults(suiteName: path) else {
            // Falling back to `.standard` would let a test write to the user's real settings.
            preconditionFailure("could not open scratch defaults at \(path)")
        }
        return defaults
    }

    /// Created on first use, which also registers it to remove the folder at the end of the run.
    /// Held here as well as by the observation center, so its lifetime never depends on how the
    /// center keeps its observers.
    private static let remover: FolderRemover = {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("movez-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let remover = FolderRemover(folder: folder)
        XCTestObservationCenter.shared.addTestObserver(remover)
        return remover
    }()

    private final class FolderRemover: NSObject, XCTestObservation {
        let folder: URL

        init(folder: URL) {
            self.folder = folder
        }

        func testBundleDidFinish(_ testBundle: Bundle) {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
