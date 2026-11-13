import Foundation
import Testing
import DeckieCrate

// Other places (D27, `ident.other_places`): the first addition to crate v1. A file found in more than one place is one
// entry (its id is the file's hash) that keeps its own place and lists the others. Proved here: a crate file without
// the field reads as before and keeps its bytes; the field round-trips; a reader that does not know it (the previous
// reader's shape) still opens a file that has it; validation; and the place operations and the same-song order cover
// other places too. Synthetic crates only.

@Suite struct OtherPlacesTests {
    typealias Place = CrateTrack.Place

    /// A crate of entries t0..t(n-1) on no source.
    func crate(_ n: Int) -> Crate {
        var c = sampleCrate()
        let base = c.tracks[1]
        c.tracks = (0..<n).map { i in
            var t = base
            t.id = "t\(i)"; t.ident.title = "Song \(i)"; t.ident.cutKey = nil
            t.ident.disc = nil; t.ident.folder = nil; t.ident.track = nil
            return t
        }
        return c
    }

    func track(_ c: Crate, _ id: String) -> CrateTrack { c.tracks.first { $0.id == id }! }

    // MARK: the format

    @Test func aCrateFileWithoutTheFieldReadsAsBefore() throws {
        // Written without other places: the key is left out, so the bytes are what they were before D27.
        let c = sampleCrate()
        let files = try CrateWriter.encode(c)
        let json = String(decoding: files["crate.json"]!, as: UTF8.self)
        #expect(!json.contains("other_places"))
        let back = try CrateReader.decode(withSignatureFiles(files, c))
        #expect(back == c)
        #expect(back.tracks.allSatisfy { $0.ident.otherPlaces.isEmpty })
        // The committed example crate, written before D27, reads with no other places and writes back byte for byte.
        let example = try CrateReader.read(from: Paths.example)
        #expect(example.tracks.allSatisfy { $0.ident.otherPlaces.isEmpty })
        let again = try CrateWriter.encode(example)
        #expect(again["crate.json"] == (try Data(contentsOf: Paths.example.appendingPathComponent("crate.json"))))
        #expect(example.manifest.minReader == 1)
    }

    @Test func theFieldIsWrittenInIdentAndReadBack() throws {
        var c = sampleCrate()
        c.tracks[0].ident.otherPlaces = [Place(disc: "Stick 3", folder: "House", track: 4),
                                         Place(disc: nil, folder: "Mac/House", track: nil)]
        let files = try CrateWriter.encode(c)
        let json = String(decoding: files["crate.json"]!, as: UTF8.self)
        #expect(json.contains(#""other_places":[{"disc":"Stick 3","folder":"House","track":4},{"disc":null,"folder":"Mac/House","track":null}]"#))
        // Only the record that has other places carries the key.
        #expect(json.components(separatedBy: "other_places").count == 2)
        let back = try CrateReader.decode(withSignatureFiles(files, c))
        #expect(back == c)
        #expect(back.problems().isEmpty)
        // The version is unchanged: a reader of version 1 may open it.
        let manifest = try JSONSerialization.jsonObject(with: files["manifest.json"]!) as! [String: Any]
        #expect(manifest["schema"] as? Int == 1 && manifest["min_reader"] as? Int == 1)
    }

    /// The reader as it was before D27: `ident` decoded with the fields it knew and nothing else (Swift's decoding
    /// ignores keys it does not know, as the format asks of every reader).
    struct PreD27Ident: Decodable, Equatable {
        var title: String
        var artist: String?, version: String?, source: String?, mbid: String?
        var disc: String?, folder: String?, track: Int?
        var cutKey: String?, isLongest: Bool?, era: String?, kind: String?
        var tags: [String]
        enum CodingKeys: String, CodingKey {
            case title, artist, version, source, mbid, disc, folder, track, era, kind, tags
            case cutKey = "cut_key", isLongest = "is_longest"
        }
    }
    struct PreD27Track: Decodable { var id: String; var ident: PreD27Ident }
    struct PreD27Tracks: Decodable { var tracks: [PreD27Track] }

    @Test func theReaderBeforeD27StillReadsAFileThatHasIt() throws {
        var c = sampleCrate()
        c.tracks[0].ident.otherPlaces = [Place(disc: "Stick 3", folder: "House", track: 4)]
        let files = try CrateWriter.encode(c)
        let old = try JSONDecoder().decode(PreD27Tracks.self, from: files["crate.json"]!)
        #expect(old.tracks.map(\.id) == c.tracks.map(\.id))
        // It sees the entry's own place, unchanged.
        let first = try #require(old.tracks.first { $0.id == c.tracks[0].id })
        #expect(first.ident.disc == "CD1" && first.ident.folder == "3 - 120ish" && first.ident.track == 7)
        #expect(first.ident.title == c.tracks[0].ident.title)
    }

    @Test func validationChecksOtherPlaces() {
        var c = sampleCrate()
        c.tracks[0].ident.otherPlaces = [
            Place(disc: nil, folder: nil, track: nil),
            Place(disc: "", folder: "A", track: 1),
            Place(disc: "B", folder: "/Users/x", track: 0),
            Place(disc: "CD1", folder: "3 - 120ish", track: 7),   // the entry's own place
            Place(disc: "S", folder: "F", track: 2),
            Place(disc: "S", folder: "F", track: 2),
        ]
        let p = c.problems().map { "\($0.path): \($0.message)" }
        #expect(p.contains("tracks[0].ident.other_places[0]: has neither a disc nor a folder, so it says no place"))
        #expect(p.contains("tracks[0].ident.other_places[1].disc: is empty"))
        #expect(p.contains { $0.hasPrefix("tracks[0].ident.other_places[2].folder: ") && $0.contains("absolute") })
        #expect(p.contains("tracks[0].ident.other_places[2].track: 0 must be 1 or more"))
        #expect(p.contains("tracks[0].ident.other_places[3]: repeats a place the entry already has"))
        #expect(p.contains("tracks[0].ident.other_places[5]: repeats a place the entry already has"))
        #expect(p.count == 6)
        #expect(throws: (any Error).self) { try CrateWriter.encode(c) }
    }

    // MARK: the place operations

    /// t0 is on "Friday / Set" (own) and on "Stick 3 / House" (other); t1 and t2 are on Stick 3 / House too.
    func twoSources() -> Crate {
        var c = crate(4)
        c.place(["t3", "t0"], disc: "Friday", folder: "Set")
        c.place(["t1", "t2"], disc: "Stick 3", folder: "House")
        c.tracks[0].ident.otherPlaces = [Place(disc: "Stick 3", folder: "House", track: 3)]
        return c
    }

    @Test func thePlanListsASongUnderEveryPlace() {
        let c = twoSources()
        #expect(c.discPlan == [
            DiscPlan(name: "Friday", folders: [FolderPlan(name: "Set", trackIds: ["t3", "t0"])]),
            DiscPlan(name: "Stick 3", folders: [FolderPlan(name: "House", trackIds: ["t1", "t2", "t0"])]),
        ])
        #expect(c.folderPlaces(disc: "Stick 3", folder: "House").map(\.number) == [1, 2, 3])
        #expect(c.folderPlaces(disc: "Friday", folder: "Set").map(\.number) == [1, 2])
        #expect(Crate.placeLine(Place(disc: "Stick 3", folder: "House", track: 3)) == "Stick 3 / House 3")
    }

    @Test func reorderWorksOnAnOtherPlace() {
        var c = twoSources()
        c.move("t0", inDisc: "Stick 3", folder: "House", to: 0)
        #expect(c.trackIds(disc: "Stick 3", folder: "House") == ["t0", "t1", "t2"])
        #expect(track(c, "t0").ident.otherPlaces == [Place(disc: "Stick 3", folder: "House", track: 1)])
        // Its own place did not move.
        #expect(track(c, "t0").ident.ownPlace == Place(disc: "Friday", folder: "Set", track: 2))
        #expect(c.trackIds(disc: "Friday", folder: "Set") == ["t3", "t0"])
        // The plain move is its own place's.
        c.move("t0", to: 0)
        #expect(c.trackIds(disc: "Friday", folder: "Set") == ["t0", "t3"])
        #expect(c.trackIds(disc: "Stick 3", folder: "House") == ["t0", "t1", "t2"])
        // No place in that folder: nothing happens.
        let before = c
        c.move("t3", inDisc: "Stick 3", folder: "House", to: 0)
        #expect(c == before)
    }

    @Test func renameWorksOnOtherPlaces() {
        var c = twoSources()
        c.renameDisc("Stick 3", to: "Stick 4")
        #expect(track(c, "t0").ident.otherPlaces == [Place(disc: "Stick 4", folder: "House", track: 3)])
        c.renameFolder("House", inDisc: "Stick 4", to: "Deep")
        #expect(track(c, "t0").ident.otherPlaces == [Place(disc: "Stick 4", folder: "Deep", track: 3)])
        #expect(c.trackIds(disc: "Stick 4", folder: "Deep") == ["t1", "t2", "t0"])
        // Renaming onto the other source joins the folders of the same name, that source's songs first: the entry is
        // then in that folder twice, as two files with the same bytes in one folder are, each with its number.
        c.renameFolder("Deep", inDisc: "Stick 4", to: "Set")
        c.renameDisc("Stick 4", to: "Friday")
        #expect(c.trackIds(disc: "Friday", folder: "Set") == ["t3", "t0", "t1", "t2", "t0"])
        #expect(c.folderPlaces(disc: "Friday", folder: "Set").map(\.number) == [1, 2, 3, 4, 5])
        #expect(track(c, "t0").ident.otherPlaces == [Place(disc: "Friday", folder: "Set", track: 5)])
        #expect(c.problems().isEmpty)
        // A rename that makes two places of one entry the same keeps it once.
        var d = crate(1)
        d.tracks[0].ident.ownPlace = Place(disc: "A", folder: "F", track: 1)
        d.tracks[0].ident.otherPlaces = [Place(disc: "B", folder: "F", track: 1)]
        d.renameDisc("B", to: "A")
        #expect(d.tracks[0].ident.otherPlaces.count <= 1)
        #expect(d.problems().isEmpty)
    }

    @Test func deletingTheOwnPlacesSourcePromotesAnOtherPlace() {
        var c = twoSources()
        c.tracks[0].ident.otherPlaces.append(Place(disc: nil, folder: "Mac", track: nil))
        c.deleteDisc("Friday")
        let t0 = track(c, "t0")
        #expect(t0.ident.ownPlace == Place(disc: "Stick 3", folder: "House", track: 3))
        #expect(t0.ident.otherPlaces == [Place(disc: nil, folder: "Mac", track: nil)])
        #expect(t0.file.rel == nil)   // the path was the Friday file's
        #expect(c.problems().isEmpty)
        // Taken off every source: the place with no source stays an other place.
        c.remove(["t0"])
        #expect(track(c, "t0").ident.ownPlace == Place(disc: nil, folder: nil, track: nil))
        #expect(track(c, "t0").ident.otherPlaces == [Place(disc: nil, folder: "Mac", track: nil)])
        #expect(c.trackIds(disc: "Stick 3", folder: "House") == ["t1", "t2"])
    }

    @Test func theLeadingPlaceIsTheFirstSourceByNameAndNoSourceLast() {
        let ps = [Place(disc: nil, folder: "Mac", track: nil), Place(disc: "Stick 3", folder: "Peak", track: 1),
                  Place(disc: "Stick 3", folder: "House", track: 2), Place(disc: "Friday", folder: "Set", track: 9)]
        #expect(CrateTrack.leadingPlace(ps) == Place(disc: "Friday", folder: "Set", track: 9))
        #expect(CrateTrack.leadingPlace(Array(ps.prefix(3))) == Place(disc: "Stick 3", folder: "House", track: 2))
        #expect(CrateTrack.leadingPlace([ps[0]]) == ps[0])
        #expect(CrateTrack.leadingPlace([]) == nil)
    }

    // MARK: the same song

    /// A song's places are its entries' own and other places, and its copies', ordered together by one rule.
    @Test func songPlacesTakeOwnOtherAndCopiesTogether() {
        var c = crate(3)
        c.tracks[0].ident.ownPlace = Place(disc: "Stick 3", folder: "House", track: 4)
        c.tracks[0].ident.otherPlaces = [Place(disc: "Friday", folder: "Set", track: 2), Place(disc: nil, folder: "Mac", track: nil)]
        c.tracks[0].ident.cutKey = "k"
        c.tracks[1].ident.ownPlace = Place(disc: "Saturday", folder: "", track: 1)   // a copy in another format
        c.tracks[1].ident.cutKey = "k"
        func line(_ ps: [SameSong.Place]) -> [String] { ps.map { "\($0.id) \($0.disc ?? "-")" } }
        // The DJ's order Saturday, Stick 3, Friday; nothing playing: Saturday leads.
        #expect(line(c.songPlaces(of: "t0", playingDisc: nil, discOrder: ["Saturday", "Stick 3", "Friday"]))
                == ["t1 Saturday", "t0 Stick 3", "t0 Friday", "t0 -"])
        // Playing from Friday: Friday leads, from an other place of t0.
        #expect(line(c.songPlaces(of: "t1", playingDisc: "Friday", discOrder: ["Saturday", "Stick 3", "Friday"]))
                == ["t0 Friday", "t1 Saturday", "t0 Stick 3", "t0 -"])
        // A song on its own with other places only.
        c.tracks[2].ident.ownPlace = Place(disc: "Stick 3", folder: "Peak", track: 1)
        c.tracks[2].ident.otherPlaces = [Place(disc: "Friday", folder: "Set", track: 1)]
        #expect(line(c.songPlaces(of: "t2", playingDisc: nil, discOrder: ["Friday", "Stick 3"])) == ["t2 Friday", "t2 Stick 3"])
        #expect(c.songPlaces(of: "nope", playingDisc: nil, discOrder: []).isEmpty)
    }

    @Test func scoringSeesASongOnASourceWhenAnyPlaceIs() {
        var t = sampleCrate().tracks[0]
        t.ident.ownPlace = Place(disc: nil, folder: nil, track: nil)
        t.ident.otherPlaces = [Place(disc: "Stick 3", folder: "House", track: 1)]
        let s = try! #require(t.scoringTrack())
        #expect(s.onDisc && s.disc == "Stick 3")
    }
}
