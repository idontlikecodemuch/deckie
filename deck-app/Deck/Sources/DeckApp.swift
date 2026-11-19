import SwiftUI
import UIKit
import UniformTypeIdentifiers
import DeckieCrate

@main
struct DeckApp: App {
    @State private var rec = Recognizer()
    @State private var sug = SuggestState()
    @State private var tab = 0
    @State private var choosing = false
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                // No crate file open: the first-run screen; a crate file open: the tabs, as before.
                switch BoothScreen.current {
                case .firstRun(let demo):
                    FirstRunView(demo: demo, openCrateFile: { choosing = true },
                                 openDemo: { if let u = DemoCrate.url() { openCrate(u) } })
                case .crate:
                    TabView(selection: $tab) {
                        ListenView().tabItem { Label(Words.tabListen, systemImage: "waveform") }.tag(0)
                        CrateTabView(tab: $tab).tabItem { Label(CrateTabView.title, systemImage: "square.stack") }.tag(1)
                    }
                    .overlay(alignment: .topLeading) { MinimalToggle().padding(.leading, Look.App.minimalLeading).padding(.top, Look.App.minimalTop) }
                }
            }
            // The library is not observed: another crate file open redraws every screen from it.
            .id(sug.crateVersion)
            .tint(Theme.orange)
            .environment(rec)
            .environment(sug)
            .preferredColorScheme(.dark)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true      // stays on next to the decks
                // What the system makes of each extension a crate file is read under (`.deckie`, the earlier
                // `.deckiecrate`), as a folder (package) and as a plain file (data).
                for ext in CrateFormat.readExtensions {
                    for (label, base) in [("as a folder", UTType.package), ("as a file", UTType.data)] {
                        if let t = UTType(filenameExtension: ext, conformingTo: base) {
                            rec.note("type for .\(ext) \(label): \(t.identifier), package \(t.conforms(to: .package)), data \(t.conforms(to: .data)), declared \(t.isDeclared)")
                        }
                    }
                }
                #if DEBUG
                // test hook without the "Open in Deckie Booth?" prompt: simctl launch <dev> io.deckie.booth -deckURL 'deck://...'
                // (Debug builds only, like every deck:// hook)
                if let u = UserDefaults.standard.string(forKey: "deckURL"), URL(string: u) != nil {
                    for part in u.components(separatedBy: " ; ") { if let x = URL(string: part) { handle(x) } }
                    return
                }
                #endif
                // With no crate file open there is nothing to listen for, and the microphone is not asked for.
                if rec.source == .idle && Library.shared.crate != nil { rec.startMic() }
            }
            .onOpenURL { url in
                // A crate file from Files, AirDrop or "Open in" (every build); the deck:// test hooks (Debug only).
                if url.isFileURL { openCrate(url); return }
                #if DEBUG
                handle(url)
                #endif
            }
            .onChange(of: sug.tabRequest) { _, t in if let t { tab = t; sug.tabRequest = nil } }
            .onChange(of: sug.chooseCrateFile) { _, on in if on { choosing = true; sug.chooseCrateFile = false } }
            .onChange(of: sug.leaveDemo) { _, on in if on { sug.leaveDemo = false; leaveDemo() } }
            .fileImporter(isPresented: $choosing, allowedContentTypes: CrateFileType.importable) { r in
                if case .success(let url) = r { openCrate(url) }
            }
            .alert(sug.openProblem?.title ?? "", isPresented: Binding(get: { sug.openProblem != nil }, set: { if !$0 { sug.openProblem = nil } }),
                   presenting: sug.openProblem) { _ in
                Button(Words.ok, role: .cancel) {}
            } message: { p in
                Text(Words.openProblem(p.why, p.detail))
            }
            .overlay(alignment: .top) {
                if let note = sug.openedNote {
                    Text(note).font(Look.App.noteFont).foregroundStyle(Theme.tx)
                        .padding(.horizontal, Look.App.noteSides).frame(minHeight: Look.App.noteMinHeight)
                        .background(Capsule().fill(Theme.card2)).overlay(Capsule().stroke(Theme.line, lineWidth: Look.App.noteLine))
                        .padding(.top, Look.App.noteTop)
                        .task(id: note) { try? await Task.sleep(for: .seconds(Look.App.noteSeconds)); if sug.openedNote == note { sug.openedNote = nil } }
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .onChange(of: phase) { _, p in
                // the audio session can be interrupted (lock, Control Centre, another app): restart listening on return
                if p == .active && rec.source == .mic { rec.startMic() }
            }
        }
    }

    /// Opens a crate file handed to the app (Files, AirDrop, iCloud Drive, "Open in", the chooser, a test hook), in
    /// either form, and starts on it: listening when it has fingerprints, otherwise waiting for a song set by hand.
    /// A crate file that cannot be opened leaves the one open now as it was, and says why in plain words.
    private func openCrate(_ url: URL, listen: Bool = true) {
        rec.note("opening \(url.lastPathComponent)")
        do {
            let r = try Library.shared.open(crateFile: url)
            rec.forgetSongs(); rec.rebuildCatalog(); sug.pinned = nil; sug.target = LibraryFilter(); sug.moreQuery = ""
            sug.reroll(rec); sug.crateVersion += 1
            let secs = Library.shared.crate.map { String(format: "%.1f", $0.poolSecs) } ?? "?"
            rec.note("crate loaded (\(r.wasSingleFile ? "single file, unpacked" : "package, copied")): \(Library.shared.data.tracks.count) tracks, "
                     + "\(Library.shared.crate?.deckieSongs ?? 0) with Deckie's fingerprints, \(Library.shared.crate?.signatures.count ?? 0) with Apple's signatures; picks are scored per song (timbre list \(secs) s)")
            sug.openedNote = DemoCrate.isOpen ? Words.demoOpened(songs: Library.shared.songCount)
                                              : Words.opened(r.crate.manifest.name, songs: Library.shared.songCount)
            tab = 0
            // Listening starts again (with no fingerprints it only says "not listening"); a test hook leaves the mic off.
            if listen { rec.startMic() } else if !Library.shared.canRecognise { rec.status = Words.notListening }
        } catch {
            rec.note("crate failed: \(error)")
            sug.openProblem = OpenProblem(title: Words.couldNotOpen(url.lastPathComponent), why: Words.whyNotOpened(error), detail: Words.detail(error))
        }
    }

    /// "Leave the demo crate": the demo crate file is put away and the booth shows its first-run screen again, where the
    /// DJ's own crate file is opened. Listening and the set's recording stop.
    private func leaveDemo() {
        rec.note("leaving the demo")
        rec.forgetSongs()
        Library.shared.close()
        sug.pinned = nil; sug.target = LibraryFilter(); sug.moreQuery = ""; sug.openedNote = nil
        sug.reroll(rec); sug.crateVersion += 1
        tab = 0
    }

    #if DEBUG
    /// Test hooks (Debug builds only; a tester's build has none): deck://test?path=/abs/file.mp3&start=60&render=r%2B4&loop=1 · deck://mic · deck://stop ·
    /// deck://lib?cd1=1&cd2=0&all=0 · deck://lib?disc=<name>&on=0|1 · deck://tab?i=1 · deck://set?id=<track id> · deck://mode?m=simple|full · deck://all?on=1 · deck://shuffle (re-roll) ·
    /// deck://shuffle?amt=0.3 (set the Shuffle dial, 0...1, then re-roll) · deck://pin?i=0 ·
    /// deck://search?q=love (search More's titles and artists; empty q clears) ·
    /// deck://hearing?with=deckie|apple|both (which recogniser; deck://stream plays a file through it as the microphone would)
    private func handle(_ url: URL) {
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func v(_ k: String) -> String? { q.first { $0.name == k }?.value }
        switch url.host {
        case "test":
            guard let p = v("path") else { return }
            tab = 0
            rec.testFile(URL(fileURLWithPath: p), start: Double(v("start") ?? "60") ?? 60, render: v("render") ?? "o", loop: v("loop") != "0")
        case "stream":
            guard let p = v("path") else { return }
            tab = 0
            rec.startStream(URL(fileURLWithPath: p), start: Double(v("start") ?? "60") ?? 60, render: v("render") ?? "o")
        case "hearing":
            // deck://hearing?with=deckie|apple|both: which recogniser names the song (the details sheet's choice)
            if let h = v("with").flatMap(Hearing.init(rawValue:)) { rec.chosen = h }
        case "recpause": rec.toggleRecPause()
        case "mic": rec.startMic()
        case "stop": rec.stop()
        case "tab": tab = Int(v("i") ?? "0") ?? 0
        case "set": if let id = v("id") { rec.setManual(id); sug.reroll(rec); tab = 0 }
        case "mode": sug.mode = v("m") == "simple" ? .simple : .full; sug.reroll(rec)
        case "minimal": sug.minimal = v("on") != "0"
        case "all": sug.target.other = v("on") == "1"; sug.reroll(rec)
        case "search": sug.moreQuery = v("q") ?? ""
        case "scroll": let t = v("to"); DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { sug.scrollRequest = t }
        case "lib":
            // deck://lib?cd1=&cd2=&all=: the whole filter, discs by position (first, second); deck://lib?disc=<name>&on=0|1:
            // one disc, by its label or its name
            let discs = Library.shared.data.discs
            if let name = v("disc") {
                if let d = discs.first(where: { $0.disc == name || $0.name == name || $0.short == name }) { sug.target.set(d.disc, on: v("on") != "0") }
            } else {
                var f = LibraryFilter(); f.other = v("all") == "1"
                for (i, key) in ["cd1", "cd2"].enumerated() where i < discs.count { f.set(discs[i].disc, on: v(key) != "0") }
                sug.target = f
            }
            sug.reroll(rec)
        case "startpt": let n = Int(v("i") ?? "1") ?? 1; let want = v("id"); DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if let id = want ?? sug.pinned ?? sug.options.first?.id { sug.startIdx[id] = n } }
        case "crate", "open":
            // deck://crate?path=/abs/x.deckie (or an earlier x.deckiecrate): open that crate file (either form) as "Open in" would, in
            // place of the crate file open now (or the first-run screen)
            guard let p = v("path") else { return }
            openCrate(URL(fileURLWithPath: p), listen: false)
        case "choose":
            // deck://choose: the Open crate file chooser (the system's document picker)
            choosing = true
        case "after":
            // deck://after?s=<seconds>&u=<url-encoded deck:// hook>: run that hook later (a scripted walk-through;
            // several hooks in one -deckURL are separated by " ; ")
            if let s = Double(v("s") ?? ""), let u = v("u"), let next = URL(string: u) {
                DispatchQueue.main.asyncAfter(deadline: .now() + s) { handle(next) }
            }
        case "shuffle":
            if let a = v("amt").flatMap(Double.init) { sug.shuffle = a }
            sug.reroll(rec)
        case "pin": if let i = Int(v("i") ?? ""), i < sug.options.count { sug.pin(sug.options[i].id, rec) }
        case "orient":
            let o: UIInterfaceOrientationMask = v("o") == "landscape" ? .landscapeRight : .portrait
            for case let ws as UIWindowScene in UIApplication.shared.connectedScenes { ws.requestGeometryUpdate(.iOS(interfaceOrientations: o)) { e in print("DECK orient error", e) }; print("DECK orient requested", ws.interfaceOrientation.rawValue) }
        default: break
        }
    }
    #endif
}

@MainActor @Observable final class SuggestState {
    var mode: SuggestMode = .simple
    /// text-only display (no waveforms), remembered between launches
    var minimal: Bool = UserDefaults.standard.bool(forKey: "minimal") { didSet { UserDefaults.standard.set(minimal, forKey: "minimal") } }
    /// The Shuffle dial, 0...1: 0 shows the shortlist in pure score order, 1 shuffles it fairly; remembered.
    var shuffle: Double = SuggestState.savedShuffle() {
        didSet {
            let c = min(1, max(0, shuffle.isFinite ? shuffle : 0.5))
            if c != shuffle { shuffle = c; return }
            UserDefaults.standard.set(shuffle, forKey: "shuffle")
        }
    }
    private static func savedShuffle() -> Double {
        guard UserDefaults.standard.object(forKey: "shuffle") != nil else { return 0.5 }
        return min(1, max(0, UserDefaults.standard.double(forKey: "shuffle")))
    }
    var target = LibraryFilter()
    var startIdx: [String: Int] = [:]   // chosen start point of each pick's lane (kept when pinned)
    var pinned: String?
    var options: [Option] = []      // the picks on the screen, a pinned song first (test hooks: pin?i=)
    var rest: [Option] = []         // More: the rest of the shortlist, then the rest of the crate by score
    var restShortlist = 0           // how many of `rest` are from the shortlist (the marker goes after them)
    var shortlistSize = 0
    /// the search over More's titles and artists (test hook: search?q=); not remembered between launches
    var moreQuery = ""
    var scrollRequest: String?     // test hook: scroll the picks to an anchor
    var tabRequest: Int?           // a view asking for another tab (the Listen page's "Choose a song")
    var chooseCrateFile = false    // the Crate tab's "Open crate file" asking for the chooser
    var leaveDemo = false          // "Leave the demo crate" (the Listen page, the Crate tab) asking for the first-run screen
    var openProblem: OpenProblem?  // why the last crate file handed to the app could not be opened
    var openedNote: String?        // "Friday night is open: 12 songs.", shown for a few seconds
    var crateVersion = 0           // raised when another crate file opens, so every view is drawn from it again
    var rolledFor: String?
    var rolledShuffle: Double?     // the dial setting the current picks were rolled with
    private var rng = SystemRandomNumberGenerator()

    func reroll(_ rec: Recognizer) {
        guard let cur = rec.current else { options = []; rest = []; restShortlist = 0; shortlistSize = 0; rolledFor = nil; rolledShuffle = shuffle; return }
        if pinned == cur.id { pinned = nil }
        let exclude = Set(rec.history.suffix(12))
        if rolledFor != cur.id { startIdx = [:] }
        let (list, short) = Suggester().ranked(cur: cur, target: target, exclude: exclude, pinned: pinned, shuffle: shuffle, rng: &rng)
        let lead = list.first?.kind == .pinned ? 1 : 0
        let n = min(short, mode == .full ? 10 : 5) + lead
        options = Array(list.prefix(n)); rest = Array(list.dropFirst(n))
        shortlistSize = short
        restShortlist = short + lead - n
        rolledFor = cur.id; rolledShuffle = shuffle
        let scored = Library.shared.takePickSecs().map { String(format: " (scored in %.0f ms)", $0 * 1000) } ?? ""   // log
        var rank = 0
        let rows = options.map { o -> String in
            let t = Library.shared.track(o.id)
            let r: String
            if o.kind == .pinned { r = "pinned" } else { rank += 1; r = "\(rank)." }
            let sc = o.pair.map { String(format: "%.3f", $0.s) } ?? "-"
            return "\(r) \(t?.song ?? o.id) \(sc)\(o.tags.isEmpty ? "" : " <" + o.tags.joined(separator: ",") + ">")"   // log
        }
        rec.note("suggestions for \(cur.song)\(scored) [\(mode.rawValue)\(", " + target.label)]: shuffle \(Int((shuffle * 100).rounded()))%, shortlist \(shortlistSize): "
                 + rows.joined(separator: " | ") + " | more \(rest.count) (shortlist \(restShortlist), rest \(rest.count - restShortlist))")
    }
    func pin(_ id: String, _ rec: Recognizer) {
        pinned = (pinned == id) ? nil : id
        reroll(rec)
    }
}

/// A crate file that could not be opened: the alert's title, the plain sentence and the reader's own words.
struct OpenProblem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let why: String
    let detail: String
}

/// The crate file's document types (declared in project.yml: `UTExportedTypeDeclarations`,
/// `UTImportedTypeDeclarations` and `CFBundleDocumentTypes`). One extension, `.deckie`, for both forms; two type
/// identifiers, because the system needs one for a folder and one for a plain file: `io.deckie.crate` for the package
/// a Mac writes, `io.deckie.crate-file` for the single file a PC writes (deck-app/README.md, "Crate files from a PC",
/// for the evidence). Both also take the earlier extension, `.deckiecrate`.
///
/// The type identifiers used before November 2026 (`io.christophershannon.deckie.crate` and `...crate-file`) are
/// declared as imported types conforming to the new ones, so a file still tagged with one opens here too.
enum CrateFileType {
    static let identifier = "io.deckie.crate"
    static let crate = UTType(exportedAs: identifier)
    static let crateFile = UTType(exportedAs: identifier + "-file")
    /// The earlier identifiers, kept importable for good.
    static let earlierIdentifiers = ["io.christophershannon.deckie.crate", "io.christophershannon.deckie.crate-file"]
    static let earlier: [UTType] = earlierIdentifiers.map { UTType(importedAs: $0) }
    /// What the chooser offers: the declared types, the earlier ones, and any type the system gives either extension
    /// (should another app declare `.deckie` differently, a crate file still shows).
    static var importable: [UTType] {
        var all = [crate, crateFile] + earlier
        for ext in CrateFormat.readExtensions {
            for base in [UTType.package, UTType.data] {
                if let t = UTType(filenameExtension: ext, conformingTo: base), !all.contains(t) { all.append(t) }
            }
        }
        return all
    }
}

/// Small quiet switch in the app's upper-left corner (every tab): text-only display on / off.
struct MinimalToggle: View {
    @Environment(SuggestState.self) private var sug
    var body: some View {
        Button { sug.minimal.toggle() } label: {
            HStack(spacing: Look.App.minimalGap) {
                Image(systemName: sug.minimal ? "text.alignleft" : "waveform").font(Look.App.minimalIconFont)
                Text(Words.minimal).font(Look.App.minimalFont(sug.minimal))
            }
            .foregroundStyle(sug.minimal ? Theme.tx : Theme.dim)
            .padding(.horizontal, Look.App.minimalSides).frame(height: Look.App.minimalHeight)
            .background(Capsule().fill(sug.minimal ? Look.App.minimalOnFill : Color.clear))
            .overlay(Capsule().stroke(Theme.dim.opacity(sug.minimal ? 0 : Look.App.minimalOffLineOpacity), lineWidth: Look.App.minimalLine))
        }
        .frame(minHeight: Look.App.minimalMinHeight)
        .accessibilityLabel(Words.minimalSpoken)
        .accessibilityValue(sug.minimal ? Words.switchOn : Words.switchOff)
    }
}
