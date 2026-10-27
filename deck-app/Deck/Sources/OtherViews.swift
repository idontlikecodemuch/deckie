import SwiftUI
import WebKit

/// Both discs as burned: folders, numbered tracks, BPM, key, Halloween marks. Tap a song to set it as playing.
/// Landscape: the two discs side by side. Portrait: one disc at a time.
struct CDsView: View {
    @Environment(Recognizer.self) private var rec
    @Binding var tab: Int
    @State private var disc = "S"
    @AppStorage("cdsDetails") private var details = false

    var body: some View {
        let lib = Library.shared
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 14) {
                        Text("CDs").font(.system(size: 26, weight: .heavy)).foregroundStyle(Theme.tx)
                        Text("tap a song to set it as playing").font(.system(size: 13)).foregroundStyle(Theme.dim)
                        Spacer()
                        if !landscape {
                            Picker("Disc", selection: $disc) { ForEach(lib.data.discs, id: \.disc) { Text($0.name).tag($0.disc) } }
                                .pickerStyle(.segmented).frame(maxWidth: 320)
                        }
                        Button { details.toggle() } label: {
                            Text(details ? "Compact" : "Details").font(.system(size: 15)).foregroundStyle(Theme.mut).frame(minHeight: 36)
                        }
                    }
                    let shown = landscape ? lib.data.discs : lib.data.discs.filter { $0.disc == disc }
                    if details {
                        HStack(alignment: .top, spacing: 28) { ForEach(shown, id: \.disc) { d in discList(d, showName: landscape) } }
                    } else {
                        HStack(alignment: .top, spacing: 22) {
                            ForEach(shown, id: \.disc) { d in denseDisc(d) }
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 6)
            }
        }
    }

    /// Dense: a whole disc in two columns, one line per song ("06 · Title  artist   BPM"), folder headers.
    private func denseDisc(_ d: Disc) -> some View {
        let col = d.disc == "S" ? Theme.sing : Theme.mix
        // flatten, then split into two equal columns (a folder may continue at the top of the right column)
        var flat: [(String, Int, String)] = []          // (folder, track number, id)
        for f in d.folders { for (i, id) in f.ids.enumerated() { flat.append((f.name, i + 1, id)) } }
        let half = (flat.count + 1) / 2
        func segments(_ rows: ArraySlice<(String, Int, String)>) -> [Segment] {
            var out: [Segment] = []
            for r in rows { if out.last?.folder == r.0 { out[out.count - 1].rows.append((r.1, r.2)) } else { out.append(Segment(folder: r.0, rows: [(r.1, r.2)])) } }
            return out
        }
        let left = segments(flat.prefix(half)), right = segments(flat.dropFirst(half))
        return VStack(alignment: .leading, spacing: 4) {
            Text(d.name + "  ·  \(d.folders.reduce(0) { $0 + $1.ids.count })").font(.system(size: 15, weight: .bold)).foregroundStyle(col)
            ScrollView {
                HStack(alignment: .top, spacing: 14) {
                    denseColumn(d, left, col)
                    denseColumn(d, right, col)
                }
                .padding(.bottom, 20)
            }
        }
    }

    struct Segment { let folder: String; var rows: [(Int, String)] }

    private func denseColumn(_ d: Disc, _ segs: [Segment], _ col: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(segs.indices, id: \.self) { si in
                let f = segs[si]
                Text("CD\(d.cd) / \(f.folder) /" + (f.rows.first?.0 ?? 1 > 1 ? "  (cont.)" : "")).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(col.opacity(0.9))
                    .padding(.top, 6).frame(height: 22, alignment: .bottomLeading)
                ForEach(f.rows, id: \.1) { r in
                    if let t = Library.shared.track(r.1) { denseRow(t, r.0) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func denseRow(_ t: Track, _ n: Int) -> some View {
        let playing = t.id == rec.currentId
        return Button { rec.setManual(t.id); tab = 0 } label: {
            HStack(spacing: 6) {
                Text(String(format: "%02d · ", n) + t.song).font(.system(size: 13.5, weight: .medium)).foregroundStyle(playing ? Theme.orange : Theme.tx).lineLimit(1).layoutPriority(1)
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

    private func discList(_ d: Disc, showName: Bool) -> some View {
        let lib = Library.shared
        return VStack(alignment: .leading, spacing: 6) {
            if showName {
                Text(d.name + "  ·  \(d.folders.reduce(0) { $0 + $1.ids.count }) tracks").font(.system(size: 17, weight: .bold)).foregroundStyle(d.disc == "S" ? Theme.sing : Theme.mix)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(d.folders, id: \.name) { f in
                        Section {
                            ForEach(Array(f.ids.enumerated()), id: \.element) { i, id in
                                if let t = lib.track(id) { row(t, i + 1) }
                            }
                        } header: {
                            Text("CD\(d.cd) / " + f.name + " /")
                                .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle((d.disc == "S" ? Theme.sing : Theme.mix).opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12).padding(.bottom, 4).background(Theme.bg)
                        }
                    }
                }
                .padding(.bottom, 30)
            }
        }
    }

    private func row(_ t: Track, _ n: Int) -> some View {
        let playing = t.id == rec.currentId
        return Button { rec.setManual(t.id); tab = 0 } label: {
            HStack(spacing: 12) {
                Text(String(format: "%02d", n)).font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.dim).frame(width: 26)
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
