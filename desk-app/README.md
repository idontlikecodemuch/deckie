# Deckie Desk (Mac)

Desk reads a DJ's crate and writes a crate file the booth can use (D21). The DJ adds music (a folder, or a CD or a
drive read as it is); Desk does everything in one run (tempo, key, bars and the rest, the recognition signatures made
on this Mac with ShazamKit, the copies of one recording found) and keeps the crate in its own storage (D28). The crate
file leaves only when the DJ sends it to the iPad (the share sheet, so AirDrop is one click) or exports it. The music
never leaves the machine.

The analysis is the shared Swift engine in `core/` (the `deckie` family: Beat This! and YAMNet through ONNX Runtime,
the lab's DSP, the research R key method). Apple's Music Understanding framework needs macOS 27; on an earlier macOS
this engine is the fallback, and it meets the charter's marks on the 373-track yardstick (stage 2a to 2c). What Desk
does that is not about windows is in the core's `DeckieDesk` (`core/Sources/DeckieDesk`), for the Windows and Linux
desks to share.

## Build

Needs Xcode 27, `xcodegen` (Homebrew), and the vendored runtime and models in `Vendor/` (not committed):

    Vendor/libonnxruntime.1.31.1.dylib            ONNX Runtime for macOS arm64 (our no-telemetry build, or Microsoft's)
    Vendor/models/beat_this_final0.onnx           release models-1
    Vendor/models/yamnet.onnx                     release models-1
    Vendor/models/deckie-key-2b4fe8fa.f16         release models-1; optional (the learned key reader)
    Vendor/models/deckie-key-2b4fe8fa-credits.tsv release models-1; ships with it (the credit CC BY asks for)

The key reader's two files are fetched by their pinned hashes, and are never committed:

    bash core/Tools/fetch-key-model.sh --into desk-app/Vendor/models

Without them the app reads keys with the untrained reader. With both, the post-build step puts the model in
`Contents/Resources/models` and the credit list, with a sentence saying what it is, in `Contents/Resources/licences`;
`"Deckie Desk" --check-engine` prints which key reader the app found (`key reader: learned, ...` or `untrained`).

Then:

    cd desk-app && xcodegen generate
    nice -n 19 xcodebuild -project Desk.xcodeproj -scheme Desk -configuration Release -destination 'platform=macOS' -derivedDataPath build build
    open "build/Build/Products/Release/Deckie Desk.app"

The post-build step copies the runtime into `Contents/Frameworks` and the models into `Contents/Resources/models`;
the app points the engine at them on launch (environment variables set in-process, which a developer's own
`DECKIE_*` variables override). Code signing is ad hoc for now.

## Releasing Desk for Mac

A download that opens on another Mac needs three things the everyday build above does not have: a Developer ID
signature, the hardened runtime (a set of limits macOS puts on a signed app, which notarisation requires), and
Apple's notarisation (Apple checks the app for malicious code and issues a ticket that is stapled to it, so
Gatekeeper lets it open without asking twice). `tools/release-mac.sh` does all of it; the everyday build and CI stay
ad hoc. Decided Nov 25, 2026 (roadmap Now-6).

**What the owner does once**, on the Mac that makes releases: the "Developer ID Application" certificate (Xcode >
Settings > Accounts, the App Hold Media team, Manage Certificates, +), made Nov 25, 2026 and in the login keychain.
The script finds it there by name each time, so no team id or certificate is written in this repository. After that,
the upload goes through the team's account signed in at Xcode > Settings > Accounts, with the login keychain unlocked
(decided Nov 25, 2026: no app-specific password, no API key, no notarytool profile). Collecting the notarised app
afterwards needs no sign-in: it staples Apple's ticket to the app Xcode sent.

**Then, from the main checkout**, with `Vendor/` filled as for the everyday build:

    bash desk-app/tools/release-mac.sh                  # build, sign, verify, package (nothing sent to Apple)
    bash desk-app/tools/release-mac.sh notarise         # sends the app to Apple through Xcode, waits, finishes
    bash desk-app/tools/release-mac.sh notarise-finish  # only the wait and the rest, when the upload already went

Run `notarise` once per build. If the wait stops (the time limit, a closed terminal), run `notarise-finish`, never
`notarise` again for the same upload.

The first command needs no network but for the two pinned downloads below and Apple's timestamp server. `notarise`
is the only stage that sends anything to Apple, and it runs only when named. It ends with the notarised, stapled app
in place, `desk-app/build/release/Deckie Desk.dmg` made from it and signed, and `Deckie Desk.zip` beside it.
Xcode's route notarises the app only: the disk image is signed with Developer ID but not itself notarised, and the
app inside it is the notarised part. Testers get `docs/product/mac-first-test.md`.

**The stages**, each runnable alone and in order (`release-mac.sh sign verify`, and so on):

- *build*: a clean Release build for Apple silicon only (`ARCHS=arm64`; the runtime in `Vendor/` is arm64),
  `nice -n 19`, two jobs, with 30 GB free on the disk. It makes sure the app ships what the Windows zip ships:
  the learned key reader's file and its credit list (fetched into `Vendor/models` by `core/Tools/fetch-key-model.sh`
  when missing, checked by their pinned hashes; the stage stops if they cannot be had), and Deckie's own ONNX
  Runtime, the build without Microsoft's usage-reporting client (DEPENDENCIES.md, section 6), fetched into
  `build/release/onnxruntime` from this repository's release, checked by the archive's and the library's pinned
  hashes and by `core/Tools/scan-onnxruntime.sh`, and put in the app in place of whatever library `Vendor/` holds.
  It ends with the app's own `--check-engine`, which must say `key reader: learned`.
- *sign*: every piece of code in the app, found by looking at each file (today only the ONNX Runtime library; the
  Swift packages are linked into the app's program), then the app, with `--options runtime --timestamp` and
  `Desk/Desk.entitlements`. The identity is the keychain's one "Developer ID Application" identity, or
  `DECKIE_SIGN_IDENTITY`; with neither, it stops and says what is missing.
- *verify*: `codesign --verify --deep --strict`, the signature's flags and entitlements, each piece of code checked
  for the runtime flag and the app's team (what library validation asks), and `spctl -a -vv`, which rejects the app
  until it is notarised; reported, not a failure.
- *package*: `Deckie Desk.dmg`, volume name "Deckie Desk", holding the app and an alias to Applications, with Desk's
  icon as the volume's icon (made writable to set the volume's custom-icon flag with `SetFile`, then compressed),
  signed with the same identity, then mounted read-only to check that the app inside verifies.
- *notarise-check*: local only, nothing sent. The archive and the export options as below, then an export with
  `destination` `export` into `build/release/export-check`, to see Xcode's re-sign and check it as notarise-finish
  checks the notarised app.
- *notarise*: wraps the signed app in an archive (`Deckie Desk.xcarchive`), made by hand: the layout and the
  Info.plist keys every Xcode archive has, filled from this app, rather than `xcodebuild archive`, which would build
  the app again ad hoc and leave an archive describing another signature. It writes the export options when it runs
  (`method` `developer-id`, `destination` `upload`, `signingStyle` `manual`, `signingCertificate` "Developer ID
  Application", and the team read from the signed app's signature), then runs `xcodebuild -exportArchive ...
  -allowProvisioningUpdates`, which re-signs the app with the certificate and sends it to Apple's notary service
  under the account signed in to Xcode. Then it does what notarise-finish does.
- *notarise-finish*: runs only on an archive the notarise stage sent. Xcode keeps the exact app it uploaded in the
  archive (`Submissions/<id>/Deckie Desk.app`); the stage copies it into `build/release/staple/` and tries
  `xcrun stapler staple` on the copy every 5 minutes (`DECKIE_NOTARY_INTERVAL`, seconds) for up to 4 hours
  (`DECKIE_NOTARY_MINUTES`). Until Apple's ticket exists the stapler answers "Record not found" (Error 65), taken as
  not ready yet. Stapling asks Apple's public ticket service and needs no Xcode account, so a sign-in that drops
  during the wait does not stop it (it dropped twice during the first real wait, Nov 25, 2026). With several
  uploads in one archive, `DECKIE_NOTARY_SUBMISSION` names the one meant. Stapling cannot tell an app Apple is still
  checking from one it refused, so at the time limit the stage asks `xcodebuild -exportNotarizedApp` once and
  prints its words (never failing on an account error), and says where to see the answer: double-click the archive
  to open it in Xcode's Organizer. `DECKIE_NOTARY_VIA=xcode` collects through `-exportNotarizedApp` instead, which
  needs the account signed in for the whole wait.
  Then it checks the app strictly: Developer ID, the runtime flag and a secure timestamp on the app and on every
  piece of code in it, one team throughout, the entitlements exactly the microphone and nothing added, the ONNX
  Runtime library still Deckie's own (the scan, and the same code as the pinned library once the signatures are
  taken off), `stapler validate`, and `spctl` accepting it as Notarized Developer ID. Then it puts it in place of the
  app, makes and signs the disk image from it (the package stage), makes the zip (`ditto -c -k --keepParent`), and
  marks a copy of the image as a browser marks a download and says what Gatekeeper makes of it and of the app
  inside.
- If Xcode cannot use the account for the upload (not signed in, keychain locked), the stage ends saying so: unlock
  the login keychain and sign in at Xcode > Settings > Accounts.

The script writes only in `desk-app/build/release/` (git-ignored), and refuses any other path, except the generated
`Desk.xcodeproj` and the key reader's two files in `Vendor/models`, which the everyday build makes too. Every run of
Desk it makes uses scratch storage there, never the real one.

**The entitlements** (`Desk/Desk.entitlements`), decided on what the code does, Nov 25, 2026:

- `com.apple.security.device.audio-input`, the only one: Booth listens through the microphone (DeckieCapture's
  `Microphone`, miniaudio on Core Audio). macOS still asks the DJ, with `NSMicrophoneUsageDescription`.
- No `disable-library-validation`: ONNX Runtime is opened with `dlopen` from `Contents/Frameworks`
  (`core/Sources/COnnxRuntime/deckie_ort.c`) and signed by the same team as the app, which is what library
  validation asks. No `allow-jit` or `allow-unsigned-executable-memory`: nothing writes code at run time; a song
  read end to end under the hardened runtime without them showed it. No Apple Events: Desk sends none.
- ShazamKit: Desk only makes signatures from files (`SHSignatureGenerator`, `Signatures.swift`) and never matches
  against Shazam's catalogue; Booth names songs with Deckie's own recogniser (DeckieRecognition). Neither needs an
  entitlement. No App Sandbox.

**Proven Nov 25, 2026, with a trial signature** (the team's Apple Development identity through
`DECKIE_SIGN_IDENTITY`; same team, so library validation behaves as it will with Developer ID): the signature
verifies with the runtime flag and the one entitlement, the app reads the demo songs (`site/demo/audio`, CC0) end to
end under the hardened runtime, the ONNX Runtime library loading and all three models running (the beat grid from
Beat This!, vocals from YAMNet, keys from the learned reader), and the disk image mounts with the app inside
verifying and reading a song from there. A copy whose ONNX Runtime library was signed ad hoc instead could not open
it ("different Team IDs"), so library validation is really in force and the same-team signature is what lets the
library load.

**Proven Nov 25, 2026, with the Developer ID certificate:** build, sign, verify and package in the main checkout
(Developer ID authority, the runtime flag, a secure timestamp; Gatekeeper: "rejected, source=Unnotarized Developer
ID", as expected before notarisation); and notarise-check: Xcode exported the hand-made archive with the manual
Developer ID re-sign, keeping the runtime flag and the timestamp on the app and the library, the one entitlement
with nothing added (no `get-task-allow`), one team, and the ONNX Runtime library's code unchanged. A copy of the
signed image marked as downloaded was rejected by `spctl -t open` as "Unnotarized Developer ID", and so was the app
inside before notarisation. **The first real upload, Nov 25, 2026:** `notarise` sent the app ("Uploaded Deckie Desk", `** EXPORT
SUCCEEDED **`); while Apple worked, `-exportNotarizedApp` answered that the archive "is processing", and twice
Xcode's account stopped being usable by `xcodebuild` mid-wait though Xcode's window still showed it signed in, which
is why collecting now staples instead. The stapling path was tried with stand-ins for `xcrun`, `xcodebuild` and
`spctl` (no ticket yet, a ticket on the third try, the time limit with Xcode processing or without an account, one or
several uploads), not yet against a real ticket. **Not proven:** Apple's answer, the stapled app and Gatekeeper's
yes;
whether a tester's Mac opens a disk image that is signed but not notarised without a warning (only a second Mac can
show it; the zip is the fallback); the microphone question under the release signature, which needs a person.

**Bundle id and the crate file's type.** The bundle id is `io.deckie.desk` (until November 2026 it was under an
earlier prefix). Desk declares the crate file's type as the booth does (`project.yml`, `UTExportedTypeDeclarations`):
`io.deckie.crate` for the package form, `io.deckie.crate-file` for the single-file form, both under the extension
`.deckie` and the earlier `.deckiecrate`; the booth's earlier type ids are declared as imported types conforming to
these. So the Mac shows a crate file as one file of the kind "Deckie crate file", not a plain folder. Desk declares no
document type, so a double-click does not open Desk; a crate file comes in through File > Import crate file. What
Desk keeps (`~/Library/Application Support/Deckie Desk`) does not depend on the bundle id, so a Desk with the new id
finds every crate made before. Desk keeps no settings under its bundle id.

## The icon

Desk for Mac has the same picture as Desk for Windows: the orange record on the dark ground, with no word on it
(decided Nov 25, 2026; the iPad app's icon is the same record with "Booth" across it). The pictures are in
`Desk/Assets.xcassets/AppIcon.appiconset` (16, 32, 128, 256 and 512 points, each at 1x and 2x), and `project.yml`
names the set with `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. The build turns them into `Assets.car` and
`AppIcon.icns` in `Contents/Resources`, and the app's Info.plist says where they are (`CFBundleIconName` and
`CFBundleIconFile`, both `AppIcon`).

`tools/draw_mac_icon.py` draws them, with Python's standard library only:

    python3 desk-app/tools/draw_mac_icon.py

It draws the record at each size from the site's vector icon (`site/icon.svg`), using the drawing code of
`deck-app/tools/draw_icon.py` (the iPad's icon and the plain picture the Windows icon is made from), so the colours
and rings are the same as theirs. It puts the record in the shape Apple gives every Mac app icon: a square with
rounded corners, 824 of the 1024-wide canvas, with clear space around it and a soft shadow underneath. At 128 pixels
and below, the edges of the shape are put on whole pixels so the small sizes stay sharp. Run it again after a change
to `site/icon.svg` and commit the pictures it writes. The same input always gives the same files.

The release script puts the same icon on the disk image's volume (`.VolumeIcon.icns`, made from these pictures).

## Words and design values (D36)

- **Words**: every word the window shows is in `DeskWords` (`core/Sources/DeckieDesk/DeskWords.swift`), the one list
  for Desk on every computer; `Desk/Sources/Words.swift` gives each a Swift name and fills its blanks. Words built
  from parts are templates with named blanks there (`"lookupCandidateTitle": "{title} ({version})"`), and the
  separators between items are words too (`join.*`), so no view joins words of its own.
- **Design values**: every colour, font, weight, space, size, corner, opacity, line and time is a named constant in
  `Desk/Sources/Look.swift`, grouped by role (`Look.Colour`, `Look.Fonts`, `Look.Space`, `Look.Size`,
  `Look.Shape`), with the run screen's in `RunLook` and the lookup's in `LookupStyle`, in the same file. Left in
  the views: the system's own named roles (`.secondary`, `.quaternary`, `.bar`, `.tint`, control styles, SF Symbol
  names) and the drawings' own arithmetic.
- **To change one**: a word, in DeskWords' table; a design value, in Look.swift. Nothing else changes.
- **The rule**: views hold neither words nor design values. The core's `VariablesTests` read the views' source and
  fail when one creeps back in (what they can and cannot catch is written there).

## Where Desk keeps things (D28)

Desk never asks where to save. Everything it makes is in `~/Library/Application Support/Deckie Desk/`, or in the
folder named by `DECKIE_DESK_HOME` when that is set (every test and manual run uses a scratch folder this way, so the
real storage is never touched). The layout (`DeskHome`, `core/Sources/DeckieDesk/DeskHome.swift`):

    desk.json                      the layout's format number (1)
    libraries.json                 DJ libraries the DJ chose by hand (File > Choose a DJ library…), read on every run
    quick-start.json               the quick start's card hidden, and the film played once (D46, DeskQuickStart)
    Crates/<id>/                   one folder per crate; <id> is a lowercase UUID made with the crate
      crate.json                   its name, when it was made and last opened, where each source and the music folder were read from,
                                   and (since Nov 25, 2026, `source_ids`, left out when empty) the identity of the drive
                                   each source was read from
      crate.deckie/                the crate file itself (crate v1, unchanged), written as the DJ works; a crate
                                   made before November 2026 keeps `crate.deckiecrate/`, read and written there
      crate.deckiebuild/           the builder's work folder (which file is which record), for a quick re-read
      corrections.json             the DJ's name fixes, by entry id, each field with how the DJ gave it
      names.json                   where each name was read from, field by field, and each song's release
      places.json                  where each place's file was, below its source's top or the music folder
      pending.json                 a run that started and has not finished; gone when it finishes (since Nov 25, 2026,
                                   with the identity of the drive it reads, `volume`, when there is one)
      runs.jsonl                   one line per finished run: counts and timings
    Files/                         what was worked out for each file, by the file's id (the hash of its bytes)
      records/<id>.json            the analysis (the builder's records, shared by every crate's work folder)
      signatures/<id>_o.*          a recognition signature, and who made it when
      prints/<id>.print            the print that finds copies of one recording
      discs/<disc id>.json         what was learned from a music CD (its table, its CD-Text, each song's id); no sound
    Outbox/<name>.deckie           the last crate file handed to the share sheet
    Reading/                       Windows and Linux only: the one song being read off a music CD, while it is worked
                                   out; removed when it is done, and at the next start after a stop (see below)

Absolute paths (where a stick was mounted, the music folder) are only in `crate.json` and `places.json`, never in the
crate file. Desk keeps no song's sound, from any source: `Files/` holds what was worked out (analysis, fingerprints,
prints), and every song is read where it is (the note on D33, Nov 14: the owner decided that the crate file never
holds a copy of the music). Deleting a crate in the window moves its folder to the Trash (with `DECKIE_DESK_HOME` set, it is deleted);
`Files/` stays, so adding the same music again is quick.

## The flow

**Several crates.** Desk opens on the crate opened most recently. The crate menu at the left of the toolbar says which
crate is showing; it lists the others, then New crate, Rename crate… and Delete crate… (which asks first). New crate
shows the first screen; the crate is made when music is added, named after the source or folder (made unique, "Friday
night 2"). With no crate at all, the first screen offers Add music the same way.

**The quick start** (D46, `QuickStart.swift`). Until the DJ hides it, the first screen opens with a card in place of
the crate's big drawing: the poster of the quick-start film with a play button, "New to Desk?", "Watch the quick start
(1 minute)" and Hide. The film (about a minute, silent, captions in the picture) plays in a sheet; it never starts by
itself (`DeskQuickStart.playsItselfOnFirstOpen` in the core is the one switch, off). Afterwards it is Help > Watch the
quick start. The film and poster are the pages' (`desk-web/quick-start/`), copied into `Contents/Resources/quick-start/`
by `project.yml`; nothing is fetched. If the Mac cannot play it (missing, not playable, or the player fails), the card
and the sheet show the poster and the film's four steps in words. Whether the card was hidden is in `quick-start.json`
in Desk's storage, where the Windows and Linux window keeps it too. The Mac plays the same film as Windows and Linux,
made from their window; its captions are true on a Mac. A Mac cut needs the Mac's whole window, toolbar and share
sheet included, which only the window server can picture (see Pictures, below).

**Seen running, Nov 23, 2026** (`--quick-start-walk`, below): the card on the first screen; the film in its sheet (the
player said ready, 1280 by 720, its time going on); Help > Watch the quick start, the Help menu's one item, opening the
same sheet; Hide, after which the first screen shows the crate's drawing and `quick-start.json` says hidden and
played; a film file that is not a film and a missing film file, each giving the poster and the four steps in words on
the card and in the sheet. Fixed then: at the window's smallest size the first screen was taller than the window (the
body cut to one line ending in "…", the last line below the window), so it now scrolls when it does not fit; the three
tiles of the ways in were three heights, now one; the sheet's steps in words were squeezed to half their width.

**Add music** (toolbar, the first screen, or File > Add music to …) adds to the crate showing and says so ("Add music
to Friday night"). It lists the CDs and drives mounted on this Mac by their own names, then "Choose a folder…" for
anything else; whatever is chosen is read as a source, named after its volume or its folder (see below). What is
added is either a source the crate already has (read again: its songs are replaced by what is found now) or a new
source, named "Music 2", "Music 3", ... when its name is in use. Since Nov 25, 2026 this is decided by the drive's own
identity (`SourceIdentity`, `SourceNaming.choose`), because unbranded sticks nearly all share a name ("NO NAME",
"Untitled", "USB DISK") and are mounted one after another at the same path. The identity is the volume UUID on the Mac
(FAT32 and exFAT sticks have one, made from the serial number written when the stick was formatted; a FAT stick whose
serial number is 0 has none), the volume serial number on Windows, and the file system UUID on Linux
(`/dev/disk/by-uuid`, no privileges needed), with the folder's path below the drive's top. It is kept in `crate.json`
(`source_ids`), never in the crate file. The rule, against each source of the crate:

1. A source whose drive has the same identity and the same place on it is that source, whatever its name now and
   wherever the drive is mounted.
2. Both identities known: a different drive is a different source; the same drive at another place on it (a folder
   moved on the stick) is decided by evidence.
3. An identity missing on either side (a file system that gives none, or a source recorded before Nov 25, 2026): the
   very same folder on the computer's own disk is the same source (a path there is not reused by another drive, as a
   mount point is); anything else is decided by evidence.
4. Evidence: more than half of the files the source is known to hold (`places.json` and each song's own path) are at
   the place added, under the same path below its top with the same size. A source with no known files never passes.
5. When nothing says it is the same, it is a new source: a wrong "same" would replace that source's songs, a wrong
   "new" only lists a song in two places.

A source recorded before Nov 25, 2026 keeps working: when its stick comes back it is found by evidence, and its
identity is kept from that read on. A run carried on reads only the drive it was asked for (`pending.json`'s
`volume`): another stick mounted at that path since is "not in a drive". The rekordbox route stays where it was
(the first screen, and File > Add music with a rekordbox collection…): an export, then a folder read as a source named
after it like any other (D31), with names, tempos, keys and cues from rekordbox (matched by the path below the folder,
so a source named "Music 2" still finds its entries). The folder chooser says so: "Choose the folder your music is in.
It becomes a source, named after the folder."

**One run** (`DeskRun`, `core/Sources/DeckieDesk/DeskRun.swift`). The builder reads and analyses with its jobs; as each
song is read, its signature (ShazamKit) and its print (`RecordingPrint`) are made on one more thread, or taken from
`Files/` when they were made before; songs taken from the work folder are finished after the builder. Then copies of
one recording are linked (`cut_key`, D24), the keys and names already on this Mac are gathered (below, D30), the DJ's
name fixes are put back, each place's path is remembered, the
crate's name is written into the crate file and it is saved. One progress view: songs done of songs found (a song is
done when it is read, signed and printed), the stage, and an estimate of the time left (the builder's estimate, or the
finishing queue's at its measured rate, whichever is longer). Make signatures and Find copies are no longer buttons.

**Stopping.** Quitting Desk mid-run loses nothing done: the builder keeps each finished file in the work folder,
signatures and prints go to `Files/` as they are made, and `pending.json` says what was being read. The crate then
says "Desk stopped before it finished reading …" with Carry on (or, when the stick is not in, a line asking for it);
carrying on reads only what is left.

**The finished screen.** How many songs went in, how many did not and why (from the import log, this read only), the
folders left out, how long the run took and the rate in songs a minute, then the next step, Send to iPad, and "See the
songs". The same numbers, with the parts of the run (build, finishing), what was analysed or reused, the signatures
and prints made, kept or failed, the jobs, device and engine, are one line of `runs.jsonl` per run, so real timings
can be collected. Nothing is tuned from them.

**Keys and names already on this Mac (D30).** Part of every run, with no button: `DeskLocalFacts` and `LocalFacts`
(`core/Sources/DeckieDesk/DeskLocalFacts.swift`, `core/Sources/DeckieBuild/LocalFacts.swift`). Nothing leaves the Mac,
and every DJ library is read from a copy, never written or locked.

- *What is read.* Each song's own tags (the key tag, TKEY or INITIALKEY; a key Mixed In Key wrote into the comment or
  the title; title, artist, album, track number), and the libraries of the DJ's programs: Traktor's `collection.nml`,
  Engine DJ's `Engine Library/Database2/m.db`, Serato's `_Serato_/database V2`, VirtualDJ's `database.xml`, found in
  the home folder where each program keeps it (on a Mac and on Windows) and at the top of each source read; a
  rekordbox collection export (XML) from the rekordbox route or chosen by hand. rekordbox's own library is encrypted
  and is not opened; when it is there and no export was given, the finished screen says how to export one. Any of
  these files can also be chosen by hand: File > Choose a DJ library… (kept in `libraries.json`).
- *Which key.* The DJ's own key wins, with Deckie's own reading kept beside it as a vote ("Deckie says 4A"). A song
  no program or tag has a key for keeps Deckie's own reading exactly as before, shown as "read by Deckie" (the note on
  D30 and D16: a key is preferred; the per-song "when sure" rule waits for the key trial and goes in
  `LocalFacts.decideKey`). A song with no key at all says "Key not read on this computer yet", and the booth's
  scoring leaves its key out of a pair's score. Where programs disagree, the program whose library was written most recently wins, then the file's
  key tag, its comment, its title; every key found stays in `key.votes`, and the table's Key from column and its help
  show where each came from ("8A from Traktor; rekordbox says 9A"). A record read by Apple's framework keeps that
  reading as its key.
- *Names.* A song with no usable title or no artist gets each missing part from, in turn: its tags, its file name
  read by pattern ("Artist - Title"; a leading number taken off when it is the song's place, "02 Song A" at place 2
  is "Song A"; underscores as spaces), its folder as the artist ("Artist - Album" holding numbered files), a `.cue`,
  `.m3u`/`.m3u8` or numbered `.txt`/`.nfo` list beside it, the DJ programs' libraries, a named copy of the same
  recording. `ident.source` says where; the inspector's Name from row says it in words. A DJ's fix always wins.
- *The finished screen* says how many keys came from where, how many songs have none, and how many still need a name
  ("Show them" shows only those). The status bar's "n need a name" does the same at any time. Naming is below; the
  one step that uses the network is "Look up songs via MusicBrainz", and only when the DJ asks (D36, below).
- *Again.* File > Look again for keys and names reads the tags and libraries again for the crate showing, without
  reading its music again (one undo step).
- *Tests and manual runs* never look in a real home folder: a desk whose storage is not the standard one (a scratch
  `DECKIE_DESK_HOME`) looks only in the folder named by `DECKIE_DJ_HOME`, when that is set.

**Out and in.** Send to iPad copies the crate file to `Outbox/` under the crate's name and opens the Mac's share
sheet with it. File > Export crate file… writes a copy where the DJ chooses. File > Import crate file… checks a crate
file and copies it in as a new crate; the original is only read. A crate file sent or exported carries only its own
songs' signatures.

**Saving as it goes, with undo.** No Save button and no "Unsaved changes": every change is written a moment after it
is made, and when Desk quits. A name fix (committed when the field is left or Return is pressed, so one fix is one
step), a source or folder rename, and a move in the Sources panel undo and redo with Edit > Undo and Redo (Command-Z,
Shift-Command-Z). Music that was added is undone by removing its source from the crate: select the source in the
Sources panel, then Remove from crate…; the confirmation says how many songs go (those with no place anywhere else;
songs that are elsewhere too stay, a place there taking the lead). That removal is one more undo step. Undo starts
afresh when another crate is shown, and after a run.

**Name fixes survive a re-read.** Reading a source or folder again writes the names from the files' tags. Desk keeps
each fix in `corrections.json` by the entry's id and puts it back after every run, so a fix stays across reads and
launches (`NameCorrections`). A fixed name is marked as the DJ's (`ident.source` "user"). Fixes belong to one crate.

**A song read once is not read again.** The builder's records, the signatures and the prints are kept in `Files/` by
the file's id and used by every crate: adding the same stick to a second crate hashes each file (to know which song it
is) and analyses, signs and prints nothing.

**Every place's file is known.** The crate file carries one path per entry (`file.rel`, the own place's). Desk
remembers the path at every place it read (`places.json`, `PlacePaths`): when a source is read again without a song
and a place on another source takes the lead, `file.rel` is set from there instead of left unknown, and anything that
needs a song's file tries each place in turn and takes the first whose source is plugged in.

**The words.** Every word the window shows is in `Desk/Sources/Words.swift`, by name (D28: placeholders until the copy
audit). The views have none of their own.

## Headless

Desk's own crates, in the storage the window uses (`DECKIE_DESK_HOME` moves it), `HeadlessDesk.swift`:

    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --crates
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --add-music <folder or drive> [crate] [jobs]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --carry-on [crate]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --show [crate]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --locate [crate]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --fix <crate> <id or title> <title|artist|version> <value>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --remove-source <crate> <source, or - for the music folder>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --rename-crate <crate> <new name>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --delete-crate <crate>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --export <crate> <out.deckie>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --import <file.deckie>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --libraries [crate]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --choose-library <file>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --look-again [crate]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --open <crate>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --snapshot <out folder> [crate]

Pictures of the window, with no one at the keyboard (each run with `DECKIE_DESK_HOME` set to a scratch folder):

    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --quick-start-walk <out folder>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --film-walk <out folder> [crate]
    DECKIE_SNAP_ON_SIGNAL=<out folder> "Deckie Desk.app/Contents/MacOS/Deckie Desk"     (each SIGUSR1 writes a picture)

`--quick-start-walk` (`QuickStartWalk.swift`) walks the quick start: the card at the usual size and at the smallest, the
film started as the play button starts it with what the player reports, Help > Watch the quick start, Hide; it prints
what it finds. `--film-walk` (`FilmWalk.swift`) writes the stills the site's film uses: the crate's songs, the Sources
panel, then Booth a frame a second. With `DECKIE_BOOTH_SOUND` naming a sound file, Booth hears that file as if the
microphone did, as the engine's stand-in does for the pages (no microphone is opened). Run the app's binary directly
with `-NSTreatUnknownArgumentsAsOpen NO` after the arguments, so the environment reaches it. Where macOS has not
allowed Deckie Desk to record the screen (Privacy & Security > Screen Recording), the window server gives the app
nothing, even of its own window, and the pictures are the window drawn by the app itself (`Snapshot.layerImage`): true
for the songs, the Sources panel, the first screen and Booth's text, but without the toolbar's buttons (they
come out as blank shapes), the inspector (blank), a playing film (black), blurs (Booth's glow comes out a hard-edged
panel) and anything in another process's window (the share sheet). Those pictures are cut or not used.

`--add-music` is the window's one run, into that crate (made if missing), else the most recent, else a new crate named
after what is read; it prints each file, the progress about once a second, and the run's report, with the keys and names taken from this
Mac. `--libraries` lists the DJ libraries a run would read, `--choose-library` adds one, `--look-again` is the menu's
Look again; `--show` prints each song's key, where it came from, and where its name came from. `--snapshot` steps
through the window and writes PNGs (`Snapshot.swift`).

Tools on crate files anywhere, for the developer (`DeskApp.swift`):

    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --check-engine
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --build <music folder> <out.deckie> [jobs]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --add-source <crate.deckie> <CD, drive or folder> [jobs]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --sign <crate.deckie> <music folder>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --find-copies <crate.deckie> <music folder>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --apply <crate.deckie> <names.tsv>

`--build` and `--add-source` run the builder alone, with a `.deckiebuild` work folder beside the crate file. `--sign`
makes one plain (`o`) signature per track into the crate file's `signatures/` folder; `--find-copies` sets `cut_key`.
Both look for each song below the music folder given, by its `file.rel`; they no longer remember where a source was
read (that is Desk's own crates' job now).

## Copies of the same recording

The one run reads every song's audio from the music folder, makes a print of it (`RecordingPrint`,
core/Sources/DeckieCore/DSP: Haitsma and Kalker's published fingerprint) and gives files that are the same recording
the same `cut_key`, so the booth shows them as one song and says every place it lives (D24). Same recording means the
sound lasts as long within 1 s and every 3 s block of it matches (fewer than 35 % of the print's bits differ); a remix,
an edit, an extended mix or a live version does not match. The print stays on this Mac; the crate file carries only
the key. The inspector lists a song's other copies under "Also in your crate as". It is part of the one run, and the
prints are kept in `Files/prints/`, so a song is printed once.

## Add music from a CD or a drive (sources)

Desk reads, it does not manage (D25). A **source** is our word, in documents and code, for the thing a DJ holds that
the songs were read from: a burned data CD, a USB stick, an SD card, or a folder the DJ chose (D31). On screen it is never "source", "disc" or "CD"
of ours: it is shown by its own name ("Stick 3", "FRIDAY"), D26.

**Add music** lists the CDs and drives mounted on
this Mac by their own names (removable, ejectable or external volumes, never the Mac's own disk), then "Choose a
folder…" for anything else. The one chosen is analysed in place like any other files (nothing is copied) and each song
is labelled with its place: the source's name (the volume's name, or the folder's name when it is not the top of a
volume), the folder below its top ("House", "House/Peak", or none at its top) and its number in that folder, in the
order a player shows. The order is one rule in the core, `SourceReading.comesBefore`
(`core/Sources/DeckieCrate/SourcePlaces.swift`): the order ISO 9660 records a folder's names (ECMA-119 section 9.3:
name, then extension, character by character on the codes, the shorter padded with spaces), which is the order the
CDJ plays a data CD in (letter K); a stick gets the same rule. So capitals come before small letters and "10" before
"2", as on the disc. Every audio file is counted, so a file that cannot be analysed still holds its number. Nothing
on a source is left out by folder name (the `_` rule is for Mac folders), hidden files excepted.

The source is added to the crate showing: everything not from that source stays as it is, and that source's songs are
replaced by what is on it now (read it again after changing the stick). A folder is a source too (D31): whatever way
the music is added, the top folder chosen is a source named after it and the folders inside it are its groups, so
several folders can sit in one crate. Only a crate file made before D31 (the rekordbox route then, or a crate made
before sources) has songs with no source; their place is their folder, they still open and show as before, and the
Sources panel offers "Remove the music folder…" only for such a crate.

A song on the Mac and on a stick is two files: when the files differ (another format, other tags) they are two
entries and the one run links them as copies, so the iPad says "also on Stick 3 / House / 04". When the bytes are identical
(the same file burned onto two CDs, or copied unchanged from the Mac onto a stick) they are one entry, since an entry's
id is the file's hash, and since D27 that entry carries every place: its own (`disc`, `folder`, `track`) and the others
in `ident.other_places`, the first addition to crate v1 (`docs/architecture/crate-format.md`). Reading a source or the
Mac folder adds the places it finds and is not logged as a duplicate; reading it again replaces that source's places
with what is on it now. The own place is the one whose file gave the record: a source already in the crate file keeps
it; otherwise the place read that leads (the first source by name, then folder and number; the Mac's folder last). If
a source no longer holds an entry's own place, its leading other place becomes its own, and the file's path is unknown
until that source is read again; Desk fills it from the path it remembered there (above). Only a second copy with the same
bytes in the same folder on the Mac, which has no numbers to tell them apart, is still in the import log, as "The same
file as another".

The **Sources** panel (toolbar, or View > Show Sources, Shift-Command-D) says under its title "A source is a CD, a
drive or a folder you added. Each keeps its own name." (D31), and shows what was read: each source by name, its
folders in the order the player walks them, each song by its number there; a song on two sources (or twice on one) has
a row in each folder it is in, with that place's number and a "+1" that names its other places on hover. It is for corrections: rename a source or a
folder, move a song up or down or drag it within its folder (that folder is then numbered 1, 2, 3 again; other
folders keep the player's numbers); each works on the place selected, so a song's other places move and rename too. Making, filling or deleting a source by hand is not in the window any more; the
shared operations stay in the core (`core/Sources/DeckieCrate/Discs.swift`, D20) for later desks. The table's Where
column and the inspector show every place of a song, the one that leads first ("Friday / Set 1 · Stick 3 / House 1 ·
Burned"; a folder on the Mac by its path, or "the top of the music folder"). Corrections are saved as they are made
and undo with Command-Z. In the crate file the fields keep their names: `disc`, `folder`, `track`.

Not here: organising or planning sources in Desk, records
(nothing to read), icons for the kind of source (the format has no field for it).

## Listening (Booth, research booth-in-desk, step 1)

The Booth switch in the toolbar (a crate with songs) shows the listening mode (`Booth.swift`): an input chooser, a
level, a state line and the song heard, the same bare mode as the pages' (`desk-web/booth.js`) on the same core
(DeckieCapture's `Microphone`, DeckieDesk's `DeskBooth`). The view listens while it shows and stops when it goes:
Back to songs, another crate, a run (listening waits; it starts again when the run ends) or the window closing.
macOS asks for the microphone once, with `NSMicrophoneUsageDescription` (DeskWords' `booth.micPermission`). The song
shown is the listener's current named song, not yet the iPad's switching rule.

## Naming a song (research AA, route A: nothing leaves the Mac)

The logic is the core's (`DeskNaming`, `DiscSongs.swift`, `DeskNamesStep` in `core/Sources/DeckieDesk`; CD-Text and the
drives in `core/Sources/DeckieDisc`), shared with the Windows and Linux window; this window only draws it.

- **The list.** "n need a name" in the status bar (and "Show them" or "Name them" on the finished screen) shows the
  songs with no title, no artist, or a name that is Desk's guess (from a file name, a folder, a list beside the
  music or the disc) the DJ has not checked; the Notes column says which ("No title", "No artist", "Desk's guess").
  The count on the finished screen is this list's.
- **One song** (the inspector's Names): title, artist and version, each with a small line saying where it came from
  ("from the file name", "from the disc", "you typed this", ...); a guess is lighter and slanted and says "Desk's
  guess"; Return on a guess as it is keeps it; typing "Artist - Title (Version)" into the title offers to split it.
  Release shows the file's album tag or the disc's own name. "Looks right" keeps the guesses of the songs selected
  (also in the table's context menu).
- **Look up via MusicBrainz** (D36, `Lookup.swift`; the logic is DeckieDesk's `DeskLookup`): a button in the names
  panel for one song, and "Look up songs via MusicBrainz…" in Name songs (the selection, or the songs that need a
  name) and beside "n need a name". A sheet says first, in plain words, what will be sent and to whom (every time for
  a batch or a disc; for one song the first time, then under the button), then counts while it goes (one request a
  second; Stop keeps what was found), then shows each song's candidates side by side with their lengths and a tick
  per field. What is used is marked "from MusicBrainz, when you looked it up" and is one undo step. "What Desk has
  sent" lists every request. Marked by its own colour and the globe, never Desk's accent. The only code that uses the
  network is `core/Sources/DeckieLookup` (Foundation's URL loading, on the Mac).
- **Name songs** (toolbar): Paste a list…, Names from the file names… (a pattern), Names from a playlist… (an .m3u
  made from these songs; each length is checked, 3 s either way). Each shows a preview with a tick per field before
  anything changes: only empty fields and Desk's guesses are ticked at first, the DJ's own names are shown and never
  changed, a version is never taken away, and a list whose count differs from the songs' is refused until fixed.
  "Use n names" is one undo step; the status bar then says "Names added to n songs. Undo".
- **Listen** (D33): the play button at the start of each row (inside the Title cell, before the title: a column of
  its own passed the table builder's limit), the inspector's Listen, the table's context menu, or the space bar on a
  selected song. The row's button shows play, and pause for the song playing; pressed again it plays on from where it
  paused. It selects its row and never starts an edit (titles are edited in the inspector); a screen reader reads it
  as "Listen to <title>" or "Pause <title>". AVPlayer plays from a third of the way in, from where the song is: its
  file on the drive or folder, or on a music CD the system's own file on the disc (nothing is copied); the bar under
  the table has play and pause, back and forward 30 seconds, a scrub bar, the position and the length. It stops when
  another song is chosen, a run starts, or the crate changes. A song whose source is not plugged in, or whose disc is
  not in the drive, says which to put back ("Put Friday night back in to listen").
- **A music CD.** Add music lists a music CD in the drive ("Music CD, 14 songs, 71:12 · music CD in Audio CD") beside
  drives and folders; a music CD's volume (the system's `cddafs`) is no longer offered as a drive. Desk reads the
  disc's music to work it out and keeps none of it: the system already shows the songs as `1 Audio Track.aiff` files,
  and the run reads each where it is, one at a time (the crate names it `Track 01.aiff`). What Desk keeps is what it
  learned, in `Files/discs/<disc id>.json` (the id is a hash of the table of contents, so the same disc put in again
  is known and only what is new on it is read, in any crate), and the disc's id with its source in `crate.json`. The
  table and CD-Text are asked of the disc's raw device (DKIOCCDREADTOC, formats 2 and 5); if this Mac does not let
  Desk open it, the table is made from the files' lengths and the names are unknown. Names from CD-Text are kept as
  "from the disc" (a guess to glance at); the source takes the disc's own title, or "Music CD, n songs, m:ss" and the
  run screen asks once, in passing, for the name written on the disc (the crate follows when it was made from the
  disc). Each song's place is the source and its number. A run stopped part way (the disc taken out) asks for the
  disc again and carries on with what is left. Disc space for the music: none on the Mac. On Windows and Linux,
  where the sound is read by sector, one song at a time is written to `Reading/` while it is analysed, fingerprinted
  and printed, and removed as soon as it is done, whether it worked or not; so the most at any moment is one song as
  CD audio, 10.1 MB a minute (about 50 MB for a five-minute song; at most the disc's longest song, about 800 MB for
  a disc burned as one 80-minute track). Listen there reads the song off the disc when asked and hands it to the
  page in memory, writing nothing. A `Discs/` folder left by the first build of this (which copied each disc, about
  750 MB) is removed when Desk starts; what it learned moves to `Files/discs/`. `DECKIE_DESK_MUSIC_CD=<folder>` lists stand-in drives made from generated bytes instead of the real ones.
- **Trying it with no one at the keyboard:** `"Deckie Desk" --naming-walk <out folder> <music folder>` (with
  `DECKIE_DESK_MUSIC_CD` and `DECKIE_DESK_PLAYLIST`) walks the flow and writes a picture at each step.

None of the music CD code has read a real disc on this Mac: there is no drive here.

## What is here

- `Desk/Sources/DeskApp.swift`: the app, its menus, the bundle wiring, the developer's headless tools.
- `DeskModel.swift`: the crates, the one run, edits saved as they go with undo, send, export and import, the
  mounted CDs and drives, the share sheet.
- `ContentView.swift`: the window: the crate menu, the first screen, the run, the finished screen, the crate, the
  bottom line, the dialogs.
- `QuickStart.swift`: the quick start's card on the first screen, its player and its steps in words (D46).
- `TrackTable.swift`, `ImportLogView.swift`: the table with an inspector for names and what the analysis found;
  What didn't go in.
- `SourcesPanel.swift`: the Sources panel (corrections, Remove from crate) and the Add music menu.
- `RunScreen.swift`: the run screen (D37), the same as the Windows and Linux window's from the same data: the song
  on stage with its wave and what Desk found, the figures so far, the wall of waves, the quiet line and the moments.
  Its colours, sizes and times are `RunLook`'s named constants.
- `Words.swift`: every word on screen, by name.
- `Naming.swift`: the Listen bar, the naming tools' sheet with its preview, and the naming walk.
- `HeadlessDesk.swift`: Desk's own crates from a terminal.
- `Snapshot.swift`: `--snapshot` steps through the window and writes PNGs; the window's own picture when the window
  server gives none; `DECKIE_SNAP_ON_SIGNAL`.
- `QuickStartWalk.swift`, `FilmWalk.swift`: the quick start's walk and the site film's stills.
- `Signatures.swift`: AVFoundation into ShazamKit's signature generator, and into the print that finds copies.
- In the core, `DeckieDesk`: `DeskHome` (where), `CrateShelf` (the crates, import, export), `FileStore` (per-file
  results), `NameCorrections`, `PlacePaths` and `SourceNaming`, `removeSource`, and `DeskRun` (the one run, its
  progress and its report). Tested in `core/Tests/DeckieDeskTests`.

Not yet: rekordbox export, picks and pairs on the desk, set planning, a Stop button (quitting is the stop; the builder
has no way to be stopped part way yet).
