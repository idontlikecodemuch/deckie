# Track K: building the crate from burned CDs and albums

Dated Oct 27, 2026. Research report for the Mac app's Desk role and spec 6.3 (crate import). Extends track B
(`b-identification.md`: the pipeline, the source table, step 5 on discs, and both addenda); does not repeat it.
`[inf]` marks inference. Measured on this Mac (M1 Max, 10 cores, macOS 26.6.2) where possible. **No optical drive
is attached** (`drutil list` and `system_profiler SPDiscBurningDataType` both return nothing), so every
disc-speed figure below comes from documentation and user reports; the file-system half of the job was measured
on the sprint's own MP3-CD image.

The problem, in Christopher's words: "We need an easy and fast way to analyze tracks from burned CDs and Albums.
Mike for example has a huge library but it's all burned CDs with obscure tracks, some with tags some without. And
albums, that's even more difficult. That was where I thought YouTube could help. We can do a super fast CD audio
play or data pull." Mike plays a Pioneer CDJ-1000MK3 from MP3 CDs: hundreds of burned discs, edits and ordinary
songs mixed, tags inconsistent.

## Summary

**Recommended flow: "Crate from discs", two queues.** The human and the Mac must never wait on each other.
Queue 1 is attended: insert a disc, Deckie reads it whole to a folder named after the disc (an MP3 CD is a file
copy; an audio CD is a copy of the AIFF files macOS already exposes on the mounted disc, with the TOC, CD-Text and
ISRCs read in the same pass), ejects, next. About 4 to 5 minutes per disc, drive-bound; a second USB drive halves
it. Queue 2 is unattended: hash, analyse, sign, name from tags and file names, overnight. Each track keeps its disc,
folder and track position as its location (the standing principle). Names come from tags and file names at once;
the opt-in lookups run later, per batch, on the Mac; whatever is left sits in a "name these" list with the parsed
guess pre-filled. Identification never blocks analysis.

**Time.** Reading is 3 to 5 minutes per disc for every kind of disc on a 24x USB drive `[inf]`. Analysis is the
real budget: at the measured 12 s per track, a 15-track audio CD analyses in 3 minutes (hidden behind the next
read), a 90-track MP3 CD in 18 minutes on one stream. 100 audio CDs: about 8 attended hours. 100 MP3 CDs: about
8 attended hours of reading plus 30 unattended hours of analysis on one stream, 8 to 10 if the framework runs three
or four tracks at once (to measure). Duplicate files across Mike's discs analyse once (content hash).

**What identification can and cannot do for Mike's discs.** A burned MP3 CD carries no usable TOC, no disc id, no
ISRC and no CD-Text: it is a volume label, folders, file names and whatever ID3 tags the burner wrote. So: tags and
file names name most ordinary songs on the spot; AcoustID (opt-in, Mac) names the commercial original behind an
untagged ordinary song and returns the original or nothing for an edit; nothing in any database names an obscure
edit except Mike, and that is acceptable because Deckie's identity for a track is its hash, signature and analysis,
and the name Deckie shows is the file name the CDJ shows too. His audio CD-Rs from the pre-MK3 years are harder: a
burned audio CD has a TOC no database knows and names only if the burner wrote CD-Text.

**YouTube.** Unchanged: no automated pull of titles or audio for a crate survives YouTube's terms or App Store
guideline 5.2.2 and 5.2.3; the "super fast data pull" is exactly what the terms forbid. What survives is a
hand-triggered "Find on YouTube" link per track carrying the DJ's own words, and resolving a link the DJ pastes.
For naming a crate it is slower than typing.

## 1. Three kinds of disc

| Kind | What it carries | What can identify its tracks | In Mike's library |
|---|---|---|---|
| **Audio CD, commercial** | Red Book TOC (track start sectors, lead-out); per-track ISRC in Q-subcode mode 3 and a media catalogue number in mode 2 where the master had them (IFPI: the carrier "shall (when technically feasible) include the ISRC of each recording", so recommended, not guaranteed) [K1][K2]; CD-Text in the R–W subchannels of the lead-in on a minority of pressings [K3][K4]; no file names, no tags | TOC → MusicBrainz disc id → the whole release in one request; ISRCs → recordings; CD-Text offline; Gracenote if ripped in Music.app | Albums, compilations |
| **Audio CD, burned** | A TOC unique to that burn; CD-Text only if the burner wrote it (Music and iTunes do when "Include CD Text" is ticked) [K5]; no ISRCs `[inf]` (burning apps copy audio, and the source files rarely carry one) | CD-Text; else AcoustID per track (opt-in); else the user | The CDJ-1000 before MK3 played audio CDs only, so his older discs `[inf]` |
| **MP3 or data CD** | ISO 9660 file system, Joliet names on top; volume label; folders; file names; ID3 tags (the CDJ-1000MK3 reads ID3 v1.0/1.1/2.2/2.3/2.4 and "Displays title, album, artist") [K6]; a TOC with one data track, useless for lookup | Tags → file names → crate cross-reference → AcoustID opt-in → user | Most of it: the MK3 wants "the ISO9660 CD-ROM file system", up to 8 folder layers, 99 folders, 999 files per folder, MPEG-1 at 32 to 320 kbps, played "in the order in which they were recorded" [K6]. The sprint's discs are ISO 9660 plus Joliet, numbered BPM folders, ID3v2.3 with album = disc name, TBPM and track number (`pool/build_two_discs.py`) |
| **Continuous mix CD, commercial** | TOC with a marker per track (Sasha & John Digweed, Northern Exposure, 1996: two CDs of 11 tracks, three disc ids attached per medium in MusicBrainz, secondary types Compilation and DJ-mix) [K7][K8]; ISRCs and CD-Text as for any pressing | Disc id → full tracklist; the TOC is the split | Few `[inf]` |
| **Continuous mix CD, home-burned** | One long track, or markers if the burner used a cue sheet | Segment by analysis and by the crate's own recognition catalogue (section 5) | His own and friends' mixes `[inf]` |

## 2. The fastest way to get the audio off a disc on a Mac

**Drives and speeds.** The Apple USB SuperDrive and the LG GP65NB60 class read CD at 24x and DVD at 8x over USB 2.0,
bus-powered [K9][K10]. 1x is 150 KB/s, 75 sectors a second, real time; CAV drives reach the rated figure only at
the outer edge, "roughly 20× average for a completely full disc" at 52x [K11]. Audio extraction is slower than the
data rating on many drives, and secure modes slower still: one owner of a 24x-class LG reports 20 to 30x in iTunes
and 2 to 4x in XLD's secure mode on the same drive; dBpoweramp users report 3 to 4 minutes per disc, about 15 with
multiple secure passes; EAC secure rips of 10 to 40 minutes are "not uncommon" [K12][K13][K14]. Deckie needs
analysis-grade audio, not an archive, so burst reading with a re-read of sectors that return C2 errors (XLD's
burst-with-C2 approach) is the right default, and the DJ who wants archival rips keeps using XLD `[inf]`.

| Path | What it does | Metadata it yields | Time per full (74 min) audio CD | Fit for Deckie |
|---|---|---|---|---|
| **cddafs mount, own code** | macOS mounts an audio CD as a file system: one `N Audio Track.aiff` per track plus a hidden `.TOC.plist` with the sessions and track start blocks [K15][K16]. Copying the files is a burst extraction with no ripper code | TOC from the plist; CD-Text, ISRC and MCN through the IOKit ioctls `DKIOCCDREADTOC`, `DKIOCCDREADISRC`, `DKIOCCDREADMCN`, `DKIOCCDREADTRACKINFO` (present in the macOS 26 SDK; `drutil toc`, `drutil cdtext` and `drutil subchannel` are the shell versions) or through libdiscid, which reads TOC, MCN and ISRC on macOS since 0.3.0 and ships 0.7.0 as a universal2 binary [K17][K18] | 3 to 5 min burst `[inf]` | **Best.** One pass, no third-party ripper, every identifier the disc has |
| **Music.app import** | Names the disc from "the Gracenote media database on the Internet" (a TOC lookup by Apple's design; works offline without names); "Use error correction" option; writes AAC, ALAC, AIFF, WAV or MP3 to the Music library [K19] | Tags from Gracenote; Deckie reads them without network through iTunesLibrary (`ITLibMediaItem.location`, `title`, `artist`, `album`, `beatsPerMinute`, `isDRMProtected`; macOS 10.13+) [K20] | 3 to 4 min at 20 to 30x [K12] | Good for DJs who already rip there, and for the years of rips they already have; Deckie ingests the library |
| **XLD** | Secure ripper or CDParanoia engine, burst with C2 check, AccurateRip, cue sheets, reads CD-Text and ISRC, metadata from gnudb, MusicBrainz or Music's Gracenote result [K21] | Everything, plus a log | 20 to 35 min secure; a few minutes burst [K12][K21] | Archival; recommend, do not embed |
| **cdparanoia** | Linux-first extraction library; XLD embeds its engine; no Homebrew formula resolved on this Mac | None | Slow by design | No |
| **drutil** | DiscRecording's CLI: `toc`, `cdtext`, `subchannel` (MCN, ISRC), `discinfo`, `trackinfo`, `dumpiso`; no audio extraction | TOC, CD-Text, ISRC, MCN | Seconds | Spike tool, not product code |
| **MP3 or data CD as a file system** | Mount read-only and read the files; the deck's own folder and file numbers become the location | Volume label, folders, names, ID3 | 650 MB at 2.5 to 3.5 MB/s effective: 3 to 5 min `[inf]` | **Best**; see the measurement below |

**Measured, file-system side.** The sprint's `CD1 Singalongs.iso` (41 files, 420 MB, ISO Joliet) mounted
read-only in 0.5 s; listing 0.05 s; ID3 tags for all 41 files through ffprobe in 1.9 s; MD5 of every byte in
1.2 s; full decode of every file 18.6 s on one core and 5.9 s eight-way; Chromaprint fingerprints of the first
120 s of all 41 files with Picard's bundled `fpcalc` 1.5.1 in 11.1 s sequential and 1.9 s eight-way. From an SSD, so
the drive is the whole cost on a real disc; the catalogue work per disc is seconds. Spotlight (`mdls`) returned no
audio fields for files on the mounted image, so do not depend on it.

**Can an iPad read a USB CD drive?** No, as a product path. Apple's iPad storage guide covers USB drives and SD
cards and never mentions optical media [K22]; Apple Community's accepted answer is that "iOS/iPadOS fundamentally
does not support connection of any optical media drives - including the Apple SuperDrive" [K23]; a fan wiki says
audio CDs are not supported but an MP3 CD can be browsed if the drive has a "flash drive mode", separate power and
an ISO 9660 or FAT32 disc, and one vendor-affiliated article claims a drive presenting ISO 9660/UDF showed files in
Files while noting the iPad's roughly 900 mA budget [K24][K25]; both unverified. Audio CDs are out on iPad
regardless (no cddafs). What the iPad can do: read files from a USB stick or SSD through Files [K22], and open songs
synced from the Mac's Music library through `MPMediaItem.assetURL` into an `AVAsset` (iOS, iPadOS, Mac Catalyst;
nil for protected items) [K26], so CD rips made in Music.app and synced over are analysable on the iPad.

## 3. Identifying what came off the disc, in the order the product allows

1. **Tags and file names, no network.** `AVAsset` metadata exposes the ID3 frames Deckie needs under
   `id3MetadataTitleDescription`, `id3MetadataLeadPerformer`, `id3MetadataAlbumTitle`, `id3MetadataYear`,
   `id3MetadataBeatsPerMinute`, `id3MetadataInitialKey`, `id3MetadataInternationalStandardRecordingCode`,
   `id3MetadataModifiedBy` (TPE4, the remixer), `id3MetadataTrackNumber`, `id3MetadataPartOfASet`,
   `id3MetadataUserText`, `id3MetadataComments`, `id3MetadataUniqueFileIdentifier`, with iTunes and common
   equivalents [K27]. Then track B's file-name grammar.
2. **Crate cross-reference, no network** (track B step 4): the same hash on five discs is one entry with five
   locations; an edit clusters under its work when the original is in the crate, via the version descriptor
   (P10, to measure).
3. **Commercial audio CDs: the disc.** Disc id (SHA-1 over first track, last track, lead-out and offsets [K28]) →
   `GET /ws/2/discid/<id>?toc=1+12+267257+150+...&inc=recordings+isrcs+artist-credits`: one request returns the
   release, every track title, artist credit and ISRC; an unknown id with a `toc=` falls back to "a fuzzy lookup
   ... to find matching MusicBrainz releases", CD stubs ("an anonymously submitted track list") are returned unless
   `cdstubs=no`, and `media-format=all` widens the fuzzy match beyond CD [K29][K30]. ISRCs read from the disc give a
   second, TOC-independent route: `GET /ws/2/isrc/<isrc>` returns the recordings, one request per track at the
   1-per-second limit, so 15 s per disc [K29]. Both send the disc's identity to MusicBrainz from the DJ's IP; under
   P10 that is the optional helper, on request, never on insert. A recent report says `inc=media+discids` on a
   discid lookup now returns HTTP 400; use the release-level includes only [K31].
4. **CD-Text, offline.** Rare on pressings [K3][K4], present on Music- and iTunes-burned CD-Rs when the box was ticked
   [K5]; read it in the same pass. Whether cddafs names the AIFF files from CD-Text is unconfirmed (forum reports
   say generic names) [K16]; read it directly.
5. **AcoustID, opt-in per batch, Mac.** `client` key, `fingerprint` (first 120 s), `duration`, `meta=recordings`,
   3 requests a second, "free for non-commercial use only" [K32]. Discloses which recordings the DJ owns (track B).
6. **The honest answer** for edits, bootlegs and mixes: no database holds them (track B addendum 1). The name is
   the DJ's own: the file name, the tag, or what they type; the identity is the hash, the signature and the analysis;
   recognition in the booth works from the signature, not from a name.

**What each route returns for Mike's case: a burned MP3 CD of edits and ordinary songs.**

| Route | Returns | Cost |
|---|---|---|
| Volume label, folder names, file names | Always; these are exactly what the CDJ shows, so Deckie's display matches the deck's | 0 |
| ID3 tags | Title, artist, album (BPM, key if a DJ tool wrote them) where the burner tagged; the MK3 shows the same three fields [K6] | 0 |
| TOC, disc id, fuzzy TOC | Nothing: one data track | n/a |
| ISRC, MCN, CD-Text | Nothing: a data disc has none | n/a |
| Crate cross-reference | A second copy of a file names the first; an edit next to its original clusters under the work `[inf]` | 0 |
| AcoustID (opt-in) | Ordinary songs: the work, release group, first year. Pool edits: the original or nothing; AcoustID's own guide lists radio edits and tracks that "only diverge after the two-minute mark" as false positives [K33]. Obscure edits: nothing | 3 req/s; the crate's contents disclosed |
| ShazamKit against Shazam's catalogue (opt-in) | Same coverage as AcoustID, Apple-native, same disclosure `[inf]` | Same |
| "Find on YouTube" link | A browser tab with the DJ's query; nothing returned | A tap per track |
| Mike | The rest, prefilled from the file name | Typing |

## 4. Albums

"Album" means three different things here, each with its own fast path.

- **A commercial CD in the drive.** Section 3 step 3: one disc-id request names the whole album; or Music.app's
  Gracenote on import (Apple's lookup, the DJ's choice, Deckie never makes it). Offline: track count and durations,
  the DJ's own disc name, full analysis.
- **A ripped folder.** Tags carry album, track number and year on 95, 98 and 71 percent of the sprint's
  compilation rips (track B); nothing to do but read them. For a folder with titles but no album, MusicBrainz
  release search by album title and track count sharpens the year and the artist credits (search syntax: the
  `release` endpoint with a Lucene query; the exact field for track count is to confirm against the search docs)
  [K34]; Discogs for compilations and 12" mixes (track B).
- **A purchased download.** Bandcamp, iTunes and Beatport files arrive tagged, often with ISRC and MusicBrainz
  ids in the file; nothing to do.

**Apple's frameworks, no network.** `AVAsset` metadata for any file the DJ owns (above); `iTunesLibrary` on macOS
for the Music library (location, title, artist, album, BPM, DRM flag) [K20]; `MediaPlayer` on iOS and iPadOS for
the synced library with `assetURL` into `AVAsset` [K26]. `MusicKit` is not a tagging source (PLA 3.3.6(D), track B
addendum). `DiscRecording` is the burning side (`DRCDText`, `DRDevice` media keys); reading goes through the IOKit
ioctls or libdiscid.

## 5. Continuous mix CDs

**Commercial mix CDs** have a TOC marker per track and a disc id; MusicBrainz tracklists them as ordinary tracks with
the DJ-mix secondary type [K7][K8]. The TOC is the split; each TOC track is analysed as a track with the usual
caveat that the analysis sees a blend at both ends `[inf]`.

**Home-burned mixes** are one long track. Three ways to split, all on device:

1. **Deckie's own recognition, turned on a file.** The crate's ShazamKit catalogue already names what the booth
   microphone hears; run it over the mix file instead and every segment that is a track in the crate comes back
   with a name and a position, pitched or not (P11's matchers cover the fader range). Edits and bootlegs that live in
   the crate are found this way, which no public database could do. Verify that signature generation from a file
   and offline matching against a custom catalogue behave as they do live (`SHSignatureGenerator`, `SHSession`).
2. **Analysis boundaries** where recognition finds nothing: the framework's sections (recall 1.00 of the lab's 8-bar
   lattice boundaries), the tempo segments (a tempo change is a track change in a mix), the key segments and the
   loudness curve (`stage1-results.md`). A blend has no single boundary; take the bar where the incoming track's
   match first holds, else the bass swap `[inf]`.
3. **The sprint's cue sheets.** A mix Deckie (or the lab) rendered has its cue sheet already:
   `docs/discs/Mix 1 - Halloween Mix - full.cue` lists 66 tracks with `TITLE`, `PERFORMER` and `INDEX 01 mm:ss:ff`
   (75 frames a second), written by `mixer/render.py`; the matching `.txt` adds BPM, Camelot key, join type and
   pitch per entry. Burned with that cue, the disc gets TOC markers too.

**What exports need.** CUE: `INDEX 01` in minutes, seconds and frames. Mixcloud: `sections-N-artist`,
`sections-N-song`, `sections-N-start_time` "in whole seconds", artist and song required per track; audio streams are
not available through the API, and read-back of sections is undocumented (track B open question) [K35].
1001Tracklists has no public API (track B).

## 6. Whether anything YouTube-shaped survives

Confirmed, no change from track B and its addendum: the consumer Terms forbid access "using any automated means",
the API Terms cap a project at 100 `search.list` calls a day for all its users and require stored results to be
deleted or refreshed within 30 days, the Developer Policies forbid obtaining "scraped YouTube data", and App Store
guideline 5.2.2 requires permission under the third party's terms while 5.2.3 bars saving or converting media from
YouTube (track B S1, S4, S32, S44). Christopher's "super fast CD audio play or data pull" is the route the terms and
Google's PO-token blocking are aimed at. Compliant and useful, both hand-triggered: a "Find on YouTube" button on
a track that opens `youtube.com/results?search_query=<the DJ's own words>` in the YouTube app, and resolving a link
the DJ pastes with `videos.list` (1 unit) to show a title the DJ may accept as their own name, storing nothing. For
a crate of thousands of files neither is faster than reading tags and typing the rest. MusicBrainz and Discogs,
both CC0, hold YouTube links per recording for a "listen to confirm" button without reading YouTube at all.

## 7. "Crate from discs": the Mac app flow

1. **Insert.** The app watches for mounts (cddafs, ISO 9660, UDF). It shows the volume label or "Audio CD, 14
   tracks, 71:12" and asks for nothing.
2. **Read, one pass.** Audio CD: copy the AIFF files, read `.TOC.plist`, CD-Text, ISRCs and MCN; compute the disc id.
   MP3 CD: copy the tree, read tags and the sprint's manifest if present. Deckie-made discs come back fully named
   from their own tags. Progress is a single bar; the disc ejects itself when done. If a sector will not read, the
   track is marked and the pass moves on; the DJ can re-read later.
3. **Next disc.** The attended loop is insert, wait 4 to 5 minutes, swap. A second drive doubles throughput; the
   app queues per drive.
4. **Analyse, unattended.** Hash and collapse duplicates across discs; analyse unique files (grid, tempo and key
   segments, structure, vocal, loudness, style); generate one signature per track; parse names. Runs overnight or
   while the DJ keeps feeding discs.
5. **Name.** Tags and file names first; "12 of 1,340 tracks need a name" with the parsed guess prefilled; one
   switch for the online helpers, per batch, Mac only: MusicBrainz by disc id and ISRC for commercial discs,
   AcoustID for untagged ordinary songs; the YouTube link per track. Every entry keeps disc, folder and track position.
6. **Hand to the iPad.** The crate file (about 10 KB per track, 45 KB more with the signature) goes to the iPad; no
   audio needs to travel, because recognition and picks run from the crate, not the files.

| Disc | Read (attended) | Analyse (unattended) | Per disc, wall | Per 100 discs |
|---|---|---|---|---|
| Audio CD, 15 tracks, 74 min | 3 to 5 min burst `[inf]` + 0.5 min handling | 15 × 12 s = 3 min, hidden behind the next read | 4 to 6 min | 7 to 9 attended hours; analysis keeps up |
| MP3 CD, 90 tracks, 650 MB | 3 to 5 min `[inf]` + 0.5 min | 90 × 12 s = 18 min on one stream; 5 to 6 min if 3 to 4 run in parallel `[inf]` | 4 to 6 min attended | 7 to 9 attended hours; 30 unattended hours on one stream, 8 to 10 in parallel; less with duplicates |
| Continuous mix, 1 track, 74 min | 3 to 5 min `[inf]` | Unknown for a 74-min file; plus one recognition pass | 4 to 6 min attended | As audio CD, plus the unmeasured analysis |

The 12 s is the stage-1 median in the iOS 27 simulator on this Mac (p90 17 s); the native Mac figure and the
framework's parallelism are the two numbers that decide whether the MP3-CD case is read-bound or analysis-bound.

**What the iPad can and cannot do.** Cannot read any disc. Can: receive the crate; read a USB stick or SSD of
already-ripped folders through Files and analyse them with the reduced engine (D11); analyse songs synced from the
Mac's Music library; name, edit and save pairs. The Mac app is the disc reader; the iPad is where the crate is used.

## 8. Open questions

- **Measure with a drive.** Buy a bus-powered 24x USB drive (about $30) and time on this Mac: a cddafs copy of a
  full audio CD; ISRC reads per track; a 650 MB data CD; whether cddafs names tracks from CD-Text; spin-up to mount.
- **Framework throughput on the Mac, native:** seconds per track with 1, 2, 4 and 8 concurrent analyses, and the
  behaviour on a 74-minute file. Decides the MP3-CD budget.
- **libdiscid or the ioctls directly.** libdiscid is LGPL (verify the exact licence); the four ioctls plus the
  SHA-1 recipe [K28] avoid the dependency.
- **ShazamKit from a file against the crate's catalogue:** confirm `SHSignatureGenerator` plus `SHSession` works
  offline and faster than real time; it is the mix-splitting tool.
- **AcoustID coverage on Mike's actual discs:** with his consent, fingerprint one disc and count hits by category
  (ordinary song, pool edit, obscure edit).
- **MusicBrainz:** the release-search field for track count; the `inc=media+discids` 400 report [K31]; the
  commercial tier (track B).
- **Music.app's Gracenote lookup:** when the DJ chooses that path, say that Apple looks the disc up; Deckie does not.
- **iPadOS and "flash drive mode" drives:** one $30 test for curiosity; not a product dependency.
- **Deckie-written manifests on discs it burns** (track B step 5): format, and whether to write the crate ids into
  the ID3 `UFID` frame so a disc names itself on return.

## Sources

Internal: `docs/product/spec-condensed.md` v0.5; `docs/product/00-decisions.md` (D3, D10, D11, D13, P2, P6, P10,
P11); `docs/research/b-identification.md` (source table, section 4 step 5, both addenda, S1, S4, S32, S35, S36,
S44, S65); `docs/architecture/stage1-results.md` (12 s per track, sections recall); `pool/README.md`,
`pool/build_two_discs.py`; `docs/discs/MANIFEST.md`, `docs/discs/Mix 1 - Halloween Mix - full.cue` and `.txt`;
`mixer/render.py` lines 1219 to 1227; `docs/research/codex-community.md` section 1 (unreadable track lists, "no
chance I could read 5 tracks in a dimly lit booth"). Measurements: this Mac, Oct 27, 2026, as described in section 2.

- K1 Compact Disc subcode (Q modes 1 to 3, CD-Text in R–W): https://en.wikipedia.org/wiki/Compact_Disc_subcode
- K2 IFPI ISRC Handbook, 4th ed., "Encoding of ISRC" and A.8: https://isrc.ifpi.org/images/downloads/ISRC_Handbook.pdf
- K3 CD-Text rarity (BASS docs, track B S36): https://www.un4seen.com/doc/basscd/BASS_CD_GetID.html
- K4 CD-Text and ISRC on masters (mastering engineer's page): https://pure-music.co.uk/?p=356
- K5 Music on Mac, burn settings, "Include CD Text": https://support.apple.com/guide/music/mus3f187e315/mac ; https://support.apple.com/guide/music/mus890140c28/mac
- K6 Pioneer CDJ-1000MK3 operating instructions, discs and MP3 files: https://www.manualsdir.com/manuals/486517/pioneer-cdj-1000-mk3.html?page=10 ; https://www.bplsv.com/manfacturers/sound/manuals/pioneer/CDJ-1000MK3_OperatingInstructions0216.pdf
- K7 MusicBrainz release search, Northern Exposure (JSON, fetched Oct 27, 2026): https://musicbrainz.org/ws/2/release/?query=release:%22Northern%20Exposure%22%20AND%20artist:%22Sasha%22%20AND%20format:CD&fmt=json&limit=3
- K8 MusicBrainz release group types (DJ-mix, Compilation, Mixtape/Street): https://musicbrainz.org/doc/Release_Group/Type
- K9 Apple USB SuperDrive specifications (retailer listings; Apple's page not found): https://www.shi.com/product/30265470/Apple-USB-SuperDrive ; https://ldlc.com/en/product/PB00135731.html
- K10 LG GP65NB60 specifications: https://solutions.lg.com/us/digital-storage/lg-GP65NB60 ; https://www.bhphotovideo.com/c/product/1098340-REG/lg_gp65nb60_8x_dvdrw_mdisc_slim.html
- K11 CD-ROM transfer rates, CAV average, Red Book playing time: https://en.wikipedia.org/wiki/CD-ROM
- K12 XLD vs iTunes speeds and error correction (user reports): https://forums.macrumors.com/threads/xld-vs-music-app-cd-ripping.2415123/ ; https://community.naimaudio.com/t/cd-rip-experience-xld-vs-itunes/3111 ; https://www.macworld.com/article/210831/four-reasons-rip-cds-without-itunes.html
- K13 dBpoweramp forum, ripping time per CD: https://forum.dbpoweramp.com/forum/dbpoweramp/cd-ripper/37153-cd-ripping-speed ; https://forum.dbpoweramp.com/forum/dbpoweramp/cd-ripper/37230-how-long-to-rip-flac-uncompressed
- K14 EAC secure-mode times (user reports): https://forums.stevehoffman.tv/threads/ripping-with-exact-audio-copy-what-are-acceptable-speeds.1083789/
- K15 Apple cddafs source (`.TOC.plist`, `N Audio Track.aiff`): https://opensource.apple.com/source/cddafs/cddafs-251/AppleCDDAFileSystemVNodeOps.c.auto.html ; Apple AudioCDSample: https://developer.apple.com/library/archive/samplecode/AudioCDSample/Listings/AudioCDSample_AudioCDSample_c.html
- K16 How Macs see audio CDs (user reports on generic names): https://forums.whathifi.com/threads/how-macs-%E2%80%98see%E2%80%99-audio-cds.81422/latest ; https://hairersoft.com/forum/viewtopic.php?p=10450
- K17 libdiscid (feature matrix, 0.7.0 universal2): https://musicbrainz.org/doc/libdiscid
- K18 libdiscid ChangeLog ("Added API for reading ISRCs and MCNs (implemented on Windows and Mac OS X)", 0.3.0; "fix ISRC reading on Mac OS X again", 0.5.2): https://raw.githubusercontent.com/metabrainz/libdiscid/master/ChangeLog
- K19 iTunes and Music CD import, Gracenote, Get Track Names, offline import: https://support.apple.com/en-ca/guide/itunes/itns2976/mac ; https://support.apple.com/guide/music/mus2976/mac
- K20 iTunesLibrary, ITLibMediaItem: https://developer.apple.com/documentation/ituneslibrary/itlibmediaitem
- K21 XLD features and change log: https://tmkk.undo.jp/xld/index_e.html
- K22 Apple, connect external storage devices to iPad (no optical media listed): https://support.apple.com/guide/ipad/external-storage-devices-ipad75b7b23f/ipados ; LaCie on iPadOS external storage: https://www.seagate.com/support/kb/lacie/ipados-external-storage-supported-functions/
- K23 Apple Community, external CD drive with an iPad (LotusPilot, Jun 5, 2023): https://discussions.apple.com/thread/254905422 ; https://discussions.apple.com/thread/252067789
- K24 Apple USB SuperDrive fan wiki, iPhone and iPad section (unverified): https://apple.fandom.com/wiki/Apple_USB_SuperDrive
- K25 Vendor-affiliated article claiming a data disc in Files on iPad (unverified; page not retrievable on fetch): https://www.aliexpress.com/s/wiki-ssr/article/dvd-drive-for-ipad
- K26 MPMediaItem.assetURL: https://developer.apple.com/documentation/mediaplayer/mpmediaitem/asseturl
- K27 AVMetadataIdentifier, ID3, iTunes and common identifiers: https://developer.apple.com/documentation/avfoundation/avmetadataidentifier
- K28 MusicBrainz Disc ID calculation (track B S35): https://musicbrainz.org/doc/Disc_ID_Calculation
- K29 MusicBrainz API: discid lookup, `toc=`, fuzzy lookup, `cdstubs`, `media-format`, isrc lookup, rate limit: https://musicbrainz.org/doc/MusicBrainz_API
- K30 MusicBrainz CD stub: https://musicbrainz.org/doc/CD_Stub
- K31 Report of HTTP 400 on `inc=media+discids` for discid lookups (single report, Oct 2026): https://github.com/KurzonDax/newznab-tmux-kd/issues/1164
- K32 AcoustID web service: https://acoustid.org/webservice
- K33 MusicBrainz AcoustID guide, false positives (track B S65): https://musicbrainz.org/doc/Guides/AcoustID
- K34 MusicBrainz API search syntax: https://musicbrainz.org/doc/MusicBrainz_API/Search
- K35 Mixcloud API, upload sections and start_time: https://www.mixcloud.com/developers/
