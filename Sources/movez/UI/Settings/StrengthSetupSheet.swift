import SwiftUI

/// The questions Strength needs answered before its first break, asked the first time it is
/// chosen, from Settings or from the dropdown.
///
/// The answers are held in a draft until Switch to Strength, so Not now leaves every setting and
/// the mode exactly as they were. Switch to Strength is never disabled: an owner with no weights
/// still gets bodyweight strength breaks.
struct StrengthSetupSheet: View {
    @ObservedObject var viewModel: SettingsViewModel

    static let width: CGFloat = 540
    /// Where the sheet's top edge sits in the window, as the design places it.
    static let top: CGFloat = 110

    // The intro is kept on one line so it reads exactly as the design writes it.
    // swiftlint:disable:next line_length
    static let intro = "Short strength breaks keep you strong through long desk days. Each takes about 5 minutes: a warm-up, three sets with your own weights, and a cool-down. Any later breaks that day are end-range stretches with no weights."

    private var draft: StrengthSetupChoices { viewModel.strengthSetupDraft }

    var body: some View {
        SheetShell(title: "Set up Strength", width: Self.width) {
            VStack(alignment: .leading, spacing: 11) {
                MovezText(Self.intro, MovezType.panelBody, color: Tokens.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
                SettingsRow(label: "Equipment on hand") {
                    StrengthEquipmentChips(selected: draft.equipment, toggle: viewModel.toggleSetupEquipment)
                }
                SettingsRow(label: "Solid wall nearby") {
                    MovezToggle(isOn: $viewModel.strengthSetupDraft.solidWallNearby)
                }
                SettingsRow(label: "Strength breaks a day") {
                    SegmentedControl(
                        options: SettingsViewModel.strengthBreaksOptions,
                        selection: $viewModel.strengthSetupDraft.breaksPerDay
                    )
                }
                SettingsRow(label: "Difficulty cap") {
                    SegmentedControl(
                        options: SettingsViewModel.difficultyOptions,
                        selection: $viewModel.strengthSetupDraft.difficultyCap
                    )
                }
                WeightGuidance()
                    .padding(.top, 4)
            }
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 18, trailing: 20))

            MovezDivider(color: Tokens.ruleSettings)
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            MovezText("Movement stays on until you switch.", MovezType.version, color: Tokens.text3)
            Spacer(minLength: 12)
            Button("Switch to Strength", action: viewModel.confirmStrengthSetupSheet)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.strengthSetupCanConfirm)
            Button("Not now", action: viewModel.declineStrengthSetup)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(EdgeInsets(top: 14, leading: 20, bottom: 16, trailing: 20))
    }
}
