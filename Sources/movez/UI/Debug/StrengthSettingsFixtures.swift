import Foundation

/// The Strength settings states the snapshots render, built on the same frozen settings window as
/// the Movement ones so the shared sections match pixel for pixel.
@MainActor
extension SnapshotFixtures {
    /// Settings with Strength selected, as the design draws it: dumbbells, a wall, three breaks,
    /// Moderate, no focus and two moves excluded.
    static func strengthSettingsViewModel(sheet: SettingsViewModel.Sheet? = nil) -> SettingsViewModel? {
        guard let viewModel = settingsViewModel(sheet: sheet) else { return nil }
        let settings = viewModel.settings
        settings.strengthSetUp = true
        settings.strengthEquipment = [.dumbbells]
        settings.strengthSolidWallNearby = true
        settings.strengthBreaksPerDay = 3
        settings.strengthDifficultyCap = 2
        settings.strengthFocus = .none
        // The first two moves of the library rather than named ones, so fixture code never has to
        // follow a library revision.
        settings.strengthExcludedIds = Set((strengthLibrary?.movements ?? []).prefix(2).map(\.id))
        settings.mode = .strength
        return viewModel
    }

    /// The first switch: Movement settings with the setup sheet over them, dumbbells ticked and
    /// the rest at the setup's defaults.
    static func strengthSetupViewModel() -> SettingsViewModel? {
        guard let viewModel = settingsViewModel() else { return nil }
        viewModel.beginStrengthSetup()
        viewModel.toggleSetupEquipment(.dumbbells)
        return viewModel
    }
}
