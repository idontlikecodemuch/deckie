# Transition recipes: how working DJs do it, translated into renderer parameters

Companion to `research.md` section C (which covers the DSP: LR4 isolator, varispeed brake, Rubber Band, Freeverb).
This sheet covers the *performance* layer: what a club / party DJ actually does on a DJM + CDJs, bar by bar, and the
numbers to put in `render.py`. Researched 2026-10-24 from DJ tutorial sites, forums and the Pioneer manual; sources are
numbered at the end and cited as [n]. Anything I could not confirm is tagged **[unverified]** or **[inferred]**.
Many sources state outright that their figures are "conventions, not measured data" [2][5]; treat every number as a
starting point to be tuned by ear.

## 0. Conventions and look-up tables

* 4/4 throughout. `beat_s = 60/bpm`, `bar_s = 4*beat_s`. Phrases are 8, 16 or 32 bars; the "32-count rule" holds for
  most dance music, but hip-hop and pop intros are often 8 or 16 counts [20][24]. Everything that lands "on the one"
  means the downbeat of a *phrase*, not just any bar; landing one bar early "reads as a mistake" [5].
* Delay times by BPM (seconds):

| BPM | 1 beat | 1/2 beat | 3/4 beat | 1 bar | 8 bars | 16 bars | 32 bars |
|---|---|---|---|---|---|---|---|
| 90  | 0.667 | 0.333 | 0.500 | 2.667 | 21.3 | 42.7 | 85.3 |
| 95  | 0.632 | 0.316 | 0.474 | 2.526 | 20.2 | 40.4 | 80.8 |
| 100 | 0.600 | 0.300 | 0.450 | 2.400 | 19.2 | 38.4 | 76.8 |
| 110 | 0.545 | 0.273 | 0.409 | 2.182 | 17.5 | 34.9 | 69.8 |
| 120 | 0.500 | 0.250 | 0.375 | 2.000 | 16.0 | 32.0 | 64.0 |
| 128 | 0.469 | 0.234 | 0.352 | 1.875 | 15.0 | 30.0 | 60.0 |

* Echo feedback needed for the repeats to fall to -24 dB after N bars (`f = 0.063 ** (1/n)`, `n = 4N / division`):

| division | 2-bar tail | 3-bar tail | 4-bar tail |
|---|---|---|---|
| 1/2 beat | 0.84 | 0.89 | 0.92 |
| 3/4 beat | 0.77 | 0.84 | 0.88 |
| 1 beat   | 0.71 | 0.79 | 0.84 |

* "o'clock" knob positions quoted from tutorials: 7 o'clock = 0 %, 12 = 50 %, 5 = 100 %; so 9 o'clock is about 20 %,
  10 about 30 %, 11 about 40 %, 2 about 70 % (linear-taper assumption **[inferred]**).
* "Dry cut" = the outgoing channel fader goes to zero in one motion (a few ms to at most one beat). Every exit below
  depends on it; a fade instead of a cut is what makes an effect exit read as a crossfade.

## 1. Echo-out and reverb throw

### 1.1 Echo-out (the DJM way)
One line: engage a tempo-synced echo on the last beat(s) of A, kill A's fader in the same motion, let the repeats ring
2-4 bars while B starts on the one.

What the hardware does (Pioneer DJM-900NXS2 manual [1]): ECHO = "a delay sound is output several times and gradually
attenuated according to the beat fraction set with the BEAT buttons"; BEAT range 1/16-16 beats, TIME 1-4000 ms;
LEVEL/DEPTH "sets the balance between the original sound and the echo sound" (it is a wet/dry mix, confirmed by Pioneer
support [25]; the decay rate is internal, you do not dial feedback); and the key sentence: "Lowering the channel faders
and cutting the input volume leaves an echo sound, producing a fade out" (the Beat FX send is post-fader; Traktor's is
pre-fader, which is why laptop DJs need workarounds [8]). The FX FREQUENCY buttons let you take LOW out of the echo;
DJ TechTools: echo/ping-pong "can quickly get overwhelming if the low end is being effected", deselect it [3].

Division, as practised: 1/2 beat or 1 beat for finishing a transition [4][6][7][9]; 1 beat for a quick vocal exit,
2 beats "gives more space before a big drop" [9]; 3/4 beat is the "shuffle" setting preferred by some DJs [11][12]
and cited as the setting for jumping between very different tempos [13] (**[weak]**, one Reddit comment). Shorter
settings (1/8, 1/4) are a build-up trick, not an exit [10][26].

Wet level: 30-40 % [4]; forum DJs run 33-50 % and never past 50 % [7]; Crossfader tutorials show one-beat echo at
9-11 o'clock (20-40 %) and 2 o'clock (70 %) for the final echo-out [14]. The DJ.Studio and Digital DJ Pool guides say
8-16 beats of echo while B rises, with a high-pass on the outgoing so repeats do not muddy the incoming kick [6][15].
Tail length: 2-4 bars [2]; "switch the echo off before it crowds B" [15].

Bar-level timeline (A at bpm, exit downbeat = bar E):
```
E-1 bar   : A plays dry; echo send opens on beat 3 or 4 (last word / last snare)      [2][15][10]
E (the 1) : A fader -> 0 within <=10 ms (hard cut); B starts at full level, bass in     [1][2][15]
E .. E+2  : repeats at 3/4 beat (or 1/2), decaying -24 dB by bar E+2..E+3              [2]
E+2..E+4  : repeats inaudible under B; nothing else happens
```
Renderer parameters:
* `delay_s = 0.75 * 60/bpm` (default) or `0.5 * 60/bpm` for a straighter feel; never un-synced.
* Feedback per the table: 0.80-0.85 at 3/4 beat for a 3-bar tail (current `ECHO_FB = 0.72`, `ECHO_REPEATS = 10`
  gives about 1.9 bars; two bars is the bottom of the practised range).
* Send = A's last 2 beats (not just the last beat), unity gain; wet level of the tail -3 to -6 dB relative to A's dry
  level (DJs' 30-50 % wet with the dry removed sounds like "about as loud as the music, then decaying").
* In-loop filters: 1-pole LP 4-6 kHz (3.5 kHz gets dull by the 8th repeat), 1-pole HP 150-250 Hz; or run the send
  through the LR4 split and drop the low band entirely (the FX-FREQUENCY-LOW-off move) [3].
* Do **not** multiply the tail by an extra fade curve; let the feedback do the decay. Only apply a short duck (-6 dB
  for 50 ms) under B's kicks if B is a hard four-on-the-floor track **[inferred]**.
* B: starts on the exit downbeat with its bass *in*. Since A's bass is gone the moment the fader is cut, there is no
  bass clash; keeping B's bass out for bars after the cut is the thing that makes it feel like a fade.
Common mistakes: engaging mid-phrase ("repeats a fragment that does not resolve") [2]; leaving the dry up under the
repeats [2]; feedback so long the tail competes with B [9]; firing the echo late so the vocal is blurred [9]; echo at
full track intensity instead of on a sparse bar [10]; stacking echo + reverb tails [9].

### 1.2 Reverb throw / wash
One line: a short, filtered reverb opened over A's last bar, dry cut on the one, 1-2 s of tail under B; the standard
exit when the tempos do not match [4][16][17].
Settings: decay 1-2 s, short plate/room, never a big hall; high-pass the return so the tail "sits above the bass";
bring it in on the last bar, pull it down as the incoming kick lands [16]. Reverb "on the last snare so the track
washes out" [10]. Crossfader runs reverb at 8 o'clock (about 10 %) on the deck being chopped [14]; the DJ TechTools
reverb exit keeps about 2/3 dry while the fader is up [18]; a Traktor user runs 33-50 % wet [7]. Thomann: rhythmic delay
suits beat-synced mixes, reverb suits tracks with different BPMs [17]. DJ TechTools: FX-out suits lo-fi / downtempo /
deep house and large BPM jumps [19].
Timeline:
```
E-1 bar : wet ramps 0 -> 100 % send over the 4 beats (snare on beat 4 is the loudest thing thrown)
E       : A dry cut; B on the one, bass in
E..E+1  : tail decays (RT60 1-2 s = about half a bar to one bar at 100-128 BPM); duck -6 dB on B's first kick
```
Renderer: `pedalboard.Reverb(room_size 0.5-0.65, damping 0.5-0.6, wet 1, dry 0)` fed by A's last bar through
HP 200-300 Hz and LP 7-8 kHz; wet level -6 dB vs A; no extra tail beyond 2 bars. Freeverb `room_size` 0.92 (old code)
is a hall; mapping of `room_size` to RT60 is **[unverified]**, tune by measuring the -60 dB point.
Mistakes: long hall across two playing tracks ("sounds like a bad PA") [16]; unfiltered reverb on a full record (adds
level across the spectrum, muddy lows) [16]; constant reverb instead of a throw [16].

## 2. Cutting instead of fading

### 2.1 Slam / cut on the one
One line: B's first downbeat replaces A's next phrase downbeat; A is killed "in the same motion"; no overlap, no
effects [5][15][20]. It is the standard move for hip-hop, pop, open-format and any big BPM change [15][20]; "a decisive
cut is forgiven more readily than prolonged drift" [5]. Energy "comes from the rate of change between records" [21].
Rules:
* A's exit = a phrase boundary (multiple of 8/16/32 bars from A's first downbeat, ideally the end of a hook or a verse)
  [5][20]. B's entry = the first beat of a phrase that is "recognisable or dramatic enough to grab attention straight
  away" (hook, first verse bar, drop), not a long intro [22][21].
* Vinyl DJs "may add a loose scratch" on the cut [17]; both tracks should have similar energy [17].
* Dropping on the four: if B's vocal has a pick-up before its downbeat, start B one beat early (on A's "4") and move
  the crossfader more slowly so both are heard for a beat [23]. In the renderer: if B's vocal timeline shows voice in
  the last beat before its cue downbeat, start B at cue - 1 beat with A at -6 dB for that beat, then cut.
Renderer: 5 ms seam ramps only; loudness-match B's entry to A's exit (same short-term LUFS +/-1 dB) **[inferred]**;
no bass hold on B; optional 1-beat scratch stab or air-horn-style impact *before* the one, never on it.
Mistakes: cutting on a bar that is not a phrase boundary [5]; cutting over a vocal line in A (use the vocal timeline:
exit only where A's vocal has >= 1 beat of silence before the one) [23]; B entering through an intro [22].

### 2.2 Drop mix / drop swap / double drop
* Drop mix (hip-hop): cue B at the start of a phrase (intro, verse or chorus); both channel faders up; on A's phrase
  end hit play on the one and throw the crossfader [23].
* Drop swap: hot cue exactly on B's drop; phrase both so the drops coincide; cut on the drop so only one is heard;
  "a miss by one beat is audible to the whole room" [27].
* Double drop: cues on both tracks at equal distances before their drops (8, 16 or 32 bars); start B when A reaches
  its cue; one track's low EQ at zero; after the drop jump between them with faders or EQ, mix out at the next
  breakdown [28]. Needs same key, similar structure and accurate grids [28].
Renderer: with the hook-bar / drop labels, align B's hook downbeat to A's hook downbeat 16 bars out, B bass off,
B at -9 dB mids/highs until the drop, then cut A on the drop (drop swap) rather than keeping both.

### 2.3 Ending a track that has no usable outro
* Loop 4-16 beats of a drum/percussion part before the ending (a 16-bar loop in the DJ TechTools example), bring B in
  over it, release the loop as A's fader reaches zero so B lands on a main section [19]. Crossfader: loop the previous
  track's outro and hot-cue into the next track's first verse [29]. Keep loops at 4/8/16/32 beats [6].
* Or snap: cut on the first beat of a bar into a major phrase change of B (breakdown or drop) [19].
* Or FX out (echo / reverb) 8-16 beats before the end [6][19]; freeze-echo or long reverb "to get out early" [30].
* "Songs with no clear outro often still have a beat or two without vocals" to loop from [30].
Renderer: when `mix-out window` is missing, choose the last 1-2 bars with no vocal that start on a phrase boundary,
loop them for 8 bars (grid-exact, 10 ms equal-power seams), then echo-out or slam.

## 3. Hip-hop and open-format

### 3.1 Quick mixing
One line: play "the part that matters" for 30-90 s per record, then cut; two cues per track (in / out); cuts or slams,
no long blends [21]. Digital DJ Tips: "one verse, one chorus"; new or huge hits get a second verse and chorus; use it
to "up the energy" at high-energy moments, not for a whole set or the warm-up [22]. DJ TechTools forum DJs playing
club sets: 3-5 min per track, mix out about 3 min from the end [31]. Hip-hop / open-format / urban DJs "tend to use
shorter mixes" and "cut in tracks on the one" [20].
Renderer timeline for a hip-hop pair at ~95 BPM (bar = 2.5 s):
```
B cue   : first bar of verse 1 or first bar of the hook (hook preferred if A was long or low energy)
play    : 24-32 bars (60-80 s): verse 1 -> hook (or hook -> verse -> hook for a big record)
exit    : end of hook (phrase boundary); exit type = slam / backspin / echo-out / chop in rotation
```
"Doubling the hook": beat-jump back 16 bars at the end of the hook to play it twice [29]; cheap energy on a big record.

### 3.2 Chopping / cutting back and forth
One line: crossfader cuts between A and B on bar (or beat) boundaries with both decks running in time, snares aligned,
bass from one side only. Sources: cut "to accent the snare or hi-hat of one of the tracks", "matching the snares is of
utmost importance" [32]; Crossfader wordplay routine: "cut and reopen Deck 1's upfader around the vocal, and repeat for
16 bars" [14]; instant doubles: cut on "every number and every and" (eighth notes) [29]; Digital DJ Tips fader cuts:
full-beat clicks, then "double-speed cuts towards the end of your patterns" over 8-bar patterns [33]. Exact
bar-alternation patterns are not written down anywhere I found; the following is a synthesis **[inferred]**:
```
bar 1-4 : B 4 bars (hook)     bar 5-6: A 2 bars     bar 7-8: B 2 bars
bar 9   : A 1 bar  bar 10: B 1 bar  bar 11: A 2 beats, B 2 beats  bar 12: 8th-note transformer cuts A/B
bar 13+ : B, A dead.   (A 2 / B 2 / A 1 / B, as in the current renderer, is a 6-bar version of this)
```
Rules: the first B segment starts on B's hook or first verse bar; A segments return to where A would be (slip), so
A's own phrasing is preserved; B's bass off while A plays and vice versa (hard switch, no ramp); cut edges 2-5 ms;
never both vocals at once (use vocal timelines: choose segments where the other track's voice is silent, else dip the
silent-side mids -6 dB) [34][35]. Crossfader with a sharp curve = instant switch [36].
Mistakes: chopping house (smashing the crossfader "is going to sound like sh!t" on house) [32]; grids off by >10 ms
(flam on the snares); segments shorter than a beat before the pattern has established itself.

### 3.3 Word-play / vocal hand-off
One line: cut from the last word of a line in A into B's vocal cue at the moment A's line ends [29][14][37]. Real
word-play needs lyrics (love -> above) [37]; the renderer can do the structural version: exit where A's vocal phrase
ends on a phrase boundary, enter on the first beat of B's vocal, with 1 beat of A's one-beat echo covering the seam
[14]. Crossfader's version adds a one-beat echo at 9 o'clock on deck 1 just before the cut [14].

### 3.4 Backspin and brake
Backspin (spinback) when the two records cannot be blended; use at most once per set [38][39].
```
last bar of A's phrase: beat 3 (zZounds) or beat 4 (DJ TechTools forum) -> spin A backwards
the next 1            : B starts at full level while the spin is still sounding; A is stopped (never restarts)
```
[40][38][39]. Lower the spun track -3 to -6 dB [39]; do not kill its lows ("takes the body out") [39]; avoid vocal
sections, spin on beats [39]. Renderer: `backspin()` over 1-2 beats starting on beat 3 or 4, rate 1 -> -3 -> 0, A
gain x0.6, B on the one.
Brake: start on a downbeat; "a quarter-bar reads as a stutter, two bars as a power cut"; faster material needs a shorter
brake; have the next record already running underneath so there is no unplanned silence [41]. Serato stop time at
about 9-10 o'clock "brakes to a stop within a beat" [29][42]. Renderer: brake length 1 beat (stutter, B on the next
beat) or 1 bar (B on the one after it); never 2.2 s fixed; B may start under the brake at -6 dB and come up on the one.

### 3.5 Scratch punctuation
Placement: before the next track enters, before a vocal hook, in a drum break, before a drop; "one or two beats can be
enough"; locked to the groove, close to the transition point, with space before the next vocal [43]. Scratch
definitions [44][45]: baby = fader open, back-and-forth; chirp = fader opens only mid-stroke, closes at direction change;
transformer = fader closed at the turn, tapped open at a fast rate "such as eighth notes", twice per direction; flare =
fader open, 1-3 clicks per stroke; stab = one forward stroke. Scratch schools drill them at quarter, eighth and
sixteenth subdivisions [46]. Suggested use **[inferred]**:
* slam / chop: 1-beat baby or chirp on beat 4 of the last bar (strokes at 1/8 or 1/16 beat), resolving on the one with
  B's first hit; stab (single forward stroke) on the "and" of 4 as a pick-up;
* transformer at 1/8 beat over beats 3-4 as the last step of a chop;
* "echo scratch": baby scratch into the echo send for exits [43].
Never scratch over a busy chorus or important lyric, and not in every transition [43]. Source slice: B's first beat
(so the scratch previews B) or a one-shot vocal stab, 300-600 ms.

## 4. Loop rolls and beat repeats as build-ups

One line: in the last bar before the landing point, roll the current beat with halving lengths, release exactly on
the downbeat; the track keeps running underneath (slip), so B (or A's own drop) lands clean [47][48][49].
Sequences: 1 beat -> 1/2 -> 1/4 released on the one [47]; 1/2 -> 1/4 -> 1/8 -> 1/32 in a Traktor thread [49];
Thomann: start with a 1/4-beat roll and shorten "just before the drop", or auto-loop from a full beat down to 1/32 in
the breakdown before the drop [10]; DJ.Studio: 1- or 2-beat fragments for rolling build-ups [6]. Rolls longer than a
bar "sound like you got stuck"; "two per set reads as taste, ten as a nervous tic" [47]. Timings at 126 BPM: 1 bar
1.90 s, 2 beats 0.95, 1 beat 0.48, 1/2 0.24, 1/4 0.12 [47].
Renderer timeline (1-bar version, the one in `render.py` is close):
```
bar E-1 beat 1-2 : 1/2-beat cell x4      beat 3: 1/4 x4      beat 4: 1/8 x4 then 1/16 x4
bar E            : B on the one at full level with bass; riser ends here; A dead
```
2-bar version for a bigger moment: bar E-2 = 1-beat cell x4 (or 2-beat x2), bar E-1 as above. Add a rising high-pass
(40 Hz -> 1.5-3 kHz, log) and/or +3 dB over the roll, plus a noise riser ending on the one [10][48]. Cell seams
2-5 ms; cell source = the beat on the grid at the roll start (A's current beat, not an arbitrary slice).
Mistakes: releasing mid-bar [47]; rolling over a vocal; using it on every transition [47][48].

## 5. EQ mixing in house and disco

Crossfader's three house methods (both tracks 127 BPM, same key) [50]:
* Seamless blend: start about two-thirds into A at a phrase change; B enters with bass killed, mids and treble dipped
  slightly, fader closed then raised slowly; swap treble over ~4 bars, mids over ~4 bars, bass over 8-16 bars
  (a full phrase); then lower A's fader. (This is the 32-bar "progressive" blend.)
* EQ swap (instant): treble swapped at the start of a 4-bar section, bass killed/slammed at a phrase change, mids at
  the next 4-bar section; A leaves sharply at the next phrase change. (16 bars total.)
* Layering: B hot-cued at a vocal breakdown; B bass killed only; dip A's mids slightly when B's vocal drops; bass
  swapped instantly at the next phrase change; A reduced by about a third, killed at the following phrase change.
Other sources: incoming LOW fully down, MID/HIGH centred, swap on the first beat of a new phrase (after 8, 16 or 32
beats), try two-beat and four-beat exchanges; small cut on incoming HIGH for busy hats, restored as A leaves; cut the
incoming or outgoing MID to decide which vocal wins; "EQ cannot make competing lyrics clean" [34]. Eight-bar bass swap
with the swap at bar 4 (Digital DJ Tips) [22]; bring B in over 8 or 16 bars, swap at the next phrase, then fade A [15];
start B 16 or 32 bars before A's outro [20]; +/-4-5 BPM gaps "use a 32-bar blend" [51]. DJ TechTools: cut mids "just
enough"; cut mids on older (90s) masters to free headroom and boost highs on vinyl rips; full-frequency fader-only mixing
for long gentle house blends; bass swaps between different keys clash even with EQ [35]. Filter fade: over 8 bars turn
A's filter toward high-pass, swap bass as A thins, lower A's fader before the filter sounds harsh; HP preserves energy,
LP "feels like the room is moving away" [15].
Renderer values (LR4 split at 200 Hz / 2.5 kHz as in research C.4):
* 16-bar bass swap: B low = -inf (gain 0) until the swap bar (bar 8, a phrase boundary of B); B mid/high ramp from
  -12 dB to 0 over bars 1-8 (equal-power); at the swap bar A low -> 0 and B low -> 1 within 1 beat; A high -> -6 dB at
  the swap, -inf by bar 12; A mid fades bars 8-16 (dip to -4 dB from bar 4 if both have vocals); A dead at bar 16.
* 32-bar progressive: same shape stretched: highs cross bars 8-12, mids 12-16, bass swap at bar 16 (or ramped over
  bars 12-20 with A low falling as B low rises, both never above unity), A out by bar 32. Only for pairs whose A outro
  and B intro are beat-only for the full length; disco/house with 32-bar intros. Otherwise use 16.
* "Mud" guards: sum of the two low-band gains <= 1 at all times; at most one vocal at a time (vocal timelines) else
  -6 dB on the other's mids; A's highs leave before its mids (hats clash first).
* Quick 8-bar swap for 90s dance pop: B in over 4 bars, everything swaps on bar 4, A out by bar 8 [22].
Mistakes: two basslines at once [15][22][34]; boosting instead of cutting [34]; swapping off-phrase [34]; all three
bands moving at once [34]; over-cut mids "strip harmonic content" [35].

## 6. Tempo and key practice

* Stretch limits with key lock: "the usual recommendation is to stay within 5 or 6 % of the original BPM" [52]; one
  semitone = 5.95 % [53]; pitch fader ranges on hardware +/-4/8/16/100 %, Traktor default 8 % [54]. Research C.2's
  <=4 % on vocals stands.
* Perceptual bands (mixgraph, unmeasured): 1-2 BPM unnoticed; 3-5 BPM needs pitch; 6-10 BPM "the dancefloor feels it",
  needs a breakdown, filter sweep, loop or cut; 10+ is a deliberate gear change [51]. NI: beatmatch within 5 BPM [20].
* Slow-to-fast climb: about +1 BPM per transition, a 10 BPM rise spread over 8-10 tracks, plateaus of 3-4 tracks;
  dropping tempo suddenly "feels like lost energy" [51]. Over a party set this means stretching each incoming track
  up 1-2 % so the set drifts upward, rather than matching A exactly.
* Bridging big gaps:
  1. Half/double time when one BPM is 2x the other within +/-3 BPM (87 R&B -> 174 DnB; 95 hip-hop -> 125 house pitched
     to 190/2) [51][55]; "works best with a faster cut" [55]; the half-time track's snare on 2 and 4 lines up with the
     fast track's 3 [55].
  2. Echo-out at the end of a 16-bar phrase, B pressed in time with B's own tempo as the tail decays; "the echo masks
     the BPM change" [56] (also reverb for unmatched tempos [17]).
  3. Breakdown / beatless bridge: bring B in during A's sparse breakdown, silence A before its beat returns; long
     "wash" blends of two beatless sections [19][55].
  4. Wide-range tempo ramp: loop 4 beats of A (no vocal), let it play twice, lower/raise the tempo fader smoothly to
     B's BPM, bring B in underneath on a new phrase [56]; Crossfader routines ramp 104 -> 126 BPM over 16 bars and
     125 -> 183 over 16 bars with the incoming deck synced to the ramp [14]. Key lock on/off during the ramp is not
     stated **[unverified]**; pitch drift is part of the gesture, so a resample ramp (no key lock) is acceptable.
  5. Transition tracks (92 -> 128 within one record) [57]; brake / backspin [17][41].
* mixgraph's catalogue: 8.4 % of 7,254 planned transitions exceed a +/-6 % fader, median gap 16.7 % [38]: so roughly
  one join in twelve is a cut/echo/brake, not a blend, even in planned sets.

## 7. Energy, set arc, party context

* Energy steps: Mixed In Key's rule is +/-1 level per transition on a 1-10 scale; 5 -> 7 "too abrupt"; a -2 drop is
  acceptable as a deliberate breather; warm-up 5-6, "dance-floor builder" 7, peak 8 (needs breakdowns), 9 only once
  the crowd is already up; sets open at 5 and finish on 7-8 [58]. Same principle quoted for hip-hop sets [58].
* Set phases (one author's rule of thumb from a search snippet, page not fetched **[weak]**): open 15-20 % of the set,
  build 20-50 %, peak 50-80 %, close last 10-15 % [59]. Save some big records; let the room dip before the next climb;
  do not end on the biggest drop [59].
* Track durations by context: quick-mix hip-hop/party 30-90 s per record (hooks) [21]; "one verse, one chorus" at
  parties, more for huge hits [22]; club house/trance 3-5 min, mix out ~3 min before the end, "mixing through a killer
  break is a mistake" [31]; weddings/regular parties: whole song unless it is not working [60]. Quick mixing "upset"
  a sizeable minority of forum DJs when overdone (teasers, repeated hooks) [31]; one commenter: do not drop the next
  track right after a build-up, listeners miss the payoff [22].
* Halloween records: "two or three well-placed throughout your set is good enough"; a novelty you are unsure of goes
  "at the end of the event"; plan the mixes into and out of them in advance because they differ from the rest;
  Ghostbusters mixes well with Thriller; some long ones (Sympathy for the Devil, 6+ min) are mixed out early [61].
  Otherwise "just play your usual stuff" with a few spooky-undertone tracks [62].
* Implication for the plan: hip-hop block = 24-32-bar plays, cuts and chops, energy steps of +1; house/disco block =
  3-4 min plays, 16-32-bar EQ blends, +1 BPM per track; novelty = full song, slammed in on the one, echoed out.

## 8. Current renderer vs the above (as of 2026-10-24, `render.py`)

* Echo-out: `ECHO_DELAY_BEATS 0.75, ECHO_FB 0.72, ECHO_REPEATS 10, LP 3.5 kHz`: the tail is ~1.9 bars and dark.
  Target: fb 0.80-0.85, tail 3-4 bars (let it decay), LP 5 kHz, send = last 2 beats, wet -3 to -6 dB, no extra fade
  multiplier. The older `quick_blend_echo` (B mids rising 0.25 -> 1 across the overlap, fb 0.58 at 3/8 beat, which is
  -50 dB after one bar) is the crossfade-sounding version; keep it out of the plan.
* Reverb throw: `REVERB_TAIL_S 4.5`, `room_size 0.92`: a hall. Target 1-2 s decay, room_size 0.5-0.65, HP 250 Hz.
* Slam: correct shape (5 ms seams). Add "drop on the four" from vocal timelines, loudness-match B's entry, and make
  B's entry a hook / verse-1 bar rather than an intro bar.
* Chop: A2-B2-A1-B is fine; add snare-alignment check (< 10 ms), hard bass switching, transformer cuts on the last bar,
  B's first segment on the hook.
* Brake: fixed `min(bar_s, 2.2)` s; use 1 beat or 1 bar, start on a downbeat, B under it.
* Loop roll: sequence is right; make the last beat go 1/8 then 1/16, add the HP rise + riser ending on the one.
* Bass swaps: B's highs at 0.4 until the swap then 1.0 is close to Crossfader's "treble first"; move the high cross to
  before the bass swap (bars 4-8 of 16), and keep `sum(low gains) <= 1`.
* Durations: hip-hop plays should be 24-32 bars; house 3-4 min; apply the +1 energy / +1 BPM rules in `plan.py`.

## Sources

1. Pioneer DJM-900NXS2 Operating Instructions, Types of BEAT FX (p.15): https://www.manualslib.com/manual/1275366/Pioneer-Djm-900nxs2.html?page=15
2. mixgraph, Echo out: https://www.mixgraph.io/glossary/echo-out
3. DJ TechTools, 3 techniques for the DJM-900NXS2's EQ effects: https://djtechtools.com/2016/04/04/3-techniques-pioneer-djm-900nxs2s-eq-effects
4. Digital DJ Tips, 3 essential effects: https://www.digitaldjtips.com/do-you-know-how-to-use-these-3-essential-dj-effects/
5. mixgraph, Cut: https://www.mixgraph.io/glossary/cut
6. DJ.Studio, Craft your own DJ mix: https://dj.studio/blog/create-mix-tips
7. DJ TechTools forum, How wet are your effects: https://forum.djtechtools.com/t/how-wet-are-your-effects/37899
8. DJ TechTools forum, Traktor echo effect (fade out) pre-fader: https://forum.djtechtools.com/t/traktor-echo-effect-fade-out/13219
9. VirtualDJ, How to use DJ effects: https://virtualdj.com/articles/how-to-use-dj-effects
10. Thomann, DJ effects: chasing the dramatic drop: https://www.thomannmusic.com/blog/inspire/dj-effects-chasing-the-dramatic-drop/
11. VirtualDJ forum, Ducking echo (3/4 beat preference): https://virtualdj.com/forums/185028/General_Discussion/Ducking_Echo.html
12. Digital DJ Tips, How to use echo when DJing (1/8-3/4 demo): https://www.digitaldjtips.com/how-to-use-echo-when-djing/
13. r/Beatmatch, DJing rules of thumb (3/4 echo for tempo jumps; not fetched): https://lr.sudovanilla.org/r/Beatmatch/comments/19942ck/djing_rule_of_thumbs/kibsgem/?context=3
14. Crossfader, 12 high-energy DJ transitions: https://wearecrossfader.co.uk/blog/12-high-energy-dj-transitions/
15. Digital DJ Pool, DJ transitions for beginners: https://digitaldjpool.com/blog/dj-transitions-for-beginners/
16. mixgraph, Reverb: https://www.mixgraph.io/glossary/reverb
17. Thomann, The 5 most important DJ transitions: https://www.thomannmusic.com/blog/gear/the-5-most-important-dj-transitions/
18. DJ TechTools forum, Echo out (gater + reverb, 2/3 dry): https://forum.djtechtools.com/t/echo-out/2533
19. DJ TechTools, Mixing songs that don't have a DJ intro: https://djtechtools.com/2017/09/11/mixing-songs-dont-dj-intro-4-common-techniques
20. Native Instruments, DJ transitions: https://www.native-instruments.com/blogs/blog/dj-transitions
21. mixgraph, Quick mix: https://www.mixgraph.io/glossary/quick-mix
22. Digital DJ Tips, The only five DJ transitions you'll ever need / How much of a song should DJs play: https://www.digitaldjtips.com/?p=2799229 , https://www.digitaldjtips.com/should-djs-play-the-whole-track/
23. Digital DJ Tips, How to dropmix like a pro hip hop DJ: https://www.digitaldjtips.com/dropmix-like-a-pro-hip-hop-dj/
24. DJ TechTools, phrasing tag (32-count rule, 8/16 in hip-hop): https://djtechtools.com/amp/tag/phrasing/
25. Pioneer DJ forum, DJM-900NXS2 echo decay (LEVEL/DEPTH = wet/dry; via search snippet, page 403): https://forums.pioneerdj.com/hc/en-us/community/posts/206037603-DJM900-NXS2-Echo-Decay-Issue-Video-explanation
26. Shimamura / Pioneer DJ, ECHO + TIME build trick (1/8-1/2 beat, DEPTH from 0): https://www.shimamura.co.jp/update/digital-dj/2019/09/dl-dldj-131966/
27. mixgraph, Drop swap: https://www.mixgraph.io/glossary/drop-swap
28. DJ Gear 2K, Double drop mixing guide: https://djgear2k.com/double-drop-mixing-guide/
29. Crossfader, How to mix hip hop: https://wearecrossfader.co.uk/blog/how-to-mix-hip-hop/
30. DJ TechTools forum, Songs without clear intro/outro: https://forum.djtechtools.com/t/songs-for-mix-without-clear-intro-outro-spots/38359
31. DJ TechTools forum, How much of a song do you play at a club: https://forum.djtechtools.com/t/at-a-club-how-much-of-a-song-do-you-typically-play/21548
32. DJ TechTools forum, Never use the crossfader? (hip-hop cutting, snares): https://forum.djtechtools.com/t/never-use-the-crossfader/36231?page=2
33. Digital DJ Tips, Fader cut fundamentals: https://www.digitaldjtips.com/fader-cut-fundamentals-free-lesson/
34. Digital DJ Pool, DJ EQ mixing for beginners: https://digitaldjpool.com/blog/dj-eq-mixing-for-beginners/
35. DJ TechTools, EQ: critical DJ techniques and theory: https://djtechtools.com/2012/03/11/eq-critical-dj-techniques-theory/
36. delamar, DJ Mixtechniken (crossfader cut curve): https://www.delamar.de/dj/dj-mixtechniken-52150/
37. Sample Focus, Advanced transition techniques: https://samplefocus.com/blog/advanced-transition-techniques-dj/
38. mixgraph, Spinback: https://www.mixgraph.io/glossary/spinback
39. DJ TechTools forum, Backspinning to drop in a track: https://forum.djtechtools.com/t/backspinning-to-drop-in-a-track/23606
40. zZounds, A well-placed backspin (beat 3 of the last bar; via search snippet, page 403): https://blog.zzounds.com/2020/01/10/improve-your-mix-with-a-well-placed-backspin/
41. mixgraph, Brake: https://www.mixgraph.io/glossary/brake
42. Crossfader, Vinyl brake tricks: https://wearecrossfader.co.uk/blog/vinyl-brake-tricks-did-you-know/
43. DJ.Studio, DJ scratching for beginners (placement): https://dj.studio/blog/dj-scratching-for-beginners
44. Wikipedia, Scratching: https://en.wikipedia.org/wiki/Scratching
45. DJ wiki, Flare / transformer / chirp (via search snippets; page paywalled): https://dj.fandom.com/wiki/Flare
46. School of Scratch, drills at quarter/eighth/sixteenth subdivisions: https://schoolofscratch.com/baby-scratch-drills-preview/
47. mixgraph, Loop roll: https://www.mixgraph.io/glossary/loop-roll
48. Engine DJ, Understanding roll mode: https://support.enginedj.com/support/solutions/articles/69000858314
49. DJ TechTools forum, Loop rolls: https://forum.djtechtools.com/t/loop-rolls/21751
50. Crossfader, 3 ways to mix house music: https://wearecrossfader.co.uk/blog/3-ways-to-mix-house-music/
51. mixgraph, BPM guide: https://www.mixgraph.io/learn/bpm-guide
52. DJ TechTools forum, Tempo adjust with keylock on: https://forum.djtechtools.com/t/tempo-adjust-with-keylock-on/54201
53. mixgraph, Key lock: https://www.mixgraph.io/glossary/key-lock
54. Wikipedia, Pitch control / VirtualDJ hardware manuals (+/-4/8/16/100 %): https://en.wikipedia.org/wiki/Pitch_control
55. DJ.Studio, DJ tempo change techniques: https://dj.studio/blog/dj-tempo-change-techniques
56. Crossfader, 3 easy transitions to mix any genre: https://wearecrossfader.co.uk/blog/3-easy-transitions-to-mix-any-genre/
57. DJ TechTools forum, Beatmatching house after transition tracks: https://forum.djtechtools.com/t/beatmatching-house-without-sync-after-using-transition-tracks/54169
58. Mixed In Key, Sorting playlists by energy level: https://mixedinkey.com/harmonic-mixing-guide/sorting-playlists-by-energy-level/
59. DJ Will Gill, Set-phase architecture (search snippet only, page 404): https://djwillgill.com/?p=33677 ; ZipDJ, How to structure a DJ set (403): https://zipdj.com/blog/how-to-structure-a-dj-set
60. Pro Mobile DJ, Mixing: how much is too much: https://promobiledj.com/mixing-how-much-is-too-much/
61. Digital DJ Tips, Best Halloween songs for DJs (2025): https://www.digitaldjtips.com/best-halloween-songs-2025/
62. Digital DJ Tips, How do I DJ a Halloween party: https://www.digitaldjtips.com/your-questions-which-tracks-should-i-play-at-a-halloween-party/

Not found / not verified: a written source giving exact bar-alternation patterns for hip-hop chopping (3.2 is
synthesised); feedback percentages on the DJM (the hardware has none; LEVEL/DEPTH is wet/dry); key-lock state during
wide tempo ramps; the Freeverb `room_size` -> RT60 mapping; the set-phase percentages in section 7.
