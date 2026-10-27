# Two-disc pool build scripts

Copied from the Claude session scratchpad so they survive. Run everything from this folder (`cd "_pool build"`):

- `newfiles/probe_new.py` — probe new audio in the playlist folder (tempo tag, aubio fallback, length, size).
- `newfiles/pool_build.py` — builds `newfiles/pool.json` (every candidate with disc S/M, folder, rec flag, notes). The user's selection baseline is `newfiles/selection_v1.json`; swaps, moves and adds are near the end of the file.
- `newfiles/page_build.py` — builds the Two-Disc Pool page (`twodisc/two-disc-pool.html`, published at https://claude.ai/artifact/5BqVJWSzeoyD34Qa8TJGpY); `--local` writes the local copy with the audio player next to the MP3s.
- `newfiles/mike_data.py` — builds `../Mike page/data.js` + `data.json` and hard-links the chosen MP3s into `../Mike page/tracks/`. Alternates are the ALT1/ALT2 lists at the top.
- `newfiles/apply_mike.py "Mike final mix.txt" [--write]` — reads the text Mike shares back from the page and prints adds/removes; `--write` stores `selection_v2.json`.
- `shop/` — the Remix Shopping List page and its items; `newfiles/club_*.py` — the club-edit search data.

Earlier four-disc build scripts (`build_cds.py`, `bpm_final.json`, `verify-disc.sh`, `tracklist_pdf.py`) stay in the playlist folder root.

## Two-disc CD build (CDs v3)
- `build_two_discs.py` — builds `../CDs v3/` from `newfiles/pool.json` (rows with `rec: true`): `CD1 Singalongs/` and `CD2 Mix-ins/` with numbered BPM folders, files named `NN [H ]<deck_name>.mp3` (deck_name reused from `newfiles/mike_data.py`; `H` = Halloween), MP3 stream copied without re-encoding, ID3v2.3 tags (artist, title, TBPM, album, track, genre Halloween), cover art stripped. Then the ISOs in `../CDs v3/ISO/` (ISO 9660 + Joliet via `hdiutil makehybrid`), a read-only mount check of every file name and size, `MANIFEST.md`, and `Track lists - CD1 and CD2.html/.pdf` (one page per disc + both side by side; PDF via Chrome headless, cupsfilter fallback).
- Re-run any time after changing the selection: `cd "_pool build" && python3 build_two_discs.py` (it wipes and rebuilds the disc folders, ISOs and printouts). `--no-iso` skips the ISO step.
- After burning, check each disc from Terminal: `"../CDs v3/verify-disc.sh" 1` (or `2`).

## TODO before the next burn: loudness normalisation (noted Oct 23, 2026)
The v3 discs burned on Oct 23, 2026 (two copies each) were built with the files untouched, and Mike had already
mentioned uneven volume on the previous set. A scan of all 90 files (`../CDs v3/loudness-scan.tsv`, sorted quietest
first) shows integrated loudness from -14.2 to -2.3 LUFS: most tracks sit near -8, eleven classics are 3 to 6 dB
quieter (Time Warp, Dracula, Vogue, Born Slippy, Lost In Music, Children, Blue Monday Mashup, Push The Feeling On,
X-Files, Demons, Barbie Girl), Justice "We Are Your Friends" is 6 dB louder than everything else, and some adjacent
tracks in one folder jump 5 to 8 dB. Chris chose to hold the re-burn until he has more blanks.

Fix it in `build_two_discs.py` as a step between copying and tagging, and apply it to every track, not just the
outliers:
- Target about -10 LUFS integrated with a -1 dBTP ceiling. That turns the loud modern masters down (lossless in
  effect) and lifts the quiet classics 2 to 4 dB, which is as far as their peaks allow without limiting.
- Preferred tool: `mp3gain` (`brew install mp3gain`), which changes the MP3 global gain losslessly in 1.5 dB steps.
  Run it with `-s s` so it writes no APE tag (the CDJ files must stay ID3v2.3 only) and `-k` so it never clips.
- Fallback: ffmpeg two-pass `loudnorm` with `linear=true` (measure first, then normalise with the measured values),
  re-encoding to CBR 320; one extra lossy generation, acceptable at 320.
- Never normalise the originals in the playlist folder in place: `../Mike page/tracks/` are hard links to them, so
  an in-place change would alter the live page copies too. Normalise into the `CDs v3` build output only.
- Re-scan the built folders afterwards (the ebur128 one-liner in `../CDs v3/loudness-scan.tsv`'s header comment is
  not stored; use `ffmpeg -i f -af ebur128=peak=true -f null -`) and expect a spread of about 2 dB, then rebuild the
  ISOs and burn four new discs with the same hdiutil command and verify-disc.sh.
