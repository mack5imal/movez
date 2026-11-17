import Foundation

/// The kinds of break the app can serve. The raw value is what `SettingsStore` persists, so a case
/// is never renamed.
///
/// Everything a mode looks like or draws from (its name, glyphs, library and settings group) lives
/// in its `ModeDefinition`, not here: a new mode is a new case plus a new definition, and nothing
/// outside `Modes/` asks which case it is holding.
enum BreakMode: String, CaseIterable, Codable, Hashable {
    case movement
    case strength

    /// The mode a fresh install, or a stored value this build does not know, starts in.
    static let fallback: BreakMode = .movement

    var definition: ModeDefinition {
        guard let definition = ModeDefinitionTable.standard.definition(for: rawValue) else {
            // Every case has a definition in the standard table; a missing one is a programming
            // error caught by `ModeExtensibilityTests`, not something to recover from.
            preconditionFailure("no mode definition for \(rawValue)")
        }
        return definition
    }
}
