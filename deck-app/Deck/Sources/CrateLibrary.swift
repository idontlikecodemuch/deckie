import Foundation
import DeckieCore
import DeckieCrate

/// A crate made by Deckie Desk, as the booth sees it: the tracks and discs, the picks' pair scores (scored here on
/// the iPad with the shared scoring, so any DJ's crate works and the crate itself stays as Desk wrote it), the
/// whole-song waves from the per-bar loudness, and where the recognition signatures are. The bundled deck_data.json
/// is the other source of the same `DeckData`.
struct CrateLibrary {
    struct SignatureRef { let id: String; let title: String; let artist: String; let url: URL }

    let url: URL
    let name: String
    let data: DeckData
    let overview: [String: Overview]
    let signatures: [SignatureRef]

    static let moveLabels = ["bass_swap_8": "short blend", "bass_swap_16": "blend", "bass_swap_32": "long blend",
                             "ramped_blend": "ramp blend", "filter_sweep": "filter out", "quick_blend_echo": "echo out",
                             "brake_cut": "brake/cut"]

    static func load(_ url: URL) throws -> CrateLibrary {
        let crate = try CrateReader.read(from: url)
        let discNames = Array(Set(crate.tracks.compactMap { $0.ident.disc })).sorted()
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
            tracks.append(Track(
                id: t.id, title: artist.isEmpty ? song : "\(artist) - \(song)", artist: artist, song: song,
                ver: t.ident.version ?? "", deck: deckName, on: t.ident.disc != nil, disc: t.ident.disc,
                folder: folder, hal: t.ident.tags.contains("halloween"), kind: t.ident.kind ?? "",
                era: t.ident.era ?? "", bpmTag: t.file.tagBpm, cut: t.ident.cutKey ?? t.id,
                longest: t.ident.isLongest ?? true, secs: t.file.durationS, cd: t.ident.disc.flatMap { cdOf[$0] },
                num: t.ident.track, bpm: bpm, bpmIn: grid?.bpmIn, bpmOut: grid?.bpmOut,
                key: t.key?.camelot, keyConf: t.key?.confidence, dur: t.file.durationS,
                mixIn: t.mixIn.map { [barStart($0.startBar), barStart($0.endBar)] },
                mixOut: t.mixOut.map { [barStart($0.startBar), barStart($0.endBar)] },
                mixInBars: t.mixIn.map { $0.endBar - $0.startBar }, mixOutBars: t.mixOut.map { $0.endBar - $0.startBar },
                fade: t.ends?.fadeOut, firstBeat: grid?.firstDownbeatS, wOut: nil, wIn: nil, wHead: nil, spb: nil,
                steadyIn: t.ends?.steadyInBar.map { barStart($0) }, bpmGrid: grid?.bpm))
            if let lufs = t.bars?[BarSeries.lufs], !lufs.isEmpty {
                // One value per bar, loudness -40 to 0 dB on the 0...63 scale the bundled overviews use.
                let vals = lufs.map { v -> Int in v.isFinite ? max(0, min(63, Int(((v + 40) / 40 * 63).rounded()))) : 0 }
                overview[t.id] = Overview(n: vals.count, dur: t.file.durationS, s: String(vals.map { Overview.alphabet[$0] }))
            }
            if t.signatures["o"] != nil {
                sigs.append(SignatureRef(id: t.id, title: song, artist: artist,
                                         url: url.appendingPathComponent("signatures/\(t.id)_o.shazamsignature")))
            }
        }

        // Discs and their folders, in the order the DJ's disc software shows them (folder name, then track number).
        var discs: [Disc] = []
        for d in discNames {
            let on = tracks.filter { $0.disc == d }
            let folders = Array(Set(on.map(\.folder))).sorted()
            discs.append(Disc(disc: d, cd: cdOf[d]!, name: d, folders: folders.map { f in
                DiscFolder(name: f, ids: on.filter { $0.folder == f }.sorted { ($0.num ?? 0) < ($1.num ?? 0) }.map(\.id))
            }))
        }

        // Pairs: every track into every other, then per source the best 40 on-disc targets and the best 40 overall,
        // as tools/prep_data.py trims the lab's table.
        let core = crate.tracks.compactMap { $0.scoringTrack() }
        let coreById = Dictionary(uniqueKeysWithValues: core.map { ($0.id, $0) })
        let scores = PairScorer.scoreAll(core)
        var bySource: [String: [PairScore]] = [:]
        for (k, p) in scores { bySource[k.a, default: []].append(p) }
        let onDisc = Set(tracks.filter(\.on).map(\.id))
        var pairs: [String: [Pair]] = [:]
        for (a, list) in bySource {
            let sorted = list.sorted { $0.scoreBase > $1.scoreBase }
            var keep = sorted.filter { onDisc.contains($0.b) }.prefix(40).map { $0 }
            let have = Set(keep.map(\.b))
            keep += sorted.filter { !have.contains($0.b) }.prefix(40)
            keep.sort { $0.scoreBase > $1.scoreBase }
            guard let A = coreById[a] else { continue }
            pairs[a] = keep.map { p in
                let B = coreById[p.b]
                let km = MNUM[p.multiplier] ?? 1
                let pitch = B.map { ((A.bpmOut / ($0.bpmIn * km)) - 1) * 100 }.map { ($0 * 10).rounded() / 10 }
                let moves = p.moves.isEmpty ? [p.suggestedTransition] : p.moves
                return Pair(b: p.b, s: (p.scoreBase * 1000).rounded() / 1000, st: (p.stretchPct * 10).rounded() / 10,
                            m: p.multiplier, pitch: pitch, tr: p.suggestedTransition,
                            trl: moveLabels[p.suggestedTransition] ?? p.suggestedTransition,
                            ka: A.camelot.isEmpty ? "?" : A.camelot, kb: (B?.camelot).flatMap { $0.isEmpty ? nil : $0 } ?? "?",
                            reasons: Array(p.reasons.prefix(5)), mv: Array(moves.map { moveLabels[$0] ?? $0 }.prefix(3)),
                            ks: p.keyShiftSt)
            }
        }

        let data = DeckData(generated: crate.manifest.createdAt, tracks: tracks, discs: discs, pairs: pairs, catalogVariants: ["o"])
        return CrateLibrary(url: url, name: crate.manifest.name, data: data, overview: overview, signatures: sigs)
    }
}
