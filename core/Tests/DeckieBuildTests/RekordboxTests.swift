import Foundation
import Testing
import DeckieBuild
import DeckieCrate

/// A hand-made rekordbox collection export in the documented format: three tracks, one with a grid of two markers,
/// a memory cue, two hot cues and a loop; Locations percent-encoded as rekordbox writes them (spaces as %20, accents as
/// UTF-8 escapes) and an ampersand escaped for XML; a folder holding a playlist that names tracks by TrackID and a
/// playlist that names them by Location.
let sampleRekordboxXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!-- exported by hand for the tests -->
    <DJ_PLAYLISTS Version="1.0.0">
      <PRODUCT Name="rekordbox" Version="6.8.5" Company="AlphaTheta"/>
      <COLLECTION Entries="3">
        <TRACK TrackID="101" Name="Track One" Artist="The Synths" Composer="" Album="" Grouping="" Genre="House"
               Kind="WAV File" Size="11186980" TotalTime="63" DiscNumber="0" TrackNumber="0" Year="0" AverageBpm="124.00"
               DateAdded="2026-10-28" BitRate="2822" SampleRate="44100" Comments="" PlayCount="0" Rating="0"
               Location="file://localhost/Users/dj/Music/Deckie%20Test/CD1/Track%20One.wav" Remixer="" Tonality="Am"
               Label="" Mix="Extended Mix">
          <TEMPO Inizio="0.500" Bpm="124.00" Metro="4/4" Battito="1"/>
          <TEMPO Inizio="31.468" Bpm="124.00" Metro="4/4" Battito="1"/>
          <POSITION_MARK Name="" Type="0" Start="0.500" Num="-1"/>
          <POSITION_MARK Name="Drop" Type="0" Start="16.629" Num="0" Red="40" Green="226" Blue="20"/>
          <POSITION_MARK Name="Outro" Type="0" Start="47.597" Num="2"/>
          <POSITION_MARK Name="Loop" Type="4" Start="8.242" End="16.000" Num="-1"/>
        </TRACK>
        <TRACK TrackID="102" Name="Caf&#233; &amp; Bar" Artist="Andr&#xE9;" Size="1000" TotalTime="200"
               AverageBpm="0.00" Tonality="8A"
               Location="file://localhost/Users/dj/Music/Deckie%20Test/CD2/Caf%C3%A9%20%26%20Bar.mp3"/>
        <TRACK TrackID="103" Name="Elsewhere" Artist="" Size="4321" AverageBpm="98.50" Tonality="1m"
               Location="file://localhost/C:/Music/Other/elsewhere.flac"/>
      </COLLECTION>
      <PLAYLISTS>
        <NODE Type="0" Name="ROOT" Count="2">
          <NODE Type="0" Name="Gigs" Count="1">
            <NODE Name="Halloween" Type="1" KeyType="0" Entries="2">
              <TRACK Key="101"/>
              <TRACK Key="102"/>
            </NODE>
          </NODE>
          <NODE Name="By location" Type="1" KeyType="1" Entries="1">
            <TRACK Key="file://localhost/Users/dj/Music/Deckie%20Test/CD1/Track%20One.wav"/>
          </NODE>
        </NODE>
      </PLAYLISTS>
    </DJ_PLAYLISTS>
    """

@Suite struct RekordboxTests {
    @Test func readsTheCollection() throws {
        let c = try RekordboxCollection.parse(Data(sampleRekordboxXML.utf8))
        #expect(c.product == "rekordbox 6.8.5")
        #expect(c.tracks.map(\.trackID) == ["101", "102", "103"])
        let one = c.tracks[0]
        #expect(one.name == "Track One" && one.artist == "The Synths" && one.mix == "Extended Mix")
        #expect(one.path == "/Users/dj/Music/Deckie Test/CD1/Track One.wav")
        #expect(one.averageBpm == 124 && one.tonality == "Am" && one.size == 11186980 && one.totalTime == 63)
        #expect(one.tempos == [.init(inizio: 0.5, bpm: 124, metro: "4/4", battito: 1),
                               .init(inizio: 31.468, bpm: 124, metro: "4/4", battito: 1)])
        #expect(one.marks.count == 4 && one.marks[3] == .init(name: "Loop", type: 4, start: 8.242, end: 16, num: -1))
        // Entities in attributes, percent-encoded UTF-8 and an encoded ampersand in the Location.
        let two = c.tracks[1]
        #expect(two.name == "Café & Bar" && two.artist == "André")
        #expect(two.path == "/Users/dj/Music/Deckie Test/CD2/Café & Bar.mp3")
        #expect(two.averageBpm == nil)  // 0.00 is no tempo
        #expect(c.tracks[2].path == "C:/Music/Other/elsewhere.flac")  // a Windows location
        // Playlists: folder path without the root, by TrackID and by Location.
        #expect(c.playlists == [.init(path: ["Gigs", "Halloween"], trackIDs: ["101", "102"]),
                                .init(path: ["By location"], trackIDs: ["101"])])
        #expect(c.playlists(holding: "101") == [["Gigs", "Halloween"], ["By location"]])
    }

    @Test func tonalityInEveryNotation() {
        let cases: [(String, String?)] = [("Am", "8A"), ("C", "8B"), ("F#m", "11A"), ("Gbm", "11A"), ("Db", "3B"),
                                          ("Ebmin", "2A"), ("B♭", "6B"), ("8A", "8A"), ("08B", "8B"), ("12A", "12A"),
                                          ("1m", "8A"), ("1d", "8B"), ("6d", "1B"), ("12m", "7A"), ("", nil),
                                          ("13A", nil), ("H", nil), ("Am7", nil)]
        for (t, want) in cases { #expect(RekordboxCollection.camelot(fromTonality: t) == want, "\(t)") }
    }

    @Test func locations() {
        #expect(RekordboxCollection.path(fromLocation: "file://localhost/Users/dj/My%20Music/a%2Bb.mp3")
                == "/Users/dj/My Music/a+b.mp3")
        #expect(RekordboxCollection.path(fromLocation: "file:///home/dj/x.flac") == "/home/dj/x.flac")
        #expect(RekordboxCollection.path(fromLocation: "file://localhost/D:/DJ/x%C3%BC.wav") == "D:/DJ/xü.wav")
        #expect(RekordboxCollection.path(fromLocation: "http://example.com/x.mp3") == nil)
    }

    @Test func matchesFilesByPathSuffixOrNameAndSize() throws {
        let m = RekordboxMatcher(try RekordboxCollection.parse(Data(sampleRekordboxXML.utf8)))
        // The same path.
        #expect(m.match(absolutePath: "/Users/dj/Music/Deckie Test/CD1/Track One.wav", rel: "CD1/Track One.wav",
                        size: nil)?.trackID == "101")
        // Built on another machine: the path below the folder is the end of the export's path. Accents in either
        // Unicode form.
        #expect(m.match(absolutePath: "/mnt/usb/music/CD2/Cafe\u{301} & Bar.mp3", rel: "CD2/Cafe\u{301} & Bar.mp3",
                        size: 5)?.trackID == "102")
        // Moved to another folder: the one entry with that name and size.
        #expect(m.match(absolutePath: "/x/elsewhere.flac", rel: "moved/elsewhere.flac", size: 4321)?.trackID == "103")
        #expect(m.match(absolutePath: "/x/elsewhere.flac", rel: "moved/elsewhere.flac", size: 99) == nil)
        #expect(m.match(absolutePath: "/x/unknown.mp3", rel: "unknown.mp3", size: 1) == nil)
    }

    @Test func whatATrackContributesToTheCrate() throws {
        let c = try RekordboxCollection.parse(Data(sampleRekordboxXML.utf8))
        let block = c.crateBlock(for: c.tracks[0])
        #expect(block.trackId == "101" && block.bpm == 124 && block.tonality == "Am")
        #expect(block.grid == [.init(startS: 0.5, bpm: 124, meter: "4/4", beatInBar: 1),
                               .init(startS: 31.468, bpm: 124, meter: "4/4", beatInBar: 1)])
        #expect(block.cues == [.init(name: "", kind: "cue", hotCue: nil, startS: 0.5, endS: nil),
                               .init(name: "Drop", kind: "cue", hotCue: 0, startS: 16.629, endS: nil),
                               .init(name: "Outro", kind: "cue", hotCue: 2, startS: 47.597, endS: nil),
                               .init(name: "Loop", kind: "loop", hotCue: nil, startS: 8.242, endS: 16)])
        #expect(block.playlists == [["Gigs", "Halloween"], ["By location"]])
    }

    @Test func refusesWhatIsNotAnExport() {
        #expect(throws: (any Error).self) { try RekordboxCollection.parse(Data("<html><body></body></html>".utf8)) }
        #expect(throws: (any Error).self) { try RekordboxCollection.parse(Data("<DJ_PLAYLISTS><COLLECTION>".utf8)) }
    }
}
