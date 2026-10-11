import SwiftUI

/// Every primitive in every state, on one page.
///
/// It exists so a change to a token or a control can be seen rather than argued about, and so the
/// snapshot harness has something to prove itself against before any real screen exists.
struct GalleryView: View {
    @State private var toggleOn = true
    @State private var toggleOff = false
    @State private var preset = "55/5"
    @State private var focus = "More upper back"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                MovezText("movez design system", MovezType.panelTitle, color: Tokens.text)
                colours
                typeScale
                buttons
                discs
                strips
                panels
                controls
            }
            .padding(40)
            .frame(width: 1400, alignment: .leading)
        }
        .scrollDisabled(true)
        .background(Tokens.panelSolid.color)
    }

    // MARK: - Sections

    private var colours: some View {
        section("Colours") {
            HStack(alignment: .top, spacing: 14) {
                ForEach(Self.swatches, id: \.name) { swatch in
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(swatch.color.color)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Tokens.panelBorder.color, lineWidth: 1)
                            )
                            .frame(width: 116, height: 60)
                        MovezText(swatch.name, MovezType.menuSecondary, color: Tokens.text2)
                        MovezText(swatch.label, MovezType.menuSecondary, color: Tokens.text3)
                    }
                }
            }
        }
    }

    private var typeScale: some View {
        section("Type — Manrope") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(MovezType.all.prefix(17), id: \.name) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 20) {
                        MovezText(entry.name, MovezType.menuSecondary, color: Tokens.text3)
                            .frame(width: 150, alignment: .leading)
                        MovezText(sample(for: entry.name), capped(entry.style), color: Tokens.text)
                    }
                }
            }
        }
    }

    private var buttons: some View {
        section("Buttons") {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Button("Back to work") {}.buttonStyle(PrimaryButtonStyle(size: .overlay))
                    Button("Snooze 5 min") {}.buttonStyle(AccentOutlineButtonStyle(size: .overlay))
                    Button("Secondary") {}.buttonStyle(SecondaryButtonStyle(size: .overlay))
                    Button("Skip · 1 today") {}
                        .buttonStyle(LinkActionStyle(color: Tokens.text3, style: MovezType.helperLink))
                }
                HStack(spacing: 12) {
                    Button("Start now") {}.buttonStyle(PrimaryButtonStyle())
                    Button("Snooze 5 min") {}.buttonStyle(SecondaryButtonStyle())
                    Button("Done") {}.buttonStyle(AccentOutlineButtonStyle(size: .panel))
                    Button("Skip · 1 today") {}.buttonStyle(LinkActionStyle())
                    Button("Skip · disabled 3 s") {}.buttonStyle(LinkActionStyle(disabled: true))
                }
            }
        }
    }

    private var discs: some View {
        section("Timer disc") {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .center, spacing: 26) {
                    discSample("progress 0", TimerDisc(size: 190, progress: 0, numerals: "1:00", label: "NEXT →"))
                    discSample("progress 0.5", TimerDisc(size: 190, progress: 0.5, numerals: "0:30", label: "NEXT →"))
                    discSample("progress 1", TimerDisc(size: 190, progress: 1, numerals: "0:00", label: "NEXT →"))
                    discSample(
                        "half share /side",
                        TimerDisc(
                            size: 190,
                            progress: 0.6,
                            numerals: "0:19",
                            label: "THEN RIGHT",
                            mode: .halfShare(sideIndex: 0)
                        )
                    )
                    discSample(
                        "half share · right",
                        TimerDisc(size: 190, progress: 0.4, numerals: "0:11", label: nil, mode: .halfShare(sideIndex: 1))
                    )
                }
                HStack(alignment: .center, spacing: 40) {
                    discSample("panel 64", TimerDisc(size: 64, progress: 0.4, numerals: "1:00", label: nil))
                    discSample("menu 40 · sitting", TimerDisc(size: 40, progress: 0.65, numerals: "32", label: nil))
                    discSample("menu 40 · paused", TimerDisc(size: 40, progress: 0, numerals: "", label: nil, mode: .dashed))
                    discSample("menu 40 · off hours", TimerDisc(size: 40, progress: 0, numerals: "", label: nil, mode: .empty))
                }
            }
        }
    }

    private var strips: some View {
        section("Sequence strip") {
            VStack(alignment: .leading, spacing: 26) {
                labelled("3 columns") {
                    SequenceStrip(items: Array(SnapshotFixtures.strip(currentIndex: 1).prefix(3)))
                }
                labelled("4 columns · current is a /side block, left half") {
                    SequenceStrip(items: SnapshotFixtures.strip(currentIndex: 1, sideIndex: 0))
                }
                labelled("5 columns") {
                    SequenceStrip(items: SnapshotFixtures.strip(currentIndex: 2) + [
                        StripItem(number: 5, name: "Box breathing", state: .upcoming, sideIndex: nil)
                    ])
                }
                labelled("all accent · end of break") {
                    SequenceStrip(items: SnapshotFixtures.strip(currentIndex: 4), allAccent: true)
                }
            }
        }
    }

    private var panels: some View {
        section("Panel and toast") {
            HStack(alignment: .top, spacing: 28) {
                PanelShell {
                    HStack(alignment: .top, spacing: 14) {
                        TimerDisc(size: 64, progress: 0.7, numerals: "1:00", label: nil)
                        VStack(alignment: .leading, spacing: 5) {
                            MovezText("MOVEMENT BREAK", MovezType.eyebrowPanel, color: Tokens.accent)
                            MovezText("Movement break in a minute", MovezType.panelTitle)
                            MovezText("Five minutes, five movements.", MovezType.panelBody, color: Tokens.text2)
                        }
                    }
                    InfoBadge(text: "Sitting for 1 h 35 m · break waited for your call")
                    HStack(spacing: 12) {
                        Button("Start now") {}.buttonStyle(PrimaryButtonStyle())
                        Button("Snooze 5 min") {}.buttonStyle(SecondaryButtonStyle())
                        Button("Skip · 1 today") {}.buttonStyle(LinkActionStyle())
                    }
                }
                ToastShell(remaining: 0.5) {
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(Tokens.accent.color).frame(width: 10, height: 10).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            MovezText("Away 7 min · counted as your break", MovezType.toastTitle)
                            MovezText("Next break at 14:02", MovezType.toastBody, color: Tokens.text2)
                        }
                        Spacer(minLength: 8)
                        Button("I was sitting") {}.buttonStyle(SecondaryButtonStyle())
                    }
                }
                StreakChip(count: SnapshotFixtures.streak)
            }
        }
    }

    private var controls: some View {
        section("Controls") {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 26) {
                    MovezToggle(isOn: $toggleOn)
                    MovezToggle(isOn: $toggleOff)
                    MovezToggle(isOn: $toggleOff, enabled: false)
                    SegmentedControl(
                        options: [("25/5", "25/5"), ("55/5", "55/5"), ("85/5", "85/5"), ("Custom", "Custom")],
                        selection: $preset
                    )
                    SelectField(
                        options: [("None", "None"), ("More upper back", "More upper back")],
                        selection: $focus
                    )
                }
                HStack(spacing: 12) {
                    Chip(label: "Band", selected: true, action: {})
                    Chip(label: "Kettlebell or dumbbell", selected: false, action: {})
                    Chip(label: "Roller", selected: false, action: {})
                    Chip(label: "Ball", selected: true, action: {})
                    SectionLabel(text: "Schedule")
                }
                VStack(spacing: 2) {
                    MenuRow(title: "Take a break now", highlighted: true, action: {})
                    MenuRow(title: "Make due in", action: {}, trailing: { MenuShortcut(text: "▸") })
                    MenuRow(title: "Take a break now", dimmed: true, action: {})
                    MenuRow(title: "Settings…", action: {}, trailing: { MenuShortcut(text: "⌘,") })
                }
                .frame(width: Tokens.Metric.menuWidth)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.menu, style: .continuous)
                        .fill(Tokens.panelMenu.color)
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.menu, style: .continuous)
                                .strokeBorder(Tokens.panelBorder.color, lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: title)
            content()
        }
    }

    @ViewBuilder
    private func labelled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MovezText(title, MovezType.menuSecondary, color: Tokens.text3)
            content()
        }
        .frame(width: 900, alignment: .leading)
    }

    @ViewBuilder
    private func discSample(_ title: String, _ disc: TimerDisc) -> some View {
        VStack(spacing: 10) {
            disc
            MovezText(title, MovezType.menuSecondary, color: Tokens.text3)
        }
        .frame(width: 160)
    }

    /// The display sizes are too tall for a gallery row, so they are shown at a readable size with
    /// their real weight and tracking.
    private func capped(_ style: MovezTextStyle) -> MovezTextStyle {
        guard style.size > 34 else { return style }
        var capped = style
        capped.size = 34
        return capped
    }

    private func sample(for name: String) -> String {
        switch name {
        case "eyebrowOverlay", "eyebrowPanel": return "Movement break · micro-break"
        case "discNumerals", "panelDisc", "menuDisc": return "0:42"
        case "discLabel": return "Next →"
        default: return "March in place"
        }
    }

    private struct Swatch {
        var name: String
        var label: String
        var color: MovezColor
    }

    private static let swatches: [Swatch] = [
        Swatch(name: "ink", label: Tokens.ink.hexString, color: Tokens.ink),
        Swatch(name: "accent", label: Tokens.accent.hexString, color: Tokens.accent),
        Swatch(name: "text", label: Tokens.text.hexString, color: Tokens.text),
        Swatch(name: "text-2", label: Tokens.text2.hexString, color: Tokens.text2),
        Swatch(name: "text-3", label: Tokens.text3.hexString, color: Tokens.text3),
        Swatch(name: "warn", label: Tokens.warn.hexString, color: Tokens.warn),
        Swatch(name: "panel .92", label: "rgba(18,42,58,.92)", color: Tokens.panel),
        Swatch(name: "panel solid", label: Tokens.panelSolid.hexString, color: Tokens.panelSolid),
        Swatch(name: "border .28", label: "rgba(127,200,183,.28)", color: Tokens.panelBorder),
        Swatch(name: "dim .86", label: "rgba(8,22,34,.86)", color: Tokens.dim)
    ]
}
