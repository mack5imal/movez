import Foundation

/// How every micro-break runs, whichever library built it: each block appears after the earlier
/// blocks' lead-ins and seconds, and starts moving one lead-in later.
///
/// The one place that rule is written. The micro-break types, the panel that runs them and the
/// record of what was done all read it from here, each with its own library's lead-in, so a lead-in
/// tuned for one mode moves the panel and the record together.
struct MicroTimeline: Equatable {
    let blockSeconds: [Int]
    let leadInSeconds: Int

    /// Every block after its lead-in: 65 s for one movement, 70 s for two.
    var totalSeconds: Int {
        blockSeconds.reduce(0) { $0 + leadInSeconds + $1 }
    }

    /// Seconds into the running micro-break at which a block appears; its lead-in starts there.
    func appearsAt(block index: Int) -> Int {
        blockSeconds.prefix(index).reduce(0) { $0 + leadInSeconds + $1 }
    }

    /// Seconds into the running micro-break at which a block's movement starts.
    func startsAt(block index: Int) -> Int {
        appearsAt(block: index) + leadInSeconds
    }

    /// The blocks the user got at least halfway through in `seconds` of running time, by index:
    /// the rule a full break is held to, applied to each movement.
    func indicesRun(seconds: Int) -> [Int] {
        blockSeconds.indices.filter { index in
            (seconds - startsAt(block: index)) * 2 >= blockSeconds[index]
        }
    }
}
