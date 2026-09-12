import SwiftUI

/// The whole settings window: its own title bar, the scrolling sections, the footer, and whatever
/// sheet is open over the top.
///
/// The sheets are drawn inside the window rather than as real `NSPanel` sheets. It keeps every
/// pixel in the app's palette — a system sheet brings its own chrome — and it is what lets each
/// one be snapshotted.
struct SettingsScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    static let size = CGSize(width: 760, height: 700)
    static let titleBarHeight: CGFloat = 52

    /// The window is a fixed 700 tall; only the debug snapshot renders it longer, so the whole
    /// expanded section can be seen at once instead of scrolled.
    var height: CGFloat = SettingsScreen.size.height

    var body: some View {
        ZStack {
            Tokens.panelSolid.color
            VStack(spacing: 0) {
                titleBar
                SettingsView(viewModel: viewModel)
                SettingsFooter(viewModel: viewModel)
            }
            if let sheet = viewModel.openSheet {
                Tokens.dim.color
                sheetContent(sheet)
            }
        }
        .frame(width: Self.size.width, height: height)
    }

    private var titleBar: some View {
        ZStack {
            MovezText("movez settings", MovezType.menuTitle, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.titleBarHeight)
        .overlay(alignment: .bottom) { MovezDivider(color: Tokens.ruleSettings) }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: SettingsViewModel.Sheet) -> some View {
        switch sheet {
        case .workingHours: WorkingHoursPopover(viewModel: viewModel)
        case .library: LibraryBrowserSheet(viewModel: viewModel)
        case .exceptions: FullscreenExceptionsSheet(viewModel: viewModel)
        }
    }
}

/// The four sections, in the order the brief puts them.
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var settings: SettingsStore { viewModel.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                schedule
                sectionRule
                movements
                sectionRule
                stayOutOfTheWay
                sectionRule
                general
                if settings.debugExpanded {
                    sectionRule
                    SettingsSection(label: "Debug") {
                        if let debug = viewModel.debug {
                            DebugSection(state: debug, actions: viewModel.debugActions)
                        } else {
                            DebugContainer()
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: 24, leading: 32, bottom: 24, trailing: 32))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sectionRule: some View {
        MovezDivider(color: Tokens.ruleSettings)
            .padding(.vertical, 15)
    }

    // MARK: - Schedule

    private var schedule: some View {
        SettingsSection(label: "Schedule") {
            SettingsRow(label: "Preset") {
                SegmentedControl(
                    options: SettingsViewModel.presetOptions,
                    selection: Binding(get: { settings.preset }, set: viewModel.setPreset)
                )
            }

            if settings.preset == .custom {
                SettingsRow(label: "Sit for") {
                    StepperField(
                        value: viewModel.customSitLabel,
                        decrement: { viewModel.stepCustomMinutes(by: -1) },
                        increment: { viewModel.stepCustomMinutes(by: 1) }
                    )
                }
            }

            if settings.microToggleAvailable {
                SettingsRow(label: viewModel.microRowLabel, detail: viewModel.microRowDetail) {
                    MovezToggle(isOn: Binding(get: { settings.microEnabled }, set: viewModel.setMicroEnabled))
                }
            }

            SettingsRow(label: "Working hours") {
                HStack(spacing: 12) {
                    MovezText(viewModel.workingHoursSummary, MovezType.settingsRow, color: Tokens.text2)
                    SettingsLinkButton(title: "Edit", action: viewModel.beginEditingHours)
                }
            }
        }
    }

    // MARK: - Movements

    private var movements: some View {
        SettingsSection(label: "Movements") {
            SettingsRow(label: "Equipment on hand") {
                HStack(spacing: 8) {
                    ForEach(SettingsViewModel.equipmentOptions, id: \.self) { item in
                        Chip(
                            label: item.displayName,
                            selected: settings.equipment.contains(item)
                        ) { viewModel.toggleEquipment(item) }
                    }
                }
            }

            SettingsRow(label: "Difficulty cap") {
                SegmentedControl(
                    options: SettingsViewModel.difficultyOptions,
                    selection: Binding(get: { settings.difficultyCap }, set: viewModel.setDifficultyCap)
                )
            }

            SettingsRow(label: "Excluded movements") {
                HStack(spacing: 12) {
                    MovezText(viewModel.excludedLine, MovezType.settingsRow, color: Tokens.text2)
                    SettingsLinkButton(title: "Browse library…") { viewModel.openSheet = .library }
                }
            }

            SettingsRow(label: "Focus") {
                SelectField(
                    options: SettingsViewModel.focusOptions,
                    selection: Binding(get: { settings.focus }, set: viewModel.setFocus)
                )
            }
        }
    }

    // MARK: - Staying out of the way

    private var stayOutOfTheWay: some View {
        SettingsSection(label: "Stay out of the way") {
            SettingsRow(label: "Wait while the microphone is in use") {
                MovezToggle(isOn: Binding(get: { settings.suppressMic }, set: viewModel.setSuppressMic))
            }
            SettingsRow(label: "Wait while the screen is shared or recorded") {
                MovezToggle(isOn: Binding(get: { settings.suppressCapture }, set: viewModel.setSuppressCapture))
            }
            SettingsRow(
                label: "Wait while a fullscreen app is in front",
                link: SettingsLink(title: viewModel.exceptionsLine) { viewModel.openSheet = .exceptions }
            ) {
                MovezToggle(isOn: Binding(get: { settings.suppressFullscreen }, set: viewModel.setSuppressFullscreen))
            }
            SettingsRow(label: "Count me away after") {
                SelectField(
                    options: SettingsViewModel.awayOptions,
                    selection: Binding(get: { settings.awayThresholdMinutes }, set: viewModel.setAwayMinutes),
                    minWidth: 92
                )
            }
        }
    }

    // MARK: - General

    private var general: some View {
        SettingsSection(label: "General") {
            SettingsRow(label: "Sounds") {
                MovezToggle(isOn: Binding(get: { settings.soundsEnabled }, set: viewModel.setSounds))
            }
            SettingsRow(label: "Launch at login") {
                MovezToggle(isOn: Binding(get: { settings.launchAtLogin }, set: viewModel.setLaunchAtLogin))
            }
            if let error = viewModel.launchAtLoginError {
                MovezText(error, MovezType.version, color: Tokens.text3)
            }
        }
    }
}

/// What the disclosure shows when there are no debug tools to show — a snapshot render, or the
/// window before the coordinator exists.
struct DebugContainer: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.settings, style: .continuous)
            .strokeBorder(Tokens.ruleSettings.color, lineWidth: 1)
            .frame(height: 96)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Debug tools")
    }
}

/// A label column and the rows beside it.
struct SettingsSection<Content: View>: View {
    static var labelWidth: CGFloat { 160 }

    var label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            SectionLabel(text: label)
                .frame(width: Self.labelWidth, alignment: .leading)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 11) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A link that sits next to a row's label, like "2 exceptions".
struct SettingsLink {
    var title: String
    var action: () -> Void
}

/// Label on the left, control on the right.
struct SettingsRow<Control: View>: View {
    var label: String
    var detail: String?
    var link: SettingsLink?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 8) {
            MovezText(label, MovezType.settingsRow)
            if let detail {
                MovezText(detail, MovezType.settingsRow, color: Tokens.text3)
            }
            if let link {
                SettingsLinkButton(title: link.title, action: link.action)
            }
            Spacer(minLength: 16)
            control
        }
        .frame(minHeight: 24)
    }
}

/// "Edit", "Browse library…", "2 exceptions" — accent text, never a button.
struct SettingsLinkButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(LinkActionStyle(color: Tokens.accent, style: MovezType.settingsRow))
    }
}

/// The custom preset's "45 min", with a step either side.
struct StepperField: View {
    var value: String
    var decrement: () -> Void
    var increment: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            stepButton("minus", action: decrement)
            MovezText(value, MovezType.settingsRow, alignment: .center)
                .frame(width: 62)
            stepButton("plus", action: increment)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.select, style: .continuous)
                .strokeBorder(Tokens.panelBorder.color, lineWidth: 1)
        )
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Tokens.accent.color)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Longer" : "Shorter")
    }
}

/// The bar along the bottom: the debug disclosure on the left, what is installed on the right.
struct SettingsFooter: View {
    static let debugLabel = "Debug · time scale, signal injectors, state inspector"

    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            MovezDivider(color: Tokens.ruleSettings)
            HStack(spacing: 12) {
                Button {
                    viewModel.setDebugExpanded(!viewModel.settings.debugExpanded)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.settings.debugExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                        MovezText(Self.debugLabel, MovezType.version, color: Tokens.text3)
                    }
                    .foregroundStyle(Tokens.text3.color)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 16)
                MovezText(viewModel.versionLine, MovezType.version, color: Tokens.text3)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
        }
    }
}
