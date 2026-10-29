import Foundation

// The structure module (BarGrid, Phrase, Sections, FadeOut, MixWindows, Flags) ports the part of mixer/analyze.py
// that turns a beat grid, novelty peaks, per-bar loudness and vocal probability into bars, phrases, sections, the
// fade-out decision, the mix-in and mix-out windows and the track's flags. Every function is pure: the audio
// measurements are inputs. Bar numbers that cross the public API are 1-based, as the lab writes them in its feature
// files (`end_bar` exclusive); the code inside works on the lab's 0-based indices. Values are kept unrounded; the lab
// rounds when it writes the file (noted on each field).

/// The lab's bar grid: bar 1 at the first grid downbeat at or after the first sound (less a quarter beat), as many
/// whole bars as fit before the end of the track, and the grid's beat and bar times (mixer/analyze.py, after the grid
/// choice). Times are seconds.
public struct BarGrid: Sendable, Equatable {
    /// Start of bar 1, the lab's `fd` (written as `grid.first_downbeat_s`, rounded to 4 decimals).
    public var firstDownbeatS: Double
    /// Seconds per beat, the grid period (written as `grid.beat_s`, 5 decimals).
    public var beatS: Double
    /// Seconds per bar, four beats (written as `grid.bar_s`, 5 decimals).
    public var barS: Double
    /// Whole bars from bar 1 to the end of the track (`grid.n_bars`).
    public var nBars: Int
    /// The `nBars + 1` bar lines: bar k (1-based) spans `barTimes[k - 1]..<barTimes[k]`. The lab's `bar_t`
    /// (written as `downbeats_s`, 3 decimals).
    public var barTimes: [Double]
    /// The `4 nBars + 1` grid beats from bar 1 on, the lab's `grid_beats`.
    public var gridBeats: [Double]
    /// The grid beats before bar 1 back to 0 s, then `gridBeats`: the lab's `grid_beats_all` (written as `beats_s`).
    public var beatTimes: [Double]

    /// The grid laid out from a known bar 1.
    public init(firstDownbeatS fd: Double, beatS P: Double, nBars: Int) {
        let barS = 4 * P
        self.firstDownbeatS = fd
        self.beatS = P
        self.barS = barS
        self.nBars = nBars
        barTimes = (0...nBars).map { fd + Double($0) * barS }
        let gridBeats = (0...(4 * nBars)).map { fd + Double($0) * P }
        self.gridBeats = gridBeats
        beatTimes = BarGrid.beatsBefore(firstDownbeat: fd, beatS: P) + gridBeats
    }

    /// The lab's bar grid from a fitted grid: `gridDownbeat` is any downbeat of the fitted grid (the fit's
    /// `first_downbeat`), `beatS` its period, `firstSound` the first sound and `duration` the track's length in
    /// seconds. Nil when fewer than 8 bars fit (the lab stops there with "only n bars on grid").
    public init?(gridDownbeat: Double, beatS P: Double, firstSound: Double, duration: Double) {
        let fd = BarGrid.firstBar(gridDownbeat: gridDownbeat, beatS: P, firstSound: firstSound)
        let n = BarGrid.barCount(firstBar: fd, beatS: P, duration: duration)
        if n < 8 { return nil }
        self.init(firstDownbeatS: fd, beatS: P, nBars: n)
    }

    /// Start of bar 1: the grid downbeat at or after `max(0, firstSound - beatS / 4)` (with 1e-9 s of slack), found by
    /// moving `gridDownbeat` by whole bars.
    public static func firstBar(gridDownbeat: Double, beatS P: Double, firstSound: Double) -> Double {
        let barS = 4 * P
        let lo = max(0.0, firstSound - 0.25 * P)
        var fd = gridDownbeat - ((gridDownbeat - lo) / barS).rounded(.down) * barS
        if fd < lo - 1e-9 { fd += barS }
        return fd
    }

    /// Whole bars from `firstBar` to `duration`: `floor((duration - firstBar) / barS)`.
    public static func barCount(firstBar fd: Double, beatS P: Double, duration: Double) -> Int {
        Int(((duration - fd) / (4 * P)).rounded(.down))
    }

    /// The grid beats before bar 1, from the earliest at or after 0 s (within 1e-9 s) to the one just before bar 1:
    /// `numpy.arange(fd - P, -1e-9, -P)` reversed, with numpy's way of filling a float range (the step it uses is
    /// `(start + step) - start`, and value i is `start + i * that`).
    public static func beatsBefore(firstDownbeat fd: Double, beatS P: Double) -> [Double] {
        let start = fd - P, stop = -1e-9, step = -P
        let length = ((stop - start) / step).rounded(.up)
        guard length >= 1 else { return [] }
        var out = [start]
        if length >= 2 {
            let next = start + step
            out.append(next)
            let delta = next - start
            var i = 2
            while Double(i) < length {
                out.append(start + Double(i) * delta)
                i += 1
            }
        }
        return out.reversed()
    }
}
