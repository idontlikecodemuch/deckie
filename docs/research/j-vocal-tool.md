# Research J: the vocal signal, which detector to port

Dated Oct 27, 2026. Brief: find the best vocal-detection tool Deckie can run on device (iPhone, iPad, Mac; Swift;
App Hold Media LLC, closed source, commercial). Reads `stage1-results.md` 1a, `analysis-port-plan.md` (A19, A22,
the vocal term and gate), `mixer/README.md`, track A section 2, D3 and D11, track C dimension 9. New measurements
in this document were made this session on the 373 `mixer/mu_raw/*.mu.json` files against `mixer/features/`;
they are labelled "measured". Inference is marked [inf]. Nothing here is legal advice.

## 1. Summary (one page)

**Recommendation: ship Music Understanding's instrument activity as the vocal signal in v1, and spend the next
effort on calibration and a listening set, not on another model.** The 0.64 correlation and the 0.53-versus-0.87
mean in stage 1 are not evidence against the framework; they are evidence against the lab. Measured this session:
where the two disagree by eight bars or more on the length of the vocal-free intro (103 tracks), the framework is
the longer side on 96, and the long side is right on the instrumentals (Children, Barber's Adagio, X-Files,
Stranger Things) and on songs that open on a vocal hook the lab missed as "clean" (Disturbia 18 bars to 5, Baby
Got Back 9 to 0, Padam Padam 8 to 0, Milkshake 17 to 7). The framework also ships a presence view we have not used:
`ranges`, which behaves like activity at or above about 0.3 with smoothing (section 3.1). Using it, 39 percent of
the pool gets an 8-bar vocal-free intro and 17 percent a 16-bar one, against the lab's 14 and 6 percent. That is the
"mix windows came out short" problem of the sprint, fixed by the signal we already have for free, in the 12 s per
track already paid.

**The hole, and why it is a product question before it is a model question.** The framework hears "singing".
Sampled, chopped and vocoded vocals read as not vocal: Eric Prydz, Call on Me, bar mean 0.06 (the lab said 0.39);
Daft Punk, Robot Rock, 0.07. A DJ would call both vocal tracks for clash purposes. No candidate below fixes this
by itself; a vocal stem would (the chopped sample lands in the vocal stem), and so would a DJ-facing flag. Decide
what "vocal" means to the slider in track C before judging any detector on it.

**Runner-up: HTDemucs vocal stem, Mac first.** MIT code, two Swift routes (demucs-mlx-swift, MIT, iOS 17 and macOS
14 or later, 112x realtime on an M4 Max; htdemucs-coreml, MIT, 200 MB fp16, GPU only, Neural Engine unstable). It
is the only candidate that also yields the stem the onboarding renders want, and a stem-energy series catches the
sampled-vocal cases. It is not a phone signal: 160 to 200 MB of weights, no published iOS timings, and the Demucs
repository is archived. Position it as the optional Mac and iPad Pro pass that upgrades a crate record, as track A
already planned.

**Third: a tiny AudioSet tagger as second opinion and level-2 fallback.** EfficientAT mn04_as (MIT code and
weights, 0.98M parameters, 0.11 GMAC per 10 s clip, AudioSet "Singing" class) or YAMNet (Apache 2.0, 3.7M, an
existing Core ML conversion). Neither has a published singing-voice-detection benchmark; both would be calibrated
on the same listening set. This replaces SoundAnalysis's built-in `singing` label in the level-2 plan only if that
label fails the listening test; the built-in classifier costs nothing to try first.

**Not recommended.** Open-Unmix (umxl is CC BY-NC-SA; the MIT umxhq scores 6.25 dB on vocals); Spleeter
(TensorFlow 1, FFT outside Core ML, no model-licence statement); BS-RoFormer and Mel-RoFormer (72 to 93M
parameters, the best weights carry no licence); PANNs (weights CC BY 4.0, 327 MB, 320 ms resolution); AST, BEATs,
CLAP (clip-level on 10 s, 80M and more; BEATs' weight licence is an unanswered issue); the Schlüter and Lehner
CNNs (MIT Theano code, no released weights; we would be training, not porting).

**Test plan in one paragraph.** Score on bars, not Pearson r (r is zero on wall-to-wall vocal tracks). Three
references: the lab's per-bar probabilities where they are trustworthy (under 0.2 and over 0.9); a 40-track
listening set labelled by Christopher per bar from the disagreement lists in section 7; and HTDemucs vocal-stem
energy on the Mac as the stem-based control. Metrics: first-vocal-bar error, vocal-free intro and outro bars
within 2, bar agreement over a threshold sweep, the share of tracks whose window size changes. Pass mark for v1:
first vocal bar within two bars on 90 percent of the listening set.

## 2. What the signal feeds

From `analysis-port-plan.md`: A22 sizes the mix-in and mix-out windows (32, 16 or 8 bars) by consecutive
vocal-free bars under a 0.5 cut; A20 and A23 use the bar mean for `vocal_heavy` (over 0.75); the scorer's vocal
term is `1 - mean(P_A x P_B)` over the overlap, a bonus when B's first 16 bars are under 0.5, the `v >= 0.6` gate,
and 0.35 and 0.6 in `transition()`; track C makes gate and weight a slider. Every constant was tuned on a head
averaging 0.87, so every constant moves. Resolution needed: a bar. Optional later: a stem for the onboarding
listening step. Budget: inside the current 12 s per track, small on disk, shippable licence.

## 3. Apple's on-device options

### 3.1 Music Understanding instrument activity (measured)

The API: `activity: [Instrument: [TimedValue<Float>]]`, "the activity level of each instrument over time, as
values from 0.0 to 1.0", and `ranges: [Instrument: [CMTimeRange]]`, "discrete time windows during which the
framework detected each instrument"; "use both properties together to determine when an instrument is present and
how prominently it features" (SDK text as mirrored by miniswift.run; Apple's page is script-rendered). The session:
ranges are "great for situations where you just want to know if an instrument is present or not"; "the closer the
value is to 1, the louder the instrument is in the mix". Apple publishes no accuracy, confidence or threshold; it
says to set `PreferPreciseDurationAndTimingKey` for accurate timing. Instruments `vocal`, `drum`, `bass`, `other`;
OS 27 on every platform.

Measured on the 373 raw results:

- Activity is sampled every 50 ms (2,205 samples at 44.1 kHz), from 0 to about 0.9. The stage 1 harness assumed
  nothing about the hop; this confirms it.
- Vocal ranges: median 7 per track (max 43), covering a median 79 percent of the duration (10th percentile 41,
  90th 96). Activity inside the ranges: median 0.73, 5th percentile 0.35, 3 percent of samples under 0.3. Outside:
  median 0.016, 95th percentile 0.19, under 0.1 percent above 0.3. So the ranges are, within rounding, activity
  at or above about 0.3 with the short dips bridged [inf]. That is the presence gate; the A22 port should read
  `ranges` directly rather than re-threshold the series, and keep the series for the overlap term.
- Vocal-free intro bars (consecutive from bar 1), lab under 0.5 versus the framework's bar mean at 0.3: at least
  8 bars on 14 versus 39 percent of tracks, at least 16 on 6 versus 17, at least 32 on 2 versus 7. Outro: 10, 5, 1
  versus 34, 21, 7. At a 0.5 cut the framework's figures rise to 47, 23 and 9 percent. The two agree within two
  bars on 211 tracks; the framework is longer by 8 or more on 96 and shorter by 8 or more on 7.
- Seventeen tracks have a bar mean under 0.15 under the framework (8 dance originals, 5 ambient, 2 pool edits);
  the lab has 3. These are the instrumentals and the sampled-vocal tracks together; the listening set separates
  them.
- Pearson r is a poor metric here: Hypnotize, No Diggity, Baby One More Time and Killing Me Softly all have both
  means high and r near zero, because there is nothing to correlate on a track that sings throughout.

What it costs: nothing beyond the session already timed at a median 11.8 s per track in the simulator; the
framework lets the caller request only the analysis types needed, so the vocal series is not separable from that
figure but adds nothing to it.

Verdict: good enough for v1's windows and overlap term, provided the thresholds are set from the listening set,
and with the sampled-vocal limitation documented in the product rather than hidden.

### 3.2 SoundAnalysis built-in classifier

`SNClassifySoundRequest(classifierIdentifier: .version1)`, iOS 15 and later, 303 labels including `singing`,
`choir_singing`, `rapping`, `humming`, `speech` and `music`; windows from 0.5 to 15 s with `overlapFactor`;
results as time ranges with confidences; no per-label accuracy published. It is a general-sound classifier, so a
rap verse over a loud beat may read as `music` alone [inf]. Verdict: the level-2 fallback to try first, because it
is in the plan and free; a 1 s window at 0.5 overlap gives bar resolution. Measure it on the listening set before
building anything else for level 2.

### 3.3 Create ML sound classifier (option, not a candidate yet)

`MLSoundClassifier` trains a small head on Apple's fixed audio feature extractor and runs through the same
SoundAnalysis API. If the built-in `singing` label fails and the listening set grows to a few hundred bars, a
two-class head trained on Christopher's own labelled bars is a half-day experiment with no licence question
[inf]. Listed as an open question, not scored below.

## 4. Candidates from the literature and the model zoos

**Singing voice detection research models.** The Schlüter and Grill ISMIR 2015 CNN (`f0k/ismir2015`, MIT,
Theano and Lasagne) and the Schlüter and Lehner ISMIR 2018 zero-mean variant (`f0k/ismir2018`, MIT) are the
reference architectures: small 2D CNNs on mel spectrograms with pitch and tempo augmentation. Reported accuracy
0.923 on Jamendo and 0.927 on RWC Pop; an independent re-implementation (Lee, Choi and Nam, ISMIR 2018) got 0.868
accuracy on Jamendo for the CNN, 0.879 for the Lehner feature set and 0.875 for the Leglaive RNN, and notes that
all three miss quiet vocals. Neither repository ships weights; the originals were trained on an in-house set. The
2018 paper shows a loudness threshold alone scores 61 percent on Jamendo, which says how biased that benchmark is.
Successors (U-Net front end plus LRCN: 0.888 Jamendo, 0.916 RWC; DAACI-VoDAn, EUSIPCO 2023, dataset CC BY-NC-SA,
no code found) are heavier and still without permissive weights. No 2024 to 2026 model with released permissive
weights turned up; the Hugging Face "voice activity detection" category is speech VAD, the wrong task. Verdict: a
research CNN is a training project, not a port, and the usable training data is tiny (Jamendo, 93 tracks) or
research-only. The shape of a future own model, not a candidate now.

**Source separation.** HTDemucs (2022): 41.4M parameters, 44.1 kHz stereo, 7.8 s segments, MUSDB18-HQ plus 800
songs, vocals SDR 8.93 dB. Repository MIT, now archived. `demucs-mlx-swift`: MIT, macOS 14 and iOS 17 minimum,
htdemucs weights about 160 MB float32, 1.07 s per 120 s of audio on an M4 Max, peak MLX allocation 4.7 GB on the
Mac, batch 1 on iOS, no iPhone or iPad timings. `htdemucs-coreml`: MIT, 200 MB fp16 or 400 MB fp32 for 10 s
segments, `.cpuAndGPU` only because "HTDemucs is not stable on the Apple Neural Engine", chunking with overlap-add.
Separation as a detection front end is the literature's standard upgrade (the U-Net front end above; the lab
README's own "A Demucs vocal stem would be the upgrade"), and per-bar vocal-stem energy against the mix is a
detector with no further model [inf]. Open-Unmix: code MIT; umxhq weights MIT on Zenodo but 6.25 dB on vocals;
umxl 7.21 dB but "only licensed for non-commercial use (CC BY-NC-SA 4.0)"; bidirectional LSTM, no Core ML port
found. Spleeter: "the code of Spleeter is MIT-licensed", nothing stated for the models, TensorFlow 1; the one Core
ML route (`fwcd/spleeter-pytorch`) leaves the STFT to the caller. BS-RoFormer (ByteDance, 2023): 72.2M parameters
for the 6-block model (10.7 dB), 93.4M for the 12-block with extra data (12.72 dB), four weeks on 16 A100s per
stem; lucidrains code MIT; the viperx weights everyone uses were "released without an explicit license", and a
public issue asking to ship them in a closed-source plug-in found no licence. Mel-Band RoFormer: Kimberley
Jensen's checkpoint is tagged MIT with an empty card; ZFTurbo's list states no licence. Verdict: HTDemucs is the one
separator with a clean licence and two Swift ports; the RoFormers separate better and cannot ship; the rest are
worse than HTDemucs on every axis. A separator is overkill for presence on the phone and right on the Mac for the
stem.

**General taggers with a singing class.** YAMNet: MobileNetV1, 3.7M weights, 69.2M multiplies per 0.96 s patch,
16 kHz, 64 mel, 521 classes including "Singing" (24), "Choir", "Rapping", "Humming", "Vocal music"; patch hop
0.48 s; balanced AudioSet mAP 0.306; Apache 2.0; an existing Core ML package (`Yehor/YAMNet-CoreML`) takes log-mel
patches, which suits an engine that owns its STFT. EfficientAT (Schmid, CP-JKU): MIT; mn04_as 0.98M parameters,
0.11 GMAC per 10 s, 43.2 mAP; mn05_as 1.43M, 44.3; mn10_as 4.88M, 0.54 GMAC, 47.1; clip-level; a 10 s clip in
under 0.25 s on a Raspberry Pi 4. No Core ML export documented; standard MobileNetV3, should convert with the mel
front end in vDSP [inf]. PANNs: code MIT, weights CC BY 4.0; Cnn14 327 MB, MobileNetV1 23.6 MB; the "framewise"
SED model (`Cnn14_DecisionLevelMax`) computes segments at 1/32 of the frame rate and upsamples, so its resolution
is 320 ms. AST: BSD-3, about 87M [inf], 10 s clips. BEATs: code MIT, checkpoint licence asked in
`microsoft/unilm#1760`, no answer. CLAP: repository CC0, `laion/larger_clap_music` card Apache 2.0, clip-level.
None of the taggers has a published singing-voice-detection number; AudioSet "Singing" is a weakly labelled 10 s
class and a tagger on 1 s windows is an extrapolation to measure [inf]. Verdict: EfficientAT mn04 or YAMNet are
the only taggers small enough to sit beside the framework; the transformers and Cnn14 are the wrong size for a
presence bit.

## 5. Comparison table

| Candidate | Licence (code / weights) | Size | Cost per 4-min track | Core ML | Frame resolution | Reported SVD accuracy | Stem | Verdict |
|---|---|---|---|---|---|---|---|---|
| Music Understanding `InstrumentActivityResult` | Apple SDK, no model licence | 0 | inside the 12 s session already paid | n/a | 50 ms series plus presence ranges | none published; this doc section 3.1 | no | **v1 signal** |
| SoundAnalysis `.version1` `singing` | Apple SDK | 0 | one pass, cheap [inf] | n/a | 0.5 to 15 s windows, overlapped | none published | no | level-2 fallback, test first |
| Create ML `MLSoundClassifier` head | Apple SDK | small | cheap | native | about 1 s windows [inf] | ours to measure | no | option if 3.2 fails |
| Schlüter 2015 / 2018 CNN | MIT code; no weights | about 1M [inf] | tiny | re-implement | 70 fps, 1.6 s context [inf] | Jamendo 0.923 orig, 0.868 re-impl; RWC 0.927 | no | needs training data; later |
| Lehner feature set + RF | method only | tiny | tiny | own code | 200 ms | Jamendo 0.879 to 0.882 | no | DSP fallback idea |
| EfficientAT mn04_as / mn10_as | MIT / MIT | 0.98M / 4.88M; 0.11 / 0.54 GMAC per 10 s | about 25 clips, seconds [inf] | convertible [inf] | clip; slide 1 s | none; AudioSet mAP 43.2 / 47.1 | no | second opinion, level 2 |
| YAMNet | Apache 2.0 / same repo | 3.7M, 69 MMAC per patch | about 500 patches, a few s [inf] | existing package | 0.96 s patch, 0.48 s hop | none; balanced mAP 0.306 | no | alternative to EfficientAT |
| PANNs Cnn14 SED / MobileNetV1 | MIT / CC BY 4.0 | 327 MB / 23.6 MB | heavy / light | existing conversion (Cnn14) | 320 ms segments upsampled | none; mAP 0.385 / 0.389 | no | no |
| AST | BSD-3 | about 87M [inf] | heavy | possible | 10 s clip | none; mAP 0.459 | no | no |
| BEATs | MIT code / weights unanswered | about 90M [inf] | heavy | untried | clip | none | no | no (licence) |
| CLAP (LAION) | CC0 repo / Apache 2.0 card | tens of M [inf] | heavy | untried | 10 s clip | none | no | no |
| HTDemucs (MLX Swift or Core ML) | MIT / none stated beyond the repo | 41.4M; 160 MB fp32, 200 MB fp16 | M4 Max 112x realtime; iOS unmeasured; GPU only | yes, two ports | sample-level stem | separation 8.93 dB vocals; stem-energy SVD unbenchmarked | **yes** | **runner-up, Mac and iPad Pro pass** |
| Open-Unmix umxhq / umxl | MIT / MIT (umxhq), CC BY-NC-SA (umxl) | not stated | LSTM, offline | no port found; MLX port exists | stem | 6.25 / 7.21 dB vocals | yes | no |
| Spleeter 2stems | MIT code / not stated | not stated | TF1 | partial (STFT outside) | stem | not stated here | yes | no |
| BS-RoFormer / Mel-RoFormer | MIT code / viperx none, Jensen MIT tag, ZFTurbo none | 72 to 93M (paper), 160 to 200M (ports) | very heavy | no | stem | 10.7 to 12.7 dB vocals | yes | no |

## 6. Licence findings (from the licence files and READMEs)

- Demucs README: "Demucs is released under the MIT license as found in the LICENSE file." Nothing separate is
  stated for the weights; the repository is archived. htdemucs-coreml: "You must comply with Demucs' MIT license
  when redistributing the resulting `.mlpackage`", attribution in `ATTRIBUTION.md` and the app's about screen.
  demucs-mlx-swift: "MIT licensed."
- Open-Unmix README: code "MIT"; for umxl, "Note, that the weights are only licensed for non-commercial use
  (CC BY-NC-SA 4.0)." Zenodo record 3370489 (UMX-HQ): MIT License.
- Spleeter README: "The code of Spleeter is MIT-licensed." No statement about the pretrained models.
- lucidrains/BS-RoFormer LICENSE: "MIT License", "Copyright (c) 2023 Phil Wang". viperx weights: "released without
  an explicit license" (kickvn MLX port card); TRvlvr/model_repo has no LICENSE file and issue #3 asks for
  permission to redistribute. KimberleyJSN/melbandroformer: "License: mit" in the card metadata, README empty.
- EfficientAT LICENSE: "MIT License", "Copyright (c) 2022 Florian Schmid".
- tensorflow/models LICENSE (YAMNet): "Apache License, Version 2.0, January 2004".
- audioset_tagging_cnn LICENSE.MIT: "The MIT License", "Copyright (c) 2018-2020 Qiuqiang Kong". Zenodo 3987831
  (weights): "Creative Commons Attribution 4.0 International".
- YuanGongND/ast LICENSE: "BSD 3-Clause License", "Copyright (c) 2021, Yuan Gong".
- microsoft/unilm beats README: "This project is licensed under the license found in the LICENSE file in the root
  directory of this source tree"; issue #1760 asking whether that covers the checkpoints has no reply.
- LAION-AI/CLAP LICENSE: "CC0 1.0 Universal"; `laion/larger_clap_music` card: "License: apache-2.0".
- f0k/ismir2015 and f0k/ismir2018: "MIT license" in the repository sidebar; no weights distributed.
- Essentia Discogs-EffNet voice head (the lab's detector): CC BY-NC-SA per `mixer/README.md` and track A; cannot
  ship, and the 373 stored per-bar probabilities are lab fixtures only.
- Datasets for evaluation: Jamendo SVD (Ramona) is CC-licensed music with annotations, used by every paper above;
  DAACI-VoDAn is CC BY-NC-SA, research only, by request; MUSDB18-HQ is research use. All three are fine as lab
  benchmarks and none is training data for a shipped model without a licence check [inf, not legal advice].

## 7. Test plan

**References.** (1) The lab's 373 per-bar `vocal_prob`, used asymmetrically: a bar under 0.2 is a reliable "no
vocal" (an over-reporting head has strong negatives), a bar over 0.9 a probable vocal, the middle no reference.
(2) A listening set of about 40 tracks, first and last 48 bars, labelled by Christopher per bar in three classes:
sung or rapped; sampled, chopped or vocoded; none. Drawn from this session's lists: where the framework hears
vocals earlier than the lab (Disturbia, Milkshake, Baby Got Back, Padam Padam, Disease, Get It On, No Diggity),
the sampled-vocal group (Call on Me both cuts, Robot Rock, The Bomb!, We Are Your Friends), the soft or reverbed
group (Fable Dream Radio, Haunted, It Feels So Good, Halcyon), instrumentals as controls (Children, Barber's Adagio,
X-Files), and 20 random tracks stratified by `kind`; a spreadsheet of bar numbers with both detectors' values
hidden. (3) HTDemucs vocal-stem energy per bar on the Mac over the whole pool, the stem-based control and a
candidate itself: stem energy in dB against the mix, thresholded on the listening set.

**Metrics, per candidate and threshold** (sweep 0.2 to 0.6 on the framework series plus the `ranges` view as its
own setting; window length for SoundAnalysis; the "Singing" score for the taggers): first-vocal-bar error (median
and share within 2); vocal-free intro and outro bars within 2; bar-level precision and recall split by the three
classes so the sampled-vocal behaviour is reported, not averaged away; agreement with the lab's strong negatives
and positives; the share of the pool whose mix-in window size (8, 16, 32) changes; the share of pairs whose vocal
term crosses the 0.6 gate. No Pearson r.

**Procedure.** Extend `mixer/bench_mu.py` with a `vocal` subcommand reading the labels and each candidate's series
on the lab's bar edges (this session's per-bar code is the seed). The framework comes from the existing `mu_raw`;
SoundAnalysis and the tagger from `tools/mubench` in the simulator; HTDemucs from the lab venv on the Mac
(installing it is a lab change, not a shipped one). Listen to the worst ten per candidate before trusting a number.

**Pass marks for v1** [inf]: framework at the chosen threshold, first vocal bar within two bars on 90 percent of
the listening set and intro length within two bars on 85 percent; sampled-vocal recall reported but not gated.
If the framework passes, the taggers are not built for level 1. If it fails on the soft-vocal group, EfficientAT
mn04 is the first thing to add, because it is the smallest model with a singing class and a clean licence.

## 8. Open questions

1. What does the vocal slider mean when the vocal is a chopped sample (Call on Me)? Track C's dimension 9 assumed
   one kind of vocal. If "clash" includes sampled hooks, the framework needs a companion (stem energy on the Mac,
   or a tagger) and the crate should carry the class, not only a probability.
2. Does `ranges` apply hysteresis or a minimum duration? The data say "about 0.3 with dips bridged"; the SDK does
   not say. Measure the shortest range and gap across the pool.
3. Rap, spoken intros and crowd vocals (Haunted, Baby Got Back): the listening set answers it; if rap reads low,
   the SoundAnalysis `rapping` label is a cheap cross-check.
4. HTDemucs on a current iPad Pro and an iPhone: time, memory and thermal through the MLX Swift example app.
   Nothing is published; both ports run iOS at batch 1.
5. Training an own small CNN later: Jamendo is tiny and the bigger sets are non-commercial, so Christopher's
   labelled bars are the only clean training source. Keep and grow the listening set for that reason.
6. Create ML head (3.3): worth a half-day only if 3.1 fails the pass mark.

## 9. Sources

Apple: Music Understanding SDK text as mirrored at https://miniswift.run/whats-new/musicunderstanding/ ;
WWDC26 session 253 transcript
https://github.com/pixelfolio/WWDC26-Transcripts/blob/main/wwdc2026-253%20-%20Meet%20the%20Music%20Understanding%20framework.md ;
second sources https://blakecrosley.com/blog/music-understanding-framework-ios-27 ,
https://www.theswift.dev/posts/build-music-aware-apps-with-music-understanding/ . SoundAnalysis: WWDC21 session
10036 https://developer.apple.com/videos/play/wwdc2021/10036/ ; built-in label list
https://zenn.dev/shu223/articles/soundanalysis-builtin ; file analysis walkthrough
https://www.createwithswift.com/identifying-individual-sounds-in-an-audio-file/ ;
https://www.swiftjectivec.com/sound-analysis-framework-built-in-model/ ; Create ML
https://developer.apple.com/documentation/createml/mlsoundclassifier .

Singing voice detection: Schlüter and Grill, ISMIR 2015, code https://github.com/f0k/ismir2015 ; Schlüter and
Lehner, ISMIR 2018, https://www.ofai.at/~jan.schlueter/pubs/2018_ismir.pdf , code https://github.com/f0k/ismir2018 ;
Schlüter, ISMIR 2016, https://archives.ismir.net/ismir2016/paper/000315.pdf ; Lee, Choi and Nam, "Revisiting
singing voice detection", ISMIR 2018, https://arxiv.org/abs/1806.01180 ; Lehner et al., EUSIPCO 2015,
https://eurasip.org/Proceedings/Eusipco/Eusipco2015/papers/1570097385.pdf ; Sun et al., separation front end plus
LRCN, https://arxiv.org/abs/2004.04040 ; survey https://www.mdpi.com/1099-4300/24/1/114 ; DAACI-VoDAn,
https://eurasip.org/Proceedings/Eusipco/Eusipco2023/pdfs/0000136.pdf and https://zenodo.org/records/8017757 .

Separation: Demucs https://github.com/facebookresearch/demucs ; HTDemucs paper https://arxiv.org/abs/2211.08553 ;
https://github.com/ssmall256/demucs-mlx-swift ; https://github.com/dexxdean/htdemucs-coreml ; Open-Unmix
https://github.com/sigsep/open-unmix-pytorch , https://sigsep.github.io/open-unmix/details.html , UMX-HQ weights
https://zenodo.org/records/3370489 ; Spleeter https://github.com/deezer/spleeter ,
https://github.com/fwcd/spleeter-pytorch ; BS-RoFormer paper https://arxiv.org/abs/2309.02612 , code
https://github.com/lucidrains/BS-RoFormer , weights question https://github.com/TRvlvr/model_repo/issues/3 ,
https://huggingface.co/kickvn/bs-roformer-viperx-mlx ; Mel-Band RoFormer https://arxiv.org/abs/2310.01809 ,
https://huggingface.co/KimberleyJSN/melbandroformer ; ZFTurbo model list
https://github.com/ZFTurbo/Music-Source-Separation-Training/blob/main/docs/pretrained_models.md .

Taggers: YAMNet https://github.com/tensorflow/models/blob/master/research/audioset/yamnet/README.md , class map
https://github.com/tensorflow/models/blob/master/research/audioset/yamnet/yamnet_class_map.csv , licence
https://github.com/tensorflow/models/blob/master/LICENSE , Core ML package https://huggingface.co/Yehor/YAMNet-CoreML ,
RFFT conversion issue https://github.com/apple/coremltools/issues/1529 ; EfficientAT https://github.com/fschmid56/EfficientAT ,
paper https://arxiv.org/abs/2211.04772 , on-device evaluation https://arxiv.org/abs/2509.14049 ; PANNs
https://github.com/qiuqiangkong/audioset_tagging_cnn , weights https://zenodo.org/records/3987831 , SED model code
https://github.com/qiuqiangkong/audioset_tagging_cnn/blob/master/pytorch/models.py , paper
https://arxiv.org/abs/1912.10211 ; AST https://github.com/YuanGongND/ast ; BEATs
https://github.com/microsoft/unilm/blob/master/beats/README.md , https://github.com/microsoft/unilm/issues/1760 ;
CLAP https://github.com/LAION-AI/CLAP , https://huggingface.co/laion/larger_clap_music .

Local: `docs/architecture/stage1-results.md`, `docs/architecture/analysis-port-plan.md`, `mixer/README.md`,
`mixer/bench_mu.py`, `mixer/mu_bench.tsv`, `mixer/mu_raw/*.mu.json` (373 files, not committed),
`mixer/features/*.json`, `docs/research/a-on-device-analysis.md`, `docs/research/c-dj-preferences.md`,
`docs/product/00-decisions.md`.
