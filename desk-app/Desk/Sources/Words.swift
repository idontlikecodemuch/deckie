import Foundation

/// Every word Deckie Desk shows, by name, in one list (D28): labels, buttons, menu items, help, messages and errors.
/// The views use these and hold no words of their own, so the copy audit changes this file only.
///
/// These are placeholders until that audit. Where `docs/product/desk.md` section 3 has a "Should be", it is used;
/// otherwise the wording Desk had before; words no one had written yet are marked "new" so the audit finds them.
/// The rules: a crate is the songs, a crate file is the file (D21); a source is shown by its own name (D26); sentence
/// case, "songs" not "tracks", no "AI" (voice.md).
enum Words {
    // MARK: the app
    static let appName = "Deckie Desk"
    static let ok = "OK"
    static let cancel = "Cancel"
    static let done = "Done"
    static let nameField = "Name"

    // MARK: the first screen
    static let firstTitle = "Your crate starts here."
    static let firstBody = "Add your music. Desk reads the tempo, key and bars of every song and writes a crate file, a small file you send to your iPad. Your music never leaves this Mac."
    static let addMusic = "Add music"
    static func addMusicTo(_ crate: String) -> String { "Add music to \(crate)" }
    static let addMusicMore = "Add music…"
    static let withRekordbox = "With a rekordbox collection…"
    /// new: the File menu's name for the rekordbox route (desk.md leaves where it goes open).
    static let withRekordboxMenu = "Add music with a rekordbox collection…"
    static let importCrateFile = "Import crate file…"
    static let exportCrateFile = "Export crate file…"
    static let sendToIPad = "Send to iPad"

    // MARK: Add music
    static let noDriveFound = "No CD or drive found. Put one in, or choose a folder."
    static let chooseFolder = "Choose a folder…"
    static let addMusicHelp = "Read a CD, a USB stick or an SD card as it is: its name, its folders and the order of its songs"
    /// new (D31): the folder chooser's message, for Add music and for the rekordbox route alike.
    static let chooseSourceMessage = "Choose the folder your music is in. It becomes a source, named after the folder."
    static let chooseSourcePrompt = "Add"
    static let rekordboxMessage = "Choose the collection you exported from rekordbox (File > Export Collection in xml format). Deckie takes names, tempos, keys, cues and playlists from it; nothing is sent anywhere."
    static let rekordboxFolderMessage = chooseSourceMessage   // new (D31)
    static let start = "Start"

    // MARK: while it works
    static let runTitle = "Reading your crate"
    /// new
    static func runReading(_ read: String, into crate: String) -> String { "Adding \(read) to \(crate)" }
    static func songsOf(_ done: Int, _ total: Int) -> String { "\(done) of \(total) \(total == 1 ? "song" : "songs")" }
    static func timeLeft(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        if seconds < 45 { return "Less than a minute left" }   // new
        return m <= 1 ? "About 1 minute left" : "About \(m) minutes left"
    }
    /// new: the stage under the bar.
    static let stageReading = "Reading tempo, key and bars"
    static let stageFinishing = "Making fingerprints and finding copies"
    static let stageSaving = "Saving"
    /// new: the run's list.
    static func lineStarted(files: Int, unchanged: Int, queued: Int) -> String {
        "\(files) audio \(files == 1 ? "file" : "files") found; \(unchanged) unchanged since last time; \(queued) to read."
    }
    static func lineRead(_ rel: String, seconds: Double) -> String { rel + String(format: "  (%.1f s)", seconds) }
    static func lineReadBefore(_ rel: String) -> String { "\(rel)  (read before)" }
    static func lineNotRead(_ rel: String, reason: String) -> String { "\(rel)  didn't go in: \(Words.reason(reason).lowercased())" }

    // MARK: the finished screen (new, unless said)
    static func finishedTitle(_ read: String, _ crate: String) -> String { "\(read) is in \(crate)" }
    static func wentIn(_ n: Int) -> String { n == 1 ? "1 song went in." : "\(n) songs went in." }
    static let everySongWentIn = "Every song went in."   // desk.md
    static func didntGoIn(_ n: Int) -> String { n == 1 ? "1 file didn't go in:" : "\(n) files didn't go in:" }
    static func foldersLeftOut(_ n: Int) -> String {
        n == 1 ? "1 folder was left out, as its name starts with _." : "\(n) folders were left out, as their names start with _."
    }
    static func took(_ seconds: Double, perMinute: Double) -> String {
        "Took \(duration(seconds)), \(rate(perMinute)) songs a minute."
    }
    static let nextStep = "Next, send the crate file to your iPad."
    static let seeSongs = "See the songs"
    static let whatDidntGoIn = "What didn't go in"   // desk.md

    /// new (D30): what the run took from what is already on this computer.
    static func keysLine(_ counts: [(origin: String, n: Int)]) -> String {
        "Keys: " + counts.map { "\($0.n) \(keyFrom($0.origin))" }.joined(separator: ", ") + "."
    }
    static func keysNone(_ n: Int) -> String {
        n == 1 ? "1 song has no key yet." : "\(n) songs have no key yet."
    }
    static func keysDisagree(_ n: Int) -> String {
        n == 1 ? "On 1 song your programs give different keys; the newest program's is shown."
            : "On \(n) songs your programs give different keys; the newest program's is shown."
    }
    static func needName(_ n: Int) -> String { n == 1 ? "1 song still needs a name." : "\(n) songs still need a name." }
    static let everySongHasAName = "Every song has a name."
    static let showThem = "Show them"
    static let rekordboxLocked = "rekordbox keeps its own library locked. To bring its keys in, export your collection from rekordbox (File > Export Collection in xml format) and choose it with File > Choose a DJ library…"
    static let rekordboxExportNotRead = "This music has a rekordbox USB export, which Desk doesn't read yet."
    static func librariesRead(_ names: [String]) -> String { "Read from " + names.joined(separator: ", ") + "." }
    static func couldntReadLibrary(_ detail: String) -> String { "Couldn't read a DJ library. \(detail)" }

    // MARK: a run that stopped (new, from desk.md's message)
    static func stoppedReading(_ read: String) -> String {
        "Desk stopped before it finished reading \(read). Songs already read are kept."
    }
    static let carryOn = "Carry on"
    static func putBack(_ read: String) -> String { "Put \(read) back in to carry on." }

    // MARK: the crate menu (new)
    static let crateMenuHelp = "The crate that is showing"
    static let newCrate = "New crate"   // desk.md
    static let renameCrate = "Rename crate…"
    static let deleteCrate = "Delete crate…"
    static func renameTitle(_ name: String) -> String { "Rename \(name)" }
    static func deleteCrateTitle(_ name: String) -> String { "Delete \(name)?" }
    static let deleteCrateBody = "The crate and your name fixes go to the Trash. Your music is not touched, and a crate file you sent is not touched."
    static let delete = "Delete"

    // MARK: the toolbar
    static let sources = "Sources"
    static let hideSources = "Hide sources"
    static let showSourcesMenu = "Show sources"
    static let sourcesHelp = "What was read from each CD or drive, by its own name"
    static let sendHelp = "Opens the share sheet, so AirDrop to your iPad is one click"   // new

    // MARK: the bottom line
    static func songs(_ n: Int) -> String { n == 1 ? "1 song" : "\(n) songs" }
    static func cantBeRecognised(_ n: Int) -> String { "\(n) can't be recognised yet" }
    static func filesDidntGoIn(_ n: Int) -> String { n == 1 ? "1 file didn't go in" : "\(n) files didn't go in" }
    /// new (D30)
    static func needNameCount(_ n: Int) -> String { n == 1 ? "1 needs a name" : "\(n) need a name" }
    static let showAllSongs = "Show all songs"
    static let onlyNeedName = "Showing the songs that need a name"

    // MARK: the table
    static let colTitle = "Title"
    static let colArtist = "Artist"
    static let colTempo = "Tempo"
    static let colKey = "Key"
    static let colBars = "Bars"
    static let colLength = "Length"
    static let colVocals = "Vocals"
    static let colWhere = "Where"
    static let colNotes = "Notes"
    static let notSureOfKey = "Not sure of the key"
    /// new (D30)
    static let colKeyFrom = "Key from"
    static let needsNameNote = "needs a name"
    static let topOfMusicFolder = "the top of the music folder"
    static func damagedFrames(_ n: Int) -> String { n == 1 ? "1 damaged frame" : "\(n) damaged frames" }
    static let gridUnsure = "beat grid unsure"
    static let vocalsNotRead = "vocals not read"
    static let signed = "signed"
    static let none = "–"

    // MARK: the inspector
    static let names = "Names"
    static let title = "Title"
    static let artist = "Artist"
    static let version = "Version"
    static let tags = "Tags"
    static let whereLabel = "Where"
    static func whereWithPlaces(_ n: Int) -> String { "Where (\(n) places)" }
    static let alsoInYourCrateAs = "Also in your crate as"   // desk.md
    static let whatDeskFound = "What Desk found"   // desk.md
    static let rowFile = "File"
    static let rowTempo = "Tempo"
    static func tempoValue(bpm: Double, bars: Int, firstDownbeat: Double) -> String {
        String(format: "%.2f, %d bars, bar 1 at %.2f s", bpm, bars, firstDownbeat)
    }
    static let rowTempoChanges = "Tempo changes"
    static func segments(_ n: Int) -> String { "\(n) segments" }
    static let rowKey = "Key"
    static let keyNotSure = ", not sure"
    /// new (D30): where a key or a name came from.
    static let rowNameFrom = "Name from"
    static let keyNotRead = "Key not read on this computer yet"   // D16's words
    static func keySays(_ origin: String, _ camelot: String) -> String { "\(programName(origin)) says \(camelot)" }
    static func keyFrom(_ source: String) -> String {
        switch source {
        case "rekordbox-xml": return "from rekordbox"
        case "traktor": return "from Traktor"
        case "engine-dj": return "from Engine DJ"
        case "serato": return "from Serato"
        case "virtualdj": return "from VirtualDJ"
        case "tag": return "from the file's tag"
        case "tag-comment": return "from the file's comment"
        case "tag-title": return "from the file's title"
        case "apple-mu": return "read by Apple's Music Understanding"
        case "deckie", "votes", "hpcp-whitened", "stft-edma": return "read by Deckie"
        default: return "from \(source)"
        }
    }
    /// The short form, for the table's column.
    static func programName(_ source: String) -> String {
        switch source {
        case "rekordbox-xml": return "rekordbox"
        case "traktor": return "Traktor"
        case "engine-dj": return "Engine DJ"
        case "serato": return "Serato"
        case "virtualdj": return "VirtualDJ"
        case "tag": return "the file's tag"
        case "tag-comment": return "the file's comment"
        case "tag-title": return "the file's title"
        case "apple-mu": return "Apple"
        case "deckie", "votes", "hpcp-whitened", "stft-edma": return "Deckie"
        default: return source
        }
    }
    static func nameFrom(_ source: String) -> String {
        source.split(separator: "+").map { part -> String in
            switch part {
            case "tag": return "the file's tags"
            case "filename": return "the file name"
            case "folder": return "the folder"
            case "cue": return "a cue sheet"
            case "m3u": return "a playlist"
            case "tracklist": return "a tracklist"
            case "copy": return "a copy of the same recording"
            case "user": return "you"
            case "lab": return "the lab"
            default: return programName(String(part))
            }
        }.joined(separator: " and ")
    }
    static let rowKeyChanges = "Key changes"
    static func keyFromBar(_ camelot: String, _ bar: Int) -> String { "\(camelot) from bar \(bar)" }
    static let rowLoudness = "Loudness"
    static func loudnessValue(lufs: Double, peak: Double) -> String { String(format: "%.1f LUFS, peak %.1f dB", lufs, peak) }
    static let rowMixWindows = "Mix windows"
    static func mixWindows(inFrom: Int, inTo: Int, outFrom: Int, outTo: Int) -> String {
        "in: bars \(inFrom) to \(inTo); out: bars \(outFrom) to \(outTo)"
    }
    static let rowSections = "Sections"
    static let rowVocals = "Vocals"
    static func vocalsValue(_ mean: Double, heavy: Bool) -> String {
        String(format: "%.0f%% of bars", mean * 100) + (heavy ? ", vocal-heavy" : "")
    }
    static let rowEngine = "Engine"
    static func engineOn(_ engine: String, _ device: String) -> String { "\(engine) on \(device)" }
    static let rowSignatures = "Signatures"
    static let noneYet = "none yet"
    static let rowDamagedFrames = "Damaged frames"
    static let selectSong = "Select a song to see and fix its names."
    static func songsSelected(_ n: Int) -> String { "\(n) songs selected." }
    static func musicAt(_ path: String) -> String { "Music: \(path)" }
    static let whereIsThisMusic = "Where is this music?"   // desk.md
    static let musicFolderMessage = "Where the music for this crate is on this Mac (needed to make recognition signatures)."

    // MARK: the Sources panel
    static let sourcesTitle = "Sources"
    /// new (D31): the caption under the panel's title.
    static let sourcesCaption = "A source is a CD, a drive or a folder you added. Each keeps its own name."
    static let nothingReadYet = "Nothing read from a CD or a drive yet."
    static let sourcesEmptyBody = "Add music from a CD, a USB stick or an SD card, and its name, its folders and the order of its songs show here, as your player shows them."
    static func sourceLine(_ name: String, songs n: Int) -> String { "\(name)  ·  \(n) \(n == 1 ? "song" : "songs")" }
    static let topFolder = "(top)"
    static func alsoIn(_ places: String) -> String { "Also in " + places }
    static let fixHint = "Desk shows what it read. Fix a name, or an order it read wrongly."
    static let moveUp = "Move up"
    static let moveDown = "Move down"
    static let rename = "Rename…"
    static func renameFolderTitle(_ f: String) -> String { "Rename the folder \(f)" }
    /// new
    static let removeFromCrate = "Remove from crate…"
    static func removeTitle(_ source: String, _ crate: String) -> String { "Remove \(source) from \(crate)?" }
    static func removeBody(_ n: Int) -> String {
        n == 0 ? "No songs go: every song on it is somewhere else in the crate too."
            : (n == 1 ? "1 song goes from the crate. Songs that are somewhere else too stay."
               : "\(n) songs go from the crate. Songs that are somewhere else too stay.")
    }
    static let remove = "Remove"
    /// Only for crate files made before D31, whose songs from the Mac have no source.
    static let musicFolderName = "The music folder"
    static let removeMusicFolder = "Remove the music folder…"

    // MARK: what didn't go in
    static func readOn(_ by: String, _ at: String, seen: Int, songs: Int) -> String {
        "Read on \(by) at \(at): \(seen) files seen, \(songs) songs in the crate."
    }
    static let noRecord = "No record of what didn't go in."   // desk.md
    static func reasonCount(_ reason: String, _ n: Int) -> String { "\(Words.reason(reason)) (\(n))" }
    static func reason(_ r: String) -> String {
        switch r {
        case "unsupported": return "File type not supported"
        case "protected": return "Protected, cannot be read"
        case "damaged_frames": return "Damaged frames, played as silence"
        case "duplicate": return "The same file as another"
        case "damaged": return "Damaged"
        case "decode_error": return "Could not be decoded"
        case "analysis_error": return "Analysis failed"
        case "skipped": return "Folder left out"
        default: return r.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: keys and names from this computer (new, D30)
    static let lookAgain = "Look again for keys and names"
    static let chooseLibrary = "Choose a DJ library…"
    static let chooseLibraryMessage = "Choose a library a DJ program keeps: a rekordbox collection export (XML), Traktor's collection.nml, Engine DJ's m.db, Serato's database V2 or VirtualDJ's database.xml. Desk only reads it, and reads it again on every run."
    static func libraryChosen(_ source: String) -> String { "Desk will read \(programName(source)) for keys and names on every run. Look again to read it now." }
    static func lookedAgain(_ lines: [String]) -> String { lines.joined(separator: " ") }
    static let undoLookAgain = "Look again"

    // MARK: undo (shown in the Edit menu after "Undo"); new
    static let undoNameFix = "Name fix"
    static let undoRename = "Rename"
    static let undoMove = "Move"
    static let undoRemove = "Remove"

    // MARK: messages and errors
    static func couldntOpen(_ detail: String) -> String { "Couldn't open that crate file. \(detail)" }   // desk.md
    static func couldntSave(_ detail: String) -> String { "Couldn't save the crate file. \(detail)" }   // desk.md
    static func runStopped(_ detail: String) -> String {
        "Desk stopped before it finished. \(detail) Songs already read are kept."   // desk.md
    }
    static func couldntExport(_ detail: String) -> String { "Couldn't write the crate file. \(detail)" }   // new
    static func couldntRename(_ detail: String) -> String { "Couldn't rename the crate. \(detail)" }   // new
    static func couldntDelete(_ detail: String) -> String { "Couldn't delete the crate. \(detail)" }   // new
    static let nothingToSendYet = "This crate has no songs yet, so there is no crate file to send. Add music first."   // new
    static let exportMessage = "Where the crate file goes. Desk keeps its own; this is a copy."   // new
    static let importMessage = "Choose a crate file (a .deckiecrate package). Desk keeps a copy; the file you choose is not changed."

    // MARK: numbers in words
    static func duration(_ s: Double) -> String {
        let t = Int(s.rounded())
        if t < 60 { return t == 1 ? "1 second" : "\(t) seconds" }
        let m = t / 60, r = t % 60
        let mins = m == 1 ? "1 minute" : "\(m) minutes"
        return r == 0 ? mins : mins + " " + (r == 1 ? "1 second" : "\(r) seconds")
    }
    static func rate(_ perMinute: Double) -> String {
        perMinute >= 10 ? String(format: "%.0f", perMinute) : String(format: "%.1f", perMinute)
    }
    static func twoDigits(_ n: Int) -> String { String(format: "%02d", n) }
    static func plusMore(_ n: Int) -> String { "+\(n)" }
    static func mmss(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
    static func tempo(_ bpm: Double) -> String { String(format: "%.1f", bpm) }
    static func percent(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
}
