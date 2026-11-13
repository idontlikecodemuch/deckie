# Check-in: the own-key trial (branch `trial/own-key`)

Newest entry first. Scores are percent of clips on the 1,270 GiantSteps-MTG-key clips Apple read (386 major, 884
minor). Exact = key right. Home note = home note right, whatever the mode. Mode given home = of the clips whose home
note is right, the share with the right mode. The bar (D16) = exact within five points of Apple on each half:
36.5 on the major half, 70.6 on the minor half.

## Nov 13, 2026, 22:40 UTC. Phase 1 done; phase 2 first pass; phase 3 training

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
| B's home note + A's mode (letter X's first ask) | 57.6 | 54.4 | 59.3 | 72.4 | 77.2 | 70.4 | 79.9 | 70.5 | 84.2 |
| B's home note + a 12-number trained mode rule (leans minor) | 60.0 | 46.9 | 66.0 | 72.4 | 77.2 | 70.4 | 83.1 | 60.7 | 93.7 |
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
