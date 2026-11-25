# Roadmap

The single ordered list of Deckie's work: what exists, what comes next and in what order, and what is waiting on a
decision. It records work; the reasons live in `00-decisions.md` (D1 to D43) and in the research letters under
`docs/research/`. Each item points at the decision, letter or branch behind it and does not argue it again.

Last updated: Nov 21, 2026. Publisher: App Hold Media.

## How to read this

- **Horizons.** *Now* is the first test build. *Next* follows it. *Later* is agreed direction with no date.
  *Recorded ideas* are written down so they are not lost; they are not agreed.
- **Each item** says what it is, why it matters to a DJ, what it depends on, its state and a rough size.
- **States**, always in these words: **done**; **built, unseen** (built and tested by machine, never seen by a
  person on a real device); **on branch `x`** (in progress, not merged); **decided, not started**; **owner's call**
  (needs the owner's decision first); **idea only**.
- **Sizes**: **small** (a day or two), **medium** (up to about two weeks), **large** (more).
- **Ids** (Now-1, Next-1, Design-1, Later-1, Idea-1, Ask-1, Risk-1) are for pointing at an item in a message.
  They are not decision numbers (D1 to D43) or research letters (A to AG).
- **Words** follow `voice.md` and D21: the *library* is all of a DJ's music, a *crate* is a group of songs from it,
  the *crate file* is the `.deckie` that Deckie Desk writes and the iPad app (Deckie) carries.
- **Decisions** are written as plain dated statements of what was decided and why; chat messages are never quoted
  (the rule at the top of `00-decisions.md`).

A few terms used below, said once:

- **TestFlight**: Apple's service for sending test builds of an app to testers. Builds for outside testers first
  pass Apple's *beta review*.
- **App Store Connect**: Apple's website where an app's record, builds and tester list are kept.
- **Developer ID signing and notarisation**: how a Mac app downloaded from the web is signed by its publisher and
  checked by Apple, so the Mac opens it without a warning.
- **Sandboxed**: an app that runs inside Apple's walled-off area. Only sandboxed Mac apps can go through TestFlight
  or the Mac App Store. Desk for Mac is not sandboxed, so it goes out as a download.
- **SmartScreen**: the Windows warning shown before running a program from an unknown publisher. Signing the program
  is how it stops.
- **MusicBrainz** and **AcoustID**: open online services that name songs, the first from words (artist, title),
  the second from a song's sound fingerprint.
- **Camelot code** and **wheel**: the DJ's way of numbering the 24 keys around a clock (9A, 9B), so neighbours mix.
- **Fingerprint**: a compact summary of a song's sound, kept in the crate file, which Booth matches against what the
  microphone hears to name the song.
- **CI**: the automatic builds and tests that run on GitHub after every change.
- **Design values** (designers say *design tokens*): named colours, type sizes, spacing, corner radii, shadows and
  motion, kept in one place and read by every app.

---

## Done so far

What exists on `main` today, in the order it came.

| When | What | Behind it |
|---|---|---|
| Oct 17 to 25 | A party prototype: a Python lab that analyses and auto-mixes, an iPad app on Apple's recogniser, burned discs | the sprint's brief and notes (private since D45) |
| Oct 26 to 30 | The product defined: name, privacy, the crate file as Deckie's own format, research A to R | D1 to D17, letters A to R |
| Oct 28 to 29 | The shared Swift core, the same on Mac, Windows and Linux: decoders, beats (Beat This!), tempo, bars, vocals (YAMNet), crate format v1, models on release `models-1`, a no-telemetry ONNX Runtime | D14, D15, note on D3 |
| Oct 29 to Nov 1 | Desk for Mac, first cut; Booth reads a crate file; picks scored for the playing song; one ranked list with Shuffle | D18, D19 |
| Oct 30 | The first night measured from the booth's own log and recording | letter S |
| Nov 12 to 16 | deckie.io live: home page, public dictionary, a 76 second film; the tagline "Know Your Crate"; cache stamps in the site build | D22, D23, letter V |
| Nov 13 | Desk keeps several crates, saves as it goes, sends and exports crate files; reads drives, discs and folders as sources; one row per recording with "also on" | D24 to D28, D31 |
| Nov 13 to 14 | Desk for Windows and Linux: web pages in a Swift window, a separate engine, a no-install zip for Windows, `.m4a` on Windows | D29, D32, letters Y, Z |
| Nov 13 to 14 | Key: keys from DJ programs on the computer; Deckie's own three-answer reader (a key, the home note, or not sure); the learned reader prepared | D30, D33, D36, D38, letters X to X4 |
| Nov 14 | Deckie's own recogniser in the core and in Booth; tested on the recording of a real night on the owner's Mac | D35, letters W to W4 |
| Nov 14 | "Look up songs via MusicBrainz" in Desk for Mac; a fingerprint lookup engine (AcoustID) built but in no window; covers; the run screen that moves | D36, D37, letters AA, AA4, AD |
| Nov 14 | Every word and design value in one named list per app | D36 |
| Nov 18 | Names read the way a DJ means them, fixed after a first read of songs "in the wild"; AAC and Apple Lossless on a Mac | D39, letter AA3 |
| Nov 19 | `.deckie` and the `io.deckie` ids; Booth with no bundled library, a first screen, credits, privacy manifest; TestFlight paperwork drafted | D1, D40, `testflight/` |

---

## Now: the first test build

Goal: outside testers can try Booth from TestFlight, and Desk from a download, on their own music.

### Booth to TestFlight

**Now-1. A demo inside Booth, and a page that plays it.** A small crate file of freely licensed songs bundled in
Booth, and a page on deckie.io that plays those songs, so a tester or Apple's reviewer can see Booth name a song and
suggest the next one with no Desk. Booth already shows "Try the demo crate" when a demo file is present
(`deck-app/Deck/Sources/FirstRun.swift`).
- *Why:* without it, nothing past the first screen can be seen, and the review notes have a gap where the sample goes.
- *Depends on:* choosing songs whose licences allow bundling and playing them (CC0 or CC BY, credits shown); the owner
  on the site rule of D23 (disagreement 8 below).
- *State:* decided, not started. *Size:* medium.

**Now-2. A privacy page at deckie.io/privacy.** The drafted policy published at its own address.
- *Why:* TestFlight asks for one before outside testing.
- *Depends on:* the owner's approval of `testflight/privacy-policy.md`.
- *State:* drafted, not published. *Size:* small.

**Now-3. The App Store Connect record.** The app's record under `io.deckie.booth`, the review form's contact details,
the beta description, what to test and the review notes copied in.
- *Why:* nothing can be uploaded without it, and the id is permanent once the record exists (D1).
- *Depends on:* the owner (the account holder); Now-1 and Now-2 for the review notes.
- *State:* owner's call. *Size:* small.

**Now-4. Booth on the real iPad, in this form.** Install 0.1.0 (1) on the test iPad and walk the "what to test" list:
the first screen, opening a crate file from Desk for Mac and from Desk for Windows, naming a song from the room,
picks, memory, launch time, the screen locked during a set.
- *Why:* the recogniser, the first screen and the single-file crate file have never been seen on an iPad (letter W4,
  section 6; `deck-app/README.md`). A device archive succeeded (3.5 MB), nothing more.
- *Depends on:* Now-1 for a crate to open, or a crate file from Desk.
- *State:* built, unseen. *Size:* small to run; fixes unknown.

**Now-5. Upload and beta review.** Archive, upload, answer the review, add testers.
- *Depends on:* Now-1 to Now-4.
- *State:* decided, not started. *Size:* small, plus Apple's wait.

### Desk to testers as files

**Now-6. Desk for Mac signed and notarised.** A Developer ID signature and Apple's notarisation, so the download opens
on another Mac. Today Desk is signed ad hoc (it opens only on the Mac that built it) with the hardened runtime off
(`desk-app/project.yml`), which notarisation requires. Apple silicon only for now.
- *Why:* without it a DJ cannot open Desk at all (`desk.md`, section 5).
- *Depends on:* a Developer ID certificate on the App Hold Media team; the models and runtime bundled, not read from
  the developer's checkout (Now-9).
- *State:* merged to `main` (`desk-app/tools/release-mac.sh`; `desk-app/README.md`, "Releasing Desk for Mac"): it
  builds, signs with the hardened runtime, verifies and makes the disk image; one entitlement, the microphone. The
  Developer ID signature is proven, Nov 25, 2026 (Gatekeeper: unnotarised, as expected). Notarisation goes through
  Xcode's signed-in account (decided Nov 25, 2026; no app-specific password or API key): the `notarise` stage, on
  branch `pc/mac-release-xcode`, its local export proven, the upload not yet run. Xcode notarises the app only, so
  the disk image is signed, not notarised; the zip of the stapled app is the fallback. Not proven: Apple's answer,
  Gatekeeper's yes, a second Mac. The tester's page is `mac-first-test.md`. *Size:* medium.

**Now-7. An app icon and a credits screen for Desk.** Desk for Mac has no icon set; neither Desk shows the credits that
Booth now shows (`CreditsView.swift`), which D15 and the licences ask for.
- *Why:* the credits are a licence duty for the models and libraries shipped (D15, `DEPENDENCIES.md`).
- *Depends on:* `core/dependencies.json` (the source the screens read, note on D13).
- *State:* decided, not started. *Size:* small.

**Now-8. The learned key reader bundled.** Its two files (the model and its credit list) are on release `models-1`
(D38). The Windows zip requires them (`pc-package.yml`, `KEY_MODEL: required` since Nov 21, 2026: a package run
showed both in the zip and the engine saying "key reader: learned"), and the checks fetch them with `--require`, so
the tests run with the reader that ships.
- *Why:* the learned reader shows a key on more songs and is level with Apple's on the songs it shows (letter X4).
- *Still open:* the credit list's licence questions (Risk-7).
- *State:* done. *Size:* small.

**Now-9. No developer path inside a shipped Desk.** Several source files record the build machine's folder and search it
at run time (`#filePath` in `OnnxRuntime.swift`, `KeyModel.swift`, `desk-shell/.../main.swift`, `deckie-e2e`), and a
lab folder path sits in `DeckieLab`, which Desk links.
- *Why:* a shipped app should find its own files and carry no private paths.
- *State:* partly built, unseen (Nov 21): `OnnxRuntime.swift` (which `KeyModel.swift` and the two models' lookups
  use) and the window's `main.swift` use the build machine's folder only in a debug build; a release build uses a
  checkout only when `DECKIE_CHECKOUT` names one. Still open: `deckie-e2e` (a test tool, not shipped) and the lab
  folder path in `DeckieLab`. *Size:* small.

**Now-10. Windows fixes from the first export.** Export right after a read said "no songs yet"; one setting was ignored
by the page's own boxes; a heading repeated a name ("Adding Stick 1 to Stick 1"); a music CD's file is let go before
sending; and the Windows compiler toolset pinned in CI so builds keep working.
- *Why:* each is something a tester meets on the first run.
- *State:* on branch `pc/win-export`. *Size:* small.

**Now-11. The privacy line for Desk's lookup.** Desk for Mac already has "Look up songs via MusicBrainz". D36 says the
public privacy line is reworded before the lookup reaches anyone outside; the tester notes must say what a lookup
sends.
- *Why:* it is the first thing in Deckie that uses the network, and the promise must stay true.
- *Depends on:* the owner's approval of the words.
- *State:* decided, not started. *Size:* small.

**Now-12. A lasting place for the downloads.** The Windows zip exists only as a CI artifact, which expires (the current
one on Dec 14, 2026). The Mac download has no home yet.
- *Why:* a tester's link must still work next month.
- *Depends on:* Now-6.
- *State:* owner's call (where: a GitHub release, the site, or another host). *Size:* small.

**Now-13. Tester pages for Desk.** `windows-first-test.md` is the Windows page; a Mac page is needed, and both updated
for the log and the lookup (`pc/lookup-transports` rewrites the Windows one).
- *State:* Windows drafted; Mac drafted on branch `pc/mac-release` (`mac-first-test.md`, Nov 25, 2026). *Size:* small.

---

## Next

In rough order. Items waiting on a decision start when it is made.

**Next-1. The loading screen's layout.** Four layouts of Desk's run screen to compare; the letter recommends D (layout A
plus the audit's wording: "Total playing time", key as "9A E minor", whole tempos, the true Camelot wheel).
- *Why:* the screen a DJ watches longest should read at a glance.
- *State:* on branch `pc/run-layouts` (web pages only, behind a switch); owner's call. *Size:* small once chosen;
  medium with the Mac window. *Behind:* letter AF, D37.

**Next-2. The quick start.** A silent, captioned film of about 52 seconds, started by the DJ, never on its own, plus three
lines on the screens (Stop keeps what was read; how the crate file gets to the iPad; "then open it in Deckie on the iPad").
- *Why:* a first-time DJ learns the whole flow in under a minute.
- *State:* on branch `pc/quick-start` (first cut, not wired in); owner's call. *Size:* small to medium.
  *Behind:* letter AG.

**Next-3. The dictionary inside Desk.** The public dictionary's words bundled into Desk from the shared word list
(`docs/vocabulary/terms.json`), so a new DJ can look up a word without leaving the app.
- *State:* owner's call; no letter covers it yet. *Size:* medium. *Behind:* D23.

**Next-4. The quicker listener in Booth: A.** After a hard cut the right song is on Booth's screen in a median of 4
seconds instead of 6, with the same number of wrong songs on screen as today's listener on the owner's library (65
clips against 64 of 14,588). The fast setting of letter W5 was not taken: it named wrong songs far more often there.
- *Why:* naming quickly is Booth's core job (note on D35).
- *Depends on:* nothing more. The switching rule has moved into the shared core (D42, Booth step 2), so Desk's Booth
  mode now shows the listener through the same rule as the iPad. Its time per reading on an iPad and on a Windows PC
  is to be read from their logs.
- *State:* listener A is chosen (D41) and is the core's listener for every product (merged Nov 21); built, unseen on
  an iPad or a PC. *Size:* small. *Behind:* D41,
  `faster-listening-results.md` section 11, letter W5.

**Next-5. "Coming in" shown in Booth.** In a blend, the song heard under the one playing is shown as coming in before
Booth switches. The reading leads the name by at most a second.
- *State:* decided (note on D35); the reading is on branch `recog/fast`, not shown in Booth. *Size:* small.

**Next-6. Booth on a Mac laptop.** The iPad app run on an Apple silicon Mac in its own window, for DJs who bring a laptop
and no iPad.
- *State:* idea only; untried. *Size:* small to try.

**Next-7. Look up by sound.** "Look up song via AcoustID" in Desk, for a disc of songs with no names: the fingerprint
engine is built and matches the reference tool exactly; it is in no window.
- *Why:* the owner's case of the unlabelled burned CD (note on D30).
- *Depends on:* the AcoustID decisions (Ask-6); a privacy line that says a fingerprint is sent; a sending method
  on Windows and Linux that can post (disagreement 14).
- *State:* built, not in Desk; owner's call. *Size:* medium. *Behind:* letter AA4.

**Next-8. The lookup on Windows and Linux.** MusicBrainz lookups through Windows' and Linux's own networking, a log a
DJ can send back, and a report-only check on Windows for Arm.
- *State:* on branch `pc/lookup-transports`, ready to merge; a real request from a real PC never made. *Size:* small.

**Next-9. Real discs and sticks.** Read real burned CDs, music CDs and USB sticks on a Mac and a Windows PC: order of
songs as the player shows it, names, CD-Text, the time it takes.
- *Why:* this is how many DJs carry music; every disc figure so far is inferred (letters K, AA).
- *Depends on:* a drive and real discs.
- *State:* decided, not started. *Size:* medium.

**Next-10. Desk for Windows signed.** The letter recommends the Microsoft Store for the first testers (free, no warning)
and Azure Artifact Signing started in parallel (identity checks take days to weeks).
- *Why:* an unsigned program meets SmartScreen, and Smart App Control blocks it outright.
- *State:* owner's call. *Size:* medium. *Behind:* letter Z.

**Next-11. A first launch on Windows that shows something at once.** The first start can take 3 to 9 seconds with
nothing on screen while Windows' web view sets itself up (`checkin-windows-builder.md`).
- *Why:* a DJ will think it failed and start it again.
- *State:* decided, not started; the tester page warns of the wait. *Size:* small.

**Next-12. The site says "your computer".** The home page's lower sections still say "Deckie Desk, on your Mac" and
"Sort your crate into discs and folders"; `llms.txt` calls Windows "planned and not built".
- *State:* decided, not started. *Size:* small. *Behind:* D25, D29, D32.

**Next-13. Publish the site build.** The Nov 16 changes (the new hero, cache stamps) are in `site/`; the site's README
records only the Nov 12 publish.
- *Depends on:* Next-12, Now-2.
- *State:* built, not confirmed published. *Size:* small.

**Next-14. Two name cases left.** Guests in brackets stay in the title; "Artist - Album - Title" with no track number
reads the album as the title. After the fixes, 49 of 56 test songs read as meant, the same on Mac and Windows.
- *State:* decided, not started. *Size:* small. *Behind:* D39, letter AA3.

**Next-15. The key reader's details.** Choose the lean toward minor (the letter recommends 65.6 percent, from openly
licensed club music) and the new wording of the key bar (the letter recommends judging the keys shown by whether
they mix correctly, within 3 points of Apple's on the same songs, with a key on at least 7 songs in 10); show the reader's confidence in words
in the Mac window and in Booth.
- *State:* owner's call; the lean is a setting, off today. *Size:* small. *Behind:* D38, letter X4 (branch
  `key/versus-apple`).

**Next-16. Recognition in a loud room.** In loud crowd noise Deckie's recogniser names only about half the songs by 5
seconds. Steps in the letters' order: spread each fingerprint point across pitch bands, more points when listening,
votes added up across listens, a beat check; and a recording of a loud room to test against. The `recog/fast` check-in
suggests the bigger gain may be where the microphone sits, or a line from the mixer.
- *Why:* clubs are loud.
- *State:* decided, not started (D35: "noise first"). *Size:* medium to large. *Behind:* letters AB, W4, W5.

**Next-17. Booth measured on the iPad.** Memory, launch time and heat with a real library; the index built on the iPad.
- *Why:* iOS ends an app that takes about 20 seconds to start (letter U).
- *Depends on:* Now-4.
- *State:* not started. *Size:* small to measure.

**Next-18. Desk usability items still open.** The drive-size rule (Mac and Windows treat external drives differently), a
labelled Add music button in the Mac toolbar, the window fitting a 1366 by 768 screen, two copies of Desk sharing one
storage folder on Windows.
- *State:* partly done; the rest decided, not started. *Size:* small each. *Behind:* letter AE.

---

## Consistency: one source of truth

There are now three Desks (Mac, Windows, Linux), one Booth and a website, sharing one visual language. Each holds its
own copy of it (`Look.swift` in each app, `desk.css`, `site.css`), so a change to a colour, an added colour, a corner
radius, a drop shadow or a font has to be made in each and can drift. The same is true of behaviour: when a feature
or an element is added, nothing says how it interacts with everything else. D28 and D36 already put every word and
design value into one named list per app; this work makes it one list for all of them.

**Design-1. Design audit and inventory.** Every colour, type size and weight, spacing step, radius, shadow, icon, frame and
component in each of the five, and where they differ. The type audit, already begun, is part of it.
- *State:* begun (the type audit); the rest not started. *Size:* medium. *Behind:* D36 ("the copy audit and the design
  audit are two separate passes, later").

**Design-2. One source of design values.** A single file of named values that the Swift apps, Desk's web pages and the site
all read, so a change is made once and shows everywhere.
- *Depends on:* Design-1.
- *State:* decided in direction, not started. *Size:* medium.

**Design-3. One description of the interface.** For each feature and element: what it is, where it appears in each
product, its states, and what it touches. When something is added, this says what else must change. The word list
is already shared this way between Desk's windows; the interface should be too.
- *Depends on:* Design-1.
- *State:* not started. *Size:* medium, then ongoing.

**Design-4. The copy audit.** Every word on screen, still placeholders (D28), checked across all five against `voice.md`
and the vocabulary.
- *State:* decided, not started. *Size:* medium. *Behind:* D28, D36.

**Design-5. Skins.** Let DJs skin Booth and Desk the way Winamp was skinned, made from a written prompt (the owner's
example was a playful themed look described in one sentence), creating a custom skin, paid per generation.
This is an **explicit carve-out from Deckie's "no AI" stance** (D22, `voice.md`): the one place where something is
generated for the DJ, by the DJ's request. It belongs here because a skin needs the full inventory of frames and
elements (Design-1) and the single source of design values (Design-2) to build against.
- *Depends on:* Design-1, Design-2.
- *State:* idea only (the owner's), not in any decision. *Size:* large.

Open questions it raises, recorded and not answered:

- Where generation runs, when nothing else in Deckie leaves the device (D3).
- Payment through the App Store and on Windows.
- Prompts that name other companies' characters or brands.
- The legibility and accessibility floors a skin may not break (contrast, type size, reduced motion).
- How a skin travels between Desk and Booth.
- How it is spoken of in public copy that never says "AI" (D22).

---

## Later

Agreed direction, no date.

**Later-1. Booth inside Desk on a computer.** Many DJs bring a laptop, and the crate file is already on it. On the Mac it
could reuse Booth (see Next-6); for Windows Booth is a rebuild, not a port.
- *State:* under way, in the steps of `docs/research/booth-in-desk.md` (on `research/booth-in-desk`). Step 1 (Desk
  listens, Nov 21) and step 2 (Nov 21, D42: the switching rule, the picks and their words moved into the shared core,
  the iPad app running them unchanged, Desk showing the iPad's song and the picks as a plain first look) are done.
  Step 3, the designed Booth screen in Desk (Mac and pages, D44), is built on branch `pc/booth-in-desk-3` (Nov 21):
  the window takes Booth's own ground while it shows, the song playing big with its place along its wave, the picks
  as rows with the iPad's Shuffle dial working live and its More, the listening controls at the foot. **Waiting on
  the owner's look**, his choice of the ground made (violet; D44). Pictured on the pages only; the
  Mac's screen compiles and is unseen. *Size:* large.

**Later-2. Desk inside Booth on the iPad.** Build a crate from a USB stick, or from music played into the iPad, for a DJ
with no computer. D29 allows the iPad finishing a crate file "as an option, never as the answer".
- *State:* idea only (P17 once placed it second). *Size:* large.

**Later-3. The album workflow.** How Desk reads and shows albums. The owner left it for later (`desk.md`).
- *State:* not designed. *Size:* medium.

**Later-4. Engine speed and memory.** Deferred on purpose until the core workflow is built (letter P has the estimates;
an 8 GB Mac may run out of memory with today's job count).
- *State:* decided, not started. *Size:* medium.

**Later-5. Organising in Desk.** Discs and playlists built in Desk, as an addition to the crate file.
- *State:* decided for later (D25). *Size:* large.

**Later-6. The spec's v1 features not yet built.** From `01-spec.md`, `spec-condensed.md` and `user-flows.md`:
onboarding from a short song chain (D5, D12, letter C); learning from what the DJ plays, shown and undoable (D5,
note on D3); saved pairs; set recording with a tracklist and CUE or Mixcloud export; rekordbox export and import
buttons (D13; a rekordbox import exists in Desk for Mac); profiles (P9). The user flows carry ten open questions for
these.
- *State:* decided as direction, not started. *Size:* large.

**Later-7. Apple's fingerprints dropped.** A crate file made on a Mac carries both kinds of fingerprint until Deckie's has
been judged on a real night; then Apple's go.
- *Depends on:* a real night with Booth (Now-4, Next-16). *State:* decided (note on D35). *Size:* small.

**Later-8. More file types and machines.** Ogg, Opus and WMA; music CDs on Windows and Linux; a native build for Windows
on Arm (today it runs emulated, about nine times slower); a Linux package; Intel Macs, or say plainly they are not
supported.
- *State:* not started; Linux packaging and Intel are owner's calls. *Size:* medium each. *Behind:* letters Y, Z,
  `desk.md`.

**Later-9. A vocal listening set.** Songs labelled by ear across styles, to calibrate the vocal reading and decide what
"vocal" means for chopped and sampled hooks.
- *State:* decided, not started. *Size:* medium. *Behind:* letters J, Q, P13.

---

## Recorded ideas

Not agreed, not designed. Written down as heard.

- **Idea-1. The brake.** A transition heard in a set of 90s and 2000s songs: the playing song is slowed all the way to a
  stop, a beat of silence, then another song starts. Powerful, probably valuable even if not common. Booth does not
  suggest it today; it could be an option a DJ turns on. It needs a word: DJs say "brake" or "power down" for the
  slow-to-a-stop, which is different from a breakdown (a quiet section inside a song). Letter E and the community
  pass already warn against "brake" alone; "vinyl brake" is the booth word in `voice.md`.
- **Idea-2. What comes after a brake.** Because the music stops, the next song need not match in tempo or key: any song
  could follow, though the same style, era or artist would feel most natural, or a random one.
- **Idea-3. Roll the dice.** A big button, or an occasional suggestion, that offers a brake and a surprise next song.
- **Idea-4. A practice game.** Most DJs play with their music at home. For someone new, returning or just bored, a game
  mode in the manner of a rhythm game: Booth sets a mix to make and scores how it went.

---

## Waiting on the owner

Open decisions gathered from every document and branch. Each gives the options and what the document recommends.

| # | Decision | Options | Recommended | Source |
|---|---|---|---|---|
| Ask-1 | Loading screen layout | A (booth-like), B (A mirrored), C (today's, in columns), D (A plus the audit's wording) | D; A if the wording waits | letter AF, `pc/run-layouts` |
| Ask-2 | Quick start | A film; a five-step tour; a checklist; a film plus three lines | Silent captioned film plus three lines. Also open: does the first-screen line go after the first crate; the film on the site too; one film or a Mac one | letter AG, `pc/quick-start` |
| Ask-3 | Dictionary inside Desk | Bundle the shared word list; link to the site; not now | None written | D23 |
| Ask-4 | Fast listener | **Decided Nov 21 (D41): listener A**, not `boothFast`. Still open: show "coming in"; show the steady fader figure; let Booth use the index before copies are found | (decided) | D41, `faster-listening-results.md`, letter W5 |
| Ask-5 | The "first label" fact | Keep "first released on" beside "came from"; drop it. Also: may a lookup's label fill a `label` field that holds junk | Keep both facts (D39); the junk question open | letter AA2, D39 |
| Ask-6 | AcoustID for "Look up by sound" | Key built into the app; key fetched from a Deckie server (makes "not us" untrue); pay the commercial plan (about €50 a month); not ship | Built-in key, commercial plan before any paid release, privacy line reworded | letter AA4, note on D30 |
| Ask-7 | Model weights trained partly on non-commercial or all-rights-reserved recordings | Ship and disclose (D15 as recorded); never ship such weights (the stricter rule the key work follows) | An attorney's answer; letter X4 has a page ready to send | D15, letters T, X3, X4 |
| Ask-8 | Key profile tables copied from Essentia (AGPL) | Re-source the numbers from the papers; ask the attorney; remove the old estimator | Re-source from the papers (letter R, `DEPENDENCIES.md`) | `KeyEstimator.swift` |
| Ask-9 | Private data in the public repo's history | **Decided (D45):** the tree is clean (Phase 1), and the public repository is a new one whose history is rebuilt so that no earlier version holds the data (Phase 2) | (decided) | D45 |
| Ask-10 | Lean toward minor and the key bar's wording | Lean: none, 55.2, 65, 65.6, 85 percent. Bar: three wordings | Lean 65.6 (open club music); bar wording 1 | D38, letter X4 (`key/versus-apple`) |
| Ask-11 | Windows signing and the WebView2 installer | Microsoft Store; Azure Artifact Signing; a bought certificate; unsigned. Ship Microsoft's installer or a message | Store first, Azure in parallel; a message, no installer | letters Y, Z |
| Ask-12 | Where the downloads live | A GitHub release; the site; another host | None written | Now-12 |
| Ask-13 | Booth's clean filter | Hide dirty songs; show only clean songs and instrumentals | None written | letter AC |
| Ask-14 | Booth's search | Title and artist (D19); also version and the whole credit | Widen it | letter AC |
| Ask-15 | Words still open | "Filter out" or "filter sweep"; "transition" or "mix" on screen; a name for a saved pair; is "source" said aloud | DJs say "filter out" | `voice.md`, D26 |
| Ask-16 | The name and the DECKEE mark | Attorney review before any filing or public launch; the "as in deckhand" footer | Review first | D9, letter V |
| Ask-17 | Pricing | One-time, about $39 to $59; something else; and how paid skins fit | One-time | letter D, `01-spec.md` section 8 |
| Ask-18 | Linux package; Intel Macs | AppImage, Flatpak or .deb; support Intel or say not | None written | letter Z, `desk.md` |
| Ask-19 | Lookup terms for a paid app | MusicBrainz commercial plan (from about $100 a month once public); Discogs (terms unread) | Before any paid release | letters AA, B |
| Ask-20 | The demo and the site rule | A demo page with freely licensed, credited songs; D23's "never a real song or artist" | None written | Now-1, D23 |
| Ask-21 | The TestFlight paperwork | Approve the five drafts in `testflight/` as written, or change them | None written | `testflight/README.md` |

---

## Risks and unknowns

**Never seen by a person on a real device**

- **Risk-1.** Booth's own recogniser has never run on an iPad: not its speed, memory, heat or the index file (letter W4,
  section 6). Real-night evidence is one quiet house party, from Apple's recogniser and from a recording replayed on
  a Mac (letters S, W3).
- **Risk-2.** No loud room has been tested. In simulated crowd noise about half the songs are named by 5 seconds
  (letter W5).
- **Risk-3.** Desk for Windows has never run on a real PC: SmartScreen, antivirus, Windows 10, an account without
  administrator rights, OneDrive and network drives (letter Y, `windows-first-test.md`). Windows on Arm only
  emulated.
- **Risk-4.** No crate file made on Windows has been opened on a real iPad; no real disc has been read by Desk.
- **Risk-5.** No DJ outside the project has used either app. The run screen's motion, the layouts and the quick start
  are unseen by any DJ.

**Legal and licence questions** (for the attorney, alongside DECKEE)

- **Risk-6.** Model weights whose training sets include non-commercial or unlicensed recordings: Beat This! ships under
  D15 with its record; YAMNet's AudioSet clips belong to their uploaders (Ask-7).
- **Risk-7.** The learned key reader's sources: a set marked "for research purposes" beside its CC BY licence, whether a
  list of pages is enough credit, public-domain marks resting on uploaders' word (`DEPENDENCIES.md` section 13).
- **Risk-8.** Key profile tables transcribed from Essentia's AGPL code still ship in the core (Ask-8).
- **Risk-9.** AcoustID is free for non-commercial use only; MusicBrainz charges once a product is public; Discogs terms
  unread (Ask-6, Ask-19).
- **Risk-10.** Microsoft's runtime libraries in the Windows zip are shared under terms that need a Visual Studio
  licence (`DEPENDENCIES.md` section 3).
- **Risk-11.** The site's fonts (SIL OFL) are not on the dependency allowlist or in `dependencies.json`. (The two lab
  models under a non-commercial licence are no longer committed, D45: the lab fetches them itself.)
- **Risk-12.** The DECKEE mark (D9); patents listed as expired from listings only, with one family (Gracenote's) still in
  force near letter AB's methods.
- **Risk-13.** Skins (Design-5) would bring prompts naming other companies' characters and brands.

**Single points of failure**

- **Risk-14.** The owner's Mac holds the only library, the only recording of a real night and the lab's environment;
  every whole-library test (Next-4, D35) must run there.
- **Risk-15.** One GitHub account holds releases `models-1` and the no-telemetry ONNX Runtime; the Beat This! export
  cannot be made again byte for byte, so the release copy is the only one. The learned key file and its credit list
  are on the same release since Now-8: one more thing that account alone holds.
- **Risk-16.** One Apple team and one test iPad (its development profile runs to Oct 2027).
- **Risk-17.** Windows builds depend on one pinned Swift release and a pinned Microsoft toolset (`pc/win-export`); a
  runner image change already broke them once.
- **Risk-18.** The site is published by hand from one machine to one hosting account; no deploy is automated.
- **Risk-19.** No CI builds the Mac or iPad apps, and no check enforces the dependency allowlist yet
  (`DEPENDENCIES.md`).
- **Risk-20.** The tree is scrubbed (D45): the private data, the old brief, the pool and the party's page are gone,
  and a check fails if they return. The public repository's history is rebuilt so no earlier version holds them
  (Ask-9).

---

## Where the documents disagree

Listed, not settled. Each needs a fix to the document, the code, or a decision.

1. ~~**D38 says the learned key file "is published".** It is not: `DEPENDENCIES.md` section 13, `core/README.md` and
   letter X4 on `main` say so, and `dependencies.json` has no row. The file is `deckie-key.f16` on `main` and
   `deckie-key-2b4fe8fa.f16` on `key/versus-apple`.~~ Settled Nov 21, 2026: the file is published on `models-1` and
   the Windows zip requires it (Now-8).
2. **The lean toward minor.** Letter X4 on `main` reads as if 55.2 percent is applied; the branch says the lean is a
   setting, off today. The branch also withdraws `main`'s claim that the learned reader is right more often than
   Apple's over all songs.
3. **Where the key tables came from.** `KeyEstimator.swift` says "Essentia's key.cpp, verbatim"; `DEPENDENCIES.md`
   says key.cpp "was not read"; letter R says both.
4. **Apple's key reading on the Mac.** D11 and D17 say the crate's key is Apple's reading where Apple's framework
   exists, and `desk-app/README.md` implies it; nothing in Desk or the core uses Apple's framework.
5. **TestFlight timing.** D36 says "TestFlight waits until more of the core is settled"; the first test build is now
   Booth to TestFlight.
6. **"Deckie Desk is the Mac app."** D22 and `voice.md` say so; D29 and D32 put Desk on Windows and Linux. The site,
   `llms.txt` and its structured data still say Mac only.
7. **Discs organised in Desk.** The site's "Sort your crate into discs and folders" and its Desk picture's caption
   follow D20, which D25 reversed.
8. **Real songs on the site.** D23 and `voice.md`: the site never shows a real song or artist. The demo (Now-1) plays
   freely licensed real songs.
9. **`desk.md`** lists TestFlight for Mac as open (Desk is not sandboxed, so a download) and fingerprints at other
   speeds as not built (D35's fingerprint covers the whole fader).
10. **Older documents still describe the Oct 27 plan**: Apple's recogniser, a Rust "Desk Lite", signatures made on
    an Apple device, the iPhone "Pocket": `spec-condensed.md`, `01-spec.md`, `architecture/overview.md`,
    `pc-linux-track.md`, `pc-linux-status.md`. D14, D32 and D35 replaced these.
11. **The READMEs.** `README.md` says the bundle id is still "deck" and describes bundled data; `deck-app/README.md`
    still carries the party-era title and says "version 1.0, build 1" (the app is 0.1.0 (1)).
12. **Training data.** D15 lets weights ship whatever their training sets' terms, with disclosure; the key work
    follows a stricter rule (no non-commercial or share-alike data in our own weights). Whether the difference is
    intended is Ask-7.
13. **Fingerprints from Windows.** `what-to-test-build-1.md` and `windows-first-test.md` say a crate file made on a
    PC carries no fingerprint; the shared engine now writes one on every computer (`Analysis.swift`, D35). Unproven
    on a real PC.
14. **The lookup's sending method.** "Look up by sound" needs to post; `main` can post only on the Mac, and
    `pc/lookup-transports`' Windows and Linux method cannot post yet.
15. **`windows-first-test.md` on `main`** says nothing is looked up; `pc/lookup-transports` rewrites it.
16. **Letter AE** describes a Desk with no Stop; Stop and three ways to add music are built since.
17. **Letter ids.** `q-vocal-uses.md` titles itself "Research O"; the recognition check-in's header names an old
    branch.

Branches seen and not listed above: `pc/covers` holds only merges of `main` and adds nothing to it.
