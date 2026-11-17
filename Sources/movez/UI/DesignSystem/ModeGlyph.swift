import SwiftUI

/// A mode's glyph: the line drawing in front of its name on every badge and inside the menu-bar
/// circle.
///
/// The vectors are the design's, written on its 20×20 grid and scaled to whatever box the glyph is
/// drawn in. A glyph is only ever stroked, never filled, with round caps and joins. Which glyph a
/// mode wears is not decided here: `ModeDefinition` names it by id, and `named(_:)` looks it up, so
/// a mode added later picks a glyph without a branch anywhere in the UI.
struct ModeGlyph: Shape {
    /// One piece of a glyph, in grid units with y pointing down, as the design writes them.
    enum Element {
        case move(CGPoint)
        case line(CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        /// A rounded corner from the current point, as SVG's quarter arcs draw one.
        case corner(CGPoint, then: CGPoint, radius: CGFloat)
        case roundedRect(CGRect, radius: CGFloat)
    }

    /// The design's grid.
    static let grid: CGFloat = 20
    /// The badge stroke on the 20-unit grid; it scales with the glyph.
    static let gridStroke: CGFloat = 1.8

    let id: String
    let elements: [Element]

    /// The stroke width the design gives a badge glyph drawn `size` points square.
    static func badgeStroke(size: CGFloat) -> CGFloat { gridStroke * size / grid }

    func path(in rect: CGRect) -> Path {
        Path(cgPath(in: rect))
    }

    /// The glyph scaled into `rect`, for SwiftUI and for the AppKit drawing of the menu-bar icon
    /// alike, so both draw the same vectors.
    func cgPath(in rect: CGRect) -> CGPath {
        let scale = min(rect.width, rect.height) / Self.grid
        let origin = CGPoint(
            x: rect.midX - Self.grid * scale / 2,
            y: rect.midY - Self.grid * scale / 2
        )
        func point(_ grid: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + grid.x * scale, y: origin.y + grid.y * scale)
        }

        let path = CGMutablePath()
        for element in elements {
            switch element {
            case .move(let to):
                path.move(to: point(to))
            case .line(let to):
                path.addLine(to: point(to))
            case let .curve(to, control1, control2):
                path.addCurve(to: point(to), control1: point(control1), control2: point(control2))
            case let .corner(corner, then, radius):
                path.addArc(tangent1End: point(corner), tangent2End: point(then), radius: radius * scale)
            case let .roundedRect(box, radius):
                let scaled = CGRect(origin: point(box.origin), size: CGSize(width: box.width * scale, height: box.height * scale))
                path.addRoundedRect(in: scaled, cornerWidth: radius * scale, cornerHeight: radius * scale)
            }
        }
        return path
    }

    // MARK: - The four glyphs

    /// A sine wave.
    static let movement = ModeGlyph(id: "mode.movement", elements: [
        .move(CGPoint(x: 2, y: 10)),
        .curve(to: CGPoint(x: 10, y: 10), control1: CGPoint(x: 4.5, y: 4), control2: CGPoint(x: 7.5, y: 4)),
        // The design's `S` reflects the previous control point through (10, 10).
        .curve(to: CGPoint(x: 18, y: 10), control1: CGPoint(x: 12.5, y: 16), control2: CGPoint(x: 15.5, y: 16))
    ])

    /// A dumbbell.
    static let strength = ModeGlyph(id: "mode.strength", elements: [
        .roundedRect(CGRect(x: 3.5, y: 5, width: 3.5, height: 10), radius: 1.2),
        .roundedRect(CGRect(x: 13, y: 5, width: 3.5, height: 10), radius: 1.2),
        .move(CGPoint(x: 7, y: 10)), .line(CGPoint(x: 13, y: 10)),
        .move(CGPoint(x: 1.5, y: 10)), .line(CGPoint(x: 3.5, y: 10)),
        .move(CGPoint(x: 16.5, y: 10)), .line(CGPoint(x: 18.5, y: 10))
    ])

    /// A tally of five.
    static let hundreds = ModeGlyph(id: "mode.hundreds", elements: [4.5, 8, 11.5, 15].flatMap { column -> [Element] in
        [.move(CGPoint(x: column, y: 4)), .line(CGPoint(x: column, y: 16))]
    } + [
        .move(CGPoint(x: 2.5, y: 14)), .line(CGPoint(x: 17.5, y: 6))
    ])

    /// A clipboard with a tick.
    static let personalTraining = ModeGlyph(id: "mode.pt", elements: [
        .move(CGPoint(x: 7.5, y: 4)),
        .line(CGPoint(x: 6.5, y: 4)),
        .corner(CGPoint(x: 4.5, y: 4), then: CGPoint(x: 4.5, y: 6), radius: 2),
        .line(CGPoint(x: 4.5, y: 15.5)),
        .corner(CGPoint(x: 4.5, y: 17.5), then: CGPoint(x: 6.5, y: 17.5), radius: 2),
        .line(CGPoint(x: 13.5, y: 17.5)),
        .corner(CGPoint(x: 15.5, y: 17.5), then: CGPoint(x: 15.5, y: 15.5), radius: 2),
        .line(CGPoint(x: 15.5, y: 6)),
        .corner(CGPoint(x: 15.5, y: 4), then: CGPoint(x: 13.5, y: 4), radius: 2),
        .line(CGPoint(x: 12.5, y: 4)),
        .roundedRect(CGRect(x: 7.5, y: 2.5, width: 5, height: 3), radius: 1),
        .move(CGPoint(x: 7.5, y: 11)), .line(CGPoint(x: 9.5, y: 13)), .line(CGPoint(x: 13, y: 9))
    ])

    /// Every glyph the design draws, by id. 100s and PT have glyphs but no mode yet.
    static let library: [String: ModeGlyph] = Dictionary(
        uniqueKeysWithValues: [movement, strength, hundreds, personalTraining].map { ($0.id, $0) }
    )

    /// The glyph a definition names, or nil for an id the design has not drawn.
    static func named(_ id: String) -> ModeGlyph? { library[id] }

    /// The glyph in front of the mode's name on badges and mode controls.
    static func badge(for definition: ModeDefinition) -> ModeGlyph? { named(definition.badgeGlyph) }

    /// The glyph inside the menu-bar circle.
    static func menuBar(for definition: ModeDefinition) -> ModeGlyph? { named(definition.menuBarGlyph) }
}

/// A glyph stroked at the design's weight for its size.
struct ModeGlyphView: View {
    var glyph: ModeGlyph?
    var size: CGFloat
    var color: MovezColor = Tokens.accent

    var body: some View {
        Group {
            if let glyph {
                glyph.stroke(
                    color.color,
                    style: StrokeStyle(lineWidth: ModeGlyph.badgeStroke(size: size), lineCap: .round, lineJoin: .round)
                )
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
