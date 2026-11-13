# The explainer film's source

The film on the page (`site/assets/deckie-explainer.mp4`) is drawn by `film.js`: a page with one canvas that paints
any moment of the film on request, rendered frame by frame in a headless browser and encoded with ffmpeg. The plan
it follows is `shotlist.md`. The research behind it is `docs/research/v-explainer-video-and-page.md`.

## What is here

- `film.js`, `film.json`: the film (fifth cut, 76 s) and its length. Timing is in beats at 120 BPM.
- `v1/`, `v2/`, `v3/`, `v4/`, `v5/`: the first cut (84 s), the second (60 s), and the third, fourth and fifth (76 s, before the
  round-six, seven and eight changes): each with its `film.js`, `film.json` and `shotlist.md`, kept for the record.
- `words/`: the script words ("you", "your", "Deckie", and "Desk" and "Booth" for the headers) as the film writes them. `rasterise.mjs` draws each
  word in the browser; `skel.py` finds its centreline; `strokes.py` holds the pen path for each word, stroke by
  stroke, and writes the `*_map.png` files (for every pixel, the moment the pen passes it) and `words.json`.
- `draw-in-contact-sheet.png`: frames from the third cut with each script word part-way through its strokes.
- `sound/`: `score.py` synthesises the soundtracks (A house, B scratch, C jackin', and D, in between, which the film
  uses) from nothing;
  `analyze.py` draws the picture of each (`sound-A.png` and so on: spectrogram, the film's accents, level over time).
  The films with each soundtrack are in `site/assets/variations/`. The main film uses D.
- `round8-header-contact-sheet.png`: the section headers with the smaller grey qualifier, across the film.
- `round7-contact-sheet.png`: frames from the fifth cut: every caption block at rest (to check line breaks), both
  app-name headers part-way through being written, the name card and the end card.
- `round6-contact-sheet.png`: frames from the fourth cut: the two-line shot, the name card, every section header
  with a reference line at its fixed height, the 1:07 shot and the end card.
- `type-trials/`: the Nov 12 comparison sheets of headline faces, and the script that makes them.
- `shotlist.md`: every shot, its time, what is on screen and the words.
- `capture/make_demo_crate.py`: makes the demo crate file from a copy of a crate file (invented names, same analysis).
- `capture/booth.sh`: records the booth walk-through in the iPad simulator.
- `capture/desk.sh`: Deckie Desk's own stills (`--snapshot`); the Mac must be unlocked.
- `capture/vocab.mjs`: the dictionary stills from `docs/vocabulary/index.html`.
- `capture/dictionary.mjs`: the dictionary stills the film uses now, from the built site, with the clock pinned so
  the word of the day does not change (letter V, section 7m; that round's sheets are in `round14/`).

## What is not here, on purpose

No captured frames, no audio and no crate file: they are large, and the crate file is made from the owner's. The
captures are remade with the scripts above. The canvas harness, the frame renderer and the sound scripts belong to the
motion-reel skill and are not copied into this repository.

## Rebuilding

In an empty work folder outside the repository, with Node, Playwright's Chromium, ffmpeg and uv installed:

1. `node <skill>/scripts/scaffold.mjs deckie --duration 76 --formats 16x9`, then copy `film.js` and `film.json` over
   the scaffold's, and Inter from `site/fonts/` to `deckie/fonts/display.woff2` and `ui.woff2`. Pacifico is not loaded
   by the film as a font: its three words come from the maps in `words/`, copied to `deckie/assets/words/`.
2. Captures into `deckie/assets/`: `booth/f0000.jpg` onward (booth.sh), `vocab/v_*.png` (vocab.mjs), and
   `desk/` with Desk's stills plus a `desk.json` naming them and the camera moves (see the end of film.js).
3. Music and beat grid: `uv run <skill>/scripts/beats.py deckie --synth --bpm 120 --tonic A --mode minor --flavor house --drop 8 --seed 7`.
4. Picture: `node <skill>/scripts/render.mjs --film deckie --video-only --workers 3` (about seven minutes).
5. Sound and the final file: `node <skill>/scripts/sfx.mjs deckie`, then `node <skill>/scripts/mix.mjs deckie --sfx-db -3`.
6. The fifteen-second clip: `ffmpeg -i final.mp4 -t 15 -af afade=t=out:st=14.4:d=0.6 deckie-15s.mp4`.

One heavy job at a time; run the render with `nice -n 19`.

## The site

Both pages share one stylesheet, `site/site.css`, whose values come from Deckie Booth's Simple view (letter V,
section 7i; before and after screenshots and five film stills in the new look are in `round10/`).

`site/build.sh` assembles `site/dist/`, the folder that goes on the host: the two pages, the files they use, the
film at web weight, `robots.txt`, `sitemap.xml`, `llms.txt`, favicons and an optional `.htaccess`. This folder
(`site/film/`), `site/assets/variations/` and the contact sheets are not part of it.
