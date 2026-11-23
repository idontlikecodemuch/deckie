import Foundation
import Testing
@testable import DeckieDesk

/// What was seen on Nov 23, 2026, the first time the Mac's quick start was looked at in the running app
/// (`"Deckie Desk" --quick-start-walk`), held here by reading the views' source, as VariablesTests does:
/// - at the window's smallest size the first screen was taller than the window: the body ended in "…" and the last
///   line was cut off, with the quick start's card and without it;
/// - the three ways in were tiles of three heights, each as tall as its drawing;
/// - the player's steps in words, given only a most width, were squeezed to half of it.
@Suite struct MacFirstScreenTests {
    @Test func theFirstScreenScrollsWhenItDoesNotFit() {
        let view = VariablesTests.read("desk-app/Desk/Sources/ContentView.swift")
        guard let start = view.range(of: "struct EmptyCrateView"), let end = view.range(of: "struct FirstScreen") else {
            Issue.record("EmptyCrateView or FirstScreen is gone"); return
        }
        let empty = view[start.lowerBound..<end.lowerBound]
        #expect(empty.contains("ViewThatFits(in: .vertical)"))
        #expect(empty.contains("ScrollView(.vertical) { FirstScreen()"))
        // the body is never shortened to one line
        #expect(view.contains("Text(Words.firstBody)") && view.range(of: #"Text\(Words\.firstBody\)[^\n]*\n[^\n]*\n\s*\.fixedSize\(horizontal: false, vertical: true\)"#, options: .regularExpression) != nil)
    }

    @Test func theThreeWaysInAreOneSize() {
        let add = VariablesTests.read("desk-app/Desk/Sources/AddMusic.swift")
        #expect(add.contains(".frame(height: Look.First.wayIconHeight)"))
        #expect(VariablesTests.read("desk-app/Desk/Sources/Look.swift").contains("static let wayIconHeight"))
    }

    @Test func thePlayersStepsKeepTheirWidth() {
        #expect(VariablesTests.read("desk-app/Desk/Sources/QuickStart.swift")
            .contains("QuickStartWords().frame(width: Look.QuickStart.wordsWidth"))
    }
}
