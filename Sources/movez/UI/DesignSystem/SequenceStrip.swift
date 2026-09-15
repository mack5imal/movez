import SwiftUI

/// One column of the sequence strip under the overlay.
struct StripItem: Equatable, Identifiable {
    enum State: Equatable {
        case done
        case current
        case upcoming
    }

    var number: Int
    var name: String
    var state: State
    /// For a per-side block in progress: 0 while the left half runs, 1 once the right does.
    var sideIndex: Int?

    var id: Int { number }
}

/// The four-or-so columns under the overlay body that show where you are in the break.
struct SequenceStrip: View {
    var items: [StripItem]
    /// The end state paints every column accent, with nothing struck through.
    var allAccent = false

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Metric.stripGap) {
            ForEach(items) { item in
                column(item)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func column(_ item: StripItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            rule(for: item)
            MovezText("\(item.number)", MovezType.stripNumber, color: numberColor(item))
            name(item)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(announcement(for: item))
    }

    /// "March in place, block 1 of 4, current" — read from standing distance, or not at all.
    func announcement(for item: StripItem) -> String {
        var parts = ["\(item.name), block \(item.number) of \(items.count)"]
        switch item.state {
        case .current: parts.append("current")
        case .done: parts.append("done")
        case .upcoming: parts.append("upcoming")
        }
        if let side = item.sideIndex { parts.append(side == 0 ? "left side" : "right side") }
        return parts.joined(separator: ", ")
    }

    /// The 3 pt rule above each column. A per-side block in progress fills only its half.
    @ViewBuilder
    private func rule(for item: StripItem) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let accentWidth: CGFloat = {
                guard !allAccent else { return width }
                switch item.state {
                case .current:
                    guard let side = item.sideIndex else { return width }
                    return side == 0 ? width / 2 : width
                case .done, .upcoming:
                    return 0
                }
            }()

            ZStack(alignment: .leading) {
                Rectangle().fill(Tokens.ruleInactive.color)
                Rectangle().fill(Tokens.accent.color).frame(width: accentWidth)
            }
        }
        .frame(height: Tokens.Metric.stripRule)
    }

    @ViewBuilder
    private func name(_ item: StripItem) -> some View {
        // Two lines, then smaller type, and never an ellipsis: the column is a quarter of the card.
        let text = MovezText(item.name, MovezType.stripName, color: numberColor(item), lineLimit: 2, minimumScaleFactor: 0.7)
        if item.state == .done, !allAccent {
            text.strikethrough(true, color: Tokens.text3.color)
        } else {
            text
        }
    }

    private func numberColor(_ item: StripItem) -> MovezColor {
        if allAccent { return Tokens.text }
        return item.state == .current ? Tokens.text : Tokens.text3
    }
}
