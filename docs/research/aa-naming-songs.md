# Research AA: naming a song, and collecting the facts about it

Dated Nov 13, 2026. Web research, reading and design on paper only: no code, no build, no measurement, no commit.
It follows D30 (names and facts may be looked up only when the DJ asks; before any lookup is built, the services'
terms for a paid app, exactly what each sends, and the public privacy line reworded) and builds on letter B (the
source table and the file-name grammar), letter K (discs, disc ids, the flow "crate from discs") and letter W
section 6 (a first pass at this job). It does not repeat them: each finding below says whether it confirms, extends
or corrects one of them.

Tags: [read] = I opened the page today and the quote is from it; [snip] = seen only through a search summary, the
page itself did not open; [B], [K], [W] = taken from that letter, not re-opened; [inf] = my inference, with the
reasoning; [unverified] = I could not open or confirm it. Source numbers are AA1, AA2 and so on, listed at the end.
Not legal advice: every reading of a service's terms here needs the attorney before anything ships.

## In plain words

**Naming a song** is Desk working out what a song is when it arrives with no usable title or artist. The wider job
is collecting a song's facts: artist, title, version or remix, release, label, year, genre and artwork.

There are three places a name can come from.

1. **The disc or the file itself.** A **tag** is a small label stored inside a music file (title, artist and so
   on). **CD-Text** is the same idea for a music CD: names written on the disc beside the music, which some CD
   players show. The **table of contents** is the list every music CD carries of how many songs it has and how
   long each is. An **ISRC** is a serial number record companies give a recording. A **cue file** or tracklist is
   a text file beside the music that lists the songs in order.
2. **The DJ's own computer.** The libraries of DJ and music programs, and a copy of the same recording elsewhere
   in the crate that already has a name.
3. **Outside.** A **lookup** asks a service on the internet. It can ask by **text** (send the words, get facts
   back), by **disc** (send the disc's song lengths, get the album back) or by **sound** (send a **fingerprint**,
   a short description of how the recording sounds that cannot be played back, and get a name back). A
   **catalogue** is the list of music a service knows.

Desk already does everything in groups 1 and 2 except reading CD-Text. This letter is mostly about group 3 and
about the screens a DJ meets.

The short answers:

- **Which outside sources can a paid app use today?** Two, both by paying a published monthly price with no
  negotiation: MusicBrainz (text and disc; from 100 dollars a month once Deckie is public, nothing before) and
  AcoustID (sound; 50 euros a month). Discogs looks usable for its public-domain facts with a credit line, but I
  could not open its terms page today. Shazam's catalogue is usable on the Mac only, with conditions. Deezer,
  Last.fm, Spotify, Apple's iTunes Search and GnuDB are closed to a paid app or to this use. Beatport, Gracenote
  and ACRCloud need a contract. AudD uploads the song itself, so it is out.
- **Will a lookup name the hard songs?** Mostly not. Edits, bootlegs and white labels are in no catalogue. A
  lookup rescues the ordinary released song that lost its tags, and fills in facts (year, label, release) for
  songs that already have a name. Letter W said this; nothing found today changes it.
- **Can Desk read the names on a burned music CD?** Yes, on all three systems, with the system's own calls and
  about a page of Deckie's own code to decode the answer. No library has to be licensed. But the names are there
  only if the burning program wrote them, and the most common one on a PC, Windows Media Player, never did.
- **Does a DJ need to listen in Desk to name a song?** Yes, a small "Listen" button is worth having. A DJ knows
  a song by ear in a few seconds, it sends nothing anywhere, and it is the only method that works for a bootleg.
- **What about the wrong version?** A lookup that returns the radio edit for an extended mix has given a wrong
  name. The song's length is the cheapest check: a candidate whose length differs by more than a few seconds is a
  different version and must not be filled in by itself.
- **The privacy line** has to change the day any lookup ships. Section 5 has wording that stays true.

## 1. Every way to name a song

### 1.1 From the disc or the file itself

All built except where marked. This confirms W 6.2 and K section 3 and adds the detail a builder needs.

| Way | What it gives | Notes |
|---|---|---|
| **Tags in the file** | Title, artist, album, year, genre, label, number, ISRC, artwork | ID3 in MP3 and AIFF; Vorbis comments in FLAC and Ogg; "atoms" in M4A; a text chunk in WAV, often missing. The frames that matter for naming: title (`TIT2`), the version line (`TIT3`), artist (`TPE1`), remixer (`TPE4`), album (`TALB`), label (`TPUB`), ISRC (`TSRC`), number (`TRCK`), disc of a set (`TPOS`), picture (`APIC`) [AA40]. Section 6 says how seldom the version and remixer frames are filled |
| **Embedded artwork** | A cover picture inside the file | The DJ's own copy. Showing it sends nothing and needs nobody's permission. The only artwork source with no terms attached |
| **ISRC** | A serial number for the recording | In the tags of bought downloads [K]; on pressed CDs in the disc's sub-code, read by libdiscid on Mac, Windows and Linux [AA28]. By itself it names nothing; it is the best key for a lookup, because one ISRC is one version |
| **File name** | Artist, title, version, number | By pattern, with a preview. Built |
| **Folder** | Album, sometimes artist | A hint. Built |
| **Tracklist and cue files** | Every song's name, in order | `.cue`, `.m3u`, numbered text lists. Built. The only thing that names the songs inside a continuous mix [K] |
| **CD-Text** | Disc title, performer, and a title and performer per song | **Not built.** Section 2 |
| **The disc's table of contents** | How many songs and how long each is | Names nothing by itself. It is the key for a disc lookup (pressed discs only), and Desk can use it with nothing leaving: to know the same disc when it comes back, and to line a disc up against a playlist of the same lengths already on the computer [inf] |

### 1.2 From the DJ's own computer

Built, per D30: the libraries of DJ programs, and a named copy of the same recording. Two additions [inf]:

- **The music program's playlists as the answer to a burned disc.** A burned music CD was almost always made from
  a playlist in iTunes, Music, Windows Media Player or a burning program. If that playlist, or just the songs, is
  still on the computer, the disc's songs are copies of files that have names. Desk's same-recording check (D24)
  already finds them once the disc's audio has been read; the table of contents can shortlist the playlist first
  (same number of songs, same lengths to the second). For a DJ whose discs came from this computer, this is
  likely to name more burned discs than CD-Text and every lookup together. To be measured on real discs.
- **A list the DJ pastes or types.** Many DJs keep a typed or handwritten list per disc. One box that takes a
  list, one song per line, and lines it up with the disc's songs in order is the cue-file route done by hand
  (section 3.6).

### 1.3 From outside: what each service's own pages say

Read Nov 13, 2026. "Store" means keep the result in the crate file for good. "Open" means a paid, closed-source
app may use it now at a published price or free; "sign-up" means a form and a published price, no negotiation;
"contract" means someone has to say yes; "closed" means the terms forbid this use.

**By text**

| Service | What leaves the computer | Paid closed-source app | Key or account | Rate limit | Store, and credit | Windows and Linux | Dance music, remixes, edits | Status |
|---|---|---|---|---|---|---|---|---|
| **MusicBrainz** (search, ISRC lookup) | The search words or the ISRC; the DJ's network address; the app's name, version and contact. Its privacy page: logs hold "your IP address, your browser's (or API client's) "User-Agent" string" and "which page (or API endpoint) you requested with which parameters"; no retention period is stated [AA4] | "Non-commercial use of this web service is free." [AA1] A company "with a current revenue stream or an expected revenue stream" picks a supporter tier: Stealth start-up, "$0.00/month and up", for those "not publicly offering their services"; Bronze, "$100.00/month and up", "for popular mobile apps and for small to mid-size start-ups with public products"; Silver 600, Gold 1,250 [AA3] | No key. No account for the DJ. The app must send a User-Agent of the form "Application name/<version> ( contact-url )" [AA2]. Deckie needs one MetaBrainz account to sign up as a supporter | "(on average) 1 request per second" per network address; over it, "all your requests will be declined (http 503)" [AA2]. Each DJ is their own address, so the limit is per DJ | "The core data of the database is licensed under the CC0", so it may be kept and no credit is required. The rest (tags, ratings, and so genres drawn from tags [inf]) is non-commercial share-alike: do not store it [AA5] | Yes, a web address | Wide for released music. A remix and an edit are each their own entry by rule [AA43]. Thinner than Discogs for 12-inch dance releases [B]. Bootlegs: a few. Pool edits: no | **Open by sign-up.** Free until Deckie is public, then from 100 dollars a month. Confirms B; corrects W, which marked the licence unverified |
| **Cover Art Archive** (pictures for MusicBrainz releases) | The release's id; the address | No terms for apps on the page I could open. The pictures belong to their owners; no licence is stated there [AA6] | None | "There are currently no rate limiting rules in place" [AA6] | **Do not store.** Nothing I read grants the right [inf] | Yes | Follows MusicBrainz | **Unclear.** Show the file's own embedded artwork instead |
| **Discogs** | The search words; the address; the app's key | Terms of May 27, 2025. Data is split into public-domain (CC0) data and "Restricted Data", and Restricted Data may not be used "for any commercial purposes" nor passed to third parties [AA7, snip]. Titles, dates, formats, tracklists and credits are the CC0 part [B] | An app key and secret from a Discogs developer account, carried in the app. Search needs it [unverified]. No account for the DJ | 60 a minute with a key, 25 without, per address [B] | CC0 facts: yes, with "Data provided by Discogs." beside them and a line that Deckie is not affiliated [B]. Pictures: restricted, no | Yes | The best public catalogue for vinyl, 12-inch mixes, white labels and compilations [B]. Entered by collectors, so a bootleg pressing is often there; a digital-only edit is not | **Probably open, with credit.** The developer and terms pages refused every fetch today (403), as they did for letter B. Someone must read the terms page in a browser before it is built |
| **Deezer** | Search words; address | "the use of the Services is strictly limited for a non-commercial purpose and in a non-commercial environment" [AA8]. "There is no paid API"; partners apply by form [AA9] | Terms must be accepted while logged in [AA10]. Reports that new access for individuals is paused [AA11, snip] | "there is a query quota"; lifting it "is not possible, unless there is a commercial agreement" [AA9] | Not granted | Yes | Wide; tells a title's version apart in its own field [unverified] | **Closed** without a partnership |
| **Apple's iTunes Search** | Search words; address | The only use the page grants is promotion of store content: artwork and previews "only to promote store content and not for entertainment purposes", placed beside a store badge [AA12]. Nothing grants keeping its facts as tags | None | About 20 calls a minute [AA13, snip; the current page would not open] | Not granted; previews must not be "downloaded, saved, cached" [AA12] | Yes | Wide for released music; versions sit in the title in brackets | **Closed for this use** [inf]. Apple's Music API is ruled out for tagging in letter K |
| **Last.fm** | Search words; the app's key | "You are permitted to use the Last.fm Data solely for non-commercial purposes"; otherwise "you must apply for a commercial use agreement" [AA14] | App key | Set by Last.fm, unpublished | A cap of "100 MB"; a "powered by AudioScrobbler" button; no "images and/or artwork" [AA14] | Yes | Listener tags for genre; weak on versions [inf] | **Closed** without an agreement |
| **Spotify** | Search words; the app's id | Terms version 10, May 15, 2025: "Do not store Spotify Content indefinitely"; only "temporary caching of: metadata and cover art"; "Do not transfer Spotify Content to third parties" [AA15] | App id, and a logged-in Spotify user for most calls [unverified] | Unpublished | No | Yes | Wide | **Closed.** Lexicon's manual now lists only Sonovault and Beatport as its sources, not Spotify [AA33] |
| **Beatport** | Search words; partner key | Partner access only; no public tier found. Letter B's reading: "available for non-commercial use only" without "express written permission" [B; AA16, snip] | Partner key | Unpublished | By contract | Yes | The catalogue DJs trust for dance music: a mix name on every song, remixer, label, genre | **Contract** |
| **Traxsource, Juno, Bandcamp, 1001Tracklists** | n/a | No public catalogue interface (Bandcamp and 1001Tracklists per letter B; Traxsource and Juno not found today [unverified]). The DJ taggers that use them read the web pages, which Deckie would not do | n/a | n/a | n/a | n/a | Strong | **Closed** |

**By disc**

| Service | What leaves | Paid closed-source app | Key or account | Rate limit | Store, and credit | Windows and Linux | Coverage | Status |
|---|---|---|---|---|---|---|---|---|
| **MusicBrainz disc id** | A code made from the disc's song positions, and the positions themselves when the fuzzy match is asked for [K]; address; app name | As MusicBrainz above | As above | 1 a second; one request names a whole disc | CC0: yes | Yes; libdiscid reads the disc on all three (LGPL 2.1 or later, so it ships only as a separate library file under Deckie's licence rule, or its short recipe is rewritten) [AA28] | Pressed CDs: usually, including mixed compilations [K]. If unknown, "a fuzzy lookup" finds "tracklists that are within a similar distance", and "CD stubs" typed in by anyone are returned too [AA1]. A burned disc: never, unless it is a straight copy of a pressed one [inf] | **Open by sign-up**, as above |
| **GnuDB** (the old freedb data) | The disc's lengths, plus a greeting with a user name, a host name and the app's name [inf, the CDDB protocol]. Reported to require an email address since a policy change [AA17, snip] | Its privacy page is reported to say the licence "does not include commercial use of gnudb.org, including its contents, or any derivative use" [AA17, snip]. The site answered only with a browser check today | An email [snip] | Not found | The old freedb data was published under the GPL, a licence Deckie's rule never ships [AA17, snip] | Yes | Pressed CDs, typed by users over decades; uneven | **Closed** on what I could see. Letter W listed it as free; this corrects that |
| **Gracenote** (what Apple's Music app asks) | A disc code | Licence by negotiation; no public programme found today [unverified] | By licence | By licence | By licence | By licence | The largest disc database | **Contract.** A DJ who imports a CD in Music has already used it, and Desk reads those tags from the files with nothing leaving [K] |

**By sound**

| Service | What leaves | Paid closed-source app | Key or account | Rate limit | Store, and credit | Windows and Linux | Dance music, remixes, edits | Status |
|---|---|---|---|---|---|---|---|---|
| **AcoustID** with Chromaprint | A fingerprint of the first two minutes [K], "duration of the whole audio file in seconds", and the "application's API key" [AA18]; the address | "This service is provided for free for non-commercial use only." A commercial product subscribes: Small, "€50/month", "1 million searches", "no rate limiting", "free trial (10k searches)"; Medium 100 euros for 15 million [AA19] | The app's own key, registered once. None for the DJ | Free tier: "Do not make more than 3 requests per second" [AA18]; paid: none | The answer is a MusicBrainz id, and that mapping is "released under CC0 1.0"; the rest of AcoustID's data is share-alike, so store the MusicBrainz id and the facts fetched with it, not AcoustID's own id [AA20] | Yes. Chromaprint's own code is MIT but, with the FFmpeg parts in it, "should be therefore considered to be licensed under the LGPL 2.1 license" [AA21]: ship it as a separate library file or run its `fpcalc` program beside Desk | 94.9 million fingerprints, 30.6 percent linked to a named recording; 88.2 percent of searches find something [AA22]. It matches the same recording only: its own guide warns of the wrong version for radio edits [K]; Picard users report a remix matched to another artist's song [AA30, snip]. Pool edits: the original or nothing. Bootlegs: nothing | **Open by sign-up**, 50 euros a month. Confirms B's price; corrects W, which said the price was not published |
| **Shazam's catalogue** through ShazamKit | A signature. Apple: "Audio is not shared with Apple and audio signatures cannot be inverted" [AA23]. It goes to Apple, from the DJ's address | Needs Deckie's Apple developer membership, the ShazamKit service switched on for the app, and a signing key [AA23]. No per-lookup price found [unverified]. Apple staff, 2022: if you match against the catalogue "and displaying song metadata then you need to provide a link to that content in Apple Music"; the Shazam mark is optional [AA24]. A clause quoted on a contracts site forbids using the results "for the purpose of improving or creating another audio recognition service" [AA25, snip; also letter L] | Deckie's membership. None for the DJ | Not published [unverified] | Not stated in anything I could open [unverified]. For the attorney, with the clause above: Deckie is building its own recognition (letter W), and although a looked-up name does not improve it, the two must be kept visibly apart | **No.** "iOS, iPadOS, macOS, tvOS, visionOS, and watchOS", and Android [AA23] | The largest catalogue, with a large dance catalogue since 2013 [W]. Names the released original of an edit, not the edit | **Open on the Mac only**, with a link to Apple Music beside every result |
| **ACRCloud** | A fingerprint made by its code, or the audio | Commercial; its pricing page showed nothing to a fetch today [unverified] | Account and key | By plan | By plan | Its code is offered for the main systems [unverified] | Very large; no figures by genre | **Contract or account**; not priced |
| **AudD** | **The audio itself**: "a URL, a file upload" or encoded audio [AA26] | "from $2 to $5 per 1000 requests"; "First 300 requests for free" [AA26] | Account and token | By plan | Not stated | Yes | "Our DB contains 160 million songs" [AA26] | **Out.** It uploads the song. Confirms W |
| **Gracenote, Audible Magic, SoundHound, seeqnc (behind Beatport's Track ID)** | Fingerprints | By negotiation; none has a public price or self-serve programme that I found [unverified] | n/a | n/a | n/a | n/a | Beatport's Track ID, May 2026, is built for blends and club recordings but lives in Beatport's own app [W; AA27, snip] | **Contract** |

### 1.4 What this adds up to

- **Open to Deckie today:** MusicBrainz, for text and for discs, at no charge while Deckie is not public and from
  100 dollars a month after; AcoustID, for sound, at 50 euros a month with the first 10,000 searches free. Both
  are published prices on a sign-up page. Both give answers Deckie may keep in the crate file with no credit line.
- **Probably open, to confirm by reading one page in a browser:** Discogs' public-domain facts, with its credit
  line. No pictures.
- **Open on one system:** Shazam's catalogue, on the Mac, with an Apple Music link beside results and a question
  for the attorney.
- **Need a contract:** Beatport, Gracenote, ACRCloud, Deezer (as a partner), Last.fm (a commercial agreement).
- **Closed for this use:** Spotify, Apple's iTunes Search, GnuDB, and every store with no public interface.
- **Out on principle:** AudD.
- **Artwork from outside** has no clean source. The file's own embedded picture is the answer.
- **Nothing here names an edit or a bootleg**, except Discogs for a bootleg that was pressed on vinyl.

One point for the App Store privacy label (the "Data Not Collected" line, P8). Apple's definition: ""Collect"
refers to transmitting data off the device in a way that allows you and/or your third-party partners to access it
for a period longer than what is necessary to service the transmitted request in real time", and partners are
vendors "whose code you've added to your app" [AA29]. A lookup sent straight from the DJ's computer to
MusicBrainz, with none of MusicBrainz's code in Desk and nothing passing through Deckie, looks to sit outside that
[inf]; a fingerprint service whose own code is built in may not. The attorney's call. Keeping every lookup in Desk
and none in the booth leaves the iPad app's label untouched either way.

## 2. Reading a burned music CD

### 2.1 What CD-Text is

CD-Text is stored "in the subchannels in the lead-in area of the disc", in packs of 18 bytes, each pack typed:
0x80 title, 0x81 performer, 0x82 songwriter, 0x83 composer, 0x84 arranger, 0x85 message, 0x86 disc id, 0x87 genre,
0x8E the disc's barcode and each song's ISRC, 0x8F a size record that also says which character set is used
(plain ASCII, Western European, or Japanese) [AA44]. The lead-in is the stretch of disc before the first song. A
drive hands the packs over when it is sent the standard command "read table of contents", in the format numbered 5
[AA45, AA46]. So reading CD-Text is one command to the drive and then decoding the packs. The decoding is the same
on every system and belongs in Deckie's shared core: about a page of code, no library [inf].

### 2.2 The call on each system

| System | The call | What a Swift program uses | Licence | Tools to check against |
|---|---|---|---|---|
| **macOS** | `DKIOCCDREADTOC` on the disc's raw device with the format set to 5 (`kCDTOCFormatTEXT = 0x05`) returns the raw packs. Apple's own header says the data "returned by the IOKit ioctl DKIOCCDREADTOC with format=5" can be parsed with `DRCDTextBlockCreateArrayFromPackList` in the DiscRecording framework [AA45, snip of Apple's headers] | `ioctl` from Swift, with the request number written out because Swift does not import that kind of C macro [inf]; then Deckie's decoder, or Apple's parser on the Mac | The system's own. Nothing to ship | `drutil cdtext` in Terminal [K] |
| **Windows** | `DeviceIoControl` with `IOCTL_CDROM_READ_TOC_EX` and the format `CDROM_READ_TOC_EX_FORMAT_CDTEXT`: "Query the device for CD-TEXT information that is recorded in the lead-in area as R-W subchannel data", returned as `CDROM_TOC_CD_TEXT_DATA` followed by its blocks [AA46] | `DeviceIoControl` through Swift's Windows module; the structures come from a driver header, so a few lines of C beside the Swift, or the bytes laid out by hand [inf] | The system's own | ImgBurn and Exact Audio Copy show CD-Text |
| **Linux** | No call of its own. The same drive command is sent through the general pass-through (`SG_IO`, or `CDROM_SEND_PACKET` in `linux/cdrom.h`) on `/dev/sr0` [AA47, snip]. The user must be allowed to open the drive, which desktops grant to whoever is logged in [inf] | `ioctl` from Swift with a small command block [inf] | The kernel's own interface. **Do not link libcdio**: it reads CD-Text well (new functions in 2.1.0 [AA47, snip]) but is under the GPL, which Deckie's rule never ships [unverified today: the project page redirected and I did not follow it; GPL is from the project's long-standing terms] | `cd-info` from libcdio, as a check on the bench only |

libdiscid does not read CD-Text [AA28]. It reads the table of contents, the barcode and ISRCs on all three
systems, and is LGPL 2.1 or later: allowed only as a separate library file. Letter K's open question (libdiscid or
the calls directly) is answered the same way for CD-Text as for the rest: the calls directly, in Deckie's own code.

To test on a real drive, since none of this could be run today: whether a Mac app may open the raw device of a
mounted music CD without extra permission; what a drive returns when the disc has no CD-Text (an error or an empty
list); and discs whose text is in the Japanese character set.

### 2.3 Drives

Not every drive hands CD-Text over. dBpoweramp's support forum: many drives "do not support it / or support it
badly", and its Mac version does not read CD-Text at all; Exact Audio Copy has a per-drive setting, off by
default, for a "CD-Text Read capable drive" [AA36, snip]. So "no names on this disc" can mean the drive, not the
disc. Desk should say which it knows: "This disc has no names on it" only when the drive answered with none.

### 2.4 Which burning programs wrote it

| Program | Writes CD-Text | Source |
|---|---|---|
| **Windows Media Player** | **No.** "Burning artist and title info to an audio CD is possible, this is a feature called CD-Text. Unfortunately, WMP doesn't support this." A plug-in from Nero added it for version 9 only | A reply on Microsoft's own forum, Nov 2010, and a later one, 2017 [AA48] |
| **iTunes 7 and later, Music** | Yes, if "Include CD Text" was ticked; off by default. Some players did not show text from its discs | [K]; [AA49, snip] |
| **Nero** | Yes, since version 5.5.10, when the option was on and the files were tagged | [AA49, snip] |
| **ImgBurn; Exact Audio Copy with a cue file; Feurio** | Yes | [AA49, snip]; [AA50] |
| **Toast and Jam (Mac)** | Yes | [AA49, snip] |
| **K3b; Brasero from 0.5.90 (Linux)** | Yes | [AA49, snip] |
| **CDBurnerXP, BurnAware, Roxio** | Not confirmed today | [unverified] |

**How often burned discs carry it.** I found no count [unverified]. The defaults point one way [inf]: the burner
built into Windows never wrote it, Apple's wrote it only when asked, and Nero wrote it when the option was on. A
DJ's discs are more likely than most to have it, because DJs chose Nero-class programs so that the titles would
show on the deck.

**The first tester's discs.** The titles show on his player. Two things produce that, and they need different
handling:

- A music CD with CD-Text. The CDJ-1000MK3's text mode "shows CD-TEXT, including the names of tracks, albums, and
  artists" [AA51, snip of the manual].
- A data CD of MP3 files, where the same display shows each file's tag or its file name [K].

Letter K recorded his discs as MP3 data CDs; the brief for this letter says music CDs. One look settles it: on a
PC, a music CD shows files named `Track01.cda` and a data CD shows `.mp3` files. If they are music CDs burned on a
PC and the titles show, they were not burned with Windows Media Player and they do carry CD-Text, which is the
good case. Worth asking him which program he used.

### 2.5 What else identifies a burned disc

- **Its table of contents.** No database knows a home-burned disc [K]. But the table is as good as a serial
  number on the DJ's own computer: Desk keeps it with the source, knows the disc when it returns, and never reads
  it twice.
- **ISRCs.** A burning program copies sound, not serial numbers, so a burned disc rarely has them [K, inf].
- **The same recordings, already named, on the computer** (section 1.2). The strongest route when the files the
  disc was burned from still exist.
- **The DJ.** The disc's own name is whatever is written on it. Desk asks for it once, in passing, and never
  waits for it.

### 2.6 How a song copied from a music CD keeps its place

A place is a source, a group and a number (D26, D31). For a music CD the source is the disc, there is no group,
and the number is the song's number in the table of contents, which is the number the deck shows. That holds
however the sound is read:

| System | How the songs appear | How the number is kept |
|---|---|---|
| macOS | As files, `N Audio Track.aiff`, with a hidden `.TOC.plist` [K]. Whether the files are ever named from CD-Text is still unconfirmed: one Mac user saw names when browsing a home-made disc but none after importing it into Music, and the thread does not say why [AA52] | The number in the file name and in the table |
| Windows | As 44-byte stubs, `Track01.cda`, that hold the song's number and where it starts and stops, not the sound [AA53, snip]. The sound is read from the drive by position [inf] | The stub's number, or the table |
| Linux | Not as files at all. The sound is read from the drive by position; desktops show a virtual folder of `Track N.wav` [inf] | The table |

What follows for Desk [inf]:

- **Read the table first, then CD-Text, then the sound**, in one pass (letter K's flow, unchanged). The name of
  the source is the disc title from CD-Text when there is one; otherwise a placeholder the DJ can change at any
  time ("Music CD, 14 songs, 71:12").
- **Order is the table's order.** There is nothing to sort and nothing to guess, unlike a folder.
- **Reading the sound bears on names in one way only**: each song must be cut exactly where the table says, so
  that a song is the same song the deck plays under that number. A plain fast read with a second try on bad
  sectors is enough (letter K); careful archival reading adds nothing to names or order.
- **A hidden song before song 1, and gaps between songs**, belong to the song the deck would play them under.
- **Desk does not need to keep the sound** once it has read it for the analysis and the fingerprints. The DJ plays
  the disc, not a copy. This fits D25 (Desk reads; it does not manage).

## 3. The flow, on paper

For Desk on every computer. The words are placeholders in Deckie's voice (D28), to be set by the copy audit.
Brackets mark what changes.

### 3.1 Reading never stops for a name

Desk reads every song under whatever name it has, and none if it has none. Nothing is asked while it works. The
progress line stays as it is: "Reading your crate. 12 of 240 songs. About 4 minutes left."

### 3.2 The finished screen

| Case | Words |
|---|---|
| Every song has a name | "240 songs are in. Every one has a name." |
| Some do not | "240 songs are in. 14 need a name." and under it, smaller: "They work in the booth as they are. A name makes them easier to find." Buttons: "Show them" and "Send to iPad" |
| A music CD with no names on it | "Friday night is in: 14 songs. This disc has no names on it." Buttons: "Name them" and "Send to iPad" |

"Send to iPad" is never greyed out for want of a name.

### 3.3 The list of songs that need a name

The table's filter, already built: "Needs a name (14)". Each row says in two or three words why it is there, so
the DJ can sort the easy from the hard:

| Label | Meaning |
|---|---|
| "No title" | Nothing usable: empty, or a placeholder such as "Track 01" |
| "No artist" | A title and nothing else |
| "Desk's guess" | Named from a file name, a folder, a list or the disc; worth a glance |

Songs with a guess are in the list only until the DJ has looked once ("Looks right" clears a whole selection).

### 3.4 One song

The side panel, under the heading "Names". Every fact has its own line and, under it in small type, where it
came from. This is the same habit as "read by Deckie" for a key.

| Field | Example | The small line under it |
|---|---|---|
| Title | Night drive | "from the file name" |
| Version | Extended mix | "from the file name" |
| Artist | (empty) | "not found" |
| Release | Friday night | "the disc's own name" |
| Label, Year, Genre | (empty) | "not found" |
| Where | Friday night / 7 | |
| Length | 6:42 | |

The small lines, one for every source: "from the file's tags"; "from the file name"; "from the folder"; "from
[Friday.cue], beside the music"; "from the disc"; "from [rekordbox]"; "from a copy in your crate"; "from
[MusicBrainz], looked up [Nov 13]"; "you typed this".

**A guess is already filled in**, in a lighter weight, with one line: "Desk's guess, from the file name." Typing
over it, or pressing Return on it, makes it the DJ's. A guess is never shown as if it were known.

At the foot of the panel: "Listen", "Look it up", and, when the file has one, its own artwork.

### 3.5 Naming by typing

Click a field, type, Return. Tab moves to the next field, and Return on the last field moves to the next song in
the list, so a DJ can name twenty songs without the mouse. What the DJ types is marked "you typed this" and
nothing ever changes it but the DJ.

Typing "Artist - Title (Version)" into the title field offers to split it: "Split into artist, title and
version?" This is the file-name grammar from letter B used on the DJ's own words.

### 3.6 Naming a whole disc or folder at once

Two tools that work on a selection, both with a preview before anything changes:

- **"Names from the file names…"** The DJ picks or types a pattern; Desk shows before and after for every song
  selected. This is Mp3tag's best-liked feature (section 4).
- **"Paste a list…"** "Paste or type the songs in order, one to a line." Desk lines the list up with the songs by
  number and shows the pairs. If the counts differ it says so ("14 songs, 13 lines") and changes nothing until
  the DJ has fixed it.

### 3.7 Listening

**Recommended: yes, a short listen in Desk.** The reasons [inf]: a DJ knows most of their own songs within a few
seconds of hearing them; it works for the bootleg no catalogue holds; it sends nothing; and without it the DJ has
to find the same song in another program to hear it, which for a music CD means finding song 7 on a disc by hand.

How other apps do it: tag editors lean on the system's player or a small one of their own (Picard has a player
bar; Mp3tag hands the file to the default player; beaTunes plays in its own window) [unverified today, from use];
rippers have play buttons for the disc's songs; DJ programs are players already. None makes the listener leave
the list.

What it should be: one button, "Listen", on the panel and on the space bar. It starts a third of the way in,
because the first half minute of a dance record is often drums alone [inf], with "Back 30 seconds" and "Forward
30 seconds". It needs the music to be reachable: "Put [Friday night] back in the drive to listen."

This changes one line of `desk.md`, which says Desk does not "play, mix or edit music". The line would become:
Desk does not mix or edit music; it can play a few seconds so you can tell what a song is. The owner's call.

### 3.8 "Look it up"

A button on the panel for one song, and "Look up all 14…" at the top of the list. A disc gets its own: "Look up
this disc".

**The sentence comes first, every time for a batch.** Pressing the button opens a small sheet. It says what will
be sent, to whom, and what will not. The DJ presses again to send.

| Lookup | The sentence |
|---|---|
| One song, by text | "Desk will send this song's title and artist, as written here, to [MusicBrainz, a public music encyclopedia]. The song itself is not sent." |
| Many songs, by text | "Desk will send the titles and artists of 14 songs to [MusicBrainz], one at a time. About 15 seconds. The songs themselves are not sent." |
| A disc | "Desk will send the lengths of this disc's 14 songs to [MusicBrainz] to ask which disc it is. The songs themselves are not sent." |
| By sound, if it is ever built | "Desk will send a fingerprint of each of 14 songs to [AcoustID]. A fingerprint is a short description of the sound. It can't be played back. The songs themselves are not sent." |

Buttons: "Look it up" and "Not now". A small link: "What Desk has sent", which opens a plain list of every lookup
made, when, and to whom, kept on the computer and clearable. That fits the note on D3: the DJ can see, export and
delete.

**Every time or once?** Recommended: the sheet appears every time for a batch and for a disc, because the count
and the service are part of the consent. For one song at a time it appears the first time, and after that the
sentence sits permanently under the button in small type and the button acts at once, so a DJ working down a list
is not stopped fourteen times. There is no "don't ask again" for batches and no setting that makes lookups
automatic (D30). Apple's own test for data a user hands over points the same way: "the user affirmatively chooses
to provide the data for collection each time" [AA29].

**No signal.** "Look it up needs a signal. Everything else works without one."

**What is sent is only what the sentence says.** Where a tidier query would help (dropping "(Extended mix)" to
find the song, then choosing the version by length), Desk does that work on the answers, on the computer, and
does not send more.

### 3.9 Nothing found

"[MusicBrainz] doesn't know this one. That's usual for edits and bootlegs. The name is yours to give." The song
stays in the list. Nothing is marked as a failure, and the same lookup is not offered again for that song unless
its words change.

For a batch: "9 of 14 found. 5 not found: edits and bootlegs often aren't." Then the list shows the five.

### 3.10 Several candidates

When more than one answer fits, Desk fills nothing and shows them. Each row has what a DJ needs to tell versions
apart, with the song's own length beside the candidate's:

| Title and version | Artist | Release | Year | Length |
|---|---|---|---|---|
| Night drive (extended mix) | … | … 12-inch | 1991 | 6:41, same as yours |
| Night drive (radio edit) | … | … | 1991 | 3:38, 3 minutes shorter |
| Night drive (2008 remaster) | … | … | 2008 | 4:06, 2:36 shorter |

"Use this one" on a row; "None of these" at the foot. "Listen" stays available. A single answer whose length is
within a few seconds of the song's is filled in as a guess, marked "from [MusicBrainz], looked up [Nov 13]", and
the DJ confirms it like any guess. A single answer whose length is far off is shown as a candidate, never filled
in (section 6).

### 3.11 Never overwriting the DJ's name

- A lookup fills empty fields only.
- Where a field has something the DJ typed, the answer is shown beside it, small: "[MusicBrainz] says: Night drive
  (extended mix)", with "Use". It is never swapped in.
- Where a field has a guess of Desk's own (from a file name, say), a looked-up answer replaces the guess and
  stays a guess until confirmed.
- The file is never changed. Names live in Desk's crate and the crate file; Desk does not write tags (D25).

### 3.12 Undo

After any change to names: a line at the foot, "Names added to 9 songs. Undo." It stays until the next change.
Command-Z, or Control-Z on Windows and Linux, steps back through changes one at a time (D28). Each field keeps
what it held before, so "Put back" on a single field is always possible, including putting a guess back in place
of a looked-up answer.

### 3.13 The booth, for a song with no name

The booth recognises a song by its sound, not its name, so a song with no name is found and shown like any other
[K]. What it shows:

- **The place leads.** "Friday night / 7" in the size the title would have. It is how the DJ finds the song
  anyway, and it matches the number on the deck's display.
- **Under it, what Desk has**, in this order: the file name without its ending, if there is one; otherwise
  nothing but the quiet line "No name yet".
- Never "Unknown", never a question mark, never a blank row. In lists and picks the row reads "Friday night / 7 ·
  no name yet" and sorts by place.
- Naming is not offered in the booth. The DJ is in the dark and in a hurry; the line "Name it in Desk" belongs on
  the set's list afterwards, not on the playing screen.

## 4. How the best existing tools do this

| Tool | How it names | What works | What annoys people |
|---|---|---|---|
| **MusicBrainz Picard** | "Lookup" by the words in the tags; "Scan" by an AcoustID fingerprint; "Lookup CD" by disc id; unmatched files stay in the left pane [W; AA30, snip] | Free; the widest open catalogue; a clear split between matched and not | Built around albums, so single songs get scattered: threads titled "how to stop Picard from tagging songs from compilations" and "MusicBrainz replacing correct tags with wrong ones"; a remix matched by fingerprint to another artist's song [AA30, snip]. A DJ's crate is mostly single songs |
| **Mp3tag** | No guessing. Tags from file names by a pattern, with a preview; album lookups at Discogs and MusicBrainz in three steps: search, choose a result, confirm in a window with a tick box per field and "Move up" and "Move down" to line songs up. Its manual: "Mp3tag doesn't auto-magically detect unnamed files and tags them correctly" [AA31] | The preview; the tick box per field; nothing happens that the user did not see first | Lookups are "on a per-album basis" [AA31, snip], so it is slow for loose songs |
| **beaTunes** | Fingerprints against a central database, then "correction hints" for inconsistent tags; the trial names 10 songs a session [AA32, snip, the maker's claims] | One place to see what is inconsistent | No independent DJ review found [unverified] |
| **Lexicon** (for DJs) | "Find Tags & Album Art" from two sources, Sonovault and Beatport, matched "by artist and title", which it never changes; songs missing either are skipped. Options: overwrite or fill empty fields only; "Interactive mode" shows a "Review found tags" page in batches of 100, each undone as one step; "Use original release" strips the remix words to find the original. "Smart Fixes" tidy names locally: fix capitals, pull the artist out of the title, remove number prefixes, add brackets round the mix [AA33; AA34, snip] | The review page; undo per batch; fill-empty-only; local tidying kept apart from lookups. Reviewers praise the clean-up most | It does nothing for a song with no name, by design. "Overwrite" is on by default [AA33] |
| **OneTagger** (for DJs) | A batch by artist and title against Beatport, Traxsource, Juno and Discogs [W] | The right catalogues for dance music | Starts from a name; reads store web pages [W, unverified] |
| **SongKong and Jaikoz** | Fingerprint and catalogue matching, fully automatic over a whole library; SongKong keeps "all changes" so they can be undone after a restart and writes a report of what it did [AA35] | Lasting undo and a report: the two things an automatic tool must have | No user reports found either way today [unverified] |
| **beets** | Applies a match by itself only when very sure; otherwise asks, with "more candidates", "use as-is", "skip"; a quiet mode skips and logs [W] | The threshold, and "use as-is" as a first-class answer | A command line |
| **Exact Audio Copy** | Disc lookup when the disc goes in; reads CD-Text if the drive is marked able [AA36, snip] | Trusted reading | The CD-Text setting is off by default and easy to miss [AA36, snip] |
| **dBpoweramp** | "PerfectMeta uses 5 meta data providers simultaneously, allowing inevitable spelling mistakes to be corrected": AccurateRip's own, GD3, MusicBrainz, Discogs and freedb; also "CD-Text, UPC, ISRC: metadata embedded on some CDs"; for artwork "show matching art for you to choose" [AA37] | Several sources compared, with differences highlighted | The better sources need the paid edition; a thread titled "PerfectMeta uses CD-Text each time instead of more useful metadata suppliers"; the Mac version cannot read CD-Text [AA36, snip] |
| **XLD (Mac)** | Disc lookup; CD-Text used when nothing comes from the lookup [AA38, snip] | CD-Text as a quiet fallback | Little guidance on screen [inf] |
| **Apple's Music app** | Gracenote when online; "Track 01" when not; "Get Track Names" later [K]. Burns CD-Text when asked and has no visible way to read it back; a third-party script exists to copy CD-Text into its tags [AA39, snip] | It never blocks an import | Names depend wholly on the lookup; a home-made disc comes in blank [AA52] |
| **DJ programs** | Show the tag, and the file name where there is none; never stop an import to ask. One vendor's blog says so in general; an Engine DJ thread shows a deck listing by file name [AA41, snip] | Never blocking | No help at all for the nameless. How rekordbox, Serato and Traktor each behave is still not written down anywhere I found [unverified], as in letter W |

What to take from them, added to letter W's five points:

1. **A tick box per field and a preview** (Mp3tag, Lexicon). The DJ sees every change before it is made.
2. **Fill empty fields only, as the default**, the opposite of Lexicon's.
3. **Undo that survives closing the app, and a plain record of what was done** (SongKong).
4. **Keep local tidying and outside lookups as two separate things on screen** (Lexicon). One sends nothing.
5. **Single songs, not albums.** Picard's troubles are what happens when an album tool meets a crate.
6. **Say when it is the drive** (dBpoweramp, EAC).

## 5. The privacy line

Today's promises: the music never leaves the DJ's devices, nothing is uploaded, no account, works with no signal.
With an opt-in lookup, three of the four stay true as written. "Nothing is uploaded" does not: words, a disc's
lengths or a fingerprint go out, and each tells a service something about what the DJ owns, from the DJ's network
address. The note on D3 says privacy covers taste, not only audio. So the line must say that something can leave,
that it leaves only when asked, what it is, and to whom.

The booth's line does not change, because the booth never looks anything up: "Your music stays on your iPad. No
account. No upload. Works with no signal."

**Version 1, short, for the site and the first screen of Desk.** Keeps four beats.

> Your music never leaves your devices. No account. Works with no signal. Nothing is sent unless you ask.

**Version 2, a sentence longer, where there is room.**

> Your music never leaves your devices. No account. Works with no signal. If you ask Desk to look up a name, it
> sends the words, never the song, and it tells you first.

If lookup by sound is ever built, the last sentence becomes: "If you ask Desk to look up a name, it sends the
words or a short fingerprint of the sound, never the song, and it tells you first."

**Version 3, long, for the privacy page and for Desk's "What Desk has sent" window.**

> **What never leaves.** Your music. Your crates and crate files, except when you send one to your own iPad. What
> you play, your sets, your picks and what Deckie learns about how you mix. None of it goes to us or to anyone.
>
> **What leaves only when you ask.** Desk has a button, "Look it up". When you press it, Desk tells you what it
> is about to send and waits for you to say yes. It then sends one of these, and nothing else:
>
> - a song's title and artist, as they are written in Desk;
> - the lengths of the songs on a CD;
> - [a short fingerprint of a song's sound, which can't be played back].
>
> **Who gets it.** [MusicBrainz, a public music encyclopedia run by a non-profit foundation.] [AcoustID.] Not us:
> a lookup goes straight from your computer to them. Like any site you visit, they see your network address and
> the name of the app, and they may keep a record of the request.
>
> **What comes back** is kept in your crate, on your computer. Desk keeps a list of every lookup it has made. You
> can read it and clear it.
>
> **If you never press the button, nothing is ever sent.** Deckie works the same without it, and with no signal.

Three checks before any of these is published [inf]:

- "Not us" is true only if lookups go straight from Desk to the service. If Deckie ever puts a server of its own
  in between (to hold a key, say), the sentence changes.
- "Nothing is sent unless you ask" must also be true of everything else Desk does: update checks, crash reports,
  the acknowledgements screen. The rule in the note on D3 (no dependency that reports home) already covers this;
  the release test should cover an update check too.
- The words on Desk's first screen today ("Your music never leaves this Mac") stay true and need no change.

## 6. Version and remix

A wrong version is a wrong name to a DJ: a radio edit has no intro to mix, an extended mix does.

### 6.1 In tags

| Format | Where a version can go | What people do |
|---|---|---|
| ID3 (MP3, AIFF) | `TIT3`, "Subtitle/Description refinement"; `TPE4`, "Interpreted, remixed, or otherwise modified by" [AA40] | Almost nobody uses them. The standard's own notes say most users "write their refinement remark into brackets within the title frame", and iTunes never showed `TPE4` [AA40, snip] |
| Vorbis comments (FLAC, Ogg) | `VERSION`: "may be used to differentiate multiple versions of the same track title in a single collection" [AA42] | Rare in practice [inf] |
| M4A | No field for it [inf] | Brackets in the title |

So the version lives in the title, in brackets, and the remixer's name lives inside the version: "Title (Somebody
remix)". Letter B's file-name grammar already splits these; the same split must run on a title read from a tag.

### 6.2 In the catalogues

| Catalogue | Rule |
|---|---|
| **MusicBrainz** | A remix "should always be given a new recording"; an edit, made by removing sections, is a new recording too; a remaster is not; adding a fade is not an edit. The version goes after the title "preceded by a single space and wrapped in parentheses", in lower case: "Situations Like These (album version)" [AA43] |
| **Beatport** | Every song carries a separate "mix name". Where a label gives none, "Original Mix" is added, which is why it appears across the store [AA54, snip of distributors' guides and a community thread; Beatport's own page refused a fetch] |
| **Apple's style guide for labels** | Versions go "in parentheses or brackets", with terms such as "Radio Edit", "Extended Mix" and "12" Mix"; titles "must not include … Album Version, Original Mix"; a remix lists "the original artist as Primary with the remixer assigned the remixer role"; clean and explicit are a flag, never words in the title [AA55] |
| **Discogs** | Each version is its own line on a release, with the remixer as a credit; a master release gathers the pressings [B; not re-read today, unverified] |
| **Record pools** | Their own words, which no catalogue holds: a "Clean Intro" is an edit that adds an intro to a song that "didn't contain at least an eight-bar intro that a DJ could use to beatmatch and transition"; "Dirty" means the swearing is left in; "Short Edits" run "about two and a half minutes to close three minutes" [AA56] |

### 6.3 In DJ programs

rekordbox's exported library has separate `Mix` ("the name of the mix") and `Remixer` attributes on every song
[AA57, snip of a third-party description of the format]. Traktor's library has the same pair [unverified, from
use]. Most DJs leave both empty and read the brackets in the title [inf]. When Desk reads a DJ program's library
(D30), it should take these two when they are filled.

### 6.4 What this means for Desk [inf]

1. **Keep the version as its own fact**, beside the title, with the remixer inside it or beside it. On screen the
   title still reads the way DJs write it: "Night drive (extended mix)".
2. **Treat a few words as "no version"** when comparing: "Original Mix", "Album Version", "Original". Apple bans
   them, Beatport adds them, and they mean the same thing: the plain one.
3. **Length is the test.** Two versions of a song almost never last the same. A candidate within about three
   seconds of the song's length is the same version; one that is further off is another version, whatever its
   title says. (D24's same-recording check already uses one second for copies; a lookup needs a little more room
   for silence at the ends. The number is to be set on music Desk has not seen, per the library-blind rule.)
4. **Never let an answer remove a bracket.** If the DJ's name says "(Somebody remix)" and the catalogue's does
   not, the catalogue has found the original. Its year and label are the original's. Show them as such ("the
   original: 1991") or not at all.
5. **An ISRC, when the file has one, beats words.** One ISRC is one version, so the lookup by ISRC cannot return
   the wrong mix. Use it first where it exists.
6. **A fingerprint is weakest here.** AcoustID reads the first two minutes; versions that differ only later come
   back as each other [K]. If it is ever built, its answers go through the same length test.
7. **Pool words stay the DJ's.** "(Intro - Dirty)" names no catalogue entry and should be kept as written.
   Lexicon's "Use original release" is the right idea, done openly: look up the original for its facts, keep the
   DJ's version on the song.
8. **Versions are separate songs everywhere else in Deckie** (D24, the note on D19). Naming must not be the place
   they get folded together.

## Options for the owner

Whole routes. Each later route includes the ones before it. Times are my estimates [inf].

| Route | What it is | Costs | Gains | Risks |
|---|---|---|---|---|
| **A. Nothing leaves** | Finish naming with what is on the disc and the computer: CD-Text on all three systems; the disc matched to named copies and playlists already on the computer; the "one song" panel with where each fact came from; "Listen"; "Names from the file names" and "Paste a list" with previews; undo; the booth's row for a song with no name | Two to three weeks. No terms, no fees, no change to the public line. A drive to test with | Names the first tester's discs if they carry CD-Text or if their files are on his PC; gives every DJ a fast way to type the rest; covers the 54 and 57 songs in the owner's library by tidying and typing. The same on every computer | CD-Text may be on few discs; a drive may not hand it over. "Listen" changes one line of what Desk is |
| **B. A plus a text and disc lookup** | "Look it up" in Desk, sending words or a disc's lengths to MusicBrainz, with the sentence first and the list of what was sent. Discogs second, once its terms page has been read | Two weeks more. MetaBrainz: free while Deckie is not public, then from 100 dollars a month. The privacy line reworded (section 5). The attorney on the terms and on the App Store label | Artist, release, label and year for released songs that have a title; a whole pressed CD named in one request; with Discogs, the 12-inch and white-label facts DJs care about | A wrong version filled in, if the length test is weak. A title with no artist returns many candidates, so the 57 songs get a list to choose from, not an answer. Nothing for edits. The promise is no longer four plain statements |
| **C. B plus a lookup by sound** | AcoustID on every computer; Shazam's catalogue on the Mac as a second opinion | Two to three weeks more. AcoustID 50 euros a month. Chromaprint shipped as a separate library file, or its small program run beside Desk. Shazam: an Apple Music link beside results, a question for the attorney about Deckie's own recognition, and a feature the PC does not have | Names a released song that has no words at all: an untagged rip, "Track 01" from a pressed CD read offline | The weakest route on versions. A fingerprint is harder to explain than words, and "nothing is uploaded" is hardest to keep honest here. Uneven between Mac and PC if Shazam is in |
| **D. A dance-music catalogue by contract** | Beatport's catalogue, or a commercial recognition service | A negotiation of unknown length and price | The catalogue DJs trust, with mix names, labels and genres | Time; a dependency on one company's goodwill; still nothing for bootlegs |

### Recommendation

**A now. B next, with MusicBrainz alone at first. C and D not yet.**

The reasoning:

- The songs that arrive with no name are mostly the ones no catalogue holds. For those the only tools that work
  are the ones in route A: the names already on the disc or the computer, the DJ's ear, and fast typing. Route A
  is also what the first tester's burned discs need, and it is the same on a Mac and a PC, which D29 asks for.
- Route A costs nothing in terms, fees or promises, so it should not wait on the attorney.
- Route B is worth having for "song DNA": year, label and release for songs that already have a name. That is
  what the owner asked for in D30. MusicBrainz is the one source that is open, storable for good, credit-free,
  free until launch and the same on every computer. Discogs is the natural second, for dance records, once
  someone has read its terms.
- Route C names a kind of song that is rare in a DJ's files (a released song with no words at all) and it is the
  route most likely to return the wrong version. Hold it until testers show the need. If it is built, AcoustID
  before Shazam, because it runs everywhere.
- Route D is a business conversation, better had when Deckie has users to point to.

### Suggested order of building

1. **The CD-Text decoder in the shared core**, with made-up pack data as its tests. No drive needed.
2. **The three system calls** (Mac, Windows, Linux) behind one interface, and a test on a real drive with discs
   burned with and without CD-Text. Ask the first tester which program burned his discs and whether they are
   music CDs or MP3 CDs.
3. **The disc matched to what is on the computer**: named copies by the same-recording check, shortlisted by the
   table of contents against playlists.
4. **The "one song" panel**: every fact with its source line, guesses shown as guesses, "you typed this" always
   winning, undo.
5. **"Names from the file names" and "Paste a list"**, with previews.
6. **"Listen"**, if the owner agrees to the change in what Desk is.
7. **The booth's row for a song with no name.**
8. **Version as its own fact**, and the length test, measured on music Desk has not seen. This is needed before
   any lookup and is useful without one.
9. Then, for route B: the attorney reads the MusicBrainz and Discogs terms and section 5; Deckie signs up with
   MetaBrainz; the site's line changes on the day the button ships, not before and not after.
10. **"Look it up"** for one song, then for a disc, then for all, in that order, each with its sentence and the
    list of what was sent.

## What I could not open or verify

- **Discogs' developer page and API terms**: refused every fetch (403), as for letter B. Everything about Discogs
  here is from search summaries and letter B. Whether search needs a key, the exact credit wording and what
  counts as restricted data must be read in a browser.
- **GnuDB's own pages**: answered only with a browser check. Its commercial-use wording and email rule are from
  forum reports seen in search summaries.
- **Apple's current iTunes Search page**: blocked here; the terms quoted are from Apple's archived copy (2017),
  and the 20-a-minute limit is from a search summary.
- **The Apple Developer Program License Agreement's ShazamKit clauses**: not opened; the Apple Music link rule is
  from an Apple staff reply (2022) and the "another audio recognition service" clause from a contracts site and
  letter L. Whether Shazam results may be stored, and ShazamKit's limits and cost, remain unverified, as in W.
- **ACRCloud's prices, Gracenote's and Beatport's current terms, Deezer's quota and whether it takes new apps,
  Spotify's need for a user login, Traxsource and Juno**: not confirmed.
- **Beatport's own metadata rules**: its help page refused a fetch; the mix-name rule is from distributors'
  guides.
- **How often burned music CDs carry CD-Text**: no count exists that I could find. Which programs write it is
  from forum posts and one old FAQ, apart from Windows Media Player (Microsoft's forum) and Music (letter K).
- **libcdio's licence page, the Linux pass-through details, the `.cda` layout, whether a Mac app can open a
  mounted music CD's raw device, and whether macOS ever names the disc's files from CD-Text**: from search
  summaries, from memory or not known; all need a drive and an afternoon.
- **Picard's manual pages** returned "not found" at the addresses I tried; its behaviour is from letter W and
  search summaries. **Whether tag editors have their own players** is from use, not re-checked.
- **rekordbox, Serato and Traktor with an empty title**: still not found written down.
- **The ID3 standard's own site** returned an error; the frame definitions are from search summaries of it and
  of mirrors.
- **User opinion** about beaTunes, SongKong, Jaikoz and XLD: none found; Reddit was not reached.
- **Nothing was run.** No disc was read, no lookup was sent, no service was signed up for.

## Sources

All read or searched Nov 13, 2026.

MusicBrainz and MetaBrainz
- AA1 MusicBrainz API (commercial use sentence, disc id lookup, fuzzy lookup, CD stubs, ISRC lookup): https://musicbrainz.org/doc/MusicBrainz_API
- AA2 Rate limiting and the User-Agent rule: https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting
- AA3 MetaBrainz supporter tiers and what counts as commercial: https://metabrainz.org/supporters/account-type
- AA4 MetaBrainz privacy policy (what its logs hold): https://metabrainz.org/privacy
- AA5 MusicBrainz data licence: https://musicbrainz.org/doc/About/Data_License
- AA6 Cover Art Archive API: https://musicbrainz.org/doc/Cover_Art_Archive/API
- AA28 libdiscid (licence, systems, what it reads): https://musicbrainz.org/doc/libdiscid
- AA43 MusicBrainz style: recordings https://musicbrainz.org/doc/Style/Recording ; titles https://musicbrainz.org/doc/Style/Titles

Other services by text
- AA7 Discogs API terms of use (not opened, 403; search summary): https://support.discogs.com/hc/en-us/articles/360009334593-API-Terms-of-Use ; developer page (not opened): https://www.discogs.com/developers/
- AA8 Deezer developer terms: https://developers.deezer.com/termsofuse
- AA9 Deezer's questions and answers for developers: https://support.deezer.com/hc/en-gb/articles/360011538897-Deezer-FAQs-For-Developers
- AA10 Deezer API page (login required to accept terms): https://developers.deezer.com/api
- AA11 Deezer community thread on paused access (search summary): https://en.deezercommunity.com/features-feedback-44/api-auth-impossible-80857
- AA12 Apple, iTunes Search API, archived overview and legal section: https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/index.html
- AA13 Apple, Search API current page (not opened; search summary): https://performance-partners.apple.com/search-api
- AA14 Last.fm API terms of service: https://www.last.fm/api/tos
- AA15 Spotify developer terms, version 10: https://developer.spotify.com/terms
- AA16 Beatport API access (search summaries; a developer group thread): https://groups.google.com/g/beatport-api/c/3qR1Uj1HnUk

By disc and by sound
- AA17 GnuDB (not opened: browser check): https://gnudb.org/howto.php ; reports of its terms and policy change (search summaries; pages refused): https://hydrogenaudio.org/index.php/topic,125826.0.html and https://forum.dbpoweramp.com/forum/read-only/news-updates-read-only/324612-gnudb-change-of-policy ; background: https://en.wikipedia.org/wiki/Freedb
- AA18 AcoustID web service: https://acoustid.org/webservice
- AA19 AcoustID commercial plans: https://acoustid.biz/
- AA20 AcoustID database licence: https://acoustid.org/database
- AA21 Chromaprint licence: https://github.com/acoustid/chromaprint/blob/master/LICENSE.md
- AA22 AcoustID statistics: https://acoustid.org/stats
- AA23 Apple, ShazamKit: https://developer.apple.com/shazamkit/
- AA24 Apple developer forum, staff reply on the Apple Music link (Jun 2022): https://developer.apple.com/forums/thread/703134
- AA25 ShazamKit sample clauses on a contracts site (search summary): https://www.lawinsider.com/clause/shazamkit
- AA26 AudD: https://audd.io/
- AA27 Beatport Track ID and TrackSniff (search summaries): https://www.edmtunes.com/2026/05/beatport-launches-track-id-music-discovery-tool-for-djs/ ; https://www.digitaldjtips.com/tracksniff-shazam-alternative/
- ACRCloud pricing (showed nothing to a fetch): https://console.acrcloud.com/pricing

Privacy
- AA29 Apple, App privacy details (definitions of "collect" and of partners; optional disclosure): https://developer.apple.com/app-store/app-privacy-details/

Tools
- AA30 Picard: scan and lookup (search summary) https://picard-docs.musicbrainz.org/en/usage/retrieve.html ; user threads (search summaries) https://community.metabrainz.org/t/how-to-stop-picard-from-tagging-songs-from-compilations/163567 , https://community.metabrainz.org/t/musicbrainz-replacing-correct-tags-with-wrong-ones/401024 , https://community.metabrainz.org/t/acousticid-matching-up-an-mp3-with-the-wrong-release-entirely-why/461390
- AA31 Mp3tag, importing from tag sources: https://docs.mp3tag.de/tag-sources/import/ ; menu page (search summary): https://docs.mp3tag.de/menus/tag-sources
- AA32 beaTunes (search summary of the maker's pages): https://www.beatunes.com/en/itunes-track-identification.html
- AA33 Lexicon manual, Find Tags and Album Art: https://www.lexicondj.com/manual/find-tags-and-album-art
- AA34 Lexicon walkthrough and reviews (search summaries): https://wearecrossfader.co.uk/blog/lexicon-music-management-for-djs/ ; https://www.trustpilot.com/review/rekord.cloud
- AA35 SongKong comparisons: https://www.jthink.net/songkong/songkong_comparisons.jsp
- AA36 dBpoweramp forum on CD-Text and drives; Exact Audio Copy's drive setting (search summaries): https://forum.dbpoweramp.com/forum/dbpoweramp/cd-ripper/21022-cd-ripper-doesn-t-read-cdtext ; https://forum.dbpoweramp.com/forum/dbpoweramp/cd-ripper/44429-perfectmeta-uses-cd-text-each-time-instead-of-more-useful-metadata-suppliers ; https://list.winehq.org/hyperkitty/list/wine-bugs@list.winehq.org/thread/Z5IU56MZQIF5XJ2P2Y3S644HKGGJQUPK/
- AA37 dBpoweramp CD Ripper: https://www.dbpoweramp.com/cd-ripper.htm
- AA38 XLD (search summary of its change log): https://tmkk.undo.jp/xld/index_e.html
- AA39 A script that copies CD-Text into Music's tags (search summary): https://dougscripts.com/itunes/2023/11/updated-cd-text-to-cd-info-v6-3/
- AA41 DJ programs and missing titles (search summaries): https://community.enginedj.com/t/denon-prime-4-shows-only-filename-in-iibrary-view/57980 ; https://greengomusic.com/blog/what-is-id3-metadata-why-every-dj-needs-it-tagged-correctly.html

Tags and versions
- AA40 ID3 version 2.4 frames (the standard's site returned an error; search summaries of it and a mirror): https://id3.org/id3v2.4.0-frames ; https://mutagen-specs.readthedocs.io/en/latest/id3/id3v2.4.0-frames.html ; the note on brackets and iTunes: https://id3.org/iTunes
- AA42 Vorbis comment field names: https://xiph.org/vorbis/doc/v-comment.html
- AA54 Beatport mix names (search summaries): https://help.labelgrid.com/en/distribution/beatport-requirements/ ; https://community.metabrainz.org/t/original-mix-in-the-main-title-of-a-track/354214 ; Beatport's own page (not opened, 403): https://greenroomsupport.beatport.com/hc/en-us/articles/15738573756948-Metadata-Quality-Standards
- AA55 Apple Music style guide: https://help.apple.com/itc/musicstyleguide/en.lproj/static.html
- AA56 Digital DJ Tips on version names: https://www.digitaldjtips.com/your-questions-what-do-all-the-names-for-different-versions-of-a-track-mean/
- AA57 rekordbox XML format, as described by a third party (search summary): https://pyrekordbox.readthedocs.io/en/stable/formats/xml.html

Discs and CD-Text
- AA44 CD-Text: https://en.wikipedia.org/wiki/CD-Text
- AA45 Apple's headers (search summary): `IOCDMediaBSDClient.h` https://opensource.apple.com/source/IOCDStorageFamily/IOCDStorageFamily-51/IOCDMediaBSDClient.h.auto.html ; `IOCDTypes.h` https://opensource.apple.com/source/IOCDStorageFamily/IOCDStorageFamily-59/IOCDTypes.h.auto.html ; DiscRecording's CD-Text header (a mirror) https://jenkins.heirloomcomputing.com/downloads/MacOSX10.8.sdk/System/Library/Frameworks/DiscRecording.framework/Headers/DRCDText.h
- AA46 Microsoft, `CDROM_READ_TOC_EX`: https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ntddcdrm/ns-ntddcdrm-_cdrom_read_toc_ex
- AA47 Linux and libcdio (search summaries): `linux/cdrom.h` https://git.zx2c4.com/linux-dev/tree/include/uapi/linux/cdrom.h ; libcdio's CD-Text notes https://gnu.org/software/libcdio/cd-text-format and release notes https://sources.debian.org/src/libcdio/2.1.0-2/NEWS.md/ ; a `cd-info` CD-Text bug https://bugzilla.redhat.com/show_bug.cgi?id=1321677
- AA48 Microsoft forum, Windows Media Player and CD-Text (replies of Nov 2010 and Apr 2017): https://learn.microsoft.com/en-us/answers/questions/e37c5af0-ef00-4e38-9907-b5452b58f453/the-track-names-are-missing-on-the-disc-after ; Microsoft's burn and rip page (says nothing of CD-Text): https://support.microsoft.com/en-us/windows/burn-and-rip-cds-235021d5-e1c7-8616-4efd-4f4965fe6b91
- AA49 Which programs write CD-Text (search summaries): https://www.hanselman.com/blog/HowToWriteOrBurnACDCDRThatIncludesCDTextWithImgBurn.aspx ; https://discussions.apple.com/thread/637806 ; https://kb.corel.com/en/126926 ; https://hydrogenaud.io/index.php/topic,47514.0.html
- AA50 An unofficial CD-Text FAQ (late 1990s; Nero and Feurio, drives, Sony's titles): https://web.ncf.ca/aa571/cdtext.htm
- AA51 Pioneer CDJ-1000MK3 manual, text display (search summary of a mirror): https://www.manualowl.com/m/Pioneer/CDJ-1000MK3/Manual/56596?page=17
- AA52 Apple Community, a home-made disc's names missing after import (macOS 14.6): https://discussions.apple.com/thread/255973067
- AA53 The `.cda` stub (search summary): https://en.wikipedia.org/wiki/.cda_file

In the repo: `docs/research/b-identification.md`, `k-cd-and-album-ingestion.md`, `w-own-recognition.md` section 6,
`l-non-apple.md`; `docs/product/00-decisions.md` (D3 and its notes, D16, D21, D24 to D31); `docs/product/desk.md`;
`docs/product/voice.md`; `DEPENDENCIES.md` (the licence allowlist).
