import SwiftUI

/// The 38×22 switch used on every settings row.
struct MovezToggle: View {
    @Binding var isOn: Bool
    var enabled = true

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill((isOn ? Tokens.accent : Tokens.toggleOffTrack).color)
                Circle()
                    .fill((isOn ? Tokens.ink : Tokens.text2).color)
                    .padding(3)
            }
            .frame(width: Tokens.Metric.togglesize.width, height: Tokens.Metric.togglesize.height)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
        .accessibilityLabel(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

/// The preset and difficulty pickers.
struct SegmentedControl<Value: Hashable>: View {
    var options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    MovezText(
                        option.label,
                        MovezType.segment,
                        color: selection == option.value ? Tokens.ink : Tokens.text2,
                        alignment: .center
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(selection == option.value ? Tokens.accent.color : .clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Capsule().fill(Tokens.accentTintSegmented.color))
    }
}

/// An equipment chip.
struct Chip: View {
    var label: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            MovezText(label, MovezType.settingsRow, color: selected ? Tokens.ink : Tokens.text2)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(selected ? Tokens.accent.color : .clear)
                        .overlay(
                            Capsule().strokeBorder(selected ? .clear : Tokens.secondaryBorder.color, lineWidth: 1.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The outlined select field used for Focus and "Count me away after".
struct SelectField<Value: Hashable>: View {
    var options: [(value: Value, label: String)]
    @Binding var selection: Value
    var minWidth: CGFloat = 160

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button(option.label) { selection = option.value }
            }
        } label: {
            HStack(spacing: 8) {
                MovezText(label(for: selection), MovezType.settingsRow, color: Tokens.text)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Tokens.text3.color)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(width: minWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.select, style: .continuous)
                .strokeBorder(Tokens.panelBorder.color, lineWidth: 1)
        )
    }

    private func label(for value: Value) -> String {
        options.first { $0.value == value }?.label ?? ""
    }
}

/// The deferred-break explanation on the heads-up panel.
struct InfoBadge: View {
    var text: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle().fill(Tokens.warn.color).frame(width: 7, height: 7)
            MovezText(text, MovezType.badge, color: Tokens.text2)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        // The badge spans its panel. A pill that hugged its text would read as another button.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.badge, style: .continuous)
                .fill(Tokens.accentTintBadge.color)
        )
    }
}

/// "4 breaks in a row today" on the end-of-break screen.
struct StreakChip: View {
    var count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            MovezText("\(count)", MovezType.streakNumber, color: Tokens.accent)
            MovezText(label, MovezType.streakLabel, color: Tokens.accent)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
        .background(Capsule().fill(Tokens.accentTint.color))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(label)")
    }

    private var label: String {
        count == 1 ? "break in a row today" : "breaks in a row today"
    }
}

/// The uppercase accent label at the head of each settings section.
struct SectionLabel: View {
    var text: String

    var body: some View {
        MovezText(text, MovezType.sectionLabel, color: Tokens.accent)
    }
}

/// One row of the menu-bar dropdown.
struct MenuRow<Trailing: View>: View {
    var title: String
    var highlighted = false
    var dimmed = false
    var action: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                MovezText(title, MovezType.menuRow, color: dimmed ? Tokens.text3 : Tokens.text)
                Spacer(minLength: 6)
                trailing
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
                    .fill(highlighted ? Tokens.accentTint.color : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension MenuRow where Trailing == EmptyView {
    init(title: String, highlighted: Bool = false, dimmed: Bool = false, action: @escaping () -> Void) {
        self.init(title: title, highlighted: highlighted, dimmed: dimmed, action: action) { EmptyView() }
    }
}

/// The keyboard shortcut shown at the right of a menu row.
struct MenuShortcut: View {
    var text: String

    var body: some View {
        MovezText(text, MovezType.menuSecondary, color: Tokens.text3)
    }
}

/// A 1 pt divider.
struct MovezDivider: View {
    var color: MovezColor = Tokens.rule

    var body: some View {
        Rectangle().fill(color.color).frame(height: 1)
    }
}
