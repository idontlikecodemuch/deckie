# Research U: a top-down review of the booth and what feeds it

Dated Nov 1, 2026, at main 00785ef. A read-only review: no code changed, no commit. The two crates under
~/Music/Deckie were only read, and only to measure size and memory; nothing here sets a number from them. Tags:
[measured] = run on this Mac for this review; [inf] = my inference from reading the code; [unmeasured] = worth
measuring, not measured here.

## In plain words

Deckie has three parts. Deckie Desk, on the Mac, turns a folder of music into a crate (a `.deckiecrate` package:
one file of track records, small companion files per track with per-bar values and a sound "style" vector, and a
recognition fingerprint per track, called a signature). The shared core (`core/`, plain Swift) holds the analysis,
the pair scoring (how well song B follows song A) and the crate format. The booth, on the iPad, reads a crate,
listens to the room, recognises the playing song and ranks what could come next.

The booth was first built for one party, from a bundled data file of 347 songs with every pair scored in advance.
In the last three days it learned to read crates of any size (2,327 songs tested), to score picks on the iPad one
song at a time, to draw the join view (the end of this song over the start of the next) from per-bar loudness, to
show one ranked shortlist ordered by a Shuffle dial, a More list over the whole crate with a search, and discs and
folders organised in Desk.

The new work is mostly sound. The pair scoring is shared and tested; the one-song-at-a-time scoring was the right
call and the numbers show it (two minutes and 4.3 GB at load became about five seconds). The trouble is at the
seams: the booth still carries the party version underneath, so it has two data sources, three track shapes, two
ideas of "the same song", and party-specific screens that a library crate does not fill. One of those seams is a
real product conflict, and it is the first thing I would fix.

## The headline findings

1. **The booth folds different versions of a song into one, against the Nov 1 note on D19.** The note says only
   copies of the same recording fold together and every remix or edit is its own row, and that "nothing changes in
   the code". The code does something else: picks keep one row per *song key*, which is the title with anything in
   brackets removed and only letters and digits kept (`Track.songKey`, `deck-app/Deck/Sources/Model.swift`;
   `Suggester.candidates`, `Mixing.swift`). "Song (Extended Mix)" and "Song (Club Remix)" share a key, so only one
   of them can be a pick, and no version of the playing song can be a pick at all. Desk-built crates never carry a
   `cut_key` (the crate's field for "same recording"; the builder does not set it), so the fold by recording that
   the note describes never happens for them; only the fold by title does. [measured] In the library crate, 1,058
   of 2,327 tracks share a song key with at least one other track (415 groups), so a large part of a library can
   never appear as a pick while its sibling is shown. The same rule is in recognition: `Recognizer.handle` treats a
   match on another track with the same song key as "the same song, not a challenger", so a DJ who plays one remix
   right after another version of that song will not see the booth switch (`Recognizer.swift`, around line 314).

2. **A crate without discs has no way to set the playing song by hand.** The README's promise ("Setting the song
   by hand on the CDs tab always works") depends on the CDs tab, which lists discs. Neither crate on this Mac has
   disc labels yet, and for such a crate the CDs tab is empty. The search in More could be that fallback, but it
   only searches More (not the picks above, not songs filtered out, not recently played, not other versions of the
   playing song), and tapping a row pins it rather than setting it as playing.

3. **Most of the steady memory is data the booth needs; most of the growth is the More list.** Measured on the Mac
   with a throwaway probe against the shared core (details in the appendix): reading the library crate peaks at
   about 165 MB and then lets go; the scoring data the booth keeps (2,327 scoring tracks with their 1,024-number
   style vectors, plus the sorted list of every pair's style similarity) is about 90 MB; the recognition catalogue
   built from 2,327 signatures adds about 125 MB. That is roughly 215 MB of the booth's figure. The rest is the
   app's own copies of the tracks and pick lists, SwiftUI, the audio engine and the frameworks [inf]. The growth
   from about 640 MB to about 830 MB after deep scrolling fits the More list: every row past the shortlist is a full
   card with its own drawn join view, built in a lazy stack (a list that builds rows as they scroll in) that keeps
   what it has built [inf; confirm with Instruments]. Note: the 640 and 830 MB figures are not in the repo;
   `deck-app/README.md` still says "about 0.5 GB".

4. **The one structure that grows with the square of the library is the style-similarity list.** To rank a pair's
   sound similarity among all pairs (the "timbre rank"), the booth keeps every pair's similarity, sorted: n x (n - 1)
   / 2 numbers. At 2,327 songs that is 2.7 million numbers, 22 MB and 2.7 s to build [measured]. At 5,000 songs it is
   about 100 MB, at 10,000 about 400 MB and well over half a minute at every launch [inf, by the square]. Nothing
   else in the booth grows that fast. Reading the crate (about 60 KB per track while reading) and the catalogue
   (about 54 KB per track per signature) grow in a straight line.

5. **Everything loads before the first frame.** The crate, the similarity list and the catalogue are all built
   synchronously when the app starts (`Recognizer.init` calls `rebuildCatalog`, which touches `Library.shared`,
   which loads the crate). The 5 s figure is from a Mac simulator; the installed iPad is an older chip, and iOS
   stops an app that takes too long to start (about 20 s) [unmeasured on the device]. There is no "loading" screen.

6. **The app is about 169 MB, and 159 MB of it is the party's catalogue,** bundled and never opened when a crate is
   present (`Deck/Resources/Deck.shazamcatalog`, 159 MB on disk; the README says 47 MB and 59 MB for the app).

## Where the new work conflicts with how the booth was built

**Two data sources under one shape.** The booth's `DeckData` (tracks, discs, pairs) was the shape of the party's
`deck_data.json`. A crate is now converted into that same shape (`CrateLibrary.load`), with `pairs` left empty and
a separate path for picks. So every view asks "crate or bundled?" through `Library.pairs(from:)`, the booth `Track`
carries both crate fields and party fields, and the join lanes are encoded from numbers into the party's text
format (a 64-letter alphabet, one letter per sample) only to be decoded again on every draw (`Wave.values`,
`Overview.values`). The crate path works; it is just paying to look like the old file.

**Disc names versus "CD1".** D20 lets a DJ name discs. The chips show the names ("Singalongs"), but the rows,
the playing panel and the CDs tab still say "CD1 / folder /" and "CD1 · 6-04", from the disc's position in name
order (`Track.folderPath`, `discLabel`, `discLocation`; `CDsView.denseColumn`). With named discs the same disc is
called two things on one screen. `discLabel` also takes a folder's first word as its number ("6 - 125-129" gives
"6"), which was the party's naming habit.

**The booth rebuilds the disc plan itself.** The core now has `Crate.discPlan` (discs, folders and tracks in order,
shared by every desk), but `CrateLibrary.load` builds its own, with small differences: a disc track with no folder
label sits in a folder named after the file's directory in the booth but in the "" folder in Desk, and ties in track
number are broken differently. One place should decide this, and the core already has it.

**More was added on top of a list designed for ten.** Each row is a full card with a drawn join view
(`NextRow` and `JoinView`). That suits the five or ten picks; for the few thousand rows of More it costs memory and
scrolling, and a DJ reading past the shortlist is looking for a name, not reading join shapes.

**The shortlist size is tied to the library, so the Shuffle dial means something different per crate.** D19 sets
the shortlist at a tenth of the library, never fewer than 10, and the dial blends score with a dice roll within it.
On a 238-song crate the dice choose among 24 songs; on 2,327 songs among 233. At the default dial (50 percent,
`SuggestState.savedShuffle`) a song near the bottom of 233 can open the first screen. The first-night evidence
(letter S) was with the dial at 0. This is the owner's design and the numbers are the owner's; the point is only
that a bigger crate makes the same dial setting more random.

**The order re-rolls on things that are not "roll again".** `reroll` draws new dice when the DJ switches Simple and
Full, toggles a disc chip, or pins a song. Switching to Full to see more can change the top five. [inf] A DJ would
expect the order to hold for a song until the dial moves or the song changes.

**Crates carry one signature per track; the party catalogue carried three.** The bundled catalogue had the plain
signature plus vinyl at -4 and +4 percent; crates have only the plain one ("Not yet from a crate: pitch-variant
signatures"). The crate format already allows variant signatures. When they come, the catalogue triples (about
375 MB for 2,327 songs at today's size per signature [inf]), which makes caching it and loading it off the main
thread more pressing, not less.

## Dead weight and things that exist twice

- **The party's bundled data path**: `deck_data.json` (11 MB), `overview.json`, `Deck.shazamcatalog` (159 MB),
  `mixmap.html`, and the tools that make them (`deck-app/tools/prep_data.py`, `mixwaves_all.py`,
  `overview_waves.py`, `catalogtool`, whose compiled binary is committed). The core already turns the lab's
  feature files into crate records (`DeckieLab`, `crate-from-lab`), so the party set could be a crate like any
  other, with its variant signatures, and the bundled path could go.
- **The Mix map tab** shows the party's map whatever crate is loaded. With a crate it is the wrong data.
- **Three track shapes and three pair shapes.** `CrateTrack` (the format), `DeckieCore.Track` (what the scoring
  reads) and the booth's `Track` (what the screens read, still `Codable` for the old file); `PairScore` (core), the
  booth's `Pair` (rounded, with labels, shaped like the old file) and `RecEntry` (the lab's lists, now only in tests).
  The first two of each are justified; the booth's own copies are mostly the old file's shape.
- **Three ideas of "the same song"**: the crate's `id` (the file's bytes), its `cut_key` (same recording, never
  set by Desk) and the booth's `songKey` (title text). See the first headline.
- **Tempo and key logic written twice.** `MNUM` in `Mixing.swift` repeats the core's `Tempo.labels`; `joinInfo`
  recomputes the pitch with its own three multipliers when there is no pair, while `CrateLibrary.picks` computes it
  another way; `keyVerdict` repeats part of the core's `Camelot` rules and finds "pitch-shift" by searching the
  scoring's reason sentences for text, so rewording a reason would silently change a verdict.
- **Whole-table scoring in the core** (`PairScorer.scoreAll`, `timbrePercentiles`, which builds an n by n table,
  and `recommendations`) is now used only by tests, as the reference the one-song scoring is checked against. That
  is a fine role; it should say so, so nobody calls it from an app.
- **Stale words.** `deck-app/README.md` still opens as the party's helper for 347 tracks, describes Easy and Harder
  picks, "2 + 1" and "3 + 2", CD1 and CD2 chips, a 59 MB app and 0.5 GB; its folder list calls `Mixing.swift` "the
  suggestion sampler". The Halloween effects, the pumpkin mark and the "RMX" chip are party features; the RMX chip
  never shows for a Desk crate, which has no version field filled.

## Memory, measured and inferred

Measured on this Mac with a small program against the shared core (Release build, nice 19), on the library crate
(2,327 tracks, 141 MB on disk, 111 MB of it signatures). "Footprint" is what the system counts against the app.

| Step | Footprint after | Peak so far |
|---|---|---|
| Read the crate (1.2 s) | 137 MB | 137 MB |
| Make the scoring tracks, crate released | 52 MB | 165 MB |
| Build the sorted similarity list (2.7 s, 2.7 million values) | 83 MB | 165 MB |
| Score 8 songs into the rest (57 ms each, kept) | 93 MB | 165 MB |
| Build the recognition catalogue from 2,327 signatures (0.5 s) | 219 MB | 219 MB |

In the booth the crate is still held while the similarity list is built (it is a local of `CrateLibrary.load`
until the end), so its load peak is higher than the probe's [inf]. The style vectors are stored in the crate as
half-size numbers and held as full doubles (four times the bytes, about 19 MB); the similarity list is doubles too.
Neither is large today. The booth's own extras over the probe are the display tracks with their encoded lanes
(a few MB), up to 8 songs' converted pick lists (2,326 pairs each, with several strings per pair: tens of MB at
most [inf]), the pick rows for the screen, and the views.

What would bring the figure down, roughly in order of effect [inf, each to be confirmed by measuring]:

- More past the shortlist as plain text rows (title, artist, BPM, pitch, move), with the join drawn only when a row
  is opened or pinned, in a recycling list (SwiftUI's `List`) rather than a lazy stack that keeps what it built.
- The catalogue built once per crate and cached (`SHCustomCatalog` can be written to a file and read back), off
  the main thread; the crate format already names a local-only `catalog/` place for this.
- The crate read with only what the booth uses, after which nothing of the full model is kept.
- The similarity list replaced by a fixed table of its quantiles (for example 4,096 cut points, a few tens of KB
  at any library size). The rank it gives differs from the exact one by at most 1 in 4,096, so the score changes
  only in the fourth decimal at most, but it is no longer bit-for-bit the lab's score; the parity test would need a
  stated tolerance. The alternative that keeps exact bits is half-size numbers, which halves the list but keeps
  the square.

The first step is to measure on the device: the booth could log its footprint after each load stage and after
each scoring, as `deckie-memprobe` already does for the analyser, so every later change is judged on numbers.

## Structure

- **The booth's logic lives in the app target, with no tests.** The shortlist and the scoring are in the core and
  tested; the rest of what decides a pick (one row per song, the disc filter, the recently played rule, the tags,
  "deep cut") is in `Mixing.swift` and `DeckApp.swift`, untested, and unavailable to the Windows and Linux desks,
  the phone, or a future Android booth. `docs/architecture/overview.md` planned these for the core.
- **A global, unobserved library.** Views and the filter read `Library.shared` directly. Loading another crate
  (only possible through the `deck://crate` test hook) does not redraw what read it; `LibraryFilter.allows` and
  `label` reach into the global. An observable model handed down to the views would make the crate switch, and a
  loading state, natural.
- **No crate picker.** The booth opens the remembered crate or the first `.deckiecrate` in Documents in name order.
  With two crates in Documents, the second is unreachable without the test hook. The remembered path is absolute,
  and iOS can move the app's folder on reinstall, so it is quietly lost then [inf].
- **The crate travels by copy.** Every disc edit in Desk means copying the whole package (141 MB, mostly
  signatures) to the iPad again. Not a bug today; a reason to keep signatures and the small changing parts apart
  when the transport (iCloud Drive, AirDrop, Files, per the overview) is chosen.
- **Desk edits copy and compare the whole crate.** `DeskModel.updateCrate` compares the crate before and after with
  `!=`, which walks every track's per-bar arrays, and every save rewrites every companion file (about 4,650 for the
  library). Fine at this size [inf]; worth knowing when libraries grow.
- **No CI for the apps.** The workflows build and test the core on Linux and Windows only.

## Product behaviour

- Versions of a song, recognised and picked, as in the first headline.
- Setting the song by hand and finding any song: one search over the whole crate, reachable from the playing panel,
  that can set a song as playing or pin it, would cover crates without discs and the "I know what I want" case.
- The order of the picks: hold the dice for a song (one roll per song, kept) so Simple and Full and the chips do
  not reshuffle; roll again only when the dial moves or on an explicit re-roll.
- Disc names everywhere a disc is shown, from the core's disc plan.
- The Mix map tab hidden for crates, or rebuilt from a crate later.
- A loading screen while a crate opens, saying how many songs and how long.

## What I would do first, and why

1. **Settle "the same song" in one place, and make recognition and picks use it.** It is the one behaviour that
   contradicts a written decision, it hides a large share of a library, and it can make the booth miss a song
   change. The change itself is small; what needs a choice is the rule (options below).
2. **Measure on the device, then take the two cheap memory wins**: More past the shortlist as text rows in a
   recycling list, and the catalogue cached and built off the main thread with a loading screen. These also fix the
   launch risk. They change no scores.
3. **Make the party set a crate and remove the bundled path.** One data source lets the booth's `Track` and `Pair`
   shrink to what the screens need, drops 159 MB from the app, removes the Mix map's stale data and four tools, and
   gives the variant signatures a home in the crate format that already allows them.
4. **Move the pick rules into the core with tests** (one row per song, filters, recently played, tags), next to
   the shortlist, so every Deckie app ranks the same way.
5. **Replace the squared similarity list before libraries grow past a few thousand songs.** Not urgent at 2,327; it
   is the one cost that will become the problem by itself.
6. **Whole-crate search with "set as playing", a crate picker, and disc names in every label.**

## Choices for the owner

On "the same song", three ways that keep crate v1 as it is:

- Fold only what the crate says is the same recording (`cut_key`), and nothing by title. Every version is its own
  row and its own song for recognition. Simple and exactly what the D19 note says; copies of one file under two
  names then show twice until something fills `cut_key`.
- As above, and let Desk fill `cut_key` by finding the same recording: Desk already makes a signature for every
  track, and matching each against the others finds files that are the same audio. The field exists, so no format
  change.
- Keep a title fold for picks only (one version shown, the others a tap away on the row), never for recognition.
  Fewer near-duplicate rows on the first screen, at the cost of the D19 note's wording.

On the shortlist and the dial: keep the tenth of the library as decided, or fix the dial's window (for example the
best 30 to 50 songs, whatever the library size) so the same dial setting feels the same on every crate. Either is
first principles; neither needs fitting to a crate.

On the similarity list: exact bits with the lab (keep the list, perhaps at half size) or a fixed-size table with a
stated tolerance against the lab.

## Appendix: how the numbers were taken

- Memory and timing: a throwaway Swift program in the session's scratch folder, depending on `core/` by path,
  built in Release with nice 19, run once on the library crate. It reads the crate with `CrateReader`, makes the
  scoring tracks, builds `PairPool`, scores 8 songs and keeps their lists, then adds every signature to an
  `SHCustomCatalog`; it prints the process footprint (`phys_footprint` and its peak) after each step. A Mac
  footprint is a guide to the iPad's, not equal to it.
- The song-key count: the booth's rule (lower case, bracketed parts removed, letters and digits kept) applied to
  every title in each crate's `crate.json`, counting titles that share a key. CDs v2 has 8 such tracks in 4 groups;
  the library 1,058 in 415. Neither crate has disc labels or `cut_key` values.
- Sizes: `du` on the crates and on the built app (`deck-app/build/dd-dev/.../Deck.app`, 169 MB).
