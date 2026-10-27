# Deckie product spec, v0.3

Dated Oct 26, 2026. Supersedes v0.2 (`history/01-spec-v0.2.md`). What changed from v0.2: Chris accepted the native
engine on Apple's Music Understanding framework with graceful fallbacks (D11); tuning speaks the DJ's language and
starts from a song chain (D12, research track E); the Mike caveat in section 2; profiles as a proposal (P9); the
YouTube verdict reopened for a deeper look. Proposed decisions still waiting for Chris are in `00-decisions.md`. Items marked
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

A second situation, from Chris (Oct 26): the DJ with an unfamiliar crate. Mike's party set was curated by Chris and
held music Mike does not usually play, so the sprint's data describes a DJ playing someone else's selection: new
DJs, a themed party with a handed-over crate, or someone having fun with a new DJ toy. His 16 percent pitch habit
is not normal either. The answer in both cases is the same, customisation, which is why D6 exists. A recording of
the set Mike actually played is coming and will replace the disc toggles as his reference.

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

### 5.1 One analysis engine on three platforms (decided, D11)

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

Graceful fallbacks (D11): Music Understanding needs OS 27, and some 2018 to 2022 iPads are dropped; check the iPad
Air 4 [measure]. Degradation is designed in, not bolted on. Level 1: a device below OS 27 consumes a crate file that
an OS 27 device or the Mac analysed, with every feature intact. Level 2: a device below OS 27 that must analyse on
its own runs the fallback engine, Beat This! small plus our own DSP plus Apple's SoundAnalysis for a singing
classifier, and marks the tracks so they are re-analysed when a capable device sees the crate. Level 3: no analysis
at all, recognition and the set log still work, picks are off. The app says which level it is on, in one line.

### 5.2 The crate file (decided with D11)

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

### 5.4 Identity and naming (track B; revised Oct 26 evening, P10 proposed)

A track's identity in Deckie is its own, with no external service: a content hash of the file for exact identity,
the ShazamKit signature for recognition, and an analysis-derived descriptor for recognising versions of the same
work across edits and crates [measure; track B addendum]. Its name comes from the file's tags and file name, parsed
by the grammar below, and the DJ can edit any field at any time; edits live in the crate file, never in the files.
Public lookups are an optional helper that suggests corrections and never applies them: in the sprint, MusicBrainz
and Discogs proved inaccurate for DJ edits and remixes, and the pool ended up with hand maps for about a hundred
original years and a hundred new entries anyway. What public data would add (original year and genre for untagged
rips) feeds only the style term, and the analysis's own style embedding covers most of that.

The pipeline, offline first, network optional, never gating:

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

YouTube (P2, after the deeper look in the track B addendum): not a source for automated mapping. Every site that
shows YouTube data gets it by one of four routes: a registered Data API client, scraping (Invidious, Piped, yt-dlp,
cobalt, the RapidAPI and Apify resellers), links people typed into another database, or the user handing over a
link. Only the first, third and fourth survive YouTube's developer policies and App Store guidelines 5.2.2 and
5.2.3, and the Data API's search quota is useless for this. Two refinements: a link the user shares or pastes into
Deckie may be resolved through the API (1 unit per lookup, 10,000 a day across all users), shown, and accepted into
the user's own name, never stored; and the best legitimate holder of YouTube links per recording is MusicBrainz's
CC0 "free streaming" URL relationships, with Discogs release videos second. Both already carry title, artist,
remixer and year, so YouTube never has to be read; its link is a "listen to confirm" button. Spotify, Deezer and
Apple Music metadata are closed to this use by their own terms. Beatport, SoundCloud, Bandcamp and
1001Tracklists are not usable sources under their terms. A burned MP3 CD is a file system with no disc id; Deckie
writes a manifest when it builds a disc and reads it back.

### 5.5 Preferences and learning (track C)

Preferences live in the crate file and are learned on device. Twelve measurable dimensions with proxies from the
pair scores, the set log or the set recording; three presentation sliders. Event weights: played-next, then
pin-then-played, pin unplayed, shown-and-chose-another, skip, ignored. Robust per-dimension quantiles with about
five gigs of forgetting; a personal played-after prior; weight learning only after about 50 joins, as a regularised
model with the current `score.py` weights as the prior. The mapping from each dimension to a `score.py` weight or
gate is in track C, section 4, with starting values marked untested.

### 5.6 Profiles (proposed, P9)

DJs often have more than one style. A profile is a named preference set (the twelve learned dimensions plus the
slider positions) inside one crate file: for example "Wedding", "Deep night", "Fun with Mike". One profile is
active per gig; learning writes to the active one; a new profile starts as a copy of another, from a set upload, or
from the onboarding chain. The crate and the history are shared across profiles. Start with one profile and let the
DJ add more; never ask a new user to choose.

### 5.7 Apps and roles

One universal iOS binary plus a native macOS target from shared packages. Roles are runtime modes: Booth (iPad beside
the decks), Pocket (iPhone: record a set, see the tracklist), Desk (Mac: import, analyse, manage the crate). Web app:
later. Android and Windows: not planned.

## 6. Features

- 6.1 Hear and identify. Exists. Add: loud-room measurement; pitch sweep; wider variants only if the sweep says so.
- 6.2 Picks and the join. Exists. Add: history strip and no repeats; a "why this pick" line; the narrowed claim in
  every pick: options, not verdicts.
- 6.3 Crate building. New. Import a folder or files; the identity and naming pipeline in 5.4; a metadata editor
  with bulk edit and undo, edits kept in the crate file; the "name these" list; "suggest a correction" from public
  data as an opt-in helper; disc manifests; an "open in YouTube" link per track.
- 6.4 Onboarding, under five minutes, only the first two steps required. Gear and pitch range (30 s). Then the
  chain (D12): the DJ picks three to five songs from their own crate in the order they would play them, and for each
  join taps how they would mix it from a palette of move words in the DJ's own vocabulary (research track E), in the
  style of a rhythm-game prompt: "long blend", "cut on the one", "echo out", "scratch in" and so on. Each tap is a
  labelled join and seeds the dimensions directly (about two minutes). Optional and stronger: upload one of your own
  recorded sets, or upload a set whose style you like (a local file; it is analysed on device and never leaves).
  Optional: listen and pick, six to eight A/B rendered joins with "neither" (needs the renderer, Mac only today).
  The sliders come pre-set from the answers and are shown once (30 s). A "How you mix" page shows what was learned,
  with undo. Sliders are last for a reason: track C found them fine for facts and useless for style.
- 6.5 Tunability, in the DJ's words. Every label, popup and slider uses the vocabulary from track E (the label set
  is the summary table of `docs/research/e-dj-vocabulary.md`; two rules from it: never show "brake" alone, and
  "filter fade", not "filter out"); nothing is shown as an internal name, and a one-line plain gloss is a long-press away for new DJs. In-app popups during a set
  use the same move words ("more range", "fade mix", "hard cut"), so tuning during a gig is one tap, not a settings
  page. Three sliders on the booth screen: pick difficulty (safe to adventurous), options (3, 5, 10), data
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

- Vocabulary: Chris's "echo in" and "more bass range" matched no source; what did he mean? Whether the brake
  versus hard-cut split goes into `score.py` or only into the labels.

- YouTube: the deeper look at sites that carry YouTube data and at mapping services (track B addendum).
- Profiles: one per style, as proposed in 5.6, or something simpler (Chris).
- The vocabulary dictionary (track E) and the Reddit pass (track F, run by Codex).

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
