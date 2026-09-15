import SwiftUI

/// The rounded, bordered card every floating panel sits in.
struct PanelShell<Content: View>: View {
    var width: CGFloat = Tokens.Metric.panelWidth
    var fill: MovezColor = Tokens.panelSmall
    var cornerRadius: CGFloat = Tokens.Radius.panel
    var padding = EdgeInsets(top: 18, leading: 20, bottom: 16, trailing: 20)
    var spacing: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(padding)
        .frame(width: width, alignment: .leading)
        .background(fill.color)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Tokens.panelBorder.color, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .movezShadow(Tokens.Shadow.panel)
    }
}

/// The away toast: a small panel with a hairline that shrinks away over its time on screen.
struct ToastShell<Content: View>: View {
    var width: CGFloat = Tokens.Metric.toastWidth
    /// 1 when the toast appears, 0 as it leaves.
    var remaining: Double = 1
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
            hairline
        }
        .frame(width: width, alignment: .leading)
        .background(Tokens.panelSmall.color)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.toast, style: .continuous)
                .strokeBorder(Tokens.panelBorder.color, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.toast, style: .continuous))
        .movezShadow(Tokens.Shadow.panel)
    }

    private var hairline: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Tokens.rule.color)
                Rectangle()
                    .fill(Tokens.accent.color)
                    .frame(width: geometry.size.width * max(0, min(1, remaining)))
            }
        }
        .frame(height: 2)
    }
}
