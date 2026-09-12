import Foundation

/// Command-line switches understood by the movez binary.
///
/// The app is a menu-bar agent, so these switches exist purely so the build can be
/// exercised head-lessly from `make` targets and from the verification harnesses:
///
/// - `--smoke` prints a single readiness line and exits.
/// - `--snapshot <surface> --out <path>` renders a UI surface offscreen to a PNG.
/// - `--probe-signals` prints one line per system-signal monitor.
/// - `--overlay-hygiene` opens the break overlay on every screen and reports window state.
/// - `--panel-hygiene` shows each floating panel and reports activation state.
struct LaunchArguments {
    var smoke = false
    var snapshot: String?
    var out: String?
    var probeSignals = false
    var overlayHygiene = false
    var panelHygiene = false

    /// True when the process was launched to do one job and exit rather than to sit in the menu bar.
    var isHeadless: Bool {
        smoke || snapshot != nil || probeSignals || overlayHygiene || panelHygiene
    }

    init(_ arguments: [String] = CommandLine.arguments) {
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            let next: String? = arguments.index(after: index) < arguments.endIndex
                ? arguments[arguments.index(after: index)]
                : nil
            switch argument {
            case "--smoke":
                smoke = true
            case "--snapshot":
                snapshot = next
                if next != nil { index = arguments.index(after: index) }
            case "--out":
                out = next
                if next != nil { index = arguments.index(after: index) }
            case "--probe-signals":
                probeSignals = true
            case "--overlay-hygiene":
                overlayHygiene = true
            case "--panel-hygiene":
                panelHygiene = true
            default:
                break
            }
            index = arguments.index(after: index)
        }
    }

    /// Parsed once from the real process arguments.
    static let current = LaunchArguments()
}
