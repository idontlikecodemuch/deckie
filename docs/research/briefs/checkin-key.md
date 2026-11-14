# Check-in: the own-key trial (branch `trial/own-key`)

Newest entry first. Scores are percent of clips on the 1,270 GiantSteps-MTG-key clips Apple read (386 major, 884
minor). Exact = key right. Home note = home note right, whatever the mode. Mode given home = of the clips whose home
note is right, the share with the right mode. The bar (D16) = exact within five points of Apple on each half:
36.5 on the major half, 70.6 on the minor half.

## Nov 14, 2026, 00:30 UTC. Complete

All four phases are done and pushed. The letter is `docs/research/x2-own-key-trial.md`; the commands are in
`mixer/keytrial/README.md`. The numbers are those of the entry below. One addition since: the trained model with
three answers and no fitted threshold (a key when it is more likely than not, the home note alone when only the home
note is, "not sure" otherwise) shows a key on 70.8 percent of MTG songs and is right on 76.4 percent of them, against
the untrained reader's 70.4 percent shown and 64.8 right.

**Nothing further is running. The owner's calls:** which of the letter's options to take (my recommendation: ship
the untrained three-answer reader, commission the labelled set, and rule that the bar is precision of the keys shown
against Apple on the same songs).

## Nov 14, 2026, 00:25 UTC. Phase 3 done: a trained model of our own equals Apple (evaluation only)

**Done.** The small convolutional model trained on five artist-grouped folds (each clip scored by a model that never
saw it or its artist), once on MTG for the two GiantSteps sets, and once the other way; learned profiles (49
numbers) as the smallest trained reader; precision against coverage, calibration and the four measures for all of
them. Letter `docs/research/x2-own-key-trial.md` is drafted with every table.

**Precision against coverage, MTG, the 1,270 clips Apple read** (key right among the songs shown; "Apple" = Apple
on those same songs):

| Songs shown | Nothing trained (B's home note, A's mode) | Apple | Learned profiles, 49 numbers | Apple | Trained model | Apple |
|---:|---:|---:|---:|---:|---:|---:|
| 100 % | 57.8 | 65.2 | 62.7 | 65.2 | **65.9** | 65.2 |
| 90 % | 60.3 | 67.0 | 65.8 | 67.9 | 70.5 | 68.8 |
| 80 % | 62.9 | 68.3 | 67.3 | 69.2 | **74.5** | 71.6 |
| 70 % | 62.8 | 68.6 | 69.7 | 71.0 | 76.7 | 74.7 |
| 60 % | 65.9 | 71.1 | 72.7 | 73.2 | 79.9 | 77.3 |
| 50 % | 67.7 | 71.2 | 73.1 | 74.2 | 82.4 | 81.3 |
| 40 % | 71.7 | 73.0 | 77.0 | 76.6 | 84.8 | 83.3 |

Outside sets, trained on MTG only (key right / within one wheel step): GiantSteps+ 82.9 / 91.2 with every song shown,
92.2 / 96.5 at 80 percent; GiantSteps Key (604) 68.7 / 81.8 and 74.9 / 86.7. Published on the 604: rekordbox 3 71.9,
the madmom network 67.9, Mixed In Key 7 67.2, KeyFinder 45.4.

| Reader (MTG, 1,270) | Exact: all | major | minor | Home note: all | major | minor | Mode given home: major | minor |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Apple | 65.2 | 41.5 | 75.6 | 76.4 | 70.7 | 78.8 | 58.6 | 95.8 |
| The bar as written | | 36.5 | 70.6 | | | | | |
| Nothing trained: B's home note + A's mode | 57.8 | 54.4 | 59.3 | 72.4 | 77.2 | 70.4 | 70.5 | 84.2 |
| Learned profiles, 49 numbers (evaluation only) | 62.7 | 35.8 | 74.4 | 74.5 | 71.0 | 76.0 | 50.4 | 97.9 |
| the same, major and minor weighed equally | 59.8 | 56.5 | 61.2 | 73.6 | 76.9 | 72.2 | 73.4 | 84.8 |
| **Trained model, 12 shifts averaged (evaluation only)** | **65.9** | **44.0** | **75.5** | 77.0 | 75.4 | 77.7 | 58.4 | 97.1 |
| Trained model, single read | 63.9 | 42.0 | 73.5 | 74.6 | 72.3 | 75.7 | 58.1 | 97.2 |

**What it says.**
- **The bar as written is passed** by the trained model on artists it never saw (major 44.0 against 36.5, minor
  75.5 against 70.6). Song for song it is level with Apple (ahead on 104 clips, behind on 95, p 0.57). Per fold:
  67.8, 63.1, 64.3, 67.5, 65.5; one training run each, so read it as 65.9 give or take 3.
- **When it may decline it is ahead of Apple on the same songs**: 74.5 against 71.6 at 80 percent shown (p 0.01).
  Its confidence can be trusted: stated probability and observed accuracy differ by 3 points on average; when it
  says 90 percent or more it is right 94 percent of the time.
- **It is small and cheap**: 236,006 numbers, 0.95 MB, 0.05 s a five-minute song on one CPU thread plus 0.35 s for
  its spectrogram.
- **It wins the way Apple wins**: a better home note than ours (77.0 against 72.4) and a lean toward minor (58
  percent of major songs' modes right, 97 of minor). It hears the mode no better than the 80 percent ceiling of
  phase 2. Trained on the 85-percent-minor 604-clip set instead, it reads 3.9 percent of MTG's major songs right:
  the lean is copied from the training music. With major and minor weighed equally the 49-number profiles score
  59.8 and fail the bar as written by 14 points on the minor half while reading 56 percent of major songs right
  instead of 36.
- **Forty-nine learned numbers get most of the way** (62.7; level with Apple song for song at every share shown) and
  stop improving at about 400 labelled songs.
- **None of it can ship**: trained on CC BY-SA labels and audio that is not ours.

**Doing next.** Phase 4 is written into the letter (the Swift port of the untrained three-answer reader: 5 to 6
days; the data that could legally back weights; what a commissioned set needs: 400 to 600 songs to fit, 300 to
score, mixed styles, a third in major keys). Final read-through, then the branch is complete.

**Carry on; one ruling would help.** The direction holds and the result is better than letter T's estimate. The
ruling: D16's bar as written rewards leaning minor (it is how Apple and the trained readers pass it). If the bar
stays as written, a trained reader should keep the lean; if it becomes "of the keys shown, as many right as Apple
on the same songs" (my recommendation), the reader can be fitted without the lean and judged on what it shows.

## Nov 13, 2026, 22:45 UTC. Owner's direction taken up: precision against coverage, untrained readers first

**Direction received** (relayed by the main session): the reader must stand on its own, work as well as the tools DJs
use or better, and fail gracefully: show a key when it is reliable, skip it when not. So the main measure from here
is **precision against coverage**: of the songs that get a key, how many are right, and what share of songs get one.
"Mode open" and "not sure" are both allowed answers. A method with no learned weights is preferred when two are close.

**First precision-against-coverage table.** The best reader with nothing trained: home note from row B, mode from
row A, clips ordered by a confidence that fits nothing (how many of the three readers name the same key, plus how
many thirds of the song name it, 0 to 6; ties by margin). MTG = the 1,270 clips Apple read; GiantSteps+ = 468
single-key clips our profiles were not made from; GiantSteps Key = the 604 clips with published tool scores.

| Songs shown a key | MTG: key right | within one wheel step | home note right | Apple right on the same songs | GiantSteps+: key right | within one step | GiantSteps Key: key right | within one step |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 100 % | 57.8 | 71.7 | 72.4 | 65.2 | 76.9 | 86.5 | 60.9 | 76.8 |
| 90 % | 60.3 | 73.8 | 74.1 | 67.0 | 81.5 | 90.3 | 64.0 | 79.0 |
| 80 % | 62.9 | 75.9 | 77.3 | 68.3 | 84.5 | 92.2 | 67.3 | 81.0 |
| 70 % | 62.8 | 77.1 | 75.7 | 68.6 | 87.8 | 95.4 | 69.5 | 83.5 |
| 60 % | 65.9 | 78.2 | 79.4 | 71.1 | 89.3 | 97.2 | 72.4 | 86.7 |
| 50 % | 67.7 | 81.3 | 77.8 | 71.2 | 93.2 | 99.1 | 74.8 | 87.4 |
| 40 % | 71.7 | 81.1 | 82.9 | 73.0 | 93.0 | 99.5 | 76.4 | 88.0 |
| 30 % | 75.3 | 85.3 | 82.7 | 77.4 | 92.9 | 99.3 | 76.2 | 89.5 |

Against the tools (published exact rates; letter X):
- **MTG.** Shown keys are as right as Apple's overall rate (65.2) and Mixed In Key 7's (65.7, Faraldo 2017, near the
  same clips) when **60 percent** of songs are shown, and clearly better (whole 95 percent interval above) at 40
  percent. But Apple is also better on those same songs (71.1 at 60 percent), so on this set the untrained reader is
  never ahead of Apple song for song; on the held-out folds alone it is level with Apple from 80 percent down.
  KeyFinder (54.8) is matched with every song shown.
- **GiantSteps Key (604).** As right as Mixed In Key 7 (67.2) at **80 percent** shown, as right as rekordbox 3 (71.9)
  at **60 percent**; KeyFinder (45.4) is beaten with every song shown.
- **GiantSteps+**, the clean set: 76.9 with every song shown, 84.5 at 80 percent, 93 at 50 percent. No tool has a
  verified published score on it, and Apple cannot be run on it from this session.

**Is the confidence trustworthy?** Yes, in order: every signal sorts right from wrong on all three sets, and the
selection and held-out folds give the same shape. On MTG, a key that all three readers and all three sections agree
on (38 percent of songs) is right 72 percent of the time; with 3 of 6 or fewer, 43 percent or less. On GiantSteps+
the top level (50 percent of songs) is right 93 percent of the time. The margin alone is the weakest signal and says
nothing about the home note (letter T saw the same).

**Three answers, no threshold at all** (a key when rows A and B agree on home note and mode; "home note, mode open"
when they agree on the home note only; "not sure" otherwise):

| Set | A key: share, right | Mode open: share, home note right | Not sure: share |
|---|---|---|---|
| MTG | 70.4 %, 64.8 (within one step 76.6) | 11.7 %, 79.2 | 17.9 % |
| GiantSteps+ | 76.1 %, 85.4 (within one step 92.1) | 4.7 %, 81.8 | 19.2 % |
| GiantSteps Key | 73.8 %, 69.1 (within one step 82.7) | 5.5 %, 60.6 | 20.7 % |

**Other results since the last entry** (all in `mixer/keytrial/`, scripts `kt_x.py`, `kt_pc.py`):
- **Trade-off curve** (letter X ask 1): with row B's home note, moving the mode threshold from "always major" to
  "always minor" never passes the bar as written; the minor half tops out at 70.4. At the balanced point both halves
  are 58.
- **The published multi-profile method** (ask 2; second minor template, gate, 200 Hz cut): its second minor template
  is what matters. On our chroma without the 200 Hz cut it scores 56.2 exact on MTG (the set its profiles came from)
  and 74.4 on GiantSteps+; with the cut it falls to 45.9 and 63.0 (my stand-in for the filter drops the bass peaks
  outright; the published filter is gentler, so this part is not a faithful replication). Its steps on row B's
  chroma: 59.3 and 77.1. It buys minor songs by leaning minor (major half 42 on MTG), like the trained mode rule.
- **GiantSteps+ is much kinder than MTG to every reader** (row B 75.9 exact against 55.6): the MTG scores are not
  flattered by the profiles' origin; MTG is simply the harder, less minor set (70 percent minor against 88).
- **Letter X's arithmetic re-derived from the per-clip results**: its mode-right table matches to the point (3f
  86.3 / 61.1, A 72.2 / 84.6, B 81.9 / 74.3, Apple 58.6 / 95.8); its minor-gap split matches (A: 19.2 short, of which
  parallel 7.0, relative 4.8, fifth 2.3, other 5.2; B: 23.3, of which 14.8, 4.3, minus 1.0, 5.2); "within one step"
  on all 1,270 is Apple 78.3, A 72.0, B 69.0 (letter X's 81 for Apple was the confident clips only); B's home note
  with A's mode measures 57.8, inside its 57 to 59 estimate.

| Reader (MTG, 1,270) | Exact: all | major | minor | Home note: all | major | minor | Mode given home: major | minor |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Apple | 65.2 | 41.5 | 75.6 | 76.4 | 70.7 | 78.8 | 58.6 | 95.8 |
| The bar as written | | 36.5 | 70.6 | | | | | |
| B's home note + A's mode (nothing trained) | 57.8 | 54.4 | 59.3 | 72.4 | 77.2 | 70.4 | 70.5 | 84.2 |
| Multi-profile steps on row B's chroma (nothing trained) | 59.3 | 41.7 | 67.0 | 72.3 | 77.2 | 70.1 | 54.0 | 95.5 |
| B's home note + trained 12-number mode rule (evaluation only) | 60.2 | 46.9 | 66.0 | 72.4 | 77.2 | 70.4 | 60.7 | 93.7 |

**Doing next.** The trained model (phase 3) is mid-training: the first of five folds is at epoch 108 of 120, with 64 percent exact
on its validation artists at best; the cross-set model (train on MTG, score both GiantSteps sets) runs beside it. About two
hours of CPU remain. When it lands: the same precision-against-coverage tables for it, its calibration, agreement
with the untrained readers as a confidence, then phase 4 and the letter.

**Carry on.** For the owner, in one line: with nothing trained, Deckie can today show a key on about 60 to 70 percent
of dance songs at the accuracy of Mixed In Key 7 and Apple's overall rate, and say "not sure" on the rest; whether
that share can rise depends on the trained model's result.

## Nov 13, 2026, 22:33 UTC. Phase 1 done; phase 2 first pass; phase 3 training

**Done.**
- Bench built in `mixer/keytrial/`. Fetched for evaluation only, nothing committed: GiantSteps-MTG-key (Zenodo
  1101082, 1,486 clips, 2.13 GB, labels CC BY-SA 4.0), GiantSteps+ (Zenodo 1095691, 600 clips, 856 MB, labels CC
  BY-SA 4.0), GiantSteps Key (604 clips, 834 MB from the JKU mirror, all checksums matched, no licence stated).
- Letter R's three readers (3f, A, B) re-run from my own decode: **the same key as letter R's sheets on 1,275 of
  1,275 clips, all three**, and every figure in its tables to the decimal. The bench can be trusted.
- Protocol fixed: five folds grouped by artist and remixer (1,269 groups on MTG); folds 3 and 4 are the held-out
  part for any choice between untrained rules; trained rules are scored only on the fold they never saw.
- Phase 2 first pass: 46 mode rules scored with the true home note given, and with row B's and row A's.
- Letter X read and merged (see "Next").

| Reader | Exact: all | major | minor | Home note: all | major | minor | Mode given home: all | major | minor |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Apple | 65.2 | 41.5 | 75.6 | 76.4 | 70.7 | 78.8 | 85.4 | 58.6 | 95.8 |
| **The bar** | | **36.5** | **70.6** | | | | | | |
| 3f | 47.6 | 60.6 | 41.9 | 69.1 | 70.2 | 68.6 | 68.9 | 86.3 | 61.1 |
| A (harmonic discount) | 55.6 | 53.9 | 56.3 | 69.1 | 74.6 | 66.6 | 80.5 | 72.2 | 84.6 |
| B (note transcription) | 55.6 | 63.2 | 52.3 | 72.4 | 77.2 | 70.4 | 76.7 | 81.9 | 74.3 |
| B's home note + A's mode (letter X's first ask) | 57.8 | 54.4 | 59.3 | 72.4 | 77.2 | 70.4 | 79.8 | 70.5 | 84.2 |
| B's home note + a 12-number trained mode rule (leans minor) | 60.2 | 46.9 | 66.0 | 72.4 | 77.2 | 70.4 | 83.1 | 60.7 | 93.7 |
| B's home note + a perfect mode (the limit) | 72.4 | 77.2 | 70.4 | 72.4 | 77.2 | 70.4 | 100 | 100 | 100 |

**What the numbers say so far.**
- **The mode alone cannot meet the bar as written.** Even a perfect mode on row B's home note gives 70.4 on the
  minor half, against a bar of 70.6. Our home note on minor songs (66.6 to 70.4) is below Apple's (78.8). The home
  note is "mostly found" three times in four, and that is not enough for this bar.
- **With the true home note given, nothing I tried names the mode better than about 80 percent when major and minor
  count equally.** The plain profile match on the overtone-cleaned chroma already sits there (rows A and B: 79.0 and
  78.6). Reading the third, sixth and seventh from the bass line alone (64 to 68), from the melody register alone (74
  to 78), only where the harmony is stable (72 to 77), from the chord on the home note over time (69), or only above
  the home note in the bass (69 to 75) are all **worse**. Small trained rules reach 78 to 80: no better at hearing
  the mode, they only choose where to lean (61 major / 95 minor at their natural setting).
- Apple by the same measure: 77 (58.6 major / 95.8 minor). So on the mode alone our readers are level with Apple;
  Apple's minor-half lead is its lean plus a better home note. This confirms letter X's arithmetic from the per-clip
  results.

**Next, in this order.**
1. Phase 3 is already training (five artist-grouped folds, CPU only, about 20 minutes a fold): it is the only thing
   on the table that can move the home note. First fold's validation exact is 60.7 at a third of the way.
2. Letter X's asks, taken up in this order: (i) B's home note with A's mode (done, row above: +2.0 exact, held-out
   gained 31 lost 17, p 0.06) and the major-against-minor trade-off curve; (ii) the mode asked only where the bass
   sits on the home note (done: worse, 69 to 75 balanced); (iii) an open mode, as coverage against precision;
   (iv) every result on four measures side by side (exact per half, mean of the halves, within one wheel step,
   precision of shown keys when abstaining); (v) scoring on GiantSteps+ (fetched; Apple cannot be run on it from
   here, so the bar itself stays on MTG); (vi) Faraldo's full multi-profile method, if its minor2 and amodal
   numbers can be read.
3. Phase 4 and the letter.

**Carry on.** One thing for the owner to know now: under the bar as written, "settle the mode alone" cannot pass,
whatever the mode rule. Passing needs a better home note on minor songs (the trained model's job) or a ruling on
what the bar measures (letter X, option 3).
