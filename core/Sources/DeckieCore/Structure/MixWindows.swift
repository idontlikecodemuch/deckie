import Foundation

/// The mix-in window, the lab's `mix_in`: from bar 1 over the vocal-free intro, snapped to the phrase lattice.
/// Bars are 1-based, `endBar` exclusive.
public struct MixIn: Sendable, Equatable {
    public var startBar: Int
    public var endBar: Int
    public var bars: Int
    /// Start and end of the window in seconds, bar line times (the lab writes them to 3 decimals).
    public var startS: Double
    public var endS: Double
    /// Bars in the window with vocal probability below 0.5.
    public var vocalFreeBars: Int
    /// First bar with vocal probability at least 0.5; nil when there is none.
    public var firstVocalBar: Int?

    public init(startBar: Int, endBar: Int, bars: Int, startS: Double, endS: Double, vocalFreeBars: Int,
                firstVocalBar: Int?) {
        self.startBar = startBar
        self.endBar = endBar
        self.bars = bars
        self.startS = startS
        self.endS = endS
        self.vocalFreeBars = vocalFreeBars
        self.firstVocalBar = firstVocalBar
    }
}

/// The mix-out window, the lab's `mix_out`: ending at the last full bar (or before a fade), over the vocal-free
/// outro. Bars are 1-based, `endBar` exclusive.
public struct MixOut: Sendable, Equatable {
    public var startBar: Int
    public var endBar: Int
    public var bars: Int
    /// Start and end of the window in seconds, bar line times (3 decimals in the file).
    public var startS: Double
    public var endS: Double
    /// Bars in the window with vocal probability below 0.5.
    public var vocalFreeBars: Int
    /// Last bar of the track with vocal probability at least 0.5; nil when there is none.
    public var lastVocalBar: Int?
    /// The fade-out decision the window was placed with.
    public var fadeOut: Bool

    public init(startBar: Int, endBar: Int, bars: Int, startS: Double, endS: Double, vocalFreeBars: Int,
                lastVocalBar: Int?, fadeOut: Bool) {
        self.startBar = startBar
        self.endBar = endBar
        self.bars = bars
        self.startS = startS
        self.endS = endS
        self.vocalFreeBars = vocalFreeBars
        self.lastVocalBar = lastVocalBar
        self.fadeOut = fadeOut
    }
}

/// Where a DJ can blend into and out of a track: the lab's mix windows (mixer/analyze.py, "mix windows"). Public bar
/// numbers are 1-based as the lab writes them; a bar given as an end is exclusive (the bar after the window).
public enum MixWindows {
    /// A bar is vocal when its vocal probability is at least this.
    public static let vocalThreshold = 0.5

    /// The window length, the lab's `pick_len`: 32 bars only if at least 32 are available and at least 16 of them are
    /// vocal-free; otherwise 16 if 16 are available; otherwise 8.
    public static func pickLen(available: Int, vocalFree: Int) -> Int {
        if available >= 32 && vocalFree >= 16 { return 32 }
        return available >= 16 ? 16 : 8
    }

    /// The snapping lattice: the bars where 8-bar phrases start, from `snapPhaseBar` up to the end line `nBars + 1`.
    public static func lattice(snapPhaseBar: Int, nBars: Int) -> [Int] {
        stride(from: snapPhaseBar - 1, through: nBars, by: 8).map { $0 + 1 }
    }

    /// True when a phrase on the snapping lattice starts at `bar`.
    public static func isOnLattice(_ bar: Int, snapPhaseBar: Int) -> Bool {
        Py.mod(bar - snapPhaseBar, 8) == 0
    }

    /// The end bar (exclusive) of a mix-in window of `length` bars from bar 1: kept when it lands on the lattice,
    /// otherwise moved to the nearest lattice bar between bar 9 and bar `1 + max(available, length)` (the earlier on
    /// a tie), or kept when there is none.
    public static func snapMixInEnd(length: Int, available: Int, snapPhaseBar: Int, nBars: Int) -> Int {
        snapInEnd(start0: 0, length: length, available: available, snap: snapPhaseBar - 1, nBars: nBars) + 1
    }

    /// The end bar (exclusive) of the mix-out window. `fullBars` is the number of whole bars before the last sound
    /// (bar lines up to it, less one); the usable end is that, kept between 8 and `nBars`. Without a fade the window
    /// ends there, or at the latest lattice bar up to 4 bars earlier. With a fade starting at `fadeStartBar` it ends at
    /// the latest lattice bar from bar 17 up to the fade, or when there is none at the fade or the usable end,
    /// whichever is earlier, but not before bar 17. Never after the last bar.
    public static func mixOutEnd(fullBars: Int, nBars: Int, snapPhaseBar: Int, fadeStartBar: Int?) -> Int {
        let endLimit = max(8, min(nBars, fullBars))
        return outEnd(endLimit: endLimit, nBars: nBars, snap: snapPhaseBar - 1, fadeStart0: fadeStartBar.map { $0 - 1 })
            + 1
    }

    /// Both windows. `vocalProb` has one value per bar of `grid`; `boundariesBars` are the section boundaries
    /// (`Phrase.boundaries`), whose inner ones, the on-lattice novelty peaks, a window extends to when the vocal-free
    /// stretch is shorter than 8 bars; `snapPhaseBar` is the phrase lattice used for snapping
    /// (`Phrase.snapPhaseBar`); `lastSound` is in seconds; `fadeOut` and `fadeStartBar` come from `FadeOut`.
    public static func windows(grid: BarGrid, vocalProb voc: [Double], boundariesBars: [Int], snapPhaseBar: Int,
                               lastSound: Double, fadeOut: Bool, fadeStartBar: Int?) -> (mixIn: MixIn, mixOut: MixOut) {
        let n = grid.nBars
        precondition(voc.count == n, "vocal probability has \(voc.count) values for \(n) bars")
        let barT = grid.barTimes
        let snap = snapPhaseBar - 1
        // The lab's bset: the on-lattice peaks, 0-based, which are the boundaries other than the first and the end.
        let bset = Array(Set(boundariesBars.map { $0 - 1 }.filter { $0 > 0 && $0 < n })).sorted()
        let lastFull = Py.countAtMost(lastSound, in: barT) - 1
        let endLimit = max(8, min(n, lastFull))
        let vocalOn = voc.indices.filter { voc[$0] >= vocalThreshold }
        let firstVocal = vocalOn.first ?? n
        let lastVocal = vocalOn.last ?? -1
        let half = max(8, n / 2)

        // Mix-in: bar 1 to the first vocal bar, or to the first boundary when the vocal-free intro is under 8 bars.
        let start0 = 0
        var availIn: Int
        if firstVocal - start0 >= 8 {
            availIn = firstVocal - start0
        } else if let firstBound = bset.first(where: { $0 >= start0 + 8 }) {
            availIn = firstBound - start0
        } else {
            availIn = 16
        }
        availIn = min(max(availIn, 8), half)
        let lIn = pickLen(available: availIn, vocalFree: vocalFree(voc, start0, start0 + availIn))
        let endIn = snapInEnd(start0: start0, length: lIn, available: availIn, snap: snap, nBars: n)
        let mixIn = MixIn(startBar: start0 + 1, endBar: endIn + 1, bars: endIn - start0, startS: barT[start0],
                          endS: barT[endIn], vocalFreeBars: vocalFree(voc, start0, endIn),
                          firstVocalBar: vocalOn.isEmpty ? nil : firstVocal + 1)

        // Mix-out: the mirror image, ending at the last full bar or before the fade.
        let endOut = outEnd(endLimit: endLimit, nBars: n, snap: snap,
                            fadeStart0: fadeOut ? fadeStartBar.map { $0 - 1 } : nil)
        let lv = voc[0..<endOut].lastIndex(where: { $0 >= vocalThreshold }) ?? -1
        var availOut: Int
        if endOut - (lv + 1) >= 8 {
            availOut = endOut - (lv + 1)
        } else if let lb = bset.filter({ $0 <= endOut - 8 }).max() {
            availOut = endOut - lb
        } else {
            availOut = 16
        }
        availOut = min(max(availOut, 8), half)
        let lOut = pickLen(available: availOut, vocalFree: vocalFree(voc, max(0, endOut - availOut), endOut))
        let startOut = max(0, endOut - lOut)
        let mixOut = MixOut(startBar: startOut + 1, endBar: endOut + 1, bars: endOut - startOut,
                            startS: barT[startOut], endS: barT[endOut], vocalFreeBars: vocalFree(voc, startOut, endOut),
                            lastVocalBar: lastVocal >= 0 ? lastVocal + 1 : nil, fadeOut: fadeOut)
        return (mixIn, mixOut)
    }

    // MARK: the lab's code on 0-based bar lines

    /// Vocal-free bars in `voc[lo..<hi]`, sliced as Python slices (clamped to the array).
    static func vocalFree(_ voc: [Double], _ lo: Int, _ hi: Int) -> Int {
        let l = min(max(lo, 0), voc.count), h = min(max(hi, 0), voc.count)
        return l < h ? voc[l..<h].lazy.filter { $0 < vocalThreshold }.count : 0
    }

    static func snapInEnd(start0: Int, length: Int, available: Int, snap: Int, nBars: Int) -> Int {
        var endIn = start0 + length
        if Py.mod(endIn - snap, 8) != 0 {
            let hi = start0 + max(available, length)
            let latc = stride(from: snap, through: nBars, by: 8).filter { start0 + 8 <= $0 && $0 <= hi }
            // Python's min with a key keeps the first of equal keys, the earlier bar.
            if var best = latc.first {
                for b in latc.dropFirst() where abs(b - (start0 + length)) < abs(best - (start0 + length)) { best = b }
                endIn = best
            }
        }
        return endIn
    }

    static func outEnd(endLimit: Int, nBars: Int, snap: Int, fadeStart0: Int?) -> Int {
        let snapLat = stride(from: snap, through: nBars, by: 8)
        var endOut: Int
        if let fs = fadeStart0 {
            endOut = snapLat.filter { 16 <= $0 && $0 <= fs }.max() ?? max(16, min(fs, endLimit))
        } else {
            endOut = snapLat.filter { endLimit - 4 <= $0 && $0 <= endLimit }.max() ?? endLimit
        }
        return min(endOut, nBars)
    }
}
