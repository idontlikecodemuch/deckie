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

### Note on D3 (Oct 26, from the community research): privacy covers taste, not only audio
DJs' fear is "I'm not helping train ai for free": that their choices become someone else's product. So D3 extends
to history, cues, saved pairs and learned preferences: all of it stays with the DJ, Deckie says who benefits from
learning (only the DJ), and the DJ can see, export and delete it. Spec 3.

### Note on D5 (Oct 26): Mike's data is a special case
Mike's party set was curated by Christopher and held music Mike does not usually play, so the sprint's data describes a
DJ with an unfamiliar crate, and his 16 percent pitch range is not typical. That is itself a use case (new DJs, a
themed party, a new toy). Christopher will supply a recording of the set Mike actually played as the real reference.

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
- **P11. Recognition across the fader range: shift the microphone, keep one signature per track.** Measured
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
