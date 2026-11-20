# Research: Booth inside Desk on a computer

Dated Nov 20, 2026. Investigation only: no product code was changed and no probe was run. It answers the roadmap's
Later-1 ("Booth inside Desk on a computer", `docs/product/roadmap.md:312`), now asked for by a tester on a Windows PC.
Facts cite `file:line` at `main` 6353261. Statements about Windows, macOS and Linux audio that are not in this repo
are from general knowledge of those systems and are marked *[untested]*: none was tried on a machine.

Words used here. **Booth**: the part of Deckie that listens and shows the playing song and the picks (on the iPad
its screen name is just "Deckie"). **Desk**: the part that reads a DJ's music and writes the crate file.
**Engine**: Desk's program with no window on Windows and Linux (`deckie-desk-engine`). **Shell**: the small window
program that shows Desk's web pages (`desk-shell/`). **Reading**: one answer from the recogniser, about once a second
(which song, where in it, the deck's speed). **Switching rule**: how readings become the one song on screen.
**Loopback**: recording what the computer itself is playing, instead of a microphone.

## Summary

- **Most of Booth's hearing is already shared; most of its judgement is not.** The recogniser, the listener, the
  scoring of pairs, the shortlist's size and Shuffle order, and crate reading are in `core/` and already build on
  Windows and Linux. The switching rule, the booth's picture of a song, the picks list, the join words, the lanes'
  values, the set log and every word live only in the iPad app (about 2,200 lines of logic, plus about 1,500 of
  screens).
- **The real work is moving that judgement into the core**, not drawing a screen. Until it moves, any second Booth
  is a re-typing of it that will drift. Once it moves, a Windows Booth is the engine plus pages, as Desk already is.
- **A computer can hear better than the iPad.** A cable from the mixer, or the computer's own output (loopback),
  is clean sound; the research letters measure clean sound at 100 percent named against 83 to 95 in a room.
  Loopback on Windows needs no permission, but may not work when DJ software holds the sound card for itself
  *[untested]*; that is the first thing to find out on the tester's laptop.
- **Cost on a modest laptop is small** by the letters' figures: about a sixth of one processor core at 2,500 songs
  while nothing is named, half that while a song is followed; memory is the open point (section 4).
- **Recommended:** web pages in Desk's window for Windows and Linux (route c), built on a core move, starting with a
  listening trial with no window; the iPad app run on Apple silicon Macs (route b) as the Mac's stopgap.

## The routes at a glance

| Route | Where it runs | Reused | Rebuilt | Size | Main risk |
|---|---|---|---|---|---|
| a. Mac Desk gains Booth from shared SwiftUI views | Mac only | The iPad screens, words and look, as they are | Sound input for macOS, window layout, the few iPad-only calls | Medium | Two layouts in one set of views; nothing for Windows |
| b. The iPad app on an Apple silicon Mac | Apple silicon Macs only | Everything | Nothing (perhaps an input chooser) | Small to try | Untried; input choice and window size are the system's; no Intel, no Windows |
| c. Booth as pages in Desk's window, the engine listening | Windows, Linux, Mac | Core (after the move), the shell, the protocol, `desk.css` | Sound capture in the engine, the pages, the words as a table | Large, in testable steps | Two Booths drifting unless the core move is done first |
| d1. A listening trial with no window | Windows, Linux, Mac | Core, `deckie-listen` | Sound capture only | Small | A terminal is not a product; it is a test |
| d2. The page captures the microphone itself | Windows, Linux, Mac | The web view's own capture | A sound path from page to engine | Medium | No loopback; the browser's sound processing; logic creeping into pages |

## 1. What Booth is made of

### Already in the shared core

| Piece | Where | Notes |
|---|---|---|
| The recogniser (fingerprint match, speed and key-lock reading) | `core/Sources/DeckieRecognition/Recogniser.swift:72` | "plain Swift with Foundation and Dispatch; nothing in it is specific to a platform" (`docs/research/w4-recognition-complete.md:335`) |
| The listener (one reading a second, follows a named song) | `core/Sources/DeckieRecognition/SongListener.swift:88`; threaded form `BoothRecogniser`, `:227` | Takes sound at any rate and channel count (`:128`, `:245`) |
| The index made from a crate file's fingerprints, kept as a file | `core/Sources/DeckieCrate/Crate+Recognition.swift:56`; `core/Sources/DeckieRecognition/IndexFile.swift:87` | Built once per crate file |
| Scoring a pair of songs, the suggested move | `core/Sources/DeckieCore/PairScoring.swift:314` | |
| Scoring one song against the whole crate | `PairPool`, `core/Sources/DeckieCore/Recommendations.swift:145`, `:167` | What D18 decided (`docs/product/00-decisions.md:225`) |
| The shortlist's size and the Shuffle dial's order | `Shortlist`, `core/Sources/DeckieCore/Recommendations.swift:184`, `:194` | The dial's arithmetic is shared; its state is not |
| Reading a crate file; a crate song as a scoring song | `core/Sources/DeckieCrate/CrateReader.swift`; `CrateTrack+Scoring.swift:9` | |
| A recording played through the listener, printed second by second | `core/Sources/deckie-listen/main.swift:5` | From a file only; no live input |

### Only in the iPad app

| Piece | Where | Tied to the iPad by |
|---|---|---|
| The switching rule: waits, the careful wait, dominance, place jumps, pause, the pitch shown, confidence | `deck-app/Deck/Sources/Recognizer.swift:551`-`584` (the numbers), `:614`-`780` (`take`), `:802` (pitch), `:184` (pause), `:218` (confidence) | Wall-clock `Date`, the `Library.shared` singleton, SwiftUI's `@Observable`, and Apple's recogniser sharing the same function (`:466`, `:488`) |
| A reading as Booth takes it, from either recogniser | `Listening.swift:26` | Nothing; plain Swift |
| The microphone | `MicCapture`, `Recognizer.swift:917` | `AVAudioSession` (iPad only) and `AVAudioEngine` |
| Booth's picture of a song, copies of one song, places | `Model.swift:42`, `:243`, `:345`-`395` | `Codable` structs, one `SwiftUI.Color` helper (`:436`) |
| A crate file as Booth sees it: songs, waves, lane values, one song's picks | `CrateLibrary.swift:30`, `:138`, `:163` | Nothing; Foundation and the core |
| The join words (pitch text, key verdict) | `Mixing.swift:12`, `:47` | Nothing. This is the third copy: the old web player has the first (`web-player/index.html:1066`, `:1077`) |
| The picks list: candidates, one row per song, tags, pinned song, Shuffle applied | `Suggester`, `Mixing.swift:106`, `:115`, `:133`, `:155` | `Library.shared` |
| The picks' state: Simple or Full, the dial, pin, search, the text-only setting | `SuggestState`, `DeckApp.swift:208`, `:211`, `:244` | `UserDefaults`, `@Observable` |
| The screens: playing panel, whole-song wave, picks, lanes, Crate tab, first screen | `ListenView.swift:45`, `:305`; `SuggestionsView.swift:8`, `:167`, `:259`, `:423`; `OtherViews.swift:8`; `FirstRun.swift` | SwiftUI, a little UIKit (`DeckApp.swift:37`, `:201`; `SuggestionsView.swift:76`; `OtherViews.swift:242`) |
| Set recording: sound to an AAC file, a log, a tracklist | `SetRecorder.swift:9`, `:10`-`28` | `AVAudioFile` for the sound; the log is plain |
| Words | `Words.swift:8` (462 lines) | A Swift list with functions for words built from parts |
| Look | `Look.swift:13`, `:39` (504 lines) | SwiftUI and UIKit types |

### How much could move, and what it costs

Nearly everything that is not a screen can move: the switching rule (Deckie's path), the reading type, Booth's
picture of a song and its copies and places, the crate as Booth sees it, the join words, the picks list and its
state, the set log (not the sound file), and the words. Call it one new core module, here named `DeckieBooth` for
discussion. What stays in the iPad app: the screens, the look, the microphone, the sound file of a set, and Apple's
recogniser, which would hand its readings to the shared rule through the same reading type it uses today
(`Listening.swift:26`).

Cost: medium. About 1,500 of the 2,200 lines move, and the work is untangling more than writing:

- The rule reads the clock itself (`Date()`), so it cannot be replayed exactly; in the core it should be handed the
  time with each reading.
- It reaches a singleton for the crate (`Library.shared`, 21 uses with `Words` in `Recognizer.swift` alone).
- Deckie's and Apple's paths share one function (`take`, `Recognizer.swift:614`).
- The words are Swift functions (`Words.syncBarsLeft(3)`); to reach web pages they must become a table with named
  blanks, as Desk's already are (`core/Sources/DeckieDesk/DeskWords.swift:22`, sent in the engine's first message,
  `docs/architecture/desk-protocol.md:55`). Every iPad view that names a word is touched, mechanically.

Risks for the iPad app:

- **The rule was tuned on measured sets** (the comments at `Recognizer.swift:551`-`584` and `:709`-`712` record the
  cases). A move that changes one wait changes what a DJ sees. Guard: before moving, make `deckie-listen` print
  what the screen would show, not only the readings (the app already has such a line for Debug builds,
  `Recognizer.swift:586`-`600`), record it on the generated test sets, and require the same output after.
- **Timing.** Booth has never run on a real iPad in its current form (roadmap Now-4, Risk-1,
  `docs/product/roadmap.md:94`, `:405`). Moving its insides before that walk mixes two sources of change. And the
  session on branch `recog/faster` is changing the listener now. The move should follow both.
- **Tests that read the views** (`core/Tests/DeckieCrateTests/BoothVariablesTests.swift`) will need their paths
  and rules updated with the words.

The gain is not only this project. One shared rule also serves a fast-listener change (Next-4), "coming in"
(Next-5), and any later host of Booth.

## 2. Sound input on each computer

### What the recogniser needs

- **Any sample rate, any channel count**; it mixes to one channel itself (`SongListener.swift:128`;
  `deck-app/Deck/Sources/Listening.swift:112`-`125`). No resampling is needed in the capture code.
- **Latency does not matter.** A reading comes once a second from the last 8 seconds of sound
  (`SongListener.swift:54`, `:56`). A capture delay of a tenth of a second is invisible.
- **No sound processing.** The iPad asks for "measurement" mode so the system does not ride the gain on loud music
  (`Recognizer.swift:929`). On a computer the same applies: no automatic gain, noise suppression or echo cancelling.
- **A steady sample clock.** The deck's speed is read from the sound, so dropped buffers would bend it. Capture
  should count samples, not wall time, as the iPad does (`Recognizer.swift:925`, `:941`).
- **A level** for a meter, a few times a second (`Recognizer.swift:942`-`947`); the pause rule also uses it
  (`Recognizer.swift:180`).

### What a computer can offer that the iPad cannot

| Source | What it hears | Quality | Who can use it |
|---|---|---|---|
| The laptop's own microphone | The room | Worst: small microphone, often with the system's voice processing | Anyone |
| A cable from the mixer (its USB output, or its record output into an audio interface) | The mix, clean | Best for a DJ on decks or CDJs | A DJ whose mixer or interface is plugged into the laptop |
| The computer's own output (loopback) | Exactly what the DJ software sends out | Clean, and no cable | A DJ playing from the same laptop |

Why it matters: against clean sound the recogniser named 100 percent at every listen length; in a room 90 to 98;
with a crowd 10 dB under the music 83 to 95; with a crowd as loud as the music 56 to 76
(`docs/research/w4-recognition-complete.md:101`). A cable or loopback puts Booth in the first column every night.
One caution: loopback or a master output hears the mix going to the room, not the headphones, which is what is wanted.

### macOS *[untested]*

- **Permission:** the system asks once per app for the microphone; the app must carry a usage sentence (the iPad
  app's is in `deck-app/project.yml`, `NSMicrophoneUsageDescription`). A program with no window started by the shell
  is asked for under the shell's name, so the shell's app bundle must carry the sentence.
- **Capture:** AVFoundation (`AVAudioEngine`, as the iPad uses) or Core Audio. `AVAudioSession`, which the iPad code
  calls (`Recognizer.swift:927`-`930`), does not exist for a native Mac program; that part is rewritten.
- **Choosing an input:** Core Audio lists every input (built-in, a mixer's USB output, an interface) and one can be
  set on the capture unit. Doable; not what the iPad code does (it takes the system's current input).
- **The computer's own output:** from macOS 14.2 a program can tap the system's or one program's output, behind its
  own permission question ("system audio recording"); before that it needs a virtual sound device the DJ installs.

### Windows *[untested]*

- **Capture:** WASAPI, the system's sound interface, in shared mode, so Booth never takes a device away from the DJ
  software. It lists every input and output and delivers sound in the device's own format (commonly 48,000 a second).
- **Permission:** no question is asked of a classic desktop program. One system switch ("let desktop apps access
  your microphone") can silence all microphones; Booth should notice silence and say where the switch is.
- **Loopback:** WASAPI can record any output device's mix with no permission and no extra driver. Two cautions:
  1. It records the system's shared mix. DJ software that takes the sound card for itself (an **ASIO** driver, or
     WASAPI "exclusive" mode: both common with DJ controllers) bypasses that mix, and loopback then hears nothing.
     Whether the tester's setup does this is unknown and decides whether loopback is the headline or a footnote.
  2. When nothing is playing, loopback delivers no sound at all rather than silence; the capture code must fill
     the gap so the listener's clock and the pause rule stay right.
- **A mixer or controller with a USB recording output** appears as an ordinary input and is the safe route when
  loopback is not available.

### Linux *[untested]*

- PipeWire is the sound system on current desktops and also answers programs written for PulseAudio; ALSA is under
  both. Every output has a "monitor" source, which is loopback with no permission. Inside a sandboxed package
  (Flatpak) the microphone goes through a permission portal; Desk is not packaged that way today.

### What each part would need

- **The engine** gains the capture. Two ways:
  1. One small C target per system, in the manner of the Windows decoder already in the core
     (`core/Sources/CMediaFoundation`): WASAPI on Windows, Core Audio on the Mac, PulseAudio or ALSA on Linux.
     No new dependency; three pieces of code to keep.
  2. One vendored single-file C library that does capture, device lists and loopback on all three, by the author of
     the two decoders already vendored (`DEPENDENCIES.md:209`, `:304`), under the same public-domain or MIT-0
     choice. One piece of code; one new dependency to record and review. It does not cover the macOS output tap.
  Either way the engine feeds `BoothRecogniser.feed` (`SongListener.swift:245`), runs the shared rule, and sends
  what to show.
- **The page** needs a list of inputs to choose from, a level meter, and a plain line when nothing is heard. It
  never touches sound.
- **The shell** needs nothing for sound on Windows and Linux. On the Mac its bundle carries the usage sentence. It
  should also keep the computer awake while Booth listens (the iPad does: `DeckApp.swift:37`).

## 3. Routes for the screen

### a. The Mac's Desk gains a Booth mode from the iPad's SwiftUI views

- **Reused:** the screens, `Words.swift`, `Look.swift`, and all the logic, as source shared between two app targets
  (the Mac Desk is SwiftUI on macOS 14, `desk-app/project.yml:5`; the iPad app on iPadOS 17, `deck-app/project.yml`).
- **Rebuilt:** the microphone for macOS and an input chooser; the handful of iPad-only calls (`DeckApp.swift:37`,
  `:201`; `SuggestionsView.swift:76`; `OtherViews.swift:242`; `Look.swift:2`); a layout that works in a resizable
  window; set files in a Mac folder.
- **Kept the same by:** being the same source. Words and look cannot drift.
- **The DJ gets:** Booth inside the Mac's Desk, opening the crate Desk just made, with any input.
- **Size:** medium (sound input, the layout pass, target plumbing).
- **Risks:** every later change to an iPad view must be checked in a Mac window; it does nothing for Windows, the
  tester's system.

### b. The iPad app on a Mac as it is, or a Mac Catalyst build

- **As it is, on Apple silicon** (roadmap Next-6, `docs/product/roadmap.md:191`, "untried"): Apple lets an iPad app
  run on these Macs unless the developer opts out; it arrives through TestFlight or the App Store *[untested]*.
  - *Likely works:* the screens, opening a crate file through the Mac's file chooser (`DeckApp.swift:68`), the
    recogniser, set recording into the app's own folder.
  - *Open:* the microphone question appears, but the input is whichever the Mac's sound settings name; the app
    has no chooser. The app asks for a full screen (`deck-app/project.yml`, `UIRequiresFullScreen`), so how its
    window sizes beside DJ software must be looked at. Loopback is not available to it.
  - *Leaves out:* Intel Macs, Windows, Linux.
- **Mac Catalyst** (the iPad app built as a Mac app): reaches Intel Macs and gives a proper Mac window and menus, at
  the price of a second build to sign, ship and test. Medium. Still nothing for Windows.
- **Kept the same by:** being the same app.
- **Size:** small to try (an afternoon on an Apple silicon Mac); small more for an input chooser.
- **Risks:** it is a separate app beside Desk, not "inside Desk"; unknowns above until someone runs it.

### c. Booth as pages in `desk-web`, the engine listening

This is the route D32 already chose for Desk on Windows and Linux: pages with no Deckie logic, a Swift shell, and an
engine spoken to in written messages (`docs/product/00-decisions.md:486`-`499`). The same shell builds on the Mac
(`desk-shell/README.md:10`).

- **Reused:** the shell; the message transport; the rule that pages hold no words and no design values
  (`desk-web/README.md:19`-`31`); `desk.css`'s values, which are already "the look of the site and the booth"
  (`desk-web/desk.css:1`); the wave-drawing know-how in `run.js`; the old web player's lane drawing as a reference
  only (`web-player/index.html:1106`; the SwiftUI lanes were ported from it, `deck-app/README.md`, "JoinView").
- **Rebuilt:** sound capture in the engine (section 2); Booth's pages (playing panel, picks, later waves and lanes);
  the words as a table.
- **Needs first:** the core move of section 1. Without it the engine would need a second copy of the rule.
- **Messages, by addition only** (adding fields, events and request types does not raise the protocol number,
  `docs/architecture/desk-protocol.md:437`-`440`). A sketch, not a design:

  | Kind | Name | Carries |
  |---|---|---|
  | First message | `hello` gains `booth` | Whether this engine can listen; Booth's words join `words` |
  | Request | `booth.open` | A crate (by id, as Desk shows it) or a crate file's path |
  | Event | `booth.index` | Preparing (songs so far) or ready |
  | Request | `booth.inputs` | Reply: the inputs and outputs that can be listened to, each with a name and a kind (microphone, line, this computer's output) |
  | Request | `booth.listen`, `booth.stop` | The chosen input |
  | Event | `booth.level` | The input's level, a few times a second |
  | Event | `booth.playing` | The song (or none), its place as an anchor time and a rate so the page moves the playhead itself (as `Recognizer.swift:172` does), the pitch shown, how sure, "not heard just now", paused, the song coming in |
  | Event | `booth.picks` | For which song; the shortlist's size; each pick with its score, move, pitch and key words, tags, and later lane values |
  | Request | `booth.setSong`, `booth.pin`, `booth.shuffle`, `booth.more` | Set by hand; pin; the dial; search and the rest of the list |
  | Later | `booth.record` and a `booth.set` event | Only if set recording is wanted (section 5) |

- **Kept the same by:** one rule and one picks list in the core, so behaviour cannot differ; one word table in the
  core read by both Booths; the look through the design source-of-truth work (section 6). What can still differ is
  layout, which is a product choice (section 5).
- **The DJ gets:** Booth on Windows and Linux in Desk's own window, with a choice of input including the
  computer's own output.
- **Size:** large in total, in steps that each stand alone: capture (medium), the core move (medium), the first
  pages in words only (medium), waves and lanes (medium), set recording (medium, optional).
- **Risks:** the web view drawing smoothly beside DJ software on a modest laptop (not measured); one engine doing a
  library run and Booth at once (simplest rule: not both; say so on screen); a Mac DJ would have a native Desk and a
  web Booth unless route a or b covers the Mac.

### d. Others worth naming

- **d1. A listening trial with no window.** `deckie-listen` plays a file through the listener
  (`core/Sources/deckie-listen/main.swift:5`). Given live capture and a crate file, it could print the named song,
  its place, the speed and the first few picks. Small. It is a test, not a product, but it answers on the tester's
  own laptop the questions everything else rests on: does capture work, does loopback hear their DJ software, what
  does it cost beside that software.
- **d2. The page captures the microphone.** The web views can do it, with their own permission step. It was
  set aside here because it cannot do loopback, the browser's voice processing must be switched off and may not
  fully be, raw sound would have to be pushed from page to engine as text, and it bends D32's "no logic in pages".
- **d3. Reading what the DJ software says is playing**, instead of listening. A different product with
  different promises (it depends on each maker's files); not investigated.
- **The old web player** draws picks from a data file in a browser with the logic in the page
  (`web-player/index.html:1066`-`1106`). It is a drawing reference, not a base: D32 puts logic in the engine.

## 4. Performance on a modest Windows laptop

All figures are from the letters, measured on one 2.3 GHz server processor core
(`docs/research/w2-own-recognition-trial.md:37`) with the current listener. The session on `recog/faster` will change them.

| Songs in the crate | One whole-crate search of 8 s of sound (median / 95th) | Index file (opened in place) | Songs' points for the check |
|---|---|---|---|
| 1,000 | 73 / 115 ms | 48 MB | 40 MB |
| 2,500 | 152 / 283 ms | 108 MB | 100 MB |
| 5,000 | 344 / 614 ms | 205 MB | 198 MB |
| 10,000 | 824 / 1,440 ms | 403 MB | 396 MB |

(`docs/research/w4-recognition-complete.md:298`-`303`.)

- **Cost per second.** The listener searches the whole crate once a second while nothing is named, and every other
  second while it follows a song (`SongListener.swift:75`, `:185`); following costs about 10 ms
  (`w4-recognition-complete.md:313`). So at 2,500 songs: about 15 percent of one core while searching, about 9
  while following. At 5,000: about 35 and 18. An older four-core laptop (the estimates' slowest row is an Intel
  i5-8250U with 8 GB, `docs/research/p-machine-estimates.md:95`) has cores of roughly that speed when cool, slower
  when hot *[inference]*. It runs on one thread, so three cores stay free for DJ software.
- **Memory.** While listening the program itself holds about 2 KB a song (9 MB at 5,000,
  `w4-recognition-complete.md:319`). The index is opened in place (`IndexFile.swift:87`), which on Apple systems
  means the system can drop and reload its pages. **Whether Swift's Foundation truly opens a file in place on
  Windows is not established**; if it reads it whole, the index sits in memory in full (about 210 MB at 2,500
  songs, 400 MB at 5,000). Worth one small probe. Separately, the scoring pool for picks was about half a gigabyte
  on the iPad for a 2,327-song crate when D18 was written (`docs/product/00-decisions.md:231`-`232`); that figure is
  old and included Apple's catalogue, and should be measured again. The web view itself costs a few hundred MB
  *[general knowledge]*. On an 8 GB laptop already running DJ software, memory is the figure to watch, not the
  processor.
- **Building the index:** about 5 s per thousand songs on one core, plus a search for copies that grows faster
  (`w4-recognition-complete.md:207`-`209`, `:320`). On a computer, Desk could build it at the end of a run so Booth
  opens at once.
- **Picks for one song:** timed in the iPad's log (`DeckApp.swift:251`) but no letter gives the figure. Not measured.
- **Beside DJ software.** DJ software must never miss a sound buffer. Booth should run its listening below normal
  priority, on one thread, never ask for a device exclusively, and draw nothing while its window is hidden (the
  run screen already does this, `desk-web/README.md:13`). Loopback and shared capture add no load to the DJ
  software itself *[untested]*.

## 5. Questions for the owner

1. **A mode inside Desk, or its own window?**
   - *A mode* (a switch in Desk's window): one program, the crate is already open, "Booth inside Desk" as the idea
     was put. But Desk's window is laid out for a table of songs, and a DJ could start a library run and listen at
     once.
   - *Its own window* (same program, opened from Desk or from its own shortcut): can sit beside DJ software at
     booth size, can open a crate file with no Desk session. Slightly more shell work.
   - *Leaning:* its own window, opened from Desk, with the crate Desk is showing already loaded.
2. **The iPad's screens, or a layout for a laptop beside the decks?**
   - *The same screens:* one description of the interface, less design work, testers compare like with like.
   - *A laptop layout:* a laptop shares its screen with DJ software, so Booth may get a narrow strip, viewed from
     further away, used with a trackpad or not touched at all. The iPad's text-only setting (`DeckApp.swift:211`,
     `ListenView.swift:499`) is close to what a strip needs.
   - *Leaning:* same content and words, a narrow layout first (the song, its place, the picks in words), the full
     iPad layout when the window is made large.
3. **Does set recording belong there?**
   - *For:* parity; a cable or loopback makes a clean recording.
   - *Against:* DJ software already records the set on that laptop; AAC encoding is the system's on the iPad
     (`SetRecorder.swift:59`) and would need another way on Windows and Linux; it is a second job running beside
     the DJ software.
   - *Middle:* keep the tracklist and log (what played, when, at what pitch), no sound. Cheap, and it is the part
     DJ software does not give.
4. **What does this do to the iPad app, and to what is sold?**
   - If Booth is free inside Desk on every computer, the iPad app becomes one of two screens for the same thing:
     the one for DJs on decks with no laptop, or who want a touch screen by the mixer.
   - If the iPad app is the paid product, Booth on the computer either needs its own price or is the free taste.
   - A laptop Booth with loopback names songs more reliably than any microphone. That is an advantage of the
     computer version the iPad cannot match, and a DJ who plays from a laptop has little reason to add an iPad.
   - Nothing in the repo decides price; this needs the owner's answer before public words are written.
5. **What is the smallest version worth giving the Windows tester?**
   - *Smallest of all:* the trial with no window (d1): open a crate file, pick an input, read the named song and
     picks as lines of text. Is a terminal acceptable for this tester?
   - *Smallest with a window:* open a crate, pick an input with a level meter, see the named song with its place
     and the picks in words. No waves, no lanes, no dial, no recording.
6. **May one small sound-capture library be added** (section 2), or should capture be written per system with no
   new dependency?
7. **On the Mac:** is the iPad app on Apple silicon (route b) enough for now, given the Mac already has a native
   Desk?

## 6. Recommended order of work

Each step ends in something a tester can try. Nothing here starts before the owner chooses.

| Step | What is built | What a tester tries | Needs from the owner |
|---|---|---|---|
| 0 | Nothing: route b tried on an Apple silicon Mac | The iPad build in a Mac window, with a mixer's USB output selected in the Mac's sound settings | An hour on the owner's Mac; answers to questions 1 to 7 |
| 1 | Live capture in the core and the listening trial with no window (d1), on Windows first | Their crate file and their own setup: laptop microphone, a cable from the mixer, loopback. Reports what was named and what the laptop's processor and memory did | Answer 6; the tester's DJ software, controller and how sound leaves the laptop |
| 2 | The core move (section 1): the rule, picks and words shared; the iPad app switched onto them with the replay check | An iPad build that behaves exactly as before; the trial of step 1 now prints what the iPad would show | That the real-iPad walk (Now-4) and `recog/faster` have landed first |
| 3 | The first Booth window in `desk-web` (route c): open the crate, choose an input, the named song and its place, picks in words | Booth beside their DJ software for a real session | Answers 1, 2 and 5 |
| 4 | The dial, pin, search and set by hand; then the whole-song wave and the lanes | The full picks experience | The laptop layout agreed (answer 2) |
| 5 | The set's tracklist and log; sound only if wanted | A tracklist after a night | Answer 3 |
| 6 | The Mac: stay with route b, or route a, or the web Booth | | Answer 7, after hearing from Mac testers |

Why this order: step 1 is small and settles the two unknowns that could change the plan (whether loopback hears
the tester's DJ software; memory on Windows). Step 2 is the one piece every route needs and the iPad app benefits
from. Steps 3 to 5 are then engine messages and pages, the kind of work Desk for Windows has already been through.

**How it sits with the design source of truth** (`docs/product/roadmap.md:261`-`283`). Booth's pages would be a
sixth place that holds the look. Three things keep that from making drift worse:

- **Words:** step 2 puts Booth's words in one core table read by both Booths, which is also what the copy audit
  (Design-4) needs.
- **Values:** step 3, in words only, needs almost no new design values and can read `desk.css`'s. Step 4's waves
  and lanes need many (the iPad's are in `Look.swift`, by screen). The single source of design values (Design-2)
  should exist before step 4, or step 4 becomes the fourth hand-copied set.
- **Behaviour:** the one description of the interface (Design-3) is where "both Booths show the same thing" is
  written down. Booth's entry in it should be written as part of step 3, from the iPad app as it stands.

## Noted in passing: Desk inside the iPad app (not investigated)

- The engine-and-messages shape works in both directions: a core module per product and a written protocol mean
  either product can be hosted by either kind of window.
- The iPad's web view could in principle show Desk's pages with the engine's code running inside the app; whether
  the analysis and its model runtime fit on an iPad is a separate question (letter A, roadmap Later-2).

## What was not done

- No code was run, on any system. Every statement about Windows, macOS and Linux sound is to be confirmed in step 1.
- No timing was taken; section 4 repeats the letters' figures.
- Recogniser speed and the design source of truth were left to their own sessions.
