# Deckie research plan: four tracks

Each track is a brief for one deep-research agent. Each writes one report to `docs/research/<letter>-<slug>.md`
with a one-page summary at the top, then the evidence. Rules for every track: cite sources; mark inference as
inference; no vendor claims without a second source; extend `docs/competitive-analysis.md`, do not redo it; do not
scrape anything; keep the body under about 3,000 words. Reports feed spec v0.2.

## Track A: on-device and on-computer analysis, and the crate file

Question: which parts of the analysis can run on an iPhone or iPad, which need the Mac, with what quality and time,
and what should the shared crate file contain?

Cover:
- Per feature, on iOS: beat and downbeat tracking (Core ML conversions of Beat This! or madmom, Apple frameworks,
  Accelerate-based approaches), key detection, vocal detection (a light alternative to Demucs), structure and
  phrases, loudness, a style embedding. For each: feasible, quality against the Python stack, seconds per track,
  library and licence, battery and thermal cost.
- ShazamKit on device: `SHSignatureGenerator` time per track, catalogue size and signature-count limits, behaviour
  with pitch variants, background processing limits.
- The Mac side: options to ship the Python stack to a non-developer (PyInstaller, py2app, a Swift port of the
  critical parts) and their size and licence implications (madmom and the Essentia models are CC BY-NC-SA).
- The crate file: schema proposal, size per track, versioning and migration, whether signatures travel with it, and
  how it moves between devices without a server.
- iPhone and iPad: one binary or two roles.

Inputs: `mixer/README.md` (feature schema), `docs/research.md` section E, `deck-app/README.md` recognition section,
`deck-app/tools/catalogtool/main.swift`.

Deliverable: `docs/research/a-on-device-analysis.md` with a per-feature table (where it runs, quality, time,
licence), a crate file v1 schema, and a recommendation for the split between device and computer.

## Track B: identifying the user's crate from their files and public metadata, inside the privacy stance

Question: how do we map a user's files, with messy names, burned CDs, DJ-site downloads, live sets and bootlegs, to
good metadata without their audio leaving the device?

Cover:
- Tag and file-name parsing: what DJ files actually look like (pool edits, "(Clean)/(Dirty)", remixer credits).
- Fingerprint lookups: AcoustID and Chromaprint. A fingerprint is a hash, not audio; decide whether sending it fits
  the privacy stance, and say so plainly.
- Metadata sources and their terms: MusicBrainz, Discogs, Beatport, 1001Tracklists, SoundCloud, Mixcloud, Bandcamp.
  For each: what it returns, API terms, rate limits, cost, privacy implications, offline behaviour.
- CDs: disc id lookup (MusicBrainz) for burned and commercial discs; what a burned MP3 CD can and cannot tell us.
- YouTube: exactly what the Data API allows for search and metadata, what the Terms of Service forbid (scraping,
  crawling, downloading, circumventing), and the line between reading and mapping versus training. A clear verdict.
- Unidentifiable tracks: keep the user's own name, analyse anyway, never block on identification.

Inputs: `pool/newfiles/pool_build.py` and `probe_new.py` (what the sprint parsed), `docs/competitive-analysis.md`
sections 3 and 6.

Deliverable: `docs/research/b-identification.md` with a source table, a recommended pipeline, and the YouTube verdict.

## Track C: how DJs mix, a preference framework, and the onboarding moment

Question: what are the dimensions of a DJ's mixing style, how do we elicit them at first run in a few minutes, and
how do we keep learning from their sets?

Cover:
- Dimensions: tempo tolerance, pitch range, key strictness, genre and era spread, energy arc, blend length, cut
  styles, echo-outs and effects, vocal handling, phrase alignment, loops. Define each with a measurable proxy.
- Existing taxonomies: DJ pedagogy, Mixed In Key and DJ.Studio presets, academic work on DJ mix analysis and mix
  segmentation, what VirtualDJ and rekordbox learn from play data.
- Elicitation: listening A/B of rendered joins, a few sliders, importing a recorded set and inferring, a short text
  conversation. Which gets the most signal per minute.
- Learning from use: played-next pairs, pins, skips, what the DJ ignored. How preferences map to score weights and
  gates. Which things are sliders the DJ moves and which are learned silently.
- Mike as the first data point: the feedback log in `BRIEF.md` section 7 and `docs/history/`.

Inputs: `docs/transition-recipes.md`, `mixer/score.py` (weights and gates), `BRIEF.md` section 7,
`docs/competitive-analysis.md` section 4.

Deliverable: `docs/research/c-dj-preferences.md` with the dimension list, an onboarding flow under five minutes, the
learning loop, and a slider set v1.

## Track D: who it is for and why: positioning and what DJs want

Question: extend the DJ-community research and produce a positioning that states value, differentiator, for whom and why.

Cover:
- Segments: open-format, mobile and wedding; vinyl and CD; bar and club residents; bedroom. Size, gear, pain.
- Where they talk and what they ask for: r/DJs, r/Beatmatch, DJ TechTools, Digital DJ Tips, Pioneer forums, Discords.
  Quotes with sources.
- Willingness to pay and comparables: djay, Mixed In Key, rekordbox tiers, DJ.Studio, Beatport Track ID.
- Privacy as a selling point: does it land with DJs, and how to say it.
- App Store realities: microphone and recording permissions, review risk for a recognition app, category.
- Naming: the Deckie items still owed in `docs/naming/00-shortlist.md`, including the DECKEE mark.
- Draft the positioning statement (Dunford shape) and one jobs-to-be-done statement, with the evidence behind each line.

Inputs: `docs/competitive-analysis.md` sections 4, 7 and 8, `docs/naming/`.

Deliverable: `docs/research/d-positioning.md` with the positioning statement, the JTBD statement, a segment table, an
evidence log with sources, and the open naming items.

## Track E: the DJ vocabulary dictionary (added Oct 26, evening)

Question: what words do DJs actually use for transitions, moves, tempo and key handling, and how should Deckie label
things? Deliverable: `docs/research/e-dj-vocabulary.md` with a label set mapping every internal move name to a
public word, a short popup label, a plain gloss and the slang synonym; the dictionary by scene with sources; the
palette for the onboarding chain; the slider words. Run as an agent on Oct 26.

## Track F: Reddit and Discord, run by Codex (added Oct 26, evening)

The research tools here cannot reach Reddit. The brief is `docs/research/briefs/codex-reddit.md`; Codex wrote the
report to `docs/research/codex-community.md` (Oct 26, 2026): direct quotes with links, r/DJs, r/Beatmatch, r/Rekordbox,
r/PioneerDJ, r/mobileDJ and Algoriddim's forum, 2019 to 2026.
