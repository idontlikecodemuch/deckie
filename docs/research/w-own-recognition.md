# Research W: recognition of Deckie's own, across the pitch fader and off Apple

Dated Nov 13, 2026. Web research and reading only: no code, no build, no measurement, no commit. It follows D29 (a
crate file made on a PC must be complete, so the shared core must recognise songs itself) and builds on letter H
(October's measurements with ShazamKit), letter L (what carries off Apple's platforms) and letter K (naming discs).
A first trial of a landmark fingerprint with a speed trick is being built in parallel; this letter says what else it
should try. Tags: [2nd] = read in a paper or page today; [H], [K], [L] = taken from that letter, not re-opened;
[vendor] = the company's own claim, not checked by anyone independent; [inf] = my inference, with the reasoning;
[unverified] = I could not open or confirm it. Not legal advice; licence and patent notes are from public records
and need the attorney before anything ships.

## In plain words

A **fingerprint** is a small description of how a recording sounds, made so that a few seconds heard through a
microphone can be matched to the right song. It is not the song and the song cannot be rebuilt from it. The
**catalogue** is the set of fingerprints the booth carries, one per song in the crate file. The **query** is the few
seconds the iPad has just heard.

The classic method, published by Shazam in 2003, draws a picture of the sound (time across, pitch up the side),
marks the loudest points, called **peaks**, and stores them in pairs: two pitches and the time between them. Each
pair is a **landmark**. A song is thousands of landmarks. If many landmarks from the query turn up in one song, all
at the same position in that song, it is a match.

The pitch fader breaks this in a simple way. Speeding a song up squeezes the time between its peaks, and with **key
lock** off (the vinyl way) it also pushes every pitch up. **Key lock**, called master tempo on Pioneer decks, is the
setting that changes speed and leaves the pitch where it was. Either way the landmarks no longer equal the stored
ones once the change passes a few percent. Apple's ShazamKit copes up to about 4 percent [H].

There are four ways round it, and the letter weighs each:

1. **More copies in the catalogue.** Store each song's fingerprint several times, once per speed.
2. **Several copies of the microphone.** Keep one fingerprint per song and try the query at several speeds.
3. **A fingerprint that does not care about speed.** Compare peaks by ratios, which a speed change leaves alone.
4. **Work out the speed first.** Deckie knows every song's tempo and beat grid, and can hear the room's tempo, so
   it can put the query back to the song's own speed before looking it up.

The short answers to the owner's questions:

- **Why not speed the songs up to match?** You can, and Apple suggests it. With audio it costs nine fingerprints per
  song and hours of preparation. With a fingerprint of our own neither side needs audio work: a speed change moves
  peaks by simple arithmetic, so the copies can be made from the peaks. Doing that on the query side costs nothing
  in the crate file. That is the route to take first.
- **How does Google do it?** A small trained model turns each second or two of sound into 96 numbers, and the phone
  compares runs of them against tens of thousands of songs stored on the phone, with no network. Google has
  published the design, not the model, and says nothing about pitch or tempo.
- **Who handles DJ music well?** Nobody has shown it publicly. Club monitoring companies claim 92 to 97 percent,
  with no method published. The one open study on real club mixes found 25 to 74 percent, and found that the simple
  methods named a wrong song about half the time.
- **How often is it needed?** In the one large study of real mixes, about one play in five to six is more than 4
  percent from the song's own tempo, almost always with key lock on. That is two or three songs an hour that a
  single plain fingerprint would miss.
- **How often does a song arrive with no name?** In one DJ's library, 2 in 100 had only a file name and none had
  nothing. The hard cases are burned audio CDs, vinyl rips, edits and continuous mixes. A lookup button can help
  with ordinary released songs and does little for edits and bootlegs; every lookup sends something off the
  computer, so it has to be asked for.

## 1. Speed up the songs, or speed up the microphone?

### The two ways, and two more

**The geometry.** Call the playback ratio *v* (1.08 is plus 8 percent). A peak at time *t* and frequency *f* in the
song appears in the room at:

| How the deck plays it | Time | Frequency |
|---|---|---|
| Key lock on (tempo only) | *t / v* | *f* |
| Key lock off (vinyl style) | *t / v* | *f × v* |

So there are two lines to cover, not a whole plane: tempo only, and vinyl style [H, section 2]. Anything a DJ does
with the fader sits on one of them, unless the deck's key-shift control is also used.

| Way | What the crate file carries | Work when the crate file is made | Work in the booth | Reads the fader? |
|---|---|---|---|---|
| **A. Variants in the catalogue, from audio** | 9 fingerprints per song for plus or minus 16 on both lines | Render each song 8 more times, then fingerprint | One lookup | Coarse at once (which variant), fine later |
| **B. Copies of the microphone, as audio** | 1 per song | None extra | 11 streams, each resampled or time-stretched, until the first match | Same |
| **C. Variants or probes made from the peaks** (own fingerprint only) | 1 per song | None extra | One peak picture; the landmarks are re-made or re-looked-up at each candidate speed | Yes: the speed that matches is the fader |
| **D. A fingerprint built from ratios** | 1 per song, somewhat larger | None extra | One lookup, more candidates to check | Yes, as a by-product |

### What each costs

**A, measured with ShazamKit [H].** About 45 KB per fingerprint, so 410 KB per song with nine; about 0.8 GB and
5.6 core-hours on a Mac for 2,000 songs. It scored 25 of 25 at every setting from minus 16 to plus 16 on both lines,
and 23 to 25 of 25 when the query came from a different time-stretcher. It needs no new code in the booth. Its
weakness is the size and the time, and that the variants must be rendered with one time-stretcher while the decks
use another.

**B, measured with ShazamKit [H].** One fingerprint per song. Eleven streams cost about 12 percent of one Mac core
until the first match, then one or two. It scored 21 to 25 of 25, weakest half-way between two candidate speeds.
Eleven streams are eleven chances of a false match in each window.

**C, not measured; this is the thing to try [inf].** With ShazamKit the fingerprint is sealed, so the only way to
change speed is to change audio. With our own landmarks it is not. A tempo-only change multiplies every time gap by
1/*v* and leaves both pitches alone; a vinyl change also moves both pitches by the same step if the pitch axis is
logarithmic (see section 5). So:

- A variant fingerprint can be computed from the song's stored peaks in microseconds, with no audio render. Way A's
  5.6 core-hours fall to nothing, though the file is still nine times the size if the variants are stored.
- Better, store nothing extra: take the query's peaks once, and for each candidate speed rescale the gaps and look
  up. One audio pipeline, no time-stretcher, no resampler. Eleven candidates are eleven table lookups of a few
  hundred landmarks each, which is small beside the work of making the peak picture [inf].
- Better still, do not guess speeds on a grid: look each landmark up with a tolerance on the time gap, then find the
  straight line that the matching pairs fall on. Its slope is the speed. This is the method of Wang and Culbert's
  patent, "Robust and invariant audio pattern matching" (a histogram of relative values across matched pairs),
  which Google Patents lists as expired on Mar 31, 2025 [2nd].

The honest limits of C: a real time-stretcher does not only move peaks, it smears drum hits and adds its own
artefacts, so some peaks appear or vanish; and every extra candidate or wider tolerance lets in more chance matches,
which is exactly where the simple methods failed on real mixes (section 3). Both are things the trial can measure.

**D.** See section 5.

### What the literature says

- **Variants in the catalogue** is Apple's own advice for ShazamKit: make skewed reference copies and keep each
  under 5 percent (WWDC22 session 10028) [H].
- **Correcting the query** has a paper: Dupraz and Richard (ICASSP 2010) first search for the common pitch offset
  between query and reference, then rescale the query; it is cited in the DJ-mix study as "a certain amount of
  robustness to changes in playback speed" [2nd, through Sonnleitner 2016; the paper itself not opened].
- **Ratio fingerprints** are Panako and Qfp (section 5).
- **Neither A nor B appears as a published DJ-mix result.** The published DJ-mix results are for plain landmarks,
  Panako's triplets and Qfp's quads (section 3).

### The size of a fingerprint of our own [inf]

No figure is needed from the literature to bound it. A landmark is two pitches, a gap and a time: 6 to 8 bytes. At
20 to 30 landmarks a second, a four-minute song is 30 to 60 KB, the same order as ShazamKit's 45 KB. Two thousand
songs are 60 to 120 MB as stored, the same as today. For scale, Google's phone fingerprint is under 3 KB a song
(section 2), because it stores one compact vector a second instead of landmarks; that is the size a trained model
buys.

## 2. How Google, Shazam and the others match songs

### Google: Now Playing and Sound Search

- **Now Playing** (Pixel phones, 2017) runs with no network. A tiny music detector (about 8,000 parameters, under
  10 KB) runs all the time on the phone's low-power signal chip and wakes the main processor only when it is sure
  music is playing: about 100 wake-ups a day, under 1 percent of the battery [2nd, arXiv 1711.10958].
- **The fingerprint** is a trained model, a stack of convolution layers, that turns a couple of seconds of sound
  into 96 numbers, an **embedding**: sounds that are the same recording land close together, different recordings
  far apart. It was trained with a triplet loss on noisy recordings lined up against their clean originals. One
  embedding is made per second. An eight-second query becomes seven two-second embeddings one second apart [2nd,
  paper and Google's 2018 research post].
- **The database** on the phone is "tens of thousands of songs", under 3 KB per song on average after squeezing the
  numbers about 32 times smaller, chosen by country and refreshed [2nd]. Press reports of the time put the whole
  feature under 500 MB [2nd, VentureBeat].
- **Matching is two steps.** A fast approximate search finds stored embeddings near each query embedding and
  touches about 2 percent of the database; songs hit several times become candidates; each candidate is then scored
  on the whole sequence. One embedding alone gives too many false matches; the sequence is what makes it safe [2nd].
- **Sound Search**, the server version, uses a model four times larger, 128 numbers instead of 96, a fingerprint
  every half second, and tens of millions of songs, with a lower bar for popular songs than obscure ones [2nd].
- **Pitch and tempo:** neither the paper nor the post mentions them. The training described adds noise, not speed
  changes [2nd]. The model and the database are not published. I searched for Google's patents on it and did not
  find the specific ones [unverified]; assume they exist.

What Deckie can take from it: the two-step shape (cheap candidates, careful check on a sequence), and the proof
that a few thousand songs fit on a device with room to spare.

### Shazam's published method and ShazamKit

- **Shazam (Wang, ISMIR 2003).** Peaks, paired into landmarks from an anchor peak to peaks in a zone after it; each
  landmark is a table key; a match is many landmarks agreeing on one time offset. It is built for noise and for
  phone-quality sound. [Mechanism as described in Sonnleitner 2016 and letter H; the 2003 PDF did not render for me
  today, so I quote no figure from it.]
- **The patents.** US 6,990,453 (Wang and Smith, priority Jul 31, 2000; the landmark method) is listed by Google
  Patents as expired, adjusted expiry Jan 7, 2024. US 7,627,477 (Wang and Culbert, priority Apr 25, 2002; the
  speed-tolerant matching) is listed as expired, Mar 31, 2025. Google marks its status lines as assumptions, not
  legal conclusions [2nd]. Olaf's author still attaches a patent warning to his code [H].
- **ShazamKit custom catalogues.** An app makes signatures from its own audio and matches the microphone against
  them on the device, with no network and no Shazam catalogue. Apple platforms, plus an Android kit; the signatures
  can only be made on Apple's systems; nothing for Windows or Linux [H, L]. Tolerance about 4 percent, with the
  pitch skew reported exactly inside that window [H].

### The field, in one table

"On device" means matching with no network. "Private catalogue" means the app's own songs, not the service's.

| System | How it works | On device | Pitch and tempo | Licence, and can it ship | Private catalogue |
|---|---|---|---|---|---|
| **ShazamKit** (Apple) | Landmark-style signatures, sealed | Yes | About plus or minus 4 percent, measured [H] | Apple's SDK terms; Apple and Android only | Yes |
| **Google Now Playing** | Trained embeddings, sequence match | Yes | Not stated [2nd] | Not available to others | No |
| **ACRCloud** | Proprietary fingerprint, cloud; an offline mode in its phone SDKs | Phone SDKs only; desktop not stated [2nd] | "Supported", no range given; ask them [vendor] | Commercial, price by quote | Yes, but the audio is uploaded to their console to build the offline database [2nd] |
| **AudD** | Cloud API; the app sends audio | No | Not stated | Commercial; 2 to 5 dollars per 1,000 requests [vendor] | Hosted only, on request [2nd] |
| **Gracenote** (Nielsen) | Proprietary fingerprint, cloud and embedded | Embedded in cars and players; no public SDK found [unverified] | Not stated | Commercial licence by negotiation | Not found |
| **SoundHound** | Cloud | No [unverified] | Not stated | Commercial | Not found [unverified] |
| **Audible Magic** | Proprietary, for platforms and rights | Not stated | Standard: "a few percent"; a premium tier for more [vendor] | Commercial | Yes, by contract |
| **AcoustID with Chromaprint** | Chroma picture of the first two minutes of a file, compared whole | The fingerprint is local; the lookup is a web service | None; built for clean whole files, not a microphone [2nd, K] | Chromaprint MIT, LGPL 2.1 as a whole because of FFmpeg parts [2nd]; service free for non-commercial use only | Could be self-built, wrong tool |
| **Panako** | Peak triplets on a constant-Q picture, compared by ratios | Yes (Java) | 2014: to about 8 percent; version 2: 83 percent of 20 s queries at plus 10 [2nd] | AGPL-3.0: cannot ship in a closed app | Yes |
| **Olaf** | Wang-style landmarks in C, for tiny devices | Yes | None | AGPL-3.0: cannot ship | Yes |
| **audfprint** | Wang-style landmarks, Python | Yes | Fails above about 3 percent [H] | MIT | Yes |
| **Dejavu** | Wang-style landmarks, Python | Yes | 25 percent right under time-stretch [2nd, arXiv 2511.05399] | MIT | Yes |
| **SeekTune**, **SoundFingerprinting** | Wang-style landmarks, in Go and in C# | Yes | None claimed | MIT [2nd, repository records] | Yes |
| **Echoprint** (The Echo Nest) | Onset timing in frequency bands | Yes | Not stated | Code generator MIT [2nd] | Yes |
| **Qfp** (Sonnleitner and Widmer) | Peak quads compared by ratios | Yes in principle | Plus or minus 30 percent, with the ratios reported | Paper only; a Python copy on GitHub carries no licence, so no rights [2nd] | Yes |
| **Neural Audio Fingerprint** (Chang et al., 2021) | Trained embedding per second, contrastive learning | Yes in principle | Not trained for it: 39 percent under time-stretch [2nd] | Code MIT; trained on Free Music Archive clips | Yes |
| **GraFPrint** (2024) | Trained embedding, graph network | Yes in principle | 58 percent under time-stretch, 97 under pitch shift [2nd] | Code MIT | Yes |
| **PeakNetFP** (2025) | Trained embedding computed from peaks; 169,000 parameters | Yes; small enough for a tablet | Over 90 percent from half to double speed, tempo only; pitch untested [2nd] | CC BY-NC-SA 4.0: non-commercial, cannot ship [2nd, repository licence file] | Yes |
| **Foundation-model fingerprints** (2025) | A large music model fine-tuned as a fingerprint | No: far too large [inf] | 96 time, 94 pitch, 87 both [2nd] | Research | Yes |

Notes on the neural line:

- **Neural Audio Fingerprint**, on 100,000 songs: 62 percent right from 1 second, 92 from 5, 96 from 10. Its training
  adds noise, room echo and small time offsets, not pitch or tempo [2nd, arXiv 2010.11910].
- **The 2025 benchmark** (5,000 songs, 10 s queries, stretch 0.7 to 1.5, pitch plus or minus 5 semitones) is the one
  place the systems are compared under speed change; the figures in the table are from it [2nd, arXiv 2511.05399].
- **Another 2025 paper**, on making the training distortions realistic for microphones, has code under GPL-3.0,
  which also cannot ship [2nd, repository record].
- **None of them reports the speed.** They say which song. Deckie also needs the fader, so a trained embedding
  would still need a second step.
- **None returns "no match".** PeakNetFP's authors say so directly: it always answers, and telling a song outside
  the catalogue apart is left as future work [2nd]. A booth hears songs that are not in the crate all night.

## 3. Platforms, and how they do with DJ music

### Published evaluations

**Sonnleitner, Arzt and Widmer, ISMIR 2016** is still the only open test on real mixes that I found [2nd, read in
full]. Eight mixes recorded from the mixing desk in clubs (7 h 16 min; pop, rock, electronic, German folk; 296
reference songs) and ten Creative Commons techno and house mixes (11 h 23 min; 723 reference songs). Each mix was
cut into 20-second queries and scored second by second.

| System | Club mixes: right | Club: precision | Club: stays silent when the song is unknown | Techno mixes: right | Precision | Stays silent |
|---|---|---|---|---|---|---|
| audfprint (plain landmarks) | 42 | 51 | 49 | 64 | 68 | 26 |
| Panako 1.4 (triplets) | 25 | 45 | 75 | 36 | 43 | 35 |
| Qfp (quads, with a checking step) | 74 | 92 | 94 | 88 | 96 | 93 |

All figures percent. Three things matter for Deckie:

- **False matches were the main failure**, not misses. The two simpler systems named a wrong song about half the
  time, against a catalogue of a few hundred songs, the same size as a crate.
- **The checking step is what saved Qfp.** After a candidate is found, it checks that the song's nearby peaks are
  also present in the query. Without it, silence on unknown songs fell from 93 to 65 percent on the techno set.
- **The catalogue size hurts.** Adding 430,000 unrelated songs took Qfp from 74 to 69 percent on the club set.
  Deckie's catalogue is small and known, which is the one advantage it has over every service below.

The authors could not say which DJ actions caused the failures, because the mixes carry no record of them. The
techno set is public under Creative Commons with its reference songs, and is the obvious outside test for the
trial. **UnmixDB** (Schwarz and Fourer, 2018) rebuilds it as synthetic mixes with exact ground truth, including the
speed factor of every song [2nd, Zenodo record].

Since 2016: a 2024 paper on unmixing DJ mixes treats identification as "well handled by fingerprinting" and moves
on [2nd, search summary of arXiv 2410.04198; not read in full]. I found no later accuracy study on real mixes.

### Commercial monitoring in clubs

All figures here are the companies' or the collecting societies' own. None publishes a method, a test set or what
counts as "identified".

| Service | What it does | Claim |
|---|---|---|
| **KUVO, powered by DJ Monitor** (AlphaTheta, the maker of Pioneer DJ decks) | A box in the club listens and reports plays for royalties; it combines listening with track names read straight from the decks. In more than 160 rooms; AlphaTheta bought DJ Monitor's technology in May 2026 | "Above 92 percent", against a library of more than 200 million tracks [vendor, The Fader, Oct 14, 2026] |
| **DJ Monitor**, earlier | UK pilot with PRS for Music and PPL from 2017; festivals and clubs | 93 percent "according to the company" [2nd, Billboard through a search summary]; 80 to 95 percent positive identification over 589 festival sets in 2022 [unverified: PRS's article would not open; figure from a search summary] |
| **YACAST** for GEMA (Germany) | A box taps the DJ booth's output | 97 percent "regardless of genre", as of June 2017; what the fingerprint misses goes to people who identify it by ear [2nd, GEMA] |
| **Audible Magic** | Rights checks for platforms | No club figure. Its own monitoring says up to half the music on user-upload platforms is changed in pitch or tempo, many by 20 percent or more, sped up four times as often as slowed [vendor] |

Two readings of these numbers [inf]. First, they are taken from the mixer's output, not a microphone in the room,
and over a whole play, not the first ten seconds: an easier job than Deckie's. Second, the systems that can read
the song name from the deck do so, and listen only for the rest; that is an admission that listening alone is not
enough for them.

### Services for finding track names

- **Shazam.** A 2013 Spin piece called it "notoriously spotty" on re-pitched records, and quoted Shazam's music
  director saying it would handle songs "sped up or slowed down, as they often are in DJ mixes" [2nd]. Since 2021
  Apple Music has used Shazam's technology to identify the songs inside DJ mixes for royalties; reports at the time
  said a mix was hosted once 70 percent of its tracks were identified [2nd, press reports of a Billboard piece].
  That 70 percent is a threshold, not an accuracy, but it shows what Apple thought was reachable.
- **Beatport Track ID**, with seeqnc (May 2026). Said to be made for pitch-shifted and time-stretched tracks,
  overlapping blends and festival recordings, by cleaning the sound of effects and other layers before matching
  against Beatport's catalogue [vendor]. No range, no accuracy; one reviewer wrote that it still needs real-world
  testing [2nd].
- **Mixcloud** has used Gracenote to identify tracks in uploads [2nd]. **1001Tracklists** is filled in by its users.
- **Tracklist tools** (TrackSniff and others) process a whole recorded mix, taking minutes. Digital DJ Tips reported
  one academy's trial: well-known tracks right, several wrong, most on piano house where records sound alike [2nd].

### What DJs report

I could not reach Reddit threads through search today [unverified]. What I did find: radio DJs on a station
software forum told that pitch-shifted shows are the "likely suspect" when ACRCloud recognition fails (Spinitron,
2020) [2nd]; the Spin piece above; and DJ-press pieces that take it as known that Shazam struggles in a blend. The
pages that say "Shazam fails on DJ mixes" most loudly are competitors' marketing and should be read as such.

### The plain conclusion

Nobody publishes a number for the job Deckie has: a microphone in a loud room, the first 5 to 10 seconds, a song at
any fader setting, maybe under another song. The best open result is 74 to 88 percent on 20-second windows with a
purpose-built method. Deckie has three things those systems lack: a catalogue of hundreds, not millions; every
song's tempo and structure known in advance; and the DJ at hand to tap the right song when it is wrong.

## 4. How often is this needed?

### What decks allow

- **Turntables.** The Technics SL-1200MK2 fader runs plus or minus 8 percent. Later models (M5G, MK5G, GR, MK7) add
  a button for plus or minus 16 [2nd, Technics specification page and model histories].
- **CDJs.** The CDJ-3000's range button steps through 6, 10, 16 and WIDE, which is 100 percent [2nd, rekordbox
  control map and a CDJ manual].
- **Key lock.** djay's manual says it is on by default there [2nd]. Kim et al. write that it is "activated by
  default in modern DJ systems" [2nd]; I did not check each maker's default. I found no survey of how many DJs leave it on [unverified]; forum opinion is
  split between "always on" and "off, because it sounds bad", with the second view strongest for big changes.

### What DJs do: the one large study

Kim, Choi, Sacks, Yang and Nam (ISMIR 2020) lined up 1,557 real mixes from 1001Tracklists against their original
tracks: 24,202 plays, average track tempo 127 BPM, "mostly House and Trance" [2nd, read in full].

| Tempo moved by | Share of plays |
|---|---|
| under 5 percent | 86.1 |
| under 10 percent | 94.5 |
| under 20 percent | 98.6 |

- The shape is sharply peaked at zero with long tails.
- Only 2.5 percent of plays were transposed, and 94.3 percent of those by one semitone. The authors conclude DJs
  "leave the master tempo function turned on in most cases".
- A caution on that last point [inf]: the method sees key only in whole semitones, and a semitone is 5.9 percent. A
  vinyl-style move of 3 percent shifts the key by half a semitone and would not be counted. So "2.5 percent" is the
  share moved by a semitone or more with the key following, not the share played with key lock off.

### What DJs say they do

- The common rule is 5 percent either way, with some DJs holding to 2 or 3 (Digital DJ Tips) [2nd]. Forum posts
  give 4 to 5 percent as the point where a track starts to sound wrong [2nd, search summaries].
- One semitone per 6 percent is the figure DJs use for when the key moves [2nd].

### By kind of DJ [inf, with thin evidence]

- **House, techno, trance.** Songs sit within a few BPM of each other, so moves are small. This is what the study
  measured.
- **Drum and bass.** The same: a narrow tempo band, small moves. I found no figures.
- **Open format, hip hop, weddings.** Songs range from 70 to 130 BPM and more. Two songs 10 BPM apart at 100 need
  10 percent between them. DJs split the difference, use a tempo change as a feature, or cut. I found no data set
  of open-format mixes with ground truth [unverified]. The share of plays beyond 4 percent is likely higher than
  in house, and the largest moves likelier to be done with key lock on, because a 10 percent vinyl move is nearly
  two semitones.
- **Vinyl and older CDJs.** No key lock, or a poor one. Every move is vinyl style, within plus or minus 8.

### The estimate

The study gives the share under 5 percent, not under 4. Fitting the peaked shape through its 5 percent figure gives
79 percent under 4; the real tails are heavier than that shape, which pushes the centre up, and the ceiling is the
86 percent that are under 5. So:

- **In house and trance mixes, 16 to 21 percent of plays are more than 4 percent from the song's tempo**: about one
  play in five or six. At 15 songs an hour that is two or three songs an hour.
- **About 6 to 10 percent are beyond 8 percent, and about 2 to 3 percent beyond 16** [inf, read between the study's
  three figures].
- **Nearly all of it is tempo only.** Vinyl-style moves of a semitone or more are 2.5 percent of plays.

How sure: the figure rests on one study of one kind of DJ (festival and radio mixes by known DJs), with tempo
measured by a beat tracker on both sides, whose own errors widen the tails. Double and half tempo errors would land
far outside 20 percent, and only 1.4 percent of plays are out there, so the tracker is not grossly wrong. For a
working open-format DJ I would put the range at 10 to 35 percent of plays, and say plainly that it is a guess.

One thing the percentage hides: the plays outside 4 percent are not spread evenly. A DJ with a habit, such as the
16 percent vinyl habit letter H was written for, is outside on most songs, every night. For that DJ the product
either works across the fader or does not work.

## 5. Newer and less obvious ideas

For each: how mature, what to expect from 5 to 10 seconds, the cost on a tablet, and licence or patent notes.

### 5.1 Peaks compared by ratios: triplets and quads

- **The idea.** Take three or four peaks. The ratio of two time gaps does not change when the song is sped up; the
  difference of two pitches on a logarithmic axis does not change when it is shifted. Build the table key from
  those. After a match, the raw gaps give back both the tempo ratio and the pitch ratio.
- **Panako** (Six and Leman, 2014): triplets on a constant-Q picture; AGPL. To about 8 percent in 2014; version 2
  found 83 percent of 20-second queries sped up 10 percent [2nd].
- **Qfp** (Sonnleitner and Widmer, 2014 and 2016): quads; 100,000 songs; plus or minus 30 percent. With 20-second
  queries 0.98, 0.98 and 0.94 for speed, tempo and pitch; with 5 seconds 0.77, 0.71 and 0.56 [H; the journal PDF
  did not render today, so I have no 10-second figure]. PeakNetFP's authors rebuilt it and got 48 percent from 2
  seconds and 94 from 20 [2nd].
- **Maturity.** Proven on paper and in the one DJ-mix test. No reusable code: Panako is AGPL and Java; the Python
  copy of Qfp has no licence.
- **At 5 to 10 seconds** [inf]: Qfp's published figures are against 100,000 songs. Against 2,000 the chance of a
  wrong song falls and the bar for a match can be lower, so better than 0.56 to 0.77 at 5 seconds; how much is for
  measurement.
- **Tablet cost** [inf]: small. Quads need a range search in place of an exact table lookup, which is cheap at this
  catalogue size.
- **Patents.** I found no patent by the Qfp authors [2nd, one search]. The nearest patent, Wang and Culbert, is
  listed as expired. A proper search is the attorney's.

### 5.2 A logarithmic pitch axis, where a pitch shift is a slide

- **The idea.** On a constant-Q or log-frequency picture, raising everything by 6 percent moves every peak up by
  the same number of rows. A landmark that stores the distance between its two pitches, not their positions, is
  unchanged. The position of the first pitch can be kept coarsely, or tried at a few shifts.
- **Prior work.** Fenet, Richard and Grenier (ISMIR 2011) built a pitch-robust landmark fingerprint this way [H].
  Panako uses it. Letter H's own quick test read the pitch ratio to 0.00 to 0.06 points from one 8-second window by
  sliding a log-frequency spectrum against the original [H, 4.8].
- **Maturity.** Standard signal processing; a constant-Q transform is more work per second of sound than a plain
  spectrum but well within a tablet [inf].
- **Use.** Whatever fingerprint is chosen, build it on this axis. It makes the vinyl line as cheap as the tempo
  line.

### 5.3 Estimate the speed first, using the beat grid

This is where Deckie has something no general service has, and I found no published system doing it for a known
small catalogue [inf, all of it].

- **The idea.** The crate file holds each song's tempo and beat grid. The booth can track the room's tempo. If the
  room is at 128 and a song is 124, that song, if it is the one playing, is at plus 3.2 percent. So the speed is
  not unknown: it is known per candidate song.
- **Two ways to use it.**
  - *Correct per candidate.* For each song whose tempo is within the fader's reach of the room's (or half or
    double), rescale the query's time gaps by that song's ratio and look up only that song's landmarks. No grid of
    guesses, and songs out of reach are never tried.
  - *Measure time in beats.* Store every landmark's time gap in beats, not seconds, on both sides. A tempo change
    then changes nothing. Pairs are enough; no triplets. Kim et al. lined up whole mixes this way, with features
    averaged per beat, because it "enables tempo invariance" [2nd]; Kurth and others proposed tempo-based features
    for time-scale-invariant identification in 2006 [2nd, cited in Sonnleitner 2016; not opened].
- **What letter H already measured.** Tracking the room's beat blind is good to a median of 0.35 to 0.8 points in
  noise: not good enough to read the fader, but well inside what a landmark tolerates. In a blend of two songs it
  fails (3.6 to 4.7 points), because it locks to the other song [H, 4.8]. So this works when one song dominates and
  needs a fallback in a blend, in a beatless intro, and for the first seconds before the tracker settles.
- **Maturity.** An idea with its parts proven separately. A week's experiment on the trial's test bench.
- **Tablet cost.** The beat tracker already runs in Deckie's engine for analysis; running it live is new work.
- **Patents.** Not searched in depth [unverified].

### 5.4 What Deckie knows, used to narrow the field

- **Tempo reach.** A song more than the fader's range from the room's tempo cannot be playing (allowing half and
  double). In a mixed crate this removes most songs; in a house crate, few [inf].
- **Checking a candidate against the song's own data.** Letter H's option C: lining the room's drum-hit pattern up
  against the song's stored pattern read the tempo to 0.05 to 0.15 points from 8 seconds and held up under an
  equal-level blend [H]. That is a strong second step: any cheap method proposes five songs, and this confirms one
  and reads the fader in the same move. It is the same role as Qfp's checking step, which was what kept false
  matches down on real mixes.
- **Per-bar loudness and the style vector.** Useful as a tie-break and as a sanity check (a quiet intro cannot be
  the loudest bar). Too coarse to name a song [inf].
- **The picks.** The booth already ranks what could come next. The next song is often one of them. That is a fair
  prior for breaking ties; it must never veto, or the booth would be unable to hear a surprise [inf].

### 5.5 A trained embedding of our own

- **What exists.** The contrastive recipe is public and its code is MIT (Neural Audio Fingerprint, GraFPrint). The
  one model built for stretch that is small enough for a tablet, PeakNetFP, is non-commercial. So Deckie would
  train its own: the public recipe, with pitch and tempo changes and real room recordings added to the training.
- **Expected accuracy** [inf from the papers]: 90 percent and more from 5 to 10 seconds on clean digital queries
  under stretch. Through a microphone in a club, under a blend, unknown.
- **Tablet cost.** PeakNetFP is 169,000 parameters; Google's runs on a phone. Not a concern.
- **What it does not do.** It does not report the speed, and it does not say "none of these". Both need the
  checking step of 5.4 anyway.
- **Training data and D15.** The public models train on Free Music Archive clips, whose licences are mixed per
  track and include non-commercial ones. D15 allows weights under their publisher's licence with the training sets
  disclosed; a model of our own means choosing and recording the training music ourselves.
- **Maturity.** Months, and a research track of its own, like the key reader.

## 6. Naming a song that arrives with no name

Recognition in the booth names a song from the crate file. This section is about the step before: Desk reading a
file or a disc that carries no usable name. Letter K covered the disc side in depth; this adds how often, the ways
that send nothing, the lookups, and what other apps do.

### 6.1 How often music arrives unnamed

I found no published count of how DJ libraries are tagged [unverified]. The one measurement is one DJ's library of
2,327 songs, measured Nov 13, 2026:

| | Songs | Share |
|---|---|---|
| Named from tags | 2,273 | 97.7 percent |
| Named from the file name only | 54 | 2.3 percent |
| No artist | 57 | 2.4 percent |
| A generic title | 1 | 0.04 percent |

So in a library of files, nearly every song has a name of some kind; the gap is the artist, and it is small. By
kind:

| Kind | What names it | How often unnamed |
|---|---|---|
| Bought downloads | Tags written by the store | Rarely [inf] |
| Record-pool files | Tags, with version, BPM and key; pools sell on this [vendor]. A DJ TechTools writer found pool tags often inaccurate [2nd, search summary] | Rarely unnamed; sometimes wrongly or inconsistently named |
| CDs ripped on a computer | The ripper asked an online database at the time and wrote tags | Named if the lookup worked; "Track 01" if it was offline or the disc was unknown |
| Burned data CDs of MP3s | The files' own tags and names; the disc adds only a label and folders [K] | As the files were |
| Commercial audio CDs | Nothing on the disc but a table of track lengths, unless it has CD-Text | Unnamed without a lookup; the lookup usually works [K] |
| CD-Text | Names written on the disc itself | Uncommon on pressed discs: mostly Sony's, and some other labels since the 1990s. One collector reported 1 disc in more than 2,000; another found it on most of 40 recent ones. Forum reports only [2nd] |
| Burned audio CDs | CD-Text only if the burning app was told to write it; no database knows the disc [K] | Usually unnamed. This is the hard case |
| Vinyl rips | Whatever the person recording typed | Often a file name only, or nothing [inf] |
| Bootlegs, edits, mashups | A file name from whoever made it | Named, loosely; and in no catalogue |
| Continuous mix CDs | Track marks, with names only from a database or a tracklist | The songs inside are unnamed without a tracklist [K] |

### 6.2 Free ways that send nothing

In the order to try them:

1. **Tags.** Title, artist, album, and the version in brackets.
2. **The file name**, read by pattern: "Artist - Title (Version)", "01 Artist - Title", "Title". Mp3tag has long
   offered this as a batch step with a preview of the result [2nd, in outline].
3. **The folder.** A folder of numbered files is usually an album or a compilation; the folder is the album, and
   sometimes the artist. A hint, shown as a suggestion.
4. **A list beside the music.** A `.cue` sheet names every track and its start time, and is the only thing that
   names the songs inside a continuous mix. `.m3u` playlists can carry names. `.nfo` and `.txt` files often hold a
   numbered tracklist that can be lined up with numbered files.
5. **A DJ-software export.** A rekordbox XML export, or another library file, names every song the DJ has already
   named there, with the path to match on [L].
6. **A named copy of the same recording in the crate.** D24 already says the same recording is the same song; if
   one copy has a name, the other can borrow it [K].
7. **CD-Text**, read from the disc when it is there.
8. **The DJ types it.** Always available, never demanded.

### 6.3 Lookups, as an explicit button

Deckie's promises are: the music never leaves the DJ's devices, nothing is uploaded, no account, works with no
signal. Every lookup below sends something. None sends the song, except where marked. All of them tell the service
which recording the DJ has, from the DJ's network address, and D3's note says privacy covers taste, not only
audio. So none can run unasked.

| Lookup | What leaves the computer | Windows and Linux | Cost and terms for a commercial app | Limits | Dance music, remixes, edits |
|---|---|---|---|---|---|
| **A text search** (MusicBrainz, Discogs, a store) with the words from the tag or file name | The words | Yes | MusicBrainz: free; core data is public domain [unverified today]. Others have their own terms | MusicBrainz: about 1 request a second per address, and the app must name itself with a contact [2nd] | Good when there are words to search. The DJ taggers do this against Beatport, Traxsource, Juno and Discogs [2nd] |
| **AcoustID** with Chromaprint | A fingerprint of the first two minutes, the length, and the app's key | Yes | Free for non-commercial apps only; commercial use by agreement with AcoustID's company, price not published [2nd] | 3 requests a second [2nd] | 94.9 million fingerprints, but only 30.6 percent are linked to a named recording; 88.2 percent of all searches find something [2nd, AcoustID's statistics page, Nov 13]. Its own guide warns that radio edits and tracks that differ only after two minutes come back as the wrong version [K]. Pool edits: the original or nothing. Bootlegs: nothing |
| **MusicBrainz disc id** | A code made from the disc's track lengths | Yes | Free | 1 a second | Pressed CDs: usually found, including DJ mix compilations with their tracklists. Burned CDs: never [K] |
| **gnudb** (the old freedb data) | The disc's track lengths | Yes | Free; freedb itself closed in 2020 [2nd] | Not checked | Pressed CDs, typed in by users over decades; quality varies |
| **Shazam's catalogue through ShazamKit** | A signature, not audio; Apple says the audio cannot be rebuilt from it [2nd, WWDC21]. It goes to Apple | No. Mac, iPhone, iPad; an Android kit exists [L] | Needs a paid Apple developer membership and the ShazamKit service switched on for the app; no per-lookup fee published that I could find [unverified]. Apple's terms forbid using its results to build another recognition service [L] | Not published [unverified] | The largest catalogue; Shazam added a large dance catalogue in 2013 [2nd]. Finds the released original of an edit, not the edit |
| **ACRCloud** | A fingerprint made by its SDK, or the audio | SDKs for the main systems [unverified for Linux desktop] | Commercial, by quote; an old forum figure of about 5.8 dollars per 1,000 [unverified] | By plan | A very large commercial catalogue; no public figures by genre |
| **AudD** | **The audio itself**, or a link to it | Yes, it is a web API | 2 to 5 dollars per 1,000 requests; 300 free [vendor] | By plan | Not stated |
| **Gracenote** | A fingerprint or disc code | By licence | Commercial licence by negotiation; the old free developer programme appears closed [unverified] | By licence | Apple's Music app uses it for CDs [K] |

How each sits against the promises:

- **A text search** sends a few words. It is the mildest, and the only one that helps with an edit, because the
  edit's file name usually names the song it was made from.
- **A fingerprint or signature** keeps "your music never leaves" true in the literal sense and breaks "nothing is
  uploaded" in the plain sense a DJ would mean. If it is offered, the words on screen must say what goes: "Deckie
  sends a short fingerprint of each song to [service] to ask its name. It never sends the song."
- **AudD** uploads the song. It cannot be offered under the promises at all.
- **All of them need a signal**, so naming must never depend on one, and none needs an account from the DJ; the
  app's own key or membership stands in.

And the limit that matters most: the songs most likely to arrive unnamed, burned audio CDs of edits, vinyl rips of
white labels, bootlegs, are the ones no catalogue holds. A lookup rescues the ordinary released song that lost its
tags. For the rest, the name is whatever the DJ says it is, which is also what the deck shows [K].

### 6.4 How other apps handle a song they cannot name

- **beets** (a library manager). It applies a match on its own only when it is very sure; otherwise it stops and
  asks, with: apply, more candidates, skip, use as-is, enter a search, enter an id. A quiet mode never asks and
  skips anything it is unsure of, writing a log. Its guide says plainly that it leans on existing tags, that
  fingerprinting is off by default, and that music missing from MusicBrainz will not match [2nd].
- **MusicBrainz Picard.** Files load into an "unmatched" pane. The user groups them, presses Lookup (by tags) or
  Scan (by fingerprint), and matched files move across to an album view. What cannot be matched stays on the left
  until the user drags it or gives up. Two ways to fail are documented: no fingerprint known, or a fingerprint
  known but linked to no named recording [2nd].
- **Mp3tag.** No guessing: the user writes a pattern, sees a preview, and applies it to a batch [2nd, in outline].
- **OneTagger and Lexicon** (for DJs). A batch run against Beatport, Traxsource, Juno or Discogs by artist and
  title, filling genre, label, year and art. They start from a name; they are not for the nameless [2nd].
- **Rippers.** They ask one or more databases as the disc goes in, show the answer or a choice of answers, and fall
  back to "Track 01" with the fields open for typing. The Music app does this with Gracenote and works offline
  without names [K].
- **DJ software.** It shows the tag, and where there is none, the file name; it never stops an import to ask
  [unverified: I did not find rekordbox's behaviour written down].

What works, across all of them [inf]:

- **Never block.** Every tool that lasts lets the song in under whatever name it has. The ones that stop and ask
  per album are the ones people run overnight in quiet mode.
- **Ask in batches, later, in one place.** A filter that shows "needs a name", not a dialog per song.
- **Suggest with the evidence showing.** Where the name came from (file name, folder, a list, a lookup), and one
  key to accept.
- **Patterns beat guesses.** One pattern applied to forty files with a preview is faster and safer than forty
  suggestions.
- **Keep the DJ's own name.** A lookup's answer is an offer. Letter K's line holds: the name is the DJ's, and the
  identity is the fingerprint.

## Options for the owner

### For recognition

| Option | What it is | Costs | Gains |
|---|---|---|---|
| **R1. Landmarks, with the speed found in the peaks** | The trial's design, with two changes: build on a logarithmic pitch axis, and change speed by arithmetic on the peaks, never on audio; find the speed as the slope of the matching pairs | Weeks. No licence in the way: the method is published and both Shazam patents are listed as expired | One fingerprint per song, about today's size; made on any computer; the fader read from the match itself |
| **R2. R1 plus a checking step from the crate file** | Any candidate is confirmed against the song's stored drum-hit pattern and peaks at the speed found | A little more in the crate file (letter H put the pattern at about 20 KB a song); a week or two | The defence against false matches, which is what sank simple methods on real mixes; a finer fader reading; holds under a blend |
| **R3. Time measured in beats** | Use the room's tempo and each song's grid so tempo changes vanish before lookup | A live beat tracker in the booth; an experiment first | No guessing of speeds at all when one song dominates; fewer songs tried |
| **R4. Ratio fingerprints (quads)** | Our own version of Qfp from the papers | A month or more; a patent search | The best published result on real mixes; any speed |
| **R5. Variants in the catalogue** | Nine fingerprints per song, made from the peaks | Nine times the size | No extra work in the booth; a fallback if probing the query gives too many false matches |
| **R6. A trained embedding of our own** | The public contrastive recipe, trained with pitch, tempo and room recordings | Months; training music to choose and disclose (D15); still needs R2 to read the fader and to say "none" | The smallest fingerprint and likely the best in noise |

**My recommendation.** R1 and R2 together as the build, R3 as the next experiment on the same bench, R5 held as the
fallback, R4 only if R1 to R3 leave a gap, R6 not now. The reasoning: the catalogue is small and known, so the
problem is not finding a needle in a hundred million but refusing wrong answers among two thousand, and the
checking step does that with data the crate file nearly has already. The published evidence says the same thing
from the other side: the method that worked on real mixes was the one that checked.

**What the trial should try next**, in this order:

1. A logarithmic pitch axis, with landmarks keyed on the distance between pitches, so vinyl and key-locked playback
   are handled the same way.
2. Speed changes done on the query's peaks, against speed changes done on the audio, on the same test set: do they
   score the same? If they do, the audio route is dropped.
3. Tolerant lookup with a line fit across the matching pairs, against a fixed grid of speeds.
4. Score false matches as carefully as hits: queries of songs that are not in the catalogue, at every catalogue
   size up to a few thousand, with and without the checking step.
5. Run on the Creative Commons techno mixes from Linz and on UnmixDB, which no setting was chosen on, and report by
   mix, not only overall (D5's library-blind rule). Fetching them needs the owner's word.
6. Queries of 5, 8 and 10 seconds; under a second song at equal level; and from a real deck's key lock, which no
   one has tested [H, open question 3].
7. Time in beats (R3), once 1 to 4 are known.

### For the song with no name

| Option | What it is | Against the promises |
|---|---|---|
| **N1. Local only** | The ladder of 6.2, a "needs a name" filter, patterns with a preview | Nothing leaves. Fully inside them |
| **N2. N1 plus a text lookup button** | Send the words to MusicBrainz or Discogs to fill in the artist and tidy the title | A few words leave, when asked |
| **N3. N2 plus a fingerprint lookup button** | AcoustID on every platform; Shazam's catalogue on the Mac as a second | A fingerprint leaves, when asked, per batch. Needs AcoustID's commercial terms and plain words on the button |

**My recommendation.** N1 now, on every platform, since it covers what the one measured library needs: 54 songs
with file names to read and 57 without an artist. N2 next. N3 only after AcoustID's commercial terms are known, and
with the public line adjusted to stay true: "Your music never leaves. If you ask Deckie to look up a name, it sends
a fingerprint of the song, never the song." AudD is out. Whatever is chosen, a lookup stays a button the DJ
presses, the song comes in either way, and the DJ's own name wins.

## What I could not open or verify

- **Wang's 2003 paper and the Qfp journal paper**: the PDFs did not render here. The method is described from other
  papers that summarise it, and Qfp's figures are letter H's. I have no 10-second figure for Qfp.
- **PRS for Music's article** on DJ Monitor (the 80 to 95 percent figure) and **Billboard's** (93 percent): seen only
  through search summaries.
- **Reddit and other DJ forums**: not reached today. The DJ-report section is thin for that reason.
- **Google's patents** on Now Playing: not found; assume they exist.
- **A patent search for quads, beat-normalised landmarks or the checking step**: one search each at most. This is
  the attorney's work.
- **Open-format and hip hop tempo data, and any survey of key-lock use**: none found.
- **GraFPrint's own results**, the 2024 unmixing paper and Dupraz and Richard 2010: quoted through other papers.
- **ShazamKit's cost and limits for catalogue lookups, Gracenote's current developer terms, ACRCloud's price,
  AcoustID's commercial price, MusicBrainz's data licence page, SoundHound**: not confirmed today.
- **How rekordbox and Serato show a song with no title tag**, and **how common CD-Text is**: forum reports or
  nothing.

## Sources

Google: Now Playing paper https://arxiv.org/abs/1711.10958 (read as https://ar5iv.labs.arxiv.org/html/1711.10958);
"Google's Next Generation Music Recognition" https://research.google/blog/googles-next-generation-music-recognition/ ;
VentureBeat on the database size
https://venturebeat.com/business/how-googles-pixel-2-now-playing-song-identification-works .

Shazam and Apple: Wang 2003 https://www.ee.columbia.edu/~dpwe/papers/Wang03-shazam.pdf (not rendered);
US 6,990,453 https://patents.google.com/patent/US6990453B2/en ; US 7,627,477
https://patents.google.com/patent/US7627477B2/en ; WWDC21 session 10044
https://developer.apple.com/videos/play/wwdc2021/10044 ; WWDC22 session 10028
https://developer.apple.com/videos/play/wwdc2022/10028/ ; Spin, 2013
https://spinmagazine.com/2013/02/shazam-adds-15-million-dance-tracks-database/ ; Apple Music and DJ mixes
https://musicbusinessworldwide.com/apple-music-is-now-using-shazam-technology-to-identify-tracks-in-dj-mixes-so-that-rightsholders-get-paid
and https://www.macrumors.com/2021/09/10/apple-music-shazam-pay-dj-mixes/ .

DJ mixes: Sonnleitner, Arzt and Widmer 2016 https://www.jku.at/fileadmin/gruppen/173/Research/187_Paper.pdf ; data
sets https://www.cp.jku.at/datasets/fingerprinting/ ; UnmixDB https://zenodo.org/record/1422385 ; Kim et al. 2020
https://arxiv.org/abs/2008.10267 and https://mir-aidj.github.io/djmix-analysis/ ; Sonnleitner's dissertation
https://www.cp.jku.at/research/papers/Sonnleitner_Dissertation.pdf (not opened).

Speed-tolerant fingerprints: Qfp https://www.cp.jku.at/research/papers/preprint_TASLP2509248.pdf (not rendered) and
https://github.com/mbortnyck/qfp (no licence); Panako https://github.com/JorenSix/Panako ,
https://archives.ismir.net/ismir2014/paper/000122.pdf and https://0110.be/date/2021/11 ; Olaf
https://github.com/JorenSix/Olaf ; audfprint https://github.com/dpwe/audfprint ; Dejavu
https://github.com/worldveil/dejavu ; SeekTune https://github.com/cgzirim/seek-tune ; SoundFingerprinting
https://github.com/AddictedCS/soundfingerprinting ; Echoprint
https://github.com/spotify/echoprint-codegen/blob/master/LICENSE ; Chromaprint
https://github.com/acoustid/chromaprint/blob/master/LICENSE.md .

Neural fingerprints: Chang et al. 2021 https://arxiv.org/abs/2010.11910 and
https://github.com/mimbres/neural-audio-fp ; GraFPrint https://arxiv.org/abs/2410.10994 and
https://github.com/chymaera96/GraFP ; PeakNetFP https://arxiv.org/abs/2506.21086 and
https://github.com/guillemcortes/peaknetfp (LICENSE: CC BY-NC-SA 4.0); foundation-model benchmark
https://arxiv.org/html/2511.05399 ; robustness to degradation https://arxiv.org/abs/2506.22661 and
https://github.com/raraz15/neural-music-fp (GPL-3.0).

Commercial recognition: ACRCloud https://www.acrcloud.com/blog/pitch-shifting-supported/ and
https://docs.acrcloud.com/get-started/tutorials/recognize-custom-content-offline ; AudD https://audd.io/ and
https://docs.audd.io/enterprise ; Audible Magic
https://www.audiblemagic.com/2024/06/06/audible-magics-broad-spectrum-detecting-transformed-audio/ ; Gracenote
https://www.nielsen.com/solutions/content-metadata/music-recognition/ ; Spinitron forum
https://forum.spinitron.com/t/recognition-fails-for-some-pre-recorded-shows-pitch-shift/169 .

Club monitoring and track naming: The Fader on KUVO
https://www.thefader.com/2026/10/14/alphatheta-kuvo-music-recognition-technology ; PRS for Music and PPL pilot
https://prsformusic.com/press/2017/ppl-and-prs-for-music-launch-music-recognition-technology-pilot ; PRS feature
(not opened)
https://www.prsformusic.com/m-magazine/features/the-future-of-mrt-how-djmonitor-is-transforming-the-payments-landscape ;
GEMA https://www.gema.de/en/music-creators/monitoring/discotheque-monitoring ; Beatport Track ID
https://www.beatportal.com/articles/1405405-beatport-launches-track-id-a-music-discovery-tool-built-for-djs and
https://weraveyou.com/2026/05/beatport-track-id-music-recognition-dj-2026/ ; TrackSniff
https://www.digitaldjtips.com/tracksniff-shazam-alternative/ ; Mixcloud and Gracenote
https://routenote.com/blog/?p=13556 .

Decks and practice: Technics SL-1200GR https://technics.com/au/products/turntables/sl-1200gr.specs.html ; CDJ-3000X
control map https://cdn.rekordbox.com/files/20250907160902/CDJ_XDJ_Control_Mapping_en_CDJ-3000X.pdf ; djay key lock
https://help.algoriddim.com/user-manual/djay-ios/dj-tools/key-lock/key-lock ; Digital DJ Tips on tempo range
https://www.digitaldjtips.com/?p=2183461 ; key lock glossary https://www.mixgraph.io/glossary/key-lock .

Naming: AcoustID web service https://acoustid.org/webservice and statistics https://acoustid.org/stats ; Picard on
AcoustID https://picard-docs.musicbrainz.org/en/tutorials/acoustid.html ; MusicBrainz rate limits
https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting ; freedb https://en.wikipedia.org/wiki/Freedb ; beets
autotagger https://beets.readthedocs.io/en/stable/guides/tagger.html ; OneTagger
https://community.enginedj.com/t/onetagger-music-tagger-for-djs/48314 ; CD-Text reports
https://hydrogenaud.io/index.php/topic,47514.0.html and
https://forums.anandtech.com/threads/why-dont-more-cds-have-cd-text.489776 .

In the repo: `docs/research/h-pitch-robust-recognition.md`, `l-non-apple.md`, `k-cd-and-album-ingestion.md`;
`docs/product/00-decisions.md` (D3, D5, D14, D15, D24, D29); `docs/product/voice.md`.
