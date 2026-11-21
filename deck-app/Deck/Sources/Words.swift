import Foundation
import DeckieCrate
import DeckieBooth

/// Every word the booth shows, in one list by name (D28, D36: placeholders until the copy audit, which changes this
/// file only). Organised by screen; each says where it shows. Words built from parts are functions with named blanks,
/// so no view joins words of its own. The spelling is the booth's as it was, oddities and all (the copy pass decides).
/// Sentence case, "songs", a crate is the songs and a crate file is the file.
///
/// The words Booth says about what it hears and picks (the join's pitch and key words, the BPM and move lines, the tags,
/// the moves, the key's other states, the filter) are the core's table (`BoothWords`, D42), shared with Desk's Booth;
/// they are named here as before and read from there.
enum Words {
    private static func b(_ key: String, _ values: [String: String] = [:]) -> String { BoothWords.t(key, values) }

    // MARK: the app: tabs, the Minimal switch, a crate file opened or not

    /// The tab bar.
    static let tabListen = "Listen"
    /// The tab bar, and the Crate tab's heading. Provisional: the owner has been asked (D26).
    static let tabCrate = "Crate"
    /// The button that closes the "could not open" alert.
    static let ok = "OK"
    /// The switch in the app's upper-left corner (every tab): its label, its spoken name and value.
    static let minimal = "Minimal"
    static let minimalSpoken = "Minimal display"
    static let switchOn = "on", switchOff = "off"

    // MARK: a song with no name (research AA, 3.13)

    /// The quiet line under a song's place when the crate file gives it no name.
    static let noNameYet = "No name yet"
    /// The same, inside a row or a pick ("Friday night / Peak / 07 · no name yet").
    static let noNameYetInRow = "no name yet"
    /// The file a song with no name was read from, shown as a file name so it never looks like a title.
    static func fileLine(_ stem: String) -> String { "file: \(stem)" }

    // MARK: where a song is (rows, picks, the playing panel, "also on")

    /// "Stick 3 /" and "Stick 3 / House /": a source, and a folder on it.
    static func sourceTop(_ source: String) -> String { "\(source) /" }
    static func sourceFolder(_ source: String, _ folder: String) -> String { "\(source) / \(folder) /" }
    /// The Crate tab's folder heading with no source: "House /", or "/" at the top.
    static let folderTop = "/"
    static func folderOnly(_ folder: String) -> String { "\(folder) /" }
    /// Between a place's parts: "Stick 3 / House / 04".
    static let placeJoin = " / "
    /// A song's number in its place: " / 04" after the place, "04" alone.
    static func placeNumber(_ n: Int) -> String { String(format: " / %02d", n) }
    static func number(_ n: Int) -> String { String(format: "%02d", n) }
    /// A song's number before its title: "06 · Title".
    static func numbered(_ n: Int, _ title: String) -> String { String(format: "%02d · ", n) + title }
    /// Between a place and "no name yet", and between a song's parts in one line.
    static let dotJoin = " · "
    /// The playing panel's big line for a song with no name: the source on one line, the rest on the next.
    static func twoLines(_ first: String, _ second: String) -> String { first + "\n" + second }
    /// "also on Stick 3 / Peak / 04 · also in Album" (rows, picks and the playing panel).
    static func alsoOn(_ places: [String]) -> String { "also on " + places.joined(separator: ", ") }
    static func alsoIn(_ places: [String]) -> String { "also in " + places.joined(separator: ", ") }
    /// A song's facts in one short line: "Friday Night · 1999 · Nervous · House, Garage".
    static func factsLine(_ facts: [[String]]) -> String? {
        let parts = facts.map { $0.joined(separator: ", ") }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    /// A disc's name cut short for a chip: its first 9 characters and this.
    static let cutShort = b("pick.cutShort")
    /// The disc filter as a sentence says it: "CD1+CD2", "Singalongs+all".
    static let filterAll = b("pick.filterAll")
    static let filterJoin = b("pick.filterJoin")
    /// "CD1, CD2 or All": choices joined for a sentence.
    static func orList(_ items: [String]) -> String {
        items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " or " + items.last!
    }

    // MARK: the Listen page: the playing panel

    /// A tempo: "128 BPM" (the playing panel and the picks).
    static func bpm(_ value: Double) -> String { BoothWords.bpm(value) }
    /// A tempo that changes in the song: "128→140 BPM".
    static func bpmChange(_ from: Double, _ to: Double) -> String { BoothWords.bpmChange(from, to) }
    /// While nothing has been recognised yet.
    static let listeningTitle = "Listening…"
    static let listeningHelp = "A song shows up after a few seconds of music."
    /// The panel's foot when a second song is heard under the first.
    static func alsoHearing(_ song: String) -> String { "also hearing: " + song }
    /// The set recording's corner chip ("REC 0:12:34" while recording), spoken as "Set recording" with these as its
    /// value. "REC on": recording is on and starts when listening does.
    static let recPaused = "REC paused"
    static func recElapsed(_ time: String) -> String { "REC " + time }
    static let recOn = "REC on"
    static let recOff = "REC off"
    /// The chip's menu: pause or resume the recording in progress (listening goes on), and set recording on or off
    /// (remembered). Its note says that Stop, beside the chip, ends the set and saves it.
    static let resumeRecording = "Resume recording"
    static let pauseRecording = "Pause recording, keep listening"
    static let recordSets = "Record each set"
    static let recWhere = phrases("Stop ends the set and saves it", "on this iPad, in Files under Deckie.")
    /// The Listen page's one control for listening, in the playing panel's corner (`ListenControl`). Stop: the
    /// microphone off, and the set's recording ended and saved; the song on screen stays. Start listening: the
    /// microphone on again, and a new set recording when set recording is on.
    static let stop = "Stop"
    static let stopSpoken = "Stop listening and save the set"
    static let startListening = "Start listening"
    /// The playing panel after Stop, when no song is on screen: what happened, where the set is, how to go on.
    static let stoppedTitle = "Stopped"
    static let stoppedHelp = "Deckie is not listening."
    static let stoppedSaved = phrases("The set is saved on this iPad,", "in Files under Deckie > Sets.")
    static let stoppedHow = phrases("Tap Start listening", "to listen again.")
    /// The playing panel's foot after Stop, when the song stays on screen.
    static let setSavedFoot = "Stopped. The set is saved in Files under Deckie > Sets."
    /// The corner's "…" button, spoken.
    static let testWithFile = "Test with file and details"
    /// The corner's tiny status.
    static let statusStopped = "stopped"
    static let statusListening = "listening"
    static let statusTestFile = "test file"
    static let statusByHand = "set by hand"
    static let statusAlsoPaused = " · paused"
    static let statusSure = " · sure", statusLikely = " · likely", statusUnsure = " · unsure"
    static func statusDeck(_ pitch: String) -> String { " · deck " + pitch + "%" }
    /// The confidence dots, spoken.
    static let confidenceByHand = "set by hand"
    static func confidence(_ percent: Int) -> String { "confidence \(percent) percent" }
    /// The whole-song wave's marks: the mix-in and the sync area (the mix-out window).
    static let waveIn = "IN"
    static let waveSync = "SYNC"
    /// The song time: elapsed, unknown, and remaining.
    static let timeUnknown = "–:––"
    static func remaining(_ time: String) -> String { "−" + time }
    /// The small note under the song time.
    static let positionUnknown = "position unknown"
    static func syncIn(_ time: String) -> String { "sync area in " + time }
    static func syncBarsLeft(_ bars: Int) -> String { "sync area · \(bars) bar\(bars == 1 ? "" : "s") left" }
    static let pastSync = "past the sync area"
    /// The Halloween moment's ghost and pumpkin, and the Halloween mark on rows and picks.
    static let ghost = "👻"
    static let pumpkin = "🎃"
    /// The remix mark.
    static let remixMark = "RMX"
    /// new (D39): clean or dirty, as a small mark where it is known (the crate file's `lyrics` fact). A placeholder
    /// until the copy audit.
    static let cleanMark = "clean"
    static let dirtyMark = "dirty"
    static func lyricsMark(_ lyrics: String) -> String? { lyrics == "clean" ? cleanMark : (lyrics == "dirty" ? dirtyMark : nil) }

    // MARK: a crate file with no fingerprints (the playing panel)

    static let setByHandTitle = "Set the song by hand"
    static let noFingerprints = "Deckie cannot name what is playing from this crate file yet: it has no song fingerprints."
    static let setByHandHow = "Tap a song in the Crate tab to set it as playing."
    static let chooseSong = "Choose a song"
    /// The status corner when nothing can be recognised.
    static let notListening = "not listening"

    // MARK: the Listen page: the picks (Up next)

    /// The group labels, shown in capitals.
    static let groupNext = "Next", groupPicks = "Picks", groupMore = "More"
    /// When the filter leaves nothing: "Switch on CD1, CD2 or All above." / "No good matches in CD1+CD2."
    static func switchOn(_ choices: String) -> String { "Switch on \(choices) above." }
    static func noGoodMatches(_ filter: String) -> String { "No good matches in \(filter)." }
    /// The "All" chip, and "All" in the sentence above.
    static let all = "All"
    /// More's search: its placeholder, its clear button (spoken), and nothing found.
    static let searchMore = "Search More by title or artist"
    static let clearSearch = "Clear search"
    static func nothingMatches(_ q: String) -> String { "Nothing in More matches \u{201C}\(q)\u{201D}." }
    /// Where the shortlist ends in More.
    static let restOfCrate = "rest of the crate, by score"
    /// A pick's BPM line: "128 BPM · pitch +3.2%", with "(x1/2)" for a half- or double-time join.
    static func pitchAfterBPM(_ bpm: String, _ pitch: String) -> String { b("pick.pitchAfterBPM", ["bpm": bpm, "pitch": pitch]) }
    static func tempoMultiple(_ m: String) -> String { b("pick.tempoMultiple", ["m": m]) }
    /// The join's pitch words (JoinInfo.pitchText; not on screen at present).
    static let pitchCutIn = b("pick.pitch.cutIn")
    static func pitchCaps(_ pitch: String) -> String { b("pick.pitch.caps", ["pitch": pitch]) }
    static func pitchMultiple(_ m: String) -> String { b("pick.pitch.multiple", ["m": m]) }
    static let pitchNA = b("pick.pitch.na")
    static func pitchAside(_ pitch: String) -> String { b("pick.pitch.aside", ["pitch": pitch]) }
    /// A pick's move line: "blend", "echo out · keys may clash", "no beat-match · brake".
    static let noBeatMatch = b("pick.noBeatMatch")
    static let keyClash = b("pick.keyClash")
    /// The brake move's label, and the shorter word the move line uses for it.
    static let brakeCut = b("pick.move.brake_cut"), brake = b("pick.brake")
    static let movesJoin = b("pick.movesJoin")
    static let moveLineJoin = b("pick.moveLineJoin")
    /// The Simple / Full switch and the Shuffle dial.
    static let simple = "Simple", full = "Full"
    static let modeJoin = "/"
    static let shuffle = "Shuffle"
    static func percent(_ n: Int) -> String { "\(n)%" }
    /// A pitch's sign, then the number to one place: "+3.2", "−1.0", "±0.0" (everywhere a pitch shows).
    static let signPlus = b("pick.sign.plus"), signMinus = b("pick.sign.minus"), signNone = b("pick.sign.none")
    static func signed(_ sign: String, _ value: Double) -> String { b("pick.signed", ["sign": sign, "value": String(format: "%.1f", value)]) }
    /// A signed pitch with its percent sign: "+3.2%".
    static func percentText(_ s: String) -> String { s + "%" }
    /// A pick's join wave: spoken hint, the count of start points, and the card's spoken hint.
    static let tryAnotherStart = "Tap to try another start point of the next song"
    static func syncs(_ n: Int) -> String { "\(n) syncs" }
    static let tapToUnpin = "Tap to unpin"
    static let tapToPin = "Tap to pin as next, long-press for why"
    /// The long-press detail of a pick.
    static func artistSong(_ artist: String, _ song: String) -> String { "\(artist) – \(song)" }
    static func keyLine(_ key: String, _ keys: String, _ verdict: String) -> String { "Key \(key) · \(keys) \(verdict)" }
    static let unknownKey = b("song.keyUnknown")
    /// The two songs' keys in the detail: "8A → 9A", "Home note A → 9A".
    static func keysArrow(_ a: String, _ c: String) -> String { b("pick.keys", ["a": a, "b": c]) }
    // new (D36): the key's other states, where a key shows (the Crate tab's rows, a pick's detail, the picks' move
    // line). Placeholders until the copy audit.
    /// A home note in place of the wheel code: "Home note A" (Desk's words, `DeskWords` "homeNote").
    static func homeNote(_ note: String) -> String { b("song.homeNote", ["note": note]) }
    /// A row's key when Deckie read the song and was not sure of it (a key never read stays "?").
    static let keyNotSureShort = b("song.keyNotSure")
    /// A pick's detail, for the song it is about, when it has no key: Deckie was not sure, or no key was read.
    static let keyNotSureLine = "Deckie is not sure of this song's key"
    static let keyNotReadLine = "Key not read yet"
    /// A pick's detail for a song with a home note: "Home note A · Home note A → 9A fits on the home note, …".
    static func homeNoteLine(_ homeNote: String, _ keys: String, _ verdict: String) -> String { "\(homeNote) · \(keys) \(verdict)" }
    /// The detail's verdict for a pair where a song has only its home note and the keys on it fit; and for a pair
    /// where a song's key Deckie was not sure of (the scoring leaves the key out of both kinds of pair alike).
    static let verdictHomeNote = b("pick.verdict.homeNote")
    static let verdictKeyNotSure = b("pick.verdict.keyNotSure")
    /// The picks' move line, for a pair that fits on a home note: "blend · home note". The fit was counted at the
    /// home note's lower weight, and the line says so rather than showing nothing, as for a key that was read.
    static let moveHomeNote = b("pick.moveHomeNote")
    static func pitchHelp(_ pitch: String) -> String { "Pitch: set the incoming deck's pitch fader to \(pitch) so the tempos match." }
    static let notAvailable = "n/a"
    static func matchScore(_ s: Double, _ stretch: Double) -> String { String(format: "Match score %.2f · %.1f%% stretch", s, stretch) }
    static func moves(_ moves: [String]) -> String {
        "Moves: " + moves.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "   ")
    }
    static func reason(_ r: String) -> String { "• " + r }
    /// The Halloween and remix marks, spoken.
    static func marksSpoken(halloween: Bool, remix: Bool) -> String { (halloween ? "Halloween " : "") + (remix ? "remix" : "") }
    /// The join wave: the first sync point's mark, and the whole wave spoken.
    static let syncMark = "sync"
    static func joinSpoken(_ a: String, _ b: String, _ from: String) -> String { "Join: end of \(a) over \(b) from \(from)" }
    /// The key verdicts in words (by the verdict's code).
    static func verdictPhrase(_ v: String) -> String {
        switch v {
        case "same key": return "same key"
        case "neighbour": return "neighbour key"
        case "relative": return "relative key"
        case "boost": return "key boost"
        case "clash": return "keys may clash"
        case "key unsure": return "key unsure"
        default: return v
        }
    }
    /// Where the next song could come in (a pick's start points).
    static let startMixIn = "mix-in start", startTrack = "track start", startSteady = "steady beat"
    static func startBar(_ n: Int) -> String { "bar \(n)" }
    /// What is unexpected about a pick, as its corner chip says it.
    static let tagHalfTime = b("pick.tag.halfTime"), tagDoubleTime = b("pick.tag.doubleTime"), tagTempoChange = b("pick.tag.tempoChange")
    static func tagTempoMultiple(_ m: String) -> String { b("pick.tag.tempoMultiple", ["m": m]) }
    static let tagHalloween = b("pick.tag.halloween")
    static func tagTo(_ disc: String) -> String { b("pick.tag.to", ["source": disc]) }
    static let tagInCrate = b("pick.tag.inCrate")
    static func tagIn(_ folder: String) -> String { b("pick.tag.in", ["folder": folder]) }
    static let tagDeepCut = b("pick.tag.deepCut")
    /// The moves by the crate file's code (the picks' move line and the detail).
    static let moveLabels = BoothWords.moveLabels

    // MARK: the Crate tab

    static let foldersShelf = "Folders"
    static let crateHelp = "tap a song to set it as playing"
    static let show = "Show"
    static let compact = "Compact", details = "Details"
    static let noSongsYet = "No songs yet."
    /// A heading's count: "Stick 3  ·  42", "Stick 3  ·  42 songs".
    static func shelfCount(_ name: String, _ n: Int) -> String { name + "  ·  \(n)" }
    static func shelfSongs(_ name: String, _ n: Int) -> String { name + "  ·  \(n) songs" }
    /// A folder that goes on at the top of the next column.
    static let continued = "  (cont.)"
    /// A row's artist and version: "Artist · Extended mix".
    static func artistVersion(_ artist: String, _ version: String) -> String { artist + (version.isEmpty ? "" : " · " + version) }
    /// A tempo in a row: "128".
    static func bpmNumber(_ value: Double) -> String { String(format: "%.0f", value) }

    // MARK: opening a crate file

    static let openCrateFile = "Open crate file"
    static func opened(_ name: String, songs: Int) -> String {
        "\(name) is open: \(songs) song\(songs == 1 ? "" : "s")."
    }
    static func couldNotOpen(_ fileName: String) -> String { "Could not open \(fileName)" }
    /// The alert's message: the plain sentence, then the reader's own words.
    static func openProblem(_ why: String, _ detail: String) -> String { why + "\n\n" + detail }

    /// What went wrong, in plain words, from the reader's problem. The reader's own words follow as a detail.
    static func whyNotOpened(_ error: Error) -> String {
        let said = (error as? CrateError)?.description ?? error.localizedDescription
        if said.contains("cut short") {
            return "This crate file is not complete. It may not have finished copying or downloading. Send it again."
        }
        if said.contains("compressed") {
            return "Another program has changed this crate file, so it cannot be opened. Make it again with Deckie and send that one."
        }
        if said.contains("min_reader") {
            return "This crate file was made by a newer Deckie. Update this app to open it."
        }
        if said.contains("is not a crate file") || said.hasPrefix("manifest.json: is missing") {
            return "This is not a crate file. A crate file is the .deckie file that Deckie makes."
        }
        if said.contains("is not there") || said.contains("could not be read") || error is CocoaError {
            return "This crate file could not be read. If it is in iCloud Drive, check that the iPad is online, then try again."
        }
        return "This crate file is damaged, so it cannot be opened. Make it again with Deckie and send it again."
    }
    /// The reader's own description, for the detail line.
    static func detail(_ error: Error) -> String {
        (error as? CrateError)?.description ?? error.localizedDescription
    }

    // MARK: the test and details sheet (the playing panel's "…")

    static let debugTitle = "Debug"
    static let done = "Done"
    static let testWithFileSection = "Test with file"
    static func startAt(_ s: Int) -> String { "Start at \(s) s" }
    static let playItAs = "Play it as"
    /// How a test file is played, by its code.
    struct Rendering: Hashable { let code: String; let words: String }
    static let renders: [Rendering] = [
        .init(code: "o", words: "original"), .init(code: "r-8", words: "vinyl −8"), .init(code: "r-4", words: "vinyl −4"), .init(code: "r+4", words: "vinyl +4"), .init(code: "r+8", words: "vinyl +8"),
        .init(code: "t-4", words: "tempo −4"), .init(code: "t+4", words: "tempo +4"), .init(code: "t+8", words: "tempo +8")]
    static let keepGoing = "Keep going (simulate playing)"
    static let chooseAudioFile = "Choose an audio file…"
    static let setRecording = "Set recording"
    static let recordWhileListening = "Record while listening"
    static let setFilesWhere = "Files: Files app > On My iPad > Deckie > Sets (or Finder > iPad > Files)."
    static let status = "Status"
    static let matches = "Matches"
    static let lastLatency = "Last match latency"
    static func milliseconds(_ ms: Double) -> String { String(format: "%.0f ms", ms) }
    static let timeToRecognise = "Time to recognise current song"
    static func seconds(_ s: Double) -> String { String(format: "%.1f s", s) }
    static let pitch = "Pitch"
    static func pitchValue(_ pitch: String, _ kind: String, _ from: String) -> String { "\(pitch)% \(kind) (\(from))" }
    static let backToMic = "Back to the microphone"
    static let log = "Log"
    static let inputLevel = "Input level"

    // MARK: new (D35): which recogniser names the song. Placeholders pending the copy and design passes. Nothing
    // leaves the iPad with either, so the booth says "Deckie" and "Apple", never a name that sounds like an online
    // service.

    /// The playing panel while Deckie's index is made from the crate file's fingerprints (once for each crate file).
    static let preparingTitle = "Getting ready to listen"
    static func preparingBody(_ songs: Int) -> String {
        "Reading the fingerprints of \(songs) song\(songs == 1 ? "" : "s"). This happens once for each crate file."
    }
    /// The status corner meanwhile.
    static let preparingStatus = "getting ready"
    /// The details sheet: the choice of recogniser, and what is in use.
    static let recogniseSection = "Recognise with"
    static let recogniseWith = "Recognise songs with"
    static func hearingName(_ h: Hearing) -> String {
        switch h {
        case .deckie: return "Deckie"
        case .apple: return "Apple"
        case .both: return "Both, to compare"
        }
    }
    static let recogniseHelp = "Both recognise on the iPad. With both, Deckie's names the song on screen and the set's log compares the two."
    static let inUse = "In use"
    static let onlyDeckie = "Deckie (this crate file has Deckie's fingerprints only)"
    static let onlyApple = "Apple (this crate file was made before Deckie's fingerprints)"
    static let neither = "Neither (this crate file has no fingerprints)"
    static let deckieIndex = "Deckie's index"
    static func indexReady(_ songs: Int, _ mb: Double, _ setting: String) -> String { String(format: "%d songs · %.1f MB on the iPad · %@", songs, mb, setting) }
    static func indexPreparing(_ songs: Int) -> String { "being made from \(songs) songs" }
    static let indexNone = "none"
    static let indexFailed = "could not be made"
    static let appMemory = "App memory"
    static func megabytes(_ mb: Double) -> String { String(format: "%.0f MB", mb) }
    /// How the pitch was found, for the details sheet's pitch line.
    static let speedFromDeckie = b("heard.speedFromDeckie")
    /// Compare mode's summary, in the details sheet.
    static let compareSection = "Deckie and Apple compared"
    static func compareSummary(deckie: Int, apple: Int, deckieFirst: Int, appleFirst: Int, disagreed: Int, atChange: Int) -> String {
        "This set: Deckie named \(deckie) song\(deckie == 1 ? "" : "s"), Apple \(apple); Deckie first \(deckieFirst) time\(deckieFirst == 1 ? "" : "s"), Apple \(appleFirst); disagreed \(disagreed) time\(disagreed == 1 ? "" : "s")"
            + (disagreed == 0 ? "." : atChange == disagreed ? ", each as one song gave way to the next." : ", \(atChange) of them as one song gave way to the next.")
    }
    static let compareNotOn = "Choose both above to compare them on the next set."

    // MARK: new: the first-run screen (FirstRun.swift), shown whenever no crate file is open

    /// Lines are set by phrase (voice.md, "Line breaks"): each is one line of its own, and its last two words never
    /// part, so no line ends with one word alone at any width the screen gives it.
    static func phrases(_ lines: String...) -> String { lines.map(keepLastTwo).joined(separator: "\n") }
    /// The last two words of a line joined by a space that does not break.
    static func keepLastTwo(_ line: String) -> String {
        guard let r = line.range(of: " ", options: .backwards) else { return line }
        return line.replacingCharacters(in: r, with: "\u{00A0}")
    }

    /// The name at the top.
    static let firstRunName = "Deckie"
    /// What the app is waiting for.
    static let firstRunWaiting = keepLastTwo("No crate file open yet")
    /// What the app does, in one sentence.
    static let firstRunWhat = phrases("Deckie listens to the room,", "names the song that's playing,",
                                      "and shows what could come next", "and how to mix it in.")
    /// The three steps: a heading each, and a note under it.
    struct Step: Hashable { let title: String; let note: String }
    static let firstRunSteps: [Step] = [
        Step(title: keepLastTwo("Get Deckie Desk on your computer"),
             note: phrases("For Mac or Windows PC,", "from deckie.io.")),
        Step(title: keepLastTwo("Let it read your music"),
             note: phrases("Desk writes a crate file:", "what it learns about your songs,", "never the songs themselves.")),
        Step(title: keepLastTwo("Send the crate file to this iPad"),
             note: phrases("By AirDrop, or save it to Files", "and open it here.")),
    ]
    /// A step's number, spoken with its heading.
    static func stepNumber(_ n: Int) -> String { "\(n)" }
    static func stepSpoken(_ n: Int, _ title: String, _ note: String) -> String { "Step \(n). \(title). \(note)" }
    /// The main button: the system's chooser for a crate file.
    static let openACrateFile = "Open a crate file"
    /// Only when a demo crate file comes with the app (DemoCrate).
    static let tryTheDemo = "Try the demo crate"
    /// Under the buttons, with the demo crate: what it needs.
    static let tryTheDemoNote = phrases("No music of your own needed:", "the demo crate's songs play from deckie.io/demo",
                                        "on another device.")
    /// The Listen page while the demo crate is open and no song is named yet.
    static let demoHow = phrases("This is the demo crate.", "On a phone or laptop, open deckie.io/demo,",
                                 "press play, and put it near this iPad.")
    /// Back to the first-run screen, from the Listen page and the Crate tab while the demo crate is open.
    static let leaveTheDemo = "Leave the demo crate"
    /// The note after the demo crate opens.
    static func demoOpened(songs: Int) -> String { "The demo crate is open: \(songs) songs. Play deckie.io/demo nearby." }
    /// The link to the site, and where it goes.
    static let siteLink = "deckie.io"
    static let siteSpoken = "Open deckie.io in Safari"
    static let siteURL = URL(string: "https://deckie.io")!
    /// The privacy line at the foot.
    static let firstRunPrivacy = phrases("Your music stays on your devices.", "No account. No upload.")

    // MARK: new: Credits (CreditsView.swift; the first-run screen's foot and the Crate tab's info button)

    static let credits = "Credits"
    static let creditsMaker = "Deckie by App Hold Media"
    static func creditsVersion(_ version: String, _ build: String) -> String { "Deckie \(version) (\(build))" }
    static let creditsOpenSourceSection = "Open-source software"
    /// When the app carries no one else's code (today): said plainly, and nothing listed.
    static let creditsNoneYet = phrases("This app is Deckie's own code,", "on the frameworks that come with iPadOS.",
                                        "It carries no open-source parts from others yet,", "so there is nothing to list here.")
    static let creditsPrivacySection = "Privacy"
    static let creditsPrivacy = phrases("Deckie hears the room on this iPad.", "The sound never leaves it,",
                                        "and there is no account.")
    /// An entry's version and licence: "1.2 · MIT".
    static func creditsLine(_ version: String, _ licence: String) -> String { version.isEmpty ? licence : version + " · " + licence }
    static let creditsLicenceText = "Licence"
    /// The demo crate's songs (Credits.demoSongs), each with its artist, licence and where it came from.
    static let creditsDemoSection = "Songs in the demo crate"
    static let creditsDemoNote = phrases("The demo crate holds these songs' facts", "and fingerprints, never the songs.",
                                         "deckie.io/demo plays them.")
    static func creditsDemoLine(_ artist: String, _ licence: String) -> String { artist + " · " + licence }
    static let creditsSource = "Source"

    // MARK: new (D35, note of Nov 14): letting go. A placeholder pending the copy pass.

    /// The status corner when Deckie's has not heard the playing song for a few seconds (talk, noise, the music
    /// stopped) and the room is not quiet; in a quiet room the corner says "paused", as before. The song stays on
    /// screen with its picks, its names dimmed.
    static let statusNotHeard = " · not heard just now"
}
