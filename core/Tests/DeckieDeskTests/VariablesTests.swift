import Foundation
import Testing
@testable import DeckieDesk

/// D36: every word a person can see comes from DeskWords, by name, and every design value from the app's one file of
/// them (the pages' desk.css :root block; the Mac's Look.swift). These read the views' source and fail when a view gains
/// a word or a design value of its own.
///
/// How a word is found: by where it sits, not by what it says (most strings in a view are names of things: keys,
/// classes, ids, requests). In the pages, a literal with a letter in it is a word when it is put on the screen
/// (`text:`, `textContent =`, a title, an aria-label, a placeholder, alt, a message), joined to a word with `+`, or used
/// to join words (`.join(",")`); index.html's text and its title, placeholder, aria-label and alt attributes; and
/// desk.css's `content:`. In the Mac's views, a literal with a letter in it as the first argument of Text, Button, Label,
/// Toggle, TextField, Section, Menu, Picker or DisclosureGroup, or of .help, .accessibilityLabel, .accessibilityHint,
/// .accessibilityValue, .navigationTitle, .alert or .confirmationDialog; set as a panel's message, prompt or title; joined
/// to anything with `+` unless it is a key's prefix ("mode."); or used as a separator in `joined(separator:)`.
///
/// What it cannot catch: a literal kept in a variable and shown later; a word built with interpolation outside those
/// places; a separator that is only spaces; formats (a time as 3:07, a number's digits); and the words of the headless
/// tools, which print to a terminal.
@Suite struct VariablesTests {
    static let repo: URL = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { u.deleteLastPathComponent() }   // Tests/DeckieDeskTests/VariablesTests.swift -> core -> repo
        return u
    }()
    static func read(_ path: String) -> String {
        ((try? String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8)) ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")   // a Windows checkout's line ends
    }
    static func lines(_ path: String) -> [(Int, String)] {
        read(path).split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { ($0.offset + 1, String($0.element)) }
    }
    static func matches(_ pattern: String, _ s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : ns.substring(with: m.range)
        }
    }
    static let letter = try! NSRegularExpression(pattern: "\\p{L}")
    static func hasLetter(_ s: String) -> Bool {
        letter.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }
    /// A literal that names a thing rather than says something: a key's or an id's prefix ("mode.", "song:",
    /// "pick-"), a form's suffix (".other"), a unit, a class name or two.
    static func isName(_ s: String) -> Bool {
        s.range(of: #"^([A-Za-z][A-Za-z0-9]*[.:-]|\.[a-z]*|px|%|:|data:image/jpeg;base64,|[a-z]+( [a-z]+)*|\s*)$"#, options: .regularExpression) != nil
    }
    /// The part of a line before a // comment (a crude cut: enough for these files, where // in a string is a URL's).
    static func code(_ line: String) -> String {
        var inString: Character?
        var prev: Character = " "
        var out = ""
        for c in line {
            if let q = inString { if c == q && prev != "\\" { inString = nil } }
            else if c == "\"" || c == "'" || c == "`" { inString = c }
            else if c == "/" && prev == "/" { out.removeLast(); return out }
            out.append(c); prev = c
        }
        return out
    }

    // MARK: the pages (desk-web)

    static let jsLit = #"("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`)"#

    static func pageWords(_ path: String) -> [String] {
        var found: [String] = []
        var inPageWords = false
        for (n, raw) in lines(path) {
            // desk.js's PAGE_WORDS: the words shown when the engine's are not there; the only ones the pages hold.
            if raw.contains("const PAGE_WORDS = {") { inPageWords = true; continue }
            if inPageWords { if raw.trimmingCharacters(in: .whitespaces).hasPrefix("};") { inPageWords = false }; continue }
            let line = code(raw)
            let shown = [#"\btext:\s*"# + jsLit, #"\.textContent\s*\+?=\s*"# + jsLit, #"\btitle:\s*"# + jsLit,
                         #""aria-label":\s*"# + jsLit, #"\bplaceholder:\s*"# + jsLit, #"\balt:\s*"# + jsLit,
                         #"setAttribute\("(?:aria-label|aria-valuetext|title|placeholder|alt)",\s*"# + jsLit,
                         #"message\(\[\s*"# + jsLit]
            for p in shown { for lit in matches(p, line) where hasLetter(lit) { found.append("\(path):\(n): shown \(lit)") } }
            for lit in matches(jsLit + #"\s*\+"#, line) + matches(#"\+\s*"# + jsLit, line) {
                if !isName(String(lit.dropFirst().dropLast())) { found.append("\(path):\(n): joined \(lit)") }
            }
            for lit in matches(#"\.join\(\s*"# + jsLit, line) {
                let s = String(lit.dropFirst().dropLast())
                if !(s.trimmingCharacters(in: .whitespaces).isEmpty || s == "\\n") { found.append("\(path):\(n): separator \(lit)") }
            }
        }
        return found
    }

    @Test func thePagesScriptsHoldNoWords() {
        let found = Self.pageWords("desk-web/desk.js") + Self.pageWords("desk-web/run.js")
        #expect(!Self.read("desk-web/desk.js").isEmpty && !Self.read("desk-web/run.js").isEmpty)
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    @Test func thePagesHtmlHoldsNoWords() {
        var html = Self.read("desk-web/index.html")
        #expect(!html.isEmpty)
        for p in [#"<!--[\s\S]*?-->"#, #"<script[\s\S]*?</script>"#, #"<style[\s\S]*?</style>"#, #"<title>[^<]*</title>"#] {
            html = html.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        var found = Self.matches(#">([^<]*)<"#, html).filter(Self.hasLetter).map { "text \($0)" }
        found += Self.matches(#"\s(?:title|placeholder|aria-label|alt)="([^"]*)""#, html).filter(Self.hasLetter).map { "attribute \($0)" }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    @Test func thePagesStyleSheetHoldsNoWordsAndNoValuesOutsideItsVariables() {
        let css = Self.read("desk-web/desk.css")
        guard let start = css.range(of: ":root {"), let end = css.range(of: "\n}\n", range: start.upperBound..<css.endIndex) else {
            Issue.record("desk.css has no :root block"); return
        }
        let rules = String(css[end.upperBound...]).replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
        var found = Self.matches(#"content:\s*("[^"]*"|'[^']*')"#, rules).map { "content \($0)" }
        // A colour, or a length or time with its unit, written in a rule: it belongs in :root. Kept out: the one @media
        // query's width (CSS cannot take a variable there), 100% (fill the box), the 0% to 100% of a gradient or a
        // keyframe, the 1px of the screen-reader-only box, and 90deg and 360deg (a direction and a whole turn).
        let values = #"(#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\(|(?<![\w.-])-?\d*\.?\d+(?:px|em|rem|vh|vw|ms|s|fr)\b)"#
        for (n, line) in rules.split(separator: "\n").enumerated() {
            var l = String(line).replacingOccurrences(of: #"var\([^)]*\)"#, with: "", options: .regularExpression)
            l = l.replacingOccurrences(of: #"@media \(max-width: \d+px\)"#, with: "", options: .regularExpression)
            if l.contains(".sr {") { continue }
            for v in Self.matches(values, l) { found.append("rule line \(n + 1): \(v) in \(line.trimmingCharacters(in: .whitespaces).prefix(90))") }
        }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    @Test func theRunScreenDrawsWithTheStyleSheetsNumbers() {
        // Every variable run.js and desk.js read is defined in desk.css's :root, and run.js keeps no fallback numbers.
        let css = Self.read("desk-web/desk.css"), js = Self.read("desk-web/run.js") + Self.read("desk-web/desk.js")
        let defined = Set(Self.matches(#"(--[\w-]+)\s*:"#, css))
        let read = Set(Self.matches(#"(?:css|num|time)\("(--[\w-]+)"\)"#, js))
        #expect(!read.isEmpty)
        #expect(read.subtracting(defined).isEmpty, "\(read.subtracting(defined).sorted())")
        #expect(Self.matches(#"\)\s*\|\|\s*[1-9]"#, Self.read("desk-web/run.js")).isEmpty, "a fallback number in run.js")
        // And every word they ask for by name is in the list (a missing word shows as its name).
        let asked = Set(Self.matches(#"\b(?:t|join)\("([A-Za-z][\w.]*)"\s*[,)]"#, js))
        let missing = asked.filter { DeskWords.table[$0] == nil }
        #expect(missing.isEmpty, "\(missing.sorted())")
    }

    // MARK: the Mac's window (desk-app)

    /// Source files of the Mac's window that are views; the word list, the look and the headless tools are not.
    static let macViews = ["AddMusic", "ContentView", "DeskApp", "DeskModel", "ImportLogView", "Lookup", "Naming", "RunScreen",
                           "SourcesPanel", "TrackTable"].map { "desk-app/Desk/Sources/\($0).swift" }

    static let swiftLit = #""(?:[^"\\]|\\.)*""#

    static func swiftWords(_ path: String) -> [String] {
        var found: [String] = []
        for (n, raw) in lines(path) {
            let line = code(raw)
            // The headless walks and checks print to a terminal and name their pictures.
            if line.contains("print(") || line.contains("say(") || line.contains("Snapshot.capture(") || line.contains("render(\"")
                || line.contains("appendingPathComponent(") { continue }
            let shown = [#"\b(?:Text|Button|Label|Toggle|TextField|SecureField|Section|Menu|Picker|DisclosureGroup)\(\s*("#
                            + swiftLit + ")",
                         #"\.(?:help|accessibilityLabel|accessibilityHint|accessibilityValue|navigationTitle|alert|confirmationDialog)\(\s*("#
                            + swiftLit + ")",
                         #"\.(?:message|prompt|title|messageText|informativeText|nameFieldLabel)\s*=\s*("# + swiftLit + ")"]
            for p in shown { for lit in matches(p, line) where hasLetter(lit) { found.append("\(path):\(n): shown \(lit)") } }
            for lit in matches("(" + swiftLit + #")\s*\+"#, line) + matches(#"\+\s*("# + swiftLit + ")", line) {
                let s = String(lit.dropFirst().dropLast())
                if !(s.range(of: #"^([A-Za-z][A-Za-z0-9]*[.:/]|\.[a-z]*|/|[a-z]{1,3}|\s*)$"#, options: .regularExpression) != nil) {
                    found.append("\(path):\(n): joined \(lit)")
                }
            }
            for lit in matches(#"joined\(separator:\s*("# + swiftLit + ")", line) {
                let s = String(lit.dropFirst().dropLast())
                if !(s.trimmingCharacters(in: .whitespaces).isEmpty || s == "\\n") { found.append("\(path):\(n): separator \(lit)") }
            }
        }
        return found
    }

    /// A design value written in a view: a number for spacing, padding, a size, a corner, an opacity, a line or a
    /// time; a colour; a font or a weight.
    static func swiftValues(_ path: String) -> [String] {
        let num = #"(?:[1-9]|0\.)"#   // a number that is not 0 (0 is flush, not a value)
        let patterns = [#"spacing: "# + num, #"Spacing: "# + num, #"\.padding\("# + num, #"\.padding\(\.[a-z]+, "# + num,
                        #"cornerRadius: "# + num,
                        #"\.frame\([^)]*\b(?:width|height|minWidth|idealWidth|maxWidth|minHeight|idealHeight|maxHeight): "# + num,
                        #"\.width\((?:min: )?\d"#, #"\.font\(\."#, #"\bColor\((?!nsColor:)"#, #"NSColor\("#,
                        #"\.(?:orange|green|red|blue|yellow|purple|pink|mint|teal|cyan|indigo|brown)\b"#,
                        #"\.opacity\("# + num, #"lineWidth: "# + num, #"duration: "# + num, #"radius: "# + num, #"\.bold\(\)"#,
                        #"\.fontWeight\(\.(?:bold|semibold|medium|heavy|black|light|thin|regular)"#,
                        #"\.weight\(\."#, #"system\(size:"#]
        var found: [String] = []
        for (n, raw) in lines(path) {
            let line = code(raw)
            if line.contains("windowBackgroundColor") { continue }   // the headless walk's picture background
            for p in patterns where !matches(p, line).isEmpty { found.append("\(path):\(n): \(line.trimmingCharacters(in: .whitespaces).prefix(100))") }
        }
        return found
    }

    @Test func theMacsViewsHoldNoWords() {
        #expect(!Self.read(Self.macViews[0]).isEmpty, "desk-app's sources are beside the core")
        let found = Self.macViews.flatMap(Self.swiftWords)
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    @Test func theMacsViewsHoldNoDesignValues() {
        let found = Self.macViews.flatMap(Self.swiftValues)
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
        #expect(Self.read("desk-app/Desk/Sources/Look.swift").contains("enum RunLook"))
        #expect(Self.read("desk-app/Desk/Sources/Look.swift").contains("enum LookupStyle"))
    }
}
