import SwiftUI
import UIKit

@main
struct DeckApp: App {
    @State private var rec = Recognizer()
    @State private var sug = SuggestState()
    @State private var tab = 0
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                ListenView().tabItem { Label("Listen", systemImage: "waveform") }.tag(0)
                CDsView(tab: $tab).tabItem { Label("CDs", systemImage: "opticaldisc") }.tag(1)
                MixMapView().tabItem { Label("Mix map", systemImage: "point.3.connected.trianglepath.dotted") }.tag(2)
            }
            .overlay(alignment: .topLeading) { MinimalToggle().padding(.leading, 20).padding(.top, 2) }
            .tint(Theme.orange)
            .environment(rec)
            .environment(sug)
            .preferredColorScheme(.dark)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true      // stays on next to the decks
                // test hook without the "Open in Deck?" prompt: simctl launch <dev> io.christophershannon.deck -deckURL 'deck://...'
                if let u = UserDefaults.standard.string(forKey: "deckURL"), let url = URL(string: u) {
                    for part in u.components(separatedBy: " ; ") { if let x = URL(string: part) { handle(x) } }
                    _ = url
                } else if rec.source == .idle { rec.startMic() }
            }
            .onOpenURL { handle($0) }
            .onChange(of: phase) { _, p in
                // the audio session can be interrupted (lock, Control Centre, another app): restart listening on return
                if p == .active && rec.source == .mic { rec.startMic() }
            }
        }
    }

    /// Test hooks: deck://test?path=/abs/file.mp3&start=60&render=r%2B4&loop=1 · deck://mic · deck://stop ·
    /// deck://tab?i=1 · deck://set?id=<track id> · deck://mode?m=simple|full · deck://all?on=1 · deck://shuffle · deck://pin?i=0
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
        case "scroll": let t = v("to"); DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { sug.scrollRequest = t }
        case "lib": sug.target = LibraryFilter(cd1: v("cd1") != "0", cd2: v("cd2") != "0", other: v("all") == "1"); sug.reroll(rec)
        case "startpt": let n = Int(v("i") ?? "1") ?? 1; let want = v("id"); DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if let id = want ?? sug.pinned ?? sug.options.first?.id { sug.startIdx[id] = n } }
        case "shuffle": sug.reroll(rec)
        case "page": let p = Int(v("i") ?? "0") ?? 0; DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { sug.page = p } }
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
    var target = LibraryFilter()
    var startIdx: [String: Int] = [:]   // chosen start point of each pick's lane (kept when pinned)
    var pinned: String?
    var options: [Option] = []      // first set (test hooks)
    var sets: [[Option]] = []
    var rest: [Option] = []
    var page = 0
    var scrollRequest: String?     // test hook: scroll the picks to an anchor
    var rolledFor: String?
    private var rng = SystemRandomNumberGenerator()

    func reroll(_ rec: Recognizer) {
        guard let cur = rec.current else { options = []; sets = []; rest = []; rolledFor = nil; return }
        if pinned == cur.id { pinned = nil }
        let exclude = Set(rec.history.suffix(12))
        if rolledFor != cur.id { startIdx = [:] }
        let r = Suggester().rollSets(cur: cur, mode: mode, target: target, exclude: exclude, pinned: pinned, nSets: 1, rng: &rng)
        sets = r.sets; rest = r.rest; page = 0
        options = sets.first ?? []
        rolledFor = cur.id
        rec.note("suggestions for \(cur.song) [\(mode.rawValue)\(", " + target.label)]: " + sets.flatMap { $0 }.map { o in
            let t = Library.shared.track(o.id)
            let k = o.kind == .best ? "B" : o.kind == .hard ? "H" : "m"
            return "\(k) \(t?.song ?? o.id) \(String(format: "%.2f", o.pair.s))\(o.tags.isEmpty ? "" : " <" + o.tags.joined(separator: ",") + ">")"
        }.joined(separator: " | "))
    }
    func pin(_ id: String, _ rec: Recognizer) {
        pinned = (pinned == id) ? nil : id
        reroll(rec)
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
