# Mike page: how to publish and what comes back

## What is in `Mike page/`
- `index.html` — the page (one file, no outside resources).
- `data.js` / `data.json` — the track data (built by `_pool build/newfiles/mike_data.py`).
- `tracks/cd1/…`, `tracks/cd2/…` — 176 MP3s in the eight BPM folders, 141 picks plus 35 alternates, about 1.5 GB. They are hard links to the originals in this folder, so they take no extra disk space here; on upload they travel as ordinary files.
- `favicon.png`, `apple-touch-icon.png` — the tab and home-screen icons.

## Hosting
1. Upload the whole `Mike page` folder to the web host under an unlisted subfolder, keeping the layout (index.html next to data.js and tracks/). For christophershannon.io (Bluehost, explicit FTPS on port 21) use the resume-safe uploader, which asks for the password at the prompt and stores nothing:

       python3 "_pool build/ftp_upload_mike.py" --server ftp.jnw.qqk.mybluehost.me --user agent1Xb1@jnw.qqk.mybluehost.me --local-dir "Mike page" --remote-dir mike-halloween

   It ends with "ALL DONE"; if it stalls or Bluehost blocks the IP after a burst (403s), wait a few minutes and rerun, it skips what is already there. The page is live at **https://christophershannon.io/mike-halloween/** (verified Oct 21, 2026: https, data, 206 range responses for the MP3s through Cloudflare). Rotate that FTP password once the upload is done.

   Lessons from the first upload: the FTP account's directory had the home path twice (`/home1/jnwqqkmy/home1/jnwqqkmy/public_html`), so the files landed outside the web root and had to be moved into the real `public_html` in cPanel's File Manager (a server-side move, seconds). When creating an FTP account for this, set its directory to `public_html` and check the path cPanel shows. The script's `--move SRC DST` renames a folder on the server from an account rooted high enough to see both. Cloudflare's challenge blocks curl on this domain; verify in a real browser. The stray nested `home1` folder under the home directory can be deleted.
2. Serve it over **https://** — the phone's Share button (Send my picks) only exists on https. On http Mike still gets a Copy sheet with the same text.
3. The server must answer byte-range requests for MP3s (`Accept-Ranges: bytes`, 206 responses). nginx, Apache and Caddy do this by default; Python's `http.server` does not, and without it the scrubber, the ±15 s buttons and auto-advance break.
4. Send Mike the link. Nothing is password-protected; the URL is the only secret, so take the folder down after the party.

## Hardening (added Oct 21)
`Mike page/.htaccess` refuses MP3 requests whose Referer is not this domain, sets `X-Robots-Tag: noindex` on the folder, and marks MP3/data files `no-store` so Cloudflare cannot cache and re-serve them; every track folder also holds an empty `index.html` so nothing can be listed. The page itself carries a no-index meta. It is referer-based, so a determined person with the page open can still save a file; signed, expiring URLs would need server code. Take the folder down after the party.

## Before you text Mike the link
- Open it on your own phone: play a track, tap +15, lock the screen and check it rolls into the next track, tap Send my picks and see the share sheet.
- Then clear the site data for that page in your phone's browser so your test switches and "heard" marks are not left behind (switches are stored only in the phone's browser).
- Remind Mike it is 1.5 GB of audio: Wi-Fi.

## What Mike sends back
"Send my picks" opens a sheet with a notes box and a Share button; sharing sends a text file `Mike final mix.txt` (or the same text pasted into a message). It lists his changes, his notes and the full ON list per disc, and ends with a block like:

    --- for Chris's script ---
    CD1 ON: 1a2b3c4d5e,…
    CD2 ON: …

Save it and run:

    cd "_pool build" && python3 newfiles/apply_mike.py "/path/to/Mike final mix.txt"

That prints the adds and removes against the current pool and the MB per disc. Add `--write` to store it as `newfiles/selection_v2.json`; point `pool_build.py` at that file, then rerun `pool_build.py`, `page_build.py` (both copies) and `mike_data.py` so the pool page and Mike's page match the final cut before the discs are built.

## Local check
Double-clicking `index.html` works for browsing and switching; playback from file:// works in Safari and mostly in Chrome. For a faithful test, serve the folder with a range-capable server (`_pool build/rangeserve.py "Mike page" 8791`, then http://127.0.0.1:8791/).
