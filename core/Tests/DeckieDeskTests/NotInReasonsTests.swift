import Foundation
import Testing
import DeckieCrate
import DeckieBuild
import DeckieDecode
import DeckieEngine
@testable import DeckieDesk

/// Why a file did not go in, in words (Nov 18, 2026): a file that decodes but has no steady beat, or is too short, says
/// so plainly; a damaged or cut-short file says "damaged or incomplete"; "Analysis failed" is kept for a real failure of
/// the analysis. Every reason the import log can give has its own words, in the window's "What didn't go in" list.
@Suite struct NotInReasonsTests {
    typealias R = CrateManifest.ImportLog.Reason

    @Test func eachFailureHasItsOwnReason() {
        #expect(FileFailure.classify(AnalyserError.noGrid, path: "/x/a.mp3").reason == R.noBeat)
        #expect(FileFailure.classify(AnalyserError.tooFewBars(3), path: "/x/a.mp3").reason == R.tooShort)
        #expect(FileFailure.classify(AnalyserError.vocalBars(got: 1, bars: 2), path: "/x/a.mp3").reason == R.analysisError)
        let cut = AudioDecodeError(kind: .damaged, file: "/x/a.mp3", format: .mp3,
                                   message: "the file is cut short (it ends in the middle of a frame), and too little of it is left to read")
        let f = FileFailure.classify(cut, path: "/x/a.mp3")
        #expect(f.reason == R.damaged && !f.message.contains("/x/"))
    }

    @Test func everyReasonHasPlainWords() {
        for r in R.all {
            let words = DeskWords.coded("reason", r)
            #expect(words != r && !words.contains("_"), "\(r): \(words)")
            #expect(!words.lowercased().contains("track") && !words.contains("AI"), "\(r): \(words)")
        }
        #expect(DeskWords.coded("reason", R.damaged) == "Damaged or incomplete")
        #expect(DeskWords.coded("reason", R.noBeat) == "No beat found")
        #expect(DeskWords.coded("reason", R.analysisError) == "Analysis failed")
    }
}
