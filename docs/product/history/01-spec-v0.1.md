# Deckie product spec, v0.1

Dated Oct 26, 2026. Status: skeleton written from the decisions in `00-decisions.md`. Sections marked RESEARCH are
waiting on the tracks in `02-research-plan.md` and will change in v0.2. Nothing here is final except the decisions.

## 1. Goal

Deckie is a booth companion that hears what a DJ is playing on any rig, knows their own crate, and shows what could
come next and how to get there, without ever touching their music.

## 2. Who it is for (draft; RESEARCH D)

- Primary: open-format, mobile and wedding DJs on mixed or legacy gear: CDJs without a link, vinyl, borrowed decks,
  house systems they cannot install software on.
- Secondary: vinyl and CD DJs by choice; anyone who records sets from hardware and wants a timestamped tracklist.
- Not for: laptop DJs inside rekordbox or Serato on Pro DJ Link gear. Their software already knows what is loaded.

## 3. Value and differentiator (draft; RESEARCH D)

- Works with any rig. It listens; nothing to plug in or install on the decks.
- Knows your crate: your edits, bootlegs, live sets and burned CDs, named the way you named them.
- Tells you how to do the join: the pitch value for the incoming deck, the join waveform, the move.
- Private by construction: your music never leaves your devices.
- Learns how you mix, not how an average DJ mixes.

Framework: a positioning statement in April Dunford's shape (competitive alternatives, unique attributes, value,
who cares, market category) plus one jobs-to-be-done statement. Chosen because it is short and forces the "for
whom" question. A Lean Canvas comes later, only if pricing is on the table. RESEARCH D fills these in with evidence.

## 4. Principles

See `00-decisions.md`, D3 and the standing principles. The two that shape every screen: recommend, never prescribe;
and the user's content is theirs.

## 5. Architecture (shape decided; details RESEARCH A and B)

- Two analysers, one file. The Mac does deep analysis; the iOS app does what it can on device; both read and write
  the same crate file. No Deckie server.
- The crate file: per-track identification and analysis features, the DJ's preferences, and play history. No audio.
  Small enough to move by AirDrop, Files or iCloud Drive. Schema and size budget: RESEARCH A. Open question: whether
  it carries recognition signatures (the shipped build was 1,041 signatures, 47 MB, for 347 tracks at three pitch
  variants) or they are regenerated on each device.
- Recognition: a ShazamKit custom catalogue built from the user's files. On the Mac today via the catalogue tool;
  on device when feasible (SHSignatureGenerator exists on iOS; cost per track unknown).
- Identification: tags and file names first, public metadata second, the user's own name as the fallback. RESEARCH B.
- Preferences: captured at onboarding, refined from use, applied as weights and gates on the pair scores.
- Web app: later. Android and Windows: not planned.

## 6. Features

- 6.1 Hear and identify. Exists. Add: measured loud-room performance; wider pitch variants if needed.
- 6.2 Picks and the join. Exists. Add: history strip, no repeats, a "why this pick" line.
- 6.3 Crate building. New. Import from a folder or files; identify; show what could not be identified and let the
  user name it; CDs by disc and folder where they exist.
- 6.4 Onboarding "training moment". New. RESEARCH C. A few minutes, not a questionnaire. Candidate inputs: listen
  to rendered joins and pick, a handful of sliders, or import a recorded set and infer.
- 6.5 Tunability. New. Sliders v1: pick difficulty, number of options, data density. Candidates: pitch range cap, key
  strictness, style spread, blend length, vocal tolerance. RESEARCH C decides which are sliders and which are learned.
- 6.6 Set recording and export. Exists. Add: CUE and Mixcloud text export; line-in recording option.
- 6.7 Learning from use. New. Played-next pairs, pins and skips feed back into the scores. On device only.

## 7. Staging (proposed; revise after the research sprint)

- Stage 0, this week: baseline. First commit, repo self-contained, music root setting, venv recreated, an analysis
  run, a scoring run, a data prep and an app build verified from this folder.
- Stage 1, one to two weeks: research sprint, tracks A to D. Output: spec v0.2 with decisions on the analysis engine
  per platform, crate file v1, identification sources, the preference framework and positioning.
- Stage 2: crate file and Mac analyser. Point the mixer at any folder and get a crate file; the iPad reads the crate
  file instead of bundled data; the catalogue is built from the user's files. Chris's crate is test fixture number one.
- Stage 3: on device. iOS subset of the analysis; on-device signatures; onboarding; the sliders.
- Stage 4: trial. TestFlight with five to ten DJs. Pass marks from the competitive analysis: identification within
  15 seconds on at least 85 percent of songs; at least one pick taken per three songs; six of ten use it at two or
  more gigs.
- Later: web app; aggregate learning across users, only with consent and never with content.

## 8. Open questions

- YouTube as a lookup source: what the Terms of Service allow (RESEARCH B).
- Signatures in the crate file or regenerated per device (RESEARCH A).
- One app for iPhone and iPad, or iPad-first with an iPhone recorder (RESEARCH A and D).
- Final bundle id under App Hold Media (Chris).
- Deckie trademark clearance and the DECKEE conflict (`docs/naming/`).

## 9. Not doing

- The auto-mix as a product. It stays a personal tool.
- A bundled catalogue of commercial tracks in any public build.
- Cloud analysis of audio, in any form.
