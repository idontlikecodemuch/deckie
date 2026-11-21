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
        #if DEBUG
        .sheet(isPresented: $showDebug) { DebugSheet() }   // the test and details sheet: Debug builds only
        #endif
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
                    // The song's cover (D36), small, beside its names; a song without one shows nothing extra.
                    HStack(alignment: .top, spacing: Look.Listen.coverGap) {
                    if let c = t.cover {
                        CoverThumb(hash: c, size: Look.Listen.coverSize, radius: Look.Listen.coverRadius, opacity: Look.Listen.coverOpacity)
                    }
                    VStack(alignment: .leading, spacing: Look.Listen.playingTitleGap) {
                        // A song with no name: its place leads, in the title's size (research AA, 3.13), so the
                        // small place line above is not repeated.
                        // A song at the top of a crate with no sources (the demo crate) has no place line.
                        if t.hasName && !t.folderPath.isEmpty {
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
                    }
                    // Not heard just now (Deckie's, D35): the song stays, its names dimmed.
                    // Stopped (the corner's Stop): the song stays with its picks, dimmed as when not heard.
                    // Interrupted or unable to listen: dimmed the same way.
                    .opacity(rec.notHeard || rec.source == .idle || rec.listenTrouble != nil ? Look.Listen.notHeardOpacity : 1)
                    .animation(.easeInOut(duration: Look.Listen.notHeardFade), value: rec.notHeard || rec.source == .idle || rec.listenTrouble != nil)
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
            } else if case .preparing(let n) = rec.deckie.state, rec.hearing != .apple {
                // Deckie's index is being made from the crate file's fingerprints (once for each crate file).
                VStack(alignment: .leading, spacing: Look.Listen.listeningGap) {
                    Text(Words.preparingTitle).font(Look.Listen.titleFont).foregroundStyle(Theme.tx)
                    Text(Words.preparingBody(n)).font(Look.Listen.listeningHelpFont).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
            } else if control == .start {
                // Stopped by the DJ (Stop in the corner), with no song on screen: said plainly, with where the set is
                // and the way back. The one button for it is the corner's Start listening.
                VStack(alignment: .leading, spacing: Look.Listen.listeningGap) {
                    Text(Words.stoppedTitle).font(Look.Listen.titleFont).foregroundStyle(Theme.tx)
                    Text(Words.stoppedHelp).font(Look.Listen.listeningHelpFont).foregroundStyle(Theme.mut)
                    if rec.savedSet != nil {
                        let empty = rec.lastRecording?.nothingRecorded == true
                        Text(empty ? Words.stoppedNothingRecorded : rec.lastRecording.map { Words.stoppedSavedLength(hms($0.seconds)) } ?? Words.stoppedSaved)
                            .font(Look.Listen.listeningHelpFont).foregroundStyle(empty ? Theme.orange : Theme.dim).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(Words.stoppedHow).font(Look.Listen.listeningHelpFont).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    if DemoCrate.isOpen {
                        Button(Words.leaveTheDemo) { sug.leaveDemo = true }.buttonStyle(PillStyle()).padding(.top, Look.Listen.byHandButtonTop)
                    }
                }
            } else if let t = rec.listenTrouble {
                // Listening interrupted (a call, Siri, an alarm), starting again, or unable to, with no song on screen:
                // said here instead of "Listening…", while it lasts; it goes back by itself.
                VStack(alignment: .leading, spacing: Look.Listen.listeningGap) {
                    Text(Words.listenTroubleTitle(t)).font(Look.Listen.titleFont).foregroundStyle(Theme.tx)
                    Text(Words.listenTroubleFoot(t, recording: rec.recActive)).font(Look.Listen.listeningHelpFont).foregroundStyle(Theme.orange).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: Look.Listen.listeningGap) {
                    Text(Words.listeningTitle).font(Look.Listen.titleFont).foregroundStyle(Theme.tx)
                    Text(Words.listeningHelp).font(Look.Listen.listeningHelpFont).foregroundStyle(Theme.dim)
                    if rec.isListening, rec.recordingOn, rec.recTrouble != nil || rec.recFailed != nil {
                        Text(Words.recCannotFoot).font(Look.Listen.listeningHelpFont).foregroundStyle(Theme.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    // The demo (DemoCrate): where its songs play from, and the way back to the first-run screen.
                    if DemoCrate.isOpen {
                        Text(Words.demoHow).font(Look.Listen.demoHowFont).foregroundStyle(Theme.mut)
                            .lineSpacing(Look.Listen.demoHowLineSpacing).fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Look.Listen.demoHowTop)
                        Button(Words.leaveTheDemo) { sug.leaveDemo = true }.buttonStyle(PillStyle()).padding(.top, Look.Listen.byHandButtonTop)
                    }
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
                // Clean or dirty, where the crate file says (D39). Choosing between a clean and a dirty copy is for a
                // later design pass; the owner's first thought: show both, and a tap on one shows where it is.
                if let t = rec.current, let l = t.lyrics.flatMap(Words.lyricsMark) { TinyChip(text: l).padding(.trailing, Look.Listen.marksTrailing) }
            }
            .padding(Look.Listen.cornerPadding)
        }
        .overlay { HalloweenFX(trigger: rec.current?.hal == true ? rec.currentId : nil).allowsHitTesting(false).clipShape(RoundedRectangle(cornerRadius: Look.Listen.panelRadius)) }
        .overlay(alignment: .bottomLeading) {
            // Stopped with the song still on screen: where the set that Stop saved is, and how long it is (or that
            // nothing was recorded in it).
            if rec.current != nil, rec.source == .idle, rec.savedSet != nil {
                Text(Words.setSavedFootLength(rec.lastRecording.map { hms($0.seconds) }, empty: rec.lastRecording?.nothingRecorded == true))
                    .font(Look.Listen.alsoHearingFont).foregroundStyle(rec.lastRecording?.nothingRecorded == true ? Theme.orange : Theme.mut).lineLimit(1).padding(.leading, Look.Listen.alsoHearingLeading).padding(.bottom, Look.Listen.alsoHearingBottom)
            } else if rec.current != nil, let t = troubleFoot {
                // Listening interrupted, starting again or unable to; the recording unable to write. While it lasts.
                Text(t).font(Look.Listen.alsoHearingFont).foregroundStyle(Theme.orange).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Look.Listen.alsoHearingLeading).padding(.bottom, Look.Listen.alsoHearingBottom)
            } else if let h = rec.alsoHearing { Text(Words.alsoHearing(h)).font(Look.Listen.alsoHearingFont).foregroundStyle(Theme.dim).lineLimit(1).padding(.leading, Look.Listen.alsoHearingLeading).padding(.bottom, Look.Listen.alsoHearingBottom) }
        }
    }

    private var status: some View {
        HStack(spacing: Look.Listen.statusGap) {
            TimelineView(.periodic(from: .now, by: Look.Listen.statusTick)) { _ in Circle().fill(dotColor).frame(width: Look.Listen.statusDot, height: Look.Listen.statusDot) }
            Text(tinyStatus).font(Look.Listen.statusFont).foregroundStyle(Theme.dim).lineLimit(1)
            // Set recording (every build): the chip says what it is doing; a tap opens a small menu to pause it, or to
            // turn recording off and on (remembered between launches). Nothing to record without fingerprints.
            if Library.shared.canRecognise {
                Menu {
                    if rec.recActive {
                        Button(rec.recPaused ? Words.resumeRecording : Words.pauseRecording) { rec.toggleRecPause() }
                    }
                    Section(Words.recWhere) {
                        Toggle(Words.recordSets, isOn: Binding(get: { rec.recordingOn }, set: { rec.setRecording($0) }))
                    }
                } label: {
                    TimelineView(.periodic(from: .now, by: Look.Listen.statusTick)) { _ in
                        HStack(spacing: Look.Listen.recGap) {
                            if rec.recordingOn {
                                Circle().fill(recState.live ? Theme.bad.opacity(Look.Listen.recDotOpacity) : Theme.dim)
                                    .frame(width: Look.Listen.recDot, height: Look.Listen.recDot)
                            } else {
                                Circle().stroke(Theme.dim, lineWidth: Look.Listen.recOffLine).frame(width: Look.Listen.recDot, height: Look.Listen.recDot)
                            }
                            Text(recChip).font(Look.Listen.recFont).foregroundStyle(Theme.dim)
                        }
                        .padding(.horizontal, Look.Listen.recSides).frame(minHeight: Look.Listen.recMinHeight)
                    }
                }
                .accessibilityLabel(Words.setRecording)
                .accessibilityValue(recChip)
            }
        }
    }

    /// The REC chip's state (`RecChip`): "REC 0:12:34" while recording, "REC paused", "REC waiting" through a gap in
    /// the sound, "cannot record", "not recording" (on, but listening is stopped), "REC off".
    private var recState: RecChip {
        RecChip.now(recordingOn: rec.recordingOn, active: rec.recActive, paused: rec.recPaused, failed: rec.recFailed != nil,
                    trouble: rec.recTrouble != nil, hearing: rec.listenTrouble == nil, seconds: rec.recActive ? rec.recorder.elapsed : 0)
    }
    private var recChip: String { recState.words }

    /// The playing panel's foot when something is wrong with listening or the recording: listening first (it is what
    /// the DJ is relying on), then the recording.
    private var troubleFoot: String? {
        if let t = rec.listenTrouble { return Words.listenTroubleFoot(t, recording: rec.recActive) }
        if rec.recordingOn, rec.recTrouble != nil || (rec.recFailed != nil && rec.isListening) { return Words.recCannotFoot }
        return nil
    }

    /// What the corner's one listening control shows now.
    private var control: ListenControl {
        ListenControl.now(listening: rec.isListening, canRecognise: Library.shared.canRecognise,
                          preparing: rec.source == .idle && { if case .preparing = rec.deckie.state, rec.hearing != .apple { return true }; return false }())
    }

    /// top-right status corner: listening status, REC with elapsed time, Stop or Start listening, "…" (the top-left
    /// stays free for the app's Minimal switch, so nothing collides in either orientation)
    private var corner: some View {
        HStack(spacing: Look.Listen.cornerButtonsGap) {
            status.padding(.trailing, Look.Listen.statusTrailing)
            // The one control for listening (it took the place of the microphone button): Stop turns the microphone
            // off and ends and saves the set's recording; Start listening turns it on again. The REC chip's menu only
            // pauses the recording or turns set recording off; listening goes on. Nothing to listen for in a crate
            // file with no fingerprints, so no control there.
            switch control {
            case .stop:
                Button { rec.stopListening() } label: {
                    Label(Words.stop, systemImage: "stop.fill").labelStyle(ListenControlLabel())
                }
                .buttonStyle(PillStyle()).accessibilityLabel(Words.stopSpoken)
            case .start:
                Button { rec.startMic() } label: {
                    Label(Words.startListening, systemImage: "mic.fill").labelStyle(ListenControlLabel())
                }
                .buttonStyle(PillStyle(prominent: true))
            case .hidden: EmptyView()
            }
            #if DEBUG
            // The test and details sheet: Debug builds only (a tester's build has no test doors).
            Button { showDebug = true } label: {
                Image(systemName: "ellipsis").font(Look.Listen.cornerIconFont).foregroundStyle(Theme.dim).frame(width: Look.Listen.cornerButton, height: Look.Listen.cornerButton)
            }
            .accessibilityLabel(Words.testWithFile)
            #endif
        }
    }

    private var dotColor: Color {
        switch rec.source {
        case .mic, .file:
            if rec.listenTrouble != nil { return Theme.orange }     // interrupted, starting again, or unable to listen
            if rec.notHeard { return Theme.dim }       // Deckie's (D35): the playing song not heard just now
            return rec.lastMatch.map { Date().timeIntervalSince($0) < Look.Listen.matchFresh } == true ? Theme.ok : Theme.dim
        default: return Theme.dim.opacity(Look.Listen.idleDotOpacity)
        }
    }

    private var tinyStatus: String {
        var s: String
        switch rec.source {
        case .idle:
            if case .preparing = rec.deckie.state, rec.hearing != .apple { s = Words.preparingStatus }
            else { s = Library.shared.canRecognise ? Words.statusStopped : Words.notListening }
        case .mic:
            if let t = rec.listenTrouble { return Words.listenTroubleStatus(t) }   // no "sure" while nothing is heard
            s = Words.statusListening
        case .file: s = Words.statusTestFile
        case .manual: s = Words.statusByHand
        }
        if rec.currentId != nil && rec.isListening {   // stopped or set by hand: no "sure", no "paused"
            if rec.paused { s += Words.statusAlsoPaused }
            // Deckie's (D35): a song not heard for a few seconds is not called sure; in a quiet room "paused" says it.
            else if rec.notHeard { s += Words.statusNotHeard }
            if !rec.notHeard {
                let c = rec.confidence
                s += c > 0.75 ? Words.statusSure : c > 0.45 ? Words.statusLikely : c > 0 ? Words.statusUnsure : ""
            }
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

/// The Listen page's one control for listening, in the playing panel's corner: Stop while listening (the microphone
/// or a test file), Start listening while not (stopped, or a song set by hand), nothing while Deckie's index is made
/// or for a crate file with no fingerprints (nothing to listen for).
/// What the REC chip says, always the truth about the recording now: recording (with its length), paused by the DJ,
/// waiting through a gap in the sound (it carries on in the same file), cannot record (it would not begin, or the file
/// will not take the sound), not recording (listening is stopped, or not started: the next Start listening records),
/// or set recording off.
enum RecChip: Equatable {
    case off, notRecording, cannotRecord, waiting, paused, recording(seconds: Double)

    static func now(recordingOn: Bool, active: Bool, paused: Bool, failed: Bool, trouble: Bool, hearing: Bool, seconds: Double) -> RecChip {
        guard recordingOn else { return .off }
        guard active else { return failed ? .cannotRecord : .notRecording }
        if trouble { return .cannotRecord }
        if paused { return .paused }
        if !hearing { return .waiting }
        return .recording(seconds: seconds)
    }

    var words: String {
        switch self {
        case .off: return Words.recOff
        case .notRecording: return Words.recNotRecording
        case .cannotRecord: return Words.recCannot
        case .waiting: return Words.recWaiting
        case .paused: return Words.recPaused
        case .recording(let s): return Words.recElapsed(hms(s))
        }
    }
    /// The dot beside the words: filled red only while sound goes into the file.
    var live: Bool { if case .recording = self { return true }; return false }
}

enum ListenControl: Equatable {
    case stop, start, hidden
    static func now(listening: Bool, canRecognise: Bool, preparing: Bool) -> ListenControl {
        guard canRecognise, !preparing else { return .hidden }
        return listening ? .stop : .start
    }
}

/// The control's icon and word side by side, the icon a little smaller.
struct ListenControlLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Look.Listen.controlGap) {
            configuration.icon.font(Look.Listen.controlIconFont)
            configuration.title
        }
    }
}

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
                    if target.hasName && !target.folderPath.isEmpty {
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
