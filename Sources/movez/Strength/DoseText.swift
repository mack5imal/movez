import Foundation

/// How a library dose reads on screen: the design's dose display rule (`design/HANDOFF.md
/// §strength-set`, "Dose display rule").
///
/// The library's text stays the only source; this only rewrites its shorthand. `/side` is written
/// for people who already know the notation, so it is spelt out, and the modifiers after the first
/// comma move to a quieter line of their own so the rep target reads first.
struct DoseText: Equatable {
    /// The rep target, time or hold: "12 reps", "10 each side".
    let line: String
    /// What qualifies it, on a line of its own: "Alternating · 2 s hold". Nil when there is none.
    let modifier: String?

    init(line: String, modifier: String?) {
        self.line = line
        self.modifier = modifier
    }

    init(_ dose: String) {
        // Split before rewriting, because the rewrite of "each direction/side" adds a comma of its
        // own that must not be mistaken for the library's.
        let trimmed = dose.trimmingCharacters(in: .whitespaces)
        let head: Substring
        let tail: Substring?
        if let comma = trimmed.firstIndex(of: ",") {
            head = trimmed[..<comma]
            tail = trimmed[trimmed.index(after: comma)...]
        } else {
            head = Substring(trimmed)
            tail = nil
        }

        line = Self.spellOutSides(String(head).trimmingCharacters(in: .whitespaces))

        let parts = (tail ?? "")
            .split(separator: ",")
            .map { Self.spellOutSides($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
        if parts.isEmpty {
            modifier = nil
        } else {
            let joined = parts.joined(separator: " · ")
            modifier = joined.prefix(1).uppercased() + joined.dropFirst()
        }
    }

    /// "10/side" → "10 each side"; "2 each direction/side" → "2 each direction, each side".
    private static func spellOutSides(_ text: String) -> String {
        text
            .replacingOccurrences(of: "each direction/side", with: "each direction, each side")
            .replacingOccurrences(of: "/side", with: " each side")
    }
}
