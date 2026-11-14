import SwiftUI
import WebKit

/// The Crate tab: the crate file's songs where they live. First each source (the CD, stick or card they were read
/// from) by its own name, its folders in the order the player shows them and its songs by their number there; then,
/// for songs with no source, their folders. BPM, key, Halloween marks. Tap a song to set it as playing.
/// Landscape: the sections side by side. Portrait: one at a time.
struct CrateTabView: View {
    /// The tab's name. Provisional: the owner has been asked (D26); change it here.
    static let title = Words.tabCrate

    @Environment(Recognizer.self) private var rec
    @Environment(SuggestState.self) private var sug
    @Binding var tab: Int
    @State private var shelf: String?
    @AppStorage("cdsDetails") private var details = false

    /// One section of the tab: a source, or the folders of songs with no source.
    struct Shelf: Identifiable {
        let id: String
        /// The source's label (nil for the folders of songs with no source).
        var disc: String? = nil
        let name: String
        let color: Color
        /// Whether the songs carry a player's number (on a source) or not (in a folder).
        let numbered: Bool
        let groups: [DiscFolder]
        /// A folder's heading: "Stick 3 / House /", or for a folder with no source, "House /".
        func heading(_ folder: String) -> String {
            numbered ? (folder.isEmpty ? Words.sourceTop(name) : Words.sourceFolder(name, folder)) : (folder.isEmpty ? Words.folderTop : Words.folderOnly(folder))
        }
    }

    /// The sources by name, then one section for the folders of songs with no source (when there are any).
    static var shelves: [Shelf] {
        let lib = Library.shared
        var out = lib.data.discs.map { Shelf(id: "s:" + $0.disc, disc: $0.disc, name: $0.name, color: $0.color, numbered: true, groups: $0.folders) }
        let folders = lib.folders
        if !folders.isEmpty { out.append(Shelf(id: "folders", name: Words.foldersShelf, color: Theme.acc, numbered: false, groups: folders)) }
        return out
    }

    var body: some View {
        let all = Self.shelves
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: Look.Crate.gap) {
                    HStack(alignment: .lastTextBaseline, spacing: Look.Crate.headGap) {
                        Text(Self.title).font(Look.Crate.titleFont).foregroundStyle(Theme.tx)
                        if let name = Library.shared.crate?.name { Text(name).font(Look.Crate.crateNameFont).foregroundStyle(Theme.mut).lineLimit(1) }
                        Text(Words.crateHelp).font(Look.Crate.helpFont).foregroundStyle(Theme.dim)
                        Spacer()
                        if !landscape && all.count > 1 {
                            Picker(Words.show, selection: Binding(get: { shelf ?? all.first?.id }, set: { shelf = $0 })) {
                                ForEach(all) { Text($0.name).tag(Optional($0.id)) }
                            }
                                .pickerStyle(.segmented).frame(maxWidth: Look.Crate.pickerWidth)
                        }
                        Button { details.toggle() } label: {
                            Text(details ? Words.compact : Words.details).font(Look.Crate.buttonFont).foregroundStyle(Theme.mut).frame(minHeight: Look.Crate.buttonMinHeight)
                        }
                        // Either form: a Mac's package or a PC's single file, from Files, iCloud Drive or a drive.
                        Button { sug.chooseCrateFile = true } label: {
                            Label(Words.openCrateFile, systemImage: "folder").font(Look.Crate.buttonFont).foregroundStyle(Theme.mut).frame(minHeight: Look.Crate.buttonMinHeight)
                        }
                    }
                    let pick = shelf ?? all.first?.id
                    let shown = landscape ? all : all.filter { $0.id == pick }
                    if all.isEmpty {
                        Text(Words.noSongsYet).font(Look.Crate.emptyFont).foregroundStyle(Theme.dim).padding(.top, Look.Crate.emptyTop)
                    } else if details {
                        HStack(alignment: .top, spacing: Look.Crate.detailsGap) { ForEach(shown) { s in shelfList(s, showName: landscape) } }
                    } else {
                        HStack(alignment: .top, spacing: Look.Crate.denseGap) {
                            ForEach(shown) { s in denseShelf(s) }
                        }
                    }
                }
                .padding(.horizontal, Look.Crate.sides).padding(.top, Look.Crate.top)
            }
        }
    }

    /// A song's number in its folder: the player's (as read from the source), at the place of it in that folder (a
    /// song can be in several, D27), else its position; none in a folder with no source.
    private func number(_ s: Shelf, _ folder: String, _ id: String, _ i: Int) -> Int? {
        guard s.numbered else { return nil }
        let here = (Library.shared.track(id)?.places ?? []).filter { $0.disc == s.disc && $0.folder == folder }
        // The same file twice in one folder: the k-th listing is the k-th place there.
        let k = Library.shared.data.discs.first { $0.disc == s.disc }?.folders.first { $0.name == folder }?
            .ids.prefix(i).filter { $0 == id }.count ?? 0
        let byNumber = here.sorted { ($0.num ?? 0) < ($1.num ?? 0) }
        return (k < byNumber.count ? byNumber[k].num : byNumber.first?.num) ?? i + 1
    }

    /// The place a song was chosen from in this shelf, so setting it plays it from there.
    private func place(_ s: Shelf, _ folder: String, _ n: Int?) -> TrackPlace {
        TrackPlace(disc: s.disc, folder: folder, num: s.numbered ? n : nil)
    }

    /// Dense: a whole section in two columns, one line per song ("06 · Title  artist   BPM"), folder headers.
    private func denseShelf(_ s: Shelf) -> some View {
        let col = s.color
        // flatten, then split into two equal columns (a folder may continue at the top of the right column)
        var flat: [Row] = []
        for f in s.groups { for (i, id) in f.ids.enumerated() { flat.append(Row(folder: f.name, index: i, n: number(s, f.name, id, i), id: id)) } }
        let half = (flat.count + 1) / 2
        func segments(_ rows: ArraySlice<Row>) -> [Segment] {
            var out: [Segment] = []
            for r in rows { if out.last?.folder == r.folder { out[out.count - 1].rows.append(r) } else { out.append(Segment(folder: r.folder, rows: [r])) } }
            return out
        }
        let left = segments(flat.prefix(half)), right = segments(flat.dropFirst(half))
        return VStack(alignment: .leading, spacing: Look.Crate.denseHeadGap) {
            Text(Words.shelfCount(s.name, flat.count)).font(Look.Crate.denseNameFont).foregroundStyle(col)
            ScrollView {
                HStack(alignment: .top, spacing: Look.Crate.denseColumnsGap) {
                    denseColumn(s, left, col)
                    denseColumn(s, right, col)
                }
                .padding(.bottom, Look.Crate.denseFoot)
            }
        }
    }

    struct Row { let folder: String; let index: Int; let n: Int?; let id: String }
    struct Segment { let folder: String; var rows: [Row] }

    private func denseColumn(_ s: Shelf, _ segs: [Segment], _ col: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(segs.indices, id: \.self) { si in
                let f = segs[si]
                Text(s.heading(f.folder) + ((f.rows.first?.index ?? 0) > 0 ? Words.continued : "")).font(Look.Crate.denseFolderFont).foregroundStyle(col.opacity(Look.Crate.denseFolderOpacity))
                    .padding(.top, Look.Crate.denseFolderTop).frame(height: Look.Crate.denseFolderHeight, alignment: .bottomLeading)
                ForEach(f.rows.indices, id: \.self) { k in
                    let r = f.rows[k]
                    if let t = Library.shared.track(r.id) { denseRow(t, r.n, at: place(s, r.folder, r.n)) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func denseRow(_ t: Track, _ n: Int?, at p: TrackPlace) -> some View {
        let playing = t.id == rec.currentId
        return Button { rec.setManual(t.id, place: p); tab = 0 } label: {
            HStack(spacing: Look.Crate.denseRowGap) {
                Text(n.map { Words.numbered($0, t.songShown) } ?? t.songShown).font(Look.Crate.denseSongFont(t.hasName)).foregroundStyle(playing ? Theme.orange : (t.hasName ? Theme.tx : Theme.mut)).lineLimit(1).layoutPriority(1)
                Text(t.secondLine).font(Look.Crate.denseArtistFont).foregroundStyle(Theme.dim).lineLimit(1)
                Spacer(minLength: Look.Crate.denseSpacer)
                if t.hal { Text(Words.pumpkin).font(Look.Crate.densePumpkinFont).fixedSize() }
                Text(Words.bpmNumber(t.bpmTag ?? t.bpmShown)).font(Look.Crate.denseBpmFont).foregroundStyle(Theme.mut).fixedSize()
            }
            .frame(height: Look.Crate.denseRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shelfList(_ s: Shelf, showName: Bool) -> some View {
        let lib = Library.shared
        return VStack(alignment: .leading, spacing: Look.Crate.listGap) {
            if showName {
                Text(Words.shelfSongs(s.name, s.groups.reduce(0) { $0 + $1.ids.count })).font(Look.Crate.listNameFont).foregroundStyle(s.color)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Look.Crate.listRowsGap, pinnedViews: [.sectionHeaders]) {
                    ForEach(s.groups, id: \.name) { f in
                        Section {
                            ForEach(Array(f.ids.enumerated()), id: \.offset) { i, id in
                                if let t = lib.track(id) { let n = number(s, f.name, id, i); row(t, n, at: place(s, f.name, n)) }
                            }
                        } header: {
                            Text(s.heading(f.name))
                                .font(Look.Crate.listFolderFont).foregroundStyle(s.color.opacity(Look.Crate.listFolderOpacity))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, Look.Crate.listFolderTop).padding(.bottom, Look.Crate.listFolderBottom).background(Theme.bg)
                        }
                    }
                }
                .padding(.bottom, Look.Crate.listFoot)
            }
        }
    }

    private func row(_ t: Track, _ n: Int?, at p: TrackPlace) -> some View {
        let playing = t.id == rec.currentId
        return Button { rec.setManual(t.id, place: p); tab = 0 } label: {
            HStack(spacing: Look.Crate.rowGap) {
                Text(n.map { Words.number($0) } ?? "").font(Look.Crate.rowNumberFont).foregroundStyle(Theme.dim).frame(width: Look.Crate.rowNumberWidth)
                VStack(alignment: .leading, spacing: Look.Crate.rowTextGap) {
                    HStack(spacing: Look.Crate.rowTitleGap) {
                        Text(t.songShown).font(Look.Crate.rowSongFont(t.hasName)).foregroundStyle(playing ? Theme.orange : (t.hasName ? Theme.tx : Theme.mut)).lineLimit(1)
                        Marks(track: t, size: Look.Crate.rowMarks)
                    }
                    Text(t.hasName ? Words.artistVersion(t.artist, t.ver) : t.secondLine).font(Look.Crate.rowArtistFont).foregroundStyle(Theme.dim).lineLimit(1)
                }
                Spacer(minLength: Look.Crate.rowSpacer)
                Text(t.key ?? Words.unknownKey).font(Look.Crate.rowKeyFont).foregroundStyle(Theme.mut).frame(width: Look.Crate.rowKeyWidth, alignment: .trailing)
                Text(Words.bpmNumber(t.bpmTag ?? t.bpmShown)).font(Look.Crate.rowBpmFont).foregroundStyle(Theme.tx).frame(width: Look.Crate.rowBpmWidth, alignment: .trailing)
            }
            .padding(.vertical, Look.Crate.rowTopBottom).padding(.horizontal, Look.Crate.rowSides)
            .background(RoundedRectangle(cornerRadius: Look.Crate.rowRadius).fill(playing ? Theme.orange.opacity(Look.Crate.rowPlayingOpacity) : Look.Crate.rowFill))
        }
        .buttonStyle(.plain)
    }
}

/// The bundled interactive mix map (self-contained HTML, offline).
struct MixMapView: View {
    var body: some View {
        WebView().ignoresSafeArea(edges: .bottom).background(Theme.bg)
    }
    struct WebView: UIViewRepresentable {
        func makeUIView(context: Context) -> WKWebView {
            let cfg = WKWebViewConfiguration()
            cfg.defaultWebpagePreferences.allowsContentJavaScript = true
            let v = WKWebView(frame: .zero, configuration: cfg)
            v.isOpaque = false
            v.backgroundColor = Look.MixMap.background
            if let url = Bundle.main.url(forResource: "mixmap", withExtension: "html") {
                // the page has no charset declaration: load it as UTF-8 explicitly (file:// would guess Latin-1)
                if let d = try? Data(contentsOf: url) {
                    v.load(d, mimeType: "text/html", characterEncodingName: "utf-8", baseURL: url.deletingLastPathComponent())
                }
            }
            return v
        }
        func updateUIView(_ v: WKWebView, context: Context) {}
    }
}
