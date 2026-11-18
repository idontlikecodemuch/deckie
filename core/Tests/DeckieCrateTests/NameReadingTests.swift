import Testing
@testable import DeckieCrate

/// D39: a song's name read the way a DJ means it (research AC, sections 2 and 5.5). Every name here is invented
/// (Marlo Dune, Kaya Venn, Tessa Ray and DJ Ostro are not real artists), in every style letter AC's section 2 lists.
@Suite struct NameReadingTests {
    struct Want {
        var artist: String? = nil
        var title: String
        var version: String? = nil
        var kinds: [VersionKind] = []
        var names: [String] = []
        var lyrics: Lyrics? = nil
        var number: String? = nil
        var first: String? = nil
        var featured: String? = nil
        var release: String? = nil
        var key: String? = nil
        var mark: String? = nil
        var notes: [String] = []
        var swapped = false
    }

    /// File names, by where they came from (AC 2.1 and 2.2).
    static let fileNames: [(String, Want)] = [
        // A record pool.
        ("Marlo Dune ft. Kaya Venn - Night Drive (Intro - Dirty)",
         Want(artist: "Marlo Dune ft. Kaya Venn", title: "Night Drive", version: "Intro - Dirty", kinds: [.intro], lyrics: .dirty, first: "Marlo Dune")),
        ("Marlo Dune - Night Drive (Intro - Clean)", Want(artist: "Marlo Dune", title: "Night Drive", version: "Intro - Clean", kinds: [.intro], lyrics: .clean)),
        // A pool's or seller's own edits, short forms.
        ("Tessa Ray - Lights Down (DJ Ostro Acap Out QH) (Clean)",
         Want(artist: "Tessa Ray", title: "Lights Down", version: "DJ Ostro Acap Out QH Clean", kinds: [.acapOut, .short], names: ["dj ostro"], lyrics: .clean)),
        ("Tessa Ray - Lights Down (Short Edit) (Dirty)", Want(artist: "Tessa Ray", title: "Lights Down", kinds: [.short], lyrics: .dirty)),
        ("Tessa Ray - Lights Down (Quick Hit) (Clean)", Want(artist: "Tessa Ray", title: "Lights Down", kinds: [.short], lyrics: .clean)),
        // A transition.
        ("Marlo Dune - Night Drive (Transition 100-128) (Dirty)",
         Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.transition], lyrics: .dirty)),
        // Beatport's old default: number, title and mix name with underscores, no artist.
        ("12345678_Night_Drive_Extended_Mix", Want(title: "12345678 Night Drive Extended Mix")),
        // Apple's Music app.
        ("1-07 Night Drive", Want(title: "Night Drive", number: "1-07")),
        ("07 Night Drive", Want(title: "Night Drive", number: "07")),
        // Bandcamp.
        ("Tessa Ray - Lights Down EP - 02 Lights Down (Dub)",
         Want(artist: "Tessa Ray", title: "Lights Down", kinds: [.dub], number: "02", release: "Lights Down EP")),
        // A ripped compilation.
        ("07. Marlo Dune - Night Drive", Want(artist: "Marlo Dune", title: "Night Drive", number: "07")),
        ("07 - Marlo Dune - Night Drive", Want(artist: "Marlo Dune", title: "Night Drive", number: "07")),
        ("(307) [Marlo Dune & Kaya Venn] Night Drive (Ostro '07 Remix)",
         Want(artist: "Marlo Dune & Kaya Venn", title: "Night Drive", kinds: [.remix], names: ["ostro"], number: "307", first: "Marlo Dune")),
        ("1.04 Marlo Dune, Kaya Venn - Night Drive", Want(artist: "Marlo Dune, Kaya Venn", title: "Night Drive", number: "1.04", first: "Marlo Dune")),
        // Scene releases.
        ("101-marlo_dune-night_drive_(extended_mix)-grp",
         Want(artist: "marlo dune", title: "night drive", kinds: [.extended], number: "101", notes: ["grp"])),
        // Video and streaming rips.
        ("Marlo Dune - Night Drive (Official Video) [siteName.com]",
         Want(artist: "Marlo Dune", title: "Night Drive", notes: ["(Official Video)", "[siteName.com]"])),
        // A producer's promo.
        ("DJ Ostro - Night Drive (Bootleg) MASTER2", Want(artist: "DJ Ostro", title: "Night Drive", kinds: [.bootleg], notes: ["MASTER2"])),
        // A CD read with no names.
        ("Track 04", Want(title: "Track 04")),
        // A version after a second dash.
        ("Marlo Dune - Night Drive - DJ Ostro Remix",
         Want(artist: "Marlo Dune", title: "Night Drive", version: "DJ Ostro Remix", kinds: [.remix], names: ["dj ostro"])),
        ("Marlo Dune - Night Drive - Dirty", Want(artist: "Marlo Dune", title: "Night Drive", lyrics: .dirty)),
        // Title first, then the artist, with the version in the title's brackets.
        ("04 - Night Drive (Ostro Remix) - Marlo Dune",
         Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.remix], names: ["ostro"], number: "04", swapped: true)),
        // Key and tempo from a key tool.
        ("8A - 128 - Marlo Dune - Night Drive", Want(artist: "Marlo Dune", title: "Night Drive", key: "8A")),
        ("[8A] Marlo Dune - Night Drive", Want(artist: "Marlo Dune", title: "Night Drive", key: "8A")),
        ("Marlo Dune - Night Drive (128.0) (C#)", Want(artist: "Marlo Dune", title: "Night Drive", notes: ["(128.0)", "(C#)"])),
        // A DJ's mark.
        ("* Marlo Dune - Night Drive", Want(artist: "Marlo Dune", title: "Night Drive", mark: "*")),
        // An artist whose name is a number keeps it.
        ("50 Mile - Night Drive", Want(artist: "50 Mile", title: "Night Drive")),
        ("112 - Night Drive", Want(artist: "112", title: "Night Drive")),
        // Spellings of one kind.
        ("Marlo Dune - Night Drive (Extended)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.extended])),
        ("Marlo Dune - Night Drive (12\" Mix)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.extended])),
        ("Marlo Dune - Night Drive (Ostro Rmx)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.remix], names: ["ostro"])),
        ("Marlo Dune - Night Drive (Original Mix)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.plain])),
        ("Marlo Dune - Night Drive (Radio Edit)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.radio])),
        ("Marlo Dune - Night Drive (Ostro Edit)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.djEdit], names: ["ostro"])),
        ("Marlo Dune - Night Drive (Edit)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.radio])),
        ("Marlo Dune - Night Drive (Ostro Vocal Mix)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.remix], names: ["ostro vocal"])),
        ("Marlo Dune - Night Drive (Acapella)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.acapella])),
        ("Marlo Dune - Night Drive (Instrumental)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.instrumental])),
        ("Marlo Dune - Night Drive (Redrum) (Clean)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.redrum], lyrics: .clean)),
        ("Marlo Dune - Night Drive (Live at Harbour Hall)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.live], names: ["harbour hall"])),
        ("Marlo Dune - Night Drive (2011 Remaster)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.remaster])),
        ("Marlo Dune - Night Drive (2011 Version)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.otherTake])),
        ("Marlo Dune - Night Drive (Sped Up)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.altered])),
        ("Marlo Dune - Night Drive (VIP)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.vip])),
        ("Marlo Dune vs Tessa Ray - Night Drive (Mashup)", Want(artist: "Marlo Dune vs Tessa Ray", title: "Night Drive", kinds: [.mashup], first: "Marlo Dune")),
        // Names that hold a version word are names.
        ("Marlo Dune - Night Drive (Dub Pilots Remix)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.remix], names: ["dub pilots"])),
        ("Marlo Dune - Night Drive (Clean Harbour Remix)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.remix], names: ["clean harbour"])),
        ("Marlo Dune - Night Drive (Dirty Coast '07 Remix)", Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.remix], names: ["dirty coast"])),
        // Brackets that are not a version.
        ("Marlo Dune - Night Drive (Part 2)", Want(artist: "Marlo Dune", title: "Night Drive (Part 2)")),
        ("Marlo Dune - Night Drive (feat. Kaya Venn)", Want(artist: "Marlo Dune", title: "Night Drive", featured: "feat. Kaya Venn")),
        ("Marlo Dune - Night Drive (Radio Edit) (feat. Kaya Venn)",
         Want(artist: "Marlo Dune", title: "Night Drive", kinds: [.radio], featured: "feat. Kaya Venn")),
        ("Marlo Dune - Night Drive (Forget the Road)", Want(artist: "Marlo Dune", title: "Night Drive (Forget the Road)")),
        ("Marlo Dune - Night Drive (2019)", Want(artist: "Marlo Dune", title: "Night Drive", notes: ["(2019)"])),
        ("Marlo Dune - Night Drive (Free Download)", Want(artist: "Marlo Dune", title: "Night Drive", notes: ["(Free Download)"])),
        ("Marlo Dune - Night Drive feat. Kaya Venn", Want(artist: "Marlo Dune", title: "Night Drive", featured: "feat. Kaya Venn")),
    ]

    @Test func fileNamesInEveryStyle() {
        for (stem, w) in Self.fileNames {
            let r = NameReading.readFileName(stem)
            #expect(r.written == stem, "\(stem)")
            #expect(r.artist == w.artist, "\(stem): artist \(String(describing: r.artist))")
            #expect(r.title == w.title, "\(stem): title \(r.title)")
            if let v = w.version { #expect(r.version?.written == v, "\(stem): version \(String(describing: r.version?.written))") }
            #expect((r.version?.kinds ?? []) == w.kinds, "\(stem): kinds \(String(describing: r.version?.kinds))")
            if !w.names.isEmpty { #expect(r.version?.names == w.names, "\(stem): names \(String(describing: r.version?.names))") }
            #expect(r.lyrics == w.lyrics, "\(stem): lyrics \(String(describing: r.lyrics))")
            if let n = w.number { #expect(r.number == n, "\(stem): number \(String(describing: r.number))") }
            if let f = w.first { #expect(r.firstArtist == f, "\(stem): first \(String(describing: r.firstArtist))") }
            #expect(r.featured == w.featured, "\(stem): featured \(String(describing: r.featured))")
            if let rel = w.release { #expect(r.release == rel, "\(stem)") }
            #expect(r.key == w.key, "\(stem): key")
            #expect(r.mark == w.mark, "\(stem): mark")
            if !w.notes.isEmpty { #expect(r.notes == w.notes, "\(stem): notes \(r.notes)") }
            #expect(r.swapped == w.swapped, "\(stem): swapped")
        }
    }

    @Test func titleTagsKeepTheirTextAndReadTheVersion() {
        let cases: [(String, String, [VersionKind], Lyrics?)] = [
            ("Night Drive (Extended Mix) (Clean)", "Night Drive", [.extended], .clean),
            ("Night Drive - Extended Mix", "Night Drive", [.extended], nil),
            ("Night Drive - DJ Ostro Remix", "Night Drive", [.remix], nil),
            ("Night Drive (Part 2) (Dub)", "Night Drive (Part 2)", [.dub], nil),
            ("Night Drive [Explicit]", "Night Drive", [], .dirty),
            ("Night Drive (Clean Edit)", "Night Drive", [], .clean),
            ("Night Drive - Part 2", "Night Drive - Part 2", [], nil),
            ("Night Drive (Street)", "Night Drive", [], .dirty),
            ("Night Drive (Street Remix)", "Night Drive", [.remix], nil),
        ]
        for (tag, title, kinds, lyrics) in cases {
            let r = NameReading.readTitle(tag)
            #expect(r.written == tag)
            #expect(r.title == title, "\(tag): \(r.title)")
            #expect((r.version?.kinds ?? []) == kinds, "\(tag): \(String(describing: r.version?.kinds))")
            #expect(r.lyrics == lyrics, "\(tag): \(String(describing: r.lyrics))")
        }
        let k = NameReading.readTags(title: "8A - Night Drive (Dub)", artist: "8A - Marlo Dune")
        #expect(k.key == "8A" && k.title == "Night Drive" && k.artist == "Marlo Dune" && k.written == "8A - Night Drive (Dub)")
    }

    @Test func creditsSplitOnJoinsAndKeepTheFirst() {
        #expect(NameReading.firstArtist("Marlo Dune feat. Kaya Venn") == "Marlo Dune")
        #expect(NameReading.firstArtist("Marlo Dune, Kaya Venn & Tessa Ray") == "Marlo Dune")
        #expect(NameReading.firstArtist("Marlo Dune x Kaya Venn") == "Marlo Dune")
        #expect(NameReading.firstArtist("Marlo Dune/Kaya Venn") == "Marlo Dune")
        // Weak joins never choose the first artist: they are as often part of a band's name.
        #expect(NameReading.firstArtist("Marlo and the Dunes") == "Marlo and the Dunes")
        let c = NameReading.credit("Marlo Dune ft. Kaya Venn & Tessa Ray")
        #expect(c.map(\.name) == ["Marlo Dune", "Kaya Venn", "Tessa Ray"])
        #expect(c.map(\.featuring) == [false, true, true])   // every name after "featuring" is a guest
    }

    @Test func shownIsTheTitleWithItsVersionOnce() {
        #expect(NameReading.shown(title: "Night Drive", version: "Extended Mix") == "Night Drive (Extended Mix)")
        #expect(NameReading.shown(title: "Night Drive (Extended Mix)", version: "Extended Mix") == "Night Drive (Extended Mix)")
        #expect(NameReading.shown(title: "Night Drive", version: nil) == "Night Drive")
        #expect(NameReading.readFileName("Marlo Dune - Night Drive - DJ Ostro Remix").shown == "Night Drive (DJ Ostro Remix)")
    }

    @Test func theVocabularyIsWhole() {
        // Every kind has its words; no phrase means two kinds; uncertain phrases are among the kind's own words.
        for k in VersionKind.allCases { #expect(VersionWords.kinds.contains { $0.kind == k }, "\(k)") }
        var seen: [String: VersionKind] = [:]
        for k in VersionWords.kinds {
            for w in k.words {
                #expect(seen[w] == nil, "\(w) is \(String(describing: seen[w])) and \(k.kind)")
                seen[w] = k.kind
                #expect(VersionWords.fold(w) == w, "\(w) is not written folded")
            }
            for u in k.uncertain { #expect(k.words.contains(u) || k.withName.contains(u), "\(u)") }
        }
        // Only the plain one and a remaster are the same recording (D24; AC 1.4).
        #expect(VersionWords.kinds.filter { !$0.differentAudio }.map(\.kind) == [.plain, .remaster])
        #expect(VersionWords.lyrics(advisory: "1") == .dirty && VersionWords.lyrics(advisory: "2") == .clean && VersionWords.lyrics(advisory: "0") == nil)
    }
}
