import Foundation
import DeckieDesk

/// Every word Deckie Desk shows, by name: labels, buttons, menu items, help, messages and errors. The words themselves
/// are one list for Desk on every computer, `DeskWords.table` in the shared core (D28, D32); this file gives the Mac's
/// views a name for each and writes the numbers in, so the views hold no words of their own and the copy audit changes
/// that table only.
enum Words {
    private static func w(_ key: String, _ values: [String: String] = [:]) -> String { DeskWords.text(key, values) }
    private static func n(_ key: String, _ count: Int, _ values: [String: String] = [:]) -> String {
        DeskWords.count(key, count, values)
    }

    // MARK: naming a song (research AA): the words by name, from the one list
    /// A word of the list by its name, with blanks filled; for the naming screens, whose words are many and plain.
    static func t(_ key: String, _ values: [String: String] = [:]) -> String { w(key, values) }
    /// A word's form for a count.
    static func c(_ key: String, _ count: Int, _ values: [String: String] = [:]) -> String { n(key, count, values) }
    /// The small line under a fact: where it came from, Desk's guess, checked, or not found.
    static func fromLine(_ f: DeskNaming.Fact) -> String {
        guard f.value != nil else { return w("factNotFound") }
        let from = f.from.map { DeskWords.coded("factFrom", $0) } ?? w("factNotFound")
        if f.checked { return w("factChecked", ["from": from]) }
        if f.guess { return w("factGuess", ["from": from]) }
        return from
    }

    // MARK: the app
    static let appName = w("appName")
    static let ok = w("ok")
    static let cancel = w("cancel")
    static let done = w("done")
    static let nameField = w("nameField")

    // MARK: the first screen
    static let firstTitle = w("firstTitle")
    static let firstBody = w("firstBody")
    static let addMusic = w("addMusic")
    static func addMusicTo(_ crate: String) -> String { w("addMusicTo", ["crate": crate]) }
    static let addMusicMore = w("addMusicMore")
    static let withRekordbox = w("withRekordbox")
    static let withRekordboxMenu = w("withRekordboxMenu")
    static let importCrateFile = w("importCrateFile")
    static let exportCrateFile = w("exportCrateFile")
    static let sendToIPad = w("sendToIPad")

    // MARK: Add music
    static let noDriveFound = w("noDriveFound")
    static let chooseFolder = w("chooseFolder")
    static let addMusicHelp = w("addMusicHelp")
    static let chooseSourceMessage = w("chooseSourceMessage")
    static let chooseSourcePrompt = w("chooseSourcePrompt")
    static let rekordboxMessage = w("rekordboxMessage")
    static let rekordboxFolderMessage = w("rekordboxFolderMessage")
    static let start = w("start")

    // MARK: while it works
    static let runTitle = w("runTitle")
    static func runReading(_ read: String, into crate: String) -> String { w("runReading", ["read": read, "crate": crate]) }
    static func songsOf(_ done: Int, _ total: Int) -> String { n("songsOf", total, ["done": "\(done)", "total": "\(total)"]) }
    static func timeLeft(_ seconds: Double) -> String {
        if seconds < 45 { return w("timeLeftUnderMinute") }
        return n("timeLeft", max(1, Int((seconds / 60).rounded())))
    }
    static let stageReading = w("stageReading")
    static let stageFinishing = w("stageFinishing")
    static let stageSaving = w("stageSaving")
    static func lineStarted(files: Int, unchanged: Int, queued: Int) -> String {
        n("lineStarted", files, ["unchanged": "\(unchanged)", "queued": "\(queued)"])
    }
    static func lineRead(_ rel: String, seconds: Double) -> String { w("lineRead", ["rel": rel, "seconds": String(format: "%.1f", seconds)]) }
    static func lineReadBefore(_ rel: String) -> String { w("lineReadBefore", ["rel": rel]) }
    static func lineNotRead(_ rel: String, reason: String) -> String {
        w("lineNotRead", ["rel": rel, "reason": Words.reason(reason).lowercased()])
    }

    // MARK: the finished screen
    static func finishedTitle(_ read: String, _ crate: String) -> String { w("finishedTitle", ["read": read, "crate": crate]) }
    static func wentIn(_ count: Int) -> String { n("wentIn", count) }
    static let everySongWentIn = w("everySongWentIn")
    static func didntGoIn(_ count: Int) -> String { n("didntGoIn", count) }
    static func foldersLeftOut(_ count: Int) -> String { n("foldersLeftOut", count) }
    static func took(_ seconds: Double, perMinute: Double) -> String {
        w("took", ["duration": duration(seconds), "rate": rate(perMinute)])
    }
    static let nextStep = w("nextStep")
    static let seeSongs = w("seeSongs")
    static let whatDidntGoIn = w("whatDidntGoIn")

    /// What the run took from what is already on this computer (D30).
    static func keysLine(_ counts: [(origin: String, n: Int)]) -> String {
        w("keysLine", ["counts": join("join.keysCounts", counts.map { w("keysCount", ["n": "\($0.n)", "from": keyFrom($0.origin)]) })])
    }
    static func keysNone(_ count: Int) -> String { n("keysNone", count) }
    /// new (D36): of the songs with no key, those Deckie read and is not sure of; and the songs with a home note.
    static func keysNotSure(_ count: Int) -> String { n("keysNotSure", count) }
    static func keysHomeNote(_ count: Int) -> String { n("keysHomeNote", count) }
    static func keysDisagree(_ count: Int) -> String { n("keysDisagree", count) }
    static func needName(_ count: Int) -> String { n("needName", count) }
    static let everySongHasAName = w("everySongHasAName")
    static let showThem = w("showThem")
    static let rekordboxLocked = w("rekordboxLocked")
    static let rekordboxExportNotRead = w("rekordboxExportNotRead")
    static func librariesRead(_ names: [String]) -> String { w("librariesRead", ["names": join("join.libraries", names)]) }
    static func couldntReadLibrary(_ detail: String) -> String { w("couldntReadLibrary", ["detail": detail]) }

    // MARK: a run that stopped
    static func stoppedReading(_ read: String) -> String { w("stoppedReading", ["read": read]) }
    static let carryOn = w("carryOn")
    static func putBack(_ read: String) -> String { w("putBack", ["read": read]) }

    // MARK: the crate menu
    static let crateMenuHelp = w("crateMenuHelp")
    static let newCrate = w("newCrate")
    static let renameCrate = w("renameCrate")
    static let deleteCrate = w("deleteCrate")
    static func renameTitle(_ name: String) -> String { w("renameTitle", ["name": name]) }
    static func deleteCrateTitle(_ name: String) -> String { w("deleteCrateTitle", ["name": name]) }
    static let deleteCrateBody = w("deleteCrateBody")
    static let delete = w("delete")

    // MARK: the toolbar
    static let sources = w("sources")
    static let hideSources = w("hideSources")
    static let showSourcesMenu = w("showSourcesMenu")
    static let sourcesHelp = w("sourcesHelp")
    static let sendHelp = w("sendHelp")

    // MARK: the bottom line
    static func songs(_ count: Int) -> String { n("songs", count) }
    static func cantBeRecognised(_ count: Int) -> String { w("cantBeRecognised", ["n": "\(count)"]) }
    static func filesDidntGoIn(_ count: Int) -> String { n("filesDidntGoIn", count) }
    static func needNameCount(_ count: Int) -> String { n("needNameCount", count) }
    static let showAllSongs = w("showAllSongs")
    static let onlyNeedName = w("onlyNeedName")

    // MARK: the table
    static let colTitle = w("colTitle")
    static let colArtist = w("colArtist")
    static let colTempo = w("colTempo")
    static let colKey = w("colKey")
    static let colBars = w("colBars")
    static let colLength = w("colLength")
    static let colVocals = w("colVocals")
    static let colWhere = w("colWhere")
    static let colNotes = w("colNotes")
    static let notSureOfKey = w("notSureOfKey")
    static let colKeyFrom = w("colKeyFrom")
    static let needsNameNote = w("needsNameNote")
    static let topOfMusicFolder = w("topOfMusicFolder")
    static func damagedFrames(_ count: Int) -> String { n("damagedFrames", count) }
    static let gridUnsure = w("gridUnsure")
    static let vocalsNotRead = w("vocalsNotRead")
    static let signed = w("signed")
    static let none = w("none")

    // MARK: the inspector
    static let names = w("names")
    static let title = w("title")
    static let artist = w("artist")
    static let version = w("version")
    static let tags = w("tags")
    static let whereLabel = w("whereLabel")
    static func whereWithPlaces(_ count: Int) -> String { w("whereWithPlaces", ["n": "\(count)"]) }
    static let alsoInYourCrateAs = w("alsoInYourCrateAs")
    static let whatDeskFound = w("whatDeskFound")
    static let rowFile = w("rowFile")
    static let rowTempo = w("rowTempo")
    static func tempoValue(bpm: Double, bars: Int, firstDownbeat: Double) -> String {
        w("tempoValue", ["bpm": String(format: "%.2f", bpm), "bars": "\(bars)", "downbeat": String(format: "%.2f", firstDownbeat)])
    }
    static let rowTempoChanges = w("rowTempoChanges")
    static func segments(_ count: Int) -> String { w("segments", ["n": "\(count)"]) }
    static let rowKey = w("rowKey")
    static let keyNotSure = w("keyNotSure")
    static let rowNameFrom = w("rowNameFrom")
    static let keyNotRead = w("keyNotRead")
    /// new (D36): the home note where a key shows ("Home note A"), what it means, and a song Deckie read and is not
    /// sure of, as distinct from one whose key was not read.
    static func homeNote(_ note: String) -> String { w("homeNote", ["note": note]) }
    static func homeNoteHelp(minor: String, major: String) -> String { w("homeNoteHelp", ["minor": minor, "major": major]) }
    static let keyDeckieNotSure = w("keyDeckieNotSure")
    /// new (D36): a song's cover in the names panel, read out: the picture, and the empty square of a song without one.
    static let cover = w("cover")
    static let noCover = w("noCover")
    static func keySays(_ origin: String, _ camelot: String) -> String {
        w("keySays", ["program": programName(origin), "camelot": camelot])
    }
    static func keyFrom(_ source: String) -> String { DeskWords.coded("keyFrom", source) }
    /// The short form, for the table's column.
    static func programName(_ source: String) -> String { DeskWords.coded("programName", source) }
    static func nameFrom(_ source: String) -> String {
        source.split(separator: "+").map { part -> String in
            DeskWords.table["nameFromPart.\(part)"] ?? programName(String(part))
        }.joined(separator: w("nameFromJoin"))
    }
    static let rowKeyChanges = w("rowKeyChanges")
    static func keyFromBar(_ camelot: String, _ bar: Int) -> String { w("keyFromBar", ["camelot": camelot, "bar": "\(bar)"]) }
    static let rowLoudness = w("rowLoudness")
    static func loudnessValue(lufs: Double, peak: Double) -> String {
        w("loudnessValue", ["lufs": String(format: "%.1f", lufs), "peak": String(format: "%.1f", peak)])
    }
    static let rowMixWindows = w("rowMixWindows")
    static func mixWindows(inFrom: Int, inTo: Int, outFrom: Int, outTo: Int) -> String {
        w("mixWindows", ["inFrom": "\(inFrom)", "inTo": "\(inTo)", "outFrom": "\(outFrom)", "outTo": "\(outTo)"])
    }
    static let rowSections = w("rowSections")
    static let rowVocals = w("rowVocals")
    static func vocalsValue(_ mean: Double, heavy: Bool) -> String {
        let value = w("vocalsValue", ["percent": String(format: "%.0f%%", mean * 100)])
        return heavy ? w("vocalsWithHeavy", ["vocals": value, "heavy": w("vocalsHeavy")]) : value
    }
    static let rowEngine = w("rowEngine")
    static func engineOn(_ engine: String, _ device: String) -> String { w("engineOn", ["engine": engine, "device": device]) }
    static let rowSignatures = w("rowSignatures")
    static let noneYet = w("noneYet")
    static let rowDamagedFrames = w("rowDamagedFrames")
    static let selectSong = w("selectSong")
    static func songsSelected(_ count: Int) -> String { w("songsSelected", ["n": "\(count)"]) }
    static func musicAt(_ path: String) -> String { w("musicAt", ["path": path]) }
    static let whereIsThisMusic = w("whereIsThisMusic")
    static let musicFolderMessage = w("musicFolderMessage")

    // MARK: the Sources panel
    static let sourcesTitle = w("sourcesTitle")
    static let sourcesCaption = w("sourcesCaption")   // new (D31)
    static let nothingReadYet = w("nothingReadYet")
    static let sourcesEmptyBody = w("sourcesEmptyBody")
    static func sourceLine(_ name: String, songs count: Int) -> String { n("sourceLine", count, ["name": name]) }
    static let topFolder = w("topFolder")
    static func alsoIn(_ places: String) -> String { w("alsoIn", ["places": places]) }
    static let fixHint = w("fixHint")
    static let moveUp = w("moveUp")
    static let moveDown = w("moveDown")
    static let rename = w("rename")
    static func renameFolderTitle(_ f: String) -> String { w("renameFolderTitle", ["folder": f]) }
    static let removeFromCrate = w("removeFromCrate")
    static func removeTitle(_ source: String, _ crate: String) -> String { w("removeTitle", ["source": source, "crate": crate]) }
    static func removeBody(_ count: Int) -> String { n("removeBody", count) }
    static let remove = w("remove")
    static let musicFolderName = w("musicFolderName")
    static let removeMusicFolder = w("removeMusicFolder")

    // MARK: what didn't go in
    static func readOn(_ by: String, _ at: String, seen: Int, songs: Int) -> String {
        w("readOn", ["by": by, "at": at, "seen": "\(seen)", "songs": "\(songs)"])
    }
    static let noRecord = w("noRecord")
    static func reasonCount(_ reason: String, _ count: Int) -> String {
        w("reasonCount", ["reason": Words.reason(reason), "n": "\(count)"])
    }
    static func reason(_ r: String) -> String {
        DeskWords.table["reason.\(r)"] ?? r.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: keys and names from this computer (D30)
    static let lookAgain = w("lookAgain")
    static let chooseLibrary = w("chooseLibrary")
    static let chooseLibraryMessage = w("chooseLibraryMessage")
    static func libraryChosen(_ source: String) -> String { w("libraryChosen", ["program": programName(source)]) }
    static func lookedAgain(_ lines: [String]) -> String { join("join.lookedAgain", lines) }
    static let undoLookAgain = w("undoLookAgain")

    // MARK: undo (shown in the Edit menu after "Undo")
    static let undoNameFix = w("undoNameFix")
    static let undoRename = w("undoRename")
    static let undoMove = w("undoMove")
    static let undoRemove = w("undoRemove")

    // MARK: messages and errors
    static func couldntOpen(_ detail: String) -> String { w("couldntOpen", ["detail": detail]) }
    static func couldntSave(_ detail: String) -> String { w("couldntSave", ["detail": detail]) }
    static func runStopped(_ detail: String) -> String { w("runStopped", ["detail": detail]) }
    static func couldntExport(_ detail: String) -> String { w("couldntExport", ["detail": detail]) }
    static func couldntRename(_ detail: String) -> String { w("couldntRename", ["detail": detail]) }
    static func couldntDelete(_ detail: String) -> String { w("couldntDelete", ["detail": detail]) }
    static let nothingToSendYet = w("nothingToSendYet")
    static let exportMessage = w("exportMessage")
    static let importMessage = w("importMessage")

    // MARK: words built from parts (D36): the templates, so no view joins words of its own
    /// Items joined by the word named `key` (DeskWords' `join.*`): separators are words too.
    static func join(_ key: String, _ items: [String]) -> String { items.joined(separator: w(key)) }
    static func places(_ places: [String]) -> String { join("join.places", places) }
    static func keyHelp(_ parts: [String]) -> String { join("join.keyHelp", parts) }
    static func keyHelpFirst(_ camelot: String, from source: String) -> String { w("keyHelpFirst", ["camelot": camelot, "from": keyFrom(source)]) }
    static func notesLine(_ notes: [String]) -> String { join("join.notes", notes) }
    static func leftOut(_ items: [String]) -> String { join("join.leftOut", items) }
    static func lookupWhat(_ items: [String]) -> String { join("join.lookupWhat", items) }
    static func lookupNotes(_ items: [String]) -> String { join("join.lookupNotes", items) }
    static func sentFields(_ items: [String]) -> String { join("join.sentFields", items) }
    static func alsoInPlaces(_ items: [String]) -> String { join("join.alsoIn", items) }
    static func wallSong(_ parts: [String]) -> String { join("join.wallSong", parts) }
    static func keysFigure(_ parts: [String]) -> String { join("join.keysFigure", parts) }
    static func keyChanges(_ items: [String]) -> String { join("join.keyChanges", items) }
    static func sections(_ items: [String]) -> String { join("join.sections", items) }
    static func signatures(_ items: [String]) -> String { join("join.signatures", items) }
    static func damagedAtList(_ items: [String]) -> String { join("join.damagedFrames", items) }
    static func moreFactLine(_ name: String, _ value: String) -> String { w("moreFactLine", ["name": name, "value": value]) }
    static func fileTagLine(_ name: String, _ value: String) -> String { w("fileTagLine", ["name": name, "value": value]) }
    static func lookupScopeNeed(_ n: Int) -> String { w("lookupScope.need", ["label": w("lookupChoice.needsName"), "n": "\(n)"]) }
    static func lookupScopeSong(_ title: String) -> String { w("lookupScope.song", ["label": w("lookupChoice.song"), "title": title]) }
    static func lookupScopeSelection(_ n: Int) -> String { w("lookupScope.selection", ["label": w("lookupChoice.selection"), "n": "\(n)"]) }
    static func lookupScopeDisc(_ source: String) -> String {
        w("lookupScope.disc", ["label": w("lookupDisc").replacingOccurrences(of: "…", with: ""), "source": source])
    }
    static func lookupCountLine(_ progress: String, found: String) -> String { w("lookupCountLine", ["progress": progress, "found": found]) }
    static func lookupOutcomeFailed(_ outcome: String, failure: String) -> String { w("lookupOutcomeFailed", ["outcome": outcome, "failure": failure]) }
    static func lookupUseThisLabel(_ title: String) -> String { w("lookupUseThisLabel", ["label": w("lookupUseThis"), "title": title]) }
    static func lookupCandidateTitle(_ title: String, version: String?) -> String {
        version.map { w("lookupCandidateTitle", ["title": title, "version": $0]) } ?? title
    }
    static func lookupTickField(_ field: String) -> String { w("lookupTickField", ["field": field]) }
    static func lookupTickBefore(_ before: String) -> String { w("lookupTickBefore", ["before": before]) }
    static func lookupTickNote(_ note: String) -> String { w("lookupTickNoteMac", ["note": note]) }
    static func toolSongTitle(_ number: Int?, _ title: String) -> String {
        number.map { w("toolSongTitle", ["number": twoDigits($0), "title": title]) } ?? title
    }
    static func toolChangeNote(_ note: String) -> String { w("toolChangeNoteMac", ["note": note]) }
    static func wallLabel(_ title: String, songs count: Int) -> String { w("wallLabel", ["title": title, "songs": songs(count)]) }
    static func figureLabel(_ figure: String, _ text: String) -> String { w("figureLabel", ["figure": figure, "text": text]) }
    static func keyWithDoubt(_ key: String, doubt: String) -> String { w("keyWithDoubt", ["key": key, "doubt": doubt]) }
    static func askDiscNameBodyAfterTitle() -> String { w("askDiscNameBodyAfterTitle", ["body": w("askDiscNameBody")]) }
    static func copyPlace(_ place: String) -> String { w("copyPlace", ["place": place]) }
    static func rowKeyText(camelot: String, key: String?, scale: String?, notSure: Bool, help: String) -> String {
        w("rowKeyText", ["camelot": camelot, "name": key.map { w("rowKeyName", ["key": $0, "scale": scale ?? ""]) } ?? "",
                         "doubt": notSure ? keyNotSure : "", "help": help])
    }
    /// The tags field: the tags joined (the field splits what is typed at commas, so the join keeps one).
    static func tagsField(_ tags: [String]) -> String { join("join.tags", tags) }
    static func sectionAt(_ label: String, bar: Int) -> String { w("sectionAt", ["label": label, "bar": "\(bar)"]) }
    static func damagedAt(_ seconds: Double) -> String { w("damagedAt", ["seconds": String(format: "%.1f", seconds)]) }
    static func musicCDLength(_ seconds: Int) -> String { "\(seconds / 60):" + String(format: "%02d", seconds % 60) }

    // MARK: numbers in words
    static func duration(_ s: Double) -> String {
        let t = Int(s.rounded())
        if t < 60 { return n("seconds", t) }
        let m = t / 60, r = t % 60
        let mins = n("minutes", m)
        return r == 0 ? mins : w("durationJoin", ["minutes": mins, "seconds": n("seconds", r)])
    }
    static func rate(_ perMinute: Double) -> String {
        perMinute >= 10 ? String(format: "%.0f", perMinute) : String(format: "%.1f", perMinute)
    }
    static func twoDigits(_ n: Int) -> String { String(format: "%02d", n) }
    static func plusMore(_ n: Int) -> String { w("sourceSongMore", ["n": "\(n)"]) }
    static func mmss(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
    static func tempo(_ bpm: Double) -> String { String(format: "%.1f", bpm) }
    static func percent(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
}
