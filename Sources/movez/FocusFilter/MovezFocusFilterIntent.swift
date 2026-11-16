import AppIntents
import Foundation

/// Lets a macOS Focus turn movement breaks off, and turn them back on when the Focus ends.
///
/// This is the whole of movez's Do Not Disturb story. There is no supported way to read which
/// Focus is on, and polling DND state is exactly the kind of guessing that gets these apps
/// uninstalled — so the user attaches movez to the Focus they care about instead. What macOS does
/// offer is this filter's own current value, which the coordinator reads at launch.
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

    /// The request is kept as well as passed on: macOS can perform the filter before there is a
    /// coordinator to take it (the notice not yet accepted, or the login item still starting).
    @MainActor
    func perform() async throws -> some IntentResult {
        FocusFilterRequest.latest = pauseBreaks
        AppCoordinator.shared?.focusFilter(paused: pauseBreaks)
        return .result()
    }
}

/// The last Focus request macOS made in this run, for a coordinator that starts after it.
@MainActor
enum FocusFilterRequest {
    static var latest: Bool?
}
