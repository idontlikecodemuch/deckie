# A quicker change of name after a hard cut: two proposals

Branch `recog/faster`. Nothing is built or measured here: this is the choice put to the owner before any work.
It follows W4 (`w4-recognition-complete.md`) and W5 (`w5-recognition-by-five-seconds.md`, on branch `recog/fast`).

**Words used.** The *listener* is the code that takes microphone sound and gives a *reading* once a second: a
song, the place in it, the speed, and how sure. A *search* looks the newest seconds of sound up in the whole crate.
The *follow check* tests only the song already named, at the place it should be now. A *hard cut* is one song
stopping and another starting at once; a *blend* is one fading in over another. A song's *points* are the loudest
moments in time and pitch that make its fingerprint. *Sure* is the bar at which one search is taken as a name
(a score of 3.0 against the third-best song). A *mid-song jump* is the name changing while the same song plays.
The *dev half* and *held-out half* are two separate halves of the outside set of songs: anything chosen by
measurement is chosen on dev and reported on held-out.

## 1. Where the seconds go now, and why the fast setting named wrong songs

Read from `SongListener.swift` on `main`:

- After a cut the follow check still passes for 3 to 4 s, because it looks at the last 5 s and most of that is
  still the old song.
- While it passes, the crate is searched only every 2 s, over the last 8 s. For the first 4 s after the cut the
  old song fills most of that and wins.
- When the check fails, a search of the last 8 s can name the old song once more. The new song is named on the
  reading after: about 5 s after the cut.

The fast setting (`ListenSettings.fast`) searches every second in the newest 4 s. That is quicker, but it gives a
short search four times as many chances to change the name, and the listener's rule for changing is weak in one
case:

- **A search is judged against the third-best song, not against the song being followed.** The rule exists so
  that two songs playing at once can both score well. Its side effect: when the followed song and a version of it
  (or a song using the same sample) share a passage, both score high, the third is low, both are "sure", and
  whichever is ahead by a hair wins. The listener switches at once, although the followed song still fits.
- `main` has the same weakness. It shows less often there because 8 s rarely lie wholly inside a shared passage
  and there are a quarter as many searches.
- The real-room recordings gave the fast setting almost no gain and 4 more misses. A likely cause *[inference,
  not measured]*: while a song is followed the fast setting never searches more than 4 s, and 4 s of room sound
  often cannot reach the bar that 8 s can.

Both proposals leave the two bars (3.0 and 2.6), the index and the app's own wait rule alone.

## 2. Proposal A: the fast search, with a challenger rule

**What changes.**

1. `main`'s search (8 s, every 2 s while following) stays exactly as it is.
2. Added: every second while a song is followed, a second search over the newest 4 s only.
3. A different song found by that short search is a *challenger*, not a name. It is scored against the followed
   song on the same 4 s of sound: both are fitted point by point (the code that does this exists) and the two
   scores compared. The challenger takes over only when
   - **(cut)** it is sure and its score is clearly above the followed song's on that sound, or
   - **(blend)** it is sure on two readings in a row at the same place and speed, and ahead of the followed song
     on both.
4. Otherwise it is reported as "coming in" (the field exists on `recog/fast`) and the name stays.
5. After a failed follow check, the search looks only at sound since the failure, as the fast setting does.

**Why faster.** Three seconds after a cut the newest 4 s hold 3 s of the new song and 1 s of the old: the new one
is sure and scores about three times the old one. That is the reading at which the fast setting names it.
Expected: clean cuts at 3 s, as the fast setting; blends close to the fast setting's 2 to 3 s after the middle.

**Why no added wrong names.** The failure seen was a single sure reading mid-song for a version or a song sharing
a passage. In that case the followed song is really playing, so it fits the whole 4 s; the other song fits at most
the shared part. Its score cannot be clearly above the followed song's, so it is never taken, however sure it
looks against third place. The 8 s search is kept, so nothing `main` would find is lost; that addresses the 4
extra misses.

**What it costs.** While following, about twice the search work: `main` averages half an 8 s search a second,
this adds one 4 s search a second (W5 measured about 47 ms for 5 s and 80 ms for 8 s against 969 songs on a Linux
machine; W4 gives a third of a second for 8 s against 5,000). One extra point-by-point fit a second, which is
small. No added memory: same window of sound, same vote table.

**What could go wrong.**

- "Clearly above" is a new number (start: twice the score). It must be chosen on dev from a short grid
  (1.5, 2, 3) and is the one thing here that could be over-fitted.
- When the followed song is itself the wrong version, the right one can no longer displace it on one reading; it
  must wait for the follow check to fail, as any new song did before.
- In a loud crowd both scores are noisy, so the comparison may hold back true changes: slower than the fast
  setting there, though not slower than `main`.
- Once it has switched earlier than `main` would, its later readings differ from `main`'s; "nothing lost" is an
  argument, not a proof.

## 3. Proposal B: hear the cut itself, and start again from it

A different route: no added search at all. The listener notices the moment the followed song stopped, and from
then searches only the sound after that moment.

**What changes.**

1. The follow check already pairs each point of the newest sound with the song's points. It now also notes
   *when* each point was heard and whether it paired.
2. A running tally (CUSUM, Page 1954: the standard test for "a rate has changed, and when") compares two
   explanations point by point: "the song is still here" (points pair at the rate this song has shown while
   followed) and "the song has gone" (points pair at the chance rate, which the code already computes). It gives
   a yes or no and the moment of the change.
3. On a yes:
   - searches run every second and look only at sound after that moment, growing from 3 s to the usual 8 s;
   - the old song cannot be named again from sound before it;
   - everything else is `main`'s: the same bars, and the old name is held and dropped by `main`'s own rule.
4. If the followed song passes its check again on sound after the moment, the yes is withdrawn.
5. No yes: every reading is `main`'s, unchanged.

**Why faster.** In clean sound the old song's points pair at a high rate and the new song's at chance, so the
tally should say yes about 1 to 2 s after the cut *[estimate, to be measured]*. The listener is then where it is
at the start of listening, with the old song out of its window, and that case is measured: a right name at 3 s
for 92 in 100 clean clips and 62 in 100 in a room (W5, section 2). Expected: clean cuts at 3 s. It also removes
the "old song named once more" reading.

**Why no added wrong names.** While the followed song fits, nothing is added: no extra search, no new chance for
another song to be accepted. The tally looks only at the followed song's own points, so a version or a song
sharing a passage cannot set it off: the followed song is playing and its points keep pairing. The fast setting's
failure has no path here.

**What it costs.** Less than `main`, not more: a few sums per point each second, a few numbers of memory, and
after a cut the searches cover less sound.

**What could go wrong.**

- **A false yes mid-song**: a breakdown, a filter sweep, an effect, a burst of crowd. The searches are then short
  for a few seconds, which is the fast setting's risky state, but only then and not every second. Usually the
  search finds the same song again or the yes is withdrawn. The alarm rate is set from the tally's own theory
  (about one false yes in an hour of points), not fitted.
- **No yes in noise.** With a crowd as loud as the music the followed song's points pair at a rate not far above
  chance, and the tally needs many seconds. The listener then behaves as `main`: no loss, no gain.
- **No gain in a blend**: there is no moment of change to find. `main`'s figures stay (name changes about 5 s
  after the middle).
- A loop or a jump inside one song also reads as a cut. That is right (the place changed), but it must name the
  same song again and not count as a jump.

## 4. Side by side

| | `main` | Fast setting | A: challenger rule | B: hear the cut |
|---|---|---|---|---|
| Right name after a clean hard cut | 5 s | 3 s | 3 s expected | 3 s expected |
| After a cut under a quiet crowd | 5 s | 3 s | 3 to 4 s expected | between `main` and fast; unknown |
| Blend: after the middle | 5 s | 2 to 3 s | 2 to 4 s expected | 5 s (no change) |
| Added searches while a song is followed | – | one a second | one a second | none |
| Path for a shared passage to change the name | weak | open | closed by comparing with the followed song | none added |
| New numbers to choose | – | – | one, on dev | one, from theory |
| Search work while following | 1 | about 1 | about 2 | 1 or less |

The figures for `main` and the fast setting are W5's medians on the outside set; the owner's library gave 6 s and
4 s. Everything in the last two columns is expectation.

## 5. The test (the same for whichever is chosen)

**The outside test as it stands cannot see the fault.** In W5 the fast setting showed no rise in wrong names on
the outside set; the owner's library showed 86 to 207. So the test needs two things it did not have: far more
clips, and songs that share passages.

**Data** (all outside the repository, fetched by `core/Tools/recognition-bench/fetch_data.py`):

- the 969 outside songs (Internet Archive netlabels, Creative Commons; GiantSteps+ excerpts), split by the
  existing hash of the song's id into dev, held-out and "not in the crate" (one in ten);
- measured rooms (OpenSLR 28) and crowd recordings (DEMAND);
- UnmixDB generated mixes for blends.
- **Shared-passage songs, made for this test** from outside songs, separately in each half and added to the
  crate: (a) a song with a 4 to 8 s passage of another song cut into it (a sample); (b) a song laid over another
  at equal level for 8 to 16 s (a mash-up); (c) an edit of a song with sections removed and reordered. The source
  song is then played through the shared passage. No number in either proposal is set from these on held-out.

**Conditions.** Each as clean, room, room with crowd 10 dB under, room with crowd at equal level, and small
speaker with room and crowd.

| Clips | What plays |
|---|---|
| Hard cuts | 20 s of one song from a random place, then 20 s of another; pairs drawn at random in any order, half within one style |
| Quick returns | 20 s of A, 6 s of B, back to A |
| Blends | UnmixDB mixes, all effects |
| Long play | 120 s of one song, no change (for mid-song jumps) |
| Shared passages | the source song played through each made passage, 60 s |
| Pitch and speed | the hard cuts again at ±2, ±6 and ±8 %, with the key moving and with the key held |
| Not in the crate | a held-out song alone; and a cut from a crate song to one |
| Noise alone | crowd alone, pink noise alone; and a cut from a song to crowd alone |

**Size.** At least 3,000 held-out clips for clean hard cuts and for long play, 1,000 for each other cell. The
owner's library put wrong names at 6 clips in 1,000 for `main` and 14 for the fast setting; 3,000 clips can tell
those apart, 200 cannot. Every listener hears the same clips.

**Numbers**, per condition, for `main`, the fast setting (as on `recog/fast`) and the proposal:

- seconds from the cut to the right name at the listener: median and 90th percentile; share by 3, 4 and 5 s;
  never;
- old name still up at 3 s and at 5 s;
- clips with a wrong name ever, and wrong readings in all (a song the index lists as the same sound is not wrong;
  a made shared-passage song is counted on its own line);
- mid-song jumps per hour of music;
- misses: songs played 10 s or more and never named;
- names given to songs not in the crate and to noise alone;
- a reading's time, median and 95th percentile, and searches a second.

**Split.** The one number in A, and any choice in B beyond its theory, is set on dev only. Dev gets its own hard
cuts and shared-passage clips (W5's dev half had none). Held-out is run once, at the end.

**A pass**, on held-out:

1. *The test can see the fault*: the fast setting shows more wrong-name clips or mid-song jumps than `main` on
   long play or shared passages. If it does not, the test proves nothing about fidelity, and that is reported as
   such.
2. *Fidelity*: in every condition, wrong-name clips, mid-song jumps, misses, and names for absent songs and noise
   are each no more than `main`'s.
3. *Speed*: clean hard cuts at a median of 3 s and 9 in 10 by 4 s; in every noisy condition the median and 90th
   percentile no later than `main`'s.
4. *Cost*: a reading's 95th percentile no more than half as long again as `main`'s.

**What a pass would still not show.** The owner's library is where the fault was seen; a pass here is needed, not
enough. The last check is the owner's own run on his Mac with one command, and then a real room. No microphone,
room or iPad is in any of this.

## 6. Which

**B first.**

- The requirement is no loss of fidelity. B adds no search while a song is followed, so the path by which the
  fast setting went wrong does not exist in it. A closes that path with a rule and a chosen number; B never
  opens it.
- The complaint measured is a hard cut, which is what B is for.
- It costs nothing on the iPad.
- Where it cannot hear the cut it is `main`.

What B gives up: blends, and probably loud rooms. If those matter as much as cuts, A is the one that reaches
them, and the two can be combined later (B's "the song has gone" is a stronger form of A's comparison). The test
is the larger part of the work and serves both.

**One doubt for either.** On the real-room recordings the fast setting gained almost nothing. If the same holds
for these, the gain is real in clean sound and small in a booth, and the honest result would be "no loss, little
gain where it counts". Only a real-room run can settle that.
