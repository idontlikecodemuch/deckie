import DeckieCrate

/// One file read in a build: the place it is at (`ident`'s source, folder and number, or no source and its folder) and
/// its path below the folder read, or below the source's top for a source (`BuildResult.placesRead`).
public struct ReadPlace: Codable, Hashable, Sendable {
    public var place: CrateTrack.Place
    public var rel: String
    public init(place: CrateTrack.Place, rel: String) { self.place = place; self.rel = rel }
}
