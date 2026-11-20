# A quicker change of name after a hard cut: what was built and what the test showed

Branch `recog/faster`. This letter follows `faster-listening-proposals.md` (the two proposals), and the owner's
choice: build both, test each, then test them together. Nothing here changes a default: every listener below is off
unless `--listener` (or `ListenSettings(.a)` and so on) asks for it.

**Words used.** The *listener* gives a *reading* once a second: a song, the place in it and how sure. A *hard cut*
is one song stopping and another starting at once. *Back and forth* is a DJ cutting between two decks in turn, both
playing on. A *jump* is the name changing to another song while the same song plays. A *made song* is one built for
this test to share a passage with a song of the crate (section 3). The *dev half* is where anything was chosen; the
*held-out half* was run once, at the end. *p90* is the 90th percentile: nine in ten are at or under it.

## 1. The answer

- **Speed: the target is met.** After a clean hard cut the right name is at the listener in **3 s with A** (9 in
  10 by 3 s) and **2 s with A+B** (all by 3 s), against **5 s for `main`**. In a room and under a quiet crowd it is
  3 to 4 s against 5. Quick returns and back and forth at 12, 8 and 5 s gain the same 2 s. With the crowd as loud
  as the music no listener is quick, and in two such cells of six clips A is slower than `main` (section 8).
- **Fidelity: not proven to be `main`'s, and by the strict mark it is not.** On every count but one, A, B and A+B
  equal `main`: wrong songs on ordinary clips (4 = 4), misses (29 = 29), names for songs not in the crate or for
  noise (3 = 3), and long play (no jump in any listener). The one count where they do not is **songs that share a
  passage**: `main` named the made song in 5 clips of 90, **A in 7, B in 8, A+B in 9**; jumps in a song were 11,
  14, 16 and 16. All of the extra is in those clips, and A's extra two are one mash-up heard in two conditions.
- **For comparison, the fast setting** named the made song in **35** clips and jumped **59** times: the test sees
  the fault it was built to see, and A and B remove most of it, but not all.
- **Recommended: A** (or A+B if the extra second matters more than the extra clip), *not merged until the owner's
  library has been run* (section 9). On this set A is the listener whose difference from `main` is smallest; it is
  within what 392 clips can tell apart (5 against 7), but the pass mark was "no more", and it is more.

## 2. What was built

| `--listener` | What it does |
|---|---|
| `main` | The listener on `main`, reading for reading (a test holds it). |
| `fast` | The fast setting of W5 (`recog/fast`), its listener only, on `main`'s index. |
| `a` | **Proposal A.** The newest 4 s are searched every second while a song is followed. Another song found there is a *challenger*: it is fitted against the followed song on the same 4 s, and takes over only when it is sure (3.0) **and its score is more than twice the followed song's**. After a failed check, searches look only at the sound since. |
| `b` | **Proposal B.** The followed song's own points are watched, point by point, for the moment they stop pairing (a CUSUM test, Page 1954). After an alarm the crate is searched every second in the sound since that moment only, from 2 s of it. |
| `ab` | Both. |

**Changed from the proposals, and why.**

1. **A's blend rule is gone.** The proposal also let a challenger take over when it was ahead on two readings in a
   row. Inside a passage two songs share, both fit the same points, so "ahead" is a coin toss; in a unit test made
   for exactly that it named the other song. A now needs the clear lead every time.
2. **No search into the sound before an early switch, for 8 s.** On trial clips, after A switched, `main`'s own
   8 s search (still mostly the old song) named the old song back a second later. A, B and A+B now leave the sound
   before the switch out of the searches for one window (8 s).
3. **Chosen on the dev half:** A's margin 2 (from 1.5, 2 and 3: 3 a second slower, 1.5 and 2 alike, so the larger);
   B's first look at 2 s after the alarm, not 3 (half a second sooner, no more wrong names on dev).
4. **Two faults in B found after the held-out run** (section 6). They are fixed on the branch; the held-out
   figures for B and A+B are for the version *before* the fix, and the fix is measured on dev only.

## 3. The test

**Songs** (all outside the repository, fetched by `core/Tools/recognition-bench/fetch_data.py`; none is committed):

| Source | Songs | Kind | Licences (largest shares) |
|---|---|---|---|
| Internet Archive netlabels, dance subjects | 1,400 | full songs, one a release | CC BY-NC-ND 3.0 (28 %), BY-NC-SA 3.0 (16 %), BY-NC-ND 4.0, public domain, others |
| Internet Archive netlabels, other subjects | 700 | full songs, one a release | CC BY-NC-ND 3.0 (44 %), BY-NC-SA 3.0 (18 %), others |
| Internet Archive netlabels, **remix releases** | 1,501 | full songs, **all of a release** (304 releases: originals with their remixes) | CC BY-NC-ND 3.0 (28 %), BY-NC-SA 3.0 (21 %), BY-NC 4.0, BY 3.0, others |
| GiantSteps+ (Zenodo 1095691) | 598 | two-minute excerpts | annotations CC BY-SA 4.0; audio commercial previews, internal evaluation only |
| OpenSLR 28 rooms, DEMAND crowds | — | measured rooms; cafeteria, restaurant and station noise | Apache 2.0; CC BY 4.0 |

ccMixter (a remix site) was tried first; its server refuses direct downloads, and that was left alone.

**Split** by the existing hash of each song's id: 417 songs "not in the crate", the rest half dev, half held-out.
**Made songs**: 60 from each half (20 each: another song with 4 to 8 s of the source cut in; laid over another song at
equal level for 8 to 16 s; an edit with its stretches reordered), added to the crate. The index's own search for
copies already merges 37 of the 40 edits with their source, so edits test little; the samples and mash-ups are the
real test (each is merged with the song it was built on, not with the one it borrows from).

**The crate index**: 3,898 songs (four times the 969 before), 409 MB on disk (105 KB a song), 208 MB of table and
200 MB of points; built in 14 min on one core, almost all of it the search for copies. A reading of `main` took
119 ms at the median on this shared 4-core machine (W5 measured 55 ms on 969 songs).

**Clips** (`switch_clips.py`, seeded): hard cuts (20 s + 20 s, any order, half the pairs of one style); quick returns
(20 s A, 6 s B, 14 s A); back and forth at 12, 8, 5 and 3 s for a minute; long play (120 s); a song through a passage
a made song shares with it (60 s); songs not in the crate; noise alone and after a song; fader at ±2, 6, 8 %,
turntable or key held. Conditions: clean, room, room with crowd 10 dB under, crowd at equal level, small speaker
with crowd at equal level (back and forth and shared passages: the first three). Dev: 254 clips, 3.9 h of sound;
held-out: **392 clips, 5.9 h**. That is far fewer than the 3,000 cuts the proposal named: five listeners over that
many would take this machine about two days. Differences of one or two clips in a cell are not evidence.

## 4. Held-out results

Cells: median / p90 seconds from the cut to the right name at the listener · share named by 3 s · by 5 s · share
of turns never named in their own turn. 99 in p90 stands for "never named".

**Hard cut** (seconds from the cut to the right name; p90 counts a turn never named as 99)

| Condition | main | fast | a | b | ab |
|---|---|---|---|---|---|
| clean | 5 / 5 · 7% · 100% | 2 / 3 · 100% · 100% | 3 / 3 · 93% · 100% | 2 / 5 · 64% · 100% | 2 / 3 · 100% · 100% |
| room | 5 / 9 · 7% · 71% | 4 / 9 · 50% · 64% | 4 / 9 · 50% · 64% | 4 / 9 · 50% · 71% | 4 / 9 · 50% · 64% |
| crowd 10 dB under | 5 / 7 · 21% · 57% | 3 / 7 · 64% · 71% | 3 / 7 · 57% · 71% | 3 / 6 · 57% · 79% | 3 / 6 · 64% · 86% |
| crowd equal | 7 / 99 · 14% · 21% · 29% not | 6 / 99 · 14% · 29% · 29% not | 6 / 99 · 14% · 29% · 29% not | 4 / 99 · 29% · 50% · 29% not | 4 / 99 · 29% · 50% · 29% not |
| small speaker, crowd equal | 5 / 7 · 7% · 64% | 4 / 7 · 36% · 79% | 4 / 7 · 36% · 79% | 4 / 7 · 29% · 71% | 4 / 7 · 43% · 79% |

**Hard cut, each song at its own fader setting** (seconds from the cut to the right name; p90 counts a turn never named as 99)

| Condition | main | fast | a | b | ab |
|---|---|---|---|---|---|
| clean | 5 / 6 · 0% · 67% | 2 / 3 · 100% · 100% | 3 / 4 · 67% · 100% | 2 / 4 · 83% · 100% | 2 / 3 · 100% · 100% |
| room | 5 / 6 · 17% · 83% | 3 / 3 · 100% · 100% | 3 / 4 · 83% · 100% | 3 / 4 · 67% · 100% | 3 / 3 · 100% · 100% |
| crowd 10 dB under | 6 / 8 · 0% · 50% | 6 / 7 · 33% · 50% | 5 / 7 · 33% · 67% | 6 / 8 · 17% · 50% | 6 / 8 · 17% · 50% |
| crowd equal | 6 / 59 · 0% · 17% · 17% not | 8 / 59 · 0% · 17% · 17% not | 8 / 59 · 0% · 17% · 17% not | 7 / 59 · 0% · 17% · 17% not | 7 / 59 · 0% · 17% · 17% not |
| small speaker, crowd equal | 6 / 52 · 0% · 33% · 17% not | 3 / 52 · 50% · 50% · 17% not | 4 / 52 · 33% · 50% · 17% not | 3 / 52 · 50% · 50% · 17% not | 3 / 52 · 50% · 50% · 17% not |

**Quick return: to the other song (6 s)** (seconds from the cut to the right name; p90 counts a turn never named as 99)

| Condition | main | fast | a | b | ab |
|---|---|---|---|---|---|
| clean | 5 / 52 · 0% · 83% · 17% not | 2 / 4 · 67% · 100% | 3 / 4 · 67% · 100% | 2 / 4 · 67% · 100% | 2 / 4 · 83% · 100% |
| room | 5 / 52 · 0% · 67% · 17% not | 4 / 52 · 33% · 83% · 17% not | 4 / 52 · 33% · 83% · 17% not | 3 / 52 · 67% · 83% · 17% not | 3 / 52 · 67% · 83% · 17% not |
| crowd 10 dB under | 4 / 99 · 17% · 67% · 33% not | 3 / 52 · 67% · 83% · 17% not | 3 / 52 · 67% · 83% · 17% not | 3 / 52 · 50% · 83% · 17% not | 3 / 52 · 67% · 83% · 17% not |
| crowd equal | 5 / 99 · 0% · 50% · 50% not | 3 / 99 · 33% · 50% · 50% not | 3 / 99 · 33% · 50% · 50% not | 4 / 99 · 17% · 33% · 50% not | 3 / 99 · 33% · 33% · 50% not |
| small speaker, crowd equal | 4 / 99 · 17% · 50% · 50% not | 3 / 99 · 33% · 50% · 50% not | 3 / 99 · 33% · 50% · 50% not | 2 / 99 · 50% · 50% · 50% not | 2 / 99 · 50% · 50% · 50% not |

**Quick return: back to the first song** (seconds from the cut to the right name; p90 counts a turn never named as 99)

| Condition | main | fast | a | b | ab |
|---|---|---|---|---|---|
| clean | 5 / 5 · 0% · 100% | 2 / 3 · 100% · 100% | 3 / 4 · 83% · 100% | 4 / 4 · 50% · 100% | 2 / 3 · 100% · 100% |
| room | 5 / 54 · 17% · 67% · 17% not | 4 / 54 · 33% · 67% · 17% not | 4 / 54 · 33% · 67% · 17% not | 4 / 54 · 33% · 67% · 17% not | 4 / 55 · 33% · 67% · 17% not |
| crowd 10 dB under | 5 / 5 · 0% · 100% | 3 / 7 · 60% · 80% | 3 / 7 · 60% · 80% | 3 / 5 · 50% · 100% | 2 / 4 · 67% · 100% |
| crowd equal | 6 / 99 · 0% · 20% · 60% not | 4 / 99 · 20% · 40% · 60% not | 5 / 99 · 0% · 20% · 60% not | 5 / 99 · 17% · 33% · 50% not | 3 / 99 · 33% · 50% · 50% not |
| small speaker, crowd equal | 5 / 10 · 17% · 67% | 4 / 10 · 50% · 67% | 4 / 10 · 33% · 67% | 4 / 10 · 33% · 67% | 4 / 10 · 50% · 67% |

**Back and forth, 12 s each** (seconds from the cut to the right name; p90 counts a turn never named as 99)

| Condition | main | fast | a | b | ab |
|---|---|---|---|---|---|
| clean | 5 / 6 · 8% · 83% | 2 / 3 · 100% · 100% | 3 / 3 · 96% · 100% | 2 / 5 · 75% · 96% | 2 / 3 · 100% · 100% |
| room | 5 / 6 · 0% · 79% · 8% not | 3 / 6 · 67% · 88% · 8% not | 3 / 6 · 67% · 83% · 8% not | 3 / 6 · 62% · 88% · 8% not | 3 / 6 · 67% · 88% · 8% not |
| crowd 10 dB under | 5 / 7 · 8% · 71% · 4% not | 3 / 10 · 54% · 83% · 4% not | 4 / 10 · 46% · 83% · 4% not | 3 / 6 · 50% · 88% · 4% not | 3 / 6 · 58% · 88% · 4% not |

**Back and forth, 8 s each** (seconds from the cut to the right name; p90 counts a turn never named as 99)

| Condition | main | fast | a | b | ab |
|---|---|---|---|---|---|
| clean | 5 / 6 · 5% · 83% · 10% not | 2 / 3 · 95% · 100% | 3 / 4 · 86% · 100% | 2 / 3 · 90% · 98% | 2 / 3 · 100% · 100% |
| room | 5 / 8 · 5% · 74% · 10% not | 3 / 4 · 76% · 93% | 3 / 4 · 69% · 93% | 3 / 6 · 64% · 83% · 2% not | 3 / 4 · 74% · 90% · 2% not |
| crowd 10 dB under | 5 / 99 · 0% · 48% · 24% not | 3 / 90 · 48% · 71% · 12% not | 4 / 99 · 31% · 69% · 14% not | 3 / 90 · 45% · 67% · 12% not | 3 / 8 · 48% · 74% · 10% not |

**Back and forth, 5 s each** (seconds from the cut to the right name; p90 counts a turn never named as 99)

| Condition | main | fast | a | b | ab |
|---|---|---|---|---|---|
| clean | 4 / 99 · 7% · 86% · 14% not | 2 / 3 · 95% · 97% · 3% not | 3 / 4 · 88% · 97% · 3% not | 4 / 99 · 34% · 84% · 16% not | 3 / 3 · 92% · 97% · 3% not |
| room | 5 / 99 · 2% · 67% · 33% not | 3 / 4 · 67% · 95% · 5% not | 3 / 4 · 64% · 95% · 5% not | 5 / 99 · 9% · 80% · 20% not | 3 / 4 · 69% · 94% · 6% not |
| crowd 10 dB under | 5 / 99 · 2% · 48% · 52% not | 4 / 99 · 35% · 73% · 27% not | 4 / 99 · 28% · 68% · 32% not | 4 / 99 · 16% · 59% · 41% not | 4 / 99 · 36% · 73% · 27% not |

**Back and forth, 3 s each** (seconds from the cut to the right name; p90 counts a turn never named as 99)

| Condition | main | fast | a | b | ab |
|---|---|---|---|---|---|
| clean | 2 / 3 · 93% · 93% · 7% not | 2 / 3 · 98% · 98% · 2% not | 3 / 3 · 94% · 94% · 6% not | 2 / 99 · 84% · 84% · 16% not | 3 / 3 · 93% · 93% · 7% not |
| room | 2 / 99 · 66% · 66% · 34% not | 3 / 99 · 70% · 70% · 30% not | 3 / 99 · 74% · 74% · 26% not | 2 / 99 · 58% · 58% · 42% not | 3 / 99 · 72% · 72% · 28% not |
| crowd 10 dB under | 2 / 99 · 54% · 54% · 46% not | 3 / 99 · 58% · 58% · 42% not | 3 / 99 · 64% · 64% · 36% not | 2 / 99 · 45% · 45% · 55% not | 3 / 99 · 60% · 60% · 40% not |


## 5. Back and forth: where each listener stops keeping up

**Back and forth: the song on show** (share of readings from 5 s on showing the song playing · the clip's other song; then clips that keep up / lag a turn / hold one / flip late)

| Turns | Condition | main | fast | a | b | ab |
|---|---|---|---|---|---|---|
| 12 s | clean | 71% · 29%; 100%/0%/0%/0% | 88% · 10%; 100%/0%/0%/0% | 86% · 14%; 100%/0%/0%/0% | 87% · 13%; 100%/0%/0%/0% | 90% · 10%; 100%/0%/0%/0% |
| 12 s | room | 66% · 28%; 83%/0%/0%/17% | 77% · 17%; 83%/0%/0%/17% | 76% · 18%; 83%/0%/0%/17% | 78% · 15%; 83%/0%/0%/17% | 79% · 15%; 83%/0%/0%/17% |
| 12 s | crowd 10 dB under | 66% · 28%; 83%/0%/0%/17% | 74% · 20%; 83%/0%/0%/17% | 73% · 21%; 83%/0%/0%/17% | 75% · 19%; 83%/0%/0%/17% | 76% · 18%; 83%/0%/0%/17% |
| 8 s | clean | 51% · 49%; 100%/0%/0%/0% | 81% · 19%; 100%/0%/0%/0% | 74% · 26%; 100%/0%/0%/0% | 83% · 17%; 100%/0%/0%/0% | 85% · 15%; 100%/0%/0%/0% |
| 8 s | room | 49% · 49%; 83%/17%/0%/0% | 71% · 27%; 100%/0%/0%/0% | 67% · 31%; 100%/0%/0%/0% | 68% · 28%; 100%/0%/0%/0% | 71% · 24%; 100%/0%/0%/0% |
| 8 s | crowd 10 dB under | 41% · 47%; 67%/17%/0%/17% | 60% · 31%; 83%/0%/0%/17% | 54% · 36%; 83%/0%/0%/17% | 58% · 30%; 83%/0%/0%/17% | 61% · 28%; 83%/0%/0%/17% |
| 5 s | clean | 35% · 65%; 83%/17%/0%/0% | 69% · 31%; 100%/0%/0%/0% | 59% · 41%; 100%/0%/0%/0% | 44% · 54%; 67%/17%/0%/17% | 65% · 34%; 100%/0%/0%/0% |
| 5 s | room | 33% · 66%; 33%/67%/0%/0% | 56% · 43%; 100%/0%/0%/0% | 54% · 46%; 100%/0%/0%/0% | 38% · 61%; 50%/50%/0%/0% | 56% · 43%; 100%/0%/0%/0% |
| 5 s | crowd 10 dB under | 37% · 60%; 0%/100%/0%/0% | 46% · 51%; 50%/50%/0%/0% | 45% · 52%; 50%/50%/0%/0% | 38% · 57%; 0%/100%/0%/0% | 44% · 51%; 50%/50%/0%/0% |
| 3 s | clean | 63% · 37%; 100%/0%/0%/0% | 54% · 46%; 100%/0%/0%/0% | 49% · 51%; 100%/0%/0%/0% | 60% · 40%; 67%/33%/0%/0% | 47% · 53%; 100%/0%/0%/0% |
| 3 s | room | 57% · 43%; 17%/83%/0%/0% | 42% · 58%; 33%/67%/0%/0% | 48% · 52%; 33%/67%/0%/0% | 53% · 47%; 17%/83%/0%/0% | 44% · 56%; 33%/67%/0%/0% |
| 3 s | crowd 10 dB under | 54% · 40%; 17%/50%/17%/17% | 42% · 51%; 17%/67%/17%/0% | 42% · 52%; 33%/50%/17%/0% | 48% · 45%; 0%/83%/17%/0% | 42% · 52%; 17%/67%/17%/0% |


- **12 s turns**: every listener keeps up; `main` shows the right song 71 % of the time clean, the others 86 to 90 %.
- **8 s turns**: `main` is right only half the time (5 s late each turn); fast, A, B and A+B 74 to 85 % clean.
- **5 s turns**: `main` and B are **a turn behind** (right a third of the time: the name changes when the turn is
  nearly over); fast, A and A+B keep up clean and in a room (54 to 69 %), and are half behind under a crowd.
- **3 s turns**: **no listener keeps up.** Every one shows the right song about half the time, which is chance: it
  holds one or flips a turn late. Naming needs about 2 to 3 s of the new song, so a 3 s turn is over when it comes.
- **A and a return to the song just left**: a return is a challenger like any other; nothing remembers the song.
  The one thing that touches it is the 8 s rule of section 2 (the old sound is not searched again), which stops a
  flip back to the song *being left*; the song *coming back* is found in the newest 4 s as any new one is. Back
  to the first song after a quick return: A 3 s clean, 3 to 4 s in a room (`main` 5).
- **B's "song has gone" in a back and forth** (held-out, B before the fix): at hard cuts and returns it fires on
  about 85 % of the cuts where the old song was being followed, raised about 1 s after the cut, and the moment it
  names is within a tenth of a second of the cut. At 12 and 8 s turns it fires on most cuts (19 to 41 of each
  condition's 24 to 42). At 5 s turns on a third of them and at 3 s on a fifth, and on many of those the old song
  was not yet followed, so there was nothing to watch.
- **The app's own wait adds to all of this** (`Recognizer.swift`, left alone as asked): a new song reaches the
  screen one reading after the listener names it (about 1 s), and **a song that was on screen in the last 30 s needs
  three readings in a row** (about 3 s more). In a back and forth every turn is such a return, so on screen the
  12 s and 8 s rows are about 3 s later than above, and at 5 s turns the screen cannot keep up with any listener.

## 6. Fidelity

**Fidelity, all clips of a condition** (clips with a wrong name · with a version of the same release named · shared-passage clips naming the made song · jumps in a song · misses of turns of 10 s or more · clips naming a song during noise or a song not in the crate)

| Condition | main | fast | a | b | ab |
|---|---|---|---|---|---|
| clean | 1 · 0 · 1 · 4 · 0/130 · 1 | 2 · 1 · 14 · 29 · 0/130 · 1 | 1 · 0 · 2 · 4 · 0/130 · 1 | 1 · 1 · 3 · 8 · 0/130 · 1 | 1 · 0 · 4 · 6 · 0/130 · 1 |
| room | 2 · 0 · 2 · 4 · 3/130 · 0 | 2 · 0 · 11 · 16 · 3/130 · 0 | 2 · 0 · 2 · 5 · 3/130 · 0 | 2 · 0 · 2 · 4 · 3/130 · 0 | 2 · 0 · 2 · 5 · 3/130 · 0 |
| crowd 10 dB under | 1 · 0 · 2 · 3 · 5/130 · 1 | 1 · 0 · 10 · 14 · 5/130 · 1 | 1 · 0 · 3 · 5 · 5/130 · 1 | 1 · 0 · 3 · 4 · 5/130 · 1 | 1 · 0 · 3 · 5 · 5/130 · 1 |
| crowd equal | 0 · 0 · 0 · 0 · 15/70 · 0 | 0 · 0 · 0 · 0 · 15/70 · 0 | 0 · 0 · 0 · 0 · 15/70 · 0 | 0 · 0 · 0 · 0 · 15/70 · 0 | 0 · 0 · 0 · 0 · 15/70 · 0 |
| small speaker, crowd equal | 0 · 0 · 0 · 0 · 6/70 · 1 | 0 · 0 · 0 · 0 · 6/70 · 1 | 0 · 0 · 0 · 0 · 6/70 · 1 | 0 · 0 · 0 · 0 · 6/70 · 1 | 0 · 0 · 0 · 0 · 6/70 · 1 |
| **all** | 4 · 0 · 5 · 11 · 29/530 · 3 | 5 · 1 · 35 · 59 · 29/530 · 3 | 4 · 0 · 7 · 14 · 29/530 · 3 | 4 · 1 · 8 · 16 · 29/530 · 3 | 4 · 0 · 9 · 16 · 29/530 · 3 |

| Clips in all | 392 | 392 | 392 | 392 | 392 |
|---|---|---|---|---|---|
| Jumps per hour of named song | 2.9 | 14.4 | 3.5 | 4.0 | 3.9 |


- **Where the extra is**: all in the 90 shared-passage clips, plus 2 jumps for A in 8 s back and forth. On long
  play, cuts, quick returns, fader changes, songs not in the crate and noise, A, B and A+B add nothing over `main`.
- Every shared-passage clip in which `main` names the made song, A names it too; A adds one mash-up (in two
  conditions). B adds one sample and two mash-ups.
- **B's faults** (found with `--alarms-out` after the held-out run): the moment of an alarm could be 0 s (the start
  of listening), so the search after it took in the old song; and points in the newest tenth of a second, chosen
  without the sound after them, counted as unpaired, giving about one false alarm in 20 s of a song where the design
  aims at one an hour. Both are fixed on the branch (the moment starts at the first point watched; points within the
  fingerprint's own reach of the window's end wait for the next reading). **On dev** the fixed B raises 11 to 18 false
  alarms an hour (still far above the aim), names a clean cut in 3 s (88 % by 3 s) and a 5 s back and forth in 3 s,
  and names the made song in 7 clips of 60 (`main` 6), one version of the same release (`main` 0), 10 jumps (`main`
  12). It has not been run on held-out clips; doing so honestly needs a new set of held-out clips.

## 7. Cost

**A reading's work** (milliseconds on one core of the test machine: median / 95th percentile, cut clips, clean)

| main | fast | a | b | ab |
|---|---|---|---|---|
| 119 / 649 | 230 / 388 | 342 / 983 | 12 / 578 | 287 / 855 |

- A searches twice as often as `main` while a song plays (its 4 s search every second, and `main`'s 8 s search
  every two). B adds no search while the song fits, which is why its median is a tenth of `main`'s (it searches
  only after an alarm and when nothing is followed). Memory: no change for any of them (same window, same table).
- These are milliseconds of one core on a shared machine running four listeners at once; an iPad's are not known.

## 8. Against the pass marks (held-out)

| Mark | `fast` | A | B (before the fix) | A+B (B before the fix) |
|---|---|---|---|---|
| 1. The test sees the fault (fast worse than `main` on shared passages) | **yes**: 35 against 5 | | | |
| 2. Fidelity: no count above `main`'s in any condition | no | **no** (made song 7 vs 5; jumps 14 vs 11) | no (8; 16; one version) | no (9; 16) |
| 3a. Speed: clean cut median 3 s and 9 in 10 by 4 s | yes | **yes** (3 s, 93 % by 3 s) | no (2 s median, p90 5 s) | **yes** (2 s, all by 3 s) |
| 3b. Noisy: median and p90 no later than `main`'s in any cell | no | **no, in two cells of six clips**: fader changes with crowd at equal level (median 8 s against 6) and 12 s back and forth under a quiet crowd (p90 10 against 7) | no | no, in one (fader with crowd at equal level: 7 against 6) |
| 4. A reading's 95th percentile at most half as long again as `main`'s | yes | no, by a hair (983 ms against 649: 1.51) | yes | yes |

## 9. What is and is not shown, and what next

- **Not real**: no microphone, no real room (measured room responses applied by computer), no iPad, no owner's
  library. Times are on a shared Linux machine.
- **Small**: 392 held-out clips. 5 against 7 is not a measured difference; 5 against 35 is.
- **Edits** test nothing here (the index merges them with the source).
- **The next evidence is the owner's library**, where the fast setting's fault showed at scale (wrong-name clips 86
  to 207). Every listener runs there with the commands below; its result is a separate check and nothing will be
  chosen from it. If A's wrong-name and jump counts there are `main`'s, A is ready to ship as an option; if they are
  above, the next step is the mash-up case (a lead of twice the score is not enough when the other song carries the
  followed song's passage under its own) rather than another number.
- **Unchosen**: the fixed B on held-out clips; a second margin for A on shared passages only.

## 10. Running it on the Mac

Needs Swift, Python 3 with numpy, and ffmpeg (no scipy, no pedalboard). From `core/`:

```bash
swift build -c release --product deckie-listen
```

The song list: `WORK/songs.tsv`, a line a song, the crate's own id, a tab, the file's path (the same ids the index
holds). Or let the maker list a folder (its ids are then its own, and must match the index's):

```bash
python3 Tools/recognition-bench/switch_clips.py songs /path/to/Music WORK
```

The clips (rooms and crowds need `fetch_data.py DATA --part small`; without `--rooms` only clean clips are made):

```bash
python3 Tools/recognition-bench/switch_clips.py make WORK --role eval --rooms DATA --n 20 --n-kind cut=60
```

Every listener on the same clips, with the crate's index, and the table:

```bash
INDEX_FILE=/path/to/crate.dkx sh Tools/recognition-bench/run_switch.sh WORK eval main fast a b ab
```

The table is `WORK/switch/eval/table.md`; `switch_tables.py WORK/switch/eval/table.json main fast a b ab` lays it out
as in this letter. With every song in the crate, "not in the crate" clips are not made; shared-passage clips need
`switch_clips.py versions` and the made songs in the index, which a crate file cannot hold, so on the owner's library
the real versions in it are the test.
