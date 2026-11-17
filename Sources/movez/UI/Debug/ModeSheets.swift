import SwiftUI

/// Every mode's badge at every size it is drawn, laid out like the design's sheet so the two can be
/// held side by side. 100s and PT come from fixture definitions; the app serves neither.
struct ModeBadgeSheet: View {
    // design: mode-badges
    static let size = CGSize(width: 1280, height: 1000)

    private static let columns: [(title: String, width: CGFloat)] = [
        ("GLYPH · 20 × 20 GRID, 1.8 STROKE", 220),
        ("OVERLAY EYEBROW · 22 / 18 PX", 270),
        ("PANEL EYEBROW · 13 / 11 PX", 250),
        ("DROPDOWN MODE ROW · 14 / 12 PX", 250),
        ("SETTINGS MODE CONTROL · 14 / 12 PX", 178)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MovezText("Mode badge · glyph + mode name", MovezType.panelTitle)
            MovezText(
                "Accent glyph with the text color of its context. No color changes between modes.",
                MovezType.panelBody,
                color: Tokens.text2
            )
            .padding(.top, 6)
            header.padding(.top, 28)
            ForEach(SnapshotFixtures.sheetModes, id: \.id) { definition in
                MovezDivider()
                row(definition)
            }
            MovezDivider()
            manyModes.padding(.top, 24)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 40, leading: 56, bottom: 40, trailing: 56))
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Self.columns, id: \.title) { column in
                MovezText(column.title, MovezType.sectionLabel, color: Tokens.text3)
                    .frame(width: column.width, alignment: .leading)
            }
        }
        .padding(.bottom, 12)
    }

    private func row(_ definition: ModeDefinition) -> some View {
        // The dropdown pairs each mode with Movement, and Movement with Strength.
        let movement = SnapshotFixtures.movementMode
        let partner = definition.id == movement.id ? SnapshotFixtures.strengthMode : definition
        return HStack(alignment: .center, spacing: 0) {
            ModeGlyphView(glyph: ModeGlyph.badge(for: definition), size: 76)
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Tokens.accentTintBadge.color))
                .frame(width: Self.columns[0].width, alignment: .leading)
            ModeBadge(definition: definition, size: .overlay, label: .breakEyebrow)
                .frame(width: Self.columns[1].width, alignment: .leading)
            ModeBadge(definition: definition, size: .panel, label: .microBreakEyebrow)
                .frame(width: Self.columns[2].width, alignment: .leading)
            ModeSegmentedControl(
                definitions: [movement, partner],
                selection: .constant(definition.id),
                variant: .dropdown
            )
            .frame(width: Self.columns[3].width, alignment: .leading)
            ModeSegmentedControl(definitions: [definition], selection: .constant(definition.id))
                .frame(width: Self.columns[4].width, alignment: .leading)
        }
        .padding(.vertical, 24)
    }

    private var manyModes: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                MovezText("WITH 3 OR 4 MODES", MovezType.sectionLabel, color: Tokens.text3)
                MovezText(
                    "The dropdown collapses inactive modes to 36 pt glyph-only buttons, named for screen readers and in a tooltip. "
                        + "Settings always shows every name.",
                    MovezType.panelBody,
                    color: Tokens.text2
                )
            }
            .frame(width: 330, alignment: .leading)
            VStack(alignment: .leading, spacing: 14) {
                ModeSegmentedControl(
                    definitions: SnapshotFixtures.sheetModes,
                    selection: .constant(SnapshotFixtures.strengthMode.id),
                    variant: .dropdown
                )
                ModeSegmentedControl(
                    definitions: SnapshotFixtures.sheetModes,
                    selection: .constant(SnapshotFixtures.strengthMode.id)
                )
                WeightGuidance()
                    .frame(width: 400)
                    .padding(.top, 10)
            }
        }
    }
}

/// The menu-bar icon in every mode at one moment, large enough to judge and then at its real size
/// on a light and a dark menu bar.
struct MenuIconSheet: View {
    static let size = CGSize(width: 1280, height: 640)
    /// From the icon to its label, in the menu bar.
    static let labelGap: CGFloat = 5

    var mode: MenuBarState.Mode

    private static let largeSize: CGFloat = 138

    private var state: MenuBarState {
        var state = MenuBarState()
        state.mode = mode
        state.minutesRemaining = mode == .paused ? 42 : 32
        state.elapsedFraction = 0.42
        return state
    }

    private var title: String {
        switch mode {
        case .sitting: return "Sitting · 42% of the bout elapsed · 32 min left"
        case .paused: return "Paused · dashed ring, no progress · 42 min left in the pause"
        case .offHours: return "Off hours · ring and glyph quieter, no label"
        case .away: return "Away · solid ring, label —"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MovezText(title, MovezType.panelTitle)
            HStack(spacing: 24) {
                ForEach(SnapshotFixtures.sheetModes, id: \.id) { definition in
                    card(definition)
                }
            }
            .padding(.top, 32)
            MovezText("Actual size", MovezType.menuTitle).padding(.top, 36)
            menuBar(background: Tokens.Backdrop.lightBar, ink: Tokens.Backdrop.lightBarInk).padding(.top, 14)
            menuBar(background: Tokens.Backdrop.darkBar, ink: Tokens.Backdrop.darkBarInk)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 40, leading: 56, bottom: 40, trailing: 56))
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    private func card(_ definition: ModeDefinition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ModeBadge(definition: definition, size: .overlay, label: .name, style: MovezType.eyebrowOverlay)
            ZStack {
                RoundedRectangle(cornerRadius: Tokens.Radius.menu, style: .continuous)
                    .fill(Tokens.panel.color)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.menu, style: .continuous)
                            .strokeBorder(Tokens.panelBorder.color, lineWidth: 1)
                    )
                icon(definition, size: Self.largeSize, ink: Tokens.text)
            }
            .frame(height: 176)
        }
        .frame(maxWidth: .infinity)
    }

    private func icon(_ definition: ModeDefinition, size: CGFloat, ink: MovezColor) -> some View {
        Image(nsImage: MenuBarIcon.image(
            mode: state.mode,
            fraction: state.elapsedFraction,
            glyph: ModeGlyph.menuBar(for: definition),
            size: size
        ))
        .renderingMode(.template)
        .foregroundStyle(ink.color)
        .frame(width: size, height: size)
    }

    /// All four side by side for comparison; the app shows one icon at a time.
    private func menuBar(background: MovezColor, ink: MovezColor) -> some View {
        HStack(spacing: 22) {
            Spacer(minLength: 0)
            ForEach(SnapshotFixtures.sheetModes, id: \.id) { definition in
                HStack(spacing: Self.labelGap) {
                    icon(definition, size: MenuBarIcon.pointSize, ink: ink)
                    if !state.labelText.isEmpty {
                        // The system menu bar's own 13 pt face, not the app's.
                        Text(state.labelText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ink.color)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 24)
        .background(background.color)
    }
}
