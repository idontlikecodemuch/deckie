import SwiftUI
import DeckieCrate
import DeckieBuild

struct TrackTable: View {
    @EnvironmentObject var model: DeskModel
    @State private var sortOrder = [KeyPathComparator(\CrateTrack.ident.title)]

    var body: some View {
        let all = model.crate?.tracks ?? []
        let tracks = (model.onlyNeedName ? all.filter(LocalFacts.needsName) : all).sorted(using: sortOrder)
        Table(tracks, selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn(Words.colTitle, value: \.ident.title) { Text($0.ident.title) }
            TableColumn(Words.colArtist, value: \.ident.artist, comparator: OptionalStringComparator()) { Text($0.ident.artist ?? "") }
                .width(min: 100, ideal: 160)
            TableColumn(Words.colTempo) { t in Text(t.grid.map { Words.tempo($0.bpm) } ?? Words.none) }.width(60)
            TableColumn(Words.colKey) { t in
                HStack(spacing: 4) {
                    Text(t.key?.camelot ?? Words.none).help(Self.keyHelp(t))
                    if t.flags.contains("key_uncertain") { Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help(Words.notSureOfKey) }
                }
            }.width(60)
            TableColumn(Words.colKeyFrom) { t in
                Text(t.key.map { Words.programName($0.source) } ?? "").foregroundStyle(.secondary).lineLimit(1).help(Self.keyHelp(t))
            }.width(min: 60, ideal: 90)
            TableColumn(Words.colBars) { t in Text(t.grid.map { "\($0.nBars)" } ?? Words.none) }.width(50)
            TableColumn(Words.colLength) { t in Text(Words.mmss(t.file.durationS)) }.width(60)
            TableColumn(Words.colVocals) { t in Text(t.vocal.map { Words.percent($0.mean) } ?? Words.none) }.width(56)
            TableColumn(Words.colWhere) { t in Text(Self.places(t).joined(separator: " · ")).lineLimit(1).help(Self.places(t).joined(separator: "\n")) }
                .width(min: 80, ideal: 180)
            TableColumn(Words.colNotes) { t in Text(Self.notes(t)).foregroundStyle(.secondary).lineLimit(1) }
        }
    }

    /// Where a song's own place is: "Stick 3 / House 4" on a source, else its folder on the Mac ("House"), or "" at
    /// the top.
    static func place(_ t: CrateTrack) -> String {
        Crate.discLine(t) ?? ((t.file.rel ?? "") as NSString).deletingLastPathComponent
    }

    /// Every place a song is (D27), the one that leads first: "Friday / Set 1", "Stick 3 / House 1", then its folders
    /// on the Mac ("Burned", or "the top of the music folder").
    static func places(_ t: CrateTrack) -> [String] {
        t.placesInOrder.map { p in
            Crate.placeLine(p) ?? ((p.folder ?? "").isEmpty ? Words.topOfMusicFolder : p.folder!)
        }
    }

    /// The key and where it came from, then what the DJ's other programs and tags say ("8A from Traktor; rekordbox says
    /// 9A"), or D16's words when there is no key.
    static func keyHelp(_ t: CrateTrack) -> String {
        guard let k = t.key else { return Words.keyNotRead }
        let others = k.votes.filter { LocalFacts.djOrigins.contains($0.key) && $0.key != k.source }.sorted { $0.key < $1.key }
            .map { Words.keySays($0.key, $0.value) }
        return ([k.camelot + " " + Words.keyFrom(k.source)] + others).joined(separator: "; ")
    }

    static func notes(_ t: CrateTrack) -> String {
        var n: [String] = []
        if LocalFacts.needsName(t) { n.append(Words.needsNameNote) }
        if let d = t.file.damagedFrames, !d.isEmpty { n.append(Words.damagedFrames(d.count)) }
        if t.flags.contains("low_grid_confidence") { n.append(Words.gridUnsure) }
        if t.flags.contains("vocal_unknown") { n.append(Words.vocalsNotRead) }
        if !t.signatures.isEmpty { n.append(Words.signed) }
        return n.joined(separator: ", ")
    }
}

struct OptionalStringComparator: SortComparator {
    var order: SortOrder = .forward
    func compare(_ a: String?, _ b: String?) -> ComparisonResult {
        let r: ComparisonResult
        switch (a, b) {
        case (nil, nil): r = .orderedSame
        case (nil, _): r = .orderedAscending
        case (_, nil): r = .orderedDescending
        case let (x?, y?): r = x.localizedCaseInsensitiveCompare(y)
        }
        return order == .forward ? r : r.reversed
    }
}

private extension ComparisonResult {
    var reversed: ComparisonResult { self == .orderedAscending ? .orderedDescending : (self == .orderedDescending ? .orderedAscending : .orderedSame) }
}

/// The right-hand panel: the selected track's names, as the DJ wants them, and what the analysis found.
struct Inspector: View {
    @EnvironmentObject var model: DeskModel

    var body: some View {
        ScrollView {
            if model.selection.count == 1, let id = model.selection.first, let t = model.binding(for: id) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(Words.names).font(.headline)
                    field(Words.title, t.ident.title, id: id) { v in model.update(id) { $0.ident.title = v } }
                    field(Words.artist, t.ident.artist ?? "", id: id) { v in model.update(id) { $0.ident.artist = v.isEmpty ? nil : v } }
                    field(Words.version, t.ident.version ?? "", id: id) { v in model.update(id) { $0.ident.version = v.isEmpty ? nil : v } }
                    field(Words.tags, t.ident.tags.joined(separator: ", "), id: id) { v in
                        model.update(id) { $0.ident.tags = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        let places = TrackTable.places(t)
                        Text(places.count > 1 ? Words.whereWithPlaces(places.count) : Words.whereLabel).font(.caption).foregroundStyle(.secondary)
                        ForEach(places.indices, id: \.self) { i in
                            Text(places[i]).foregroundStyle(i == 0 ? .primary : .secondary)
                        }
                    }
                    let copies = model.copies(of: t)
                    if !copies.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Words.alsoInYourCrateAs).font(.caption).foregroundStyle(.secondary)
                            ForEach(copies, id: \.id) { c in
                                (Text(c.file.rel ?? c.file.name)
                                    + Text(c.ident.disc == nil ? "" : "  (\(TrackTable.place(c)))").foregroundColor(.secondary))
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                    Divider()
                    Text(Words.whatDeskFound).font(.headline)
                    Grid(alignment: .leading, verticalSpacing: 4) {
                        row(Words.rowFile, t.file.name)
                        if let g = t.grid { row(Words.rowTempo, Words.tempoValue(bpm: g.bpm, bars: g.nBars, firstDownbeat: g.firstDownbeatS)) }
                        if let segs = t.tempoSegments, segs.count > 1 { row(Words.rowTempoChanges, Words.segments(segs.count)) }
                        if let k = t.key { row(Words.rowKey, "\(k.camelot)" + (k.key.map { " (\($0) \(k.scale ?? ""))" } ?? "") + (t.flags.contains("key_uncertain") ? Words.keyNotSure : "") + "\n" + String(TrackTable.keyHelp(t).dropFirst(k.camelot.count + 1))) }
                        else { row(Words.rowKey, Words.keyNotRead) }
                        if let s = t.ident.source { row(Words.rowNameFrom, Words.nameFrom(s)) }
                        if let ch = t.key?.changes, !ch.isEmpty { row(Words.rowKeyChanges, ch.map { Words.keyFromBar($0.camelot, $0.startBar) }.joined(separator: ", ")) }
                        if let l = t.loudness { row(Words.rowLoudness, Words.loudnessValue(lufs: l.integratedLufs, peak: l.truePeakDb)) }
                        if let mi = t.mixIn, let mo = t.mixOut { row(Words.rowMixWindows, Words.mixWindows(inFrom: mi.startBar, inTo: mi.endBar, outFrom: mo.startBar, outTo: mo.endBar)) }
                        if let s = t.sections { row(Words.rowSections, s.map { "\($0.label) \($0.startBar)" }.joined(separator: ", ")) }
                        if let v = t.vocal { row(Words.rowVocals, Words.vocalsValue(v.mean, heavy: v.heavy)) }
                        row(Words.rowEngine, Words.engineOn(t.analysis.engine, t.analysis.device))
                        row(Words.rowSignatures, t.signatures.isEmpty ? Words.noneYet : t.signatures.keys.sorted().joined(separator: ", "))
                        if let d = t.file.damagedFrames, !d.isEmpty { row(Words.rowDamagedFrames, d.map { String(format: "%.1f s", $0.startS) }.joined(separator: ", ")) }
                    }.font(.callout)
                }.padding(14)
            } else {
                VStack(spacing: 8) {
                    Text(model.selection.isEmpty ? Words.selectSong : Words.songsSelected(model.selection.count))
                        .foregroundStyle(.secondary)
                    if let f = model.musicFolder { Text(Words.musicAt(f.path)).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    Button(Words.whereIsThisMusic) { model.chooseMusicFolder() }.controlSize(.small)
                }.padding(14)
            }
        }
    }

    @ViewBuilder func field(_ label: String, _ value: String, id: String, set: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            CommitField(label: label, value: value, commit: set).id(id + label)
        }
    }

    @ViewBuilder func row(_ k: String, _ v: String) -> some View {
        GridRow { Text(k).foregroundStyle(.secondary).gridColumnAlignment(.trailing); Text(v).textSelection(.enabled) }
    }
}

extension CrateTrack: @retroactive Identifiable {}

/// A text field that changes the crate when the DJ is done with it (Return, or leaving the field), so one fix is one
/// undo step, not one per letter. It follows the value when the value changes elsewhere (undo, another song).
struct CommitField: View {
    let label: String
    let value: String
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { text = value }
            .onChange(of: value) { _, v in if !focused { text = v } }
            .onChange(of: focused) { _, f in if !f, text != value { commit(text) } }
            .onSubmit { if text != value { commit(text) } }
            .onDisappear { if text != value { commit(text) } }
    }
}
