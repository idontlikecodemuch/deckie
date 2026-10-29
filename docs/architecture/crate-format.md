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
`engines_used` (the tracks' `analysis.engine` labels, sorted; written for a quick look, recomputed by readers), and
`import_log` or null (with step 5, accepted Oct 29, below).

## The track record (`crate.json`)

Numbers carry their unit in the name (`_s` seconds, `_ms`, `_db`, `_lufs`, `bpm`); `lra` is in LU. Every field below
is written in every record; `null` means "no value" and is allowed only where marked "or null". A block marked
*(feature X)* is present exactly when `features_present` lists X, and is `null` otherwise; the two blocks proposed with
memo Q's vocal fields, `vocal_structure` and `hooks`, are instead left out when absent (below).

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
  `sections`, `mix_windows`, `ends`, `loudness`, `vocal`, `onset_pattern`, `style`, `vocal_structure`, `hooks` and
  `bars.<series>`. Readers ignore names they do not know, but keep a per-bar series they do not know. **proposed** (the
  names; `vocal_structure` and `hooks` with memo Q's vocal fields).
- `file`: `name`, `rel` (path below the folder the crate was built from, or null; never absolute), `bytes` or null,
  `sha1_head` or null, `sha256` or null, `duration_s`, `tag_bpm` or null (with step 5, below), `damaged_frames` or
  null (accepted Oct 29, 2026, with the damaged-frame concealment, below). `sha256` is the whole
  file's SHA-256 hash as 64 lower-case hexadecimal characters, the spec's "content hash of the file for exact identity"
  (spec 5.4); the record's `id` is its start, as above, and it is null only in lab records. `sha1_head` is track A's
  head hash: a SHA-1 of the start of the file, which the Apple apps keep for a quick identity check. Track A section 5
  defines it only by its rule, "Store a relative path plus size and a head hash to re-find files", and its example
  record, which shows `"sha1_head": "..."`; track B refers to it as the content hash "in Track A's crate file as a head
  hash". Neither document says how many bytes of the head it covers or how the hash is written, and no code computes it
  yet, so this format does not define it further: every record this track writes has it null, and the reader does not
  check it.
- `ident`: `title`, and each or null: `artist`, `version`, `source`, `mbid`, `disc`, `folder`, `track`, `cut_key`,
  `is_longest`, `era`, `kind`; plus `tags` (list). **proposed**: `tags` (the lab's Halloween mark becomes the tag
  `halloween`, as the port plan suggests), and `folder` and `era` as text, as the lab has them (track A showed numbers).
- `analysis`: `engine` (label), `analysed_at`, `device` (a model label such as `Mac15,6`, never a user's device
  name), `secs` or null, `level`.
- `engine` **proposed** (where track L's record sits: a block beside `analysis`, which keeps its text label): `family`
  (`apple-mu` for the Apple apps' engine, `deckie` for the Windows and Linux engine, `lab`; decided by the main session:
  a family names an engine and must not claim a licence, and while the Windows and Linux engine's models are open
  source, the engine is not; track L wrote `deckie-core`, which now names the code both engines share), `version`,
  `platform` (`macos-arm64`, `linux-x86_64`, `windows-x86_64`), `fidelity`, `models` (each `name`, `version` or null,
  `weights_sha256` or null), `decoder` (`name`, `version` or null) or null. An engine's `version` goes up whenever the
  record it writes gains or changes fields (the Windows and Linux engine's is 0.4.0: 0.2.0 brought the vocal
  blocks and `file.tag_bpm`, 0.3.0 the three-profile key vote, which changes keys, 0.3.1 `file.damaged_frames`, with
  damaged MP3 frames silenced, 0.4.0 the whitened-HPCP key, which changes keys again), so a builder's work folder made
  by an older version is analysed again rather than reused.
  **proposed**: `fidelity` 0 means not benchmarked; n means the build passed benchmark tier n, tier 1 being the stage 1
  pass marks. A device with the audio re-analyses a record when its own fidelity is higher, or the record's level is a
  fallback the device can better.
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
- `imported` or null (with step 5, accepted Oct 29, below): what was imported with the track from the DJ's own
  software, by source (`imported.rekordbox`).
- `vocal_structure` *(vocal_structure)* and `hooks` *(hooks)* **accepted** (Oct 29, 2026) with memo Q's vocal fields (below): where
  the track is sung, to the beat, and up to three hook candidates. Left out when absent, never written as null.

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
no spaces; strings escaped only where JSON requires; `null` written, never left out (except a record's absent
`vocal_structure` and `hooks`, which are left out); whole numbers plain; other
numbers rounded to a fixed number of decimals by field name, trailing zeros dropped, one digit kept after the point
(3: `bpm`, `bpm_in`, `bpm_out`, `confidence`, `duration_s`, `first_sound_s`, `last_sound_s`, `lra`, `tag_bpm`; 4:
`first_downbeat_s`, `start_s`, `end_s`, `mean`, `onset_pattern_16`, `seconds`; 2: `fit_mad_ms`, `integrated_lufs`,
`true_peak_db`, `secs`; the vocal blocks' numbers are listed with them, below).
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

## Additions with the crate builder (step 5), accepted Oct 29, 2026

`deckie-build` (`core/Sources/DeckieBuild`) builds a crate from a folder of audio files. It needed places the format did
not have, all additive: a reader that does not know them ignores them, a crate written before them reads them as null,
and the example crate gains `file.tag_bpm` and `imported`, both null, in each record. The builder proposed
`manifest.import_log` and a record block named `deckie`; the main session accepted both on Oct 29, 2026 with three
renames, applied here: `import_log.built_by` is a device label, the block is `imported`, and the tag tempo is
`file.tag_bpm`.

- **`manifest.import_log`**, so no file of the folder is left out silently (decision P18): `built_by`, `built_at`
  (UTC), `files_seen` (audio files found, by extension: mp3, flac, wav, aif, aiff, aifc, m4a, mp4, aac, wma, ogg, opus,
  m4p), `tracks` (records written), `entries` (one per file with no record of its own, sorted by path: `rel`, the path
  below the folder, never absolute; `ext`, lower case; `reason`; `message`, the decoder's or the analyser's own words),
  `counts` (reason, then extension, to a number; written from the entries for a quick look and recomputed by readers,
  as `engines_used` is) and `rekordbox` (`tracks` in the collection export and how many `matched` a file) or null.
  `built_by` is the device that built the crate: a model label such as `Mac15,6` or `linux-x86_64`, never the user's
  own name for the device, by the same rule and with the same value as `analysis.device` (the builder writes its one
  device label, `Analysis.platform` on Windows and Linux, to both); the builder had proposed its program and version,
  which the records' `engine` blocks already give. Reasons: `unsupported` (a format this platform cannot decode: AAC
  and WMA on Linux, Ogg, Opus), `protected` (copy protection: no decoder will ever read it), `damaged` (cut short or
  corrupted), `decode_error` (could not be read, or failed otherwise while decoding), `analysis_error` (decoded, but no
  beat grid, too few bars, or the model failed) and `duplicate` (the same bytes as another file, which has the record:
  the id is the file's hash). The log describes the last build; an app that later adds tracks leaves it as it is.
- **`file.tag_bpm`**, a number or null: the tag tempo, the tempo written down for the file before it was analysed (the
  collection's `AverageBpm` from a rekordbox export, else, with `--bpm-tags`, the file's own tag such as ID3 `TBPM`),
  which the octave alignment was steered by. The main session's reason: the tag tempo is a fact about the file, not an
  import, so it sits with the file. Its source, which the proposal recorded beside it, is dropped, from the record and
  from the import log alike: rekordbox's tempo is taken whenever the collection has one, so the tag came from rekordbox
  exactly when it equals `imported.rekordbox.bpm`, and from the file's own tag otherwise. `ident.tags` stays the list of
  labels.
- **`imported`** on a record, null when nothing was imported: what came with the track from the DJ's own software,
  keyed by source, so a Serato import can sit beside a rekordbox one later. The main session's reason for the name: it
  holds the DJ's own data, so the name says where it came from; `deckie`, as proposed, would read as ours. (The lab
  JSON the engine writes keeps its own `deckie` block, `deckie.madmom_would_run`, `deckie.vocal` and the rest: the
  engine's fields in the lab's file, a different thing.) `imported.rekordbox` or null is the track's entry in a
  rekordbox collection export as rekordbox wrote it: `imported_at` (when the builder took it from the export, UTC to the
  second; a rebuild that finds the entry unchanged keeps the first time, so rebuilding from the same export changes no
  record), `track_id`, `bpm` (`AverageBpm`) or null, `tonality` (as written: `Am`, `8A` or `1m`, by the DJ's display
  setting) or null, `grid_markers` (the TEMPO elements: `start_s`, `bpm`, `meter` or null, `beat_in_bar`), `cues` (the
  POSITION_MARK elements that are not loops: `name`, `kind` one of `cue`, `fade-in`, `fade-out`, `load`, `hot_cue` 0
  for A to 7 for H or null for a memory cue, `start_s`), `loops` (the POSITION_MARK loops, rekordbox's type 4: `name`,
  `hot_cue` or null, `start_s`, `end_s`, null only when rekordbox wrote no end) and `playlists` (each playlist holding
  the track as its path of names from the top folder, the playlist last). Times are as rekordbox measured them, from
  the start of the file as its decoder reads it. `end_s` is written with 4 decimals, as `start_s`; `tag_bpm` with 3, as
  `bpm`.

What a rekordbox export puts in fields the format already has: the track's `Name`, `Artist` and `Mix` become
`ident.title`, `ident.artist` and `ident.version` with `ident.source` `rekordbox-xml` (else the file's own title and
artist tags, source `tag`, else the file name, source `filename`); the DJ's key becomes the vote `rekordbox-xml` in
`key.votes`, as a Camelot code, while `key.camelot` stays the engine's decision; the DJ's tempo steers the analysis
(the lab's octave alignment to a tag) and is recorded in `file.tag_bpm`. The engine's own grid stays in `grid` and
`tempo_segments`; the DJ's grid markers, cues and loops stay in `imported.rekordbox`, untouched, so the Apple apps can
show or compare them without either side overwriting the other.

## Accepted with the damaged-frame concealment (proposed and accepted Oct 29, 2026)

The main session decided on Oct 29, 2026 that the Windows and Linux MP3 decoder plays a damaged frame (one whose
Huffman data runs past its own end, as on a damaged or badly spliced file) as silence, as mpg123 does, rather than
decode it into a burst (dr_mp3 alone gave one lab track a true peak of +9.2 dBTP where the lab's decoder gave +2.5), and
that the DJ is told. Both fields are additive: a reader that does not know them ignores them, a crate written before
them reads them as null, and the example crate gains `file.damaged_frames`, null, in each record. Accepted by the
main session on Oct 29, 2026 as proposed, no rename (it adds them to the note on D13 on `main`):

- **`file.damaged_frames`**, a list or null: the frames played as silence, in order, each `start_s` (where the frame's
  decoded audio starts, in seconds from the start of the decoded audio, 4 decimals) and `seconds` (its length, one MP3
  frame, 0.0261 at 44.1 kHz; 4 decimals); null when there were none, as for every file that is not MP3. Reason: the
  file is faulty but playable, and every other number in the record was measured on the audio with those frames silent,
  so the record says where the audio is not the file's own. The engine's lab JSON carries the same list as
  `deckie.damaged_frames`.
- **`import_log` entries with reason `damaged_frames`**: a file whose record is in the crate but has damaged frames is
  listed too, the times in its `message` ("damaged frame at 1:01.234 (26 ms), played as silence; the track is in the
  crate"), and counted under its reason in `counts`; `tracks` still counts it, and the builder's summary does not count
  it among the files left out. Reason: decision P18's "nothing left out silently" extended to a file that was changed
  on its way in.

## Additions accepted with the vocal fields (memo Q; the main session's yes, Oct 29, 2026)

Memo Q (`docs/research/q-vocal-uses.md`, sections 3 and 4) found that DJs use vocals six ways (keep two apart, hand off,
acapella, tease, echo out, singalong) and that a per-bar probability serves few of them: a hand-off needs the beat of
the last word, a "drop on the four" the pickup, an acapella a vocal-free stretch in the middle of the track. Two blocks
carry its items A1 to A6 and B7, computed from what the engine already measures: the vocal tagger's frame-by-frame
scores (YAMNet's, 0.48 s apart, finer than a bar), the grid, the 8-bar lattice, the per-bar `lufs`, `low_db`, `high_db`
and onset density, and the fade-out. Code: `core/Sources/DeckieCore/Structure/VocalStructure.swift` and `Hooks.swift`
(the rules), `core/Sources/DeckieCrate/CrateModel+Vocal.swift` (the blocks).

Both are additive: a record without them reads as before. Unlike every other field they are **left out when absent,
not written as null**, so the records of engines that do not make them (the lab's, the Apple apps' until they add
them) keep their bytes, and the example crate is unchanged; `features_present` lists each exactly when it is there. The
Windows and Linux engine writes both whenever it has a vocal tagger and neither without one (the record keeps its flag
`vocal_unknown`). The lab JSON the engine writes carries the same fields and values under its `deckie` block
(`deckie.vocal_structure`, `deckie.hooks`, null without a tagger), where the lab's own tools do not look.

The rules are a first cut on uncalibrated scores. Each is relative to the track, and its parameters and the threshold
it used are written in the block's `rule`, so the Mac's listening test can tune them and a scorer mixing records can
tell which rule made each.

**Bars and beats.** Bars are 1-based and beats 1 to 4 within the bar (the grid's beats, 4/4). A start is the beat a
stretch begins on: the grid beat nearest the time the score rises through the threshold. An end is the beat line it
stops at: the grid beat nearest the time the score falls through it, exclusive like every `end_bar`, so an end can be
beat 1 of bar `n_bars + 1`. Times (`start_s`, `end_s`, `time_s`) are those crossing times, read between frame centres
by straight-line interpolation, in seconds from the start of the decoded audio; singing before bar 1 or past the end
line is clamped to the grid in bars and beats, not in seconds.

- `vocal_structure` *(vocal_structure)* **accepted** (Oct 29, 2026):
  - `source`: the tagger's model, as `vocal.source`. `frame_hop_s`: seconds between the frames read (0.48 for YAMNet;
    a bar's length when the tagger gives bars only, and then a change is placed on the bar line). `lattice_phase_bar`:
    the lattice used below (`phrase.lattice_phase_bar`).
  - `spans` (A1): the sung stretches in order, none overlapping, each `start_bar`, `start_beat`, `start_s`, `end_bar`,
    `end_beat`, `end_s`, and `start_offset_beats`, `end_offset_beats` (A6, memo Q's `span_end_offset`): each end's
    signed distance in beats from the nearest 8-bar lattice point, -15 to 16, negative before it (a tie at 16 counts
    as after the earlier point). Near zero, the stretch starts or stops on a phrase boundary, where a hand-off or an
    echo out sounds intended. The rule: a frame is sung when its score is at least `rule.threshold`; dips shorter than
    `rule.bridge_beats` between sung stretches are bridged, so a span is a verse or a chorus rather than a line (Apple's
    `ranges` bridges the same way); then stretches shorter than `rule.min_span_beats` are dropped as blips.
  - `first` (A2): `bar`, `beat` and `time_s` of the first sung beat, and `pickup`, true when that beat is within
    `rule.pickup_beats` before a downbeat (with 1, it is beat 4): the "drop on the four" case. `last`: `bar` and `beat`
    of the last sung beat (the beat before the last span's end line) and `time_s`, when the singing stops: the beat of
    the last word, for an echo out. Both null when there is no span.
  - `intro_free_bars`, `outro_free_bars` (A3): whole bars before the bar of the first sung beat and after the bar of the
    last (`n_bars` when nothing is sung); a pickup's bar is not free. `intro_kind`, `outro_kind`: what they hold, one of
    `beat_only`, `ambient`, `vocal`, `fade`. The rule, a first cut for the Mac to tune: `vocal` when there is no free
    bar (sung from bar 1, or into the last bar); for the outro, `fade` when the fade-out starts at or before the first
    bar read; otherwise the first `rule.kind_bars` free bars of the intro, or the last `kind_bars` free bars of the
    outro before any fade, are `beat_only` when their median onset density is at least `rule.beat_density_ratio` of the
    track's median (a beat goes on) and their median `high_db` at most `rule.bright_margin_db` above the track's median
    (not a riser or a noise sweep, whose onsets are not a beat), and `ambient` otherwise. The intro is never `fade`: no
    fade-in is detected.
  - `free_gaps` (A4): vocal-free stretches anywhere (whole bars with no sung beat), each with its start moved forward
    to the next lattice bar and kept when `rule.min_gap_bars` or more remain: `start_bar`, `end_bar` (the bar line
    where singing resumes, or `n_bars + 1`), `bars`. Where A's vocal drops out, where an acapella fits, where to loop.
  - `exposed_proxy` (A5): `start_bar`, `end_bar` of runs of `rule.exposed_min_bars` bars or more in which at least half
    of each bar's beats are sung, its `low_db` is at least `rule.exposed_low_drop_db` under the track's median and its
    onset density at most `rule.exposed_density_ratio` of the track's median: the bass and the drums drop while the
    voice goes on. Memo Q's `exposed` wants vocal high and drums and bass low; this engine measures no drum or bass
    activity, so `low_db` and the onset density stand in, and the name says so. The Apple apps' records will carry
    `exposed` (same shape) from SoundAnalysis's real drum and bass activity; a reader prefers `exposed` when present
    and falls back to `exposed_proxy`.
  - `rule`: `threshold`, the frame score used, `max(threshold_floor, threshold_fraction x score_p95)` with `score_p95`
    the track's 95th-percentile frame score; `threshold_fraction` (0.25), `threshold_floor` (0.01), `bridge_beats` (8),
    `min_span_beats` (2), `pickup_beats` (1), `min_gap_bars` (8), `kind_bars` (16), `beat_density_ratio` (0.5),
    `bright_margin_db` (6), `exposed_low_drop_db` (6), `exposed_density_ratio` (0.5), `exposed_min_bars` (2): the
    engine's values in brackets. Why a quarter: YAMNet's score rose late as the voice filled a frame's 0.96 s window
    (on the synthesised test voice, 4 percent of its peak with the window 35 percent voiced, 10 percent at 58, about
    half at 85), so a quarter of the peak is crossed when the window is about half voiced, near the voice's start or
    stop; half the peak split verses apart, because sung frames dip far below their peak. It also errs toward hearing a
    voice: a missed vocal makes a clash, a false one only an unused bar. The floor keeps a track with no voice from
    having its background read as singing; it is set for YAMNet's scores on the synthesised voice (a few hundredths)
    and should rise once real voices are measured. Two bars of bridge: longer than a breath or a fill between lines,
    shorter than the 4-bar breaks DJs mix in.
- `hooks` *(hooks)* **accepted** (Oct 29, 2026; B7): up to three hook candidates, strongest first, for the DJ to confirm with one tap
  (whether a line is recognisable is not in the audio): `source` (`deckie-core`), `lattice_phase_bar`, `candidates`
  (each `start_bar`, `end_bar`, 4 or 8 bars on, `strength` 0 to 1, `sung`, the terms behind the strength,
  `repetition`, `loudness_score` and `vocal_density`, each 0 to 1, and `repeat_start_bar`, where the same stretch comes
  again), and `rule`. The rule: candidates of `rule.lengths_bars` (8 and 4) bars start every `rule.step_bars` (4) bars
  from the lattice phase, on a phrase boundary or halfway through one. `repetition` is the best mean bar-to-bar
  similarity with a window of the same length elsewhere that does not overlap it, and must be at least
  `rule.min_repetition` (0.5); the similarity is the cosine between bars of the frame-wise MFCC the structure novelty
  already uses, averaged over each bar on the novelty's own frame edges, its first coefficient (the level) left out and
  the others centred on the track. `loudness_score` places the stretch's mean bar `lufs` between the track's 10th and
  90th percentile bar loudness (taken at least 1 LU apart). `vocal_density` is the share of its beats inside a span,
  and `sung` is true from `rule.sung_share` (0.5). `strength` = (`weight_repetition` x repetition + `weight_loudness` x
  loudness_score + `weight_vocal` x vocal_density) / the weights' sum (0.5, 0.25, 0.25): repetition counts most,
  because it is what makes a stretch a hook rather than merely the loudest part. A shorter candidate inside a longer
  one is kept only when stronger by more than `rule.short_margin` (0.05), so an 8-bar chorus is not cut to the 4 bars
  that score a hair higher; a candidate overlapping one already taken, or that one's repeat, is the same hook and is
  skipped; at most `rule.max_hooks` (3).

**Decimals** (`CrateFormat.decimals`): 4 for `time_s`, `frame_hop_s`, `threshold`, `score_p95`, `threshold_floor`
(`start_s` and `end_s` keep their 4); 3 for `threshold_fraction`, `beat_density_ratio`, `exposed_density_ratio`,
`strength`, `repetition`, `loudness_score`, `vocal_density`, `weight_repetition`, `weight_loudness`, `weight_vocal`,
`min_repetition`, `short_margin`, `sung_share`; 2 for `bright_margin_db`, `exposed_low_drop_db`.

**What the reader checks** for them: the grid is there; bars and beats in range (a start on a bar of the grid, an end up
to beat 1 of bar `n_bars + 1`); spans in order, not overlapping, each ending after it starts; offsets between -16 and
16; `first` and `last` there exactly when a span is; free bars between 0 and `n_bars`; the kinds from the four names;
each gap's `bars` its length; the hooks' bars in range, their scores between 0 and 1, strongest first.

**What is uncalibrated, for the Mac to tune.** Everything above rests on YAMNet's scores, which no listening test has
calibrated: on the synthesised voice its frames dip far below their peak inside a sung stretch, so on the engine's
test track a span's ends land within two beats of the construction (the pickup, the last sung beat and the free bars
exactly), not on it every time. The listening set (memo Q section 4, "Next") should mark the first and last sung beat,
the hook and the exposed line, and tune the threshold fraction and floor, the bridge, the kind rule, the proxy and the
hook weights. Size: about 1.5 KB a record on the test track (two spans, three hooks), most of it the two rules.

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
9. With step 5, **accepted Oct 29, 2026** with three renames (above): `manifest.import_log`, its `built_by` a device
   model label as `analysis.device` is, never the user's device name; the record's per-track block named `imported`,
   keyed by source (`imported.rekordbox`, null when nothing was imported), not `deckie`, because it holds the DJ's own
   data and its name should say where that came from; the tag tempo as `file.tag_bpm`, a fact about the file rather
   than an import, without its source; `end_s` and `tag_bpm` in the decimals table.
10. Accepted Oct 29, 2026. With memo Q's vocal fields: the record's `vocal_structure` and `hooks` blocks and their `features_present` names,
    left out when absent rather than written as null (the one exception to the canonical form's nulls, so existing
    records keep their bytes); `exposed_proxy` named apart from the Apple family's `exposed`, which a reader prefers;
    their decimals.
