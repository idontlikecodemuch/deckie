import Foundation
import DeckieCore

/// One thing wrong with a crate: the file, the field path in it, the track when there is one, and what is wrong.
public struct CrateProblem: Equatable, Sendable, CustomStringConvertible {
    /// `manifest.json`, `crate.json`, `bars/<id>.bin`, ...
    public var file: String
    /// `tracks[2].mix_in.end_bar`, `min_reader`, ...; empty for the file as a whole.
    public var path: String
    /// The track's id, when the problem is in a track.
    public var track: String?
    public var message: String

    public init(file: String, path: String, track: String? = nil, message: String) {
        self.file = file; self.path = path; self.track = track; self.message = message
    }

    public var description: String {
        var s = file
        if !path.isEmpty { s += ": " + path }
        if let track { s += " (track \(track))" }
        return s + ": " + message
    }
}

/// A crate that cannot be read or written, with every problem found.
public struct CrateError: Error, Equatable, CustomStringConvertible {
    public var problems: [CrateProblem]
    public init(_ problems: [CrateProblem]) { self.problems = problems }
    public var description: String { problems.map(\.description).joined(separator: "\n") }
}

extension Crate {
    /// Everything that keeps this crate from being written as the format defines it; empty when it can be.
    /// Checks the versions, ids, every block's ranges and every bar number against the grid. What only a package
    /// on disk can show (sidecar headers, signature files) the reader and the writer check themselves.
    public func problems() -> [CrateProblem] {
        var p = Problems()
        let m = manifest
        if m.schema < 1 { p.add("manifest.json", "schema", nil, "\(m.schema) is not a format version (1 or more)") }
        if m.minReader < 1 || m.minReader > m.schema {
            p.add("manifest.json", "min_reader", nil, "\(m.minReader) must be between 1 and the schema, \(m.schema)")
        }
        if m.crateId.isEmpty { p.add("manifest.json", "crate_id", nil, "is empty") }
        if let log = m.importLog {
            for (j, e) in log.entries.enumerated() {
                if isAbsolute(e.rel) {
                    p.add("manifest.json", "import_log.entries[\(j)].rel", nil,
                          "\"\(e.rel)\" is an absolute path; the crate keeps paths relative")
                }
                if e.reason.isEmpty { p.add("manifest.json", "import_log.entries[\(j)].reason", nil, "is empty") }
            }
        }
        var seen: [String: Int] = [:]
        for (i, t) in tracks.enumerated() {
            if let j = seen[t.id] {
                p.add("crate.json", "tracks[\(i)].id", t.id, "the same id as tracks[\(j)]")
            } else {
                seen[t.id] = i
            }
            t.check(index: i, manifestSchema: m.schema, into: &p)
        }
        return p.list
    }
}

extension CrateTrack {
    /// The `vocal_structure` block's checks: bars and beats in range, spans in order and not overlapping, `first` and
    /// `last` there exactly when a span is, the free bars and kinds, the gaps' lengths and the stretches' bars.
    func checkVocalStructure(_ vs: VocalStructure, nBars n: Int?, add: (String, String) -> Void) {
        let base = "vocal_structure"
        if vs.source.isEmpty { add("\(base).source", "is empty") }
        if !(vs.frameHopS > 0) { add("\(base).frame_hop_s", "\(vs.frameHopS) must be above 0") }
        if !(1...8).contains(vs.latticePhaseBar) {
            add("\(base).lattice_phase_bar", "\(vs.latticePhaseBar) must be 1 to 8")
        }
        if !(vs.rule.threshold >= 0) { add("\(base).rule.threshold", "\(vs.rule.threshold) must be 0 or more") }
        /// A beat of a bar (bars 1 to n_bars, beats 1 to 4), or a beat line (up to beat 1 of bar n_bars + 1) when
        /// `line`; `path` is the field's name less `_bar` and `_beat`.
        func beat(_ path: String, _ b: Int, _ beat: Int, line: Bool) {
            if !(1...4).contains(beat) { add("\(path)_beat", "\(beat) must be 1 to 4") }
            guard let n else { return }
            if b < 1 { add("\(path)_bar", "\(b) is before bar 1") }
            if line {
                if b > n + 1 { add("\(path)_bar", "\(b) is past the end of the grid (\(n) bars, so at most \(n + 1))") }
                if b == n + 1 && beat != 1 {
                    add("\(path)_beat", "\(beat) is past the grid's end line, beat 1 of bar \(n + 1)")
                }
            } else if b > n {
                add("\(path)_bar", "\(b) is past the last bar (\(n) bars)")
            }
        }
        func index(_ bar: Int, _ beat: Int) -> Int { 4 * (bar - 1) + beat - 1 }
        var previousEnd = Int.min
        for (j, sp) in vs.spans.enumerated() {
            let path = "\(base).spans[\(j)]"
            beat("\(path).start", sp.startBar, sp.startBeat, line: false)
            beat("\(path).end", sp.endBar, sp.endBeat, line: true)
            let a = index(sp.startBar, sp.startBeat), b = index(sp.endBar, sp.endBeat)
            if b <= a { add("\(path).end_bar", "bar \(sp.endBar) beat \(sp.endBeat) is not after the span's start") }
            if a < previousEnd { add("\(path).start_bar", "starts before the previous span ends") }
            if sp.endS < sp.startS { add("\(path).end_s", "\(sp.endS) is before start_s \(sp.startS)") }
            for (name, o) in [("start_offset_beats", sp.startOffsetBeats), ("end_offset_beats", sp.endOffsetBeats)]
                where !(-16...16).contains(o) {
                add("\(path).\(name)", "\(o) must be -16 to 16 (beats from the nearest 8-bar lattice point)")
            }
            previousEnd = b
        }
        if (vs.first == nil) != vs.spans.isEmpty {
            add("\(base).first", vs.spans.isEmpty ? "is set, but there is no span" : "is null, but there are spans")
        }
        if (vs.last == nil) != vs.spans.isEmpty {
            add("\(base).last", vs.spans.isEmpty ? "is set, but there is no span" : "is null, but there are spans")
        }
        if let f = vs.first { beat("\(base).first", f.bar, f.beat, line: false) }
        if let l = vs.last { beat("\(base).last", l.bar, l.beat, line: false) }
        for (name, free) in [("intro_free_bars", vs.introFreeBars), ("outro_free_bars", vs.outroFreeBars)] {
            if free < 0 { add("\(base).\(name)", "\(free) must be 0 or more") }
            if let n, free > n { add("\(base).\(name)", "\(free) is more than the grid's \(n) bars") }
        }
        for (name, kind) in [("intro_kind", vs.introKind), ("outro_kind", vs.outroKind)]
            where !VocalStructure.kinds.contains(kind) {
            add("\(base).\(name)", "\"\(kind)\" must be one of \(VocalStructure.kinds.joined(separator: ", "))")
        }
        func stretch(_ path: String, _ start: Int, _ end: Int) {
            if let n {
                if start < 1 { add("\(path).start_bar", "\(start) is before bar 1") }
                if start > n { add("\(path).start_bar", "\(start) is past the last bar (\(n) bars)") }
                if end > n + 1 {
                    add("\(path).end_bar", "\(end) is past the end of the grid (\(n) bars, so at most \(n + 1))")
                }
            }
            if end <= start { add("\(path).end_bar", "\(end) is not after start_bar \(start)") }
        }
        for (j, g) in vs.freeGaps.enumerated() {
            let path = "\(base).free_gaps[\(j)]"
            stretch(path, g.startBar, g.endBar)
            if g.bars != g.endBar - g.startBar {
                add("\(path).bars", "\(g.bars) is not end_bar - start_bar, \(g.endBar - g.startBar)")
            }
        }
        for (j, e) in vs.exposedProxy.enumerated() { stretch("\(base).exposed_proxy[\(j)]", e.startBar, e.endBar) }
    }
}

/// Collects problems.
struct Problems {
    var list: [CrateProblem] = []
    mutating func add(_ file: String, _ path: String, _ track: String?, _ message: String) {
        list.append(CrateProblem(file: file, path: path, track: track, message: message))
    }
}

/// A path that starts at the root of a disk: `/...`, `\\...` or a drive letter (`C:`).
func isAbsolute(_ path: String) -> Bool {
    path.hasPrefix("/") || path.hasPrefix("\\") || path.dropFirst().hasPrefix(":")
}

/// Letters, digits and the given punctuation only, and not empty: safe in a file name on every system.
func isFileSafe(_ s: String, also extra: Set<Character> = ["-", "_"]) -> Bool {
    !s.isEmpty && s.count <= 128 && s.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || extra.contains($0) }
}

extension CrateTrack {
    func check(index i: Int, manifestSchema: Int, into p: inout Problems) {
        let base = "tracks[\(i)]"
        func add(_ path: String, _ message: String) { p.add("crate.json", "\(base).\(path)", id, message) }

        if !isFileSafe(id) {
            add("id", "\"\(id)\" must be letters, digits, - and _ only, as it names the sidecar files")
        }
        if schema < 1 || schema > manifestSchema {
            add("schema", "\(schema) must be between 1 and the manifest's \(manifestSchema)")
        }
        if file.name.isEmpty { add("file.name", "is empty") }
        if let rel = file.rel, isAbsolute(rel) {
            add("file.rel", "\"\(rel)\" is an absolute path; the crate keeps paths relative")
        }
        if let h = file.sha256 {
            if !CrateIDs.isSHA256(h) {
                add("file.sha256", "\"\(h)\" must be 64 lower-case hexadecimal characters (a SHA-256 hash)")
            } else if id != CrateIDs.id(forSHA256: h) {
                add("id", "\"\(id)\" must be the first \(CrateIDs.idLength) characters of file.sha256, " +
                          "\(CrateIDs.id(forSHA256: h))")
            }
        }
        if !(file.durationS > 0) { add("file.duration_s", "\(file.durationS) must be above 0") }
        if let t = file.tagBpm, !(t > 0) { add("file.tag_bpm", "\(t) must be above 0") }
        for (i, f) in (file.damagedFrames ?? []).enumerated() {
            if !(f.startS >= 0) { add("file.damaged_frames[\(i)].start_s", "\(f.startS) must be 0 or more") }
            if !(f.seconds > 0) { add("file.damaged_frames[\(i)].seconds", "\(f.seconds) must be above 0") }
        }
        if !(1...3).contains(analysis.level) { add("analysis.level", "\(analysis.level) must be 1, 2 or 3") }
        if engine.fidelity < 0 { add("engine.fidelity", "\(engine.fidelity) must be 0 or more") }
        if let s = analysis.secs, s < 0 { add("analysis.secs", "\(s) must be 0 or more") }

        func unit(_ path: String, _ x: Double?) {
            if let x, !(0...1).contains(x) { add(path, "\(x) must be between 0 and 1") }
        }
        let n = grid?.nBars
        /// A bar: 1 to n_bars.
        func bar(_ path: String, _ b: Int?) {
            guard let b, let n else { return }
            if b < 1 { add(path, "\(b) is before bar 1") }
            if b > n { add(path, "\(b) is past the last bar (\(n) bars)") }
        }
        /// A bar line (an exclusive end, a boundary): 1 to n_bars + 1.
        func line(_ path: String, _ b: Int?) {
            guard let b, let n else { return }
            if b < 1 { add(path, "\(b) is before bar 1") }
            if b > n + 1 { add(path, "\(b) is past the end of the grid (\(n) bars, so at most \(n + 1))") }
        }
        func span(_ path: String, _ start: Int, _ end: Int) {
            bar("\(path).start_bar", start)
            line("\(path).end_bar", end)
            if end <= start { add("\(path).end_bar", "\(end) is not after start_bar \(start)") }
        }
        func needsGrid(_ path: String, _ present: Bool) {
            if present && grid == nil { add(path, "needs the grid, which gives the bar count, but grid is null") }
        }
        func camelot(_ path: String, _ code: String) {
            if Camelot.tonic(code) == nil { add(path, "\"\(code)\" is not a Camelot code (1A to 12B)") }
        }

        if let g = grid {
            if !(g.bpm > 0) { add("grid.bpm", "\(g.bpm) must be above 0") }
            if !(g.bpmIn > 0) { add("grid.bpm_in", "\(g.bpmIn) must be above 0") }
            if !(g.bpmOut > 0) { add("grid.bpm_out", "\(g.bpmOut) must be above 0") }
            if g.nBars < 1 { add("grid.n_bars", "\(g.nBars) must be 1 or more") }
            if g.firstDownbeatS < 0 { add("grid.first_downbeat_s", "\(g.firstDownbeatS) is before the start") }
            unit("grid.confidence", g.confidence)
        }
        needsGrid("tempo_segments", tempoSegments != nil)
        if let segs = tempoSegments {
            if segs.isEmpty { add("tempo_segments", "is empty; a grid has at least one segment") }
            for (k, s) in segs.enumerated() {
                let path = "tempo_segments[\(k)]"
                bar("\(path).start_bar", s.startBar)
                if k > 0 && s.startBar <= segs[k - 1].startBar {
                    add("\(path).start_bar", "\(s.startBar) is not after the previous segment's \(segs[k - 1].startBar)")
                }
                if !(s.bpm > 0) { add("\(path).bpm", "\(s.bpm) must be above 0") }
                if s.beatsPerBar < 1 { add("\(path).beats_per_bar", "\(s.beatsPerBar) must be 1 or more") }
                if s.beatInBar < 1 || s.beatInBar > max(s.beatsPerBar, 1) {
                    add("\(path).beat_in_bar", "\(s.beatInBar) must be between 1 and beats_per_bar, \(s.beatsPerBar)")
                }
                unit("\(path).confidence", s.confidence)
            }
        }
        if let k = key {
            camelot("key.camelot", k.camelot)
            for name in k.votes.keys.sorted(by: byteOrder) { camelot("key.votes.\(name)", k.votes[name]!) }
            unit("key.confidence", k.confidence)
            if let s = k.scale, s != "major" && s != "minor" { add("key.scale", "\"\(s)\" must be major or minor") }
            needsGrid("key.changes", k.changes != nil)
            for (j, c) in (k.changes ?? []).enumerated() {
                span("key.changes[\(j)]", c.startBar, c.endBar)
                camelot("key.changes[\(j)].camelot", c.camelot)
            }
        }
        needsGrid("phrase", phrase != nil)
        if let ph = phrase {
            unit("phrase.confidence", ph.confidence)
            if !(1...8).contains(ph.latticePhaseBar) {
                add("phrase.lattice_phase_bar", "\(ph.latticePhaseBar) must be 1 to 8")
            }
            for (j, b) in ph.boundariesBars.enumerated() {
                line("phrase.boundaries_bars[\(j)]", b)
                if j > 0 && b <= ph.boundariesBars[j - 1] {
                    add("phrase.boundaries_bars[\(j)]", "\(b) is not after \(ph.boundariesBars[j - 1])")
                }
            }
        }
        needsGrid("sections", sections != nil)
        for (j, s) in (sections ?? []).enumerated() { span("sections[\(j)]", s.startBar, s.endBar) }
        needsGrid("mix_in", mixIn != nil || mixOut != nil)
        if (mixIn == nil) != (mixOut == nil) {
            add(mixIn == nil ? "mix_in" : "mix_out", "is null while the other mix window is not; there are both or neither")
        }
        for (name, w) in [("mix_in", mixIn), ("mix_out", mixOut)] {
            guard let w else { continue }
            span(name, w.startBar, w.endBar)
            if let v = w.vocalFreeBars, v < 0 || v > max(w.endBar - w.startBar, 0) {
                add("\(name).vocal_free_bars", "\(v) must be between 0 and the window's \(w.endBar - w.startBar) bars")
            }
        }
        if let e = ends {
            if e.firstSoundS < 0 { add("ends.first_sound_s", "\(e.firstSoundS) is before the start") }
            if e.lastSoundS < e.firstSoundS { add("ends.last_sound_s", "\(e.lastSoundS) is before first_sound_s") }
            needsGrid("ends", e.fadeStartBar != nil || e.steadyInBar != nil || e.steadyOutBar != nil)
            line("ends.fade_start_bar", e.fadeStartBar)
            line("ends.steady_in_bar", e.steadyInBar)
            line("ends.steady_out_bar", e.steadyOutBar)
        }
        if let l = loudness { unit("loudness.confidence", l.confidence) }
        if let v = vocal {
            unit("vocal.mean", v.mean)
            unit("vocal.confidence", v.confidence)
        }
        needsGrid("vocal_structure", vocalStructure != nil)
        if let vs = vocalStructure { checkVocalStructure(vs, nBars: n, add: add) }
        needsGrid("hooks", hooks != nil)
        if let h = hooks {
            if h.source.isEmpty { add("hooks.source", "is empty") }
            if !(1...8).contains(h.latticePhaseBar) {
                add("hooks.lattice_phase_bar", "\(h.latticePhaseBar) must be 1 to 8")
            }
            for (j, c) in h.candidates.enumerated() {
                let path = "hooks.candidates[\(j)]"
                span(path, c.startBar, c.endBar)
                bar("\(path).repeat_start_bar", c.repeatStartBar)
                unit("\(path).strength", c.strength)
                unit("\(path).repetition", c.repetition)
                unit("\(path).loudness_score", c.loudnessScore)
                unit("\(path).vocal_density", c.vocalDensity)
                if j > 0 && c.strength > h.candidates[j - 1].strength {
                    add("\(path).strength", "\(c.strength) is above the previous candidate's; strongest come first")
                }
            }
        }
        if let o = onsetPattern16, o.count != 16 { add("onset_pattern_16", "has \(o.count) values, not 16") }
        for (j, f) in flags.enumerated() where f.isEmpty { add("flags[\(j)]", "is empty") }
        // Sidecar values are kept rounded to float16, so a value beyond its range (65504) has become infinite.
        let beyond = "holds a value that is not a number or is beyond float16's range (65504)"
        if let s = style {
            if s.model.isEmpty { add("style.model", "is empty") }
            if s.dims < 1 { add("style.dims", "\(s.dims) must be 1 or more") }
            if s.values.count != s.dims { add("style.dims", "is \(s.dims) but the style vector has \(s.values.count) values") }
            if !s.values.allSatisfy(\.isFinite) { add("style", beyond) }
        }
        for variant in signatures.keys.sorted(by: byteOrder) {
            if !isFileSafe(variant, also: ["-", "_", "+"]) {
                add("signatures.\(variant)", "the variant name must be letters, digits, -, + and _ only")
            }
            if signatures[variant]!.madeBy.isEmpty { add("signatures.\(variant).made_by", "is empty") }
        }
        if let r = imported?.rekordbox {
            let rb = "imported.rekordbox"
            if r.importedAt.isEmpty { add("\(rb).imported_at", "is empty") }
            for (j, g) in r.gridMarkers.enumerated() {
                if !(g.bpm > 0) { add("\(rb).grid_markers[\(j)].bpm", "\(g.bpm) must be above 0") }
                if g.beatInBar < 1 { add("\(rb).grid_markers[\(j)].beat_in_bar", "\(g.beatInBar) must be 1 or more") }
            }
            for (j, c) in r.cues.enumerated() {
                let path = "\(rb).cues[\(j)]"
                if c.kind.isEmpty { add("\(path).kind", "is empty") }
                if let h = c.hotCue, h < 0 { add("\(path).hot_cue", "\(h) must be 0 or more") }
            }
            for (j, l) in r.loops.enumerated() {
                let path = "\(rb).loops[\(j)]"
                if let h = l.hotCue, h < 0 { add("\(path).hot_cue", "\(h) must be 0 or more") }
                if let e = l.endS, e < l.startS { add("\(path).end_s", "\(e) is before start_s \(l.startS)") }
            }
        }
        if let b = bars {
            needsGrid("bars", true)
            for name in b.names {
                let values = b.series[name]!
                if !isFileSafe(name) {
                    add("bars", "\"\(name)\" is not a series name (letters, digits, - and _)")
                }
                if let n, values.count != n { add("bars.\(name)", "has \(values.count) values for the grid's \(n) bars") }
                if !values.allSatisfy(\.isFinite) { add("bars.\(name)", beyond) }
            }
        }
    }
}
