---
name: project-mixer-toolkit
description: The auto-DJ mixing toolkit built Oct 23-24, 2026 (analysis, pair scoring, mix map, player Up next) and what is still pending (mix CD not started, live page upload waiting on the FTP root)
metadata:
  type: project
---

Chris's second phase of the Halloween project is an auto-DJ toolkit in `_pool build/mixer/` (README there): a Python 3.14 venv at `.venv`, `analyze.py` (Beat This! + madmom beats, Essentia key and vocal timeline, structure, loudness; features cached in `features/<id>.json`), `local_tempo.py` (start and end tempo per track with a trust rule), `score.py` (directed A->B scores with reasons, `pairs.json`, `recs.json`), `add_mix_to_data.py` (writes a `mix` list into `Mike page/data.js` for the player's "Up next" slots), `build_mixmap.py` (interactive map artifact https://claude.ai/artifact/BRk439Zdyz942HKb9bdZz6, shared with anyone with the link) and `build_print.py` (one-page landscape printout `CDs v3/Mix map - CD1 and CD2.pdf`, CD1 | CD2 | CD1 columns). All 346 candidates (four v2 discs plus additions) are analysed; the 90 disc tracks are the scoring targets.

**Why:** Mike wants to know which songs mix into which, and Chris wants a 2 to 3 hour pre-mixed DJ set CD from the unselected tracks for when Mike is off the decks (not started as of Oct 24, 2026).

**How to apply:** after any selection change run `newfiles/mike_data.py` then `.venv/bin/python -I add_mix_to_data.py`, then rebuild the maps; add new tracks (transition edits go in `transitions/`) with `add_tracks.py` and re-run `analyze.py --ids`. Chris said not to over-engineer the scoring further. The updated player files plus 21 extended MP3s and `.htaccess` are staged in `_pool build/mike_push/` and still need Chris to upload them (see [[project-mike-page-hosting]] for the FTP root problem). Loudness normalisation is still owed on the next disc build: [[project-cd-loudness-todo]].

**To do when Chris is home (noted Oct 24, 2026):** add "Got To Do" by Disco Lines to the pool (drop the file in the playlist folder, `newfiles/probe_new.py`, a NEW entry in `pool_build.py`, then `build_candidates.py`, `analyze.py --ids`, `score.py`) and place it in the matching pre-mixed set (the disco / dance stage) with a re-plan and re-render of that hour. Also pending: install the hardened Deck build on the iPad with the command in `Deck app/README.md`.

**Scoring change (evening of Oct 24, 2026, from Mike's live feedback):** the tempo term now allows beat-matching up to 12 percent stretch (a CDJ fader's reach; brake only beyond it or on non-octave ratios, half/double time at a small penalty) and a `style` term (remix/house vs pop original, era, Halloween) weighs 0.13 with timbre raised to 0.12 (weights in `score.py` W). Mike's complaint was too many "no beat-match · brake" picks and style being ignored. The web player data and the Deck app data were regenerated; the Deck app's own "PITCH n/a" cutoff is 12 percent too. The continuous Halloween mix was burned and read-back verified that evening.
