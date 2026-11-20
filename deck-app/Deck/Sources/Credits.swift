import Foundation

/// One part of someone else's work inside Deckie Booth, as the Credits sheet shows it: its name, version and licence
/// as the licence names itself, the licence's own text, and for a model what it was trained on.
///
/// An entry is added here when the part ships in Booth's binary, with the same name, version and licence as its row in
/// `core/dependencies.json` (`id` is that row's id) and the licence text quoted in DEPENDENCIES.md. Not every row ships
/// in Booth: the decoders, the window, ONNX Runtime and the analysis models are Desk's. Deckie's own key reader's model
/// is expected to be the first entry here, with its training recordings and their terms in `parts`.
struct Credit: Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let licence: String
    /// The licence's text, shown in full.
    let licenceText: String
    /// What a model was trained on, one line each, with each set's terms; empty for code.
    var parts: [String] = []
}

enum Credits {
    /// What Booth carries that Deckie did not write. Today: nothing. Booth links only Deckie's own packages
    /// (DeckieCore, DeckieCrate, DeckieRecognition and DeckieAudio, which vendor nothing) and Apple's frameworks,
    /// which come with iPadOS; the built app embeds no library of anyone else's (checked with otool, Nov 19, 2026).
    static let booth: [Credit] = []

    /// The songs in the demo crate file (DemoCrate), in the order deckie.io/demo plays them. The same table, with each
    /// file's SHA-256 and the date it was fetched, is site/demo/CREDITS.md; the two are kept in step. Each song's licence
    /// is the one its own page on the Free Music Archive states (checked Nov 19, 2026; the set chosen again that day so
    /// that most songs suit each other, `pc/booth-build-2`).
    static let demoSongs: [DemoSong] = [
        DemoSong(title: "Roller Fever", artist: "Loyalty Freak Music",
                 source: "https://freemusicarchive.org/music/Loyalty_Freak_Music/ROLLER_DISCO_DANCE_DANCE/Loyalty_Freak_Music_-_ROLLER_DISCO_DANCE_DANCE_-_01_Roller_Fever/"),
        DemoSong(title: "La montagne", artist: "Komiku",
                 source: "https://freemusicarchive.org/music/Komiku/Its_time_for_adventure_/Komiku_-_Its_time_for_adventure_-_07_La_montagne/"),
        DemoSong(title: "Everything is groovy (How to move your body)", artist: "Komiku",
                 source: "https://freemusicarchive.org/music/Komiku/Helice_Awesome_Dance_Adventure_/everything-is-groovy-how-to-move-your-body/"),
        DemoSong(title: "Sweet You", artist: "Loyalty Freak Music",
                 source: "https://freemusicarchive.org/music/Loyalty_Freak_Music/MELODIES_WITH_A_BEAT/Loyalty_Freak_Music_-_MELODIES_WITH_A_BEAT_-_01_Sweet_You/"),
        DemoSong(title: "Captain Glouglou contest", artist: "Komiku",
                 source: "https://freemusicarchive.org/music/Komiku/Helice_Awesome_Dance_Adventure_/captain-glouglou-contest/"),
        DemoSong(title: "Sweet They", artist: "Loyalty Freak Music",
                 source: "https://freemusicarchive.org/music/Loyalty_Freak_Music/MELODIES_WITH_A_BEAT/Loyalty_Freak_Music_-_MELODIES_WITH_A_BEAT_-_14_Sweet_They/"),
        DemoSong(title: "Street of love", artist: "Loyalty Freak Music",
                 source: "https://freemusicarchive.org/music/Loyalty_Freak_Music/POSITIVE_ATTITUDE_/Loyalty_Freak_Music_-_POSITIVE_ATTITUDE__-_06_Street_of_love/"),
    ]
}

/// One song in the demo crate file: its title and artist as its source names them, its licence, and its page.
struct DemoSong: Identifiable, Hashable {
    var id: String { source }
    let title: String
    let artist: String
    var licence = "CC0 1.0 Universal (public domain dedication)"
    var licenceURL = "https://creativecommons.org/publicdomain/zero/1.0/"
    let source: String
}
