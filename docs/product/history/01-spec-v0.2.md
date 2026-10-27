# Deckie product spec, v0.2

Dated Oct 26, 2026. Supersedes v0.1 (`history/01-spec-v0.1.md`). What changed: the four research reports in
`docs/research/` are folded in, so the sections that were marked RESEARCH now have content. Everything that is new
and would change the product is listed as a proposed decision in `00-decisions.md` and waits for Chris. Items marked
[measure] need an experiment before they are relied on; the experiments are in section 7, stage 1.

## 1. Goal

Deckie is a booth companion that listens. Beside decks that do not know the DJ's library, it hears what is playing,
names it from the DJ's own crate, reads the pitch fader, shows what could come next and how to bring it in, learns
how this DJ mixes, and writes the set's timestamped tracklist. The music never leaves the DJ's devices.

## 2. Who it is for

Define the segment by the rig first and the music second.

- Primary: DJs playing open-format on gear that does not know what is loaded. Bar and club residents on house CDJs
  and mixers; mobile and wedding DJs when they are on venue gear or standalone players; vinyl and CD DJs. Mike is the
  type specimen. This is narrower than v0.1's "mobile and wedding": most mobile DJs carry a controller and a laptop,
  and the laptop already knows the track (track D, section 2).
- Secondary: anyone who records sets from hardware and wants a tracklist without typing it. Tracklist and history
  export from any rig is the most frequent ask in the DJ forums (track D, section 3).
- Not for: laptop DJs inside rekordbox or Serato on Pro DJ Link gear. For them only the picks, the join and the
  tracklist are new.

Size: about a quarter of DJs were off the laptop in 2022 and about 10 percent on CDJs or separates in 2021. Niche,
and the one place where every Deckie feature is new rather than one of them.

## 3. Value and differentiator

Positioning statement (April Dunford's shape; evidence in track D, section 1):

For DJs who play on gear that does not know their library and who pick across genres and eras, Deckie is a booth
companion that listens. Unlike Beatport Track ID or Shazam inside djay (global catalogue, nothing about the join),
rekordbox Related Tracks, djay Match or Mixed In Key's DJ Mix mode (need a laptop running that software), or memory
and a crate list, Deckie identifies what is playing from the DJ's own crate, edits, bootlegs, live sets and burned CDs
included, offline; reads the pitch fader; shows what could come next with the join; learns how this DJ mixes; and
writes the tracklist, with the music never leaving the DJ's devices.

Jobs to be done: when I am behind decks that do not know my crate and the floor is up, I want to see which record I
already own fits next and how to bring it in, so that the floor stays full and I leave with the tracklist, without my
music going anywhere.

Claim discipline: two apps do identify through a microphone (djay's Shazam feature; Beatport Track ID, May 2026). The
claim Deckie makes is own crate, offline, pitch readout, join advice, learning, tracklist. Never "nobody else hears
the room".

Privacy, said concretely or not at all: "Your music stays on your iPad. No account. No upload. Works with no signal."

## 4. Principles

See `00-decisions.md`, D3 and the standing principles. Two shape every screen: recommend, never prescribe; the
user's content is theirs. One shapes the learning (track C): a slider is for something the DJ can name and would
change between gigs; learning is for what they do without thinking; learning moves a default, never a setting the DJ
touched, and says what it changed.

## 5. Architecture

### 5.1 One analysis engine on three platforms (proposed, P1)

A Swift package, working name DeckieAnalysis, runs the same analysis on iPhone, iPad and Mac:

- Apple's Music Understanding framework (OS 27, on device, offline) for beats, bars and BPM, key over time,
  sections and phrases, per-instrument activity (vocal, drum, bass, other) and BS.1770 loudness. No model licence.
  Accuracy and timing are unpublished [measure].
- Our own DSP ported from `mixer/analyze.py` and `local_tempo.py`: constant-grid fit and confidence, start and end
  tempo, the 8-bar lattice, mix-in and mix-out windows, fade-out, first and last sound, per-bar low and high bands,
  onset pattern, Camelot mapping, flags.
- Second opinions where the Python stack had them: Beat This! small (MIT, 2M parameters) as a Core ML model when
  the grid fit is doubtful; an own HPCP key vote.
- The Mac is the same engine where the audio usually lives, plus the heavy optional extras: Demucs stems through the
  MIT MLX-Swift port, batch runs over a library, signature generation at scale.

The Python stack in `mixer/` becomes the lab: ground truth for the 373 analysed tracks and the place to try models.
It does not ship. The madmom models and the Essentia models are licensed non-commercial and Essentia is AGPL
(track A, section 4). Chris's crate must be regenerated with the shipped engine before it is a TestFlight fixture.

OS floor: iOS, iPadOS and macOS 27. Some 2018 to 2022 iPads are dropped; check the iPad Air 4 [measure]. The crate
file mitigates it: any OS 27 device analyses, any device consumes. A fallback engine for older devices exists on
paper only and is built only if trial DJs need it.

### 5.2 The crate file (proposed, P1)

A package folder, `<name>.deckiecrate`: a compact `crate.json` core (about 7 KB per track, 3 KB gzipped; no raw beat
arrays, no 1280-d embedding), binary sidecars for per-bar series, a style vector, `prefs.json`, append-only
per-device history logs, and an optional `signatures/` store. Budget about 10 KB per track without signatures, about
145 KB with three pitch variants. Signatures are irreversible by Apple's statement, so carrying them does not breach
D3; they travel when the receiving device has no audio to regenerate from. Schema int plus per-track engine string;
readers ignore unknown keys; merge by timestamps; history is a union. Moves by iCloud Drive, AirDrop and Files. No
server. Schema in track A, section 5.

### 5.3 Recognition

A ShazamKit custom catalogue built from the user's files, per crate, rebuilt locally. On-device signature cost,
memory at thousands of signatures and pitch tolerance beyond the current variants were never measured [measure].
Apple's guidance says matches are safe under 5 percent skew, so the plus or minus 4 percent variants may be partly
redundant [measure]. Bulk work runs only on power, watches thermal state, and uses the OS 26 continued-processing
task so the user sees progress.

### 5.4 Identification (track B)

Offline first, network optional, never gating:

1. Tags first, then a file-name grammar for DJ files that splits each file into a work (song, original artist, year)
   and a version (remixer, edit kind, clean or dirty, intro, extended). DJ-pool files are the best tagged; YouTube
   rips are the worst.
2. Cross-reference inside the crate: cluster versions of a work, group by album, folder and disc, fold half-time and
   double-time tags, drop exact duplicates by content hash.
3. Optional text enrichment, off by default, one switch: MusicBrainz and Discogs (both CC0, titles only, never
   audio). CC0 data may be cached in the crate file; YouTube and SoundCloud data may not be stored at all.
4. Optional fingerprint lookup, explicit opt-in per batch, Mac first: Chromaprint plus AcoustID, to name the work
   behind an untagged rip. A lookup discloses which records the user owns to a third party, so never automatic.
5. Unidentified tracks keep the user's own name, get the full analysis, and appear in a "name these" list.

YouTube is not a source (proposed, P2): the Data API quota is 100 searches per day per project shared by all users,
fetched data must be deleted within 30 days, and all access outside the API is prohibited. The only compliant use
is a hand-triggered "open in YouTube" link carrying the user's own query. Beatport, SoundCloud, Bandcamp and
1001Tracklists are not usable sources under their terms. A burned MP3 CD is a file system with no disc id; Deckie
writes a manifest when it builds a disc and reads it back.

### 5.5 Preferences and learning (track C)

Preferences live in the crate file and are learned on device. Twelve measurable dimensions with proxies from the
pair scores, the set log or the set recording; three presentation sliders. Event weights: played-next, then
pin-then-played, pin unplayed, shown-and-chose-another, skip, ignored. Robust per-dimension quantiles with about
five gigs of forgetting; a personal played-after prior; weight learning only after about 50 joins, as a regularised
model with the current `score.py` weights as the prior. The mapping from each dimension to a `score.py` weight or
gate is in track C, section 4, with starting values marked untested.

### 5.6 Apps and roles

One universal iOS binary plus a native macOS target from shared packages. Roles are runtime modes: Booth (iPad beside
the decks), Pocket (iPhone: record a set, see the tracklist), Desk (Mac: import, analyse, manage the crate). Web app:
later. Android and Windows: not planned.

## 6. Features

- 6.1 Hear and identify. Exists. Add: loud-room measurement; pitch sweep; wider variants only if the sweep says so.
- 6.2 Picks and the join. Exists. Add: history strip and no repeats; a "why this pick" line; the narrowed claim in
  every pick: options, not verdicts.
- 6.3 Crate building. New. Import a folder or files; the identification pipeline in 5.4; the "name these" list;
  disc manifests; an "open in YouTube" link per track.
- 6.4 Onboarding, under five minutes, only the first two steps required (track C): gear and pitch range (30 s);
  how-you-mix cards in DJ words plus genre and era chips from the crate's own tags (30 s); listen and pick, six to
  eight A/B rendered joins from the DJ's own crate with "neither" (about three minutes; needs the renderer, Mac only
  today); the sliders pre-set from the answers, shown once (30 s). Optional: import a recorded set. A "How you mix"
  page shows what was learned, with undo.
- 6.5 Tunability. Three sliders on the booth screen: pick difficulty (safe to adventurous), options (3, 5, 10), data
  density (Minimal, Simple, Full). Five in the "How you mix" sheet: pitch range cap; key (ignore, warn, prefer); style
  spread (stay in lane to roam); blend to cut (palette order); vocals (keep apart to overlap fine). Each carries a
  learned-default marker the DJ can override. Presets per gig: later.
- 6.6 Set recording and export. Exists. Add: CUE and Mixcloud text export; line-in recording option.
- 6.7 Learning from use. New. As in 5.5, on device only.

## 7. Staging (revised)

- Stage 0, this week: baseline. First commit, repo self-contained, music root setting, venv recreated, an analysis
  run, a scoring run, a data prep and an app build verified from this folder.
- Stage 1, next: the measuring experiments, before any engine code. (a) Music Understanding over the 373 tracks
  against the Python features: beat and downbeat F-measure, key agreement, vocal-timeline correlation, section
  boundaries. Needs macOS 27 or an iOS 27 device; this Mac is on 26. (b) ShazamKit on device: signature time per
  track on an iPhone, memory at a few thousand signatures, and a pitch sweep with `catalogtool bench` including
  tempo-only variants. (c) Does the iPad Air 4 run iPadOS 27. (d) Regenerate Chris's crate with the new engine once
  (a) passes.
- Stage 2: DeckieAnalysis on the Mac and crate file v1. Point it at any folder and get a crate file; the identification
  pipeline; the iPad reads the crate file instead of bundled data; the catalogue is built from the user's files.
  Chris's crate is test fixture number one.
- Stage 3: on device. The engine on iPad and iPhone; on-device signatures; onboarding; the sliders; the learning loop.
- Stage 4: trial. TestFlight with five to ten DJs from the primary segment. Pass marks: identification within 15 s on
  at least 85 percent of songs; at least one pick taken per three songs; six of ten use it at two or more gigs.
- Later: web app; aggregate learning across users only with consent and never with content; gig presets; an
  iPhone-only set-recorder SKU if vinyl and CD DJs want it.

## 8. Pricing and distribution (track D; nothing decided)

- Comparables, Oct 26, 2026: djay $6.99 a month or $49.99 a year; rekordbox $120 to $360 a year; Serato $11.99 a
  month or $299; Mixed In Key $58 and $99; DJ.Studio $99 to $209 one-time; Beatport Track ID free; NXTCue $19.
  Identification alone is now free, so the price is for the join, the learning and the tracklist.
- Lean (track D, inference): a one-time price in the $39 to $59 range, with the $49 one-time versus $4.99 a month
  test from the competitive analysis kept for the trial. DJs are subscription-averse and mostly use no AI tools, so
  do not sell it as AI.
- App Store: microphone purpose string; consent and a persistent recording indicator; audio background mode; a
  privacy policy even with no collection; guideline 5.2.3 forbids downloading media from YouTube or SoundCloud; a
  royalty-free demo crate and a video for the reviewer, since the reviewer has no crate; "Data Not Collected" only
  if the policy matches and crash reporting is off or opt-in; store name "Deckie: DJ Booth Companion"; category Music.

## 9. Open questions

- Music Understanding accuracy, confidence and timings (stage 1a).
- ShazamKit on device: cost, memory, pitch tolerance (stage 1b).
- iPad Air 4 on iPadOS 27 (stage 1c).
- Beatport Track ID: on device or server; does it run on iPad.
- The renderer for onboarding A/B joins: Mac only, or an on-device port.
- Chromaprint on iOS (LGPL 2.1 static linking); the MetaBrainz tier for a per-user client app.
- Whether anyone but Mike uses the pitch readout; the 2026 off-laptop share.
- Final bundle id under App Hold Media (Chris).
- Deckie trademark: attorney review of DECKEE; deckie.dj registrar availability (still unconfirmed at the registry).
- A human pass on r/DJs, r/Beatmatch and the DJ Discords; the tools could not reach Reddit.

## 10. Not doing

- The auto-mix as a product. It stays a personal tool.
- A bundled catalogue of commercial tracks in any public build.
- Cloud analysis of audio, in any form.
- YouTube, SoundCloud, Beatport, Bandcamp or 1001Tracklists as identification sources.
- Fingerprint lookups by default or from the iPad.
- Selling it as AI.
