import Foundation
import Testing
@testable import DeckieDesk

/// What a person reads in place of the software's own insides (Nov 20, 2026 wording review): a file that didn't go in
/// gets a plain line, not the decoder's words; a file's tags get the names a DJ knows, or are left out when they only
/// say how the file was made; the platform-specific words are each where the window really has them.
@Suite struct PlainWordsTests {
    @Test func aFileThatDidntGoInHasAPlainLine() {
        #expect(DeskWords.reasonDetail("unsupported", raw: "not a format DeckieDecode recognises (WAV, AIFF, MP3, FLAC, AAC)")
                == "Desk can't read this type of file. It reads WAV, AIFF, MP3, FLAC, AAC.")
        #expect(DeskWords.reasonDetail("unsupported", raw: "AVFoundation could not open it") == DeskWords.text("reasonDetail.unsupportedPlain"))
        #expect(DeskWords.reasonDetail("damaged", raw: "no complete MPEG audio frame found; the file may be cut short, or not be MP3")
                == "The file seems cut short or damaged.")
        // A heading that says it all gets no line under it.
        #expect(DeskWords.reasonDetail("no_beat", raw: "no beat grid could be fitted (too few beats)") == nil)
        for code in ["damaged", "unsupported", "no_beat", "too_short", "protected", "decode_error", "analysis_error", "duplicate"] {
            let line = DeskWords.reasonDetail(code, raw: "x (WAV)") ?? ""
            #expect(!line.contains("Deckie") && !line.contains("MPEG"), "\(code)")
        }
    }

    @Test func fileTagsGetPlainNamesOrAreLeftOut() {
        #expect(DeskNaming.fileTagLabel("TSSE") == nil)
        #expect(DeskNaming.fileTagLabel("----:com.apple.iTunes:iTunSMPB") == nil)
        #expect(DeskNaming.fileTagLabel("TXXX:MusicBrainz Album Id") == nil)
        #expect(DeskNaming.fileTagLabel("REPLAYGAIN_TRACK_GAIN") == nil)
        #expect(DeskNaming.fileTagLabel("COMMENT") == "Comment")
        #expect(DeskNaming.fileTagLabel("COMM") == "Comment")
        #expect(DeskNaming.fileTagLabel("TPUB") == "Label")
        #expect(DeskNaming.fileTagLabel("MOOD") == "Mood")
        // One Desk has no word for keeps its own name.
        #expect(DeskNaming.fileTagLabel("DJ_NOTES") == "DJ_NOTES")
    }

    @Test func wordsThatNameAPlaceInTheWindowAreFilledByIt() {
        // rekordbox's help names the menu each window has; nothing is left as a blank.
        let mac = DeskWords.text("rekordboxLocked", ["chooseLibraryAt": DeskWords.text("chooseLibraryAt.menu")])
        let pages = DeskWords.text("rekordboxLocked", ["chooseLibraryAt": DeskWords.text("chooseLibraryAt.more")])
        #expect(mac.hasSuffix("File > Choose a DJ library…") && pages.hasSuffix("⋯ > Choose a DJ library…"))
        // The Mac's steps to the iPad name no Windows software.
        for k in ["toIPadAirDropMac", "toIPadICloudMac", "toIPadCableMac", "toIPadICloudLinux"] {
            let w = DeskWords.text(k)
            #expect(!w.contains("Windows") && !w.contains("Apple Devices"), "\(k)")
        }
        // The window's insides are not in the words: no platform string or raw time in "Read on".
        #expect(!DeskWords.table["readOn"]!.contains("{by}") && !DeskWords.table["readOn"]!.contains("{at}"))
    }

    @Test func aDiscMusicBrainzDoesntKnowIsSaidOnce() {
        let r = DeskLookup.Review(scope: "disc", source: "Friday late", songs: [], stopped: false, failure: nil, requests: 1, discMatch: nil)
        #expect(DeskLookup.summaryLine(r) == DeskWords.coded("lookupDiscMatch", "none"))
    }
}
