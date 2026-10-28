import Testing
import Foundation
import DeckieCore
import DeckieLab

/// Fixtures/gridfit.json: per track, what the lab's current fit_grid and its IRLS path give for the committed
/// detected beats (computed by core/Tools/make_fixtures.py with the lab's own Python).
struct GridRow: Decodable {
    struct Fit: Decodable {
        var bpm, period, t0, firstDownbeat, fitMadMs, inlierFrac, downbeatAgree, confidence: Double
        var method: String?
        var trustedWindows: Int?
        var periodSpreadPct: Double?
        enum CodingKeys: String, CodingKey {
            case bpm, period, t0, method, confidence
            case firstDownbeat = "first_downbeat", fitMadMs = "fit_mad_ms", inlierFrac = "inlier_frac"
            case downbeatAgree = "downbeat_agree", trustedWindows = "trusted_windows"
            case periodSpreadPct = "period_spread_pct"
        }
    }
    var nBeats: Int
    var nDownbeats: Int
    var full: Fit
    var irls: Fit
    var windows: Fit?
    enum CodingKeys: String, CodingKey { case full, irls, windows, nBeats = "n_beats", nDownbeats = "n_downbeats" }
}

@Suite struct GridFitTests {
    static let rows = try! RepoPaths.fixture("gridfit.json", as: [String: GridRow].self)

    static func check(_ got: GridFit, _ want: GridRow.Fit, _ label: String) {
        #expect(near(got.bpm, want.bpm, 1e-6), "\(label) bpm \(got.bpm) vs \(want.bpm)")
        #expect(near(got.t0, want.t0, 1e-6), "\(label) t0 \(got.t0) vs \(want.t0)")
        #expect(near(got.firstDownbeat, want.firstDownbeat, 1e-6), "\(label) first downbeat")
        // The median error and the confidence built on it differ from numpy by up to a few hundredths of a
        // microsecond on tracks whose grid does not fit at all (errors above 80 ms): twelve reweighting
        // rounds on a hopeless fit amplify the last bits of the 2x2 solve. Nothing audible lives there.
        #expect(near(got.fitMadMs, want.fitMadMs, 1e-4), "\(label) mad \(got.fitMadMs) vs \(want.fitMadMs)")
        #expect(got.inlierFrac == want.inlierFrac, "\(label) inlier \(got.inlierFrac) vs \(want.inlierFrac)")
        #expect(got.downbeatAgree == want.downbeatAgree, "\(label) downbeat agree")
        #expect(near(got.confidence, want.confidence, 1e-6), "\(label) confidence \(got.confidence) vs \(want.confidence)")
    }

    /// The full current fit (both estimators) lands on the lab's numbers for all 373 tracks.
    @Test func currentFitReproducesTheLabOnEveryTrack() throws {
        var methods: [String: Int] = [:]
        for (id, row) in Self.rows {
            let d = try FeatureFile.load(RepoPaths.features.appendingPathComponent("\(id).json"))
            #expect(d.detectedBeatsS.count == row.nBeats)
            let got = try #require(BeatGrid.fit(beats: d.detectedBeatsS, downbeats: d.detectedDownbeatsS ?? []))
            #expect(got.method == row.full.method, "\(id) method \(got.method) vs \(row.full.method!)")
            Self.check(got, row.full, "\(id) full")
            if let w = row.windows {
                #expect(got.trustedWindows == w.trustedWindows, "\(id) trusted windows")
                #expect(got.periodSpreadPct == w.periodSpreadPct, "\(id) spread")
            } else {
                #expect(got.trustedWindows == nil, "\(id) expected no windows estimate")
            }
            methods[got.method, default: 0] += 1
        }
        print("grid fit methods chosen: \(methods)")
    }

    /// Each estimator on its own matches the lab's value for it.
    @Test func eachEstimatorReproducesTheLab() throws {
        for (id, row) in Self.rows {
            let d = try FeatureFile.load(RepoPaths.features.appendingPathComponent("\(id).json"))
            let b = d.detectedBeatsS.sorted()
            let downs = d.detectedDownbeatsS ?? []
            let (P, t0) = BeatGrid.periodPhaseIRLS(b)
            Self.check(BeatGrid.evaluate(beats: b, downbeats: downs, period: P, t0: t0), row.irls, "\(id) irls")
            if let w = BeatGrid.periodPhaseWindows(b) {
                let want = try #require(row.windows, "\(id): Swift found trusted windows, the lab did not")
                Self.check(BeatGrid.evaluate(beats: b, downbeats: downs, period: w.period, t0: w.phase), want, "\(id) windows")
            } else {
                #expect(row.windows == nil, "\(id): the lab found trusted windows, Swift did not")
            }
        }
    }

    /// The committed feature files were written by two generations of the lab's fit. From the
    /// millisecond-rounded beats, every committed `grid_candidates.beatthis` is reproduced within 0.005 BPM,
    /// 0.5 ms and 0.01 confidence by either the current two-estimator fit or the IRLS path on its own.
    @Test func committedGridCandidatesAreReproducedByOneOfTheTwoPaths() throws {
        var n = 0, byFull = 0, byIRLS = 0
        for id in Self.rows.keys.sorted() {
            let d = try FeatureFile.load(RepoPaths.features.appendingPathComponent("\(id).json"))
            guard let candOpt = d.gridCandidates?["beatthis"], let cand = candOpt else { continue }
            let candBpm: Double = cand.bpm, candMad: Double = cand.fitMadMs, candConf: Double = cand.confidence
            let b = d.detectedBeatsS.sorted()
            let downs = d.detectedDownbeatsS ?? []
            func matches(_ g: GridFit) -> Bool {
                near(g.bpm, candBpm, 0.005) && near(g.fitMadMs, candMad, 0.5) && near(g.confidence, candConf, 0.01)
            }
            let full = try #require(BeatGrid.fit(beats: b, downbeats: downs))
            let (P, t0) = BeatGrid.periodPhaseIRLS(b)
            let irls = BeatGrid.evaluate(beats: b, downbeats: downs, period: P, t0: t0)
            n += 1
            if matches(full) { byFull += 1 } else if matches(irls) { byIRLS += 1 }
            #expect(matches(full) || matches(irls),
                    "\(id): committed \(candBpm) BPM, \(candMad) ms, \(candConf); full \(full.bpm), \(full.fitMadMs), \(full.confidence); irls \(irls.bpm), \(irls.fitMadMs), \(irls.confidence)")
        }
        #expect(n == 373)
        print("committed beatthis grids: \(n); reproduced by the current fit: \(byFull), by the IRLS path alone: \(byIRLS)")
    }

    @Test func tooFewBeatsGivesNoGrid() {
        #expect(BeatGrid.fit(beats: (0..<15).map { Double($0) * 0.5 }, downbeats: []) == nil)
    }

    @Test func syntheticSteadyBeatsFitExactly() throws {
        let beats = (0..<200).map { 1.25 + Double($0) * 0.5 }
        let downs = stride(from: 0, to: 200, by: 4).map { 1.25 + Double($0) * 0.5 + 1.0 }  // phase 2 of 4
        let g = try #require(BeatGrid.fit(beats: beats, downbeats: downs))
        #expect(near(g.bpm, 120, 1e-9))
        #expect(near(g.fitMadMs, 0, 1e-6))
        #expect(g.inlierFrac == 1 && g.downbeatAgree == 1 && near(g.confidence, 1, 1e-9))
        #expect(near(g.firstDownbeat, 2.25, 1e-9))
    }
}
