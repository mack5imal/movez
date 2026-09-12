import SwiftUI

/// The card every settings sheet sits in.
struct SheetShell<Content: View>: View {
    var title: String
    var width: CGFloat
    var height: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MovezText(title, MovezType.settingsTitle)
                .padding(EdgeInsets(top: 16, leading: 20, bottom: 14, trailing: 20))
            MovezDivider(color: Tokens.ruleSettings)
            content
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Tokens.panelSolid.color)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.settings, style: .continuous)
                .strokeBorder(Tokens.panelBorder.color, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.settings, style: .continuous))
        .movezShadow(Tokens.Shadow.menu)
    }
}

/// Cancel on the left of Apply, the way every sheet in the app ends.
struct SheetActions: View {
    var confirmTitle = "Done"
    var cancel: (() -> Void)?
    var confirm: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            if let cancel {
                Button("Cancel", action: cancel)
                    .buttonStyle(SecondaryButtonStyle())
            }
            Button(confirmTitle, action: confirm)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(EdgeInsets(top: 14, leading: 20, bottom: 16, trailing: 20))
    }
}

/// One window a day, seven days, with a switch for the days movez should stay quiet on.
///
/// Times are chosen from fifteen-minute steps rather than typed: a working day that starts at
/// 09:07 is not a thing anyone means, and a select field can wear the app's palette where a
/// `DatePicker` cannot.
struct WorkingHoursPopover: View {
    @ObservedObject var viewModel: SettingsViewModel

    static let stepMinutes = 15
    static let width: CGFloat = 460

    static var startOptions: [(value: Int, label: String)] {
        stride(from: 0, to: 24 * 60, by: stepMinutes).map { ($0, DayHours.label(minutes: $0)) }
    }

    /// The end of a day may be midnight itself, which no start may be.
    static var endOptions: [(value: Int, label: String)] {
        startOptions.dropFirst() + [(24 * 60, "24:00")]
    }

    var body: some View {
        SheetShell(title: "Working hours", width: Self.width) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(WorkingHours.displayOrder, id: \.self) { weekday in
                    row(index: weekday - 1)
                }
                if let error = viewModel.hoursError {
                    MovezText(error, MovezType.version, color: Tokens.warn)
                        .padding(.top, 2)
                }
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 4, trailing: 20))

            SheetActions(confirmTitle: "Apply", cancel: { viewModel.openSheet = nil }, confirm: viewModel.applyHours)
        }
    }

    private func row(index: Int) -> some View {
        let day = viewModel.hoursDraft.days[index]
        return HStack(spacing: 12) {
            MovezToggle(isOn: $viewModel.hoursDraft.days[index].enabled)
            MovezText(WorkingHours.shortNames[index], MovezType.settingsRow, color: day.enabled ? Tokens.text : Tokens.text3)
                .frame(width: 40, alignment: .leading)
            Spacer(minLength: 8)
            SelectField(
                options: Self.startOptions,
                selection: $viewModel.hoursDraft.days[index].startMinutes,
                minWidth: 96,
                accessibilityName: "\(WorkingHours.shortNames[index]) start"
            )
            MovezText("–", MovezType.settingsRow, color: Tokens.text3)
            SelectField(
                options: Self.endOptions,
                selection: $viewModel.hoursDraft.days[index].endMinutes,
                minWidth: 96,
                accessibilityName: "\(WorkingHours.shortNames[index]) end"
            )
        }
        .opacity(day.enabled ? 1 : 0.55)
    }
}
