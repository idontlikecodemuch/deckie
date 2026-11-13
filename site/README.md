# The Deckie site

What is published at https://deckie.io: a coming-soon home page, a dictionary of DJ words, and the explainer film.
Plain HTML, CSS and JavaScript. No framework, no server code, nothing fetched from another site.

The research behind every choice is `docs/research/v-explainer-video-and-page.md` (letter V). The decisions are D22
and D23 in `docs/product/00-decisions.md`.

## The three parts

| Part | What a visitor sees | Where it is made |
|---|---|---|
| Home page | https://deckie.io/ | `index.html`, written from the copy document `home-copy.md` |
| Dictionary | https://deckie.io/dictionary/ | `dictionary/build.py`, from `docs/vocabulary/terms.json` |
| Film | The 76 second explainer in the home page's hero | `film/` (see `film/README.md`) |

## What is here

- `home-copy.md`: the home page's words, as a document. Change the words here first, then the page. It also records
  what was cut and why.
- `index.html`: the home page. Its head carries the title, description, share-card tags and the structured data
  (schema.org SoftwareApplication) that search engines read.
- `site.css`, `site.js`: shared by both pages. The look comes from Deckie Booth's Simple view: one flat dark
  background, rounded cards, one lavender accent. `site.js` draws the moving waveform behind the page, the tile
  animations, the wordmark that sticks in the bar, and the dictionary panel's card swap.
- `home_terms.py`: copies five words from the built dictionary into the home page's dictionary panel, so the two
  cannot drift apart. `build.sh` runs it.
- `dictionary/`: `build.py` writes `index.html` from the vocabulary; `dictionary.css` and `dictionary.js` style it
  and add search, the A to Z bar, topic chips and the word of the day. The page reads completely with scripts off.
- `share/`: the two link-preview cards as small pages (`home.html`, `dictionary.html`, `base.css`). The pictures
  made from them are `assets/share-home.jpg` and `assets/share-dictionary.jpg`, 1200 by 630.
- `assets/`: the film (`deckie-explainer.mp4`, the master), its first fifteen seconds (`deckie-15s.mp4`), the
  poster, and the screen pictures the page uses. Every screen shows a demo crate file with invented song and artist
  names.
- `icon.svg`, `icon-line.svg`, `favicon.*`, `apple-touch-icon.png`: the app's icon, redrawn as a vector from the
  booth app's icon.
- `fonts/`: Inter and Pacifico with their licences. Pacifico is used only for "you", "your" and "Deckie".
- `llms.txt`: the site's facts as plain text, for assistants that read sites. `robots.txt`, `sitemap.xml`,
  `404.html`.
- `.htaccess`: the 404 page, www to the bare address, http to https, file types and cache lifetimes.
- `film/`: the film's source, shot list, sound and capture scripts.

## Changing something

**Words on the home page.** Edit `home-copy.md`, then `index.html`. If a fact changes, change it in `llms.txt` and
the structured data in the page's head too: the three say the same things.

**A dictionary word.** Edit `docs/vocabulary/terms.json`, then run:

```
python3 site/dictionary/build.py
```

It rewrites `site/dictionary/index.html` and keeps the internal page `docs/vocabulary/index.html` in step.
`--check` changes nothing and fails if either is out of date. A term with `"public": false` stays off the public
page. The fields are explained at the top of `build.py`.

**A share card.** Edit the page in `share/`, then render it at 1200 by 630 with headless Chrome and save it as the
JPEG in `assets/`:

```
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --window-size=1200,630 --screenshot=site/share/home.png site/share/home.html
```

**The film.** See `film/README.md`. A new render replaces `assets/deckie-explainer.mp4` and `assets/deckie-15s.mp4`.

## Building and publishing

```
site/build.sh
```

This assembles `site/dist/`, the folder that goes on the host: the two pages, the files they use, and the film
re-encoded at web weight (about 10 MB). It needs ffmpeg. An earlier build is set aside as `dist-old-<time>`, never
deleted. The script ends by listing every file with its size and fails if the home page points at a file that is
not in the build.

`site/dist/` is uploaded to the host over FTPS. The login is not in this repository and is never committed. After
an upload, check the live pages, the film, the 404 page and both redirects, and compare file sizes with the build.

Published Nov 12, 2026: 28 files, 13,282,076 bytes.

## What is not committed, on purpose

`dist/` and `dist-old-*/` (build output), `assets/variations/` (the soundtrack trials), the film's working
screenshots and contact sheets, and the rendered PNGs in `share/`. All are remade by the scripts here.

## Rules that apply to the site

- It names no person, with one exception: the credit, "Made by Christopher Shannon and App Hold Media".
- No real song, artist or playlist appears. Screens show the demo crate file.
- The film's music was made for the film. No DJ's music is in any public file.
- Product copy does not say "AI". See `docs/product/voice.md`.
- Line breaks in headlines and captions are set by phrase: no line of one word, and a new sentence never leaves its
  first word alone at the end of the line before.
