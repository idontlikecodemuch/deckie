import Foundation

/// Short-term (3 s, K-weighted) loudness near the end of a track, in LUFS: the 3 s windows starting 20, 10 and 4 s
/// before the last sound (`end_lufs_st`, keys "t-20", "t-10", "t-4", 2 decimals). From audio,
/// `Loudness.shortTerm(buffer, endingAt: lastSound - 17)`, `- 7` and `- 1` measure them as the lab does.
public struct EndLoudness: Sendable, Equatable {
    public var t20: Double
    public var t10: Double
    public var t4: Double
    public init(t20: Double, t10: Double, t4: Double) {
        self.t20 = t20
        self.t10 = t10
        self.t4 = t4
    }
}

/// Whether a track fades out (or ends in a long decaying tail), the lab's fade-out detection (mixer/analyze.py):
/// more than 6 dB of decline over the last 20 s, at least 3 bars between the last body-level bar and the last sound,
/// and more than a minute of sound. Either way the end is no good for a blend, and the mix-out window stops before it.
public struct FadeOut: Sendable, Equatable {
    /// The decision (`fade_out`).
    public var fadeOut: Bool
    /// `t20 - t4` of the end loudness, in LU (`fade_drop_lu`, 2 decimals).
    public var fadeDropLu: Double
    /// Bars from the end of the last body-level bar to the last sound (`tail_bars`, 2 decimals).
    public var tailBars: Double
    /// The 1-based bar after the last body-level bar, where the fade starts; nil without a fade (`fade_start_bar`).
    public var fadeStartBar: Int?
    /// The last bar (1-based) whose loudness is at least the median bar loudness - 2 LU; the last bar when none is.
    public var lastBodyBar: Int

    /// Decline over the last 20 s, in LU, above which the end counts as a fade.
    public static let minDrop = 6.0
    /// Bars of tail after the last body-level bar needed for a fade.
    public static let minTailBars = 3.0
    /// A bar is body level when its loudness is at least the median bar loudness minus this, in LU.
    public static let bodyMargin = 2.0
    /// Seconds of sound a track needs before an ending can count as a fade.
    public static let minSoundSeconds = 60.0

    public init(fadeOut: Bool, fadeDropLu: Double, tailBars: Double, fadeStartBar: Int?, lastBodyBar: Int) {
        self.fadeOut = fadeOut
        self.fadeDropLu = fadeDropLu
        self.tailBars = tailBars
        self.fadeStartBar = fadeStartBar
        self.lastBodyBar = lastBodyBar
    }

    /// The fade decision from the end loudness, the per-bar loudness `lufsSt` (one value per bar of `grid`), the bar
    /// grid, and the first and last sound in seconds.
    public init(endLoudness l: EndLoudness, lufsSt: [Double], grid: BarGrid, firstSound: Double, lastSound: Double) {
        precondition(lufsSt.count == grid.nBars, "per-bar loudness has \(lufsSt.count) values for \(grid.nBars) bars")
        let nBars = grid.nBars
        let drop = l.t20 - l.t4
        let body = Py.median(lufsSt)
        // Index of the last body-level bar (0-based); the last bar when there is none.
        var lastBody = nBars - 1
        if let i = lufsSt.lastIndex(where: { $0 >= body - FadeOut.bodyMargin }) { lastBody = i }
        let tail = lastBody + 1 <= nBars ? (lastSound - grid.barTimes[lastBody + 1]) / grid.barS : 0.0
        let fade = drop > FadeOut.minDrop && tail >= FadeOut.minTailBars
            && lastSound - firstSound > FadeOut.minSoundSeconds
        // The lab keeps the 0-based exclusive end of the body, lastBody + 1, and writes it plus one.
        self.init(fadeOut: fade, fadeDropLu: drop, tailBars: tail, fadeStartBar: fade ? lastBody + 2 : nil,
                  lastBodyBar: lastBody + 1)
    }
}
