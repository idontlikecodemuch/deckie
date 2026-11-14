# Research AB: fingerprints that hold up in a noisy room, and how small they can be

Dated Nov 14, 2026. Web research and reading only: no code, no build, no measurement, no commit. It follows D35 (we
go for a fingerprint of our own; noise first, size next) and builds on letter W2 (the trial and its numbers), letter
W (the field, already surveyed) and letter H (ShazamKit across the fader). It does not repeat them. Tags: [read] =
read in the source itself today; [via] = taken from another paper's account of it, an abstract or a search summary,
the source itself not opened; [W2], [W], [H] = from that letter; [vendor] = a company's own claim; [inf] = my
inference, with the reasoning; [unverified] = I could not open or confirm it. Figures "read from the plot" were taken
off a published graph by eye and are good to a few points. Not legal advice: licence and patent notes are from public
listings and need the attorney before anything ships.

## In plain words

A **fingerprint** is a small description of how a recording sounds, made so that a few seconds heard through a
microphone can be matched to the right song. The trial's fingerprint works on a **spectrogram**, a picture of sound
with time across and pitch up the side. It marks the **peaks**, the spots louder than everything around them, and
looks them up in threes. Each group of three is turned into one number, a **hash**, which is what the booth looks up.
The **index** is the table of every song's hashes that the booth holds while it listens.

**Noise** is measured against the music as a **signal-to-noise ratio**, in decibels (dB). At 0 dB the crowd is as
loud as the music at the microphone; at +10 dB the music is ten times the crowd's power; at -5 dB the crowd is about
three times the music's. **Reverberation** is the room's echo, which smears every sound in time. **Clipping** is what
an overdriven speaker or microphone does: it flattens the tops of the wave, which adds tones that were not in the song.

The owner's observation was that the fingerprint uses only the loudest points, and that a loud crowd or a distorting
speaker would spoil those. The reading backs it, and adds three things.

1. **The loudest point is a good choice, and a fragile one when three must survive together.** Shazam's own paper
   chose the loudest points because they are the most likely to survive noise. But if one point in three is knocked
   out or moved, the whole hash is lost. With pairs, a point that survives half the time gives a hash that survives a
   quarter of the time; with threes, an eighth. The trial already measured the price: about 20 points at equal-level
   crowd noise.
2. **Every system that does well in noise has the same shape: a cheap first pass that proposes a few songs, then a
   careful check of each one.** The published systems differ in what the first pass looks at. They agree on the check.
   The trial has a check; it is used on a dozen candidates that the three-point hashes already had to find.
3. **The published systems that are best in real bars and clubs are trained models, and they are not small or free to
   use.** The best published figure on real recordings from bars, nightclubs and concert halls is 82 percent from 5
   seconds, by a trained model of about 200 MB under a licence that cannot ship. The classic Shazam method, in its own
   2003 paper, named 80 percent of songs from 5 seconds and 96 percent from 10 at equal-level pub noise, with no room
   echo and no pitch fader to cover.

On size, the plain finding is that the index does not need to be dense. The systems built for small memory keep a
thin index (9 to 20 hashes for each second of a song, where the trial keeps 192), take many more points from the
microphone than from the songs, and rely on the check. And on an iPad a file that is opened in place from storage,
never copied into memory, does not count against the app's memory limit, by Apple's own account.

What I recommend trying, in order, is in "Options for the owner and the trial". The first three change only how the
booth matches, not what the crate file holds: gather evidence across several seconds of listening; let the first pass
propose more songs and let the check decide; and once a song is named, follow it, which is far easier than finding it.

## 1. How the fingerprints that survive noise work

### What the trial does now, as the baseline [W2]

Mono at 8 kHz, a spectrogram every 16 ms, a point kept wherever it is the loudest within 96 ms and 12 percent of its
own frequency, between 300 and 3600 Hz: 32 points a second. Each point is hashed with two later points (three in
all), six hashes a point, 192 hashes a second of music. The strongest point in each slice of the zone after the
anchor is the one taken. At equal-level crowd noise in a measured room it names 60 percent of songs from 8 s; with
two-point hashes, about 80 percent on the development sample, at ten times the matching time.

### The families, side by side

"Speed" below means the deck's pitch fader with key lock off (time and pitch move together); "tempo" means key lock on.

| Family | What it measures | Additive noise (a crowd) | Reverberation | Clipping, overdriven speakers | A small microphone's band | Speed and tempo change |
|---|---|---|---|---|---|---|
| **Peak pairs** (Wang 2003; audfprint; Dejavu; Olaf) | Where the loudest spots are; the hash is two pitches and the time between | Good while the peaks stay the loudest things nearby; a hash dies if either point is lost or moves one step | Smears onsets in time, so peaks shift a frame or two; tolerable [inf] | Adds peaks at overtones; the true peaks mostly stay [inf]; the trial lost about 25 points under UnmixDB's distortion [W2] | Indifferent: "a peak in the spectrum is still a peak" after equalising [read, Wang] | None beyond a few percent unless the matcher searches speeds |
| **Peak triples and quads** (Panako; Qfp; the trial) | The shape made by three or four peaks | Worse than pairs: all points must survive. Qfp holds to +15 dB and falls below [read] | As pairs | As pairs | As pairs | Built for it: Qfp to plus or minus 30 percent [read] |
| **Sub-band energy differences** (Haitsma and Kalker; Philips) | For 33 pitch bands every 11.6 ms: is this band louder than the next, and is that difference growing? One bit each | Bits flip one by one, so the match weakens gradually and never collapses on one lost point; Gracenote reports matching at -4 to -7 dB with a weighting added [via] | Echo addition raised the error rate to 0.14 to 0.16 against a limit of 0.35 [read] | Amplitude compression: 0.05 to 0.11, barely touched [read] | Band-pass filter: 0.02 to 0.04 [read] | Fails beyond about 2.5 percent speed; tempo of 4 percent survives [read] |
| **Learned box filters** (Ke, Hoiem and Sukthankar 2005) | As above, with the 32 comparisons chosen by training on clean and noisy pairs | Depends on the training noise; did worst of three on real phone recordings [read, Chandrasekhar 2011] | Not stated | Not stated | Not stated | Not stated |
| **Wavelet picture** (Waveprint; Baluja and Covell) | A third of a second of spectrogram as a small picture; keeps the signs of its 200 strongest wavelets, squeezed to 100 bytes | Best of three on real noisy phone recordings: about 93 percent from 5 s where peak pairs got 46 [read, Chandrasekhar 2011] | Not stated | Not stated | Not stated | Tempo to 10 percent; speed breaks at 2 percent [via Sonnleitner 2016] |
| **Chroma** (Chromaprint) | Loudness of each of the 12 notes over time, compared by 16 trained filters into 32 bits | Not built for it: made for whole clean files [read; W] | Not stated | Not stated | Folding octaves together discards the band's detail | None [W] |
| **Spectral flatness** (MPEG-7 AudioSignature; Fraunhofer's AudioID) | For each band, how tone-like or noise-like it is | Weak by construction: added noise makes every band flatter, so the measure itself moves with the noise level [inf] | Not checked | Not checked | Not checked | Not checked [unverified: sources not opened today] |
| **Binary descriptors round a peak** (MASK, Telefonica; ORB or SIFT on the spectrogram) | Find a peak, then describe the patch of sound round it in bits (which neighbouring regions are louder) | A peak is still needed, but one peak with its patch replaces two or three bare peaks [inf] | Not stated | Not stated | Not stated | SIFT on a logarithmic pitch axis: very robust to both [via Sonnleitner 2016] |
| **Thresholded picture** (Gracenote; Rafii, Coover and Han 2014) | A logarithmic-pitch spectrogram turned black and white: each cell is 1 if it is above the median of its neighbourhood | Made to match live performances to studio recordings; figures not opened [via] | Not stated | Robust to large changes of timbre and energy, by its patent's account [via] | Not stated | Key and tempo changes handled in the matching [via] |
| **Trained embedding** (Google Now Playing; Neural Audio Fingerprint; the 2025 models) | A small trained model turns each second into 64 to 128 numbers | The best published figures (table below), because noise is in the training | Trained in, with measured rooms | Only if trained in; Deezer's simulation, made for its denoiser, clips up to 1 percent of samples [read] | Trained in, with microphone responses | Only if trained in; none reports the speed [W] |

### Published accuracy in noise

No two rows share a test, so read down a row, not across.

| System, source | Catalogue | Noise | Query | Right song named |
|---|---|---|---|---|
| Peak pairs, Wang 2003 [read; read from the plots] | 10,000 songs | Pub noise mixed in digitally, no room, 8 kHz | 5 / 10 / 15 s | 0 dB: 80 / 96 / 97. -3 dB: 55 / 83 / 94. -6 dB: 22 / 57 / 84. Half are named at -3 / -6 / -9 dB |
| The same after a phone's voice codec (GSM) [read] | 10,000 | As above | 5 / 10 / 15 s | 0 dB: 14 / 55 / 82. Half are named at +4 / 0 / -3 dB |
| The trial, three-point [W2] | 969 | Measured room, crowd at 0 dB, five fader settings | 5 / 8 / 12 s | 48 / 60 / 72 |
| The trial, two-point, development sample [W2] | 969 | As above | 5 / 8 / 12 s | 65 / 80 / 83 |
| ShazamKit [H] | 373 | Synthetic reverb, pink noise at 0 dB | 8 s | 90 to 100 |
| Peak pairs (Ellis's code, tuned), Chandrasekhar 2011 [read; from the plot] | 39 songs, all pairs scored | Real: a phone recording a TV or laptop speaker in noisy places | 5 / 10 / 15 s | 46 / 80 / 87 |
| Waveprint, same test [read; from the plot] | 39 | Same | 5 / 10 / 15 s | 93 / 97 / 97 |
| Ke et al., same test [read; from the plot] | 39 | Same | 5 / 10 / 15 s | 37 / 56 / 61 |
| audfprint, Deezer 2023 [read] | 4,888 | Simulated: scenes at -10 to +10 dB, room, microphone, clipping | 3 / 5 / 10 s | 43 / 62 / 79; clean 89 / 96 / 99 |
| audfprint, same, 105,721 songs [read] | 105,721 | Same | 3 / 5 / 10 s | 25 / 45 / 65 |
| Dejavu, Chang 2021 [read] | 10,000 clips of 30 s | Simulated, 0 to 10 dB, rooms and microphones | 6 s | 69.6 |
| Quads (Qfp), Sonnleitner and Widmer 2016 [read; from the plot] | 100,000 | White noise, with a search over plus or minus 30 percent | 15 s | About 0.4 at 0 dB, 0.8 at +10, 0.92 at +15 |
| Now Playing as rebuilt by Chang 2021 [read] | 100,000 | Simulated, 0 to 10 dB | 5 / 10 s | 78 / 88 |
| Neural Audio Fingerprint, Chang 2021 [read] | 100,000 | Same | 1 / 3 / 5 / 10 s | 62 / 87 / 92 / 96 |
| The same model on real venue recordings, Araz 2025 [read] | 95,163 | Real: phones and recorders in bars, nightclubs and concert halls | 5 / 10 s | 65 to 71 / 72 to 76 |
| Araz et al.'s model (2025), simulated / real [read] | 95,163 | As above | 5 s | 94.5 / 82.0 |
| A transformer model, Nikou and Giannakopoulos 2025 [via abstract] | Over 100,000 | Real: played and re-recorded with noise at three levels | 10 s low noise; 15 s heavy noise | 97; 56.5 |

Four readings of this table:

- **Wang's own pairs, in his own test, are well ahead of the trial at 0 dB** (96 percent from 10 s against 72 from
  12). His test has no room, one speed and pub noise; the trial has a measured room, 69 candidate speeds and three
  points a hash. Each of those costs something, and the trial's two-point column (80 at 8 s) sits between. So the
  method has more to give than the trial's fast matcher takes, as W2 said [inf].
- **On real phone recordings, a picture of the whole spectrogram beat peaks by a wide margin at 5 seconds, and the
  gap closed by 15.** Chandrasekhar, Sharifi and Ross put it down to peak pairs being "sensitive to small offsets" in
  where a peak lands, and to dense fingerprints seeing more of the sound [read]. The price was six times the data.
- **Simulated noise flatters every system.** The same trained model lost 20 to 25 points going from simulated to real
  venue recordings; the best one lost 12 [read, Araz 2025].
- **Length buys noise.** In Wang's curves each doubling of the listening time moves the half-way point by about 3 dB
  [read].

### Size, licence and patents

Sizes are for the reference side. "A song" is four minutes unless the source says otherwise.

| System | Bits or bytes per second of music | What the index held | Licence and patents, from public listings |
|---|---|---|---|
| Haitsma and Kalker | 32 bits every 11.6 ms: 2.6 kbit/s, about 78 KB a song [read] | 10,000 five-minute songs are 250 million 32-bit values (1 GB [inf]) plus a lookup table [read] | US 7,549,052 listed expired Jul 6, 2024 [W2] |
| Wang 2003 | A 64-bit record per hash: 32 for the hash, 32 for time and song; hashes are points times a fan-out, 10 in the paper's example [read] | Sorted records; density and fan-out set higher for phones than for radio [read] | US 6,990,453 and US 7,627,477 listed expired [W2] |
| audfprint | 20 hashes a second by default ("7 works well" for references), 20-bit hash, 4 bytes an entry (18 bits of song, 14 of time; the hash is the bucket's position) [read] | 1 million buckets of 100 entries; full buckets drop entries at random [read]. About 19 KB a song [inf] | MIT |
| Ellis's code as tuned by Chandrasekhar | 587 hashes of 20 bits per 10 s of query [read] | Not stated | |
| Qfp (quads) | 9 quads a second from about 9 peaks a second; 36 bytes a record, 24 possible [read] | 100,011 songs in 9.85 GB: 98 KB a song, of which the peaks kept for checking are 16 KB [read] | Paper only; no patent by its authors found [W2] |
| Panako 2014 | Estimated 28 GB for a million songs: 28 KB a song [via Sonnleitner 2016] | Key-value store | AGPL-3.0 |
| Olaf | 100,000 tracks in a 15 GB database: 150 KB a track [read; the division is mine] | LMDB on disk | AGPL-3.0; its README warns of US 7,627,477 and US 6,990,453 "and perhaps others" [read] |
| Waveprint, as tuned by Chandrasekhar | 100 bytes about ten times a second: about 0.9 KB/s, 200 KB a song [read; arithmetic mine] | 25 tables of 4-byte bands | US 8,411,977 (Google) listed "Expired - Fee Related"; a continuation, US 8,977,067, status not found [via] |
| Ke et al. | 32 bits every 11.6 ms, as Haitsma and Kalker [read] | | Not searched |
| Chromaprint | 32 bits about 8 times a second: 32 bytes/s, 8 KB a song [inf from the stated frame sizes] | Compared whole | MIT; LGPL 2.1 with its FFmpeg parts [W] |
| MASK (Telefonica) | Not opened | | Applications EP 2 751 804 and US 14/241,665; status not found [via] |
| Thresholded picture (Gracenote) | Not opened | | "Audio identification based on data structure", US 10,713,296, US 11,907,288 and US 12,105,754: recent grants, so assume in force [via; not read] |
| ShazamKit | About 45 KB a song for one signature [H] | Sealed | Apple's SDK terms |
| Now Playing | One 96-number embedding a second, squeezed about 32 times: under 3 KB a song [read] | Tens of thousands of songs on a phone [read] | Not available; patents not found [W] |
| Neural Audio Fingerprint | 5.8 GB for 56 million half-second segments: about 100 bytes each, 50 KB a song [read; division mine] | Product-quantised index; under 0.1 percent lost against exact search [read] | Code MIT [W] |
| Araz et al. 2025 | Not stated; the model itself is about 200 MB [read] | | Code and weights Affero GPL-3.0 (the page also shows GPL-3.0) [read] |
| The trial | 96 bytes/s on disk (23 KB a song); 192 hashes/s and about 0.3 MB a song in memory [W2] | Built in memory when the crate file opens | Our own code |

### Each family, plainly and then precisely

**Sub-band energy differences (Haitsma and Kalker, Philips, 2002)** [read in full].

- *Plainly.* Slice the sound into 33 pitch bands. Every hundredth of a second ask of each neighbouring pair of bands:
  is the lower one louder than the upper one, and is that more so than a moment ago? Write a 1 or a 0. Thirty-two
  answers make one line of the fingerprint; 256 lines (3 seconds) are compared with the song's lines by counting how
  many answers differ.
- *Precisely.* 5 kHz mono; 0.37 s frames, 31/32 overlap, so one 32-bit sub-fingerprint every 11.6 ms; 33
  logarithmically spaced bands from 300 to 2000 Hz; bit = sign of the energy difference along frequency and time
  together. A match is a bit error rate under 0.35 over 8,192 bits, for which the paper derives a false-match chance
  of 3.6 in 10^20.
- *Why it survives.* Each bit is a comparison of two neighbouring energies, so anything that scales or tilts the
  sound leaves it alone. No single bit matters: noise flips some, and the count rises smoothly.
- *Where it fails.* Speed. The bands sit at fixed frequencies and the frames at fixed times; beyond about 2.5 percent
  of speed change the error passes the limit. The authors' remedy is "appropriate pre-scaling (for example by
  exhaustive search)", the same idea as the trial's candidate speeds.
- *Its search is the part to borrow.* One exactly matching 32-bit line is enough to propose a place in a song; the
  full 3-second block then decides. When no line is exact, the bits nearest to their threshold (the least reliable
  ones) are flipped and tried. With the 10 weakest bits tried, a clip through a phone codec went from 1 to 57 exact
  hits of 256, and a clip at the edge of reception from 0 to 3.
- *Noise figures are thin.* The paper's "noise addition" row is mild white noise. Gracenote's Coover and Han (2014)
  studied the Philips fingerprint in heavy noise and, with a weight on each bit, report recognition at -4 to -7 dB on
  1,030 songs [via abstract; paper not opened].

**Landmarks (Wang, Shazam, 2003)** [read in full].

- *Plainly.* Keep only where the loudest spots are, not how loud. Pair each with a few later ones. A match is many
  pairs agreeing on one place in one song.
- *Precisely, the parts W did not have.* Peaks are chosen by two rules together: a **density criterion**, "to assure
  that the time-frequency strip ... has reasonably uniform coverage", and amplitude within each locality. Amplitude
  is then thrown away, which makes the fingerprint "fairly insensitive to EQ". A hash is 32 bits; each is stored
  with 32 bits of time and song. With a fan-out of 10, storage is ten times the bare points and the search about
  10,000 times faster. The paper states the trade the trial ran into: pairing "squares the probability of point
  survival", made up for by having many hashes per point. And a match needs very little: "only about 1-2% of the
  generated hash tokens actually surviving" from a heavily corrupted 15 s sample.
- *What is publicly known of later Shazam and ShazamKit.*
  - The SongRec project's README, a reverse-engineered description, says the app now works at 16 kHz and cuts the
    sound into four bands (250 to 520, 520 to 1450, 1450 to 3500 and 3500 to 5500 Hz), so that if one band is too
    noisy "recognition from other bands may apply", and that the signature sent is a list of (frequency, amplitude,
    time) points, with the pairing done on the server [read]. I read the README only, not the code, which is GPL-3.0,
    to keep the trial's position that no GPL code was read.
  - ShazamKit matches within about 4 percent of speed and reports the pitch skew exactly [H], which fits the expired
    Wang and Culbert patent on finding the speed from the matched pairs [W].
  - The later patents I could see listed (US 8,190,435; 8,386,258; 9,401,154; 9,899,030; 10,497,378) carry the 2003
    title and abstract [via]. I found no talk or paper from Apple describing a change of method since [unverified].
  - So three differences from the trial are on the public record: a wider band (to 5.5 kHz against 3.6), picking in
    four bands separately, and keeping each point's amplitude.

**Wavelet and picture fingerprints (Waveprint, Baluja and Covell, Google, 2006 to 2008)** [via Chandrasekhar 2011 and
Sonnleitner 2016, both read; the Waveprint papers themselves not opened].

- *Plainly.* Treat each third of a second of spectrogram as a small photograph and fingerprint it the way photographs
  are matched: keep only its boldest strokes.
- *Precisely.* Overlapping spectrogram images of 0.372 s; a Haar wavelet transform; only the signs of the top 200
  wavelets kept; min-hash reduces that to 100 bytes; 25 hash tables of 4-byte bands find near matches.
- *Why it survives.* The whole picture votes, not three points of it; noise changes some strokes and leaves most.
- *Cost.* About six times the data of peak pairs per second, and it breaks at 2 percent of speed.

**Chroma (Chromaprint)** [read, its author's 2011 post]. 11,025 Hz, frames of 0.37 s overlapping by two thirds, the
spectrum folded to 12 notes, 16 trained filters each giving 2 bits. Small and good at telling files apart. It
measures harmony, which a crowd's voices also have, and it was not made or tested for microphones. Not a candidate.

**Constant-Q, triples and quads (Panako; Qfp; Olaf)** [Qfp read in full; W covered the rest].

- What is new for this letter is how Qfp handles size and noise. It takes about 9 peaks and **9 quads a second from
  the songs**, and **about 1,500 quads a second from the query**, with a finer peak picker on the query side. It
  keeps "strong" quads, chosen by the loudness of their points, and reports that this "extracts the robust quads"
  and raised accuracy. It does not quantise its hashes: it searches for near values, because with quantised hashes
  "one or more peaks of the triple migrate into a neighbouring bin" and the hash changes although the sound barely
  did. The authors name this as the likely cause of Panako's misses even on clean audio.
- Its noise result is the caution: "stable and high performance for SNR down to +15dB". Four points must all survive.

**Spectral flatness (MPEG-7 AudioSignature, Fraunhofer's AudioID, 2001)** [unverified today; Haitsma and Kalker cite
it as the MPEG-7 descriptor "AudioFlatness"]. It measures, band by band, whether the sound is tone-like or noise-like.
It was built for broadcast and codec changes. I found nothing that tests it in a crowd, and the measure itself drifts
as noise is added [inf]. Not a candidate.

**Binary descriptors (Ke et al. 2005; MASK 2012; ORB and SIFT on spectrograms)**.

- Ke, Hoiem and Sukthankar replaced Haitsma and Kalker's fixed comparisons with 32 box-shaped comparisons chosen by
  training on clean and noisy pairs, and checked candidates with a geometric fit [via Chandrasekhar 2011, read]. In
  that independent test it did worst, and the reviewers' reason matters for any trained method: "a mismatch between
  training and test data can affect the performance of this scheme adversely".
- MASK (Anguera, Garzon and Adamek, Telefonica, 2012) finds salient peaks and then describes the energy round each
  in bits, so one peak carries what a pair or triple of bare peaks would [via abstract; paper not opened].
- SIFT descriptors on a logarithmic spectrogram were "exceptionally" robust to speed, tempo and pitch on a small
  catalogue [via Sonnleitner 2016].

**Trained embeddings** [Now Playing and Chang 2021 read; Araz 2025 read; others via].

- *Plainly.* A model is shown thousands of clean clips beside the same clips with noise, rooms and microphones
  added, and adjusts itself until both land on nearly the same short list of numbers.
- *Now Playing* (Google, 2017): 96 numbers a second, under 3 KB a song, a first pass that touches about 2 percent of
  the database and then a score over the whole sequence. The paper gives curves, not noise figures [read].
- *Neural Audio Fingerprint* (Chang et al., 2021): 8 kHz, 300 to 4000 Hz, one-second segments every half second, 64
  or 128 numbers; trained with noise at 0 to 10 dB (including 2.3 hours of pub and cafe noise the authors recorded),
  measured rooms and microphone responses. With no such training it scored 0.0 percent [read].
- *Araz et al. (2025)* is the one paper I found that tests on **real recordings from bars, nightclubs and concert
  halls**: 3,692 pairs made with phones and recorders, with the monitoring company BMAT [read]. The recordings are
  not in the public release as far as its page shows [read].
- *PeakNetFP (2025)* feeds 256 peaks a second to a small model (169,000 parameters); it reports no noise test and
  always returns a match [read]. *Since then:* a variable-length fingerprint (March 2026, arXiv 2603.23947) and
  pretrained Conformers (arXiv 2508.11609) [via search summaries; not read].
- *What they cost Deckie:* training music to choose and disclose (D15), no reading of the fader, no "none of these"
  [W], and the strongest models are large and under licences that cannot ship.

## 2. Why picking the loudest points is fragile, and the known remedies

### The mechanism

- **Three things happen to a peak in noise.** It is *buried* (something louder appears nearby and takes its place),
  it is *moved* (the maximum shifts a frame or a pitch step), or a *false* peak appears. Deezer measured it on
  audfprint's peaks under their simulated venues: only about a quarter of the noisy clip's peaks matched the clean
  clip's (precision 0.28, recall 0.24) [read].
- **False peaks cost little; lost and moved ones cost a lot.** Wang: matching survives "spurious peaks injected due
  to noise, as peak positions are relatively independent", and also many deletions [read]. But a moved peak is a
  deleted one to a quantised hash [read, Sonnleitner 2016].
- **The arithmetic of groups.** If a point survives with chance *p*, a pair survives with about *p* squared and a
  triple with *p* cubed. At *p* = 0.5 that is 25 percent against 12.5; at 0.3, 9 percent against 2.7 [inf, after
  Wang's own argument]. This is the trial's two-point against three-point table in one line.
- **A crowd is not spread evenly.** Speech has most of its power from about 250 Hz to 4 kHz, falling by roughly 6 dB
  an octave from 1 kHz and faster above 4 kHz [via; Byrne et al. 1994 not opened]. The trial reads 300 to 3600 Hz:
  the crowd's own band. And a voice is made of strong steady harmonics, which are exactly what a peak picker likes.
- **The trial's target rule lets one loud voice take a whole anchor.** Each anchor's six hashes use the strongest
  point in each of six time slices [W2]. If a talker's harmonic is the strongest thing in those slices, every hash
  from that anchor contains a point that is not in the song [inf].
- **The level in the tables may understate the noise the fingerprint sees.** The trial's benchmark sets the noise
  against the music's whole power. Dance music carries much of its power below 300 Hz, where the fingerprint does
  not look. W2's own table shows it: with the music first limited to 250 to 3000 Hz (so that all its power is in
  band), 79 percent were named at 0 dB; with full-range music, 60. So "0 dB" in the room and crowd rows is several
  dB worse than 0 inside the fingerprint's band [inf, from W2's table and the benchmark's script]. Letter H limited
  the band to 120 Hz to 8 kHz before adding noise, which is one more reason the two sets of figures differ.

### The remedies, with the evidence for each

| Remedy | What it is | Evidence, and how much | Cost |
|---|---|---|---|
| **Density and quotas** | Aim for an even number of points per stretch of time and pitch, not a fixed loudness rule | Wang's "density criterion" [read]; audfprint's target of hashes per second with at most 5 peaks a frame [read]; Shazam's four bands picked separately so one noisy band cannot starve the rest [read, SongRec README]. No published gain in points | None in size |
| **A masking curve that decays** | After a peak, raise a threshold round it that falls away in time and spreads in pitch; only what pokes above is a new peak | audfprint spreads each peak's threshold over 30 bins of pitch [read]; how it decays in time is on Ellis's page, which returned an error. The trial's fixed neighbourhood does a similar job | None |
| **More points from the microphone than from the song** | Thin, strong points in the index; a dense, forgiving picker on the query | Qfp: 9 quads/s against about 1,500 [read]; Wang: density and fan-out "may be chosen for different signal conditions" [read] | Query time; a smaller index |
| **Keep the strong ones** | Rank points or groups by how far they stand above their surroundings; index the top ones | Qfp reports higher accuracy with strong quads [read, no figure]; Wang's reason for amplitude [read]. The trial stores a strength level already and uses it only to pick targets [W2] | None; it shrinks the index |
| **Stable, not only loud** | Prefer points that last (a steady tone over several frames) or that sit on a sharp onset across many pitches; ignore gliding ones, which is what voices do | Gracenote's "foreground harmonic noise reduction" removes voice-like gliding lines before peaks are picked and reports that previously unrecognised queries became recognisable in speech and babble [via search summary; the slides did not open]. Median filtering separates steady tones and drum hits from the rest (FitzGerald 2010) [via]. I found no paper giving a figure for fingerprints | A little query time. Note the Gracenote patents in section 1 on thresholding by a local median |
| **Clean the query first** | A trained denoiser on the spectrogram before the peaks | Deezer 2023: peak precision 0.28 to 0.35, recall 0.24 to 0.30; identification alone moved by -4 to +7 points; **matching both the raw and the cleaned query and pooling gave +5 to +10** (audfprint, 10 s: 79.3 to 84.1; on 105,721 songs 64.6 to 74.0) [read] | A model of 31 million parameters, 0.75 s per 10 s of sound on a laptop [read]: not for the booth as it stands |
| **Fewer bits in the hash** | Quantise more coarsely so a small shift does not change the hash | Chandrasekhar 2011: a 20-bit hash did better than 32 bits on real phone recordings; "over quantization could affect performance adversely" [read] | More chance matches per lookup, so slower, and more need of the check |
| **Fuzzy lookup** | Also look up the neighbours of a hash | Haitsma and Kalker: flipping the least reliable bits took exact hits from 1 to 57 of 256 through a phone codec; trying all one-bit neighbours costs 33 times the lookups, trying the weak bits only costs far less [read]. Qfp's near-value search, radius 0.01 [read] | Lookups multiply; no size |
| **More hashes per anchor** | A larger fan-out, so that some hash of each anchor survives | Wang: with fan-out *F*, the chance that an anchor keeps at least one hash is about *p* times (1 - (1 - *p*)^*F*), close to *p* itself for *F* over 10 [read] | Storage in proportion: the opposite of what size wants, unless done on the query side only |
| **Two passes** | A fast strict pass; if it fails, a slower forgiving one | The trial's second pass: +3 to +10 points, 13 false names in 1,944 against 4 [W2]. Haitsma and Kalker's two settings [read] | Time on the hard queries only |
| **Evidence across time** | Add up votes over successive windows | Wang: 5, 10 and 15 s reach half-right at -3, -6 and -9 dB [read]. Chandrasekhar: peak pairs 46, 80, 87 percent at 5, 10, 15 s on real recordings [read]. The trial: 60 to 72 from 8 to 12 s at 0 dB [W2]. Now Playing scores the sequence because one embedding alone gives too many false matches [W] | A later answer on the hard songs only |
| **A second kind of evidence** | Confirm a candidate with something other than the hashes that proposed it | Qfp: after a candidate, count how many of the song's nearby peaks appear where they should in the query; accept above 0.53 [read]. On real DJ mixes that check took silence on unknown songs from 65 to 93 percent [W]. Haitsma and Kalker: one exact line proposes, 8,192 bits decide [read]. Chandrasekhar: requiring 5 aligned matches gave 100 percent precision for all three schemes [read] | The points or bits kept for checking: 16 KB a song in Qfp |

## 3. Using what Deckie already knows

### Checking a candidate

Every system above that reports few false matches has a checking stage, and each checks against something denser
than what proposed the candidate:

- **Qfp** keeps every song's peaks in a separate file and, for each candidate, lines them up with the query at the
  speed the candidate implies, within 1.8 s either side, in boxes 72 ms wide. It asks only that a share of the
  song's peaks be found in the query, not the reverse, so extra peaks from noise do no harm [read]. This is the
  trial's checking step, almost exactly.
- **Haitsma and Kalker** compare the whole 3-second block bit by bit [read]. **Ke et al.** fit a line through the
  matched lines and discard what is off it [via]. **Now Playing** rescores the whole sequence [W].
- **The crate file has two more things to check against.** Letter H lined the room's drum-hit pattern up against
  the song's own and read the tempo to 0.05 to 0.15 fader points from 8 s, and it held with a second song at equal
  level [H]. That pattern is a different kind of evidence from the peaks: it comes from the beat, which sits below
  300 Hz and in sharp onsets, where a crowd is weakest [inf]. It was never joined to a recogniser. W2 says the same:
  the check against the beat grid was not built.
- **Per-bar loudness and the style vector** are too coarse to name a song [W]. Their use is to refuse: a candidate
  whose loud bars fall where the room is quiet is unlikely.

### Narrowing by tempo

- I found no fingerprinting paper that prunes candidates with a known tempo [unverified: two searches]. Haitsma and
  Kalker considered tempo as a feature and rejected it because it "does not typically apply" to all music [read];
  that is an argument about a universal fingerprint, not about a DJ's crate where every song has a grid.
- What letter H measured sets the limits: listening blind, the room's tempo is found to a median of 0.35 to 0.8
  fader points in noise, and it is wrong by 3.6 to 4.7 points when two songs play [H]. So tempo can order the
  candidates and can decide which part of a split crate to open first. It must not rule a song out [inf].
- Its larger use is on the 69 candidate speeds. For a song whose tempo is known, the room's tempo says which two or
  three of the 69 are worth trying for that song [inf; W's idea 5.3, still untried].

### Following a song once it is named

- The literature treats finding and following as two jobs. Arzt, Widmer and colleagues' "music companion" (2012)
  runs a recogniser that keeps telling a tracker the likely piece and place, and a tracker that follows by on-line
  time warping, a method that lines live sound up with a stored version as it arrives [via search summary and
  abstract; papers not opened]. Concert-recording tools find a rough place by fingerprint and refine it by
  cross-correlation, sliding one signal against the other to find the best fit [via].
- ShazamKit's streaming session behaves this way, and letter H's "re-centring" was the same idea [H].
- **Why following is so much easier** [inf]. Naming asks "which of 5,000 songs, at which of thousands of places, at
  which of 69 speeds?": hundreds of millions of guesses, so the bar for accepting one has to be high. Following asks
  one question: "is this song still here, a second further on, at the speed I measured?" With one guess on the
  table, a handful of matching points is strong evidence. So a song that took 8 clean seconds to name can be held
  through a breakdown, a shout or a loud chorus on evidence that would never name it from cold.
- For the booth this means three states, not one: *searching* (everything, all speeds), *following* (one song, two
  or three speeds, each second), and *listening for the next* (the picks and songs within tempo reach first, then
  everything). W2 names this tracking mode as not built.

## 4. Front ends for a noisy room

A **front end** is whatever is done to the microphone's sound before the fingerprint is made.

| Step | What it does | Evidence | Cost, and my reading |
|---|---|---|---|
| **The band** | Which pitches the fingerprint reads | Haitsma and Kalker 300 to 2000 Hz; Neural Audio Fingerprint 300 to 4000; Shazam 250 to 5500 in four bands; Qfp 16 or 8 kHz sampling (its paper says both) [all read]. W2: cutting everything above 2 kHz cost nothing on clean sound | Reading higher (to 5.5 kHz) puts points where a crowd is weak and cymbals are strong [inf]; it needs 16 kHz sound and a new print. Worth measuring before building |
| **The phone's own processing** | Automatic gain, noise suppression, echo cancelling | Apple: measurement mode is for apps "that need to minimize the amount of system-supplied signal processing", and it records from the primary microphone [read]. Chandrasekhar lists "quality-enhancement algorithms that might be built into the mobile device" among the hazards [read] | **The booth already asks for it**: `Recognizer.swift` sets the record category with measurement mode. Nothing to change; worth confirming on the iPad that the level does not pump |
| **Overload** | Whether the microphone itself clips | Club sets averaged 98 to 108 dB(A) at the DJ in one dosimeter study; phone microphones are specified to overload at 120 to 130 dB [via; vendor]. Deezer's simulation clips up to 1 percent of samples and shifts gain by 5 dB [read] | Probably inside the microphone's range, with little to spare beside a monitor [inf]. The Oct 24 recording can answer it: count the samples at full scale |
| **Speaker distortion** | Overdriven monitors add overtones | No public data set of it found; Deezer names "non-linear distortions" as work they have not done [read]. The trial lost about 25 points under UnmixDB's distortion effect [W2] | Peaks at exact multiples of a stronger peak's pitch could be dropped on the query side [inf]; untested anywhere I found |
| **Per-channel energy normalisation (PCEN)** | Divides each pitch band by its own recent average, so steady background flattens and changes stand out | Made by Google for far-field voice commands (Wang et al. 2017); Lostanlen et al. 2019 show it turns many real backgrounds into something close to even noise [via abstracts] | Cheap. It would also flatten a held note, so it suits onsets better than tones [inf]. Try as a second view of the query, not a replacement |
| **Spectral subtraction** | Estimate the noise floor in each band and subtract it | Standard in speech work; I found no fingerprinting result for it, and Deezer's learned version barely helped alone [read] | A crowd is not steady enough, and peak picking already ignores a flat floor [inf]. Low priority |
| **Median filtering** | Keep what is steady in time (tones) and what is sharp in time (drum hits); drop the rest | FitzGerald 2010 for separation; Gracenote for thresholding [via] | Cheap. No published figure for fingerprints. Mind the Gracenote patents |
| **Two views, pooled** | Fingerprint the query two ways and add the votes | Deezer: +5 to +10 points from pooling raw and cleaned queries, where cleaning alone gave nothing [read] | Twice the query work. The pooling is the finding, more than the cleaner |
| **Several microphones** | Combine microphones to favour the monitor's direction | iPadOS presents "the individual device microphones, and beamformers that use multiple microphones" as data sources, one chosen at a time, with a choice of pattern including stereo [read]. I found nothing that gives an app several raw microphones at once [unverified]. Measurement mode uses the primary one [read] | Whether a pattern that favours one side can be combined with measurement mode on an iPad is untested [unverified]. A cheap experiment on the device; no literature |

## 5. Size

### What the published systems do

- **Fewer hashes per second on the song side.** The trial keeps 192. audfprint keeps 20 by default and says 7 works
  well for references [read]. Qfp keeps 9 [read]. Wang's example is ten per point, with fewer for clean sources
  [read]. The systems that keep few all lean on a check, or on long queries.
- **Small records.** audfprint stores 4 bytes an entry and no hash at all: the hash is where the entry sits [read].
  Wang stores 8 [read]. Qfp stores 36 and says 24 would do [read]. The trial is at 5 bytes a hash already [W2], so
  its size is in the count, not the record.
- **Drop, do not grow.** audfprint's buckets hold 100 entries; beyond that entries are dropped at random, and
  matching still works "because it needs only a minimum number of matches" [read].
- **Keep the check's data out of the index.** Qfp's peaks for checking are a flat file read by position, 16 KB a
  song; an earlier design with search trees over the peaks took 13 GB more [read].
- **Embeddings are the smallest.** Under 3 KB a song for Now Playing, by squeezing each vector about 32 times with
  quantisation chosen from the data [read]; product quantisation in Chang et al. lost under 0.1 percent [read].

### Compact tables

- **A sorted array with a small directory** is what Wang and audfprint amount to. It can be written once to a file
  and read in place.
- **Minimal perfect hashing** gives every key its own slot with 2 to 3 bits a key of overhead, against a floor
  of 1.44 [via, PTHash 2021]. Useful if the table is rebuilt rarely, which a crate's is.
- **A filter in front** (Bloom's kind) answers "this hash is in no song" from about 10 bits an entry at a 1 percent
  error [standard result, not opened today]. In noise most query hashes match nothing, so a filter held in memory
  would spare most reads of a table left on storage [inf].
- **Reading in place.** Apple, WWDC 2018: a read-only file mapped into memory is "clean" memory that the system can
  drop and re-read; an app's limit counts its "dirty and compressed" memory, and "clean memory doesn't really
  count" [read]. So an index written once into the booth's local `catalog/` folder and mapped read-only is not
  charged to the app the way the trial's in-memory index is. W2 already pointed at this. What is untested is how
  an iPad behaves when lookups jump all over a mapped file of several hundred MB [unverified].

### What an index for 2,000 to 10,000 songs could come down to [inf throughout]

The trial's 0.3 MB a song is 192 hashes a second at 5 bytes, a 6-byte copy of every point, and the table [W2].

| Step | Hashes per second of music | Held for matching, per four-minute song | 2,000 songs | 5,000 | 10,000 |
|---|---|---|---|---|---|
| Today | 192 | about 300 KB, in the app's own memory | 0.6 GB | 1.5 GB | 3 GB |
| Points read from the crate file's own prints, mapped; no copy | 192 | about 230 KB index, plus 23 KB mapped | 0.5 GB | 1.3 GB | 2.5 GB |
| Half the points (the two stronger levels), three hashes each | 48 | about 58 KB, plus 23 KB mapped | 160 MB | 400 MB | 0.8 GB |
| A quarter of the points, three hashes each (audfprint's default density) | 24 | about 29 KB, plus 23 KB mapped | 105 MB | 260 MB | 0.5 GB |
| Qfp's density | 9 | about 11 KB, plus 23 KB mapped | 70 MB | 170 MB | 340 MB |

- All of the lower rows can sit in mapped files, so the app's own charged memory would be small at any of them.
- The 23 KB of points a song stays whatever the index does: it is what the check reads, and it is the crate file's
  own print.
- **What it costs in accuracy is not in the literature for this design and has to be measured.** The direction is
  known: Wang set density higher for phones than for radio, and Qfp at 9 a second is good only down to +15 dB. A
  thin index names fewer songs by itself. It can still *propose* the right song among its top few dozen, which is
  all a first pass has to do when a check decides. So thinning and the wider check (option 2 below) belong together.
- **Splitting a crate**, the owner's second step, falls out of the same layout: if the songs in the file are ordered
  by tempo, "the part of the crate within reach of the room's tempo" is one stretch of the file.

## 6. Evaluating honestly for a noisy venue

### What the published tests do

- **Mix recorded noise into clean clips at a stated level.** Wang used noise "recorded in a noisy pub", 250 clips
  from the middle of each song, 10,000 songs, levels from -15 to +15 dB in steps of 3, three lengths [read]. Chang
  et al. drew levels from 0 to 10 dB and added rooms and microphones [read]. Deezer drew from -10 to +10 dB [read].
- **Report the misses and the false names apart.** Sonnleitner and Widmer give accuracy, precision and, on 18,229
  and 50,000 songs that are not in the catalogue, how often the system rightly stays silent (0.96 and 0.97) [read].
- **Real recordings, where anyone has them.** Chandrasekhar et al.: a phone, 39 songs from a TV and laptop speakers
  "in noisy environments", over 1,000 clips; they wrote that they could find no public set of phone recordings
  [read]. Araz et al.: 3,692 venue recordings with BMAT, not released [read]. Nikou and Giannakopoulos: music played
  on one device and noise on another, re-recorded at three noise levels [via].
- **The gap between simulated and real is 10 to 25 points** for trained models [read, Araz 2025]. Nobody has
  published it for landmarks.

### Kinds of noise are not alike

- **Pink noise** has equal power in every octave and no structure. It buries peaks evenly and makes none of its own
  that last. It is the kindest loud noise.
- **Crowd babble** is many voices. Its power sits in the fingerprint's band, and with few talkers it has steady
  harmonics that make peaks. A recording of a cafeteria (the trial's DEMAND set) is many distant talkers; a booth
  has a few near ones shouting over music, which shifts their power upward [inf].
- **Music from the next room, or the other deck**, is the hardest: it is made of exactly the kind of peaks the
  fingerprint looks for. The trial's blend rows are this case at full band. A next-room version would be a second
  song with its top end removed, 5 to 15 dB down; nobody publishes that condition [inf].
- **State the level inside the band.** As section 2 found, the same "0 dB" means different things for full-range
  and band-limited music.

### Public material, with licences

| Set | What it is | Licence | Note |
|---|---|---|---|
| DEMAND | Cafeteria, restaurant, station and other scenes, 16 microphones | CC BY 4.0 [W2] | In use |
| OpenSLR 28 | 417 measured rooms and more | Apache 2.0 [W2] | In use |
| MUSAN (OpenSLR 17) | Music, speech and noise, 11 GB | CC BY 4.0 [read] | Babble with a chosen number of talkers can be made from its speech |
| BUT ReverbDB | Nine rooms, 31 microphones each, with each room's own background noise | CC BY 4.0 [read] | Rooms and matching noise together |
| WHAM! noise | About 80 hours in restaurants, cafes and bars | CC BY-NC 4.0 by one catalogue's listing; the project's page did not open [via] | Deezer rejected it because many clips have music in the background [read]: which is a booth's real condition, but with no record of what is playing |
| TUT and TAU acoustic scenes | Streets, stations, malls, transport; 64 hours in the 2020 set | "Other (Non-Commercial)" [read] | Used by Deezer and by Araz et al. |
| MIT impulse response survey | 271 measured rooms | Licence not found; a mirror lists it as unknown [via] | Used by Deezer and Araz et al. |
| Microphone responses | Xaudia's set, used by Chang et al.; Franco et al.'s 25 microphones, used by Araz et al. | Not checked | |
| Loudspeaker roll-offs | 431 speakers' low cut-offs from the Spinorama site, used by Deezer | Not checked | Only the bass roll-off; no distortion |
| UnmixDB | Generated DJ mixes with a distortion effect | CC BY-NC-ND 4.0 [W2] | In use |
| Real venue recordings with ground truth | None public that I found | | The Oct 24 recording is the only one in reach |

### What an honest protocol for the booth needs [inf, from the above]

1. The Oct 24 recording as the test that decides (D35), never tuned on.
2. Simulated conditions reported with the level inside the fingerprint's band beside the overall level.
3. Babble built with a stated number of talkers (2, 4, 8, many), beside the cafeteria recordings.
4. A next-room condition and an overdriven-speaker condition, since neither exists in public sets.
5. Songs that are not in the crate at every step, with and without noise; and noise alone.
6. Every figure by condition and by kind of music, on the half no choice was made on, as W2 did.
7. Time to the name counted from when the song starts, with the booth listening continuously: the published tests
   all ask one isolated clip, which is not what a booth does.

## Options for the owner and the trial

### Changes to try on the fingerprint we have, in order

Expected gains are my inference from the evidence named, at crowd noise as loud as the music in a measured room,
where the trial names 60 percent from 8 s. None is a promise. Items 1 to 5 leave the crate file as it is.

**1. Gather evidence across seconds.** Keep the votes for (song, place, speed) from each second's listen and add
them; accept when several listens agree, even if none passes the bar alone.
- *Evidence.* Wang: each doubling of length is worth about 3 dB. The trial: 60 to 72 percent from 8 to 12 s.
  Chandrasekhar: 46 to 80 percent from 5 to 10 s on real recordings. Now Playing's sequence score.
- *Expected gain.* 10 to 15 points by 16 s on the songs missed at 8 s; nothing lost on the easy ones, which are
  still named at once.
- *Cost.* No size. Little time. The hard songs are named later, not never.
- *How to measure.* The bench already cuts 12 s clips; cut 20 s ones, run the listener second by second, and report
  "named by" 8, 12, 16 and 20 s, with false names on songs not in the crate re-measured, since agreement across
  listens changes the bar.

**2. Propose widely, decide by the check.** Lower the first pass's bar and send the top 30 to 50 songs to the
checking step, together with the song being followed, the booth's picks and songs within reach of the room's tempo.
Inside that short list, match with pairs.
- *Evidence.* The trial's own two-point column: about 20 points better at this noise, at a cost that came from
  looking pairs up across the whole catalogue. Qfp, Haitsma and Kalker, Now Playing and Chandrasekhar's test all
  propose cheaply and decide carefully. On real DJ mixes the check was what separated the system that worked [W].
- *Expected gain.* Up to the two-point column: toward 80 percent at 8 s, if the right song is usually in the list.
- *Cost.* No size (pairs for 50 songs are made from their stored points). Time on hard queries; easy ones exit early.
- *How to measure.* First the one number that says whether it can work: on the development clips, how often is the
  right song in the first pass's top 10, 30, 50 and 100? Then the full run, right and wrong, with the time at the
  95th percentile.

**3. Follow a song once it is named.** Each second, test the one song at the predicted place and two or three speeds.
- *Evidence.* The recogniser-and-tracker design of Arzt and others; ShazamKit's streaming behaviour [H]; the
  reasoning in section 3 that one guess needs far less proof than millions.
- *Expected gain.* Not in first naming. It holds a name through passages that could not win it, reads the fader
  more finely, and frees the time that items 1 and 2 spend.
- *Cost.* None in size; it lowers the booth's steady work to a few percent [W2's estimate].
- *How to measure.* On generated mixes and the Oct 24 recording: share of each song's seconds with the right name
  held; seconds to notice a change of song; false holds after the song has gone.

**4. Make the index thin, and read it in place.** Index only the stronger points on the song side (the print
already stores a strength level), three hashes each; keep the microphone side dense; write the index once into the
local catalogue folder and map it read-only; read points for the check from the crate file's prints.
- *Evidence.* audfprint (20 a second, or 7), Qfp (9 a second with 1,500 on the query), Wang's remark on density;
  Apple on mapped files.
- *Expected gain in noise.* None; by itself a loss. With item 2 in place the loss should be small, because the index
  then only has to propose.
- *Cost and saving.* From about 0.3 MB a song in memory to 50 to 80 KB a song in mapped files, its points
  included: 2,000 songs in 100 to 160 MB, 10,000 in 0.5 to 0.8 GB (the table in section 5).
- *How to measure.* Sweep 192, 96, 48, 24 and 12 hashes a second on the development half with items 1 and 2 on;
  plot right-at-8-s and top-50 recall in the noisy conditions against size. Then, on the iPad, the app's charged
  memory and the time of a lookup with a mapped index at 2,000 and 5,000 songs.

**5. Forgive a point that moved one step.** For each hash, also look up the value with the least certain part moved
to the next step (the time or pitch difference nearest to a boundary).
- *Evidence.* Haitsma and Kalker's weak-bit search; Sonnleitner and Widmer on peaks migrating to the next bin;
  Chandrasekhar's finding that fewer bits did better on real recordings.
- *Expected gain.* Unknown, and cheap to bound first.
- *Cost.* Two to four times the lookups; no size.
- *How to measure.* First count, on noisy development clips, what share of the true song's hashes are lost only
  because one part crossed a boundary. If it is a few percent, stop there.

**6. Choose the points better. This changes the print, so do it once, after the first five.** Four parts, each to
be measured before it is built in:
- *(a) Measure the level by band.* On the benchmark's own noise and music: how far the music stands above the crowd
  in 300 to 3600 Hz, in 3.6 to 5.5 kHz and above. A day's work with no change to the fingerprint, and it says
  whether (c) is worth anything.
- *(b) Spread each anchor's targets across pitch bands*, not only time slices, so one loud voice cannot take all of
  an anchor's hashes. Evidence: Shazam's four bands, Wang's density rule. No size.
- *(c) Read up to about 5.5 kHz.* Evidence: Shazam's band; the shape of speech. Cost: 16 kHz sound, about a third
  more points (a larger print and index), every song fingerprinted again.
- *(d) Prefer points that last or that sit on an onset; drop gliding ones on the microphone side.* Evidence:
  Gracenote's report on voice-like lines; no figure. Check the Gracenote patents before building anything that
  thresholds by a local median.
- *How to measure.* Each against the development half's noisy conditions, and against babble made with 2, 4 and 8
  talkers, where (b) and (d) should show most.

**7. A second kind of evidence in the check: the beat.** Confirm a candidate against the song's stored drum-hit
pattern at the place and speed found (letter H's option C; W2's unbuilt point 4).
- *Evidence.* Letter H: 0.05 to 0.15 fader points from 8 s, holding under an equal-level second song.
- *Expected gain.* Fewer false names, which lets the bars in items 1 and 2 come down; a finer fader reading.
- *Cost.* About 20 KB a song in the crate file [H's estimate], or nothing if made from the beat grid and per-bar
  data already there, which is untested.

**8. Two views of the microphone, pooled.** Fingerprint the query plain and after a simple normalisation (PCEN, or
a median filter) and add the votes.
- *Evidence.* Deezer's +5 to +10 from pooling; theirs used a large trained cleaner, so a simple filter will give
  less. Last because its gain is the least certain.

### Alternatives that would replace the fingerprint

| Alternative | For | Against |
|---|---|---|
| **A dense bit fingerprint** (Haitsma and Kalker's energy differences, on a logarithmic pitch axis) | Degrades gradually in noise; indifferent to compression and equalising; the method's patent is listed expired; simple | Breaks at 2.5 percent of speed, so the query would be re-made at every candidate speed; 78 KB a song at the published rate; noise figures in the open are thin; a new build with no fader reading of its own |
| **A picture fingerprint** (Waveprint's kind) | The best published result on real phone recordings at 5 s | Six times the data; breaks at 2 percent of speed; one continuation patent's status not found |
| **Peaks with a patch described round each** (MASK's kind) | One surviving peak is enough, where the trial needs three | Paper not opened; Telefonica applications of unknown status; no public code |
| **A trained embedding of our own** | The best noise figures anywhere, and the smallest index | Months; training music to choose and disclose (D15); loses 10 to 25 points from simulated to real unless trained on real rooms; no fader reading, no "none of these"; the trained scheme in the one independent comparison did worst when its training did not match the test |
| **Quads** | Any speed | Worse in noise than what we have [W2; Qfp's own +15 dB] |

### My recommendation

Stay with the landmark fingerprint and change the matcher round it: items 1, 2 and 3 first, as one piece of work,
because they need no change to the crate file, they are where the published systems get their noise results, and the
trial's own two-point column says the points already hold about 20 more points of accuracy than the fast matcher
takes. Then item 4, which is the size answer and depends on item 2. Then run the room test and the Oct 24 recording.
Items 5 and 6(a) are measurements of a day or two each and can run beside the first three; item 6's changes to the
print wait for those numbers, so that songs are fingerprinted again once, not twice.

Do not replace the fingerprint now. The one alternative I would keep in view is a dense bit fingerprint used only
*inside the check*, on the short list, as a second kind of evidence; it needs no index and no speed tolerance there,
because the check already knows the song, the place and the speed [inf].

The challenge to my own recommendation: every figure for items 1 to 3 is from simulated noise, and the published
gap to real rooms is 10 to 25 points. If the Oct 24 recording shows the booth's trouble is the monitor's distortion
or the other deck, not the crowd, then item 6 and item 7 move ahead of items 1 and 2.

## What I could not open or verify

- **The Waveprint papers, Ke et al. 2005, MASK, Coover and Han 2014, Rafii et al. 2014, Gracenote's harmonic noise
  reduction, the MPEG-7 and AudioID papers, Byrne et al. 1994, FitzGerald 2010, the PCEN papers, Arzt et al. 2012.**
  Described from papers that summarise them, abstracts or search summaries, as tagged. Ellis's page on audfprint's
  peak picking returned an error; audfprint's README was read.
- **How Shazam's method changed after 2003.** Only the SongRec README (not its code) and the patent titles. No talk
  or paper from Apple found.
- **Patent status** of Waveprint's continuation, the Telefonica applications and the Gracenote family; whether PCEN
  or Now Playing are patented. Listings and search summaries only; no register consulted.
- **Qfp's and Wang's noise figures** are read off plots. Qfp's is white noise with 15 s queries.
- **Any published use of a known tempo or beat grid to prune fingerprint candidates.** None found in two searches.
- **Any published figure for landmark fingerprints on real club or bar recordings through a microphone.** None
  found. Araz et al.'s venue recordings are for trained models and are not public.
- **Any measurement of speaker distortion's effect on fingerprints, or a public data set of it.** None found.
- **iPad behaviour**: charged memory and lookup time with a large mapped index; whether a directional microphone
  pattern works with measurement mode; whether the microphone clips beside a monitor. Apple's statements were read;
  nothing was run.
- **Licences** of the WHAM! noise (one catalogue's listing), the MIT impulse responses (not found), the microphone
  and loudspeaker sets (not checked), Deezer's augmentation code (not stated in the paper).
- **The size table in section 5 and every "expected gain"** are my arithmetic and inference, not measurements.
- **Bloom filter and minimal perfect hashing figures** are standard results or from a search summary of the PTHash
  paper, not opened today.

## Sources

Classic fingerprints: Haitsma and Kalker 2002 https://ismir2002.ismir.net/proceedings/02-FP04-2.pdf ; Wang 2003
https://www.ee.columbia.edu/~dpwe/papers/Wang03-shazam.pdf ; Chandrasekhar, Sharifi and Ross 2011
https://archives.ismir.net/ismir2011/paper/000005.pdf ; Chromaprint's author on how it works
https://oxygene.sk/2011/01/how-does-chromaprint-work/ ; Waveprint (not opened)
https://research.google/pubs/known-audio-detection-using-waveprint-spectrogram-fingerprinting-by-wavelet-hashing/ ;
Ke, Hoiem and Sukthankar 2005 (not opened) https://www.cs.cmu.edu/~yke/musicretrieval/cvpr2005-mr.pdf ; Coover and
Han 2014 (abstract) https://archive.cps-vo.org/node/19680 ; Rafii, Coover and Han 2014 (not opened)
https://users.cs.northwestern.edu/~zra446/doc/Rafii%20-%20An%20Audio%20Fingerprinting%20System%20for%20Live%20Version%20Identification%20using%20Image%20Processing%20Techniques%20-%20MMIRG%202014.pdf ;
MASK (not opened) https://typeset.io/pdf/mask-robust-local-features-for-audio-fingerprinting-4pbxhgfbsl.pdf ;
Gracenote's harmonic noise reduction (did not open)
https://sigport.org/sites/all/modules/pubdlcnt/pubdlcnt.php?fid=3374 .

Landmark variants and code: Sonnleitner and Widmer 2016 (Qfp)
https://www.cp.jku.at/research/papers/preprint_TASLP2509248.pdf ; audfprint https://github.com/dpwe/audfprint ;
Ellis's page (error) https://www.ee.columbia.edu/~dpwe/resources/matlab/fingerprint/ ; Olaf
https://github.com/JorenSix/Olaf ; SongRec README https://github.com/marin-m/SongRec .

Trained fingerprints: Now Playing https://arxiv.org/abs/1711.10958 (read as
https://ar5iv.labs.arxiv.org/html/1711.10958) ; Chang et al. 2021 https://arxiv.org/abs/2010.11910 ; Araz et al. 2025
https://arxiv.org/abs/2506.22661 and https://github.com/raraz15/neural-music-fp ; PeakNetFP
https://arxiv.org/abs/2506.21086 ; Nikou and Giannakopoulos 2025 https://arxiv.org/abs/2507.06070 ; variable-length
fingerprint, March 2026 (not read) https://arxiv.org/pdf/2603.23947 ; pretrained Conformers (not read)
https://arxiv.org/html/2508.11609v2 .

Noise and peaks: Akesbi et al. (Deezer) 2023 https://arxiv.org/abs/2310.13388 ; Akesbi's 2022 thesis on Deezer's
own fingerprint https://arxiv.org/abs/2212.11277 ; FitzGerald 2010 (not opened)
https://www.audiolabs-erlangen.com/resources/aps-w23/papers/2010_FitzGerald_HarmonicPercussiveSep_DAFx.pdf ; PCEN:
Wang et al. 2017 https://research.google/pubs/trainable-frontend-for-robust-and-far-field-keyword-spotting/ and
Lostanlen et al. 2019 https://researchwith.njit.edu/en/publications/per-channel-energy-normalization-why-and-how/ ;
Byrne et al. 1994 (not opened)
https://researchers.mq.edu.au/en/publications/an-international-comparison-of-long-term-average-speech-spectra/ .

Following and checking: Arzt et al. 2012 (not opened) https://www.cp.jku.at/research/papers/Arzt_etal_Ecai_2012.pdf ;
Arzt and Widmer 2010 (not opened) https://www.cp.jku.at/research/papers/Arzt_Widmer_STAIRS_2010.pdf ; Subramanian
and Lerch (not opened)
https://musicinformatics.gatech.edu/wp-content_nondefault/uploads/2018/06/Subramanian-and-Lerch-Concert-Stitch-Organization-and-Synchromization-o.pdf .

Apple: measurement mode
https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/measurement ; stereo capture and
data sources https://developer.apple.com/documentation/avfaudio/capturing-stereo-audio-from-built-in-microphones ;
WWDC 2018 session 416, iOS Memory Deep Dive https://developer.apple.com/videos/play/wwdc2018/416/ .

Levels and microphones: nightclub and DJ sound levels (search summaries of) https://stacks.cdc.gov/view/cdc/248546
and https://canadianaudiologist.ca/?p=1982 ; microphone overload points [vendor]
https://st.com/content/st_com/en/about/media-center/press-item.html/n3576d.html and
https://infineon.com/cms/en/product/sensor/mems-microphones/mems-microphones-for-consumer/im69d120 .

Patents (listings): Waveprint US 8,411,977 https://patents.google.com/patent/US8411977 ; Telefonica
https://data.epo.org/publication-server/rest/v1.2/patents/EP2751804NWA1/document.html and
https://uspto.report/patent/app/20140310006 ; Gracenote family, for example
https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10713296 ; Wang's patents by inventor
https://patents.justia.com/inventor/avery-li-chun-wang .

Compact tables: PTHash https://arxiv.org/abs/2104.10402 (search summary).

Data sets: MUSAN https://www.openslr.org/17/ ; BUT ReverbDB
https://speech.fit.vut.cz/software/but-speech-fit-reverb-database ; TAU Urban Acoustic Scenes 2020 Mobile
https://zenodo.org/records/3819968 ; WHAM! http://wham.whisper.ai/ (did not open) and
https://audeering.github.io/datasets/datasets/wham.html ; MIT impulse responses (a mirror)
https://huggingface.co/datasets/davidscripka/MIT_environmental_impulse_responses ; OpenSLR 28
https://openslr.org/28 .

In the repo: `docs/research/w2-own-recognition-trial.md`, `w-own-recognition.md`,
`h-pitch-robust-recognition.md`; `docs/product/00-decisions.md` (D5, D15, D35);
`core/Tools/recognition-bench/make_queries.py` (how the benchmark sets the noise level);
`deck-app/Deck/Sources/Recognizer.swift` (the audio session's mode).
