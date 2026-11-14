import Foundation
import DeckieCore
import DeckieCrate

/// A crate file made by Deckie Desk, as the booth sees it: the tracks and their sources, the picks (scored here on the iPad with
/// the shared scoring, one song at a time as it plays, so any DJ's crate works and the crate itself stays as Desk
/// wrote it), the whole-song waves and the join lanes from the per-bar loudness, and where the recognition
/// signatures are. The bundled deck_data.json is the other source of the same `DeckData`; a crate's `DeckData` has
/// no pairs (`picks(from:)`).
struct CrateLibrary {
    struct SignatureRef { let id: String; let title: String; let artist: String; let url: URL }

    let url: URL
    let name: String
    let data: DeckData
    let overview: [String: Overview]
    let signatures: [SignatureRef]
    /// The scoring tracks and the sorted cosine list, for scoring one song's picks at a time.
    let pool: PairPool
    let coreById: [String: DeckieCore.Track]
    /// How long building the sorted cosine list took when the crate loaded, in seconds.
    let poolSecs: Double

    static let moveLabels = Words.moveLabels

    static func load(_ url: URL) throws -> CrateLibrary {
        let crate = try CrateReader.read(from: url)
        // Every source a place names, own or other (D27).
        let discNames = Array(Set(crate.tracks.flatMap { $0.ident.allPlaces.compactMap(\.disc) })).sorted()
        let cdOf = Dictionary(uniqueKeysWithValues: discNames.enumerated().map { ($1, $0 + 1) })

        var tracks: [Track] = []
        var overview: [String: Overview] = [:]
        var sigs: [SignatureRef] = []
        for t in crate.tracks {
            let grid = t.grid
            let bpm = grid?.bpm ?? t.file.tagBpm
            func barStart(_ bar: Int) -> Double {
                guard let grid else { return 0 }
                return grid.firstDownbeatS + Double(bar - 1) * 4 * 60 / grid.bpm
            }
            let artist = t.ident.artist ?? ""
            let song = t.ident.title
            let deckName = (t.file.name as NSString).deletingPathExtension
            // The folder as the DJ's software shows it: the crate's own label, else the file's parent folder.
            let folder = t.ident.folder ?? ((t.file.rel ?? "") as NSString).deletingLastPathComponent.components(separatedBy: "/").last ?? ""
            // One value per bar on the 0...63 scale, as the bundled overviews measure it: the bar's amplitude
            // (10^(dB/20)) next to the song's loudest bar, so the loudest bar is 63 and a bar without a value is 0.
            let barVals: [Int]? = t.bars?[BarSeries.lufs].flatMap { lufs in
                guard !lufs.isEmpty else { return nil }
                let amp = lufs.map { $0.isFinite ? pow(10, $0 / 20) : 0 }
                let mx = amp.max().flatMap { $0 > 0 ? $0 : nil } ?? 1
                return amp.map { max(0, min(63, Int(($0 / mx * 63).rounded()))) }
            }
            let waves: (out: Wave, in: Wave, head: Wave)? = {
                guard let grid, let mi = t.mixIn, let mo = t.mixOut, let barVals else { return nil }
                // The whole-song wave's heights (its floor and curve), so a lane is that wave zoomed in to the join.
                let heights = Overview.shape(barVals.map { Double($0) / 63 })
                return CrateLibrary.joinWaves(heights: heights, bpm: grid.bpm, firstDownbeat: grid.firstDownbeatS, dur: t.file.durationS,
                                              mixIn: [barStart(mi.startBar), barStart(mi.endBar)],
                                              mixOut: [barStart(mo.startBar), barStart(mo.endBar)])
            }()
            tracks.append(Track(
                id: t.id, title: artist.isEmpty ? song : "\(artist) - \(song)", artist: artist, song: song,
                ver: t.ident.version ?? "", deck: deckName, on: t.ident.disc != nil, disc: t.ident.disc,
                folder: folder, hal: t.ident.tags.contains("halloween"), kind: t.ident.kind ?? "",
                era: t.ident.era ?? "", bpmTag: t.file.tagBpm, cut: t.recordingKey,
                longest: t.ident.isLongest ?? true, secs: t.file.durationS, cd: t.ident.disc.flatMap { cdOf[$0] },
                num: t.ident.track, bpm: bpm, bpmIn: grid?.bpmIn, bpmOut: grid?.bpmOut,
                key: t.key?.camelot, keyConf: t.key?.confidence, dur: t.file.durationS,
                mixIn: t.mixIn.map { [barStart($0.startBar), barStart($0.endBar)] },
                mixOut: t.mixOut.map { [barStart($0.startBar), barStart($0.endBar)] },
                mixInBars: t.mixIn.map { $0.endBar - $0.startBar }, mixOutBars: t.mixOut.map { $0.endBar - $0.startBar },
                fade: t.ends?.fadeOut, firstBeat: grid?.firstDownbeatS, wOut: waves?.out, wIn: waves?.in, wHead: waves?.head,
                spb: waves == nil ? nil : CrateLibrary.waveSPB,
                steadyIn: t.ends?.steadyInBar.map { barStart($0) }, bpmGrid: grid?.bpm,
                // Other places (D27): on a source, its folder there; with no source, the folder's own name, as above.
                others: t.ident.otherPlaces.isEmpty ? nil : t.ident.otherPlaces.map { p in
                    TrackPlace(disc: p.disc, folder: p.disc != nil ? p.folder ?? ""
                               : (p.folder ?? "").components(separatedBy: "/").last ?? "", num: p.track)
                },
                // A song with no usable title (the crate file's own rule, `SongName`) leads with its place.
                named: t.hasUsableTitle ? nil : false,
                // Its facts (D34), kept with the song; none in a crate file written before them.
                facts: t.ident.facts.isEmpty ? nil : t.ident.facts.mapValues(\.values)))
            if let vals = barVals {
                overview[t.id] = Overview(n: vals.count, dur: t.file.durationS, s: String(vals.map { Overview.alphabet[$0] }))
            }
            if t.signatures["o"] != nil {
                sigs.append(SignatureRef(id: t.id, title: song, artist: artist,
                                         url: url.appendingPathComponent("signatures/\(t.id)_o.shazamsignature")))
            }
        }

        // Sources and their folders, in the order the DJ's player shows them (`SourceReading`: folders as the player
        // walks them, then the song's number). A source's name is its label: Desk writes the source's own name.
        // A song is listed under every place it has (D27).
        var discs: [Disc] = []
        for d in discNames {
            let on = tracks.flatMap { t in t.places.filter { $0.disc == d }.map { (id: t.id, place: $0) } }
            let folders = Array(Set(on.map(\.place.folder))).sorted(by: SourceReading.groupComesBefore)
            discs.append(Disc(disc: d, cd: cdOf[d]!, name: d, folders: folders.map { f in
                DiscFolder(name: f, ids: on.filter { $0.place.folder == f }.sorted { ($0.place.num ?? 0) < ($1.place.num ?? 0) }.map(\.id))
            }))
        }

        // Picks are scored per song when it plays (`picks(from:)`), not here: the pool keeps the sorted list of
        // track-to-track cosines the timbre rank needs, built once.
        let core = crate.tracks.compactMap { $0.scoringTrack() }
        let coreById = Dictionary(core.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let t0 = Date()
        let pool = PairPool(core)
        let poolSecs = Date().timeIntervalSince(t0)

        let data = DeckData(generated: crate.manifest.createdAt, tracks: tracks, discs: discs, pairs: [:], catalogVariants: ["o"])
        return CrateLibrary(url: url, name: crate.manifest.name, data: data, overview: overview, signatures: sigs,
                            pool: pool, coreById: coreById, poolSecs: poolSecs)
    }

    /// Samples per beat of the join lanes built from a crate: a quarter beat per sample, 16 per bar.
    static let waveSPB = 4

    /// The join view's three snippets (the end of the song, its mix-in, its first 64 bars) from per-bar heights,
    /// over the same windows tools/mixwaves_all.py cuts from the audio. `heights` are the song's whole-song wave
    /// values (0...1, from `Overview.shape`, so the floor is the whole song's), one per bar. Each bar's height fills
    /// its 16 samples as round(height * 63), so a lane is a flat step per bar, cut by the beat and bar lines the
    /// join view draws, and is the whole-song wave zoomed in to the join; there is no per-snippet scaling. Anything
    /// before bar 1 or after the last bar is 0.
    static func joinWaves(heights amp: [Double], bpm: Double, firstDownbeat fd: Double, dur: Double,
                          mixIn mi: [Double], mixOut mo: [Double]) -> (out: Wave, in: Wave, head: Wave) {
        let spb = waveSPB, perBar = 4 * spb
        let P = 60 / bpm / Double(spb), bar = 240 / bpm
        func snippet(_ ta: Double, _ tb: Double, _ win: [Double]) -> Wave {
            let k0 = Int(((ta - fd) / P).rounded(.down)), k1 = Int(((tb - fd) / P).rounded(.up))
            let vals = (k0..<max(k0, k1)).map { k -> Double in
                let b = k >= 0 ? k / perBar : -1
                return b >= 0 && b < amp.count ? amp[b] : 0
            }
            let t0 = fd + Double(k0) * P
            let s = String(vals.map { Overview.alphabet[max(0, min(63, Int(($0 * 63).rounded())))] })
            let beat0 = Int((Double(k0) / Double(spb)).rounded(.down))
            return Wave(t0: (t0 * 1000).rounded() / 1000, n: s.count, s: s,
                        win: win.map { Int((($0 - t0) / P).rounded()) }, beat0: beat0, k0: k0)
        }
        let leadBars = 8.0, maxBars = 32.0, headBars = 64.0
        let out = snippet(max(0, mo[0] - leadBars * bar), min(dur, mo[0] + maxBars * bar, mo[1]), mo)
        let inn = snippet(max(0, mi[0]), min(dur, mi[1] + leadBars * bar, mi[0] + (maxBars + leadBars) * bar), mi)
        let head = snippet(0, min(dur, fd + headBars * bar), mi)
        return (out, inn, head)
    }

    /// The picks for one song: every other track that passes the scoring's gates, scored from it, best first.
    /// Nothing is cut here; the booth keeps the shortlist (the best tenth) from this list after its filters.
    func picks(from a: String) -> [Pair] {
        guard let A = coreById[a] else { return [] }
        let sorted = pool.scores(from: A).sorted { $0.scoreBase > $1.scoreBase }
        return sorted.map { p in
            let B = coreById[p.b]
            let km = MNUM[p.multiplier] ?? 1
            let pitch = B.map { ((A.bpmOut / ($0.bpmIn * km)) - 1) * 100 }.map { ($0 * 10).rounded() / 10 }
            let moves = p.moves.isEmpty ? [p.suggestedTransition] : p.moves
            return Pair(b: p.b, s: (p.scoreBase * 1000).rounded() / 1000, st: (p.stretchPct * 10).rounded() / 10,
                        m: p.multiplier, pitch: pitch, tr: p.suggestedTransition,
                        trl: CrateLibrary.moveLabels[p.suggestedTransition] ?? p.suggestedTransition,
                        ka: A.camelot.isEmpty ? "?" : A.camelot, kb: (B?.camelot).flatMap { $0.isEmpty ? nil : $0 } ?? "?",
                        reasons: Array(p.reasons.prefix(5)), mv: Array(moves.map { CrateLibrary.moveLabels[$0] ?? $0 }.prefix(3)),
                        ks: p.keyShiftSt)
        }
    }
}
