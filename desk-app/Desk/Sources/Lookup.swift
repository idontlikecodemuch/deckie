import SwiftUI
import DeckieCrate
import DeckieDesk
import DeckieLookup

/// "Look up songs via MusicBrainz" on the Mac (D36; letter AA, 3.8 to 3.12): the same plan, sentence, lookup, review
/// and apply as the Windows and Linux window, all DeckieDesk's (`DeskLookup`, `DeskLookupRun`); this file only shows
/// them. The step that uses the internet is marked everywhere by its own colour and the globe, never Desk's accent.

/// The lookup's design values, named in one place for the design pass (D36).
enum LookupStyle {
    static let net = Color(red: 0.435, green: 0.839, blue: 0.788)
    static let band = net.opacity(0.14)
    static let fits = Color(red: 0.56, green: 0.89, blue: 0.64)
    static let off = Color.orange
    static let icon = "globe"
    static let sheetWidth: CGFloat = 860
    static let sheetHeight: CGFloat = 640
}

/// The sheet's state: which step, the plan, the count while it goes, the review and what the DJ chose.
struct LookupSheetState {
    enum Step { case ask, progress, review }
    var step: Step = .ask
    var scope: String
    var ids: [String]?
    var source: String?
    var plan: DeskLookup.Plan?
    var done = 0, total = 0, found = 0
    var review: DeskLookup.Review?
    /// By song: the candidate used (-1: none of these) and the fields ticked.
    var choices: [String: (candidate: Int, fields: Set<String>)] = [:]
    var failure: String?

    var ticked: Int { choices.values.filter { $0.candidate >= 0 }.reduce(0) { $0 + $1.fields.count } }
}

extension DeskModel {
    /// What Desk has sent, and whether the one-song sentence was shown once (`lookups.json` in Desk's storage).
    var lookupLog: LookupLog { LookupLog.load(home) }

    func lookupPlan(scope: String, ids: [String]?, source: String?) -> DeskLookup.Plan? {
        guard let c = crate else { return nil }
        do {
            return try DeskLookup.plan(scope: scope, ids: ids, source: source, crate: c, info: current, paths: placePaths,
                                       home: home, facts: facts)
        } catch { errorText = error.localizedDescription; return nil }
    }

    /// Opens the lookup on these songs (or a source, a disc, the songs that need a name). One song, once its sentence
    /// has been read, is looked up at once; a batch and a disc always show the sentence first.
    func lookUp(scope: String, ids: [String]? = nil, source: String? = nil) {
        guard let plan = lookupPlan(scope: scope, ids: ids, source: source) else { return }
        lookup = LookupSheetState(scope: scope, ids: ids, source: source, plan: plan)
        if plan.scope == "song", lookupExplained, plan.summary.nothingToSend == 0 { startLookup() }
    }

    /// The sheet's chooser changed what is looked up: a new plan and sentence; nothing is sent.
    func replan(scope: String, ids: [String]?, source: String?) {
        guard lookup?.step == .ask, let plan = lookupPlan(scope: scope, ids: ids, source: source) else { return }
        lookup?.scope = scope; lookup?.ids = ids; lookup?.source = source; lookup?.plan = plan
    }

    func startLookup() {
        guard let plan = lookup?.plan else { return }
        guard lookupClient.available else {
            lookup?.step = .review; lookup?.failure = LookupFailure.notOnThisComputer.code; return
        }
        if plan.scope == "song" {
            var log = lookupLog
            if !log.explained { log.explained = true; try? log.save(home) }
            lookupExplained = true
        }
        lookup?.step = .progress; lookup?.done = 0; lookup?.total = plan.songs.count; lookup?.found = 0
        let home = self.home, lock = self.sentLock
        let run = DeskLookupRun(plan: plan, client: lookupClient, sent: { LookupLog.record($0, home: home, lock: lock) })
        lookupRun = run
        Thread.detachNewThread { [weak self] in
            let review = run.run { p in
                Task { @MainActor [weak self] in
                    guard self?.lookup?.step == .progress else { return }
                    self?.lookup?.done = p.done; self?.lookup?.total = p.total; self?.lookup?.found = p.found
                }
            }
            Task { @MainActor [weak self] in self?.lookupFinished(review) }
        }
    }

    func stopLookup() { lookupRun?.stop() }

    func lookupFinished(_ r: DeskLookup.Review) {
        lookupRun = nil
        guard lookup != nil else { return }
        lookup?.step = .review
        lookup?.review = r
        lookup?.failure = nil
        var choices: [String: (candidate: Int, fields: Set<String>)] = [:]
        for c in DeskLookup.defaultChoices(r) { choices[c.song] = (c.candidate, Set(c.fields)) }
        lookup?.choices = choices
    }

    /// The DJ picked a candidate (-1: none of these): its default ticks.
    func pick(_ song: String, _ i: Int) {
        guard let s = lookup?.review?.songs.first(where: { $0.song == song }) else { return }
        let fields = i >= 0 && i < s.candidates.count ? Set(s.candidates[i].changes.filter { $0.tick && !$0.locked }.map(\.field)) : []
        lookup?.choices[song] = (i, fields)
    }

    /// Applies what the DJ ticked as one undo step, marked `lookup:musicbrainz`.
    func applyLookup() {
        guard let L = lookup, let r = L.review, crate != nil else { lookup = nil; return }
        let choices = L.choices.compactMap { song, c in
            c.candidate >= 0 && !c.fields.isEmpty ? DeskLookup.Choice(song: song, candidate: c.candidate, fields: Array(c.fields)) : nil
        }
        var n = 0
        changeForLookup(Words.t("undoLookup")) {
            n = DeskLookup.apply(r, choices, to: &$0, corrections: &$1, book: &$2)
        }
        lookup = nil
        if n > 0 { undoLine = Words.c("lookupApplied", n) }
    }

    func clearSent() {
        sentLock.lock(); defer { sentLock.unlock() }
        var log = lookupLog
        log.sent = []
        try? log.save(home)
        objectWillChange.send()
    }
}

/// The lookup's sheet: the sentence first, then the count, then the review.
struct LookupSheet: View {
    @EnvironmentObject var model: DeskModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: LookupStyle.icon)
                Text(Words.t("lookupKindLine"))
            }
            .font(.callout.weight(.medium)).foregroundStyle(LookupStyle.net)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LookupStyle.band, in: RoundedRectangle(cornerRadius: 10))
            if let L = model.lookup {
                switch L.step {
                case .ask: ask(L)
                case .progress: progress(L)
                case .review: review(L)
                }
            }
        }
        .padding(20)
        .frame(width: LookupStyle.sheetWidth, height: LookupStyle.sheetHeight, alignment: .topLeading)
    }

    // MARK: the sentence

    struct Option: Hashable { var key: String; var label: String; var scope: String; var ids: [String]?; var source: String? }

    var options: [Option] {
        var out: [Option] = []
        let need = model.needingNames.count
        if need > 0 { out.append(Option(key: "need", label: Words.t("lookupChoice.needsName") + " (\(need))", scope: "songs")) }
        let sel = Array(model.selection)
        if sel.count == 1, let t = model.binding(for: sel[0]) {
            out.append(Option(key: "song:" + t.id, label: Words.t("lookupChoice.song") + ": " + t.ident.title, scope: "song", ids: sel))
        } else if sel.count > 1 {
            out.append(Option(key: "selection", label: Words.t("lookupChoice.selection") + " (\(sel.count))", scope: "songs", ids: sel))
        }
        for src in model.crate?.discPlan ?? [] {
            if model.current?.discs[src.name] != nil {
                out.append(Option(key: "disc:" + src.name, label: Words.t("lookupDisc").replacingOccurrences(of: "…", with: "") + ": " + src.name,
                                  scope: "disc", source: src.name))
            } else {
                out.append(Option(key: "source:" + src.name, label: src.name, scope: "songs", source: src.name))
            }
        }
        return out
    }

    func key(_ L: LookupSheetState) -> String {
        if L.scope == "disc" { return "disc:" + (L.source ?? "") }
        if L.scope == "song" { return "song:" + (L.ids?.first ?? "") }
        if let s = L.source { return "source:" + s }
        if L.ids != nil { return "selection" }
        return "need"
    }

    @ViewBuilder func ask(_ L: LookupSheetState) -> some View {
        Text(Words.t("lookupSheetTitle")).font(.title2.bold())
        let opts = options
        if opts.count > 1 || L.scope != "song" {
            Picker(Words.t("lookupSongsFrom"), selection: Binding(get: { key(L) }, set: { k in
                if let o = opts.first(where: { $0.key == k }) { model.replan(scope: o.scope, ids: o.ids, source: o.source) }
            })) {
                ForEach(opts, id: \.key) { Text($0.label).tag($0.key) }
            }
            .frame(maxWidth: 520)
        }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array((L.plan?.summary.sentence ?? []).enumerated()), id: \.offset) { i, line in
                Text(line).font(i == 0 ? .title3 : .body).foregroundStyle(i == 0 ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
        Spacer()
        HStack {
            Button(Words.t("lookupSentLink")) { model.showSent = true }.buttonStyle(.link).foregroundStyle(LookupStyle.net)
            Spacer()
            Button(Words.t("lookupNotNow")) { model.lookup = nil }.keyboardShortcut(.cancelAction)
            Button { model.startLookup() } label: { Label(Words.t("lookupGo"), systemImage: LookupStyle.icon) }
                .buttonStyle(.borderedProminent).tint(LookupStyle.net).keyboardShortcut(.defaultAction)
                .disabled((L.plan?.summary.songs ?? 0) - (L.plan?.summary.nothingToSend ?? 0) <= 0)
        }
    }

    // MARK: the count

    @ViewBuilder func progress(_ L: LookupSheetState) -> some View {
        Text(Words.t("lookupProgressTitle")).font(.title2.bold())
        ProgressView(value: Double(L.done), total: Double(max(1, L.total))).tint(LookupStyle.net)
        Text(Words.c("lookupProgress", L.total, ["done": "\(L.done)"]) + " · " + Words.c("lookupProgressFound", L.found))
            .font(.headline).monospacedDigit()
        Text(Words.t("lookupProgressHelp")).foregroundStyle(.secondary)
        Spacer()
        HStack { Spacer(); Button(Words.t("lookupStop")) { model.stopLookup() }.keyboardShortcut(.cancelAction) }
    }

    // MARK: the review

    @ViewBuilder func review(_ L: LookupSheetState) -> some View {
        Text(Words.t("lookupReviewTitle")).font(.title2.bold())
        if let f = L.failure {
            Text(DeskWords.text("lookupFailure." + f)).font(.headline)
        } else if let r = L.review {
            Text(DeskLookup.summaryLine(r)).font(.headline)
            if r.scope == "disc" { Text(DeskWords.coded("lookupDiscMatch", r.discMatch ?? "none")).foregroundStyle(.secondary) }
            Text(Words.t("lookupReviewHelp")).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(r.songs, id: \.song) { s in SongCard(song: s, single: r.scope == "song") }
                }
            }
            Text(Words.t("lookupGenreNote")).font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        HStack {
            Button(Words.t("lookupSentLink")) { model.showSent = true }.buttonStyle(.link)
            Spacer()
            Button(Words.cancel) { model.lookup = nil }.keyboardShortcut(.cancelAction)
            Button(Words.c("lookupApply", L.ticked)) { model.applyLookup() }
                .buttonStyle(.borderedProminent).tint(LookupStyle.net).disabled(L.ticked == 0)
        }
    }
}

/// One song in the review: its length, what was found, the candidates side by side, and a tick per field.
struct SongCard: View {
    @EnvironmentObject var model: DeskModel
    let song: DeskLookup.SongResult
    let single: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(song.title).font(.headline)
                Text(Words.t("lookupYourSong", ["length": Words.mmss(song.seconds)])).foregroundStyle(.secondary)
            }
            if song.outcome != "found" {
                Text(outcome).foregroundStyle(.secondary)
            } else {
                if song.several { Text(Words.t("lookupSeveral")).foregroundStyle(.secondary) }
                else if song.chosen == nil { Text(Words.t("lookupNoneFits")).foregroundStyle(.secondary) }
                let choice = model.lookup?.choices[song.song] ?? (-1, [])
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("")
                        Text(Words.t("colTitle")); Text(Words.t("colArtist")); Text(Words.t("colRelease"))
                        Text(Words.t("colYear")); Text(Words.t("label")); Text(Words.t("colLength"))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(song.candidates.enumerated()), id: \.offset) { i, c in
                        GridRow {
                            Button { model.pick(song.song, i) } label: {
                                Image(systemName: choice.candidate == i ? "largecircle.fill.circle" : "circle")
                            }
                            .buttonStyle(.plain).foregroundStyle(LookupStyle.net)
                            .accessibilityLabel(Words.t("lookupUseThis") + ": " + c.title)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.title + (c.version.map { " (\($0))" } ?? "")).lineLimit(2)
                                if !c.notes.isEmpty {
                                    Text(c.notes.map { DeskWords.coded("lookupNote", $0) }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(c.artist ?? "").lineLimit(1)
                            Text(c.release ?? "").lineLimit(2)
                            Text(c.year ?? "")
                            Text(c.label ?? "").lineLimit(1)
                            Text(lengthWords(c)).foregroundStyle(c.fit == "fits" ? LookupStyle.fits : (c.fit == "off" ? LookupStyle.off : .secondary))
                        }
                        .foregroundStyle(c.otherVersion ? .secondary : .primary)
                    }
                    GridRow {
                        Button { model.pick(song.song, -1) } label: { Image(systemName: choice.candidate < 0 ? "largecircle.fill.circle" : "circle") }
                            .buttonStyle(.plain).foregroundStyle(LookupStyle.net)
                        Text(Words.t("lookupNoneOfThese")).foregroundStyle(.secondary).gridCellColumns(6)
                    }
                }
                .font(.callout)
                if choice.candidate >= 0, choice.candidate < song.candidates.count {
                    let c = song.candidates[choice.candidate]
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(c.changes, id: \.field) { ch in
                            Toggle(isOn: Binding(get: { model.lookup?.choices[song.song]?.fields.contains(ch.field) == true && !ch.locked },
                                                 set: { on in
                                                     var cur = model.lookup?.choices[song.song] ?? (choice.candidate, [])
                                                     if on { cur.fields.insert(ch.field) } else { cur.fields.remove(ch.field) }
                                                     model.lookup?.choices[song.song] = cur
                                                 })) {
                                (Text(Words.t(ch.field) + ": ") + Text(ch.before.map { $0 + " → " } ?? "").foregroundColor(.secondary)
                                    + Text(ch.after ?? "")
                                    + Text(ch.note.map { "  (" + DeskWords.coded("changeNote", $0) + ")" } ?? "").foregroundColor(.secondary))
                            }
                            .toggleStyle(.checkbox).disabled(ch.locked)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    var outcome: String {
        if song.outcome == "nothing" && single { return Words.t("lookupNothingOne") }
        var s = DeskWords.coded("lookupOutcome", song.outcome)
        if song.outcome == "failed", let f = song.failure { s += ": " + DeskWords.text("lookupFailure." + f) }
        return s
    }

    func lengthWords(_ c: DeskLookup.Candidate) -> String {
        guard let secs = c.seconds else { return Words.t("lookupLengthUnknown") }
        let len = Words.mmss(secs)
        guard let d = c.difference else { return len }
        if abs(d) < 1 { return Words.t("lookupLengthSame", ["length": len]) }
        let diff = abs(d) < 60 ? Words.c("seconds", Int(abs(d).rounded())) : Words.mmss(abs(d))
        return Words.t(d > 0 ? "lookupLengthLonger" : "lookupLengthShorter", ["length": len, "difference": diff])
    }
}

/// "What Desk has sent": every request, newest first, with what it carried and the whole address; clearable.
struct SentSheet: View {
    @EnvironmentObject var model: DeskModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let sent = Array(model.lookupLog.sent.reversed())
        VStack(alignment: .leading, spacing: 10) {
            Text(Words.t("lookupSentTitle")).font(.title2.bold())
            Text(Words.t("lookupSentIntro")).foregroundStyle(.secondary)
            if sent.isEmpty {
                Text(Words.t("lookupSentEmpty")).foregroundStyle(.secondary)
            }
            List(Array(sent.enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Words.t("lookupSentLine", ["kind": DeskWords.coded("sentKind", r.kind),
                                                    "fields": r.fields.map { DeskWords.fill(DeskWords.coded("sentField", $0.first ?? ""), ["value": $0.last ?? ""]) }.joined(separator: ", ")]))
                    Text(Words.t("lookupSentAnswer", ["time": r.at.formatted(date: .abbreviated, time: .standard),
                                                      "answer": DeskWords.coded("sentAnswer", r.answer)])).font(.caption).foregroundStyle(.secondary)
                    Text(r.address).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
                }
            }
            HStack {
                Button(Words.t("lookupSentClear"), role: .destructive) { model.clearSent() }.disabled(sent.isEmpty)
                Spacer()
                Button(Words.done) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 760, height: 560)
    }
}
