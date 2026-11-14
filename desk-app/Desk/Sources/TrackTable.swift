import SwiftUI
import DeckieCrate
import DeckieBuild
import DeckieDesk

struct TrackTable: View {
    @EnvironmentObject var model: DeskModel
    @State private var sortOrder = [KeyPathComparator(\CrateTrack.ident.title)]

    var body: some View {
        let all = model.crate?.tracks ?? []
        let tracks = (model.onlyNeedName ? all.filter { model.reason($0) != nil } : all).sorted(using: sortOrder)
        Table(tracks, selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn(Words.colTitle, value: \.ident.title) { (t: CrateTrack) in
                HStack(spacing: 6) { PlayButton(track: t); NameCell(track: t, field: "title") }
            }
            .width(min: 140, ideal: 220)
            TableColumn(Words.colArtist, value: \.ident.artist, comparator: OptionalStringComparator()) { (t: CrateTrack) in NameCell(track: t, field: "artist") }
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
            TableColumn(Words.colNotes) { (t: CrateTrack) in NotesCell(track: t) }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, ids.count == 1, let t = model.binding(for: id) {
                Button(Words.t("listen")) { model.listen(t) }
            }
            if ids.contains(where: { id in model.binding(for: id).map { model.reason($0) == "guess" } ?? false }) {
                Button(Words.t("looksRight")) { model.check(Array(ids)) }
            }
        }
        .onKeyPress(.space) {
            guard model.selection.count == 1, let id = model.selection.first, let t = model.binding(for: id) else { return .ignored }
            if model.listener.song == id { model.listener.stop() } else { model.listen(t) }
            return .handled
        }
        .onChange(of: model.selection) { _, sel in
            if let s = model.listener.song, !sel.contains(s) { model.listener.stop() }
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
        let others = k.votes.filter { (LocalFacts.djOrigins.contains($0.key) || $0.key == LocalFacts.ownVote) && $0.key != k.source }.sorted { $0.key < $1.key }
            .map { Words.keySays($0.key, $0.value) }
        return ([k.camelot + " " + Words.keyFrom(k.source)] + others).joined(separator: "; ")
    }

    static func notes(_ t: CrateTrack, reason: String? = nil) -> String {
        var n: [String] = []
        if let reason { n.append(Words.t("nameReason." + reason)) } else if LocalFacts.needsName(t) { n.append(Words.needsNameNote) }
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
                    let f = model.facts(t)
                    field(Words.title, t.ident.title, id: id, fact: f.title, field: "title") { v in
                        if let sp = DeskNaming.split(v) { offer = (id, v, sp.artist, sp.title, sp.version) }
                        else { model.update(id) { $0.ident.title = v } }
                    }
                    if let o = offer, o.id == id {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Words.t("splitOffer")).font(.callout)
                            HStack {
                                Button(Words.t("split")) { model.applySplit(id, artist: o.artist, title: o.title, version: o.version); offer = nil }
                                    .buttonStyle(.borderedProminent)
                                Button(Words.t("keepAsTyped")) { model.update(id) { $0.ident.title = o.text }; offer = nil }
                            }
                        }.padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    field(Words.artist, t.ident.artist ?? "", id: id, fact: f.artist, field: "artist") { v in model.update(id) { $0.ident.artist = v.isEmpty ? nil : v } }
                    field(Words.version, t.ident.version ?? "", id: id, fact: f.version, field: "version") { v in model.update(id) { $0.ident.version = v.isEmpty ? nil : v } }
                    // A song's facts (D34): release, year, label and genre as fields like the names, with where each
                    // came from; the rest listed. Everything here goes to the iPad.
                    ForEach(DeskNaming.factFields, id: \.self) { name in
                        factField(name, f.fact(name), id: id)
                    }
                    if !f.others.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Words.t("moreFacts")).font(.caption).foregroundStyle(.secondary)
                            ForEach(f.others, id: \.name) { o in
                                Text(DeskWords.coded("factName", o.name) + ": " + o.value).textSelection(.enabled)
                                    .help(o.from.map { DeskWords.coded("factFrom", $0) } ?? "")
                            }
                        }
                    }
                    if !f.fileTags.isEmpty || !f.leftOut.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Words.t("fileTagsHeading")).font(.caption).foregroundStyle(.secondary)
                            ForEach(f.fileTags, id: \.name) { o in
                                Text(o.name + ": " + o.value).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            if !f.leftOut.isEmpty {
                                Text(Words.t("leftOutLine", ["what": f.leftOut.keys.sorted().map { DeskWords.coded("leftOut", $0) }.joined(separator: ", ")]))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        Button(model.listener.song == id ? Words.t("stopListening") : Words.t("listen")) {
                            model.listener.song == id ? model.listener.stop() : model.listen(t)
                        }.buttonStyle(.borderedProminent)
                        if model.reason(t) == "guess" { Button(Words.t("looksRight")) { model.check([id]) }.help(Words.t("looksRightHelp")) }
                        // LOOK UP SONG VIA ... GOES HERE (the note on D30): the one explicit lookup, by sound, beside Listen.
                        // Not built: route A sends nothing anywhere.
                    }
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

    @State private var offer: (id: String, text: String, artist: String?, title: String, version: String?)?

    @ViewBuilder func field(_ label: String, _ value: String, id: String, fact: DeskNaming.Fact? = nil, field name: String = "",
                            set: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            CommitField(label: label, value: value, commit: set, guess: fact?.guess ?? false,
                        same: { if fact?.guess == true { model.check([id], field: name) } }).id(id + label)
            if let fact { Text(Words.fromLine(fact)).font(.caption2).foregroundStyle(fact.guess ? .orange : .secondary) }
        }
    }

    /// One of a song's facts (D34), edited like a name: Return or leaving the field keeps it as the DJ's; empty clears it.
    @ViewBuilder func factField(_ name: String, _ fact: DeskNaming.Fact, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Words.t(name)).font(.caption).foregroundStyle(.secondary)
            CommitField(label: Words.t(name), value: fact.value ?? "", commit: { v in
                if v != (fact.value ?? "") { model.setFacts(id, [name: v]) }
            }, guess: false, same: {}).id(id + name)
            Text(fact.value == nil ? Words.t("factNotFound") : DeskWords.coded("factFrom", fact.from ?? ""))
                .font(.caption2).foregroundStyle(.secondary)
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
    /// Desk's guess: drawn lighter; Return on it as it is keeps it (`same`).
    var guess = false
    var same: () -> Void = {}
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.roundedBorder)
            .italic(guess && text == value)
            .foregroundStyle(guess && text == value ? .secondary : .primary)
            .focused($focused)
            .onAppear { text = value }
            .onChange(of: value) { _, v in if !focused { text = v } }
            .onChange(of: focused) { _, f in if !f, text != value { commit(text) } }
            .onSubmit { if text != value { commit(text) } else { same() } }
            .onDisappear { if text != value { commit(text) } }
    }
}

/// The play button at the start of each row, inside the Title cell (a column of its own passed the table builder's
/// limit): play, and pause for the song that is playing; pressed again, it plays on from where it paused. It selects
/// its row, as the Windows and Linux window's does, and never starts an edit: titles are edited in the inspector. The
/// space bar on the selected song and the context menu's Listen still work; a screen reader reads it as "Listen to
/// <title>" or "Pause <title>".
struct PlayButton: View {
    @EnvironmentObject var model: DeskModel
    let track: CrateTrack
    var body: some View {
        let mine = model.listener.song == track.id
        let pause = mine && model.listener.playing
        let label = Words.t(pause ? "pauseSong" : "listenTo", ["title": track.ident.title])
        Button {
            model.selection = [track.id]
            model.playOrPause(track)
        } label: {
            Image(systemName: pause ? "pause.fill" : "play.fill").frame(width: 14)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(mine ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A title or an artist: lighter and slanted when it is Desk's guess.
struct NameCell: View {
    @EnvironmentObject var model: DeskModel
    let track: CrateTrack
    let field: String
    var body: some View {
        let f = model.facts(track).fact(field)
        let text = field == "title" ? track.ident.title : (track.ident.artist ?? "")
        Text(text).italic(f.guess).foregroundStyle(f.guess ? Color.secondary : Color.primary)
    }
}

/// The notes, with why the song needs a name first.
struct NotesCell: View {
    @EnvironmentObject var model: DeskModel
    let track: CrateTrack
    var body: some View {
        let why = model.reason(track)
        Text(TrackTable.notes(track, reason: why)).foregroundStyle(why != nil ? Color.orange : Color.secondary).lineLimit(1)
    }
}
