import SwiftUI
import WebKit

/// The Crate tab: the crate file's songs where they live. First each source (the CD, stick or card they were read
/// from) by its own name, its folders in the order the player shows them and its songs by their number there; then,
/// for songs with no source, their folders. BPM, key, Halloween marks. Tap a song to set it as playing.
/// Landscape: the sections side by side. Portrait: one at a time.
struct CrateTabView: View {
    /// The tab's name. Provisional: the owner has been asked (D26); change it here.
    static let title = "Crate"

    @Environment(Recognizer.self) private var rec
    @Binding var tab: Int
    @State private var shelf: String?
    @AppStorage("cdsDetails") private var details = false

    /// One section of the tab: a source, or the folders of songs with no source.
    struct Shelf: Identifiable {
        let id: String
        let name: String
        let color: Color
        /// Whether the songs carry a player's number (on a source) or not (in a folder).
        let numbered: Bool
        let groups: [DiscFolder]
        /// A folder's heading: "Stick 3 / House /", or for a folder with no source, "House /".
        func heading(_ folder: String) -> String {
            numbered ? (folder.isEmpty ? "\(name) /" : "\(name) / \(folder) /") : (folder.isEmpty ? "/" : "\(folder) /")
        }
    }

    /// The sources by name, then one section for the folders of songs with no source (when there are any).
    static var shelves: [Shelf] {
        let lib = Library.shared
        var out = lib.data.discs.map { Shelf(id: "s:" + $0.disc, name: $0.name, color: $0.color, numbered: true, groups: $0.folders) }
        let folders = lib.folders
        if !folders.isEmpty { out.append(Shelf(id: "folders", name: "Folders", color: Theme.acc, numbered: false, groups: folders)) }
        return out
    }

    var body: some View {
        let all = Self.shelves
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 14) {
                        Text(Self.title).font(.system(size: 26, weight: .heavy)).foregroundStyle(Theme.tx)
                        Text("tap a song to set it as playing").font(.system(size: 13)).foregroundStyle(Theme.dim)
                        Spacer()
                        if !landscape && all.count > 1 {
                            Picker("Show", selection: Binding(get: { shelf ?? all.first?.id }, set: { shelf = $0 })) {
                                ForEach(all) { Text($0.name).tag(Optional($0.id)) }
                            }
                                .pickerStyle(.segmented).frame(maxWidth: 320)
                        }
                        Button { details.toggle() } label: {
                            Text(details ? "Compact" : "Details").font(.system(size: 15)).foregroundStyle(Theme.mut).frame(minHeight: 36)
                        }
                    }
                    let pick = shelf ?? all.first?.id
                    let shown = landscape ? all : all.filter { $0.id == pick }
                    if all.isEmpty {
                        Text("No songs yet.").font(.system(size: 15)).foregroundStyle(Theme.dim).padding(.top, 20)
                    } else if details {
                        HStack(alignment: .top, spacing: 28) { ForEach(shown) { s in shelfList(s, showName: landscape) } }
                    } else {
                        HStack(alignment: .top, spacing: 22) {
                            ForEach(shown) { s in denseShelf(s) }
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 6)
            }
        }
    }

    /// A song's number in its folder: the player's (as read from the source), else its position; none in a folder
    /// with no source.
    private func number(_ s: Shelf, _ id: String, _ i: Int) -> Int? {
        s.numbered ? (Library.shared.track(id)?.num ?? i + 1) : nil
    }

    /// Dense: a whole section in two columns, one line per song ("06 · Title  artist   BPM"), folder headers.
    private func denseShelf(_ s: Shelf) -> some View {
        let col = s.color
        // flatten, then split into two equal columns (a folder may continue at the top of the right column)
        var flat: [Row] = []
        for f in s.groups { for (i, id) in f.ids.enumerated() { flat.append(Row(folder: f.name, index: i, n: number(s, id, i), id: id)) } }
        let half = (flat.count + 1) / 2
        func segments(_ rows: ArraySlice<Row>) -> [Segment] {
            var out: [Segment] = []
            for r in rows { if out.last?.folder == r.folder { out[out.count - 1].rows.append(r) } else { out.append(Segment(folder: r.folder, rows: [r])) } }
            return out
        }
        let left = segments(flat.prefix(half)), right = segments(flat.dropFirst(half))
        return VStack(alignment: .leading, spacing: 4) {
            Text(s.name + "  ·  \(flat.count)").font(.system(size: 15, weight: .bold)).foregroundStyle(col)
            ScrollView {
                HStack(alignment: .top, spacing: 14) {
                    denseColumn(s, left, col)
                    denseColumn(s, right, col)
                }
                .padding(.bottom, 20)
            }
        }
    }

    struct Row { let folder: String; let index: Int; let n: Int?; let id: String }
    struct Segment { let folder: String; var rows: [Row] }

    private func denseColumn(_ s: Shelf, _ segs: [Segment], _ col: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(segs.indices, id: \.self) { si in
                let f = segs[si]
                Text(s.heading(f.folder) + ((f.rows.first?.index ?? 0) > 0 ? "  (cont.)" : "")).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(col.opacity(0.9))
                    .padding(.top, 6).frame(height: 22, alignment: .bottomLeading)
                ForEach(f.rows, id: \.id) { r in
                    if let t = Library.shared.track(r.id) { denseRow(t, r.n) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func denseRow(_ t: Track, _ n: Int?) -> some View {
        let playing = t.id == rec.currentId
        return Button { rec.setManual(t.id); tab = 0 } label: {
            HStack(spacing: 6) {
                Text((n.map { String(format: "%02d · ", $0) } ?? "") + t.song).font(.system(size: 13.5, weight: .medium)).foregroundStyle(playing ? Theme.orange : Theme.tx).lineLimit(1).layoutPriority(1)
                Text(t.artist).font(.system(size: 10)).foregroundStyle(Theme.dim).lineLimit(1)
                Spacer(minLength: 2)
                if t.hal { Text("🎃").font(.system(size: 9)).fixedSize() }
                Text(String(format: "%.0f", t.bpmTag ?? t.bpmShown)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.mut).fixedSize()
            }
            .frame(height: 21)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shelfList(_ s: Shelf, showName: Bool) -> some View {
        let lib = Library.shared
        return VStack(alignment: .leading, spacing: 6) {
            if showName {
                Text(s.name + "  ·  \(s.groups.reduce(0) { $0 + $1.ids.count }) tracks").font(.system(size: 17, weight: .bold)).foregroundStyle(s.color)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(s.groups, id: \.name) { f in
                        Section {
                            ForEach(Array(f.ids.enumerated()), id: \.element) { i, id in
                                if let t = lib.track(id) { row(t, number(s, id, i)) }
                            }
                        } header: {
                            Text(s.heading(f.name))
                                .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(s.color.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12).padding(.bottom, 4).background(Theme.bg)
                        }
                    }
                }
                .padding(.bottom, 30)
            }
        }
    }

    private func row(_ t: Track, _ n: Int?) -> some View {
        let playing = t.id == rec.currentId
        return Button { rec.setManual(t.id); tab = 0 } label: {
            HStack(spacing: 12) {
                Text(n.map { String(format: "%02d", $0) } ?? "").font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.dim).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(t.song).font(.system(size: 18, weight: .semibold)).foregroundStyle(playing ? Theme.orange : Theme.tx).lineLimit(1)
                        Marks(track: t, size: 12)
                    }
                    Text(t.artist + (t.ver.isEmpty ? "" : " · " + t.ver)).font(.system(size: 14)).foregroundStyle(Theme.dim).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(t.key ?? "?").font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.mut).frame(width: 40, alignment: .trailing)
                Text(String(format: "%.0f", t.bpmTag ?? t.bpmShown)).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(Theme.tx).frame(width: 42, alignment: .trailing)
            }
            .padding(.vertical, 7).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(playing ? Theme.orange.opacity(0.12) : Color.white.opacity(0.03)))
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
            v.backgroundColor = UIColor(red: 0.06, green: 0.04, blue: 0.09, alpha: 1)
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
