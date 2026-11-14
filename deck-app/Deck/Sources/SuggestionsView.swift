import SwiftUI
import UIKit

/// The picks for the song now playing: one ranked list, the song's shortlist (the best tenth of the library) in the
/// order the Shuffle dial gives; Full shows 10, Simple 5. More holds the rest of the shortlist, then (after a quiet
/// marker) every other candidate in score order, with a search over title and artist. A new song, a move of the dial
/// or a pin brings a new roll.
struct UpNextPanel: View {
    @Environment(Recognizer.self) private var rec
    @Environment(SuggestState.self) private var sug
    private let zoom = 8          // bars across the join view: 2 before the join, 6 after
    let landscape: Bool
    @FocusState private var searchFocused: Bool
    @State private var keyboardHeight: CGFloat = 0

    var body: some View {
        @Bindable var sug = sug
        let m = RowMetrics(simple: sug.mode == .simple, minimal: sug.minimal)
        VStack(alignment: .leading, spacing: Look.Picks.panelGap) {
            PickControls()
            if let cur = rec.current {
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let picks = sug.options.filter { $0.kind == .pick }
                        if let pinned = sug.options.first(where: { $0.kind == .pinned }), let t = Library.shared.placed(pinned.id, playingDisc: cur.disc, among: sug.target.allows) {
                            groupLabel(Words.groupNext)
                            if sug.minimal { PlainPick(cur: cur, target: t, pair: pinned.pair, kind: .pinned, tags: [], big: m.simple).padding(.top, Look.Picks.plainPinnedTop) }
                            else { NextRow(cur: cur, target: t, pair: pinned.pair, kind: .pinned, tags: [], zoom: zoom, m: m) }
                            Color.clear.frame(height: m.groupGap)
                        }
                        if picks.isEmpty {
                            Text(sug.target.label.isEmpty ? Words.switchOn((Library.shared.data.discs.map(\.short) + [Words.all]).joinedWithOr) : Words.noGoodMatches(sug.target.label))
                                .font(Look.Picks.emptyFont).foregroundStyle(Theme.dim).padding(.vertical, Look.Picks.emptyPadding)
                        } else {
                            VStack(alignment: .leading, spacing: m.cardGap) {
                                groupLabel(Words.groupPicks)
                                ForEach(picks) { o in row(cur, o, m) }
                            }
                        }
                        if !sug.rest.isEmpty {
                            groupLabel(Words.groupMore).padding(.top, m.groupGap).padding(.bottom, m.cardGap).id("more")
                            MoreSearchField(text: $sug.moreQuery, focused: $searchFocused)
                                .padding(.bottom, m.cardGap + Look.Picks.searchBelowExtra)
                            // the rest of the crate: a few thousand rows in a big library, built as they scroll in
                            let q = sug.moreQuery.trimmingCharacters(in: .whitespaces)
                            LazyVStack(alignment: .leading, spacing: m.cardGap) {
                                if q.isEmpty {
                                    let cut = min(sug.restShortlist, sug.rest.count)
                                    ForEach(sug.rest[..<cut]) { o in row(cur, o, m) }
                                    if cut < sug.rest.count {
                                        ShortlistEndMarker().padding(.vertical, m.simple ? Look.Picks.markerPaddingSimple : Look.Picks.markerPadding).id("crate-rest")
                                        ForEach(sug.rest[cut...]) { o in row(cur, o, m) }
                                    }
                                } else {
                                    let hits = sug.rest.filter { o in
                                        guard let t = Library.shared.track(o.id) else { return false }
                                        return t.matches(q)
                                    }
                                    if hits.isEmpty {
                                        Text(Words.nothingMatches(q)).font(Look.Picks.nothingFont).foregroundStyle(Theme.dim).padding(.vertical, Look.Picks.nothingPadding)
                                    }
                                    ForEach(hits) { o in row(cur, o, m) }
                                }
                                Color.clear.frame(height: Look.Picks.endAnchor).id("more-end")   // test hook: scroll?to=more-end
                            }
                        }
                    }
                    .padding(.bottom, Look.Picks.listFoot + keyboardHeight)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: searchFocused) { _, f in if f { withAnimation { proxy.scrollTo("more", anchor: .top) } } }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
                    // the screen ignores the keyboard (the layout keeps its shape); the list gets room to scroll past it
                    let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
                    let screen = UIScreen.main.bounds
                    keyboardHeight = end.minY >= screen.maxY ? 0 : max(0, screen.maxY - end.minY)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardHeight = 0 }
                .onChange(of: sug.scrollRequest) { _, r in if let r { withAnimation { proxy.scrollTo(r, anchor: .top) } } }
                }
            } else {
                Spacer()
            }
        }
    }

    /// A pick's row, shown at the place of it that leads among those the filter allows (D27); its other places are
    /// its "also on".
    @ViewBuilder private func row(_ cur: Track, _ o: Option, _ m: RowMetrics) -> some View {
        if let t = Library.shared.placed(o.id, playingDisc: cur.disc, among: sug.target.allows) {
            if sug.minimal { PlainPick(cur: cur, target: t, pair: o.pair, kind: o.kind, tags: o.tags, big: m.simple).padding(.top, sug.minimal ? Look.Picks.plainTop : 0) }
            else { NextRow(cur: cur, target: t, pair: o.pair, kind: o.kind, tags: o.tags, zoom: zoom, m: m) }
        }
    }

    private func groupLabel(_ s: String) -> some View {
        Text(s.uppercased()).font(Look.Picks.groupFont).kerning(Look.Picks.groupKerning).foregroundStyle(Theme.dim)
            .frame(height: sug.mode == .simple ? Look.Picks.groupHeightSimple : Look.Picks.groupHeight, alignment: .bottomLeading)
    }

}

/// The search at the top of More: filters More's rows by title or artist; an (x) clears it.
struct MoreSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: Look.Search.gap) {
            Image(systemName: "magnifyingglass").font(Look.Search.iconFont).foregroundStyle(Theme.dim)
            TextField("", text: $text, prompt: Text(Words.searchMore).foregroundStyle(Theme.dim))
                .font(Look.Search.font).foregroundStyle(Theme.tx).tint(Theme.orange)
                .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                .focused(focused)
                .onSubmit { focused.wrappedValue = false }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(Look.Search.clearFont).foregroundStyle(Theme.mut)
                        .frame(width: Look.Search.clearSize, height: Look.Search.clearSize).contentShape(Rectangle())
                }
                .accessibilityLabel(Words.clearSearch)
            }
        }
        .padding(.leading, Look.Search.sides).padding(.trailing, text.isEmpty ? Look.Search.sides : 0)
        .frame(minHeight: Look.Search.minHeight)
        .background(RoundedRectangle(cornerRadius: Look.Search.radius).fill(Look.Search.fill))
        .overlay(RoundedRectangle(cornerRadius: Look.Search.radius).stroke(focused.wrappedValue ? Theme.orange.opacity(Look.Search.focusOpacity) : Theme.line, lineWidth: Look.Search.line))
        .frame(maxWidth: Look.Search.maxWidth, alignment: .leading)
    }
}

/// Where the shortlist ends in More: a thin line with a small dim label.
struct ShortlistEndMarker: View {
    var body: some View {
        HStack(spacing: Look.Marker.gap) {
            Rectangle().fill(Theme.line).frame(width: Look.Marker.leadWidth, height: Look.Marker.line)
            Text(Words.restOfCrate).font(Look.Marker.font).foregroundStyle(Theme.dim).fixedSize()
            Rectangle().fill(Theme.line).frame(height: Look.Marker.line)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "128 BPM · pitch +3.2%" ("128→140 BPM" when the song changes tempo; no pitch when it can't be beat-matched)
func pickBPMLine(_ t: Track, _ pair: Pair?, _ ji: JoinInfo) -> String {
    var bpm = Words.bpm(t.bpmShown)
    if let bi = t.bpmIn, abs(bi / max(1, t.bpmShown) - 1) > 0.02 { bpm = Words.bpmChange(bi, t.bpmShown) }
    guard pair?.tr != "brake_cut", ji.beatMatch, let p = ji.pitch else { return bpm }
    return Words.pitchAfterBPM(bpm, signed1(p)) + (pair.map { $0.m != "1" ? Words.tempoMultiple($0.m) : "" } ?? "")
}
/// the move: "blend", "echo out · key clash", "no beat-match · brake"
func pickMoveLine(_ pair: Pair?, _ ji: JoinInfo) -> String {
    var parts: [String] = []
    if pair?.tr == "brake_cut" || !ji.beatMatch { parts.append(Words.noBeatMatch) }
    if let p = pair {
        // the moves as a small menu: primary / alternative
        let mv = (p.mv?.isEmpty == false ? p.mv! : [p.trl]).map { $0 == Words.brakeCut ? Words.brake : $0 }
        parts.append(mv.prefix(2).joined(separator: Words.movesJoin))
    }
    if ji.verdict == "clash" { parts.append(Words.keyClash) }
    // A home-note pair that fits (D36): the fit rests on the note alone, with major or minor open.
    else if ji.verdict == Words.verdictHomeNote { parts.append(Words.moveHomeNote) }
    return parts.joined(separator: Words.moveLineJoin)
}

struct PickControls: View {
    @Environment(Recognizer.self) private var rec
    @Environment(SuggestState.self) private var sug

    @State private var dragging = false

    /// Simple / Full and the Shuffle dial on the left; library chips (one per disc of the crate, then All, each on/off)
    /// on the right.
    var body: some View {
        @Bindable var sug = sug
        return HStack(spacing: Look.Controls.pickControlsGap) {
            toggle([Words.simple, Words.full], sug.mode == .simple ? 0 : 1) { i in sug.mode = i == 0 ? .simple : .full; sug.reroll(rec) }
                .fixedSize()
            shuffleDial($sug.shuffle)
            Spacer(minLength: 0)
            if !Library.shared.data.discs.isEmpty {   // a crate without discs has one pool: nothing to narrow
                ForEach(Library.shared.data.discs, id: \.disc) { d in
                    libChip(d.short, on: sug.target.isOn(d.disc), color: d.color) { sug.target.toggle(d.disc); sug.reroll(rec) }
                }
                libChip(Words.all, on: sug.target.other, color: Theme.acc) { sug.target.other.toggle(); sug.reroll(rec) }
            }
        }
    }

    /// The Shuffle dial: 0% = the shortlist in score order, 100% = a fair shuffle of it. Letting go re-rolls the
    /// picks (and so does each step from VoiceOver's adjust gesture).
    private func shuffleDial(_ value: Binding<Double>) -> some View {
        HStack(spacing: Look.Controls.dialGap) {
            HStack(spacing: Look.Controls.dialLabelGap) {
                Text(Words.shuffle).font(Look.Controls.dialFont).foregroundStyle(Theme.dim)
                Text(Words.percent(Int((value.wrappedValue * 100).rounded()))).font(Look.Controls.dialValueFont)
                    .foregroundStyle(Theme.tx).frame(width: Look.Controls.dialValueWidth, alignment: .leading)
            }
            .lineLimit(1).fixedSize()
            Slider(value: value, in: 0...1, step: 0.05) { editing in
                dragging = editing
                if !editing { sug.reroll(rec) }
            }
            .frame(minWidth: Look.Controls.dialMinWidth, maxWidth: Look.Controls.dialMaxWidth)
        }
        .frame(minHeight: Look.Controls.dialMinHeight)
        .onChange(of: value.wrappedValue) { _, v in if !dragging && v != sug.rolledShuffle { sug.reroll(rec) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Words.shuffle)
    }

    private func libChip(_ t: String, on: Bool, color: Color, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(t).font(Look.Chips.libraryFont(on))
                .foregroundStyle(on ? Theme.tx : Theme.dim)
                .padding(.horizontal, Look.Chips.librarySides).frame(height: Look.Chips.libraryHeight)
                .background(Capsule().fill(on ? color.opacity(Look.Chips.libraryOnOpacity) : Color.clear))
                .overlay(Capsule().stroke(on ? Color.clear : Theme.dim.opacity(Look.Chips.libraryOffOpacity), lineWidth: Look.Chips.libraryLine))
        }
        .frame(minHeight: Look.Chips.libraryMinHeight)
        .fixedSize()
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggle(_ labels: [String], _ sel: Int, _ act: @escaping (Int) -> Void) -> some View {
        HStack(spacing: Look.Controls.modeGap) {
            ForEach(labels.indices, id: \.self) { i in
                Button { act(i) } label: {
                    Text(labels[i]).font(Look.Controls.modeFont(i == sel))
                        .foregroundStyle(i == sel ? Theme.tx : Theme.dim)
                        .padding(.horizontal, Look.Controls.modeSides).frame(minHeight: Look.Controls.modeMinHeight)
                }
                .accessibilityAddTraits(i == sel ? .isSelected : [])
                if i < labels.count - 1 { Text(Words.modeJoin).font(Look.Controls.modeJoinFont).foregroundStyle(Theme.dim.opacity(Look.Controls.modeJoinOpacity)) }
            }
        }
    }
}

struct RowMetrics {
    let simple: Bool
    var minimal = false
    var titleSize: CGFloat { simple ? Look.Picks.titleSimple : Look.Picks.title }
    var lineSize: CGFloat { simple ? Look.Picks.lineSimple : Look.Picks.line }      // folder path, artist
    var bpmSize: CGFloat { simple ? Look.Picks.bpmSimple : Look.Picks.bpm }
    var smallSize: CGFloat { simple ? Look.Picks.smallSimple : Look.Picks.small }
    var textWidth: CGFloat { simple ? Look.Picks.textWidthSimple : Look.Picks.textWidth }
    var waveHeight: CGFloat { simple ? Look.Picks.waveHeightSimple : Look.Picks.waveHeight }
    var cardHeight: CGFloat { simple ? Look.Picks.cardHeightSimple : Look.Picks.cardHeight }
    var padH: CGFloat { simple ? Look.Picks.sidesSimple : Look.Picks.sides }
    var padV: CGFloat { simple ? Look.Picks.topSimple : Look.Picks.top }
    var cardGap: CGFloat { simple ? Look.Picks.cardGapSimple : Look.Picks.cardGap }
    var groupGap: CGFloat { minimal ? Look.Picks.groupGapMinimal : simple ? Look.Picks.groupGapSimple : Look.Picks.groupGap }
    var labelHeight: CGFloat { simple ? Look.Picks.groupHeightSimple : Look.Picks.groupHeight }
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
        HStack(alignment: .center, spacing: Look.Picks.rowGap) {
            // The pick's cover (D36), inside the text column, which keeps its width; nothing when the song has none.
            HStack(alignment: .top, spacing: Look.Picks.coverGap) {
            if let c = target.cover {
                CoverThumb(hash: c, size: m.simple ? Look.Picks.coverSimple : Look.Picks.cover, radius: Look.Picks.coverRadius, opacity: Look.Picks.coverOpacity)
            }
            VStack(alignment: .leading, spacing: m.simple ? Look.Picks.textGapSimple : Look.Picks.textGap) {
                Text(target.folderPath).font(Look.Picks.placeFont(m.lineSize)).foregroundStyle(target.on ? target.discColor : Theme.mut).lineLimit(1)
                if let also = Library.shared.alsoOn(target, playingDisc: cur.disc) {
                    Text(also).font(Look.Picks.alsoFont(m.smallSize)).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(Look.Picks.alsoShrink)
                }
                Text(target.numberedSong).font(Look.Picks.titleFont(m.titleSize)).foregroundStyle(Theme.tx).lineLimit(1).minimumScaleFactor(Look.Picks.titleShrink)
                Text(target.secondLine).font(Look.Picks.artistFont(m.lineSize)).foregroundStyle(Theme.dim).lineLimit(1)
                Text(bpmLine(ji)).font(Look.Picks.bpmFont(m.bpmSize)).foregroundStyle(Theme.amber.opacity(Look.Picks.bpmOpacity)).lineLimit(1).padding(.top, m.simple ? Look.Picks.bpmTopSimple : Look.Picks.bpmTop)
                Text(smallLine(ji)).font(Look.Picks.moveFont(m.smallSize)).foregroundStyle(Theme.mut).lineLimit(1).minimumScaleFactor(Look.Picks.moveShrink)
            }
            }
            .frame(width: m.textWidth, alignment: .leading)
            if let wa = cur.wOut, let wb = target.wHead ?? target.wIn {
                let pts = StartPoint.candidates(for: target)
                let sp = pts[(sug.startIdx[target.id] ?? 0) % max(1, pts.count)]
                VStack(alignment: .leading, spacing: Look.Picks.joinGap) {
                    JoinView(a: cur, b: target, wa: wa, wb: wb, startB: sp.t, info: ji, zoom: zoom, height: m.waveHeight, marks: pts.map(\.t))
                        .contentShape(Rectangle())
                        .onTapGesture { sug.startIdx[target.id] = ((sug.startIdx[target.id] ?? 0) + 1) % max(1, pts.count) }
                        .accessibilityHint(Words.tryAnotherStart)
                    GeometryReader { g in
                        let fs: CGFloat = m.simple ? Look.Picks.startTimeSimple : Look.Picks.startTime
                        let tw = fs * Look.Picks.monoWidthShare * CGFloat(fmtTime(sp.t).count)        // monospaced width of "0:34"
                        HStack(alignment: .firstTextBaseline, spacing: Look.Picks.startGap) {
                            Text(fmtTime(sp.t)).font(Look.Picks.startTimeFont(fs)).foregroundStyle(Theme.mut)
                            if pts.count > 1 { Text(Words.syncs(pts.count)).font(Look.Picks.syncsFont(m.simple)).foregroundStyle(Theme.dim) }
                        }
                        .lineLimit(1).fixedSize()
                        .offset(x: max(0, g.size.width * Look.Picks.startTimeAt - tw / 2))
                    }
                    .frame(height: m.simple ? Look.Picks.startRowSimple : Look.Picks.startRow)
                }
                .frame(maxWidth: .infinity)
            } else { Spacer() }
        }
        .padding(.horizontal, m.padH).padding(.top, m.padV).padding(.bottom, max(Look.Picks.bottomMin, m.padV * Look.Picks.bottomShare))
        .frame(height: m.cardHeight)
        .background(RoundedRectangle(cornerRadius: Look.Picks.cardRadius).fill(Look.Picks.cardFill))
        .overlay(alignment: .topTrailing) { cornerChips.padding(.top, Look.Picks.chipsTop).padding(.trailing, Look.Picks.chipsTrailing) }
        .overlay(alignment: .leading) { if kind == .pinned { Capsule().fill(Theme.orange).frame(width: Look.Picks.pinnedBar).padding(.vertical, Look.Picks.pinnedBarInset) } }
        .contentShape(Rectangle())
        .onTapGesture { sug.pin(target.id, rec) }
        .onLongPressGesture { showDetail = true }
        .popover(isPresented: $showDetail) { detail(ji).presentationCompactAdaptation(.popover) }
        .accessibilityElement(children: .combine)
        .accessibilityHint(kind == .pinned ? Words.tapToUnpin : Words.tapToPin)
    }

    private func bpmLine(_ ji: JoinInfo) -> String { pickBPMLine(target, pair, ji) }
    private func smallLine(_ ji: JoinInfo) -> String { pickMoveLine(pair, ji) }

    /// tiny chips in the card's upper-right corner: what is unexpected about the pick (its first tag), Halloween, remix
    private var cornerChips: some View {
        HStack(spacing: Look.Chips.cornerGap) {
            if kind == .pick, let t = tags.first(where: { $0 != Words.tagHalloween }) { TinyChip(text: t) }
            if target.hal { TinyChip(text: Words.pumpkin) }
            if target.isRemix { TinyChip(text: Words.remixMark) }
            // Clean or dirty, where the crate file says (D39).
            if let l = target.lyrics.flatMap(Words.lyricsMark) { TinyChip(text: l) }
        }
    }

    private func detail(_ ji: JoinInfo) -> some View {
        VStack(alignment: .leading, spacing: Look.Detail.gap) {
            Text(target.hasName ? (target.artist.isEmpty ? target.song : Words.artistSong(target.artist, target.song)) : target.oneLine).font(Look.Detail.titleFont)
            if !target.ver.isEmpty { Text(target.ver).foregroundStyle(.secondary) }
            // A song with no key says which kind of none (D33): Deckie was not sure, or no key was read. A home note
            // shows in place of the code (D36).
            if target.key == nil && target.keyHome == nil {
                Text(target.keyNotSure == true ? Words.keyNotSureLine : Words.keyNotReadLine).font(Look.Detail.font)
            } else if target.key == nil {
                Text(Words.homeNoteLine(target.keyShown, ji.keyText, ji.verdict)).font(Look.Detail.font)
            } else {
                Text(Words.keyLine(target.keyShown, ji.keyText, ji.verdict)).font(Look.Detail.font)
            }
            Text(Words.pitchHelp(ji.pitch.map { Words.percentText(signed1($0)) } ?? Words.notAvailable)).font(Look.Detail.font)
            if let p = pair {
                Text(Words.matchScore(p.s, p.st)).font(Look.Detail.scoreFont).foregroundStyle(.secondary)
                Text(Words.moves(p.mv ?? [p.trl])).font(Look.Detail.font)
                ForEach(p.reasons, id: \.self) { Text(Words.reason($0)).font(Look.Detail.font) }
            }
        }
        .padding(Look.Detail.padding).frame(width: Look.Detail.width, alignment: .leading)
    }
}

func verdictPhrase(_ v: String) -> String {
    Words.verdictPhrase(v)
}

/// Where the next song could come in: its mix-in window (default), the track start, the first steady-beat bar,
/// and the following 8-bar phrase boundaries (within the 64-bar head snippet).
struct StartPoint: Hashable {
    let t: Double
    let label: String
    static func candidates(for b: Track) -> [StartPoint] {
        let bar = 240 / b.gridBPM
        let mi = b.mixIn?[0] ?? (b.firstBeat ?? 0)
        var pts = [StartPoint(t: mi, label: Words.startMixIn)]
        func add(_ t: Double, _ l: String) { if t >= 0, !pts.contains(where: { abs($0.t - t) < 0.5 }) { pts.append(StartPoint(t: t, label: l)) } }
        guard let h = b.wHead else { return pts }
        let headEnd = h.t0 + Double(h.n) * 60 / b.gridBPM / Double(b.samplesPerBeat) - 2 * bar
        add(0, Words.startTrack)
        if let s = b.steadyIn, s < headEnd { add(s, Words.startSteady) }
        let fb = b.firstBeat ?? mi
        let miBar = Int(((mi - fb) / bar).rounded())
        for k in 1...7 {
            let t = mi + Double(8 * k) * bar
            if t < headEnd { add(t, Words.startBar(miBar + 8 * k + 1)) }
        }
        return pts
    }
}

/// Small quiet chip (corner marks: 🎃, RMX, a pick's tag).
struct TinyChip: View {
    let text: String
    var body: some View {
        Text(text).font(Look.Chips.tinyFont).foregroundStyle(Theme.dim)
            .padding(.horizontal, Look.Chips.tinySides).frame(height: Look.Chips.tinyHeight)
            .background(Capsule().fill(Look.Chips.tinyFill))
    }
}

/// Halloween and remix/edit marks as tiny chips.
struct Marks: View {
    let track: Track
    var size: CGFloat = Look.Chips.marksSize
    var body: some View {
        HStack(spacing: Look.Chips.cornerGap) {
            if track.hal { TinyChip(text: Words.pumpkin) }
            if track.isRemix { TinyChip(text: Words.remixMark) }
        }
        .accessibilityLabel(Words.marksSpoken(halloween: track.hal, remix: track.isRemix))
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
            let num: CGFloat = Look.Join.numberRoom
            let laneA = (num, H / 2 - Look.Join.laneGap / 2), laneB = (H / 2 + Look.Join.laneGap / 2, H - num)
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
            g.fill(Path(ov), with: .color(Look.Join.overlapFill))
            g.fill(Path(CGRect(x: ov.minX, y: ov.minY, width: ov.width, height: Look.Join.overlapLine)), with: .color(Theme.amber.opacity(Look.Join.overlapLineOpacity)))
            g.fill(Path(CGRect(x: ov.minX, y: ov.maxY - Look.Join.overlapLine, width: ov.width, height: Look.Join.overlapLine)), with: .color(Theme.amber.opacity(Look.Join.overlapLineOpacity)))
            func lane(_ w: Wave, _ vals: [Int], j: Double, scl: Double, spb: Int, _ ly: (CGFloat, CGFloat), _ col: Color, fallbackK0: Int, numberY: CGFloat, brightFromJoin: Bool = false, numbers: Bool = true) {
                let mid = (ly.0 + ly.1) / 2, half = (ly.1 - ly.0) / 2 - Look.Join.laneInset
                let step = P * scl
                let k0 = w.k0 ?? fallbackK0
                var on = Path(), off = Path()
                for i in 0..<min(w.n, vals.count) {
                    let x = X((Double(i) - j) * scl)
                    if x < -step || x > W { continue }
                    let hh = max(Look.Join.barMin, CGFloat(vals[i]) / 63 * half)
                    let r = CGRect(x: x, y: mid - hh, width: step + Look.Join.barOverlap, height: hh * 2)
                    let bright = brightFromJoin ? Double(i) >= j.rounded() : (i >= w.win[0] && i < w.win[1])
                    if bright { on.addRect(r) } else { off.addRect(r) }
                }
                g.fill(off, with: .color(col.opacity(Look.Join.offOpacity)))
                g.fill(on, with: .color(col.opacity(Look.Join.onOpacity)))
                let perBar = 4 * spb, perPhrase = 32 * spb
                for i in 0...w.n {
                    let k = k0 + i
                    guard ((k % spb) + spb) % spb == 0 else { continue }
                    let x = X((Double(i) - j) * scl)
                    if x < 0 || x > W { continue }
                    let isBar = ((k % perBar) + perBar) % perBar == 0
                    if !isBar {
                        // beat line: a thin dark cut through the filled shape
                        g.fill(Path(CGRect(x: x - Look.Join.beatLine / 2, y: ly.0 + Look.Join.beatInset, width: Look.Join.beatLine, height: ly.1 - ly.0 - 2 * Look.Join.beatInset)), with: .color(Theme.bg.opacity(Look.Join.beatOpacity)))
                        continue
                    }
                    let phrase = ((k % perPhrase) + perPhrase) % perPhrase == 0
                    g.fill(Path(CGRect(x: x - Look.Join.barLineOffset, y: ly.0, width: phrase ? Look.Join.phraseLine : Look.Join.barLine, height: ly.1 - ly.0)), with: .color(Look.Join.lines.opacity(phrase ? Look.Join.phraseOpacity : Look.Join.barOpacity)))
                    if numbers && phrase && k >= 0 {
                        g.draw(Text("\(k / perBar + 1)").font(Look.Join.numberFont).foregroundColor(Theme.mut),
                               at: CGPoint(x: x + Look.Join.numberInset, y: numberY), anchor: .leading)
                    }
                }
                let xe = X((Double(w.win[1]) - j) * scl)
                if xe > 0 && xe < W { g.fill(Path(CGRect(x: xe - Look.Join.windowEnd / 2, y: ly.0, width: Look.Join.windowEnd, height: ly.1 - ly.0)), with: .color(col)) }
            }
            let fbA = (JoinView.bar(at: a.mixOut?[0] ?? 0, of: a) - 1) * 4 * spbA - wa.win[0]
            let fbB = -wb.win[0]                                    // mix-in window starts on bar 1
            lane(wa, va, j: jA, scl: 1, spb: spbA, laneA, a.discColor, fallbackK0: fbA, numberY: num / 2)
            lane(wb, vb, j: jB, scl: sB, spb: spbB, laneB, info.beatMatch ? b.discColor : Theme.dim, fallbackK0: fbB, numberY: H - num / 2, brightFromJoin: true, numbers: marks.isEmpty)
            // the other places B could start (tap the wave to move there), numbered in order
            let PB = 60 / b.gridBPM / Double(spbB)
            for (n, t) in marks.enumerated() {
                let x = X(((t - wb.t0) / PB - jB) * sB)
                if x < Look.Join.markLeftMin || x > W - Look.Join.markRightMin { continue }
                if n == 0 {
                    // the recommended first sync point (B's mix-in start): a small labelled marker under the lane
                    var tri = Path(); tri.move(to: CGPoint(x: x, y: laneB.1 + Look.Join.syncTriTop)); tri.addLine(to: CGPoint(x: x - Look.Join.syncTriHalf, y: laneB.1 + Look.Join.syncTriBottom)); tri.addLine(to: CGPoint(x: x + Look.Join.syncTriHalf, y: laneB.1 + Look.Join.syncTriBottom)); tri.closeSubpath()
                    g.fill(tri, with: .color(Theme.amber.opacity(Look.Join.syncOpacity)))
                    g.draw(Text(Words.syncMark).font(Look.Join.markFont).foregroundColor(Theme.amber.opacity(Look.Join.syncOpacity)),
                           at: CGPoint(x: x + Look.Join.syncLabelInset, y: H - num / 2 + Look.Join.syncLabelDrop), anchor: .leading)
                    continue
                }
                if abs(t - startB) <= 0.3 { continue }
                g.fill(Path(CGRect(x: x - Look.Join.tickWidth / 2, y: laneB.1 - Look.Join.tickHeight, width: Look.Join.tickWidth, height: Look.Join.tickHeight)), with: .color(Theme.mut))
                g.draw(Text("\(n + 1)").font(Look.Join.markFont).foregroundColor(Theme.mut),
                       at: CGPoint(x: x, y: H - num / 2), anchor: .center)
            }
            var c = g
            c.addFilter(.shadow(color: Look.Join.joinGlow, radius: Look.Join.joinGlowRadius))
            c.fill(Path(CGRect(x: X(0) - Look.Join.joinLine / 2, y: laneA.0 - Look.Join.joinOverhang, width: Look.Join.joinLine, height: laneB.1 - laneA.0 + 2 * Look.Join.joinOverhang)), with: .color(Look.Join.join))
        }
        .frame(height: height)
        .accessibilityLabel(Words.joinSpoken(a.oneLine, b.oneLine, fmtTime(startB)))
    }

    static func bar(at t: Double, of tr: Track) -> Int {
        guard let fb = tr.firstBeat else { return 1 }
        return Int(((t - fb) / (240 / tr.gridBPM)).rounded()) + 1
    }
}
