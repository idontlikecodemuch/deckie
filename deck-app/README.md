# Deckie for iPad (the app once called Deckie Booth)

A native iPad app (SwiftUI, iPadOS 17+, iPad only) that sits beside the DJ's decks. It listens through the
microphone, names which song of the DJ's crate is playing from the fingerprints in a crate file (`.deckie`, made by
Deckie Desk), fully offline, and shows what could come next and how to mix it in.

## The tester build (Nov 19, 2026)

Since `pc/booth-testflight` no song data of a DJ's ships inside the app (the demo crate file, below, is the one crate
file it carries): with no crate file open, Booth shows its first-run screen (what it does, the three steps to a crate file, "Open a crate file", deckie.io, Credits); with one open it
behaves as before. The party's bundled data, its catalogue and the Mix map tab are gone from the app. Version 0.1.0,
build 1. A Release build has no test doors: the deck:// hooks, `-deckURL`, `-traceShown`, `-indexSmall` and the "…"
test and details sheet are Debug only, and the deck:// URL scheme is added to a Debug build's Info.plist by a build
script (project.yml). The paperwork for TestFlight is in `docs/product/testflight/`.

## The demo (Nov 19, 2026, `pc/booth-demo`)

Booth carries one crate file of its own: the demo, `Deck/Demo/Demo.deckie` (a crate package of about 200 KB (156 KB before build 2): the facts
and fingerprints of seven public-domain songs, no audio), named in project.yml and copied whole into the app. With
it bundled, the first-run screen shows "Try the demo crate" and a line saying the songs play from deckie.io/demo on another
device. Tapping it opens the demo exactly as any crate file opens (copied into Application Support/Crates and
remembered); the open note says "The demo crate is open: 7 songs. Play deckie.io/demo nearby." (any crate file's
open note sits under the tabs for 5 s and lets every tap through to what is under it). While it waits for a song
the Listen page says where the songs play from and has "Leave the demo crate"; the Crate tab has "Leave the demo crate" beside
"Open crate file". Leaving closes the crate file (`Library.close`), forgets it for the next launch, and shows the
first-run screen. `DemoCrate.isOpen` knows the demo by its crate id (the bundled manifest's `crate_id`).

The songs, their licences and SHA-256s: `site/demo/CREDITS.md`; the Credits sheet lists them (`Credits.demoSongs`).
deckie.io/demo (`site/demo/`) plays the same songs as 128 kbps MP3s. To rebuild the crate file, see CREDITS.md
("How the files were made").

**Its name and its id (Nov 19, 2026, `pc/booth-build-1`).** The Crate tab shows the crate file's own name, so the
manifest's `name` is "Demo crate" (it was "Demo"). It was changed in `manifest.json` by hand, in place: the manifest is
plain JSON with no checksum over it, and the bytes are exactly what the core's writer writes (DeckTests re-encode the
crate and compare). The crate id is unchanged, `1a365511-96d6-4840-a9f3-e9b7a772179c`, and DeckTests hold it. To keep it
on a rebuild, build into the existing package (`deckie-build <folder> --out deck-app/Deck/Demo/Demo.deckie`): the
builder keeps an existing crate's id, name and created date (`Builder.swift`, `existing?.manifest.crateId`); a build
to a new path makes a new id.

## Build 2 (Nov 19, 2026, `pc/booth-build-2`)

- **The name.** On the home screen and wherever the app names itself it is "Deckie" (`CFBundleDisplayName`, the
  microphone line, the first-run screen, Credits, the Files folder the sets are in). The bundle id stays
  `io.deckie.booth`, and the code keeps its names (the Xcode target and scheme `Deck`, "booth" in comments and
  types). "Booth" was never the name of a mode on screen (the tabs are Listen and Crate), so no "Booth" is left in
  the app's words. Version 0.1.0, build 2.
- **Stop.** The microphone button in the playing panel's corner is now one labelled control (`ListenControl`):
  **Stop** while listening, which turns the microphone off and ends and saves the set's recording if one is running
  (`Recognizer.stopListening`); **Start listening** (orange) while not. The song on screen stays, dimmed, with its
  picks; the corner says "stopped", and the panel's foot says where the set was saved. With no song on screen the
  panel says "Stopped", that Deckie is not listening and how to start again. Listening does not start again on its own
  when the iPad comes back from the lock screen. The REC chip's menu only pauses the recording ("Pause recording,
  keep listening") or turns set recording off; its note says that Stop ends the set and saves it.
- **The demo crate's songs**, chosen again so most of them suit each other (`site/demo/CREDITS.md`); the crate id is
  kept. They sit at the top of the folder the crate was built from, so no folder line shows above a song, and the
  Crate tab shows no "/" heading for a crate whose songs are all at the top.

## Build 3 (Nov 21, 2026, `pc/listener-a`)

- **The listener is A (D41).** The core's default listener now also searches the newest 4 s every second and lets
  another song take over only when it clearly beats the one playing; after a hard cut the right song is on screen
  about 2 s sooner. Nothing in the app chose it: `BoothRecogniser(index:)` takes the core's default.
- **Reading times in the log.** When listening stops, the log (the details sheet's Log in a Debug build, and the
  console as `DECK ...`) gets one line: `listener: a, 142 readings, typical 61 ms, slowest 240 ms`. Nothing new on
  the normal screen. Version 0.1.0, build 3.

## Build 4: the icon (Nov 24, 2026, `pc/ipad-icon`)

The icon picture, `Deck/Assets.xcassets/AppIcon.appiconset/icon1024.png`, is drawn from `site/icon.svg` by
`tools/draw_icon.py` (Python's standard library only): 1024 by 1024, 8-bit RGB with no alpha channel, marked sRGB, the
dark ground (#160f2b) filling the whole square, every edge mixed by how much of each shape covers the pixel. iPadOS and
the App Store round the corners themselves, so none are drawn in; the SVG's corner rounding is the one thing left out.
Build 3's picture had rounded corners drawn in on white (all four corner pixels 255,255,255) and was an enlarged small
picture (ring edges 3 to 5 pixels soft, about 17,000 colours); the new one has edges one pixel wide and 426 colours.
Its rings are the SVG's: eleven thin grooves with a band of plain orange round the label, where build 3's picture had
eight wider ones. The Windows icon (`core/Tools/windows/make_ico.py`) and the Desk film's close
(`desk-quickstart/film.js`) are made from this picture and round the corners themselves. To redraw it after a change
to `site/icon.svg`:

```
python3 deck-app/tools/draw_icon.py
```

Version 0.1.0, build 4; nothing else differs from build 3.

## The sound input (Nov 21, 2026, `pc/ipad-recording-interruptions`)

Not yet tried on a real iPad; everything below is tested in the simulator with made-up buffers and events
(`DeckTests/AudioInputTests.swift`).

- **Which channels.** A mono input (the iPad's microphone) and a stereo input are heard and recorded as they are. An
  input of more channels (a 4- or 8-channel interface) is heard and recorded from its first pair, inputs 1 and 2,
  where DJ mixers and interfaces put the master; the other inputs are not mixed in (they are usually a deck, a cue or
  a microphone). If they carry sound, the log and the set's log say so once ("inputs 3–4 of 4 carry sound; Deckie
  hears and records inputs 1–2 only"). `ChannelMap`, `CaptureSink` (AudioInput.swift). Before, an input of more than
  two channels left the recording empty: every buffer was skipped.
- **Every buffer counted.** The recorder counts buffers written, skipped and failed (`RecordingTally`); a problem is
  said while it lasts (REC says "cannot record", the panel's foot says the set is not being recorded), and is noted in
  the set's log. When the recording ends, `log.json` gets a `summary` (seconds recorded, the counts, the gaps,
  `nothingRecorded`) and the tracklist a last line; Stop's words say how long was saved, or that nothing was recorded.
- **REC tells the truth.** "REC 0:12:34" recording, "REC paused", "REC waiting" (a gap in the sound), "cannot record",
  "not recording" (set recording is on but listening is stopped; it said "REC on" before), "REC off". `RecChip`.
- **Interruptions and changes of input.** A call, Siri or an alarm, an interface plugged in or out, the engine's
  configuration change and iPadOS's audio restarting are watched (`ListenGuard`). Listening stops cleanly and starts
  again by itself with a new engine and the input as it is then (when the interruption ends with "may resume";
  otherwise every 5 s and when the app comes to the front). The corner says "interrupted", "starting again" or
  "cannot listen", with a plain line under the song; the song stays, dimmed. A new input format starts the recognisers
  afresh; the set's recording carries on in the same file (mixed and converted to its channels and sample rate), and
  each gap is noted in its log with its length. Coming back to the front no longer starts listening afresh (which
  ended the set's recording and began a new file each time).
- **The session** is play-and-record (it was record, which silences other audio on the iPad, such as a DJ app),
  measurement mode, mixing with others (starting to listen never stops or ducks that music), Bluetooth A2DP for output
  only; no Bluetooth hands-free input. The ring switch does not silence recording.

## Folder layout

```
Deck app/
  project.yml                 xcodegen spec (the developer team, bundle io.deckie.booth, automatic signing)
  Deck.xcodeproj              generated by `xcodegen generate` (do not edit by hand)
  Deck/
    Sources/
      DeckApp.swift           app, the first-run screen or the tabs, suggestion state, deck:// test hooks (Debug only)
      FirstRun.swift          the first-run screen (no crate file open), BoothScreen, DemoCrate
      Credits.swift           the Credits model (Credits.booth: empty today; Credits.demoSongs: the demo's songs)
      CreditsView.swift       the Credits sheet (first-run screen's foot, the Crate tab's info button)
      Model.swift             the crate's data as the booth reads it
      Mixing.swift            joinInfo / keyVerdict port + the suggestion sampler
      Recognizer.swift        microphone + file-test matching, position / pitch / confidence logic
      ListenView.swift        Listen page: playing panel, whole-song wave, chips
      DebugSheet.swift        test-with-file sheet, mic level meter (Debug only)
      SuggestionsView.swift   Up next: Simple / Full and the Shuffle dial, the ranked picks, More, JoinView (Canvas port of drawJoin)
      OtherViews.swift        the Crate tab (sources and folders, Open crate file, Credits)
      CrateLibrary.swift      a crate file as the booth sees it (tracks, places, waves, signatures, picks)
      Words.swift             every word the booth shows, by screen (D28, D36)
      Look.swift              every design value: Theme (the web player's colours) and Look, by screen (D36)
    Demo/Demo.deckie          the demo crate file (bundled; facts and fingerprints of seven CC0 songs, no audio)
    PrivacyInfo.xcprivacy     the privacy manifest (no tracking, no data collected; the required-reason APIs)
    Resources/                NOT bundled, git-ignored: the party's data that tools/prep_data.py still writes
                              (deck_data.json, overview.json, Deck.shazamcatalog, mixmap.html). Private; never
                              committed. The app names each file it carries in project.yml; nothing here is one.
    Assets.xcassets           app icon (from the web player's touch icon)
  DeckTests/                  the booth's own tests (first-run state, opening crate files in both forms and extensions)
  tools/
    prep_data.py              ONE script: snippets + JSON + mix map + catalog
    mixwaves_all.py           copy of mixer/mixwaves.py covering all catalogue tracks
    overview_waves.py         480-bin whole-song waveform per catalogue track
    catalogtool/main.swift    macOS command-line tool: signatures, catalog, matching bench, live mic test
    build/                    caches: sigs/ (signatures), mixwaves_all.json, manifest.json
```

## Words and design values (D36)

- **Words**: every word the booth shows, speaks or puts in a chip is in `Deck/Sources/Words.swift`, organised by
  screen, each with a note of where it shows. Words built from parts are functions with named blanks
  (`Words.syncBarsLeft(3)`); separators are words too.
- **Design values**: every colour, font, size, space, corner, opacity, line and time is in `Deck/Sources/Look.swift`:
  `Theme` (the web player's colours) and `Look`, grouped by screen (`Look.Listen`, `Look.Picks`, `Look.Crate`,
  `Look.Join`, `Look.FX` and the rest). Left in the views: the system's named roles (`.secondary`), SF Symbol
  names, 0, and the drawings' own arithmetic.
- **To change one**: a word in Words.swift, a design value in Look.swift. Nothing else changes.
- **The rule**: views hold neither. The core's `BoothVariablesTests` read the views and fail when one creeps back
  in. Recognizer.swift's few words (the test sheet's pitch details) are still there, and SetRecorder writes files,
  not the screen.

## Rebuild the data and the catalog (after tracks change)

Re-run the mixer pipeline first if tracks were added (`mixer/README.md`: candidates, analyze, score; the lab's data
is private and lives in the folder `DECKIE_LAB_DATA` names, decision D45). Then, from `deck-app/tools`:

```
PY="../../mixer/.venv/bin/python"
$PY -I prep_data.py                          # snippets, deck_data.json, mixmap.html, Deck.shazamcatalog
$PY -I prep_data.py --no-catalog             # data only
$PY -I prep_data.py --variants o,r-4,r+4     # choose the pitch variants in the catalog (this is the default)
```

It compiles `catalogtool` if needed, makes any missing signatures in 8 parallel processes (about 1 s per
signature; a full rebuild of 347 tracks x 3 variants takes about 1 minute), and assembles the catalog.
Variant audio is rendered in memory (AVAudioUnitVarispeed for vinyl, AVAudioUnitTimePitch for tempo only)
and streamed straight into SHSignatureGenerator, so no variant audio is ever written to disk.
Signatures are cached in `tools/build/sigs/<id>_<variant>.shazamsignature`; delete a track's files
there to force it to be redone. The MP3s are only read.

Variant names: `o` original, `r+4` resampled (vinyl: tempo and key move together), `t-4` tempo only (key kept).
Each SHMediaItem carries `deck_id`, `deck_flavour` (o/r/t) and `deck_pct`.

Matching tests on the Mac:

```
./catalogtool/catalogtool bench --catalog ../Deck/Resources/Deck.shazamcatalog --manifest build/manifest.json \
    --n 25 --dur 8 --render o,r+4,r-4,t+4,t-4,r+8,t+8
./catalogtool/catalogtool match --catalog ../Deck/Resources/Deck.shazamcatalog --file some.mp3 --start 60 --dur 8 --render t+4
./catalogtool/catalogtool listen --catalog ../Deck/Resources/Deck.shazamcatalog --secs 40   # Mac mic, needs mic permission
```

## Build

```
cd "Deck app"
xcodegen generate
# simulator
xcodebuild -project Deck.xcodeproj -scheme Deck -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' -derivedDataPath build/dd build
```

The booth's own tests (the app as their host):

```
nice -n 19 xcodebuild test -project Deck.xcodeproj -scheme Deck -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' -derivedDataPath build/dd
```

The app carries no DJ's song data, only the demo crate file, about 200 KB (until Nov 19, 2026 it carried the party's, about 59 MB).

## Install on the iPad (a paid developer account)

**Installed Oct 31, 2026** (main at b77eb13: crate files from the Documents folder, picks scored when a song is recognised,
the whole-song wave and join lanes from the crate file's per-bar loudness). Earlier installs: Oct 24, evening (moves menu,
16 % pitch range, sync marker). To install again, with the iPad connected and unlocked, from `deck-app/` run:

```
xcodebuild -project Deck.xcodeproj -scheme Deck -configuration Release -destination 'id=<iPad UDID>' -derivedDataPath build/dd-dev -allowProvisioningUpdates -allowProvisioningDeviceRegistration build && xcrun devicectl device install app --device <iPad UDID> build/dd-dev/Build/Products/Release-iphoneos/Deck.app && xcrun devicectl device process launch --device <iPad UDID> io.deckie.booth
```

`<iPad UDID>` is the iPad's identifier, as `xcrun devicectl list devices` shows it.


The project already names the developer team (`DEVELOPMENT_TEAM` in project.yml) and uses automatic signing, so nothing needs editing.

1. Plug the iPad into the Mac with a cable, unlock it, tap "Trust This Computer".
   On the iPad, turn on Settings > Privacy & Security > Developer Mode (restart when asked) if it is not on yet.
2. Either open `Deck.xcodeproj` in Xcode, pick the iPad as the run destination and press Run,
   or from Terminal (one line, replace the name with the iPad's name from `xcrun devicectl list devices`):

```
cd deck-app && xcodebuild -project Deck.xcodeproj -scheme Deck -configuration Release -destination 'platform=iOS,name=<iPad name>' -derivedDataPath build/dd-dev -allowProvisioningUpdates build && xcrun devicectl device install app --device '<iPad name>' build/dd-dev/Build/Products/Release-iphoneos/Deck.app
```

3. First launch: allow the microphone. The screen stays on while the app is open (idle timer off).

With the paid account the development profile lasts a year: the profile on the iPad expires Oct 24, 2027 (read from the
built app's embedded.mobileprovision), so the app keeps working until then without a re-install.
(With a free Apple ID the profile would expire after 7 days and the app would stop opening until re-installed.)

## Using it

* **Listen** (designed for landscape; portrait stacks the two halves).
  Left panel: song title, artist, where it is (the source's own name, the folder and the number, as on the player), BPM (at the detected deck
  pitch), the whole-song waveform with IN and SYNC (the analysed mix-out window, toned down), the song time (elapsed and remaining) and a small note "sync area in 0:37" / "sync area · 16 bars left".
  Tiny in the corners: listening status (sure / likely / unsure, deck pitch), the mic on/off and "…" (test with
  file, details).
* **Picks** (right): "Easy" = best matches, "Harder" = unexpected ones; Simple (default) shows 2 + 1, Full 3 + 2 (all five fit on one landscape screen);
  the rest of the matches follow as the same cards when you scroll. New picks come with every new song. Each row: title, where it is, BPM, the join waveform (end of this song over the start of that one,
  aligned at the join) and one grey line: "pitch +4.0%" = where to set the incoming deck's pitch fader,
  key relation, transition type (and why it is a harder pick). Tap to pin as NEXT (tap again to unpin),
  long-press for the reasons. "Simple / Full" sits top left of the picks; the "Minimal" switch in the app's top-left corner (remembered) switches the waveforms off: same screen and same picks, the playing panel keeps its whole-song wave and each pick becomes a compact pill without the join wave (title, artist, folder, BPM · pitch, move); the CD1 / CD2 / All chips (top right, each on/off; CD1+CD2 on by default, All = the
  other catalogue cuts) choose where picks come from. Colours: muted lavender = CD1, dark blue = CD2 (folder paths, waves,
  Crate tab), grey wave = no beat-match. 🎃 = Halloween, RMX = remix / edit. Tap a join wave to cycle the next song's
  start point (mix-in start, track start, steady beat, then every 8 bars); "start 0:32" under the wave shows it,
  and a pinned pick keeps it. Join snippets are 8 samples per beat (tools/mixwaves_all.py --spb 8; refresh only
  them with `prep_data.py --snippets-only`).
* **Song changes** (Apple's; Deckie's switches sooner, see Deckie's own recogniser below): a blend (both songs heard) switches only after the new song has out-matched the current one for
  about 10 s ("also hearing: …" shows the other song meanwhile); a hard cut (the old song stops matching, the new
  one matches 3 times within 6 s) switches in about 4–5 s; another copy of the same recording never counts as a change, while a remix, an edit or a live version of a song is a song of its own (D24).
* **Pauses**: when the song stops matching and the room is quiet the song stays on screen, its position freezes and
  the status shows "paused"; it resumes from the new offset when matches come back. ShazamKit keeps repeating the
  last match during silence; those repeats are ignored. Only after 2 minutes with no match at all does the panel
  go back to "listening…". Cue jumps inside a song are accepted after 2 agreeing matches once the old position has
  been silent for 5 s (repeated choruses otherwise make ShazamKit alternate); a restart near the top is instant. The recording log follows the panel, so a transition is logged once.
  Halloween songs get a two-second lightning / ghost / pumpkin moment once (only a soft fade with Reduce Motion).
* **Set recording**: every listening session is recorded from the same microphone tap that feeds recognition
  (one engine) to `Documents/Sets/Deckie set <date time>.aac` ("Deck set" before Nov 21, 2026) (AAC, 128 kbps, ADTS so the file stays playable
  even if the app quits), with `<name> log.json` (timestamp, seconds into the recording, track id, title,
  artist, place (source / folder / number, or "in <folder>"), detected pitch, confidence; rewritten after every change) and
  `<name> tracklist.txt` (one line per song, appended as it goes). The tiny REC chip on the status line says what
  recording is doing ("REC 0:12:34", "REC paused", "REC waiting", "cannot record", "not recording" while listening is stopped, "REC off"); a tap opens
  its menu, in every build: Pause / Resume recording, and "Record each set" (on by default, remembered between
  launches as `recordSets`; off closes the recording in progress, on starts one at once if the microphone is
  listening). The Debug details sheet's switch is the same setting. Get the files with the Files app (On My iPad >
  Deck > Sets) or Finder (iPad > Files > Deck). The app declares background audio, so capture should continue
  if the screen locks (the screen is kept on while the app is open anyway); not yet verified on the iPad.
* **Crate** (the tab's name is provisional and is one constant, `CrateTabView.title`): first each source (the CD, stick
  or card the songs were read from) by its own name, by folder, numbered as the player numbers them; then a section
  "Folders" with the songs that have no source, by their folder, unnumbered. A dense list ("Details" switches to the
  larger rows); the sections side by side in landscape, one at a time in portrait. Tap a song to set it as playing by
  hand (fallback if the room is too loud or the iPad cannot hear). The bundled data's sources are named "CD1
  Singalongs" and "CD2 Mix-ins": those are the discs' own names, data, not our word.
* **Mix map**: removed Nov 19, 2026 (it only ever showed the party's bundled map).
* Debug builds only: the "…" button opens the test and details sheet: "Test with file" (pick an audio file, a start time and a
  pitch rendering; "keep going" simulates playing), match counts, latency and the log.

## Deckie's own recogniser (Nov 14, 2026, D35)

* **Which one listens.** A crate file with Deckie's fingerprints (`print`, `prints/<id>.dkl`: every builder writes them
  now) is recognised with Deckie's own recogniser (`core/Sources/DeckieRecognition`); one with only Apple's signatures
  (made before D35) with Apple's, as before; one with neither says so, as before. With both kinds the DJ chooses in
  the details sheet ("…" > Recognise with: Deckie, Apple, or both); Deckie's is the default. Nothing leaves the iPad
  with either.
* **One reading.** Both recognisers turn what they hear into a `Reading` (Listening.swift: the song, its place, the
  deck's speed if it reads it, key lock, a confidence, or nothing yet); `Recognizer.take` is the one place a reading
  becomes the playing song, the pitch shown and the set's log, so the rest of the app does not know which ran.
* **The index.** Made once per crate file from its fingerprints, off the main thread (the playing panel says "Getting
  ready to listen" with the number of songs), kept beside the app's copy of the crate file in Application
  Support/Crates as `<crate>.recognition.dkx` with the core's stamp, and opened in place (mapped) every time after.
  Copies of one recording count as one: the crate file's `cut_key`s go to the index, which finds the rest itself.
  Setting `booth` (the default); `-indexSmall YES` at launch makes it with `boothSmall` instead, for measuring.
* **The microphone.** The same tap as before (measurement mode: the least processed input) feeds
  `BoothRecogniser.feed` (mono, at whatever rate arrives) and returns at once; readings come back once a second on the
  recogniser's own thread, each inside a release pool, and hop to the main actor. The listener follows a named song
  cheaply and searches the whole crate every other second; the app never restarts or re-searches on its own.
* **Both, to compare.** The two hear the same sound; Deckie's names the song on screen; the set's log
  (`<set> log.json`) gains `hearing` and `compare` (each song with when each recogniser first named it and the speed
  each read, and every moment they named different songs), and the details sheet shows a one-line summary.
* **Hooks.** `deck://hearing?with=deckie|apple|both`; `deck://stream?path=...&start=0` plays a file through whichever is
  chosen as the microphone would (`deck://test`, Apple's rendered segments, streams instead when Deckie's is in use).
  `-traceShown YES` at launch writes one `SHOWN` line to the console after each of Deckie's readings (the sound's
  time, what the reading said, what the screen shows, the pitch shown), for measuring.
* **Song changes with Deckie's (note on D35, Nov 14).** The listener already gathers evidence across seconds, so the
  hold written for Apple's (above, under Using it) is not applied to its readings. Each reading carries a wait
  (`Reading.wait`, `Recognizer.deckieWait`): a name that is sure (confidence 3 or more, the listener's own `sure`) and
  agrees with the search before on place and speed replaces the song on screen at once; a sure name on one search,
  on the next reading that names it too (about a second); a fair name (2.6 to 3) after three more readings. A song
  that was on screen until less than 30 s ago, or any song while the one on screen was set by hand and not heard
  since, needs three readings in a row; so does a song whose confirming check is no stronger than the playing song's
  own check a moment before (dominance, kept from the old hold). A reading of the playing song, or one that names
  nothing, breaks a run. Apple's readings keep the old hold. When no reading has named the playing song for 4 s, it
  stays on screen with its picks, its names dimmed and the corner saying "not heard just now" ("paused" in a quiet
  room, as before). The pitch shown is the median of the song's last nine readings, started afresh on a song change
  and when two readings in a row move more than half a percent from it (the fader moved); one such reading alone is
  set aside. `Reading.incoming` carries a song heard coming in under the
  playing one, for the listener's next version; the booth keeps it as `Recognizer.incoming` and does not show it yet.

## How recognition works (Apple's)

* Catalog: one reference signature per track for the original plus vinyl -4 % and +4 % (1041 signatures, 47 MB).
* Live: AVAudioEngine microphone tap -> `SHSession.matchStreamingBuffer`, results consumed from `session.results`.
* Position: the match offset (converted to original-track seconds for variant matches) is anchored to the
  clock and advanced at the detected playback rate. A same-song match far from the predicted position
  (repeated chorus) is ignored unless the next match confirms the jump.
* Pitch: vinyl-style (master tempo off) changes move the key, and ShazamKit reports the frequency skew
  directly; deck pitch = variant ratio x (1 + skew). Tempo-only (master tempo on) changes keep the key, so
  they are measured from how fast the matched position advances (least squares over at least 20 s of
  matches), rounded to 0.5 %.
* Confidence: share of the last six matches that agree on the song x how well consecutive offsets line up x
  number of matches, decaying after 20 s without a match.

## Test hooks (simulator)

Debug builds only: `xcrun simctl launch <device> io.deckie.booth -deckURL '<url> ; <url>'` runs these at launch
(the deck:// scheme also works from Safari, with a confirmation prompt):
`deck://test?path=/abs/file.mp3&start=60&render=r%2B4&loop=1`, `deck://mic`, `deck://stop`, `deck://set?id=<track id>`,
`deck://mode?m=simple|full`, `deck://all?on=1`,
`deck://lib?cd1=1&cd2=0&all=0` (the whole filter, the first and second source by position; test hooks keep their old names),
`deck://lib?disc=<name>&on=0|1` (one source on or off, by its label or name), `deck://shuffle` (re-roll), `deck://shuffle?amt=0.3` (set the Shuffle
dial, 0 to 1, then re-roll), `deck://pin?i=0`, `deck://tab?i=0|1`,
`deck://scroll?to=more|crate-rest|more-end` (scroll the picks to More, to where the shortlist ends, or to the end),
`deck://search?q=love` (search More; an empty q clears),
`deck://orient?o=landscape|portrait`,
`deck://crate?path=/abs/x.deckie` (or `deck://open?path=`: open a crate file in either form, `.deckie` or the earlier
`.deckiecrate`, as "Open in" does),
`deck://choose` (the Open crate file chooser), `deck://minimal?on=0|1`,
`deck://after?s=<seconds>&u=<url-encoded hook>` (run a hook later),
`deck://hearing?with=deckie|apple|both` (the recogniser), `deck://stream?path=/abs/set.wav&start=0` (a file played
through it in real time, as the microphone would hear it; waits for Deckie's index if it is still being made).

## Limitations

* The simulator has no microphone unless it is attached to a live simulator window. The live mic path was
  tested only through file rendering and the same SHSession code; test it once on the iPad before the party
  (play a CD track near it).
* Tempo-only pitch needs about 20 s of steady matches before it shows; until then it shows "±0%".
* Very loud rooms reduce matching; the level meter helps place the iPad. Setting the song by hand on the Crate tab always works.
* `UIRequiresFullScreen` is on (no Split View), so the app owns the screen and can rotate freely.

## TestFlight (remote updates)

`project.yml` sets `ITSAppUsesNonExemptEncryption = false` (no export-compliance prompt), version 0.1.0, build 4 (raise
`CFBundleVersion` for every later upload; builds 1 and 2 were never uploaded; build 3 was uploaded to TestFlight on Nov
24, 2026, the first upload; build 4 is the next upload and differs from it only by the icon). The fields to fill in App
Store Connect are in `docs/product/testflight/app-store-connect-fields.md`.

**Build 3, archived Nov 24, 2026** (`pc/testflight-3`, main at d6c3091), signed with what was already on the Mac (the
development certificate and the team's wildcard development profile) and without `-allowProvisioningUpdates`, so
nothing in the developer account was made or changed. The app is 3.9 MB (2.2 MB zipped), arm64 only, iPad only
(device family 2), minimum iPadOS 17.0, all four orientations, full screen; it holds no library data and carries
`Demo.deckie` (unchanged from the checkout), `PrivacyInfo.xcprivacy`, the microphone line, a launch screen, the
1024-point icon (no alpha channel) in the asset catalogue, and no `deck` URL scheme. DeckTests passed first (41 tests).

**Build 4, archived Nov 24, 2026** (`pc/ipad-icon`, at 96ee9da), the same way and with the same commands: nothing in
the developer account was made or changed. Version 0.1.0, build 4; the app is 3.4 MB, arm64 only, with `Demo.deckie`,
`PrivacyInfo.xcprivacy` and no `deck` URL scheme. Its icons: `AppIcon60x60@2x.png` (120 pixels) and
`AppIcon76x76@2x~ipad.png` (152 pixels) loose in the app, and the 1024-pixel rendition in `Assets.car` (opaque, sRGB,
by `xcrun assetutil --info`); the two loose ones, converted back to ordinary PNGs, are square, fully opaque and the
dark ground (22,15,43) in all four corners. DeckTests passed first (41 tests in 3 suites).

```
cd deck-app && xcodegen generate
nice -n 19 xcodebuild -project Deck.xcodeproj -scheme Deck -configuration Release -destination 'generic/platform=iOS' -archivePath build/Deck.xcarchive -derivedDataPath build/dd-archive -jobs 2 archive
```

`build/exportOptions.plist` (git-ignored, made on the Mac; the team id is read from the project, not written here):

```
TEAM=$(xcodebuild -project Deck.xcodeproj -target Deck -configuration Release -showBuildSettings | awk '$1=="DEVELOPMENT_TEAM"{print $3}')
/usr/libexec/PlistBuddy -c "Add :method string app-store-connect" -c "Add :destination string upload" \
  -c "Add :signingStyle string automatic" -c "Add :teamID string $TEAM" -c "Add :uploadSymbols bool true" \
  -c "Add :manageAppVersionAndBuildNumber bool false" build/exportOptions.plist
```

Export and upload in one step (`destination` `upload` sends the build to App Store Connect as it exports). The Mac
has no Apple Distribution certificate and no App Store profile for `io.deckie.booth` yet, so this one needs
`-allowProvisioningUpdates`: Xcode makes both on this first export, through the account signed in to Xcode (Admin or
App Manager role in the team). It re-signs the app for distribution, which also drops the development build's
`get-task-allow`.

```
nice -n 19 xcodebuild -exportArchive -archivePath build/Deck.xcarchive -exportOptionsPlist build/exportOptions.plist -exportPath build/export -allowProvisioningUpdates
```

Without an account in Xcode, an App Store Connect API key does the same (add `-authenticationKeyPath
~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 -authenticationKeyID <KEYID> -authenticationKeyIssuerID <ISSUER>`
to the export command). The App Store Connect app record for `io.deckie.booth` must exist (Apps > + > New App), and
before it, the explicit App ID `io.deckie.booth` in the developer account. Both were made by hand on Nov 24, 2026.
Automatic signing did not make the App ID on the device builds, as these notes said before: they were signed with the
team's wildcard development profile, so no explicit App ID existed and the bundle id was missing from App Store
Connect's list. It was registered under Certificates, Identifiers & Profiles > Identifiers (App IDs > App, explicit
bundle id, no capabilities).

## Crate files from a PC, and songs with no name (Nov 13, 2026)

**Opening a crate file, either form.** The booth opens a crate file whether it is the Mac's package (a folder) or the
single file a PC writes (one plain zip under the same name, `docs/architecture/crate-format.md`, "The single-file
form"): from the Files app (tap it), "Open in" and the share sheet, AirDrop, iCloud Drive, or the Crate tab's "Open
crate file" (the system's chooser). Either form is taken into the app's own storage as a package
(`Library/Application Support/Crates/<crate id>.deckie`; a copy stored earlier as `<crate id>.deckiecrate` is
replaced when the same crate comes in again) by the core's `CrateImport.copy`: a package is copied, a
single file is unpacked with `CrateArchive.unpack`, and the copy is read whole before it replaces anything. The file the
DJ gave is only read (it is opened in place, through a file coordinator, so a file in iCloud Drive is downloaded first);
it is never moved or changed. A damaged file is refused in plain words with the reader's own line under them, and the
crate file open before stays open: "This crate file is not complete…" for a file cut short, "…is damaged, so it cannot
be opened…" for a changed byte, "This is not a crate file…", "…made by a newer Deckie…". A crate file placed in the
Documents folder is taken in the same way at launch. After an open the booth shows "Friday night is open: 5 songs."

**The file type, settled in the simulator.** One declared type cannot cover both forms. Declared as a package
(`com.apple.package`), `.deckiecrate` names a folder only: the system gives a plain file with that extension a dynamic
type of its own (`UTType(filenameExtension:conformingTo: .data)` returned `dyn.ah62d4rv4ge80k3pdrry0n25wqf4gn`), and the
chooser showed the PC's single files greyed out while the packages could be chosen
(scratchpad `booth-single/shots/10-picker-type-package-only.png`). So `project.yml` declares **two type identifiers
with the same extension**: `<earlier prefix>.deckie.crate` (a package) and `<earlier prefix>.deckie.crate-file`
(a plain file, `public.data`), both under one document type the booth owns. The system picks by what the item is: a
folder resolves to the first, a file to the second (both logged at launch as `type for .deckiecrate as a folder / as a
file`). With that, every crate file in the chooser could be chosen, a single file tapped in the Files app opened the
booth directly, and a package chosen in the chooser opened too. **No second extension and no change to the format were
needed.** (Deckie Desk on the Mac did not declare the type then; it does now, below.)

**The extension and the ids moved (November 2026).** The crate file's extension is now `.deckie` and the type ids
are on the product's domain: `io.deckie.crate` (the package) and `io.deckie.crate-file` (the plain file), each
declared with both `.deckie` and the earlier `.deckiecrate`, so a crate file made before still resolves to one of
them. The earlier ids (listed under `UTImportedTypeDeclarations` in `project.yml`) are declared as imported types that
conform to the new ones and claim no extension, and the document type lists all four, so a file still tagged with an
earlier id opens. Deckie Desk on the Mac declares the same two types. The launch log now reports both extensions
(`type for .deckie as a folder`, `type for .deckiecrate as a file`, and so on). Not yet seen in the simulator or on
the iPad: that a `.deckie` single file and a `.deckiecrate` single file both tap open, and that both can be chosen.

**The bundle id moved (November 2026)** from an id under an earlier prefix to `io.deckie.booth`, and the name under the
icon from "Deck" to "Deckie Booth". To the iPad it is a different app: the one installed with the earlier id stays,
with its own crate files, settings (Minimal, the Shuffle dial, the recogniser, the remembered crate file) and saved
sets, and the new one starts empty. Open the crate file once in the new app; copy anything wanted from the earlier
app's folder in the Files app (On My iPad > Deck) before deleting it, because deleting an app deletes what it keeps.

**A crate file with no fingerprints** (one made on a PC today): the booth opens it and shows its songs, places and
picks. There is nothing to listen for, so the bundled catalogue is not used either (it would name songs that are not in
the crate), the mic button is hidden, the corner says "not listening", and the playing panel says once, until a song is
set: "Set the song by hand. The booth cannot name what is playing from this crate file yet: it has no song
fingerprints. Tap a song in the Crate tab to set it as playing", with a "Choose a song" button to the Crate tab. Picks
work as for any song set by hand. Set recording runs from the listening microphone, so it does not run with such a
crate file.

**A song with no name** (research AA, 3.13). A song whose title is not usable by the crate file's own rule
(`SongName.isUsableTitle` in the core, the rule Desk's "Needs a name" uses: empty, only a number, "Track 07", "Audio
Track 3", "Untitled", "Unknown") is found and shown like any other, and its place leads:
- the playing panel: the place in the title's size, broken by phrase ("Friday night" / "2 Peak / 03"; the folder for a
  song on no source), then "No name yet", then the file it was read from as a file ("file: 03 07"), never in the
  title's place;
- picks and the Minimal pills: under the place line, "03 · no name yet" and "file: 03 07" where the artist goes;
- the Crate tab: "03 · no name yet" in the quieter colour, with the file line, under its place's heading;
- the search in More looks through the place and the file name of such a song, and "no name" finds them all;
- logs, the set's tracklist and the join view's spoken label use "Friday night / 2 Peak / 03 · no name yet".
The words are placeholders in one list, `Deck/Sources/Words.swift` (D28).

## Crate files (Oct 29, 2026)

The app can run from a crate file made by Deckie Desk instead of the bundled data: put a `.deckie` (either form; the earlier `.deckiecrate` too) in the
app's Documents folder (Files app > On My iPad > Deckie (Deckie Booth before build 2), or Finder > iPad > Files) and relaunch, or point a test launch at
one with `deck://crate?path=/abs/x.deckie`. The crate file gives the tracks and their analysis, the whole-song wave
(from the per-bar loudness), the recognition catalogue (one plain signature per track, made on the Mac) and the picks:
the pair scores are computed on the iPad with the shared scoring in `core` (DeckieCore's PairScoring, the port of
mixer/score.py), so any DJ's crate file works and stays exactly as Desk wrote it. The picks are scored for one
song at a time: when a song is recognised (or set by hand) the app scores it into every other track, keeps every
scored pair as that song's list, best first, and remembers the last 8 songs' lists, and keeps no table of all pairs. The one thing that needs the whole crate is
the timbre rank (how a pair's sound similarity compares with every other pair's), so the load builds the sorted list
of all track-to-track similarities once. From that list the screen keeps the song's shortlist: the best tenth of the
library by score, never fewer than 10, after the filters (one row per recording, nothing played in the last 12, the source
chips). The Shuffle dial next to Simple / Full orders it: at 0 percent the shortlist is in score order, at 100 percent
it is shuffled fairly, and in between each song's place blends its score with a dice roll, so the better songs tend to
stay near the top. Full shows the first 10, Simple the first 5, the rest of the shortlist sits under More; a pinned song stays first.
More then runs on past the shortlist with every other song the filters leave, in score order, after a thin line
("rest of the crate, by score"), and has a search at its top over title and artist (the picks above are not filtered).
A row's small label says what is unexpected about it (half time, tempo change, "to" another source by its name, "in"
its folder when it is on no source, deep cut for the lower half of the shortlist). The full library (Oct 30, 2026: 2,327 tracks, 141 MB with
signatures; the Release build on the iPad A16 iOS 27 simulator) loads in about 5 s, 2.8 s of it the similarity
list, and holds about 0.5 GB afterwards (it held 4.3 GB and took 2 min 7 s when every pair was scored at load); one
song's picks take 55 to 80 ms, and a streamed track is matched within a few seconds, each 4 s segment in 1 to 4 ms.
A 238-track crate file loads at once and scores a song in about 7 ms. From a crate file, the whole-song wave and the join view's two
lanes come from the per-bar loudness: each bar is measured against the song's loudest bar, as the bundled waves are,
then the quiet floor (the quietest tenth of the song's bars) is removed and the same curve applied, so a lane is the
whole-song wave zoomed in to the join, one flat step per bar cut by the beat and bar lines (the bundled data's lanes
are finer, an eighth of a beat per sample from the audio). The crate file's places (D25, D26: Deckie Desk
reads each CD, stick or card as it is and writes its own name, the folder on it and the player's number into the
format's `disc`, `folder` and `track` fields) give the Crate tab its sources, folders and numbered songs, give the
picks one filter chip per source (named after it, shortened to about 10 characters, the two colours alternating, every
source on by default) and mark songs on a source as favoured; a song with no source shows the file's own folder. On
screen a source is always its own name; "disc", "CD" and "CDs" as our word are gone. Not yet from a crate file: pitch-variant
signatures.

## The same song (Nov 13, 2026, D24)

Two crate entries are the same song only when they are the same recording: the same `cut_key` in the crate file,
which Deckie Desk's Find copies fills. Nothing is folded by title, so every version is its own row and its own song
for recognition. The rule is the shared core's (`SameSong`, `core/Sources/DeckieCrate/SameSong.swift`); the booth's
index of copies is `Library.copiesByCut`.

- **Picks**: one row per recording. The row is the copy whose place leads among the copies the filter allows: on the
  playing song's source, else on the first source in the crate's order. A song is allowed when any copy is; copies on
  a source switched off still show on the row as "also on". A song played in the last 12, by any copy, is left out. The
  shortlist's tenth counts songs, not entries.
- **Places**: the playing panel and each pick show the leading place, then "also on Stick 3 / Peak / 04" for the
  other copies on sources and "also in <folder>" for copies on no source. The Crate tab lists each copy in its own place.
- **One file in several places** (Nov 13, 2026, D27): the same file burned onto two CDs or copied unchanged onto a
  stick is one entry in the crate file with its own place and other places (`ident.other_places`). The booth treats
  them like copies: one row; the place that leads by the same rule (the playing song's source, else the first source
  in the crate's order, a place with no source last), taken among the places the filter allows; "also on" for the
  rest; allowed when any place is on a source switched on. The Crate tab lists the song under each place with that
  place's number, and choosing it there sets the same song, playing from that place (so the next picks lead with
  that source). Recognition is unchanged: one entry, one set of signatures, one song. `Library.places(of:)` gives
  every place of a song, copies and other places together; `Library.placed` the entry at the place a row shows.
- **Recognition**: a match on any copy of the playing song is the playing song (same audio, same position); a match
  on another song is taken as its leading copy, so its copies count as one challenger.
- The bundled sprint data keeps the lab's own `cut` values.
