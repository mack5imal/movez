import AppKit
import CoreText
import SwiftUI

/// Manrope registration and resolution.
///
/// The variable TTF ships in `Resources/Fonts`. `ATSApplicationFontsPath` registers it for the
/// running app, but unit tests and offscreen renderers need an explicit, idempotent registration.
enum MovezFont {
    static let familyName = "Manrope"

    private static let registrationLock = NSLock()
    nonisolated(unsafe) private static var didRegister = false

    /// Registers every `.ttf` in the bundled `Fonts` directory. Safe to call repeatedly.
    @discardableResult
    static func register() -> Bool {
        registrationLock.lock()
        defer { registrationLock.unlock() }
        if didRegister { return true }

        for url in fontURLs() {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Re-registration of an already-registered file is expected and harmless.
                error?.release()
            }
        }
        didRegister = isAvailable
        // A missing font is not fatal — `nsFont` falls back to the system face and movez still
        // runs — but it is loud in a Debug build, because every screen would be off-design.
        assert(didRegister, "Manrope did not register; movez is drawing in the system face")
        return didRegister
    }

    /// True when the Manrope family can be resolved by the font manager.
    static var isAvailable: Bool {
        NSFontManager.shared.availableFontFamilies.contains(familyName)
    }

    /// Every bundled Manrope face, searched in the app bundle and in the source tree
    /// (the latter keeps offscreen tooling working before the resource copy phase runs).
    static func fontURLs() -> [URL] {
        var urls: [URL] = []
        if let resourceURL = MovezBundle.resources.resourceURL {
            let fontsDirectory = resourceURL.appendingPathComponent("Fonts", isDirectory: true)
            urls.append(contentsOf: ttfFiles(in: fontsDirectory))
            if urls.isEmpty { urls.append(contentsOf: ttfFiles(in: resourceURL)) }
        }
        return urls
    }

    private static func ttfFiles(in directory: URL) -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return (contents ?? []).filter { $0.pathExtension.lowercased() == "ttf" }
    }

    /// Resolved faces, keyed by size and weight.
    ///
    /// There are thirty-odd styles in the app and the overlay redraws every second, so resolving
    /// a descriptor — under the registration lock — for each of fifteen text views per frame is
    /// most of what drawing a break costs.
    private static let faceLock = NSLock()
    nonisolated(unsafe) private static var faces: [String: NSFont] = [:]

    /// An `NSFont` on the Manrope weight axis, falling back to the system face if registration failed.
    static func nsFont(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        register()
        let key = "\(size)-\(weight.rawValue)"

        faceLock.lock()
        defer { faceLock.unlock() }
        if let cached = faces[key] { return cached }

        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: familyName,
            .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]
        ])
        let face = NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: weight)
        faces[key] = face
        return face
    }

    /// A SwiftUI `Font` on the Manrope weight axis.
    static func manrope(_ size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        Font(nsFont(size, weight: weight) as CTFont)
    }
}
