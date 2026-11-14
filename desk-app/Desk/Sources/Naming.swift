import SwiftUI
import DeckieCrate
import DeckieDesk
import DeckieDisc

/// Listen (D33): play and pause, back and forward 30 seconds, the scrub bar, the position and the length.
struct PlayerBar: View {
    @EnvironmentObject var model: DeskModel
    @ObservedObject var listener: Listener
    @State private var scrub: Double?

    var body: some View {
        HStack(spacing: 10) {
            Button { listener.toggle() } label: { Image(systemName: listener.playing ? "pause.fill" : "play.fill") }
                .help(listener.playing ? Words.t("pause") : Words.t("play"))
            Button { listener.seek(listener.position - DeskListen.step) } label: { Image(systemName: "gobackward.30") }
                .help(Words.t("back30"))
            Slider(value: Binding(get: { scrub ?? listener.position }, set: { scrub = $0 }),
                   in: 0...max(1, listener.length)) { editing in
                if !editing, let s = scrub { listener.seek(s); scrub = nil }
            }
            .accessibilityLabel(Words.t("listenPosition", ["title": listener.title]))
            Button { listener.seek(listener.position + DeskListen.step) } label: { Image(systemName: "goforward.30") }
                .help(Words.t("forward30"))
            Text(listener.length > 0
                 ? Words.t("listenTime", ["position": Words.mmss(scrub ?? listener.position), "length": Words.mmss(listener.length)])
                 : Words.t("listenGettingReady", ["title": listener.title]))
                .monospacedDigit().foregroundStyle(.secondary)
            Text(listener.title).lineLimit(1).frame(maxWidth: 220, alignment: .leading)
            Button(Words.t("stopListening")) { listener.stop() }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
    }
}

/// A batch tool (letter AA, 3.6): what it works on, its input, and a preview with a tick per field before anything
/// changes; "Use n names" applies the ticked ones as one undo step.
struct ToolSheet: View {
    @EnvironmentObject var model: DeskModel
    let kind: String
    @State private var source = ""
    @State private var text = ""
    @State private var pattern = DeskNaming.patterns[0]
    @State private var playlist: URL?
    @State private var onlyEmpty = true
    @State private var preview: DeskNaming.Preview?
    @State private var ticks = Set<Int>()

    var title: String { Words.t(["paste": "pasteList", "pattern": "namesFromFileNames", "playlist": "namesFromPlaylist"][kind] ?? "nameTools").replacingOccurrences(of: "…", with: "") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2)
            HStack {
                Picker(Words.t("toolSongsFrom"), selection: $source) {
                    ForEach(model.crate?.discPlan.map(\.name) ?? [], id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 320)
                Toggle(Words.t("onlyEmpty"), isOn: $onlyEmpty)
            }
            switch kind {
            case "paste":
                Text(Words.t("pasteHelp")).foregroundStyle(.secondary)
                TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            case "pattern":
                HStack {
                    TextField(Words.t("patternLabel"), text: $pattern).textFieldStyle(.roundedBorder)
                    Menu("") { ForEach(DeskNaming.patterns, id: \.self) { p in Button(p) { pattern = p } } }.frame(width: 30)
                }
                Text(Words.t("patternHelp")).font(.caption).foregroundStyle(.secondary)
            default:
                Text(Words.t("choosePlaylistMessage")).foregroundStyle(.secondary)
                HStack {
                    Button(Words.t("choosePlaylist")) { choosePlaylist() }
                    Text(playlist?.lastPathComponent ?? "").foregroundStyle(.secondary)
                }
            }
            Text(Words.t("previewTitle")).font(.headline)
            if let line = problemLine { Text(line).foregroundStyle(preview?.problem != nil ? .orange : .secondary) }
            List {
                if let p = preview {
                    ForEach(p.changes.indices, id: \.self) { i in
                        let c = p.changes[i]
                        HStack {
                            Toggle("", isOn: Binding(get: { ticks.contains(i) }, set: { if $0 { ticks.insert(i) } else { ticks.remove(i) } }))
                                .labelsHidden().disabled(c.locked)
                            Text(songLabel(c.song)).frame(width: 180, alignment: .leading).lineLimit(1)
                            Text(Words.t(c.field)).frame(width: 70, alignment: .leading)
                            Text(c.before ?? Words.none).foregroundStyle(.secondary).frame(width: 150, alignment: .leading).lineLimit(1)
                            Text(c.after ?? "").lineLimit(1)
                            if let n = c.note { Text("(" + Words.t("changeNote." + n) + ")").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }.frame(minHeight: 200)
            HStack {
                Spacer()
                Button(Words.cancel) { model.tool = nil }.keyboardShortcut(.cancelAction)
                Button(Words.c("useNames", usable)) {
                    if let p = preview { model.apply(p, ticks: ticks) }
                    model.tool = nil
                }.buttonStyle(.borderedProminent).disabled(usable == 0)
            }
        }
        .padding(20).frame(width: 760, height: 600)
        .onAppear {
            let sources = model.crate?.discPlan.map(\.name) ?? []
            let sel = model.selection.first.flatMap { model.binding(for: $0) }?.ident.disc
            source = sel ?? model.needingNames.first?.ident.disc ?? sources.first ?? ""
            if let t = model.toolPrefill { text = t; model.toolPrefill = nil }
            if kind == "playlist", let preset = ProcessInfo.processInfo.environment["DECKIE_DESK_PLAYLIST"] { playlist = URL(fileURLWithPath: preset) }
            refresh()
        }
        .onChange(of: text) { _, _ in refresh() }
        .onChange(of: pattern) { _, _ in refresh() }
        .onChange(of: source) { _, _ in refresh() }
        .onChange(of: onlyEmpty) { _, _ in refresh() }
        .onChange(of: playlist) { _, _ in refresh() }
    }

    var usable: Int { preview?.problem == nil ? ticks.count : 0 }

    var problemLine: String? {
        guard let p = preview else { return nil }
        switch p.problem {
        case "counts": return Words.t("countsDiffer", ["songs": Words.songs(p.songs), "lines": Words.c("lines", p.lines)])
        case "empty": return kind == "playlist" && playlist == nil ? nil : Words.t("listEmpty")
        case "noMatch": return Words.t("patternFitsNone")
        default: break
        }
        if p.changes.isEmpty { return Words.t("nothingToChange") }
        if p.tool == "pattern" { return Words.t("patternFits", ["fits": "\(p.lines)", "songs": "\(p.songs)"]) }
        if p.tool == "playlist" {
            guard let d = p.lengthsDiffer else { return Words.t("playlistNoLengths") }
            return d == 0 ? Words.t("lengthsAllMatch") : Words.c("lengthsDiffer", d)
        }
        return nil
    }

    func songLabel(_ id: String) -> String {
        guard let t = model.binding(for: id) else { return id }
        return (t.ident.track.map { String(format: "%02d  ", $0) } ?? "") + t.ident.title
    }

    func refresh() {
        let p = model.preview(kind, source: source.isEmpty ? nil : source, text: text, pattern: pattern, playlist: playlist,
                              onlyEmpty: onlyEmpty)
        preview = p
        ticks = Set(p.changes.indices.filter { p.changes[$0].tick })
    }

    func choosePlaylist() {
        if let preset = ProcessInfo.processInfo.environment["DECKIE_DESK_PLAYLIST"] { playlist = URL(fileURLWithPath: preset); return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = Words.t("choosePlaylistMessage")
        if panel.runModal() == .OK { playlist = panel.url }
    }
}

/// "Deckie Desk" --naming-walk <out folder> <music folder>: the naming flow on this Mac's window, with no one at the
/// keyboard (generated songs; a stand-in music CD from DECKIE_DESK_MUSIC_CD; a playlist from DECKIE_DESK_PLAYLIST):
/// a folder read, the list of songs that need a name, one song's names with a guess, Listen, a pasted list and its
/// preview, the names added, a music CD with no names asked for its name while it is read, and a playlist's preview.
/// Writes a picture at each step (Snapshot.capture; whole windows only when the Mac is unlocked), then quits.
@MainActor
enum NamingWalk {
    static var request: (out: String, music: String)? {
        let a = CommandLine.arguments
        guard a.count >= 4, a[1] == "--naming-walk" else { return nil }
        return (a[2], a[3])
    }

    static func run(model: DeskModel, out: String, music: String) {
        Snapshot.prepare(out: out)
        Task { @MainActor in
            func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }
            func say(_ s: String) { print("[naming-walk] " + s) }
            Snapshot.sizeWindow()
            model.newCrate()
            await wait(1)
            let url = URL(fileURLWithPath: music, isDirectory: true)
            model.addSource(url, name: url.lastPathComponent)
            await wait(1.5); Snapshot.capture("m01-run", hold: 1)
            while model.running { await wait(0.25) }
            await wait(1); Snapshot.capture("m02-finished-names", hold: 1)
            model.finished = nil; model.onlyNeedName = true
            await wait(1); Snapshot.capture("m03-needs-a-name", hold: 1)
            if let t = model.crate?.tracks.first(where: { model.reason($0) == "guess" }) {
                model.selection = [t.id]
                await wait(1); Snapshot.capture("m04-names-panel-guess", hold: 1)
                model.listen(t)
                await wait(2); Snapshot.capture("m05-listen", hold: 1)
                say("listening: \(model.listener.song != nil), at \(model.listener.position) of \(model.listener.length) s")
                model.listener.seek(model.listener.length * 0.7)
                await wait(1); Snapshot.capture("m06-listen-scrubbed", hold: 1)
                model.listener.stop()
            }
            let source = model.crate?.discPlan.first?.name
            let order = model.toolSongs(source: source, ids: nil)
            model.toolPrefill = order.enumerated().map { i, s in "Artist \(i + 1) - Tune \(i + 1)" }.joined(separator: "\n")
            model.tool = "paste"
            await wait(1.5); Snapshot.capture("m07-paste-preview", hold: 1, withSheet: true)
            let p = model.preview("paste", source: source, text: order.enumerated().map { i, _ in "Artist \(i + 1) - Tune \(i + 1)" }.joined(separator: "\n"))
            model.tool = nil
            model.apply(p, ticks: Set(p.changes.indices.filter { p.changes[$0].tick }))
            await wait(1); Snapshot.capture("m08-names-added", hold: 1)
            say("after the paste: \(model.needingNames.count) still need a name; undo line: \(model.undoLine ?? "none")")
            model.musicCDs = MusicCDs.list()
            if let cd = model.musicCDs.first(where: { $0.drive == "E" }) ?? model.musicCDs.first {
                model.newCrate()
                await wait(0.5)
                model.addMusicCD(cd)
                await wait(0.3); Snapshot.capture("m09-music-cd-asks-name", hold: 1)
                model.discAnswer = "Friday late"
                say("asked: \(model.discAsk ?? "nothing"), running \(model.running)")
                model.nameDisc()
                while model.running { await wait(0.25) }
                await wait(1); Snapshot.capture("m10-music-cd-finished", hold: 1)
                say("music CD: report \(String(describing: model.finished?.disc)); crate \(model.current?.name ?? "-"); sources \(model.crate?.discPlan.map(\.name) ?? [])")
                model.finished = nil; model.onlyNeedName = true
                model.tool = "playlist"
                await wait(1.5); Snapshot.capture("m11-playlist-preview", hold: 1, withSheet: true)
                model.tool = nil
            } else { say("no music CD listed (set DECKIE_DESK_MUSIC_CD)") }
            await wait(0.5)
            Snapshot.finish()
        }
    }
}
