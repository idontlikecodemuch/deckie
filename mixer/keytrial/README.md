# The own-key trial (research X2)

A bench and a set of experiments asking whether a key reader Deckie owns can be good enough to show. The letter is
`docs/research/x2-own-key-trial.md`; the running notes are `docs/research/briefs/checkin-key.md`.

**Evaluation only.** Nothing trained here ships, and no weights, audio or data set are in the repository. The data
sets are third-party (their labels CC BY-SA 4.0 or unlicensed, their audio Beatport's and the labels'). They are read
by path from a folder outside the repository.

## Data (fetched Nov 13, 2026; none committed)

| Set | Source | What | Size | Licence |
|---|---|---|---|---|
| GiantSteps-MTG-key | Zenodo record 1101082, `audio.zip`, `Beatport-EDM-Key-Dataset.xlsx` | 1,486 two-minute Beatport clips; 1,275 with a plain major or minor label | 2.13 GB (MD5 f490ee6c23578482d6fcfa11b82636a1) | labels CC BY-SA 4.0; audio Beatport's and the labels' |
| GiantSteps+ | Zenodo record 1095691, `audio.zip`, `GiantSteps+.xlsx` | 600 clips, the revised labels of the 604; 468 single-key, 230 plain | 856 MB | labels CC BY-SA 4.0; audio Beatport's and the labels' |
| GiantSteps Key | `github.com/GiantSteps/giantsteps-key-dataset` (labels, checksums); audio from `www.cp.jku.at/datasets/giantsteps/backup/` | 604 clips, original labels | 834 MB, all 604 checksums matched | none stated; audio Beatport's and the labels' |

GiantSteps+ and GiantSteps Key are the same recordings with different labels; no clip is shared with the MTG set, and
36 artist or remixer names are (39 MTG clips, left out of training whenever a model is scored on the other sets).
The data set's own download script was read, not run.

```bash
export DECKIE_KT_DATA=/path/outside/the/repo/data      # mtg/audio, mtg/Beatport-EDM-Key-Dataset.xlsx, gsplus/GiantSteps+.xlsx, gs/audio, gs/repo
export DECKIE_KT_CACHE=/path/outside/the/repo/cache    # about 2 GB of features
```

## Python

```bash
python3 -m venv venv
venv/bin/pip install numpy scipy soundfile librosa soxr scikit-learn onnx onnxruntime
venv/bin/pip install torch --index-url https://download.pytorch.org/whl/cpu
```

## Commands, in order (run from this folder)

```bash
venv/bin/python kt_extract.py --jobs 4      # one decode per clip: peaks, note transcription, log-frequency spectrogram (about 15 minutes on 4 cores)
```

```bash
venv/bin/python kt_bench.py                 # phase 1: letter R's three readers re-run and checked against its sheets; folds; bench_readers.tsv
```

```bash
venv/bin/python kt_modefeats.py             # phase 2: per-clip measurements for the mode rules
```

```bash
OMP_NUM_THREADS=1 venv/bin/python kt_mode.py   # phase 2: every mode rule, true home note and the readers'; mode_results.tsv, mode_clips.tsv
```

```bash
venv/bin/python kt_cnn.py cv --threads 3    # phase 3: the small convolutional model, five artist-grouped folds (about 25 minutes a fold, CPU)
```

```bash
venv/bin/python kt_cnn.py cross --threads 3 # phase 3: train on MTG, score both GiantSteps sets; train on GiantSteps Key, score MTG
```

```bash
venv/bin/python kt_cnn.py sections          # the model's answer on each third of a clip (a confidence signal)
```

```bash
venv/bin/python kt_cnn.py cost              # parameters, file size, CPU time for a five-minute song
```

```bash
OMP_NUM_THREADS=1 venv/bin/python kt_x.py   # every reader on every set, four measures, trade-off curve, open mode; x_results.tsv, x_clips_*.tsv
```

```bash
OMP_NUM_THREADS=1 venv/bin/python kt_pc.py  # precision against coverage, confidence signals, calibration; pc_curves.tsv
```

```bash
OMP_NUM_THREADS=1 venv/bin/python kt_curve.py   # phase 4: learned profiles against the number of labelled songs; curve_results.tsv
```

## The three-answer reader's reference and parity (D33)

```bash
venv/bin/python kt_three.py expected --jobs 4   # the Python reference on every clip -> three_answer_expected.tsv (about 16 minutes)
```

```bash
venv/bin/python kt_three.py parity ../../core/.build/release/deckie-keyparity   # the Swift reader on the same samples (about 25 minutes)
```

```bash
venv/bin/python kt_three.py fixture ../../core/Tests/DeckieCoreTests/Fixtures/three_answer.json   # the generated fixture of the Swift test
```

## Training on data that could ship (research X3)

More data, fetched Nov 14, 2026, for evaluation only, none committed. Only the files used were pulled, by HTTP range
requests into the archives (`kt_remote_zip.py`):

| Set | Source | Used | Licence |
|---|---|---|---|
| Freesound Loop Dataset | Zenodo 3967852 (`annotations.zip`, and `metadata.json` and 711 wav files out of `FSL10K.zip`) | 711 loops whose annotators agree on a key and mode | each loop's own: CC0 1.0 (380) or CC BY 3.0 (331); loops under other licences are not used |
| FMAK | Zenodo 10719860 (`fma_keys_metadata.csv`, and 373 mp3 files out of its ten zips), joined with `tracks.csv` of the Free Music Archive's `fma_metadata.zip` | 373 songs | labels CC BY 4.0; each song's own: CC BY (347), CC0 or public domain (26) |
| Open Well-Tempered Clavier, Book 1 | archive.org item `bach-well-tempered-clavier-book-1` (48 mp3 files) | 48 recordings, the key from each title | CC0 |
| Bach chorales (scores) | the music21 corpus (`pip install music21`) | 412 chorales, rendered by `kt_scores.py` | compositions public domain; the encodings' terms are the corpus's |

Layout under `$DECKIE_KT_DATA`: `fsl/annotations.zip`, `fsl/metadata.json`, `fsl/audio/<freesound id>.wav`;
`fmak/usable.json` (track id to label, licence, artist, genre), `fmak/audio/<track id>.mp3`; `wtc/tracks.json`,
`wtc/audio/<nn>.mp3`.

```bash
venv/bin/python kt_made.py --n 1500 --jobs 4     # program-written dance clips to a chosen key (features only)
```

```bash
venv/bin/python kt_scores.py --jobs 2            # public-domain chorales rendered with our synthesiser voices (features only)
```

```bash
venv/bin/python kt_ship.py feats --jobs 4        # features of the real, shippable audio
```

```bash
OMP_NUM_THREADS=1 venv/bin/python kt_ship.py profiles   # learned profiles on every source and mix -> ship_results.tsv
```

```bash
venv/bin/python kt_ship.py cnn --threads 4       # the small convolutional model on three mixes (about 20 minutes each)
```

```bash
OMP_NUM_THREADS=1 venv/bin/python kt_ship.py report     # the model's tables
```

## Research X4: without labelling, and the reader that can ship

More data, fetched Nov 14, 2026, for evaluation only, none committed: the thirty-second clips of the 8,352 Free
Music Archive tracks whose own licence is CC BY, CC0 or public domain (`tracks.csv` of `fma_metadata.zip`; tracks
marked "Public Domain / Sound Recording Common Law Protection" left out), read one by one out of `fma_large.zip`
(`https://os.unil.cloud.switch.ch/fma/`; `kt_remote_zip.py`, 7.9 GB) into `$DECKIE_KT_DATA/fma/audio/<track id>.mp3`
with `$DECKIE_KT_DATA/fma/usable.json` (track id to licence, artist, top-level genres).

```bash
venv/bin/python kt_x4.py feats --jobs 4                       # the untrained reader and the spectrogram, per clip
OMP_NUM_THREADS=1 venv/bin/python kt_x4.py pseudo             # pseudo-labels, THE LEAN -> x4_lean.json, profiles
venv/bin/python kt_x4.py cnn ssl --threads 4                  # pretrained with no labels, then the human labels
venv/bin/python kt_x4.py cnn mix --threads 4                  # human labels + 2,000 pseudo-labels (the one chosen)
venv/bin/python kt_x4.py cnn pseudo --threads 4               # pseudo-labels only
OMP_NUM_THREADS=1 venv/bin/python kt_x4.py report             # -> x4_results.md
OMP_NUM_THREADS=1 venv/bin/python kt_x4.py ship               # readers as three-answer readers -> x4_ship_results.md
OMP_NUM_THREADS=1 venv/bin/python kt_x4.py export mix         # as shipped -> x4_shipped_results.md, core/.models/deckie-key.f16
OMP_NUM_THREADS=1 venv/bin/python kt_x4.py record mix         # every training recording, its page and licence (not committed)
OMP_NUM_THREADS=1 venv/bin/python kt_x4.py fixture            # the Swift test's fixture, for a model of made-up numbers
venv/bin/python kt_x4.py parity mix "<path>/deckie-keyparity --learned <path>/deckie-key.f16"   # Swift against this file
```

The rules fixed before scoring (the lean, the candidate, the thresholds, what "beats" means) are written at the
top of `kt_x4.py` and above `main_ship`. `core/.models/deckie-key.f16` and the list `record` writes are not in the
repository: no trained numbers are committed, and the list names people.

## Files

| File | What |
|---|---|
| `kt.py` | data sets by path, labels, artist-grouped folds, the scorer, sign test and intervals |
| `kt_extract.py` | features (cached outside the repository) |
| `kt_bench.py` | the bench: letter R's readers 3f, A and B, unchanged, from `../key_parity.py` and `../key_overtones.py` |
| `kt_modefeats.py`, `kt_mode.py` | the mode alone |
| `kt_prof.py`, `kt_curve.py` | learned key profiles: the smallest trained reader (25 to 169 numbers), and its learning curve |
| `kt_cnn.py` | the small convolutional model |
| `kt_x.py`, `kt_pc.py` | the scoring tables |
| `kt_three.py` | the three-answer reader's Python reference, its parity run against the Swift port, and the test fixture |
| `kt_ship.py`, `kt_made.py`, `kt_scores.py`, `kt_remote_zip.py` | research X3: readers trained only on data that could ship |
| `kt_x4.py` | research X4: pseudo-labels, no-label pretraining, the lean, the reader as shipped, its export, record, fixture and parity |
| `*.tsv` | per-clip keys and per-reader scores (clip ids and keys only; no audio, no artist names) |

## Protocol

- **Folds.** Five, grouped by artist and named remixer (clips sharing any name fall in one group; 1,269 groups on MTG),
  balanced for major and minor. A clip's fold depends only on the data set's spreadsheet.
- **Untrained rules** have no fitted value. Where one is picked among several it is picked on folds 0 to 2 and
  reported on folds 3 and 4.
- **Trained rules** are fitted on four folds and scored on the fifth; across sets they are fitted on one set and
  scored on another. Every trained row is marked EVALUATION ONLY.
- **Scores.** Exact key; home note (exact or the parallel key); mode given the right home note; within one step on
  the Camelot wheel (exact, relative, or a fifth either way); and, when a reader may decline, the share of clips shown
  a key and how often a shown key is right.
