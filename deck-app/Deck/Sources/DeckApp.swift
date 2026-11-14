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
            TabView(selection: $tab) {
                ListenView().tabItem { Label("Listen", systemImage: "waveform") }.tag(0)
                CrateTabView(tab: $tab).tabItem { Label(CrateTabView.title, systemImage: "square.stack") }.tag(1)
                MixMapView().tabItem { Label("Mix map", systemImage: "point.3.connected.trianglepath.dotted") }.tag(2)
            }
            // The library is not observed: another crate file open redraws every tab from it.
            .id(sug.crateVersion)
            .overlay(alignment: .topLeading) { MinimalToggle().padding(.leading, 20).padding(.top, 2) }
            .tint(Theme.orange)
            .environment(rec)
            .environment(sug)
            .preferredColorScheme(.dark)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true      // stays on next to the decks
                // What the system makes of the extension, as a folder (package) and as a plain file (data).
                for (label, base) in [("as a folder", UTType.package), ("as a file", UTType.data)] {
                    if let t = UTType(filenameExtension: CrateFormat.packageExtension, conformingTo: base) {
                        rec.note("type for .deckiecrate \(label): \(t.identifier), package \(t.conforms(to: .package)), data \(t.conforms(to: .data)), declared \(t.isDeclared)")
                    }
                }
                // test hook without the "Open in Deck?" prompt: simctl launch <dev> io.christophershannon.deck -deckURL 'deck://...'
                if let u = UserDefaults.standard.string(forKey: "deckURL"), let url = URL(string: u) {
                    for part in u.components(separatedBy: " ; ") { if let x = URL(string: part) { handle(x) } }
                    _ = url
                } else if rec.source == .idle { rec.startMic() }
            }
            .onOpenURL { url in url.isFileURL ? openCrate(url) : handle(url) }
            .onChange(of: sug.tabRequest) { _, t in if let t { tab = t; sug.tabRequest = nil } }
            .onChange(of: sug.chooseCrateFile) { _, on in if on { choosing = true; sug.chooseCrateFile = false } }
            .fileImporter(isPresented: $choosing, allowedContentTypes: CrateFileType.importable) { r in
                if case .success(let url) = r { openCrate(url) }
            }
            .alert(sug.openProblem?.title ?? "", isPresented: Binding(get: { sug.openProblem != nil }, set: { if !$0 { sug.openProblem = nil } }),
                   presenting: sug.openProblem) { _ in
                Button("OK", role: .cancel) {}
            } message: { p in
                Text(p.why + "\n\n" + p.detail)
            }
            .overlay(alignment: .top) {
                if let note = sug.openedNote {
                    Text(note).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.tx)
                        .padding(.horizontal, 18).frame(minHeight: 40)
                        .background(Capsule().fill(Theme.card2)).overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                        .padding(.top, 8)
                        .task(id: note) { try? await Task.sleep(for: .seconds(5)); if sug.openedNote == note { sug.openedNote = nil } }
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
                     + "\(Library.shared.crate?.signatures.count ?? 0) with fingerprints; picks are scored per song (timbre list \(secs) s)")
            sug.openedNote = Words.opened(r.crate.manifest.name, songs: Library.shared.songCount)
            tab = 0
            // Listening starts again (with no fingerprints it only says "not listening"); a test hook leaves the mic off.
            if listen { rec.startMic() } else if !Library.shared.canRecognise { rec.status = Words.notListening }
        } catch {
            rec.note("crate failed: \(error)")
            sug.openProblem = OpenProblem(title: Words.couldNotOpen(url.lastPathComponent), why: Words.whyNotOpened(error), detail: Words.detail(error))
        }
    }

    /// Test hooks: deck://test?path=/abs/file.mp3&start=60&render=r%2B4&loop=1 · deck://mic · deck://stop ·
    /// deck://lib?cd1=1&cd2=0&all=0 · deck://lib?disc=<name>&on=0|1 · deck://tab?i=1 · deck://set?id=<track id> · deck://mode?m=simple|full · deck://all?on=1 · deck://shuffle (re-roll) ·
    /// deck://shuffle?amt=0.3 (set the Shuffle dial, 0...1, then re-roll) · deck://pin?i=0 ·
    /// deck://search?q=love (search More's titles and artists; empty q clears)
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
            // deck://crate?path=/abs/x.deckiecrate: open that crate file (either form) as "Open in" would, instead
            // of the bundled data or the crate file open now
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
        let scored = Library.shared.takePickSecs().map { String(format: " (scored in %.0f ms)", $0 * 1000) } ?? ""
        var rank = 0
        let rows = options.map { o -> String in
            let t = Library.shared.track(o.id)
            let r: String
            if o.kind == .pinned { r = "pinned" } else { rank += 1; r = "\(rank)." }
            let sc = o.pair.map { String(format: "%.3f", $0.s) } ?? "-"
            return "\(r) \(t?.song ?? o.id) \(sc)\(o.tags.isEmpty ? "" : " <" + o.tags.joined(separator: ",") + ">")"
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

/// The crate file's document type (declared in project.yml: `UTExportedTypeDeclarations` and
/// `CFBundleDocumentTypes`). One type, `.deckiecrate`, covers both forms: the package a Mac writes and the single file
/// a PC writes (deck-app/README.md, "Crate files from a PC", for the evidence).
enum CrateFileType {
    static let identifier = "io.christophershannon.deckie.crate"
    static let crate = UTType(exportedAs: identifier)
    static let crateFile = UTType(exportedAs: identifier + "-file")
    /// What the chooser offers: the declared type, and any type the system gives the extension (should another app
    /// declare `.deckiecrate` differently, a crate file still shows).
    static var importable: [UTType] {
        [crate, crateFile]
    }
}

/// Small quiet switch in the app's upper-left corner (every tab): text-only display on / off.
struct MinimalToggle: View {
    @Environment(SuggestState.self) private var sug
    var body: some View {
        Button { sug.minimal.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: sug.minimal ? "text.alignleft" : "waveform").font(.system(size: 13, weight: .medium))
                Text("Minimal").font(.system(size: 13, weight: sug.minimal ? .semibold : .regular))
            }
            .foregroundStyle(sug.minimal ? Theme.tx : Theme.dim)
            .padding(.horizontal, 10).frame(height: 30)
            .background(Capsule().fill(sug.minimal ? Color.white.opacity(0.12) : Color.clear))
            .overlay(Capsule().stroke(Theme.dim.opacity(sug.minimal ? 0 : 0.35), lineWidth: 1))
        }
        .frame(minHeight: 44)
        .accessibilityLabel("Minimal display")
        .accessibilityValue(sug.minimal ? "on" : "off")
    }
}
