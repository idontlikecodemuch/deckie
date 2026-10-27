# Automatic DJ mixing toolkit: research report

Date: 2026-10-23. Target machine: Apple Silicon Mac, macOS 26 (Darwin 25.6), Homebrew 7.0.9, ffmpeg 8.1.1 (Homebrew build), Homebrew `python@3.15` (3.15.0, the default `python3`) and `python@3.14` (3.14.5) both already installed.
Pool: ~200 MP3s (320 kbps), 1990s-2020s pop / house / hip-hop / dance remixes / Halloween novelty, 90-160 BPM, BPM already tagged.

Two deliverables this report is written for:

1. a pairwise "A mixes into B" compatibility score with human-readable reasons (for faint lines on a phone web page);
2. an offline renderer that turns a chosen track order into a 2-3 hour continuous mix file with DJ-style transitions.

Everything marked **[verified]** was checked today against a live URL, the PyPI JSON API, the GitHub API, or by actually installing and running it in a throwaway venv in the scratchpad (`venv314`, Python 3.14.5, numpy 2.5.4) on one real track from the pool (`Crystal Waters - Gypsy Woman (ALRT Remix)`, 181.6 s, 44.1 kHz stereo MP3). Anything marked **[unverified]** is from memory or from a secondary source. Opinions are labelled **[opinion]**.

---

## 0. Headline findings (read this first)

* **Use Python 3.14, not 3.15 or 3.13.** PyTorch 2.14.1 ships `cp310`-`cp314` macOS arm64 wheels but no `cp315` wheel yet, and the newest Essentia wheel (`2.1b6.dev1438`, 2026-05-19) is `cp314`-only on macOS arm64 (`macosx_15_0_arm64`); the previous build (`dev1389`, 2025-07-24) covers `cp39`-`cp313`. `python@3.14` is already installed via Homebrew. **[verified via PyPI JSON]**
* **madmom is usable again, but only from git.** PyPI `madmom 0.16.1` (2018) does not work on modern Python/numpy. `pip install --no-build-isolation git+https://github.com/CPJKU/madmom` (after `pip install setuptools wheel cython "numpy<3"`) builds `0.17.dev0` on Python 3.14 with numpy 2.5.4; `RNNDownBeatProcessor` + `DBNDownBeatTrackingProcessor` run (13.5 s for a 3-minute track on CPU). **[verified locally]** Issue #557 (Feb 2026) confirms the `np.float` fixes are on `main` (PR #542) but unreleased. The repo was last pushed 2026-03-20.
* **Beat This! is the best beat/downbeat tracker to lead with.** `pip install beat-this` (1.1.0, 2026-04-14, MIT code and weights) runs on Apple MPS by passing `device="mps"`: **0.8 s inference (+0.5 s model load)** for the 3-minute track, 2.4 s on CPU, 5.6 s on the very first run including the checkpoint download; 383 beats / 96 downbeats, 125.0 BPM; madmom's DBN downbeats agreed to within 20 ms on the same file. **[verified locally]**
* **Essentia works on arm64 from pip, but install `essentia-tensorflow` only, never both.** Installing `essentia` after `essentia-tensorflow` silently replaces the module and `TensorflowPredictEffnetDiscogs` disappears. **[verified locally: ImportError]** `KeyExtractor(profileType="edma"/"bgate")` and `RhythmExtractor2013` ran fine (D minor, strength 0.88; 126.9 BPM in 1.9 s).
* **librosa 1.0.0 (2026-08-11, requires Python >= 3.12)**, **pedalboard 0.9.26 (2026-10-07, wheels through cp315)**, **pyloudnorm 0.2.0 (2026-01-04)**, **soundfile 0.14.0 (2026-06-06)** all install from wheels and run. `pedalboard.time_stretch` (Rubber Band inside) stretched 30 s by 5% in 1.7 s. **[verified locally]**
* **MP3 decoder offsets were zero on the test file**: `soundfile`, `librosa.load`, `madmom.audio.signal.Signal` and `ffmpeg -> WAV` all produced 8,007,795 samples with 0-sample lag (all honour the LAME gapless header). The all-in-one README still warns of 20-40 ms differences between decoders, so decode **once** and analyse and render from the same array. **[verified on one file]**
* `torchaudio 2.11.0` `load()` now requires `torchcodec`; use `soundfile` for I/O instead. **[verified locally: ImportError]**
* **pydub is unmaintained (0.25.1, 2021) and imports `audioop`, which was removed in Python 3.13**; avoid it. **[PyPI date verified; audioop removal is standard Python 3.13 release info, the pydub breakage itself is unverified here]**
* Homebrew's ffmpeg 8.1.1 **does not include the `rubberband` filter** (checked `ffmpeg -filters`); it does have `atempo`, `loudnorm`, `alimiter`, `ebur128`, `afade`, `acrossfade`, `asetrate`, `aresample`, `firequalizer`, `anequalizer`, `aecho`. **[verified locally]**
* The best-documented scoring recipes to copy are **Vande Veire & De Bie 2018** (key filter + style descriptor + three transition types with 16/32-bar fades + ODF-DTW rhythm check + vocal-clash veto) and **Mosaikbox (ISMIR 2024)** (weighted sum: rhythm 0.3, timbre 0.75, key 0.2, harmony 0.2, spectral balance 0.1; cue points only at segment boundaries; -14 LUFS normalisation; <= +/-8% stretch; 16-downbeat bass-swap). Both are summarised with numbers in section B.
* Nothing called "DJ-GPT", "StyleDJ" or "DiffMix" exists as a DJ-transition paper that I could find. The 2023-2026 work that does exist: DJ StructFreak (ISMIR 2023 LBD), CUE-DETR (ISMIR 2024, cue points via object detection, code + 21k-cue dataset), Mosaikbox (ISMIR 2024, code), Diff2Mix (ISMIR 2026, multitrack mixing, **not** DJ transitions), plus several hobby LLM-driven mixers on GitHub (section D).

---

## A. Analysis tools (state as of 2026-10-23)

### A.1 Tempo, beat and downbeat tracking

| Tool | Version / date | Install on Apple Silicon | Downbeats? | Notes |
|---|---|---|---|---|
| **Beat This!** (CPJKU) https://github.com/CPJKU/beat_this | PyPI `beat-this` 1.1.0, 2026-04-14; repo pushed 2026-05-28; MIT (code and weights) | `pip install torch torchaudio soxr einops tqdm rotary-embedding-torch beat-this` (pure-Python wheel). Model `final0` (~78 MB) auto-downloads. **[verified]** | Yes | Transformer, no DBN by default (`dbn=True` needs madmom). Device is a plain string: `File2Beats(checkpoint_path="final0", device="mps")` worked: 0.8 s inference on MPS, 2.4 s on CPU for a 181 s track. Paper: https://arxiv.org/abs/2407.21658 (ISMIR 2024) claims SOTA F1 "despite using no DBN" but "performs worse on continuity metrics". Ports exist: ONNX (https://huggingface.co/musetric/beat-this-onnx), Core ML (https://huggingface.co/schism-audio/beat-this-coreml), Rust (`beat-this` crate). |
| **madmom** https://github.com/CPJKU/madmom | PyPI 0.16.1 (2018-11-14, do not use); git `main` = 0.17.dev0, pushed 2026-03-20; BSD code, **models CC BY-NC-SA 4.0** | `pip install setuptools wheel cython "numpy<3"` then `pip install --no-build-isolation git+https://github.com/CPJKU/madmom`. Builds on 3.14 + numpy 2.5.4. **[verified]** setup.py classifiers only list 3.9-3.12 and `python_requires` is unset. | Yes (`RNNDownBeatProcessor` + `DBNDownBeatTrackingProcessor(beats_per_bar=[4])`) | 13.5 s per 3-min track, CPU only. Still the reference DBN for "constant tempo + meter" post-processing. Issues: https://github.com/CPJKU/madmom/issues/557, #550, #535. |
| **BeatNet** https://github.com/mjhydri/BeatNet | PyPI 1.1.3 (2023-11-28); repo pushed 2026-04-13; **CC-BY-4.0** | `pip install BeatNet` + madmom (for offline DBN mode) + torch; `device` accepts `mps` per README. **[not run]** | Yes (+ meter) | CRNN + particle filter; good online/streaming; Mosaikbox used it as the beat front end and then fitted a constant grid on top (see B.4). |
| **librosa** `beat.beat_track`, `feature.tempo`, `beat.plp` https://librosa.org | 1.0.0, 2026-08-11, requires Python >= 3.12; ISC | `pip install librosa` **[verified]** | No | Ellis dynamic-programming beat tracker on onset strength: 8.5 s for the track (slower than Beat This on MPS!), 126.0 BPM. No downbeats. Fine as a cross-check and for `onset_strength` / spectral flux curves. |
| **Essentia** `RhythmExtractor2013(method="multifeature")`, `TempoCNN` https://essentia.upf.edu | PyPI `essentia`/`essentia-tensorflow` 2.1b6.dev1438, 2026-05-19 (cp314 arm64) / dev1389 (cp39-cp313); AGPL-3.0 | `pip install essentia-tensorflow` **[verified]** | `RhythmExtractor2013` no; there is a `BeatTrackerMultiFeature`; no downbeat algorithm | 126.9 BPM, confidence 1.39, 1.9 s. `TempoCNN` models (`deepsquare-k16-3.pb`, `deeptemp-k4-3.pb`) give global + local tempo at 11025 Hz input: https://essentia.upf.edu/models.html |
| **aubio** https://github.com/aubio/aubio | PyPI 0.4.9 (2019-02-08, no arm64 wheels, build fails on new numpy **[unverified]**); Homebrew `aubio 0.4.9` installed, CLIs `aubiotrack`, `aubiotempo`-style tools present **[verified]** | brew only | No | You already used it for BPM tags. Keep only as the "tag" source. |
| **all-in-one (allin1)** https://github.com/mir-aidj/all-in-one | PyPI 1.1.0 (2023-10-10); repo pushed 2024-05-09; MIT | needs `natten` (sdist only, compiles against torch; "installs automatically on macOS" per README) + madmom from git + demucs. **[not run; risky build]** Fork **`all-in-one-infer` 3.1.0 (2026-07-12)** removes NATTEN with pure-PyTorch attention and uses `demucs-infer`: https://pypi.org/project/all-in-one-infer/ **[PyPI verified, not run]** | Yes (beats, downbeats, `beat_positions`) | Also gives tempo and functional segments (see A.3). Runs Demucs internally, so it is the slowest option. |

Tempo sanity for your pool: hip-hop at 85-100 BPM vs house at 120-130 is often a 3:4 or 1:2 relationship. Treat the tag BPM, Beat This's median inter-beat interval and Essentia's `RhythmExtractor2013` as three votes; accept when two agree within 1%, otherwise flag the track. Mosaikbox reports that averaging inter-beat intervals from a neural tracker causes 1/3 and 3x octave errors on non-duple material and fixes it by fitting a constant 4/4 grid with dual annealing (B.4) — do the same for your constant-tempo tracks (almost all of them).

### A.2 Musical key detection and Camelot mapping

| Tool | Status | Notes |
|---|---|---|
| **Essentia `KeyExtractor`** https://essentia.upf.edu/reference/std_KeyExtractor.html | **[verified running]** | `profileType` default `bgate`; options include `edma`, `edmm`, `braw`, `bgate`, `shaath`, `krumhansl`, `temperley`, ... Profile notes from https://essentia.upf.edu/reference/std_Key.html: `edma` = profiles learned from an EDM corpus (Faraldo et al. 2016), "normally perform better" than `shaath`; `edmm` = hand-tweaked edma that reports majors as minors; `braw`/`bgate` = Beatport-derived median profiles (Faraldo 2017), `bgate` zeroes the 4 least relevant bins; `useMajMin=True` adds a third "majmin" class for ambiguous tracks (only with `edma`, `bgate`, `braw`). On the test track `edma`, `bgate`, `krumhansl` all said D minor (strength 0.88 / 0.88 / 0.78). Vande Veire & De Bie used exactly this (Faraldo) algorithm. |
| **libKeyFinder / keyfinder-cli** https://github.com/mixxxdj/libkeyfinder , https://github.com/evanpurkhiser/keyfinder-cli | Homebrew `libkeyfinder 2.2.8` bottled **[verified]**; `keyfinder-cli` is **not** in Homebrew, build with CMake (repo pushed 2026-09-17, GPL-3.0). `keyfinder-cli -n camelot file.mp3` prints e.g. `8B`. | The algorithm behind Mixxx's optional KeyFinder analyser ("more accurate than QM but slower": https://mixxx.org/news/2021-04-08-new-in-2-3-keyfinder) and Mosaikbox's key module. No Python binding found; shell out. |
| **madmom `CNNKeyRecognitionProcessor`** https://github.com/CPJKU/madmom/blob/main/madmom/features/key.py | ships with madmom git **[import not separately tested]** | Korzeniowski & Widmer, "Genre-Agnostic Key Classification with CNNs", ISMIR 2018; 24 classes (12 major then 12 minor, from A). A genuinely different (learned) method, useful as the second vote on vocal-heavy pop. Model files are CC BY-NC-SA. |
| Mixxx | Queen Mary key analyser default, KeyFinder optional (manual: https://manual.mixxx.org/2.5/en/chapters/preferences/key_detection) | |

Accuracy reality check: published key-detection tests on pop/EDM sit roughly between 40% and 86% depending on dataset (quoted by https://blog.faderpro.com/music-theory/camelot-wheel-dj-harmonic-mixing/). **[opinion]** For 1990s-2020s pop with heavy vocals, run two detectors (Essentia `edma` + either KeyFinder or madmom CNN), store both plus Essentia's `strength`, and treat key as a soft, confidence-weighted term in the score rather than a hard filter.

Camelot mapping (standard; `A` = minor, `B` = major): 1A Abm/G#m, 1B B; 2A Ebm, 2B F#/Gb; 3A Bbm, 3B Db; 4A Fm, 4B Ab; 5A Cm, 5B Eb; 6A Gm, 6B Bb; 7A Dm, 7B F; 8A Am, 8B C; 9A Em, 9B G; 10A Bm, 10B D; 11A F#m, 11B A; 12A C#m/Dbm, 12B E. (keyfinder-cli will emit this directly with `-n camelot`.)

### A.3 Structure, phrase grid, intro/outro regions

| Tool | Status | What it gives you |
|---|---|---|
| **all-in-one / all-in-one-infer** (Kim & Nam, WASPAA 2023, https://arxiv.org/abs/2307.16425) | see A.1 | Functional labels `intro, outro, break, bridge, inst, solo, verse, chorus, start, end` with boundaries, plus beats/downbeats and optional per-stem embeddings `[4 stems, T, 24]`. Trained on Harmonix (pop/EDM), which matches your pool well. CLI: `allin1 file.wav` -> `./struct/*.json`. RTX 4090: 10 songs (33 min) in 73 s; on an M-series CPU/MPS expect minutes per track **[unverified estimate]**. Used by DJ StructFreak and by the 2026 hobby project `autodj-mixer`. |
| **librosa Laplacian segmentation** (McFee & Ellis 2014) https://librosa.org/doc/0.11.0/auto_examples/plot_segmentation.html | library verified; example page for 1.0 moved (0.11 page is live) | Beat-synchronous CQT -> `librosa.segment.recurrence_matrix` + `path_enhance` -> graph Laplacian eigenvectors -> k-means. No labels, but cheap (seconds) and robust for "where do the big sections change". `librosa.segment.{recurrence_matrix, path_enhance, agglomerative, subsegment}` all present in 1.0.0. **[verified import]** |
| **msaf** https://github.com/urinieto/msaf | PyPI 0.1.80 (2023-06-25); repo pushed 2026-05-13; MIT | Boundary algorithms (`sf`, `foote`, `cnmf`, `olda`, `scluster`, `vmo`) + labelling (`fmc2d`, `cnmf`...). Install from git (`pip install .`); Python version support not stated **[not run]**. |
| **sf_segmenter** https://github.com/wayne391/sf_segmenter | 0.0.1, pushed 2023-02-08, no licence stated | Minimal reimplementation of Serra's structural-features boundary detector (what Mosaikbox used). |
| **Foote novelty (own code)** | trivial with numpy | Vande Veire & De Bie's recipe (B.1): two SSMs (13 MFCC cosine, RMS absolute diff) at half-beat frames, 64-frame checkerboard kernel (4 bars each side), geometric mean of the two novelty curves, top-20 peaks, snap to downbeats, keep subsets lying on an 8-bar lattice. |
| **CUE-DETR** https://github.com/ETH-DISCO/cue-detr | ISMIR 2024, MIT, Python 3.11.9, pushed 2024-08-19; checkpoints `disco-eth/cue-detr`, dataset `disco-eth/edm-cue` on Hugging Face | Predicts DJ cue points directly from spectrogram images (DETR). Trained on 21,461 cue points from four DJs' rekordbox libraries (4,710 EDM tracks, 95-190 BPM). Inter-cue distance peaks at 16 bars. CLI `python cue_points.py -t dir` (MP3 only). EDM-trained, so expect degraded results on 90s pop **[opinion]**, but it is the only "learned cue point" model with code. |

**Phrase grid recipe [opinion, assembled from the papers]:** downbeats from Beat This; constant-grid fit (bpm, first-downbeat offset) by least-absolute-deviation like Mosaikbox; boundaries from novelty (or allin1 labels); snap every boundary to the nearest downbeat; choose the 8-bar lattice phase that maximises summed novelty at lattice points (Vande Veire); from then on all cue points are `lattice_phase + 8k` bars. "Usable outro" = from the last strong boundary (last chorus end / outro label) to last sound (>-60 dBFS, Mixxx's rule); "usable intro" = first sound to first vocal/chorus boundary. CUE-DETR's data says real DJs' cues are 16 bars apart most often, so default to 16-bar mix-in/out windows and allow 8 or 32.

### A.4 Energy / loudness curves

* **pyloudnorm 0.2.0** (MIT, https://github.com/csteinmetz1/pyloudnorm): BS.1770-4 `Meter(rate).integrated_loudness(x)`, `loudness_range`, `normalize.loudness/peak`; `Meter(rate, block_size=0.4)` with gating gives you the K-weighted blocks. There is no public "momentary curve" method, so compute it yourself: apply the K-weighting filters (`meter._filters` or your own two biquads), then 400 ms RMS in LUFS on a 100 ms hop. **[verified: integrated loudness of the test track = -8.2 LUFS, i.e. a brickwalled modern master]**
* **ffmpeg `ebur128`** (`-af ebur128=peak=true:metadata=1 -f null -`) prints momentary (M), short-term (S), integrated, LRA and true peak per 100 ms frame. **[filter present locally]**
* `librosa.onset.onset_strength` (spectral flux on mel bands) and `librosa.feature.rms` for frame-level energy; beat-synchronise with `librosa.util.sync`. Vande Veire's melflux ODF is 40 mel bands, frame 1024 / hop 512, half-wave-rectified difference, minus a 16-frame running mean.
* **[opinion]** Store per-bar: short-term LUFS, low-band (<150 Hz) energy, high-band (>4 kHz) energy, onset density. That is enough for "energy continuity" and for choosing where a bass swap is safe.

### A.5 Vocal activity (to avoid vocal-on-vocal)

| Option | Status | Notes |
|---|---|---|
| **Essentia `voice_instrumental` classifier heads** https://essentia.upf.edu/models.html | models downloaded (`discogs-effnet-bs64-1.pb` 18 MB + `voice_instrumental-discogs-effnet-1.pb` 0.5 MB) and run: **1.0 s per 3-minute track**, one `[instrumental, voice]` probability per ~1 s patch, and the same call yields the 1280-d EffNet embeddings for A.6 **[verified]** | `TensorflowPredictEffnetDiscogs(graphFilename=..., output="PartitionedCall:1")` on 16 kHz audio, then `TensorflowPredict2D(graphFilename="voice_instrumental-discogs-effnet-1.pb", output="model/Softmax")` -> per-patch `[instrumental, voice]` probabilities (patches of ~1.9-3 s). Cheapest route to a vocal timeline. Also heads on `msd-musicnn`, `vggish`, `yamnet`, `openl3`. |
| **Demucs 4.1.0** https://github.com/adefossez/demucs | PyPI 2026-07-11, MIT, Python >= 3.10; maintainer says not actively developed. `docs/mac.md`: Apple Silicon uses Metal (MPS) automatically, fall back `-d cpu`. **Measured: `demucs -d mps --two-stems vocals` 17.7 s wall (about 10x realtime) vs `-d cpu` 53.8 s wall for the 181 s track; MPS works out of the box with torch 2.14.1 [verified]** | `demucs --two-stems vocals file.wav` (still computes all 4 stems). CPU ~1.5x realtime per README. Then vocal activity = frame RMS of the vocal stem relative to the mix (threshold around -30 dB, smooth over a beat). Most accurate, slowest. |
| **demucs-mlx** https://github.com/andrade0/demucs-mlx (MIT, pushed 2026-02-27) and `pip install demucs-mlx` from https://huggingface.co/ssmall256/demucs-mlx (MIT, pushed 2026-10-05) | author benchmarks: 34x realtime on M4 Max, 7-min track in 12 s, output within 1e-6 of PyTorch **[author's own numbers, unverified here]** | If Demucs on MPS is slow or falls back to CPU, this is the Apple-native path. `--stems vocals`. |
| **python-audio-separator 0.47.1** https://github.com/nomadkaraoke/python-audio-separator | PyPI 2026-10-19, MIT, Python >= 3.10 (`!= 3.14.1`); MPS for PyTorch models, CoreML for ONNX | BS-Roformer default model (best vocal SDR); `--mdxc_overlap=2` to speed up. Good alternative to Demucs for a clean vocal stem. |
| Speech VADs (Silero etc.) | not suitable | trained on speech; poor on sung vocals over music **[opinion from search results]**. |
| rekordbox "vocal detection" overlay | commercial, closed | exists in current rekordbox per reviews; not usable programmatically. |

Vande Veire & De Bie built a vocal-activity detector into their selector and veto any candidate whose vocals overlap the current song's vocals in the crossfade window; Mosaikbox goes further and removes clashing stems during the transition (significantly improved listener ratings). For your renderer, the cheap version is: never overlap two bars that are both "vocal" above a threshold; if the only good transition would, use an echo-out or a cut instead of a long blend.

### A.6 Timbre / style similarity embeddings

| Embedding | Install status | Licence | Notes |
|---|---|---|---|
| **Essentia Discogs-EffNet** (`discogs-effnet-bs64-1.pb`) | works with the `essentia-tensorflow` wheel: embeddings `[181, 1280]` for the 181 s track in 1.0 s including the voice/instrumental head **[verified running]** | Essentia AGPL; models CC BY-NC-SA 4.0 **[unverified]** | Mean-pool the 1280-d patch embeddings per track (or per section). Heads available for genre (Discogs400), mood, danceability, `timbre` (bright/dark), `tonal_atonal`, `voice_instrumental`. Cheapest "does this sound like that" vector. |
| **MERT-v1-95M** https://huggingface.co/m-a-p/MERT-v1-95M | `transformers` + `trust_remote_code=True`, 24 kHz input, 13 layers x 768 | **CC-BY-NC-4.0** | Strong general music representation; pick a middle layer and mean-pool. Heavier. |
| **CLAP** (LAION) https://github.com/LAION-AI/CLAP | PyPI `laion-clap` 1.1.7 (2025-05-04); repo CC0; pushed 2025-05-15 **[not installed; pinning issues with recent transformers are common, unverified]** | CC0 code | Lets you also score text prompts ("spooky", "90s house") against audio - handy for the Halloween novelty tracks. Microsoft `msclap` 1.3.4 (2025-05-23) is the lighter alternative. |
| **OpenL3** https://github.com/marl/openl3 | 0.4.2 (2023-05), TensorFlow/kapre; repo pushed 2023-06 | MIT | TF on arm64 is doable but the pins are old; `torchopenl3` 1.0.1 (2022) is also stale. Essentia ships OpenL3 `.pb` graphs instead (`openl3-music-mel128-emb512-3.pb`). **[opinion]** skip. |
| **musicnn** | PyPI 0.1.0 (2019), TF1 | - | dead; use Essentia's `msd-musicnn-1.pb` instead. |
| Hand-crafted (Vande Veire) | numpy | - | 48-d spectral-contrast mean/std/delta vector projected to a low-dim "style" space; worked for DnB. |

### A.7 How DJ software picks cue points and mix in/out points

* **Mixxx AutoDJ** (https://github.com/mixxxdj/mixxx/blob/main/src/library/autodj/autodjprocessor.cpp, `calculateTransition()`): intro/outro are *sections* (two points each). Analyzer puts intro-start at first sound and outro-end at last sound using a **-60 dBFS** threshold (https://mixxx.org/news/2020-07-09-intro-outro-sections); the DJ marks intro-end / outro-start. Modes: `FullIntroOutro` = transition length is the **shorter of intro and outro**, fade ends at outro-end (`fadeBeginPos = outroEnd - transitionLength`); `FadeAtOutroStart` = fade starts at outro-start, length = outro length capped by intro length; `FixedFullTrack`, `FixedSkipSilence` (fixed seconds, trimmed at first/last sound), `FixedStartCenterSkipSilence`. The crossfader moves **linearly with the outgoing deck's play position**; AutoDJ does **no tempo sync** itself (sync is a separate deck feature). Beat/key analysis: QM analysers by default, KeyFinder optional.
* **VirtualDJ Automix** (https://www.virtualdj.com/manuals/virtualdj/interface/browser/sideview/automix.html): "optimal mix point based on the outro of the current track and intro of the upcoming track", ~4-8 s; modes Fade (remove intro/outro | remove silence | remove nothing), Fade-out/Cut-in, None; POI editor exposes "mix in / mix out" points that can be snapped to the beat grid.
* **rekordbox Phrase Analysis** (https://rekordbox.com/en/feature/djing/): labels Intro/Up/Down/Chorus/Verse/Outro with separate EDM and pop modes; results are rigid and often need manual correction (reviews); newer versions overlay vocal sections. The `djcues` PyPI tool maps rekordbox phrases to a fixed cue scheme (first chorus after 20% = "Drop", etc.). CUE-DETR's dataset shows pro DJs' rekordbox cues cluster on 16-bar phrase boundaries.
* **Serato / Traktor**: not researched in depth; neither exposes a documented automatic mix-point algorithm **[unverified]**.

---

## B. Compatibility scoring: what the literature and the software actually do

### B.1 Vande Veire & De Bie, "From raw audio to a seamless mix: creating an automated DJ system for Drum and Bass", EURASIP J. Audio Speech Music Process. 2018:13
Paper (open access, CC BY 4.0): https://doi.org/10.1186/s13636-018-0134-8 (PDF via https://asmp-eurasipjournals.springeropen.com/track/pdf/10.1186/s13636-018-0134-8). Code: https://github.com/lenvdv/dnb-autodj-3 (Python 3 port, AGPL-3.0, last pushed 2024-06-17, written for Python 3.6 / Ubuntu 16.04, pyaudio + ffmpeg; the original Python 2 repo link in its README is dead). **[paper text extracted and read; code not run]**

What it computes (with the numbers):
* **Beat tracking**: Davies & Plumbley-style, assumes constant tempo; melflux ODF (40 mel bands, frame 1024, hop 512 at 44.1 kHz), 16-frame running-mean subtraction, autocorrelation summed at integer multiples of the lag to pick the period, then phase.
* **Downbeat tracking**: learned classifier on bar-level features (section 3.2; not needed today because Beat This/madmom do it better).
* **Structural segmentation**: Foote novelty on two SSMs (13 MFCCs with cosine distance; RMS with absolute difference) at half-beat frames / quarter-beat hop; checkerboard kernel K = 64 frames (4 bars each side); combine by **geometric mean** of the two novelty curves (peak only where energy *and* timbre change); take the 20 highest peaks, snap to the nearest downbeat, discard peaks > 0.4 bar from a downbeat, then keep the subset of boundaries that lie on an **8-bar lattice** maximising summed novelty, suppressing peaks 1-2 bars before a bigger peak (breaks). Segments are labelled high/low energy; a "drop" = low->high boundary.
* **Track selection, five sieves in order**: (1) **key filter**: allowed = same key, perfect fifth up or down (dominant/subdominant), relative major/minor, plus keys one semitone off those (which are then **pitch-shifted** by +/-1 semitone to fit); key from Essentia's Faraldo EDM profile; (2) **style descriptor**: 48-d spectral-contrast statistics projected to a low-dim space, keep the **6 nearest** songs; (3) **cue point selection** per transition type (below); (4) **vocal clash veto**; (5) **rhythmic similarity** = DTW distance between the onset-detection functions of the two overlapped segments (with beam search to limit warping); lowest DTW wins.
* **Three transition types** (Table 3 is a Markov chain: from Relaxed -> Rolling 0.7 / DoubleDrop 0.3; from Rolling -> Relaxed 0.2 / Rolling 0.8; from DoubleDrop -> Relaxed 0.2 / Rolling 0.8; no double drop after a rolling or another double drop):
  * **Double drop**: both cues 16 bars before a drop; fade-in 16 bars, fade-out 32 bars; drops aligned.
  * **Rolling**: current-song cue 32 bars before the next high->low boundary; next-song cue 16 bars before its drop; 16-bar fade-in and fade-out.
  * **Relaxed**: current-song cue 16 bars before a high->low boundary; next song starts at its first structural boundary; 16/16 bars.
* **Crossfade rendering**: time-stretch via HPSS, phase vocoder on the harmonic part + OLA on the percussive part (Driedger & Muller); volume + 3-band EQ pattern: during the fade-in the incoming song rises in volume with bass and treble almost fully cut; at the end of the fade-in a quick **switch** swaps bass+treble (new in, old out); the old song's volume then fades to zero. "Only one song's bass and treble at any moment."
* **Numbers**: 12 s per song to annotate (2.3 s per minute of audio) and 17 s per transition on a 2016 i7 laptop; 91% of 380 songs fully correctly annotated; 18-listener study positive.

### B.2 AutoMashUpper (Davies, Hamel, Yoshii, Goto; ISMIR 2013 https://archives.ismir.net/ismir2013/paper/000077.pdf, IEEE/ACM TASLP 22(12) 2014 https://staff.aist.go.jp/m.goto/PAPER/IEEETASLP201412davies.pdf)
"Mashability" between a phrase section of the seed and every phrase of every candidate, **over a grid of key shifts and tempo changes**: harmonic similarity (beat-synchronous chroma correlation), rhythmic similarity (sub-beat onset pattern cosine), and **spectral balance** (how the low/mid/high energy of the two complement each other); sections are then pitch-shifted/time-stretched and loudness-matched. No official code found **[unverified]**; Mosaikbox reimplemented it as its baseline (and its harmonic + spectral-balance terms are reused there).

### B.3 Kim, Choi, Sacks, Yang, Nam (KAIST) - analysis of real DJ mixes
* "A Computational Analysis of Real-World DJ Mixes using Mix-To-Track Subsequence Alignment", ISMIR 2020, https://arxiv.org/abs/2008.10267 ; code https://github.com/mir-aidj/djmix-analysis (Python 3.8 + madmom 0.16.1, no licence file, pushed 2020-10-21). Subsequence DTW aligns 1,557 mixes / 13,728 tracks / 20,765 transitions; yields cue points, transition lengths, tempo adjustments in real mixes.
* "Reverse-Engineering the Transition Regions of Real-World DJ Mixes using Sub-band Analysis with Convex Optimization", NIME 2021, https://nime.pubpub.org/pub/g7avj1a7 ; code https://github.com/mir-aidj/transition-analysis (pushed 2021-06-15, no licence). Estimates per-band (EQ-3: low/mid/high) gain curves DJs applied; renders baseline / crossfade / EQ-3 reconstructions.
* "Joint Estimation of Fader and Equalizer Gains of DJ Mixers using Convex Optimization", DAFx 2022, https://mac.kaist.ac.kr/pubs/KimYangNam-dafx2022.pdf ; dataset https://github.com/mir-aidj/djmix-dataset.
* "DJ StructFreak", ISMIR 2023 LBD https://ismir2023program.ismir.net/lbd_328.html : picks the best-matching *segment* for a user-chosen mix point using all-in-one's structure embeddings (demo at https://taejun.kim/dj-structfreak).
All verified via https://mac.kaist.ac.kr/ai_dj.html. Code is research-grade and pinned to madmom 0.16.1; mine them for ideas, not for reuse.

### B.4 Mosaikbox (Sowula & Knees, ISMIR 2024) https://doi.org/10.5281/zenodo.14877463 , code https://github.com/robaerd/mosaikbox (Python 3.11, FastAPI backend, hard-codes `mps`, KeyFinder in Docker, no licence file, pushed 2025-06-27) **[paper read; code not run]**
* Beat grid: BeatNet beats -> constant 4/4 grid (bpm, first downbeat) by dual annealing minimising mean |grid - detected beats|, search +/-15% then +/-5% of the IBI-median tempo. Beats 1% tolerance accuracy on GiantSteps: 69.6% vs 67.0% for Bock & Davis.
* Segmentation: Serra structural features + Nieto/Bello labels, quantised to downbeats; intro/outro segments penalised x0.5 (they want energetic mixes).
* Similarity terms: rhythm (drum transcription -> kick/snare/hat on a 12-sub-beat grid, fraction of matching cells), timbre (28-d MFCC+flatness+"dirtiness", cosine), key (KeyFinder; 1 if same tonic, else 1/semitone-distance, with pitch shifting allowed), harmony and spectral balance (AutoMashUpper's), lyrics sentence embeddings (no benefit).
* **Mixability = 0.3 rhythm + 0.75 timbre + 0.2 key + 0.2 harmony + 0.1 spectral balance** (+0.25 lyrics), evaluated over the 64 beats *after* the seed phrase; cue point = segment boundary of the candidate with max mixability (free beat shifts gave 7/9/15/17-bar nonsense); minimum play per song 55 s.
* Rendering: every song normalised to **-14 LUFS**; pitch-shift to compatible key; time-stretch to the previous tempo with **max +/-8%**; **16-downbeat transition** (8 before the seed's end, 8 after); bass-swap extended to highs; if timbre similarity < 0.95 cut the outgoing song's mids, if rhythm similarity >= 0.95 attenuate bass less; **rule-based stem removal** of clashing stems during the overlap (significantly better ratings, p < 0.0001 vs. its own base model; all variants beat AutoMashUpper).

### B.5 DJtransGAN (Chen et al., ICASSP 2022) https://arxiv.org/abs/2110.06525
Code: https://github.com/ChenPaulYu/DJtransGAN (MIT, pushed 2025-11-07; pretrained `djtransgan_minmax.pt`, `script/inference.py --prev_track --next_track --prev_cue --next_cue`) and the data pipeline https://github.com/ChenPaulYu/DJtransGAN-dg-pipeline (MIT, 2022). Generator = differentiable fader + time-frequency EQ driven by a CNN, discriminator trained on real mixes. It **renders** a transition given two tracks and two cue points; it does not pick tracks or cues. Dependencies are 2021-era **[not run]**; **[opinion]** interesting as a "learned EQ/fader curves" generator but not worth the dependency pain versus hand-written bass-swap curves.

### B.6 Cue-point work
* Zehren, Alunno, Bientinesi, "Automatic Detection of Cue Points for DJ Mixing", 2020, https://arxiv.org/abs/2007.08411 ; rules from DJ interviews + novelty; code https://github.com/MZehren/Automix (MIT, pushed 2020-02-11, madmom fork, partly Python 2) and dataset https://github.com/MZehren/M-DJCUE. 96% of generated points judged usable.
* CUE-DETR (ISMIR 2024) - see A.3. Inter-cue distance mode = 16 bars; dataset tempo 95-190 BPM.

### B.7 Mixxx AutoDJ, VirtualDJ, rekordbox - see A.7. None of them score pairs; they only decide *where* to fade. Mixxx's rule "transition length = min(intro length, outro length), fade ends at outro end" and the -60 dBFS first/last-sound trim are worth copying as defaults.

### B.8 2023-2026 generative / LLM work
* Diff2Mix (Zong, Shi, Reiss, ISMIR 2026, https://arxiv.org/abs/2608.05442): diffusion + differentiable console for **multitrack** mixing - not DJ transitions.
* M. Hein, "A Supervised Learning Framework for Generating DJ Transitions", Princeton senior thesis 2025 (https://theses-dissertations.princeton.edu/entities/publication/86237923-6f8a-4172-a6e7-d639e97d38d1): CNN on mel-spectrograms predicting volume/EQ control signals from 1001Tracklists mixes. Code availability **[unverified]**.
* Hobby LLM mixers: kckDeepak/AI-DJ-Mixing-System (GPT-4o picks songs and transition points, Whisper for vocals, librosa + pydub rendering; MIT; pushed 2026-02-03), StanAngular/autodj-mixer (all-in-one fork + Demucs + madmom + ACE-Step "AI transitions"; MIT; pushed 2026-10-23, 0 stars). Neither has an evaluation. No "DJ-GPT", "StyleDJ" or "DiffMix" paper exists that I could find (extended search, 2026-10-23).

### B.9 Harmonic rules and how much to penalise (Camelot)
Sources: Mixed In Key guide https://mixedinkey.com/harmonic-mixing-guide/ and book chapter https://mixedinkey.com/Book/Use-Advanced-Harmonic-Mixing-Techniques/ ; FaderPro https://blog.faderpro.com/music-theory/camelot-wheel-dj-harmonic-mixing/ ; Mixed In Key "Change energy with the Camelot wheel" https://mixedinkey.com/workflows/change-energy-with-camelot-wheel/.
* Same code (8A->8A): perfect. +/-1 same letter (8A->7A/9A): a fifth apart, "smooth". Same number other letter (8A->8B): relative major/minor, "pleasant". These three plus same-key are the canonical "compatible" set.
* **Energy boost**: +7 on the wheel = **+1 semitone** (8A->3A), +2 on the wheel = **+2 semitones** (8A->10A). Mixed In Key says both lift energy and that +2 is the stronger of the two; the forum/Bonedo sources point out +2 semitones is really 14 steps (one full turn plus two). These are "use when you *want* a lift" moves, not neutral ones.
* Everything else: dissonant unless one track is in a breakdown with no sustained harmony (which is why DJs mix drums-only sections).
* Vande Veire & De Bie allow exactly {same, +/-1, relative} and *extend* the pool with +/-1-semitone neighbours of those by pitch-shifting; Mosaikbox scores 1/semitone-distance and pitch-shifts to the nearest compatible key.

**[opinion] Suggested key term** (needs both detectors' confidence c_A, c_B in 0..1):
`key_raw`: same 1.00; +/-1 same letter 0.90; relative (A<->B) 0.85; +2 (energy boost) 0.65; +7 / -7 (semitone up/down) 0.50; -2 0.45; everything else 0.15.
If a pitch shift of s semitones (|s| <= 2) would put B in the {same, +/-1, relative} set, offer `key_shifted = 0.85 - 0.12*|s|` and record the reason "pitch-shift B by +1 st". Final `key = max(key_raw, key_shifted) * (0.5 + 0.5 * min(c_A, c_B))` so a low-confidence key never dominates. Treat `strength < 0.6` from Essentia or disagreement between the two detectors as c = 0.3.

### B.10 A concrete pairwise score with reasons [opinion, synthesised from B.1-B.9]
Compute once per ordered pair (A -> B), using A's **mix-out window** (its usable outro, default last 16-32 bars before last sound / after the last chorus) and B's **mix-in window** (first 16-32 bars):

1. **Tempo** `r = bpm_B / bpm_A` after choosing the multiplier k in {1/2, 2/3, 3/4, 1, 4/3, 3/2, 2} that minimises |log r|; stretch % = |r-1|*100 applied to B (or split between both). `tempo = 1` for <= 3%, linear down to 0 at 8%, hard reject beyond 10%. If k != 1 subtract 0.15 and add reason "half-time/double-time blend". (Mosaikbox cap +/-8%; the songs-automixer project accepts half/double-time pairs as-is.)
2. **Key** as in B.9.
3. **Energy continuity** `dE` = short-term LUFS of B's mix-in minus A's mix-out, in LU, after each has been normalised to the same integrated loudness: `energy = 1 - clip(|dE| - 2, 0, 8)/8`. Keep the sign for the "set arc" (rising vs. resting) rather than penalising it.
4. **Vocal overlap** `v = mean over overlapped bars of P_vocal_A(bar) * P_vocal_B(bar)` over the planned overlap; `vocal = 1 - v`; if B's first 16 bars are instrumental add +0.1 ("B has a clean 16-bar intro").
5. **Phrase feasibility** `phrase = conf_grid_A * conf_grid_B * [A has >= 16 bars of outro] * [B has >= 16 bars of intro]`; otherwise fall back to an 8-bar quick blend and mark the reason.
6. **Timbre / style** cosine similarity of Discogs-EffNet (or MERT) mean embeddings over the two windows, rank-normalised within your pool to 0..1 (so the score says "closer than 80% of pairs").
7. **Rhythm** correlation of beat-synchronous onset-strength patterns (2 bars, 16 cells) between the windows, or Vande Veire's DTW; 0..1.

`score = 0.30*tempo + 0.20*key + 0.15*energy + 0.15*vocal + 0.10*phrase + 0.05*timbre + 0.05*rhythm`, with hard gates: tempo > 0 and not (vocal overlap > 0.5 without an alternative cut-style transition). Emit `reasons` = the three largest positive terms and every term below 0.4, each rendered as a short string ("+4.1% stretch", "8A -> 9A", "B intro is instrumental", "vocals overlap 6 of 16 bars"). The scores are symmetric only by accident: A->B uses A's outro and B's intro, so keep the matrix directed (200 x 199 = 39,800 pairs; with per-track features cached this is milliseconds).

For the phone page: draw a line when `score >= 0.6`, opacity = (score - 0.6)/0.4, and show the reasons on tap.

---

## C. Rendering transitions in Python

### C.1 Library choice (which to prefer)
| Library | Role | Verdict |
|---|---|---|
| **numpy + scipy.signal** | all mixing maths (gain envelopes, LR4 crossovers via `butter`+`sosfilt`, `np.interp` varispeed) | primary |
| **soundfile 0.14.0** (arm64 wheel) | read MP3/WAV/FLAC into float32, stream-write the long mix in blocks (`sf.SoundFile(..., mode="w")`) | primary I/O; verified zero-offset MP3 decode |
| **pedalboard 0.9.26** (Spotify, GPL-3.0, wheels cp310-cp315) https://spotify.github.io/pedalboard/ | `time_stretch` (Rubber Band inside, see C.2), `PitchShift`, `BrickwallLimiter(true_peak=True)`, `Delay`, `Reverb`, `LadderFilter` (12/24 dB), `PeakFilter`, shelves, `Resample` | primary FX; note its `HighpassFilter`/`LowpassFilter` are **first-order 6 dB/oct**, too gentle for an isolator - use scipy for the 3-band split |
| **pyloudnorm 0.2.0** | LUFS metering and per-track normalisation | primary |
| **ffmpeg 8.1.1** | decode/encode (MP3 320k via libmp3lame), `loudnorm` two-pass, `ebur128`, `atempo`, `acrossfade`, chapters | encode + final loudnorm fallback |
| **Rubber Band CLI 4.0.0** (brew, GPL) + **pyrubberband 0.4.0** | alternative stretcher via temp files (`rubberband -3` / `--fine` for the R3 engine) | optional; pedalboard already embeds Rubber Band |
| **sox 14.4.2** (brew) | `speed` (pitch+tempo), `tempo` (WSOLA), `fade` shapes `q h t l p`, `splice` | optional CLI fallback |
| **pydub** | - | avoid (unmaintained since 2021; `audioop` removed in 3.13) |
| **soxr 1.1.0** (python-soxr) | high-quality fixed resampling; experimental `ResampleStream(vr=True)` + `set_io_ratio(..., slew_len)` for variable-rate | optional for brakes (numpy interp is simpler) |

### C.2 Tempo matching (pitch preserved)
* **pedalboard.time_stretch(audio, sr, stretch_factor, pitch_shift_in_semitones=0, high_quality=True, transient_mode="crisp"|"mixed"|"smooth", transient_detector="compound"|"percussive"|"soft", retain_phase_continuity, use_long_fft_window, use_time_domain_smoothing, preserve_formants)** - these are Rubber Band's option names; `stretch_factor > 1` speeds up. **Both `stretch_factor` and `pitch_shift_in_semitones` accept per-sample float64 arrays (since v0.9.8; changes finer than 1024 samples are ignored)**, which gives you *gradual tempo ramps* (pyCrossfade-style "1.01x -> 1.10x over 10 bars") in one call. 30 s stretched by 5% took 1.7 s. **[verified]** Whether `high_quality=True` selects the R3 engine is not stated in the docstring **[unverified; likely]**.
* **Rubber Band Library 4.0.0** (2024-10-25, GPL / commercial; https://breakfastquay.com/rubberband/): R2 "faster" vs R3 "finer" engines (R3 since v3.0, 2022-07; better on vocals and complex mixes, several times the CPU); CLI `rubberband -3 --tempo 1.04 in.wav out.wav` (or `rubberband-r3`). Homebrew formula is bottled for arm64. `pyrubberband` just shells out through temp WAVs.
* **ffmpeg `atempo=1.04`** (range 0.5-100, chain for more): usable for small ratios **[opinion: audibly worse than R3 on sustained vocals]**; Homebrew ffmpeg has no `rubberband` filter.
* **sox `tempo -m 1.04`** (WSOLA with music preset): ok for +/-5%.
* **librosa.effects.time_stretch(y, rate=...)**: plain STFT phase vocoder; smeared transients and phasiness at >3% **[opinion]**; keep for prototypes only.
* **SoundTouch**: `soundstretch` CLI exists on Homebrew as `sound-touch` **[unverified]**; no maintained Python wheel; skip.
* Vande Veire & De Bie's HPSS trick (phase vocoder on harmonic + OLA on percussive) is implementable with `librosa.decompose.hpss` + two stretchers if you want to avoid GPL Rubber Band.
* **Practical limits [opinion, consistent with Mosaikbox's +/-8% cap and the DJ folklore of +/-6%]**: <= 4% is inaudible on most pop; 4-8% is fine on drums/house but smears sustained vocals; >8% use a resample ("vinyl pitch") instead if the key term tolerates the semitone drift, or do a non-blend transition (brake, echo-out, cut, scratch).

### C.3 Beat-aligned crossfade with equal-power curves
1. Choose cue downbeat `t_A` (bar index in A's grid) and `t_B` (bar in B's grid), transition length `L` bars (8/16/32).
2. Stretch B by `r` so its bar length equals A's; recompute B's grid (`t * 1/r`).
3. Sample-align: offset so that B's downbeat `t_B` lands exactly on A's downbeat `t_A`; sub-sample accuracy is unnecessary (beat tracker jitter is ~10-20 ms) but keep the two **constant grids** exact so later bars do not drift.
4. Equal-power curves over the overlap `x in [0,1]`: `g_A = cos(pi/2 * x)`, `g_B = sin(pi/2 * x)` (power-complementary; sum of squares = 1). Use equal-power for uncorrelated material; a linear ("equal-gain") curve dips 6 dB in the middle for correlated signals, which almost never happens with two different songs **[standard DSP]**. ffmpeg's `acrossfade` curves `qsin`/`hsin` (quarter/half sine), `esin`, `log`, `exp`, `tri` and friends are the same family; `afade curve=` list: `tri qsin hsin esin log ipar qua cub squ cbr par exp iqsin ihsin dese desi losi sinc isinc quat quatr qsin2 hsin2 nofade` **[filter present locally]**.
5. Snap fade segments to bars: most DJ-style fades are step-wise (per 4 or 8 bars), not continuous; compose the envelope as a piecewise-linear curve over bar boundaries.

### C.4 EQ bass-swap (3-band isolator)
* Split each track into low / mid / high with **Linkwitz-Riley 4th-order (LR4)** crossovers at ~200 Hz and ~2.5 kHz: `sos = scipy.signal.butter(2, fc, btype, fs=sr, output="sos")` applied **twice** (two cascaded Butterworth-2 = LR4; bands sum flat in magnitude). Apply per-band time-varying gains (gain arrays, linear-in-dB ramps per bar) then sum. The 2026 `autodj-mixer` repo does exactly this ("LR4 crossover, bar-by-bar warp").
* Mosaikbox's curve (16 downbeats): incoming volume rises over the first 8, its **bass stays cut until the swap bar**, outgoing bass drops at the swap, highs follow the same pattern; cut the outgoing mids if timbre similarity is low. Vande Veire: bass+treble of only one song audible at any instant, swap is "quick" (1 bar).
* Kim et al.'s NIME 2021 analysis of real mixes found DJs' EQ moves are well modelled as three sub-band gain curves - the same model.
* pedalboard route: `LowShelfFilter(cutoff_frequency_hz=200, gain_db=-24)` / `HighShelfFilter` in a `Pedalboard`, processed in 1024-sample blocks with `reset=False` while you update `gain_db` per block - works, but the scipy LR4 version is simpler and sample-accurate.

### C.5 Echo-out and filter-sweep exits
* **Echo-out**: tempo-synced delay (3/8 or 1/2 beat; `delay_s = 60/bpm * 0.75`), feedback 0.55-0.7, mix 100% on a *send*: take A's last bar(s) before the exit bar, zero everything after the exit, run through `pedalboard.Delay(delay_seconds, feedback, mix=1.0)` (or your own feedback line in numpy), so only the tail rings into B. Add a gentle low-pass in the feedback path (`LadderFilter LPF12 ~4 kHz`) for the classic dub decay **[opinion]**.
* **Filter-sweep exit**: high-pass cutoff ramp 30 Hz -> 3 kHz over 8-16 bars (log-spaced), resonance 0.2-0.4, on A while B's bass comes in; implement with `pedalboard.LadderFilter(mode=HPF24)` in blocks with `reset=False`, updating `cutoff_hz` per 1024-sample block, or with scipy biquads recomputed per block. Low-pass sweep (20 kHz -> 300 Hz) is the "drown" variant.

### C.6 Vinyl brake / slow-down and backspin (pitch *not* preserved, by design)
Varispeed resampling, not time-stretch. Define a playback-rate curve `r(t)` from 1 down to 0 over `T` = 1-3 s (a bar at 128 BPM is 1.875 s): `r(t) = (1 - t/T)^p` with `p` about 1.5-2 (ease-out feels like a motor spinning down); read position `pos = cumsum(r)/1` in input samples; output `y = np.interp(pos, np.arange(n), x)` (linear is fine while slowing; use `scipy.signal.resample_poly` or `soxr` only for speeding up, where aliasing appears). Multiply by a gain fade (e.g. `r**0.5`) and optionally a low-pass that tracks `r` to mimic cartridge roll-off. **Backspin**: `r` goes from 1 to about -3 quickly then decays to 0 while the gain drops; or simply play a sampled backspin (the songs-automixer project ships `samples/top_DJ_Rewind_SFX_10.mp3`, licence of that file unclear). Reference implementations of the phase-accumulator varispeed: Ardour's `Interpolation` classes (https://git.ardour.org/ardour/ardour/commit/43340cd37ce91752f80b776d905e1b0d103c89ef), FL Studio's Tape Stop semantics (https://www.image-line.com/fl-studio-learning/fl-studio-mobile-online-manual/html/plugins/FL%20Studio%20Mobile_Module_Tape_Stop.htm). ffmpeg can do a static version with `asetrate`+`aresample` but not a ramp in one filter; sox `speed` likewise. python-soxr `ResampleStream(vr=True)` + `set_io_ratio(..., slew_len)` is the "proper" variable-rate resampler if you want band-limited output (https://python-soxr.readthedocs.io/en/stable/soxr.html).

### C.7 Scratch transitions
* **Synthesis from a sample** (own design, same model as the GPL-2.0 C++ "Scratcher" simulator https://github.com/fynv/Scratcher , which uses a cubic-Hermite *time-map* curve for the record position and a separate volume curve): pick a 0.3-1.0 s source slice (a vocal stab, "ahh"/"fresh", a snare, or 1 beat of A itself); define a record-position function `s(t)` over the scratch duration (baby scratch = triangle wave of period 1/4-1/2 beat with amplitude = slice length; chirp = fast forward stroke + crossfader cut on the backstroke; transformer = steady stroke gated by a square-wave crossfader at 1/8 or 1/16 beat); render `y = interp(s(t)*sr, x)` with cosine-smoothed corners (`scipy.interpolate.CubicHermiteSpline`) so velocity is continuous; multiply by a crossfader gate envelope with 2-5 ms ramps (no clicks). Quantise strokes to the beat grid and end the scratch on the downbeat where B starts.
* **Free scratch samples (CC0)**: Freesound search "scratch dj" filtered to Creative Commons 0 returns 342 sounds **[verified 2026-10-23]**: packs include "Scratch" (SaschaRettberg), "DJ Scratching" (templeofhades), "VINYL_SCRATCHES" (G_M_D_THREE, e.g. `SCRATCH_TRANSFORM_013.aif`), "Scratching samples (100 BPM)" (Bronxio) - https://freesound.org/search/?q=scratch+dj&f=license%3A%22Creative+Commons+0%22 . Check each sound's page; the filter is per-file. The Crossfader "scratching tools" pack (https://wearecrossfader.co.uk/scratching-tools) needs sign-up and states no licence.
* No maintained Python scratch library exists **[extended search]**.

### C.8 Risers, impacts, air horns (licences)
* Freesound "riser" with CC0 filter: **879 sounds** (packs "Risers" by rubenrox, "reverses, risers, sweeps and swells" by reathance, "Risers and dopplers" by WildBurne, "Risers / Downers 01" by spaghettiSFX, `riser_02_140bpm` by vekoN) - https://freesound.org/search/?q=riser&f=license%3A%22Creative+Commons+0%22 **[verified]**. Do the same query for `impact`, `air horn`, `sub drop`, `reverse cymbal`.
* Risers are tempo-specific: pick ones tagged with a BPM near the target or time-stretch them (they tolerate large ratios), and align their *end* to the drop downbeat.
* 99Sounds packs are "royalty-free", not CC0 (https://99sounds.org/); Uppbeat/Artlist are stock licences. Avoid.
* Or synthesise: white-noise riser = noise through a band-pass whose centre sweeps 200 Hz -> 8 kHz with rising gain and a 1/16-beat tremolo; impact = 60 Hz sine with pitch drop + noise burst + reverb. Both are 20 lines of numpy/pedalboard.

### C.9 Mastering the final mix
* Normalise **each track** to the same integrated loudness before mixing (Mosaikbox: -14 LUFS; your masters sit around -8 LUFS, so that is 6 dB of headroom, which also prevents clipping when two tracks overlap). `pyln.normalize.loudness(x, meter.integrated_loudness(x), -14.0)`.
* Sum in float32/64, never int16, and keep the running mix in a memory-mapped or block-written file (3 h stereo float32 = 1.9 GB).
* Final stage: `pedalboard.BrickwallLimiter(ceiling_db=-1.0, true_peak=True, release_ms=...)` (configurable ceiling, no makeup gain, 4x-oversampled true-peak sidechain) - do **not** use `pedalboard.Limiter`, which is a JUCE loudness maximiser with automatic makeup gain and a hard clip at 0 dBFS **[docstrings verified]**. Then measure with pyloudnorm and trim gain to your target (-14 LUFS for phones/streaming; -9 to -10 LUFS "club" level if you want it to sound like the originals **[opinion]**).
* Alternative in ffmpeg: two-pass `loudnorm=I=-14:TP=-1:LRA=11:print_format=json` (first pass) then `loudnorm=...:measured_I=..:measured_LRA=..:measured_TP=..:measured_thresh=..:linear=true` (second pass) - options verified in the local build. `alimiter=limit=0.89:attack=5:release=50` is the ffmpeg limiter.
* Export: WAV/FLAC master plus `ffmpeg -i mix.wav -codec:a libmp3lame -b:a 320k mix.mp3`; write a cue sheet / ffmpeg chapter metadata with each track's start so phones can skip.

---

## D. Existing end-to-end open-source auto-DJ projects (GitHub API checked 2026-10-23)

| Project | Language / licence | Last push | What it does well | Runs on current Python? |
|---|---|---|---|---|
| **lenvdv/dnb-autodj-3** https://github.com/lenvdv/dnb-autodj-3 | Python, AGPL-3.0 | 2024-06-17 | The reference architecture (B.1): annotation modules -> JSON per song, track selector with key/style/vocal/ODF sieves, three transition types, HPSS stretching, EQ crossfade, live playback via pyaudio. | Written for 3.6; expect dependency surgery. Copy the algorithms, not the code. |
| **oguzhan-yilmaz/pyCrossfade** https://github.com/oguzhan-yilmaz/pyCrossfade | Python, MIT, 150 stars | 2026-08-09 (v0.4.0) | Bar-level beat matching of the last K bars of A and first K bars of B, **gradual tempo ramp** over N downbeats, 3-band EQ (low/high shelves out on master, in on slave, mid dip at centre), fade curves linear/cosine/equal-power, returns a typed `Transition` with slices and times, click-protected seams. Uses madmom (45-150 s/track, cached) and Essentia (BPM, replaygain, key). | Author recommends Docker because "dependencies were updated and broke the old code". Best single file to crib the transition maths from. |
| **LaRambla20/songs-automixer_python** https://github.com/LaRambla20/songs-automixer_python | Python 3.9+, MIT (code), Textual TUI | 2026-10-19 | Live auto-mixer: BPM/key cache, accepts half/double-time pairs unstretched, otherwise stretches with the rubberband CLI during the fade then ramps back over 30 s, snaps cues to bars, HPF/LPF/gate master FX, **backspin** (stops A, plays a rewind SFX, starts B at its cue). | Yes (needs `brew install rubberband`). Playback-oriented, not a file renderer. |
| **StanAngular/autodj-mixer** https://github.com/StanAngular/autodj-mixer | Python (uv), MIT, 0 stars | 2026-10-23 | All-in-one (fork "A1F") structure + Demucs vocal zones + madmom beats; Camelot gating (incompatible keys get longer fades + notch); bar-by-bar warp; LR4 crossover; 20-60 s transitions; renders 24-bit WAV + 320k MP3; ACE-Step for generated bridges. | Brand new and unreviewed; the design matches this report's recommendations, worth reading. |
| **robaerd/mosaikbox** https://github.com/robaerd/mosaikbox | Python 3.11, FastAPI, no licence file | 2025-06-27 | Research code behind the ISMIR 2024 paper (B.4): BeatNet + annealed grid, stem separation, rule-based stem removal, mixability scoring. Hard-codes `mps`. | Needs Docker (KeyFinder, MongoDB) and a Genius key; no licence = cannot legally reuse code, but the paper is CC BY. |
| **kckDeepak/AI-DJ-Mixing-System** https://github.com/kckDeepak/AI-DJ-Mixing-System | Python 3.8+, MIT, 54 stars | 2026-02-03 | GPT-4o chooses songs/transition points from a prompt; librosa beats/energy/phrases; echo transition, 32-step tempo ramp, LP/HP EQ, 8-bar snapping; outputs MP3 + JSON plan. | Uses pydub (breaks on 3.13+) and OpenAI API. Interesting for the "mix plan JSON" shape. |
| **ChenPaulYu/DJtransGAN** (+ `-dg-pipeline`) | Python, MIT | 2025-11-07 | Learned fader/EQ transition renderer with pretrained weights (B.5). | 2021-era torch pins; unverified. |
| **mir-aidj/djmix-analysis**, **transition-analysis** | Python 3.8, no licence | 2020 / 2021 | Analysis of real mixes (B.3). | madmom 0.16.1 pins; read-only. |
| **ETH-DISCO/cue-detr** | Python 3.11.9, MIT | 2024-08-19 | Cue-point model + 21k-cue dataset (A.3). | Probably runs with pinned requirements. |
| **MZehren/Automix** | Python (2/3 mix), MIT | 2020-02-11 | Rule-based cue-in detection (B.6). | No. |
| **dodiku/MixingBear** https://github.com/dodiku/MixingBear | Python 3.6, MIT, 131 stars | 2018-04-26 | Two-file beat-mixing on top of AudioOwl. | No (dead). |
| **cameronbracken/mix-machine** | Python (EchoNest remix) | old | Historical. | No (EchoNest API gone). |
| **mixxxdj/mixxx** AutoDJ (C++, GPL-2.0) | - | active | Only intro/outro-section-based fade timing (A.7); no scoring, no tempo sync in AutoDJ. | n/a |
| "dj-mix-generator", "pyautodj", "DJ-Mix-Generation", "mixcraft" | - | - | **Not found** as real projects (Mixcraft is Acoustica's commercial DAW; "Unmixer" is Smith/Kawasaki/Goto's ISMIR 2019 loop-extraction web service https://zenodo.org/record/3527938, closed source). | - |

**[opinion]** Nothing here is a drop-in. The right move is a small purpose-built toolkit that reuses: Beat This + madmom (beats/downbeats), Essentia (key, rhythm cross-check, voice/instrumental, EffNet embeddings), Demucs/demucs-mlx (vocal stems when needed), pedalboard (stretch, FX, limiter), pyloudnorm, soundfile/ffmpeg; and copies the *rules* from Vande Veire & De Bie, Mosaikbox and pyCrossfade.

---

## E. Recommended pipeline for this Mac

### E.1 Environment (all commands verified on this machine unless noted)

```bash
# system tools (ffmpeg 8.1.1, aubio, python@3.14, python@3.15 already present)
brew install rubberband libkeyfinder sox        # optional: rubberband CLI, KeyFinder lib, sox
# keyfinder-cli is not in Homebrew: git clone https://github.com/evanpurkhiser/keyfinder-cli && cmake ... (optional)

/opt/homebrew/bin/python3.14 -m venv ~/mixer-venv && source ~/mixer-venv/bin/activate
pip install -U pip setuptools wheel cython "numpy<3"
pip install --no-build-isolation "git+https://github.com/CPJKU/madmom"      # 0.17.dev0, builds in ~1 min
pip install torch torchaudio soxr einops tqdm rotary-embedding-torch beat-this
pip install librosa soundfile pedalboard pyloudnorm pyrubberband scipy
pip install essentia-tensorflow            # NOT `essentia` as well: the second install wins and drops the TF algorithms
pip install demucs                         # 4.1.0; or: pip install demucs-mlx (Apple MLX port, untested here)
# optional, untested: pip install all-in-one-infer   (structure labels; pure-PyTorch fork of allin1)
# optional, untested: pip install "audio-separator[cpu]"  (BS-Roformer vocals; MPS/CoreML)
```
Everything above (except the two optional lines) was installed in `scratchpad/mixer/venv314` and import-tested: `torch 2.14.1 (mps available: True)`, `librosa 1.0.0`, `soundfile 0.14.0`, `pedalboard 0.9.26`, `pyloudnorm 0.2.0`, `pyrubberband 0.4.0`, `beat_this 1.1.0`, `essentia 2.1-beta6-dev`, `madmom 0.17.dev0`, `soxr 1.1.0`, `demucs 4.1.0`.

Things that will **not** work: Python 3.15 for anything torch-based (no wheel yet); `pip install madmom` from PyPI; `pip install essentia` on top of `essentia-tensorflow`; `torchaudio.load` without `torchcodec`; `pydub` on 3.13+; `natten` from PyPI (sdist only, long compile) - prefer `all-in-one-infer`; `aubio` Python package (2019, no arm64 wheels; the brew CLI is fine).

### E.2 Stage 1: per-track analysis -> `features/<id>.json` (run once, cache forever)
Decode once with `soundfile.read(mp3, dtype="float32")` (zero offset vs ffmpeg on the test file) and pass the **same array** to every analyser; also write a 44.1 kHz WAV to a cache dir for the CLI tools (Beat This's `File2Beats`, Demucs). Per track store:

```json
{
 "id": "...", "path": "...", "sr": 44100, "duration_s": 181.58,
 "bpm_tag": 125.0, "bpm_beatthis": 125.0, "bpm_essentia": 126.9, "bpm": 125.0, "bpm_agree": true,
 "grid": {"bpm": 125.0, "first_downbeat_s": 0.04, "bar_s": 1.92, "fit_mad_ms": 9.1, "confidence": 0.93},
 "beats_s": [...], "downbeats_s": [...],
 "phrase": {"lattice_phase_bar": 1, "phrase_len_bars": 8, "confidence": 0.8},
 "boundaries_bars": [1, 9, 25, 41, ...], "sections": [{"start_bar":1,"end_bar":9,"label":"intro","energy":"low"}, ...],
 "first_sound_s": 0.0, "last_sound_s": 180.9,
 "mix_in": {"start_bar": 1, "end_bar": 17, "vocal_free_bars": 16},
 "mix_out": {"start_bar": 81, "end_bar": 95, "vocal_free_bars": 8},
 "key": {"essentia_edma": ["D","minor",0.88], "keyfinder": "7A", "camelot": "7A", "confidence": 0.85},
 "loudness": {"integrated_lufs": -8.2, "lra": 5.1, "true_peak_db": -0.1},
 "per_bar": {"lufs_st": [...], "low_db": [...], "high_db": [...], "onset_density": [...], "vocal_prob": [...]},
 "onset_pattern_16": [...],          // beat-synchronous onset strength, 2 bars x 8 sub-beats, averaged over the track
 "embedding_effnet": [... 1280 floats ...],
 "flags": ["half_time_candidate", "vocal_heavy"]
}
```

Steps and measured costs (M-series Mac, this session, 181 s track):
1. Beats/downbeats: **Beat This on MPS ~1.3 s** (0.8 s inference + 0.5 s model load; 2.4 s on CPU) -> optional **madmom DBN 13.5 s** as a second opinion; constant-grid fit (Mosaikbox) in numpy; `bpm_agree` when |tag - tracker| < 1% (after x0.5 / x2 normalisation).
2. Tempo cross-check: Essentia `RhythmExtractor2013` **1.9 s**; `librosa.beat.beat_track` 8.5 s (skip it).
3. Key: Essentia `KeyExtractor(profileType="edma")` and `"bgate"` (<1 s each) + madmom `CNNKeyRecognitionProcessor` or `keyfinder-cli -n camelot` as the second detector.
4. Structure: Foote novelty (own, seconds) or librosa Laplacian; optionally `all-in-one-infer` for labels (minutes per track, unverified).
5. Loudness curves: pyloudnorm integrated + own K-weighted 400 ms blocks; per-bar low/high band energy from an LR4 split.
6. Vocal probability per patch: Essentia `voice_instrumental-discogs-effnet-1` on 16 kHz audio (see E.5 for the measured cost); upgrade to **Demucs `--two-stems vocals` on MPS: 17.7 s wall per track** (CPU: 53.8 s) when you want a real vocal stem (also reusable for "drums-only" transition tricks).
7. Embedding: reuse the Discogs-EffNet embeddings from step 6 (mean-pool).

**Total for 200 tracks**: about 200 x (1.5 beats + 2 tempo check + 2 key + 5 structure + 3 loudness + 1 vocal/embedding + 1 decode) s = ~15 s/track = **~50 min** without Demucs or madmom; add ~45 min if madmom is run on every track as a second opinion; add ~1 h with Demucs on MPS (or ~20 min with demucs-mlx if its 30x-realtime claim holds); add 3-6 h if you also run all-in-one on every track **[estimate]**. Run it as a resumable batch (skip when the JSON exists).

### E.3 Stage 2: pairwise scoring -> `pairs.json`
Pure numpy over the cached features (B.10). 39,800 directed pairs, well under a second. Output per pair: `score`, the seven sub-scores, `stretch_pct`, `multiplier`, `suggested_transition` (see E.4), `reasons[]`. The phone page only needs `{a, b, score, reasons}` for pairs above the threshold (and a symmetric `max(score_ab, score_ba)` if you want undirected lines).

### E.4 Stage 3: mix plan -> `plan.json`
Given the chosen order, for each consecutive pair pick a transition type with simple rules **[opinion]**:
* `stretch <= 6%` and `vocal overlap < 0.2` and both windows >= 16 bars -> **32-bar (or 16-bar) bass-swap blend** (incoming bass cut until the swap bar at the midpoint; highs swap one bar later; outgoing mids dip if timbre differs).
* compatible tempo but vocals clash -> **8-bar quick blend with echo-out** (A's last vocal phrase echoes into B's instrumental intro) or **filter-sweep exit**.
* `6% < stretch <= 10%` -> blend but **ramp** B's tempo across the overlap (time-varying `stretch_factor` array in `pedalboard.time_stretch`) and ramp A the other way, so neither track is stretched more than ~5% at any instant (pyCrossfade's trick).
* `stretch > 10%` or half/double time that does not groove -> **no beat-matching**: vinyl brake / backspin on A's last downbeat, optional riser over A's last 4-8 bars, B starts cold on its downbeat (with a sampled or synthesised scratch/impact on the cut) - the classic hip-hop <-> house change-up.
* Halloween novelty tracks: treat them like the above (cut-ins with an SFX) unless the scorer says they blend.
Record every decision with bar numbers so the plan is editable by hand before rendering.

### E.5 Stage 4: renderer
1. For each track load float32, normalise to **-14 LUFS**, trim to first/last sound (-60 dBFS).
2. For each transition, stretch the incoming track with `pedalboard.time_stretch` (constant or ramped), recompute its grid, align downbeat to downbeat at sample precision, build per-band gain envelopes (bar-quantised), LR4-split, apply, sum into the output stream.
3. Non-blend transitions: brake/backspin via `np.interp` varispeed (C.6), SFX from the CC0 library aligned to the downbeat, optional scratch synthesis (C.7).
4. Write the running mix with `soundfile.SoundFile` in blocks; at the end run `BrickwallLimiter(ceiling_db=-1, true_peak=True)`, re-measure LUFS with pyloudnorm, encode MP3 320k with ffmpeg, emit a cue sheet/chapters.
Rendering cost is dominated by stretching: Rubber Band R3 at ~18x realtime on this machine (30 s in 1.7 s) -> a 3-hour set with ~40 stretched overlaps of 1 minute each is a few minutes; the rest is numpy.

Measured in this session (test track, Python 3.14 venv):
* Beat This: MPS 0.8 s inference + 0.5 s load (first-ever run 5.6 s incl. checkpoint download); CPU 2.4 s + 0.3 s. madmom downbeats CPU: 13.5 s. Essentia key x3 + RhythmExtractor: ~3 s. librosa beat_track: 8.5 s. pedalboard time_stretch 30 s @1.05: 1.7 s. Demucs htdemucs two-stems: MPS 17.7 s wall, CPU 53.8 s wall. Essentia voice/instrumental (Discogs-EffNet + head): **1.0 s for the whole 181 s track** (181 patches at ~1 s hop, embeddings shaped [181, 1280]); the voice-probability timeline correctly shows the first ~6 s as instrumental (p = 0.05) before the vocal enters (p = 0.75-0.97), mean 0.84 for this vocal house track.
* Downbeat agreement Beat This vs madmom on the test track: first four downbeats 0.04/1.92/3.80/5.70 s vs 0.02/1.91/3.80/5.69 s.

### E.6 Top pitfalls (ordered by how likely they are to bite)
1. **Python/wheel matrix**: use 3.14; torch has no 3.15 wheel; the newest Essentia wheel is cp314-only, the cp313 one is a year older; `audio-separator` excludes 3.14.1 exactly (3.14.5 is installed, fine).
2. **madmom**: PyPI release is dead; install from git with `setuptools`+`cython` and `--no-build-isolation` (without `setuptools` in the venv the build fails with "Cannot import setuptools.build_meta" - reproduced). Models are CC BY-NC-SA.
3. **Essentia packaging**: `essentia` and `essentia-tensorflow` are the same module; install only the latter (reproduced the silent breakage).
4. **Decoder offsets**: zero on the tested LAME-encoded file across soundfile/librosa/madmom/ffmpeg, but allin1 documents 20-40 ms differences on other decoders/files - decode once, cache the WAV, analyse and render from the same samples; never mix "beats from decoder X" with "audio from decoder Y".
5. **Half-time hip-hop / double-time**: trackers and tags disagree by x2 (and occasionally x3/2); normalise with the multiplier set in B.10, and sanity-check with the onset-density of beats 1/3 vs 2/4 (snare on 2 and 4 in pop). Downbeat trackers also like to land on beat 3 of the bar in sparse intros; compare the 8-bar lattice energy to pick the phase.
6. **Key detection on vocal pop** is 60-80% at best; never hard-filter on key, use two detectors and confidence weighting; consider pitch-shifting by one semitone (Vande Veire) only with `preserve_formants=True` and only on instrumental sections.
7. **Stretch artefacts**: cap at 8% (Mosaikbox), prefer <= 5% per track by splitting the difference and ramping; use R3 (`high_quality=True`), `transient_mode="crisp"` for drums-heavy, `"smooth"` for vocal/pad material; never stretch the whole track when only the overlap needs it.
8. **Clipping/headroom**: the pool is mastered around -8 LUFS; two such tracks summed will clip. Normalise to -14 LUFS first, sum in float, limit once at the end with a true-peak limiter (`BrickwallLimiter`, not `Limiter`).
9. **Phrase errors are worse than beat errors**: a 4-bar lattice error makes a "correct" blend feel wrong. Store lattice confidence, prefer 16-bar multiples from a strong boundary (CUE-DETR: 16 bars is the mode in pro cue libraries), and let the plan be hand-edited.
10. **Intros/outros that are not usable**: cold vocal starts, long reverbs, fade-outs (90s pop!). Compute `vocal_free_bars` and `last_sound - fade` explicitly; for a fade-out outro, mix out at the last chorus boundary instead and let an echo-out carry it.
11. **Homebrew ffmpeg has no `rubberband` filter**; `atempo` is the only built-in stretcher there.
12. **Long-array memory**: 3 h x 44.1 kHz x 2 ch x float32 = 1.9 GB; stream to disk per transition instead of holding the whole set.
13. **Licensing of models/SFX**: madmom + Essentia models CC BY-NC-SA (fine for a private party mix), MERT CC-BY-NC, BeatNet CC-BY-4.0, pedalboard/Rubber Band GPL (fine for scripts); check each Freesound file's licence (CC0 filter is per file, some packs mix licences).
14. **Tag BPMs** are often rounded or doubled; trust the grid fit, write the corrected BPM back to the JSON, not to the file.

### E.7 What I did not verify
* all-in-one / all-in-one-infer install and runtime on this Mac; CUE-DETR; DJtransGAN; demucs-mlx; audio-separator; laion-clap; pyrubberband (needs `brew install rubberband`); sox.
* Whether `pedalboard.time_stretch(high_quality=True)` maps to Rubber Band R3.
* Essentia model licence (believed CC BY-NC-SA 4.0).
* Serato/Traktor cue logic; rekordbox vocal detection internals.


---

## F. Local verification artefacts (scratchpad, this session)

* Venv: `scratchpad/mixer/venv314` (Python 3.14.5, numpy 2.5.4) with the full E.1 stack installed, including madmom 0.17.dev0 from git, essentia-tensorflow dev1438, beat-this 1.1.0, demucs 4.1.0.
* Scripts: `scratchpad/mixer/smoke.sh` (install + import test), `test_analysis.py` (Beat This CPU/MPS, Essentia key x3 + RhythmExtractor2013, librosa beat_track, pyloudnorm, pedalboard time_stretch, madmom downbeats), `test_vocal.py` (Discogs-EffNet + voice_instrumental head), `demucs_test.sh` (MPS vs CPU two-stem timing), plus the MP3-decoder-offset check run inline.
* Models: `scratchpad/mixer/models/discogs-effnet-bs64-1.pb`, `voice_instrumental-discogs-effnet-1.pb` (from https://essentia.upf.edu/models/).
* Papers extracted to text: `scratchpad/mixer/pdfs/{vandeveire,mosaikbox,cuedetr}.pdf(.txt)`.
* Test audio: `scratchpad/mixer/testaudio/sample.{mp3,wav}` (copy of one pool track) and Demucs stems in `scratchpad/mixer/sep/`.

Nothing was installed system-wide; no Homebrew formulae were added.
