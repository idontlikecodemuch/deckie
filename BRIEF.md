# Deckie: product brief for the next agent

Written Oct 26, 2026, at the end of a one-week sprint that built these tools for a single Halloween party.
This folder is a clean copy of everything that is code, data or documentation. It holds no music, no
virtual environment, no build caches and no credentials. Read this file first, then `docs/competitive-analysis.md`,
then the component READMEs. The product name is **Deckie** (chosen Oct 26, 2026, not yet trademark-cleared; Australian slang for a
deckhand). "Deck" survives only as the code name in folder names, the Xcode target and the bundle id. The naming
research, the names rejected on the way and the checks still owed are in `docs/naming/` (start with `00-shortlist.md`).

## 1. What this is, in one paragraph

A booth companion for DJs who play on gear with no network link (an old CDJ, vinyl, borrowed decks). An iPad
listens to the room, recognises which track from the DJ's own crate is playing (including bootlegs and edits), reads
the pitch-fader setting, shows where the track is and where its mix-out window starts, and suggests what to play
next with the information needed to actually do the join: the pitch value for the incoming deck, a two-lane join
waveform aligned at the join, the key relation, and a menu of moves (blend / echo out / brake). It also records the
set and writes a timestamped tracklist. Alongside it sit two more pieces: a phone web player the DJ used to audition
and edit the disc selection, and an offline analysis + auto-mix toolkit that scores every pair of tracks and can
render a continuous DJ-style mix. The competitive analysis found that no major DJ app identifies the playing track
through a microphone and none tells the DJ how to do the join; the auto-mix slice is crowded and copyright-exposed.

## 2. The people and the history

- **Christopher Shannon** (owner, c@christophershannon.io): built all of this with Claude Code agents over Oct 17-25,
  2026, for his friend's Halloween party on Oct 24. He has a paid Apple developer account (team 566NNM5HT8, App Hold
  Media LLC), a Bluehost site (christophershannon.io, behind Cloudflare) and an iPad Air (4th gen) that ran the app
  at the party. He is design-literate and direct: "don't over-engineer", "simplify", "options not verdicts",
  "the range is wider for him", "focus on the info Mike needs".
- **Mike** (the DJ): plays a Pioneer CDJ-1000MK3 from MP3 CDs, mixes progressively (long blends in and out), uses the
  pitch fader well beyond +/-8 percent, cares about pitch, BPM, key and disc location, and dislikes clutter. His live
  feedback shaped the last rounds (see section 7).
- **Timeline:** two MP3 CDs were curated (91 tracks, CD1 Singalongs 41 / CD2 Mix-ins 50), loudness-normalised and
  burned; a web player for Mike went live at christophershannon.io/mike-halloween; the mixer toolkit analysed 373
  tracks and scored every pair; the Deck iPad app was built in one day and installed by cable; a continuous
  144-minute auto-mix was rendered and burned to a third disc; Mike used the app and the mix at the party and it
  "worked great with the changes"; a competitive analysis was written the day after.

## 3. Folder map

```
deckie/
  BRIEF.md                 this file
  deck-app/                the iPad app (xcodegen project; see deck-app/README.md)
    project.yml, Deck/Sources/*.swift, Deck/Resources/{deck_data.json, Deck.shazamcatalog, overview.json, mixmap.html}
    tools/prep_data.py, tools/mixwaves_all.py, tools/overview_waves.py, tools/catalogtool/main.swift
  mixer/                   analysis, scoring, planner, renderer (see mixer/README.md)
    analyze.py, local_tempo.py, score.py, build_candidates.py, add_tracks.py, mixwaves.py, add_mix_to_data.py,
    plan.py, render.py, sampler.py, build_mixmap.py, build_print.py, build_mix_discs.py, summary.py
    candidates.json (373 tracks), features/<id>.json (per-track analysis), pairs.json (99,832 scored pairs),
    mixwaves.json, models/ (Essentia graphs), plan_*.json, mixes/*.cue|*.txt|*.render.json (audio removed)
    recs.json, recs.md, summary.md, research.md, transition-recipes.md, competitive-analysis.md
  pool/                    the disc-curation pipeline that fed everything (see pool/README.md)
    newfiles/pool_build.py, probe_new.py, mike_data.py, apply_mike.py, waveforms.py, page_build.py,
    newfiles/pool.json (1,876 rows: 347 disc candidates + 1,529 library), selection_v2.json, ...
    build_two_discs.py (disc build with loudness normalisation), ftp_upload_mike.py (FTPS uploader)
  web-player/              Mike's phone page (index.html, data.js, data.json, .htaccess, icons, HOW-TO-PUBLISH.md)
  docs/                    research.md, transition-recipes.md, competitive-analysis.md (copies),
    discs/ (disc manifest, loudness scan, printouts, the final mix's tracklist and cue), history/ (the agent
    memory notes written during the sprint: decisions and why)
```

Absolute paths inside the data still point at the original music folder,
`/Users/christophershannon/personal/90s2000 playlist/` (candidates.json `path`, pool.json `path`, the features'
`path`). The music stays there; see section 9 for how to re-point.

## 4. Architecture and data flow

1. **Pool** (`pool/newfiles/pool_build.py`): scans the music folder, probes files (`probe_new.py`, tags + aubio
   tempo), builds `pool.json` with disc assignment, BPM folders (`1 - under 90` ... `8 - 135 plus`), Halloween flag,
   kind (pool edit / official remix / dance original / pop original / library), and the selection baseline
   (`selection_v2.json`). Since Oct 24 the BPM used for folders is the measured start tempo from the mixer
   (`bpm_meas`), with one pinned exception (Bette Midler club mix kept at 140).
2. **Candidates** (`mixer/build_candidates.py`): every non-library pool row plus listed extras
   (`extra_lib_ids.json`) -> `candidates.json` with `on_disc`, `cut_key` and `is_longest` (longest cut of a song
   version wins).
3. **Analysis** (`mixer/analyze.py`): per track, decoded once: Beat This! (MPS) beats/downbeats, madmom as second
   opinion when the grid is doubtful, constant-grid fit (two estimators, best inlier fraction wins), octave alignment
   to the tag, Essentia key (edma + bgate) plus madmom CNN key, Camelot, Foote-novelty structure on an 8-bar lattice,
   first/last sound, fade-out detection, mix-in / mix-out windows, pyloudnorm loudness, per-bar LUFS / low / high /
   onset density / vocal probability (Essentia Discogs-EffNet voice head), EffNet embedding, flags.
   `local_tempo.py` adds start/end tempo by regression with a trust rule (residual <= 15 ms) and `steady_in_bar`.
   Schema in `mixer/README.md`. About 15 s per track.
4. **Scoring** (`mixer/score.py`): directed A->B using A's end tempo vs B's start tempo. Terms and weights:
   tempo 0.26, key 0.14, energy 0.11, vocal 0.11, phrase 0.08, timbre 0.12, rhythm 0.05, style 0.13. Tempo is free
   to 3 percent, gentle to 10, usable to 16 (a CDJ's wide range), rejected past 18; half/double time at a small
   penalty; 2/3, 3/4 relations capped at 0.35. Blends are the default move; `moves` lists up to three options
   (primary first); `bass_swap_8` is the short blend. Outputs `pairs.json`, `recs.json`, `recs.md`.
5. **Consumers:** `add_mix_to_data.py` writes `mix` lists, mix windows, snippets and pitch values into the web
   player's `data.js`; `deck-app/tools/prep_data.py` builds the app's `deck_data.json`, `overview.json` and the
   ShazamKit catalogue; `build_mixmap.py` / `build_print.py` make the mix map artifact and the one-page printout;
   `plan.py` + `render.py` make the auto-mix; `build_two_discs.py` and `build_mix_discs.py` make MP3-CD ISOs.
6. **Deck app** (`deck-app/`): SwiftUI, iPadOS 17+, landscape-first. `Recognizer.swift` runs
   `SHSession.matchStreamingBuffer` on the mic with a state machine (pause detection, 2-match position jumps, hard
   cut switch in ~4-5 s, blend switch after 10 s of dominance, no flip-flopping, same-song alternate cuts merged),
   pitch from `frequencySkew` (vinyl) and position drift (master tempo). `Mixing.swift` draws Easy / Harder picks
   (weighted random from the top band; surprise tags for the hard ones), Simple 2+1 / Full 3+2, Minimal toggle
   (waveforms off, pills), CD1/CD2/All chips, move menus, 16 percent beat-match cutoff. `SetRecorder.swift`
   records AAC + JSON log + tracklist to Documents/Sets. Tabs: Listen, CDs (dense, both discs), Mix map (WKWebView
   of mixmap.html). Signing: automatic, team 566NNM5HT8; install by cable with the command in its README
   (`-allowProvisioningDeviceRegistration` was the missing flag the first time). TestFlight needs an App Store
   Connect app record and an account with App Manager access; the archive and exportOptions are prepared.
7. **Web player** (`web-player/index.html` + `data.js`): the phone page Mike used to toggle tracks on/off, star,
   chain and send his picks back as a text report (`apply_mike.py` parses it, including `CHAIN` lines). Its "Up
   next" uses the same scores with stacked join waveforms, pitch chips, key verdicts, move menus. Hosted at
   christophershannon.io/mike-halloween (Bluehost FTPS via `ftp_upload_mike.py --env`; Cloudflare caches
   aggressively, so data files are served no-store and the page link carries a version query).

## 5. Environment recipe (verified on an Apple Silicon Mac, Oct 2026)

- Python 3.14 (Homebrew `python@3.14`); 3.15 has no torch wheel. Create `mixer/.venv` with it and install in this
  order: `pip install -U pip setuptools wheel cython "numpy<3"`; `pip install --no-build-isolation
  git+https://github.com/CPJKU/madmom`; `pip install torch torchaudio soxr einops tqdm rotary-embedding-torch
  beat-this`; `pip install librosa soundfile pedalboard pyloudnorm scipy`; `pip install essentia-tensorflow` (never
  plain `essentia` on top of it). Demucs is NOT installed in the mixer venv (it was verified in a scratch venv);
  install it when stems are needed. Full recipe and pitfalls: `docs/research.md` section E.
- ffmpeg 8.x from Homebrew (no rubberband filter; pedalboard embeds Rubber Band). Essentia model graphs are in
  `mixer/models/`.
- Xcode 27, xcodegen (`brew install xcodegen`), iPad simulators. The simulator has no microphone; the app has a
  "test with file" path that streams a file through the same pipeline. ShazamKit custom catalogues: signatures are
  generated by `tools/catalogtool` (macOS) from the audio; the shipped catalogue is original + vinyl +/-4 percent
  (1,119 signatures, 49 MB); all nine variant sets exist in the original machine's `tools/build/sigs` cache
  (not copied).
- Run everything with the venv's python and `-I`. Analysis of the 373-track catalogue takes about 90 minutes.

## 6. State of play (what works, what is pending)

Works and was used live: recognition from the room with pitch readout; Easy / Harder picks with join waveforms and
move menus; Simple / Full / Minimal; CDs tab; mix map; set recording. The web player with Up next, chains and
reports. The disc build with loudness normalisation (-10 LUFS, -2 dBTP pre-encode, limiter fallback; final spread
1.3 dB). The scorer with start/end tempo, style term and move options. The auto-mix renderer produced a 144:40
continuous mix that was burned and played at the party.

Pending or weak:
- Auto-mix quality (the owner: "still needs some work"): 19 of 65 joins still dip more than 2 LU after three
  repair passes; 12 of 31 bass-swap blends join clashing keys; blends are short (vocal model over-reports singing,
  so 16-32-bar windows are rare); 26 percent of joins jump tempo more than 6 percent; no energy model; the repair
  filler (synthetic kick/hat, make-up gain) may sound artificial; nobody has listened to the final render end to
  end. Three recipe items were never implemented: starting the next song a beat early on vocal pick-ups, the
  vocal-silence check before a slam, fast transformer cuts on the last chop bar.
- Deck app: live recognition in a loud room was never measured; tempo-only (master tempo) pitch takes about 20-30 s;
  hysteresis trades speed for stability (a blend switches only when the new song dominates for 10 s); no history
  strip; no line-in recording; cue times past 99 minutes in exported CUE files may not load in older players;
  TestFlight blocked only on the App Store Connect app record and account role.
- Data: the key detector is 60-80 percent accurate on vocal pop; about 30 tracks have wobbly grids (used only as
  cut-ins); the vocal detector is strict; `recs.md` and `summary.md` are from earlier runs.
- Naming: the owner chose **Deckie** after the Deckhand research found a live US registration DECKHAND (Reg. 6629861,
  fishing logbook software, classes 9/42). The deep check (`docs/naming/05-deckie.md`) scored Deckie 72.2 against
  Deckhand 71.4 and found that Deckie moves the problem rather than escaping it: DECKEE (a boating-safety app) is
  registered for class 9 software in the US with narrow goods, and in the EU, UK, Australia, NZ and Canada with broad
  "computer software" goods. Plan: brand "Deckie", "DJ" in the App Store subtitle, home deckie.dj, handle deckieapp.
  Allowed now: deckie.dj (after a registrar check), deckie.io, getdeckie.com, the deckieapp handles. On hold until a
  trademark attorney has reviewed DECKEE: deckie.com ($59,888 asking), any trademark filing, any public launch. The
  attorney questions are coexistence limited to DJ software and partial non-use cancellation of DECKEE's broad claim.
  Folders, bundle id and the deck-app/ target keep "deck" until the owner says to rename.
- The mix sets' leftover files (old three-hour renders, previews) were left in the original mixer/mixes folder;
  only cue, txt and render.json came here.

## 7. Feedback log (verbatim intent, in order)

1. Discs: "normalise the volume" (done; Mike had complained about level jumps on the first set).
2. Web player Up next: "waveforms aren't very helpful... zoomed enough and lines small enough to show where the best
   could match; pitch is important to him" -> beat-synced 8-samples-per-beat snippets, stacked lanes, PITCH chip.
3. "Expand to 10 options"; "lines connecting songs that the end matches the next song" (the mix map printout).
4. Deck app rounds (eleven of them): simplify; vertical centre; different background for now playing; remove
   headings and shuffle; hierarchy = song, disc location, BPM, waveforms; no chips he can't read; group Easy /
   Harder, randomised; narrower waveforms; folder path above the title ("CD1 / 6 - 125-129 /"), track number on the
   title line ("06 · Lady"); BPM and pitch one line in amber, smaller than the title; remove the countdown ("we
   recommend, not prescribe"), song time as the readout, "sync area" as a small note; Minimal is a toggle that
   only removes the pick waveforms (keeps the playing waveform); CD1 / CD2 / All as independent chips; pumpkin and
   RMX as corner chips; no orange fills; dark spooky blue for CD2; sync points numbered on the wave; recommended
   first sync marked; less bottom padding; move menus; a Halloween animation (lightning, ghost, pumpkin) when a
   Halloween song is recognised; hysteresis so the panel doesn't flip during long blends; set recording.
5. Mike live: "too many 'not mixable / brake'", "music style matters", "too much brake and filter out", "the range
   is wider for him" -> 16 percent, style term, blends first, options not verdicts.
6. Auto-mix listening: "needs more reverb or repeat loops, sounds like a crossfade"; "for hip-hop do quicker
   non-progressive, cut back and forth, scratches"; "if a song must end it should cut directly into the next, not
   fade"; later "much better... still a little safe; lulls between songs; bring beats from one song into the other
   staccato-ly; add human-driven random variance; document everything"; "more dance and remix-y, with a few
   downbeat or hard pop callouts; more disco house; two CDs continuous; then one CD, mixed into each other".
   All of Christopher's individually downloaded remixes/edits are favourites and should be represented.

## 8. Principles that held up

- Recommend, never prescribe. Show options and let the DJ choose. Confidence and position are approximations;
  never let them compete with the deck's own display.
- The DJ's own crate is the catalogue; the disc / folder / track location is the primary identifier.
- Pitch (the fader) is a first-class number. The matchable range follows the hardware (16 percent), not a theory.
- Style and era matter as much as key. Key is a warning when it clashes, not a score to maximise.
- Less text, more space, one accent colour used only for meaning (pinned, sync area). Minimal mode exists because
  waveforms are interesting but too much while actually mixing.
- Measure, then listen. Render logs catch alignment and level problems; only ears catch a boring join.
- Never modify or re-tag the source music; never normalise originals in place (the web player hard-links them).
- Never commit credentials: the FTP `.env` stays outside this repo; the uploader reads it by path.

## 9. How to run things here

- Point the data at a music folder (updated Oct 26, evening): the scripts now find the repo's own files by their
  location and the audio through `DECKIE_MUSIC_ROOT` (default: the original folder on Christopher's Mac). `pool.json`
  paths are relative to that root; `candidates.json` and the feature files carry absolute paths and are rebuilt by
  `build_candidates.py`. Disc outputs and the phone page's hard-linked tracks are written beside the audio. See the
  root `README.md`.
- Analysis for new tracks: `add_tracks.py <folder>` then `analyze.py --ids ...`, `local_tempo.py`, `score.py`.
- Web player data: `pool/newfiles/mike_data.py` then `mixer/add_mix_to_data.py`; upload with `ftp_upload_mike.py
  --env <path to .env> --local-dir <staging> --remote-dir auto`.
- Deck app: `cd deck-app && xcodegen generate`; data via `tools/prep_data.py` (uses the mixer venv); build, install,
  TestFlight: see `deck-app/README.md`.
- Auto-mix: `plan.py` (see README for the mixed-hour design, callouts, hip-hop stretches, picks) then `render.py
  plan_<n>.json`; `sampler.py` renders one clip per transition type; `build_mix_discs.py` makes the ISO.

## 10. Competitive summary (full report: docs/competitive-analysis.md)

Unique: mic-based identification against the DJ's own crate with pitch readout; join-level guidance. Closest:
Beatport Track ID and EarShot (global catalogue track ID), rekordbox Radar / VirtualDJ GeniusDJ / djay Match / Mixed
In Key (suggestions), DJ.Studio / djay Automix AI / Spotify Mix / Apple AutoMix (auto-mix, "glorified crossfade").
DJs ask for crate-scoped suggestions with genre sense and history, drift-following beatgrids, phrase countdowns,
phrase- and stem-aware automix with no dips, CUE/Mixcloud tracklist export, key as a guide, an iPad second screen.
Recommendation: keep it personal for now, two weeks of auto-mix fixes, then a 30-day TestFlight trial with 5-10 DJs;
never ship the bundled catalogue of commercial tracks; build catalogues from the user's own files.

Top ten (effort): listening QA per join (1-2 d); key gate on blends (0.5 d); Demucs stems for vocals and
drums-first blends (3-5 d); fix dips at the source, drop synthetic filler (2-3 d); energy-curve planning with ~2
percent tempo steps (2-3 d); loud-room recognition test and wider pitch variants (2 d); history strip, no repeats,
"why" line (1.5 d); line-in recording and CUE/Mixcloud export (1-2 d); learn from what the DJ actually played
(2 d); stay on development/TestFlight installs (0).

## 11. Suggested first week for the product agent

1. Recreate the environment (section 5) and confirm `analyze.py --ids <one id> --force`, `score.py`,
   `prep_data.py` and an app build all run from this folder. Fix the relative-path constants (section 9) so the
   repo is self-contained; decide where the music lives (a `MUSIC_ROOT` setting).
2. Listening QA of the final mix: cut the 20 s clips per join, listen, classify, and turn the findings into the
   key gate, the energy-curve planner and the dip fixes. Install Demucs and try drums-first blends on ten pairs.
3. Deck: a loud-room recognition test with a real speaker at 0, +4, +8, +12 percent; the history strip; CUE export
   of the set log; then an internal TestFlight build (needs the App Store Connect app record for
   io.christophershannon.deck).
4. Write down the product hypothesis and the trial plan from the analysis's 30/60/90-day section, and decide the
   catalogue story (user-built from their own files, on device).

## 12. Things not to do

- Do not redistribute the mixes or the catalogue; the audio is commercial. Mixcloud is the only sanctioned place
  for a mix.
- Do not put the FTP `.env`, API keys or the Apple account into the repo.
- Do not change the burned discs' numbering conventions without re-burning; the deck shows those names.
- Do not over-engineer the UI. Every round that removed something was welcomed.
