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
                HStack(spacing: Look.Space.titleCell) { PlayButton(track: t); NameCell(track: t, field: "title") }
            }
            .width(min: Look.Size.colTitleMin, ideal: Look.Size.colTitleIdeal)
            TableColumn(Words.colArtist, value: \.ident.artist, comparator: OptionalStringComparator()) { (t: CrateTrack) in NameCell(track: t, field: "artist") }
                .width(min: Look.Size.colArtistMin, ideal: Look.Size.colArtistIdeal)
            TableColumn(Words.colTempo) { t in Text(t.grid.map { Words.tempo($0.bpm) } ?? Words.none) }.width(Look.Size.colTempo)
            TableColumn(Words.colKey) { t in
                HStack(spacing: Look.Space.keyCell) {
                    Text(Self.keyCell(t)).lineLimit(1).help(Self.keyHelp(t))
                    if t.key != nil, t.flags.contains("key_uncertain") { Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help(Words.notSureOfKey) }
                }
            }.width(min: Look.Size.colKey, ideal: Look.Size.colKeyIdeal)
            TableColumn(Words.colKeyFrom) { t in
                Text(t.key.map { Words.programName($0.source) } ?? "").foregroundStyle(.secondary).lineLimit(1).help(Self.keyHelp(t))
            }.width(min: Look.Size.colKeyFromMin, ideal: Look.Size.colKeyFromIdeal)
            TableColumn(Words.colBars) { t in Text(t.grid.map { "\($0.nBars)" } ?? Words.none) }.width(Look.Size.colBars)
            TableColumn(Words.colLength) { t in Text(Words.mmss(t.file.durationS)) }.width(Look.Size.colLength)
            TableColumn(Words.colVocals) { t in Text(t.vocal.map { Words.percent($0.mean) } ?? Words.none) }.width(Look.Size.colVocals)
            TableColumn(Words.colWhere) { t in Text(Words.places(Self.places(t))).lineLimit(1).help(Self.places(t).joined(separator: "\n")) }
                .width(min: Look.Size.colWhereMin, ideal: Look.Size.colWhereIdeal)
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
        guard let k = t.key else { return noKeyWords(t) }
        let others = k.votes.filter { (LocalFacts.djOrigins.contains($0.key) || $0.key == LocalFacts.ownVote) && $0.key != k.source }.sorted { $0.key < $1.key }
            .map { Words.keySays($0.key, $0.value) }
        return Words.keyHelp([Words.keyHelpFirst(k.camelot, from: k.source)] + others)
    }

    /// What the Key column shows (D33, D36, as the pages do): the code; "Home note A" when the reader found the home
    /// note alone; else the dash, with the words in its help.
    static func keyCell(_ t: CrateTrack) -> String {
        if let k = t.key { return k.camelot }
        if t.keyState == .homeNote, let h = t.keyHome { return Words.homeNote(h.note) }
        return Words.none
    }

    /// A song with no key, in words, by what its record says: the home note and the two keys it can fit; Deckie read
    /// it and is not sure; or no key was read on the computer that made the record.
    static func noKeyWords(_ t: CrateTrack) -> String {
        switch t.keyState {
        case .homeNote:
            guard let h = t.keyHome, h.camelot.count == 2 else { return Words.keyNotRead }
            return Words.homeNoteHelp(minor: h.camelot[0], major: h.camelot[1])
        case .notSure: return Words.keyDeckieNotSure
        case .key, .notRead: return Words.keyNotRead
        }
    }

    static func notes(_ t: CrateTrack, reason: String? = nil) -> String {
        var n: [String] = []
        if let reason { n.append(Words.t("nameReason." + reason)) } else if LocalFacts.needsName(t) { n.append(Words.needsNameNote) }
        if let d = t.file.damagedFrames, !d.isEmpty { n.append(Words.damagedFrames(d.count)) }
        if t.flags.contains("low_grid_confidence") { n.append(Words.gridUnsure) }
        if t.flags.contains("vocal_unknown") { n.append(Words.vocalsNotRead) }
        if !t.signatures.isEmpty { n.append(Words.signed) }
        return Words.notesLine(n)
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
                VStack(alignment: .leading, spacing: Look.Space.inspector) {
                    // The song's cover (D36), small, as the pages show it; a song without one gets the same empty square.
                    CoverSquare(package: model.current.map { model.shelf.package($0.id) }, hash: t.file.cover)
                    Text(Words.names).font(Look.Fonts.inspectorHeading)
                    let f = model.facts(t)
                    field(Words.title, t.ident.title, id: id, fact: f.title, field: "title") { v in
                        if let sp = DeskNaming.split(v) { offer = (id, v, sp.artist, sp.title, sp.version) }
                        else { model.update(id) { $0.ident.title = v } }
                    }
                    if let o = offer, o.id == id {
                        VStack(alignment: .leading, spacing: Look.Space.splitOffer) {
                            Text(Words.t("splitOffer")).font(Look.Fonts.splitOffer)
                            HStack {
                                Button(Words.t("split")) { model.applySplit(id, artist: o.artist, title: o.title, version: o.version); offer = nil }
                                    .buttonStyle(.borderedProminent)
                                Button(Words.t("keepAsTyped")) { model.update(id) { $0.ident.title = o.text }; offer = nil }
                            }
                        }.padding(Look.Space.splitOfferPadding).background(.quaternary, in: RoundedRectangle(cornerRadius: Look.Shape.splitOffer))
                    }
                    field(Words.artist, t.ident.artist ?? "", id: id, fact: f.artist, field: "artist") { v in model.update(id) { $0.ident.artist = v.isEmpty ? nil : v } }
                    field(Words.version, t.ident.version ?? "", id: id, fact: f.version, field: "version") { v in model.update(id) { $0.ident.version = v.isEmpty ? nil : v } }
                    // A song's facts (D34): release, year, label and genre as fields like the names, with where each
                    // came from; the rest listed. Everything here goes to the iPad.
                    ForEach(DeskNaming.factFields, id: \.self) { name in
                        factField(name, f.fact(name), id: id)
                    }
                    if !f.others.isEmpty {
                        VStack(alignment: .leading, spacing: Look.Space.inspectorGroup) {
                            Text(Words.t("moreFacts")).font(Look.Fonts.inspectorLabel).foregroundStyle(.secondary)
                            ForEach(f.others, id: \.name) { o in
                                Text(Words.moreFactLine(DeskWords.coded("factName", o.name), o.value)).textSelection(.enabled)
                                    .help(o.from.map { DeskWords.coded("factFrom", $0) } ?? "")
                            }
                        }
                    }
                    if !f.fileTags.isEmpty || !f.leftOut.isEmpty {
                        VStack(alignment: .leading, spacing: Look.Space.inspectorGroup) {
                            Text(Words.t("fileTagsHeading")).font(Look.Fonts.inspectorLabel).foregroundStyle(.secondary)
                            ForEach(f.fileTags, id: \.name) { o in
                                Text(Words.fileTagLine(o.name, o.value)).font(Look.Fonts.fileTag).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            if !f.leftOut.isEmpty {
                                Text(Words.t("leftOutLine", ["what": Words.leftOut(f.leftOut.keys.sorted().map { DeskWords.coded("leftOut", $0) })]))
                                    .font(Look.Fonts.inspectorSmallPrint).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        Button(model.listener.song == id ? Words.t("stopListening") : Words.t("listen")) {
                            model.listener.song == id ? model.listener.stop() : model.listen(t)
                        }.buttonStyle(.borderedProminent)
                        if model.reason(t) == "guess" { Button(Words.t("looksRight")) { model.check([id]) }.help(Words.t("looksRightHelp")) }
                        // "Look up via MusicBrainz" (D36): the one step that uses the internet, in its own colour. A
                        // lookup by sound (AcoustID) would sit beside it, feeding the same review (Lookup.swift).
                        Button { model.lookUp(scope: "song", ids: [id]) } label: { Label(Words.t("lookupOne"), systemImage: LookupStyle.icon) }
                            .buttonStyle(.bordered).tint(LookupStyle.net)
                    }
                    // After the sentence has been read once, it sits under the button (letter AA, 3.8).
                    if model.lookupExplained, let what = DeskLookup.plan(model.toolSongs(source: nil, ids: [id])).summary.what, !what.isEmpty {
                        HStack(spacing: Look.Space.lookupUnder) {
                            Text(Words.t("lookupUnder", ["what": Words.lookupWhat(what.map { Words.t("lookupWhat." + $0[0], ["value": $0[1]]) })]))
                            Button(Words.t("lookupSentLink")) { model.showSent = true }.buttonStyle(.link)
                        }
                        .font(Look.Fonts.lookupUnder).foregroundStyle(.secondary)
                    }
                    field(Words.tags, Words.tagsField(t.ident.tags), id: id) { v in
                        model.update(id) { $0.ident.tags = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    }
                    VStack(alignment: .leading, spacing: Look.Space.inspectorGroup) {
                        let places = TrackTable.places(t)
                        Text(places.count > 1 ? Words.whereWithPlaces(places.count) : Words.whereLabel).font(Look.Fonts.inspectorLabel).foregroundStyle(.secondary)
                        ForEach(places.indices, id: \.self) { i in
                            Text(places[i]).foregroundStyle(i == 0 ? .primary : .secondary)
                        }
                    }
                    let copies = model.copies(of: t)
                    if !copies.isEmpty {
                        VStack(alignment: .leading, spacing: Look.Space.inspectorGroup) {
                            Text(Words.alsoInYourCrateAs).font(Look.Fonts.inspectorLabel).foregroundStyle(.secondary)
                            ForEach(copies, id: \.id) { c in
                                (Text(c.file.rel ?? c.file.name)
                                    + Text(c.ident.disc == nil ? "" : Words.copyPlace(TrackTable.place(c))).foregroundColor(.secondary))
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                    Divider()
                    Text(Words.whatDeskFound).font(Look.Fonts.inspectorHeading)
                    Grid(alignment: .leading, verticalSpacing: Look.Space.foundRows) {
                        row(Words.rowFile, t.file.name)
                        if let g = t.grid { row(Words.rowTempo, Words.tempoValue(bpm: g.bpm, bars: g.nBars, firstDownbeat: g.firstDownbeatS)) }
                        if let segs = t.tempoSegments, segs.count > 1 { row(Words.rowTempoChanges, Words.segments(segs.count)) }
                        if let k = t.key { row(Words.rowKey, Words.rowKeyText(camelot: k.camelot, key: k.key, scale: k.scale, notSure: t.flags.contains("key_uncertain"), help: String(TrackTable.keyHelp(t).dropFirst(k.camelot.count + 1)))) }
                        else if t.keyState == .homeNote, let h = t.keyHome { row(Words.rowKey, Words.homeNote(h.note)); row("", TrackTable.noKeyWords(t)) }
                        else { row(Words.rowKey, TrackTable.noKeyWords(t)) }
                        if let s = t.ident.source { row(Words.rowNameFrom, Words.nameFrom(s)) }
                        if let ch = t.key?.changes, !ch.isEmpty { row(Words.rowKeyChanges, Words.keyChanges(ch.map { Words.keyFromBar($0.camelot, $0.startBar) })) }
                        if let l = t.loudness { row(Words.rowLoudness, Words.loudnessValue(lufs: l.integratedLufs, peak: l.truePeakDb)) }
                        if let mi = t.mixIn, let mo = t.mixOut { row(Words.rowMixWindows, Words.mixWindows(inFrom: mi.startBar, inTo: mi.endBar, outFrom: mo.startBar, outTo: mo.endBar)) }
                        if let s = t.sections { row(Words.rowSections, Words.sections(s.map { Words.sectionAt($0.label, bar: $0.startBar) })) }
                        if let v = t.vocal { row(Words.rowVocals, Words.vocalsValue(v.mean, heavy: v.heavy)) }
                        row(Words.rowEngine, Words.engineOn(t.analysis.engine, t.analysis.device))
                        row(Words.rowSignatures, t.signatures.isEmpty ? Words.noneYet : Words.signatures(t.signatures.keys.sorted()))
                        if let d = t.file.damagedFrames, !d.isEmpty { row(Words.rowDamagedFrames, Words.damagedAtList(d.map { Words.damagedAt($0.startS) })) }
                    }.font(Look.Fonts.found)
                }.padding(Look.Space.inspectorPadding)
            } else {
                VStack(spacing: Look.Space.inspectorEmpty) {
                    Text(model.selection.isEmpty ? Words.selectSong : Words.songsSelected(model.selection.count))
                        .foregroundStyle(.secondary)
                    if let f = model.musicFolder { Text(Words.musicAt(f.path)).font(Look.Fonts.musicAt).foregroundStyle(.secondary).lineLimit(2) }
                    Button(Words.whereIsThisMusic) { model.chooseMusicFolder() }.controlSize(.small)
                }.padding(Look.Space.inspectorPadding)
            }
        }
    }

    @State private var offer: (id: String, text: String, artist: String?, title: String, version: String?)?

    @ViewBuilder func field(_ label: String, _ value: String, id: String, fact: DeskNaming.Fact? = nil, field name: String = "",
                            set: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Look.Space.field) {
            Text(label).font(Look.Fonts.inspectorLabel).foregroundStyle(.secondary)
            CommitField(label: label, value: value, commit: set, guess: fact?.guess ?? false,
                        same: { if fact?.guess == true { model.check([id], field: name) } }).id(id + label)
            if let fact { Text(Words.fromLine(fact)).font(Look.Fonts.inspectorSmallPrint).foregroundStyle(fact.guess ? Look.Colour.guess : .secondary) }
        }
    }

    /// One of a song's facts (D34), edited like a name: Return or leaving the field keeps it as the DJ's; empty clears it.
    @ViewBuilder func factField(_ name: String, _ fact: DeskNaming.Fact, id: String) -> some View {
        VStack(alignment: .leading, spacing: Look.Space.field) {
            Text(Words.t(name)).font(Look.Fonts.inspectorLabel).foregroundStyle(.secondary)
            CommitField(label: Words.t(name), value: fact.value ?? "", commit: { v in
                if v != (fact.value ?? "") { model.setFacts(id, [name: v]) }
            }, guess: false, same: {}).id(id + name)
            Text(fact.value == nil ? Words.t("factNotFound") : DeskWords.coded("factFrom", fact.from ?? ""))
                .font(Look.Fonts.inspectorSmallPrint).foregroundStyle(.secondary)
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
            Image(systemName: pause ? "pause.fill" : "play.fill").frame(width: Look.Size.playButton)
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
        Text(TrackTable.notes(track, reason: why)).foregroundStyle(why != nil ? Look.Colour.needsName : Color.secondary).lineLimit(1)
    }
}

/// A song's cover in the names panel (D36): the crate file's `covers/<hash>.jpg`, read when the song is shown and
/// never before, through the reader's checks (`CrateReader.coverData`). A song without one, a cover still being read,
/// and one that cannot be shown all get the same empty square, so the fields below never move when a picture arrives.
struct CoverSquare: View {
    let package: URL?
    let hash: String?
    @State private var image: NSImage?
    @State private var shown: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Look.Shape.cover).fill(Look.Colour.coverEmpty)
            if let image, shown == hash {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: Look.Size.cover, height: Look.Size.cover)
        .clipShape(RoundedRectangle(cornerRadius: Look.Shape.cover))
        .accessibilityElement()
        .accessibilityLabel(image != nil && shown == hash ? Words.cover : Words.noCover)
        .task(id: hash) {
            image = nil; shown = hash
            guard let package, let hash else { return }
            let data = await Task.detached(priority: .utility) { CrateReader.coverData(in: package, hash: hash) }.value
            if !Task.isCancelled, shown == hash, let data { image = NSImage(data: data) }
        }
    }
}
