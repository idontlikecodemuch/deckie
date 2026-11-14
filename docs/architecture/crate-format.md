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
  prints/<id>.dkl                          the song's fingerprint for recognition (D35, below)
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
memo Q's vocal fields, `vocal_structure` and `hooks`, are instead left out when absent (below), as is
`ident.other_places` (D27, below) when the entry has no other place.

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
  `sections`, `mix_windows`, `ends`, `loudness`, `vocal`, `onset_pattern`, `style`, `vocal_structure`, `hooks`,
  `key_home` (D36) and `bars.<series>`. Readers ignore names they do not know, but keep a per-bar series they do not know. **proposed** (the
  names; `vocal_structure` and `hooks` with memo Q's vocal fields).
- `file`: `name`, `rel` (path below the folder the crate was built from, or, for an entry read from a source, below
  that source's top, the source being named by `ident.disc` (D25, Nov 13, 2026; meaning only); or null; never absolute), `bytes` or null,
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
  `is_longest`, `era`, `kind`; plus `tags` (list); and `other_places` (list, D27, Nov 13, 2026; left out when empty). **proposed**: `tags` (the lab's Halloween mark becomes the tag
  `halloween`, as the port plan suggests), and `folder` and `era` as text, as the lab has them (track A showed numbers).
  `disc`, `folder` and `track` (D25 and D26, Nov 13, 2026; meaning only, the fields are unchanged) are a song's
  place. `disc` is the **source** the song was read from, by the source's own name as the DJ sees it ("Stick 3"): a
  burned data CD, a USB stick or an SD card that Deckie Desk read as it is. `folder` is the group inside it, the
  folder's path below the source's top with names joined by "/" ("House", "House/Peak"; "" at its top). `track` is the
  song's number in that group, counted from 1 in the order a player shows (`SourceReading` in DeckieCrate, which holds
  the one rule); a file on the source that is not in the crate still holds its number, so a folder may have gaps. An
  entry with no `disc` has no source: it is only in a folder on the Mac, and its place is that folder (`rel`'s). Readers
  show a source by `disc` itself, never by a word of their own. A source reads as it is, so the same file content on
  two sources is one entry (ids are unique): its own place is one of them, and the others are listed in
  `other_places` (D27, below). Earlier crate files may hold discs made by hand in Desk (D20); they read the same way.
  `cut_key` (D24, Nov 13, 2026; meaning only, the field is unchanged): entries with the same `cut_key` are copies of
  one recording, the same song; an entry whose `cut_key` is null or empty is a song on its own, keyed by its `id`.
  Nothing is folded by title, so a remix, an edit or a live version is its own song. Deckie Desk fills it with Find
  copies from a print of each file's audio (`RecordingPrint` in DeckieCore, the rule written there), choosing the
  smallest `id` of the copies as the key; readers take it through `SameSong` (DeckieCrate). Lab records keep the lab's
  own `cut_key`.
  `ident.source` (D30, Nov 13, 2026; meaning only) names where the name came from: `tag`, `filename` (the file name
  read by pattern), `folder` (the folder as the artist), `cue`, `m3u`, `tracklist` (a list beside the music), a DJ
  program's name as in `key.source` (`rekordbox-xml`, `traktor`, `engine-dj`, `serato`, `virtualdj`), `copy` (a named
  copy of the same recording), `user` (the DJ's own fix), `lab`. When the title and the artist came from different
  places the two are joined by "+", the title's first (`filename+folder`).
- `analysis`: `engine` (label), `analysed_at`, `device` (a model label such as `Mac15,6`, never a user's device
  name), `secs` or null, `level`.
- `engine` **proposed** (where track L's record sits: a block beside `analysis`, which keeps its text label): `family`
  (`apple-mu` for the Apple apps' engine, `deckie` for the Windows and Linux engine, `lab`; decided by the main session:
  a family names an engine and must not claim a licence, and while the Windows and Linux engine's models are open
  source, the engine is not; track L wrote `deckie-core`, which now names the code both engines share), `version`,
  `platform` (`macos-arm64`, `linux-x86_64`, `windows-x86_64`), `fidelity`, `models` (each `name`, `version` or null,
  `weights_sha256` or null), `decoder` (`name`, `version` or null) or null. An engine's `version` goes up whenever the
  record it writes gains or changes fields (the Windows and Linux engine's is 0.6.0: 0.2.0 brought the vocal
  blocks and `file.tag_bpm`, 0.3.0 the three-profile key vote, which changes keys, 0.3.1 `file.damaged_frames`, with
  damaged MP3 frames silenced, 0.4.0 the whitened-HPCP key, which changes keys again, 0.5.0 the three-answer key
  reader of D33, which changes the key block's source, confidence, code and votes, 0.6.0 the home note of D36:
  `key_home` in place of a key block at 0.45), so a builder's work folder made
  by an older version is analysed again rather than reused.
  **proposed**: `fidelity` 0 means not benchmarked; n means the build passed benchmark tier n, tier 1 being the stage 1
  pass marks. A device with the audio re-analyses a record when its own fidelity is higher, or the record's level is a
  fallback the device can better.
- `grid` *(grid)*: `source`, `confidence` (0 to 1), `bpm`, `first_downbeat_s` (the start of bar 1), `n_bars` (whole
  bars from bar 1 to the end), `fit_mad_ms` or null, `bpm_in`, `bpm_out`, `in_trusted`, `out_trusted`.
- `tempo_segments` *(tempo_segments)* **proposed** (spec 5.2's grid marker): a list of `start_bar`, `start_s`, `bpm`,
  `beats_per_bar`, `beat_in_bar` (1 when the segment starts on a downbeat, as rekordbox's `Battito`), `confidence`
  or null. One segment for a steady track.
- `key` *(key)*: `source` (`three-answer` from engine 0.5.0, D33's reader, below; `hpcp-whitened` in 0.4.0, research
  R's method; `votes` from 0.3.0, `stft-edma` before), `confidence`, `camelot`, `key` or null, `scale` or null, `votes` (source name to Camelot
  code), `changes` *(key_changes)*: a list of `start_bar`, `end_bar`, `camelot`, or null. **proposed**: objects
  rather than track A's three-element lists.
  **The DJ's own key** (D30, Nov 13, 2026; meaning only, no field added or changed): a record whose key is the DJ's
  has `key.source` naming where it came from: `rekordbox-xml`, `traktor`, `engine-dj`, `serato`, `virtualdj` (that
  program's library), `tag` (the file's key tag), `tag-comment` (a key written into the comment, as Mixed In Key
  does), `tag-title` (one written into the title). `key.votes` holds every key the DJ's programs and tags gave, under
  the same names, so the ones not chosen stay visible; `key.confidence` is then the share of those that agree with
  `key.camelot` (1 when there is one, or all agree), on that scale; `key.key` and `key.scale` spell the code; and
  `key.changes` is null. Which wins: the program whose library file was written most recently, then the file's tag,
  comment, title (`LocalFacts` in DeckieBuild). A record from Deckie's own engine keeps the engine's reading beside the
  DJ's key as the vote `deckie`; with no key from the DJ its `key` block is the engine's own, exactly as the engine
  wrote it (the note on D30 and D16 prefers a key; whether it is shown song by song waits for the key trial). A
  record read by Apple's framework (`engine.family` `apple-mu`) keeps that reading as `key.camelot`, with the DJ's
  keys added to `key.votes` under these names.
  **Deckie's own reading from engine 0.5.0** (D33, Nov 14, 2026; meaning only, no field added or changed): the
  three-answer reader (`ThreeAnswerKey` in DeckieCore; research X2) writes `key.source` `three-answer` and puts its
  answer on the block's confidence scale: **1.0** a key (its two readings name the same home note and the same
  mode); **0.2** not sure (different home notes), when `key.camelot` is only the reader's best guess, under the 0.5
  line that sets `key_uncertain`. Its third answer, the home note alone (the same home note, different modes), is
  not a key block: it is the `key_home` block ("The home note", below; engine 0.6.0, D36. Engine 0.5.0 wrote a key
  block at **0.45** for it, which `LocalFacts` still reads as a home note). `key.votes` gains `hpcp_discount` and
  `note_transcription` (the two readings' own keys) and `hpcp_whitened` (the 0.4.0 method's key) beside the four it
  had. That is the builder's record, as the engine wrote it. **What a crate file shows** is decided by
  `LocalFacts.decideKey` (Desk and `deckie-build`) and `LocalFacts.ownKeysOnly` (`deckie-make`): a three-answer
  reading is the record's key only at 1.0; a reading at 0.2 is dropped, so the record has no `key` block (unless a
  DJ's own key takes its place), and it is not kept as the vote `deckie` beside a DJ's key. So a crate file never
  carries a three-answer key the reader was not sure of. **What a record says about its key** is then one of four
  things (`CrateTrack.keyState`): a key; a home note; not sure (a record of the `deckie` engine from 0.5.0 with
  neither: the reader reads every song); not read (any other record with neither).
- `phrase` *(phrase)*: `source`, `confidence`, `lattice_phase_bar` (1 to 8), `boundaries_bars`. Its `source` is track
  L's `structure.source` and covers `sections` too.
- `sections` *(sections)*: a list of `start_bar`, `end_bar`, `label` (`intro`, `main`, `break`, `outro`), `energy`.
- `mix_in`, `mix_out` *(mix_windows)*: `start_bar`, `end_bar`, `vocal_free_bars` or null.
- `ends` *(ends)*: `first_sound_s`, `last_sound_s`, `fade_out`, and each or null: `fade_start_bar` (**proposed**
  addition), `steady_in_bar`, `steady_out_bar`.
- `loudness` *(loudness)*: `source`, `confidence` or null, `integrated_lufs`, `lra`, `true_peak_db`.
- `vocal` *(vocal)*: `source`, `confidence` or null, `mean`, `heavy`.
- `onset_pattern_16` *(onset_pattern)*: 16 numbers. `flags`: a list of names, possibly empty. One name
  added Nov 14, 2026 (D33), with no field changed: **`start_uncertain`**, set by the engine when its decoder could
  not place the start of the sound to the sample (an AAC file read on Windows that states its encoder's lead-in
  nowhere). Every time in such a record (the grid's first downbeat, the tempo segments, the ends) may be up to 48 ms
  late against the file as a player plays it. A reader shows the song as any other and may show its grid with
  that caveat; a reader that does not know the name ignores it, as with every flag.
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
`vocal_structure` and `hooks`, and an empty `ident.other_places`, which are left out); whole numbers plain; other
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
header, size and bar count against `n_bars`, that each listed signature file exists, and each of
`ident.other_places` (D27, below). A problem
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
  m4p), `tracks` (records written; when a source is added to a crate file, `files_seen` and `entries` cover every part read
  into it, the entries kept from earlier reads included), `entries` (one per file with no record of its own, sorted by path: `rel`, the path
  below the folder, never absolute, or for a file on a source the source's name, a "/" and the path below its top
  (D25; meaning only); `ext`, lower case; `reason`; `message`, the decoder's or the analyser's own words),
  `counts` (reason, then extension, to a number; written from the entries for a quick look and recomputed by readers,
  as `engines_used` is) and `rekordbox` (`tracks` in the collection export and how many `matched` a file) or null.
  `built_by` is the device that built the crate: a model label such as `Mac15,6` or `linux-x86_64`, never the user's
  own name for the device, by the same rule and with the same value as `analysis.device` (the builder writes its one
  device label, `Analysis.platform` on Windows and Linux, to both); the builder had proposed its program and version,
  which the records' `engine` blocks already give. Reasons: `unsupported` (a format this platform cannot decode: AAC
  and WMA on Linux, Ogg, Opus), `protected` (copy protection: no decoder will ever read it), `damaged` (cut short or
  corrupted), `decode_error` (could not be read, or failed otherwise while decoding), `analysis_error` (decoded, but no
  beat grid, too few bars, or the model failed) and `duplicate` (the same bytes as another file, which has the record:
  the id is the file's hash; since D27 only a second file in a place the entry already has, that is two copies in one
  folder on the Mac, which has no numbers: a file anywhere else adds a place, below). The log describes the last build; an app that later adds tracks leaves it as it is.
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
`key.votes`, as a Camelot code, while `key.camelot` stays the engine's decision (as the builder writes it; since
D30, Nov 13, 2026, Deckie Desk's run then makes the DJ's key the record's key, `key.source` `rekordbox-xml`, as above); the DJ's tempo steers the analysis
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

## Addition with D27 (Nov 13, 2026): other places of one file

D27, the first addition to crate v1, decided by the owner on Nov 13, 2026: an entry's id is made from the file's
bytes, so the same file burned onto two discs, or copied unchanged from the Mac onto a stick, is one entry, and until
now the second place was dropped and the file logged as a duplicate. An entry now keeps its own place and may list
others. Additive like every field above it: no field changes name or meaning, `schema` and `min_reader` stay 1, a
crate file written before it reads with no other places, and a reader that does not know it (it ignores keys it does
not know) opens a crate file that has it and shows the entry's own place. Code: `CrateTrack.Ident.otherPlaces` and
`CrateTrack.Place` (`CrateModel.swift`), the operations in `Discs.swift`, the order in `SameSong.swift`, the builder's
reading in `Builder.swift`.

- **`ident.other_places`**, a list, inside `ident` beside the own place it extends: the entry's other places, each
  `disc`, `folder` and `track`, the same three parts with the same meaning as the entry's own (above): the source by
  its own name, or null for a place with no source; the group inside it, or for a place with no source the folder's
  path below the music folder ("" at its top); the song's number there, or null for a place with no source. **Left
  out when empty, never written as null or `[]`**, as `vocal_structure` and `hooks` are, so every record without
  other places keeps its bytes and the example crate is unchanged. Within a place, `null` is written as everywhere
  else. The list is in the order of the rule below; a reader does not rely on it.
- **Which place is the entry's own.** The own place is the one whose file gave the record: `file.name` and `file.rel`
  name that file, and an other place has no path of its own. When a source or folder is read, a place on a source
  already in the crate file and not read now stays the own place; otherwise the place read now that leads by the rule
  of D24 (with no song playing and the sources in name order: the first source by name, then by folder and number; a
  place with no source last) is the own place. An entry only in a folder on the Mac keeps its own place as before
  (`disc`, `folder` and `track` null, the place being `file.rel`'s folder).
- **Reading again.** Reading a source again replaces that source's places, own and other, with what is on it now;
  reading the music folder again does the same for the places with no source. An entry whose own place was on a
  source that no longer holds it takes its leading other place as its own, and its `file.rel` is then null (the crate
  file does not hold the path at the other place) until that source is read again, which writes it. An entry left
  with no place is removed, as before.
- **Duplicates.** A file whose bytes match an entry already in the crate file adds its place to that entry and is no
  longer logged. `import_log` keeps `duplicate` only for a second file in a place the entry already has: two copies
  with the same bytes in one folder on the Mac, which has no numbers to tell them apart. Files seen
  (`import_log.files_seen`) count every place kept from earlier reads, own and other, as one file each.
- **Readers show the places like copies** (D24): one row for the song, one place leading by the same rule (the
  source the playing song is on, else the first source in the DJ's order, a place with no source last; `SameSong`
  takes every place of every copy together), the others as "also on"; a song is allowed by a filter of sources when
  any of its places is. Recognition is unchanged: one entry, one set of signatures.

**What the reader checks** for it: each place has a `disc` or a `folder` (it says some place); a `disc` is not empty; a
`folder` is not an absolute path; a `track` is 1 or more; no place is listed twice or repeats the entry's own.

## Addition with D34 (Nov 14, 2026): a song's facts

D34, decided by the owner on Nov 14, 2026: "Let's port and save whatever info the song crate file has", and each fact
says where it came from, so a lookup fills the same fields and a DJ's own entry is never overwritten. Until now the
crate file kept a song's title, artist and version, and nothing else its file said: the release, the year, the
label, the genre and the rest stayed in Desk, or were never read. Additive like D27: no field changes name or
meaning, `schema` and `min_reader` stay 1, a crate file written before it reads with no facts and writes back byte
for byte, and a reader that does not know it (it ignores keys it does not know) opens a crate file that has it and
shows the song as before. Code: `CrateTrack.Fact`, `CrateTrack.OtherTags` and `SongFacts` (`SongFacts.swift`), the
file's reading in `FileFacts` (`core/Sources/DeckieBuild/FileFacts.swift`), the libraries' in `DJLibraries.swift`
and `Rekordbox.swift`, the gathering in `LocalFacts+SongFacts.swift`; tests in
`core/Tests/DeckieCrateTests/SongFactsTests.swift` and `core/Tests/DeckieBuildTests/FileFactsTests.swift`.

Two places, both **left out when empty, never written as null, `{}` or `[]`**, as `ident.other_places` is, so every
record without them keeps its bytes and the example crate is unchanged:

- **`ident.facts`**, an object, inside `ident` beside the title, artist and version it adds to: one member per fact,
  by name, each `{"from": origin, "values": [text, ...]}`. `values` is a list of one or more texts in every fact, so
  every fact reads the same way in any language; a fact that may hold several (a file may give several genres) keeps
  each once, in the file's order. Every value is text, as the source wrote it: numbers too (`"2"`), and the tempo
  and key a file's tags state are text the DJ's software wrote (`bpm_text`, `key_text`), never Deckie's reading,
  which stays in `grid` and `key`. The names Deckie knows (`SongFacts.known`), in the order a window lists them:

  | Name | What it is |
  |---|---|
  | `release` | the release (album, EP, single, compilation) the song is on |
  | `release_artist` | the release's own artist, kept only where it differs from the song's artist |
  | `year`, `date` | four digits; and the whole date as written when the source gives more than the year |
  | `original_year`, `original_date` | the same for the first release, when the source says this is a later one |
  | `label`, `catalog_number` | the record label, and its number for the release |
  | `genre` | one or more |
  | `track_number`, `track_count`, `disc_number`, `disc_count` | the song's number on the release and how many songs it has; the disc's number in a set and how many discs |
  | `composer`, `lyricist`, `remixer`, `producer`, `original_artist` | people, one or more each |
  | `isrc`, `barcode` | the recording's code (one per version), and the release's UPC or EAN |
  | `bpm_text`, `key_text` | the tempo and the key the file's tags state, as written |
  | `comment`, `grouping`, `mood` | as the DJ or their software wrote them |
  | `subtitle` | the tag standards' line under the title (ID3's `TIT3`), kept apart from `ident.version` |
  | `compilation` | `1` when the source marks the release as a compilation |
  | `copyright`, `language` | as written |

  A name is lower-case letters, digits and `_`, starting with a letter; a reader ignores a name it does not know, so
  a later fact is added without a new version. The title, the artist and the version are never facts: they stay in
  `ident.title`, `ident.artist` and `ident.version`, named as before (D30).
- **`file.other_tags`**, an object, inside `file` beside `tag_bpm`, the other fact about the file: everything else the
  file's text tags say, so nothing is thrown away. `formats` is the tag formats read, in the order read (`id3v2.2`,
  `id3v2.3`, `id3v2.4`, `id3v1`, `vorbis`, `riff-info`, `aiff-text`, `mp4`); `tags` is each text tag Deckie has no
  fact for, by **the tag's own name** as the file has it (an ID3 frame's four letters, `TXXX:<description>` and
  `COMM:<description>` for ID3's described frames, a Vorbis key as written, a RIFF INFO item's four letters, an MP4
  atom's name, `----:<mean>:<name>` for iTunes' free-form atoms) to its values, a list as in a fact; and `left_out`
  counts what was not kept, by reason (below). Its origin is always the file's tags. It is there when the file's
  tags gave a fact, another tag or something left out, and left out otherwise (the formats alone say nothing).

**Where a fact came from** (`from`): `tag` (the file's tags), `cdtext` (a music CD's CD-Text), a DJ program by the
names `key.source` already uses (`rekordbox-xml`, `traktor`, `engine-dj`, `serato`, `virtualdj`: that program's
library on the computer, or for `rekordbox-xml` also the collection export given to the builder), `user` (the DJ, in
Desk), and **`lookup:<service>`** for a lookup the DJ asks for later (note on D30), naming its service
(`lookup:musicbrainz`). An origin is letters, digits, `-`, `_`, `.` and `:`, 1 to 64 bytes; a reader shows one it does
not know as it is.

**Which source wins** (`SongFacts.rank`), one value per fact: the DJ, then the file's tags, then a DJ program's
library (the most recently written first, as for the key), then the disc, then a lookup. So a lookup fills only what
nothing else gives, and nothing but the DJ replaces the DJ's own entry. Reading a source again replaces the facts that
source gave before (a file's tags: every `tag` fact and `file.other_tags`; a library read now: that program's), and
keeps the rest; a file that is not there keeps what its tags gave last time. A DJ's entries live in Desk's storage
with the DJ's name fixes (`corrections.json`) and are put back after every read, so they survive it, as name fixes do.

**Bounds**, so a tag can never swell a crate file (`SongFacts`): text only (a value that is not plain text, with a
control character other than a tab or a line break, is data and left out); a value at most **1,024 bytes** of UTF-8
(`too_long` past it); at most **16 values** a fact or tag (`too_many` for the rest); a tag's name at most **64 bytes**
(`too_long`); the facts of one song at most **8,192 bytes**, names and values together, taken in the table's order
(`over_total` for a fact past it); and the other tags of one file at most **4,096 bytes**, taken in name order
(`over_total` for the tags past it). Never read at all, and counted: pictures (`picture`), any other data that is not
text, such as play counts, ratings, volume settings and binary ids (`binary`), and the private data DJ programs and
players keep in text tags (`private`: Serato's markers, Traktor's, iTunes' volume, gapless and database notes). Each
reason is counted once per item left out; `left_out` holds only reasons with a count. A song with the usual tags
adds 150 to 500 bytes; the most any one song can add is about 13 KB with the JSON around them.

**What the reader checks**: each fact's name is well formed and its origin is one; each fact and each other tag has
1 to 16 values, each plain text, trimmed, not empty, at most 1,024 bytes; the facts hold at most 8,192 bytes; each
tag's name is plain text of 1 to 64 bytes; the other tags hold at most 4,096 bytes; every count in `left_out` is 1 or more; and `file.other_tags`, when
there, is not empty.

An example record's two places (the rest of the record as above):

```json
"file": {..., "other_tags": {"formats": ["id3v2.4", "id3v1"], "left_out": {"picture": 1, "private": 1},
                             "tags": {"TSSE": ["LAME 3.100"], "TXXX:Crowd": ["peak time"]}}, ...},
"ident": {..., "facts": {"bpm_text": {"from": "tag", "values": ["124"]},
                         "genre": {"from": "tag", "values": ["House", "Deep House"]},
                         "label": {"from": "user", "values": ["Nervous"]},
                         "release": {"from": "tag", "values": ["Friday Night"]},
                         "track_count": {"from": "tag", "values": ["12"]},
                         "track_number": {"from": "tag", "values": ["2"]},
                         "year": {"from": "traktor", "values": ["1999"]}}, ...}
```

## Addition (Nov 13, 2026, with D29): the single-file form **proposed**

A crate file as one file, for the platforms where a package folder is only a folder. On a Mac a `.deckiecrate` is a
package: Finder, Files and AirDrop show and move it as one document. On Windows it is a plain folder, awkward to
email or to put on an iPad. The single-file form is the same crate file in one archive. **Nothing inside changes**:
the same files, with the same names and the same bytes, so everything above this section holds for both forms, and
`schema` and `min_reader` stay 1. Code: `CrateArchive` (`core/Sources/DeckieCrate/CrateArchive.swift`), with its tests
in `core/Tests/DeckieCrateTests/ArchiveTests.swift`; example: `core/fixtures/example-single.deckiecrate`, the
example crate above as one file (21,416 bytes against the package's 20,626: 790 bytes of archive tables).

- **What it is.** A zip archive in which every file is stored, not compressed (zip's method 0). The package's files
  sit in it under their paths inside the package, with "/" between names: `manifest.json`, `crate.json`,
  `bars/<id>.bin`, `style/<id>.bin`, `signatures/...`, and the apps' own files (`prefs.json`, `history/`) when the
  package had them. Names that start with a dot (`.DS_Store`) are left out.
- **Why a plain zip, stored, written by our own code.** No new dependency: writing and reading a stored zip is
  about 250 lines of Swift with a CRC-32 table, the same on macOS, Linux and Windows. Nothing is gained by
  compressing (the sidecars are binary and small; `crate.json` is 4 KB a song) and a decompressor would be the only
  hard part of a zip reader. Any zip tool opens it, so a crate file is never a black box: `unzip`, Python's
  `zipfile`, Windows Explorer and the Files app all list what is inside. Weighed and passed over: a tar file (no
  checksum of the contents, and Windows users cannot look inside), a compressed zip (needs a decompressor, ours to
  write or a dependency), a new container of our own (nothing else could open it).
- **The same name.** The file is called `<name>.deckiecrate`, like the package. A DJ has one thing called a crate
  file whichever computer made it. A reader tells the two apart by looking: a folder is the package; a file that
  starts with the zip signature (`PK`, bytes 50 4B 03 04) is the single-file form.
- **Written canonically**, like the rest of the format: `manifest.json` first, `crate.json` second, then every other
  file sorted by the bytes of its path; every time stamp is the zip format's zero (Jan 1, 1980, 00:00); the "name is
  UTF-8" flag set; no extra fields, no comments, no entries for folders. So the same contents give the same bytes on
  every platform: the committed example is rebuilt byte for byte by the test on Linux, Windows and macOS.
- **Damage is detected.** Zip keeps a CRC-32 checksum of every file (a 4-byte fingerprint of its bytes), checked on
  reading; the archive's tables at its end are checked against the headers in front of each file. A file cut short
  (a download that stopped) has no end table and is refused as "cut short"; a changed byte in a file's contents
  names that file; a damaged table is refused as damaged. The records' own checks ("What the reader checks", above)
  then run as for a package.
- **Read strictly, but not only our own writing.** A zip made by another tool reads when its entries are stored
  (folder entries, time stamps, extra fields and a comment are accepted and ignored). An entry that is compressed
  or encrypted is refused in words ("is compressed, so another program has rewritten this crate file; make it again
  with Deckie"), never guessed at. A path that would leave the package (`..`, a leading `/`, a drive letter, a
  backslash) is refused, when writing and when reading.
- **Sizes.** The zip64 extension is written and read for the count of files, which passes plain zip's 65,535 at
  about 20,000 songs with signatures. An archive of 4 GB or more is refused; a crate file is about 4 KB a song.
- **One call to read either form.** `CrateReader.read(from:)` takes a package folder or a single file and returns
  the same crate. `CrateArchive.pack(package:to:)` writes a package as one file; `CrateArchive.unpack(_:to:)` turns
  one file back into a package folder, for an app that keeps crates as packages and writes its own files into them.
- **Who writes which.** The Mac keeps writing packages (D28: Desk keeps its crates in its own storage, as packages).
  The PC builder writes the single-file form next to the music folder, and Deckie Desk on Windows and Linux writes
  it when a crate file is exported (`DeskSession.export`, since Nov 14, 2026; in its own storage Desk keeps packages
  there too). Either may be sent to an iPad.

**What the iPad app needs**, built Nov 13 (`deck-app/README.md`, "Crate files from a PC"). (1) Its reads go through
`CrateReader.read(from:)`, which takes both forms. (2) A crate file handed to the app is taken into its own storage by
`CrateImport.copy` (`core/Sources/DeckieCrate/CrateImport.swift`): a package is copied, a single file is unpacked with
`CrateArchive.unpack`, and the copy is read whole before it replaces anything, so everything after works on a package
as before; the file the DJ gave is never changed. (3) The open point is settled, in the iPad simulator: one declared
type cannot cover both forms, because a type that conforms to `com.apple.package` names folders only and the system
gives a plain file with the same extension a dynamic type of its own (the chooser showed the single files greyed out).
Two type identifiers with the **same extension** do cover both: `io.christophershannon.deckie.crate` (a package) and
`io.christophershannon.deckie.crate-file` (a plain file), and the system picks one by whether the item is a folder or
a file. So the single file keeps the name `<name>.deckiecrate`, and nothing in this format changes. Still to see on a
real iPad: AirDrop, iCloud Drive and a cable.

## The home note (D36, Nov 14, 2026; decided)

D33's reader has three answers: a key, the home note alone, and not sure. The first is a `key` block; the third is
no `key` block, which every reader understands as no key. The second could not be written: `key.camelot` is required
text and a Camelot code always names a mode, and a guessed code at a low confidence would show a mode the reader did
not find to every reader that ignores the confidence, which D16 rules out. The owner accepted the addition proposed
with D33 and named it: on screen it is the **home note** ("home note, mode open" was clunky).

**The block.** One optional block beside `key`, left out when absent (as `vocal_structure` and `hooks` are, so
every record without it keeps its bytes), with the feature name `key_home`:

- `key_home` *(key_home)*: `source` (the method, `three-answer`), `note` (the home note as the engine spells a
  key's, sharps: `A`, `C#`), `pitch_class` (0 to 11, C = 0), `camelot` (the two codes on that home note, minor
  first: `["8A", "11B"]`).

**Rules.**

- A record has `key_home` only when it has no `key` block: a key, the DJ's or Deckie's or Apple's, always replaces
  it. The validator refuses a record with both, a `pitch_class` outside 0 to 11, a `camelot` that is not the two
  codes on that pitch class in that order, and a `note` that is not its name.
- `features_present` lists `key_home` exactly when the block is there.
- `schema` and `min_reader` stay 1. A reader from before the block passes over the member (it ignores keys it does
  not know) and over the name in `features_present` (it checks only the names it knows), and sees a song with no
  key, which is true as far as it goes. Proved both ways in `KeyHomeTests` (DeckieCrateTests): a crate without the
  block is written, read and written again to the same bytes with no `key_home` in them; a crate with it reads
  through the previous reader's shape; and by hand, the reader built from the commit before this one checked a
  crate file written with the block (the check-in of Nov 14 records the run).
- **Who writes it.** The engine (0.6.0), in the builder's record, when the reader's answer is the home note alone;
  `LocalFacts.decideKey` and `ownKeysOnly` keep it when no key takes its place, remove it when a DJ's key does, and
  bring it back from the builder's records if that key goes. A record read by Apple's framework never has one.
- **The run's report** counts it apart: `keys_home_note` (songs with a home note; not counted in `keys_not_read`),
  beside `keys_not_sure` (of the songs with no key, those Deckie read and was not sure of).
- **Scoring** (`PairScoring.keyTerm`): a song with only a home note is compared as either of the two keys on it,
  whichever fits the other song better, and counts with the confidence 0.45 (the level the key block's scale already
  has for it), so a home-note fit is worth 0.725 of the same fit between two keys read with full confidence. Two
  songs with only home notes: the best of the four pairings. A song with neither a key nor a home note stays out of
  the key term, as before, and two songs whose keys were both read score exactly as before.
- **On screen** it is "Home note A". Desk's rows carry `keyState` and `homeNote`
  (docs/architecture/desk-protocol.md); the words are `homeNote`, `homeNoteHelp`, `keyDeckieNotSure`.

On the outside sets of research X2 this is 5 to 12 percent of songs, with the home note right on 61 to 82 percent of
them.

Not done, and why: allowing `key.camelot` to be null (changes a required field's type for every reader); a flag on
a block that still carries a guessed code (old readers would show the guess).

## Addition with D36 (Nov 14, 2026): covers

D36: "Covers go into the crate file... A small picture for each release, stored once, as an addition." Additive like
every addition above: no field changes name or meaning, `schema` and `min_reader` stay 1, a crate file written before
it reads as it did, and a reader that does not know it ignores the new key and the new folder and shows no cover.
Code: `CrateTrack.File.cover`, `CrateFormat.cover*` and the checks in `CrateReader` and `CrateWriter` (DeckieCrate);
`Cover` (DeckieCovers), which makes the thumbnail; tests in `CoversFormatTests` and `DeckieCoversTests`.

```
Example.deckiecrate/
  covers/<sha256 of the source picture>.jpg     one small JPEG for each distinct picture
```

- **`file.cover`**, text: the SHA-256 hash (64 lower-case hexadecimal characters) of the **picture the cover was
  made from**, exactly as its bytes were found (in the file's tag, or the picture file beside the music). It names
  the thumbnail, `covers/<hash>.jpg`. **Left out when the song has no cover**, never written as null, so a record
  without one keeps its bytes. It sits in `file` because it is a fact about the file, like `file.other_tags`, where
  the picture is still counted as left out of the text tags (`left_out.picture`): the tags hold no picture; the
  cover is its own thing.
- **Stored once.** Songs of one release carry the same picture, byte for byte, so they name the same hash and share
  one file. Two pictures that only look alike (another scan, another size) are two covers.
- **Why the hash is the source picture's and not the thumbnail's.** The thumbnail is made by different code on
  different systems (below), and two encoders never give the same bytes. Named by the source, one release has one
  entry whichever computer read which song, and a crate file merged from two computers does not double its covers.
- **One size: the longest side 128 pixels**, the shape kept, never scaled up (a 50-pixel picture stays 50). Why 128:
  a cover in a list is about 48 to 64 points across, which is 96 to 128 pixels on the screens Deckie runs on, so
  128 is sharp there and a little soft only if shown larger. Measured, a cover is 2 to 5 KB (below), against about
  4 KB of everything else for a song. A second, larger size for a now-playing view would cost four times as much
  for something no screen shows yet; if the design pass wants it, it is a later addition beside this one
  (`covers/<hash>@2.jpg`), not a change to it.
- **A baseline JPEG at quality 80**, sRGB assumed, anything see-through laid over white, no metadata carried over
  (no camera data, no embedded profile, no text). A reader may rely on: a JPEG; at most 128 pixels a side; at most
  **24 KB** (`CrateFormat.coverMaxBytes`).
- **Limits on the source.** A picture is made into a cover only if it is a JPEG or a PNG, at most 32 MB and at most
  8,192 pixels a side; its size in pixels is read before any of it is decoded. A picture that is damaged, of
  another kind (GIF, WebP, BMP), or over those limits gives **no cover**: the song is in the crate file as any
  other, without `file.cover`, and the builder counts such pictures in its summary. A thumbnail that came out over
  24 KB is made again at quality 60, then 40, then given up; with scaling by area this has not happened on any test
  picture (512 pixels of random colour give 5.4 KB).
- **No cap for the crate file as a whole.** The cap per cover bounds it: at most 24 KB for each distinct picture,
  and in practice 2 to 5 KB.
- **The single-file form** carries the folder as it carries every folder: `covers/<hash>.jpg` entries, stored, after
  `crate.json` in path order. Nothing new.
- **Where the picture comes from**, in this order (the builder, `core/README.md`): the file's own front cover (ID3
  `APIC`, FLAC `PICTURE`, MP4 `covr`); else a picture file beside the song, in its own folder: `cover`, `folder`,
  `front`, `albumart` or `album`, as `.jpg`, `.jpeg` or `.png`, in that order, whatever the case of the name.
- **Writing.** The thumbnail must be in the package before the records that name it are written; the writer refuses
  a record whose cover is missing, and **deletes every `covers/*.jpg` that no record names**, so taking the last
  song of a release out of a crate takes its cover out, as sidecars go with their songs.
- **Which system makes it.** On Linux and Windows the thumbnail is decoded by stb_image, scaled by whole-number
  area averaging and encoded by stb_image_write (`DEPENDENCIES.md` section 11): the same bytes on both, checked by
  a hash pinned in the tests. On Apple's systems it is made by the system's image code, so the Mac's bytes for the
  same picture differ; the name does not.

**What the reader checks:** `file.cover` is 64 lower-case hexadecimal characters; `covers/<hash>.jpg` is in the crate
file, starts as a JPEG does and is at most 24 KB. A cover in the folder that no record names is ignored. It does not
decode the picture.

**What a reader app needs** (the Mac window and the iPad app; not built here): read `file.cover`; when it is there,
show `covers/<hash>.jpg` from the package (or, for the single-file form, after `CrateArchive.unpack`, or straight
from `CrateArchive.read(file)["covers/<hash>.jpg"]`); when it is not, show its placeholder. An app that writes a
crate file itself calls `Cover.make(picture)` and `cover.write(into: package)` before `CrateWriter.write`.

## Addition with D35 (Nov 14, 2026): a song's fingerprint

D35, decided by the owner on Nov 14, 2026: recognising what is playing uses a fingerprint of Deckie's own, so the
crate file carries one for every song, made by every builder on every computer. A **fingerprint** is a small summary
of a song's sound from which a few seconds heard in a room can be matched to the song; Deckie's is the song's
**constellation**, the points of its spectrogram (time against frequency) that are louder than everything around
them, as the recognition trial describes (`docs/research/w2-own-recognition-trial.md`). Until now a crate file could
be recognised from only through `signatures/`, which only an Apple device can make. Additive like D27 and D34: no
field changes name or meaning, `schema` and `min_reader` stay 1, a crate file written before it reads with no
fingerprints and writes back byte for byte, and a reader that does not know it (it ignores keys and files it does
not know) opens a crate file that has it and shows every song as before. Code: `CrateTrack.Fingerprint`
(`CrateModel.swift`), the constellation and its bytes in `Landmarks`
(`core/Sources/DeckieRecognition/Landmarks.swift`), the making in the engine (`Analyser.swift`) and for older
records in the builder (`Builder.fingerprint`); tests in `core/Tests/DeckieCrateTests/PrintTests.swift`.

Two places, in the manner of `signatures`: a file per song, and a note of it on the record.

- **`prints/<id>.dkl`**, beside `signatures/`: the song's fingerprint, exactly the bytes `Landmarks.encoded()` gives.
  They start with the four letters `DKL2`; then the number of frames analysed (a frame is 16 ms of the song) and the
  number of points, each a 32-bit little-endian integer; then each point in time order: the frames since the point
  before, as a variable-length number (7 bits a byte, the low bits first, the top bit set on every byte but the
  last), and two bytes, little-endian, holding the point's frequency in the low 14 bits (in 1/4096 of an octave
  above 300 Hz) and its strength, 0 to 3, in the top two. About 3 bytes a point and 96 bytes for a second of music:
  about 23 KB for a four-minute song, which is several times the rest of that song's record.
- **`print`**, a key on the song's record, an object: `format` (the text `DKL2`, the file's first four letters);
  `version` (a whole number, 1 now: the fingerprint's own version, apart from the crate format's `schema`, so the
  way a song is fingerprinted can change without older crate files or older readers breaking); `points` (the number
  of points in the file); `made_by` (the device that made it, a model label as a signature's `made_by` and
  `analysis.device` are, never a user's name for the device); `made_at` (UTC, to the second). **Left out when the
  song has no fingerprint, never written as null**, as `ident.other_places` is, so every record without one keeps
  its bytes and the example crate is unchanged. It is not a feature: `features_present` does not list it.

**A later version.** A reader that meets a `print` whose `version` is higher than the highest it knows ignores that
print, whatever else it holds, and treats the song as having no fingerprint; it does not open the song's file in
`prints/` and does not refuse the crate file. The song is still shown, and still recognised by a signature if it has
one. A writer writes only versions it knows, so such a reader that writes the crate file again writes that song
without a fingerprint.

**Who makes it.** Every builder, once per file: the Windows and Linux engine makes the fingerprint in the analysis,
from the audio it has just decoded (the channels averaged, at the file's own rate), so Deckie Desk's run,
`deckie-build` and `deckie-make` all write it and no song is decoded a second time for it. The builder keeps it in
its work folder beside the song's record (`records/<id>.dkl`), which in Deckie Desk is the store shared by every
crate, so a file in several crates is fingerprinted once. A record made before the fingerprint gains it on the next
run from one decode of the file, with no second analysis; that is why the engine's `version` did not go up for it.
An entry kept from an earlier crate file has none until its file is read again, for this crate or, in Deckie Desk,
for any other. Building a crate file again keeps a fingerprint it already has.

**What a song can be recognised from.** A song with a fingerprint or a signature can be named from its sound; a song
with neither cannot yet. That is the count Deckie Desk shows as "can't be recognised yet"
(`CrateTrack.canBeRecognised`).

**In the single-file form** the fingerprints sit in the archive under `prints/<id>.dkl`, like every other file of
the package. **The writer** writes each fingerprint's file from the record's, and deletes the `.dkl` file of a song
that has left the crate or no longer has a fingerprint, as it deletes the `.bin` sidecars of removed songs. A file
in `prints/` that no record lists is treated as a sidecar left behind is: the reader ignores it, and the next write
deletes it.

**What the reader checks** for it: `format` is `DKL2`; `version` is 1 or more (and at most the reader's own, or the
print is ignored, above); `made_by` and `made_at` are not empty; the listed file is in the package, starts with
`DKL2`, and reads whole as a constellation (the count of points is one the file's length can hold, every point is
complete, and nothing follows the last); and the points in it number exactly `points`. For example:
`prints/0327cf1c94.dkl (track 0327cf1c94): holds 5112 points but tracks[2].print.points is 5113`.

An example record's key (the rest of the record as above):

```json
"print": {"format": "DKL2", "made_at": "2026-11-14T09:00:00Z", "made_by": "linux-x86_64", "points": 5112, "version": 1}
```

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
11. Accepted Nov 13, 2026 (D27, the owner's yes). `ident.other_places`: the entry's other places, each `disc`, `folder`
    and `track`, left out when empty; no version raised.
12. Proposed Nov 13, 2026 (with D29). The single-file form: the same files in one uncompressed zip under the same
    name, written and read by `CrateArchive`; `CrateReader.read(from:)` takes either form. Nothing inside changes;
    no version raised. The iPad's document types cover both forms with one extension (two type identifiers, settled
    Nov 13 in the simulator).
13. Decided Nov 14, 2026 (D34, the owner's yes to sending every fact). `ident.facts` (the facts Deckie knows, each with
    its origin) and `file.other_tags` (the rest of the file's text tags, within bounds, with what was left out
    counted), both left out when empty; no version raised. The fact names, the origins, the order of which source
    wins and the bounds are this format's choices, made with D34.
14. Accepted Nov 14, 2026 (D36, the owner's yes). `key_home`: the home note alone, an optional block beside `key`,
    present only when there is no `key` block, left out when absent; no version raised ("The home note", above).
15. Addition with D36 (Nov 14, 2026, the owner's "lets add them"). Covers: `file.cover` (the SHA-256 of the source
    picture, left out when none) and `covers/<hash>.jpg`, one 128-pixel JPEG of at most 24 KB for each distinct
    picture; no version raised.
16. Decided Nov 14, 2026 (D35, a fingerprint of Deckie's own). `prints/<id>.dkl`, the song's fingerprint, and the
    record's `print` (`format`, `version`, `points`, `made_by`, `made_at`), left out when there is none; a print of
    a later `version` is ignored, not refused; no version of the crate format raised. The file's name and the
    record's key are this format's choices, made with D35.
