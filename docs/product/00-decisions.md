# Deckie: decision log

Decisions Christopher made, in order, with the reasoning and what each one rules out. New decisions are appended with
their date. The spec (`01-spec.md`) restates these as requirements; the research plan (`02-research-plan.md`) lists
what we do not know yet. Standing principles from the sprint are at the end.

## Oct 26, 2026

### D1. Deckie is an App Hold Media LLC product
The Apple developer team (566NNM5HT8) is already registered to the LLC. The bundle id is still
`io.christophershannon.deck` and no App Store Connect record exists, so the final bundle id can still be chosen for
free. Decide it under the LLC before the first TestFlight upload; after the record exists it is permanent.

### D2. Analysis runs in the iOS app and on the computer, sharing one analysis file
- Two analysers: the iPad/iPhone app does what it can on device; the Mac (later any computer) does the deep work.
- They exchange a single file (working name: the crate file). It must be in-depth but light enough to pass around.
- A web app is punted to much later: analysis in a browser does not scale.
- Rules out: a Deckie server that analyses audio; a bundled catalogue compiled into the app.

### D3. We never handle the user's content
- The user's audio never leaves their devices or computer. Deckie analyses; it does not store, sync or see music.
- No central library, no upload, no bundled catalogue of commercial tracks in any public build.
- The crate file contains analysis and metadata, never audio. Recognition fingerprints stay with the user.
- This is the privacy stance of every App Hold Media app and is a selling point, not a constraint to work around.

### D4. The user's crate is the catalogue, built from their own files plus public metadata
- Sources on the user's side: audio files, file names and tags, album and CD names, burned CDs, downloads from DJ
  sites where DJs keep their sets. Obscure mixes, edits, bootlegs and live sets are first-class, not edge cases.
- Identification is best-effort mapping of the user's files to public metadata. Reading public metadata to map a
  file is not model training on the user's content.
- YouTube: Christopher raised using YouTube as a public reference for mapping, since most songs are there and public.
  Open question, scoped in research track B: what YouTube's Terms of Service allow from an app on iOS or macOS.
  The official Data API allows metadata search within quota; scraping, crawling and audio download are prohibited.
  The answer decides whether YouTube is a lookup source or off the table.

### D5. Analysis depth: a general base plus a per-DJ onboarding
- The base analysis is tuned generally: beat grid, key, structure, vocal timeline, energy, loudness, style.
- At first run a short "training moment" captures how this DJ mixes: tempo tolerance, pitch range comfort, genre
  and era spread, transition styles (hard cuts to long progressive blends), vocal handling (overlay, cutting in and
  out), and the rest of the range. Research track C defines the dimensions and the learning framework.
- Learning continues from use: what the DJ actually plays after what.

### D6. Everything is tunable
- Sliders, not settings pages: how hard the picks are, how many options to show, how much data is on screen, and
  more as research reveals them. Sliders are how "recommend, never prescribe" shows up in the product.

### D7. Fold in the DJ-community research and extend it
- `docs/competitive-analysis.md` section 4 is the baseline. Research track D extends it and feeds positioning.

### D8. Work from an iterative spec with explicit staging
- `01-spec.md` is the living spec, versioned. Where a section needs research first, it says so and points at the
  track. The spec must state goal, use, value, differentiator, for whom and why.

### D9. Name: Deckie (decided earlier on Oct 26)
Folders, the Xcode target and the bundle id keep "deck" until Christopher says to rename. The deep report is
`docs/naming/05-deckie.md`. Its finding: DECKEE (Deckee Pty Ltd, a boating-safety app, pronounced the same) is
registered for class 9 software in the US (Reg. 6993660, narrow boating goods), the EU, UK, NZ and Canada
(IR 1605323, broad "computer software, downloadable software (apps)") and Australia (2119248, 2119251). Cheap buys
are fine now: deckie.dj after a registrar check, deckie.io, getdeckie.com, the handle deckieapp. On hold until a
trademark attorney reviews DECKEE: deckie.com, any filing, any public launch.

### D10. Repo hygiene
`mixer/pairs.json` (61 MB) is derived from committed inputs and does not belong in the repo; a small test fixture may.

## Standing principles from the sprint (still in force)

- Recommend, never prescribe. Confidence and position are approximations and never compete with the deck's display.
- The DJ's own crate is the catalogue; disc, folder and track location is the primary identifier where discs exist.
- Pitch is a first-class number; the matchable range follows the hardware, not a theory.
- Style and era matter as much as key; key is a warning when it clashes, not a score to maximise.
- Less text, more space, one accent colour used only for meaning.
- Measure, then listen.
- Never modify the source music; never commit audio, catalogues, `.env` or `.p8` files.
- Do not over-engineer; every round that removed something was welcomed.

### D11. Build natively on Apple's Music Understanding framework, with graceful fallbacks (accepted later on Oct 26)
Christopher accepted P1 ("let's build natively for that and create some graceful fallbacks"). One Swift engine on
iPhone, iPad and Mac; the Python stack becomes the lab and does not ship. The fallback is designed in, not bolted
on: a device below OS 27 consumes a crate analysed elsewhere; one that must analyse alone runs a reduced engine and
marks its tracks for re-analysis; the app always says which level it is on. Spec 5.1. Supersedes the hard OS 27
floor in P3.

### D12. Tuning speaks the DJ's language and starts from a song chain (Oct 26)
Christopher: tuning "should be more intuitive. Make a song chain and say how you'd mix it", with in-app popups in the
style of a rhythm-game prompt ("fade mix", "hard break", "echo in", "scratch"), and a researched dictionary so the
app uses the words DJs actually use. Research track E produces the dictionary; every label, popup and slider uses
it; the onboarding chain replaces sliders as the first elicitation. Also accepted as tuning inputs: upload one of
your own sets; upload a set whose style you like. Spec 6.4 and 6.5.

### D13. The crate is Deckie's own format, richer than the industry's; interchange is a button, not a sync (Oct 27)
Christopher: key-change markers, yes; "if we can we should improve the industry standard"; import and export
buttons for other systems, "but it shouldn't be fully interchangeable. I want a little bit of friction. We are
building a unique analysis and product." So the crate carries what no player's format holds: key markers (a key
per segment, so a modulation and the key at each mix window are known), tempo markers with confidence, the mix
windows and vocal-free bars, per-bar instrument activity, the style vector, saved pairs and preferences. Export to
rekordbox XML is explicit and lossy by nature (grids, cues, BPM, one key); import is explicit and keeps a DJ's own
grids and cues. No live sync with other software, and the crate's own fields never leave through the export.
Supersedes the "fully interchangeable" reading of P12.

### D14. Deckie's own code is written once in Swift and runs on Linux and Windows: decided by the spike (Oct 28)
Christopher's direction was to settle the language in practice. The two-week spike took one day: a Swift package
with the grid fit, Camelot mapping and pair scoring reproduces the lab's numbers on all 373 tracks and all 138,608
pairs on Linux (Swift 6.4.1), and the same package builds and passes the same 13 tests on GitHub's Windows machine
with no Windows-specific code (run 40750217848; pull request #1, both workflows green). Rust stays the named
fallback for the Windows build alone if a later mechanic proves painful there. The Apple apps keep Apple's Music
Understanding framework (D11); this core is what both sides share. Dependency policy as in P16.

### Note on D14 (Oct 28): model weights, their training data, and CC BY 4.0
Settled with the PC and Linux session while it chose a vocal model (its report is `docs/research/n-vocal-tagger.md`
on its branch). Two lines added to the dependency policy. First: weights published under an allowlisted licence
ship even when we could not ship their training data ourselves, unless that data's own licence forbids commercial
use, in which case the weights are treated as non-commercial whatever their stated licence; where the data's
licence is unknown, the trainer must be the data's rights-holder. The data set, its licence and who trained are
recorded in `DEPENDENCIES.md` beside the weights. So Spleeter's vocal model (Deezer, MIT, trained on Deezer's own
catalogue) and EfficientAT (MIT, trained on AudioSet, whose labels are CC BY 4.0) are in; musicnn (ISC code, but
trained on CC BY-NC-SA audio) and CLAP (mixed-licence web audio) are out. Second: CC BY 4.0 joins the allowlist for
model weights and data only, never code, with the attribution shown in the app's acknowledgements; CC BY-SA and
CC BY-NC stay off. Christopher can overrule either line; neither is needed by the recommended models.
Third line, same day: MPL 2.0 (file-level copyleft: changes to those files must be published) ships when its files are
unmodified by us, with its notices in the acknowledgements; any change we make to an MPL file is published; an
allowlisted equivalent is preferred where one exists. (A patch an upstream applies and publishes, as ONNX Runtime
does to Eigen, is that upstream's obligation, met by the notices it ships.) Found the same evening: ONNX Runtime
patches Eigen on every platform (two published patches for IBM Z builds, touching nothing these three platforms
compile), so the acknowledgements say "unmodified by Deckie; carries ONNX Runtime's two published patches" and ship
the two patch files beside Eigen's notice, which is the licence's source-availability ask met in the simplest way. Needed because ONNX Runtime (MIT) carries Eigen (MPL 2.0) inside it. For
the attorney to confirm alongside the DECKEE review. Christopher approved all three lines on Oct 28, with a
search for alternatives to the vocal models and the model runtime still to run.

The alternatives search ran the same day (`docs/research/o-alternatives-vocal-and-runtime.md`). It changed the vocal
pick. EfficientAT's small models start from ImageNet weights, and ImageNet's terms are research-only, so it fails
the training-data line; Spleeter's weights are called MIT only in Deezer's paper, which says the training set is
Deezer's internal catalogue without saying Deezer owns it, so it fails the rights-holder test; and every other
separator with a stated licence was trained on MUSDB18-HQ, which is non-commercial. So the Windows and Linux
vocal signal is a tagger, as the lab's was: Google's YAMNet (Apache 2.0, trained on AudioSet alone, 3.7 million
weights), with PANNs MobileNetV2 (MIT code, CC BY 4.0 weights, AudioSet) as the optional second opinion, read per
bar from the singing classes and calibrated by track J's listening set. AudioSet's labels are CC BY 4.0 and
Google ships YAMNet for commercial use, which is the anchor for accepting AudioSet-trained weights; the app uses
its own class words, not AudioSet's share-alike ontology file. A separator returns only if a clean one appears or
the listening test shows a tagger is not enough. The runtime stays ONNX Runtime: its notices name Eigen as the only
MPL part and nothing LGPL, GPL or non-commercial; ncnn (BSD-3, C API, no Eigen) is the named fallback. Two checks
for the PC and Linux session: which third-party parts reach the CPU binary (the notices also list json.org's
"JSON License", off our list), and the CPU time per track of each tagger.
Christopher approved the YAMNet download and any further vocal-model weights the track needs, within these
licence lines (Oct 28).

### Note on D13 (Oct 28): crate format version 1 accepted
The PC and Linux session wrote the reader and writer (`DeckieCrate`) and a design note, `docs/architecture/crate-format.md`
on its branch, listing what spec 5.2, track A and track L fix and eight proposals for the open field-level detail.
Accepted as proposed, with two changes: the engine family for the Windows and Linux engine is `deckie`, not
`deckie-oss` (the models are open source; the engine is not, and the name must not claim a licence); and the note
must say how a shipped engine makes a record's `id` (a prefix of the file's content hash, with the full hash stored),
since the lab's ids were made another way. Measured: 373 lab files round-trip; about 4 KB a track without
signatures, inside the 10 KB budget. The writer refuses to rewrite a crate from a newer schema rather than drop
fields, so an older app will need a line of copy for that case. Christopher approved on Oct 28. Later the same day, two
additive blocks accepted: `manifest.import_log` (device model label, time, files seen, tracks, failures with reasons,
rekordbox matches; the count P18 asks for) and a per-record `imported` block keyed by source (`imported.rekordbox`:
grid markers, cues, loops, playlists, with the import time; null when nothing was imported), the DJ's own data named
for where it came from; the file's tag tempo is `file.tag_bpm`. The acknowledgements screen reads
`core/dependencies.json`, the source of truth, from which the Markdown table in `DEPENDENCIES.md` is generated and
checked by a test, so the apps never parse Markdown. Later still, proposal 10 accepted: two additive blocks
from the session's vocal-uses memo, `vocal_structure` (sung stretches to the beat with each end's distance from the
nearest 8-bar point; the first and last sung beat, with the pickup; free intro and outro bars and what they hold;
vocal-free gaps of 8 bars or more; an "exposed vocal" proxy from the low band and onsets, with the Apple engine's
real reading preferred when present) and `hooks` (up to three candidates for the DJ to confirm), each listed in
features_present and left out entirely when absent so older records keep their bytes; every rule and threshold is
written into the record so the Mac's listening test can tune them. The id of a shipped record is the first 16
hex characters of the file's SHA-256, with the full hash in `file.sha256`. The session's memo is
research Q (`docs/research/q-vocal-uses.md`): O on main is the alternatives search and P is the Mac session's
machine estimates.

### D15. Model weights ship under their publisher's licence; training data is disclosed, not a gate (Oct 28)
Christopher accepted P19: "I agree with your assessment, though we should clarify that in the terms of service /
use." So the training-data line of the note on D14 is replaced by this: weights ship under the licence their
publisher grants; a model is refused when the publisher's own terms restrict use or when a data owner has objected;
every model's training sets and their terms are recorded in `DEPENDENCIES.md` and shown in the app's
acknowledgements, with a named replacement path; the attorney reviews the line with DECKEE. Beat This! ships with
its record. The terms of use say it plainly: Deckie contains third-party models published under open licences,
listed with their licences and training-data disclosures in the acknowledgements; Deckie never trains on the user's
content (D3). Spec 5.9.

### D16. No key is better than a wrong key: Deckie's own key reading ships only when it is good enough (Oct 29)
Christopher: "If key tagging isn't good enough, not with Apple's framework, we just don't record it and release
without it, or with a caveat till it is." So, on a platform without Apple's framework (Windows, Linux, a Mac before
macOS 27), the crate carries the DJ's own key where the file's tags or a rekordbox import have one, and Deckie's
own reading only once it meets the bar on the outside set (research R's GiantSteps-MTG-key test): exact within five
points of Apple's framework on the same clips, measured on the major and minor halves separately. Until then the
record's key block is absent or marked not read, the app says "key not read on this computer yet", and nothing is
scored on it. Three cheap, library-blind improvements are being tested first (a separate mode test after the home
note; chroma weighted toward downbeats, since we know the bar grid; reading the key the DJ's tools wrote into the
tags), and a mixed-genre listening set with keys written down by a musician is the next thing to commission. Same
evening, two of the three measured (letter R, "Mode test and tag survey"): a separate mode rule from Temperley's and
Krumhansl's profiles changes 3f's answer on 81 of 1,122 clips for a net gain of about nine, within chance, because in
this music the minor third is louder than the major third in barely half of the minor-key clips; and only 4.3 percent
of Christopher's library carries a key tag at all (Serato, on the loose files; none in the compilations), so reading
tags fills gaps but cannot make the reading better. The third, chroma weighted toward the beat grid (Oct 30, with
Apple's grid on the clips standing in for the engine's), is worse the more weight the strong beats get: downbeat
frames only 32.8 percent exact against 47.4 with equal weights, beat frames 42.0, a metrical weighting 46.7, on both
halves alike. All three are measured and none moves the minor half; and Apple's own framework reads 65.2 percent of
these clips exactly (75.6 of the minor, 41.5 of the major), so the bar is missed on the minor half by 34 points.
Short of a trained model, D16 stands: no key from our own reader on non-Apple platforms. A fourth test (Oct 30, letter R, "Overtones taken out of the chroma"): taking the overtones out of the twelve-note
profile before the key is decided, either by the reader's own harmonic discount (a few multiplications a frame) or by Mauch
and Dixon's note transcription (heavier: 2.3 s a clip in Python), lifts exact from 47.4 to 55.4 percent on all 1,275 clips,
and the gain holds on the half the choice never saw (sign test p 0.001 or better). It is the mode lean that the overtones
were causing; the home note does not move beyond chance (held-out 71.6 to 72.6). Against Apple the exact gap narrows from
17.6 points to 9.6: the major half is now ahead of Apple on both measures, the minor half is 23 points short of the bar.
D16 still stands; whether the engine takes the discount now, the transcription later, or neither until a trained model
is Christopher's call, with the facts in the letter.

### D17. Key is shown with its limits: Apple's reading where it exists, a plain caveat everywhere, the mode named as the weak part (Oct 30)
Christopher, on the overtones test: "Apple does a better job and I think we use that when it is available. On a
completely separate track we need to investigate a way to improve the native tone detector. In the product we should
just flag that tone detection isn't perfect (even for apple) and flag the mode issue." So: on a device with Apple's
framework (iOS 27, macOS 27) the crate's key is Apple's reading, as D11 has it. The product says, once and plainly, that
no key reader is right every time, Apple's included (on the outside set of unfamiliar dance tracks Apple's reading is
exact about two times in three and finds the home note three times in four), and that the part most often wrong is the
mode: major against minor on the right home note. Where Deckie shows a key it shows the Camelot code and, when the
reading is unsure, says so rather than hiding it (the key-stability confidence of D13 carries this). Improving Deckie's
own reader is a research track of its own, apart from the product work, under D16's bar and D5's library-blind rule;
the facts to start from are letter R's last four sections (the outside test, Apple on the same clips, the beat-grid
weighting, the overtones). Spec 5's key bullet carries the caveat.

### D18. The booth scores picks for the song that is playing, and draws the join lanes from the crate's per-bar loudness (Oct 30)
Christopher, on the two booth choices put to him: "Score when recognized and draw the lanes from the per bar values. Agree
on both." So: the booth keeps no table of every pair. When a song is recognised (or set by hand) its picks are scored
then, from the crate's own analysis with the shared scoring, and the last few songs' lists are kept. The one thing that
needs the whole crate, the timbre rank (where a pair's sound similarity sits among every pair of the crate), is a sorted
list built once when the crate loads. The picks are the ones the whole table gave, with the same trim (the best 40 on the
discs and the best 40 of the rest); D19 (Nov 1) lifted that cut. With the 2,327-track library crate the booth
loads in about five seconds and holds about half a gigabyte, where it took two minutes and 4.3 GB before. And the join
view's two lanes, the end of the playing song over the start of the next, come from the crate's loudness per bar, one
flat step a bar, cut by the beat and bar lines the view already draws. Since Oct 31 the crate's whole-song wave and the lanes measure each bar against the song's loudest bar, as the bundled waves do, then remove the quiet floor and apply the same curve, so a lane is the whole-song wave zoomed in and loud masters keep their shape; the bundled sprint data's lanes are finer (an
eighth of a beat, from the audio) and stay as they are. No crate field is added (crate v1 stays frozen). Commits cdeb021,
6abc147 and fc51030.

### D19. One ranked list with a Shuffle dial; the shortlist is the top tenth of the library (Nov 1)
The decision, in the owner's words: "Let's have the top 10 be top 10% of the songs BUT I want a good amount of
randomization - this should be customizable (slider?) and really there should just be a rank and the order of which
should be based on the settings the DJ chooses." So the booth's picks are one ranked list. Every song in the crate is
scored from the playing song; the 40-song cut on a song's pick list is gone. The word "trim" is retired for it, since
trim is a mixer's gain knob: the songs kept for the screen are the song's **shortlist**, the best tenth of the library
by score after the filters (one cut per song, nothing played in the last 12, the disc chips), never fewer than 10. The
**Shuffle** dial (a slider from 0 to 100 percent, next to Simple / Full) sets the order: each song's place blends its
score with a dice roll, so at 0 the shortlist is in pure score order, at 100 it is a fair shuffle, and in between the
better songs tend to stay near the top. Full shows the first 10, Simple the first 5, the rest of the shortlist sits
under More. A pinned song stays first. The old Easy and Harder sections and their sampler are gone; what made a pick
"harder" (half time, a tempo change, another disc, another era, a deep cut, now the lower half of the shortlist) stays
as a small label on the row. The tenth and the floor of 10 are the owner's numbers, and the blend is first principles;
nothing is fitted to a crate. From the first-night analysis (docs/research/s-first-night.md): with the dial at 0 and
ten rows, the song the DJ played next would have been on the first screen in 12 of the 43 clean changes (ranks 1 to 10),
where the sampled screen gave about 5. No crate field is added. Commit f00e3e1.
Later the same day, in the owner's words: "Let's have more run past the shortlist. We should also add a search to
more." So More no longer stops at the shortlist: after the rest of the shortlist (still in the dial's order) comes
every other song the filters leave, in plain score order, best first, with no dice. A thin line labelled "rest of
the crate, by score" marks where the shortlist ends. A search field at the top of More narrows its rows to songs
whose title or artist contains the typed text (ignoring case and accents), keeping their order; the picks above are
not filtered, and the search is forgotten when the app closes. Commit ba1bdfd.

### D20. Discs and folders are organised in Desk, on every desk version (Nov 1)
The decision, in the owner's words, asked about disc and folder labels in Desk: "yes we will need to be able to
organize in all three versions". The three versions are Deckie Desk on the Mac now and on Windows and Linux later
(D14: Swift everywhere for Deckie's own code). So the organising operations live in the shared core (DeckieCrate's
`Discs.swift`: the plan of discs, folders and tracks; place, remove, move; rename and delete a disc or a folder), and
every desk gets the same behaviour; Desk on the Mac has the window for it now (the Discs panel, a third column). A
disc is the set of songs a DJ takes to a night; its folders are the groups inside it, in the order the DJ's player
shows them; each folder's songs are numbered 1 to n with no gaps after every change. A track sits in at most one
folder of one disc. The crate carries the labels in its existing fields (`ident.disc`, `ident.folder`,
`ident.track`); crate v1 stays frozen and no field is added. The booth reads them for its CDs tab (discs, folders
and songs in order), its filter chips (one chip per disc, named after it, every disc on by default) and its picks
(songs on a disc are favoured, and a pick on another disc says "to <disc>"). The bundled sprint data still reads
CD1 and CD2. Commit 4eac5da.

### D21. Crate is the songs, crate file is what Desk writes from them (Nov 11)
The decision, in the owner's words: "we have been using crate to mean both the music and the crate file and we
should separate them", and "Why don't we just call it the crate and the crate file". Three words, each with one
meaning. The **library** is all the music a DJ owns. A **crate** is a group of songs from it, the way DJs already
say it, and can be the whole library. A **crate file** is the `.deckiecrate` that Deckie Desk writes from a crate
and the booth carries: tempo, key, bars, style and the fingerprints for recognition, never audio. The sentence that
teaches it: "Desk reads your crate and writes a crate file." "Crate index" was weighed and passed over: an index only
points at things, and it is our word, not a DJ's. Nothing in the format or the code is renamed; "crate v1" stays the
name of the file format. The vocabulary, the voice notes and the living product docs follow from today; research
letters and the history folder keep the words they were written with, where "crate" often means the file.

### D22. The tagline is "Know Your Crate", and the three names are public (Nov 12)
The decision, in the owner's words: "I like "Know Your Crate" as the final tagline. We can test this with DJs but
for now." So it is the tagline on the site, in the film and in the page's title, until DJs have been asked. The
names a DJ sees: **Deckie** is the whole product, **Deckie Desk** is the Mac app, **Deckie Booth** is the iPad app.
Three more lines were chosen the same day and are used as written: "Know the beat. Nail the mix." (the owner's:
"Lets simplify it to - Know the beat. Nail the mix."), "Nail the mix." alone as the home page's hero line, and "Your
music. Your mix." where privacy is said. Public copy does not say "AI", not even to deny it; the owner on an early
caption: ""not an AI DJ" begs the question if it is". The name itself is "fine for now": it is not registered and
not in an app store, so D9 (the name and the DECKEE mark) stays open and does not hold up the coming-soon site.

### D23. A public site: a home page, a dictionary and a film (Nov 12)
Deckie has a public face at https://deckie.io, published Nov 12, 2026. Its source is `site/`; how it is built and
published is `site/README.md`; the reasons are letter V.

- **The home page** is short, after a product page: what the booth does, what Deckie isn't, how Desk prepares a
  crate file, the dictionary, a short about with a list of facts, and the ask. "What it isn't" stays because it
  answers a DJ's worries directly: it doesn't mix for you, doesn't beatmatch for you, doesn't take your music,
  doesn't replace your DJ software.
- **The dictionary is public**, for anyone and for DJs: "Every DJ starts somewhere", "DJ speak, in plain words."
  Each word leads with its plain meaning, then how it is used on the decks. What Deckie does with the word is shown
  last and quietest; the owner: ""what deckie does with it" is important for us and maybe for the user but is much
  less important than the first two". This replaces the earlier rule that the Deckie register stays in our
  documents. Of the vocabulary's 155 terms, 91 are public; the rest are our own working words and stay on the
  internal page. Which 91, and the topics they are filed under, were chosen in the build and have not been reviewed
  word by word by the owner; they stand as published until he changes them.
- **The film** is 76 seconds, words on screen, no voice, with music made for it. It keeps its own look and is not
  re-rendered when the site's look changes.
- **The look** of the site comes from Deckie Booth's Simple view, so the site and the app read as one thing.
- **The credit** is "Made by Christopher Shannon and App Hold Media", linked to apphold.media. It is the one place
  public material names a person. "Help us beta test" opens an email to info@apphold.media.
- **What the site never shows**: a real song, artist or playlist, any DJ's music, or anyone but the credit. Screens
  show a demo crate file with invented names.

### D24. The same song is the same recording; every copy keeps its place (Nov 13)
This settles the open step in the note on D19 below. The decision, in the owner's words, on the three ways letter U
laid out: "I think 2 is the best option but what if a song is on multiple disks or albums. Even in multiple file
folders. The idea is that deckie will tell you where the song is too." And on the answer that follows: "Great I
agree with this".

- **Two entries are the same song only when they are the same recording.** Nothing is folded by title. A remix, an
  edit or a live version is its own song, with its own row and its own score.
- **Desk finds the copies.** It already makes a fingerprint for every song; entries whose audio is the same
  recording get the same key in the crate file's existing field (`cut_key`). Crate v1 stays frozen; no field is
  added.
- **Folding changes what is shown, never what is kept.** Every copy stays its own entry in the crate file with its
  own disc, folder and track. The booth shows one row for the song and reads the places from every copy behind it.
- **The booth says every place the song lives.** One place leads and the others follow as "also on". The place
  that leads is on the disc the playing song is on; failing that, the first disc in the DJ's order.
- **Recognition names the song once**, whichever copy it hears, and never treats a move between two copies as a
  song change.
- **One file on several discs** was part of this decision in the morning and was withdrawn the same day: see D25.

### Note on D24 (Nov 13): built, except one file on several discs
Built the same day (commits 623e039 to 4778ed9): the shared rule (`SameSong` in the core), Desk's "Find copies",
and the booth's single row with "also on" for every other place. Desk tells copies apart from versions with a
published audio fingerprint (Haitsma and Kalker, 2002) and two conditions: the sound lasts the same within one
second, and every three-second block of the whole song matches. Tested on generated songs only: a copy in another
format matched, and an edit, a remix, a live take and an extended mix did not.

Not built, and no longer wanted in this version: one file on several discs. Crate v1 does not allow two entries
for one file, because an entry's id is taken from the file itself and ids must be unique. D25 removes the need.

### D25. Desk reads discs; it does not manage them, in this version (Nov 13)
The decision, in the owner's words, on the hand-built discs of D20: "What you are talking about makes it sound more
like Deckie Desk is library management", and on reading in place of managing: "I agree with it for now. I could see
a world where a CDJ (like Mike) would use this to organize their crate. And I think it will eventually have to work
like that. but in this version we should keep it as read only."

- **Desk reads a disc, a drive or a folder as it is.** Its name, its folders and the order of its songs come from
  the thing itself. The DJ does not rebuild in Desk what already exists in their hands.
- **A song on two discs is two files**, one on each, so D24 already shows both places. Nothing in the crate file
  format has to change, and "one file on several discs" is dropped.
- **The Discs panel stays for corrections**: a name, or an order Desk read wrongly. It is no longer how discs are
  made. This rewords D20: the shared operations stay in the core for every desk, but reading is the main route.
- **Organising in Desk is expected later.** When it comes it will be an addition to the crate file format, not a
  change to what is there: readers already ignore fields they do not know, so files written today will still open.
  Its shape is not designed now, because it depends on things not yet seen (playlists on a stick, one song in
  several of them, whether order belongs to the disc or to a list).

### D26. A source is shown by its own name (Nov 13)
The decision, in the owner's words: "Yah lets say its own name where it read from. it is kind of "source: stick 3"
we just use the name of the source right?" Asked first whether "disc" was the right word for a CD, a jump drive and
an album alike.

- **A source is the thing a DJ holds that the songs were read from**: a burned CD, a USB stick, an SD card, a
  record. "Source" is our word for it, in documents and in the dictionary.
- **On screen a source is shown by its own name**, the one it already has ("Friday night", "Stick 3"). A DJ does
  not have to learn a word of ours, and "disc" and "CDs" leave the screen.
- **A place has three levels**: the source, the group inside it (a folder, a playlist, a record's side), and the
  song's number there. An album is not another kind: it is a source when it is a record or a CD, and a folder
  otherwise.
- **Music that is only on the Mac has no source.** Its place is its folder.
- **In the crate file the field keeps its name**, `disc`. Crate v1 stays frozen and no DJ sees it.

Still to ask working DJs: whether "source" is said out loud or is only the word on the player's button.

### D27. A song can carry more than one place: the first addition to crate v1 (Nov 13)
The decision, in the owner's words: "Yes lets update the file format."

What made it necessary. D25 said a song on two discs is two files, so both places show. That holds only when the
two files differ. The same file burned onto two discs, or copied unchanged from the Mac onto a stick, is the same
bytes, and an entry's id is made from the file's bytes, so the crate file holds one entry and the second place was
dropped. That is likely the common case, and it made "Deckie tells you where the song is" wrong for a DJ with
several discs.

- **An entry keeps its own place and may list others.** Each other place is a source, a folder and a number, the
  same three parts as the entry's own.
- **It is an addition.** No existing field changes name or meaning. A crate file written before today reads as it
  did, and a booth that does not know the new field still opens a new crate file and shows the entry's own place.
- **Desk fills it when it reads.** A file it has already read, found again somewhere else, adds a place and is no
  longer listed as a duplicate.
- **The booth treats these places like copies** (D24): one row, one place leading by the same rule, the others as
  "also on", and a song is allowed by the filter when any of its places is.
- **Organising in Desk is still not in this version** (D25). This is reading only.

### D28. Desk keeps its crates; a crate file is made on the way out (Nov 13)
The decisions, in the owner's words, on the open questions of `docs/product/desk.md`:

- Where the crate file lives: "shouldn't it live in the application or library and be exportable? Not everyon's
  music set up is going to be the same... what if someone messes with it thinking its a music file?" So Desk keeps
  its crates in the app's own storage and never asks where to save. A crate file appears when the DJ sends or
  exports one, and one made elsewhere is imported as a copy.
- One crate or several: "it should default to the most recent one but that should be like a "add new crate" and or
  drop down when adding sources? We will need to resolve which crate you are adding to at some point. Why not now."
  So a DJ can have several crates, Desk opens on the most recent, the window says which crate is showing with a menu
  to switch and "New crate", and Add music adds to the crate that is showing.
- Saving: "Save as it goes with the ability to undo". No Save button and no "Unsaved changes".
- The words: "Words we need to do a whole audit of separately and they will need to match all touchpoints so lets
  have those be placeholders. We can build out a copy and design reference file with each variable later." So the
  words on screen are placeholders until that audit, and each app keeps its words in one list, by name, so the audit
  changes one file.

This fits D21: the DJ works with crates, and the crate file is what Desk writes from one. It also fits D25: several
crates are groups of songs that were read, not a library being managed.

### D29. A PC version is wanted, and the fix is in the core, not on the iPad (Nov 13)
The decision, in the owner's words: "Mike has a PC and the DJ community is pretty split. Most DJs who would be
interested in this might have lower budgets and use a PC so I would like to see a PC version working." Offered the
route where a PC writes the crate file without key and fingerprints and the iPad adds them: "The ipad can be an
option but shouldn't be the fix. We are now asking them to provide the music twice when the ipad could just do all
of it - but that would take a while. The better solution is to just fix the deckie desk core."

- **A crate file made on a PC must be complete**: song recognition and key included, with no second pass on
  another device.
- **So Deckie's own core has to do the two things it borrows from Apple today**: recognise a song from the room
  (ShazamKit now) and read its key well enough to show (Apple's framework now; D16's bar still holds).
- **The iPad finishing a crate file may exist as an option**, never as the answer.
- What is already the same on every platform: tempo, bars, style and vocals (the engine of D11 and D14).

The evidence to start from: letter H (recognition across the pitch fader, and its section on a fingerprint of our
own), letter L (what does and does not carry off Apple's platforms), letters R and T (the key reader and the ways
to a better one).

### D30. Take what is already on the computer; look up names and facts only when asked (Nov 13)
From research letters W and X, with the owner's "I agree with all this" on letter X's recommendations and, on
lookups: "For 6 I meant getting song names from lookup. Or general song DNA data."

- **Desk reads the keys a DJ's own software already wrote** on the same computer (rekordbox, Serato, Traktor,
  Engine DJ, VirtualDJ, Mixed In Key), and shows where each key came from. Nothing leaves the computer. This is
  what makes a crate file made on a PC complete for most DJs now (D29), and it widens D16's "the DJ's own key from
  tags or a rekordbox import" to every DJ program.
- **A mode can be open.** Where the music does not say major or minor, Deckie's own reader may answer with the home
  note and an open mode instead of guessing. To be measured by the key trial before it ships.
- **Key and tempo are not looked up by a song's name.** The keys on those services are machine readings no better
  than Deckie's own, they miss edits and bootlegs, and a lookup would send a list of what a DJ owns.
- **Names and facts about a song may be looked up, when the DJ asks.** A song that arrives with no name, or facts
  such as artist, release and year, can come from a lookup that the DJ starts in Desk. It is never automatic. Before
  it is built: the services' terms for a paid app, exactly what each sends, and the public privacy line reworded so
  it stays true. Names found on the computer come first (tags, file names, folders, tracklist files, a DJ program's
  library, a named copy of the same recording).
- **What D16's bar measures** is the owner's to rule on once the key trial reports all four measures: exact on each
  half as now, the mean of the halves, within one step on the wheel, or how often a shown key is right.

### Note on D30 and D16 (Nov 13): Deckie's own key reader has to stand on its own
The owner, the same day, on reading keys from DJ programs: "Most starting DJs don't have these programs. Mike for
example doesn't. Our method will still need to work as well as competitors or better and fail gracefully. It is
just a tag for the song and the waveform. Just info for the DJ. If we can get it reliably we use it and add it if
not we skip it. I would refer we have it."

- **Keys from a DJ's own software are a help, not the answer.** Many DJs have none of those programs. Deckie's own
  reader is the main route on a computer without Apple's framework.
- **The target is the tools DJs already use**: as good as them or better, on music it has not seen.
- **It fails quietly.** A key is shown when the reader is sure and left off when it is not. A missing key is
  acceptable; a wrong one shown with confidence is not. This is D16's "no key is better than a wrong key", applied
  song by song instead of to the whole reader.
- **A key is information for the DJ**: a tag on the song and its wave. Having it is preferred.

This points the bar toward "how often a shown key is right, and how many songs get one", against the competitors'
figures. The owner confirms the measure and the numbers when the key trial reports.

### D31. A folder is a source too (Nov 13)
The decision, in the owner's words: "I think a folder counts as a source. Whatever the top level folder that was
selected. We should say that in the UI." This replaces D26's line that music only on the Mac has no source.

- **Whatever the DJ adds is a source**: a CD, a drive, or a folder. A folder's source is the top folder the DJ chose,
  named after it, and the folders inside it are its groups.
- **Desk says so** where the DJ chooses the folder and where sources are listed.
- Every song therefore has a place with a source. The booth's "Folders" section for songs with no source remains
  only for crate files made before this.

### D32. Desk on Windows and Linux: web pages in a window of Desk's own, with a Swift shell (Nov 13)
From research letter Z. The decision, in the owner's words: "I agree with approach 2 with swift. We already built in
Swift. If we have to build in rust we should rebuild the whole thing on it. Not swift to rust to web."

- **The window's contents are web pages** in the look the site and the booth already share. No Deckie logic lives
  in them: they show what the engine says and send what the DJ does.
- **The window itself is a small shell written in Swift** around the system's own web view (WebView2 on Windows,
  WebKitGTK on Linux). It gives Desk its own window and icon, real folder choosers and drag and drop.
- **The engine is a separate Swift program** the shell talks to in a written, versioned set of messages, so it can
  be tested with no window on all three systems.
- **No Rust.** If the Swift shell cannot be made to work, that is reported and the owner decides; a mixed stack is
  not the fallback.
- **The Mac keeps its own window** for now (letter Z, question 5).
- **Native later is an open door, not a plan.** What makes it cheap is decided now: the messages, no logic in the
  interface, and one list of words for Desk on every computer.
- The same flow as the Mac: open Deckie Desk, add music, watch it build, send the crate file to the iPad.

### Note on D30 (Nov 13): naming is route A plus one explicit lookup by sound
From research letter AA. The owner: "My thought is A plus another method. It will be via "look up song via ____"
and an explicit different use than the rest of the app. It could even just direct you to and batch upload or
something. We can figure that out later. There is a real use case for a CD someone had that is a bunch of songs
with no labels. Even if it only gets some of them right. I have Picard music brainz and it does that."

- **Route A is built first**: everything that names a song with nothing leaving the computer, including reading a
  burned music CD's own titles, on every computer.
- **One lookup by sound is wanted beside it**, for the disc of songs with no labels. It is named for the service it
  uses ("Look up song via ..."), is plainly a different kind of step from the rest of the app, and is never
  automatic. Getting some of the songs right is enough to be worth having.
- **Which service, and how it is offered** (inside Desk, or by sending the DJ to another tool with a batch), is
  not decided. The services' terms and prices are in letter AA.

### D33. The key reader: the bar stays, the three-answer reader ships now, and Desk can play a song to name it (Nov 13)
From the key trial (letter X2, merged Nov 13) and the naming research (letter AA). The owner's answers:

- **The bar stays as written** (D16: exact within five points of Apple on the major and the minor half). "I'd like
  to keep the bar going. It sounds like we can meet it." The trial's trained model met it on artists it had never
  heard, for evaluation only; it cannot ship because of what it learned from.
- **The reader with nothing trained ships now**, giving three answers: a key when its two readings agree, the home
  note with the mode left open when only the home note agrees, and "not sure" otherwise. "Yes let's ship." This is
  the "shown when sure, left off when not" of the note on D30 and D16. On music it had not seen it shows a key on
  about seven songs in ten and is right on about two in three of those, the level of the tools DJs pay for on the
  songs it shows.
- **Training data for a model that can ship**: the owner asked whether a public set can be used before anything
  is commissioned. To be answered with evidence: sets whose licences allow shipped weights under D15.
- **Apple Lossless and AAC files on Windows whose lead-in is stated nowhere are accepted**, with the song's start
  marked uncertain, not refused.
- **Desk gets a Listen control with a scrub bar**, to name a song by ear: "Yes listen. Let's add a scrub". This
  changes one line of `docs/product/desk.md`: Desk plays a song so the DJ can name it; it still does not mix or
  edit.

### Note on D33 (Nov 14): Desk does not keep a copy of a disc's music
The first build of reading a music CD copied the disc's audio into Desk's own storage, about 750 MB a disc, so that
Listen would work with the disc out of the drive. The owner: "The crate file shouldn't rip the music. Its just the
crate file."

- **Desk reads a disc's music to work it out, and keeps none of it.** Whatever it has to hold while a song is
  being read is removed as soon as that song is done.
- **Listening to a song from a disc needs the disc in the drive**, as listening to a song on a stick needs the
  stick. Desk says so in plain words.
- This holds for every source. Desk never was a way to copy music, and it is not one now.

### D34. Whatever a song's file says about it goes into the crate file (Nov 14)
The decision, in the owner's words, asked whether the release, label, year and genre Desk finds should stay in Desk
or travel to the booth: "Let's port and save whatever info the song crate file has. if the user wants to add a
bunch of genre info or release info it should go to the app and maybe show in the mix list. how we display we can
refine later but whatever info it has should be sent." And: "As we figure out the "song name and info" part of the
song id (via another service) we should fold that into these other fields. If we have the track name(s) there may
be a free way to find out and fill genre for example."

- **Every fact a song's file carries is read and written into the crate file**: release, year, label, genre,
  numbers on the release, and the rest of what its tags say. The booth receives all of it.
- **A DJ can add to it and correct it in Desk**, and what they enter goes to the booth the same way.
- **Each fact says where it came from** (the file, the disc, the DJ, later a lookup), so a lookup fills the same
  fields and never a separate set, and a DJ's own entry is never overwritten.
- **How the booth shows these facts is to be refined.** Sending them is decided; display is not.
- **This is an addition to crate v1** (the next after D27's places): no existing field changes name or meaning.
- **Filling genre and the like from a song's name** belongs to the lookup that the DJ asks for (note on D30); the
  sources and their terms are in letter AA.

### D35. Recognising what is playing: we go for a fingerprint of our own (Nov 14)
From the recognition trial (letter W2, merged Nov 14). The trial's fingerprint names the right song across the
whole pitch fader from clean sound and reads the fader, on any computer, where Apple's tool stops at about 4
percent; it falls behind Apple's in loud noise, and it holds too much in memory for an iPad. The owner: "We seem
very close on our own work. I think we try to get there on our fingerprint."

- **The aim is one recogniser of Deckie's own**, in Desk on every computer and in the booth, not Apple's tool with
  ours beside it.
- **Noise first, by learning from how other fingerprints work.** The owner: "We are using only loudest which would
  cause problems in rooms where there is a lot of noise or distortion from the speakers."
- **Speed is good enough** as long as a song is named within a few seconds of listening: "The speed is fine. as long
  as we get there in a few seconds. Previously it took almost 8-10 seconds on the ipad."
- **Size is the large problem** (what the booth must hold in memory to match). Two ways, in this order: make it
  smaller and see how small it can go while still working; then, if needed, split a crate so the booth holds only
  part of it at a time.
- **The real-room test is the recording of the Oct 24 set**, made by the booth's own microphone, with the booth's
  log of what it named and when. It is run on the owner's Mac only; the recording and his music never leave it and
  are never public, and nothing is fitted to them.
- Nothing ships from the trial until it has passed that test and a test on the owner's whole library.

### D36. Home note, covers, a lookup through MusicBrainz, and every value a variable (Nov 14)
The owner's answers to the open list of Nov 14.

- **The key reader's third answer is accepted into the crate file**, as the addition proposed with D33 (the home
  note written when the mode is left open). On screen it is called the **home note**; "home note, mode open" was
  "clunky": "maybe just home note?"
- **Covers go into the crate file**: "lets add them". A small picture for each release, stored once, as an
  addition. How the booth shows them waits for the design pass.
- **"Look up songs via MusicBrainz" is built**: "lets build it. I like MusicBrainz. They are open source and we can
  start there. We should test on our library." It is the lookup the note on D30 describes: asked for by the DJ,
  never automatic, plainly a different kind of step, and it fills the same facts as everything else (D34) without
  overwriting a DJ's own entry. It is the first thing in Deckie that uses the network; the public privacy line is
  reworded before it reaches anyone outside.
- **Deckie Desk is packaged for Windows once the core is complete**, not before.
- **TestFlight waits** until more of the core is settled. The bundle id waits with it.
- **The copy audit and the design audit are two separate passes, later.** Until then: "Lets just tag all values as
  variables so we can change them later." Every word and every design value (colours, sizes, spacing, type) in
  Desk's two windows and in the booth is a named variable in one place for each app. The Inter font in the Windows
  and Linux window is a question for the design pass.

### D37. The run screen shows what Desk is doing, and is worth watching (Nov 14)
The owner, on the screen a DJ watches while Desk reads their music: "The loader needs more visual interest. Some
quite sayings like AI does, Some visuals (waveforms) some representations of what is happening and some fun
moments."

- **The run screen draws what is really happening**: each song's own wave as it is read, what Desk found in it,
  and the crate filling up. Nothing on it is decoration that pretends to be progress.
- **Quiet sayings** change as it works, in the voice of a DJ friend, tied to the step Desk is on or to something
  true it just found.
- **Fun moments** mark real things: a round number of songs, an hour of music read, every key on the wheel found.
- **The plain facts stay**: how many songs are done, how long is left, and that it can be left to run. Reduced
  motion and screen readers get the plain version.
- The sayings are words like any others: placeholders in the one word list until the copy audit.

### Note on D35 (Nov 14, morning): faster to a name, and the song coming in
After the recogniser was finished and run on the recorded party set (letters W3 and W4), the owner on how long a
name takes: "8 seconds is kind of a long time. What's the distribution? Would like songs to be locked by 5ish. Not
a hard rule." And: "I just think it's a little slow at recognizing which is its core function."

- **Naming the song quickly is the recogniser's core job**, and it is to get faster.
- **No target number yet.** "I'd rather know where the distribution is first then give it a 5sec target." The spread
  of times to a name is measured first, by kind of change (a hard cut, a blend) and by how loud the room is, along
  with what more size buys, second by second; the target is set from that.
- **Size may rise to buy speed.** The booth's own memory for a crate is small, and "we could probably make it even
  a little larger if it helps on our other metrics." What grows is the index the booth builds and keeps on the
  iPad; the fingerprint in the crate file stays as it is.
- **The booth switches sooner.** Its wait before changing the song on screen was written for Apple's recogniser;
  when Deckie's is sure, the wait comes down to about a second. (The owner's yes.)
- **The song coming in is shown.** In a blend the recogniser reports the song it hears under the one playing, and
  the booth shows it as coming in before it switches: "I like that. Let's build it in. If we want to remove it
  later as part of the UI (like in simplify mode) we can."
- **Both recognisers at once is a test setting**, for judging the two on one night. A crate file made on a Mac
  carries both kinds of fingerprint until Deckie's has been judged on a real set; then Apple's can go.

### D38. Deckie's own key reader ships: its trained file is published (Nov 14)
From the key work of Nov 13 and 14 (letters X2, X3, X4). The owner: "Yes we can publish. Though I think it will be
updated shortly, correct?"

- **The learned key reader ships.** It was trained only on recordings whose licences allow it, runs in plain Swift
  on every system, and gives the three answers of D33 and D36: a key, the home note, or not sure. Its file is
  published the way the engine's other models are, with a version of its own, and replaced by a newer file when a
  retrain beats it by a rule fixed beforehand. The untrained reader stays as the fallback.
- **What it learned from is disclosed** (D15), with the credits its sources' licences ask for.
- **A slight lean toward minor is the owner's inclination**, taken from a source that is not the test collection
  and fixed before any test score is looked at; which source, and whether it applies only to dance and electronic
  songs, is chosen from measurements still to come.
- **The bar of D16 is to be reworded.** It was written before it was known that Apple's reader leans toward minor,
  and as written it rewards that lean. The new wording is to judge the keys Deckie shows by whether they mix
  correctly, against Apple's on the same songs; the exact sentence is chosen when the numbers are in.
- "Right" in the key tables means the home note and the mode both. The error that harms a mix is the right home
  note with the wrong mode; the home-note answer exists so that Deckie does not guess it.
- The owner's reading of where this stands: "Overall it feels like we are there or very close."

### Note on D19 (Nov 1): versions of a song stay separate rows
Christopher, on two remixes of one song both showing in the picks: "we shouldn't merge them unless they are the same
songs. DJs often have a bunch of versions of the same song". So the booth folds together only copies of the same
recording (the crate's cut), and a remix, an edit or another version of a song is its own row with its own score and
join. Correction the same day, from the top-down review (letter U): the code does not do this yet. The booth folds
rows by title with anything in brackets removed, so remixes named in brackets merge into one row, and Desk never
fills the crate's cut key, so nothing folds by recording. Settling what counts as the same song, in one place for the
picks and for recognition, is the open step; letter U lays out the ways.

### Note on D3 (Oct 26, from the community research): privacy covers taste, not only audio
DJs' fear is "I'm not helping train ai for free": that their choices become someone else's product. So D3 extends
to history, cues, saved pairs and learned preferences: all of it stays with the DJ, Deckie says who benefits from
learning (only the DJ), and the DJ can see, export and delete it. Spec 3.

### Note on D3 (Oct 28): dependencies that report home
ONNX Runtime's official builds send usage events to Microsoft: its `docs/Privacy.md` says telemetry is "turned ON by
default in the official builds", over HTTPS through Microsoft's 1DS client on Linux and macOS and through the
operating system's event tracing on Windows. Counts and timings, never audio, but it is a network call during
analysis, which the charter forbids, and it would make the "Data Not Collected" line (P8) false. Found by the PC and
Linux session. Decided: development builds, CI and the bench may use the official binaries with the
`ORT_DISABLE_TELEMETRY=1` switch set inside the process before the library loads, checked by a test; no build that
reaches a user carries a reporting client, so before the first TestFlight or PC build ONNX Runtime is built by us
with its `--no_telemetry` flag, which leaves the client out, and pinned like any dependency; a release test scans
each shipped library for the client's endpoint and symbols, so the promise is checked rather than assumed. The client's
own dependencies (curl, mbedTLS, SQLite) leave with it; curl's MIT-style licence is not added to the allowlist and is
recorded as present in development builds only. General rule: a dependency with a reporting client is built without
it or not used. Windows detail, same evening: ONNX Runtime built without telemetry never registers its
event-tracing provider, but the provider's name stays in the library as a string, so the Windows scan reports that one
marker as "present, never registered", with the registration path documented, and fails on every other marker as
the Linux and Mac scans do; events through that path reach nothing unless the user runs a trace session, and the
build never registers. A patched build that removes the definition was judged not worth its upkeep.

### Note on D5 (Oct 26): Mike's data is a special case
Mike's party set was curated by Christopher and held music Mike does not usually play, so the sprint's data describes a
DJ with an unfamiliar crate, and his 16 percent pitch range is not typical. That is itself a use case (new DJs, a
themed party, a new toy). Christopher will supply a recording of the set Mike actually played as the real reference.

### Note on D5 (Oct 29, Christopher): what in the sprint's data is known, and what the early version decided
The sprint's data (pool.json, candidates.json, discs_def.json, library_probe.json under the music folder's
`_pool build/`) is two kinds of thing, and a test of Deckie must keep them apart. Known facts, usable as an answer
key: a track's name and artist, the compilation or album it came from and its release year (the compilations' and
discography's own tags; the disc map). Decided by the early version of the analysis, not confirmed, usable only as
"agrees with the early version": the BPMs (including the hand-set overrides and the folded ones), keys, the era and
kind labels, the Halloween flag and the version groupings. The lab's 373 feature files are the same second kind: a
parity yardstick for the engine, not truth. Any sheet that scores Deckie against this data says which column is
which.

### Note on D5 (Oct 28, Christopher): tuning is library-blind
The 373-track yardstick is one DJ's crate, mostly house and pop, and Deckie must work for any DJ's music. So no
parameter of the analysis (key profiles and vote rules, vocal thresholds, section rules, anything) is fitted to
that set: values come from the literature or first principles with their source named; where a value must be chosen
by measurement, it is chosen on one half of the set and reported on the other, split by kind (era, style, folder)
rather than at random; results are reported per bucket as well as overall, and a gain that lives in one bucket is a
flag, not a win. Outside key-annotated data sets are the real test and are listed with licence and size before any
is fetched. Applies to research R (key parity) and to the vocal listening set. Research R (Oct 29) ran under it: a whitened
HPCP with Faraldo's three published profiles averaged reaches 83.3 percent exact against the lab's confident keys
(the engine shipped 74.6; held-out split 83.2; against Apple 70.4 from 63.4) with the gain in every era, style and
tempo bucket; its few choices were made on the 90s and 2000s and reported on the other eras. The PC and Linux
session ports it, with the profile values re-sourced from the papers rather than Essentia's AGPL code. The outside test
ran on Oct 29 with Christopher's yes (GiantSteps-MTG-key, 1,486 EDM clips, 85 percent minor, annotations CC BY-SA 4.0,
audio from Zenodo for internal evaluation only; letter R's last section): the method is exact on 50 percent of the
high-confidence clips (MIREX-weighted 0.61), the shipped baseline 48; the gain is all in major keys (+12 points) and
minor keys are 2.5 points worse; the main error is the wrong mode on the right note (44 percent of minor clips read
as major). That puts our own key reader near the free KeyFinder and well below rekordbox and Mixed In Key on
unfamiliar dance music; the crate's 83 percent flatters it. Apple's framework on the same clips (the iOS 27 simulator harness, all 1,275, finished Oct 30, 00:49;
`mixer/key_outside_apple.py`; letter R, "Apple's framework on the outside set"): exact 65.2 percent against ours
47.6 on the 1,270 clips it read (a first pass over 214 clips had shown 74.3 against 50.0). The two lean opposite
ways on the mode: Apple reads 75.6 percent of the minor clips and 41.5 of the major exactly, ours 41.9 and 60.6, and
Apple calls half of the major-key clips minor. Where they agree (604 clips) the key is right three times in four.
D16's bar (within five points of Apple on each half) is met on the major half and missed on the minor half by 34
points. Overtones taken out of the chroma (Oct 30; `mixer/key_overtones.py`; letter R, "Overtones taken out of the chroma"):
exact 55.4 from 47.4 on all 1,275 with either the harmonic discount or NNLS note transcription, held on the even ids;
the home note 72.2 (transcription) against 68.8, within chance; beside Apple on the 1,270: exact 55.6 against 65.2, home
note 72.4 against 76.4. So Apple's framework reads key on Mac and iPad, and on Windows
and Linux ours is the known gap, parked under the Oct 29 plateau. A Codex pass on what DJs say about key tools is briefed in
`docs/research/briefs/codex-key-reddit.md`.

## Proposed on Oct 26, 2026, from the research (awaiting Christopher)

Each of these follows from a research report and is written into spec v0.2 as "proposed". None is decided until
Christopher says so; a yes moves it up into the dated decisions above.

- **P1. Accepted as D11.**
- **P2. YouTube is not a source for automated mapping; user-shared links may be resolved and shown, never stored.**
  The deeper look (track B addendum) checked the scrapers, the analytics vendors, the other catalogues and the
  link-holding databases. Only API clients, link holders and the user's own link survive the terms. MusicBrainz's
  CC0 URL relationships are the legitimate holder of YouTube links per recording.
- **P3. Superseded by D11:** no hard OS 27 floor; graceful fallback levels instead. The iPad Air 4 check stands.
- **P4. Regenerate Christopher's crate with the shipped engine before any TestFlight build.** The current features were
  produced with non-commercial models. Track A (not legal advice).
- **P5. Primary segment: DJs playing open-format on gear that does not know what is loaded.** Narrower than
  "mobile and wedding". Track D.
- **P6. Fingerprint lookups are explicit, per-batch, opt-in, Mac first; never automatic, never from the iPad by
  default.** A lookup discloses the crate, not the music, and that still needs consent under D3. Track B.
- **P7. Claim discipline: Deckie never claims to be the only app that hears the room.** djay and Beatport Track ID
  do. The claim is own crate, offline, pitch, join, learning, tracklist. Track D.
- **P8. Store name "Deckie: DJ Booth Companion", category Music; "Data Not Collected" only if true.** Track D.
- **Open, not proposed:** pricing (track D leans one-time, $39 to $59); the onboarding renderer on device or Mac
  only; an iPhone-only set-recorder SKU.
- **P9. Profiles: one crate, several named preference sets, one active per gig.** Christopher asked whether multiple
  styles mean profiles. Lean: yes, but start with one and never make a new user choose; a new profile is a copy, a
  set upload, or a fresh onboarding chain. Spec 5.6.
- **P10. Identity is self-contained; public lookup is an optional helper, never applied automatically.** Christopher:
  MusicBrainz and Discogs were inaccurate in the sprint, so the DJ edits anyway; can Deckie fingerprint from its own
  analysis and take names from tags? Lean: yes. Content hash plus ShazamKit signature plus an analysis descriptor for
  versions; names from tags with an editor; edits in the crate file. Public data only suggests corrections. The
  sprint's pool needed hand maps for 98 original years and 105 new entries, which is the evidence. Spec 5.4.
- **P11 (interim half built Oct 28: nine signatures per track and the two-match pitch reading are in the Deck app,
  measured in stage 1 results 1f). Recognition across the fader range: shift the microphone, keep one signature per track.** Measured
  (track H): a ShazamKit signature matches within about plus or minus 4 percent of its own speed in every mode.
  Proposed: while listening for a new song, run several ShazamKit sessions in parallel on transformed copies of
  the microphone signal (as is; resampled for vinyl-style plus and minus 8 and 16; time-stretched for tempo-only
  plus and minus 5, 10 and 15), then drop to one stream re-centred on the measured ratio. The crate keeps one
  45 KB signature per track. Offline stand-ins matched 21 to 25 of 25 across plus and minus 16 percent in both
  modes; CPU about 12 percent of one Mac core, to be measured on the iPad. Interim for the next gig: a
  nine-signature catalogue, which matched 25 of 25 everywhere and needs no new code. Also: fix the tempo-only
  pitch reading to a two-match offset fit reported to 0.1 percent in about 16 s, instead of 20 s rounded to 0.5.
  Not now: an own pitch-invariant fingerprint (the proven designs are AGPL or paper-only). Spec 5.3.
- **P12 (narrowed by D13). The beat grid's tempo segment uses the industry's marker shape so export and import are
  clean; the crate itself stays Deckie's richer format.** Christopher
  (Oct 27): a starter DJ's tool should match what they graduate to. Each tempo segment is stored as the same record
  rekordbox's open XML uses for a grid marker, a start time, a BPM, a meter such as 4/4 and the beat of the bar the
  marker sits on, and Serato's Beat Warp Markers express the same thing. Mix-in and mix-out windows and chosen
  start points are expressible as cue points in the same XML. Deckie exports a rekordbox XML of grids, cues, BPM
  and key from the crate, so a DJ's work travels with them, and imports one so an existing DJ's own grids and cues
  are respected rather than redone. Exports go to a file, never into the music files. Key-change markers have no
  industry equivalent and stay Deckie's own. Spec 5.2 and 6.6.
- **P13. The v1 vocal signal is Apple's instrument activity, calibrated against a listening set; a vocal stem
  comes later as an optional pass.** Track J: the framework's vocal activity is a 50 ms series plus a "ranges"
  view that acts as a presence gate; where it disagrees with the lab the framework is right far more often than
  not (instrumentals, songs opening with a sung hook), and at a 0.3 cut 39 percent of tracks get an 8-bar clean
  intro against the lab's 14, which fixes the sprint's short mix windows at no cost. The hole is sampled, chopped
  or vocoded vocals, which read as not vocal; that is a product question about what the vocal slider means before
  it is a model question. Runner-up for the upgrade and for the onboarding stem: HTDemucs (MIT) on the Mac and
  larger iPads. Rejected with licence quotes: Open-Unmix, Spleeter, the RoFormers, PANNs, AST, BEATs, CLAP, the
  Schlüter and Lehner CNNs. Test: a 40-track listening set labelled per bar by Christopher in three classes (sung,
  sampled, none). Spec 5.1 and 6.4.
- **Refinement of D13 (Oct 27): key segments come from Apple's key analysis on windows**, seeded with the song key
  and filtered by the hysteresis rule, not from the lightweight estimator, which stays in the lab as the fallback
  candidate. Stage 1 results section 1e.
- **P14. "Crate from discs" on the Mac: an attended read queue and an unattended analyse-and-name queue.** Track K.
  Audio CDs arrive as the AIFFs macOS exposes plus TOC, CD-Text and ISRCs; MP3 CDs as a file copy; about 4 to 5
  minutes per disc attended, analysis hidden behind reads for audio CDs and about 30 unattended hours per 100 MP3
  discs at today's speed. Naming in the product's order: tags and file names, then a single MusicBrainz disc-id
  request for commercial albums (on request, no audio sent), CD-Text, opt-in AcoustID, else the DJ's own name.
  Home-burned continuous mixes split by the crate's own recognition plus the analysis boundaries. The iPad cannot
  read optical drives; it consumes the crate. YouTube confirmed out for any automated pull. Spec: "Crate from discs".
- **P16. Our own DSP is written once as a Rust core and called from Swift, so Mac, iPad and a Windows or Linux
  builder share it.** Track L: deciding this before stage 2 costs two to three weeks of plumbing; retrofitting later
  costs far more. Apple's framework, ShazamKit and the UI stay in Swift. Christopher's direction on Oct 28: start
  the PC and Linux track now, in a cloud session.
- **P17. Crate-builder platforms, in order:** the Mac app (primary); the iPad building from a USB stick for DJs
  without a Mac (no engine work, interface only); Desk Lite for Windows and Linux after the trials (rekordbox XML
  import first, a second engine for the rest, signatures still from an Apple device); Android booth only on demand.
  Spec 5.7, overview section 5.
- **P16 (decided as D14 on Oct 28 by the spike). Revised by track M: Deckie's own code is written once in Swift, as a plain package with no Apple-only
  framework, and runs on Windows and Linux too; Rust is the runner-up, not the default.** Track M found the shared
  core is small (about 3,000 lines once ported: the DJ DSP, the key estimator, the scoring and the crate format),
  that a Rust core would put a translation layer under every Mac and iPad build now for a Windows builder that P17
  places after the trials, that Swift 6.4 runs on Windows and Linux with a Windows workgroup since Jan 2026, and
  that the bugs that change picks are numeric, which neither compiler catches, so the parity tests against the lab
  are the real safety net. Three-year cost, all inference: Swift everywhere 9 to 12 weeks, a Rust core 13 to 19,
  two separate implementations 18 to 32. Guard before stage 2: a two-week spike porting the grid fit, Camelot and
  score.py to a Swift package that reproduces pairs.json on Linux and on a Windows CI runner; if it fails, Rust.
  Dependency policy (track M): depend on decoders, the FFT, the model runtime, loudness, XML and model weights; own
  the DJ DSP, the key estimator, the scoring and the crate format; platform tools first, then permissive C
  libraries; pin every dependency by version and hash in one DEPENDENCIES.md with a CI licence allowlist; vendor
  small leaf libraries; nothing that runs or downloads code at build time; a quarterly update day with a benchmark
  rerun. Awaiting Christopher.
- **P18. Audio file types a crate can hold, by platform (Oct 28).** What DJs actually own: MP3 from pools and
  rips; WAV, AIFF and FLAC from Beatport, Bandcamp and lossless rips; AAC (.m4a) from iTunes purchases; ALAC
  (Apple Lossless, also .m4a); Ogg Vorbis and Opus rarely; WMA rarely and ageing. Streaming-service offline files
  (Apple Music, Spotify, Tidal) are rights-protected and cannot be read by anyone; Deckie says so plainly and never
  tries. Plan: on every platform, WAV, AIFF, MP3 and FLAC (plain PCM parsers of our own for WAV and AIFF; dr_mp3 and
  dr_flac, public domain, pinned, for the other two); on Mac and iPad, anything the system plays through
  AVFoundation, which adds AAC and ALAC; on Windows, AAC and WMA through Media Foundation, the system's own
  decoder; on Linux, AAC and WMA only through the user's own ffmpeg run as a separate program (P-AAC decision), and
  ALAC through Apple's open-source ALAC decoder (Apache 2.0) if demand appears; Vorbis and Opus through public-domain
  or BSD decoders only if the trials show them. Unsupported files are always reported, counted by extension, never
  skipped silently. Each decoder's leading-sample offset is measured against the lab's and corrected, so beat times
  agree across platforms.
- **P19. The training-data line re-read for the beat model (Oct 28, awaiting Christopher).** The PC and Linux
  session recorded Beat This!'s training sets as the note on D14 asks: fifteen sets, three with non-commercial terms
  on their own pages (ASAP with MAESTRO audio, RWC, Filosax), several of commercial recordings the sets do not
  license at all (Ballroom, Hainsworth, Beatles, JAAH), some with YouTube links, some unstated; the weights are MIT
  from the authors (JKU), who say the user must assess the training files' terms. Read literally, the morning's
  line ("weights whose training data carries a non-commercial licence are out") refuses Beat This!, and no
  permissively licensed beat tracker with clean training terms exists: madmom's models are CC BY-NC-SA, model-free
  trackers are far weaker and find no downbeats, and training our own on licensed data is months of work for a
  worse result. The line is also inconsistent: it refuses sets that say "non-commercial" while accepting
  all-rights-reserved recordings that grant nothing (most sets, YAMNet's YouTube clips, and whatever Apple trained
  its framework on). Proposed re-read: weights ship under the licence their publisher grants; a model is refused when
  the publisher's own terms restrict use (madmom, Essentia, umxl) or when a data owner has objected; the training
  sets and their terms are recorded for every model as disclosure, with a named replacement path; the attorney
  reviews the line with DECKEE. Under this reading Beat This! ships with its record, YAMNet is unchanged, and the
  Spleeter and musicnn refusals of the morning stand on other grounds (YAMNet is the like-for-like signal). The
  alternative is to keep the literal line and fund a clean-data beat tracker as a research track, with the PC and
  Linux engine unable to ship beats until it lands. Until Christopher answers, Beat This! stays in the engine for the
  bench only, which is development.

**Note on D13 and the plateau (Oct 29, 2026, evening): the booth reads a crate.** The iPad app can now run from a
.deckiecrate made by Deckie Desk instead of its bundled data: the tracks and their analysis, the whole-song wave from
the per-bar loudness, the recognition catalogue from the crate's signatures, and the picks. The picks' pair scores are
computed on the iPad with the shared scoring in `core` (the port of the lab's score.py), from the crate's grid, mix
windows, loudness, vocal series and style vector, so the crate carries no pair table and stays as Desk wrote it; any
DJ's crate works the same way. On Christopher's 238-track crate the scores take about 7 s on the simulator and the
first picks match the lab's character (same words, same bands). Not yet from a crate: per-beat waveforms in the join
view (rows show text), pitch-variant signatures, disc labels beyond the file's own folder. This is the step that lets
another DJ test Deckie on their own music: Desk makes the crate, the iPad reads it.
