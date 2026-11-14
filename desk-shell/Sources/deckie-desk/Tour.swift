import Foundation
#if os(macOS)
import AppKit
import WebKit
#endif

/// `deckie-desk --tour <folder> --music <folder> --export-to <folder>`: walks every screen of the window with the
/// music given (generated songs; never a DJ's own), as a DJ would click through it, and writes a picture of each into
/// <folder>. The pictures come from the web view itself (WKWebView's snapshot), so they work with no screen recording
/// permission. The Mac only: the other systems have no snapshot here and run `--check` instead.
enum Tour {
    struct Step {
        var name: String?
        var js: String?
        /// Waits for an engine event of this name (after the step's script ran), else just `delay`.
        var event: String?
        var eventTest: (([String: Any]) -> Bool)?
        var delay: Double = 0.8

        func with(js: String) -> Step { var s = self; s.js = js; return s }
    }

    static func arm(_ desk: Desk, out: URL) {
        #if os(macOS)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let click = { (selector: String) in "document.querySelector(\(js(selector))).click();" }
        let tourSteps: [Step] = [
            Step(name: "01-first-screen", delay: 2.0),
            Step(name: "02-add-music-menu", js: click("#add-button"), delay: 1.0),
            Step(name: "03-run", js: "[...document.querySelectorAll('#add-menu [role=menuitem]')].pop().click();",
                 event: "run.progress", eventTest: { (($0["done"] as? NSNumber)?.intValue ?? 0) >= 2 }, delay: 0.3),
            Step(name: "04-finished", event: "run.finished", delay: 1.2),
            Step(name: "05-exported", js: click("#finished-export"), delay: 2.0),
            Step(name: "06-songs", js: click("#finished-songs"), delay: 1.0),
            Step(name: "07-needs-a-name", js: click("#status-needname"), delay: 0.8),
            Step(name: nil, js: click("#status-needname"), delay: 0.5),
            Step(name: "08-name-fix-in-place", js: """
                var td = [...document.querySelectorAll('#songs-body td[data-col=title]')].find(function (c) { return c.textContent === 'Night Drive'; });
                td.dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
                td.querySelector('input').value = 'Night Drive (Club Mix)';
                """, delay: 0.6),
            Step(name: "09-name-fixed", js: """
                document.querySelector('#songs-body td input').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
                """, event: "songs", delay: 0.8),
            Step(name: "10-sources-panel", js: click("#sources-button"), delay: 1.0),
            Step(name: "11-remove-source", js: click(".tree .src .danger"), delay: 1.0),
            Step(name: nil, js: "document.getElementById('confirm').close('cancel');", delay: 0.4),
            Step(name: "12-crate-menu", js: click("#crate-button"), delay: 0.8),
            Step(name: "13-rename-crate", js: "[...document.querySelectorAll('#crate-menu [role=menuitem]')].find(function (b) { return b.textContent.indexOf('Rename') === 0; }).click();", delay: 0.8),
            Step(name: nil, js: "document.getElementById('ask').close('cancel');", delay: 0.4),
            Step(name: "14-what-didnt-go-in", js: click("#log-button"), delay: 0.8),
            Step(name: nil, js: "document.getElementById('log').close('ok');", delay: 0.4),
            Step(name: "15-more-menu", js: click("#more-button"), delay: 0.8),
            Step(name: nil, js: click("#more-button"), delay: 0.3),
            Step(name: "16-undo-named", js: click("#side-close"), delay: 0.6),
            Step(name: "17-new-crate", js: "desk.request('crate.new');", event: "state", delay: 1.0),
        ]
        let arguments = ProcessInfo.processInfo.arguments
        let steps = arguments.contains("--lookup") ? lookupSteps(click)
            : arguments.contains("--naming") ? namingSteps(click)
            : arguments.contains("--run-screen") ? runScreenSteps(click) : tourSteps
        if arguments.contains("--record") { record(desk, out: out.appendingPathComponent("frames")) }
        var events: [[String: Any]] = []
        let lock = NSLock()
        desk.watchers.append { line in
            guard let m = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
            lock.lock(); events.append(m); lock.unlock()
        }
        func say(_ s: String) { FileHandle.standardError.write(Data(("[tour] " + s + "\n").utf8)) }

        func run(_ i: Int) {
            guard i < steps.count else {
                say("done: \(steps.compactMap(\.name).count) pictures in \(out.path)")
                desk.engine?.stop()
                exit(0)
            }
            let step = steps[i]
            lock.lock(); let mark = events.count; lock.unlock()
            if let js = step.js { desk.window.eval("try { \(js) } catch (e) { console.error(e); }") }
            Thread.detachNewThread {
                if let event = step.event {
                    let end = Date().addingTimeInterval(600)
                    while Date() < end {
                        lock.lock(); let seen = events[mark...].contains { $0["event"] as? String == event && (step.eventTest?($0) ?? true) }; lock.unlock()
                        if seen { break }
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                }
                Thread.sleep(forTimeInterval: step.delay)
                desk.window.onWindowThread {
                    guard let name = step.name else { run(i + 1); return }
                    snapshot(desk, to: out.appendingPathComponent(name + ".png")) { ok in
                        say((ok ? "wrote " : "could not write ") + name)
                        run(i + 1)
                    }
                }
            }
        }
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 1.0)
            desk.window.onWindowThread { run(0) }
        }
        #else
        FileHandle.standardError.write(Data("deckie-desk: --tour takes pictures on the Mac only\n".utf8))
        exit(1)
        #endif
    }

    /// The naming screens (research AA): the list of songs that need a name, one song's panel with a guess and the
    /// offer to split typed words, Listen with its scrub bar, the tools with their previews, a music CD with no names
    /// (asked for its name while it is read, then named from a playlist) and one with CD-Text. Needs the generated
    /// songs as `--music`, stand-in discs D (CD-Text) and E (none) in DECKIE_DESK_MUSIC_CD, and `--playlist`.
    static func namingSteps(_ click: (String) -> String) -> [Step] {
        let row = { (title: String) in "[...document.querySelectorAll('#songs-body td[data-col=title]')].find(function (c) { return c.textContent === \(js(title)); }).click();" }
        let menuItem = { (menu: String, i: Int) in "document.querySelectorAll('#\(menu) [role=menuitem]')[\(i)].click();" }
        let enter = "dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));"
        let songsEvent: (String) -> Step = { name in Step(name: name, event: "songs", delay: 1.0) }
        return [
            Step(name: "n01-first-screen", delay: 2.0),
            Step(name: nil, js: click("#add-button"), delay: 0.8),
            Step(name: "n02-run", js: "[...document.querySelectorAll('#add-menu [role=menuitem]')].pop().click();",
                 event: "run.progress", eventTest: { (($0["done"] as? NSNumber)?.intValue ?? 0) >= 1 }, delay: 0.3),
            Step(name: "n03-finished-names", event: "run.finished", delay: 1.5),
            Step(name: "n04-needs-a-name-list", js: click("#finished-summary button.link"), delay: 1.0),
            Step(name: "n05-names-panel-guess", js: row("Sunrise"), delay: 0.8),
            Step(name: "n06-split-offer", js: row("Night Drive") + " setTimeout(function () { var i = document.getElementById('fact-title'); i.value = 'Artist K - Night Drive (Extended mix)'; i.\(enter) }, 300);", delay: 1.4),
            songsEvent("n07-split-applied").with(js: click("#names .offer button.main")),
            Step(name: "n08-listen", js: row("Low Tide (Dub)") + " setTimeout(function () { document.querySelector('#names .foot button.main').click(); }, 300);", delay: 4.0),
            Step(name: "n09-listen-scrubbed", js: "var r = document.getElementById('player-scrub'); r.value = '700'; r.dispatchEvent(new Event('input', { bubbles: true })); r.dispatchEvent(new Event('change', { bubbles: true }));", delay: 1.2),
            Step(name: nil, js: click("#player-stop"), delay: 0.4),
            Step(name: "n10-tools-menu", js: click("#tools-button"), delay: 0.8),
            Step(name: "n11-paste-counts-differ", js: menuItem("tools-menu", 0) + " setTimeout(function () { var x = document.getElementById('tool-text'); x.value = 'Artist A - Sunrise\\nArtist L - Night Drive'; x.dispatchEvent(new Event('input')); }, 300);", delay: 1.6),
            Step(name: "n12-paste-preview", js: "var x = document.getElementById('tool-text'); x.value = ['Artist A - Sunrise', 'Artist K - Night Drive (Extended mix)', 'Artist B - Low Tide (Dub)', 'Artist M - Harbour lights', 'Artist N - Slow Bloom', 'Artist O - Morning'].join('\\n'); x.dispatchEvent(new Event('input'));", delay: 1.6),
            songsEvent("n13-names-added").with(js: click("#tool-apply")),
            Step(name: nil, js: click("#tools-button"), delay: 0.5),
            Step(name: "n14-pattern-tool", js: menuItem("tools-menu", 1), delay: 1.6),
            Step(name: nil, js: "document.getElementById('tool').close('cancel');", delay: 0.4),
            Step(name: nil, js: "desk.request('crate.new');", event: "state", delay: 0.8),
            Step(name: "n15-add-menu-music-cds", js: click("#add-button"), delay: 1.4),
            Step(name: "n16-reading-asks-disc-name", js: "[...document.querySelectorAll('#add-menu [role=menuitem]')].find(function (b) { return / E$/.test(b.textContent); }).click();",
                 event: "run.started", delay: 0.6),
            Step(name: nil, js: "var i = document.getElementById('disc-ask-input'); i.value = 'Friday late'; document.getElementById('disc-ask').requestSubmit();", delay: 0.3),
            Step(name: "n17-disc-no-names-finished", event: "run.finished", delay: 1.8),
            Step(name: "n18-disc-songs-need-names", js: click("#finished-summary button.link"), delay: 1.0),
            Step(name: nil, js: click("#tools-button"), delay: 0.5),
            Step(name: "n19-playlist-preview", js: menuItem("tools-menu", 2) + " setTimeout(function () { document.getElementById('tool-choose').click(); }, 300);", delay: 1.8),
            songsEvent("n20-playlist-applied").with(js: click("#tool-apply")),
            Step(name: nil, js: "desk.request('crate.new');", event: "state", delay: 0.8),
            Step(name: nil, js: click("#add-button"), delay: 1.2),
            Step(name: "n21-disc-with-names-finished", js: "[...document.querySelectorAll('#add-menu [role=menuitem]')].find(function (b) { return / D$/.test(b.textContent); }).click();",
                 event: "run.finished", delay: 1.8),
            Step(name: "n22-disc-names-panel", js: click("#finished-songs") + " setTimeout(function () { document.querySelector('#songs-body tr td[data-col=title]').click(); }, 400);", delay: 1.2),
        ]
    }

    /// "Look up songs via MusicBrainz" (D36): one song's button, its sentence, its review and what was filled in; the
    /// line under the button after that; a source's batch with its sentence, its count while it goes and its review;
    /// the needs-a-name bar's button; "What Desk has sent"; a music CD's sentence and MusicBrainz not knowing it. Needs
    /// the lookup's generated songs as `--music`, DECKIE_LOOKUP_RECORDED (answers recorded once; nothing is sent), and
    /// stand-in disc E in DECKIE_DESK_MUSIC_CD.
    static func lookupSteps(_ click: (String) -> String) -> [Step] {
        let row = { (title: String) in "[...document.querySelectorAll('#songs-body td[data-col=title]')].find(function (c) { return c.textContent === \(js(title)); }).click();" }
        let menuText = { (menu: String, text: String) in "[...document.querySelectorAll('#\(menu) [role=menuitem]')].find(function (b) { return b.textContent.indexOf(\(js(text))) === 0; }).click();" }
        let scope = { (prefix: String) in "var s = document.getElementById('lookup-scope'); s.value = [...s.options].find(function (o) { return o.value.indexOf(\(js(prefix))) === 0; }).value; s.dispatchEvent(new Event('change'));" }
        return [
            Step(name: nil, delay: 2.0),
            Step(name: nil, js: click("#add-button"), delay: 0.8),
            Step(name: nil, js: "[...document.querySelectorAll('#add-menu [role=menuitem]')].pop().click();", event: "run.finished", delay: 1.0),
            Step(name: nil, js: click("#finished-songs"), delay: 1.0),
            Step(name: "l01-panel-lookup-button", js: row("Around the World"), delay: 1.0),
            Step(name: "l02-sentence-one-song", js: click("#names .foot button.net"), delay: 1.2),
            Step(name: "l03-review-one-song", js: click("#lookup-go"), event: "lookup.finished", delay: 1.0),
            Step(name: "l04-filled-from-musicbrainz", js: click("#lookup-go"), event: "songs", delay: 1.2),
            Step(name: "l05-under-the-button", js: row("Blue Monday"), delay: 1.5),
            // Undo the one song's lookup, so the batch asks for it as it was (the answers recorded once are for that).
            Step(name: nil, js: click("#undo"), event: "songs", delay: 0.6),
            Step(name: "l06-more-menu", js: click("#more-button"), delay: 0.8),
            Step(name: nil, js: menuText("more-menu", "Look up songs via MusicBrainz"), delay: 1.0),
            Step(name: "l07-sentence-batch", js: scope("source:"), delay: 1.2),
            Step(name: "l08-progress", js: click("#lookup-go"), event: "lookup.progress",
                 eventTest: { (($0["done"] as? NSNumber)?.intValue ?? 0) >= 2 }, delay: 0.2),
            Step(name: "l09-review-batch", event: "lookup.finished", delay: 1.0),
            Step(name: "l10-review-batch-further", js: "document.getElementById('lookup-songs').scrollTop = 900;", delay: 0.6),
            Step(name: "l11-review-batch-end", js: "var b = document.getElementById('lookup-songs'); b.scrollTop = b.scrollHeight;", delay: 0.6),
            Step(name: "l12-names-added", js: click("#lookup-go"), event: "songs", delay: 1.2),
            Step(name: "l13-needs-a-name-bar", js: click("#status-needname"), delay: 1.0),
            Step(name: nil, js: click("#more-button"), delay: 0.6),
            Step(name: "l14-what-desk-has-sent", js: menuText("more-menu", "What Desk has sent"), delay: 1.2),
            Step(name: nil, js: "document.getElementById('sent').close('ok');", delay: 0.4),
            Step(name: nil, js: "desk.request('crate.new');", event: "state", delay: 0.8),
            Step(name: nil, js: click("#add-button"), delay: 1.2),
            Step(name: nil, js: "[...document.querySelectorAll('#add-menu [role=menuitem]')].find(function (b) { return / E$/.test(b.textContent); }).click();",
                 event: "run.finished", delay: 1.0),
            Step(name: nil, js: click("#finished-songs"), delay: 1.0),
            Step(name: nil, js: click("#more-button"), delay: 0.6),
            Step(name: nil, js: menuText("more-menu", "Look up songs via MusicBrainz"), delay: 1.0),
            Step(name: "l15-sentence-disc", js: scope("disc:"), delay: 1.2),
            Step(name: "l16-disc-not-known", js: click("#lookup-go"), event: "lookup.finished", delay: 1.0),
        ]
    }

    /// The run screen (D37): the run from the first screen to the finished one, with a picture at a few song counts
    /// (`DECKIE_TOUR_SONGS`, the songs in `--music`, sets them), then a line of the wall pointed at and one chosen with
    /// the keyboard.
    static func runScreenSteps(_ click: (String) -> String) -> [Step] {
        let total = ProcessInfo.processInfo.environment["DECKIE_TOUR_SONGS"].flatMap(Int.init) ?? 30
        let done = { (n: Int) -> ([String: Any]) -> Bool in
            { $0["event"] as? String == "run.progress" && (($0["done"] as? NSNumber)?.intValue ?? 0) >= n }
        }
        var steps = [Step(name: "r01-first-screen", delay: 1.5), Step(name: nil, js: click("#add-button"), delay: 0.8),
                     Step(name: "r02-first-song", js: "[...document.querySelectorAll('#add-menu [role=menuitem]')].pop().click();",
                          event: "run.progress", eventTest: done(1), delay: 1.0)]
        var seen = Set<Int>()
        for (i, n) in [3, total / 4, total / 2, total * 3 / 4, total * 9 / 10].enumerated() where n > 0 && seen.insert(n).inserted {
            steps.append(Step(name: "r0\(i + 3)-\(n)-songs", event: "run.progress", eventTest: done(n), delay: 1.2))
        }
        steps.append(Step(name: "r08-finished", event: "run.finished", delay: 2.4))
        steps.append(Step(name: "r09-wall-pointed", js: """
            var c = document.getElementById('done-wall'), r = c.getBoundingClientRect();
            c.dispatchEvent(new MouseEvent('mousemove', { clientX: r.left + r.width * 0.3, clientY: r.top + r.height * 0.42, bubbles: true }));
            """, delay: 0.8))
        steps.append(Step(name: "r10-wall-keyboard", js: """
            var c = document.getElementById('done-wall'); c.focus();
            c.dispatchEvent(new KeyboardEvent('keydown', { key: 'End', bubbles: true }));
            c.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true }));
            """, delay: 0.8))
        return steps
    }

    /// With `--record`: a picture of the window every half second from the moment a run starts until a few seconds
    /// after it finishes, numbered in order, for a short film of the run screen (ffmpeg makes one from them).
    static func record(_ desk: Desk, out: URL) {
        #if os(macOS)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let lock = NSLock()
        var started = false, finishedAt: Date?
        desk.watchers.append { line in
            lock.lock(); defer { lock.unlock() }
            if line.contains("\"event\":\"run.started\"") { started = true }
            if line.contains("\"event\":\"run.finished\"") { finishedAt = Date() }
        }
        Thread.detachNewThread {
            var frame = 0
            while true {
                Thread.sleep(forTimeInterval: 0.5)
                lock.lock(); let go = started, end = finishedAt; lock.unlock()
                if let end, Date().timeIntervalSince(end) > 4 { return }
                guard go else { continue }
                frame += 1
                let url = out.appendingPathComponent(String(format: "%05d.png", frame))
                let wait = DispatchSemaphore(value: 0)
                desk.window.onWindowThread { snapshot(desk, to: url) { _ in wait.signal() } }
                wait.wait()
            }
        }
        #endif
    }

    static func js(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: d, as: UTF8.self).dropFirst().dropLast())
    }

    #if os(macOS)
    static func snapshot(_ desk: Desk, to url: URL, done: @escaping (Bool) -> Void) {
        guard let p = desk.window.nativeView else { done(false); return }
        let view = Unmanaged<WKWebView>.fromOpaque(p).takeUnretainedValue()
        view.takeSnapshot(with: nil) { image, _ in
            guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { done(false); return }
            done((try? png.write(to: url)) != nil)
        }
    }
    #endif
}
