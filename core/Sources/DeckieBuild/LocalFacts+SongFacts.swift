import Foundation
import DeckieCrate

/// A song's facts already on the computer (D34): what its file's tags say (`FileFacts`), and what the DJ programs'
/// libraries hold about it beyond its name and key. Part of the same gathering as the keys and names (D30), with the
/// same rules: nothing leaves the computer, every file and library is only read, and a file that is not here keeps
/// the facts its tags gave last time.
extension LocalFacts {
    /// Puts each entry's facts into `crate`: its file's tags when the file is here (replacing the facts its tags gave
    /// before, and `file.other_tags`), then each library read that has the song, the most recently written first
    /// (replacing what that program gave before). A fact the DJ gave, or one from a source that ranks higher
    /// (`SongFacts.rank`), is kept. Returns how many songs have facts from each origin.
    @discardableResult
    public static func gatherFacts(_ crate: inout Crate, files: [String: [FileRef]], libraries: [DJLibrary],
                                   fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) })
        -> [String: Int] {
        var newest: [DJProgram: DJLibrary] = [:]
        for lib in libraries {
            if let have = newest[lib.program], (have.written ?? .distantPast) >= (lib.written ?? .distantPast) { continue }
            newest[lib.program] = lib
        }
        let libs = newest.values.sorted {
            let a = $0.written ?? .distantPast, b = $1.written ?? .distantPast
            return a != b ? a > b : $0.program.tieOrder < $1.program.tieOrder
        }
        let readNow = Set(libs.map(\.program.rawValue))
        let matcher = DJLibraryMatcher(libs)
        var from: [String: Int] = [:]
        for i in crate.tracks.indices {
            var t = crate.tracks[i]
            let refs = files[t.id] ?? []
            if let present = refs.first(where: { fileExists($0.url) }) {
                FileFacts.read(present.url).apply(to: &t)
            }
            t.ident.dropFacts { readNow.contains($0) }
            let matches = matcher.match(paths: refs.map { PathKey.slashes($0.url.path) }, rels: refs.map(\.rel), size: t.file.bytes)
            for (li, e) in matches {
                for (name, values) in e.facts { t.ident.offer(name, .init(values, from: libs[li].program.rawValue)) }
            }
            for o in Set(t.ident.facts.values.map(\.from)) { from[o, default: 0] += 1 }
            crate.tracks[i] = t
        }
        return from
    }
}
