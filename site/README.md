# The Deckie site

What is published at https://deckie.io: a coming-soon home page, a dictionary of DJ words, the explainer film, the
demo crate's page and the privacy policy.
Plain HTML, CSS and JavaScript. No framework, no server code, nothing fetched from another site.

The research behind every choice is `docs/research/v-explainer-video-and-page.md` (letter V). The decisions are D22
and D23 in `docs/product/00-decisions.md`.

## The parts

| Part | What a visitor sees | Where it is made |
|---|---|---|
| Home page | https://deckie.io/ | `index.html`, written from the copy document `home-copy.md` |
| Dictionary | https://deckie.io/dictionary/ | `dictionary/build.py`, from `docs/vocabulary/terms.json` |
| Film | The 76 second explainer in the home page's hero | `film/` (see `film/README.md`) |
| How-to | Deckie Desk's quick start (57.6 s, no sound) in the home page's "Desk reads your crate", beside its four steps | Made for Desk (D46) in `desk-quickstart/`; the 720p film and poster are copied from `desk-web/quick-start/` to `assets/deckie-desk-quick-start.mp4` and `assets/quick-start-poster.jpg` |
| Demo | https://deckie.io/demo/: plays the demo crate's songs out loud, for the iPad app's "Try the demo crate" | `demo/` (see `demo/CREDITS.md`) |
| Privacy | https://deckie.io/privacy/: the privacy policy, linked from every page's footer | `privacy/`, from `docs/product/testflight/privacy-policy.md` |

## What is here

- `home-copy.md`: the home page's words, as a document. Change the words here first, then the page. It also records
  what was cut and why.
- `index.html`: the home page. Its head carries the title, description, share-card tags and the structured data
  (schema.org SoftwareApplication) that search engines read.
- `site.css`, `site.js`: shared by both pages. The look comes from the Simple view of Deckie, the iPad app: one flat dark
  background, rounded cards, one lavender accent. `site.js` draws the moving waveform behind the page, the tile
  animations, the wordmark that sticks in the bar, and the dictionary panel's card swap.
- `home_terms.py`: copies five words from the built dictionary into the home page's dictionary panel, so the two
  cannot drift apart. `build.sh` runs it.
- `dictionary/`: `build.py` writes `index.html` from the vocabulary; `dictionary.css` and `dictionary.js` style it
  and add search, the A to Z bar, topic chips and the word of the day. The page reads completely with scripts off.
- `share/`: the two link-preview cards as small pages (`home.html`, `dictionary.html`, `base.css`). The pictures
  made from them are `assets/share-home.jpg` and `assets/share-dictionary.jpg`, 1200 by 630.
- `assets/`: the film (`deckie-explainer.mp4`, the master), its first fifteen seconds (`deckie-15s.mp4`), the
  poster, Desk's quick start and its poster, and the screen pictures the page uses (`desk.jpg` is the film's Desk
  still and is no longer on the page). Every screen shows a demo crate file with invented song and artist
  names.
- `icon.svg`, `icon-line.svg`, `favicon.*`, `apple-touch-icon.png`: the app's icon, redrawn as a vector from the
  booth app's icon.
- `fonts/`: Inter and Pacifico with their licences. Pacifico is used only for "you", "your" and "Deckie".
- `llms.txt`: the site's facts as plain text, for assistants that read sites. `robots.txt`, `sitemap.xml`,
  `404.html`.
- `.htaccess`: the 404 page, www to the bare address, http to https, file types and cache lifetimes.
- `film/`: the film's source, shot list, sound and capture scripts.
- `demo/`: the demo page (`index.html`, `demo.css`, `demo.js`: a player that plays the songs one after another, with
  scripts off a list of links), the songs as 128 kbps MP3s in `audio/` (about 16.7 MB in all, loaded one song at a
  time), and `CREDITS.md`, each song's artist, source, licence (all CC0 1.0), date fetched and SHA-256. The iPad app
  carries the same songs' facts and fingerprints as its demo crate file and lists the same credits. Not in the
  sitemap and marked noindex: it is a tool for testers, reached from the iPad app.
- `privacy/`: the privacy policy (`index.html`, `privacy.css`), written from
  `docs/product/testflight/privacy-policy.md`; change the two together. Every page's footer links to it, and it is in
  the sitemap.

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

In the built pages, every link to a CSS or JS file carries `?v=` and the first 10 hex characters of that file's
SHA-256, so a changed file gets a new address while an unchanged one keeps its stamp and the visitor's day-long cache.
The pages in `site/` stay unstamped, so they still open straight from the repository.

`site/dist/` is uploaded to the host over FTPS. The login is not in this repository and is never committed. After
an upload, check the live pages, the film, the 404 page and both redirects, and compare file sizes with the build.

Published Nov 12, 2026: 28 files, 13,282,076 bytes.

## What is not committed, on purpose

`dist/` and `dist-old-*/` (build output), `assets/variations/` (the soundtrack trials), the film's working
screenshots and contact sheets, and the rendered PNGs in `share/`. All are remade by the scripts here.

## Rules that apply to the site

- It names no person, with two exceptions: the home page's maker credit, and the demo page's song artists.
- No real song, artist or playlist appears, with one exception: the demo page plays public-domain (CC0) songs and
  credits their artists (`demo/CREDITS.md`). Screens show the demo crate file.
- The film's music was made for the film. No DJ's music is in any public file.
- Product copy does not say "AI". See `docs/product/voice.md`.
- Line breaks in headlines and captions are set by phrase: no line of one word, and a new sentence never leaves its
  first word alone at the end of the line before.
