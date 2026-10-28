import Foundation
import Testing
@testable import DeckieCrate

// The two low-level pieces of the format: float16 for the sidecars and the canonical JSON text.

@Suite struct HalfTests {
    @Test func everyFloat16ComesBackToItself() {
        var checked = 0
        for h in 0...0xffff {
            let bits = UInt16(h)
            let v = Half.value(bits)
            if v.isNaN { continue }
            #expect(Half.bits(v) == bits, "\(String(bits, radix: 16)) -> \(v)")
            checked += 1
        }
        #expect(checked == 65536 - 2046)  // 2046 NaN patterns
    }

    @Test func knownValues() {
        #expect(Half.bits(1.0) == 0x3c00)
        #expect(Half.bits(-2.0) == 0xc000)
        #expect(Half.bits(65504) == 0x7bff)
        #expect(Half.bits(65520) == 0x7c00)  // halfway to the next step rounds to even, which is infinity
        #expect(Half.bits(0x1p-24) == 0x0001)  // the smallest subnormal
        #expect(Half.bits(0x1p-25) == 0x0000)  // half of it: a tie, to even (zero)
        #expect(Half.bits(0x1.8p-25) == 0x0001)
        #expect(Half.value(0x3555) == 0.333251953125)
        #expect(Half.rounded(-24.48) == -24.484375)
        #expect(Half.bits(-0.0) == 0x8000)
    }

    @Test func tiesGoToEven() {
        // Between 1 and 1 + 2^-10 the halfway point rounds down to 1 (even); between 1 + 2^-10 and 1 + 2^-9 it
        // rounds up to 1 + 2^-9 (even).
        #expect(Half.bits(1 + 0x1p-11) == 0x3c00)
        #expect(Half.bits(1 + 3 * 0x1p-11) == 0x3c02)
        #expect(Half.bits(1 + 0x1p-11 + 0x1p-40) == 0x3c01)
    }
}

@Suite struct CanonicalJSONTests {
    @Test func numbersKeepTheirDecimalsAndDropTrailingZeros() {
        #expect(CanonicalJSON.number(118.497, decimals: 3) == "118.497")
        #expect(CanonicalJSON.number(125, decimals: 3) == "125.0")
        #expect(CanonicalJSON.number(0.1, decimals: 4) == "0.1")
        #expect(CanonicalJSON.number(-0.0001, decimals: 3) == "0.0")
        #expect(CanonicalJSON.number(-0.0, decimals: 2) == "0.0")
        #expect(CanonicalJSON.number(-24.484375, decimals: 2) == "-24.48")
        #expect(CanonicalJSON.number(2.675, decimals: 2) == "2.67")  // 2.675 is 2.67499999... in binary, as Python has it
        #expect(CanonicalJSON.number(0.125, decimals: 2) == "0.12")  // an exact tie, to even
        #expect(CanonicalJSON.number(1e6, decimals: 2) == "1000000.0")
    }

    @Test func keysAreSortedNullsWrittenAndStringsEscaped() throws {
        struct Sample: Encodable {
            var zeta = 1
            var alpha: String? = nil
            var bpm = 120.0
            var text = "a\"b\\c/d\n\u{1}é"
            var list: [Double] = [0.5, 1]
            enum CodingKeys: String, CodingKey { case zeta, alpha, bpm, text, list = "onset_pattern_16" }
        }
        let tree = try CanonicalJSON.tree(Sample(), decimals: CrateFormat.decimals)
        #expect(CanonicalJSON.text(tree) ==
            #"{"alpha":null,"bpm":120.0,"onset_pattern_16":[0.5,1.0],"text":"a\"b\\c/d\n\u0001é","zeta":1}"# + "\n")
    }

    @Test func anUndocumentedOrNonFiniteNumberIsRefused() {
        struct Odd: Encodable { var tempo = 1.5 }
        struct Bad: Encodable { var bpm = Double.nan }
        #expect(throws: EncodingError.self) { try CanonicalJSON.tree(Odd(), decimals: CrateFormat.decimals) }
        #expect(throws: EncodingError.self) { try CanonicalJSON.tree(Bad(), decimals: CrateFormat.decimals) }
    }
}
