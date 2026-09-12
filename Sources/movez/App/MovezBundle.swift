import Foundation

/// Anchor class used to resolve the movez application bundle from any context,
/// including unit tests hosted inside the app.
final class MovezBundleToken {}

enum MovezBundle {
    /// The bundle that carries movez resources (fonts, chimes, movement library).
    static let resources = Bundle(for: MovezBundleToken.self)
}
