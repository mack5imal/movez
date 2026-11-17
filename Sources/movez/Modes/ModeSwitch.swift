import Foundation

/// What a mode request needs the caller to do next.
enum ModeSwitchAction: Equatable {
    /// Show this mode's setup. The mode has not changed and will not until the setup is confirmed.
    case openSetup(BreakMode)
}

/// The one way the mode changes, whether the request comes from Settings or the dropdown.
///
/// A mode with a set-up flag (Strength) cannot be switched to before its setup has been confirmed
/// once, because its breaks depend on answers the user has not given yet: what equipment there is,
/// how many strength breaks a day. Keeping that rule here, rather than in each control, is what
/// stops one surface from switching straight past the setup.
@MainActor
enum ModeSwitch {
    /// Switches to `mode` when it is ready, or returns the setup to open when it is not. Asking
    /// for the mode already in use does nothing.
    static func request(_ mode: BreakMode, in settings: SettingsStore) -> ModeSwitchAction? {
        guard mode != settings.mode else { return nil }
        if let isSetUp = mode.definition.isSetUp, !isSetUp(settings) {
            return .openSetup(mode)
        }
        settings.mode = mode
        return nil
    }

    /// Saves the first-switch choices, marks Strength as set up and switches to it. No equipment
    /// is a valid answer: the user trains with bodyweight only.
    static func confirmStrengthSetup(_ choices: StrengthSetupChoices, in settings: SettingsStore) {
        settings.strengthEquipment = choices.equipment
        settings.strengthSolidWallNearby = choices.solidWallNearby
        settings.strengthBreaksPerDay = choices.breaksPerDay
        settings.strengthDifficultyCap = choices.difficultyCap
        settings.strengthSetUp = true
        settings.mode = .strength
    }
}

extension ModeSwitchAction {
    /// Whether the action asks for the Strength first-switch sheet. Answered here so the settings
    /// window can open the right sheet without naming a mode case outside `Modes/`.
    var opensStrengthSetup: Bool {
        switch self {
        case .openSetup(let mode): return mode.definition.settingsGroup == ModeSettingsGroup.strength
        }
    }
}
