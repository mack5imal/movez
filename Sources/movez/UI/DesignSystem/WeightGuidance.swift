import SwiftUI

/// How to choose a dumbbell, in Strength settings and the first-switch sheet.
///
/// An `InfoBadge` variant: the same tinted card, with the Strength glyph where the deferred badge
/// has its dot, a bold lead sentence and the advice after it. It is never on the set screen, so
/// nothing interrupts a set to talk about weights.
struct WeightGuidance: View {
    static let lead = "Choosing a weight."
    // The copy is kept on one line so it reads exactly as the design writes it.
    // swiftlint:disable:next line_length
    static let advice = "Pick a weight you could lift 3–5 more times when the set ends. If the last reps feel easy, step up a size next time; if they feel hard, step down."

    /// The mode whose glyph leads the card.
    var definition: ModeDefinition = ModeDefinition.strength

    var body: some View {
        HStack(alignment: .top, spacing: ModeBadge.Size.weightGuidance.gap) {
            ModeGlyphView(glyph: ModeGlyph.badge(for: definition), size: ModeBadge.Size.weightGuidance.glyph)
            (
                Text(Self.lead)
                    .font(MovezType.guidanceLead.font)
                    .foregroundColor(Tokens.text.color)
                    + Text(" ")
                    + Text(Self.advice)
                    .font(MovezType.guidance.font)
                    .foregroundColor(Tokens.text2.color)
            )
            .lineSpacing(MovezType.guidance.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.badge, style: .continuous)
                .fill(Tokens.accentTintBadge.color)
        )
        .accessibilityElement(children: .combine)
    }
}
