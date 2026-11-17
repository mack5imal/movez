import Foundation

/// Which bundled library a mode's breaks are drawn from, named by its resource.
///
/// A struct rather than an enum so a mode added later, or a test, can name a library of its own
/// without a new case here.
struct ModeLibraryKind: Hashable {
    let resourceName: String

    static let movement = ModeLibraryKind(resourceName: LibraryLoader.resourceName)
    static let strength = ModeLibraryKind(resourceName: StrengthLibraryLoader.resourceName)
}

/// The Settings section that holds a mode's own settings, shown in place of the other modes'.
struct ModeSettingsGroup: Hashable {
    let id: String
    /// The section header, in the design's capitals.
    let title: String

    static let movements = ModeSettingsGroup(id: "movements", title: "MOVEMENTS")
    static let strength = ModeSettingsGroup(id: "strength", title: "STRENGTH")
}

/// Everything that makes one mode look and behave like itself.
///
/// This is the only place a mode is mapped to its parts: surfaces read the name, eyebrow and glyphs
/// from here, and the coordinator reads the library and settings group, so serving a third mode
/// means adding a definition rather than another branch at every call site.
struct ModeDefinition: Hashable {
    /// Matches the `BreakMode` raw value for a real mode.
    let id: String
    /// The name in the mode control and badges: "Movement".
    let displayName: String
    /// The word in front of BREAK and MICRO-BREAK in an eyebrow: "MOVEMENT".
    let eyebrowWord: String
    /// The glyph `ModeBadge` draws, by identifier; the vectors live with the badge.
    let badgeGlyph: String
    /// The glyph drawn inside the menu-bar circle. The design uses the badge glyph, but it is kept
    /// separate so the two can diverge without touching the badge.
    let menuBarGlyph: String
    let libraryKind: ModeLibraryKind
    let settingsGroup: ModeSettingsGroup
    /// Whether the mode's setup has been confirmed, so a switch to it can apply straight away. Nil
    /// for a mode with nothing to set up; while it reads false, a switch opens the setup instead.
    /// A closure rather than a key path because the store is main-actor isolated.
    let isSetUp: (@MainActor (SettingsStore) -> Bool)?

    /// "MOVEMENT BREAK"
    var breakEyebrow: String { "\(eyebrowWord) BREAK" }
    /// "MOVEMENT MICRO-BREAK"
    var microBreakEyebrow: String { "\(eyebrowWord) MICRO-BREAK" }

    static let movement = ModeDefinition(
        id: BreakMode.movement.rawValue,
        displayName: "Movement",
        eyebrowWord: "MOVEMENT",
        badgeGlyph: "mode.movement",
        menuBarGlyph: "mode.movement",
        libraryKind: .movement,
        settingsGroup: .movements,
        isSetUp: nil
    )

    static let strength = ModeDefinition(
        id: BreakMode.strength.rawValue,
        displayName: "Strength",
        eyebrowWord: "STRENGTH",
        badgeGlyph: "mode.strength",
        menuBarGlyph: "mode.strength",
        libraryKind: .strength,
        settingsGroup: .strength,
        isSetUp: { $0.strengthSetUp }
    )

    /// Two definitions are the same mode when every value part matches; the set-up check is code,
    /// so it takes no part.
    static func == (lhs: ModeDefinition, rhs: ModeDefinition) -> Bool {
        lhs.id == rhs.id && lhs.displayName == rhs.displayName && lhs.eyebrowWord == rhs.eyebrowWord
            && lhs.badgeGlyph == rhs.badgeGlyph && lhs.menuBarGlyph == rhs.menuBarGlyph
            && lhs.libraryKind == rhs.libraryKind && lhs.settingsGroup == rhs.settingsGroup
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Every real mode's definition, in the order the mode controls list them.
    static var all: [ModeDefinition] { ModeDefinitionTable.standard.definitions }
}

/// An ordered set of mode definitions with lookup by id.
///
/// The app uses `standard`; a test builds its own table with an extra definition to show that a
/// new mode is served by lookup alone.
struct ModeDefinitionTable {
    let definitions: [ModeDefinition]

    static let standard = ModeDefinitionTable(definitions: [.movement, .strength])

    func definition(for id: String) -> ModeDefinition? {
        definitions.first { $0.id == id }
    }

    var ids: [String] { definitions.map(\.id) }
}
