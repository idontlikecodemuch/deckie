# Track B: identifying the user's crate from their files and public metadata

Dated Oct 26, 2026. Research report for `docs/product/02-research-plan.md`, Track B. Feeds spec v0.2 sections 5 and
6.3. Extends `docs/competitive-analysis.md` sections 3.3 and 6.5; does not repeat them. `[inf]` marks inference.
Quotes are the operative sentences of the terms relied on, fetched on Oct 26, 2026 unless noted.

## Summary

**Recommended pipeline, in five lines**

1. Parse what is already on the device: tags first, then a file-name grammar built for DJ files (`Artist - Title -
   Remixer Remix (Intro - Dirty)`), splitting every file into a *work* (song, original artist, original year) and a
   *version* (remixer, edit type, clean/dirty, intro, extended). No network.
2. Cross-reference inside the crate: cluster versions of the same work, group by album, folder and disc, fold
   half-time and double-time BPM tags, drop exact duplicates by content hash.
3. Optional text enrichment, off by default, one switch: MusicBrainz (CC0, free, 1 request per second) for the work;
   Discogs (CC0 data, attribution required) for remixes, 12" mixes and compilations. Sends titles, never audio.
4. Optional fingerprint lookup, opt-in per batch, Mac-first: Chromaprint plus AcoustID, used only to name the *work*
   behind an untagged rip. Fingerprints identify the commercial original, not the DJ edit.
5. Whatever is still unidentified keeps the user's own name, gets the full analysis, and shows up in a "name these"
   list. Identification never gates anything.

**YouTube verdict.** YouTube is off the table as an identification source: the Data API allows text search, but a
project gets 100 `search.list` calls per day shared across every user, anything fetched must be deleted or refreshed
within 30 days, and all access outside the API (page reads, third-party scrapers, downloads) is prohibited by both
the consumer and the API terms. The only compliant and useful thing is a hand-triggered "open in YouTube" link that
sends the user's own query string to the YouTube app; the reading-versus-training distinction never comes into play
because the terms restrict the reading itself.

**The privacy call on fingerprints.** A Chromaprint fingerprint is about 2.5 KB derived from the first 120 seconds
of audio; it cannot be played back and no audio leaves the device. But a lookup tells AcoustID, from the user's IP
with Deckie's client key, which recordings the user owns. That is a disclosure of the *crate*, not the *music*. It
fits D3 only as an explicit opt-in ("send fingerprints of 212 unnamed files to AcoustID to name them?"), never
automatically, never silently on first import, and never from the iPad by default. The same rule applies to a
ShazamKit lookup against the Shazam catalogue, which also sends a signature to Apple `[inf]`.

**Three things that matter for the spec.** (a) DJ-pool files are the best-tagged files in the crate (title, artist
with "ft." credits, BPM, key); YouTube and mp3.pm rips are the worst, with no tags and the channel name where the
remixer goes. (b) A burned MP3 CD is a file system, not an audio CD: no table of contents, no disc id; its identity is
its volume label, folders and the files' own tags, the same pipeline as a folder. Deckie should write a manifest when
it builds a disc and read it back. (c) Every online source is text-in, text-out and reveals the crate's names to that
service; CC0 data (MusicBrainz core, Discogs core) may live in the crate file forever, YouTube and SoundCloud data may
not be stored at all.

## 1. Source table

| Source | What it gives | Terms (operative sentence) | Rate limit | Cost | Privacy implication | Offline |
|---|---|---|---|---|---|---|
| **Tags and file names** (on device) | Title, artist, album, year, BPM, key, remixer (TPE4), ISRC, MusicBrainz ids if Picard-tagged; pool version labels | None | None | Free | None | Yes |
| **MusicBrainz** | Recording, release, release group, first release date, ISRC, credits; disc id and fuzzy TOC lookup; CD stubs | "Non-commercial use of this web service is free"; commercial users asked to "see our commercial plans" [S6]. Core data CC0; tags, ratings, annotations CC BY-NC-SA [S7][S8] | "(on average) 1 request per second" per IP; "meaningful user-agent string" [S5][S6] | Free; commercial tiers from $0 to $100+/month [S9] | Titles and artists sent per query from the user's IP | No; results cacheable forever (CC0) |
| **AcoustID + Chromaprint** | AcoustID id and MusicBrainz recording ids for a fingerprint; covers commercial releases | "This service is provided for free for non-commercial use only" [S10]. Data CC BY-SA 3.0, MB mapping CC0 [S11]. Chromaprint LGPL 2.1 [S13] | "Do not make more than 3 requests per second" [S10] | €50/month for 1M searches, 10k free trial [S12] | Fingerprint, duration and client key sent: discloses which recordings the user owns | Fingerprint offline, lookup online |
| **Discogs** | Releases, masters, remix and 12" versions, "Mixed by" credits, labels, catalogue numbers, compilations | Terms of May 27, 2025: "Data provided by Discogs." next to the data, plus a non-affiliation notice; titles, dates, formats, tracklists, credits are CC0; "restricted data" defined in the terms [S14][S15] | 60/min authenticated, 25/min not, per IP, User-Agent required [S14] | Free | Text queries; app key in the binary | No; core data cacheable |
| **Beatport** | BPM, key, genre, mix name, remixers, ISRC, label | "available for non-commercial use only"; "pre-approved licensees"; commercial use needs "express written permission" [S16] (search-indexed; fetch refused) | Not published | Partner application only | Text queries; partner key in the binary | No |
| **1001Tracklists** | Tracklists of published sets | No public API found; its privacy page lists it as an API *client* of others [S17]; a vendor says it "does not offer a public developer API" [S18] | n/a | n/a | n/a | n/a |
| **SoundCloud** | Track, user, duration, artwork; text search | Registration needs Artist Pro [S20]. "any cached content must cease to be available... at the end of that session"; no "offline access to any User Content"; no "scraping"; no "fingerprints... of User Content"; no AI training [S19] | 100/min; search 3,000/hour; per client_id [S21] | Free; "reserves the right to charge" [S19] | Text queries; client id in the binary | No, nothing may be stored |
| **Mixcloud** | Cloudcast title, user, tags, duration; search; upload with tracklist sections | Read needs "None"; "Audio streams are not available through the Mixcloud API" [S22]. Site: no "robot, spider, scraper", no "text and data mining", no ML training [S23] | "Every action in the API is rate limited", Retry-After [S22] | Free | Text queries | No |
| **Bandcamp** | API for "Labels and merchandise fulfillment partners" only; no catalogue search [S24] | May 7, 2026: no "storage of any Content for other than personal, non-commercial use" [S25] | n/a | n/a | n/a | Downloads arrive well tagged `[inf]` |
| **YouTube Data API** | Video title, channel, duration for a text query | Section 3 | 100 `search.list` calls per day per project [S1][S2] | Free; more only after an audit [S3] | Query text and IP to Google; API key in the binary | No; delete or refresh within 30 days [S4] |
| **CD table of contents** (Mac with a drive) | Disc id from track offsets; fuzzy TOC lookup; CD stubs | MusicBrainz, as above | As above | Free | Disc id sent, reveals the disc owned | No |

## 2. What DJ files actually look like

Evidence: the sprint's `pool/newfiles/probe.json` (106 files added the week before Halloween) and
`library_probe.json` (2,447 files), read by `probe_new.py` with ffprobe (title, artist, TBPM, TKEY, codec, bit rate,
duration, MD5). `pool_build.py` then hand-mapped edits to originals (`ORIGINALS`), original years (`YEAR`) and version
notes (`NEW`). That hand mapping is what the pipeline must automate.

**Shapes in 2,553 file names.** 96 percent contain ` - `; 49 percent contain underscores (the `mp3.pm` rip style,
`Ace_Of_Base_-_All_That_She_Wants_Snbrn_Klatch_Remix_(mp3.pm).mp3`); 4 start with a track number. The most frequent
bracket tokens are not versions: `[pmedia]` 643 times, years on compilation rips, `[320 kbps]`. Version tokens follow:
`(Dirty)` 30, `(Extended Mix)` 29, `(Radio Edit)` 26, `(Club Mix)` 14, `(Intro - Dirty)` 12, `(Radio Mix)` 12,
`(Extended)` 11, `(Extended Version)` 10, `(Intro)` 6, `(Clean)` 4, then `(Acap - Dirty)`, `(Album Version)`,
`(Lyrics)`, `(Official Audio)`.

**Three families, three grammars.**

1. *DJ-pool files* (DJcity here): `Artist - Title - Remixer Remix (Intro - Dirty).mp3`. The remixer sits in a
   *third* ` - ` segment, not in brackets. Tags are complete: TIT2 `No Broke Boys (Intro - Dirty)`, TPE1 with credits
   the name drops (`Drake ft. Sexyy Red & SZA` vs file `Drake - Rich Baby Daddy`), TBPM, TKEY (`G#m`, `Ebm`). The pool
   brand lives only in the tag: file `(Intro - Dirty)`, tag `(DJcity Intro - Dirty)`. DJcity's definitions: Intro
   "includes an 8-bar instrumental added to the beginning and end"; Clean "edited to remove the explicit words"; Dirty
   "the original version, containing explicit words"; Main: no explicit words; Short edit "features the most popular
   section"; Transition: moves between tempos; Hook first: starts on the chorus [S26]. Other pools use 16 or 32 bars
   and add Outro, Quick Edit, Acapella In/Out, Redrum, Hype [S27][S28]. Pool tracks are licensed "to promote new music
   only" (competitive analysis S42), so they are never on Bandcamp or Beatport and rarely on MusicBrainz: the *work* is
   public, the *version* is not.
2. *YouTube and mp3.pm rips*: no tags (37 of the 106 new files had no title tag). Names are `Title (Extended) -
   Channel.mp3` with the *channel* where a pool file puts the remixer (`Afraid To Feel (Extended) - LF SYSTEM.mp3`,
   `... - Spinnin' Records.mp3`), or hyphenated slugs (`Joel-Dickinson-Thee-Greatest-Hits-Bette-Midler-...`), or commas
   between artists. Bit rate is a tell: the sprint flagged 128 and 192 kbps rips by hand.
3. *Compilation and album rips*: 98 percent have title and artist tags, 95 percent album, 71 percent year, 73 percent
   genre, 26 percent BPM. The album tag is the disc name, and in Chris's crate the *user's* disc names (`CD1 - 90s`,
   `CD3 - Halloween`) sit next to commercial ones (`NOW That's What I Call Music! Forever 90s`). Album, track number and
   year are enough for a MusicBrainz release lookup; the user's own disc names must be kept as-is.

**Traps.** Half- and double-time BPM tags (`67`, `70`, `146`; the probe folds to 68 to 160). `(1)` duplicate
downloads, caught by MD5. One work in five versions (No Broke Boys: plain, Intro, Acap, each Dirty). "Remix" that is a
cover (`Jolyon Petch - Thriller - Freejak Remix`, TPE1 is the cover artist) and "Remix" that is a mashup of two works
(`Bad Bunny - DtMF - ETX vs ... Better Off Alone Edit`). Tag year on a pool edit is 2025 or 2026; the work is from
1996. The sprint keyed era on the work, and so should the crate.

**Tag frames worth reading** (ID3v2.3 [S29]): TIT2, TPE1, TPE4 "Interpreted, remixed, or otherwise modified by",
TIT3, TALB, TYER, TBPM, TKEY "Initial key", TSRC (ISRC), TPUB, TPOS, TRCK, TXXX, COMM, UFID (Picard puts the
MusicBrainz recording id here), GEOB (Serato's cues, grid and `Serato Autotags` BPM/gain, documented by reverse
engineering [S30]). MP4 and FLAC carry equivalents. Mixed In Key and Serato sometimes put the key in COMM when TKEY is
empty [S31] `[second source needed]`. Never write any of these back.

## 3. YouTube: what the terms allow

Three documents govern an iOS or macOS app: the consumer Terms of Service, the API Services Terms of Service
(updated 2026-09-14) and the Developer Policies (updated 2026-10-15).

**Consumer Terms of Service** (effective December 15, 2023), "Permissions and Restrictions" [S32]. Not allowed:
"access, reproduce, download, distribute, transmit, broadcast, display, sell, license, alter, modify or otherwise use
any part of the Service or any Content except: (a) as expressly authorized by the Service; or (b) with prior written
permission from YouTube and, if applicable, the respective rights holders"; "circumvent, disable, fraudulently engage
with, or otherwise interfere with any part of the Service"; "access the Service using any automated means (such as
robots, botnets or scrapers) except (a) in the case of public search engines, in accordance with YouTube's robots.txt
file; or (b) with YouTube's prior written permission". That rules out yt-dlp-style extraction, page reads and any
third-party "YouTube scraper API", from any app.

**API Services Terms of Service** [S33]: "YouTube may set a quota on usage of any YouTube API Services at any time"
and you "will not attempt to, exceed or circumvent use or quota restrictions" (section 15); YouTube may "monitor and
audit your access to and use of the YouTube API Services, at any time and without further notice to you" (section 6);
"no rights or licenses are granted to reproduce or distribute audiovisual content" (16.3).

**Developer Policies** [S4]. III.E.1: must not "download, import, backup, cache, or store copies of YouTube
audiovisual content without YouTube's prior written approval" nor "make content available for offline playback".
III.E.4.d: "may temporarily store limited amounts of Non-Authorized Data for as long as is necessary... but not
longer than 30 calendar days"; III.E.4.c: "After 30 calendar days, the API Client must either delete or refresh the
stored data." Non-Authorized Data "means API Data accessible by an API Client without User Credentials", which is what
a search returns. III.E.6: "must not, and must not encourage, enable, or require others to, directly or indirectly,
scrape" YouTube. III.I.1: must not "act as a substitute for, or substantially similar service to" YouTube. III.I.7:
must not "separate, isolate, or modify the audio or video components".

**Quota** [S1][S2][S3]. "Projects that enable the YouTube Data API have a default quota allocation of 100 search.list
calls, 100 videos.insert calls, and 10,000 units per day combined for all other endpoints." `search.list`: "The quota
cost is 1 per call", capped at 100 calls per day. The allocation is per Google Cloud project, so per app, not per user
`[inf]`. More requires an audit that the project "is in compliance with the YouTube API Services Terms of Service"; no
timeline is published; purchase is not offered.

**Reading versus training.** None of the three documents contains "train", "machine learning" or "artificial
intelligence"; YouTube's help page says only that the Terms "prohibits content from unauthorized use, such as
unauthorized downloads and scraping", with a creator-side training setting that "By default... is turned off" [S34].
Chris's point stands, mapping a file to public metadata is not training, but it does not help: the terms restrict the
access and the storage, not the purpose.

**Verdict.** Off the table as a lookup source. Numerically: a 2,447-file crate at 100 searches per day for the whole
user base is 25 days for one user and nothing for the next. Legally: a crate file that remembers a YouTube title or
video id past 30 days breaks III.E.4, and the crate file is by design permanent and offline. Compliant and useful: a
button on an unidentified track that opens `https://www.youtube.com/results?search_query=<the user's own query>`
(a universal link the YouTube app takes over). No API, no key, no storage; the user reads the result and types the
name. The same shape works for
1001Tracklists and Discogs web pages.

## 4. Recommended pipeline, step by step

Runs on import (folder, files, AirDrop, a disc on the Mac) and on demand. Each step writes to the crate entry:
`display_name` (what the DJ sees; defaults to the file name), `work` {artist, title, original_year, mbid?}, `version`
{remixer, kind, clean|dirty|main, intro, extended, bootleg|mashup|cover}, `source` {pool|rip|album|disc|unknown},
`ids` {isrc?, mb_recording?, discogs_release?, acoustid?}, `confidence`, `identified_by`
(tags|name|crate|musicbrainz|discogs|acoustid|user).

1. **Read the container.** Duration, codec, bit rate, content hash (MD5, as the probe does). Exact duplicates collapse
   to one entry with two paths. Keep the folder path and, for discs, disc, folder and track position: the standing
   principle makes that the primary identifier.
2. **Read tags** in order of trust: UFID/TXXX MusicBrainz ids and TSRC if present (Picard, Bandcamp, iTunes purchases);
   TIT2/TPE1/TALB/TYER/TPOS/TRCK; TPE4; TBPM/TKEY (fold BPM to 68 to 160, keep the raw value); COMM (pool brand, MIK
   energy). A pool brand in a tag sets `source = pool`.
3. **Parse the name** with one grammar, three dialects. Split on ` - ` (also `_-_`, ` – `); strip rip tokens
   (`[pmedia]`, `(mp3.pm)`, `(320kbps)`, `(Lyrics)`, `(Official Audio)`, trailing `(1)`); lift version tokens (`Remix`,
   `Edit`, `Rework`, `Flip`, `Bootleg`, `Mashup`, `VIP`, `Club Mix`, `Extended`, `Radio Edit`, `Intro`, `Outro`, `Acap
   In/Out`, `Clean`, `Dirty`, `Transition`, `Redrum`, `Short`, `Hook First`, `Instrumental`) into `version`; the segment
   containing `Remix|Edit|Mix|Rework|Flip` names the remixer; a trailing segment on a known channel or label list
   (`Spinnin' Records`, `Future House Music`, `AURA`) is a rip source, not a remixer; `A vs B`, `A x B` set `mashup` and
   keep both works; title-first order (`Title (Extended) - Artist`) is detected when the trailing segment is an artist
   already in the crate. Tags win over names; the name wins for `version` when the tag title lacks the bracket.
   Confidence: high when tags and name agree, medium from name alone, low for slugs and underscores.
4. **Cross-reference inside the crate** (no network). Cluster by normalised work title (fold accents as `fold()`
   does, drop version tokens): five No Broke Boys files become one work, five versions. `original_year` is the earliest
   tag year in the cluster or the compilation's track year. Credits propagate from the best-tagged sibling to the
   untagged rip. This step alone would have produced most of the sprint's `ORIGINALS` and `YEAR` maps `[inf]`.
5. **Discs.** Audio CD in the Mac's drive: MusicBrainz disc id from the TOC (first and last track, lead-out and track
   offsets, SHA-1, 28 characters [S35]); query with `toc=` so an unknown disc gets "a fuzzy lookup... to find matching
   MusicBrainz releases" and CD stubs [S6]. A burned audio CD of the user's own selection has a TOC no database holds
   and no CD-TEXT unless the burner wrote it, which is rare [S36]; its tracks come from the source files and the disc is
   recorded as the user's (`CD1 - 90s`). A burned MP3 CD has no audio TOC and so no disc id; it is an ISO 9660/Joliet
   file system with a volume label and folders [S37]: steps 1 to 4 on that mount, with the CDJ's folder and file
   numbers as the location. Deckie should write a manifest (today `docs/discs/MANIFEST.md`, `discs_def.json`) onto the
   disc and into the crate when it builds one, and read it back when it sees that volume label.
6. **Text enrichment, off by default**, one switch: "Look up names online (sends titles, never audio)". MusicBrainz
   first: recording by artist and title, release by album and year; keep `mb_recording`, ISRC, first release date
   (CC0, cacheable forever); 1 request per second with a User-Agent like `Deckie/0.2 (contact email)`. Discogs second,
   for what MusicBrainz lacks: remix and 12" mixes, compilations, "Mixed by" credits; keep release id and year; show
   "Data provided by Discogs." where its data appears. Requests go from each user's IP, so the per-IP limits are per
   user; MetaBrainz will still count Deckie as commercial once it charges, so budget a supporter tier. Beatport: apply
   for partner access later. SoundCloud and Mixcloud: lookup-and-link only, nothing stored.
7. **Fingerprint, opt-in per batch, Mac-first.** For files still at low confidence: Chromaprint over the first 120
   seconds (fpcalc default [S38]; 11,025 Hz, 12 chroma bins, 16 filters into one 32-bit integer per window [S39]),
   AcoustID lookup with `meta=recordings+releasegroups`, 3 requests per second, €50 per month for 1M lookups.
   Expectation: a pool edit or bootleg returns the commercial original or nothing, so the result names the *work* and
   the parsed version stays `[inf]`. Chromaprint is LGPL 2.1 [S13]: on the Mac, link dynamically or call `fpcalc`; on
   iOS, static linking a closed app against LGPL code is the known problem [S40], so keep it off the iPad until settled.
   ShazamKit against the Shazam catalogue is the Apple-native alternative with the same disclosure `[inf]`; it needs
   ShazamKit enabled on the app id [S41] and the same opt-in.
8. **Never block.** Every entry is analysed (grid, key, structure, vocal, energy, loudness, style) regardless of
   steps 2 to 7. The crate view shows "12 tracks need a name" with the parsed guess pre-filled; a typed name becomes
   `display_name` with `identified_by = user` and top confidence. Picks, recognition and the set log use
   `display_name`; metadata only sharpens the era and style signals.

## 5. Open questions

- MusicBrainz commercial status: "Non-commercial includes personal use" [S9]; a paid App Store app is commercial.
  Ask MetaBrainz which tier applies to a client app that makes per-user requests.
- Mixcloud tracklist read-back: `sections` is documented for upload only [S22]; third-party wrappers show it in GET
  responses [S42]. Verify in a spike before promising set import.
- Discogs "restricted data" and the exact non-affiliation wording: the terms page refused a fetch [S15]; read it in
  a browser before shipping the attribution.
- Beatport partner application: worth a letter once the crate file exists; the terms are search-indexed only [S16].
- Apple Music API catalogue search as a text source: not in the brief; needs a developer token `[inf]`; check its
  terms on storing results.
- Chromaprint on iOS: LGPL 2.1 with no exception [S13]; decide Mac-only or a clean-room fingerprint.
- gnudb for CD lookups: behind a browser check [S43]; MusicBrainz covers the need.

## Sources

Internal: `pool/newfiles/probe.json`, `library_probe.json`, `probe_new.py`, `pool_build.py`, `discs_def.json`;
`docs/discs/MANIFEST.md`; `docs/competitive-analysis.md` 3.3, 6.5 and S39, S41, S42; `docs/product/00-decisions.md`.

- S1 YouTube Data API getting started, quota: https://developers.google.com/youtube/v3/getting-started
- S2 YouTube quota costs: https://developers.google.com/youtube/v3/determine_quota_cost
- S3 Quota and compliance audits: https://developers.google.com/youtube/v3/guides/quota_and_compliance_audits
- S4 YouTube API Services Developer Policies (2026-10-15): https://developers.google.com/youtube/terms/developer-policies
- S5 MusicBrainz rate limiting: https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting
- S6 MusicBrainz API (commercial use, discid, toc, cdstubs): https://musicbrainz.org/doc/MusicBrainz_API
- S7 MusicBrainz data licence: https://musicbrainz.org/doc/About/Data_License
- S8 MusicBrainz database, core vs supplementary: https://musicbrainz.org/doc/MusicBrainz_Database
- S9 MetaBrainz account types and tiers: https://metabrainz.org/supporters/account-type
- S10 AcoustID web service: https://acoustid.org/webservice
- S11 AcoustID data licence: https://acoustid.org/license
- S12 AcoustID commercial plans: https://acoustid.biz/
- S13 Chromaprint licence: https://raw.githubusercontent.com/acoustid/chromaprint/master/LICENSE.md
- S14 Discogs API documentation (rate limits, auth, images; search-indexed, fetch refused): https://www.discogs.com/developers
- S15 Discogs API Terms of Use (May 27, 2025; search-indexed, fetch refused): https://support.discogs.com/hc/en-us/articles/360009334593-API-Terms-of-Use ; attribution notes: https://github.com/tagrex/tagrex/issues/361
- S16 Beatport API docs (search-indexed, fetch refused) and third-party summary: https://oauth-api.beatport.com/ ; https://sonovault.now/beatport-api
- S17 1001Tracklists privacy and API client terms: https://www.1001tracklists.com/info/privacy.html
- S18 Parse.bot on 1001Tracklists having no public API (vendor claim): https://parse.bot/marketplace/ec03e43b-6798-40ce-86c9-02832adedc4c/1001tracklists-com-api
- S19 SoundCloud API Terms of Use (30 March 2024): https://developers.soundcloud.com/docs/api/terms-of-use
- S20 SoundCloud app registration: https://developers.soundcloud.com/docs/api/register-app
- S21 SoundCloud rate limits: https://developers.soundcloud.com/docs/api/rate-limits
- S22 Mixcloud API: https://www.mixcloud.com/developers/
- S23 Mixcloud terms: https://www.mixcloud.com/terms/
- S24 Bandcamp developer API: https://bandcamp.com/developer
- S25 Bandcamp terms of use (May 7, 2026): https://bandcamp.com/terms_of_use
- S26 DJcity version definitions (support article, search-indexed): https://support.djcity.com/hc/en-us/articles/34409884914708-What-type-of-music-does-DJcity-provide ; https://support.djcity.com/hc/en-us/articles/32309210373652-How-do-record-pools-work
- S27 Digital DJ Tips, version names: https://www.digitaldjtips.com/your-questions-what-do-all-the-names-for-different-versions-of-a-track-mean/
- S28 Digital DJ Pool, DJ edits explained: https://digitaldjpool.com/blog/dj-edits-explained/
- S29 ID3v2.3 frames: https://id3.org/id3v2.3.0
- S30 Serato GEOB tags, reverse-engineered: https://github.com/Holzhaus/serato-tags
- S31 Key in COMM when TKEY empty (vendor guide): https://www.mixgraph.io/tools/mp3-metadata-editor
- S32 YouTube Terms of Service (effective December 15, 2023): https://www.youtube.com/t/terms
- S33 YouTube API Services Terms of Service (2026-09-14): https://developers.google.com/youtube/terms/api-services-terms-of-service
- S34 YouTube help, third-party training: https://support.google.com/youtube/answer/15509945
- S35 MusicBrainz Disc ID and calculation: https://musicbrainz.org/doc/Disc_ID ; https://musicbrainz.org/doc/Disc_ID_Calculation
- S36 CD-TEXT rarity (BASS docs): https://www.un4seen.com/doc/basscd/BASS_CD_GetID.html
- S37 ISO 9660 volume id and Joliet names (mkisofs discussion): https://lists.mythtv.org/pipermail/mythtv-users/2004-June/044306.html
- S38 fpcalc default length 120 s: https://raw.githubusercontent.com/acoustid/chromaprint/master/src/cmd/fpcalc.cpp
- S39 How Chromaprint works: https://oxygene.sk/2011/01/how-does-chromaprint-work/
- S40 LGPL and App Store static linking (FFmpeg ticket): https://trac.ffmpeg.org/ticket/1229
- S41 Apple SHSession: https://developer.apple.com/documentation/shazamkit/shsession
- S42 Mixcloud sections in third-party wrapper: https://metacpan.org/pod/WWW::Mixcloud::Cloudcast::Section
- S43 gnudb: https://gnudb.org/ ; MusicBrainz on FreeDB and GnuDB: https://musicbrainz.org/doc/FreeDB

## Addendum: YouTube, dug further

Follow-up of Oct 26, 2026 to Chris's question: he knows sites that pull YouTube data; is any route to YouTube's
public metadata usable for best-mapping a user's files, titles only, never audio, nothing the App Store would reject?

**Every site that shows YouTube data gets it one of four ways.** (A) As a registered Data API client, bound by the
API Terms and Developer Policies quoted in section 3 (1001Tracklists, Last.fm, the playlist movers, Social Blade).
(B) By calling YouTube's internal "InnerTube" endpoints or reading page HTML, which is what Invidious, Piped, NewPipe,
yt-dlp, ytmusicapi, cobalt and every "YouTube API alternative" sold on SerpApi, Apify or RapidAPI do. (C) From links
that people typed into another database (MusicBrainz, Discogs, Wikidata, WhoSampled, Genius). (D) Because the user
hands over a link. Only A, C and D survive the two rules below.

**Two rules bind an App Store app.** Apple's guideline 5.2.2: "If your app uses, accesses, monetizes access to, or
displays content from a third-party service, ensure that you are specifically permitted to do so under the service's
terms of use. Authorization must be provided upon request." Guideline 5.2.3: "Apps should not facilitate illegal file
sharing or include the ability to save, convert, or download media from third-party sources (such as Apple Music,
YouTube, SoundCloud, Vimeo, etc.) without explicit authorization from those sources" [S44]. On YouTube's side, route B
is "automated means" under the consumer Terms (section 3), and the Developer Policies add that an API client "must
not, and must not encourage, enable, or require others to, directly or indirectly, scrape YouTube Applications or
Google Applications, or obtain scraped YouTube data or content" (III.E.6) and must not "use any technology other than
YouTube API Services to access or retrieve API Data" (III.I) [S4]. So a scraper bought from a vendor is still ours.

| Route | What it gives | How it gets it | Standing | Usable for Deckie |
|---|---|---|---|---|
| Data API `search.list` | Title, channel, video id for a query | A | Compliant; 100 calls/day/project; 30-day storage [S1][S4] | No (section 3) |
| Data API `videos.list` by id | Title, channel, duration for a known id | A | Compliant; "The quota cost is 1 per call", 10,000 units/day for all users [S2]; 30-day storage | Yes, to resolve a link the user pasted; show, never store |
| YouTube oEmbed `youtube.com/oembed` | Title, author, thumbnail for a URL | YouTube's own embed endpoint, listed at oembed.com [S62] | Not a listed API Service; "expressly authorized by the Service" for embedding `[inf]`; grey for title lookup | Only user-initiated; prefer `videos.list` |
| Share sheet from the YouTube app | The URL (title text unverified) | D | User action, no automation | Yes; verify the payload in a spike |
| "Find on YouTube" link | Opens the user's query in the YouTube app | D | No API, no data returned | Yes (section 3) |
| Invidious, Piped, NewPipe Extractor | Search and full video metadata (`title`, `author`, `lengthSeconds`) [S46] | B: Piped "Does not use official YouTube APIs" [S47]; Invidious: "we don't use their official API" [S46] | YouTube legal contacted Invidious Jun 8, 2023; instances fight blocking (docs page "Rotate your IPv6 address for escaping YouTube blocking") [S46]; consumer ToS item 3; fails 5.2.2 | No |
| yt-dlp, cobalt | `-j` metadata without download; downloads [S48][S49] | B; YouTube now demands PO Tokens "to attest the requests are coming from a genuine client", else "HTTP Error 403, or ... your account or IP address being blocked" [S48] | As above plus 5.2.3; cobalt's hosted API "not intended to be used in other projects without explicit permission" [S49] | No |
| ytmusicapi | YouTube Music search: songs with `videoId` [S50] | B: "emulates YouTube Music web client requests using the user's cookie data" [S50] | Unofficial; consumer ToS item 3; 5.2.2 | No |
| SerpApi, Apify, RapidAPI "YouTube API alternatives" | Scraped search JSON; Apify "from $2.40 / 1,000 videos", "beyond what the YouTube Data API allows" [S51][S52] | B, resold | III.E.6 "obtain scraped YouTube data"; SerpApi's own terms assume liability only for "lawful collection", not use [S51]; 5.2.2 | No |
| Social Blade, vidIQ, NoxInfluencer, Playboard | Channel and video statistics; Social Blade sells a credit-priced Business API, "only public statistical data" [S53]; no public API found for the other three [S54] | A | API clients may not "sell ... redistribute, or sublicense" API Services (III.G.1) [S4]; no song search anyway | No, wrong data |
| MusicBrainz recording URL relationships | "free streaming" links on recordings, "Spotify and YouTube" named as examples [S56] | C, contributors | CC0, storable forever, 1 req/s [S6][S7] | Yes: best legitimate link source |
| Discogs release `videos` | YouTube links per release, remixes included | C, contributors; in the API and the CC0 monthly dumps [S57] | CC0 dumps; whether `videos` is "restricted data" in the API terms unverified [S15] | Yes, second |
| Wikidata P1651 "YouTube video ID" | Video id on the track item (`[-_0-9A-Za-z]{11}`) [S58] | C | CC0; sparse for songs | Marginal |
| Odesli / Songlink | Links on all platforms, `youtube` and `youtubeMusic` included, for a platform URL or id | C, resolver | 10 req/min without key, 60 with; key issuance reported closed; terms page unreachable [S55] | Only for a link the user pasted; needs a platform id first |
| Spotify Web API | Search, ISRC | A-type partner API | Dev mode "Up to 5 authenticated Spotify users"; extended mode needs a business and "at least 250k MAUs"; "you may not store, aggregate or create compilations or databases of Spotify Content"; "Do not use the Spotify Platform or any Spotify Content to train a machine learning or AI model"; "must not offer metadata ... as a standalone service" [S59] | No |
| Deezer API | Public search with ISRC; 50 req/5 s per IP (third-party) [S60] | A-type | "the use of the Services is strictly limited for a non-commercial purpose" [S60] | No for a paid app |
| Apple Music API / MusicKit | Catalogue search, ISRC, developer token | Apple-native | PLA 3.3.6(D): "You agree not to call the MusicKit APIs ... for purposes unrelated to facilitating access to Your end users' Apple Music subscriptions"; "music-related text from the MusicKit API may not be used separately from music playback or managing playlists" [S61] | No as a tagging source |

**Revised verdict.** Unchanged for automated mapping: no route delivers YouTube metadata for thousands of files on a
user's device inside YouTube's terms and Apple's 5.2.2. Two refinements. First, user-initiated use is fine: when the
DJ shares or pastes a YouTube link, resolve it with `videos.list` (1 unit, 10,000 a day across all users), show the
title, and let the DJ accept it as their own name; store nothing from the response. Second, the best legitimate
source of YouTube links per recording is MusicBrainz, with Discogs videos second, and both carry the title, artist,
remixer and year themselves, so YouTube never has to be read at all; the link is a "listen to confirm" button. The
reading-versus-training question stays moot: the terms govern access and storage, and the InnerTube routes that the
frontends use are the access YouTube is actively blocking with PO Tokens.

**Sites Chris may mean, for him to confirm.** API clients (route A): 1001Tracklists (its privacy page says it uses
the YouTube API "to add and embed YouTube media links" [S17]), Last.fm, Soundiiz, TuneMyMusic, FreeYourMusic,
Social Blade, vidIQ, Kworb, Chartmetric, Soundcharts. Frontends and extractors (route B): Invidious, Piped, NewPipe,
FreeTube, Yattee (reported gone from the App Store [S64]), yt-dlp, cobalt, y2mate-style converters, ytmusicapi,
SerpApi, Apify, the RapidAPI listings, Return YouTube Dislike. Link holders (route C): Discogs, MusicBrainz,
Wikidata, WhoSampled, Genius, MixesDB, Shazam's "listen on YouTube", Odesli. If the sites he means are in the first
or third group, they confirm the picture; if in the second, they are the ones YouTube is blocking.

## Addendum: self-contained identity

Chris's question: MusicBrainz and Discogs were inaccurate in the sprint and the DJ edits names anyway, so does public
identification matter, or can Deckie make its own identity from the analysis and take names from tags, with an editor?

**1. The accuracy problem is structural, not a bug.** The sprint ended with hand maps for about a hundred original
years and a hundred new entries (`pool_build.py` `YEAR`, `NEW`; spec v0.2 section 5). The databases say why.
MusicBrainz: "Bootleg should be used for pirated/counterfeit/unofficial releases," but "not every unofficial release
should be added"; versions "supplied to radio DJs for air-play" are "promotion" status [S66]; the community expects
notability, so a pool edit or a bootleg that lives only in DJ folders is usually absent, and the lookup lands on the
original or on a different edit. AcoustID's own guide lists its false positives: "Instrumental versions", "Radio
edits (where only a small amount is edited, bleeped out, etc.)", "Any recordings which only diverge after the
two-minute mark where the acoustID fingerprint ends" [S65]; when one fingerprint maps to several recordings, Picard
breaks the tie on metadata, which an untagged rip lacks [S67]. Discogs "only catalogs items that have been released
to the general public" and digital releases "may be held under closer scrutiny"; the forum rule of thumb is that
unofficial remixes need the remixer's consent and DJ mixes are not allowed unless authorised [S68]. The Discogs-VI
authors had to match Discogs to YouTube with their own search rather than Discogs' links [S72] `[inf]`. Live sets:
neither database models a recording's tracklist. So for exactly our material (pool versions, bootlegs, mashups,
recorded sets) coverage is the gap, and wrong-version matches are the failure mode when coverage exists.

**2. A self-contained scheme is feasible.** Three layers, no service. (a) Content hash per file for exact identity,
already in the probe (MD5) and in Track A's crate file as a head hash [S79]. (b) The ShazamKit signature for
recognition: about 45 KB, irreversible, generated on device [S79]. (c) An analysis-derived version descriptor for
clustering versions of one work and deduping across crates. The prior art is cover-song identification: the
chroma-based systems that won MIREX 2006-07 (beat-synchronous chroma, cross-correlation or local alignment; Ellis
and Poliner, Serrà) [S69], packaged in Essentia as HPCP, `ChromaCrossSimilarity` and `CoverSongSimilarity` with key
transposition handled by Serrà's optimal transposition index [S70]; then learned embeddings: MOVE, "learning scalable
embeddings in an Euclidean distance space, using a triplet loss" [S71], CoverHunter "with an embedding size of 128"
[S71], Discogs-VINet trained on "about 1,900,000 versions across 348,000 cliques" with model and features published
[S72], DiVers (2026) for "amateur and user-generated content" [S73], and a 2026 benchmark showing one embedding can
do exact-track and version identification with 10-second queries [S73]. On device: chroma over vDSP is cheap and a
128-d embedding model is a few megabytes on Core ML `[inf]`; Track A already budgets a style embedding per track
[S79]. Expectation `[inf]`: intro, extended, clean, dirty and short edits of one recording are the easy case (same
audio, shifted structure); remixes with new instrumentals are partial; mashups are two works. Measure on Chris's
crate first: five No Broke Boys, three Return of the Mack.

**3. Editing without touching files has precedent.** Lexicon: select any number of tracks, press E, fields that
differ show `<multiple values>` and a typed value "will be set to all tracks on that field"; Recipes for rule-based
changes; `Edit > Undo History`; writing to files is a separate action or an opt-in "Auto Write File (ID3) Tags"
setting with field mappings [S74]. rekordbox keeps edits in its database and writes only the key to the file, from
an off-by-default analysis setting [S75]. Serato edits in the library browser, multi-select included, and writes to
the file's tags [S76]. Mixed In Key writes key, BPM and energy into Key, Comment or Grouping per its Tag Options
[S77]. beets `modify` lists affected items and asks before changing them, `-W` skips the file write; no undo [S78].
Crate-only edits are workable, and rekordbox and Lexicon's default already behave that way. Requirements: key every
entry by content hash so a renamed or moved file keeps its edits; an undo history; `<multiple values>` bulk edit;
and an export (CSV or Picard-style) so a DJ who wants tags written can do it with another tool.

**Verdict.** Public lookup is an optional helper, not core, and not dropped: v1 ships identity from hash, signature
and descriptor, names from tags and file names with the editor; the online switch stays off and only ever suggests.
It earns its place later for original year and genre on untagged rips, where CC0 data can be cached for good.

## Sources (addenda)

- S44 App Store Review Guidelines 5.2.2, 5.2.3: https://developer.apple.com/app-store/review/guidelines/
- S46 Invidious legal thread and API docs: https://github.com/iv-org/invidious/issues/3872 ; https://docs.invidious.io/api/
- S47 NewPipe Extractor; Piped: https://github.com/TeamNewPipe/NewPipeExtractor ; https://github.com/TeamPiped/Piped
- S48 yt-dlp README and PO Token guide; GitHub on the youtube-dl takedown: https://github.com/yt-dlp/yt-dlp ; https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide ; https://github.blog/2020-11-16-standing-up-for-developers-youtube-dl-is-back/
- S49 cobalt and its API docs: https://github.com/imputnet/cobalt ; https://github.com/imputnet/cobalt/blob/main/docs/api.md
- S50 ytmusicapi: https://github.com/sigma67/ytmusicapi
- S51 SerpApi YouTube Search API and legal page: https://serpapi.com/youtube-search-api ; https://serpapi.com/legal
- S52 Apify YouTube Scraper: https://apify.com/streamers/youtube-scraper
- S53 Social Blade Business API (search-indexed; fetch refused): https://socialblade.com/business-api
- S54 vidIQ, NoxInfluencer, Playboard: no public API documentation found (searches Oct 26, 2026)
- S55 Odesli API docs (official page unreachable; search-indexed): http://help.song.link/articles/3037922-api-documentation-v1-alpha-1
- S56 MusicBrainz recording-URL relationship types: https://musicbrainz.org/relationships/recording-url
- S57 Discogs data dumps (CC0): https://data.discogs.com/
- S58 Wikidata P1651; data access and licence: https://www.wikidata.org/wiki/Property:P1651 ; https://www.wikidata.org/wiki/Wikidata:Data_access
- S59 Spotify Developer Terms (v10, 15 May 2025), Developer Policy, quota modes, rate limits: https://developer.spotify.com/terms ; https://developer.spotify.com/policy ; https://developer.spotify.com/documentation/web-api/concepts/quota-modes ; https://developer.spotify.com/documentation/web-api/concepts/rate-limits
- S60 Deezer API terms of use; third-party quota note: https://developers.deezer.com/termsofuse ; https://next.tangled.org/rocksky.app/rocksky/tree/main/deezer
- S61 Apple Developer Program License Agreement 3.3.3(D), 3.3.6(D): https://developer.apple.com/support/terms/apple-developer-program-license-agreement/
- S62 oEmbed providers list (YouTube endpoint): https://oembed.com/providers.json
- S64 Yattee removal discussion (secondary): https://discuss.privacyguides.net/t/remove-yattee/20900
- S65 MusicBrainz AcoustID guide, false positives: https://musicbrainz.org/doc/Guides/AcoustID
- S66 MusicBrainz Style/Release (bootleg, promotion); community on notability: https://musicbrainz.org/doc/Style/Release ; https://community.metabrainz.org/t/unreleased-and-bootleg-albums/75892
- S67 Picard tie-breaking on shared AcoustIDs: https://community.metabrainz.org/t/same-acoustid-causes-picard-to-recognize-songs-incorrectly/766111
- S68 Discogs general rules (search-indexed) and forum on DJ mixes and unofficial remixes: https://support.discogs.com/hc/en-us/articles/360005006334-Database-Guidelines-1-General-Rules ; https://www.discogs.com/forum/thread/343474
- S69 Ellis and Poliner (MIREX 2006-07); Serrà 2007: https://www.ee.columbia.edu/~dpwe/talks/coversongs-poster-07.pdf ; https://archives.ismir.net/ismir2007/paper/000239.pdf
- S70 Essentia cover-song similarity tutorial: https://essentia.upf.edu/tutorial_similarity_cover.html
- S71 MOVE; CoverHunter: https://arxiv.org/abs/1910.12551 ; https://arxiv.org/abs/2306.09025
- S72 Discogs-VI dataset, code and Discogs-VINet: https://arxiv.org/abs/2410.17400 ; https://github.com/MTG/discogs-vi-dataset ; https://github.com/raraz15/Discogs-VINet
- S73 DiVers (2026); unified track and version identification (2026): https://arxiv.org/abs/2608.04543 ; https://arxiv.org/abs/2608.19919
- S74 Lexicon manual: https://www.lexicondj.com/manual/all ; https://www.lexicondj.com/manual/track-editor-manual
- S75 rekordbox writes only key to ID3 (forum and third-party; fetch refused): https://forums.pioneerdj.com/hc/en-us/community/posts/360018010683-ID3-tags-written-to-mp3- ; https://github.com/chrisle/rbxport/pull/391
- S76 Serato editing ID3 tags and beatgrid lock (search-indexed; fetch refused): https://support.serato.com/hc/en-us/articles/227561607-Editing-ID3-Tags ; https://support.serato.com/hc/en-us/articles/14361544561167-Preventing-Changes-to-your-Beatgrids-and-Tracks
- S77 Mixed In Key tag options: https://mixedinkey.com/workflows/add-key-and-bpm-tags/
- S78 beets CLI reference: https://beets.readthedocs.io/en/stable/reference/cli.html
- S79 Track A report (internal): `docs/research/a-on-device-analysis.md`
