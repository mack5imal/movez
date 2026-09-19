import SwiftUI

/// The dropdown as a snapshot: the menu under a stand-in menu bar, over a placeholder desktop —
/// the framing `screenshots/3b-menu-dropdown.png` uses, so the two can be held side by side.
struct MenuSnapshot: View {
    var state: MenuBarState

    /// The light desktop the handoff draws its menus over.
    private static let desktop = MovezColor(hex: 0xD9D6_CF)
    private static let bar = MovezColor(hex: 0xF2F0_EA)
    private static let barInk = MovezColor(hex: 0x2A30_35)

    private static let barHeight: CGFloat = 26

    var body: some View {
        ZStack(alignment: .top) {
            Self.desktop.color
            VStack(spacing: 0) {
                menuBar
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    MenuBarView(state: state)
                        .padding(.top, 6)
                        .padding(.trailing, 28)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// The system menu bar, only as far as it takes to show where the icon sits.
    private var menuBar: some View {
        ZStack(alignment: .trailing) {
            Self.bar.color
            HStack(spacing: 6) {
                Image(nsImage: MenuBarIcon.image(for: state, size: 12))
                    .renderingMode(.template)
                if !state.labelText.isEmpty {
                    MovezText(state.labelText, MovezType.menuSecondary, color: Self.barInk)
                }
            }
            .foregroundStyle(Self.barInk.color)
            .padding(.horizontal, 12)
        }
        .frame(height: Self.barHeight)
    }
}

/// The menu-bar glyph at the moments worth looking at, drawn large enough to judge.
struct MenuIconStrip: View {
    struct Sample: Identifiable {
        var id: String { caption }
        var mode: MenuBarState.Mode
        var fraction: Double
        var caption: String
        var label: String
    }

    static let samples: [Sample] = [
        Sample(mode: .sitting, fraction: 0, caption: "fresh bout", label: "55m"),
        Sample(mode: .sitting, fraction: 0.42, caption: "42% elapsed", label: "32m"),
        Sample(mode: .sitting, fraction: 0.9, caption: "90% elapsed", label: "6m"),
        Sample(mode: .paused, fraction: 0, caption: "paused", label: "‖ 42m"),
        Sample(mode: .away, fraction: 0, caption: "away", label: "—"),
        Sample(mode: .offHours, fraction: 0, caption: "off hours", label: "")
    ]

    /// Drawn at four times the menu bar's 12 pt so the arc is actually judgeable.
    static let drawSize: CGFloat = 48

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            ForEach(Self.samples) { sample in
                VStack(spacing: 14) {
                    Image(nsImage: MenuBarIcon.image(mode: sample.mode, fraction: sample.fraction, size: Self.drawSize))
                        .renderingMode(.template)
                        .foregroundStyle(Tokens.text.color)
                        .frame(width: Self.drawSize, height: Self.drawSize)
                    MovezText(sample.label, MovezType.menuRow, color: Tokens.text, alignment: .center)
                    MovezText(sample.caption, MovezType.menuSecondary, color: Tokens.text3, alignment: .center)
                }
                .frame(width: 110)
            }
        }
        .padding(40)
    }
}
