# Research C: how DJs mix, a preference framework, and the onboarding moment

Dated Oct 26, 2026. Brief: `docs/product/02-research-plan.md`, Track C. Feeds spec v0.2 sections 6.4, 6.5 and 6.7.
Extends `docs/competitive-analysis.md` section 4 and `docs/transition-recipes.md`; does not redo them. Inference is
marked **[inf]**. Sources are numbered [n] at the end.

## Summary (one page)

**The dimensions.** A DJ's mixing style is twelve things we can measure plus three things they tell us about the
screen. Each has a proxy computable from data we already have: the pair features and scores (P), the set log the Deck
app already records (S: recognised sequence, pitch, match offsets, timestamps), or the set recording analysed against
the crate's originals (A).

| # | Dimension | Measurable proxy | Data | Slider or learned |
|---|---|---|---|---|
| 1 | Tempo tolerance | P90 of abs stretch percent over played joins | S | learned, inside the range cap |
| 2 | Pitch range and key lock | hardware range (6/10/16/wide); whether pitch skew tracks tempo drift | asked; S | slider (cap); learned (key lock) |
| 3 | Key strictness | lift: share of played joins with key_raw >= 0.85 vs the crate's base rate | P, S | slider: ignore / warn / prefer |
| 4 | Genre and era spread | share of played joins with style < 0.6; timbre percentile; era entropy per set | P, S | slider: stay in lane / roam |
| 5 | Energy arc | mean energy delta LU per join; BPM slope per transition | P, S | learned |
| 6 | Blend length | bars between B's first match and A's last match | S | learned; "blend / cut" slider sets the default |
| 7 | Cut styles | share of joins with under 2 bars overlap; alternating matches (chops) | S (partly) | learned; palette slider |
| 8 | Echo-outs and effects | decaying beat-fraction repeats after A's last match | A | asked at onboarding; learned later |
| 9 | Vocal handling | share of played joins with vocal_overlap >= 0.35 | P, S | slider: keep apart / overlap fine |
| 10 | Phrase alignment | share of joins landing within 1 bar of an 8-bar boundary of A | S (coarse) | learned |
| 11 | Loops | match offset stalls or repeats by N beats | S | learned, low priority |
| 12 | Mix-in point and felt tempo | B's first matched offset (start vs hook); share of joins at x2 or x1/2 | S | learned |
| 13-15 | Pick difficulty, number of options, data density | the slider values themselves | - | sliders |

**The onboarding flow (under five minutes; only the first two steps are required).**
1. Gear (30 s, three taps): deck type, pitch range (6 / 10 / 16 / wide), key lock on, off or don't know.
2. How you mix (30 s, four taps): one or two cards in DJ words (long blends; quick cuts on the one; echo or effects
   out; a bit of everything) and what you play (genre and era chips built from the crate's own tags).
3. Listen and pick (about three minutes, six to eight pairs): two rendered joins of the same pair from their own crate
   (32-bar blend vs 16-bar swap; swap vs slam; echo-out vs cut; vocals overlapping vs kept apart), "which sounds like
   you?", with "neither". Pairs are chosen adaptively; the renderer runs on the Mac.
4. The sliders, pre-set from the answers, shown once with a skip button (30 s).
5. Then learn from use. "Have a recorded set? Import it" is optional. A "How you mix" page shows what was learned,
   with undo.

**Slider set v1.** Three on the booth screen: pick difficulty (safe to adventurous), options (3 / 5 / 10), data
density (Minimal / Simple / Full). Five in the "How you mix" sheet: pitch range cap; key (ignore / warn / prefer);
style spread (stay in lane to roam); blend to cut (palette order); vocals (keep apart to overlap fine). Every slider
carries a learned-default marker that moves as Deckie learns; the DJ can always override it; presets per gig come later.

**The rule for slider versus learned.** A slider is for something the DJ can name and would change between gigs.
Learning is for what they do without thinking. Learning moves a default, never a setting the DJ touched, and it says
what it changed. Recommend, never prescribe, applies to the learning as much as to the picks.

## 1. The dimensions, defined

Each entry: definition, proxy, and what it drives in `mixer/score.py`. Real-world baselines come from Kim et al.'s
alignment of 1,557 mixes (13,728 tracks, 20,765 transitions, mostly house and trance) [1][2] and mixgraph's 7,243
hand-sequenced transitions [8].

**1. Tempo tolerance.** How far the DJ stretches B to match A. Proxy: P90 of abs(stretch percent) over played joins; the
Deck app already reads pitch from match drift, rounded to 0.5 percent. Drives the `tempo_term` knees (3 / 10 / 16,
reject past 18, written for Mike). Baseline: 86.1 percent of plays stretched under 5 percent, 94.5 under 10, 98.6
under 20 [2]; median BPM gap 1.0, 81.5 percent within 3 BPM [8]. Mike is in the tail, so the general default is 3 / 8
and his profile widens it.

**2. Pitch range and key lock.** The hardware fact and whether master tempo is on. The CDJ-1000MK3 offers 6, 10, 16
or WIDE [13]. Key lock is inferable **[inf]**: with it off, ShazamKit's frequency skew tracks the tempo change; with
it on, the skew stays near zero while the offset drifts. Drives the hard reject (range plus 2) and whether a 6 percent
stretch counts as a semitone in `key_term`.

**3. Key strictness.** Proxy: lift, the share of played joins with `key_raw >= 0.85` divided by the share available in
the crate; 1.0 means key is ignored. Baseline: DJs rarely transpose (2.5 percent of plays, 94.3 percent of those by one
semitone) [2]; the community treats key as a tool, not a rule (competitive analysis section 4). Drives `W["key"]`
(0.14) and whether a clash gates long bass-swap blends.

**4. Genre and era spread.** Proxies: share of played joins with `style_term < 0.6`; mean timbre percentile of played
pairs; entropy of era and kind per set. Drives `W["style"]`, `W["timbre"]` and the cross-family value (0.45). The
djay Match threads ask for exactly this ("no one wants to mix dubstep to country", competitive analysis S29).

**5. Energy arc.** Proxies: mean `energy_delta_lu` per join and BPM slope per transition. Baselines: Mixed In Key's plus
or minus one energy level per transition [9]; mixgraph's median energy gap 4 on a 100 scale, about 1 BPM per
transition [8]. Drives `W["energy"]` and its sign while climbing. Learned only.

**6. Blend length.** Proxy: bars between B's first match and A's last match at A's BPM, bucketed under 2 (cut), 2 to 8,
16, 32 and up. Baseline: transition lengths peak at every 32 beats [1]; 16 to 32 bars is common in house and techno
[8]. Drives the order in `transition()` and `move_options()`, `LONG_BONUS`, and the `phrase` window (8 to 16 bars).
The match offset runs 1 to 3 seconds late (competitive analysis 6.2), so phrase-level precision is available,
bar-level is not.

**7. Cut styles.** Proxy: share of joins with under 2 bars overlap and no echo tail; chops show as A and B alternating
inside 16 bars, which the recogniser's 10-second hysteresis hides today **[inf]**. Drives whether `brake_cut` appears
in `moves[]` and what it is called (Mike did not know "filter out"; the palette must use the DJ's words).

**8. Echo-outs and effects.** Proxy: decaying repeats at 1/2, 3/4 or 1 beat after A's last match (autocorrelation of the
recording) **[inf]**; a reverb throw is a tail without repeats. Needs audio (A). Kim, Yang and Nam show that fader and
three-band EQ curves can be recovered from a mix when the source tracks are known [3]; Deckie has both. Asked at
onboarding, learned later.

**9. Vocal handling.** Proxy: share of played joins with `vocal_overlap >= 0.35` against the crate's base rate. Drives
`VOC` (0.5), the `v >= 0.6` gate and `W["vocal"]`. Mike gave no feedback here; today's rules are design choices.

**10. Phrase alignment.** Proxy: share of joins within 1 bar of an 8-bar boundary of A, from the match offset (coarse).
Baseline: DJs agree on cue points (23.6 percent of pairs identical, 86.2 percent within 16 measures) [2]. Drives
`W["phrase"]`.

**11. Loops.** Proxy: the match offset stalling or jumping back by 4, 8 or 16 beats. Low priority; mostly a renderer
concern (recipes sections 2.3 and 4).

**12. Mix-in point and felt tempo.** Where in B the DJ enters, and whether they think in felt tempo (Mike: "I Put A Spell
On You" stays at 140, double time). Proxies: B's first matched offset; share of played joins at x2 or x1/2. Drives
whether `bpm_in` is read at B's start or hook, the half/double penalty (0.10), and how the crate is organised (Mike's
discs are grouped by start tempo because he mixes in at the start).

**13 to 15. Presentation.** `PAIR_MIN` and the Easy/Harder split; `TOPN` (2+1, 3+2, 10); Minimal / Simple / Full.
Sliders by decision D6.

## 2. Existing taxonomies

**DJ pedagogy** describes moves, not styles: the recipes doc catalogues echo-out, reverb throw, slam, drop mix, chop,
backspin, brake, loop roll and the three house blends (32-bar seamless, 16-bar EQ swap, layering) [10]. The one
style-level split that recurs is by genre: house and trance DJs blend long; hip-hop and open-format DJs cut on the
one and play 30 to 90 seconds per record [10][11]. Nobody publishes a style profile with numbers; the figures are
conventions.

**Mixed In Key.** Camelot compatibility (same code, plus or minus one, A/B swap; plus two as an "energy boost") and
Energy Level 1 to 10 with a plus or minus one rule per transition [9]. No learning.

**DJ.Studio Harmonize.** The richest explicit preset set found: Fuzzy (safe keys) vs Mood (bold key moves); a
BPM-to-Key priority slider with a BPM tolerance (for example 4 BPM); tempo direction; transition style presets
(crossfade, bass swap, filter, echo, user-saved); transition length Auto (follows intros and outros, 2 to 16 bars) or
fixed (for example 32); synchronise tempo on or off [5][6]. Energy is deliberately unused; nothing learns the user [5].
Close to our slider set, minus vocals and minus learning.

**VirtualDJ.** GeniusDJ and LiveFeedback are crowd co-play, "what hundreds of thousands of other DJs play" after a
track, online only; no personal learning is documented [4]. Automix's Smart / Fade / Cut is a three-value transition
taxonomy (competitive analysis S3).

**rekordbox 7.** Track Suggestion combines Era, Mood and Association (metadata rules) with Collection and Streaming
Radar (AI similarity); play history is stored but no feature is documented as learning from it [7]. The one personal
learner is Intelligent Cue Creation: a "CUE Tendency" built from about 30 tracks the DJ cued by hand, with a crowd
tendency as fallback [12]. That is the closest shipped precedent for "import what you did and infer".

**djay.** Match suggests by genre, BPM and key similarity; no learning from history was found; users ask for crate
scoping and a BPM tolerance (competitive analysis S29).

**Academic work.** Kim et al. 2020 measured cue points, transition lengths, tempo and key changes in real mixes [1][2];
Kim, Yang and Nam 2022 recover fader and EQ curves from 5,040 mixes with 50,742 transitions [3]. Raveform (2025) adds
beat-level alignments and a nine-term section vocabulary (Intro, Buildup, Breakdown, Drop, Cooldown, Bridge, Outro,
Ambient-Intro, Ambient-Outro) for 4,902 mixes; the commonest section is 16 measures [14]. Zehren et al. derive
switch-point rules from DJ interviews [15]; Vande Veire and De Bie built a drum-and-bass auto-DJ on genre rules [16];
Chen et al. trained a GAN on real mixes for fader and EQ trajectories [17]. Williams et al. 2025 frame DJ decisions at
three levels (transition, track, mix), list the techniques automatic systems use, and note that repeated exposure to
the same few techniques makes machine transitions recognisable and disliked [18]. DJ-MC is the learning precedent: a
reinforcement-learning playlist agent that models preferences over songs and over transitions, initialised from a
short feedback session, and beats non-sequential baselines with human listeners [19]. Nobody in this literature
elicits one DJ's style; they measure populations.

## 3. Elicitation methods compared

| Method | DJ minutes | Covers well | Covers poorly | Needs | Signal per minute |
|---|---|---|---|---|---|
| Import a recorded set and infer | about 1 | 1, 3, 4, 5, 6, 10, 12 | 7, 8, 9 (coarse), 11 | a recording, the crate, the Mac | highest, when a recording exists |
| Listen and pick (A/B of rendered joins) | 3 to 4 | 6, 7, 8, 9, 3 | 1, 2, 4, 5 | the renderer, their own tracks | high; the only route to 7 to 9 without audio |
| Short conversation (tap cards) | 1 | 2, 4, 7 (named), 13 to 15 | everything numeric | nothing | high for one minute, then flat |
| Sliders | 1 | 2, 13 to 15 | 1, 3 to 12 | nothing | low for style, fine for facts |

Choice beats rating in the cold-start literature: Graus and Willemsen's choice interface took less effort and gave
more satisfying first recommendations than ratings [20]; the GroupLens study found the elicitation strategy changes
both effort and accuracy [21]; active pair selection reports about half the comparisons for the same quality
(preprint) [22]. A/B of rendered joins is choice-based, uses the DJ's own records (no popularity bias, the known
weakness of choice-based onboarding [20]), and varies exactly what a log cannot show: blend length, cut style,
effects, vocal overlap. Risks: a robotic render makes them pick "neither" (keep that option, count it), and it needs
the Mac renderer (track A decides whether a light version runs on device). Sliders alone fail for the reason Mike
showed: DJs do not know their numbers and did not recognise "filter out". The cards are for what only they know (gear,
what they play), as taps, not typing. Importing a set is the best signal per minute of attention but not universal;
the Deck app's own recordings make it routine after the first gig.

## 4. The learning loop and the mapping to score.py

**Events, in order of weight.** (a) Played-next: A then B recognised, with pitch, overlap bars and time of night.
(b) Pin then played. (c) Pin not played: weak positive for B, weak negative for the join. (d) Shown for at least 20
seconds, and the DJ played a different track that was also on the list: a pairwise choice, the same shape as the A/B
step. (e) Explicit skip. (f) Shown and ignored while something off the list played: almost no information, since the
pick may not have been seen. Skips are noisy even in streaming, where sessions split into "listener" and "skipper"
types [23]; weight them lightly.

**Model.** Keep it inspectable. Per dimension, a running robust quantile with exponential forgetting (half-life about
five gigs), seeded by the onboarding answer. Per pair, a played-after count (a personal GeniusDJ) as a small prior on
the score. Weight learning only after about 50 played joins (a mix averages 12.9 transitions [2], so four gigs), as a
regularised logistic model over the eight terms of shown-versus-played picks with the current `W` as the prior.
Everything on device, in the crate file (D2, D3). Nothing moves a slider the DJ has touched; learning moves the
default marker, and the "How you mix" page lists each change with undo.

**Mapping.**

| Dimension | score.py knob today | Learned or slider effect |
|---|---|---|
| Tempo tolerance | `tempo_term` knees 3 / 10 / 16; reject at 18 | knees follow P50 / P90 of played stretch; reject = cap + 2 |
| Pitch range, key lock | hard-coded for the MK3 | cap from the slider; key-lock state switches the semitone reasoning |
| Key strictness | `W["key"]` 0.14; no gate | ignore 0.05; warn 0.14 (label only); prefer 0.25 plus a clash gate on `bass_swap_32` |
| Style and era spread | `W["style"]` 0.13, `W["timbre"]` 0.12, cross-family 0.45 | stay in lane 0.20 / 0.15 / 0.30; roam 0.06 / 0.08 / 0.70 |
| Energy arc | `W["energy"]` 0.11, symmetric | learned sign and slope; asymmetric penalty for drops while climbing |
| Blend length | `transition()` order; `phrase` window 8 to 16; `LONG_BONUS` | palette order from the slider; window and bonus from learned bars |
| Cut styles | `brake_cut` always in `moves[]` | cut-first DJs: slams and chops first; blend-first DJs: brake only past the cap |
| Echo-outs and effects | `quick_blend_echo` as the vocal fallback | effects-out DJs: echo offered on every pair; others: only where beats cannot match |
| Vocal handling | `VOC` 0.5, gate at `v >= 0.6`, `W["vocal"]` 0.11 | keep apart: gate 0.45; overlap fine: gate off, weight 0.04 |
| Phrase alignment | `W["phrase"]` 0.08 | learned, 0.04 to 0.14 |
| Mix-in point, felt tempo | `bpm_in` at B's start; x2 penalty 0.10 | hook-entry DJs: `bpm_in` at the hook; felt-tempo DJs: penalty 0.02 |
| Difficulty, options, density | `PAIR_MIN` 0.45, `TOPN` 8, app modes | sliders, direct |

The right-hand values are starting points **[inf]**; they need the measure-then-listen pass the weights had in October.

## 5. Mike, the first data point

**The sample is thin but real.** Two "final mix" files from the web page (Oct 23 and 24,
`pool/newfiles/mike_final_mix_*.txt`): his ON lists per disc (Oct 24: 52 singalongs on CD1, 54 mix-ins on CD2),
toggles against Christopher's picks (46 changes, then 41), one note ("Extended dance remixes"), STARRED "(none)", CHAINS
"(none)"; `mike_chains.json` was never produced. Plus the verbatim feedback in `BRIEF.md` section 7 and the live
session on Oct 24. No recorded set has been analysed, so dimensions 6 to 11 rest on what he said and what Christopher saw.

**What the sample says.** CD2 (mix-ins) is 70 percent remixes, edits and extended versions, median 126.5 BPM, 43 of 54
tracks between 120 and 134; CD1 is 55 percent remixes, median 124, spread 81 to 155, with 20 Halloween records. On Oct
24 he dropped the newest hard records above 130 (GNARLY, Fcukers, LCD Soundsystem, Unholy, OMG!) and re-added 1990s to
2010s hits and 90 to 105 BPM hip-hop edits he had removed the day before. That flip (38 removals on Oct 23, 28 of the
same kind added back on Oct 24) is the lesson for the loop: selection toggles are noisy; plays are not.

**His profile, as the v1 flow would have captured it.**

| Dimension | Value | Source |
|---|---|---|
| Tempo tolerance | up to about 16 percent; the curve was rewritten for him | live session; `project-mixer-toolkit.md` |
| Pitch range, key lock | CDJ-1000MK3 at 16; master tempo unknown | gear; open question |
| Key strictness | cares about the number, not as a score; key chip removed for clutter | app rounds |
| Style and era spread | "extended dance remixes"; 1990s to 2010s pop and dance, hip-hop edits; style ignored was his main complaint | note, ON lists, live |
| Energy arc | climbs by tempo; discs in 5-BPM folders by start tempo | disc design |
| Blend length | long progressive blends in and out; blends offered first | live session |
| Cut styles | objected to "brake"; asked what "filter out" meant | live session |
| Effects, vocals, phrase, loops | no data; the vocal rules are design choices, not learned | coordinator's note |
| Mix-in point, felt tempo | mixes in at the start of B; "Spell On You" at 140, double time | disc design; live |
| Presentation | ten options on the web page; Simple 2+1 or Full 3+2; Minimal toggle; no chips he cannot read; BPM, pitch and disc location prominent | eleven app rounds |

Mike would answer step 1 with "CDJ, 16", step 2 with "long blends" and the dance-remix chips; the A/B step would
confirm blend-first and fill the unknowns (effects, vocals); the set log would widen his tempo knee from the general
3 / 8 to 3 / 10 / 16 within one gig. The Oct 24 scorer rewrite was, in effect, the first manual run of this loop.

## 6. Open questions

1. Master tempo on the MK3: on, off or per record? It changes the key reasoning and is inferable from the skew.
2. Chops and echo-outs from a phone microphone: hysteresis hides chops; effects need audio analysis against the
   originals (track A decides where that runs).
3. The renderer on device for the A/B step, or Mac-only onboarding with cards and sliders as the phone fallback.
4. Sets where the automix plays must be excluded from learning; detect by the known mix file.
5. Whether the DJ sees and edits the learned numbers (proposed yes, on "How you mix"), and gig presets.
6. Sample size: four gigs to a stable profile at 13 joins an hour; a wedding DJ at 60 songs a night gets there in one.
7. The mapping table's right column is untested; measure, then listen.

## Sources

1. Kim, Choi, Sacks, Yang, Nam, "A Computational Analysis of Real-World DJ Mixes using Mix-To-Track Subsequence
   Alignment", ISMIR 2020: https://arxiv.org/abs/2008.10267 ; https://archives.ismir.net/ismir2020/paper/000352.pdf
2. The same authors' results summary (dataset counts, tempo, key and cue-point statistics):
   https://mir-aidj.github.io/djmix-analysis/
3. Kim, Yang, Nam, "Joint Estimation of Fader and Equalizer Gains of DJ Mixers Using Convex Optimization", DAFx 2022:
   https://dafx2020.mdw.ac.at/proceedings/papers/DAFx20in22_paper_33.pdf
4. VirtualDJ manual, GeniusDJ and LiveFeedback: https://virtualdj.com/manuals/virtualdj/interface/database/geniusdj.html ;
   https://virtualdj.com/manuals/virtualdj/interface/database/geniusdj/livefeedback.html
5. DJ.Studio help, Harmonize (previously Automix): https://help.dj.studio/en/articles/7878402-automix
6. DJ.Studio help, Settings menu: https://help.dj.studio/en/articles/8105773-settings-menu
7. rekordbox 7 FAQ, Track Suggestion and Radar: https://rekordbox.com/en/support/faq/operation-hints-7/
8. mixgraph glossary, Blend (7,243 hand-sequenced transitions): https://www.mixgraph.io/glossary/blend ; BPM guide:
   https://www.mixgraph.io/learn/bpm-guide
9. Mixed In Key, energy levels and Camelot rules: https://mixedinkey.com/harmonic-mixing-guide/sorting-playlists-by-energy-level/ ;
   https://mixedinkey.com/workflows/change-energy-with-camelot-wheel/
10. `docs/transition-recipes.md` and its 62 sources, in particular Crossfader's three house methods
    (https://wearecrossfader.co.uk/blog/3-ways-to-mix-house-music/), Digital DJ Tips' five transitions, and NI's
    DJ transitions (https://www.native-instruments.com/blogs/blog/dj-transitions)
11. Wikipedia, DJ mix (genre-driven blending vs cutting): https://en.wikipedia.org/wiki/DJ_mix
12. rekordbox Intelligent Cue Creation (personal CUE Tendency from about 30 cued tracks):
    https://rekordbox.com/en/feature/overview/ ; https://djmag.com/tech/rekordbox-7-released-alphatheta ;
    https://music.loop.fans/ai/rekordbox-ai-review-a-new-era-of-intelligent-djing-in-the-pioneer-ecosystem
13. Pioneer CDJ-1000MK3 manual (tempo ranges 6 / 10 / 16 / WIDE, master tempo):
    https://www.manualsbase.com/manual/57970/cd_player/pioneer/pioneer_cd_player_cdj-1000mk3/ ;
    https://www.digitaldjtips.com/stop-dont-spin-on-cdjs-until-youve-checked-these-5-settings/
14. Raveform dataset, TISMIR 2025: https://transactions.ismir.net/articles/10.5334/tismir.288
15. Zehren, Alunno, Bientinesi, "Automatic Detection of Cue Points for DJ Mixing": https://arxiv.org/abs/2007.08411
16. Vande Veire, De Bie, "From raw audio to a seamless mix", EURASIP 2018:
    https://asmp-eurasipjournals.springeropen.com/articles/10.1186/s13636-018-0134-8
17. Chen et al., "Automatic DJ Transitions with Differentiable Audio Effects and GANs", ICASSP 2022:
    https://arxiv.org/abs/2110.06525
18. Williams, Meehan, Lattner, Pauwels, Barthet, "Temporal Considerations in DJ Mix Information Retrieval and
    Generation", TIME 2025: https://drops.dagstuhl.de/storage/00lipics/lipics-vol355-time2025/LIPIcs.TIME.2025.20/LIPIcs.TIME.2025.20.pdf
19. Liebman, Saar-Tsechansky, Stone, "DJ-MC: A Reinforcement-Learning Agent for Music Playlist Recommendation",
    AAMAS 2015: https://arxiv.org/abs/1401.1880
20. Graus, Willemsen, "Improving the User Experience during Cold Start through Choice-Based Preference Elicitation",
    RecSys 2015: https://doi.org/10.1145/2792838.2799681 ; follow-up on popularity bias: https://ceur-ws.org/Vol-1679/paper4.pdf
21. Rashid et al., "Getting to know you: learning new user preferences in recommender systems", IUI 2002:
    https://files.grouplens.org/papers/voi-final.pdf
22. Hodge-guided active preference elicitation for pairwise ranking (preprint, unreviewed):
    https://www.researchgate.net/publication/415251241_Hodge-Guided_Active_Preference_Elicitation_for_Efficient_Pairwise_Ranking
23. Meggetto et al., "On skipping behaviour types in music streaming sessions", CIKM 2021:
    https://strathprints.strath.ac.uk/78436/ ; "Negative Feedback for Music Personalization": https://arxiv.org/abs/2406.04488
24. Internal: `mixer/score.py`, `BRIEF.md` section 7, `docs/history/project-mixer-toolkit.md`,
    `pool/newfiles/mike_final_mix_2026-10-23.txt` and `_2026-10-24.txt`, `pool/newfiles/apply_mike.py`,
    `deck-app/Deck/Sources/Recognizer.swift` (history, hysteresis) and `Mixing.swift` (pinned, exclude).
