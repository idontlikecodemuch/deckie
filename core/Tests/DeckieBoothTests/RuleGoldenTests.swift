import Foundation
import Testing
import DeckieCrate

/// The switching rule's golden record (the move of Nov 21, 2026: the iPad's rule into the core must not change what
/// the iPad shows). Each script, hand-made and generated, is played through the iPad's rule as it was before the move
/// (PresentRule.swift); what the screen shows after every step is kept in Fixtures/rule-golden.txt.
/// `DECKIE_RECORD_GOLDEN=1 swift test --filter DeckieBoothTests` writes the record again (only ever from PresentRule).
@Suite struct RuleGoldenTests {
    static let crate = FixtureCrate.crate

    static func text(_ make: () -> RuleUnderTest) -> String {
        var parts: [String] = []
        for (name, steps) in RuleScripts.handMade { parts.append(runScript(make(), name, steps)) }
        for seed in RuleScripts.seeds { parts.append(runScript(make(), "generated \(seed)", RuleScripts.generated(seed))) }
        return parts.joined(separator: "\n") + "\n"
    }

    @Test func thePresentRuleMatchesItsRecord() throws {
        let lib = PresentLibrary(Self.crate)
        let made = Self.text { PresentDriver(lib) }
        if let diff = try Golden.check("rule-golden", made) { Issue.record(Comment(rawValue: diff)) }
    }

    /// The scripts reach what they are for: every kind of switch, the careful wait, dominance, pauses, the two-minute
    /// rule, jumps and the fader, so the record is not a record of nothing happening.
    @Test func theScriptsCoverTheRule() throws {
        let lib = PresentLibrary(Self.crate)
        let made = Self.text { PresentDriver(lib) }
        for needed in ["the careful wait", "(Deckie's: 1 reading in", "hard cut", "blend", "paused (quiet", "not heard just now",
                       "back to listening", "position jump to", "fader moved", "restart from the top", "repeated section?",
                       "position jump confirmed", "heard again", "resumed at", "kind=vinyl", "kind=master tempo",
                       "position drift over", "tempo-only variant, measuring", "also=Glass Floor", "incoming=s05", "cur=zz",
                       "status=set by hand", "cur=s05 place=Stick 3/Peak/1", "cur=s07 place=CD Party/Warm up/2"] {
            #expect(made.contains(needed), "no step shows \(needed)")
        }
    }
}

/// The fixture crate, written as a crate package for the iPad app's tests to open (`DECKIE_RECORD_GOLDEN=1` writes it;
/// otherwise it must read back as the crate these tests make).
@Suite struct FixtureCrateTests {
    @Test func theFixtureCrateIsKeptAsWritten() throws {
        if Golden.recording {
            try? FileManager.default.removeItem(at: FixtureCrate.packageURL)
            try FileManager.default.createDirectory(at: FixtureCrate.folder, withIntermediateDirectories: true)
            try CrateWriter.write(FixtureCrate.crate, to: FixtureCrate.packageURL)
        }
        let kept = try CrateReader.read(from: FixtureCrate.packageURL)
        let made = try CrateReader.decode(CrateWriter.encode(FixtureCrate.crate))
        #expect(kept == made)
        #expect(kept.tracks.count == 24)
        #expect(kept.tracks.compactMap { $0.scoringTrack() }.count == 23)
    }
}
