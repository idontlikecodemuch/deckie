import Foundation
import DeckieCrate
import DeckieBuild
import DeckieDesk

/// Desk's own crates (D28) without the window, in the storage the window uses (`DECKIE_DESK_HOME` moves it). For
/// checks, timings and runs from a terminal; the window does the same through DeskModel.
///
///   --crates                                   lists the crates, the most recent first
///   --add-music <folder or drive> [crate] [jobs]   the one run: into that crate (made if missing), else the most
///                                              recent, else a new crate named after what is read
///   --carry-on [crate]                         carries on a run that stopped
///   --show [crate]                             lists the songs: title, places, signature, copies
///   --locate [crate]                           where each song's file is found now, trying every place
///   --fix <crate> <id or title> <field> <value>   a name fix (title, artist, version), kept across reads
///   --remove-source <crate> <source>           takes a source out of the crate ("-" for the music folder)
///   --rename-crate <crate> <new name>          renames a crate
///   --delete-crate <crate>                     deletes a crate for good
///   --export <crate> <out.deckiecrate>         writes a copy of its crate file
///   --import <file.deckiecrate>                brings a crate file in as a copy
/// Words printed here are for the person at the terminal, not the DJ's screen, so they are not in Words.swift.
enum HeadlessDesk {
    static func runIfAsked() {
        let a = CommandLine.arguments
        guard a.count >= 2, a[1].hasPrefix("--") else { return }
        let modes = ["--crates", "--add-music", "--carry-on", "--show", "--locate", "--fix", "--remove-source",
                     "--rename-crate", "--delete-crate", "--export", "--import"]
        guard modes.contains(a[1]) else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        let home = DeskHome.standard()
        print("desk home: \(home.root.path)")
        do {
            try home.prepare()
            try run(a[1], Array(a.dropFirst(2)), home)
            exit(0)
        } catch {
            print("failed: \(error)")
            exit(1)
        }
    }

    static func crate(_ name: String?, _ home: DeskHome) throws -> CrateInfo {
        if let name { if let c = home.shelf.named(name) { return c } else { throw DeskError("no crate named \(name)") } }
        guard let c = home.shelf.mostRecent else { throw DeskError("no crates yet") }
        return c
    }

    static func load(_ info: CrateInfo, _ home: DeskHome) throws -> Crate { try CrateReader.read(from: home.shelf.package(info.id)) }

    static func run(_ mode: String, _ args: [String], _ home: DeskHome) throws {
        let shelf = home.shelf
        switch mode {
        case "--crates":
            for c in shelf.list() {
                let n = (try? load(c, home))?.tracks.count ?? 0
                print("\(c.name)\t\(n) songs\t\(c.id)" + (DeskRun.pending(home: home, crateId: c.id) == nil ? "" : "\t(stopped run)"))
            }

        case "--add-music", "--carry-on":
            var request: RunRequest
            var info: CrateInfo
            let jobs: Int
            if mode == "--carry-on" {
                info = try crate(args.first, home)
                guard let p = DeskRun.pending(home: home, crateId: info.id) else { throw DeskError("\(info.name) has no stopped run") }
                request = p
                jobs = 2
            } else {
                guard let path = args.first else { throw DeskError("--add-music <folder or drive> [crate] [jobs]") }
                let url = URL(fileURLWithPath: path).standardizedFileURL
                let name = MountedSource.name(of: url)
                if args.count >= 2, !args[1].isEmpty {
                    info = try shelf.named(args[1]) ?? shelf.make(name: args[1])
                } else {
                    info = try shelf.mostRecent ?? shelf.make(name: name)
                }
                request = RunRequest(folder: url, source: SourceNaming.unique(name, root: url, roots: info.roots))
                jobs = args.count >= 3 ? Int(args[2]) ?? 2 : 2
            }
            print("adding \(request.name) to \(info.name), \(jobs) at a time")
            let run = DeskRun(home: home, crateId: info.id, request: request, jobs: jobs, device: Device.modelLabel(),
                              signer: { try Signatures.signature(of: $0) }, printer: { try Signatures.recordingPrint(of: $0) })
            let lastPrinted = Locked(0.0)
            let (crate, r) = try run.run { p in
                if case let .file(rel, outcome)? = p.line { print("  \(rel)  \(outcome)") }
                let now = Date().timeIntervalSince1970
                if now - lastPrinted.value > 1 || p.done == p.total {
                    lastPrinted.value = now
                    print("[\(p.stage.rawValue)] \(p.done) of \(p.total)" + (p.remaining.map { String(format: ", about %.0f s left", $0) } ?? ""))
                }
            }
            print("done: \(r.read) into \(r.crate): \(r.songsSeen) seen, \(r.wentIn) went in, \(r.notInCount) didn't \(r.notIn)")
            print(String(format: "took %.1f s (build %.1f s, finishing %.1f s), %.1f songs a minute", r.seconds, r.buildSeconds,
                         r.finishSeconds, r.songsPerMinute))
            print("analysed \(r.analysed), reused \(r.reused); signatures made \(r.signaturesMade), kept \(r.signaturesKept), failed \(r.signaturesFailed); prints made \(r.printsMade), kept \(r.printsKept), failed \(r.printsFailed); copies \(r.copies); \(crate.tracks.count) songs in the crate" + (r.carriedOn ? "; carried on a stopped run" : ""))

        case "--show":
            let info = try crate(args.first, home)
            let c = try load(info, home)
            print("\(info.name): \(c.tracks.count) songs")
            for t in c.tracks.sorted(by: { $0.ident.title < $1.ident.title }) {
                let places = t.placesInOrder.map { Crate.placeLine($0) ?? ("folder " + ($0.folder ?? "")) }.joined(separator: " · ")
                print("  \(t.id)  \(t.ident.title)" + (t.ident.artist.map { " — \($0)" } ?? "") + "  [\(places)]"
                      + "  rel=\(t.file.rel ?? "nil")" + (t.signatures["o"] == nil ? "  no signature" : "  signed")
                      + (t.ident.cutKey.map { "  copy of \($0)" } ?? "") + (t.ident.source == "user" ? "  (fixed)" : ""))
            }

        case "--locate":
            let info = try crate(args.first, home)
            let c = try load(info, home)
            let paths = PlacePaths.load(from: shelf.file(DeskRun.placesFile, of: info.id))
            for t in c.tracks.sorted(by: { $0.ident.title < $1.ident.title }) {
                let all = paths.candidates(for: t, roots: info.roots, musicFolder: info.musicFolderURL)
                let found = paths.locate(t, roots: info.roots, musicFolder: info.musicFolderURL)
                print("  \(t.ident.title): \(found?.path ?? "not found") (\(all.count) places known)")
            }

        case "--fix":
            guard args.count >= 4 else { throw DeskError("--fix <crate> <id or title> <field> <value>") }
            let info = try crate(args[0], home)
            var c = try load(info, home)
            guard let i = c.tracks.firstIndex(where: { $0.id == args[1] || $0.ident.title == args[1] }) else {
                throw DeskError("no song \(args[1])")
            }
            let before = c.tracks[i]
            switch args[2] {
            case "title": c.tracks[i].ident.title = args[3]
            case "artist": c.tracks[i].ident.artist = args[3].isEmpty ? nil : args[3]
            case "version": c.tracks[i].ident.version = args[3].isEmpty ? nil : args[3]
            default: throw DeskError("field is title, artist or version")
            }
            c.tracks[i].ident.source = "user"
            let url = shelf.file(DeskRun.correctionsFile, of: info.id)
            var fixes = NameCorrections.load(from: url)
            fixes.note(before: before, after: c.tracks[i])
            try CrateWriter.write(c, to: shelf.package(info.id))
            try fixes.save(to: url)
            print("fixed \(args[2]) of \(before.ident.title): \(args[3])")

        case "--remove-source":
            guard args.count >= 2 else { throw DeskError("--remove-source <crate> <source, or - for the music folder>") }
            var info = try crate(args[0], home)
            var c = try load(info, home)
            let source: String? = args[1] == "-" ? nil : args[1]
            let gone = c.removeSource(source)
            let url = shelf.file(DeskRun.placesFile, of: info.id)
            var paths = PlacePaths.load(from: url)
            paths.forget(source: source)
            paths.fillMissingPaths(&c)
            if let source { info.sourceRoots[source] = nil } else { info.musicFolder = nil }
            try CrateWriter.write(c, to: shelf.package(info.id))
            try paths.save(to: url)
            try shelf.save(info)
            print("removed \(args[1]): \(gone.count) songs left the crate, \(c.tracks.count) stay")

        case "--rename-crate":
            guard args.count >= 2 else { throw DeskError("--rename-crate <crate> <new name>") }
            let i = try shelf.rename(try crate(args[0], home).id, to: args[1])
            print("renamed to \(i.name)")

        case "--delete-crate":
            let info = try crate(args.first, home)
            try shelf.delete(info.id)
            print("deleted \(info.name)")

        case "--export":
            guard args.count >= 2 else { throw DeskError("--export <crate> <out.deckiecrate>") }
            let info = try crate(args[0], home)
            try shelf.exportCopy(info.id, to: URL(fileURLWithPath: args[1]))
            print("wrote \(args[1])")

        case "--import":
            guard let path = args.first else { throw DeskError("--import <file.deckiecrate>") }
            let i = try shelf.importCopy(of: URL(fileURLWithPath: path))
            print("imported as \(i.name) (\(i.id))")

        default: break
        }
    }
}

/// A value shared with the run's progress callback.
final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return v }
        set { lock.lock(); v = newValue; lock.unlock() }
    }
}
