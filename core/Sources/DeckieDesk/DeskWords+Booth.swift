import Foundation
import DeckieBooth

extension DeskWords {
    /// The one list: Desk's words (`baseTable`, DeskWords.swift) with the listening mode's beside them, and the words
    /// Booth says about what it hears and picks, shared with the iPad app (`BoothWords`, DeckieBooth, D42). A name in
    /// two keeps Desk's.
    public static let table: [String: String] = baseTable.merging(boothTable) { desk, _ in desk }
        .merging(BoothWords.table) { desk, _ in desk }

    /// The listening mode's words (research booth-in-desk, step 1), kept apart so the two lists change without
    /// meeting. The mode's name, "Booth", is decided (D43, Nov 21, 2026); the rest is provisional until the owner decides
    /// (the input's label, the nothing-heard line and the microphone sentence especially). Sentence case, "songs" not
    /// "tracks", no "AI".
    static let boothTable: [String: String] = [
        // The switch in the top bar into the mode and out of it. The name is decided: "Booth" (D43).
        "booth.mode": "Booth",
        "booth.modeHelp": "Listen to the music playing and name each song from this crate",
        "booth.leave": "Back to songs",
        "booth.title": "Listening with {crate}",
        // The input chooser (provisional label), and its default input.
        "booth.input": "Listen with",
        "booth.inputDefault": "{name} (the usual one)",
        "booth.noInputs": "No microphone or other input found",
        "booth.level": "Level",
        "booth.tryAgain": "Try again",
        // The state line.
        "booth.state.starting": "Getting ready…",
        "booth.state.index": "Getting {crate} ready to listen: {percent}%",
        "booth.state.listening": "Listening",
        // The nothing-heard line (provisional).
        "booth.state.nothingHeard": "Listening. Nothing heard yet from {crate}.",
        // new (Nov 21, 2026): the same, once a song from the crate has been named in this listening ("yet" no longer
        // fits).
        "booth.state.nothingNow": "Listening. Nothing from {crate} is playing right now.",
        // new (Nov 21, 2026): the input is on but gives no sound, or almost none, for several seconds (DeskBooth's
        // noSound): said in place of the nothing-heard line, so the DJ checks the input, not the crate.
        "booth.state.noSound": "No sound is coming from this input. Check that the microphone is on and allowed, or pick another input.",
        "booth.state.stopped": "Not listening",
        "booth.waits": "Listening waits while Desk reads music.",
        "booth.silent": "No sound is reaching Desk. Check the input is plugged in, and that {thisComputer} lets Desk use the microphone.",
        // Why listening stopped, by code (DeckieCapture's CaptureError and DeskBooth's).
        "booth.error.noInput": "No microphone or other input found. Plug one in, or choose another.",
        "booth.error.notAllowed": "Desk isn’t allowed to use the microphone on {thisComputer}. Allow it in the privacy settings, then try again.",
        "booth.error.busy": "Another program is using this input. Close it, or choose another.",
        "booth.error.gone": "The input stopped. It may have been unplugged.",
        "booth.error.noSystem": "Desk can’t reach the sound on {thisComputer}.",
        "booth.error.noPrints": "No song in this crate can be named from its sound yet. Add the music again to fix that.",
        "booth.error.index": "Desk couldn’t get this crate ready to listen.",
        "booth.error.other": "Listening stopped.",
        // The song card: its tempo, key and place, from the crate.
        "booth.tempo": "{bpm} BPM",
        "booth.key": "Key {camelot}",
        "booth.place": "{place} of {length}",
        // new (Nov 21, 2026, step 2): the song on screen is the iPad's (the shared switching rule), so it can stay while
        // nothing is heard for a moment, and another song can be heard under it. Provisional, as the iPad's are.
        "booth.notHeard": "Not heard just now",
        "booth.paused": "Paused",
        "booth.alsoHearing": "Also hearing: {song}",
        // new (Nov 21, 2026, step 2): the picks for the song on screen, a plain first look until the Booth screen is
        // designed (step 3).
        "booth.picksTitle": "Picks for this song (a first look)",
        "booth.picksNone": "No picks for this song in this crate yet.",
        "booth.picksMore": "{n} more in the crate",
        // Between the parts of one line (a pick's facts, the song's notes): "120 BPM · 10B · blend".
        "booth.join": " · ",
        // The microphone permission sentence (provisional): the Mac shows it when it asks (NSMicrophoneUsageDescription
        // in desk-app/project.yml and desk-shell's Info.plist carry these words; BoothTests checks they agree).
        "booth.micPermission": "Deckie Desk listens through the microphone to name the song playing from your crate. Nothing it hears is kept or sent anywhere.",
    ]
}
