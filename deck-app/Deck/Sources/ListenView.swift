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
                    HStack(alignment: .top, spacing: Look.Listen.landscapeGap) {
                        PlayingPanel(showDebug: $showDebug, waveHeight: max(Look.Listen.waveMinHeight, geo.size.height * Look.Listen.waveHeightShare))
                            .frame(width: geo.size.width * Look.Listen.panelWidthShare)
                            .frame(maxHeight: .infinity)
                        UpNextPanel(landscape: true)
                            .padding(.top, Look.Listen.picksTop).padding(.leading, Look.Listen.picksLeading)
                    }
                    .padding(.leading, Look.Listen.landscapeLeading).padding(.trailing, Look.Listen.landscapeTrailing).padding(.bottom, Look.Listen.landscapeBottom).padding(.top, Look.Listen.landscapeTop)
                } else {
                    VStack(alignment: .leading, spacing: Look.Listen.portraitGap) {
                        PlayingPanel(showDebug: $showDebug, waveHeight: Look.Listen.portraitWaveHeight).fixedSize(horizontal: false, vertical: true)
                        UpNextPanel(landscape: false)
                    }
                    .padding(.horizontal, Look.Listen.portraitSides).padding(.top, Look.Listen.portraitTop)
                }
            }
        }
        .ignoresSafeArea(.keyboard)      // the search keyboard covers the screen's foot; nothing reflows
        .onChange(of: rec.currentId) { if sug.rolledFor != rec.currentId { sug.reroll(rec) } }   // a hook may have rolled already
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
                VStack(alignment: .leading, spacing: Look.Listen.playingGap) {
                    VStack(alignment: .leading, spacing: Look.Listen.playingTitleGap) {
                        // A song with no name: its place leads, in the title's size (research AA, 3.13), so the
                        // small place line above is not repeated.
                        if t.hasName {
                            Text(t.folderPath).font(Look.Listen.placeFont).foregroundStyle(t.on ? t.discColor : Theme.dim).lineLimit(1)
                        }
                        if let also = Library.shared.alsoOn(t, playingDisc: t.disc) {
                            Text(also).font(Look.Listen.alsoFont).foregroundStyle(Theme.mut).lineLimit(1).minimumScaleFactor(Look.Listen.alsoShrink)
                        }
                        Text(t.playingTitle).font(Look.Listen.titleFont).foregroundStyle(t.hasName ? Theme.tx : (t.on ? t.discColor : Theme.tx)).lineLimit(2).minimumScaleFactor(Look.Listen.titleShrink)
                        if t.hasName {
                            Text(t.artist).font(Look.Listen.artistFont).foregroundStyle(Theme.mut).lineLimit(1).minimumScaleFactor(Look.Listen.artistShrink)
                            // The song's facts (D34) in one short line; none shows nothing, as before.
                            if let line = t.factsLine {
                                Text(line).font(Look.Listen.factsFont).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.tail)
                            }
                        } else {
                            Text(Words.noNameYet).font(Look.Listen.artistFont).foregroundStyle(Theme.mut).lineLimit(1)
                            if !t.secondLine.isEmpty {
                                Text(t.secondLine).font(Look.Listen.factsFont).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                    Text(Words.bpm(t.bpmShown * (rec.source == .manual ? 1 : rec.rate)))
                        .font(Look.Listen.bpmFont).foregroundStyle(Theme.rsn)
                    SongWave(track: t, height: waveHeight)
                }
            } else if !Library.shared.canRecognise {
                // A crate file with no fingerprints: said once, here, until a song is set by hand.
                VStack(alignment: .leading, spacing: Look.Listen.byHandGap) {
                    Text(Words.setByHandTitle).font(Look.Listen.titleFont).foregroundStyle(Theme.tx).minimumScaleFactor(Look.Listen.titleShrink)
                    Text(Words.noFingerprints).font(Look.Listen.byHandBodyFont).foregroundStyle(Theme.mut).fixedSize(horizontal: false, vertical: true)
                    Text(Words.setByHandHow).font(Look.Listen.byHandHowFont).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    Button(Words.chooseSong) { sug.tabRequest = 1 }.buttonStyle(PillStyle(prominent: true)).padding(.top, Look.Listen.byHandButtonTop)
                }
            } else {
                VStack(alignment: .leading, spacing: Look.Listen.listeningGap) {
                    Text(Words.listeningTitle).font(Look.Listen.titleFont).foregroundStyle(Theme.tx)
                    Text(Words.listeningHelp).font(Look.Listen.listeningHelpFont).foregroundStyle(Theme.dim)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Look.Listen.panelSides).padding(.top, Look.Listen.panelTop).padding(.bottom, Look.Listen.panelBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Look.Listen.panelRadius)
                .fill(LinearGradient(colors: [(rec.current?.discColor ?? Theme.acc).opacity(Look.Listen.panelTintTop), (rec.current?.discColor ?? Theme.acc).opacity(Look.Listen.panelTintBottom)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .background(RoundedRectangle(cornerRadius: Look.Listen.panelRadius).fill(Theme.card))
        )
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: Look.Listen.cornerGap) {
                corner
                if let t = rec.current, !sug.minimal { Marks(track: t).padding(.trailing, Look.Listen.marksTrailing) }
            }
            .padding(Look.Listen.cornerPadding)
        }
        .overlay { HalloweenFX(trigger: rec.current?.hal == true ? rec.currentId : nil).allowsHitTesting(false).clipShape(RoundedRectangle(cornerRadius: Look.Listen.panelRadius)) }
        .overlay(alignment: .bottomLeading) {
            if let h = rec.alsoHearing { Text(Words.alsoHearing(h)).font(Look.Listen.alsoHearingFont).foregroundStyle(Theme.dim).lineLimit(1).padding(.leading, Look.Listen.alsoHearingLeading).padding(.bottom, Look.Listen.alsoHearingBottom) }
        }
    }

    private var status: some View {
        HStack(spacing: Look.Listen.statusGap) {
            TimelineView(.periodic(from: .now, by: Look.Listen.statusTick)) { _ in Circle().fill(dotColor).frame(width: Look.Listen.statusDot, height: Look.Listen.statusDot) }
            Text(tinyStatus).font(Look.Listen.statusFont).foregroundStyle(Theme.dim).lineLimit(1)
            if rec.recActive {
                Button { rec.toggleRecPause() } label: {
                    TimelineView(.periodic(from: .now, by: Look.Listen.statusTick)) { _ in
                        HStack(spacing: Look.Listen.recGap) {
                            Circle().fill(rec.recPaused ? Theme.dim : Theme.bad.opacity(Look.Listen.recDotOpacity)).frame(width: Look.Listen.recDot, height: Look.Listen.recDot)
                            Text(rec.recPaused ? Words.recPaused : Words.recElapsed(hms(rec.recorder.elapsed)))
                                .font(Look.Listen.recFont).foregroundStyle(Theme.dim)
                        }
                        .padding(.horizontal, Look.Listen.recSides).frame(minHeight: Look.Listen.recMinHeight)
                    }
                }
                .accessibilityLabel(rec.recPaused ? Words.resumeRecording : Words.pauseRecording)
            }
        }
    }

    /// top-right status corner: listening status, REC with elapsed time, mic, "…" (the top-left stays free for the
    /// app's Minimal switch, so nothing collides in either orientation)
    private var corner: some View {
        HStack(spacing: Look.Listen.cornerButtonsGap) {
            status.padding(.trailing, Look.Listen.statusTrailing)
            // Nothing to listen for in a crate file with no fingerprints, so no mic button.
            if Library.shared.canRecognise {
                Button { rec.source == .mic ? rec.stop() : rec.startMic() } label: {
                    Image(systemName: rec.source == .mic ? "mic" : "mic.slash").font(Look.Listen.cornerIconFont).foregroundStyle(Theme.dim).frame(width: Look.Listen.cornerButton, height: Look.Listen.cornerButton)
                }
                .accessibilityLabel(rec.source == .mic ? Words.pauseListening : Words.listen)
            }
            Button { showDebug = true } label: {
                Image(systemName: "ellipsis").font(Look.Listen.cornerIconFont).foregroundStyle(Theme.dim).frame(width: Look.Listen.cornerButton, height: Look.Listen.cornerButton)
            }
            .accessibilityLabel(Words.testWithFile)
        }
    }

    private var dotColor: Color {
        switch rec.source {
        case .mic, .file: return rec.lastMatch.map { Date().timeIntervalSince($0) < Look.Listen.matchFresh } == true ? Theme.ok : Theme.dim
        default: return Theme.dim.opacity(Look.Listen.idleDotOpacity)
        }
    }

    private var tinyStatus: String {
        var s: String
        switch rec.source {
        case .idle: s = Library.shared.canRecognise ? Words.statusPaused : Words.notListening
        case .mic: s = rec.lastMatch == nil ? Words.statusListening : Words.statusListening
        case .file: s = Words.statusTestFile
        case .manual: s = Words.statusByHand
        }
        if rec.currentId != nil && rec.source != .manual {
            if rec.paused { s += Words.statusAlsoPaused }
            let c = rec.confidence
            s += c > 0.75 ? Words.statusSure : c > 0.45 ? Words.statusLikely : c > 0 ? Words.statusUnsure : ""
            if abs(rec.pitchPct) >= 0.25 { s += Words.statusDeck(signed1(rec.pitchPct)) }
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
            .font(Look.Chips.quietFont)
            .foregroundStyle(accent ? Theme.orange : Theme.mut)
            .padding(.horizontal, Look.Chips.quietSides).frame(height: Look.Chips.quietHeight)
            .background(RoundedRectangle(cornerRadius: Look.Chips.quietRadius).fill(Look.Chips.quietFill))
    }
}

struct ConfidenceDots: View {
    let value: Double
    var manual = false
    var body: some View {
        HStack(spacing: Look.Confidence.gap) {
            ForEach(0..<5) { i in
                Circle().fill(Double(i) < value * 5 - 0.01 ? (value > 0.45 ? Theme.ok : Theme.orange) : Look.Confidence.off).frame(width: Look.Confidence.dot, height: Look.Confidence.dot)
            }
        }
        .accessibilityLabel(manual ? Words.confidenceByHand : Words.confidence(Int(value * 100)))
    }
}

/// The whole song: overview waveform with the playhead, mix-in and sync area (mix-out window) shaded, song time.
struct SongWave: View {
    @Environment(Recognizer.self) private var rec
    let track: Track
    let height: CGFloat
    var showWave = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: Look.Wave.tick)) { ctx in
            let dur = track.duration
            let known = rec.positionKnown
            let pos = min(dur, max(0, rec.position(at: ctx.date)))
            let mo = track.mixOut ?? [dur - 30, dur], mi = track.mixIn ?? [0, 16]
            let vals = Library.shared.overview[track.id]?.display ?? []
            VStack(alignment: .leading, spacing: Look.Wave.gap) {
                if showWave {
                Canvas { g, size in
                    let W = size.width, H = size.height
                    func X(_ t: Double) -> CGFloat { CGFloat(t / dur) * W }
                    g.fill(Path(CGRect(x: X(mi[0]), y: 0, width: X(mi[1]) - X(mi[0]), height: H)), with: .color(Look.Wave.mixInFill))
                    g.fill(Path(CGRect(x: X(mo[0]), y: 0, width: X(mo[1]) - X(mo[0]), height: H)), with: .color(Look.Wave.syncFill))
                    g.fill(Path(CGRect(x: X(mo[0]), y: 0, width: X(mo[1]) - X(mo[0]), height: Look.Wave.syncLine)), with: .color(Look.Wave.syncLineColor))
                    let top: CGFloat = Look.Wave.labelRoom, mid = top + (H - top) / 2
                    if vals.isEmpty {
                        g.fill(Path(CGRect(x: 0, y: mid - Look.Wave.flatLine / 2, width: W, height: Look.Wave.flatLine)), with: .color(Look.Wave.flatColor))
                    } else {
                        let n = vals.count, bw = W / CGFloat(n)
                        var played = Path(), ahead = Path()
                        for i in 0..<n {
                            let h = max(Look.Wave.barMin, CGFloat(vals[i]) * ((H - top) / 2 - Look.Wave.barInset))
                            let r = CGRect(x: CGFloat(i) * bw, y: mid - h, width: max(Look.Wave.barMinWidth, bw * Look.Wave.barShare), height: h * 2)
                            if known && Double(i) / Double(n) * dur < pos { played.addRect(r) } else { ahead.addRect(r) }
                        }
                        g.fill(ahead, with: .color(track.discColor.opacity(Look.Wave.aheadOpacity)))
                        g.fill(played, with: .color(track.discColor.opacity(Look.Wave.playedOpacity)))
                    }
                    if known {
                        var c = g
                        c.addFilter(.shadow(color: Look.Wave.playheadGlow, radius: Look.Wave.playheadGlowRadius))
                        c.fill(Path(CGRect(x: X(pos) - Look.Wave.playheadWidth / 2, y: -Look.Wave.playheadOverhang, width: Look.Wave.playheadWidth, height: H + 2 * Look.Wave.playheadOverhang)), with: .color(Look.Wave.playhead))
                    }
                    g.draw(Text(Words.waveIn).font(Look.Wave.markFont).foregroundColor(Theme.dim), at: CGPoint(x: X(mi[0]) + Look.Wave.markInset, y: Look.Wave.inMarkY), anchor: .leading)
                    g.draw(Text(Words.waveSync).font(Look.Wave.markFont).foregroundColor(Theme.dim), at: CGPoint(x: X(mo[0]) + Look.Wave.markInset, y: Look.Wave.syncMarkY), anchor: .leading)
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
        return VStack(alignment: .leading, spacing: Look.Wave.readoutGap) {
            HStack(alignment: .lastTextBaseline) {
                Text(known ? fmtTime(pos / r) : Words.timeUnknown).font(Look.Wave.timeFont).foregroundStyle(Theme.mut)
                Spacer()
                Text(known ? Words.remaining(fmtTime((dur - pos) / r)) : fmtTime(dur))
                    .font(Look.Wave.timeFont).foregroundStyle(Theme.dim)
            }
            Text(syncNote(pos: pos, known: known, mo: mo, r: r)).font(Look.Wave.syncNoteFont).foregroundStyle(Theme.dim)
        }
    }

    private func syncNote(pos: Double, known: Bool, mo: [Double], r: Double) -> String {
        guard known else { return Words.positionUnknown }
        let bar = 240 / max(40, track.bpmShown)
        if pos < mo[0] { return Words.syncIn(fmtTime((mo[0] - pos) / r)) }
        if pos < mo[1] { let bars = Int(((mo[1] - pos) / bar).rounded(.up)); return Words.syncBarsLeft(bars) }
        return Words.pastSync
    }
}

func hms(_ s: Double) -> String { let t = Int(s); return String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) }

// MARK: - shared bits

struct IconStyle: ButtonStyle {
    var accent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Look.Controls.iconFont)
            .frame(width: Look.Controls.iconSize, height: Look.Controls.iconSize)
            .foregroundStyle(accent ? Look.Controls.accentInk : Theme.mut)
            .background(Circle().fill(accent ? Theme.orange : Look.Controls.fill))
            .opacity(configuration.isPressed ? Look.Controls.pressedOpacity : 1)
    }
}

struct PillStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Look.Controls.pillFont)
            .padding(.horizontal, Look.Controls.pillSides).frame(minHeight: Look.Controls.pillMinHeight)
            .foregroundStyle(prominent ? Look.Controls.accentInk : Theme.mut)
            .background(Capsule().fill(prominent ? AnyShapeStyle(Theme.orange) : AnyShapeStyle(Look.Controls.fill)))
            .opacity(configuration.isPressed ? Look.Controls.pressedOpacity : 1)
    }
}

/// Simple wrapping row
struct FlowRow: Layout {
    var spacing: CGFloat = Look.Controls.flowGap
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
    @State private var ghostX: CGFloat = Look.FX.ghostRest
    @State private var ghostOpacity = 0.0
    @State private var pumpkin = 0.0
    @State private var shown: Set<String> = []

    var body: some View {
        GeometryReader { g in
            ZStack {
                RoundedRectangle(cornerRadius: Look.Listen.panelRadius).fill(Look.FX.flashColor.opacity(flash))
                Text(Words.ghost).font(Look.FX.ghostFont).opacity(ghostOpacity)
                    .position(x: g.size.width * ghostX, y: g.size.height * Look.FX.ghostY + sin(ghostX * Look.FX.ghostWaves) * Look.FX.ghostSway)
                Text(Words.pumpkin).font(Look.FX.pumpkinFont).scaleEffect(Look.FX.pumpkinScaleMin + Look.FX.pumpkinScaleRange * pumpkin).opacity(pumpkin)
                    .position(x: g.size.width * Look.FX.pumpkinX, y: g.size.height * Look.FX.pumpkinY)
            }
        }
        .task(id: trigger) {
            guard let id = trigger, !shown.contains(id) else { return }
            shown.insert(id)
            if reduceMotion {
                withAnimation(.easeInOut(duration: Look.FX.stillFade)) { pumpkin = Look.FX.stillPumpkin }
                try? await Task.sleep(for: .seconds(Look.FX.stillHold))
                withAnimation(.easeInOut(duration: Look.FX.stillFade)) { pumpkin = 0 }
                return
            }
            // lightning: two quick flashes
            withAnimation(.easeOut(duration: Look.FX.flash1In)) { flash = Look.FX.flash1 }
            try? await Task.sleep(for: .milliseconds(Look.FX.flash1HoldMs)); withAnimation(.easeIn(duration: Look.FX.flash1Out)) { flash = 0 }
            try? await Task.sleep(for: .milliseconds(Look.FX.flashGapMs)); withAnimation(.easeOut(duration: Look.FX.flash2In)) { flash = Look.FX.flash2 }
            try? await Task.sleep(for: .milliseconds(Look.FX.flash2HoldMs)); withAnimation(.easeIn(duration: Look.FX.flash2Out)) { flash = 0 }
            // ghost drifts through, pumpkin pops in and out
            ghostX = Look.FX.ghostStart; ghostOpacity = 0
            withAnimation(.easeInOut(duration: Look.FX.ghostDrift)) { ghostX = Look.FX.ghostEnd }
            withAnimation(.easeIn(duration: Look.FX.ghostFadeIn)) { ghostOpacity = Look.FX.ghostOpacity }
            withAnimation(.spring(response: Look.FX.pumpkinSpring, dampingFraction: Look.FX.pumpkinDamping)) { pumpkin = 1 }
            try? await Task.sleep(for: .milliseconds(Look.FX.showMs))
            withAnimation(.easeOut(duration: Look.FX.fadeOut)) { ghostOpacity = 0; pumpkin = 0 }
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
        HStack(alignment: .center, spacing: Look.Plain.gap) {
            VStack(alignment: .leading, spacing: Look.Plain.textGap) {
                // A song with no name: the place leads in the title's line ("Friday night / Peak / 02 · no name yet").
                // Broken by phrase: the place on one line, "no name yet" on the next.
                Text(target.hasName ? target.numberedSong : target.oneLine.replacingOccurrences(of: Words.dotJoin + Words.noNameYetInRow, with: Words.twoLines("", Words.noNameYetInRow))).font(Look.Plain.titleFont(big)).foregroundStyle(Theme.tx).lineLimit(target.hasName ? 1 : 2).minimumScaleFactor(Look.Plain.titleShrink)
                HStack(spacing: Look.Plain.lineGap) {
                    Text(target.secondLine).font(Look.Plain.lineFont(big)).foregroundStyle(Theme.dim).lineLimit(1)
                    if target.hasName {
                        Text(target.folderPath).font(Look.Plain.placeFont(big)).foregroundStyle(target.on ? target.discColor : Theme.dim).lineLimit(1)
                    }
                }
                if let also = Library.shared.alsoOn(target, playingDisc: cur.disc) {
                    Text(also).font(Look.Plain.alsoFont(big)).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(Look.Plain.alsoShrink)
                }
            }
            Spacer(minLength: Look.Plain.middleMin)
            VStack(alignment: .trailing, spacing: Look.Plain.textGap) {
                Text(pickBPMLine(target, pair, ji)).font(Look.Plain.bpmFont(big)).foregroundStyle(Theme.amber.opacity(Look.Plain.bpmOpacity)).lineLimit(1)
                Text(pickMoveLine(pair, ji)).font(Look.Plain.moveFont(big)).foregroundStyle(Theme.mut).lineLimit(1)
            }
            .fixedSize()
        }
        .padding(.horizontal, Look.Plain.sides).padding(.vertical, big ? Look.Plain.topBottomBig : Look.Plain.topBottom)
        .background(Capsule().fill(Look.Plain.fill))
        .overlay(Capsule().stroke(kind == .pinned ? Theme.orange.opacity(Look.Plain.pinnedOpacity) : .clear, lineWidth: Look.Plain.pinnedLine))
        .contentShape(Capsule())
        .onTapGesture { sug.pin(target.id, rec) }
    }
}
