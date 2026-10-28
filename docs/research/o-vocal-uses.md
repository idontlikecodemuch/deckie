# Research O: how DJs use vocals, and what each track's record should say about them

Dated Oct 28, 2026. Question (Christopher): DJs mix vocals in and echo them out; what per-track vocal data should the
crate hold so the app can help? Read first: `transition-recipes.md`, `c-dj-preferences.md`, `e-dj-vocabulary.md`,
`j-vocal-tool.md` (1, 2, 3.1), `spec-condensed.md`, `mixer/README.md` (Mix windows, score.py).
**Method and limits.** WebFetch could not reach any host here (wearecrossfader.co.uk, mixgraph.io, digitaldjtips.com,
attackmagazine.com failed to resolve; they need allowing in the network settings), so no page was read in full. Every web
claim comes from WebSearch summaries and is marked (2nd); "(2nd, x2)" = two summaries agree. [inf] = my inference.

## Summary
1. DJs use vocals six ways: keep two apart; hand off at the end of a sung line; lay an acapella over a beat; tease the
   next hook; echo or reverb out the last line; leave a gap so the crowd sings. Today's data covers "keep apart" well,
   "hand off" and "echo out" halfway, and tease, acapella and singalong not at all.
2. On 90s and 2000s pop the vocal is on nearly every bar (README: voice head 0.85 to 1.0 on most pop), so "vocal-free" is
   rare. What helps is where each sung line starts and ends, and where the hook is.
3. Add a list of vocal spans (bars and beats), the first and last sung beat, free gaps and a hook list. Most come from
   Apple's 50 ms activity and its `ranges`. Per-bar probability alone gives spans and gaps; hooks and roles need more.

## 1. The six ways DJs use vocals
**1. Keep two vocals apart.** Mix where neither track sings, or bring B in over A's instrumental outro. If both sing,
overlap 4 to 8 bars, not 16 to 32; two rap tracks over 16 bars is "almost always a trainwreck" (2nd, mixgraph). Drop A's
vocal at its breakdown, bring B's in at its intro (2nd). Let A's line finish; cutting mid-word "sounds amateur" (2nd). Cut
B's mids, then swap (recipes 5). No clean outro: loop a hook or beat-only bars as a break (2nd, DJTT forum; recipes 2.3).
Needs: per-bar vocal presence both sides; free intro and outro length; rapped or sung.

**2. Hand off at the end of a sung line (vocal in, vocal out).** A's last line ends on a phrase boundary, B's first line
starts on the next: cut on the one, drop mix or word-play (recipes 2.1, 3.3). If B's vocal has a pickup before its
downbeat, start B a beat early, "drop on the four" (recipes 2.1). Pool edits serve it: "acapella in" is about 8 bars of
bare vocal ahead of the beat (2nd, Beatsource); intro edits add 8 bars of beat (2nd, DJcity).
Needs: last sung bar and beat of A; first sung bar and beat of B; pickup flag; does the line end on a phrase boundary.

**3. Acapella over an instrumental.** Must match: tempo within a few BPM (key lock holds at 5 or 6 percent, recipes 6); key
the same or one Camelot step (2nd, x2); and the beat side has no vocal of its own. Start the vocal at a breakdown or drop,
cued on its first word or a bar early, counting in eights (2nd, Digital DJ Tips). An acapella has no beat, so DJs copy the
grid from the full track (2nd). Shifting a vocal costs: listeners preferred its original key (2nd, arXiv 2103.14208).
Without a real acapella the DJ needs stems (Serato, djay, VirtualDJ) (2nd).
Needs: a vocal-free stretch of 8+ bars (beat side); a vocal span in bars (vocal side); sung or rapped; the grid.

**4. Tease the next hook.** 4 to 8 bars of B's most recognisable line over A, on a phrase boundary, then pulled away, not
blended in; once or twice a set (2nd, mixgraph; e-dj-vocabulary, Tease). Pop version: loop B's intro under A's verse, extend it under
A's chorus, fade A's chorus into B's verse (2nd, DJTT, mixing pop).
Needs: the hook's start and end bar; a bar where A's vocal is not in the way; B's vocal-free intro to loop.

**5. Echo or reverb out the last line.** Open the echo on the last word in the last beats of a phrase, cut A dry on the one,
let 2 to 4 bars of tail ring under B (recipes 1.1). A 1-beat echo is "often ideal for a quick vocal exit" (recipes [9]);
engaging mid-phrase "repeats a fragment that does not resolve" (recipes [2]). The tail needs B's first 2 to 4 bars
vocal-free or it blurs [inf]. With stems, DJs echo only the vocal and let the beat run (2nd, x2: Serato vocal-echo pad, djay).
Freezing a vocal phrase over B's breakdown is a known move (2nd, DJTT forum).
Needs: A's last sung bar and beat; does it end on a phrase boundary; are B's first 2 to 4 bars vocal-free.

**6. Leave room for the crowd to sing.** Drop or dip the music (or just the vocal, with stems) on the chorus so the room
sings. DJ TechTools calls it a classic and a cliche that a singalong set forgives (2nd); r/Beatmatch DJs "loop a fun
vocal" (`codex-community.md`). Needs: the line's bar span; is it exposed (vocal loud, drums and bass quiet); the exit bar.

**Club versus party.** Club DJs treat the vocal as a hazard: long blends over beat-only intros, a tease or two, judged on
the mix. Mobile and wedding DJs treat it as the payoff: "about the songs, not the DJ" (2nd), whole song or a quick cut to
the chorus (recipes 7; e-dj-vocabulary [92]), radio-style joins, edits with a 16 to 24 beat intro and 15 to 20 s of chorus
(2nd, thread unidentified), unplanned requests (2nd). [inf] Clean versions matter at weddings (explicit flag; not
searched). With vocals everywhere the usable moves are hand-off, hook cut, last-line echo and intro-under-verse; only 39
percent of the pool has 8+ vocal-free intro bars, 17 percent 16+ (j-vocal-tool 1).

## 2. What Deckie's data supports today
Today: per-bar `vocal_prob`; `mix_in`/`mix_out` with `vocal_free_bars`, `first_vocal_bar`, `last_vocal_bar`; sections; the
8-bar lattice; per pair `vocal_overlap`, the 0.6 gate, echo-out or cut at v > 0.5 (README, score.py). `ranges` is not stored.

| Use | Supported? | Missing |
|---|---|---|
| 1 Keep apart | Yes: overlap term, windows, gate, echo fallback | rap vs sung; sampled vocals read as none (J); mean hides 4 vs 16 bars |
| 2 Hand off | Half: first and last vocal bar, bar resolution | the beat, pickup, phrase-end flag, list of lines |
| 3 Acapella | No: free stretches only at start and end | mid-track gaps, vocal-only spans, version kinds |
| 4 Tease | No | any hook; sections have no verse or chorus |
| 5 Echo out | Half: fires when vocals overlap | where the last word is; B's first 2 to 4 bars as tail room |
| 6 Singalong | No | the line, and whether it is exposed |

## 3. Data to add to each track's record
A: from signals already computed (Apple 50 ms vocal, drum and bass activity; `ranges`; the lattice). Cheap.
1. `vocal_spans`: [start, end] in bars plus beats, from `ranges` (J 3.1: median 7 per track) - first and last sung point,
   gaps, and uses 1, 2, 3, 5 in one list.
2. `first_vocal`, `last_vocal` as bar and beat, and `pickup` (sung within a beat before a downbeat) - drop on the four,
   echo on the last word. The per-bar mean cannot show a beat; the 50 ms series can.
3. `intro_free_bars`, `outro_free_bars` from the spans, plus `intro_kind`, `outro_kind` (beat only, ambient, vocal, fade) -
   which intro can be looped or teased under, and tail room for an echo.
4. `free_gaps`: vocal-free stretches of 8+ bars anywhere, starting on the lattice - where A's vocal drops out, where an
   acapella fits, where to loop.
5. `exposed_vocal`: spans with vocal high and drums and bass low [inf] - singalong moments and acapella-style hooks.
6. `span_end_offset`: each span's start and end, in beats from the nearest 8-bar point - hand off or echo only near zero
   (off-phrase reads as a mistake, recipes 0).

B: needs a new step.
7. `hooks`: up to three {start_bar, end_bar (4 to 8), strength, sung}, strongest first - tease, hook entry, quick mix,
   singalong. Repetition plus loudness on the similarity matrix we already build [inf].
8. Verse and chorus labels on vocal sections (rekordbox names Intro, Verse, Bridge, Chorus, Outro for pop, e-dj-vocabulary
   [76][77]) - DJs cue at "first verse" or "the chorus".
9. `vocal_kind` per span: sung, rapped, spoken, chopped or sampled, choir - rap over rap is the worst clash (2nd); sampled
   vocals read as none (J 1). From SoundAnalysis `singing`, `rapping`, `speech`, `choir_singing` (J 3.2) or a stem pass.
10. `vocal_role` per span, lead or backing, and vocal level against the mix in dB - backing and ad-libs overlap safely, a
    lead does not [inf]. Needs a vocal stem (the Mac pass, J). Not v1.
11. `version` (acapella, instrumental, clean, radio, extended, intro edit), `version_of`, and `explicit` from the tag - a
    real acapella in the crate is the easy route to use 3 [inf]; from file name and tags.
12. Later: `lyric_lines` with times; rekordbox shows word- and line-synced lyrics (2nd). Lyric text is licensed [inf]; not v1.
Size: spans, gaps and hooks are about 100 numbers a track, well inside the 10 KB budget.

## 4. What per-bar probability gives, and what needs more
Per-bar probability alone (threshold, smoothing): first and last sung bar; free intro and outro; free gaps; spans at bar
resolution; pair overlap (done). With the 50 ms series and drum and bass activity we hold: the beat of the last word, the
pickup, exposed vocal. With the lattice: span ends against phrase boundaries. Needs more:
- **Line-level phrases.** `ranges` bridges dips, so spans are verse-sized. For the last line use the final fall of the 50 ms
  series [inf]; a full list of lines needs a minimum-gap rule tuned on the listening set.
- **Hook, verse, chorus.** A repetition detector plus loudness and vocal density. "Recognisable" is not in the audio (a DJ
  picks the title line): detect candidates, let the DJ confirm with one tap, stored [inf].
- **Lead vs backing, rapped vs sung vs chopped.** A stem or classifier; the activity series cannot say (J). Lyrics and
  word-play need speech recognition or a lyrics source; later.
- **What "vocal" means** (J open question 1, P13): is someone singing (probability), is it the lead (stem), will the room
  know it (hook, one tap). The vocal slider should mean the first two.
- **Next:** add last sung beat, first sung beat, hook and exposed line to the listening set (j-vocal-tool 7); store
  `vocal_spans` and the A items; prototype the hook detector on the 373 tracks against Christopher's picks.

## 5. How other software handles it today
Only rekordbox marks where vocals are: an AI model (Qosmo with AlphaTheta, 6.0.1, 2020) draws a blue band on the waveform;
a third-party tool says per-frame confidence sits in the `.2EX` file (2nd; unverified). It also shows word-, line- or
un-synced lyrics (2nd). Serato Stems, djay Neural Mix, VirtualDJ and DJ.Studio separate vocals and add stem echo, crossfades
or swaps; I found no vocal map or hook marker in them (2nd). Mixed In Key gives key, BPM, energy, up to 8 cue points,
mashup suggestions and stem export; no vocal timing or lyrics (2nd). A vocal map, last-word marker and hook for any DJ's
crate, burned CDs included, looks open [inf].

## Sources
Repo: `docs/transition-recipes.md` ([2], [9] there); `docs/research/c-dj-preferences.md`, `e-dj-vocabulary.md` ([76], [77],
[92]), `j-vocal-tool.md`, `codex-community.md`; `docs/product/spec-condensed.md`; `mixer/README.md`.
Web (all (2nd): WebSearch summaries only; no page fetched):
1. mixgraph, Vocal mixing guide: https://www.mixgraph.io/learn/vocal-mixing-guide
2. mixgraph, Tease: https://www.mixgraph.io/glossary/tease ; Echo out: https://www.mixgraph.io/glossary/echo-out
3. Digital DJ Tips, DJ with acapellas: https://www.digitaldjtips.com/how-to-dj-with-acapellas/ ; beatgrid acapellas:
   https://www.digitaldjtips.com/the-easy-way-to-beatgrid-acapellas/
4. Mixed In Key, stems: https://mixedinkey.com/workflows/use-stems-in-mixed-in-key-pro/ ;
   https://magneticmag.com/2025/07/mixed-in-key-11-2-pro-brings-stem-separation-and-smarter-mashups-to-your-workflow/
5. rekordbox vocal detection: https://rekordbox.com/en/feature/overview/ ;
   https://djmag.com/news/pioneer-dj-add-new-vocal-detection-analysis-rekordbox-dj-601 ; https://qosmo.jp/en/news/pioneer-dj-2 ;
   djcues (`.2EX` claim): https://pypi.org/project/djcues/
6. rekordbox 6 lyric guide: https://cdn.rekordbox.com/files/20200324114337/rekordbox6.0.0_lyric_function_operation_guide_EN.pdf
7. Serato Stems: https://serato.com/dj/pro/stems ; https://www.digitaldjtips.com/real-time-stems-separation-comes-to-serato-dj-software/ ;
   https://music.loop.fans/ai/serato-stems-ai-review-revolutionizing-live-dj-remixing
8. djay Neural Mix: https://help.algoriddim.com/user-manual/djay-ios/neural-mix/overview ;
   https://community.algoriddim.com/t/echo-effect-on-voice-stem-doesnt-fully-fade-out/32737
9. DJ.Studio, Making mashups: https://dj.studio/academy/making-mashups
10. DJ TechTools, mixing pop: https://djtechtools.com/2014/04/20/dj-tips-how-to-mix-pop-music/ ; 5 cheap DJ tricks:
    https://djtechtools.com/2014/06/28/5-cheap-dj-tricks-and-how-to-avoid-them
11. DJ TechTools forum, mix techniques thread: https://forum.djtechtools.com/t/the-official-mix-techniques-thread/19065?page=2
12. Beatsource, DJ edits glossary: https://news.beatsource.com/?p=14137 ; DJcity support:
    https://support.djcity.com/hc/en-us/articles/34409884914708-What-type-of-music-does-DJcity-provide
13. PCDJ, mobile vs club: https://pcdj.com/mobile-dj-club-dj-lines-are-getting-more-and-more-blurred/ ; wedding vs club:
    https://pcdj.com/how-are-wedding-djs-and-club-djs-different/
14. VirtualDJ forum, wedding tips (16 to 24 beat intro; thread unidentified between these two):
    https://virtualdj.com/forums/56337/Music_discussion/First_Gig%21_-_Wedding_DJing_Tips_Please%21.html ;
    https://virtualdj.com/forums/34066/Music_discussion/Mix_Length.html
15. Mashup research: https://arxiv.org/pdf/2103.14208 ; Davies et al., AutoMashUpper:
    https://staff.aist.go.jp/m.goto/PAPER/IEEETASLP201412davies.pdf

Not verified: any page text (fetch blocked); the `.2EX` per-frame confidence; whether any app besides rekordbox maps vocals
(absence is from summaries only); wedding-DJ practice of muting a vocal for a singalong (no direct source); clean-version
practice; acapella key and tempo limits beyond the 5 to 6 percent in the repo.
