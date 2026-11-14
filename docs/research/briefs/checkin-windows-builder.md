# Check-ins: the Windows builder (branches `pc/windows-builder`, `pc/m4a`, `pc/package-desk`)

Newest entry first. Each entry: when, what is done, what failed and why, what is next, and one plain line.

**Newest zip, Deckie Desk with its window: `pc-package` run 43581053583** (branch `pc/package-desk`, commit
`c964f6c`), artifact `Deckie-Desk-for-Windows-first-test` (id 14108458447): **128,981,732 bytes**, SHA-256
`65c94acef23ff8d1fe983ff40004a436415f22bdfc9c88fbd7f626e2dd3ccb97`. It supersedes every zip named further down.

## Nov 14, 2026, 10:00 UTC: Deckie Desk for Windows is packaged and tried on the runner; all four workflows green

**The zip to use: `pc-package` run 43581053583** (branch `pc/package-desk`, commit `c964f6c`), artifact
`Deckie-Desk-for-Windows-first-test` (id 14108458447, kept 30 days): `Deckie-Desk-for-Windows-first-test.zip`,
**128,981,732 bytes**, SHA-256 `65c94acef23ff8d1fe983ff40004a436415f22bdfc9c88fbd7f626e2dd3ccb97`. It is a run artifact only: no release, no tag, no pull request.

**All four workflows are green on that one commit:** `pc-package` 43581053583, `desk-window` 43581053551,
`core-linux` 43581053633, `core-windows` 43581053570. The commits after `c964f6c` on the branch change documents
only and start no workflow.

**What a DJ gets.** A folder, "Deckie Desk for Windows (first test)": `READ ME FIRST.txt`, `Deckie Desk.exe`,
`Make Crate File.exe`, and `app` (the window, its engine, the pages, `deckie-make`, 19 runtime libraries, ONNX
Runtime, the two models, the licences). Unzip, double-click "Deckie Desk". Nothing is installed.

**Seen on the runner** (Windows Server 2025, the unzipped folder in "A DJ's PC", PATH cut down to `System32` and
the Windows folder, every start through `Deckie Desk.exe` unless said):

| What | Result |
|---|---|
| The window | made, with WebView2 156.0.4314.58; Desk's own icon is on the window (asked of the window itself) |
| No console window | read from the program files: `Deckie Desk.exe`, `deckie-desk.exe` and `deckie-desk-engine.exe` are programs of the kind Windows gives no console to. No person looked |
| The page | loaded, and drew the first screen in the engine's words: heading "Your crate starts here.", button "Add music" |
| The engine | found `onnxruntime.dll` and `models/` beside itself (it says it is ready to read music) |
| **Start-up time** | from starting `Deckie Desk.exe` to the page showing the engine's words: **0.54 s and 0.47 s** on two starts with nothing to write to, as a double click starts it. The very first start on the account, when the web view makes its own storage, is slower: **9.4 s** in this run, and 3.1, 5.3 and 4.5 s in the three runs before it (measured inside `deckie-desk.exe`) |
| A run | the test music folder ("My Müsic": a WAV, a FLAC, an MP3, a nested folder, a name that is not ASCII, one file too short, one protected, hidden files) added through the page's own Add music button and folder chooser (answered by the check); the run finished in 9.0 s; the finished screen said "4 songs went in. 2 files didn't go in: Analysis failed (1), Protected, cannot be read (1). Keys: 4 read by Deckie." |
| Export | through the page's Export button: `My Müsic.deckiecrate`, **one file**, 27,239 bytes; the core's validator reads it (`deckie-e2e check-desk`): single-file form, 4 songs at 124 BPM and 32 bars, key 8A, each from the source "My Müsic" |
| Where Desk keeps its crates | that run used the place a DJ's PC uses, nothing set: `C:\Users\runneradmin\AppData\Local\Deckie Desk`. After it, this account held `AppData\Local\Deckie Desk` (26 files, 238 KB: the crate and what was worked out for each song), `AppData\Local\Deckie` (`Make Crate File`'s) and `AppData\Roaming\deckie-desk.exe` (the web view's own storage, 5.1 MB), which is what the READ ME says |
| A PC without the WebView2 Runtime | tried honestly: the registry values that say where the runtime is were renamed for a moment, so **the program's own detection said no**. Deckie Desk ended with its code 4 and the words "Deckie Desk needs a free part of Windows that this PC does not have yet: Microsoft's WebView2 Runtime..." with Microsoft's page and "Make Crate File". With the values back, the window opened again. The message **box** was not shown (nobody could click it): the words went to standard error |
| Started from inside the zip | the starter alone says "Unzip first..." and ends with 3 (the words, not the box) |
| `Make Crate File` | everything it passed before: a folder dropped on it, a second run, the typed path, the starter alone, four four-minute songs |

**What failed along the way, exactly:**

1. `desk-window` 43575041468: the shell did not compile on Windows. A variable was named `small`, which a Windows
   header defines as something else. Renamed.
2. `desk-window` 43575623174 and `core-windows` 43576872162: the engine test `speaksTheProtocolWithNoMusicRead`
   failed twice, at two different lines, each reading "the latest event" straight after a reply. Both lines were
   there before this work; a busy runner delivers the event a moment later. The test now waits for the event that
   shows each change. It is the race the brief named.
3. `pc-package` 43575623179: `Deckie Desk.exe` did not finish in three minutes. `pc-package` 43576872179 showed
   why: started with nothing to write to, **the window program stopped at once with Windows' code 0xC000001D**,
   and the starter then waited in a message box nobody could click. The cause was a line written for a developer:
   a program with no console, started by a double click, has no standard error at all, and Swift stops a program
   that writes to one that is not there. My first fix (handing the program Windows' "NUL" to write to) did not
   help, because Swift writes through the C runtime's own file number, which is set once when the program starts.
   The fix that works: the shell asks once whether it has a standard error and does not write when it has none.
   **This would have stopped every real double click.** It was caught only because the workflow starts the program
   the way a double click does.
4. `pc-package` 43578864554: a new step of mine expected Desk's storage folder to exist after a start that stored
   nothing. Desk makes it with the first crate. The step now follows the run, which uses that folder.
5. `core-windows` 43578864539 and `desk-window` 43580169379: the test
   `exportWritesTheCrateFileUnderItsNameAndDeleteMovesOn` failed, twice in eight Windows runs, at its last step:
   deleting the crate. "Couldn't delete ...: another program kept the file open (tried 6 times over about a
   second)", and the file named was a temporary one that a save leaves when its move into place is interrupted.
   That is the Windows hold `DeckieFiles` was written for (another program, a virus scanner most likely, reading a
   file Deckie has just written); a second was not always enough for a whole folder. A delete now waits about five
   seconds before it gives up. **I did not prove the cause**: I did not see which program held the file, and my
   new export writes more small files than the old one did, which may be why it showed now. It passed on the
   commit after (one run of each workflow), which is not proof either. If it returns, the next thing to look at
   is whether the temporary file is being held by Deckie's own program.

**Every decision made on the owner's behalf, with its reason** (1 to 10 are in the entry below at more length;
repeated in one line each so this entry stands alone):

1. Folder and zip renamed to "Deckie Desk for Windows (first test)": the thing a DJ gets is Desk.
2. No console window by marking the finished programs' kind (`pe_kind.py`), not by a build switch: the tests'
   builds stay console programs, and the engine needs it too since Swift's child-starting has no "no window" switch.
3. The engine finds its files beside itself through `OnnxRuntime.programFolder`: the order `deckie-make` uses.
4. The WebView2 test is the window's own loader; the registry values Microsoft documents only choose the words.
5. The message asks (Yes or No) before opening Microsoft's page; Deckie downloads nothing.
6. The icon keeps the rounded corners of `site/icon.svg`.
7. The icon file: plain bitmaps for the seven small sizes, a PNG for 256.
8. The programs carry a description and version; no company name and no copyright line (the owner's to word).
9. Desk's export writes one file on Windows and Linux only; the Mac keeps the package.
10. `deckie-e2e check-desk` reads Desk's exported crate file.
11. **`Make Crate File` stays in the zip and is the offered way on a PC without WebView2**, as the brief said.
    Microsoft's installer for the runtime is **not** shipped: it would be a new licence question for the owner.
12. **A check must never wait on a box.** `DECKIE_NO_BOXES` makes the starter and the shell say their words on
    standard error; the workflow sets it for every start. A DJ never sets it.
13. **A test switch, `DECKIE_DESK_NO_WEBVIEW2`**, makes the shell behave as on a PC without the runtime. The
    workflow did not need it (hiding the registry values worked) and falls back to it if a runner ever refuses.
14. **The shell's own words** (four messages a DJ can meet before there is a window) live in
    `desk-shell/Sources/deckie-desk/Notice.swift` as named values, in the voice of `docs/product/voice.md`. The
    pages still hold no words; the engine's list cannot be asked when there is no window to show it in.
15. **The READ ME says key is read on a PC and recognition is not yet**, which is what `main` held tonight, and is
    worded to stay true when Deckie's own fingerprint lands: it tells the DJ to look at the window's own line ("N
    can't be recognised yet"). If the fingerprint has landed by morning, only the one dated sentence is stale.
16. **Racy lines in an engine test that I did not write were fixed** (four reads, at three places) rather than
    re-run until green.
17. **A delete waits about five seconds for a held file, not one** (`DeckieFiles.removePauses`), in the core
    everyone shares. Reason: failure 5 above; a DJ deleting a crate should not have to ask twice. The other
    operations keep their one second.
18. **D36 says Desk is packaged for Windows "once the core is complete, not before".** This work was asked for
    tonight all the same, so it is done as a first test, labelled so everywhere, and not released.
19. **`main` was not merged into the branch.** While this was built, `main` moved on by 34 commits (the run screen
    of D37, and the lookup through MusicBrainz of D36, among others). The zip is built from `main` as it stood
    when the branch was cut (`098afc1`), so it has neither. Reason: the lookup is the first thing in Deckie that
    uses the network, and D36 says the privacy line is reworded before that reaches anyone outside; the READ ME
    in this zip says "It works with no internet" and "Nothing is looked up on the internet in this version",
    which is true of this zip and would not be of a merged one. Those words are the owner's. Deckie's own
    fingerprint had not reached the crate file on `main` by 10:00 UTC, so the READ ME's line on recognition is
    still the true one.

**Not done, or not proven, said plainly:**

- No person has seen the window, the icon, the message box or the absence of a console. A runner has no screen.
- The message box itself was never shown, nor its Yes button opening Microsoft's page.
- The runner is Windows Server 2025 with the WebView2 Runtime and Microsoft's Visual C++ runtime already on it. It
  is not Windows 10 or 11, and its account is an administrator.
- A real double click goes through Explorer; the workflow's start is the same kind (a program with a window,
  nothing to write to), which is how failure 3 was found, but it is not Explorer.
- Dragging a folder onto the window, a music CD, a USB stick in the Add music list, Listen: none was tried here.
- The crate file opening in Deckie Booth on a real iPad was not tried in this work.
- Two copies of Deckie Desk open at once share one storage; nothing stops that, and it is not tested.
- The window is 1180 by 760 points; on a small laptop screen (1366 by 768) it may not fit. Not tried.

**Next, for whoever picks this up:** merging `main` into `pc/package-desk` (or the other way) conflicts in four
files, tried and put back: `.github/workflows/pc-package.yml` (the list of branches), `desk-shell/Sources/
deckie-desk/main.swift` (the tour's options beside the check's), `core/Tests/DeckieDeskTests/EngineProcessTests.swift`
(new tests beside the waits) and this file. None is deep. After the merge the READ ME and the tester's page need the
lookup's words, and the packaging run should be read again: the lookup brings Foundation's networking library into
the engine, which the import-table reader will copy by itself, and which no run has tried from the zip.

**For a person with a real PC, in this order:**

1. On the PC, download the artifact zip in a browser (that is what makes Windows treat it as "from the
   internet"). Note what the browser and Windows' antivirus say about the download.
2. Right-click the zip, "Extract All". Note anything the antivirus says while it unzips.
3. Before unzipping anything else: open the zip by double-clicking it and double-click "Deckie Desk" inside it.
   Expected: a box saying "Unzip first".
4. In the unzipped folder, look at the two programs in Explorer: both should show Deckie's icon (the orange record
   on dark purple), in the list and as large icons.
5. Double-click "Deckie Desk". Expected: the blue "Windows protected your PC" box; "More info", then "Run anyway".
   Does it ask again for a second program? (The starter starts another unsigned program.) Does it ask again on
   the next start?
6. Watch for a black console window flashing or staying. There should be none, at start or when music is added.
7. The window: titled "Deckie Desk", the icon in its title bar, on the taskbar and in Alt-Tab; Task Manager should
   call it "Deckie Desk". Time it from the double click.
8. Click "Add music", "Choose a folder…": the real Windows folder chooser. Pick a small music folder. Watch the
   run to the end; read what the finished screen says.
9. "Export crate file…" onto a USB stick or into iCloud Drive; get it to an iPad and open it in Deckie Booth.
10. Drag a music folder from Explorer onto the window.
11. Plug in a USB stick with music; does it show under "Add music"? If the PC has a disc drive, a music CD.
12. Close the window in the middle of a run; start again; "Carry on".
13. Play a song in the window (Listen), an MP3 and an M4A.
14. Start "Deckie Desk" twice. (Two windows on one storage: not handled.)
15. Drag a music folder onto "Make Crate File": the console window, the crate file next to the folder.
16. The same on an account that is **not an administrator**.
17. The same on **Windows 10** (and on Windows 11 if the first PC was 10). Check a laptop with a small screen and
    one with display scaling at 125 or 150 percent.
18. **A PC without the WebView2 Runtime** (a Windows 10 that never had Edge updated, or one where the runtime is
    uninstalled under "Apps"): double-click "Deckie Desk". Expected: a box naming Microsoft's WebView2 Runtime and
    its page; "Yes" opens the page in the browser; "Download WebView2" there, install, start again and the window
    opens. Then "No" on a second PC, and "Make Crate File" there.
19. A PC whose Windows account name has letters outside English, or with the folder on a OneDrive Desktop.
20. A long run: a thousand songs, the laptop on battery, the lid closed for a while.
21. Remove it: delete the folder; look in `%LOCALAPPDATA%` and `%APPDATA%` for what is left (the READ ME names it).

carry on

## Nov 14, 2026, 08:45 UTC: branch `pc/package-desk` (from `main`): Deckie Desk is in the zip; it assembles on the runner; its first start from the zip does not finish yet

The work: package Deckie Desk for Windows (the window `deckie-desk`, its engine, the pages) as a folder a DJ unzips
and runs, with its icon, no console window and a plain message on a PC without the WebView2 Runtime (the part of
Windows, from Microsoft, that draws Desk's window). Nobody is awake to ask, so each decision is written here with
its reason.

**Done and seen on the runner** (`pc-package` run 43575623179, commit `a2c9694`):

- The zip assembles: `Deckie-Desk-for-Windows-first-test.zip`, 128,973,372 bytes, 46 files. It holds
  `Deckie Desk.exe` and `Make Crate File.exe` at the top, and in `app` the window, the engine, `deckie-make`, the
  pages, 19 runtime libraries, ONNX Runtime, the models and the licences (now with the `webview` library's licence
  and the licence of Microsoft's WebView2 SDK header).
- The icon is made in the run from the iPad app's picture by `core/Tools/windows/make_ico.py` (102,045 bytes, eight
  sizes) and compiled by `llvm-rc`, which the Swift toolchain on the runner does carry. The check of the finished
  programs says: `Deckie Desk.exe` and `deckie-desk.exe` open no console window and carry the icon; the engine
  opens no console window; `Make Crate File.exe` is a console program and carries the icon.
- `Make Crate File` from the new zip passes everything it passed before.
- `core-linux` and `core-windows` are green with the core's two changes (the single file on export; the engine
  finding its files beside itself).

**Failed, and why:**

1. `desk-window` run 43575041468: the shell did not compile on Windows. I had named a variable `small`, and a
   Windows header defines that word as something else. Renamed. It compiles now (run 43575623174).
2. `desk-window` run 43575623174: one engine test failed, `speaksTheProtocolWithNoMusicRead`, at a line that read
   the latest `state` event straight after a reply. That is the race the brief warned of, in a line that was there
   before; the test now waits for the event it means.
3. `pc-package` run 43575623179: **`Deckie Desk.exe`, started from the unzipped folder, did not finish its check in
   three minutes**, and its log file was empty. An empty log means the program started and then stopped or hung
   before the window was made. I do not know why yet. The same program as a console build passes the same check in
   `desk-window`. What differs in the zip: a release build, marked as a program with no console window, started
   with nothing to write to, with PATH cut down. My first suspect is something I added: at start the program gave
   itself Windows' "NUL" as standard output and error when it had none; the web view may not start under that.

**Next:** the run in progress (commit `926a701`) starts the window program four ways and writes down what Windows
itself says about each, so the cause is seen rather than guessed. I have already taken the "NUL" step out (the
program now leaves its standard handles alone and simply does not write when it has none) and made the check's
time limit start before the window is made, so a web view that never comes up ends the check with words.

**Decisions made so far, each with its reason:**

1. **The folder and zip are renamed** "Deckie Desk for Windows (first test)" and
   `Deckie-Desk-for-Windows-first-test.zip` (artifact of the same name). The thing a DJ gets is now Desk, and the old
   name said "for PC".
2. **No console window by marking the finished programs**, not by a build switch: the copies of `deckie-desk.exe`
   and `deckie-desk-engine.exe` that go into the zip have one two-byte field of their header changed
   (`core/Tools/windows/pe_kind.py`; Microsoft's `editbin /SUBSYSTEM` does the same). Reason: the builds the tests
   use stay console programs, so their messages show, and no build flag has to be threaded through two packages.
   The engine is marked too because Swift's way of starting a child program has no "no window" switch; a child
   marked this way gets no console from Windows at all.
3. **The engine finds its files beside itself** through one new setting in the core
   (`OnnxRuntime.programFolder`), which the engine program sets to its own folder; the environment variables still
   come first, the checkout last. Reason: the same order `deckie-make` uses, and it works for every run the engine
   makes, not only the first.
4. **The WebView2 check is the window's own loader**, not a second test in the starter: the shell tries to make the
   window, and when that fails on Windows it reads the registry values Microsoft documents to say which of two
   things is true (not installed; installed but did not start). Reason: one test cannot disagree with itself.
5. **The message asks before opening Microsoft's page** (Yes or No), and names the page in words as well. Nothing
   is downloaded by Deckie. The page is the one Microsoft's own documentation says to send people to
   (`https://developer.microsoft.com/microsoft-edge/webview2/consumer/`, read tonight).
6. **The icon keeps the rounded corners of `site/icon.svg`** (radius 230 in 1024). The iPad picture is a full
   square that iOS rounds itself; Windows shows a picture as it is, and a square would look unlike the site.
7. **The icon file holds plain bitmaps for the seven small sizes and a PNG for 256**, not PNGs throughout. Reason:
   it is the layout every Windows and both resource compilers read; it cost ten more lines.
8. **The programs also carry a description** ("Deckie Desk"; version 0.1.0), which Task Manager and a file's
   Properties show, and **no company name and no copyright line**: those are the owner's to word.
9. **Desk's export writes the single file on Windows and Linux only**; the Mac keeps the package, since its own
   Desk does not use this path and AirDrop moves a package as one thing.
10. **A new mode of the test tool, `deckie-e2e check-desk`**, reads Desk's exported crate file: the validator's
    existing checks assume the PC program's layout, and Desk names each file from its source.

consider changing direction only if the next run shows the window cannot start at all as a program with no
console; otherwise carry on

**The last zip without the window, with `.m4a` reading: `pc-package` run 43545418975** (branch `pc/m4a`, commit
`665490a`), artifact `Deckie-for-PC-first-test` (id 14094366437): **122,379,915 bytes**, SHA-256
`4da005fe55bce0d5be43b12d5aba0806185c39c685a565b48c9492215308874d`.

## Nov 14, 2026, 08:00 UTC: covers (D36) on branch `pc/covers`: core, builders and Desk written; all four workflows green

**Green on commit `a15a78b`**: `core-linux` 43572620220, `core-windows` 43572620242 (which also compares the
Linux and Windows crate files: the same covers, byte for byte), `desk-window` 43572620234, `pc-package` 43572620331.
Covers are parked here while the packaging of Desk's window is done first, on `pc/package-desk` (the owner's change
of order). What is left for covers is listed under "Not done" below; nothing is half-written.

**The addition as written** (`docs/architecture/crate-format.md`, "Addition with D36"):

- A record may carry **`file.cover`**: the SHA-256 of the **source picture's bytes**, left out when the song has
  none. The thumbnail is **`covers/<hash>.jpg`**, stored once for every song that shares the picture.
- **One size**: longest side 128 pixels, shape kept, never scaled up; a baseline JPEG at quality 80, anything
  see-through over white, no metadata. A reader may rely on at most 128 pixels and at most 24 KB.
- **Limits on the source**: JPEG or PNG only, at most 32 MB and 8,192 pixels a side, the size read before anything
  is decoded. A damaged, enormous or other-format picture gives no cover; the song still goes in and the picture
  is counted.
- **No cap for the whole crate file**; the cap per cover bounds it.
- **The single-file form** carries the folder as it carries any folder. Nothing new.
- The writer refuses a record whose cover file is missing and deletes covers no record names, so the last song of
  a release leaving a crate takes its cover with it.
- **Why the source's hash**: the thumbnail's bytes are the same on Linux and Windows (a hash pinned in the tests
  passed on both runners) but will differ on a Mac, which uses the system's image code. Named by the source, one
  release has one entry whichever computer read it.

**Where the picture comes from**: the file's own front cover (ID3 `APIC` and `PIC`, FLAC `PICTURE` and the two
Vorbis-comment forms, MP4 `covr`); else a picture beside the song, in its own folder, named `cover`, `folder`,
`front`, `albumart` or `album` with `.jpg`, `.jpeg` or `.png` (what Windows Media Player, Explorer, rippers and
stores write). Known weakness: a folder of unrelated singles with one such picture gives every song that picture.

**The builders** (`deckie-build`, `deckie-make`, Desk's run) write covers through one path. A second run does not
redo them: each file's line in the work folder remembers where its picture came from and its hash, and the
thumbnail is kept there. A picture added, changed or removed beside the music later is noticed without reading any
song.

**Desk**: a new request `song.cover` answers with the JPEG inside the message (no port, the page never told a path
or a hash), each song row says whether it has one, and the naming panel shows it at 80 pixels with an empty square
of the same size when there is none. Protocol number unchanged (an addition). Two new words in `DeskWords`.

**Measured:**

| | |
|---|---|
| A cover from the generated test pictures | 2.2 to 2.3 KB |
| The worst case tried (512 pixels of random colour) | 5.4 KB |
| The end-to-end folder (3 songs, 2 covers) | crate file 20,992 bytes without covers, 26,002 with: 4,558 bytes of covers |

**What 2,000 songs would gain.** From these numbers, about 2.3 KB for each distinct picture: 4.6 MB if every song
has its own cover, under 0.5 MB if they come ten to a release. The rest of the crate file is about 8 MB at that
size, so the worst case adds a little over half again. Real sleeves have more detail than my generated pictures,
so 3 to 5 KB each is the safer guess (6 to 10 MB for 2,000 singles); that part is an estimate, not a measurement,
because no real cover is in the repository.

**Dependency chosen**: stb_image 2.32 and stb_image_write 1.18, two single-file C libraries, public domain or MIT
at the user's choice, both on the allowlist; vendored by hash (`DEPENDENCIES.md` section 11). The licence was not
in doubt, so I did not stop. Their resizer was not taken: scaling is 60 lines of whole-number arithmetic of our own,
which is what makes the bytes the same everywhere. **A judgement to check**: stb_image is not hardened against
hostile pictures. Only JPEG and PNG are compiled in, sizes are checked before decoding, and a failure gives no
cover; Wuffs (Apache 2.0) is the stronger decoder if that is wanted.

**What the Mac window and the iPad app need** (not built, could not be):

- Read `file.cover`; when present show `covers/<hash>.jpg` from the package, else a placeholder. For the
  single-file form, after `CrateArchive.unpack`, or straight from `CrateArchive.read(file)`.
- The Mac's Desk gets covers from the shared run with no change if it builds against this core; the thumbnail is
  then made by `Cover.systemThumbnail` (ImageIO). **That function has never been compiled**: it was written on
  Linux. It needs a build and a look on a Mac first.
- The booth only reads.

**Failed along the way:** the window workflow failed twice (runs 43569575522 and 43570530998) in two older engine
tests that read an event straight after a reply; with one more test running beside them they lost the race on the
runners (never here). They now wait for the event. A third such check failed once more on Windows (run 43571817713) and was fixed the same way. One Windows core
run (43569575464) failed its test step on the same commit; I did not read its log and took it for the same race,
which the later green runs support but do not prove.

**Could not verify:** anything on a Mac or an iPad; the pages' cover drawing in a real web view (the window check
runs in CI only); real covers from real files (every test picture is generated, every tag built by hand); a
library with thousands of covers; ID3 pictures written by iTunes or Serato specifically.

**Not done:** songs read off a music CD get no cover; thumbnails in the work folder are never cleared out; the
packaging of Desk's window was not started, as told.

carry on

**Newest zip, with `.m4a` reading: `pc-package` run 43545418975** (branch `pc/m4a`, commit `665490a`), artifact
`Deckie-for-PC-first-test` (id 14094366437): **122,379,915 bytes**, SHA-256
`4da005fe55bce0d5be43b12d5aba0806185c39c685a565b48c9492215308874d`. It supersedes the one named further down.

## Nov 14, 2026, 02:50 UTC: `.m4a` works on the Windows runner; all three workflows green on `pc/m4a`

**Seen on the Windows runner** (`core-windows` run 43545419066, commit `665490a`; `core-linux` 43545418976 and
`pc-package` 43545418975 green on the same commit):

- 436 tests pass on Windows. The AAC test tone comes back through the decoder at its own length (176,400 frames)
  with its click at frame 88,200, where it was; the same file with its edit list taken out comes back whole, the
  click 1,024 frames late, and marked.
- **A crate file from real `.m4a` files**, built with `deckie-build` from the test track (124 BPM, first downbeat
  at 0.5084 s as a WAV):

  | File | First downbeat | Against the WAV | Flag |
  |---|---|---|---|
  | AAC, 192 kbps (ffmpeg) | 0.5044 s | -4.0 ms | none |
  | Apple Lossless | 0.5056 s | -2.8 ms | none |
  | The AAC file with no stated lead-in | 0.5308 s | +22.4 ms | `start_uncertain` |

  All three are 32 bars at 124 BPM, decoder `media-foundation`. The limit in the check is 5 ms; an untrimmed
  lead-in is 23 ms, which is what the third file shows. The few milliseconds on the first two are the grid fit, not
  a shift of the audio (the decoder test puts the click on its exact frame), but the AAC file's 4.0 ms is close to
  my 5 ms limit, and I have not measured what the same files give on a Mac.

**Failed along the way:** the first Windows run on this branch (43544024924) failed one older test, which expected
every MP4 that is not protected to be unreadable. True on Linux, no longer on Windows; the test now says so.

**Not proven:** Windows 10 and 11 (the runner is Windows Server 2025); a Windows "N" edition; real iTunes
purchases (the `iTunSMPB` reading is tested on a file built by hand, since no iTunes file is in the repository);
HE-AAC (tested as arithmetic only); files with more than two channels.

**Known gap:** a PC that ran an earlier zip keeps its `.m4a` files marked unreadable until its storage folder is
deleted, because a file that could not be read is not tried again while the engine's version is the same. No earlier
zip was handed out, so I left the builder's rule alone.

**Also done:** the letter has a section on packaging the window (`deckie-desk`): what it takes, a PC without
WebView2, the icon. Nothing of it is built.

**Next:** nothing owed. Candidates: WMA (needs a new case in the public format list), a run on a real PC.

carry on

## Nov 14, 2026, 02:05 UTC: branch `pc/m4a` (from `main`), `.m4a` on Windows written, first push

D33 applied: build it, and a file whose lead-in is stated nowhere is accepted with its start marked uncertain.

**Written, tested on Linux where it can be (433 tests pass here), not yet seen on Windows:**

- `core/Sources/DeckieDecode/MP4Audio.swift`: reads what an `.m4a` says about its start and end (the edit list, or
  iTunes' `iTunSMPB` tag; Apple Lossless has no lead-in) and works out what to drop. It drops the lead-in only when
  the decoded length shows the decoder handed back the whole track, as measured; a length that fits nothing is
  refused, not guessed at.
- `AudioDecoder` on Windows reads AAC and Apple Lossless through the Media Foundation shim and applies that trim.
  A Windows without media features (the "N" editions) reports the file as unreadable, in words.
- **The uncertain start uses what the crate file can already say**: the record's `flags` list gains the name
  `start_uncertain`. No field is added or changed, so there is nothing to stop on; the name is written into
  `docs/architecture/crate-format.md`. The PC program counts such songs in its closing words and lists them in
  the log.
- The Windows workflow now builds a crate file from the test track as AAC, as Apple Lossless, and as AAC with its
  edit list taken out, and checks the first two grids against the WAV's (within 5 ms; an untrimmed lead-in would be
  23 ms) and the flag on the third.

**Not done yet:** the note for the letter on packaging the window (`deckie-desk`); WMA, Ogg and Opus stay unread.

**Next:** read the Windows run; fix what breaks.

carry on

**The zip to use: `pc-package` run 43535065527** (commit `21ad255`), artifact `Deckie-for-PC-first-test` (id
14090055016, kept to Dec 14, 2026): `Deckie-for-PC-first-test.zip`, **122,280,833 bytes**, SHA-256
`6e1cd29b2c9cce10c6e0059954612d5ee9bb35f0b036270773f6cbf4e857e480`. Microsoft's runtime included. Earlier zips are
superseded.

## Nov 14, 2026, 01:15 UTC: `.m4a` measured, reported before building; still green

- **Measured on the Windows runner** (`core-windows` run 43536290887, commit `fffaeb7`, all jobs green): Windows'
  Media Foundation does **not** remove the lead-in of an AAC file. On the test tone the click comes out 1,024
  frames (23.2 ms) late and the audio 1,776 frames too long. The file's edit list says both numbers, so Deckie has
  to read it and trim.
- **So `.m4a` is larger than hoped, and is reported, not built**, as asked: two to three days. The plan and the one
  decision it needs (what to do with AAC files that state their lead-in nowhere: refuse them, or accept them with
  the start marked uncertain) are in the letter, "File types on Windows", "Measured since".
- What is in the tree: the shim (`core/Sources/CMediaFoundation`) and the test that pins the measurement. The
  builder does not use them; `.m4a` is still counted as unreadable, in plain words.
- All three workflows are green on `fffaeb7` (`core-windows` 43536290887, `core-linux` 43536290919, `pc-package`
  43536291060). The zip named at the top (run 43535065527) is unchanged in what it does; the newer run's zip
  differs only by the unused shim inside the program.

**Failed:** nothing.

Later the same hour: the test that pins the measurement went in as `702eeac`, and all three workflows are green on
it too (`core-windows` 43538078109, `core-linux` 43538078136, `pc-package` 43538078075). Nothing after it touches
code.

**Next:** waits on the decision above. The branch is ready for the main session to merge.

carry on; consider changing direction on `.m4a` only if refusing files without a stated lead-in loses too many of a
real DJ's files, because then the record needs a new field and that is a format addition

## Nov 14, 2026, 00:45 UTC: the owner's four answers applied; `main` merged; all three workflows green; fresh zip

The main session relayed the owner's yes to all four open points (Nov 13). Done:

- **Microsoft's Visual C++ runtime ships in the zip**: `msvcp140.dll`, `msvcp140_1.dll`, `vcruntime140.dll`,
  `vcruntime140_1.dll`, version 14.42.34433.0, the copies the Swift toolchain installs beside its own runtime, with
  a notice in the zip's licences and a row in the acknowledgements. Recorded in `DEPENDENCIES.md` section 3 with
  sizes, hashes and the quoted terms. **One thing for the attorney**, written there: Microsoft's permission is given
  to licensed Visual Studio users (the free Community edition counts, within its limits), so the company should
  hold one; and I could quote Microsoft's list of distributable files but not the licence terms themselves, whose
  page did not give up its text.
- **ICU's Unicode License V3** is on the allowlist ("the owner, Nov 13, 2026"); its text ships in the zip.
- The iPad side and the engine's key: nothing done, as told.
- **`main` merged** (at `3be2986`), no conflicts. The merged tree passes 412 tests here on Linux.
- **All three workflows green on `21ad255`**: `core-windows` 43535065509, `core-linux` 43535065566, `pc-package`
  43535065527. The zip was again unzipped and run on the runner with nothing but Windows on the path; this time the
  runtime it used is its own. Four four-minute songs: 5.8 s a song by the clock (10.8 s each on its own).

**Failed:** nothing in this round.

**Next, started:** `.m4a` through Windows' Media Foundation. First only a measurement: a small shim and a test
that prints where the click in the AAC test tone lands on the Windows runner, which says whether Windows removes
the encoder's lead-in. Nothing is wired into the builder until that is known. The commit after `21ad255` carries
it; if it turns the Windows workflow red I fix or back it out, and say so here.

carry on

## Nov 14, 2026, 00:10 UTC: done as far as a runner can show; three decisions open

**Done.** All three workflows are green on commit `13d69b8`:

- `core-windows` run 43529510729: 379 tests passed on Windows with the engine suites running; the end-to-end build;
  Windows against Linux, every compared value identical on the three test songs.
- `core-linux` run 43529510806: the same suites and end-to-end steps.
- `pc-package` run **43529510736**: the zip, **121,600,412 bytes** (SHA-256 `f41d6cd8…29d6`), artifact
  `Deckie-for-PC-first-test`, kept to Dec 13, 2026. Without Microsoft's runtime files this time. Built, unzipped
  and tried on the runner as a DJ would use it.
- Measured on the runner, four four-minute songs, two at once: 6.0 s a song by the clock (11.2 s each on its own);
  the run before, on another runner, 11.3 s by the clock.
- The letter: `docs/research/y-windows-builder.md`, with each claim marked as seen on a runner or not provable
  without a real PC. The tester's words: `core/Tools/windows/READ ME FIRST.txt` and
  `docs/product/windows-first-test.md`.
- The branch merges with `main` (at `3be2986`) without conflicts, checked with `git merge-tree`; not merged.

**Failed or not done:**

- Reading `.m4a` on Windows (step 2's "build what is small and safe"): not built. Nothing about it was small or
  safe; the letter says what it takes.
- Nothing was tried on a real PC. The letter's table lists what that leaves unproven: the blue "Windows protected
  your PC" box, antivirus, a real drag and drop, typing into a real console window, a PC without Microsoft's
  runtime, Windows 10, Windows on Arm, a standard (non-administrator) user.
- The zip of the earlier run 43528242707 contains Microsoft's runtime files and should not be handed on.

**Open, for the owner or the main session, before a tester gets the zip:**

1. Ship Microsoft's Visual C++ runtime in the zip or not. I recommend shipping it.
2. ICU's licence (Unicode License V3), which Swift's Foundation brings: yes or no.
3. The iPad app: build against this core, call `CrateArchive.unpack` on import, and let its document type take a
   plain file. Needs a device.
4. The engine writes its own key on Windows and Linux, which D16 says it should not yet.

**Next, if this carries on:** a run by hand on a real PC; then `.m4a` through Media Foundation with the lead-in
measured.

carry on, once the three decisions are made; consider changing direction only if the iPad cannot take a plain
file under `.deckiecrate`, because then the single file needs its own extension (a small change, in one place)

## Nov 13, 2026, 23:45 UTC: steps 1, 3 and 4 seen working on Windows runners; step 5 written; step 2 reported, not built

**Done and seen on GitHub's Windows machine:**

- **Step 1.** `core-windows` run 43526173797 (commit 2337e7b) is green in all four jobs. The engine suites run on
  Windows instead of skipping (the test step's own lines: 25 inference tests, 35 engine tests, 33 builder tests, all
  passed; the only skips are one test that needs Linux's library layout, the suite that runs only where the vocal
  model is missing, and three MP3 tests that need the ffmpeg program, which skip in Linux CI too). The end-to-end
  build made a crate file from the generated folder with `deckie-build`, the core's validator read it in both forms,
  and a second run read nothing. **Windows against Linux: every compared value identical** on the three songs
  (WAV, FLAC, MP3), records and float16 sidecars alike; the tolerance in `core/Tools/compare_crates.py` was not
  needed on this folder and stays as the guard for real music, which CI does not have. `core-linux` run
  43526173752 is green with the same end-to-end steps.
- **Step 3.** The single-file form's tests pass on Windows in that run, including the committed file made on Linux
  being read and rebuilt byte for byte on Windows. Written into `docs/architecture/crate-format.md` as a proposed
  addition, with what the iPad app needs.
- **Step 4.** `pc-package` run 43528242707 (commit 2a13a42) is green: the zip was built on a Windows runner
  (121,892,360 bytes; 188 MB unzipped, 37 files), unzipped with Windows' own tool into a fresh folder with a space
  in its name, and "Make Crate File.exe" was started with nothing on the path but Windows: a folder given as its
  argument (what a drop does) made the crate file and the log next to the music folder; a second run read nothing;
  with no argument it asked for the folder, said a wrong path plainly, and took the right one; the starter alone,
  without the rest, said to unzip first. **But that zip must not be handed on** (next point).

**Failed or found, exactly:**

- **The zip of run 43528242707 contains Microsoft's Visual C++ runtime** (`msvcp140.dll`, `msvcp140_1.dll`,
  `vcruntime140.dll`, `vcruntime140_1.dll`), which I had said would not ship. The Swift toolchain's own runtime
  folder holds a copy, and the script copies whatever the program imports from that folder. Fixed in commit 13d69b8
  (the script now leaves them out and stops if one gets in); the run of that commit is the zip to use. The owner's
  decision is still open: Swift's own installer ships these files beside its runtime, and a PC whose copy is older
  than the one Swift was built with would fail to start, so my recommendation is to ship them, once the licence is
  accepted (`DEPENDENCIES.md`, section 3; one switch in `package.sh`).
- The first `pc-package` run (43527240272) failed in one step only: the test of the starter alone treated the
  starter's expected ending as a failure. A mistake in the workflow, fixed.
- The first runs of both core workflows failed at the end-to-end step because the MP3 was not in the repository
  (see the entry below).
- **ICU's licence** (Unicode License V3) is not on the allowlist word for word. ICU is inside Swift's Foundation and
  cannot be left out. It was already named in the acknowledgements table; now a build carries it, the main session
  needs to say yes or no. Texts and hashes: `core/notices/swift/`.
- **The engine writes its own key into the record** (confidence 0.45 or 1.0) on Windows and Linux, though D16 says
  a platform without Apple's framework carries no key of Deckie's own until it meets the bar. I did not change the
  engine. The READ ME says "no key yet", which is true of what the booth should show, not of the file's bytes.

**Step 2, reported instead of built.** On Windows the builder reads MP3, FLAC (and Ogg-FLAC), WAV and AIFF, as on
Linux. It does not read AAC or Apple Lossless (.m4a, .mp4, .aac), WMA, Ogg Vorbis or Opus, and never protected
files. The program says which files it could not read and why, counted by type, on screen and in the log. Reading
.m4a through Windows' Media Foundation is not small and not safe to ship unmeasured: the letter says what it takes
(a C shim of about 200 lines, loaded at run time so Windows editions without media features still start, and a
measurement of the 23 to 48 ms lead-in AAC files carry, on Windows 10 and 11, before any grid from such a file can
be trusted).

**Next:** read the run of commit 13d69b8 (zip without Microsoft's files; time per four-minute song), then the
letter `docs/research/y-windows-builder.md`.

carry on

## Nov 13, 2026, 23:10 UTC: first push (steps 1 and 3 written, not yet seen on a Windows runner)

**Done, on Linux only so far (this cloud machine, Swift 6.4.1):**

- Step 3, the single-file form: `core/Sources/DeckieCrate/CrateArchive.swift`. A plain zip with nothing compressed,
  written and read by about 250 lines of our own, no new dependency. `CrateReader.read(from:)` now takes either form
  in the one call. 11 tests pass here (round trip, canonical bytes, a zip from another tool, a changed byte, a file cut
  short, compressed and encrypted entries refused, more than 65,535 files). `unzip` and Python's `zipfile` both open
  what it writes. A committed fixture, `core/fixtures/example-single.deckiecrate` (21 KB, made on Linux), is what the
  "made on one platform, read on another" test reads and must reproduce byte for byte on every platform.
- Step 1, written: `fetch-onnxruntime.sh` now fetches the Windows x64 archive too when run in Git Bash (both pins were
  already in `DEPENDENCIES.md`; the workflows use Deckie's own build, 6.6 MB). `core-windows.yml` fetches it and the
  two models, runs every suite, then builds a crate file from a generated folder with `deckie-build`, validates it
  and uploads it; a second job builds the same folder on Linux; a third compares the two
  (`core/Tools/compare_crates.py`, which states the tolerance and why). `core-linux.yml` runs the same end-to-end
  steps. The new tool `deckie-e2e` makes the folder and checks the result. On this machine: 3 songs in (WAV, FLAC,
  MP3), 2 files not in with their reasons, 1 folder left out, hidden files not read, second run reads nothing.

**Two things the main session should know:**

- No audio is committed. (I first meant to commit a generated MP3 of the synthesised test track; that was stopped,
  rightly, by the rule. The MP3 is now encoded once per workflow run on Linux with ffmpeg and handed to the Windows
  job as a run artifact, so both platforms read the same bytes.)
- The Windows ONNX Runtime library needs four Microsoft files that are not part of every Windows:
  `MSVCP140.dll`, `MSVCP140_1.dll`, `VCRUNTIME140.dll`, `VCRUNTIME140_1.dll` (the Visual C++ runtime; Swift's own
  runtime needs it too). Shipping them in the zip means a Microsoft licence that is not on the allowlist, so I have
  not added them. Plan: the program checks for them first and says in plain words what to install if they are
  missing. This is the one place "needs no other software" may not hold on a fresh PC. The owner decides whether
  the four files ship.

**Failed:** nothing yet; nothing has run on Windows yet.

**Next:** read the first Windows run and fix what breaks; then the program a DJ drags a folder onto (step 4), file
types (step 2), the words (step 5).

carry on
