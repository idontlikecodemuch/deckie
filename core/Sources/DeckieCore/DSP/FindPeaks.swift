import Foundation

/// `scipy.signal.find_peaks` with the one condition the lab uses, `distance` (mixer/analyze.py picks novelty peaks with
/// `find_peaks(nov, distance=8)`), following scipy's code (scipy 1.18, `_peak_finding.py` and
/// `_peak_finding_utils.pyx`).
public enum FindPeaks {
    /// scipy's `_local_maxima_1d`: every sample, or flat run of equal samples (a plateau), that is higher than the
    /// sample before it and than the first different sample after it. Neither end can be a peak: the first sample has
    /// nothing before it, and a plateau that reaches the last sample has no lower sample after it. A plateau's peak is
    /// its middle sample, rounded down for an even length ((left + right) / 2); its edges are returned too.
    public static func localMaxima(_ x: [Double]) -> (peaks: [Int], leftEdges: [Int], rightEdges: [Int]) {
        var mid: [Int] = [], left: [Int] = [], right: [Int] = []
        let last = x.count - 1
        var i = 1
        while i < last {
            if x[i - 1] < x[i] {
                var ahead = i + 1
                while ahead < last && x[ahead] == x[i] { ahead += 1 }
                if x[ahead] < x[i] {
                    left.append(i)
                    right.append(ahead - 1)
                    mid.append((i + ahead - 1) / 2)
                    i = ahead
                }
            }
            i += 1
        }
        return (mid, left, right)
    }

    /// scipy's `_select_by_peak_distance`: with the peaks in position order, take them from the highest `priority`
    /// down; each one still kept removes every neighbour closer than `distance` (rounded up to whole samples) on either
    /// side. Returns which peaks are kept.
    ///
    /// scipy orders the peaks with numpy's default `argsort`, which is not stable: when two peaks within `distance`
    /// have exactly the same height, which one survives depends on numpy's sort kernel (and so on the machine). Here
    /// equal heights are ordered by position, so the later of two equal peaks is taken first. The lab's novelty curve
    /// is a float64 square root of products of normalised sums, where two distinct peaks of exactly equal height do
    /// not occur in practice; SpectralTests shows the curves with ties separately.
    public static func selectByDistance(peaks: [Int], priority: [Double], distance: Double) -> [Bool] {
        precondition(peaks.count == priority.count)
        let n = peaks.count
        let d = Int(distance.rounded(.up))
        var keep = [Bool](repeating: true, count: n)
        let order = (0..<n).sorted { priority[$0] < priority[$1] || (priority[$0] == priority[$1] && $0 < $1) }
        var i = n - 1
        while i >= 0 {
            let j = order[i]
            i -= 1
            if !keep[j] { continue }
            var k = j - 1
            while k >= 0 && peaks[j] - peaks[k] < d { keep[k] = false; k -= 1 }
            k = j + 1
            while k < n && peaks[k] - peaks[j] < d { keep[k] = false; k += 1 }
        }
        return keep
    }

    /// `scipy.signal.find_peaks(x, distance=distance)`'s peak indices, in increasing order. Without a distance, every
    /// local maximum.
    public static func find(_ x: [Double], distance: Double? = nil) -> [Int] {
        let peaks = localMaxima(x).peaks
        guard let distance else { return peaks }
        precondition(distance >= 1, "`distance` must be greater or equal to 1")
        let keep = selectByDistance(peaks: peaks, priority: peaks.map { x[$0] }, distance: distance)
        return peaks.indices.filter { keep[$0] }.map { peaks[$0] }
    }
}
