import Foundation
import Testing
import DeckieCore

/// The four readings' arithmetic on a constructed three-class model (Speech, Singing, Music), every number known.
@Suite struct VocalReadingsTests {
    /// Four patches of (Speech, Singing, Music), all exact in binary: a mixed patch, one with no singing and full
    /// music, one with nothing at all, and one with full singing.
    static let toy = ClassScoreMatrix(patches: 4, names: ["Speech", "Singing", "Music"],
                                      scores: [0.25, 0.5, 0.75,
                                               0.125, 0, 1,
                                               0, 0, 0,
                                               0.5, 1, 0.25])

    /// The logit of a score clamped to 1e-7 (and, negated, of one clamped to 1 - 1e-7).
    static let floorLogit = -log(1e7 - 1)

    /// The classes are found by name in the model's list, in the order asked; the others are reported missing.
    @Test func classesAreFoundByName() {
        let c = VocalReadings.read(Self.toy).classes
        #expect(c.max == [.init("Singing", 1)])
        #expect(c.voice == [.init("Singing", 1), .init("Speech", 0)])
        #expect(c.music == [.init("Music", 2)])
        #expect(c.missingMax == VocalReadings.maxClassNames.filter { $0 != "Singing" })
        #expect(c.missingVoice == VocalReadings.voiceClassNames.filter { $0 != "Singing" && $0 != "Speech" })
        #expect(c.missingMusic == ["Musical instrument"])
        // An unnamed column never matches; a repeated name is its first column.
        let r = VocalReadings.resolve(["", "a"], in: ["", "a", "a"])
        #expect(r.found == [.init("a", 1)] && r.missing == [""])
        // The eleven of max11 are all among the voice classes, so voice_sum is never below max11.
        #expect(Set(VocalReadings.maxClassNames).isSubset(of: VocalReadings.voiceClassNames))
    }

    /// Each reading patch by patch.
    @Test func readingsPerPatch() {
        let r = VocalReadings.read(Self.toy)
        #expect(r.max11 == [0.5, 0, 0, 1])
        #expect(r.voiceSum == [0.75, 0.125, 0, 1.5])
        // ln(0.25 / 0.75) + ln(0.5 / 0.5); ln(0.125 / 0.875) + the floor; twice the floor; ln(1) + the ceiling.
        let logits = [-log(3.0), -log(7.0) + Self.floorLogit, 2 * Self.floorLogit, -Self.floorLogit]
        #expect(zip(r.voiceLogitSum, logits).allSatisfy { abs($0 - $1) < 1e-12 }, "\(r.voiceLogitSum)")
        #expect(abs(Self.floorLogit + 16.118095) < 1e-6)
        // 0.75 / (0.75 + 0.75); 0.125 / (0.125 + 1); nothing over nothing is 0; 1.5 / (1.5 + 0.25).
        #expect(r.voiceVsMusic == [0.5, 1.0 / 9.0, 0, 6.0 / 7.0])
        #expect(VocalReadings.names == r.series.map(\.name))
        #expect(VocalReadings.names == VocalReadings.notes.map(\.name))
    }

    /// Into bars as `PatchBars.average` does: patches centred at 0.5, 1.5, 2.5, 3.5 s; bars 0-2 s (patches 0 and 1),
    /// 2-4 s (patches 2 and 3), and 4-5 s, which no patch is centred in (the last patch's value, as numpy's interp
    /// gives past the last centre).
    @Test func readingsPerBar() {
        let b = VocalReadings.read(Self.toy).averaged(hop: 1, centreOffset: 0.5, barTimes: [0, 2, 4, 5])
        #expect(b.max11 == [0.25, 0.5, 1])
        #expect(b.voiceSum == [0.4375, 0.75, 1.5])
        let logits = [(-log(3.0) - log(7.0) + Self.floorLogit) / 2, Self.floorLogit / 2, -Self.floorLogit]
        #expect(zip(b.voiceLogitSum, logits).allSatisfy { abs($0 - $1) < 1e-12 }, "\(b.voiceLogitSum)")
        #expect(b.voiceVsMusic == [(0.5 + 1.0 / 9.0) / 2, (0 + 6.0 / 7.0) / 2, 6.0 / 7.0])
        #expect(b.classes == VocalReadings.read(Self.toy).classes)
    }

    /// No patches: empty series per patch, zeros per bar (as `PatchBars.average` gives).
    @Test func noPatches() {
        let r = VocalReadings.read(ClassScoreMatrix(patches: 0, names: ["Singing"], scores: []))
        #expect(r.series.allSatisfy { $0.values.isEmpty })
        let b = r.averaged(hop: 0.48, centreOffset: 0.4875, barTimes: [0, 2, 4])
        #expect(b.series.allSatisfy { $0.values == [0, 0] })
    }
}
