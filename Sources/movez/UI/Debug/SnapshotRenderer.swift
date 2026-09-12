import AppKit
import SwiftUI

/// Every surface `movez --snapshot` can render.
///
/// This is the evidence mechanism for the UI: each screen can be produced offscreen, at 2×, with
/// fixture data, and looked at — by a person or by a build — without waiting an hour for a break.
enum SnapshotSurface: String, CaseIterable {
    case gallery

    /// The point size the surface is rendered at.
    var size: CGSize {
        switch self {
        case .gallery: return CGSize(width: 1400, height: 2900)
        }
    }

    /// The colour behind the surface, so panels are legible against something.
    var backdrop: MovezColor {
        switch self {
        case .gallery: return Tokens.panelSolid
        }
    }
}

enum SnapshotError: LocalizedError {
    case unknownSurface(String)
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownSurface(let name):
            let known = SnapshotSurface.allCases.map(\.rawValue).joined(separator: ", ")
            return "Unknown surface \"\(name)\". Known surfaces: \(known)"
        case .renderFailed(let reason):
            return "Could not render the surface: \(reason)"
        }
    }
}

/// Renders a SwiftUI surface to a PNG without ever showing it to anyone.
@MainActor
enum SnapshotRenderer {
    /// Snapshots are written at 2× so text can actually be read in the PNG.
    static let scale: CGFloat = 2

    static func view(for surface: SnapshotSurface) -> AnyView {
        switch surface {
        case .gallery: return AnyView(GalleryView())
        }
    }

    /// Renders one surface and writes it as a PNG.
    static func render(_ surface: SnapshotSurface, to url: URL) throws {
        let size = surface.size
        let content = ZStack {
            surface.backdrop.color
            view(for: surface)
        }
        .frame(width: size.width, height: size.height)

        let hosting = NSHostingView(rootView: content)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        // SwiftUI needs a window before it will lay text out at its real metrics. The window is
        // parked far offscreen so nothing flashes on a real display.
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -30_000, y: -30_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        pumpRunLoop(seconds: 0.35)

        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw SnapshotError.renderFailed("could not allocate a \(Int(size.width * scale)) px bitmap")
        }
        bitmap.size = size

        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.renderFailed("could not encode PNG")
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    /// Lets SwiftUI settle before the pixels are taken.
    static func pumpRunLoop(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// The `--snapshot` command-line entry point.
    ///
    /// Cleanliness note: the prints below are the output of a command-line tool, not logging.
    static func runCLI(surface name: String, out path: String?, completion: @escaping (Int32) -> Void) {
        MovezFont.register()

        if name == "list" {
            for surface in SnapshotSurface.allCases { print(surface.rawValue) }
            fflush(stdout)
            return completion(0)
        }

        let destination = path ?? "build/snapshots"
        do {
            if name == "all" {
                for surface in SnapshotSurface.allCases {
                    let url = URL(fileURLWithPath: destination).appendingPathComponent("\(surface.rawValue).png")
                    try render(surface, to: url)
                    print(url.path)
                }
            } else {
                guard let surface = SnapshotSurface(rawValue: name) else {
                    throw SnapshotError.unknownSurface(name)
                }
                let url = URL(fileURLWithPath: destination)
                let target = url.pathExtension.lowercased() == "png"
                    ? url
                    : url.appendingPathComponent("\(surface.rawValue).png")
                try render(surface, to: target)
                print(target.path)
            }
            fflush(stdout)
            completion(0)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            completion(2)
        }
    }
}
