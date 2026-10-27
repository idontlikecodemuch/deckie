import SwiftUI

/// The picks for the song now playing: "Easy" (best matches) and "Harder" (unexpected), randomised per song.
/// Swipe sideways for another set, scroll down (Full) for the rest. A new song brings new picks.
struct UpNextPanel: View {
    @Environment(Recognizer.self) private var rec
    @Environment(SuggestState.self) private var sug
    private let zoom = 8          // bars across the join view: 2 before the join, 6 after
    let landscape: Bool

    var body: some View {
        @Bindable var sug = sug
        let m = RowMetrics(simple: sug.mode == .simple, minimal: sug.minimal)
        VStack(alignment: .leading, spacing: 8) {
            PickControls()
            if let cur = rec.current {
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let pid = sug.pinned, let t = Library.shared.track(pid) {
                            groupLabel("Next")
                            if sug.minimal { PlainPick(cur: cur, target: t, pair: Suggester().pair(from: cur.id, to: pid), kind: .pinned, tags: [], big: m.simple).padding(.top, 6) }
                            else { NextRow(cur: cur, target: t, pair: Suggester().pair(from: cur.id, to: pid), kind: .pinned, tags: [], zoom: zoom, m: m) }
                            Color.clear.frame(height: m.groupGap)
                        }
                        if sug.sets.isEmpty {
                            Text(sug.target.label.isEmpty ? "Switch on CD1, CD2 or All above." : "No good matches in \(sug.target.label).")
                                .font(.system(size: 20)).foregroundStyle(Theme.dim).padding(.vertical, 40)
                        } else {
                            setView(cur, sug.sets[0], m)
                        }
                        if !sug.rest.isEmpty {
                            groupLabel("More").padding(.top, m.groupGap).padding(.bottom, m.cardGap).id("more")
                            VStack(alignment: .leading, spacing: m.cardGap) {
                                ForEach(sug.rest) { o in row(cur, o, m) }
                            }
                        }
                    }
                    .padding(.bottom, 30)
                }
                .onChange(of: sug.scrollRequest) { _, r in if let r { withAnimation { proxy.scrollTo(r, anchor: .top) } } }
                }
            } else {
                Spacer()
            }
        }
    }

    private func setView(_ cur: Track, _ set: [Option], _ m: RowMetrics) -> some View {
        let easy = set.filter { $0.kind == .best }, hard = set.filter { $0.kind == .hard }
        return VStack(alignment: .leading, spacing: m.cardGap) {
            groupLabel("Easy")
            ForEach(easy) { o in row(cur, o, m) }
            if !hard.isEmpty {
                groupLabel("Harder").padding(.top, m.groupGap)
                ForEach(hard) { o in row(cur, o, m) }
            }
        }
    }

    @ViewBuilder private func row(_ cur: Track, _ o: Option, _ m: RowMetrics) -> some View {
        if let t = Library.shared.track(o.id) {
            if sug.minimal { PlainPick(cur: cur, target: t, pair: o.pair, kind: o.kind, tags: o.tags, big: m.simple).padding(.top, sug.minimal ? 14 : 0) }
            else { NextRow(cur: cur, target: t, pair: o.pair, kind: o.kind, tags: o.tags, zoom: zoom, m: m) }
        }
    }

    private func groupLabel(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 13, weight: .bold)).kerning(1.2).foregroundStyle(Theme.dim)
            .frame(height: sug.mode == .simple ? 22 : 17, alignment: .bottomLeading)
    }

}

/// "128 BPM · pitch +3.2%" ("128→140 BPM" when the song changes tempo; no pitch when it can't be beat-matched)
func pickBPMLine(_ t: Track, _ pair: Pair?, _ ji: JoinInfo) -> String {
    var bpm = String(format: "%.0f BPM", t.bpmShown)
    if let bi = t.bpmIn, abs(bi / max(1, t.bpmShown) - 1) > 0.02 { bpm = String(format: "%.0f→%.0f BPM", bi, t.bpmShown) }
    guard pair?.tr != "brake_cut", ji.beatMatch, let p = ji.pitch else { return bpm }
    return bpm + " · pitch " + signed1(p) + "%" + (pair.map { $0.m != "1" ? " (x\($0.m))" : "" } ?? "")
}
/// the move: "blend", "echo out · key clash", "no beat-match · brake"
func pickMoveLine(_ pair: Pair?, _ ji: JoinInfo) -> String {
    var parts: [String] = []
    if pair?.tr == "brake_cut" || !ji.beatMatch { parts.append("no beat-match") }
    if let p = pair {
        // the moves as a small menu: primary / alternative
        let mv = (p.mv?.isEmpty == false ? p.mv! : [p.trl]).map { $0 == "brake/cut" ? "brake" : $0 }
        parts.append(mv.prefix(2).joined(separator: " / "))
    }
    if ji.verdict == "clash" { parts.append("key clash") }
    return parts.joined(separator: " · ")
}

struct PickControls: View {
    @Environment(Recognizer.self) private var rec
    @Environment(SuggestState.self) private var sug

    /// Simple / Full on the left; library chips (CD1, CD2, All, each on/off) on the right.
    var body: some View {
        @Bindable var sug = sug
        return HStack(spacing: 14) {
            toggle(["Simple", "Full"], sug.mode == .simple ? 0 : 1) { i in sug.mode = i == 0 ? .simple : .full; sug.reroll(rec) }
            Spacer()
            libChip("CD1", on: sug.target.cd1, color: Theme.sing) { sug.target.cd1.toggle(); sug.reroll(rec) }
            libChip("CD2", on: sug.target.cd2, color: Theme.mix) { sug.target.cd2.toggle(); sug.reroll(rec) }
            libChip("All", on: sug.target.other, color: Theme.acc) { sug.target.other.toggle(); sug.reroll(rec) }
        }
    }

    private func libChip(_ t: String, on: Bool, color: Color, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(t).font(.system(size: 14, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.tx : Theme.dim)
                .padding(.horizontal, 11).frame(height: 30)
                .background(Capsule().fill(on ? color.opacity(0.28) : Color.clear))
                .overlay(Capsule().stroke(on ? Color.clear : Theme.dim.opacity(0.4), lineWidth: 1))
        }
        .frame(minHeight: 40)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggle(_ labels: [String], _ sel: Int, _ act: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(labels.indices, id: \.self) { i in
                Button { act(i) } label: {
                    Text(labels[i]).font(.system(size: 15, weight: i == sel ? .semibold : .regular))
                        .foregroundStyle(i == sel ? Theme.tx : Theme.dim)
                        .padding(.horizontal, 7).frame(minHeight: 36)
                }
                .accessibilityAddTraits(i == sel ? .isSelected : [])
                if i < labels.count - 1 { Text("/").font(.system(size: 15)).foregroundStyle(Theme.dim.opacity(0.5)) }
            }
        }
    }
}

struct RowMetrics {
    let simple: Bool
    var minimal = false
    var titleSize: CGFloat { simple ? 25 : 19 }
    var lineSize: CGFloat { simple ? 16 : 12.5 }      // folder path, artist
    var bpmSize: CGFloat { simple ? 18 : 15 }
    var smallSize: CGFloat { simple ? 16 : 13 }
    var textWidth: CGFloat { simple ? 275 : 235 }
    var waveHeight: CGFloat { simple ? 96 : 68 }
    var cardHeight: CGFloat { simple ? 152 : 106 }
    var padH: CGFloat { simple ? 20 : 16 }
    var padV: CGFloat { simple ? 14 : 7 }
    var cardGap: CGFloat { simple ? 10 : 6 }
    var groupGap: CGFloat { minimal ? 40 : simple ? 30 : 12 }
    var labelHeight: CGFloat { simple ? 22 : 17 }
    func setHeight(_ set: [Option]) -> CGFloat {
        let rows = CGFloat(set.count), groups: CGFloat = set.contains { $0.kind == .hard } ? 2 : 1
        return rows * (cardHeight + cardGap) + groups * (labelHeight + cardGap) + (groups - 1) * groupGap
    }
}

/// One pick in a soft card: folder path, "06 · Title", artist, BPM · pitch, one small info line; the join wave right after.
struct NextRow: View {
    @Environment(Recognizer.self) private var rec
    @Environment(SuggestState.self) private var sug
    let cur: Track
    let target: Track
    let pair: Pair?
    let kind: Option.Kind
    let tags: [String]
    let zoom: Int
    let m: RowMetrics
    @State private var showDetail = false

    var body: some View {
        let ji = joinInfo(cur, target, pair, deckAPitch: rec.source == .manual ? 0 : rec.pitchPct)
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: m.simple ? 3 : 1) {
                Text(target.folderPath).font(.system(size: m.lineSize, weight: .semibold, design: .rounded)).foregroundStyle(target.on ? target.discColor : Theme.mut).lineLimit(1)
                Text(target.numberedSong).font(.system(size: m.titleSize, weight: .semibold)).foregroundStyle(Theme.tx).lineLimit(1).minimumScaleFactor(0.75)
                Text(target.artist).font(.system(size: m.lineSize)).foregroundStyle(Theme.dim).lineLimit(1)
                Text(bpmLine(ji)).font(.system(size: m.bpmSize, weight: .regular, design: .rounded)).foregroundStyle(Theme.amber.opacity(0.85)).lineLimit(1).padding(.top, m.simple ? 3 : 1)
                Text(smallLine(ji)).font(.system(size: m.smallSize + 1)).foregroundStyle(Theme.mut).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: m.textWidth, alignment: .leading)
            if let wa = cur.wOut, let wb = target.wHead ?? target.wIn {
                let pts = StartPoint.candidates(for: target)
                let sp = pts[(sug.startIdx[target.id] ?? 0) % max(1, pts.count)]
                VStack(alignment: .leading, spacing: 2) {
                    JoinView(a: cur, b: target, wa: wa, wb: wb, startB: sp.t, info: ji, zoom: zoom, height: m.waveHeight, marks: pts.map(\.t))
                        .contentShape(Rectangle())
                        .onTapGesture { sug.startIdx[target.id] = ((sug.startIdx[target.id] ?? 0) + 1) % max(1, pts.count) }
                        .accessibilityHint("Tap to try another start point of the next song")
                    GeometryReader { g in
                        let fs: CGFloat = m.simple ? 13 : 11
                        let tw = fs * 0.62 * CGFloat(fmtTime(sp.t).count)        // monospaced width of "0:34"
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(fmtTime(sp.t)).font(.system(size: fs, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.mut)
                            if pts.count > 1 { Text("\(pts.count) syncs").font(.system(size: m.simple ? 10 : 9)).foregroundStyle(Theme.dim) }
                        }
                        .lineLimit(1).fixedSize()
                        .offset(x: max(0, g.size.width * 0.25 - tw / 2))
                    }
                    .frame(height: m.simple ? 16 : 14)
                }
                .frame(maxWidth: .infinity)
            } else { Spacer() }
        }
        .padding(.horizontal, m.padH).padding(.top, m.padV).padding(.bottom, max(2, m.padV * 0.35))
        .frame(height: m.cardHeight)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.045)))
        .overlay(alignment: .topTrailing) { cornerChips.padding(.top, 7).padding(.trailing, 10) }
        .overlay(alignment: .leading) { if kind == .pinned { Capsule().fill(Theme.orange).frame(width: 4).padding(.vertical, 16) } }
        .contentShape(Rectangle())
        .onTapGesture { sug.pin(target.id, rec) }
        .onLongPressGesture { showDetail = true }
        .popover(isPresented: $showDetail) { detail(ji).presentationCompactAdaptation(.popover) }
        .accessibilityElement(children: .combine)
        .accessibilityHint(kind == .pinned ? "Tap to unpin" : "Tap to pin as next, long-press for why")
    }

    private func bpmLine(_ ji: JoinInfo) -> String { pickBPMLine(target, pair, ji) }
    private func smallLine(_ ji: JoinInfo) -> String { pickMoveLine(pair, ji) }

    /// tiny chips in the card's upper-right corner: harder-pick reason, Halloween, remix
    private var cornerChips: some View {
        HStack(spacing: 4) {
            if kind == .hard, let t = tags.first { TinyChip(text: t) }
            if target.hal { TinyChip(text: "🎃") }
            if target.isRemix { TinyChip(text: "RMX") }
        }
    }

    private func detail(_ ji: JoinInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(target.artist) – \(target.song)").font(.system(size: 18, weight: .bold))
            if !target.ver.isEmpty { Text(target.ver).foregroundStyle(.secondary) }
            Text("Key \(target.key ?? "?") · \(ji.keyText) \(ji.verdict)").font(.system(size: 15))
            Text("Pitch: set the incoming deck's pitch fader to \(ji.pitch.map { signed1($0) + "%" } ?? "n/a") so the tempos match.").font(.system(size: 15))
            if let p = pair {
                Text(String(format: "Match score %.2f · %.1f%% stretch", p.s, p.st)).font(.system(size: 14)).foregroundStyle(.secondary)
                Text("Moves: " + (p.mv ?? [p.trl]).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "   ")).font(.system(size: 15))
                ForEach(p.reasons, id: \.self) { Text("• " + $0).font(.system(size: 15)) }
            }
        }
        .padding(20).frame(width: 420, alignment: .leading)
    }
}

func verdictPhrase(_ v: String) -> String {
    switch v {
    case "same key": return "same key"
    case "neighbour": return "neighbour key"
    case "relative": return "relative key"
    case "boost": return "key boost"
    case "clash": return "keys clash"
    case "key unsure": return "key unsure"
    default: return v
    }
}

/// Where the next song could come in: its mix-in window (default), the track start, the first steady-beat bar,
/// and the following 8-bar phrase boundaries (within the 64-bar head snippet).
struct StartPoint: Hashable {
    let t: Double
    let label: String
    static func candidates(for b: Track) -> [StartPoint] {
        let bar = 240 / b.gridBPM
        let mi = b.mixIn?[0] ?? (b.firstBeat ?? 0)
        var pts = [StartPoint(t: mi, label: "mix-in start")]
        func add(_ t: Double, _ l: String) { if t >= 0, !pts.contains(where: { abs($0.t - t) < 0.5 }) { pts.append(StartPoint(t: t, label: l)) } }
        guard let h = b.wHead else { return pts }
        let headEnd = h.t0 + Double(h.n) * 60 / b.gridBPM / Double(b.samplesPerBeat) - 2 * bar
        add(0, "track start")
        if let s = b.steadyIn, s < headEnd { add(s, "steady beat") }
        let fb = b.firstBeat ?? mi
        let miBar = Int(((mi - fb) / bar).rounded())
        for k in 1...7 {
            let t = mi + Double(8 * k) * bar
            if t < headEnd { add(t, "bar \(miBar + 8 * k + 1)") }
        }
        return pts
    }
}

/// Small quiet chip (corner marks: 🎃, RMX, harder-pick reason).
struct TinyChip: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Theme.dim)
            .padding(.horizontal, 5).frame(height: 17)
            .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}

/// Halloween and remix/edit marks as tiny chips.
struct Marks: View {
    let track: Track
    var size: CGFloat = 11
    var body: some View {
        HStack(spacing: 4) {
            if track.hal { TinyChip(text: "🎃") }
            if track.isRemix { TinyChip(text: "RMX") }
        }
        .accessibilityLabel((track.hal ? "Halloween " : "") + (track.isRemix ? "remix" : ""))
    }
}

/// Port of the web player's drawJoin, in the song wave's filled style: end of the current song (top lane) over
/// the next one (bottom lane) from the chosen start point, aligned so A's mix-out start and the start point sit
/// on the join line. 8 bars across (2 before the join); 1 pt per sample (8 per beat); beat lines, bar ticks,
/// 8-bar lines with the tracks' bar numbers, window ends, overlap shading and the join line.
struct JoinView: View {
    let a: Track, b: Track, wa: Wave, wb: Wave
    let startB: Double
    let info: JoinInfo
    let zoom: Int
    let height: CGFloat
    var marks: [Double] = []        // candidate start points of B (seconds), numbered on lane B

    var body: some View {
        let va = wa.values, vb = wb.values
        let spbA = a.samplesPerBeat, spbB = b.samplesPerBeat
        Canvas { g, size in
            let W = size.width, H = size.height
            let num: CGFloat = 10
            let laneA = (num, H / 2 - 1), laneB = (H / 2 + 1, H - num)
            let barA = Double(4 * spbA)                            // lane-A samples per bar
            let P = W / (Double(zoom) * barA)
            let uMin = -2 * barA                                   // 2 bars before the join
            func X(_ u: Double) -> CGFloat { CGFloat((u - uMin) * P) }
            // lane B scale in lane-A samples per B sample: the tempo relation, and the snippets' samples per beat
            let sB = info.scaleB * Double(spbA) / Double(spbB)
            let jA = Double(wa.win[0])
            let jB = (startB - wb.t0) / (60 / b.gridBPM / Double(spbB))  // B sample index at the join
            let aLen = Double(wa.win[1]) - jA
            let bLen = (Double(wb.win[1]) - jB) * sB
            let uEnd = bLen > 0 ? min(aLen, bLen) : aLen
            let ov = CGRect(x: X(0), y: laneA.0, width: max(0, min(W, X(uEnd)) - X(0)), height: laneB.1 - laneA.0)
            g.fill(Path(ov), with: .color(.white.opacity(0.07)))
            g.fill(Path(CGRect(x: ov.minX, y: ov.minY, width: ov.width, height: 1)), with: .color(Theme.amber.opacity(0.7)))
            g.fill(Path(CGRect(x: ov.minX, y: ov.maxY - 1, width: ov.width, height: 1)), with: .color(Theme.amber.opacity(0.7)))
            func lane(_ w: Wave, _ vals: [Int], j: Double, scl: Double, spb: Int, _ ly: (CGFloat, CGFloat), _ col: Color, fallbackK0: Int, numberY: CGFloat, brightFromJoin: Bool = false, numbers: Bool = true) {
                let mid = (ly.0 + ly.1) / 2, half = (ly.1 - ly.0) / 2 - 1
                let step = P * scl
                let k0 = w.k0 ?? fallbackK0
                var on = Path(), off = Path()
                for i in 0..<min(w.n, vals.count) {
                    let x = X((Double(i) - j) * scl)
                    if x < -step || x > W { continue }
                    let hh = max(0.5, CGFloat(vals[i]) / 63 * half)
                    let r = CGRect(x: x, y: mid - hh, width: step + 0.3, height: hh * 2)
                    let bright = brightFromJoin ? Double(i) >= j.rounded() : (i >= w.win[0] && i < w.win[1])
                    if bright { on.addRect(r) } else { off.addRect(r) }
                }
                g.fill(off, with: .color(col.opacity(0.3)))
                g.fill(on, with: .color(col.opacity(0.78)))
                let perBar = 4 * spb, perPhrase = 32 * spb
                for i in 0...w.n {
                    let k = k0 + i
                    guard ((k % spb) + spb) % spb == 0 else { continue }
                    let x = X((Double(i) - j) * scl)
                    if x < 0 || x > W { continue }
                    let isBar = ((k % perBar) + perBar) % perBar == 0
                    if !isBar {
                        // beat line: a thin dark cut through the filled shape
                        g.fill(Path(CGRect(x: x - 0.5, y: ly.0 + 1, width: 1, height: ly.1 - ly.0 - 2)), with: .color(Theme.bg.opacity(0.75)))
                        continue
                    }
                    let phrase = ((k % perPhrase) + perPhrase) % perPhrase == 0
                    g.fill(Path(CGRect(x: x - 0.5, y: ly.0, width: phrase ? 1.3 : 0.8, height: ly.1 - ly.0)), with: .color(.white.opacity(phrase ? 0.6 : 0.3)))
                    if numbers && phrase && k >= 0 {
                        g.draw(Text("\(k / perBar + 1)").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(Theme.mut),
                               at: CGPoint(x: x + 2, y: numberY), anchor: .leading)
                    }
                }
                let xe = X((Double(w.win[1]) - j) * scl)
                if xe > 0 && xe < W { g.fill(Path(CGRect(x: xe - 1, y: ly.0, width: 2, height: ly.1 - ly.0)), with: .color(col)) }
            }
            let fbA = (JoinView.bar(at: a.mixOut?[0] ?? 0, of: a) - 1) * 4 * spbA - wa.win[0]
            let fbB = -wb.win[0]                                    // mix-in window starts on bar 1
            lane(wa, va, j: jA, scl: 1, spb: spbA, laneA, a.discColor, fallbackK0: fbA, numberY: num / 2)
            lane(wb, vb, j: jB, scl: sB, spb: spbB, laneB, info.beatMatch ? b.discColor : Theme.dim, fallbackK0: fbB, numberY: H - num / 2, brightFromJoin: true, numbers: marks.isEmpty)
            // the other places B could start (tap the wave to move there), numbered in order
            let PB = 60 / b.gridBPM / Double(spbB)
            for (n, t) in marks.enumerated() {
                let x = X(((t - wb.t0) / PB - jB) * sB)
                if x < 4 || x > W - 8 { continue }
                if n == 0 {
                    // the recommended first sync point (B's mix-in start): a small labelled marker under the lane
                    var tri = Path(); tri.move(to: CGPoint(x: x, y: laneB.1 + 1)); tri.addLine(to: CGPoint(x: x - 3.5, y: laneB.1 + 6)); tri.addLine(to: CGPoint(x: x + 3.5, y: laneB.1 + 6)); tri.closeSubpath()
                    g.fill(tri, with: .color(Theme.amber.opacity(0.9)))
                    g.draw(Text("sync").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundColor(Theme.amber.opacity(0.9)),
                           at: CGPoint(x: x + 5, y: H - num / 2 + 1), anchor: .leading)
                    continue
                }
                if abs(t - startB) <= 0.3 { continue }
                g.fill(Path(CGRect(x: x - 0.5, y: laneB.1 - 5, width: 1, height: 5)), with: .color(Theme.mut))
                g.draw(Text("\(n + 1)").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundColor(Theme.mut),
                       at: CGPoint(x: x, y: H - num / 2), anchor: .center)
            }
            var c = g
            c.addFilter(.shadow(color: .white.opacity(0.8), radius: 3))
            c.fill(Path(CGRect(x: X(0) - 1, y: laneA.0 - 2, width: 2, height: laneB.1 - laneA.0 + 4)), with: .color(.white))
        }
        .frame(height: height)
        .accessibilityLabel("Join: end of \(a.song) over \(b.song) from \(fmtTime(startB))")
    }

    static func bar(at t: Double, of tr: Track) -> Int {
        guard let fb = tr.firstBeat else { return 1 }
        return Int(((t - fb) / (240 / tr.gridBPM)).rounded()) + 1
    }
}
