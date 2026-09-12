import Foundation

/// WCAG 2.1 contrast, so the palette's legibility is a number in a test rather than an opinion.
enum Contrast {
    /// The minimum ratio WCAG AA asks of body text.
    static let aa: Double = 4.5

    static func relativeLuminance(_ color: MovezColor) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }

    static func ratio(_ first: MovezColor, _ second: MovezColor) -> Double {
        let lighter = max(relativeLuminance(first), relativeLuminance(second))
        let darker = min(relativeLuminance(first), relativeLuminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// The panel fills are translucent, so the colour text actually sits on is the composite.
    static func composite(_ top: MovezColor, over bottom: MovezColor) -> MovezColor {
        func blend(_ topValue: Double, _ bottomValue: Double) -> Double {
            topValue * top.alpha + bottomValue * (1 - top.alpha)
        }
        return MovezColor(
            red: blend(top.red, bottom.red),
            green: blend(top.green, bottom.green),
            blue: blend(top.blue, bottom.blue)
        )
    }
}
