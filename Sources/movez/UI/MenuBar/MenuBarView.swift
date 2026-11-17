import SwiftUI

/// The dropdown behind the menu-bar icon: a header that repeats what the icon says, the actions
/// for whatever the scheduler is currently doing, today's numbers, and the two rows every Mac app
/// is expected to have.
///
/// A window-style `MenuBarExtra` has no submenus, so "Make due in" and "Pause for" expand inline
/// instead of flying out, and the mode row is a plain inline control rather than a menu.
///
/// Every mode shares this view; what differs by mode arrives as plain values in the state (the
/// header subtitle, the selected segment, the icon's glyph).
struct MenuBarView: View {
    // design: menu
    // design: menu-strength
    // design: menu-icons
    // The three dropdown screens share one marker file because the design checker counts a
    // prefix id ("menu") as marked wherever a longer one ("menu-strength") is. The Strength
    // header copy comes from ModeMenuCopy; the icon is drawn by MenuBarIcon in the menu bar
    // this dropdown hangs from.
    var state: MenuBarState
    var actions = MenuBarActions()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            MovezDivider()
                .padding(.bottom, 6)
            modeRow
            divider
            rows
            divider
            statsBlock
            divider
            footer
        }
        .padding(6)
        .frame(width: Tokens.Metric.menuWidth, alignment: .leading)
        .background(Tokens.panelMenu.color)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.menu, style: .continuous)
                .strokeBorder(Tokens.panelBorder.color, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.menu, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            TimerDisc(
                size: Tokens.Metric.menuDisc,
                progress: state.discProgress,
                numerals: state.discNumerals,
                mode: state.discMode,
                numeralStyle: MovezType.menuDisc
            )
            VStack(alignment: .leading, spacing: 2) {
                MovezText(state.title, MovezType.menuTitle)
                if !state.subtitle.isEmpty {
                    MovezText(state.subtitle, MovezType.menuSecondary, color: Tokens.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 12, trailing: 10))
    }

    /// One click switches mode. The selection is the state's, never the control's own: the
    /// dropdown is rebuilt on every open, and a first switch to Strength leaves the mode where it
    /// was until the setup is confirmed, so the row must keep showing the mode actually in use.
    private var modeRow: some View {
        ModeSegmentedControl(
            definitions: state.modes,
            selection: Binding(
                get: { state.breakMode.rawValue },
                set: { actions.selectMode($0) }
            ),
            variant: .dropdown
        )
        .padding(EdgeInsets(top: 2, leading: 4, bottom: 4, trailing: 4))
    }

    private var divider: some View {
        MovezDivider()
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        switch state.mode {
        // Away offers exactly what sitting does: someone reading this menu is back at the desk.
        case .sitting, .away: sittingRows
        case .paused: pausedRows
        case .offHours: offHoursRows
        }
    }

    @ViewBuilder
    private var sittingRows: some View {
        MenuRow(title: state.takeBreakLabel, highlighted: true, action: actions.takeBreakNow)
        makeDueRow
        if state.isAdHocSession {
            // A session started by hand ends by hand; pausing it would be the long way round.
            MenuRow(title: "End session", action: actions.endSession)
        } else {
            MenuRow(title: "Pause for", action: actions.togglePauseOptions) { Chevron() }
            if state.pauseExpanded {
                PillRow(options: PauseOption.allCases, action: actions.pause)
            }
        }
    }

    @ViewBuilder
    private var pausedRows: some View {
        MenuRow(title: "Resume now", highlighted: true, action: actions.resume)
        MenuRow(title: "Extend pause", action: actions.toggleExtendOptions) { Chevron() }
        if state.extendExpanded {
            PillRow(options: PauseOption.extendable, action: actions.extendPause)
        }
        // Quiet, but never unavailable: a break the user asks for always happens.
        MenuRow(title: state.takeBreakLabel, dimmed: true, action: actions.takeBreakNow)
    }

    @ViewBuilder
    private var offHoursRows: some View {
        MenuRow(title: "Start a session now", highlighted: true, action: actions.startSession)
        MenuRow(title: state.takeBreakLabel, action: actions.takeBreakNow)
    }

    /// "Make due in    5 · 10 · 15 · 30 min ▸" — each number is its own target, because the row
    /// as a whole has nothing to do.
    private var makeDueRow: some View {
        HStack(spacing: 8) {
            MovezText("Make due in", MovezType.menuRow)
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                ForEach(Array(MenuBarState.makeDueMinutes.enumerated()), id: \.element) { index, minutes in
                    if index > 0 {
                        MovezText("·", MovezType.menuSecondary, color: Tokens.text3)
                    }
                    Button("\(minutes)") { actions.makeDue(minutes) }
                        .buttonStyle(MinuteStepStyle())
                }
                MovezText("min", MovezType.menuSecondary, color: Tokens.text3)
            }
            Chevron()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Make due in \(MenuBarState.makeDueSummary)")
    }

    // MARK: - Stats and footer

    private var statsBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            MovezText(state.stats, MovezType.menuSecondary, color: Tokens.text2)
            MovezText(state.longestBout, MovezType.menuSecondary, color: Tokens.text3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var footer: some View {
        MenuRow(title: "Settings…", action: actions.openSettings) {
            MenuShortcut(text: MenuShortcutSpec.settings.label)
        }
        .keyboardShortcut(MenuShortcutSpec.settings.keyEquivalent, modifiers: .command)

        MenuRow(title: "Quit Movez", action: actions.quit) {
            MenuShortcut(text: MenuShortcutSpec.quit.label)
        }
        .keyboardShortcut(MenuShortcutSpec.quit.keyEquivalent, modifiers: .command)
    }
}

extension MenuShortcutSpec {
    /// The key as SwiftUI wants it. The spec itself stays Foundation-only so the state and its
    /// tests never have to import SwiftUI.
    var keyEquivalent: KeyEquivalent { KeyEquivalent(key) }
}

/// The "▸" that says a row has more behind it.
struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Tokens.text3.color)
    }
}

/// One of the minutes in "5 · 10 · 15 · 30 min".
struct MinuteStepStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .movezType(MovezType.menuSecondary)
            .foregroundStyle((configuration.isPressed ? Tokens.accent : Tokens.text3).color)
            .contentShape(Rectangle())
    }
}

/// The pause lengths, revealed under the row that offers them.
struct PillRow: View {
    var options: [PauseOption]
    var action: (PauseOption) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                Button(option.label) { action(option) }
                    .buttonStyle(PausePillStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

struct PausePillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .movezType(MovezType.menuSecondary)
            .foregroundStyle((configuration.isPressed ? Tokens.ink : Tokens.text2).color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(configuration.isPressed ? Tokens.accent.color : Tokens.accentTintSegmented.color)
            )
    }
}
