import AVFoundation
import Foundation

/// Plays the three synthesised chimes.
@MainActor
protocol ChimePlayer: AnyObject {
    func play(_ chime: Chime)
}

/// The real player. The three WAVs are preloaded at launch so a transition chime never arrives
/// late.
@MainActor
final class AudioChimePlayer: ChimePlayer {
    private var players: [Chime: AVAudioPlayer] = [:]

    init() {
        preload()
    }

    func play(_ chime: Chime) {
        guard let player = players[chime] else { return }
        player.currentTime = 0
        player.play()
    }

    private func preload() {
        for chime in Chime.allCases {
            guard let url = MovezBundle.resources.url(
                forResource: chime.resourceName,
                withExtension: "wav",
                subdirectory: "Chimes"
            ) else { continue }
            guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[chime] = player
        }
    }

    var loadedChimes: Int { players.count }
}

/// The Sounds setting, applied to whatever player is underneath.
///
/// The gate is a wrapper rather than a check inside the real player so that "sounds off means
/// nothing is played" is a fact about the app that a test can actually observe.
@MainActor
final class GatedChimePlayer: ChimePlayer {
    private let wrapped: ChimePlayer
    private let isEnabled: () -> Bool

    init(wrapping wrapped: ChimePlayer, isEnabled: @escaping () -> Bool) {
        self.wrapped = wrapped
        self.isEnabled = isEnabled
    }

    func play(_ chime: Chime) {
        guard isEnabled() else { return }
        wrapped.play(chime)
    }
}

/// The player the tests assert against.
@MainActor
final class RecordingChimePlayer: ChimePlayer {
    private(set) var played: [Chime] = []
    var enabled = true

    func play(_ chime: Chime) {
        guard enabled else { return }
        played.append(chime)
    }

    func count(of chime: Chime) -> Int { played.filter { $0 == chime }.count }
    func clear() { played.removeAll() }
}
