# The explainer film's source

The film on the page (`site/assets/deckie-explainer.mp4`) is drawn by `film.js`: a page with one canvas that paints
any moment of the film on request, rendered frame by frame in a headless browser and encoded with ffmpeg. The plan
it follows is `shotlist.md`. The research behind it is `docs/research/v-explainer-video-and-page.md`.

## What is here

- `film.js`, `film.json`: the film's sixth cut (76 s, Nov 21) and its length. Timing is in beats at 120 BPM. One
  switch at the top, `BOOTH_IN_DESK`, takes out the Booth-in-Desk shot (55 to 59 s).
- `v1/`, `v2/`, `v3/`, `v4/`, `v5/`, `v6/`: the first cut (84 s), the second (60 s), the third, fourth and fifth (76 s, before the
  round-six, seven and eight changes) and the cut published on Nov 12 (76 s, "Deckie Booth on your iPad"): each
  with its `film.js`, `film.json` and `shotlist.md`, kept for the record.
- `words/`: the script words ("you", "your", "Deckie", and "Desk" and "Booth" for the headers) as the film writes them. `rasterise.mjs` draws each
  word in the browser; `skel.py` finds its centreline; `strokes.py` holds the pen path for each word, stroke by
  stroke, and writes the `*_map.png` files (for every pixel, the moment the pen passes it) and `words.json`.
- `sound/`: `score.py` synthesises the soundtracks (A house, B scratch, C jackin', and D, in between, which the film
  uses) from nothing;
  `analyze.py` draws a picture of each (spectrogram, the film's accents, level over time). The film uses D.
- `type-trials/`: the scripts that make the Nov 12 comparison sheets of headline faces.
- `shotlist.md`: every shot, its time, what is on screen and the words.
- `capture/make_demo_crate.py`: makes the demo crate file from a copy of a crate file (invented names, same analysis).
- `capture/booth.sh`: records Deckie's walk-through in the iPad simulator (a Debug build, for its hooks; the
  simulator records with the Mac locked).
- `capture/desk.sh`: Deckie Desk's own stills (`--snapshot`); the Mac must be unlocked. Since Nov 23 the film uses two
  stills of the Mac window with the crate "Gig Friday" (the twelve songs of `desk-quickstart/capture/songs.py`, read
  into a scratch Desk with `--add-music`): `site/assets/desk.jpg` (its songs) and `site/assets/desk-sources.jpg` (the
  Sources panel), made by `"Deckie Desk" --film-walk <out> "Gig Friday"` (`desk-app/Desk/Sources/FilmWalk.swift`) and
  cut to the window below its toolbar, 1800 by 1125 pixels from (0, 100), scaled to 1600 by 1000. Desk draws those
  frames itself; without Screen Recording permission for Deckie Desk the toolbar's buttons do not draw, hence the cut.
- Booth in Desk (shot 16): Desk's pages (`desk-web/`) in headless Chrome with the real engine, the crate file
  imported and its Booth switch pressed, the engine hearing a song of the crate through its stand-in input
  (`DECKIE_BOOTH_SOUND`). It is Desk's quick-start capture (`desk-quickstart/capture/live.mjs` and `clock.js`) cut down to
  that: the run replaced by `crate.import`. Two stills are used, `assets/deskbooth/wait.jpg` and `named.jpg`.
- `capture/vocab.mjs`: the dictionary stills from `docs/vocabulary/index.html`.
- `capture/dictionary.mjs`: the dictionary stills the film uses now, from the built site, with the clock pinned so
  the word of the day does not change (letter V, section 7m).

## What is not here, on purpose

No captured frames, no audio and no crate file: they are large, and the crate file is made from the owner's. The
captures are remade with the scripts above. Working pictures are not committed either: the word maps
(`words/*_map.png`, written by `strokes.py`), the sound pictures (`sound/*.png`, by `analyze.py`), the contact
sheets and each round's screenshots (`round*/`), and the films with the trial soundtracks
(`site/assets/variations/`). They stay on the Mac that made them. The canvas harness, the frame renderer and the sound scripts belong to the
motion-reel skill and are not copied into this repository.

## Rebuilding

In an empty work folder outside the repository, with Node, Playwright's Chromium, ffmpeg and uv installed:

1. `node <skill>/scripts/scaffold.mjs deckie --duration 76 --formats 16x9`, then copy `film.js` and `film.json` over
   the scaffold's, and Inter from `site/fonts/` to `deckie/fonts/display.woff2` and `ui.woff2`. Pacifico is not loaded
   by the film as a font: its three words come from the maps in `words/`, copied to `deckie/assets/words/`.
2. Captures into `deckie/assets/`: `booth/f0000.jpg` onward (booth.sh), `vocab2/d_top.png` and `d_echo.png`
   (dictionary.mjs, against the site served locally), `deskbooth/wait.jpg` and `named.jpg` (Booth in Desk, at
   1600 x 1000), and `desk/` with Desk's still plus a `desk.json` naming it and the table's camera:
   `{"images":{"desk_open":"assets/desk/desk.jpg","desk_discs":"assets/desk/desk-sources.jpg"},"cam":[[0,[494,312,1.62]]]}`.
   The word maps: `node words/rasterise.mjs site/fonts/pacifico.woff2 deckie/assets/words`, then `uv run
   words/skel.py` and `uv run words/strokes.py` on that folder.
3. Music and beat grid: `uv run <skill>/scripts/beats.py deckie --synth --bpm 120 --tonic A --mode minor --flavor house --drop 8 --seed 7`
   for `beats.json`, then soundtrack D over its music: `MOTION_REEL_SKILL=<skill> uv run sound/score.py D deckie/audio/music.wav`.
4. Picture: `node <skill>/scripts/render.mjs --film deckie --video-only --workers 2` (about eight minutes).
5. The final file: `node <skill>/scripts/mix.mjs deckie` (soundtrack D carries its own accents, so there is no
   `sfx.wav`; mix.mjs masters to -14 LUFS and muxes).
6. The fifteen-second clip: `ffmpeg -i final.mp4 -t 15 -af afade=t=out:st=14.4:d=0.6 deckie-15s.mp4`.

One heavy job at a time; run the render with `nice -n 19`.

## Nov 23, 2026: Desk's shots, spliced into the master

Only shots 5 to 7 changed, so only 12.2 to 28.0 s was rendered again (`render.mjs --range 12.2:28 --video-only`; both
ends are cuts where the master has a key frame). Its work folder had the new Desk stills, the word maps made again
(`words.json` came out byte for byte the same), and for frames 90 to 199 of `booth/` one still of Deckie in the
iPad simulator (a Debug build, the crate file "Gig Friday" opened with `deck://crate`, landscape, the status bar at
9:41), the state the recording showed there. The new span was joined to the master's frames before and after it and the
picture encoded once more as `render.mjs` encodes (x264, CRF 16, slow); the sound is the master's, copied. A rendered
frame at 12.2 s matched the master's to within the encoder's noise. The fifteen-second clip and the poster (32.5 s)
show nothing that changed and were left as they were.

## The site

The pages, the build and how it is published are in `site/README.md`.
