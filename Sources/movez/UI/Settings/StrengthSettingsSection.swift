import SwiftUI

/// The STRENGTH section, shown in place of MOVEMENTS while Strength is the mode.
///
/// Every control here writes a strength key and nothing else, so trying Strength never disturbs
/// the movement setup the user will come back to.
struct StrengthSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var settings: SettingsStore { viewModel.settings }

    var body: some View {
        SettingsSection(label: "Strength") {
            SettingsRow(label: "Equipment on hand") {
                StrengthEquipmentChips(selected: settings.strengthEquipment, toggle: viewModel.toggleStrengthEquipment)
            }
            SettingsRow(label: "Solid wall nearby") {
                MovezToggle(label: "Solid wall nearby", isOn: Binding(
                    get: { settings.strengthSolidWallNearby },
                    set: viewModel.setStrengthSolidWallNearby
                ))
            }
            SettingsRow(label: "Strength breaks a day", sub: StrengthSettingsSection.breaksSub) {
                SegmentedControl(
                    options: SettingsViewModel.strengthBreaksOptions,
                    selection: Binding(get: { settings.strengthBreaksPerDay }, set: viewModel.setStrengthBreaksPerDay)
                )
            }
            SettingsRow(label: "Difficulty cap") {
                SegmentedControl(
                    options: SettingsViewModel.difficultyOptions,
                    selection: Binding(get: { settings.strengthDifficultyCap }, set: viewModel.setStrengthDifficultyCap)
                )
            }
            SettingsRow(label: "Focus") {
                SelectField(
                    options: SettingsViewModel.strengthFocusOptions,
                    selection: Binding(get: { settings.strengthFocus }, set: viewModel.setStrengthFocus),
                    minWidth: 200,
                    accessibilityName: "Focus"
                )
            }
            SettingsRow(label: "Excluded moves") {
                HStack(spacing: 12) {
                    MovezText(viewModel.strengthExcludedLine, MovezType.settingsRow, color: Tokens.text2)
                    SettingsLinkButton(title: "Browse library…", action: viewModel.openStrengthLibrary)
                }
            }
            WeightGuidance()
        }
    }

    static let breaksSub = "Later breaks that day are end-range breaks."
}

/// Dumbbells · Kettlebell, as chips. Shared by the section and the first-switch sheet.
struct StrengthEquipmentChips: View {
    var selected: Set<StrengthEquipment>
    var toggle: (StrengthEquipment) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SettingsViewModel.strengthEquipmentOptions, id: \.self) { item in
                Chip(label: item.displayName, selected: selected.contains(item)) { toggle(item) }
            }
        }
    }
}

/// Every strength move, searchable, with a switch to take any of them out of rotation. The
/// Strength counterpart of `LibraryBrowserSheet`, over the strength library and its own buckets.
struct StrengthLibraryBrowserSheet: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SheetShell(
            title: "Strength library",
            width: LibraryBrowserSheet.size.width,
            height: LibraryBrowserSheet.size.height
        ) {
            VStack(alignment: .leading, spacing: 10) {
                LibrarySearchField(text: $viewModel.librarySearch)
                buckets
                HStack {
                    MovezText(viewModel.strengthExcludedLine, MovezType.settingsRow, color: Tokens.text2)
                    Spacer(minLength: 8)
                    MovezText(viewModel.strengthShownLine, MovezType.version, color: Tokens.text3)
                }
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 8, trailing: 20))

            MovezDivider(color: Tokens.ruleSettings)
            list
            MovezDivider(color: Tokens.ruleSettings)
            SheetActions { viewModel.openSheet = nil }
        }
    }

    private var buckets: some View {
        HStack(spacing: 6) {
            Chip(label: "All", selected: viewModel.strengthLibraryBucket == nil) { viewModel.strengthLibraryBucket = nil }
            ForEach(viewModel.strengthBucketChips, id: \.bucket) { chip in
                Chip(label: chip.bucket.rawValue, selected: viewModel.strengthLibraryBucket == chip.bucket) {
                    viewModel.strengthLibraryBucket = chip.bucket
                }
                .help(chip.name)
                .accessibilityLabel(chip.name)
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.matchingStrengthMovements(), id: \.id) { movement in
                    let excluded = viewModel.isStrengthExcluded(movement.id)
                    HStack(spacing: 12) {
                        MovezText(movement.id, MovezType.version, color: Tokens.text3)
                            .frame(width: 68, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            MovezText(movement.name, MovezType.settingsRow, color: excluded ? Tokens.text3 : Tokens.text)
                            MovezText(viewModel.strengthMeta(for: movement), MovezType.version, color: Tokens.text3)
                        }
                        Spacer(minLength: 12)
                        MovezToggle(label: "Include \(movement.name)", isOn: Binding(
                            get: { !excluded },
                            set: { viewModel.setStrengthExcluded(movement.id, !$0) }
                        ))
                    }
                    .padding(.vertical, 9)
                    .opacity(excluded ? 0.75 : 1)
                    MovezDivider(color: Tokens.ruleSettings)
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(maxHeight: .infinity)
    }
}
