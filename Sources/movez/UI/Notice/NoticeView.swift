import SwiftUI

/// The health and safety notice in a window of its own: the full text scrolling between a title
/// bar and a footer with the buttons, in the settings window's palette.
struct NoticeScreen: View {
    @ObservedObject var viewModel: NoticeViewModel

    static let size = CGSize(width: 720, height: 760)

    var body: some View {
        ZStack {
            Tokens.panelSolid.color
            VStack(spacing: 0) {
                titleBar
                ScrollView {
                    NoticeText(notice: viewModel.notice, versionLine: viewModel.versionLine) {
                        viewModel.endReached()
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 28)
                }
                footer
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var titleBar: some View {
        MovezText("Health, safety and terms", MovezType.menuTitle, alignment: .center)
            .frame(maxWidth: .infinity)
            .frame(height: SettingsScreen.titleBarHeight)
            .overlay(alignment: .bottom) { MovezDivider(color: Tokens.ruleSettings) }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if let accepted = viewModel.acceptedLine {
                    MovezText(accepted, MovezType.version, color: Tokens.text3)
                }
                Spacer(minLength: 16)
                switch viewModel.mode {
                case .accept:
                    Button("Quit", action: viewModel.quit)
                        .buttonStyle(SecondaryButtonStyle())
                    Button("I understand and agree", action: viewModel.agree)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!viewModel.canAgree)
                        .opacity(viewModel.canAgree ? 1 : 0.4)
                        .keyboardShortcut(.defaultAction)
                case .read:
                    Button("Close", action: viewModel.close)
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            if let hint = viewModel.hint {
                MovezText(hint, MovezType.version, color: Tokens.text3)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .overlay(alignment: .top) { MovezDivider(color: Tokens.ruleSettings) }
    }
}

/// The notice's blocks, set in the app's type. A lazy stack, so the sentinel at the end only
/// appears — and only reports — once it has actually scrolled into view.
struct NoticeText: View {
    let notice: HealthNotice
    let versionLine: String
    var onEndReached: () -> Void = {}

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            MovezText(notice.title, MovezType.panelTitle)
            MovezText(versionLine, MovezType.version, color: Tokens.text2)
                .padding(.bottom, 6)
            ForEach(Array(notice.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
            Color.clear
                .frame(height: 1)
                .onAppear(perform: onEndReached)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: HealthNotice.Block) -> some View {
        switch block {
        case .heading(let text):
            MovezText(text, MovezType.settingsTitle)
                .padding(.top, 12)
        case .paragraph(let text):
            styled(text, color: Tokens.text)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").movezType(MovezType.panelBody).foregroundStyle(Tokens.text2.color)
                styled(text, color: Tokens.text)
            }
            .padding(.leading, 6)
        case .rule:
            MovezDivider(color: Tokens.ruleSettings)
                .padding(.vertical, 8)
        case .note(let text):
            styled(text, color: Tokens.text)
                .italic()
        }
    }

    private func styled(_ text: String, color: MovezColor) -> some View {
        Text(HealthNotice.styled(text))
            .movezType(MovezType.panelBody)
            .foregroundStyle(color.color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
