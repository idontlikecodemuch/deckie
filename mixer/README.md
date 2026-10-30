# mixer: per-track analysis + pairwise "A mixes into B" scoring

First half of the auto-DJ toolkit described in `research.md` (sections A, B.9, B.10, E.1-E.3).
Source MP3s are only read; nothing is cached except `features/<id>.json`.

## Environment

`.venv` was built with `/opt/homebrew/bin/python3.14` (torch has no 3.15 wheel), following research.md E.1:

```
/opt/homebrew/bin/python3.14 -m venv .venv
.venv/bin/pip install -U pip setuptools wheel cython "numpy<3"
.venv/bin/pip install --no-build-isolation "git+https://github.com/CPJKU/madmom"
.venv/bin/pip install torch torchaudio soxr einops tqdm rotary-embedding-torch beat-this
.venv/bin/pip install librosa soundfile pedalboard pyloudnorm scipy
.venv/bin/pip install essentia-tensorflow          # never plain `essentia` as well
```

Versions installed: numpy 2.5.4, torch 2.14.1 (MPS), beat-this 1.1.0, madmom 0.17.dev0 (git 27f032e),
essentia-tensorflow 2.1b6.dev1438, librosa 1.0.0, soundfile 0.14.0, pyloudnorm 0.2.0, pedalboard 0.9.26,
soxr 1.1.0, scipy 1.18.1. Nothing from Homebrew and nothing system-wide.
The Essentia models live in `models/` (Discogs-EffNet + voice_instrumental head).

## Running

Always call the venv's python by path (from this folder):

```
M="/Users/christophershannon/personal/90s2000 playlist/_pool build/mixer"
cd "$M"
# analysis (resumable: skips ids whose features/<id>.json exists)
nohup .venv/bin/python analyze.py > analyze_full.log 2>&1 &
.venv/bin/python analyze.py --ids c546b63944,50b4b2b2aa --force      # re-do some tracks
.venv/bin/python analyze.py --limit 10 --madmom never                # options: always|auto|never
# scoring + summary (work on whatever features exist)
.venv/bin/python score.py      # -> pairs.json, recs.json, recs.md
.venv/bin/python summary.py    # -> summary.md, summary.tsv
```

`analyze.py` prints one line per track; per-track exceptions go to `analyze_errors.log`
(`--log PATH` to change) and the run continues. Output JSON is written atomically.

Timing on this Mac (M-series, Beat This on MPS): about 10-13 s for a 3-4 minute track without madmom,
about 27 s for an 8.6-minute extended mix, +13-18 s when madmom runs (auto mode only runs it on doubtful tracks).
The largest fixed costs are madmom's key CNN (~5-7 s, CPU numpy) and loudness/filters (~3 s).

## analyze.py: what it computes

Decode once with soundfile (float32, 44.1 kHz; resampled with soxr only if a file is not 44.1 kHz);
the same arrays feed every analyser (Beat This takes the array directly through `Audio2Beats`,
so no temp WAV is written). Mono = channel mean.

* **Beats/downbeats**: Beat This `final0` on MPS (falls back to CPU). A constant 4/4 grid is fitted by
  least absolute deviation (IRLS on integer beat indices with two global re-indexing passes, which makes
  it robust to missed/extra beats); the downbeat phase is the beat phase (of 4) carrying most detected
  downbeats. `grid.fit_mad_ms` = median |detected beat - grid|; `grid.confidence` =
  `inlier_frac(<70 ms) * (0.5 + 0.5*downbeat_agree) * max(0, 1 - max(0, mad_ms - 5)/50)`.
* **Tempo votes**: `bpm_tag`, `bpm_beatthis` (grid fit), `bpm_essentia` (RhythmExtractor2013), and `bpm_madmom`
  when madmom ran. `--madmom auto` runs madmom RNN + DBN(beats_per_bar=[4]) when the Beat This grid
  confidence < 0.5 or the Beat This BPM differs from the tag by > 2% after x1/2, x1, x2 normalisation; the
  chosen grid is the one within 2% of the tag (after octave normalisation), then the lower MAD.
  `bpm` is the chosen grid's tempo (the tag is never trusted over the grid); `multiplier_vs_tag` is the
  element of {1/2, 2/3, 3/4, 1, 4/3, 3/2, 2} closest to bpm/tag; `bpm_agree` = within 1% of the tag after
  octave normalisation.
* **Bars**: bar 1 starts at the first grid downbeat at/after first sound (minus a quarter beat).
  `downbeats_s` / `beats_s` are the *grid* positions (spacing exactly 240/bpm and 60/bpm);
  the raw tracker output is in `detected_beats_s` / `detected_downbeats_s` (+ `madmom_downbeats_s`).
  All per-bar arrays have length `grid.n_bars`; bar numbers in JSON are 1-based and `end_bar` is exclusive.
* **Key**: Essentia KeyExtractor `edma` and `bgate` + madmom CNNKeyRecognitionProcessor; Camelot per A.2.
  Confidence (B.9, made concrete): all three agree -> 1.0 (0.6 if the Essentia strength < 0.6);
  two agree and the dissenter is a Camelot neighbour (same, +/-1, relative) -> 0.65; two agree otherwise
  -> 0.45; any two-of-three case with strength < 0.6 -> 0.3; no agreement -> 0.3 (edma's key is used).
  If madmom fails: edma == bgate and strength >= 0.6 -> 0.7, else 0.3. `key_uncertain` when < 0.5.
* **Structure**: Foote novelty (B.1): 13-MFCC cosine SSM and RMS-dB absolute-difference SSM at half-beat
  frames, 64-frame Gaussian checkerboard, geometric mean, top-20 peaks (>= 1 bar apart), snapped to downbeats
  (discarded if > 0.4 bar away), then the 8-bar lattice phase with the largest summed novelty.
  `phrase.confidence` = 0.6 * (lattice share of peak novelty) + 0.4 * (margin over the runner-up phase).
  `boundaries_bars` = the on-lattice peaks plus start and end; `sections` get `energy` high/low (section
  loudness vs the median bar loudness - 1.5 LU) and a label intro / main / break / outro.
* **First/last sound**: first/last 10 ms frame whose peak exceeds -60 dBFS (Mixxx rule).
* **Fade-out**: short-term (3 s, K-weighted) loudness 20 s before last sound minus the last 3 s > 6 dB **and**
  at least 3 bars between the last body-level bar (>= median bar loudness - 2 LU) and last sound
  (so a hard stop with a short decay is not a fade). Long decaying tails after a hard stop also count;
  either way the end is unusable for a blend. With a fade, `mix_out` ends at the last lattice point before
  the fade begins.
* **Mix windows** (`mix_in`, `mix_out`): mix-in starts at bar 1. If the vocal-free intro (vocal prob < 0.5)
  is >= 8 bars it is the available length, otherwise the distance to the first boundary. Length = 32 if
  available and >= 16 of those bars are vocal-free, else 16 if available, else 8 (minimum). The end is snapped
  to the 8-bar lattice; when `phrase.confidence` < 0.35 the lattice is assumed to start on bar 1
  (`phrase.snap_phase_bar`). The mix-out window is the mirror image, ending at the last full bar (pulled back
  to the lattice if within 4 bars) or at the fade start. Each has `vocal_free_bars`.
* **Loudness**: pyloudnorm integrated LUFS and LRA; true peak from 4x `resample_poly` oversampling in 10 s
  blocks. Per bar: `lufs_st` (K-weighted mean square over the bar), `low_db` (< 150 Hz) and `high_db` (> 4 kHz)
  from LR4 (two cascaded Butterworth-2) splits, `onset_density` (librosa onsets per beat), `vocal_prob`.
* **Vocal + embedding**: one Discogs-EffNet pass on 16 kHz audio gives 1280-d patch embeddings (mean-pooled to
  `embedding_effnet`) and the voice/instrumental head's per-patch probability (hop 0.992 s, centred +1.024 s)
  averaged into bars. `vocal.mean_prob`; `vocal_heavy` when > 0.75.
* **onset_pattern_16**: librosa onset strength, max within each eighth-note cell, 2 bars x 8 cells, averaged
  over all bar pairs whose loudness is within 10 LU of the median, normalised to max 1.
* **Flags**: `half_time_candidate` (bpm < 100 or multiplier_vs_tag != 1), `vocal_heavy`, `fade_out`,
  `low_grid_confidence` (< 0.5), `key_uncertain` (< 0.5), `short_intro` / `short_outro` (window < 16 bars or
  < 8 vocal-free bars).

### Feature JSON (main fields; layout follows research.md E.2)

```
id, title, ver, path, sr, duration_s,
bpm_tag, bpm_beatthis, bpm_essentia, bpm_madmom, bpm, bpm_agree, multiplier_vs_tag, tag_dev_pct,
madmom_ran, madmom_reason, essentia_agree,
grid {source, bpm, first_downbeat_s, beat_s, bar_s, fit_mad_ms, inlier_frac, downbeat_agree, confidence, n_bars},
grid_candidates {beatthis|madmom: {bpm, fit_mad_ms, confidence, tag_dev_pct}},
beats_s, downbeats_s (grid), detected_beats_s, detected_downbeats_s, madmom_downbeats_s,
phrase {lattice_phase_bar, phrase_len_bars, confidence, phase_novelty[8], snap_phase_bar},
boundaries_bars, novelty_peaks [[bar, value]], sections [{start_bar, end_bar, label, energy, lufs, vocal}],
first_sound_s, last_sound_s, fade_out, fade_drop_lu, end_lufs_st, tail_bars, fade_start_bar,
mix_in {start_bar, end_bar, bars, start_s, end_s, vocal_free_bars, first_vocal_bar},
mix_out {start_bar, end_bar, bars, start_s, end_s, vocal_free_bars, last_vocal_bar, fade_out},
key {essentia_edma [key, scale, strength], essentia_bgate [...], madmom_cnn [key, scale, prob],
     camelot_edma, camelot_bgate, camelot_madmom, camelot, confidence, confidence_rule},
loudness {integrated_lufs, lra, true_peak_db},
per_bar {lufs_st, low_db, high_db, onset_density, vocal_prob},
onset_pattern_16, vocal {mean_prob, vocal_heavy, patch_hop_s, n_patches}, embedding_effnet [1280],
flags, meta {secs, on_disc, disc, folder, hal, kind, era, cut_key, is_longest}, timing_s, beatthis_device
```

## score.py: the formula (research.md B.10)

For every directed pair A -> B (A's `mix_out` against B's `mix_in`; pairs sharing a `cut_key` are skipped):

* **tempo**: k in {1/2, 2/3, 3/4, 1, 4/3, 3/2, 2} minimising |log(bpm_B*k/bpm_A)|; stretch % = |r-1|*100.
  1 up to 3%, linear to 0 at 8%; 8-10% gets a floor of 0.05 (so "tempo > 0" and "reject beyond 10%" both hold);
  > 10% rejected. k != 1: -0.15 (floor 0.01) and the reason "half-time/double-time blend".
* **key**: B.9 table (same 1.0; +/-1 0.90; relative 0.85; +2 0.65; +/-7 0.50; -2 0.45; else 0.15); a pitch shift of
  B by s in {+/-1, +/-2} semitones that lands in {same, +/-1, relative} offers 0.85 - 0.12|s|;
  key = max(raw, shifted) * (0.5 + 0.5*min(conf_A, conf_B)).
* **energy**: dE = (B mix-in bar loudness - B integrated) - (A mix-out bar loudness - A integrated), power mean
  over the window bars; energy = 1 - clip(|dE| - 2, 0, 8)/8. Sign kept in `energy_delta_lu`.
* **vocal**: overlap L = min(A mix-out bars, B mix-in bars); v = mean(P_A * P_B) over A's last L outro bars and
  B's first L intro bars; vocal = 1 - v, +0.1 (capped at 1) if B's first 16 bars are all < 0.5.
* **phrase**: grid_conf_A * grid_conf_B if A outro >= 16 and B intro >= 16 bars, else 0 with reason
  "only N-bar window (quick blend)".
* **timbre**: cosine of mean EffNet embeddings, rank-normalised over all pairs in the analysed pool.
* **rhythm**: max(0, Pearson r) of `onset_pattern_16`; for k = 2 or 1/2 the half-tempo track's pattern is folded
  to one bar and stretched to 16 cells first; other multipliers get a neutral 0.25.

`score = 0.26 tempo + 0.14 key + 0.11 energy + 0.11 vocal + 0.08 phrase + 0.12 timbre + 0.05 rhythm + 0.13 style` (the weights `W` in score.py since Oct 24; the earlier 0.30/0.20/0.15 formula is what recs.md from older runs prints),
plus +0.03 when the *recommended* track (B for outgoing, A for incoming lists) is >= 270 s ("longer cut").
Gates: stretch <= 10%; v > 0.5 only with `quick_blend_echo` (echo-out) or `brake_cut` (cut).

`suggested_transition` (E.4): `brake_cut` if either grid confidence < 0.3, or k != 1 and rhythm < 0.5;
v > 0.5 -> `quick_blend_echo` (or `brake_cut` above 8%); stretch > 6% -> `ramped_blend`; v < 0.2 and both
windows >= 16 bars -> `bass_swap_32` (both >= 32) or `bass_swap_16`; v >= 0.2 -> `quick_blend_echo` when A's outro
is the more vocal side, else `filter_sweep`; otherwise `filter_sweep`.

`reasons`: the three largest positive terms plus every term below 0.4, as short strings, plus "longer cut".

Outputs:
* `pairs.json`: `{n_tracks, threshold, weights, pairs:[{a, b, score, score_base, terms{...}, stretch_pct,
  multiplier, suggested_transition, reasons, vocal_overlap, overlap_bars, key_shift_st, energy_delta_lu}]}`
  for every directed pair with score >= 0.45.
* `recs.json`: per track id `{title, on_disc, disc, folder, bpm, camelot, disc:{out[8], in[8]}, pool:{out[8], in[8]}}`.
  "disc" candidates are the on-disc tracks; "pool" candidates are all analysed tracks. In both views one track
  per `cut_key` is kept (the `is_longest` one, else the longest analysed cut), and a track is never paired with
  another cut of itself.
* `recs.md`: on-disc tracks by disc and BPM folder with their top 3 disc-view matches, the 20 strongest pairs,
  and the tracks without any match >= 0.6.

## summary.py

`summary.md` / `summary.tsv`: title, bpm_tag, bpm, multiplier, grid confidence, Camelot key, key confidence,
integrated LUFS, mean vocal probability, mix-in/out bars, flags; sorted by grid confidence ascending.

## Known limitations

* One constant grid per track. Live/older recordings with drifting tempo (e.g. Monster Mash, grid confidence
  0.29) get low confidence and `brake_cut` suggestions rather than a piecewise grid.
* The phrase lattice comes from novelty alone; on vocal pop it is often weak (confidence 0.2-0.3), in which
  case windows snap to bar 1 + 8k. Expect some 4-bar phrase offsets; treat `phrase.confidence` seriously.
* The EffNet voice head reads "voice" on most pop bars (mean 0.85-1.0), so many tracks get 8-16 bar windows,
  `short_intro`/`short_outro` and vocal-clash penalties; DJ edits with real instrumental intros stand out.
  A Demucs vocal stem (not installed yet) would be the upgrade.
* The 3/4 and 2/3 multipliers are allowed by B.10 and score well on tempo even though they cannot be blended;
  the transition rule turns them into `brake_cut`.
* Key detection on vocal pop is 60-80% at best; key is a confidence-weighted soft term, never a filter.
* Timbre uses whole-track mean embeddings, not window embeddings, and is rank-normalised within the
  *current* analysed set, so scores shift slightly as more tracks are analysed.
* madmom and the Essentia models are CC BY-NC-SA (fine for a private party mix).

## Added Oct 24, 2026: the rest of the pipeline

Run everything with the venv's python from this folder, in this order after any change to the pool or the selection:

1. `build_candidates.py` — rebuilds `candidates.json` from `newfiles/pool.json` (every non-library row: the four v2 discs plus additions) with `on_disc`, `on_page`, `cut_key` and `is_longest` (the longest cut of a song version wins in recommendations). Rows added with `add_tracks.py` are kept.
2. `add_tracks.py <folder> [--kind transition]` — registers new MP3s that are not in the pool (for example DJ transition edits dropped into `../../transitions/`) and prints the `analyze.py --ids ...` command for them.
3. `analyze.py [--ids a,b] [--force]` — per-track features (see above). Since Oct 24 it also aligns the beat grid to the tag's octave when the tracker sits at exactly double or half the tag (`octave_fix`), tries two grid estimators and keeps the one with more inlier beats (`grid.method`, `period_spread_pct`), and calls `local_tempo.py` for start and end tempo.
4. `local_tempo.py [--force]` — start/end/windowed tempo from the raw detected beats by regression (`local_tempo` block: `bpm_in`, `bpm_out`, trust flags, `steady_in_bar`, 15 s profile). A window is trusted only when its beats fit a steady period within 15 ms; otherwise the global grid stands in and the end is flagged `intro_no_steady_beat` / `outro_no_steady_beat`. Backfills existing features.
5. `score.py` — directed pairs. Uses A's `bpm_out` against B's `bpm_in`; 2/3, 3/4, 4/3 and 3/2 relations are capped at 0.35 on the tempo term (transition-track territory); the phrase term is graded from 8 to 16 bars; ends without a steady beat drop the phrase term and suggest an echo-out or cut.
6. `mixwaves.py [--force]` — beat-synchronous waveform snippets of every page track's mix-out window (plus 8 bars of lead-in) and mix-in window (plus 8 bars after), 4 RMS samples per beat on the fitted grid, base64 like the page's `wave`. Output `mixwaves.json`, used by the player's join view.
7. `add_mix_to_data.py` — writes into `../../Mike page/data.js` and `data.json`, per track: `mix` (up to 12 best next tracks on the discs with score, stretch, multiplier, `pitch` = CDJ pitch-fader percent for the incoming deck, transition, keys, short label and reasons), `mixIn`/`mixOut` seconds, `bpmIn`/`bpmOut`/`bpmM`, `key`/`keyConf`, steadiness flags, `dur`, and the `wOut`/`wIn` snippets with `spb`. Run it after `newfiles/mike_data.py` (which regenerates data.js without these fields).
8. `build_mixmap.py <out.html>` and `build_print.py [topK] [minScore]` — the interactive map (artifact https://claude.ai/artifact/BRk439Zdyz942HKb9bdZz6) and the one-page landscape printout in `../../CDs v3/`.

`../newfiles/apply_mike.py` reads the report Mike sends back; it now also parses `CHAIN <name>: id>id>id` lines and saves them to `newfiles/mike_chains.json`.

## To do
- Add "Got To Do" by Disco Lines (Chris, Oct 24): probe, NEW entry in pool_build.py, build_candidates, analyze --ids, score; then re-plan and re-render the set it belongs in (disco / dance stage).
- Install the hardened Deck app build on the iPad (see Deck app/README.md).

---

# Part 2: mix planner and offline renderer (Oct 24, 2026)

Second half of the auto-DJ toolkit: `plan.py` chooses and orders the songs of two continuous ~72-minute mixes and
decides every join; `render.py` renders them to mastered MP3s; `sampler.py` renders one clip per transition type.
The DJ technique and every number below follow `transition-recipes.md` (how working DJs do echo-outs, reverb throws,
cuts on the one, chops, scratches, loop rolls, bass swaps, tempo bridging and set arcs, with sources) and research.md
sections C and E.4-E.5.

## Running

```
M="/Users/christophershannon/personal/90s2000 playlist/_pool build/mixer"; cd "$M"
.venv/bin/python -I plan.py                       # -> plan_mix1.json, plan_mix2.json, mixes/mix_<n>_tracklist.txt (~15 s)
.venv/bin/python -I render.py plan_mix1.json      # -> mixes/1 - Haunted Disco.mp3 (+ .cue, .txt, .render.json), ~5 min
.venv/bin/python -I render.py plan_mix2.json      # -> mixes/2 - Witching Hour Warehouse.mp3 ...
.venv/bin/python -I render.py plan_mix1.json --preview 5   # first 5 joins only -> mixes/preview.mp3
.venv/bin/python -I sampler.py                    # -> mixes/transition-examples.mp3 + .txt
.venv/bin/python -I plan.py --hours 1,2,3         # the older three one-hour plans (plan_1..3.json), kept for reference
```
`render.py --one-pass` skips the lull measurement/fix pass (faster, for experiments).

**One continuous file (the MP3 CD)**: `plan.py --full` joins `plan_mix1.json` and `plan_mix2.json` into
`plan_full.json`: mix 1's last song gets a real exit (its mix-out window instead of playing to the end) and a seam join is
planned into mix 2's first song with the same join rules (a beat-matched blend if the pair allows; otherwise a loop roll +
riser into B on the one, or a brake when A's end has no steady beat). Then
`.venv/bin/python -I render.py plan_full.json` writes `mixes/Halloween Mix - full.mp3` with one `.cue` and one `.txt`
tracklist whose timestamps run straight through (about 145 minutes, ~20 minutes to render with the three lull passes).
Re-run `plan.py --full` after any change to either mix plan. The full file uses its own variance seed (1003), so its
nudges differ slightly from the two separate halves.

## plan.py: the planner

**Inputs**: `candidates.json`, `features/<id>.json`, `pairs.json` (all read fresh on every run), and
`keep_from_sampler.json` (songs Chris approved in the sampler; they must stay in their mix).

**Pool**: off-disc tracks (`is_longest`, kbps >= 200, cut_key not on a disc) + Mike's CD1 (disc "S", singalongs and
Halloween remixes) with a penalty and a cap of 4 per mix; CD2 (disc "M", Mike's house lane) is excluded except tracks
Chris named. `MUST` (top of plan.py) lists Chris's picks with the mix and role each is assigned to (block / flow /
callout); `EXCLUDE` lists removed tracks and the other cuts of picked songs (so the version Chris named is the one used).
One song per title across both mixes (covers count as the same song); no artist twice in a row.

**Variants** of each track (all share the song): the full *flow* version (cue at the mix-in window, exit at the mix-out
window or an earlier phrase boundary so a play lasts 150-215 s); a *callout* version (`#co`) for slow / pop / novelty /
loose-grid songs, played from the hook for 85-125 s; a *hip-hop stretch* version (`#hh`) cued 2 bars before the hook and
exiting on a phrase boundary 55-95 s later. The hook = first high-energy "main" section within 40 bars of the intro,
else the first vocal bar.

**Shape** (beam search, width 160, over the pairs graph; `plan_mix`):
* flow follows a tempo arc 119 -> 129 BPM over 72 minutes (`MIX_ARC`), remix/edit versions preferred (+0.18), pop and
  hip-hop originals penalised in the flow; mix 1 leans disco-house and pop remixes, mix 2 harder house and Halloween;
* 3-4 callouts per mix (between 10 % and 85 %, at least 4 songs apart): entered by vinyl brake, echo-out, backspin or
  slam (rotating), left by riser + slam or echo-out + riser onto the next track's hook/drop;
* one hip-hop quick-mix stretch per mix, 8-10.5 minutes at 90-112 BPM, entered between 25 % and 60 % by echo-out or brake
  (mix 1 enters through the Get Ur Freak On Bizzon Halloween 70->90 transition edit), records 55-95 s each joined by a
  slam on the one or a 2-2-1-bar chop (alternating) with a scratch stab, left by riser + slam back to 118+ BPM;
* 5-6 Halloween songs per mix spread over the thirds; mixes 70-74 minutes;
* join value = pairs.json score (+0.08 for 16/32-bar bass swaps, +0.03 for 8-bar / filter sweep), tempo-arc fit,
  flavour/lean bonuses, +0.8 for a must-include.

**Join rules in the flow** (`Edges.get`): beat-matched blend only when both grids are trusted at that end and the tempo
gap is <= 6 % (4-6 % only for beat-only windows, as a tempo-ramped bass swap); 16-bar bass swap when the 16-bar vocal
overlap is < 0.25 and both windows are 16 bars (32 bars when 32 bars are beat-only), otherwise an 8-bar bass swap when the
vocals allow (< 0.6 over 8 bars), a 16-bar high-pass sweep when B's intro is clean and A's outro is vocal, else A ENDS
with an effect (echo-out / loop roll / reverb throw, rotating) and B cuts in on the one; vinyl brake when A's end has no
steady beat. A pitch shift of +/-1 semitone is applied to B when the pair's reasons say so. Teasers are planned on about
half of the flow joins and every hip-hop cut (not into callouts, not where B's tempo is more than 8 % away).

**Output** `plan_mix<n>.json`: `songs` (id, path, cue_in bar/time/mode, exit bar/time/mode, grid, flags, callout /
hiphop_stretch / must / on_disc) and `joins` (type, overlap bars, cue bars on both sides, stretch and which side carries
it, pair score and reasons, scratch / backspin / riser / teaser / key_shift_st, readable `name`). Edit it by hand (change a
join `type`, `overlap_bars`, cue or exit `bar`, the flags) and re-render; render.py recomputes all geometry from it.
The tracklists `mixes/mix_<n>_tracklist.txt` mark H = Halloween, C = callout, Q = hip-hop stretch, ! = Chris's pick,
* = Mike's CD1.

## render.py: the renderer

**Per song**: decode once with soundfile (soxr to 44.1 kHz if needed), normalise to -14 LUFS (pyloudnorm), play only
between first and last sound; optional pitch shift (Rubber Band, formant-preserving). Songs are laid on their constant
beat grids; every played bar boundary maps to an output sample. Inside an overlap both songs use identical integer bar
positions, then a phase lock shifts B so the two songs' *tracker* beats line up (median offset, logged as `phase_corr_ms`).
Tempo: `pedalboard.time_stretch` with a per-sample stretch array, staircase per bar, ramping from A's tempo to B's across
the overlap; `high_quality=False` (the R2 engine) because the R3 engine drifts 1.5-2 ms/s on this build.
The running mix is streamed to a float WAV (only ~one song in memory).

**Transitions** (bar timelines; bar 0 = first overlap bar or the cut downbeat; LR4 3-band split at 200 Hz / 2.5 kHz with
mid = signal - low - high):
* `bass_swap_8/16/32`, `ramped_blend` (16 bars): B enters with mids and highs at -6 dB (-2.5 dB after a measured lull),
  highs full by bar M/2, mids full by bar M; B's bass is killed until the swap bar M = L/2 (varied, below); at M the
  basses change hands within 1/8 bar (low gains sum to 1); A's highs fall to -6 dB at M and out by 1.5 M, A's mids
  fade M -> L (dipped 4 dB when the timbres differ); A is gone at bar L.
* `filter_sweep` (16): A high-passed 30 Hz -> 4 kHz (24 dB/oct, log ramp) at full level and stopped at the exit; B as above.
* `echo_out`: A's last 2 beats (lows removed) feed a delay of 3/4 beat (or 1/2), feedback 0.81-0.91, 1-pole LP 5 kHz +
  HP 250 Hz in the loop, wet -4 dB, 3-4 bars of tail at its natural decay; A's dry signal is cut on the exit downbeat
  (5 ms); B starts on that downbeat at full level, bass in.
* `reverb_out`: A's last bar ramps into a short room reverb (room 0.6, damping 0.55, HP 250 Hz, LP 7.5 kHz, -6 dB),
  dry cut on the one, at most 2 bars of tail.
* `loop_roll`: A's last bar replaced by its first beat looped 1/2 beat x4, 1/4 x4, 1/8 x4, 1/16 x4 with a high-pass rising
  40 Hz -> 2 kHz and +3 dB; noise riser over the last 4 bars; B on the one with a sub impact.
* `brake_cut`: one bar of vinyl brake from A's last downbeat (rate (1-t)^1.7, gain following, tracking low-pass); or
  `backspin` (once per mix): beats 1-2 play, then the platter is yanked back (rate 1 -> -3 -> 0) at -6 dB; B on the one.
* `slam`: B's hook/drop downbeat replaces A's exit downbeat (5 ms seams); in the hip-hop stretch A's last beat is replaced
  by a 1-beat baby scratch (chirp-gated) of B's entry slice; out of callouts and the stretch a noise riser + sub impact.
* `chop` (hip-hop stretch, 5 bars, B running at A's tempo): A 2 bars / B 2 bars / A 1 bar / B; hard 3 ms crossfader cuts
  so only one side (and one bass, one vocal) is heard; a scratch stab replaces A's last beat before B's first segment,
  which starts on B's hook.
* Risers: white noise through a band-pass sweeping 200 Hz -> 8 kHz with rising gain and a 1/16 tremolo, ending on B's
  downbeat; impact: 38-88 Hz sine drop + noise burst.

**Teaser layer** (`teaser` joins): B's drum section (bass off) is varispeeded to A's tempo and gated into A as stabs:
bar -4 one beat (HP 300 Hz), bar -2 half a bar (HP 700 Hz), bar -1 beats 3-4 transformer-gated in 1/16s (HP 1.5 kHz),
so the next song announces itself (skipped on the brake/roll bar).

**Human variance layer** (seeded, default seed 1000 + mix number, logged with every per-join value in `variance`):
beat-sync nudge of 2-8 ms that is corrected over B's first bar; 1 in 5 cuts a 16th early or late; pitch-fader wobble of
0.1-0.3 % alternating and settling over the 4 bars after a blend; echo division (3/4 or 1/2 beat), feedback (+/-0.03) and
tail length (3-4 bars) per join; fader-timing jitter of 10-40 ms on the mid/high moves; the bass-swap bar moved by +/-1
(8-bar) or +/-2 (16-bar) on 2 in 5 blends. Same seed + same plan = identical render.

**Lull check and fix** (`render_checked`, default): pass 1 renders the premaster and measures the 3-second K-weighted
short-term loudness through every join (3 s before to 6 s after the overlap) against the median of the surrounding
~30 s on both sides, plus 25 ms near-silence (< -45 dBFS) runs longer than half a beat. Joins more than 2 LU below
the music get a fix and the mix is rendered again: blends keep A's mids up longer and B's entry hotter, plus (when the dip
is at the end of the overlap or after it) up to +4 dB make-up on B for 4 bars and a synth kick/hat beat element on B's
grid; cuts get the make-up + beat element after the cut, or a riser before it. A second measurement escalates the fixes for joins that still dip (make-up up to
+6 dB, a stronger beat element, and for dips in A's last bars before the join: make-up on those 4 bars plus the beat
element on A's grid, and a riser before cuts); the third pass is the one mastered. All passes are in the render log
(`lulls_pass1`, `lulls_pass2`, `lulls`, `fixes`). Near-silences that are part of a record itself (stop-beats in
Goodies, Poison, the No Scrubs cover) are reported but not filled.

**Mastering**: gain into `pedalboard.BrickwallLimiter` (true peak, ceiling -1.8 dBTP so the MP3 lands near -1 dBTP,
release 80 ms), iterated (secant on the measured loudness, keeping the closest pass) to -10 LUFS integrated like the
burned discs; encoded with ffmpeg libmp3lame CBR 320; final loudness and true peak measured on the MP3 with ffmpeg ebur128.

**Outputs** in `mixes/`: `<n> - <name>.mp3`, `.cue` (track starts at the bass-swap point or the cut), `.txt` (readable
tracklist with times, BPM, key and join), `.render.json` (seed, every join's parameters, variance, teaser, fix,
phase correction, residual beat offset, lull measurements, loudness, peak, timings, sanity checks: no clipping, no silent
gaps, joins within 10 ms, duration vs plan). Temporary WAVs go to `mixes/_work/` and are deleted.

## sampler.py
One 60-75 s clip per transition type from real pairs in the two plans (types not in the plans are forced onto a real
pair and marked), 1 s of silence between clips, mastered like the mixes; list in `mixes/transition-examples.txt`.

## After adding a track
1. register/analyse it (Part 1: `add_tracks.py`, `analyze.py --ids ...`, then `score.py` for new pairs);
2. to force it into a mix add its id to `MUST` in plan.py (mix, role), or to keep it out add it to `EXCLUDE`;
3. `plan.py`, check the tracklists, then `render.py plan_mix1.json` / `plan_mix2.json` and `sampler.py`.

## sprint_check.py (Oct 29, 2026): a Deckie crate against the sprint's data
`python3 sprint_check.py <crate.deckiecrate>` joins the sprint's pool (`<music folder>/_pool build/newfiles/pool.json`
and `mixer/candidates.json`) with a crate by file path (files the build dropped as duplicates follow the import log
to the file that has the record) and writes `sprint_check.tsv` and `sprint_check.md`. The sheet keeps the two kinds
of sprint data apart, as the D5 note of Oct 29 asks: the `fact.` columns are the known facts (artist and song name,
from the compilations' own tags and the disc map) and the `early.` columns are what the early version decided (BPM
with its overrides and folded values, the lab's key for the 373 candidates, era, kind, the Halloween flag, cut_key).
Agreement with an `early.` column is agreement, not correctness. Deckie writes no era, kind, Halloween flag or cut_key
yet, so those are reported as sprint-only.

## key_downbeat.py (Oct 29, 2026): chroma weighted toward the beat grid, on the outside set
`.venv/bin/python key_downbeat.py <mu outdir> <manifest.json> [--jobs 2]` reads the beat grid Apple's run wrote for
each GiantSteps clip (tools/mubench output) and scores the recommended reader (3f) with four fixed frame weightings:
equal (reproduces `key_outside_results.tsv` clip for clip), downbeat frames only, beat frames only, and metrical
(downbeat 1, beat 1/2, between 1/4). Writes `key_downbeat.tsv` and prints the table overall, per major and minor
half, and per data set confidence level. Nothing is tuned and no variant is chosen by the script.

## key_outside_apple.py (Oct 29 to 30, 2026): Apple's key on the outside set
`.venv/bin/python key_outside_apple.py <mu outdir> [key_outside_apple.tsv]` reads the key Apple's framework wrote for
each GiantSteps clip (tools/mubench output; the longest key range), scores it against the annotation beside the
stored row 3f (`key_outside_results.tsv`) and writes the per-clip sheet. The full run's sheet is committed
(`key_outside_apple.tsv`, 1,270 clips; Apple gave no key on 5). The tables in letter R were computed from it with
`key_parity.relation`, which names the fifth, relative and parallel classes the MIREX weighting needs.
