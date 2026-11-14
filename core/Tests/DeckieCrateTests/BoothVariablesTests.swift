import Foundation
import Testing

/// D36 for the booth (deck-app): every word the booth shows is in `Deck/Sources/Words.swift` and every design value in
/// `Deck/Sources/Look.swift`. These read the views' source and fail when a view gains a word or a design value of its
/// own. They live here because the core's tests run on every push (the booth has no test target of its own).
///
/// How a word is found: by where it sits. A literal with a letter in it as the first argument of Text, Button, Label,
/// Toggle, TextField, Section, Menu, Picker, Stepper or LabeledContent, or of .help, .accessibilityLabel,
/// .accessibilityHint, .accessibilityValue, .navigationTitle or .alert; a literal with a letter in it joined with `+`
/// to anything (unless it is a key's or an id's prefix); a separator in `joined(separator:)` other than spaces or a
/// line break; and `String(format:)` with a letter in its format. What it cannot catch: a literal kept in a variable
/// and shown later, a word made with interpolation outside those places, the debug log's own lines (`note(`, or a line marked `// log`), and the
/// recogniser (Recognizer.swift), left as it is while another change is made there.
@Suite struct BoothVariablesTests {
    static let repo: URL = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { u.deleteLastPathComponent() }   // Tests/DeckieCrateTests/<file> -> core -> repo
        return u
    }()
    static let views = ["CrateLibrary", "DebugSheet", "DeckApp", "ListenView", "Mixing", "Model", "OtherViews",
                        "SuggestionsView"].map { "deck-app/Deck/Sources/\($0).swift" }   // SetRecorder writes files, not the screen
    static func lines(_ path: String) -> [(Int, String)] {
        let s = (try? String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8)) ?? ""
        let text = s.replacingOccurrences(of: "\r\n", with: "\n")   // a Windows checkout's line ends
        return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { ($0.offset + 1, String($0.element)) }
    }
    static func matches(_ pattern: String, _ s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : ns.substring(with: m.range)
        }
    }
    /// A letter outside a format's specifiers ("%.1f" has none).
    /// A letter inside an interpolation ("\(n + 1)") is code, not a word.
    static func hasLetter(_ s: String) -> Bool {
        s.replacingOccurrences(of: #"%[-+ #0-9.]*(?:ll|l)?[a-zA-Z@]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\\\((?:[^()]|\([^()]*\))*\)"#, with: "", options: .regularExpression)
            .range(of: #"\p{L}"#, options: .regularExpression) != nil
    }
    /// The line before a // comment (outside a string).
    static func code(_ line: String) -> String {
        var inString = false, prev: Character = " ", out = ""
        for c in line {
            if c == "\"" && prev != "\\" { inString.toggle() }
            else if !inString && c == "/" && prev == "/" { out.removeLast(); return out }
            out.append(c); prev = c
        }
        return out
    }
    static let lit = #""(?:[^"\\]|\\.)*""#

    @Test func theBoothsViewsHoldNoWords() {
        #expect(!Self.lines(Self.views[3]).isEmpty, "deck-app's sources are beside the core")
        var found: [String] = []
        for path in Self.views {
            var previous = ""
            for (n, raw) in Self.lines(path) {
                let line = Self.code(raw)
                defer { previous = line }
                if raw.hasSuffix("// log") || line.contains("note(") || line.contains("print(") || line.contains("NSLocalizedDescriptionKey") { continue }
                // A debug log line carried on to the next line.
                if previous.contains("note(") && line.trimmingCharacters(in: .whitespaces).hasPrefix("+") { continue }
                let shown = [#"\b(?:Text|Button|Label|Toggle|TextField|SecureField|Section|Menu|Picker|Stepper|LabeledContent)\(\s*("# + Self.lit + ")",
                             #"\.(?:help|accessibilityLabel|accessibilityHint|accessibilityValue|navigationTitle|alert)\(\s*("# + Self.lit + ")",
                             #"prompt:\s*Text\(\s*("# + Self.lit + ")",
                             #"String\(format:\s*("# + Self.lit + ")"]
                for p in shown { for l in Self.matches(p, line) where Self.hasLetter(l) { found.append("\(path):\(n): shown \(l)") } }
                for l in Self.matches("(" + Self.lit + #")\s*\+"#, line) + Self.matches(#"\+\s*("# + Self.lit + ")", line) {
                    let s = String(l.dropFirst().dropLast())
                    if Self.hasLetter(s) && s.range(of: #"^([A-Za-z][A-Za-z0-9]*[.:/-]|-[a-z]+)$"#, options: .regularExpression) == nil {
                        found.append("\(path):\(n): joined \(l)")
                    }
                }
                for l in Self.matches(#"joined\(separator:\s*("# + Self.lit + ")", line) {
                    let s = String(l.dropFirst().dropLast())
                    if !(s.trimmingCharacters(in: .whitespaces).isEmpty || s == "\\n") { found.append("\(path):\(n): separator \(l)") }
                }
            }
        }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    @Test func theBoothsViewsHoldNoDesignValues() {
        let num = #"(?:[1-9]|0\.)"#
        let patterns = [#"spacing: "# + num, #"Spacing: "# + num, #"\.padding\("# + num, #"\.padding\(\.[a-z]+, "# + num,
                        #"cornerRadius: "# + num, #"\b(?:width|height|minWidth|maxWidth|minHeight|maxHeight): "# + num,
                        #"\bsize: "# + num, #"\.font\(\."#, #"hex: 0x"#, #"\bColor\.(?:white|black|orange|red|green|blue)\b"#,
                        #"\.opacity\("# + num, #"lineWidth: "# + num, #"duration: "# + num, #"radius: "# + num,
                        #"minimumScaleFactor\("# + num, #"\.(?:seconds|milliseconds)\(\d"#, #"UIColor\(red:"#]
        var found: [String] = []
        for path in Self.views {
            for (n, raw) in Self.lines(path) {
                let line = Self.code(raw)
                if line.contains("init(hex:") { continue }   // the colour reader itself
                for p in patterns where !Self.matches(p, line).isEmpty { found.append("\(path):\(n): \(line.trimmingCharacters(in: .whitespaces).prefix(110))") }
            }
        }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
        let look = Self.lines("deck-app/Deck/Sources/Look.swift").map(\.1).joined(separator: "\n")
        #expect(look.contains("enum Theme") && look.contains("enum Look"))
    }
}
