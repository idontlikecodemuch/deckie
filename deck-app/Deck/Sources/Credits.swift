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
}
