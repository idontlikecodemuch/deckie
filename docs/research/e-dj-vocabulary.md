# Research E: the DJ's own words for moves, tempo, key and picks

Dated Oct 26, 2026. Brief: decision D12 and spec v0.3 sections 6.4 and 6.5. Builds on `docs/transition-recipes.md`
(how the moves are done) and `docs/research/c-dj-preferences.md` (what the sliders measure); this report is only about
what to call things. Inference is marked **[inf]**. Sources are numbered [n] at the end; where a page refused the
fetch and only a search snippet was read, the source list says so. Quotes are kept under 15 words.

## Summary (one page)

1. **There is a stable taught vocabulary.** Native Instruments, Digital DJ Tips, Digital DJ Pool, Thomann, Crossfader
   and the mixgraph glossary teach the same core set under the same names: the fade, the cut, the bass swap, the
   filter fade, the echo out, the backspin, the brake and power-off, the loop roll, phrasing, beatmatching, key lock
   [15][16][21][23][1][2]. These are safe public words for every scene.
2. **Length is said in bars.** "8-bar", "16-bar", "32-bar"; a "long blend" is 16 to 32 bars and is the house default
   [2][14][41]. Nobody says "short blend" as a term, but it is plain English and Mike never objected to it.
3. **Two sprint labels fail.** "brake/cut" bundles two moves a DJ keeps apart (a dead stop and a clean cut) and
   "brake" reads as a misspelt "break", which to a DJ is a drums-only section [48][57]. "filter out" appears in no
   source; the taught names are "filter fade" (NI, Digital DJ Pool, mixgraph glossary) and "filter sweep" (mixgraph's
   lesson page) [15][21][1][2]. Mike's two objections match the two weakest labels.
4. **Scenes split on a few words.** House and techno: blend, bass swap, phrase, long. Hip-hop and open format: cut
   and drop on the one, quick mix, chop, doubles, wordplay, scratch, and "blend" means an acapella over another
   record's beat [17][37][63]. Mobile and wedding: play the whole song, fade or "tight, radio style transitions",
   slam-cues [51][92]. Turntablists: scratch names, juggling, transform. Drum and bass, jungle, dancehall: double drop,
   rewind and pull-up [56][64]. The hardware supplies scene-neutral names DJs on CDJs see every night: TEMPO
   ±6/±10/±16/WIDE, MASTER TEMPO, VINYL BRAKE, SLIP, KEY SYNC, KEY SHIFT, HOT CUE, BEAT JUMP [27][28][29].
5. **Range words come from the gear.** Pioneer's fader steps are ±6, ±10, ±16 and WIDE (±100) [27]; Serato and
   Rane say ±8, ±16, ±50 [31]; Traktor 2 to 100 percent [34]. DJs talk in "within 3 BPM", "5 or 6 percent", "one
   semitone is about 6 percent" [3][84]. Key is "in key", "compatible", "a clash", Camelot "same number, plus or
   minus one, A to B", with "+2" as Mixed In Key's "energy boost" [42][43][36].
6. **"Safe" and "left-field" are about the record, not the join.** Floor filler, anthem, banger, heater, hit are the
   safe picks; deep cut, secret weapon, curveball, leftfield are the risky ones [11][12][18][59][60][61]. Deckie's
   pick-difficulty slider ranks how hard the *join* is, so those words would mislead; keep Mike's accepted "Easy /
   Harder" and save "deep cuts" for a later obscurity axis.

### Recommended label set

Popup labels are at most three words, verb-first where a verb exists, with the bar count as a suffix so "blend" is
unambiguous to a hip-hop DJ. The gloss is the long-press line for new DJs. The slang column is what the app should
also accept in search and show in the gloss, never as the primary label.

| Internal (score.py, plan.py) | Public word | Popup label | Plain gloss (long-press) | DJ slang, also called |
|---|---|---|---|---|
| `bass_swap_8` | Short blend | Short blend · 8 bars | Bring the next track in over 8 bars and swap the bass halfway. | bass swap, 8-bar mix, EQ mix |
| `bass_swap_16` | Blend | Blend · 16 bars | Both tracks run together for 16 bars; the bass moves over at the phrase. | 16-bar bass swap, EQ swap, beatmix |
| `bass_swap_32` | Long blend | Long blend · 32 bars | A full 32-bar overlap: highs cross first, then mids, then the bass. | seamless blend, progressive mix, long mix |
| `ramped_blend` | Tempo ramp | Ramp the tempo | Blend while sliding the pitch so the speed drifts to the next track's. | tempo ramp, pitch ramp, ride the pitch up |
| `filter_sweep` | Filter fade | Filter fade | Thin the playing track out with the filter while the next rises under it. | filter sweep, sweep out, HPF out |
| `quick_blend_echo`, `echo_out` | Echo out | Echo out | Cut the track on the one and let its echo ring under the next. | echo freeze, delay out, wash-out, FX out |
| `brake_cut` (cut half) | Cut | Hard cut | The next track starts on the one and the playing one stops dead. No overlap. | slam, drop mix, cut on the one, stop/start |
| `brake_cut` (brake half) | Vinyl brake | Vinyl brake | Slow the track to a stop like a turntable powering down, then cut in. | brake, power-off, power down, tape stop |
| `backspin` | Backspin | Backspin | Spin the track backwards for a beat; the next lands on the one. | spinback |
| `slam` | Cut (open-format flavour) | Slam it in | A hard cut at the end of a phrase with no fade at all. | slam, hip-hop slam, drop on the one |
| `chop` | Chop | Chop · back and forth | Flick between both tracks bar by bar, snares lined up, one bass at a time. | chop mix, cutting back and forth, fader cuts |
| `loop_roll` | Loop roll | Loop roll | Roll the last bar into shrinking repeats; the next track lands on the one. | roll, slip roll, beat roll, stutter |
| `reverb_out` | Reverb wash | Reverb wash | Throw the last bar into reverb, cut, and let the tail sit under the next. | reverb throw, wash-out, FX out |
| `teaser` | Tease | Tease it | Drop in 4 to 8 bars of the next track's hook, pull it back, bring it in later. | teasing, teaser |
| multiplier 1/2 or 2 | Half time, double time | Half time | The next track runs at half (or twice) the felt tempo. | halftime, 2x, doubling up |
| multiplier 2/3, 3/4, 4/3, 3/2 | Transition track | Needs a bridge | Tempos too far apart to match; bridge with a transition edit or a cut. | transition edit, tempo-change track |
| `key_shift_st` | Key shift | Key shift +1 | Shift the next track by a semitone so the keys agree. | key shift, Pitch 'n Time, tonal shift |

Reason strings in `score.py` that should change with the same logic: "stretch" is a software word, DJs say "pitch up
3 percent"; "shaky beat grid" is fine ("beatgrid" is a DJ word [33]); "no vocal clash" is already the DJ's phrase
[39][79]; "clean 16-bar intro" is fine ("DJ intro" [87]).

### Sliders, in the DJ's words

| Slider (spec 6.5) | Label | Ends or values | Why |
|---|---|---|---|
| Pick difficulty | Picks | Easy ↔ Harder | Mike's accepted grouping; "safe/left-field" means obscurity, not join difficulty |
| Options | Picks shown | 3 · 5 · 10 | Mike's own "expand to 10 options" |
| Data density | On screen | Minimal · Simple · Full | Mike's "Minimal" toggle |
| Pitch range cap | Pitch range | ±6 · ±10 · ±16 · wide (Pioneer); ±8 · ±16 · ±50 (Serato/Rane) | the fader's own steps, chosen by the gear answer [27][31] |
| Key | Key | Off · Flag clashes · In key first | "clash" and "in key" are the DJ words [36][43] |
| Style spread | Style | Stay in lane ↔ Open format | "open format" is the scene's name for roaming [15][1] |
| Blend to cut | First choice | Blends first ↔ Cuts first | Mike: "blends first" |
| Vocals | Vocals | No clashes ↔ Overlap OK | "clash of vocals" [39] |

In-set popups (spec 6.5) use the same words: "Widen the range (±16)" rather than "more range"; "Fade" rather than
"fade mix" (the taught name is "the fade" [15][21][23]); "Hard cut" rather than "hard break".

## 1. Dictionary

Alphabetical. "Scene" says who uses the word that way; "all" means every tutorial site teaches it under that name.

| Term | Meaning | Also called | Scene | Src |
|---|---|---|---|---|
| Acapella in / out (edit) | A DJ-pool version with about 8 bars of bare vocal at the start (in) or end (out) so it can be dropped over another beat. | vocal in/out | hip-hop, open format | [45][46] |
| Backspin | Spin the record backwards fast for a rewind sound, then cut to the next on the one. "Backspin" is the US and turntablist word; "spinback" is UK and glossary usage; mixgraph splits them: backspin mid-track, spinback as the exit. One forum poster: never heard "spinback", always "backspin". | spinback, rewind (ambiguous) | all; turntablist origin | [13][24][66][23] |
| Bass swap | The low EQ handed from one track to the other in one move at a phrase boundary; one record carries the bass at a time. | EQ swap, low swap, "hard swap" (slang) | house core; taught to all | [4][15][16][48] |
| Beatmatching | Matching the tempo and phase of two tracks by ear with the pitch fader and nudges; software "sync" replaces it. | beatmixing | all | [49][47][33] |
| Blend | House: a transition where both records play long enough to feel like music, 16 to 32 bars. Hip-hop mixtapes: an acapella laid over another record's instrumental ("the Stephanie Mills acapella blended with Impeach The President"). | beatmix, mix, long mix | house vs hip-hop | [3][14][63] |
| Brake, vinyl brake, power-off | The track slows to a stop like a turntable switched off; power-off is the slower grind. Pioneer: VINYL BRAKE (Beat FX and rekordbox Release FX); Serato: the stop-time dial, "a brake effect"; DJing Tips: "the stop". | power down, tape stop, the stop | all; hardware name | [29][24][37][74][75][23] |
| Break | A drums-only section of 4 to 8 bars inside a record; "breakdown" in dance music is the stripped section before a drop. Not a transition. | drum break, breakdown | hip-hop; dance | [48][57][5] |
| Breakdown, build-up, drop, riser | Structure words: the drums fall away (breakdown), the climb back with risers (build-up), everything lands (drop). Most transitions finish before a drop or start after it. | build, break | house, EDM, DnB | [5] |
| Camelot, Open Key | Mixed In Key's key codes 1A to 12B (A minor, B major); Traktor's Open Key is the same wheel numbered differently (8A = 1m, m minor, d major). rekordbox and Serato can show classical names. | key code | software DJs | [42][7][36] |
| Chop, chop mix | Alternate the crossfader between two running tracks, a bar or phrase at a time; start with four-bar trades. Mike's "cut back and forth". | cutting back and forth, fader cuts | hip-hop, open format | [8][37] |
| Cue, hot cue, memory cue | Cue: set and preview a start point. Hot cue: a saved point fired from a pad (CDJ-3000: 8 per track). Memory cue: a stored marker on the waveform. | cue point | all | [27][47][1] |
| Cut, hard cut | Switch instantly from A to B on a downbeat with no overlap; "hard cut" when deliberately abrupt. Second meaning: lower an EQ band ("cut the bass"). | slam, drop | hip-hop, DnB, open format | [15][23][21][48] |
| Cut on the one, drop on the one, dropmix | Start B on the first beat of a phrase while cutting A; "drop on the four" when B's vocal starts a beat early. Point Blank teaches "drop mixing". | drop mixing | hip-hop | [17][15][52] |
| Double drop | Both tracks' drops landing at the same instant. | | drum and bass | [55][56][5] |
| Doubles, instant doubles | The same track on both decks, slightly offset, for stutters and juggles. | beat juggling | turntablism, hip-hop | [37][89] |
| Echo out | Cut A on the one and let a beat-synced echo ring under B. "Echo freeze" is the software version that holds the tail; Thomann calls echo and reverb exits "wash-outs". | delay out, wash-out, FX out, echo freeze | all | [2][19][23][69][40] |
| Energy boost mix | Mixed In Key's +2 Camelot move (8A to 10A), "advanced", "use carefully"; −5 is "another advanced boost". | | harmonic mixers | [42] |
| Energy level | Mixed In Key's 1 to 10 rating with a plus or minus one rule per transition; mixgraph uses 0 to 100. | energy | software DJs | [44][5] |
| EQ mixing | Swapping bands between tracks over a blend: highs, mids, bass; the bass swap is its core. | EQ swap, three-band mixing | house | [41][15] |
| Fade | B's fader up as A's goes down; the first transition taught; VirtualDJ Automix "Fade"; Digital DJ Tips "the fade-out". | crossfade, fade mix | mobile, radio, beginners | [15][21][23][50][16] |
| Filter fade, filter sweep | Sweep A up a high-pass (or down a low-pass) while B rises underneath; NI and Digital DJ Pool say "filter fade", mixgraph's glossary too, its lesson page "the filter sweep". | sweep out, HPF out, filter mix | house; busy tracks; genre pivots | [15][21][1][2][80][91] |
| Half time, double time | Running a track at half or twice the felt tempo (87 and 174, 95 and 190). | halftime, 2x | hip-hop to DnB, trap | [1][14] |
| Harmonic mixing, in key, key clash | Choosing the next track by key: same code, one step round the wheel, or the A/B swap; anything else risks a clash. | mixing in key | software DJs; house, trance | [58][43][36][7] |
| Intro edit, outro edit, short edit, transition edit | DJ-pool versions: 8 to 32 bars of beat added at the start or end; a 2 to 3 minute cut ("quick hit" is one seller's label); a record that changes tempo inside itself. | intro, quick edit, transition (track) | hip-hop, open format, mobile | [22][45][46][37][73] |
| Key lock, master tempo | Keep the key while the tempo changes. Pioneer: MASTER TEMPO ("without changing the pitch"); Serato and Rane: Keylock; Traktor: Key Lock; DJ.Studio: "pitch lock". | pitch lock, MT | all | [27][31][33][35][47] |
| Key shift, key sync | CDJ-3000 KEY SHIFT: "Each press shifts the key up or down by a semitone"; KEY SYNC picks the least change among same, dominant, subdominant and relative keys; Serato's Pitch 'n Time does the same by pad. | pitch shift, tonal shift | CDJ-3000, software | [27][32][1] |
| Layering | B hot-cued at a vocal breakdown with its bass killed, run under A until the phrase. | | house | [41] |
| Long blend | A 16 to 32 bar overlap; Crossfader's "seamless blend". | seamless, progressive, 32-bar | house, techno, disco | [2][41][14] |
| Loop roll | A momentary loop that returns to where the track would have been (Serato); Pioneer "Roll" and "Slip Roll", Traktor "Beatmasher", Engine "Roll". | roll, slip roll, beat roll | software; build-ups | [67][68][29][88] |
| Loop out | Loop the last beat-only bars of A to make an outro of chosen length. | loop the outro | all | [10][87] |
| Mashup | Parts of two or more songs combined, usually a vocal over another's instrumental; prepared, not live. | bootleg, blend (hip-hop) | all | [38] |
| Nudge, pitch bend, riding the pitch | Nudge: push the platter or jog to fix phase. Pitch bend: the CDJ's name for the jog-ring speed-up. Riding the pitch: correcting with the fader only, so there is no warble; "NOT for beginners". Old slang "throwing"; Traktor "tempo bend". | tempo bend, throwing | all | [27][33][47][48][70][71] |
| Open format | A set that crosses genres, and the DJ who plays one. | | the scene's own name | [15][1] |
| Phrase, phrasing, phrase mixing | 8, 16 or 32 bar blocks; aligning joins to them; "on the one" means a phrase downbeat, not any bar. | phrase matching | all | [47][21][1] |
| Pitch range, tempo range | The fader's reach. Pioneer: ±6, ±10, ±16, WIDE (±100). Serato and Rane: ±8, ±16, ±50. Traktor: 2 to 100 percent. Pioneer labels the fader TEMPO; vinyl and Serato DJs say "pitch". | tempo range | hardware | [27][31][34][30] |
| Quick mix, quick mixing | Play 30 to 90 seconds of each record and cut; Grandmaster Flash's "Quick Mix Theory" (two copies, backspin) is the origin. | short mix | hip-hop, open format, party | [1][53][54] |
| Reverb wash, reverb throw | Reverb opened on A's last bar, dry cut on the one, tail under B; Thomann: reverb "suits tracks with different BPMs". | wash-out, reverb out, FX out | all; big BPM jumps | [23] |
| Rewind, pull up, wheel up | Stop and restart a tune on crowd demand; a sound-system tradition, "omnipresent in UK urban music". Not a transition. | reload | dancehall, jungle, garage, grime | [64][65][93][1] |
| Scratch, scratch in | A short scratch (baby, chirp, stab, transform) as punctuation before B enters; Digital DJ Tips sells a lesson "Scratching In Your Next Track". | scratch stab, cutting | hip-hop, open format, turntablism | [20][82][83] |
| Slam | An abrupt switch, "generally done on the first beat of a bar"; "Hip Hop Slam"; Digital DJ Tips' "stop/start" and "end-to-end" are the same move. | hard cut, cut | open format, hip-hop | [25][26][85][16] |
| Slip, flux mode | The track keeps running underneath while you loop, scratch or reverse; CDJ SLIP, Traktor Flux Mode. | | CDJ, software | [27][33] |
| Spin-in | Launch B by spinning it forward by hand into its first beat; the entrance counterpart of a spinback. | | vinyl | [9] |
| Sync, beatgrid, quantize | Software tempo lock; the beat map it relies on; snapping cues and jumps to it. | | software | [33][49] |
| Tease | Play 4 to 8 bars of B's hook over A, then pull it away; "Once or twice a set is the ceiling." | teaser, teasing | club, hip-hop | [6][81] |
| Tempo ramp | Slide the pitch over a loop or a blend to reach B's tempo (104 to 126 over 16 bars in a Crossfader routine). | pitch ramp, ride it up | open format, genre changes | [1][40] |
| Trainwreck | Two kicks slightly out of time during a blend. | clanger | all (slang) | [48][1] |
| Transition, transition track | The join itself; a "transition track" or "transition edit" is a record built to change tempo (DJcity: moves "from a higher or lower tempo to the original"). | mix, blend, join | all | [3][45][73] |
| Wordplay | Cut from A's last word into B's matching word; a lyric link, a DJ Premier and Pete Rock signature. | word play | hip-hop | [37][72] |

## 2. Range, tolerance and difficulty words

**Tempo.** DJs quote tempo gaps in BPM for small gaps and in percent for the fader: "within 3 BPM" (81.5 percent of
mixgraph's 7,243 planned transitions) [3]; "1-2 BPM unnoticed; 3-5 needs pitch; 6-10 the dancefloor feels it; 10+ is
a gear change" [14]; "stay within 5 or 6 percent" with key lock on, because one semitone is about 6 percent [84].
The fader steps are the gear's words: Pioneer "±6 (0.02%), ±10 (0.05%), ±16 (0.05%), WIDE (0.5%)", WIDE being ±100
[27], ±10 the CDJ default [78]; Serato and Rane "±8%, ±16%, and ±50%" [31][30]; Traktor "from 2% to 100%" in Pro 4
(user report) [34], 8/10/35/50/100 in older builds [90]. Pioneer calls the fader TEMPO and the knob-less jog move
"Pitch Bend"; vinyl and Serato DJs call the fader "pitch" [27][31]. **[inf]** Deckie should show whichever word the
gear answer implies and accept both in search.

**Key.** "In key", "compatible", "harmonically compatible", "a clash" [36][43]. The Camelot moves: "same number",
"±1", "A to B" are "smooth"; "+2" is the "Energy Boost"; "−5" is "another advanced boost"; the risky vocabulary is
"advanced", "dramatic", "tension", "forced" [42]. Open Key's "1m" is Camelot's "8A" [7]. The CDJ-3000's Key Sync ranks
"Same key, Dominant key, Subdominant key, Relative key" [27]; rekordbox phrase analysis labels sections Intro, Up,
Down, Chorus, Outro for dance music and Intro, Verse, Bridge, Chorus, Outro for pop (third-party listing) [76][77].

**Energy.** Mixed In Key: Energy Level 1 to 10, plus or minus one per transition [44]; mixgraph: 0 to 100, median gap
4 between adjacent tracks [5][3].

**Pick words.** Safe: "floor filler" ("a record that reliably brings people to the dancefloor"), "anthem", "bangers",
"hits", "heaters", "crowd-pleaser" [11][12][18]. Risky or rare: "deep cut" (dictionary: "an obscure song by a
well-known musician"; DJs: "two unfamiliar/new/deep cuts" after six hits) [59][18]; "secret weapon" ("works as
reliably as an anthem" but few others play it) [12]; "curveball" and "leftfield" in mix copy ("leftfield house,
classic tracks, and occasional curveballs") [62][61]; "left field" in plain English means from an unexpected direction
[60]. "Played out" means overplayed [18]. None of these describe how hard the join is; for the join, DJs say "easy
mix", "a stretch", "a clash", and Mixed In Key says "smooth" versus "advanced" [42] **[inf]**.

## 3. Jargon versus plain

Three tiers, judged by which sources explain the word without defining it (plain), define it in a beginner piece
(taught jargon), or use it only inside a scene (insider).

- **Plain, any new DJ follows it:** fade, cut, blend (as "mix"), echo out, loop, drop, hook, intro, outro, BPM,
  "in key", hot cue, sync. The djay glossary, written for consumers, defines only beatmatching, BPM, cue point,
  loop, sync and tempo and leaves fade, cut and drop undefined, which is the best evidence they need no gloss [49].
- **Taught jargon, understood after one tutorial:** bass swap, filter fade, backspin, phrase and "on the one",
  key lock and master tempo, slam, drop mix, quick mix, tease, half time, tempo ramp, loop roll, vinyl brake [15][16][21][23].
- **Insider, scene-specific:** wordplay, doubles, chop mix, double drop, Camelot numbers and Open Key, pull-up and
  wheel-up, slip and flux, "hard swap", "throwing", trainwreck, "the stop", spin-in [37][48][24][9][64].

**Words that confuse, and why.**

- *Brake versus break.* Homophones with opposite feel: a brake stops the record, a break is the drums-only section a
  DJ loops or cuts on [48][57]. On a screen "brake" looks like a typo unless it sits next to "vinyl", which is how
  Pioneer and rekordbox print it ("VINYL BRAKE") [29][75]. Thomann itself slips, using "break" for a noticeable
  transition [23]. Mike wrote "break" and objected. Rule: never show "brake" alone.
- *Filter out.* No tutorial names a move this way; in plain English "filter out" means remove something, and the
  object is missing (filter out what?). The taught names are "filter fade" and "filter sweep" [15][21][2]. Mike asked
  what it meant. Rule: "Filter fade".
- *Blend.* House "blend" is a long mix [3]; hip-hop "blend" is an acapella over a beat [63]. A bar count after the
  word ("Blend · 16 bars") settles it.
- *Drop.* The section where everything lands [5], the verb "drop it on the one" [17], and the radio "DJ drop" jingle.
  Use "drop" only with "on the one".
- *Quick mix versus quick blend.* "Quick mix" is the hip-hop practice of 30 to 90 seconds per record [1][53]; a
  "quick blend" would be heard as that. Deckie's 8-bar move is "Short blend".
- *Cut.* Both "switch instantly" and "lower an EQ band" [48]. Fine in a move label, avoid in EQ reasons ("bass off"
  rather than "cut the bass").
- *Pitch versus tempo versus key.* Pioneer's fader says TEMPO and its key control says MASTER TEMPO; DJs say "pitch"
  for the fader and "key" for the note, and "pitch" also names the Beat FX pitch shifter [27][29]. Deckie uses
  "pitch" for the fader (Mike's word) and "key" for the note, never "pitch" for key.
- *Spinback versus rewind.* A spinback ends a track; a rewind or pull-up restarts it on crowd demand [13][64].
- *Transition.* The join, the DJ-pool edit type, and "transition track" the record. Say "join" in the app's prose,
  "transition track" only for the record.
- *Echo in.* Not found as a term in any source; the nearest named moves are "echo freeze" (the tail carried into B)
  [69] and "spin-in" (vinyl) [9]. Open question below.

## 4. The onboarding palette

The chain screen (spec 6.4) shows one join at a time and a tile grid in the style of a rhythm-game prompt. Rules from
the findings: one word family per tile; verb-first where the move has a verb; bar counts on blends; no bare "brake";
"Not sure" and "Something else" always present so the DJ is never forced to lie. Twelve tiles in three rows by family,
plus a second-tap flavour row for the cut family.

| Row | Tiles | Flavour on second tap | Seeds (track C dimensions) |
|---|---|---|---|
| Blends | Long blend · 32 bars, Blend · 16 bars, Short blend · 8 bars, Filter fade | with a tempo ramp | 6 blend length; 1 tempo tolerance (ramp); 9 vocals (long blends imply vocals kept apart) |
| Effects out | Echo out, Reverb wash, Loop roll | | 8 echo and effects; 7 cut styles (effect exits count as cuts) |
| Cuts | Hard cut, Chop, Backspin, Vinyl brake | scratch in; tease first | 7 cut styles; 10 phrase alignment (cuts are on the one by definition); 12 mix-in point |
| Escape | Not sure, Something else, Half time | | nothing, or a note for the "How you mix" page |

Mapping notes: a blend tile sets the blend-length bucket directly (under 2, 8, 16, 32); any cut or effect tile raises
the cut share and keeps `brake_cut` in `moves[]`; "Vinyl brake" or "Backspin" marks a stop-style exit so the renderer
rotates them in; "Chop" marks the alternating style the recogniser cannot yet see; "Filter fade" and "Echo out"
distinguish the two exits `transition()` chooses between at line 193 of `score.py`. Christopher's examples map as: "fade
mix" to Blend, "hard break" to Hard cut, "echo in" to Echo out or Tease (ask), "scratch" to the scratch-in flavour,
"more bass range" **[inf]** to the pitch-range popup "Widen the range".

## 5. Open questions

1. **YouTube titles.** Four searches never returned a youtube.com result; the only video titles seen are Digital DJ
   Tips pages that mirror their videos ("Stop Using Echo Out", "The Only Five DJ Transitions You'll Ever Need",
   "How To Dropmix Like A Pro Hip Hop DJ") [19][16][17]. A human pass on YouTube would confirm which names headline
   tutorials.
2. **Reddit** was unreachable here; the forum usage above is DJ TechTools, NI community, dnbforum, TranceAddict and
   VirtualDJ. Track F covers Reddit.
3. **Two tiles or one for brake_cut.** The recommendation splits it into Hard cut and Vinyl brake; the scorer today
   emits one code. Christopher decides whether the split goes into `score.py` or only into the labels.
4. **Hip-hop "blend".** If Mike's circle uses "blend" for acapella-over-beat, test the bar-count suffix with him.
5. **"Echo in" and "more bass range"** are Christopher's words with no source match; ask what he hears in them.
6. **Serato's own manual wording** could not be fetched (support site refuses); the ±8/±16/±50 figures come from the
   Rane ONE manual and a Serato support snippet [31][30]. Traktor's current range list is a user report [34].
7. **Gear-specific words.** Whether to say "Master tempo" to a CDJ DJ and "Keylock" to a Serato DJ, from the gear
   answer, or one word for all.
8. **Mike's real set recording** will show which of these moves he actually does (chops and echoes in particular),
   which decides the default tile order.

## Sources

1. mixgraph glossary index (categories: Mix moves, Set craft, Deck controls, Turntablism): https://www.mixgraph.io/glossary
2. mixgraph, DJ transition techniques (long blend, cut, filter sweep, echo out, loop and build, breakdown swap): https://www.mixgraph.io/learn/dj-transition-techniques
3. mixgraph glossary, Blend and Transition (7,243 transitions; 81.5 percent within 3 BPM): https://www.mixgraph.io/glossary/blend
4. mixgraph glossary, Bass swap: https://www.mixgraph.io/glossary/bass-swap
5. mixgraph glossary, Drop (breakdown, build-up, double drop, energy): https://www.mixgraph.io/glossary/drop
6. mixgraph glossary, Tease: https://www.mixgraph.io/glossary/tease
7. mixgraph glossary, Open Key: https://www.mixgraph.io/glossary/open-key
8. mixgraph glossary, Chop mix: https://www.mixgraph.io/glossary/chop-mix
9. mixgraph glossary, Spin-in: https://www.mixgraph.io/glossary/spin-in
10. mixgraph glossary, Loop out: https://www.mixgraph.io/glossary/loop-out
11. mixgraph glossary, Floor filler: https://www.mixgraph.io/glossary/floor-filler
12. mixgraph glossary, Secret weapon: https://www.mixgraph.io/glossary/secret-weapon
13. mixgraph glossary, Spinback: https://www.mixgraph.io/glossary/spinback
14. mixgraph, BPM guide (perceptual bands): https://www.mixgraph.io/learn/bpm-guide
15. Native Instruments blog, 5 basic DJ transitions (the fade, the cut, single phrase beatmatch, bass swap, filter fade): https://www.native-instruments.com/blogs/blog/dj-transitions
16. Digital DJ Tips, The only five DJ transitions you'll ever need (basic beatmix, bass swap, end-to-end, fade-out, stop/start): https://www.digitaldjtips.com/?p=2799229
17. Digital DJ Tips, How to dropmix like a pro hip hop DJ: https://www.digitaldjtips.com/dropmix-like-a-pro-hip-hop-dj/
18. Digital DJ Tips, How to pick songs for a DJ set (bangers, deep cuts, heaters, played out): https://www.digitaldjtips.com/how-to-pick-songs-for-a-dj-set/
19. Digital DJ Tips, Stop using echo out (video page): https://www.digitaldjtips.com/stop-using-echo-out/
20. Digital DJ Tips course listing, "Transitions: Scratching In Your Next Track": https://1.digitaldjtips.com/ofsm-sale
21. Digital DJ Pool, 7 DJ transitions every beginner should learn: https://digitaldjpool.com/blog/dj-transitions-for-beginners/
22. Digital DJ Pool, DJ edits explained (intro, outro, quick, clean, transition edits): https://digitaldjpool.com/blog/dj-edits-explained/
23. Thomann, The 5 most important DJ transitions (fading, mix transition, cut, backspin/brake/power-off, wash-outs): https://www.thomannmusic.com/blog/gear/the-5-most-important-dj-transitions/
24. DJing Tips, Backspins, stops and power-offs: https://www.djingtips.com/how-to-dj/backspins-stops-and-power-offs/
25. zZounds, Three DJ transitions to try between songs (slam; search snippet, fetch refused): https://blog.zzounds.com/2019/10/03/three-dj-transitions-to-try-between-songs/
26. BPM Music glossary (slam, hard cut, backspin/spinback; search snippet, page is script-rendered): https://bpmmusic.io/glossary
27. Pioneer DJ, CDJ-3000 operating instructions (PDF mirror; text extracted locally): https://www.fullcompass.com/common/files/87303-CDJ3000UserManual.pdf
28. Pioneer DJ, CDJ-3000X control mapping (TEMPO ±6/±10/±16/WIDE, MASTER TEMPO, KEY SHIFT): https://cdn.rekordbox.com/files/20250907160902/CDJ_XDJ_Control_Mapping_en_CDJ-3000X.pdf
29. Pioneer DJM-900NXS2 manual, Beat FX types (ECHO, ROLL, SLIP ROLL, VINYL BRAKE, PITCH): https://www.manualslib.com/manual/1275366/Pioneer-Djm-900nxs2.html?page=15
30. Serato, Adjusting a track's tempo (pitch range buttons; search snippet, fetch refused): https://support.serato.com/hc/en-us/articles/233437367-Adjusting-a-Track-s-Tempo
31. Rane ONE manual, pitch range ±8/±16/±50 and Keylock (search snippet): https://manualslib.mx/manual/235219/Rane-One.html?page=7
32. Serato, Pitch 'n Time key shift and pitch play (search snippet): https://support.serato.com/hc/en-us/articles/10173686473231
33. Native Instruments, Traktor Pro manual, Global concepts (Key Lock, tempo bend, Master Clock, Open Key, beatgrid): https://docs.native-instruments.com/online-guides/traktor-pro-manual/en/global-concepts
34. NI community, Traktor Pro 4 tempo range 2 to 100 percent (user report): https://community.native-instruments.com/discussion/comment/209556
35. Crossfader, Key lock and master tempo: https://wearecrossfader.co.uk/blog/key-lock/
36. Crossfader, Mixing in key for DJs (Camelot, Open Key, classical; clash; in key): https://wearecrossfader.co.uk/blog/mixing-in-key-for-djs/
37. Crossfader, How to mix hip hop (wordplay, instant doubles, brake effect, stop time, transition tracks, beat juggling): https://wearecrossfader.co.uk/blog/how-to-mix-hip-hop/
38. Crossfader, DJ edits vs mashups vs remixes: https://wearecrossfader.co.uk/blog/edits-mashups-remixes/
39. Crossfader, How to avoid a clash of vocals while mixing: https://wearecrossfader.co.uk/blog/free-dj-lesson-vocals/
40. Crossfader, 12 high-energy DJ transitions (echo out, tempo ramps): https://wearecrossfader.co.uk/blog/12-high-energy-dj-transitions/
41. Crossfader, 3 ways to mix house music (seamless blend, EQ swap, layering): https://wearecrossfader.co.uk/blog/3-ways-to-mix-house-music/
42. Mixed In Key, Change energy with the Camelot wheel (Energy Boost +2, −5): https://mixedinkey.com/workflows/change-energy-with-camelot-wheel/
43. Mixed In Key, Harmonic mixing guide: https://mixedinkey.com/harmonic-mixing-guide/
44. Mixed In Key, Sorting playlists by energy level: https://mixedinkey.com/harmonic-mixing-guide/sorting-playlists-by-energy-level/
45. DJcity support, What type of music does DJcity provide (intro, short edit, transition, acapella; search snippet, fetch refused): https://support.djcity.com/hc/en-us/articles/34409884914708-What-type-of-music-does-DJcity-provide
46. Serato forum, edit pack abbreviations QH = Quick Hitter, SE = Short Edit (search snippet): https://serato.com/forum/discussion/1604726
47. DJ.Studio, DJ mixing terms, the definitive DJ dictionary: https://dj.studio/blog/dj-mixing-terms
48. DJ Courses Online, Short glossary of DJ slang (break, cut, hard swap, spinback, throwing, trainwreck): https://djcoursesonline.com/dj-blog/2018/8/20/short-glossary-of-dj-slang
49. Algoriddim, djay user manual glossary: https://help.algoriddim.com/user-manual/djay-ios/getting-started/glossary
50. VirtualDJ manual, Automix (Smart, Fade, Fade out/Cut in, None): https://www.virtualdj.com/manuals/virtualdj/interface/browser/sideview/automix.html
51. Pro Mobile DJ, Mixing: how much is too much (play the whole song, slam-cues, cold endings): https://promobiledj.com/mixing-how-much-is-too-much/
52. Point Blank, DJ Skills Crash Course ("drop mixing and fade/brake speed transitions"; search snippet, fetch refused): https://www.pointblankmusicschool.com/courses/london/dj-skills-crash-course/
53. Wikipedia, Grandmaster Flash (Quick Mix Theory): https://en.wikipedia.org/wiki/Grandmaster_Flash
54. NPR Fresh Air, Grandmaster Flash transcript (clock theory, needle drops): https://www.npr.org/transcripts/1195668291
55. Wikipedia, Drop (music) (double drop): https://en.wikipedia.org/wiki/Drop_(music)
56. dnbforum, Meaning of double dropping: https://dnbforum.com/threads/meaning-of-double-dropping.30255/
57. Wikipedia, Break (music): https://en.wikipedia.org/wiki/Break_(music)
58. Wikipedia, Harmonic mixing: https://en.wikipedia.org/wiki/Harmonic_mixing
59. Wiktionary, deep cut: https://en.wiktionary.org/wiki/deep_cut
60. Wiktionary, left field: https://en.wiktionary.org/wiki/left_field
61. Mixmag, The best DJ mixes of 2024 so far (leftfield, deep cuts in mix copy): https://mixmag.net/feature/the-best-dj-mixes-of-the-year-2024-so-far-january
62. Radio Blast, Notable broadcasts ("leftfield house, classic tracks, and occasional curveballs"): https://shop.blastradio.com/blogs/blast-radio-news-updates/notable-broadcasts-week-of-10-25-21
63. unkut, Kid Capri: mixtape king (hip-hop "blends", Ron G): https://unkut.com/2005/07/kid-capri-mixtape-king/
64. Dub-Stuy, Wheel it up: a history of the rewind: https://www.dub-stuy.com/wheel-it-up-history-of-the-rewind/
65. Jamaican Patwah, Pull up: https://mail.jamaicanpatwah.com/term/Pull-up/2794
66. TranceAddict forum, What's a spinback: https://tranceaddict.com/forums/showthread/t-104634.html
67. DJ TechTools forum, Loop rolls: https://forum.djtechtools.com/t/loop-rolls/21751
68. DJ TechTools forum, Loop roll in Traktor (Beatmasher): https://forum.djtechtools.com/t/loop-roll-in-traktor/53222
69. DJ TechTools forum, Echo freeze effect in rekordbox DJ: https://forum.djtechtools.com/t/echo-freeze-effect-in-rekordbox-dj/74088
70. zZounds, Using pitch riding to improve your mixing: https://blog.zzounds.com/2020/02/25/using-pitch-riding-to-improve-your-mixing/
71. DJ TechTools forum, Could use some beat matching tips (fader riding): https://forum.djtechtools.com/t/could-use-some-beat-matching-tips/44389
72. Sample Focus, Advanced transition techniques (wordplay): https://samplefocus.com/blog/advanced-transition-techniques-dj/
73. DJ TechTools forum, Beatmatching house after using transition tracks: https://forum.djtechtools.com/t/beatmatching-house-without-sync-after-using-transition-tracks/54169
74. Elephorm, rekordbox performance FX panel (Release FX: Vinyl Brake, Echo, Backspin): https://www.elephorm.com/formation/maitriser-rekordbox-7/maitriser-le-panneau-deffets-dans-rekordbox-mode-performance
75. rekordbox v6.6.0 release notes (VINYL BRAKE added to Beat FX): https://rekordbox.com/en/2021/11/rekordbox-v660-release-information/
76. rekordbox feature page (phrase analysis): https://rekordbox.com/en/feature/djing/
77. CueGen, rekordbox phrase names (Intro, Verse, Bridge, Chorus, Outro, Up, Down): https://github.com/mganss/CueGen
78. MusicRadar, Playing your first gig with CDJs (tempo range default ±10, master tempo): https://www.musicradar.com/music-tech/dj-gear/playing-your-first-gig-with-cdjs-heres-10-essential-features-you-need-to-know-about
79. Beatsource, common DJ mistakes (clashing vocals; search snippet): https://news.beatsource.com/?p=7918
80. Violet Recording, How to do smooth DJ transitions (quick cut, filter sweep): https://violetrecording.com/how-to-do-smooth-dj-transitions/
81. Thomann, DJ systems FAQ (cut in a section "to tease the audience"): https://www.thomannmusic.com/onlineexpert_page_dj_systems_frequently_asked_questions_faqs.html
82. DJ.Studio, DJ scratching for beginners (placement before the next track): https://dj.studio/blog/dj-scratching-for-beginners
83. dnbforum, Scratch and juggle terminology (transform, flare, chirp, crab): https://dnbforum.com/threads/scratch-and-juggle-terminology.1569/
84. DJ TechTools forum, Tempo adjust with keylock on ("stay within 5 or 6 %"): https://forum.djtechtools.com/t/tempo-adjust-with-keylock-on/54201
85. mtesfaldet, 5 basic DJ transitions ("Hip Hop Slam"): http://blog.mtesfaldet.net/2016/04/18/5-basic-dj-transitions-between-2-songs
86. ZipDJ, 10 DJ techniques (spinback as a backup technique): https://www.zipdj.com/dj-techniques/
87. DJ TechTools, Mixing songs that don't have a DJ intro: https://djtechtools.com/2017/09/11/mixing-songs-dont-dj-intro-4-common-techniques
88. Engine DJ, Understanding roll mode: https://support.enginedj.com/support/solutions/articles/69000858314
89. Wikipedia, Beat juggling: https://en.wikipedia.org/wiki/Beat_juggling
90. DJ TechTools forum, Pitch faders (Traktor 8/10/35/50/100): https://forum.djtechtools.com/t/pitch-faders/13316
91. djlearn.de, Filters for DJs: https://djlearn.de/en/how-to-use-filters-dj
92. djsoft forum, Crossfade question (wedding DJ: "tight, radio style transitions"): https://www.djsoft.net/community/threads/crossfade-question.615/latest
93. Jamaica Gleaner, Pull it (forward, pull up): https://past.jamaica-gleaner.com/article/entertainment/20160403/pull-it-father-and-son

Not found or not verified: a Mixed In Key glossary page (its workflow and guide pages were used instead); a DJ TechTools
or Digital DJ Tips glossary page; YouTube video titles (the search tool returned none); Reddit; Serato's own manual
text for Keylock and pitch range; Traktor's current tempo-range list; a written definition of "echo in".
