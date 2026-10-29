# Research R: key parity for the shippable engine

Dated Oct 29, 2026. Measurement and evidence, no decisions. Builds on stage 1 sections 1a, 1c, 1e and 2a, L (key
section) and M section 3.1 (the key estimator is "own" code). Script `mixer/key_parity.py`; every row below, plus
per-bucket figures and confusion columns, is in `mixer/key_parity_results.tsv`. Tags: [unmeasured] = not measured
here; [2nd] = from a web source I read but did not test; [inf] = my inference. Not legal advice.

## In plain words

A song's key is the home note and scale its melody and chords settle on, for example A minor. DJs use it to pick two
songs that sound right together, so a wrong key means a bad recommendation. A computer finds the key by measuring how
much of each of the twelve notes the song contains, then comparing that pattern with a template for each of the 24
keys; the best match wins. The errors are near misses, not random. A major key and its "relative" minor share all seven
notes (C major and A minor), and a key shares six of seven notes with the key a fifth away, so even trained listeners
disagree on these. Bass, drums, loud overtones and long intros without harmony blur the note counts, and some songs
change key or use a scale that is neither plain major nor minor.

## Summary

- **Baseline reproduced.** The bench file gives 74.6 percent exact, 14.5 neighbour and 10.9 other on the lab's 311
  confident tracks; the script's row 0 matches the engine's key on all 373 tracks.
- **Recommended (row 3f):** an HPCP pitch-class profile from spectral peaks, peaks whitened against a running-max
  envelope, four harmonics, and the mean Pearson correlation over Faraldo's three published EDM profiles (edma,
  bgate, braw). Against the lab: **83.3 exact, 10.3 neighbour, 6.4 other** (charter 75 passed; equal to Apple's own
  83.3 against the lab). Against Apple: **70.4 exact** where the shipped estimator has 63.4. Dev and held-out both
  read 83 against the lab; the gain shows in every bucket. Cost 0.2 to 0.4 s per track in Python after decoding.
- **Whitening is the step that matters** (each peak scaled against the strongest peak near it), then the harmonics,
  then the profile average. Tuning estimation, bass emphasis, polyphonic profiles, mid-track windows and window votes
  did not help.
- **Caution.** Two of the lab's three votes are Essentia's own whitened HPCP with these profiles, so part of the gain
  against the lab is "agreeing with Essentia". Apple is the independent check: +7 points there, but still 2 below
  Essentia (72.3) and 12 below madmom's network (82.0). What remains is mostly major/minor (below).

## Results (lab = its 311 confident tracks; Apple = the 372 tracks with an Apple key)

Neighbour follows the bench (`bench_mu.key_relation`): relative key, or one wheel step in the same mode. Parallel
(same tonic, other mode) counts as other here and is broken out under confusions.

| Method | Lab exact | nbr | other | Apple exact | nbr | other | Lab dev / held-out |
|---|---|---|---|---|---|---|---|
| ref: Essentia KeyExtractor edma (lab vote 1; AGPL) | 94.9 | 5.1 | 0.0 | 72.3 | 15.1 | 12.6 | 96.1 / 93.1 |
| ref: Essentia KeyExtractor bgate (lab vote 2; AGPL) | 97.1 | 2.9 | 0.0 | 71.2 | 16.7 | 12.1 | 96.7 / 97.7 |
| ref: madmom CNN (lab vote 3; non-commercial weights) | 86.8 | 13.2 | 0.0 | 82.0 | 12.1 | 5.9 | 87.8 / 85.5 |
| ref: Apple Music Understanding | 83.3 | 13.2 | 3.5 | 100 | 0 | 0 | 84.4 / 81.7 |
| **0 shipped: STFT chroma, edma** | **74.6** | 14.5 | 10.9 | **63.4** | 19.6 | 16.9 | 75.6 / 73.3 |
| 1a own semitone chroma, edma | 66.6 | 16.1 | 17.4 | 57.5 | 19.9 | 22.6 | 67.8 / 64.9 |
| 1b 1a + tuning estimate | 66.9 | 17.4 | 15.8 | 57.5 | 20.7 | 21.8 | 69.4 / 63.4 |
| 1c 1b + log compression | 71.1 | 17.4 | 11.6 | 61.6 | 20.2 | 18.3 | 73.3 / 67.9 |
| 1d bass only (E1 to D#3) / 1e no bass (C3 up) | 40.5 / 65.9 | | | 36.0 / 57.8 | | | |
| 2a HPCP, 1 harmonic, not whitened, edma | 77.2 | 14.5 | 8.4 | 63.2 | 17.2 | 19.6 | 80.6 / 72.5 |
| 2b HPCP, 4 harmonics, not whitened, edma | 75.2 | 14.1 | 10.6 | 61.0 | 18.0 | 21.0 | 78.3 / 71.0 |
| 2d HPCP, 4 harmonics, whitened ±1/3 octave, edma | 78.5 | 14.5 | 7.1 | 66.7 | 16.1 | 17.2 | 77.8 / 79.4 |
| 2c / 2e envelope ±1/6 / ±1/2 octave | 78.8 / 77.8 | | | 68.3 / 65.3 | | | |
| 2g 2d + tuning estimate | 76.2 | 14.5 | 9.3 | 65.3 | 15.9 | 18.8 | 75.6 / 77.1 |
| 2j 2d with Gómez's polyphonic edma profile | 53.4 | 29.9 | 16.7 | 43.3 | 35.2 | 21.5 | 53.3 / 53.4 |
| 3a / 3b / 3c / 3d / 3e 2d with bgate / braw / krumhansl / shaath / temperley | 81.0 / 83.3 / 69.5 / 78.5 / 52.7 | | | 67.2 / 71.2 / 56.7 / 64.5 / 41.7 | | | |
| **3f 2d, mean r over edma, bgate, braw (recommended)** | **83.3** | 10.3 | 6.4 | **70.4** | 14.8 | 14.8 | **83.3 / 83.2** |
| 3g 2d, majority of the three | 82.0 | 10.9 | 7.1 | 69.1 | 15.3 | 15.6 | 82.2 / 81.7 |
| 3h 2d, mean over all six profiles | 79.1 | 11.9 | 9.0 | 64.0 | 16.7 | 19.4 | 79.4 / 78.6 |
| 3i the 3f average on the shipped STFT chroma | 75.6 | 16.4 | 8.0 | 64.5 | 22.6 | 12.9 | 77.2 / 73.3 |
| 3j 3f with 8 harmonics | 83.9 | 10.3 | 5.8 | 71.2 | 15.6 | 13.2 | 82.8 / 85.5 |
| 3k / 3l 3f, peaks below 100 / 200 Hz ignored | 80.1 / 71.7 | | | 68.0 / 61.6 | | | 80.0 / 73.3 dev |
| 3m 3f, 1-semitone cosine window (Essentia's default) | 84.6 | 9.3 | 6.1 | 71.0 | 14.2 | 14.8 | 83.9 / 85.5 |
| 4a 3f, frames weighted by loudness (RMS) | 84.2 | 10.0 | 5.8 | 70.7 | 14.5 | 14.8 | 84.4 / 84.0 |
| 4c 3f, middle 60 percent of the track only | 81.7 | 11.3 | 7.1 | 67.7 | 15.6 | 16.7 | 81.7 / 81.7 |
| 4d 3f, majority over 30 s windows, hop 15 s | 82.6 | 10.9 | 6.4 | 69.1 | 16.4 | 14.5 | 83.3 / 81.7 |

**What each change bought** (lab exact points, Apple in brackets):

- Peaks (HPCP) in place of the full-spectrum chroma: +2.6 (-0.2).
- Whitening on 4-harmonic HPCP: +3.3 (+5.7). In a black-box test of Essentia's KeyExtractor on 48 tracks,
  switching whitening off changed 17 keys; the envelope width barely matters (rows 2c, 2d, 2e).
- The three Faraldo profiles averaged instead of edma alone: +4.8 (+3.7). The average only helps on whitened HPCP
  (+1.0 on the shipped chroma, row 3i). braw alone does as well; the average is kept because it is even across
  buckets and its agreement count supplies the confidence.
- No gain: tuning estimation, -2.3 on HPCP and +0.3 on semitone chroma (median detune here is 3.5 cents, 7.8 percent
  of tracks beyond 25 cents; Sha'ath found tuning correction did not help dance music either [2nd]); bass emphasis
  (bass alone 40.5; a 200 Hz high-pass, as in Faraldo's 2017 pipeline [2nd], drops 3f to 71.7); Gómez's polyphonic
  profiles (-25, because the harmonics are then counted twice, once in the HPCP and once in the profile); loudness
  weighting (+0.9, three tracks, noise); the middle of the track (-1.6); window majority (-0.7); all six profiles
  (-4.2; Krumhansl and Temperley are classical-music profiles).

## Library-blind checks

Every value comes from the literature or first principles. The few choices between measured variants were made on
the dev split, the lab's 90s and 2000s eras (180 confident tracks). The held-out split is pre-90s, 2010s and 2020s
(131 tracks), so it differs in production, not at random. Gain of 3f over the shipped estimator by bucket (lab /
Apple exact points): 2000s +6.9 / +4.4; 2010s +8.5 / +7.9; 2020s +7.4 / +3.7; 90s +8.4 / +7.7; pre-90s (27 tracks)
+18.5 / +19.3; dance +9.6 / +6.2; pop +9.2 / +9.2; other (library, ambient, rips; 38 tracks) +2.7 / +6.5; under
110 BPM +8.5 / +14.2; 110-129 +10.4 / +5.1; 130 plus +5.4 / +2.2. **Flags:** the gain is not concentrated in one
bucket. It is smallest for "other" against the lab and for 130-plus and the 2020s against Apple. The 2020s are
weakest in absolute terms (76 lab, 60 Apple). Two variants beat 3f overall by a point but were not chosen: 3m wins
dev by one track and 3j loses dev by one, so both are noise. No era split can remove the crate's one-DJ house-and-pop
bias; the real test is an outside dataset (below) [unmeasured].

## Confusions that remain, and why

**Against the lab** (shares of 311 tracks), the shipped estimator's misses are fifths 10.3, parallel 6.1, relative
4.2, unrelated keys 4.5 and mode flips 7.4 each way. 3f's are fifths 6.8, parallel 2.6, relative 3.5 and unrelated
3.9. Neither has any tritone errors.

**Against Apple**, 3f's misses are: we say major where Apple says minor 16.1; the reverse 3.5; fifths 7.5; relatives
7.3; parallels 5.6; unrelated 7.8.

**Why [inf]:**

- **The major-for-minor lean is shared** by everything we can run. Against Apple, Essentia edma shows it at 14.8 and
  madmom at 12.1, while Apple against the lab shows the mirror image (9.6 minor-for-major). So mode is where the
  references disagree with each other.
- **The physical cause:** the fifth harmonic of a minor tonic is its major third, so bright synth timbres raise the
  major third inside minor tracks (Faraldo 2017 [2nd]). A twelve-bin profile cannot tell an overtone from a played
  note.
- **Fifth errors** come from hooks and bass lines that sit on the dominant.
- **Unrelated keys** are mostly ambient, rubato and multi-key edits, the tracks the lab itself marks unsure.

**Confidence.** "Sure" means all three profiles agree and the margin is at least 0.08 (the lower tercile of margins
on dev). On held-out, sure tracks score 92.0 percent exact against the lab (88 tracks) against 65.1 for unsure ones
(43 tracks). Against Apple the same split is 77.5 (89 tracks) against 53.2 (62 tracks). The flag holds on material
it was not set on, which is what D13's soft key needs.

## Specification for the Swift port (row 3f)

Plain arithmetic on one real FFT per frame; no model. Reference Python: `recommended`, `spectral_peaks`, `hpcp`,
`decide` in `mixer/key_parity.py`.

1. **Input:** mono (channel mean), 44,100 Hz, float. Other rates are resampled to 44,100 first; the resampler's
   effect is [unmeasured].
2. **Frames:**
   - N = 4096, hop 4096, starting at sample 0, full frames only.
   - Periodic Hann window w[n] = 0.5 - 0.5 cos(2πn/N).
   - X[k] = |FFT(w·x)[k]| · 2/Σw, for k = 0..2048.
3. **Peaks**, for k = 3..324 (25 Hz up to 3500 Hz):
   - k is a peak if X[k] > X[k-1], X[k] ≥ X[k+1] and X[k] > 1e-5.
   - With a, b, c = 20 log10(X + 1e-10) at k-1, k, k+1, let p = 0.5(a-c)/(a-2b+c) (0 when the denominator is 0).
     Then f = (k+p)·44100/N and A = 10^((b - 0.25(a-c)p)/20).
   - Keep the 60 largest A per frame.
4. **Whitening:**
   - env = max X[j] for j from floor(κ·2^(-1/3)) to ceil(κ·2^(1/3)), with κ = f·N/44100 and j clipped to 0..460.
   - a = A/env. Values slightly above 1 are kept.
5. **HPCP**, 12 bins, C = 0:
   - For each peak with 25 ≤ f ≤ 3500 and each h = 1..4: s = 12 log2(f/(440h)) + 9.
   - For each integer c from floor(s)-1 to floor(s)+2, with d = s - c: if |d| ≤ 2/3, add cos²(3πd/4) · 0.6^(h-1) · a²
     to bin c mod 12.
   - Sum over all frames, with no per-frame normalisation. The scale of the sum is irrelevant.
6. **Correlation:**
   - For each profile P in {edma, bgate, braw}, each mode and each tonic t = 0..11, rotate P so its first value sits
     on bin t.
   - Pearson r against the HPCP: subtract both means, divide the dot product by the product of the norms.
   - Average r over the three profiles for each of the 24 keys.
7. **Decision:**
   - The highest mean r wins, mapped to Camelot with the engine's existing `CAM_MAJ` / `CAM_MIN`.
   - Ties go to the first key in the order major C..B, then minor C..B. No tie occurred here.
8. **Confidence:**
   - margin = best mean r minus the second best.
   - agree = how many of the three profiles pick the winner on their own.
   - sure = (agree = 3 and margin ≥ 0.08).
   - Store margin and agree. A mapping onto the lab's 0-to-1 scale is [unmeasured].

**Profile values**, tonic first, rising by semitone:

| Profile | Values |
|---|---|
| edma, major | 1.00 0.29 0.50 0.40 0.60 0.56 0.32 0.80 0.31 0.45 0.42 0.39 |
| edma, minor | 1.00 0.31 0.44 0.58 0.33 0.49 0.29 0.78 0.43 0.29 0.53 0.32 |
| bgate, major | 1.00 0.00 0.42 0.00 0.53 0.37 0.00 0.77 0.00 0.38 0.21 0.30 |
| bgate, minor | 1.00 0.00 0.36 0.39 0.00 0.38 0.00 0.74 0.27 0.00 0.42 0.23 |
| braw, major | 1.0000 0.1573 0.4200 0.1570 0.5296 0.3669 0.1632 0.7711 0.1676 0.3827 0.2113 0.2965 |
| braw, minor | 1.0000 0.2330 0.3615 0.3905 0.2925 0.3777 0.1961 0.7425 0.2701 0.2161 0.4228 0.2272 |

edma comes from Faraldo, Gómez, Jordà and Herrera, ECIR 2016 (LNCS 9626, 335-347). braw and bgate come from Faraldo,
Jordà and Herrera, AES Semantic Audio 2017: braw is the median profile of Beatport tracks, and bgate is braw with its
four weakest degrees zeroed. The numbers are as `key_light.py` carries them, transcribed from Essentia's key.cpp. I
could not open the ECIR tables to check them (open item 1).

**Where each parameter came from:**

| Parameter | Value | Source |
|---|---|---|
| Frame and hop | 4096 / 4096 | Essentia KeyExtractor's documented defaults; Faraldo 2017 [2nd] |
| Peak band | 25 to 3500 Hz | KeyExtractor defaults |
| Peaks per frame | 60 | KeyExtractor defaults |
| Peak floor | 1e-5 | first principles: below 16-bit noise, so effectively no threshold |
| Interpolation | parabolic on dB | standard spectral-peak practice [2nd: Smith and Serra 1987] |
| Whitening | on | Faraldo 2017 and Essentia's documentation (after Röbel and Rodet, DAFx 2005); confirmed by the black-box test |
| Envelope width | running max over ±1/3 octave | my simplification of the "true envelope", a third of an octave being the classic auditory band; ±1/6 and ±1/2 read within a point |
| Weighting window | 4/3 semitone, cos² | Gómez 2006, INFORMS J. Computing 18(3) |
| Amplitude | squared | Gómez 2006 |
| Harmonics | 4 | Essentia's documented Key default (numHarmonics 4); 8 reads the same within noise |
| Harmonic decay | 0.6 per harmonic | Essentia's documented slope 0.6, after Gómez 2006 |
| Profile average and margin threshold | three-profile average; 0.08 | dev split |

**Licence notes.**

- The method implements published papers.
- Essentia was used only as an oracle. I read its documentation strings and compared outputs on 48 tracks. That is
  how I found that in KeyExtractor, whitening plus 4-harmonic HPCP plus a plain (not polyphonic) profile reproduce its
  key on 46 of 48 tracks. I read no Essentia code.
- KeyFinder and Mixxx's detector are GPL and were not used.
- Mixed In Key's US 7,842,878 claims key classification against a database of labelled tracks, which this method does
  not do. Google Patents lists it as expired in 2023 [2nd]. No freedom-to-operate search was done.

**Cost.** 0.18 to 0.38 s per track in Python on this Mac, plus 0.2 to 0.3 s for decoding (`key_parity.py check`, 10
tracks). Swift does about 3,000 FFTs of 4096 points per track [inf: well under a second; unmeasured].

## Outside evidence (web search, Oct 28 to 29; nothing downloaded)

**Published scores.**

- GiantSteps Key (604 two-minute Beatport clips, 85 percent minor), exact percent from Knees et al., ISMIR 2015,
  Table 5: rekordbox 3 71.9; Mixed In Key 7 67.2; KeyFinder 45.4; QM Key 39.4; Essentia default 30.5.
- Faraldo 2017 on the same set: Mixed In Key 0.672; edmm 0.642; bgate 0.641; KeyFinder 0.604; edma 0.581.
- On Billboard pop, edma reaches 78.7 MIREX-weighted against a CNN's 83.9 (Korzeniowski and Widmer, EUSIPCO 2017).
- The MIREX weighted score is exact + 0.5 fifth + 0.3 relative + 0.2 parallel. The MIREX result pages failed on
  certificates, so I could not verify per-year bests.
- 3f uses these same profiles, so it should land near these numbers [unmeasured].

**DJ listening tests.** DJ TechTools judged tracks by ear with 6 or 7 listeners: in 2014 (61 tracks) Mixed In Key
scored 95, KeyFinder 77 and rekordbox 57; in 2015 (66 tracks) Mixed In Key 86, Serato and rekordbox 70, and Traktor
47. Mixed In Key publishes no accuracy figure that I found.

**Datasets** (annotation licence; audio):

| Dataset | Size and genre | Licence | Audio |
|---|---|---|---|
| GiantSteps Key | 604 EDM | none stated | script fetches Beatport previews |
| GiantSteps+ | 600 EDM, with key changes | CC BY-SA 4.0 | |
| GiantSteps-MTG-key | 1,486 EDM, 1,077 single-key high-confidence | CC BY-SA 4.0 | bundled on Zenodo, but the labels own it [inf: internal use only] |
| McGill Billboard | 740 pop/rock songs, 1958-91 | CC0 | none; tonic without mode |
| Isophonics | 231 songs (Beatles, Queen, Carole King, Zweieck), timed key segments | licence not found | tied to specific CDs |
| GTZAN key | about 837 clips | MIT | GTZAN's own known problems |

RWC Popular has no key labels. Schubert Winterreise (CC BY 3.0) is classical and out of scope.

**Run first: GiantSteps-MTG-key**, or GiantSteps Key if the bundled audio is not acceptable. It is the only set with
published rekordbox, Mixed In Key, KeyFinder, edma and bgate scores, so our number lands on a known scale. Report the
major-key subset separately. Then run a Billboard subset of songs we own, for pop. Christopher must approve any fetch.

**Forums.** DJ TechTools and Engine DJ threads name the same failures:

- relative and parallel major/minor first;
- modal tracks such as Phrygian and acid techno;
- bass- or vocal-heavy tracks;
- key changes.

One Engine user found about 150 of 200 tracks differed from Beatport and Tunebat [2nd]. Reddit would not fetch.
Snippets suggest an r/DJs series putting Mixed In Key at about 75 to 85 percent over 840 to 2,648 tracks [2nd,
unverified]. **Forum evidence is thin; a Reddit pass by Codex would help.**

## Open items

1. Re-source the profile tables from the Faraldo 2016 and 2017 papers rather than key.cpp, and get a view on the
   AGPL question.
2. The outside-dataset test above [unmeasured].
3. Key segments and mix-window keys with the new HPCP. The hysteresis rule from 1e was tuned on the old chroma; only
   the window majority (row 4d) was measured here.
4. Swift timing and agreement with this Python on the 373 tracks, the way 2a checked the old port [unmeasured].
5. A major/minor tie-break aimed at the 16 percent major-for-minor reads against Apple, for example discounting the
   fifth harmonic's share of the major third. Untested [inf]; it must be chosen on dev.

## Outside test: GiantSteps-MTG-key (Oct 29, 2026)

**The data set as fetched.** Zenodo record 1101082, "Beatport EDM Key Dataset" (Faraldo, UPF), version 1, DOI
10.5281/zenodo.1101082, published 2017-12-21, annotations CC BY-SA 4.0. It is the 1,486 two-minute Beatport EDM
excerpts of GiantSteps-MTG-key. The audio belongs to Beatport and the labels, so it was fetched for internal
evaluation only, kept in the session scratchpad, and is not committed and does not ship. Files fetched from the
Zenodo record by plain HTTP (no script from the data set was run): audio.zip 2,127,891,180 bytes (2.13 GB, MD5
matched Zenodo's), keys.zip 380 KB, Beatport-EDM-Key-Dataset.xlsx 148 KB, original_metadata.zip 921 KB. The
annotations used are the spreadsheet's main_key and confidence (0, 1, 2) columns.

**Subsets scored** (`mixer/key_outside.py`; per-clip results in `mixer/key_outside_results.tsv`):

- All 1,275 clips whose main key is a plain "note major" or "note minor". The other 211 (X, unknown, "other", modal
  names, key changes, two-key labels) are left out.
- High confidence: confidence 2 and a plain key, 1,122 clips (352 major, 770 minor). This is my own definition. The
  thesis reports 1,077 high-confidence single-key clips and I could not reproduce that count from the spreadsheet
  (confidence 2 without a key change gives 1,100) [unverified against the thesis]. The set is about 70 percent minor
  here and 85 percent minor in GiantSteps Key.

Row 3f is `key_parity.recommended` on the decoded clip; row 0 is the shipped engine's STFT chroma with edma. Neither
was tuned on this set. Exact, neighbour (relative key or one step on the wheel) and other follow the bench; parallel
keys count as other. MIREX weighted: exact 1, fifth 0.5, relative 0.3, parallel 0.2.

| Subset | Row | n | Exact | Neighbour | Other | MIREX weighted |
|---|---|---|---|---|---|---|
| All plain-key clips | 3f | 1,275 | 47.4 | 15.9 | 36.7 | 58.5 |
| All plain-key clips | 0 shipped | 1,275 | 45.5 | 15.4 | 39.1 | 56.2 |
| High confidence | 3f | 1,122 | 50.0 | 15.3 | 34.7 | 60.9 |
| High confidence | 0 shipped | 1,122 | 47.9 | 14.6 | 37.5 | 58.3 |
| High confidence, major keys | 3f | 352 | 61.9 | 16.2 | 21.9 | 71.0 |
| High confidence, major keys | 0 shipped | 352 | 49.7 | 18.2 | 32.1 | 61.0 |
| High confidence, minor keys | 3f | 770 | 44.5 | 14.9 | 40.5 | 56.4 |
| High confidence, minor keys | 0 shipped | 770 | 47.0 | 13.0 | 40.0 | 57.1 |

**Sure flag** (3f, high confidence): 43.6 percent of clips are flagged sure (489 of 1,122); exact is 58.5 among sure
and 43.4 among unsure. Over all 1,275 clips: 43.4 percent sure, exact 55.0 and 41.6. The flag still separates better
from worse reads, but the gap is 15 points, not the large gap the threshold was set for on the crate.

**Confusions** (3f, high confidence, percent of all clips): relative 5.6, fifth 9.7, parallel 22.0 (the parallel key
has the same tonic and the other mode, for example A minor read as A major). Major read as minor 7.8 (25 percent of the
major clips); minor read as major 30.0 (44 percent of the minor clips). Row 0 shows the same shape (major as minor
11.2, minor as major 26.6).

**Against published numbers.** Nothing here is a like-for-like exact-rate comparison.

| Source | Set | Metric | Value |
|---|---|---|---|
| Faraldo 2017 | GiantSteps Key (604 clips), not this set | MIREX weighted: Mixed In Key 0.672, edmm 0.642, bgate 0.641, KeyFinder 0.604, edma 0.581 | |
| Knees et al. 2015 | GiantSteps Key (604 clips) | exact percent: rekordbox 71.9, Mixed In Key 67.2, KeyFinder 45.4 | |
| This test | the 1,486-clip MTG set (the 604-clip set is a different, older annotation of other excerpts), high-confidence subset | MIREX weighted 60.9 (3f), 58.3 (row 0); exact 50.0 and 47.9 | |

The only like-for-like figure is Faraldo's MIREX-weighted scale, and even that is on a different set, so it is a
rough guide only: 3f at 0.609 sits between KeyFinder (0.604) and the better Faraldo methods (0.64), and the shipped
row 0 at 0.583 sits level with edma (0.581), as it should since it is edma on STFT chroma. The exact rates of Knees
et al. (rekordbox, Mixed In Key at 67 to 72) are on the other set and a different scorer, and are not comparable;
our 50 percent exact is well below them. That our exact rate is below commercial products is consistent with the
DJ listening tests above, but I have not run any commercial product on these clips [inf].

**What it says.** On music the method never saw, the new method is a little better than the engine we ship (about 2
points exact, 2.6 on the weighted score), and all of the gain is in major keys (12 points); in minor keys, which are
most of this music, it is 2.5 points worse. Both get about half of the keys exactly right, and the main mistake for
both is naming the wrong mode on the right note, so the crate result (83 percent) overstates how well this will do on
unfamiliar dance music. The sure flag still tells a better read from a worse one, but less sharply than on the crate.
The gain on this outside set is small, and the minor-key weakness is the thing to fix next: the open-item tie-break
(item 5) should be tried against minor-key losses, chosen on a split and not on this set.
