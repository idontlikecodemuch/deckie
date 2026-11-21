# The demo crate's songs

Seven songs for the demo crate: deckie.io/demo plays them out loud, and the demo crate file inside Deckie on the iPad
(`deck-app/Deck/Demo/Demo.deckie`) holds their facts and fingerprints, never the audio. The app's Credits screen
lists the same songs (`deck-app/Deck/Sources/Credits.swift`, `Credits.demoSongs`); keep the two in step.

## The rule they were chosen by

Only music whose licence clearly allows redistribution and commercial use, stated on the source's own page: CC0 or a
public domain dedication first, CC BY 4.0 with full attribution otherwise. Never NC, ND or SA, never "royalty-free"
terms that forbid redistribution, never a licence that cannot be pointed to on the source's page. All seven are CC0.

**Chosen again on Nov 19, 2026 (`pc/booth-build-2`) so the picks show the app well.** The first set had one song in
E major (12B) that clashed with every other, and tempos of 120 and 140 that cannot be beat-matched, so most picks read
"key clash" or "no beat-match". This set was picked from 93 CC0 songs on the Free Music Archive (eight albums by
Loyalty Freak Music and Komiku), each analysed by Deckie's own engine (deckie-build, engine deckie-0.7.0, as below),
choosing by the tempos and keys the engine read. No engine setting or rule was changed to make a song fit.

- Five songs in the same key, 10B (D major), at 120 and 130 BPM; one in the next key round the wheel, 9B (G major),
  at 130; so most pairs are the same key or a neighbour key, at the same tempo or 8 percent apart (a ramp blend).
- One deliberate key contrast: **Street of love** (8B, C major). From the 10B songs it reads "keys may clash" (two steps
  back round the wheel); from Street of love to them it is a two-step energy boost, which fits.
- "No beat-match" shows where a song has no steady beat at the join, as the engine read it: into **La montagne**
  (its start) from the 120 BPM songs, a brake rather than a blend.
- Roller Fever comes first on the page: every other song is a good next song from it.

## The songs

Each licence was read on the song's own page at the Free Music Archive on the date fetched. The original is the file
as the Free Music Archive served it; the page file is what `site/demo/audio/` holds. "Good next songs" counts, of
the six others, the picks that are beat-matched and whose keys do not clash, as the app shows them (DeckTests,
`theDemoSongsMostlySuitEachOther`).

| # | Title | Artist | Release | Licence | Source (licence stated there) | Fetched | Tempo, key (Deckie's reading) | Good next songs |
|---|---|---|---|---|---|---|---|---|
| 1 | Roller Fever | Loyalty Freak Music | ROLLER DISCO DANCE DANCE | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) | [freemusicarchive.org](https://freemusicarchive.org/music/Loyalty_Freak_Music/ROLLER_DISCO_DANCE_DANCE/Loyalty_Freak_Music_-_ROLLER_DISCO_DANCE_DANCE_-_01_Roller_Fever/) | 2026-11-19 | 130, 9B | 6 of 6 |
| 2 | La montagne | Komiku | It's time for adventure ! | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) | [freemusicarchive.org](https://freemusicarchive.org/music/Komiku/Its_time_for_adventure_/Komiku_-_Its_time_for_adventure_-_07_La_montagne/) | 2026-11-19 | 130, 10B | 5 of 6 |
| 3 | Everything is groovy (How to move your body) | Komiku | Helice Awesome Dance Adventure !! | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) | [freemusicarchive.org](https://freemusicarchive.org/music/Komiku/Helice_Awesome_Dance_Adventure_/everything-is-groovy-how-to-move-your-body/) | 2026-11-19 | 120, 10B | 4 of 6 |
| 4 | Sweet You | Loyalty Freak Music | MELODIES WITH A BEAT | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) | [freemusicarchive.org](https://freemusicarchive.org/music/Loyalty_Freak_Music/MELODIES_WITH_A_BEAT/Loyalty_Freak_Music_-_MELODIES_WITH_A_BEAT_-_01_Sweet_You/) | 2026-11-19 | 120, 10B | 4 of 6 |
| 5 | Captain Glouglou contest | Komiku | Helice Awesome Dance Adventure !! | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) | [freemusicarchive.org](https://freemusicarchive.org/music/Komiku/Helice_Awesome_Dance_Adventure_/captain-glouglou-contest/) | 2026-11-19 | 120, 10B | 4 of 6 |
| 6 | Sweet They | Loyalty Freak Music | MELODIES WITH A BEAT | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) | [freemusicarchive.org](https://freemusicarchive.org/music/Loyalty_Freak_Music/MELODIES_WITH_A_BEAT/Loyalty_Freak_Music_-_MELODIES_WITH_A_BEAT_-_14_Sweet_They/) | 2026-11-19 | 120, 10B | 4 of 6 |
| 7 | Street of love | Loyalty Freak Music | POSITIVE ATTITUDE ! | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) | [freemusicarchive.org](https://freemusicarchive.org/music/Loyalty_Freak_Music/POSITIVE_ATTITUDE_/Loyalty_Freak_Music_-_POSITIVE_ATTITUDE__-_06_Street_of_love/) | 2026-11-19 | 120, 8B | 5 of 6 |

## The files

SHA-256 of each original as fetched, and of each page file.

| # | Original (bytes) | Original SHA-256 | Page file (bytes) | Page file SHA-256 |
|---|---|---|---|---|
| 1 | 5900130 | `fa9986971c76189754b6592b83424b453dcb581fb1394f935f678eb4dba3d98f` | `01-roller-fever.mp3` (2331729) | `6582f00cf23e9eac5cdae05bc21f4aa1e74af358531d5ace304947330c913e56` |
| 2 | 8889896 | `a03d4aab6fe6db18db46fa8803bec5fd7751c55d08b470ebbaa344d5c42e84fd` | `02-la-montagne.mp3` (3492777) | `b7df57352f5eb4c74e5511652f29b47a3398d5bcfda1b99e86ab209a60dee1ee` |
| 3 | 4736698 | `2c39ca0c3834c2ce5c215a5ac4acea86f80a31a20d3aa3958f2d02b005e2691e` | `03-everything-is-groovy-how-to-move-your-body.mp3` (1857345) | `ae08f9b0769eeec9d2df0f6712451e22b4c2aa7fac86df7476baf6398767b944` |
| 4 | 6462514 | `9dca0e6d50bc458f4862af134c3a46ba384c21e1fa176dbf65c4ca0afdc05669` | `04-sweet-you.mp3` (2561170) | `5a86d2cad13e316b9bcd881935aae29e4cd5928c942d123da9e890e122c7a5af` |
| 5 | 4257090 | `6b49c1d7af19ab27315c0783a4ced5ec02bfcea36a764b754bab1630282af59c` | `05-captain-glouglou-contest.mp3` (1665464) | `930b646e3c2aea171b094e46f7789deac3e008c2fdeec1c6ff0da146de6a7767` |
| 6 | 9022514 | `f3fcab47f1e66577ae7d92d6899a42b0535880deb681fe6be912a8f6cf773462` | `06-sweet-they.mp3` (3585172) | `cd5edd24d2cd791f27c7a8e0bd3c5fc9413c936eafab46e58352594714483d31` |
| 7 | 6674587 | `b4a42e2690e20d395b3e65de52a3d83aae67c5f90a75a08d095a8add0d4cda7f` | `07-street-of-love.mp3` (2645185) | `8b969ea5149794501f466ddad1e166a66f31ae7b9cbfbc614c393d456b95d1e7` |

Page files total 18,138,842 bytes (the first set's were 16,706,689); the page loads one song at a time, when it plays.

## How the files were made

- **Fetched** from the Free Music Archive's own file links, with a generic User-Agent, on 2026-11-19. The originals
  are not committed.
- **The demo crate file**: each original's audio copied unchanged (no re-encoding, `ffmpeg -c copy`) into a file with
  its pictures and other tags removed and only title, artist, release and a comment naming the licence and source
  set; then, with the seven files at the top of one folder (no folder of their own, so the app shows no folder above
  each song), `deckie-build <folder> --out deck-app/Deck/Demo/Demo.deckie --no-dj-home` (engine deckie-0.7.0, without
  the learned key model, so the key is the three-answer reader's, as before). Building into the existing package keeps
  its crate id (`1a365511-96d6-4840-a9f3-e9b7a772179c`), its name ("Demo crate") and its created date; DeckTests hold
  the id and that the files are exactly as the writer writes them. The album pictures are left out because their
  licence is not stated. The crate file holds the songs' facts, beat grids, keys, per-bar loudness and fingerprints:
  about 200 KB.
- **The page files**: the same tag-stripped files encoded with ffmpeg's LAME at 128 kbps, 44.1 kHz stereo, tags as
  above.
- **Checked** (Nov 19, 2026): every page file through Deckie's listener (`deckie-listen`, the booth's index setting)
  against the bundled crate file's fingerprints, from five places (0, 20, 40, 60 and 80 percent in), clean and
  through a rough phone-speaker-in-a-room filter (250 Hz to 7 kHz, pink noise about 12 dB under the music). No other
  song was ever named. Seconds to the first name: 3 for most places; 4 to 5 for a few places in Roller Fever, Sweet
  You, Sweet They and Everything is groovy; Street of love takes 8 to 10 seconds from two quieter places (45 and
  80 percent in) and 3 elsewhere.
