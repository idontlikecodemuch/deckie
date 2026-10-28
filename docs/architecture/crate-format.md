# The crate file, format version 1

Dated Oct 28, 2026; step 4 of the PC and Linux track (`pc-linux-track.md`). The crate is the one file Deckie writes:
a DJ's tracks with their analysis, names and history, never audio, moved between devices by iCloud Drive, AirDrop or
Files. This page says what the documents already fix, what they leave open, and the choice made here for each open
point. Every choice not taken from a document is marked **proposed**, for the main session to accept or change.
The main session accepted the format as v1 on Oct 28 with two changes, both applied below: the Windows and Linux
engine's family is `deckie`, and a shipped engine makes a record's `id` from the SHA-256 hash of the file, kept whole
in the new `file.sha256`.
Code: `core/Sources/DeckieCrate` (reader, writer, checks), `core/Sources/DeckieLab/FeatureFile+Crate.swift` (the lab's
feature files to crate records). Example: `core/fixtures/example.deckiecrate`.

## What the documents fix

- **Container** (spec 5.2, "decided with D11"; track A section 5; overview): a package folder `<name>.deckiecrate`
  (a folder that Finder, Files and AirDrop treat as one document) holding `manifest.json`, `crate.json` (one record
  per track), binary sidecars (small companion files) for the per-bar series and the style vector, `prefs.json`,
  append-only history logs per device, an optional `signatures/` store and a local-only `catalog/`.
- **Encoding**: JSON for the manifest and the records; float16 (2-byte numbers, about three significant digits) for
  the per-bar series and the style vector (track A).
- **Versioning** (track A, spec 5.2): an integer `schema` in the manifest and in each record; readers ignore keys
  they do not know and refuse a crate only when its `min_reader` is above their own version.
- **The record** (track A section 5, port plan section 4): `id`, `file`, `ident`, `analysis` (`engine` as a text
  label, `analysed_at`, `device`, `secs`, and the port plan's `level`: 1 full, 2 fallback, 3 none), `grid`, `key`
  (with `votes` and key `changes`), `phrase`, `sections`, `mix_in`, `mix_out`, `ends`, `loudness`, `vocal`,
  `onset_pattern_16`, `flags`, `signatures`. Bars are 1-based with an exclusive end bar, as in the lab. Left out on
  purpose: raw beat arrays, the 1280-value embedding, novelty peaks, grid candidates, the lab's timings and paths.
- **Tempo and key as segments** (spec 5.2, D13, P12): a tempo segment is the industry's grid marker (start time,
  BPM, meter, beat of the bar); key segments are Deckie's own.
- **Engine-agnostic additions** (track L section 5, to be in crate v1): a structured engine record (`family`,
  `version`, `platform`, `models[]` with name, version and weights hash, `decoder`), a `fidelity` integer per engine
  build earned on the benchmark (replacing "newer engine wins"), a `source` and a confidence per block, values on
  agreed scales, and `features_present[]` so a reader never infers a feature from the level.
- **Constraints** (D3, charter): no audio; no absolute paths; recognition signatures come from an Apple device, and
  a crate built elsewhere leaves a place for them. Merging (track A): records by newest `analysed_at`, prefs by
  `updated_at`, history files unioned.
- **Shared code** (D14, track L's "option chosen"): Swift everywhere, so `DeckieCrate` is the one reader and writer
  for the Apple apps and the Windows and Linux builder.

## What is open

Field-level detail track A leaves out (the sidecar header, how a reader knows which series a sidecar holds, the
shape of a signature entry, number precision, key order), where the track L additions sit in the record, the meaning
of `fidelity` values, what "agreed scale" means before the vocal listening set exists, and how the lab's files map
in. Not decided here and not built: `prefs.json`, the history logs, the merge itself and the port plan's `waves/`
sidecar (the apps own them; the reader leaves them alone).

## The package folder

```
Example.deckiecrate/
  manifest.json                            the crate as a whole
  crate.json                               {"tracks": [one record per track, sorted by id]}
  bars/<id>.bin                            per-bar series, float16
  style/<id>.bin                           style vector, float16
  signatures/<id>_<variant>.shazamsignature   made on an Apple device; never written by this track
  prefs.json, history/, catalog/, ...      the apps' own; read and written by them only
```

**`manifest.json`**: `schema` (1), `min_reader` (1), `crate_id` (text, made once when the crate is created),
`name`, `created_at` (UTC, to the second, as `2026-10-26T00:00:00Z`), `devices_seen` (device labels), and
`engines_used` (the tracks' `analysis.engine` labels, sorted; written for a quick look, recomputed by readers).

## The track record (`crate.json`)

Numbers carry their unit in the name (`_s` seconds, `_ms`, `_db`, `_lufs`, `bpm`); `lra` is in LU. Every field below
is written in every record; `null` means "no value" and is allowed only where marked "or null". A block marked
*(feature X)* is present exactly when `features_present` lists X, and is `null` otherwise.

- `id`: letters, digits, `-` and `_` only, as it names the sidecar files. **How a shipped engine makes it**
  (main session, Oct 28): the first 16 hexadecimal characters, lower case, of the SHA-256 hash of the audio file's
  bytes, the whole file as it is on disk, tags included; the full hash is `file.sha256`. 16 characters are 64 bits:
  the chance that any two files of a 100,000-track crate share an id is about one in 3.7 billion. The id names the
  file, not the recording: two files with the same audio but different bytes (another encode, a copy retagged by
  another program) are different files with different ids, and finding them as one recording is the analysis-derived
  version descriptor's job (spec 5.4), not the id's. Lab records keep the lab's 10-character ids and write
  `file.sha256` as null. `CrateIDs.id(forFileBytes:)` and `CrateIDs.sha256(of:)` compute both, on SHA-256 written in
  Swift (`SHA256.swift`), so no system library is needed.
- `schema`: 1. `features_present`: sorted names, from `grid`, `tempo_segments`, `key`, `key_changes`, `phrase`,
  `sections`, `mix_windows`, `ends`, `loudness`, `vocal`, `onset_pattern`, `style` and `bars.<series>`. Readers ignore
  names they do not know, but keep a per-bar series they do not know. **proposed** (the names).
- `file`: `name`, `rel` (path below the folder the crate was built from, or null; never absolute), `bytes` or null,
  `sha1_head` or null, `sha256` or null, `duration_s`. `sha256` is the whole file's SHA-256 hash as 64 lower-case
  hexadecimal characters, the spec's "content hash of the file for exact identity" (spec 5.4); the record's `id` is
  its start, as above, and it is null only in lab records. `sha1_head` is track A's head hash: a SHA-1 of the start
  of the file, which the Apple apps keep for a quick identity check. Track A section 5 defines it only by its rule,
  "Store a relative path plus size and a head hash to re-find files", and its example record, which shows
  `"sha1_head": "..."`; track B refers to it as the content hash "in Track A's crate file as a head hash". Neither
  document says how many bytes of the head it covers or how the hash is written, and no code computes it yet, so this
  format does not define it further: every record this track writes has it null, and the reader does not check it.
- `ident`: `title`, and each or null: `artist`, `version`, `source`, `mbid`, `disc`, `folder`, `track`, `cut_key`,
  `is_longest`, `era`, `kind`; plus `tags` (list). **proposed**: `tags` (the lab's Halloween mark becomes the tag
  `halloween`, as the port plan suggests), and `folder` and `era` as text, as the lab has them (track A showed numbers).
- `analysis`: `engine` (label), `analysed_at`, `device` (a model label such as `Mac15,6`, never a user's device
  name), `secs` or null, `level`.
- `engine` **proposed** (where track L's record sits: a block beside `analysis`, which keeps its text label):
  `family` (`apple-mu` for the Apple apps' engine, `deckie` for the Windows and Linux engine, `lab`; decided by the
  main session: a family names an engine and must not claim a licence, and while the Windows and Linux engine's models
  are open source, the engine is not; track L wrote `deckie-core`, which now names the code both engines share),
  `version`, `platform` (`macos-arm64`, `linux-x86_64`, `windows-x86_64`),
  `fidelity`, `models` (each `name`, `version` or null, `weights_sha256` or null), `decoder` (`name`, `version` or
  null) or null. **proposed**: `fidelity` 0 means not benchmarked; n means the build passed benchmark tier n, tier 1
  being the stage 1 pass marks. A device with the audio re-analyses a record when its own fidelity is higher, or the
  record's level is a fallback the device can better.
- `grid` *(grid)*: `source`, `confidence` (0 to 1), `bpm`, `first_downbeat_s` (the start of bar 1), `n_bars` (whole
  bars from bar 1 to the end), `fit_mad_ms` or null, `bpm_in`, `bpm_out`, `in_trusted`, `out_trusted`.
- `tempo_segments` *(tempo_segments)* **proposed** (spec 5.2's grid marker): a list of `start_bar`, `start_s`, `bpm`,
  `beats_per_bar`, `beat_in_bar` (1 when the segment starts on a downbeat, as rekordbox's `Battito`), `confidence`
  or null. One segment for a steady track.
- `key` *(key)*: `source`, `confidence`, `camelot`, `key` or null, `scale` or null, `votes` (source name to Camelot
  code), `changes` *(key_changes)*: a list of `start_bar`, `end_bar`, `camelot`, or null. **proposed**: objects
  rather than track A's three-element lists.
- `phrase` *(phrase)*: `source`, `confidence`, `lattice_phase_bar` (1 to 8), `boundaries_bars`. Its `source` is track
  L's `structure.source` and covers `sections` too.
- `sections` *(sections)*: a list of `start_bar`, `end_bar`, `label` (`intro`, `main`, `break`, `outro`), `energy`.
- `mix_in`, `mix_out` *(mix_windows)*: `start_bar`, `end_bar`, `vocal_free_bars` or null.
- `ends` *(ends)*: `first_sound_s`, `last_sound_s`, `fade_out`, and each or null: `fade_start_bar` (**proposed**
  addition), `steady_in_bar`, `steady_out_bar`.
- `loudness` *(loudness)*: `source`, `confidence` or null, `integrated_lufs`, `lra`, `true_peak_db`.
- `vocal` *(vocal)*: `source`, `confidence` or null, `mean`, `heavy`.
- `onset_pattern_16` *(onset_pattern)*: 16 numbers. `flags`: a list of names, possibly empty.
- `style` *(style)* **proposed**: `model` and `dims`; the values are in `style/<id>.bin`. A reader compares style
  vectors only between records with the same `model`.
- `signatures` **proposed** (track A had variant to `true`): variant name (`o`, `r-4`, `r+4`, as P11 settles) to
  `made_by` (device label) and `made_at`; the file is `signatures/<id>_<variant>.shazamsignature` and must exist.
  Empty (`{}`) until an Apple device adds signatures: this track builds no fingerprint.

**Bar numbers.** A bar is 1 to `n_bars`; a bar line (an exclusive end, a boundary, the start of a fade, the start or
end of the steady beat) is 1 to `n_bars + 1`. **Per-block source and confidence** (**proposed**): `source` names a
model from `engine.models` or a method (`votes` for a key decided from `key.votes`, `foote-novelty`, `pyloudnorm`,
`deckie-core`, `rekordbox-xml`, `user`). `confidence` is on the block's own documented scale (the grid fit, the key
vote rule, the phrase share) until the Mac benchmark can say how often each source is right; that reading will be
added as a new field, not poured into `confidence`, so no field changes meaning with a version. Likewise the 0-to-1
series are on their source's scale until the listening-set calibration exists; a scorer mixing records checks that
the sources match.

## Sidecars **proposed** (the header and the order)

`bars/<id>.bin`: a 16-byte header, the four letters `DKB1`, then `n_bars`, the number of series and 0, each a 32-bit
little-endian integer; then each series in turn, `n_bars` float16 values (little-endian, rounded to nearest, ties to
even). The series are the `bars.<series>` names in `features_present`, in that list's order (sorted), so a reader can
skip a series it does not know. Known series: `lufs` (loudness of the bar), `low_db` (below 150 Hz), `high_db` (above
4 kHz), `onset_density` (onsets per beat), and `vocal`, `drum`, `bass`, `other` (activity, 0 to 1). `style/<id>.bin`:
`DKS1`, `dims`, 0, 0, then `dims` float16 values. Float16 steps are 0.016 dB near -20 dB and 0.06 dB near -100,
and 0.0005 or finer on 0-to-1 values (no per-bar value of the lab's moves more than 0.03): enough for picks, not for
parity tests, which stay on the lab's files.

## How it is written **proposed**

Canonical, so two writes of the same crate are identical byte for byte, in any language: UTF-8; keys sorted by byte;
no spaces; strings escaped only where JSON requires; `null` written, never left out; whole numbers plain; other
numbers rounded to a fixed number of decimals by field name, trailing zeros dropped, one digit kept after the point
(3: `bpm`, `bpm_in`, `bpm_out`, `confidence`, `duration_s`, `first_sound_s`, `last_sound_s`, `lra`; 4:
`first_downbeat_s`, `start_s`, `mean`, `onset_pattern_16`; 2: `fit_mad_ms`, `integrated_lufs`, `true_peak_db`, `secs`).
These are the lab's own roundings. `crate.json` puts each track on its own line, for readable diffs; every file ends
with a newline. The writer replaces `manifest.json`, `crate.json` and the sidecars of current tracks, deletes sidecars
of removed tracks, and touches nothing else. It refuses a crate whose `schema` is newer than its own, because it would
drop fields it does not know; a newer crate can still be read.

## What the reader checks

The version (`schema` at least 1, `min_reader` at most this reader's 1, each record's `schema` at most the
manifest's), required fields and their types, unique and file-safe ids, a `file.sha256` when present (64 lower-case
hexadecimal characters, with the record's `id` its first 16), `features_present` against the blocks, every bar number
in range, starts before ends, `onset_pattern_16` of 16, Camelot codes, confidences between 0 and 1, each sidecar's
header, size and bar count against `n_bars`, and that each listed signature file exists. A problem
names the file, the field path and the track, for example `crate.json: tracks[2].mix_in.end_bar (track 0327cf1c94):
177 is past the end of the grid (175 bars, so at most 176)`. The writer runs the same checks before writing.

## From the lab's feature files **proposed**

`FeatureFile.crateTrack` maps any committed `mixer/features/<id>.json` to a record, with its `candidates.json` row for
the artist and song where the row has them (198 of 373; elsewhere the lab's "Artist - Title" stays whole in `title`).
Engine label `lab-1`, family `lab`, version `1` (the files' schema), `fidelity` 0, so any benchmarked engine redoes
these tracks, as Christopher's crate must be regenerated with the shipped engine before a TestFlight build (track A).
Level 1; `analysed_at` is given by the caller, as the files carry no date; `secs` is the sum of `timing_s` as written
(two files hold stages of 3 to 40 minutes, Thriller's adding up to 4,277 s: the lab's record, not a speed). Grid source
`beat-this-final0` or `madmom-rnn-dbn`; one tempo segment from the grid; key from the three votes (`votes`), no key
changes; `rel` is the path below the lab's music folder; the lab's id stays the record's id, and `sha256` is null.
Two departures from the files: on 21 of the 373 the lab rounds the end of the steady beat to the bar line after the
last partial bar (`n_bars + 2`), which the record writes as the grid's end, `n_bars + 1`; and the 1280-value EffNet
embedding is not carried at all, because its model is non-commercial and the port plan says the stored embeddings
must not travel in any crate, so lab records have no `style` and the scorer's timbre term needs the shipped style
vector. Not carried, as the port plan lists: beat arrays (beats follow from the grid), the tempo votes, grid
candidates, novelty peaks, phase novelty, end loudness, tail bars, the 15-second tempo profile and window fits, the
octave-fix details, `path` and `timing_s`.

The example crate holds five of them: a grid from madmom (Thriller), an octave-fixed grid (Livin' La Vida Loca), a
fade-out whose steady beat needed the clamp (Blue (Da Ba Dee)), a tempo change (NOKIA, a transition edit), and the
shortest track (Rich Baby Daddy, 44 bars): 20 KB in all, with no embedding, as above.
`core/Tools/make_crate_fixture.sh` rebuilds it; a test checks the committed bytes are what the converter makes today.
All 373 tracks as one crate make 1.5 MB, about 4 KB a track (2.9 KB of record, 1.2 KB of sidecar), inside track A's
budget of about 10 KB.

## The proposals in one list, for the main session

1. Track L's additions: the `engine` block beside `analysis` (which keeps its label); the `features_present` names;
   `source` on `grid`, `key`, `phrase` (for structure), `loudness` and `vocal`, `confidence` on each block's own
   scale, calibrated readings to come as new fields.
2. `fidelity`: 0 not benchmarked, n for benchmark tier n (tier 1 the stage 1 pass marks); lab records 0.
3. Engine families `apple-mu`, `deckie`, `lab` (track L's `deckie-core` renamed; the main session chose `deckie`
   over the proposed `deckie-oss`).
4. Additions to track A's record: `tempo_segments`, `ends.fade_start_bar`, `ident.tags`, the `style` block.
5. Shape changes to track A's record (no reader exists yet): `key.changes` as objects; a signature entry as
   `made_by` and `made_at` instead of `true`; `ident.folder` and `ident.era` as text.
6. The sidecar headers (`DKB1`, `DKS1`) and the series order (that of `features_present`).
7. The canonical form, and the writer's refusal to rewrite a newer crate.
8. The lab conversion: the steady-beat clamp, no EffNet embedding ever, `analysed_at` from the caller.
