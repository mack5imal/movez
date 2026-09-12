import SwiftUI

/// The last screen of a break: what was done, the streak it built, and the way back to work.
struct OverlayEndView: View {
    var state: OverlayState
    var actions = OverlayActions()

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 0)
            VStack(spacing: 22) {
                MovezText(state.completionTitle, MovezType.endTitle, color: Tokens.text, alignment: .center)
                MovezText(state.endSummary, MovezType.endBody, color: Tokens.text2, alignment: .center)
                StreakChip(count: state.streak)
                Button("Back to work", action: actions.backToWork)
                    .buttonStyle(PrimaryButtonStyle(size: .overlay))
            }
            .frame(maxWidth: 780)
            Spacer(minLength: 0)
            SequenceStrip(items: state.strip, allAccent: true)
                .padding(.top, 28)
        }
        .padding(EdgeInsets(top: 56, leading: 80, bottom: 44, trailing: 80))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            MovezText(state.eyebrow, MovezType.eyebrowOverlay, color: Tokens.accent)
            Spacer(minLength: 24)
            MovezText(state.headerTrailing, MovezType.eyebrowOverlay, color: Tokens.text2)
        }
    }
}
