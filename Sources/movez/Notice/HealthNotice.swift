import Foundation

enum HealthNoticeError: LocalizedError {
    case resourceMissing
    case versionMissing

    var errorDescription: String? {
        switch self {
        case .resourceMissing: return "The health and safety notice is missing from the app bundle."
        case .versionMissing: return "The health and safety notice has no version line."
        }
    }
}

/// The health, safety and terms notice, read from the same `HEALTH_AND_SAFETY.md` the repository
/// publishes, so the app and the README can never show two different texts.
///
/// Foundation only, like `MovementLibrary`: the parser and the acceptance rule are tested without
/// any UI. The parser knows exactly the Markdown the notice uses — headings, paragraphs, bullets,
/// a rule, italic notes and inline bold — and nothing more.
struct HealthNotice: Equatable {
    enum Block: Equatable {
        case heading(String)
        case paragraph(String)
        case bullet(String)
        case rule
        case note(String)
    }

    static let resourceName = "HEALTH_AND_SAFETY"
    static let resourceExtension = "md"

    let title: String
    /// From the "Notice version 1.0 · Effective …" line. Bumping it is what asks everyone to
    /// accept again; a typo fix that leaves it alone does not.
    let version: String
    let effective: String
    let blocks: [Block]

    /// The bundled notice. Missing or unversioned, the app cannot ask anyone to accept it, so
    /// both are fatal at launch, like a missing library.
    static func loadBundled() throws -> HealthNotice {
        let url = MovezBundle.resources.url(forResource: resourceName, withExtension: resourceExtension)
            ?? Bundle.main.url(forResource: resourceName, withExtension: resourceExtension)
        guard let url else { throw HealthNoticeError.resourceMissing }
        return try parse(String(contentsOf: url, encoding: .utf8))
    }

    static func parse(_ markdown: String) throws -> HealthNotice {
        var title = ""
        var version: String?
        var effective = ""
        var blocks: [Block] = []
        var pending: [String] = []
        var pendingIsBullet = false

        func flush() {
            guard !pending.isEmpty else { return }
            let text = pending.joined(separator: " ")
            blocks.append(pendingIsBullet ? .bullet(text) : .paragraph(text))
            pending = []
            pendingIsBullet = false
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("## ") {
                flush()
                blocks.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flush()
                title = String(line.dropFirst(2))
            } else if line == "---" {
                flush()
                blocks.append(.rule)
            } else if let parsed = versionLine(line) {
                flush()
                version = parsed.version
                effective = parsed.effective
            } else if isMockButtonRow(line) {
                // The README shows the buttons as text; the app has real ones.
                flush()
            } else if line.hasPrefix("- ") {
                flush()
                pending = [String(line.dropFirst(2))]
                pendingIsBullet = true
            } else if line.hasPrefix("*"), line.hasSuffix("*"), !line.hasPrefix("**"), pending.isEmpty {
                blocks.append(.note(String(line.dropFirst().dropLast())))
            } else {
                // A continuation of the paragraph or bullet above: wrapped lines join with a space.
                pending.append(line)
            }
        }
        flush()

        guard let version else { throw HealthNoticeError.versionMissing }
        return HealthNotice(title: title, version: version, effective: effective, blocks: blocks)
    }

    /// "*Notice version 1.0 · Effective October 19, 2026*"
    private static func versionLine(_ line: String) -> (version: String, effective: String)? {
        let text = line.trimmingCharacters(in: CharacterSet(charactersIn: "*"))
        guard text.hasPrefix("Notice version ") else { return nil }
        let parts = text.dropFirst("Notice version ".count).components(separatedBy: "·")
        let version = parts[0].trimmingCharacters(in: .whitespaces)
        guard !version.isEmpty else { return nil }
        let effective = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        return (version, effective)
    }

    /// "[ Quit ]    [ I understand and agree ]"
    private static func isMockButtonRow(_ line: String) -> Bool {
        line.hasPrefix("[ ") && line.hasSuffix(" ]")
    }

    /// A block's text with its inline bold and italics applied, for display.
    static func styled(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

/// Whether the user has accepted the current notice. Kept apart from the window so the launch
/// gate is a plain rule a test can read.
enum NoticeAcceptance {
    static func isNeeded(acceptedVersion: String?, notice: HealthNotice) -> Bool {
        acceptedVersion != notice.version
    }
}
