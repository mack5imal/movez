import AppIntents
import Foundation

/// Lets a macOS Focus turn movement breaks off, and turn them back on when the Focus ends.
///
/// This is the whole of movez's Do Not Disturb story. There is no supported way to read the
/// current Focus, and polling DND state is exactly the kind of guessing that gets these apps
/// uninstalled — so the user attaches movez to the Focus they care about instead.
struct MovezFocusFilterIntent: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Movez"

    static var description: IntentDescription? {
        IntentDescription("Pause movement breaks while this Focus is on.")
    }

    /// Off by default, because macOS sends the default whenever no Focus is on: once after every
    /// boot, and each time a Focus ends. A default of on paused movez at every boot and never let
    /// a Focus that ended resume it (DECISIONS 51).
    @Parameter(title: "Pause breaks", default: false)
    var pauseBreaks: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: pauseBreaks ? "Movement breaks paused" : "Movement breaks running",
            subtitle: pauseBreaks
                ? "Movez will wait until this Focus ends."
                : "Movez keeps its usual schedule."
        )
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Pause movement breaks: \(\.$pauseBreaks)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppCoordinator.shared?.focusFilter(paused: pauseBreaks)
        return .result()
    }
}
