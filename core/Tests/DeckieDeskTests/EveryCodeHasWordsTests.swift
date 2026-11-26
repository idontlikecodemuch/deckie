import Foundation
import Testing
import DeckieCrate
import DeckieBuild
@testable import DeckieDesk

/// Every code the engine and the builder can hand a window has words of its own: `DeskWords.coded` falls back to the
/// code itself (or "from {code}"), which a DJ should never see. The Key from column showed "learned-key" on most rows
/// until Nov 25, 2026 (the learned key reader's source had no words).
@Suite struct EveryCodeHasWordsTests {
    /// Every source a key can come from: Deckie's own readers, the DJ programs, the file's tags.
    static let keySources: [String] = Array(LocalFacts.ownKeySources).sorted() + DJProgram.allCases.map(\.rawValue)
        + LocalFacts.tagOrigins + [CrateFormat.EngineFamily.appleMU, CrateFormat.EngineFamily.deckie]

    static func hasOwnWords(_ key: String, _ code: String) -> Bool { DeskWords.table[key + "." + code] != nil }

    @Test func everyKeySourceHasWords() {
        for code in Self.keySources {
            #expect(Self.hasOwnWords("keyFrom", code), "keyFrom.\(code)")
            #expect(Self.hasOwnWords("programName", code), "programName.\(code)")
        }
        #expect(DeskWords.coded("keyFrom", LocalFacts.learnedKeySource) == "read by Deckie")
        #expect(DeskWords.coded("programName", LocalFacts.learnedKeySource) == "Deckie")
    }

    @Test func everyOtherCodeHasWords() {
        for code in CrateManifest.ImportLog.Reason.all + [CrateManifest.ImportLog.Reason.damagedFrames] {
            #expect(Self.hasOwnWords("reason", code), "reason.\(code)")
        }
        for code in RunNow.analysisSteps { #expect(Self.hasOwnWords("nowStage", code), "nowStage.\(code)") }
        for code in SongFacts.LeftOut.all { #expect(Self.hasOwnWords("leftOut", code), "leftOut.\(code)") }
        for code in SongFacts.known { #expect(Self.hasOwnWords("factName", code), "factName.\(code)") }
    }

    /// What went wrong, set between two sentences, is a sentence of its own (the stop message read "E:/ is not a
    /// folder Songs already read are kept." in the Windows hand pass of Nov 25, 2026).
    @Test func aDetailBetweenSentencesEndsWithAFullStop() {
        #expect(DeskWords.text("runStopped", ["detail": "E:/ is not a folder"])
                == "Desk stopped before it finished. E:/ is not a folder. Songs already read are kept.")
        #expect(DeskWords.text("runStopped", ["detail": "The disk is full."])
                == "Desk stopped before it finished. The disk is full. Songs already read are kept.")
        #expect(DeskWords.text("runStopped", ["detail": ""]) == "Desk stopped before it finished. Songs already read are kept.")
        #expect(DeskWords.text("couldntSave", ["detail": "no room"]) == "Couldn't save the crate file. no room.")
        #expect(DeskWords.text("couldntSave", ["detail": " "]) == "Couldn't save the crate file.")
        // In brackets it is left as it is.
        #expect(DeskWords.text("error.couldNotRead", ["name": "S", "detail": "I/O error"])
                == "S could not be read (I/O error). Put S back in to carry on.")
    }
}
