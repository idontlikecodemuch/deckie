# DeckieAnalysis: analysis port plan and the stage 1 benchmark

Dated Oct 26, 2026. Companion to `overview.md` (the top-level map, written separately) and to track A,
`docs/research/a-on-device-analysis.md` (the decision record; the crate schema is its section 5). This document
covers only the analysis: what moves from `mixer/analyze.py`, `mixer/local_tempo.py`, `mixer/score.py` and
`deck-app/tools/prep_data.py` into Swift, the benchmark that runs before any engine code (spec section 7, stage 1),
the package that results, and the risks. Facts come from those files, `mixer/README.md`, the 373 feature files and
`candidates.json`; [inf] marks inference.

Conventions. "MU" is a Music Understanding result. "Port" means the Python block is rewritten in Swift; "vDSP" in
the disposition means it needs Accelerate, otherwise it is plain Swift over arrays. Size: small is under about 60
lines of Swift, medium 60 to 200, large over 200 or involving a model. Bar numbers stay 1-based with an exclusive
`end_bar`, as in the lab. Line numbers refer to the files at commit 96e116c.

## 1. Inventory: analyze.py and local_tempo.py

Measured on the 373 feature files, as calibration for what matters: median track 232 s and 114 bars; grid
confidence under 0.5 on 40 tracks (33 under 0.3); madmom's grid chosen on 57; the octave fix fired on 21; key
confidence under 0.5 on 58; phrase confidence under 0.35 on 128; `vocal_heavy` on 273; `fade_out` on 149;
`short_intro` on 323 and `short_outro` on 324. Median seconds per block: key 5.1, loudness 3.0, Essentia rhythm 2.9,
EffNet 0.9, Beat This 0.6; every numpy block under 0.3.

| # | Block (lines) | Computes | Inputs | Feature JSON outputs | Disposition | Size | Depends on |
|---|---|---|---|---|---|---|---|
| A1 | Decode (377-385) | soundfile read as float32, soxr to 44.1 kHz, first two channels, mono = channel mean | file | `sr`, `duration_s` | Port: `AVAudioFile` + `AVAudioConverter`, vDSP for the mono mix; DRM content refused | small | - |
| A2 | First and last sound (387-394) | first and last 10 ms frame with a peak above -60 dBFS | stereo samples | `first_sound_s`, `last_sound_s` | Port, vDSP `maxmgv` per frame | small | A1 |
| A3 | Beat tracking (`Models.beats`, 293-302) | Beat This final0 (20M, MPS, no DBN): beat and downbeat times on a 20 ms frame grid | mono | `detected_beats_s`, `detected_downbeats_s`, `bpm_beatthis`, `bpm_beatthis_median_ibi`, `beatthis_device` | MU replaces (`RhythmResult` beats and bars); Beat This small in Core ML stays as the second opinion and the level 2 detector | large (model) | A1 |
| A4 | Grid fit (`_win_fit`, `_period_phase_windows`, `_period_phase_irls`, `_grid_eval`, `fit_grid`, 100-211) | constant 4/4 grid: whole-track L1 IRLS (12 iterations, re-index at 3 and 7) and the median period of trusted 20 s windows; the winner puts more beats within 70 ms, then lower MAD; downbeat phase by vote; confidence = inlier x (0.5 + 0.5 agree) x MAD penalty | detected beats and downbeats, duration | `grid.{bpm, first_downbeat_s, beat_s, bar_s, fit_mad_ms, inlier_frac, downbeat_agree, confidence, n_bars}` (`method`, `period_spread_pct`, `trusted_windows` are computed but never written) | Port, plain Swift; the two-parameter least squares is closed form over vDSP sums | medium | A3 or A6 |
| A5 | Octave align (`_rms_at`, `octave_align`, 215-253) | halve or double the detections when the grid sits at 2x or 0.5x the tag; downbeat parity by low-end RMS | beats, downbeats, grid, `bpm_tag`, mono | `octave_fix{mode, from_bpm, parity}` | Port, vDSP `rmsqv` over 50 ms windows | small | A4, tag |
| A6 | Second opinion and grid choice (`madmom_downbeats` 304-315; 433-465) | madmom RNN + DBN when confidence < 0.5 or tag deviation > 2 percent; choose by (tag deviation > 2 percent, then `fit_mad_ms`) | grid confidence, tag | `madmom_ran`, `madmom_reason`, `bpm_madmom`, `madmom_downbeats_s`, `grid_candidates`, `grid.source` | madmom dropped (CC BY-NC-SA); the rule ports as is with Beat This small in the slot; `grid.source` becomes `mu` or `beatthis` | small (rule); the model is A3 | A4, A5 |
| A7 | Essentia tempo (`RhythmExtractor2013`, 408-413, 487) | a third BPM vote | mono | `bpm_essentia`, `essentia_confidence`, `essentia_agree` | Drop: nothing downstream reads it; MU BPM and the grid BPM remain | - | - |
| A8 | Bar bookkeeping (467-487) | `bpm` = 60 / period; bar 1 = first grid downbeat at or after first sound minus a quarter beat; `n_bars` (error under 8); grid beat and bar arrays; multiplier vs tag from {1/2, 2/3, 3/4, 1, 4/3, 3/2, 2}; `bpm_agree` within 1 percent after octave normalisation | grid, first sound, tag | `bpm`, `bpm_agree`, `multiplier_vs_tag`, `multiplier_vs_tag_value`, `tag_dev_pct`, `beats_s`, `downbeats_s` | Port, plain Swift | small | A2, A4, A6 |
| A9 | Key votes (263-264, 414-429) | Essentia `KeyExtractor` edma and bgate (key, scale, strength); madmom CNN key (key, scale, probability) | mono | `key.essentia_edma`, `key.essentia_bgate`, `key.madmom_cnn`, `key.camelot_edma`, `key.camelot_bgate`, `key.camelot_madmom` | Replace: MU `KeyResult` ranges are vote 1; own HPCP is vote 2 (12-bin chroma from the shared STFT, correlated with published major and minor profiles), vDSP | medium (HPCP) | A1, A12 |
| A10 | Camelot (`camelot`, `camelot_parse`, `camelot_neighbour`, 38-64) | key name and scale to Camelot; neighbour test (same, +/-1, relative) | key, scale | `key.camelot*` | Port, plain Swift; the pitch-class table already covers MU's 17 enharmonic tonics | small | - |
| A11 | Key confidence (701-742) | three votes: all agree 1.0 (0.6 under strength 0.6); two agree 0.65 if the dissenter is a neighbour else 0.45, 0.3 under strength 0.6; none 0.3; two votes: agree and strength >= 0.6 gives 0.7 else 0.3 | votes, strengths | `key.camelot`, `key.confidence`, `key.confidence_rule` | Port the two-vote branch; strength = HPCP correlation margin [inf]; add `key.votes{mu, hpcp}` and `key.changes` from MU ranges | small | A9, A10 |
| A12 | Spectral front end (489-500) | resample to 22.05 kHz; mel 64 (n_fft 2048, hop 512), log power, MFCC-13, frame RMS, librosa onset strength | mono | none directly; feeds A13, A16, A18 | Port with vDSP: FFT, mel filterbank as a matrix multiply, DCT-II, onset strength = mean positive first difference of the log-mel (lag 1, centred); one STFT module also serves Beat This small (1024/441, 128 mels) and HPCP | medium | A1 |
| A13 | Structure (`foote_novelty` 349-365; 502-535) | half-beat MFCC-cosine and RMS-dB SSMs, 64-frame Gaussian checkerboard, geometric mean, top 20 peaks >= 1 bar apart snapped to bars within 0.4 bar; 8-bar lattice phase with most novelty; confidence = 0.6 share + 0.4 margin over the runner-up | MFCC, RMS, grid | `phrase.{lattice_phase_bar, phrase_len_bars, confidence, phase_novelty[8], snap_phase_bar}`, `boundaries_bars`, `novelty_peaks` | MU `StructureResult` replaces boundary detection; lattice phase, confidence and the boundary set port as plain Swift over MU boundaries (weights in section 5); Foote novelty ports with vDSP as the level 2 path and tie-breaker | small (lattice); large (Foote) | A8, A12 |
| A14 | K-weighting and per-bar loudness (`k_weight` 325-333; 539-547) | pyloudnorm's two BS.1770 filters; per-bar K-weighted mean square, -0.691 + 10 log10 | stereo, bar edges | `per_bar.lufs_st` | Port, vDSP `biquad` with the ITU coefficients at 44.1 kHz; MU momentary loudness is a cross-check only | small | A1, A8 |
| A15 | Band energy (`lr4` 319-322; 542-549) | LR4 (Butterworth-2 applied twice) low-pass 150 Hz and high-pass 4 kHz; per-bar mean square in dB | mono, bar edges | `per_bar.low_db`, `per_bar.high_db` | Port, vDSP `biquad`, bilinear coefficient design | small | A1, A8 |
| A16 | Onsets and density (544, 550-551) | librosa `onset_detect`: envelope normalised to 0..1, peak picking with pre_max 30 ms, pre and post average 100 ms, wait 30 ms, delta 0.07; onsets per bar / 4 | onset strength, bar edges | `per_bar.onset_density` | Port, plain Swift | small | A8, A12 |
| A17 | Track loudness (`true_peak_db` 336-346; 554-560) | pyloudnorm integrated LUFS and LRA; true peak by 4x `resample_poly` in 10 s blocks | stereo | `loudness.{integrated_lufs, lra, true_peak_db}` | MU replaces integrated; LRA from MU short-term with EBU gating (small port); peak from MU if it is true peak, else port the 4x oversample as a vDSP FIR | small | A1 |
| A18 | Onset pattern (563-573) | eighth-note cells, 2 bars x 8, max onset strength per cell, mean over bar pairs within 10 LU of the median bar loudness, normalised to 1 | onset strength, grid, `per_bar.lufs_st` | `onset_pattern_16` | Port, plain Swift | small | A8, A12, A14 |
| A19 | Vocal and embedding (266-271, 575-594) | Discogs-EffNet at 16 kHz: 1280-d patch embeddings (mean-pooled) and the voice head per patch (hop 0.992 s), averaged into bars | mono | `per_bar.vocal_prob`, `vocal.{mean_prob, vocal_heavy, patch_hop_s, n_patches}`, `embedding_effnet[1280]` | MU `InstrumentActivityResult` replaces vocal (per-bar mean of `.vocal`; `.drum`, `.bass`, `.other` are new series); the embedding is dropped (NonCommercial) and the style vector takes its place (section 5) | small (glue) | A8 |
| A20 | Sections (596-610) | energy high or low against the median bar loudness - 1.5 LU; labels intro, main, break, outro; section LUFS and vocal mean | boundaries, `lufs_st`, `vocal_prob` | `sections[{start_bar, end_bar, label, energy, lufs, vocal}]` | Port, plain Swift | small | A13, A14, A19 |
| A21 | Fade-out (612-633) | 3 s K-weighted loudness at 17, 7 and 1 s before last sound; fade if the drop > 6 dB and >= 3 bars follow the last body-level bar and sound lasts > 60 s | stereo, `lufs_st`, last sound | `fade_out`, `fade_drop_lu`, `end_lufs_st`, `tail_bars`, `fade_start_bar` | Port, plain Swift over A14's filters (MU short-term series is an alternative input) | small | A2, A8, A14 |
| A22 | Mix windows (635-699) | mix-in from bar 1, length 32, 16 or 8 by vocal-free bars and the first boundary, snapped to the lattice (phase assumed bar 1 under phrase confidence 0.35); mix-out mirrored, ending at the last full bar or before the fade | `vocal_prob`, boundaries, lattice, fade start, last sound | `mix_in{start_bar, end_bar, bars, start_s, end_s, vocal_free_bars, first_vocal_bar}`, `mix_out{..., last_vocal_bar, fade_out}` | Port, plain Swift, line for line | medium | A8, A13, A19, A21 |
| A23 | Flags (744-760) | `half_time_candidate`, `vocal_heavy`, `fade_out`, `low_grid_confidence`, `key_uncertain`, `short_intro`, `short_outro` | the above | `flags[]` | Port | small | A6, A11, A19, A21, A22 |
| A24 | Assembly and CLI (762-886) | the feature dict; resumable loop, atomic write, error log, `--ids`, `--limit`, `--force`, `--madmom` | everything | `features/<id>.json` incl. `path`, `meta`, `timing_s` | Port as `TrackAnalysis` plus the Desk batch runner; `path` and `meta` leave the record (DeckieCore's `file` and `ident`); `timing_s` becomes `analysis.secs` | small | all |

Three things the table does not show. `grid.method`, `period_spread_pct` and `trusted_windows` are computed by
`fit_grid` but never written because `grid_out` lists its keys explicitly, so no stored feature has them; the port
writes them, they are the cheapest grid-quality signal after `confidence`. `vmask` (line 593) is dead code, and
`vocal.mean_prob` is the mean over EffNet patches, not over bars; the port keeps that definition (mean over MU
samples) so `vocal_heavy` stays comparable. Every analyser runs on one 44.1 kHz float32 decode; MU takes the
`AVAsset` itself, so the engine decodes once for our DSP, hands MU the asset, and resamples other rates to 44.1 kHz
for parity with the lab.

`local_tempo.py` runs on the raw detections, not the grid, and is what gives the app `bpmIn`, `bpmOut` and the
trust flags:

| # | Block (lines) | Computes | Inputs | Feature JSON outputs | Disposition | Size | Depends on |
|---|---|---|---|---|---|---|---|
| L1 | `_local` (31-57) | window tempo by regression of beat time on a cumulative integer index, three passes, rejection at a quarter period; octave-normalised to the global BPM with the scorer's multipliers | detected beats, window, `bpm` | `local_tempo.{first30, last30, mix_in, mix_out}{bpm, bpm_raw, mult, n_beats, resid_ms, t0, t1}` | Port; same algorithm as `_win_fit`, one `RobustPeriodFit` serves both | small | A3 or A6, A2, A22 |
| L2 | `_grid_dev_ms` (60-67) | median distance from detected beats to the nearest grid beat in a window | detections, grid beats | `grid_dev_in_ms`, `grid_dev_out_ms` | Port | small | A8 |
| L3 | `_trusted`, `_decide` (75-91) | trusted when residual <= 15 ms and >= 16 beats; on the global grid when the deviation <= 15 ms; the local tempo only when it differs by > 1.5 percent | L1, L2 | `bpm_in`, `in_trusted`, `in_rule`, `bpm_out`, `out_trusted`, `out_rule`, `drift_pct` | Port | small | L1, L2 |
| L4 | `compute`, second half (94-152) | 15 s profile; range and untrusted count; steady-in and steady-out bars from the first and last trusted segment (in pulled to the next detected downbeat); first downbeats in the end windows; tempo-change, transition-track, half-time and no-steady-beat decisions | L1 to L3, downbeats, grid | `profile`, `range_pct`, `untrusted_segments`, `steady_in_s`, `steady_in_bar`, `steady_out_s`, `steady_out_bar`, `first_downbeat_in_s`, `first_downbeat_out_s`, `tempo_change`, `transition_track`, `in_half_time`, `out_half_time`, `intro_no_steady_beat`, `outro_no_steady_beat` | Port | medium | L1 to L3, A8 |
| L5 | `flags` (155-163) | six flags from L4 | L4 | additions to `flags[]` | Port | small | L4 |
| L6 | `main` (166-193) | backfill CLI over `features/` | - | - | Drop (lab only) | - | - |

## 2. Scoring terms and the app's per-track fields

`score.py` ports as it is into DeckieCore (overview, section 2); nothing in it needs Accelerate except the timbre
matrix. One correction to the record: the weights in the code are `W = {tempo .26, key .14, energy .11, vocal .11,
phrase .08, timbre .12, rhythm .05, style .13}`; `mixer/README.md` and the footer of `recs.md` still print the older
0.30/0.20/0.15 formula. The port follows the code.

| Block | Inputs (feature fields) | What it does | Port |
|---|---|---|---|
| `load()` | `per_bar.{lufs_st, vocal_prob}`, `mix_in`, `mix_out`, `loudness.integrated_lufs`, `embedding_effnet`, `bpm`, `grid.{confidence, n_bars}`, `local_tempo.{bpm_in, bpm_out, in_trusted, out_trusted, steady_in_bar, tempo_change, drift_pct}`, `key.{camelot, confidence}`, `onset_pattern_16`, `fade_out`, `flags`; from candidates `cut_key`, `is_longest`, `on_disc`, `disc`, `folder`, `hal`, `kind`, `era`, `secs` | the per-track projection: window loudness as a power mean minus integrated (`in_rel`, `out_rel`), vocal slices, unit-norm embedding | `ScoringTrack` built from a crate record plus its bars sidecar; `emb` becomes the style vector |
| `tempo_term` | `bpm_out` (A), `bpm_in` (B) | best k of seven multipliers by abs(log r); stretch = abs(r - 1) x 100; 1.0 up to 3 percent, down to 0.4 at 10, 0.1 at 18, floor 0.05, rejected above 18; -0.10 for 1/2 and 2; capped at 0.35 for the thirds and quarters | as is |
| `key_raw`, `cshift`, `key_term` | `camelot`, `key_conf` | B.9 table (same 1.0, +/-1 0.90, relative 0.85, +2 0.65, +/-7 0.50, -2 0.45, else 0.15); pitch-shift B by +/-1 or +/-2 st when that lands at >= 0.85 (0.85 - 0.12 abs(s)); times (0.5 + 0.5 min conf) | as is |
| energy (`score_pair`) | `in_rel`, `out_rel` | dE = B's in-window minus A's out-window relative loudness; 1 - clip(abs(dE) - 2, 0, 8) / 8 | as is |
| vocal (`score_pair`) | `voc_out`, `voc_in`, `voc_first16` | v = mean(P_A x P_B) over the last and first L bars; 1 - v, +0.1 when B's first 16 bars are under 0.5, capped at 1; clash count | as is; thresholds become parameters (section 5, item 3) |
| phrase (`score_pair`) | `out_bars`, `in_bars`, `grid_conf`, `in_trusted`, `out_trusted`, `steady_in_bar`, `n_bars` | (0.7 + 0.3 cA)(0.7 + 0.3 cB) x clip((win - 8) / 8); x0.6 when B's beat drops in by bar max(9, 0.3 n), x0.4 when an end is untrusted | as is |
| timbre (`main`) | `embedding_effnet` | cosine matrix over the pool; each pair's percentile among all upper-triangle values | as is over the style vector; n x n cosine through BLAS; percentile within the crate |
| `rhythm_term`, `fold8`, `up16`, `corr` | `onset_pattern_16` | max(0, Pearson r); for k = 2 or 1/2 the slower track's pattern folds to one bar and stretches to 16 cells; 0.25 for other k | as is |
| `style_term` | `kind`, `era`, `hal` | 1.0 for the same family (dance kinds against pop) else 0.45; -0.15 across eras; +0.1 when both are Halloween | as is; inputs from `ident` and a user tag |
| `transition`, `move_options` | stretch, k, v, rhythm, window bars, trust | the E.4 rule: untrusted end gives echo or brake; > 16 percent or an odd k with weak rhythm gives brake; v >= 0.6 echo; > 6 percent ramped blend; v < 0.35 with 16-bar windows bass swap 32 or 16; 8-bar windows bass swap 8; else echo or filter sweep; a three-move menu | as is |
| `score_pair` assembly | all terms | weighted sum with `W`; gate v >= 0.6 only with echo or brake; reasons = the three largest terms plus every term under 0.4; one `pairs.json` row | as is; the reason strings are UI copy and move to DeckieCore's localisable table |
| `bonus`, `dedupe`, `entry`, views (`main`) | `secs`, `cut_key`, `is_longest`, `on_disc` | +0.03 for a candidate >= 270 s; one cut per `cut_key`; top 8 in and out per track; `PAIR_MIN` 0.45 | as is; the views become queries over a crate |

`prep_data.py` turns features into `Deck/Resources/deck_data.json`; the app's `Track` (`Model.swift`) and
`Mixing.swift` read these fields. In the crate world each is a projection of the crate record, except the waveforms,
which need audio.

| App field | Source today | In the crate world |
|---|---|---|
| `bpm`, `bpmGrid`, `firstBeat` | `bpm` (1 dp), `grid.bpm` (3 dp), `grid.first_downbeat_s` | `grid.bpm`, `grid.first_downbeat_s` |
| `bpmIn`, `bpmOut` | `local_tempo.bpm_in`, `bpm_out` (fallback `bpm`) | `grid.bpm_in`, `grid.bpm_out` |
| `key`, `keyConf` | `key.camelot`, `key.confidence` | `key` |
| `dur` | `duration_s` | `file.duration_s` |
| `mixIn`, `mixOut` (seconds), `mixInBars`, `mixOutBars` | `mix_in` and `mix_out` `start_s`, `end_s`, `bars` | derived from the window bars and the grid: `first_downbeat_s + (bar - 1) x 240 / bpm` |
| `fade` | `fade_out` | `ends.fade_out` |
| `steadyIn` | `local_tempo.steady_in_bar` to seconds | `ends.steady_in_bar` to seconds |
| `wOut`, `wIn`, `wHead`, `spb` (`mixwaves_all.py`) | audio RMS per eighth of a beat on the grid: mix-out window plus 8 lead bars, mix-in window plus 8 bars after, head = start to 64 bars; 6-bit base64 with `t0`, `win`, `beat0`, `k0` | needs audio: proposed `waves/<id>.bin` sidecar written by the analysing device (section 4); vDSP `rmsqv` per cell |
| overview wave (`overview_waves.py`) | 480 RMS bins over the file, 6-bit | the same sidecar, 480 bytes |
| pair rows `b`, `s`, `st`, `m`, `pitch`, `tr`, `trl`, `ka`, `kb`, `reasons[:5]`, `ks`, `mv[:3]` | `pairs.json` plus `pitch = (bpm_out_A / (bpm_in_B x k) - 1) x 100` and the `LABEL` map | DeckieCore scoring output; `pitch` and the labels port with it |
| `cd`, `num`, `discs` | candidates `on_disc`, `disc`, `folder`, sorted by folder and tag BPM | the sprint's disc layout; becomes the disc manifest of spec 5.4 |

## 3. Stage 1 benchmark harness

Purpose: measure MU against the lab on the 373 tracks before writing engine code (spec 7, stage 1a; track A,
section 7, question 1). Neither side is ground truth. The lab's beats come from Beat This 20M (madmom on 57 tracks),
its key from three NonCommercial detectors that are 60 to 80 percent right on vocal pop, its vocal timeline from a
head that over-reports. The metrics therefore report agreement, split by the lab's own confidence, and listening to
the worst 20 tracks per metric is part of the protocol.

### 3.1 The Swift tool: `mubench`

A SwiftPM package at `tools/mubench/` with one library target, `MUBenchCore` (decode, the MU calls, the JSON writer,
timing and thermal logging), and two fronts: `mubench`, a macOS 27 command-line executable, and `MUBenchApp`, a
one-screen iOS 27 SwiftUI app around the same library for while this Mac is on macOS 26. The library is the seed of
the `MusicUnderstandingProvider` in section 4; nothing else from it is kept.

```
swift run -c release mubench manifest --candidates mixer/candidates.json \
    --music-root "/Users/christophershannon/personal/90s2000 playlist" --out bench/manifest.json [--subset 60]
swift run -c release mubench analyze --manifest bench/manifest.json --music-root <root> \
    --out bench/mu/<label> --label mac-m4 [--ids a,b] [--limit N] [--force]
swift run -c release mubench analyze ... --self-test      # one track; prints every MU field and type it saw
```

`manifest` rewrites `candidates.json` to `{id, rel, bpm_tag, secs, kind}` with paths relative to the music root, so
one manifest works on a device; `--subset` picks a stratified sample (by grid confidence and kind) for phone runs.
`analyze` is resumable (skips ids with an output file), writes atomically, logs per-track errors to `errors.log` and
goes on, like `analyze.py`. Every run also writes `run.json`: device model, OS build, power source,
`ProcessInfo.thermalState` sampled every 10 s, wall time. Core signatures (MU type names follow track A, section 8;
confirm against the SDK before coding):

```swift
struct MUTrackOutput: Codable { /* the JSON below */ }
func analyzeTrack(id: String, url: URL) async throws -> MUTrackOutput   // one MusicUnderstandingSession, all five results
func decodeInfo(url: URL) throws -> (sr: Double, channels: Int, duration: Double)
func lraFromShortTerm(_ shortTerm: [Float]) -> Float                     // EBU Tech 3342 gating, like pyloudnorm
```

Per-track output, `bench/mu/<label>/<id>.json`, a defined subset of the feature schema with MU's raw series kept,
because looking at them is the point:

```
{ "schema": "mubench-1", "id": "c546b63944", "rel": "CDs v2/...", "sr": 44100, "channels": 2, "duration_s": 224.0,
  "engine": {"framework": "MusicUnderstanding", "os": "macOS 27.0 (25A...)", "device": "Mac15,6", "label": "mac-m4", "mubench": "0.1"},
  "timing_s": {"decode": 0.2, "mu": 6.1, "total": 6.4}, "thermal": ["nominal", "nominal"], "power": "ac",
  "bpm_mu": 125.0,
  "detected_beats_s": [...], "detected_downbeats_s": [...],
  "key_ranges": [{"start_s": 0.0, "end_s": 224.0, "key": "D", "scale": "minor", "camelot": "7A"}],
  "key_mu": {"camelot": "7A", "key": "D", "scale": "minor"},
  "structure": {"sections_s": [[0.0, 15.4], ...], "segments_s": [...], "phrases_s": [...]},
  "activity": {"hop_s": 0.1, "t0_s": 0.0, "vocal": [...], "drum": [...], "bass": [...], "other": [...]},
  "loudness": {"integrated_lufs": -8.2, "lra": 5.1, "peak_db": -0.1, "peak_kind": "unknown",
               "short_term": {"hop_s": 0.1, "values": [...]}, "momentary": {"hop_s": 0.1, "values": [...]}},
  "pace": {"hop_s": 0.1, "values": [...]}, "errors": [] }
```

`detected_beats_s` and `detected_downbeats_s` hold MU's beats and bar starts under the lab's names and units so the
comparison code is symmetric; `key_mu` is the duration-weighted dominant range; `hop_s` and `t0_s` are whatever the
API reports, never assumed.

Running on an iPhone or iPad. This Mac is on macOS 26. By Apple's usual rule Xcode 27 runs on macOS 26 [inf], so the
device route needs no Mac upgrade: build `MUBenchApp` to an iPhone 11 or later, or an iPad on the iPadOS 27 list,
with `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`. Audio reaches the device by Finder file sharing
into the app's Documents folder, or by picking the music folder in Files, which the app reads through security-scoped
access; the app reads the manifest, writes `Documents/bench/mu/<label>/`, and Finder copies the results back. The
full set is 3.7 GB and 25.5 hours of audio, so an iPad run can be the full comparison and the phone run is the timing
subset (`--subset 60`). Plug in and watch the thermal column; a phone that reaches `.serious` pauses the loop.

### 3.2 The comparison script: `mixer/bench_mu.py`

Runs in the lab venv with `-I`, imports numpy and `analyze.fit_grid`, `analyze.camelot`,
`analyze.camelot_neighbour`, `local_tempo._local` (the model imports in `analyze.py` are lazy, so this works without
torch or Essentia):

```
cd mixer && .venv/bin/python -I bench_mu.py score --mu ../bench/mu/mac-m4 --features features \
    --candidates candidates.json --out ../bench/mu_scores_mac-m4.json --report ../bench/mu_report_mac-m4.md
.venv/bin/python -I bench_mu.py timing --runs ../bench/mu/*/run.json      # s per track and x realtime per device
```

```python
def beat_f(ref_s, est_s, tol=0.07) -> dict        # greedy one-to-one match: f, p, r; also f at 2x, 0.5x and half-beat offset
def key_class(cam_lab, cam_mu) -> str             # "exact" | "neighbour" | "relative" | "other"
def per_bar_mean(t, values, bar_edges) -> np.ndarray
def boundary_hits(bars_lab, bars_mu, tol_bars=1) -> dict   # precision, recall, on_lattice share
def score_track(feat, mu, cand) -> dict
```

Per-track metrics go to `mu_scores_<label>.json`; `mu_report_<label>.md` has medians and quartiles, the same split by
grid confidence, key confidence, phrase confidence and `kind`, and the worst 20 tracks per metric with titles.

| Metric | Lab side | MU side | Definition |
|---|---|---|---|
| Beat F | `detected_beats_s`, and separately the grid `beats_s` | `detected_beats_s` | F-measure at 70 ms, one-to-one greedy match; also F after doubling and halving MU and at a half-beat offset, so octave and phase errors are named rather than hidden |
| Downbeat F | `detected_downbeats_s`, and the grid `downbeats_s` | `detected_downbeats_s` | same at 70 ms; plus the share of MU bars on each of the four grid beat phases |
| Tempo | `bpm`, `bpm_tag` | `bpm_mu` | deviation in percent, raw and after octave normalisation |
| Grid quality | `grid.fit_mad_ms`, `inlier_frac`, `confidence` | `fit_grid(mu beats, mu bars)` | the lab's own fit applied to MU beats; decides whether the second opinion is still needed |
| Residual shape | `local_tempo.first30.resid_ms` | `_local` on MU beats | median residual in 30 s windows; tells whether MU beats are frame-quantised or pre-snapped (section 5, item 2) |
| Key | `key.camelot` and each of the three votes | `key_mu` | exact, Camelot neighbour (+/-1, same letter), relative, other; counted separately and split by `key.confidence` |
| Key stability | - | `key_ranges` | number of ranges; share of duration in the dominant range |
| Vocal timeline | `per_bar.vocal_prob` | `activity.vocal` averaged on the lab's bar edges | Pearson r per track; bar agreement rate over a threshold sweep 0.3 to 0.7; first-vocal-bar delta on the intro subset (12 candidates with `intro: true`; 26 tracks with `first_vocal_bar >= 17`) |
| Sections | `boundaries_bars` without bar 1 and the end | section and segment starts snapped to the nearest bar | precision and recall within one bar; share of MU boundaries on the lab's 8-bar lattice (`phrase.lattice_phase_bar`) |
| Loudness | `loudness.{integrated_lufs, lra, true_peak_db}`, `per_bar.lufs_st` | `integrated_lufs`, `lra`, `peak_db`; momentary averaged per bar | deltas in LU and dB; mean absolute per-bar delta |
| Timing | `timing_s` (lab) | `timing_s`, `thermal`, `run.json` | seconds per track and x realtime per device; thermal transitions |

Proposed pass marks for stage 1d, the regeneration of Christopher's crate, to be argued with the numbers rather than
before them [inf]: beat F at or above 0.90 and downbeat F at or above 0.80 (medians, lab grid confidence at or above
0.5); key exact plus neighbour at or above 85 percent where the lab's confidence is 1.0; vocal r at or above 0.6
median and the first vocal bar within two bars on the intro subset; boundary recall at or above 0.6 where phrase
confidence is at or above 0.35; integrated loudness within 0.5 LU; under 15 s per track on the Mac and under 40 s on
a plugged-in iPhone. If beat F is high but the grid-quality row shows MU beats already sitting on a constant grid,
the second-opinion trigger is redesigned (section 5, item 2) before stage 2 starts.

## 4. The DeckieAnalysis package

Platforms iOS 26 and macOS 26, so level 2 devices can link it, with MU behind `#available(iOS 27, macOS 27, *)`.

```
DeckieAnalysis/
  Package.swift
  Sources/DeckieAnalysis/              public API, TrackAnalysis, BarSeries, crate encodings
    Analyzer.swift                     actor: orchestration, progress, cancellation, level selection
    Model/      TrackAnalysis.swift  BarSeries.swift  Camelot.swift  CrateRecord.swift
    Decode/     AudioLoader.swift      AVAudioFile -> 44.1 kHz float32 mono and stereo; DRM refused
    MU/         MusicUnderstandingProvider.swift   one session, five results, OS 27 only
    DSP/        STFT.swift  Mel.swift  MFCC.swift  OnsetStrength.swift  Biquad.swift (LR4, K-weight)
                TruePeak.swift  HPCP.swift  FirstLastSound.swift
    Grid/       RobustPeriodFit.swift (A4 and L1)  GridFit.swift  OctaveAlign.swift  LocalTempo.swift
    Structure/  Lattice.swift  FooteNovelty.swift  Sections.swift
    Windows/    MixWindows.swift  FadeOut.swift  Flags.swift
    Style/      StyleVector.swift      v1 hand-crafted, 64-d
  Sources/DeckieAnalysisBeatThis/      mel front end (22.05 kHz, 1024/441, 128 mels, log1p(1000x)), Core ML wrapper, peak picking
    Resources/BeatThisSmall.mlpackage  about 4 MB fp16, MIT; licence file beside it
  Sources/DeckieAnalysisFallback/      SoundAnalysis "singing" -> vocal series (level 2 only)
  Sources/deckie-analyze/              macOS CLI: folder -> crate records; grows out of mubench
  Tests/DeckieAnalysisTests/           parity fixtures: ten lab feature JSONs (no audio), synthetic signals
```

Public API:

```swift
public enum EngineCapability: Sendable { case full, fallback, none
  public static var current: EngineCapability   // full on OS 27 when MU reports support; fallback when Beat This small and SoundAnalysis load; else none
  public var engineString: String }             // "mu27.0+deckie1" | "btsmall1+deckie1", written to analysis.engine

public struct AnalysisOptions: Sendable {
  public var bpmTag: Double?                                 // from the file's tags when present (octave alignment, second-opinion trigger)
  public var secondOpinion: SecondOpinion = .auto            // .never | .auto (grid confidence < 0.5 or tag deviation > 2 percent) | .always
  public var level: EngineCapability? = nil                  // nil means EngineCapability.current
  public var injectedDetections: (beats: [Double], downbeats: [Double])? = nil   // lab parity tests only
}

public struct AnalysisProgress: Sendable { public let stage: Stage; public let fraction: Double
  public enum Stage: Sendable { case decode, musicUnderstanding, grid, secondOpinion, dsp, structure, windows, style, done } }

public actor Analyzer {
  public init(options: AnalysisOptions = .init())
  public func analyze(url: URL, progress: @Sendable (AnalysisProgress) -> Void = { _ in }) async throws -> TrackAnalysis
}

public struct TrackAnalysis: Codable, Sendable {
  public let duration: Double, engine: String, level: EngineCapability, seconds: Double
  public let grid: Grid, localTempo: LocalTempo, key: Key, phrase: Phrase, sections: [Section]
  public let mixIn: MixWindow, mixOut: MixWindow, ends: Ends, loudness: Loudness, vocal: VocalSummary
  public let onsetPattern16: [Float], flags: [String]
  public let bars: BarSeries                     // 8 series x n_bars
  public let style: [Float]                      // 64-d, v1
  public let lab: LabExtras?                     // detected beats, grid candidates, votes: benchmark export and tests, never the crate
  public var crateRecord: CrateTrackRecord { get }   // the crate.json object below
  public func barsSidecar() -> Data              // float16 little-endian; 16-byte header "DKB1", n_bars, n_series [inf: track A gives no header]
}
```

Cancellation is structured: the caller cancels its `Task`; `Analyzer` checks `Task.checkCancellation()` between
stages and forwards cancellation to the MU session and the Core ML prediction [inf on whether MU exposes it].
Progress is per stage, with a fraction inside the long ones. Batch running, pausing at thermal `.serious`, the power
requirement and `BGContinuedProcessingTask` belong to the app layer; the package guarantees only that `analyze` is
cancellable at stage boundaries and holds at most one track's audio.

The pipeline inside `analyze`, with the second opinion and the level selection:

1. Decode once (A1); first and last sound (A2).
2. Level `.full`: one MU session over the asset for rhythm, key, structure, instrument activity and loudness.
   Level `.fallback`: Beat This small for beats and bars, SoundAnalysis for a vocal series, the HPCP key vote
   alone, Foote novelty for boundaries, own loudness; the record gets `analysis.level = 2` so a capable device
   re-analyses it (spec 5.1, level 2). `.none` throws before decoding; the app shows level 3.
3. Grid fit (A4) on the primary beats; octave alignment when a tag exists (A5). Second opinion (A6): on `.always`,
   or on `.auto` when confidence < 0.5 or the tag deviation > 2 percent, run Beat This small, fit its grid, choose
   by (tag deviation > 2 percent, then lower `fit_mad_ms`); `grid.source` is `mu` or `beatthis`.
4. Bar bookkeeping (A8); local tempo (L1 to L5) on the chosen detector's raw beats.
5. DSP at 22.05 and 44.1 kHz (A12, A14 to A18); vocal, drum, bass and other per bar from MU (A19).
6. Lattice and boundaries from MU structure (A13), sections (A20), fade-out (A21), windows (A22), flags (A23, L5).
7. Key: Camelot from MU's dominant range plus the HPCP vote, confidence by the two-vote rule (A9 to A11).
8. Style vector v1 (section 5, item 1); assemble `TrackAnalysis`.

Crate fields the engine writes, matching track A section 5. DeckieCore fills `file`, `ident` and `signatures` and
places the record and sidecars in the package.

| Crate field | From | Lab field |
|---|---|---|
| `schema`; `analysis.{engine, analysed_at, device, secs, level}` | engine | `schema`; `timing_s` summed |
| `grid.{bpm, first_downbeat_s, n_bars, fit_mad_ms, confidence, source}` | A4, A6, A8 | `grid.*` |
| `grid.{bpm_in, bpm_out, in_trusted, out_trusted}` | L3 | `local_tempo.*` |
| `key.{camelot, key, scale, confidence, votes{mu, hpcp}, changes[[start_bar, end_bar, camelot]]}` | A9 to A11 | `key.*` |
| `phrase.{lattice_phase_bar, confidence, boundaries_bars}` | A13 | `phrase.*`, `boundaries_bars` |
| `sections[{start_bar, end_bar, label, energy}]` | A20 | `sections[]` without `lufs` and `vocal` (recoverable from the sidecar) |
| `mix_in`, `mix_out` as `{start_bar, end_bar, vocal_free_bars}` | A22 | `mix_in`, `mix_out` (`bars`, `start_s`, `end_s` derive from the grid) |
| `ends.{first_sound_s, last_sound_s, fade_out, steady_in_bar, steady_out_bar}` | A2, A21, L4 | `first_sound_s`, `last_sound_s`, `fade_out`, `local_tempo.steady_*` |
| `loudness.{integrated_lufs, lra, true_peak_db}` | A17 | `loudness.*` |
| `vocal.{mean, heavy}`, `onset_pattern_16`, `flags` | A19, A18, A23 | `vocal.mean_prob`, `vocal.vocal_heavy`, `onset_pattern_16`, `flags` |
| `bars/<id>.bin`: lufs, low_db, high_db, onset_density, vocal, drum, bass, other | A14 to A19 | `per_bar.*` plus three new series |
| `style/<id>.bin` | Style v1 | replaces `embedding_effnet` |

Dropped from the crate on purpose, per track A's budget: `beats_s`, `downbeats_s`, `detected_*`, `madmom_*`,
`essentia_*`, `grid_candidates`, `novelty_peaks`, `phase_novelty`, `end_lufs_st`, `tail_bars`, `path`, `meta`,
`timing_s`, `embedding_effnet`. The beat arrays and candidates stay reachable through `TrackAnalysis.lab` for the
benchmark and the tests. Two small additions to the track A record are proposed here and need the overview author's
agreement: `analysis.level`, so level 2 records are re-analysed by a capable device, and a `waves/<id>.bin` sidecar
(section 2; about 5 KB, raising the per-track budget from about 10 to about 15 KB), because the join view's
snippets need audio the iPad does not have.

Parity tests feed `injectedDetections` from a lab feature file's `detected_beats_s` and `detected_downbeats_s`
plus the same decoded audio, and require: grid BPM within 0.01 percent and first downbeat within 1 ms; per-bar LUFS
within 0.1 LU and bands within 0.2 dB; onset pattern r above 0.99; identical mix-window bars, flags, Camelot codes
and local-tempo trust decisions. That proves the port on its own before MU's differences are layered on.

## 5. Risks and open questions

1. **The EffNet embedding.** `timbre` (weight 0.12, not the 0.05 the README states) is the cosine of 1280-d
   Discogs-EffNet means, rank-normalised over the pool; the model is NonCommercial and cannot ship, and the 373
   stored embeddings must not travel in any crate (track A). Plan: a hand-crafted 64-d style vector v1 from what the
   engine already has (tempo and pace; Camelot as two cyclic coordinates; mean and spread of the four activity
   series; low and high band balance and its spread; the 16-cell onset pattern; the section energy profile;
   integrated loudness and LRA; MFCC means and variances from A12), z-scored per crate. Measure it in stage 2:
   Spearman rank correlation between EffNet-cosine percentiles and v1-cosine percentiles over the 373 x 372
   directed pairs, and the overlap of each track's top-8 timbre neighbours. At or above 0.5, ship v1; below, add
   YAMNet 1024-d through Core ML (Apache-2.0, 16 kHz, 0.96 s patches, about 15 MB) in stage 3 and keep v1 as the
   level 2 vector; PANNs MobileNetV1 (code MIT, weights CC BY 4.0, attribution in About) if YAMNet converts badly.
   `style` is unaffected: it reads `kind`, `era` and the Halloween flag, which become `ident.kind`, `ident.era` and
   a user tag [inf].
2. **What MU beats look like.** Every threshold in A4, A6 and L3 (70 ms inlier, 5 ms MAD floor, 15 ms trust
   residual, the integer re-indexing) was tuned on Beat This's 20 ms frame grid. If MU returns beats already snapped
   to its own constant tempo, `inlier_frac` saturates, `confidence` stops meaning "doubtful", the `.auto` trigger
   never fires and `local_tempo` trusts every window; coarser or smoother beats move the trust rule the other way.
   The residual-shape row decides: either MU stays the primary detector with retuned thresholds, or Beat This small
   becomes the raw detector and MU supplies bars, key, structure and activity [inf].
3. **Vocal semantics.** `VOC = 0.5` for vocal-free bars, 0.75 for `vocal_heavy`, 0.35 and 0.6 in `transition()`
   and the `v >= 0.6` gate were tuned against a head that reads 0.85 to 1.0 on most pop bars (273 of 373 are
   `vocal_heavy`). MU's activity is stem-like and probably sharper, so every one of these moves; the threshold sweep
   sets them, and the `score.py` constants become `Profile` parameters in DeckieCore rather than literals.
4. **Structure without labels or weights.** The lattice phase and the phrase confidence weight boundaries by
   novelty; MU boundaries carry none. Proposal: section starts 1.0, segments 0.5, phrases 0.25, with the Foote port
   as tie-breaker and the level 2 path [inf]. The on-lattice share in the benchmark says whether MU boundaries follow
   8-bar phrases on this material at all; under about 0.5, Foote stays the lattice source and MU supplies only the
   section labels.
5. **Loudness details.** Whether `LoudnessResult.peak` is true peak (track A, question 6) decides A17; LRA has to
   be recomputed from the short-term series with EBU gating to match pyloudnorm; 400 ms momentary windows straddle
   bar edges, so the engine keeps its own K-weighted per-bar measure (A14, tiny) and MU's series is a cross-check.
6. **Key confidence with two votes** caps at 0.7, so the key term's `(0.5 + 0.5 conf)` factor never reaches 1.0;
   acceptable for a soft term, but the "strength" in the rule has no MU equivalent and becomes the HPCP correlation
   margin [inf]. Key ranges may flicker; `key.changes` records ranges of 16 bars or more only. The published key
   profiles (Krumhansl and Kessler, Temperley, Faraldo's EDMA from the paper) are literature values, but the tables
   inside Essentia's source are AGPL code; take the numbers from the papers [inf, not legal advice].
7. **BPM tags.** Every candidate had a curated `bpm_tag`; in the product it comes from file tags and is often
   absent, which disables A5 and the tag half of the A6 trigger. Tagless behaviour to define: MU's octave stands,
   `half_time_candidate` keeps firing under 100 BPM, the second opinion fires on confidence alone.
8. **Cost, memory and thermal.** MU time is unpublished. The longest pool track is 598 s, which is 105 MB as 44.1
   kHz float32 mono and twice that in stereo: fine on a Mac, tight on an A13 phone, so the DSP path streams in
   blocks (biquads and the STFT are block-friendly; the true peak already is). Whether two MU sessions run at once
   on the Mac is a measurement, not a setting.
9. **Waveform snippets** and the overview wave are audio-derived and not in track A's crate; see the `waves/`
   proposal. Until that is decided the iPad cannot draw the join view from a crate alone.
10. **Toolchain.** Xcode 27 on macOS 26 [inf] for the device route, otherwise the Mac upgrades; the iPad Air 4 on
    iPadOS 27 is still the spec's open question (c).
11. **Legal and provenance.** Christopher's crate is regenerated by the shipped engine before any TestFlight build (track
    A, spec 5.1); Beat This small ships with its MIT licence file; a CC BY model needs attribution in About. The lab
    stays on this Mac.
12. **Documentation drift.** `mixer/README.md`'s weights and score line are stale against `score.py`; the port and
    the benchmark report cite the code. Fixing the README is a lab change outside this plan.
