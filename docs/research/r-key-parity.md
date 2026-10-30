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
   fifth harmonic's share of the major third. Tested Oct 30, 2026: see "Overtones taken out of the chroma" at the end
   of this letter (the discount, and NNLS chroma beside it; chosen on the odd ids, reported on the even ids).

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

## Mode test and tag survey (Oct 29, 2026)

Two cheap ideas for the outside set's main error (minor keys read as major), tested without fitting anything to the
set. Scripts `mixer/key_mode.py` (per-variant and per-subset figures in `mixer/key_mode_results.tsv`) and
`mixer/key_tags_survey.py` (per-folder counts in `mixer/key_tags_survey.tsv`). Same clips, labels and scorer as the
outside test above; the cached features reproduce that test's row 3f and row 0 keys on all 1,275 clips.

### In plain words

A key has two parts: the home note and the mode (major, which sounds bright, or minor, which sounds dark). The only
written difference between the two modes on the same home note is three of the seven notes: the third, sixth and
seventh notes above the home note are each a half step lower in minor. Test 1 asks: once we know the home note, can we
decide the mode just by checking which version of those notes is louder? Test 2 asks: do the music files already
carry a key that a DJ program wrote, which we could read instead of working it out?

### Test 1: the mode test

**Method.** Row 3f picks the home note (T1: the tonic of its winning key; T2, a mode-neutral variant: the tonic whose
major and minor match scores add up highest). Then a separate rule picks the mode from the twelve-note profile p, with
the tonic at t:

- **a, third only:** minor if p[t+3] (the minor third) is larger than p[t+4] (the major third), else major.
- **b, third, sixth and seventh, equal weights:** minor if (p[t+3] - p[t+4]) + (p[t+8] - p[t+9]) + (p[t+10] - p[t+11]) > 0.
- **b2, third and sixth:** the same without the seventh.
- Each rule runs on three profiles: **H4w**, the whitened 4-harmonic HPCP that 3f itself uses; **C0**, the shipped
  engine's plain STFT chroma; and **H1w**, whitened HPCP with no harmonic folding. A tie keeps 3f's mode.

**Where the rules come from.** Temperley's revised profiles (Temperley 1999, *Music Perception* 17(1), 65-100) differ
between major and minor only at the third and the sixth; his minor uses the raised seventh. That is rule b2.
Krumhansl and Kessler's probe-tone profiles (1982, *Psychological Review* 89(4), 334-368) differ most at the third,
then the sixth, then the minor seventh. Faraldo's EDM profiles (edma, braw, bgate) show the same three degrees. That
is rule b. As a share of each profile's total, minor minus major at the minor and major third, minor and major sixth
and minor and major seventh: Krumhansl +6.5/-4.6, +3.2/-2.7, +2.0/+0.2; Temperley +6.5/-6.5, +3.9/-3.9, 0/0; edma
+3.4/-4.2, +2.3/-2.4, +2.2/-0.9; braw +4.9/-5.3, +2.1/-3.7, +4.4/-1.6 (computed from `key_light.PROFILES`). The decision
is a plain comparison. A ratio such as p[t+3]/p[t+4] against 1 is the same rule, and no source gives another threshold,
so no threshold was set.

**No fitting.** No rule has a parameter. Picking the best of the 18 variants is still a choice, so it was made on the
odd-numbered clip ids (high confidence, 579 clips) by **balanced exact**: the mean of the major-key and minor-key exact
rates, so a rule that just says "minor" more often cannot win on a set that is 70 percent minor. The even ids (543 clips)
are the held-out result.

**High confidence, 1,122 clips** (352 major, 770 minor; percent):

| Row | Exact | Nbr | Other | MIREX | Major exact | Major MIREX | Minor exact | Minor MIREX |
|---|---|---|---|---|---|---|---|---|
| 3f (outside test) | 50.0 | 15.3 | 34.7 | 60.9 | 61.9 | 71.0 | 44.5 | 56.4 |
| 0 shipped (outside test) | 47.9 | 14.6 | 37.5 | 58.3 | 49.7 | 61.0 | 47.0 | 57.1 |
| T1, H4w, a | 44.3 | 14.1 | 41.6 | 55.8 | 66.8 | 75.0 | 34.0 | 47.0 |
| **T1, H4w, b (best on odd ids)** | **50.8** | 15.3 | 33.9 | **61.6** | 63.1 | 72.0 | 45.2 | 56.8 |
| T1, H4w, b2 | 43.8 | 15.5 | 40.7 | 56.0 | 64.2 | 73.5 | 34.4 | 48.0 |
| T1, C0, a | 45.0 | 13.8 | 41.2 | 56.3 | 61.4 | 70.5 | 37.5 | 49.7 |
| T1, C0, b | 41.0 | 14.4 | 44.6 | 53.3 | 66.2 | 74.8 | 29.5 | 43.5 |
| T1, C0, b2 | 48.1 | 14.5 | 37.3 | 59.1 | 57.4 | 67.4 | 43.9 | 55.2 |
| T1, H1w, a | 41.9 | 14.0 | 44.1 | 53.8 | 66.5 | 74.8 | 30.6 | 44.2 |
| T1, H1w, b | 49.3 | 15.2 | 35.5 | 60.3 | 62.8 | 71.8 | 43.1 | 55.1 |
| T1, H1w, b2 | 42.8 | 15.1 | 42.2 | 55.0 | 63.6 | 73.1 | 33.2 | 46.8 |
| T2, H4w, b (best T2) | 48.5 | 16.6 | 34.9 | 60.0 | 55.7 | 66.8 | 45.2 | 56.9 |

**All 1,275 plain-key clips** (388 major, 887 minor):

| Row | Exact | Nbr | Other | MIREX | Major exact | Minor exact |
|---|---|---|---|---|---|---|
| 3f | 47.4 | 15.9 | 36.7 | 58.5 | 60.3 | 41.7 |
| 0 shipped | 45.5 | 15.4 | 39.1 | 56.2 | 48.5 | 44.2 |
| T1, H4w, a | 41.8 | 14.5 | 43.7 | 53.4 | 64.9 | 31.7 |
| **T1, H4w, b** | **48.1** | 15.8 | 36.2 | **59.0** | 61.1 | 42.4 |
| T1, C0, a | 42.7 | 14.4 | 42.8 | 54.1 | 59.0 | 35.6 |
| T1, C0, b2 | 45.9 | 15.2 | 38.9 | 57.0 | 55.9 | 41.5 |
| T1, H1w, b | 46.8 | 15.6 | 37.6 | 57.9 | 60.8 | 40.7 |

The other T1 and all T2 rows are in the TSV. Every T2 row is below its T1 row.

**Confusions** (high confidence, percent of all 1,122 clips):

| Row | Major as minor | Minor as major | Fifth | Relative | Parallel |
|---|---|---|---|---|---|
| 3f | 7.8 | 30.0 | 9.7 | 5.6 | 22.0 |
| 0 shipped | 11.2 | 26.6 | 9.8 | 4.8 | 20.5 |
| T1, H4w, a | 5.8 | 38.7 | 8.6 | 5.5 | 27.7 |
| T1, H4w, b | 7.4 | 30.0 | 9.7 | 5.6 | 21.2 |
| T1, C0, a | 7.8 | 35.1 | 8.6 | 5.3 | 27.0 |
| T1, C0, b2 | 9.2 | 30.8 | 9.0 | 5.5 | 23.9 |

**Held-out.** Balanced exact on the odd ids, where the choice was made: 3f 54.6, best rule (T1, H4w, b) 54.5, row 0
52.2. No rule beat 3f on the selection half. On the even ids: the rule scores 53.8 balanced (exact 50.3; major 62.9,
minor 44.7; MIREX 61.2), against 3f's 51.8 (exact 48.3; major 61.1, minor 42.6; MIREX 59.6) and row 0's 44.2. The
rule changes 3f's mode on only 81 of 1,122 clips (7 percent). On those 81 clips it is right 45.7 percent of the time,
where 3f was right 34.6 percent, a net of about nine clips. Gaining on one half and level on the other is what noise
looks like at this size, so the gain is not established.

**One-sided variants (flag).** On whitened HPCP, rules a and b2 gain 2 to 5 exact points on major keys and lose 10
to 14 on minor keys (H4w a: +4.9 / -10.5; H1w a: +4.6 / -13.9). Rule b on plain chroma gains 4.3 on major and loses
15.0 on minor. These rules push reads toward major, the direction of the existing error. On plain chroma, rules a and
b2 lose on both halves (a: -0.5 / -7.0; b2: -4.5 / -0.6). Only rule b on whitened 4-harmonic HPCP is better on both
halves (+1.2 / +0.7). On H1w the same rule is +0.9 / -1.4.

**Why the rules fail: a check with the right home note given.** This is a diagnostic, not a method, because it uses
the label's tonic. With the true home note given, here is how often each rule names the right mode (percent of major
clips / minor clips):

| Profile | a | b | b2 |
|---|---|---|---|
| H4w (whitened HPCP) | 94.0 / 55.5 | 89.2 / 66.0 | 90.6 / 52.5 |
| C0 (plain chroma) | 85.8 / 58.1 | 91.5 / 48.7 | 80.7 / 63.0 |
| H1w (whitened, no harmonics) | 93.5 / 50.9 | 88.9 / 62.7 | 90.3 / 50.5 |

In about half of the minor clips, the major third above the home note carries as much energy as the minor third
(51 to 58 percent "minor" by the third alone), even with the right home note. For comparison, 3f's own profile match
gets the mode right on about 62 percent of minor clips and 86 percent of major clips when its tonic is right. The
twelve-note profile of this music does not separate the modes at the third. This fits two causes. The tonic's fifth
harmonic lands on the major third (Faraldo 2017 [2nd], above). And EDM minor tracks often play the major third in
chords or leads, for example in a borrowed major chord or a raised-seventh dominant [inf]. Whitening and the harmonic
folding are not the main cause: by the third alone, plain chroma is only slightly better (58 against 56).

**The sure flag under the best rule.** 3f's flag as is (high confidence): 489 clips sure (43.6 percent), exact 58.7
with the rule against 44.7 unsure (3f's own key: 58.5 / 43.4). Tightening the flag to also require that the rule
agrees with 3f's mode changes 4 clips (485 sure, 58.8 against 44.7). The rule agreeing with 3f is not a useful flag
by itself: 92.8 percent of clips, exact 51.2 against 45.7. On all 1,275: sure 43.4 percent, 55.2 against 42.7. The
flag behaves as before.

**On the 214 clips Apple has read:** Apple 74.3 exact (MIREX 80.9), 3f 50.0 (61.4), row 0 50.0 (61.4), best rule 50.9
(61.6). The mode rule closes none of the 24-point gap to Apple.

**What it says.** Checking which version of the third, sixth and seventh notes is louder does not fix our major/minor
mistakes. In this dance music, the "major" version of the third is often just as loud in songs that people hear as
minor, so the sound itself, measured this way, does not give the answer. The one rule that is not worse moves results
by about a point, which is within chance. The mode is decided by something a twelve-note count does not capture, such
as which chords come where and how the bass moves. A fix needs a method that looks at that, for example a trained
model or Apple's framework, not a smarter count.

**Cost.** Extraction 175 s wall time for 1,272 clips (2 workers at nice 19, 0.27 s per clip per worker; free plus
inactive memory stayed at 7.6 to 8.2 GB). Scoring all variants from the cache takes 2 s. The cache is 203 MB in the
scratchpad and not committed.

### Test 2: the tag survey

**Method.** Tags only, no decoding, no file changed. ffprobe reads each file's container metadata, and a small ID3v2
reader lists the frames that ffprobe hides (GEOB and PRIV owner names). The script looks for:

- a TKEY frame;
- an INITIALKEY or KEY field (ID3 TXXX, Vorbis or MP4);
- a Mixed In Key style comment (a Camelot code such as "8A", or "Energy 6") or an EnergyLevel field;
- a Camelot prefix on the title;
- Serato, rekordbox/Pioneer, Traktor or Mixed In Key data.

Folders whose name starts with "_" are skipped. The sprint's `_pool build/newfiles/probe.json` is summarised from its
tag_key column, which `probe_new.py` read from TKEY.

| Source | Files | Any key tag | TKEY | Other key fields | Serato data | Format |
|---|---|---|---|---|---|---|
| 90s2000 playlist, top level | 117 | 61 | 61 | 0 | 63 | short ("Gm", "F#m") |
| Mike page | 198 | 54 | 54 | 0 | 55 | short |
| 17 other folders (CDs, CDs v2, CDs v3, PARTY CD'S, the album and compilation folders, dance-hits-collection) | 2,345 | 0 | 0 | 0 | 0 | |
| **Library total** | **2,660** | **115 (4.3 %)** | 115 | 0 | 118 | all 115 short notation |
| probe.json tag_key (the sprint's 106 new files) | 106 | 61 | 61 | | | short |
| Outside set (GiantSteps-MTG-key clips) | 1,486 | 7 | 7 | 0 | 0 | 6 read "o", 1 "B" |

No file had an INITIALKEY field, a Camelot or open-key value, a Mixed In Key comment or energy field, a title prefix, or
any rekordbox data. One Traktor mark in dance-hits-collection carries no key. Every key tag present is a TKEY in short
notation ("Am", "F#m", "D"), and every one sits in a file that also carries Serato's GEOB frames, so Serato wrote it.
Mike page probably holds copies of the top-level Serato files [inf; not checked by content].

**Against the human labels (outside set).** The Beatport clips carry no usable key: 7 of 1,486 have a TKEY, 6 of them
the single letter "o". The one readable tag ("B", B major) does not match its label. The audio in the Zenodo
archive was stripped of Beatport's key tags, so this set cannot say what reading tags is worth.

**Against references (the crate, agreement not accuracy).** The crate has no human labels, so this compares tags with
our other readings. 61 of the 373 crate tracks have a Serato TKEY. On those 61, Serato's key equals Apple's on 41
(67 percent), row 3f's on 40 and the lab's on 36. Row 3f equals Apple's on 44 of the same 61 (72 percent).

**What it says.** Only about one file in 25 in this library has a key written by a DJ program, all of them from Serato
in the same format. On those, Serato's answer agrees with Apple's about as often as ours does, no more. Reading the tag
is cheap and could fill in a key where we have none, but it would not make our keys more accurate. The outside set
cannot tell us how good tags are, because its files carry none.

## Apple's framework on the outside set (Oct 30, 2026)

**Method.** Apple's Music Understanding (iOS 27) ran over the same 1,275 clips in the iPad simulator (`tools/mubench`,
one clip at a time, about 7 s a clip, Oct 29 afternoon to Oct 30, 00:49). Its key for a clip is the longest key range
it reports, read as a Camelot code. Scored against the same annotations with the same scorer as row 3f
(`mixer/key_outside_apple.py`; per-clip results in `mixer/key_outside_apple.tsv`). Apple returned no key on 5 clips
(ids 277874, 299040, 574896, 797707, 1077935), so the tables are on 1,270 clips, and row 3f's figures below are on the
same 1,270 (they differ from the 1,275-clip table above in the first decimal only). Nothing here was tuned: Apple's
framework is a black box, and row 3f is the stored result.

| Subset | Reader | n | Exact | Fifth | Relative | Parallel | Other | MIREX weighted |
|---|---|---|---|---|---|---|---|---|
| All plain-key clips | Apple | 1,270 | 65.2 | 8.0 | 5.2 | 11.2 | 10.5 | 73.0 |
| All plain-key clips | 3f | 1,270 | 47.6 | 10.3 | 5.7 | 21.5 | 15.0 | 58.7 |
| Major keys | Apple | 386 | 41.5 | 6.0 | 12.2 | 29.3 | 11.1 | 53.9 |
| Major keys | 3f | 386 | 60.6 | 11.4 | 5.2 | 9.6 | 13.2 | 69.8 |
| Minor keys | Apple | 884 | 75.6 | 8.8 | 2.1 | 3.3 | 10.2 | 81.3 |
| Minor keys | 3f | 884 | 41.9 | 9.8 | 5.9 | 26.7 | 15.7 | 53.9 |
| Confidence 2 | Apple | 1,120 | 68.8 | 7.1 | 5.1 | 11.5 | 7.5 | 76.2 |
| Confidence 2 | 3f | 1,120 | 50.1 | 9.7 | 5.6 | 22.1 | 12.5 | 61.1 |
| Confidence 1 | Apple | 135 | 40.0 | 16.3 | 6.7 | 8.1 | 28.9 | 51.8 |
| Confidence 1 | 3f | 135 | 28.9 | 14.8 | 6.7 | 17.0 | 32.6 | 41.7 |
| Confidence 0 | Apple | 15 | 20.0 | 0.0 | 0.0 | 13.3 | 66.7 | 22.7 |
| Confidence 0 | 3f | 15 | 26.7 | 13.3 | 0.0 | 20.0 | 40.0 | 37.3 |

In the earlier table's terms (neighbour is the relative key or one step on the wheel; parallel counts as other): Apple
exact 65.2, neighbour 13.1, other 21.7; row 3f 47.6, 16.0, 36.5.

**The mode.** The set is 70 percent minor. Apple answers minor on 1,003 of the 1,270 clips (the truth is 884); row 3f
answers minor on 598. Apple reads 51.6 percent of the major clips as minor; row 3f reads 44.0 percent of the minor
clips as major. So the two readers lean opposite ways on the mode, and the set's minor majority is what puts Apple
ahead overall. On the home note alone (exact or parallel): Apple 76.4, row 3f 69.1.

**Where they agree.** The two give the same key on 604 clips, and there the key is exact 75.3 percent of the time
(major 63.7, minor 80.2). Where they differ (666 clips), Apple is right on 56.0 percent and row 3f on 22.4, neither on
21.6. Split by mode: on the minor clips they differ on, Apple is right on 71.2 percent and row 3f on 6.3; on the major
clips, row 3f on 58.0 and Apple on 22.2.

**Against the first pass.** The first 214 clips (Oct 29 afternoon, noted in 00-decisions) gave Apple 74.3 exact against
row 3f's 50.0; the full set gives 65.2 against 47.6. The first 214 (the lowest ids) were easier clips for Apple.

**Against published numbers.** Same caveat as above: GiantSteps Key (604 clips) is a different, older annotation of
other excerpts, and Knees et al. 2015 used a different scorer. Their exact rates (rekordbox 71.9, Mixed In Key 67.2,
KeyFinder 45.4) are a rough scale only; on it Apple's 65.2 sits near Mixed In Key and row 3f's 47.6 near KeyFinder.

**Against D16's bar.** D16 asks that our own reader be exact within five points of Apple's framework on the same clips,
on the major and minor halves separately. Major half: row 3f 60.6, Apple 41.5 (ours ahead by 19 points). Minor half:
row 3f 41.9, Apple 75.6 (ours behind by 34 points). The bar is not met; the minor half decides it. Overall, ours
trails by 17.6 points.

**What it says.** Apple's framework is not a gold standard on this music: it gets two clips in three exactly, and it
calls half of the major-key clips minor. Ours is the better reader of major keys and much the worse reader of minor
keys, which are most of dance music. The two readers' mistakes are different enough that their agreement says
something (three in four right when they agree, against one in two overall); on Mac and iPad, where Apple's key is
what ships (D11), that is an observation about the sure flag, not a change. For Windows and Linux, D16 holds, and
the minor-key weakness is the gap. The downbeat-weighted chroma, the last of the three cheap ideas, is scored in the
next section.

## Chroma weighted toward the beat grid (Oct 30, 2026)

The third cheap idea of D16. Harmony is carried most by what sounds on the strong beats (the bass note on the downbeat
names the chord root, and chords change on bar lines far more often than inside a bar: the metrical hierarchy of
Lerdahl and Jackendoff 1983), so the frames on the downbeat and on the beat might deserve more weight than the frames
between them. Script `mixer/key_downbeat.py`; per-clip results in `mixer/key_downbeat.tsv`.

**Method.** Row 3f as stored, with one change: the whitened HPCP frames (4,096 samples at 44.1 kHz, about 93 ms, no
overlap) are summed with a weight per frame instead of equally. The beat grid is Apple's, from the run in the section
above (each clip's rhythm.bars and rhythm.beats), standing in for the engine's grid, which is the same kind of thing;
all 1,275 clips have one. Four weightings, fixed before the run, none tuned: equal (the baseline, which reproduces the
stored row 3f clip for clip), downbeat frames only (one frame per bar), beat frames only (one per beat), and metrical
(the downbeat frame 1, the other beat frames 1/2, the frames between beats 1/4). The profiles, the tie rules and the
sure flag are unchanged.

| Weighting (all 1,275 clips) | Exact | Fifth | Relative | Parallel | Other | MIREX weighted |
|---|---|---|---|---|---|---|
| equal (row 3f) | 47.4 | 10.3 | 5.6 | 21.4 | 15.3 | 58.5 |
| downbeat frames only | 32.8 | 12.7 | 7.4 | 19.6 | 27.5 | 45.3 |
| beat frames only | 42.0 | 10.6 | 7.1 | 18.9 | 21.4 | 53.2 |
| metrical (1, 1/2, 1/4) | 46.7 | 10.8 | 6.3 | 20.5 | 15.7 | 58.1 |

| Subset | n | equal | downbeat | beat | metrical |
|---|---|---|---|---|---|
| Major keys, exact | 388 | 60.3 | 44.8 | 50.3 | 58.0 |
| Minor keys, exact | 887 | 41.7 | 27.5 | 38.3 | 41.7 |
| Confidence 2, exact | 1,122 | 50.0 | 34.7 | 43.9 | 49.2 |
| Confidence 1, exact | 138 | 28.3 | 20.3 | 28.3 | 29.0 |
| Confidence 0, exact | 15 | 26.7 | 6.7 | 20.0 | 20.0 |

Against equal: downbeat answers differently on 597 clips, exact gained 79 and lost 265 (net 186 lost); beat differs
on 361, gained 70, lost 139 (net 69 lost); metrical differs on 94, gained 26, lost 35 (net 9 lost).

**What it says.** Weighting the chroma toward the grid does not help, and the more weight the strong beats get, the
worse the key, on both halves and at every confidence level. The frames on the beat are where the kick drum lands in
this music, and a kick's energy is broad and low and sits on top of whatever the bass is playing, so the frames
between the hits are where the harmony is clearest [inf: the shape of the numbers, not measured on the frames]. The
metrical weighting, which keeps every frame, lands within chance of equal and gains nothing on the minor half. So all
three cheap ideas are now measured: the mode rule is within chance, the tags are too few to matter, and the grid
weighting is worse. None moves the minor-key weakness, and D16 stands: on a computer without Apple's framework,
Deckie's own key waits for a better reader than a profile match. What remains is larger: the open items above (the
tie-break of item 5 tried against minor-key losses) or a trained model.

## Overtones taken out of the chroma (Oct 30, 2026)

The next test after the three cheap ideas, aimed first at the home note and second at the mode. Script
`mixer/key_overtones.py`; per-clip results for every row in `mixer/key_overtones.tsv` (key, relation, margin and sure
flag per row, the half of the split, row 3f's stored key and Apple's).

### In plain words

A key has a home note (the note a piece keeps coming back to and feels finished on; it is the key's letter, such as A
in A minor) and a mode (major, which sounds bright, or minor, which sounds dark). Every note an instrument plays also
sounds a ladder of fainter, higher notes at the same moment, its overtones. Two rungs of that ladder land on notes that
matter for the key: the third overtone sounds the note a fifth above (for A, the E), and the fifth overtone sounds the
major third above (for A, the C sharp). So a bass line on A makes an E and a C sharp ring faintly even when nobody
plays them, and a reader that counts how loud each of the twelve notes is will hear "A major" in a track that is in A
minor, or "E" as the home note in a track at home on A. The principle of this test is to take that overtone energy out
before the key is decided. Part A does it with simple arithmetic: from each note's loudness, subtract the share the
note below it would have put there through its overtones. Part B does it the way the published method does, by
approximate transcription: working out, moment by moment, which notes were most likely played (each note with its
whole ladder of overtones) and counting only those. Nothing was fitted to the music; the same reader should hold for
any DJ's crate.

### Method

**Part A, the harmonic discount (open item 5).** From the per-frame cache of the mode test (row 3f's own whitened
4-harmonic HPCP per 93 ms frame, H4w, and the 1-harmonic version, H1w), for each frame and pitch class k:
p'[k] = max(0, p[k] − w · p[k − d]), with (d, w) = (7, 0.6²) for the third harmonic and (4, 0.6⁴) for the fifth
harmonic; "both" takes both shares off the original frame at once. Twelve rows: {third, fifth, both} × {per frame, on
the clip's summed vector} × {H4w, H1w}, each decided as 3f (the three Faraldo profiles averaged). Per frame is the
principled version: an overtone sounds at the same moment as its root, so the share to take off is set by the root's
energy in the same frame; on the summed vector a root in one bar would discount a fifth played in another. The summed
form is shown for comparison.

**Part B, NNLS chroma.** Our own implementation of the published method: audio at 11,025 Hz, Hamming frames of 4,096
samples (0.37 s), a log-frequency spectrum of 256 bins a third of a semitone apart, global tuning, the "std"
pre-processing (subtract a running mean over a Hamming-weighted octave, divide by the running standard deviation,
negatives to zero; this plays the part of 3f's whitening), a dictionary of 84 notes A0 to G#7 each with 20 harmonics of
amplitude s^(k−1), a non-negative least-squares fit per frame, and the note activations summed into twelve pitch
classes. The hop is 1,024 samples at 11,025 Hz (93 ms, the reader's own frame rate; the plugin's is twice as dense),
padded so frame centres coincide with the H4w frames. Four values of s ran as fixed variants (0.6, 0.7, 0.9 and the
paper's "LS", 0.9 for the lowest note down to 0.6 for the highest); three ranges (full, and the paper's treble and bass
windows); seven decisions (the Faraldo average as 3f, and each single profile set in `key_light.PROFILES`). 84 rows.

**Selection.** The best row of each part is chosen on the selection half (odd clip ids, data set confidence 2, 579
clips) by balanced home note (the mean of the major-key and minor-key home-note rates, home note = exact + parallel),
ties by balanced exact, and reported on the held-out half (even ids, confidence 2, 543 clips), on all 1,275 clips and
on the 1,270 Apple read. A paired sign test on the held-out half (clips one reader gets right and the other wrong)
says whether a difference is more than noise.

**Checks.** The cache reproduces row 3f's stored key on all 1,275 clips. The treble and bass windows are the plugin's
tabulated values, reproduced by closed forms to within 1e-5 and 1.1e-3.

### Where the numbers come from

- The overtone ladder and the slope 0.6 per harmonic: Gómez 2006, *Tonal Description of Music Audio Signals*, PhD
  thesis, Universitat Pompeu Fabra, section 3 (the reader's own `harmonic_template`).
- NNLS chroma: Mauch and Dixon 2010, "Approximate note transcription for the improved identification of difficult
  chords", ISMIR 2010 (Utrecht), pp. 135-140: frame length and sample rate (2.2), 3 bins a semitone and 256 bins
  (2.2), the "std" pre-processing over an octave, bins k−18 to k+18 (2.3), s^(k−1) with s = 0.6, 0.9 and LS tested and
  84 tones from 27.5 Hz to 3,322 Hz, each normalised to sum 1 (2.4), the treble and bass chroma windows (2.5, Figure
  2). The paper's best rows were std with s = 0.6 (80.0 on the MIREX chord metric) and std with LS (63.3 on the finer
  metric).
- NNLS Chroma / Chordino Vamp plugin (Mauch, QMUL; release 0.2 README and source, GPL; read, not copied): spectral shape
  default s = 0.7, whitening 1.0 (the std case), 20 harmonics per note, tuning from the lower 62 percent of the bins,
  the window tables.
- Non-negative least squares: Lawson and Hanson 1974, *Solving Least Squares Problems*, ch. 23 (scipy.optimize.nnls).

### No fitting

Every value is the reader's own or published, written into the script before the run. The only choice is which row
to report, and it was made on the selection half. Caution: braw and bgate (Faraldo, Jordà and Herrera, AES Semantic
Audio 2017) were made from Beatport EDM, the music of this data set, so rows that use them are not clean outside
measurements of those profiles; the outside-test section above does not note this [2nd: the derivation is as the 2017
paper's abstract and this letter's profile note describe it; I could not open the paper to check whether the very same
clips were used]. The chosen Part B row decides with the Faraldo average, which includes them, as row 3f does.

### Results

Chosen rows: Part A **A-both-frame-H4w** (both shares, per frame, on H4w); Part B **B-s07-full-faraldo** (s = 0.7, full
range, Faraldo average). Columns are percent of clips; home note = exact + parallel; Camelot number = exact +
relative.

| Subset | Row | n | Exact | Fifth | Relative | Parallel | Other | Home note | Camelot number | MIREX |
|---|---|---|---|---|---|---|---|---|---|---|
| Selection half | 3f | 579 | 51.6 | 10.0 | 4.7 | 20.7 | 13.0 | 72.4 | 56.3 | 62.2 |
| Selection half | A-both-frame-H4w | 579 | 60.4 | 9.8 | 5.7 | 13.3 | 10.7 | 73.7 | 66.1 | 69.7 |
| Selection half | B-s07-full-faraldo | 579 | 62.0 | 7.6 | 4.1 | 16.2 | 10.0 | 78.2 | 66.1 | 70.3 |
| Held-out half | 3f | 543 | 48.3 | 9.4 | 6.6 | 23.4 | 12.3 | 71.6 | 54.9 | 59.6 |
| Held-out half | A-both-frame-H4w | 543 | 56.0 | 10.9 | 5.5 | 14.2 | 13.4 | 70.2 | 61.5 | 65.9 |
| Held-out half | B-s07-full-faraldo | 543 | 54.9 | 8.1 | 6.3 | 17.7 | 13.1 | 72.6 | 61.1 | 64.3 |
| Held-out, major | 3f | 167 | 61.1 | 12.0 | 6.0 | 11.4 | 9.6 | 72.5 | 67.1 | 71.1 |
| Held-out, major | A-both-frame-H4w | 167 | 56.9 | 8.4 | 3.0 | 22.2 | 9.6 | 79.0 | 59.9 | 66.4 |
| Held-out, major | B-s07-full-faraldo | 167 | 62.3 | 8.4 | 3.0 | 16.8 | 9.6 | 79.0 | 65.3 | 70.7 |
| Held-out, minor | 3f | 376 | 42.6 | 8.2 | 6.9 | 28.7 | 13.6 | 71.3 | 49.5 | 54.5 |
| Held-out, minor | A-both-frame-H4w | 376 | 55.6 | 12.0 | 6.6 | 10.6 | 15.2 | 66.2 | 62.2 | 65.7 |
| Held-out, minor | B-s07-full-faraldo | 376 | 51.6 | 8.0 | 7.7 | 18.1 | 14.6 | 69.7 | 59.3 | 61.5 |
| All 1,275 | 3f | 1,275 | 47.4 | 10.3 | 5.6 | 21.4 | 15.3 | 68.8 | 53.0 | 58.5 |
| All 1,275 | A-both-frame-H4w | 1,275 | 55.4 | 10.6 | 5.8 | 13.5 | 14.7 | 68.9 | 61.2 | 65.1 |
| All 1,275 | B-s07-full-faraldo | 1,275 | 55.4 | 8.1 | 5.3 | 16.9 | 14.4 | 72.2 | 60.6 | 64.4 |
| All, confidence 1 | 3f / A / B | 138 | 28.3 / 32.6 / 31.9 | | | | | 44.9 / 44.9 / 49.3 | | 40.8 / 43.8 / 42.5 |
| All, confidence 0 | 3f / A / B | 15 | 26.7 / 46.7 / 33.3 | | | | | 46.7 / 53.3 / 40.0 | | 37.3 / 53.3 / 36.7 |

**Beside Apple** (the 1,270 clips Apple read):

| Half | Reader | n | Exact | Fifth | Relative | Parallel | Other | Home note | Camelot number | MIREX |
|---|---|---|---|---|---|---|---|---|---|---|
| All | Apple | 1,270 | 65.2 | 8.0 | 5.2 | 11.2 | 10.5 | 76.4 | 70.4 | 73.0 |
| All | 3f | 1,270 | 47.6 | 10.3 | 5.7 | 21.5 | 15.0 | 69.1 | 53.2 | 58.7 |
| All | A-both-frame-H4w | 1,270 | 55.6 | 10.6 | 5.8 | 13.5 | 14.5 | 69.1 | 61.4 | 65.3 |
| All | B-s07-full-faraldo | 1,270 | 55.6 | 8.1 | 5.3 | 16.9 | 14.2 | 72.4 | 60.9 | 64.6 |
| Major | Apple | 386 | 41.5 | 6.0 | 12.2 | 29.3 | 11.1 | 70.7 | 53.6 | 53.9 |
| Major | 3f | 386 | 60.6 | 11.4 | 5.2 | 9.6 | 13.2 | 70.2 | 65.8 | 69.8 |
| Major | A-both-frame-H4w | 386 | 53.9 | 9.6 | 3.4 | 20.7 | 12.4 | 74.6 | 57.3 | 63.8 |
| Major | B-s07-full-faraldo | 386 | 63.2 | 8.8 | 2.6 | 14.0 | 11.4 | 77.2 | 65.8 | 71.2 |
| Minor | Apple | 884 | 75.6 | 8.8 | 2.1 | 3.3 | 10.2 | 78.8 | 77.7 | 81.3 |
| Minor | 3f | 884 | 41.9 | 9.8 | 5.9 | 26.7 | 15.7 | 68.6 | 47.7 | 53.9 |
| Minor | A-both-frame-H4w | 884 | 56.3 | 11.1 | 6.9 | 10.3 | 15.4 | 66.6 | 63.2 | 66.0 |
| Minor | B-s07-full-faraldo | 884 | 52.3 | 7.8 | 6.4 | 18.1 | 15.4 | 70.4 | 58.7 | 61.7 |

**Home-note errors by interval** (predicted home note minus the true one, in semitones; clip counts on the 1,270):

| Interval | +1 | +2 | +3 | +4 | +5 | +6 | +7 | +8 | +9 | +10 | +11 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Apple | 9 | 22 | 27 | 16 | 59 | 5 | 67 | 13 | 58 | 17 | 7 |
| 3f | 11 | 21 | 53 | 32 | 65 | 6 | 127 | 19 | 21 | 34 | 4 |
| A-both-frame-H4w | 9 | 15 | 65 | 17 | 129 | 6 | 62 | 32 | 17 | 37 | 4 |
| B-s07-full-faraldo | 15 | 18 | 59 | 22 | 72 | 8 | 85 | 22 | 16 | 28 | 5 |

+7 is naming the dominant (the fifth above) as home, +5 the subdominant (the fifth below), +3 the relative major of a
minor key, +9 the relative minor of a major key.

**Every Part A row** (balanced = mean of the major and minor halves; held-out = even ids, confidence 2; "differs" and
"gained / lost" are exact answers against 3f over all 1,275):

| Row | Sel. balanced home | Sel. balanced exact | Held-out balanced home | Held-out balanced exact | All home | All exact | All MIREX | Differs | Gained / lost |
|---|---|---|---|---|---|---|---|---|---|
| 3f (baseline) | 72.0 | 54.6 | 71.9 | 51.8 | 68.8 | 47.4 | 58.5 | 0 | |
| H1w (baseline) | 68.9 | 51.1 | 64.9 | 45.0 | 65.2 | 43.5 | 56.4 | 167 | 30 / 80 |
| both, per frame, H4w | 73.8 | 58.6 | 72.6 | 56.2 | 68.9 | 55.4 | 65.1 | 430 | 210 / 108 |
| fifth, per frame, H4w | 73.3 | 59.5 | 72.4 | 57.5 | 69.0 | 54.7 | 64.6 | 210 | 131 / 37 |
| both, summed, H1w | 73.0 | 56.6 | 73.2 | 55.7 | 69.1 | 55.1 | 64.7 | 401 | 199 / 100 |
| fifth, summed, H4w | 72.9 | 59.1 | 72.4 | 56.7 | 68.9 | 54.4 | 64.3 | 213 | 130 / 41 |
| third, per frame, H4w | 72.8 | 58.0 | 72.9 | 57.6 | 68.6 | 52.8 | 62.7 | 320 | 148 / 79 |
| both, per frame, H1w | 72.2 | 58.0 | 73.4 | 58.0 | 68.9 | 55.8 | 65.2 | 332 | 179 / 71 |
| third, summed, H1w | 72.1 | 56.2 | 74.1 | 57.7 | 69.3 | 52.9 | 62.6 | 269 | 132 / 61 |
| third, summed, H4w | 72.0 | 57.8 | 72.0 | 56.2 | 68.0 | 52.8 | 62.9 | 356 | 159 / 90 |
| third, per frame, H1w | 72.0 | 56.1 | 73.4 | 56.6 | 68.8 | 51.6 | 61.6 | 222 | 108 / 54 |
| both, summed, H4w | 71.4 | 56.1 | 72.3 | 54.5 | 67.4 | 53.9 | 64.2 | 495 | 222 / 139 |
| fifth, summed, H1w | 70.9 | 57.6 | 66.7 | 50.9 | 66.4 | 52.0 | 63.0 | 241 | 120 / 61 |
| fifth, per frame, H1w | 70.3 | 56.7 | 66.9 | 51.3 | 66.3 | 51.5 | 62.7 | 234 | 114 / 61 |

**Part B by family** (balanced home note; the Faraldo-average row of each s and range, and the single profile that did
best on the selection half). The chosen row, B-s07-full-faraldo, differs from 3f on 367 clips, exact gained 183 and
lost 81. All 84 rows are in the sheet.

| s | Range | Faraldo average: selection | held-out | Best single profile (selection) | its selection | its held-out |
|---|---|---|---|---|---|---|
| 0.6 | full | 77.2 | 73.4 | braw | 77.5 | 73.2 |
| 0.6 | treble | 74.8 | 74.1 | braw | 75.2 | 74.5 |
| 0.6 | bass | 64.6 | 65.0 | edma | 65.5 | 65.8 |
| 0.7 | full | 78.1 | 74.4 | braw | 77.8 | 74.7 |
| 0.7 | treble | 75.8 | 73.3 | braw | 75.2 | 74.4 |
| 0.7 | bass | 65.9 | 65.9 | edma | 67.0 | 66.8 |
| 0.9 | full | 75.7 | 77.4 | krumhansl | 77.3 | 75.4 |
| 0.9 | treble | 74.2 | 73.6 | bgate | 74.9 | 72.2 |
| 0.9 | bass | 66.7 | 68.1 | krumhansl | 70.9 | 69.3 |
| LS | full | 76.9 | 75.3 | shaath | 77.5 | 73.6 |
| LS | treble | 75.5 | 74.2 | braw | 75.4 | 74.1 |
| LS | bass | 66.2 | 66.2 | edma | 68.9 | 67.8 |
| (3f) | | 72.0 | 71.9 | | | |

### Held-out

| Row (held-out half, paired against 3f) | Home note gained | lost | sign test p | Exact gained | lost | sign test p |
|---|---|---|---|---|---|---|
| A-both-frame-H4w | 33 | 41 | 0.42 | 89 | 47 | <0.001 |
| B-s07-full-faraldo | 34 | 29 | 0.62 | 72 | 36 | 0.001 |

Home-note gain over 3f by half, in points (selection / held-out / all 1,275): A-both-frame-H4w major +3.2 / +6.6 /
+4.4, minor +0.5 / −5.1 / −1.8; B-s07-full-faraldo major +7.0 / +6.6 / +7.0, minor +5.3 / −1.6 / +1.9.

The selection half's home-note gain does not hold on the held-out half for either chosen row: Part A goes from +1.8
balanced points to +0.7 and B from +6.1 to +2.5, and the paired counts on the held-out home note are within chance
(p 0.42 and 0.62). The exact gain does hold: +7.7 and +6.6 points on the held-out half (sign test p < 0.001 and p = 0.001). The
B row's home-note gain that remains sits in the major half (+6.6 held out); in the minor half it reverses (+5.3
selected, −1.6 held out), which by this letter's rule for the mode test is noise.

### What it says

- **The overtones were the mode lean.** Taking them out moves 3f's exact rate from 47.4 to 55.4 percent on all 1,275
  clips in both parts, and the gain holds on the clips the choice never saw. It comes from the parallel errors (right
  home note, wrong mode), which fall from 21.4 to 13.5 (A) and 16.9 (B) percent, and it is concentrated in the minor
  half (held-out minor exact 42.6 to 55.6 and 51.6). Part A trades some of it back in the major half (held-out major
  exact 61.1 to 56.9: it now calls some major keys minor); Part B does not (62.3).
- **The home note did not move beyond chance.** Balanced home note on the held-out half: 3f 71.9, A 72.6, B 74.4, and
  the paired counts are level. Part A removes half of the dominant errors (+7: 127 to 62) and adds the same number as
  subdominant errors (+5: 65 to 129): the discount takes the fifth's energy down so far that the note below the home
  note wins instead. Part B cuts the dominant errors to 85 without that swap (+5: 72), the nearest any of our readers
  has come to Apple's interval shape (67 and 59) [measured counts; whether this is a real gain in the home note is
  what the sign test does not support at this size].
- **Every full-range and treble NNLS row with the Faraldo average beats 3f on the held-out balanced home note** (73.3
  to 77.4 against 71.9), and every bass-range row with the Faraldo average is worse (65.0 to 68.1). The rows share most of their arithmetic, so
  this is one finding seen eight times, not eight findings [inf]. The best held-out row (s = 0.9, full, 77.4) is not
  the one the selection half chose, which is what noise among near-equal rows looks like [inf].
- **Against Apple** on the 1,270: the gap in exact narrows from 17.6 points to 9.6 for both parts. On the home note, B
  is 4.0 behind Apple (72.4 against 76.4; 3f is 7.3 behind). By half, B beats Apple on major keys on both measures
  (exact 63.2 against 41.5, home note 77.2 against 70.7) and still trails on minor keys (exact 52.3 against 75.6, home
  note 70.4 against 78.8). D16's bar (exact within five points on each half) is still not met: the minor half is 23
  points short.
- **Per frame against summed.** On the held-out balanced home note, for H4w per frame is ahead of summed for both
  shares (72.6 against 72.3) and the third (72.9 against 72.0) and level for the fifth (72.4 each); for H1w summed is
  as good or better (third 74.1 against 73.4). Differences under a point: no firm order [measured, mixed].
- **Cost.** NNLS took 2.29 s a clip per worker (decode included), 24 minutes for the 1,275 clips at two workers and
  nice 19; Part A runs from the cache in seconds and would add a few multiplications a frame to the engine [inf].

Nothing here is decided; the decision note says what follows.
