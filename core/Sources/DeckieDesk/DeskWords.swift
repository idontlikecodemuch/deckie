import Foundation

/// Every word Deckie Desk shows, on every computer, in one list (D28, D32): the Mac's window reads it through
/// `desk-app/Desk/Sources/Words.swift`, and the Windows and Linux window's pages receive it from the engine program in
/// its first message (docs/architecture/desk-protocol.md). So the copy audit changes this table only.
///
/// The table is data: a name, then the words. `{name}` in the words is filled in by whoever shows them, with numbers
/// already written out (the Mac with Swift's formatting, the pages with JavaScript's). Words that change with a count
/// have one entry per form: `name.one` for 1, `name.other` for any other count, and `name.zero` where 0 reads
/// differently; `{n}` is the count. Words that depend on a code from the engine (where a key came from, why a file did
/// not go in) have one entry per code, `name.<code>`, and `name.other` for a code with no words of its own.
///
/// These are placeholders until the copy audit. Where `docs/product/desk.md` section 3 has a "Should be", it is used;
/// otherwise the wording Desk had before; words no one had written yet were marked "new" in Words.swift. D31 (a folder
/// is a source too) changed five: addMusicHelp, sourcesHelp, nothingReadYet, sourcesEmptyBody, chooseSourceMessage.
/// The rules: a crate is the songs, a crate file is the file (D21); a source is shown by its own name (D26); sentence
/// case, "songs" not "tracks", no "AI" (voice.md).
public enum DeskWords {
    /// The table's format; the pages check it.
    public static let version = 1

    public static let table: [String: String] = [
        // the app
        "appName": "Deckie Desk",
        // The computer Desk runs on, as words name it: `{thisComputer}` in any word is filled with the form for this
        // computer's kind (`DeskWords.computerKind`: "mac", or "other" for Windows and Linux). D32.
        "thisComputer.mac": "this Mac",
        "thisComputer.other": "this computer",
        "ok": "OK",
        "cancel": "Cancel",
        "done": "Done",
        "nameField": "Name",

        // the first screen
        "firstTitle": "Your crate starts here.",
        "firstBody": "Add your music. Desk reads the tempo, key and bars of every song and writes a crate file, a small file you send to your iPad. Your music never leaves {thisComputer}.",
        "addMusic": "Add music",
        "addMusicTo": "Add music to {crate}",
        "addMusicMore": "Add music…",
        "withRekordbox": "With a rekordbox collection…",
        "withRekordboxMenu": "Add music with a rekordbox collection…",
        "importCrateFile": "Import crate file…",
        "exportCrateFile": "Export crate file…",
        "sendToIPad": "Send to iPad",

        // Add music
        "noDriveFound": "No CD or drive found. Put one in, or choose a folder.",
        "chooseFolder": "Choose a folder…",
        "addMusicHelp": "Read a CD, a USB stick, an SD card or a folder as it is: its name, its folders and the order of its songs",
        "chooseSourceMessage": "Choose the folder your music is in. It becomes a source, named after the folder.",
        "chooseSourcePrompt": "Add",
        "rekordboxMessage": "Choose the collection you exported from rekordbox (File > Export Collection in xml format). Deckie takes names, tempos, keys, cues and playlists from it; nothing is sent anywhere.",
        "rekordboxFolderMessage": "Choose the folder your music is in. It becomes a source, named after the folder.",
        "start": "Start",
        // new (D32): drag and drop onto the window.
        "dropHere": "Drop a folder here to add it",

        // while it works
        "runTitle": "Reading your crate",
        "runReading": "Adding {read} to {crate}",
        "songsOf.one": "{done} of {total} song",
        "songsOf.other": "{done} of {total} songs",
        "timeLeftUnderMinute": "Less than a minute left",
        "timeLeft.one": "About 1 minute left",
        "timeLeft.other": "About {n} minutes left",
        "stageReading": "Reading tempo, key and bars",
        "stageFinishing": "Making fingerprints and finding copies",
        "stageSaving": "Saving",
        "lineStarted.one": "{n} audio file found; {unchanged} unchanged since last time; {queued} to read.",
        "lineStarted.other": "{n} audio files found; {unchanged} unchanged since last time; {queued} to read.",
        "lineRead": "{rel}  ({seconds} s)",
        "lineReadBefore": "{rel}  (read before)",
        "lineNotRead": "{rel}  didn't go in: {reason}",

        // the finished screen
        "finishedTitle": "{read} is in {crate}",
        "wentIn.one": "1 song went in.",
        "wentIn.other": "{n} songs went in.",
        "everySongWentIn": "Every song went in.",
        "didntGoIn.one": "1 file didn't go in:",
        "didntGoIn.other": "{n} files didn't go in:",
        "foldersLeftOut.one": "1 folder was left out, as its name starts with _.",
        "foldersLeftOut.other": "{n} folders were left out, as their names start with _.",
        "took": "Took {duration}, {rate} songs a minute.",
        "nextStep": "Next, send the crate file to your iPad.",
        "seeSongs": "See the songs",
        "whatDidntGoIn": "What didn't go in",
        "keysLine": "Keys: {counts}.",
        "keysCount": "{n} {from}",
        "keysNone.one": "1 song has no key yet.",
        "keysNone.other": "{n} songs have no key yet.",
        "keysDisagree.one": "On 1 song your programs give different keys; the newest program's is shown.",
        "keysDisagree.other": "On {n} songs your programs give different keys; the newest program's is shown.",
        "needName.one": "1 song still needs a name.",
        "needName.other": "{n} songs still need a name.",
        "everySongHasAName": "Every song has a name.",
        "showThem": "Show them",
        "rekordboxLocked": "rekordbox keeps its own library locked. To bring its keys in, export your collection from rekordbox (File > Export Collection in xml format) and choose it with File > Choose a DJ library…",
        "rekordboxExportNotRead": "This music has a rekordbox USB export, which Desk doesn't read yet.",
        "librariesRead": "Read from {names}.",
        "couldntReadLibrary": "Couldn't read a DJ library. {detail}",
        // new (D32): "Send to iPad" on Windows and Linux, until the booth takes a crate file another way.
        "exportedTo": "The crate file is in {folder}.",
        "toIPadTitle": "To get it to your iPad",
        "toIPadStick": "A USB stick or SD card: export the crate file onto it, plug it into the iPad and open it from the Files app.",
        "toIPadICloud": "iCloud Drive: with iCloud for Windows, export the crate file into your iCloud Drive folder; it shows in Files on the iPad.",
        "toIPadCable": "A cable: connect the iPad, open Apple Devices, choose the iPad, then Files, and drag the crate file onto Deckie Booth.",
        "openFolder": "Show the folder",

        // a run that stopped
        "stoppedReading": "Desk stopped before it finished reading {read}. Songs already read are kept.",
        "carryOn": "Carry on",
        "putBack": "Put {read} back in to carry on.",

        // the crate menu
        "crateMenuHelp": "The crate that is showing",
        "newCrate": "New crate",
        "renameCrate": "Rename crate…",
        "deleteCrate": "Delete crate…",
        "renameTitle": "Rename {name}",
        "deleteCrateTitle": "Delete {name}?",
        "deleteCrateBody": "The crate and your name fixes go to the Trash. Your music is not touched, and a crate file you sent is not touched.",
        // new (D32): where there is no Trash Desk can use, the crate is deleted for good.
        "deleteCrateBodyForGood": "The crate and your name fixes are deleted. Your music is not touched, and a crate file you sent is not touched.",
        "delete": "Delete",

        // the toolbar
        "sources": "Sources",
        "hideSources": "Hide sources",
        "showSourcesMenu": "Show sources",
        "sourcesHelp": "What was read from each CD, drive or folder, by its own name",
        "sendHelp": "Opens the share sheet, so AirDrop to your iPad is one click",
        // new (D32): the toolbar's menu of the rest.
        "moreMenu": "More",
        "undo": "Undo",
        "redo": "Redo",
        "undoNamed": "Undo {action}",
        "redoNamed": "Redo {action}",

        // the bottom line
        "songs.one": "1 song",
        "songs.other": "{n} songs",
        "cantBeRecognised": "{n} can't be recognised yet",
        "filesDidntGoIn.one": "1 file didn't go in",
        "filesDidntGoIn.other": "{n} files didn't go in",
        "needNameCount.one": "1 needs a name",
        "needNameCount.other": "{n} need a name",
        "showAllSongs": "Show all songs",
        "onlyNeedName": "Showing the songs that need a name",

        // the table
        "colTitle": "Title",
        "colArtist": "Artist",
        "colTempo": "Tempo",
        "colKey": "Key",
        "colBars": "Bars",
        "colLength": "Length",
        "colVocals": "Vocals",
        "colWhere": "Where",
        "colNotes": "Notes",
        "colKeyFrom": "Key from",
        "notSureOfKey": "Not sure of the key",
        "needsNameNote": "needs a name",
        "topOfMusicFolder": "the top of the music folder",
        "damagedFrames.one": "1 damaged frame",
        "damagedFrames.other": "{n} damaged frames",
        "gridUnsure": "beat grid unsure",
        "vocalsNotRead": "vocals not read",
        "signed": "signed",
        "none": "–",

        // the inspector
        "names": "Names",
        "title": "Title",
        "artist": "Artist",
        "version": "Version",
        "tags": "Tags",
        "whereLabel": "Where",
        "whereWithPlaces": "Where ({n} places)",
        "alsoInYourCrateAs": "Also in your crate as",
        "whatDeskFound": "What Desk found",
        "rowFile": "File",
        "rowTempo": "Tempo",
        "tempoValue": "{bpm}, {bars} bars, bar 1 at {downbeat} s",
        "rowTempoChanges": "Tempo changes",
        "segments": "{n} segments",
        "rowKey": "Key",
        "keyNotSure": ", not sure",
        "rowNameFrom": "Name from",
        "keyNotRead": "Key not read on this computer yet",
        "keySays": "{program} says {camelot}",
        "keyFrom.rekordbox-xml": "from rekordbox",
        "keyFrom.traktor": "from Traktor",
        "keyFrom.engine-dj": "from Engine DJ",
        "keyFrom.serato": "from Serato",
        "keyFrom.virtualdj": "from VirtualDJ",
        "keyFrom.tag": "from the file's tag",
        "keyFrom.tag-comment": "from the file's comment",
        "keyFrom.tag-title": "from the file's title",
        "keyFrom.apple-mu": "read by Apple's Music Understanding",
        "keyFrom.deckie": "read by Deckie",
        "keyFrom.votes": "read by Deckie",
        "keyFrom.hpcp-whitened": "read by Deckie",
        "keyFrom.stft-edma": "read by Deckie",
        "keyFrom.other": "from {code}",
        "programName.rekordbox-xml": "rekordbox",
        "programName.traktor": "Traktor",
        "programName.engine-dj": "Engine DJ",
        "programName.serato": "Serato",
        "programName.virtualdj": "VirtualDJ",
        "programName.tag": "the file's tag",
        "programName.tag-comment": "the file's comment",
        "programName.tag-title": "the file's title",
        "programName.apple-mu": "Apple",
        "programName.deckie": "Deckie",
        "programName.votes": "Deckie",
        "programName.hpcp-whitened": "Deckie",
        "programName.stft-edma": "Deckie",
        "programName.other": "{code}",
        "nameFromPart.tag": "the file's tags",
        "nameFromPart.filename": "the file name",
        "nameFromPart.folder": "the folder",
        "nameFromPart.cue": "a cue sheet",
        "nameFromPart.m3u": "a playlist",
        "nameFromPart.tracklist": "a tracklist",
        "nameFromPart.copy": "a copy of the same recording",
        "nameFromPart.user": "you",
        "nameFromPart.lab": "the lab",
        "nameFromJoin": " and ",
        "rowKeyChanges": "Key changes",
        "keyFromBar": "{camelot} from bar {bar}",
        "rowLoudness": "Loudness",
        "loudnessValue": "{lufs} LUFS, peak {peak} dB",
        "rowMixWindows": "Mix windows",
        "mixWindows": "in: bars {inFrom} to {inTo}; out: bars {outFrom} to {outTo}",
        "rowSections": "Sections",
        "rowVocals": "Vocals",
        "vocalsValue": "{percent} of bars",
        "vocalsHeavy": ", vocal-heavy",
        "rowEngine": "Engine",
        "engineOn": "{engine} on {device}",
        "rowSignatures": "Signatures",
        "noneYet": "none yet",
        "rowDamagedFrames": "Damaged frames",
        "selectSong": "Select a song to see and fix its names.",
        "songsSelected": "{n} songs selected.",
        "musicAt": "Music: {path}",
        "whereIsThisMusic": "Where is this music?",
        "musicFolderMessage": "Where the music for this crate is on {thisComputer} (needed to make recognition signatures).",

        // the Sources panel
        "sourcesTitle": "Sources",
        "sourcesCaption": "A source is a CD, a drive or a folder you added. Each keeps its own name.",
        "nothingReadYet": "Nothing read from a CD, a drive or a folder yet.",
        "sourcesEmptyBody": "Add music from a CD, a USB stick, an SD card or a folder, and its name, its folders and the order of its songs show here, as your player shows them.",
        "sourceLine.one": "{name}  ·  1 song",
        "sourceLine.other": "{name}  ·  {n} songs",
        "topFolder": "(top)",
        "alsoIn": "Also in {places}",
        "fixHint": "Desk shows what it read. Fix a name, or an order it read wrongly.",
        "moveUp": "Move up",
        "moveDown": "Move down",
        "rename": "Rename…",
        "renameFolderTitle": "Rename the folder {folder}",
        "removeFromCrate": "Remove from crate…",
        "removeTitle": "Remove {source} from {crate}?",
        "removeBody.zero": "No songs go: every song on it is somewhere else in the crate too.",
        "removeBody.one": "1 song goes from the crate. Songs that are somewhere else too stay.",
        "removeBody.other": "{n} songs go from the crate. Songs that are somewhere else too stay.",
        "remove": "Remove",
        "musicFolderName": "The music folder",
        "removeMusicFolder": "Remove the music folder…",

        // what didn't go in
        "readOn": "Read on {by} at {at}: {seen} files seen, {songs} songs in the crate.",
        "noRecord": "No record of what didn't go in.",
        "reasonCount": "{reason} ({n})",
        "reason.unsupported": "File type not supported",
        "reason.protected": "Protected, cannot be read",
        "reason.damaged_frames": "Damaged frames, played as silence",
        "reason.duplicate": "The same file as another",
        "reason.damaged": "Damaged",
        "reason.decode_error": "Could not be decoded",
        "reason.analysis_error": "Analysis failed",
        "reason.skipped": "Folder left out",

        // keys and names from this computer (D30)
        "lookAgain": "Look again for keys and names",
        "chooseLibrary": "Choose a DJ library…",
        "chooseLibraryMessage": "Choose a library a DJ program keeps: a rekordbox collection export (XML), Traktor's collection.nml, Engine DJ's m.db, Serato's database V2 or VirtualDJ's database.xml. Desk only reads it, and reads it again on every run.",
        "libraryChosen": "Desk will read {program} for keys and names on every run. Look again to read it now.",
        "undoLookAgain": "Look again",

        // undo (shown after "Undo")
        "undoNameFix": "Name fix",
        "undoRename": "Rename",
        "undoMove": "Move",
        "undoRemove": "Remove",

        // messages and errors
        "couldntOpen": "Couldn't open that crate file. {detail}",
        "couldntSave": "Couldn't save the crate file. {detail}",
        "runStopped": "Desk stopped before it finished. {detail} Songs already read are kept.",
        "couldntExport": "Couldn't write the crate file. {detail}",
        "couldntRename": "Couldn't rename the crate. {detail}",
        "couldntDelete": "Couldn't delete the crate. {detail}",
        "nothingToSendYet": "This crate has no songs yet, so there is no crate file to send. Add music first.",
        "exportMessage": "Where the crate file goes. Desk keeps its own; this is a copy.",
        "importMessage": "Choose a crate file (a .deckiecrate package). Desk keeps a copy; the file you choose is not changed.",
        // new (D32): the engine program could not be started or stopped answering.
        "engineGone": "Desk's engine stopped. Close Desk and open it again; songs already read are kept.",
        // new (D32): this computer has no beat tracker's runtime or model, so music cannot be read.
        "engineMissing": "Desk can't read music on this computer yet: a part it needs is missing. {detail}",

        // naming a song (research AA, route A; D30, D33). All new, placeholders until the copy audit.
        // new: a music CD in Add music, and while it is read.
        "musicCDItem": "{name}  ·  music CD in {drive}",
        "musicCDPlaceholder.one": "Music CD, 1 song, {length}",
        "musicCDPlaceholder.other": "Music CD, {n} songs, {length}",
        "askDiscNameTitle": "What's written on this disc?",
        "askDiscNameBody": "Desk names it after that. Reading carries on meanwhile, and you can change the name any time.",
        "lineDiscDamaged": "Song {number}: part of it couldn't be read off the disc and was read as silence",
        "putDiscBack": "Put {read} back in the drive to carry on.",
        // new: the finished screen (letter AA, 3.2).
        "needNameHelp": "They work in the booth as they are. A name makes them easier to find.",
        "discNoNames": "This disc has no names on it.",
        "discDriveNoNames": "The drive gave no names. The disc may have none, or this drive may not pass them on.",
        "discNamed.one": "1 song took its name from the disc.",
        "discNamed.other": "{n} songs took their names from the disc.",
        "discDamaged": "Some of the disc couldn't be read, even on a second try. Desk read those parts as silence.",
        "nameThem": "Name them",
        // new: the list of songs that need a name (letter AA, 3.3).
        "needsNameFilter": "Needs a name ({n})",
        "colWhy": "Why",
        "nameReason.noTitle": "No title",
        "nameReason.noArtist": "No artist",
        "nameReason.guess": "Desk's guess",
        "looksRight": "Looks right",
        "looksRightAll.one": "Looks right: 1 song",
        "looksRightAll.other": "Looks right: all {n}",
        "looksRightHelp": "Keeps Desk's guesses as they are, and takes the songs off this list",
        // new: one song's names (letter AA, 3.4).
        "release": "Release",
        "factNotFound": "not found",
        "factGuess": "Desk's guess, {from}.",
        "factChecked": "{from}, checked by you",
        "factFrom.tag": "from the file's tags",
        "factFrom.filename": "from the file name",
        "factFrom.folder": "from the folder",
        "factFrom.cue": "from a cue sheet beside the music",
        "factFrom.m3u": "from a playlist beside the music",
        "factFrom.tracklist": "from a tracklist beside the music",
        "factFrom.cdtext": "from the disc",
        "factFrom.disc": "the disc's own name",
        "factFrom.copy": "from a copy in your crate",
        "factFrom.user": "you typed this",
        "factFrom.pasted": "from your list",
        "factFrom.pattern": "from the file name, as you set it",
        "factFrom.playlist": "from a playlist you chose",
        "factFrom.rekordbox-xml": "from rekordbox",
        "factFrom.traktor": "from Traktor",
        "factFrom.engine-dj": "from Engine DJ",
        "factFrom.serato": "from Serato",
        "factFrom.virtualdj": "from VirtualDJ",
        "factFrom.lab": "from the lab",
        "factFrom.other": "from {code}",
        "fileLine": "File: {file}",
        "lengthLine": "Length: {length}",
        "splitOffer": "Split into artist, title and version?",
        "split": "Split",
        "keepAsTyped": "Keep as typed",
        // new: Listen (D33; letter AA, 3.7).
        "listen": "Listen",
        "listenTo": "Listen to {title}",
        "pauseSong": "Pause {title}",
        "pause": "Pause",
        "play": "Play",
        "back30": "Back 30 seconds",
        "forward30": "Forward 30 seconds",
        "stopListening": "Stop",
        "listenPosition": "Position in {title}",
        "listenTime": "{position} of {length}",
        "listenGettingReady": "Getting {title} ready…",
        "listenPutBack": "Put {source} back in to listen.",
        "listenCantPlay": "This window can't play {kind} files, and Desk can't turn this one into a kind it can. Listen to it in another program.",
        "listenCouldntPlay": "Couldn't play {title}. {detail}",
        // new: naming many songs at once, with a preview (letter AA, 3.6).
        "nameTools": "Name songs",
        "namesFromFileNames": "Names from the file names…",
        "pasteList": "Paste a list…",
        "namesFromPlaylist": "Names from a playlist…",
        "toolSongsFrom": "Songs from",
        "patternLabel": "Pattern",
        "patternHelp": "Use {artist}, {title}, {version} and {number} for the parts. Anything else must be in the file name as written.",
        "pasteHelp": "Paste or type the songs in order, one to a line.",
        "choosePlaylistMessage": "Choose a playlist (.m3u or .m3u8) made from these songs, in the same order.",
        "choosePlaylist": "Choose a playlist…",
        "onlyEmpty": "Fill only what is empty",
        "previewTitle": "Before anything changes",
        "colSong": "Song",
        "colField": "Field",
        "colNow": "Now",
        "colBecomes": "Becomes",
        "colLine": "Line",
        "changeNote.filled": "has a name",
        "changeNote.yours": "yours, kept",
        "changeNote.lengthDiffers": "length differs",
        "countsDiffer": "{songs}, {lines}. Make them match; nothing changes until then.",
        "lines.one": "1 line",
        "lines.other": "{n} lines",
        "listEmpty": "Nothing to line up yet.",
        "patternFitsNone": "The pattern fits none of the file names.",
        "patternFits": "The pattern fits {fits} of {songs}.",
        "lengthsAllMatch": "Every length matches.",
        "lengthsDiffer.one": "1 song's length doesn't match its line. It is left unticked.",
        "lengthsDiffer.other": "{n} songs' lengths don't match their lines. They are left unticked.",
        "playlistNoLengths": "This playlist gives no lengths, so Desk can't check them.",
        "nothingToChange": "Nothing to change: every name here is already as the list has it.",
        "useNames.one": "Use 1 name",
        "useNames.other": "Use {n} names",
        "namesAdded.one": "Names added to 1 song.",
        "namesAdded.other": "Names added to {n} songs.",
        "namesChecked.one": "1 song checked.",
        "namesChecked.other": "{n} songs checked.",
        "undoNames": "Names",
        "undoCheck": "Looks right",

        // numbers in words
        "seconds.one": "1 second",
        "seconds.other": "{n} seconds",
        "minutes.one": "1 minute",
        "minutes.other": "{n} minutes",
        "durationJoin": "{minutes} {seconds}",
    ]

    /// The words named `key` with `{name}` filled from `values`; the key itself when there are none, so a missing word
    /// shows as its name rather than as nothing.
    public static func text(_ key: String, _ values: [String: String] = [:]) -> String {
        fill(table[key] ?? key, withComputer(values))
    }

    /// The kind of computer this is, for `{thisComputer}`: "mac" on a Mac, "other" on Windows and Linux. The engine
    /// sends it to the pages with the words.
    public static var computerKind: String {
        #if os(macOS)
        return "mac"
        #else
        return "other"
        #endif
    }

    /// `values` with `thisComputer` added for the computer of kind `kind`, unless it is given.
    public static func withComputer(_ values: [String: String], kind: String = computerKind) -> [String: String] {
        guard values["thisComputer"] == nil else { return values }
        var v = values
        v["thisComputer"] = table["thisComputer." + kind] ?? table["thisComputer.other"] ?? ""
        return v
    }

    /// The form of `key` for the count `n` (`key.zero` when n is 0 and there is one, `key.one` for 1, else
    /// `key.other`), with `{n}` and `values` filled in.
    public static func count(_ key: String, _ n: Int, _ values: [String: String] = [:]) -> String {
        let form = n == 0 && table[key + ".zero"] != nil ? "zero" : (n == 1 ? "one" : "other")
        var v = values
        v["n"] = v["n"] ?? String(n)
        return fill(table[key + "." + form] ?? table[key + ".other"] ?? key, withComputer(v))
    }

    /// The words of `key` for the engine's code `code` (`key.<code>`), else `key.other` with `{code}` filled in.
    public static func coded(_ key: String, _ code: String) -> String {
        if let t = table[key + "." + code] { return t }
        return fill(table[key + ".other"] ?? code, ["code": code])
    }

    static func fill(_ template: String, _ values: [String: String]) -> String {
        guard template.contains("{"), !values.isEmpty else { return template }
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            let after = rest[rest.index(after: open)...]
            if let close = after.firstIndex(of: "}"), let v = values[String(after[..<close])] {
                out += v
                rest = after[after.index(after: close)...]
            } else {
                out += "{"
                rest = after
            }
        }
        return out + rest
    }

    /// The table as JSON with its keys sorted, as the engine sends it to the pages.
    public static var json: Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(table)) ?? Data("{}".utf8)
    }
}
