import SwiftUI

/// One button system everywhere: the overlay uses the large size, every panel the small one.
enum ButtonSize {
    case overlay
    case panel

    var horizontalPadding: CGFloat { self == .overlay ? 48 : 18 }
    var verticalPadding: CGFloat { self == .overlay ? 20 : 9 }
    var style: MovezTextStyle { self == .overlay ? MovezType.backToWork : MovezType.panelButton }
}

/// Accent fill, ink text. The one thing the user is meant to do.
struct PrimaryButtonStyle: ButtonStyle {
    var size: ButtonSize = .panel

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .movezType(size.style)
            .foregroundStyle(Tokens.ink.color)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(Tokens.accent.color.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(Capsule())
    }
}

/// A 1.5 pt outline. The alternative the user might want.
struct SecondaryButtonStyle: ButtonStyle {
    var size: ButtonSize = .panel
    var accented = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .movezType(size.style)
            .foregroundStyle((accented ? Tokens.accent : Tokens.text2).color)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(
                Capsule().strokeBorder(
                    (accented ? Tokens.accent : Tokens.secondaryBorder).color,
                    lineWidth: 1.5
                )
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Snooze and Done in the overlay: a secondary button wearing the accent.
struct AccentOutlineButtonStyle: ButtonStyle {
    var size: ButtonSize = .overlay

    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonStyle(size: size, accented: true).makeBody(configuration: configuration)
    }
}

/// Skip, "I know this one", "Show instruction". Never a button — plain underlined text, because
/// the whole point is that skipping should be quieter than snoozing.
struct LinkActionStyle: ButtonStyle {
    var color: MovezColor = Tokens.text3
    var style: MovezTextStyle = MovezType.panelButton
    var disabled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .movezType(style)
            .foregroundStyle(color.color)
            .underline(true, pattern: .solid)
            .opacity(disabled ? 0.4 : (configuration.isPressed ? 0.7 : 1))
    }
}

/// Primary · secondary · link, in that order, centred, 12 pt apart.
struct ActionRow<Primary: View, Secondary: View, Link: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary
    @ViewBuilder var link: Link

    var body: some View {
        HStack(spacing: spacing) {
            primary
            secondary
            link
        }
    }
}
