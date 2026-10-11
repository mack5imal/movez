import SwiftUI

/// Every movement in the library, searchable, with a switch to take any of them out of rotation.
///
/// Excluding is deliberately the only thing this sheet does. The library is the app's content and
/// the routine builder owns which movement runs when; the user's say is "not this one".
struct LibraryBrowserSheet: View {
    @ObservedObject var viewModel: SettingsViewModel

    static let size = CGSize(width: 560, height: 520)

    var body: some View {
        SheetShell(title: "Movement library", width: Self.size.width, height: Self.size.height) {
            VStack(alignment: .leading, spacing: 10) {
                search
                buckets
                header
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 8, trailing: 20))

            MovezDivider(color: Tokens.ruleSettings)
            list
            MovezDivider(color: Tokens.ruleSettings)
            SheetActions { viewModel.openSheet = nil }
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Tokens.text3.color)
            TextField("Search by name or id", text: $viewModel.librarySearch)
                .textFieldStyle(.plain)
                .movezType(MovezType.settingsRow)
                .foregroundStyle(Tokens.text.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.select, style: .continuous)
                .strokeBorder(Tokens.panelBorder.color, lineWidth: 1)
        )
    }

    private var buckets: some View {
        HStack(spacing: 6) {
            Chip(label: "All", selected: viewModel.libraryBucket == nil) { viewModel.libraryBucket = nil }
            ForEach(Bucket.allCases, id: \.self) { bucket in
                Chip(label: bucket.rawValue, selected: viewModel.libraryBucket == bucket) {
                    viewModel.libraryBucket = bucket
                }
            }
        }
    }

    private var header: some View {
        HStack {
            MovezText(viewModel.excludedLine, MovezType.settingsRow, color: Tokens.text2)
            Spacer(minLength: 8)
            MovezText("\(viewModel.matchingMovements().count) shown", MovezType.version, color: Tokens.text3)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.matchingMovements(), id: \.id) { movement in
                    LibraryRow(
                        movement: movement,
                        excluded: viewModel.isExcluded(movement.id),
                        unavailable: viewModel.settings.unavailableRequirements,
                        setExcluded: { viewModel.setExcluded(movement.id, $0) }
                    )
                    MovezDivider(color: Tokens.ruleSettings)
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(maxHeight: .infinity)
    }
}

/// One movement: what it is, how hard it is, and whether it is in rotation.
struct LibraryRow: View {
    var movement: Movement
    var excluded: Bool
    /// What the user has said they do not have. A movement that needs it is shown dimmed: it is
    /// out of rotation whatever its switch says.
    var unavailable: Set<Requirement> = []
    var setExcluded: (Bool) -> Void

    private var outOfReach: Bool { movement.needsAny(of: unavailable) }

    var body: some View {
        HStack(spacing: 12) {
            MovezText(movement.id, MovezType.version, color: Tokens.text3)
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                MovezText(movement.name, MovezType.settingsRow, color: excluded || outOfReach ? Tokens.text3 : Tokens.text)
                MovezText(subtitle, MovezType.version, color: Tokens.text3)
            }
            Spacer(minLength: 12)
            MovezToggle(isOn: Binding(get: { !excluded }, set: { setExcluded(!$0) }))
        }
        .padding(.vertical, 9)
        .opacity(excluded || outOfReach ? 0.75 : 1)
    }

    /// "Strength · Diff 1 · needs floor", or "Circulation & metabolic · Diff 1 · micro"
    var subtitle: String {
        var parts = [movement.bucket.displayName, "Diff \(movement.difficulty)"]
        if !movement.requires.isEmpty {
            parts.append("needs " + movement.requires.map(\.displayName).joined(separator: " and "))
        }
        if movement.microEligible { parts.append("micro") }
        return parts.joined(separator: " · ")
    }
}
