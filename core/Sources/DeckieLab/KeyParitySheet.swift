import Foundation

/// One row of mixer/key_parity_keys.tsv: research R's recommended key method (row 3f) on one of the lab's tracks, as
/// mixer/key_parity.py (`keys`) decided it on the Mac from the track's audio, with the lab's and Apple's keys.
public struct KeyParityRow: Sendable, Equatable {
    /// The lab's track id (the candidates row's and the feature file's).
    public var id: String
    /// The key key_parity.py decides (Camelot), the margin over the second key (4 decimals), how many of the three
    /// profiles pick it alone (0 to 3), and the sure flag.
    public var key: String
    public var margin: Double
    public var agree: Int
    public var sure: Bool
    /// The lab's key, whether the lab is confident in it (0.65 or more, as the bench counts it), and Apple's key (nil
    /// where Apple gave none).
    public var lab: String
    public var labConfident: Bool
    public var apple: String?

    public init(id: String, key: String, margin: Double, agree: Int, sure: Bool, lab: String, labConfident: Bool,
                apple: String?) {
        self.id = id; self.key = key; self.margin = margin; self.agree = agree; self.sure = sure; self.lab = lab
        self.labConfident = labConfident; self.apple = apple
    }

    /// The parity rule the main session set for the engine's key against this row: the same key, the margin within
    /// 1e-3, the same sure flag. Nil when they match; otherwise each difference in words.
    public func differences(key other: String, margin otherMargin: Double, sure otherSure: Bool) -> String? {
        var out: [String] = []
        if other != key { out.append("key \(other), key_parity.py \(key)") }
        if !(abs(otherMargin - margin) <= KeyParitySheet.marginTolerance) {
            out.append("margin \(String(format: "%.4f", otherMargin)), key_parity.py \(String(format: "%.4f", margin))")
        }
        if otherSure != sure { out.append("sure \(otherSure), key_parity.py \(sure)") }
        return out.isEmpty ? nil : out.joined(separator: "; ")
    }
}

public enum KeyParitySheetError: Error, Equatable, CustomStringConvertible {
    case header(String)
    case row(line: Int, text: String)

    public var description: String {
        switch self {
        case .header(let h): return "mixer/key_parity_keys.tsv: unexpected header \(h)"
        case .row(let line, let text): return "mixer/key_parity_keys.tsv line \(line): cannot read \(text)"
        }
    }
}

/// mixer/key_parity_keys.tsv, read-only: research R's per-track keys (`key_parity.py keys` writes it, 373 rows, row
/// 3f's 83.3 percent exact on the lab's 311 confident keys), the reference the bench's parity column compares the
/// engine's key with.
public enum KeyParitySheet {
    /// The file's name beside the lab's features folder (mixer/).
    public static let fileName = "key_parity_keys.tsv"
    /// The columns, in order.
    public static let columns = ["id", "key_3f", "margin", "agree", "sure", "lab", "lab_confident", "apple"]
    /// How far the engine's margin may be from the sheet's and still count as parity.
    public static let marginTolerance = 1e-3

    /// The rows, in the file's order.
    public static func load(_ url: URL) throws -> [KeyParityRow] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let header = lines.first else { throw KeyParitySheetError.header("(empty file)") }
        guard header.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) == columns else {
            throw KeyParitySheetError.header(header)
        }
        lines.removeFirst()
        return try lines.enumerated().map { i, line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == columns.count, let margin = Double(f[2]), let agree = Int(f[3]),
                  ["0", "1"].contains(f[4]), ["0", "1"].contains(f[6]) else {
                throw KeyParitySheetError.row(line: i + 2, text: line)
            }
            return KeyParityRow(id: f[0], key: f[1], margin: margin, agree: agree, sure: f[4] == "1", lab: f[5],
                                labConfident: f[6] == "1", apple: f[7].isEmpty ? nil : f[7])
        }
    }

    /// The rows by track id.
    public static func byID(_ url: URL) throws -> [String: KeyParityRow] {
        Dictionary(try load(url).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}
