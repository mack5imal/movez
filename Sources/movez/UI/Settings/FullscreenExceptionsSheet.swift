import AppKit
import SwiftUI

/// The apps whose fullscreen mode movez should ignore.
///
/// The fullscreen signal is the bluntest of the three: a maximised editor looks exactly like a
/// presentation. The exceptions list is how the user sharpens it.
struct FullscreenExceptionsSheet: View {
    @ObservedObject var viewModel: SettingsViewModel

    static let size = CGSize(width: 480, height: 420)
    @State private var candidate = ""

    var body: some View {
        SheetShell(title: "Fullscreen exceptions", width: Self.size.width, height: Self.size.height) {
            VStack(alignment: .leading, spacing: 10) {
                MovezText(
                    "Breaks still arrive while these apps are fullscreen.",
                    MovezType.version,
                    color: Tokens.text3
                )
                exceptionList
                Spacer(minLength: 0)
                addRow
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 8, trailing: 20))

            MovezDivider(color: Tokens.ruleSettings)
            SheetActions { viewModel.openSheet = nil }
        }
    }

    @ViewBuilder
    private var exceptionList: some View {
        if viewModel.settings.fullscreenExceptions.isEmpty {
            MovezText("No exceptions yet.", MovezType.settingsRow, color: Tokens.text3)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 0) {
                ForEach(viewModel.settings.fullscreenExceptions, id: \.self) { bundleId in
                    ExceptionRow(bundleId: bundleId) { viewModel.removeException(bundleId) }
                    MovezDivider(color: Tokens.ruleSettings)
                }
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 12) {
            MovezText("Add running app", MovezType.settingsRow)
            Spacer(minLength: 12)
            SelectField(
                options: [(value: "", label: "Choose…")] + viewModel.exceptionCandidates(),
                selection: Binding(
                    get: { candidate },
                    set: { bundleId in
                        candidate = ""
                        viewModel.addException(bundleId)
                    }
                ),
                minWidth: 200
            )
        }
    }
}

/// One exception: the app's own icon and name, and the way back out.
struct ExceptionRow: View {
    var bundleId: String
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let icon = SettingsViewModel.applicationIcon(for: bundleId) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                MovezText(SettingsViewModel.applicationName(for: bundleId), MovezType.settingsRow)
                MovezText(bundleId, MovezType.version, color: Tokens.text3)
            }
            Spacer(minLength: 12)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Tokens.text3.color)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(bundleId)")
        }
        .padding(.vertical, 8)
    }
}
