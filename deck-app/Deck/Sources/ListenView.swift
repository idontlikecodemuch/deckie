import SwiftUI

/// Landscape first: the playing song in its own panel on the left, the picks on the right. Portrait: stacked.
struct ListenView: View {
    @Environment(Recognizer.self) private var rec
    @Environment(SuggestState.self) private var sug
    @State private var showDebug = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Theme.bg.ignoresSafeArea()
                if landscape {
                    HStack(alignment: .top, spacing: 52) {
                        PlayingPanel(showDebug: $showDebug, waveHeight: max(140, geo.size.height * 0.22))
                            .frame(width: geo.size.width * 0.42)
                            .frame(maxHeight: .infinity)
                        UpNextPanel(landscape: true)
                            .padding(.top, 6).padding(.leading, 18)
                    }
                    .padding(.leading, 20).padding(.trailing, 36).padding(.bottom, 16).padding(.top, 4)
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        PlayingPanel(showDebug: $showDebug, waveHeight: 110).fixedSize(horizontal: false, vertical: true)
                        UpNextPanel(landscape: false)
                    }
                    .padding(.horizontal, 24).padding(.top, 4)
                }
            }
        }
        .onChange(of: rec.currentId) { sug.reroll(rec) }
        .onAppear { if sug.rolledFor != rec.currentId { sug.reroll(rec) } }
        .sheet(isPresented: $showDebug) { DebugSheet() }
    }
}

// MARK: - playing side

/// The song now playing: title, artist, disc location, BPM, whole-song waveform with IN / SYNC and the song time.
/// Status, listen and test controls are tiny, in the corners.
struct PlayingPanel: View {
    @Environment(Recognizer.self) private var rec
    @Environment(SuggestState.self) private var sug
    @Binding var showDebug: Bool
    let waveHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            if let t = rec.current {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.folderPath).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(t.on ? t.discColor : Theme.dim).lineLimit(1)
                        Text(t.numberedSong).font(.system(size: 44, weight: .heavy)).foregroundStyle(Theme.tx).lineLimit(2).minimumScaleFactor(0.6)
                        Text(t.artist).font(.system(size: 24, weight: .medium)).foregroundStyle(Theme.mut).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Text(String(format: "%.0f BPM", t.bpmShown * (rec.source == .manual ? 1 : rec.rate)))
                        .font(.system(size: 22, weight: .regular, design: .rounded)).foregroundStyle(Theme.rsn)
                    SongWave(track: t, height: waveHeight)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Listening…").font(.system(size: 44, weight: .heavy)).foregroundStyle(Theme.tx)
                    Text("A song shows up after 5–10 seconds of music.").font(.system(size: 18)).foregroundStyle(Theme.dim)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30).padding(.top, 44).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [(rec.current?.discColor ?? Theme.acc).opacity(0.24), (rec.current?.discColor ?? Theme.acc).opacity(0.08)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .background(RoundedRectangle(cornerRadius: 24).fill(Theme.card))
        )
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 6) {
                corner
                if let t = rec.current, !sug.minimal { Marks(track: t).padding(.trailing, 8) }
            }
            .padding(10)
        }
        .overlay { HalloweenFX(trigger: rec.current?.hal == true ? rec.currentId : nil).allowsHitTesting(false).clipShape(RoundedRectangle(cornerRadius: 24)) }
        .overlay(alignment: .bottomLeading) {
            if let h = rec.alsoHearing { Text("also hearing: " + h).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1).padding(.leading, 30).padding(.bottom, 12) }
        }
    }

    private var status: some View {
        HStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in Circle().fill(dotColor).frame(width: 7, height: 7) }
            Text(tinyStatus).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.dim).lineLimit(1)
            if rec.recActive {
                Button { rec.toggleRecPause() } label: {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        HStack(spacing: 4) {
                            Circle().fill(rec.recPaused ? Theme.dim : Theme.bad.opacity(0.75)).frame(width: 6, height: 6)
                            Text(rec.recPaused ? "REC paused" : "REC " + hms(rec.recorder.elapsed))
                                .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.dim)
                        }
                        .padding(.horizontal, 6).frame(minHeight: 28)
                    }
                }
                .accessibilityLabel(rec.recPaused ? "Resume recording" : "Pause recording")
            }
        }
    }

    /// top-right status corner: listening status, REC with elapsed time, mic, "…" (the top-left stays free for the
    /// app's Minimal switch, so nothing collides in either orientation)
    private var corner: some View {
        HStack(spacing: 2) {
            status.padding(.trailing, 6)
            Button { rec.source == .mic ? rec.stop() : rec.startMic() } label: {
                Image(systemName: rec.source == .mic ? "mic" : "mic.slash").font(.system(size: 14)).foregroundStyle(Theme.dim).frame(width: 34, height: 34)
            }
            .accessibilityLabel(rec.source == .mic ? "Pause listening" : "Listen")
            Button { showDebug = true } label: {
                Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(Theme.dim).frame(width: 34, height: 34)
            }
            .accessibilityLabel("Test with file and details")
        }
    }

    private var dotColor: Color {
        switch rec.source {
        case .mic, .file: return rec.lastMatch.map { Date().timeIntervalSince($0) < 20 } == true ? Theme.ok : Theme.dim
        default: return Theme.dim.opacity(0.5)
        }
    }

    private var tinyStatus: String {
        var s: String
        switch rec.source {
        case .idle: s = "paused"
        case .mic: s = rec.lastMatch == nil ? "listening" : "listening"
        case .file: s = "test file"
        case .manual: s = "set by hand"
        }
        if rec.currentId != nil && rec.source != .manual {
            if rec.paused { s += " · paused" }
            let c = rec.confidence
            s += c > 0.75 ? " · sure" : c > 0.45 ? " · likely" : c > 0 ? " · unsure" : ""
            if abs(rec.pitchPct) >= 0.25 { s += " · deck " + signed1(rec.pitchPct) + "%" }
        }
        return s
    }
}

/// Small quiet chip; accent = the one orange highlight.
struct QChip: View {
    let text: String
    var accent = false
    init(_ text: String, accent: Bool = false) { self.text = text; self.accent = accent }
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundStyle(accent ? Theme.orange : Theme.mut)
            .padding(.horizontal, 7).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
    }
}

struct ConfidenceDots: View {
    let value: Double
    var manual = false
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { i in
                Circle().fill(Double(i) < value * 5 - 0.01 ? (value > 0.45 ? Theme.ok : Theme.orange) : Color.white.opacity(0.14)).frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel(manual ? "set by hand" : "confidence \(Int(value * 100)) percent")
    }
}

/// The whole song: overview waveform with the playhead, mix-in and sync area (mix-out window) shaded, song time.
struct SongWave: View {
    @Environment(Recognizer.self) private var rec
    let track: Track
    let height: CGFloat
    var showWave = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let dur = track.duration
            let known = rec.positionKnown
            let pos = min(dur, max(0, rec.position(at: ctx.date)))
            let mo = track.mixOut ?? [dur - 30, dur], mi = track.mixIn ?? [0, 16]
            let vals = Library.shared.overview[track.id]?.display ?? []
            VStack(alignment: .leading, spacing: 10) {
                if showWave {
                Canvas { g, size in
                    let W = size.width, H = size.height
                    func X(_ t: Double) -> CGFloat { CGFloat(t / dur) * W }
                    g.fill(Path(CGRect(x: X(mi[0]), y: 0, width: X(mi[1]) - X(mi[0]), height: H)), with: .color(.white.opacity(0.06)))
                    g.fill(Path(CGRect(x: X(mo[0]), y: 0, width: X(mo[1]) - X(mo[0]), height: H)), with: .color(Color(hex: 0xc9b99a, alpha: 0.10)))
                    g.fill(Path(CGRect(x: X(mo[0]), y: 0, width: X(mo[1]) - X(mo[0]), height: 2)), with: .color(Color(hex: 0xc9b99a, alpha: 0.45)))
                    let top: CGFloat = 18, mid = top + (H - top) / 2
                    if vals.isEmpty {
                        g.fill(Path(CGRect(x: 0, y: mid - 1, width: W, height: 2)), with: .color(.white.opacity(0.3)))
                    } else {
                        let n = vals.count, bw = W / CGFloat(n)
                        var played = Path(), ahead = Path()
                        for i in 0..<n {
                            let h = max(1, CGFloat(vals[i]) * ((H - top) / 2 - 2))
                            let r = CGRect(x: CGFloat(i) * bw, y: mid - h, width: max(1, bw * 0.7), height: h * 2)
                            if known && Double(i) / Double(n) * dur < pos { played.addRect(r) } else { ahead.addRect(r) }
                        }
                        g.fill(ahead, with: .color(track.discColor.opacity(0.35)))
                        g.fill(played, with: .color(track.discColor.opacity(0.85)))
                    }
                    if known {
                        var c = g
                        c.addFilter(.shadow(color: .white, radius: 4))
                        c.fill(Path(CGRect(x: X(pos) - 1.5, y: -2, width: 3, height: H + 4)), with: .color(.white))
                    }
                    g.draw(Text("IN").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.dim), at: CGPoint(x: X(mi[0]) + 4, y: 9), anchor: .leading)
                    g.draw(Text("SYNC").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.dim), at: CGPoint(x: X(mo[0]) + 4, y: 10), anchor: .leading)
                }
                .frame(height: height)
                }
                timeReadout(pos: pos, known: known, mo: mo, dur: dur)
            }
        }
    }

    /// Main readout = the song itself (elapsed, remaining to the end, at the playing tempo);
    /// the sync area (the analysed mix-out window) is only a small neutral note.
    private func timeReadout(pos: Double, known: Bool, mo: [Double], dur: Double) -> some View {
        let r = max(0.5, rec.rate)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline) {
                Text(known ? fmtTime(pos / r) : "–:––").font(.system(size: 22, weight: .regular, design: .monospaced)).foregroundStyle(Theme.mut)
                Spacer()
                Text(known ? "−" + fmtTime((dur - pos) / r) : fmtTime(dur))
                    .font(.system(size: 22, weight: .regular, design: .monospaced)).foregroundStyle(Theme.dim)
            }
            Text(syncNote(pos: pos, known: known, mo: mo, r: r)).font(.system(size: 15)).foregroundStyle(Theme.dim)
        }
    }

    private func syncNote(pos: Double, known: Bool, mo: [Double], r: Double) -> String {
        guard known else { return "position unknown" }
        let bar = 240 / max(40, track.bpmShown)
        if pos < mo[0] { return "sync area in " + fmtTime((mo[0] - pos) / r) }
        if pos < mo[1] { let bars = Int(((mo[1] - pos) / bar).rounded(.up)); return "sync area · \(bars) bar\(bars == 1 ? "" : "s") left" }
        return "past the sync area"
    }
}

func hms(_ s: Double) -> String { let t = Int(s); return String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) }

// MARK: - shared bits

struct IconStyle: ButtonStyle {
    var accent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 44, height: 44)
            .foregroundStyle(accent ? Color(hex: 0x1a0d02) : Theme.mut)
            .background(Circle().fill(accent ? Theme.orange : Color.white.opacity(0.07)))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct PillStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .padding(.horizontal, 14).frame(minHeight: 40)
            .foregroundStyle(prominent ? Color(hex: 0x1a0d02) : Theme.mut)
            .background(Capsule().fill(prominent ? AnyShapeStyle(Theme.orange) : AnyShapeStyle(Color.white.opacity(0.07))))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Simple wrapping row
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let W = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > W { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(W, maxX), height: y + rowH)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > b.minX && x + sz.width > b.maxX { x = b.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

/// A short Halloween moment when a Halloween song is recognised: a lightning flash, a ghost drifting across and a
/// pumpkin popping in (about two seconds, once per song, silent). With Reduce Motion: only a soft pumpkin fade.
struct HalloweenFX: View {
    let trigger: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash = 0.0
    @State private var ghostX: CGFloat = -0.2
    @State private var ghostOpacity = 0.0
    @State private var pumpkin = 0.0
    @State private var shown: Set<String> = []

    var body: some View {
        GeometryReader { g in
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(flash))
                Text("👻").font(.system(size: 64)).opacity(ghostOpacity)
                    .position(x: g.size.width * ghostX, y: g.size.height * 0.30 + sin(ghostX * 9) * 14)
                Text("🎃").font(.system(size: 80)).scaleEffect(0.4 + 0.6 * pumpkin).opacity(pumpkin)
                    .position(x: g.size.width * 0.78, y: g.size.height * 0.62)
            }
        }
        .task(id: trigger) {
            guard let id = trigger, !shown.contains(id) else { return }
            shown.insert(id)
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.6)) { pumpkin = 0.8 }
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.easeInOut(duration: 0.6)) { pumpkin = 0 }
                return
            }
            // lightning: two quick flashes
            withAnimation(.easeOut(duration: 0.06)) { flash = 0.35 }
            try? await Task.sleep(for: .milliseconds(90)); withAnimation(.easeIn(duration: 0.12)) { flash = 0 }
            try? await Task.sleep(for: .milliseconds(140)); withAnimation(.easeOut(duration: 0.05)) { flash = 0.22 }
            try? await Task.sleep(for: .milliseconds(70)); withAnimation(.easeIn(duration: 0.3)) { flash = 0 }
            // ghost drifts through, pumpkin pops in and out
            ghostX = -0.15; ghostOpacity = 0
            withAnimation(.easeInOut(duration: 1.6)) { ghostX = 1.15 }
            withAnimation(.easeIn(duration: 0.3)) { ghostOpacity = 0.85 }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { pumpkin = 1 }
            try? await Task.sleep(for: .milliseconds(1200))
            withAnimation(.easeOut(duration: 0.4)) { ghostOpacity = 0; pumpkin = 0 }
        }
    }
}

/// Minimal mode's pick: a compact rounded pill with "06 · Title", artist, folder path, "128 BPM · pitch +3.2%" and the move.
struct PlainPick: View {
    @Environment(Recognizer.self) private var rec
    @Environment(SuggestState.self) private var sug
    let cur: Track, target: Track, pair: Pair?
    let kind: Option.Kind
    let tags: [String]
    var big = false

    var body: some View {
        let ji = joinInfo(cur, target, pair, deckAPitch: rec.source == .manual ? 0 : rec.pitchPct)
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(target.numberedSong).font(.system(size: big ? 22 : 19, weight: .semibold)).foregroundStyle(Theme.tx).lineLimit(1).minimumScaleFactor(0.75)
                HStack(spacing: 14) {
                    Text(target.artist).font(.system(size: big ? 14 : 13)).foregroundStyle(Theme.dim).lineLimit(1)
                    Text(target.folderPath).font(.system(size: big ? 14 : 13, weight: .semibold, design: .rounded)).foregroundStyle(target.on ? target.discColor : Theme.dim).lineLimit(1)
                }
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 5) {
                Text(pickBPMLine(target, pair, ji)).font(.system(size: big ? 17 : 15, weight: .regular, design: .rounded)).foregroundStyle(Theme.amber.opacity(0.85)).lineLimit(1)
                Text(pickMoveLine(pair, ji)).font(.system(size: big ? 14 : 13)).foregroundStyle(Theme.mut).lineLimit(1)
            }
            .fixedSize()
        }
        .padding(.horizontal, 28).padding(.vertical, big ? 20 : 16)
        .background(Capsule().fill(Color.white.opacity(0.04)))
        .overlay(Capsule().stroke(kind == .pinned ? Theme.orange.opacity(0.8) : .clear, lineWidth: 1.5))
        .contentShape(Capsule())
        .onTapGesture { sug.pin(target.id, rec) }
    }
}
