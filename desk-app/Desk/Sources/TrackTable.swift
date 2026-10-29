import SwiftUI
import DeckieCrate

struct TrackTable: View {
    @EnvironmentObject var model: DeskModel
    @State private var sortOrder = [KeyPathComparator(\CrateTrack.ident.title)]

    var body: some View {
        let tracks = (model.crate?.tracks ?? []).sorted(using: sortOrder)
        Table(tracks, selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.ident.title) { Text($0.ident.title) }
            TableColumn("Artist", value: \.ident.artist, comparator: OptionalStringComparator()) { Text($0.ident.artist ?? "") }
                .width(min: 100, ideal: 160)
            TableColumn("Tempo") { t in Text(t.grid.map { String(format: "%.1f", $0.bpm) } ?? "–") }.width(60)
            TableColumn("Key") { t in
                HStack(spacing: 4) {
                    Text(t.key?.camelot ?? "–")
                    if t.flags.contains("key_uncertain") { Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help("Not sure of the key") }
                }
            }.width(60)
            TableColumn("Bars") { t in Text(t.grid.map { "\($0.nBars)" } ?? "–") }.width(50)
            TableColumn("Length") { t in Text(Self.mmss(t.file.durationS)) }.width(60)
            TableColumn("Vocals") { t in Text(t.vocal.map { String(format: "%.0f%%", $0.mean * 100) } ?? "–") }.width(56)
            TableColumn("Notes") { t in Text(Self.notes(t)).foregroundStyle(.secondary).lineLimit(1) }
        }
    }

    static func mmss(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

    static func notes(_ t: CrateTrack) -> String {
        var n: [String] = []
        if let d = t.file.damagedFrames, !d.isEmpty { n.append("\(d.count) damaged frame\(d.count == 1 ? "" : "s")") }
        if t.flags.contains("low_grid_confidence") { n.append("beat grid unsure") }
        if t.flags.contains("vocal_unknown") { n.append("vocals not read") }
        if !t.signatures.isEmpty { n.append("signed") }
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
                    Text("Names").font(.headline)
                    field("Title", t.ident.title) { v in model.update(id) { $0.ident.title = v } }
                    field("Artist", t.ident.artist ?? "") { v in model.update(id) { $0.ident.artist = v.isEmpty ? nil : v } }
                    field("Version", t.ident.version ?? "") { v in model.update(id) { $0.ident.version = v.isEmpty ? nil : v } }
                    field("Tags", t.ident.tags.joined(separator: ", ")) { v in
                        model.update(id) { $0.ident.tags = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    }
                    Divider()
                    Text("What Deckie found").font(.headline)
                    Grid(alignment: .leading, verticalSpacing: 4) {
                        row("File", t.file.name)
                        if let g = t.grid { row("Tempo", String(format: "%.2f, %d bars, bar 1 at %.2f s", g.bpm, g.nBars, g.firstDownbeatS)) }
                        if let segs = t.tempoSegments, segs.count > 1 { row("Tempo changes", "\(segs.count) segments") }
                        if let k = t.key { row("Key", "\(k.camelot)" + (k.key.map { " (\($0) \(k.scale ?? ""))" } ?? "") + (t.flags.contains("key_uncertain") ? ", not sure" : "")) }
                        if let ch = t.key?.changes, !ch.isEmpty { row("Key changes", ch.map { "\($0.camelot) from bar \($0.startBar)" }.joined(separator: ", ")) }
                        if let l = t.loudness { row("Loudness", String(format: "%.1f LUFS, peak %.1f dB", l.integratedLufs, l.truePeakDb)) }
                        if let mi = t.mixIn, let mo = t.mixOut { row("Mix windows", "in: bars \(mi.startBar) to \(mi.endBar); out: bars \(mo.startBar) to \(mo.endBar)") }
                        if let s = t.sections { row("Sections", s.map { "\($0.label) \($0.startBar)" }.joined(separator: ", ")) }
                        if let v = t.vocal { row("Vocals", String(format: "%.0f%% of bars%@", v.mean * 100, v.heavy ? ", vocal-heavy" : "")) }
                        row("Engine", "\(t.analysis.engine) on \(t.analysis.device)")
                        row("Signatures", t.signatures.isEmpty ? "none yet" : t.signatures.keys.sorted().joined(separator: ", "))
                        if let d = t.file.damagedFrames, !d.isEmpty { row("Damaged frames", d.map { String(format: "%.1f s", $0.startS) }.joined(separator: ", ")) }
                    }.font(.callout)
                }.padding(14)
            } else {
                VStack(spacing: 8) {
                    Text(model.selection.isEmpty ? "Select a track to see and fix its names." : "\(model.selection.count) tracks selected.")
                        .foregroundStyle(.secondary)
                    if let f = model.sourceFolder { Text("Music: \(f.path)").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    Button("Where is this crate's music?") { model.chooseSourceFolder() }.controlSize(.small)
                }.padding(14)
            }
        }
    }

    @ViewBuilder func field(_ label: String, _ value: String, set: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: Binding(get: { value }, set: set)).textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder func row(_ k: String, _ v: String) -> some View {
        GridRow { Text(k).foregroundStyle(.secondary).gridColumnAlignment(.trailing); Text(v).textSelection(.enabled) }
    }
}

extension CrateTrack: @retroactive Identifiable {}
