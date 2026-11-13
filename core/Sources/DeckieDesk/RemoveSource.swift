import Foundation
import DeckieCrate

extension Crate {
    /// Whether a place is on `source` (nil: the music folder, a place with no source).
    static func isOn(_ p: CrateTrack.Place, _ source: String?) -> Bool { p.disc == source }

    /// The entries that would leave the crate if `source` were removed (nil: the music folder): those with no place
    /// anywhere else. This is the count the confirmation says.
    public func entriesOnlyOn(source: String?) -> [String] {
        tracks.filter { t in t.ident.allPlaces.allSatisfy { Crate.isOn($0, source) } }.map(\.id)
    }

    /// Takes a source (or the music folder, nil) out of the crate, which is how music that was added is taken back:
    /// every place on it goes; an entry with no place left leaves the crate; an entry whose own place was on it and
    /// that is somewhere else takes its leading other place as its own (`promoteOtherPlace`; its `file.rel` is then
    /// unknown until a desk fills it, `PlacePaths.fillMissingPaths`). The import log forgets that source's files.
    /// Returns the ids that left.
    @discardableResult
    public mutating func removeSource(_ source: String?) -> [String] {
        let leaving = Set(entriesOnlyOn(source: source))
        tracks.removeAll { leaving.contains($0.id) }
        for i in tracks.indices {
            tracks[i].ident.otherPlaces.removeAll { Crate.isOn($0, source) }
            if Crate.isOn(tracks[i].ident.ownPlace, source) {
                tracks[i].ident.disc = nil; tracks[i].ident.folder = nil; tracks[i].ident.track = nil
                tracks[i].promoteOtherPlace()
            }
        }
        if var log = manifest.importLog {
            let sources = Set(tracks.flatMap { $0.ident.allPlaces.compactMap(\.disc) })
            log.entries.removeAll { e in
                if let source { return e.rel.hasPrefix(source + "/") }
                // The music folder's files are logged by their path, with no source's name first.
                return !sources.contains { e.rel.hasPrefix($0 + "/") }
            }
            log.tracks = tracks.count
            manifest.importLog = log
        }
        return Array(leaving)
    }
}
