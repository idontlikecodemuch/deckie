# Halloween DJ tools: competitive analysis, DJ needs and roadmap

Product-analyst report, 2026-10-25. Covers the three things built the week of the party:
**Deck** (iPad listening companion), **Mike page** (phone audition player with "Up next") and the **mixer toolkit**
(analysis, pair scoring, planner, offline renderer). Sources are numbered [S#] and listed at the end.
**[inf]** marks my inference; **[local]** marks a number measured from our own files today.

---

## Executive summary (one page)

**What we have.** A complete loop for one party: analyse 373 tracks (beats, start/end tempo, key, phrase lattice,
vocal timeline, loudness), score 99,832 directed "A mixes into B" pairs with reasons, show those scores live on an
iPad that *hears* what a CDJ-1000MK3 is playing (ShazamKit custom catalogue, offline, with pitch read from frequency
skew and position drift), and render a 144-minute continuous auto-mix with 7 transition types, teasers and a
human-variance layer. No single competitor does all three, and **none of the major DJ apps identifies what's playing
through a microphone** [S1-S6].

**Where we stand against the field.**
* *Live suggestion*: rekordbox 7 (Related Tracks, Radar AI similarity), VirtualDJ (GeniusDJ crowd co-play data),
  djay (Match) and Mixed In Key 11 Pro (DJ Mix Mode) all suggest next tracks [S1][S3][S4][S7]. Ours is the only one
  that explains *how* to do the join: pitch-fader value, join waveform, a move like "blend / echo out", and the window
  to start in. That is the one feature with no direct equal. Theirs learn from what DJs actually play next; ours
  doesn't.
* *Track ID*: the closest rivals are **Beatport Track ID** (May 2026: robust to pitch, stretch, blends and loud rooms,
  phone app) [S8] and the open-source **What's Now Playing EarShot** (Shazam-based, for stream overlays) [S9]. Both
  use the global catalogue. Ours matches only the DJ's own crate, offline, so it knows CD/folder/track numbers, and it
  reads the deck's pitch.
* *Auto-mix*: DJ.Studio (timeline editor, Demucs stems, Mixcloud export) [S10], djay Automix AI [S4], Spotify Mix and
  Apple AutoMix [S11][S12]. Reviewers call the consumer ones "glorified crossfade features" [S13]. Our renderer's
  *vocabulary* is richer than any of them: EQ bass swaps, echo/reverb throws, brakes, backspins, loop rolls, chops,
  scratch stabs, teasers. Its *execution* is weaker than its vocabulary (below).

**The auto-mix's real problems** [local, from `Halloween Mix - full.render.json`]:
1. 19 of 65 joins still dip more than 2 LU after three repair passes (48, then 26, then 19). All 5 chops dip, and 9 dips
   come *after* the overlap, inside B's intro. The repair adds synthetic kick/hat and make-up gain: a band-aid that can
   itself sound artificial.
2. **12 of 31 bass-swap blends join keys that clash on the Camelot wheel** (for example 7B to 4A, 2B to 11B, 3A to 9A).
   The DJ sources say bass swaps between different keys clash even with EQ [S14]. Key detection is only 60-80 % accurate
   on vocal pop, so some of these are false alarms, but nobody has listened to check.
3. 19 of 31 blends are 8-bar swaps, 12 are 16-bar and none are 32-bar. Our own recipes call for 16-32 bars on house and
   disco [S14]. The cause: the vocal model marks most pop bars as vocal, so the mix windows shrink.
4. 17 of 65 joins change tempo by more than 6 % (callouts and the hip-hop stretch). That is 26 %, against roughly 8 % in
   planned sets on mixgraph [S14]. Tempo runs 136, 155, 128 in three songs around 98 minutes in. The energy arc is
   managed by BPM, not by measured energy.
5. Stems are not used. The brief says Demucs is installed, but it is not in the mixer venv or on the PATH [local].
   Nothing listens to the result: QA is loudness and beat-offset numbers only.

**Is there a product?** A small one. The defensible slice is **"a hardware-agnostic booth companion that hears the
room"**: it works with any rig (legacy CDJs, vinyl, borrowed gear, a laptop you can't install on), names the track
from your own crate, reads the pitch, says what to play next and how to get there, and writes a timestamped tracklist
and recording. It is not a big market. Most working DJs are on rekordbox/Serato and Pro DJ Link gear that already
knows what's loaded [S9][S15], and Beatport now owns "ID in a loud room" for phones [S8]. The auto-mix generator is
the most crowded and most legally exposed slice. **Recommendation:** keep everything as a personal tool for now and
spend about 2 weeks on the auto-mix fixes below. Then run a 30-day validation with 5-10 open-format and mobile DJs on
TestFlight before deciding to build a product.

### Top ten recommendations (in priority order)

| # | Recommendation | Area | Effort |
|---|---|---|---|
| 1 | Do a **listening QA pass**: render 20-second clips around every join into one review file, with a sheet to mark keep, fix or replace. Add an automatic check with an onset/spectral-flux "groove continuity" metric | auto-mix | 1-2 d |
| 2 | **Key gate on blends**: no bass swap unless the keys are compatible with both confidences at least 0.5, or a ±1 semitone shift fixes it. Otherwise use an echo-out or a cut | auto-mix | 0.5 d |
| 3 | **Demucs vocal and drum stems** (htdemucs, offline, cached) to (a) replace the EffNet vocal probability, so mix windows grow to 16-32 bars, and (b) render stem-aware blends: B's drums under A's vocal, then a vocal hand-off | auto-mix + scoring | 3-5 d |
| 4 | **Fix lulls at the source**: choose B's entry bar by energy (skip quiet intro bars), never cue B into a breakdown, and for chops run A and B at equal short-term loudness. Drop the synthetic beat filler | auto-mix | 2-3 d |
| 5 | **Energy curve planning**: per-bar energy (loudness, onset density, low band) as the planner's objective, with at most ±1 step per join and a 16-32-bar plateau rule. Smooth tempo moves to about 1-2 % per track except at deliberate callouts | planner | 2-3 d |
| 6 | **Deck: measure recognition in a loud room** with a script that plays catalogue tracks at ±0-12 % pitch through a PA with crowd noise, logging time-to-ID and false switches. Add **tempo-only ±8 % and vinyl ±8/±12 % variants** if needed | Deck | 2 d |
| 7 | **Deck: a set-history strip** (played already, minutes ago) that removes played songs and same-artist repeats from picks. Add a "why this pick" line on the top pick | Deck | 1 d |
| 8 | **Deck: line-in recording option** (a USB audio interface from the mixer's REC out) so recordings are usable. Export the tracklist as CUE and Mixcloud text | Deck | 1-2 d |
| 9 | **Learn from use**: log what Mike actually played after what (from Deck logs and the Mike page chains and stars) and add a small "played after" prior to the scores. This is the start of a moat | scoring | 2 d |
| 10 | **Decide on distribution later**: stay on development installs or TestFlight internal testers. Do not put the bundled catalogue of commercial tracks in the App Store. A product version must build its catalogue on the device from the user's own files | legal | n/a |

---

## 1. Analysis plan (written before the research)

**Questions**
1. Feature by feature, what do the leading DJ tools do that ours do not, and the reverse? Price, platform, and whether
   any of them identifies tracks from the room. (A)
2. What do open-format and party DJs say they want, and distrust, in next-track suggestion, key mixing, auto-mix,
   cue/phrase accuracy, live ID, recording and tracklists? (B)
3. How good is our auto-mix, judged against our own recipe research and against what makes auto-mixes sound robotic?
   What should be fixed first? (C)
4. Where are the Deck app's UX, feature and robustness gaps, and how could it be distributed? What are the legal
   limits of a custom catalogue and of mix redistribution? (D)
5. Is there a product, for whom, which slice, with what moat and what roadmap? (E)

**Sources**
* Internal: the READMEs, `research.md`, `transition-recipes.md`, the Swift sources (`Recognizer.swift`,
  `Mixing.swift`), screenshots `build/shots16-18`, `pairs.json`, `mixes/*.render.json` and `.txt`, and the memory
  notes on the premixed sets, Deck and the toolkit (treated as data).
* External: vendor docs and release notes, trade press (Digital DJ Tips, DJ TechTools, DJ Mag, Mixmag, MusicTech,
  TechRadar, 9to5Mac), DJ forums (Algoriddim community, VirtualDJ, Engine DJ, DJTT, NI, Serato), App Store reviews,
  Apple developer docs and WWDC sessions, and academic fingerprinting papers. The work was split across five parallel
  web-research passes: competitors (two passes), DJ sentiment, now-playing integrations, and legal/distribution.

**Method**
* Competitive: a feature matrix with one row per capability we have, plus the capabilities they have and we lack.
* Sentiment: count the threads and sources found per theme and mark the direction of each. Use short quotes only.
* Auto-mix: quantitative audit of the final render log (join types, lulls, key relations, tempo gaps, window
  lengths) against the recipe targets, then a list of robotic-sounding failure modes from reviews.
* Deck: code read of the recognition state machine, plus a heuristic UX review of the screenshots against the
  feature requests.
* Opportunity: segment, job-to-be-done, alternatives, moat, risks, and a 30/60/90-day plan.

**What counts as evidence**
* Strong: vendor docs and manuals, release notes, our own logs, peer-reviewed papers.
* Medium: trade-press reviews, forum threads with several participants.
* Weak: single comments, vendor blogs about competitors, search snippets. These are flagged.
* An absence of evidence (for example "no mic ID found") is stated as such, not as fact.

**Limits of the evidence**
* The search tools returned almost no Reddit or Hacker News threads, so the sentiment section leans on vendor forums
  and the trade press.
* Several named products ("Tracklist.ai", "SetCaster", "Pulse DJ", "Hydra", "Mixtape AI", a "1001TL" ID app, Beatoven
  as a DJ tool) produced nothing verifiable and are left out.
* Nobody has listened to the final auto-mix. Every audio-quality judgement here comes from the render logs, not from
  ears.

---

## 2. What we built, as a feature inventory

| Capability | Deck (iPad) | Mike page (phone web) | Mixer toolkit (Mac) |
|---|---|---|---|
| Identify the playing track from the room mic | Yes. ShazamKit custom catalogue, 1,041 signatures (original plus vinyl ±4 %), 47 MB, offline | - | - |
| Position, "sync area" countdown | Yes (match offset anchored to a clock) | Scrub and join lanes | - |
| Deck pitch readout | Yes. Vinyl from frequency skew; master tempo from the slope of position drift, after about 20 s | - | - |
| Next-track picks | Easy / Harder, Simple 2+1 / Full 3+2, Minimal, CD1/CD2/All | Up next (12 best), chains, stars | `pairs.json`, `recs.json` |
| How to join | Pitch-fader %, key verdict, move ("blend / echo out"), join waveform, cyclable start point | Same plus audition of both lanes | `suggested_transition` and reasons |
| Scoring terms | (uses toolkit) | (uses toolkit) | tempo .26, key .14, style .13, timbre .12, energy .11, vocal .11, phrase .08, rhythm .05 |
| Set recording and tracklist | AAC from the mic, JSON log, TXT tracklist | Report sent back (picks, chains) | `.cue` / `.txt` per mix |
| Auto-mix | - | - | 144-minute render: 65 joins, 7 types, teasers, variance, three-pass lull fix, -10 LUFS master |
| Mix map | Bundled WKWebView | - | Interactive artifact plus a one-page printout |

Two numbers don't line up. The Deck README says 347 catalogue tracks, the brief says 373, and `pairs.json` has
`n_tracks` 373 [local]. Re-run `prep_data.py` if the catalogue is meant to cover all 373.

---

## 3. Competitive landscape (A)

### 3.1 Master feature matrix

Key: Y = yes, P = partial, N = no, ? = not found.

| Product | Next-track suggestion | Signals used | Tells you *how* to join | Auto-mix | Stems | Mic ID of the room | Set rec + timestamped tracklist | Price | Platform |
|---|---|---|---|---|---|---|---|---|---|
| **Ours (Deck + toolkit)** | Y, scored pairs, Easy/Harder | tempo (start/end), key and its confidence, energy, vocal overlap, phrase, timbre, rhythm, style | **Y**: pitch %, move, join wave, start bar | Y, offline, rich vocabulary | N (planned) | **Y, own crate, offline, with pitch** | P (room-mic audio, JSON/TXT) | free (personal) | iPadOS, web, Mac CLI |
| rekordbox 7 | Y: Related Tracks (rules), Track Suggestion (Era/Mood/Association), Collection/Streaming **Radar** (AI embeddings) [S1][S16] | metadata, key, BPM, genre, vocal, DNN embedding | N | P (Automix, not phrase-aware) [S1] | Y | N | Y; mobile recording with timestamps (Oct 2025) [S17] | Free; $10-30/mo [S1] | Mac, Win, iOS, Android |
| Serato DJ Pro 4 | N (Smart Crates are rules) [S2] | - | N | N (AutoPlay leaves gaps) [S2] | Y | N | Y (Pro), History to Mixcloud | Lite free; Pro $9.99/mo; $449 Suite [S2] | Mac, Win |
| VirtualDJ 2026 | Y: **GeniusDJ / LiveFeedback**, what other DJs played next (online) [S3] | crowd co-play | N | Y: Smart (4-8 s mixes), Fade, Cut [S3] | Y | N | Y (cue sheet) | free home; $19/mo Pro; about $299 Infinity [S3] | Win, Mac |
| djay Pro (Algoriddim) | Y: Match / Matching Songs (BPM, key, style, danceability; TIDAL engine) [S4] | audio and streaming recs | N | Y: **Automix AI** (ML in/out points, EQ/filter, Riser/Echo/Neural Mix) [S4] | Y (Neural Mix) | P: Shazam loads an *external* track onto a deck [S18] | Y (not streams) | free; $6.99/mo or $49.99/yr [S4] | Mac, Win, iPad, iPhone, Android |
| Traktor Pro 4 | N | - | N | P: Cruise mode (plain crossfade) [S5] | Y (iZotope) | N | P (no timestamped export) [S19] | $149 [S5] | Mac, Win |
| Mixxx 2.5 | N (random from crates) | - | N | P: AutoDJ intro/outro fades [S6] | N | N | Y (WAV + CUE) | free | Win, Mac, Linux |
| Mixed In Key 11 Pro | Y: DJ Mix Mode and Mashup Mode [S7] | key, BPM, energy 1-10 | P (mashup audition) | N | Y (export) | N (MIK Live hears *system* audio, key only) [S7] | N | $58 / $99 one-time [S7] | Mac, Win |
| DJ.Studio | P: "Solver" bridges bad joins [S10] | BPM and key (Camelot) | Y (timeline editor) | **Y**: Harmonize ordering, editable transitions, htDemucs stems [S10] | Y | N | Y: Mixcloud upload with tracklist, CUE, YouTube chapters [S10] | about $119-199, or a subscription [S10] | Mac, Win, web |
| RaveDJ | N | - | N | Y (mashups and long mixes from YouTube/Spotify links), "a mixed bag" [S20] | ? | N | N | free | web |
| MIXO / Lexicon | N (rule-based Smartlists) [S21] | - | N | N | N | N | N | free to about $7/mo | desktop, mobile |
| Beatport Streaming / DJ / **Track ID** | P (catalogue browsing) | - | N | Y (Beatport DJ web automix) [S22] | N | **Y: Track ID (May 2026), pitch/stretch and blend robust, loud rooms** [S8] | N | $10-30/mo [S22] | web, iOS, Android |
| Spotify AI DJ / **Mix** | Y (personal radio, voice requests) [S23] | listening history | N | Y: Mix (Aug 2025) per-join Fade/Rise with editable curves; no tempo or key change [S11][S13] | N | N | N | Premium | mobile |
| Apple Music **AutoMix** | N | - | N | Y: beatmatch and time-stretch, no settings; trims 15-20 s [S12] | N | N | N | Apple Music | iOS 26+ |
| Shazam / SoundHound | N | - | N | N | N | Y, global catalogue; Auto Shazam can run through a set [S24] | N | free | iOS, Android |
| 1001Tracklists / set79 / Trakd | N | - | N | N | N | P: set79 and Trakd ID recorded mixes after the fact [S25][S9] | Y (published sets) | free / varies | web, mobile |
| What's Now Playing + **EarShot** | N | - | N | N | N | **Y (Shazam-based, any deck or vinyl), for OBS overlays** [S9] | P | free, open source | Win, Mac, Linux |
| Beat Link Trigger / PRO DJ LINK Bridge | N | - | N | N | N | n/a: reads track, grid, waveform and phrase *over the network* from NXS2/3000 gear [S15] | P | free / bundled | Mac, Win |
| NXTCue / Mixgraph Live | Y (desktop: reads Serato/rekordbox/VDJ/djay/Mixxx; Mixgraph by manual entry) [S9][S26] | key, BPM, sets data | P | N | N | N | N | $19-29 (NXTCue) | Mac, Win, iOS |
| Engine DJ 4.2/5.0 | ? | - | N | ? | Y | N | Y (normalised recording) [S27] | free with hardware | Denon/Numark hardware |

### 3.2 Product by product: what they do that we don't, and the reverse

**rekordbox 7.**
* They have, we don't:
  * Radar suggestions from DNN embeddings over the library and Beatport/TIDAL/SoundCloud catalogues [S1][S16].
  * PHRASE labels (Intro/Up/Down/Chorus/Verse/Outro) that can be edited.
  * Vocal position overlay on all plans since 7.2.16 [S1].
  * Intelligent Cue Creation that learns your cue habits.
  * Cloud library and analysis, and hardware integration.
* We have, they don't:
  * Concrete join instructions: the fader value at the detected deck pitch, the move, and the bars to start on.
  * Directed A-to-B scores that use *end* tempo against *start* tempo.
  * Room-mic identification.
* DJs distrust rekordbox's phrase labels: all 3 threads found say they need correcting [S28].

**Serato DJ Pro 4.**
* They have, we don't: stems, a library rebuilt in 4.0, Spotify, and, in the 5.0 beta, "Lucid Beatgrids" for drifting
  tempo [S2][S28].
* We have, they don't: any suggestion at all, and any automix (AutoPlay is not a mix).

**VirtualDJ.**
* They have, we don't: GeniusDJ is the only *co-play* recommender, built on what thousands of DJs actually played
  next [S3]. This is the signal we lack most.
* Its automix gets mixed reviews: hard cuts, gaps, "one step up from a jukebox" [S3].

**djay Pro.**
* djay is the best-placed competitor on iPad: Automix AI, Neural Mix stems, Match, and ShazamKit already in the app
  [S4][S18].
* Its Shazam feature loads an external track onto a deck. It does not follow a hardware DJ.
* Match's users ask for crate scoping, BPM tolerance and genre sense, and complain it is "often … way off". The
  thread runs to 4+ pages [S29].

**Traktor and Mixxx.** Neither suggests anything. Their auto-DJ modes are crossfades by design ("a break, not a
replacement") [S5][S6].

**Mixed In Key 11 Pro.**
* MIK Pro's DJ Mix Mode is the closest *offline* analogue to our Up next: harmony, BPM and energy, one track at a time
  [S7].
* It has no join geometry, no mic and no rendering.
* MIK's 1-10 energy scale is the industry vocabulary we lack (recommendation 5).

**DJ.Studio.**
* This is the reference for "auto-mix generator done as a product" [S10]:
  * an editable timeline;
  * htDemucs stems;
  * AI Flex grids;
  * export to Ableton and rekordbox;
  * Mixcloud upload with a tracklist.
* Reviewers say its default transitions are basic and need editing [S13]. Our renderer chooses and executes more kinds
  of join automatically, but it has no editor beyond hand-editing JSON.

**RaveDJ, MIXO, Lexicon.** Not direct competitors. RaveDJ shows how consumers judge automatic mashups ("a mixed bag")
[S20]. Lexicon and MIXO are library plumbing [S21].

**Beatport Track ID.**
* This is the biggest competitive fact for Deck's ID half. Since May 2026 a free-to-try phone app claims to identify
  pitch-shifted, stretched and blended tracks in loud clubs, and to name both tracks in a blend [S8].
* It uses the global catalogue, not the DJ's crate. It gives no position, no pitch fader value, and no next-track
  advice.

**Spotify DJ / Mix and Apple AutoMix.**
* These set listener expectations: automatic, "works every time", no settings [S11][S12].
* Spotify Mix can't change tempo or key. Apple AutoMix time-stretches but trims song ends and avoids "incompatible"
  genres [S12][S13].
* Our renderer is far beyond both in vocabulary. Both are far beyond us in reliability QA and in reach.

**Track-ID apps.**
* Shazam is built for one clean track. Blends fail, and a 2-hour set can take "20+ tries" (a vendor claim) [S25].
* The 2014 TVZ study found Shazam unreliable in a loud club [S30].
* Apple has used Shazam offline to identify tracks inside DJ mixes on Apple Music since 2021 [S9].

**Now-playing tools.**
* Anything with Pro DJ Link (NXS and later), StageLinQ or laptop software can read the loaded track exactly, with no
  listening [S9][S15].
* Players older than the CDJ-900 Nexus expose almost nothing. The CDJ-1000MK3 has no link at all [S15].
* This is exactly the gap Deck fills.

### 3.3 Recognition from the room, compared

| Approach | Example | Catalogue | Pitch/tempo | Knows position | Knows CD/folder | Offline | Blends |
|---|---|---|---|---|---|---|---|
| Network protocol | Beat Link, StageLinQ, Now Playing [S9][S15] | exact (whatever is loaded) | exact | exact | n/a | yes (LAN) | knows both decks |
| Global fingerprint | Shazam, Beatport Track ID, EarShot [S8][S9][S24] | 10^7-10^8 tracks; misses edits and bootlegs | Track ID claims robust; Shazam weak on pitch [S31] | approximate | no | no | Track ID claims both |
| **Own-crate fingerprint (ours)** | Deck | the 373-track crate, including DJ edits and bootlegs | ±4 % variants plus skew; master tempo by drift [local] | yes, about ±1-3 s (forum: custom-catalogue `predictedCurrentMatchOffset` runs 1-3 s late) [S32] | **yes** | **yes** | hysteresis: about 10 s of dominance, or about 4-5 s on a hard cut |
| Pitch-robust research fingerprint | Panako 2.0: ±10 % stretch/shift, reports the factor [S33] | own index | robust | yes | yes | yes | partial |

**[inf]** Our real advantage is not recognition quality. It is *context*: own-crate IDs include the bootlegs and DJ
edits that global catalogues miss, the disc location is known, the pitch is read, and the result ties straight into
scoring. On recognition quality alone, Beatport's Track ID is probably more robust, because it was trained for club
noise and blends.

---

## 4. What DJs say they need (B)

Evidence base: about 45 sources across the three sentiment passes. Reddit and HN coverage was poor (see the plan).

| Theme | Direction of sentiment | Representative evidence | Implication for us |
|---|---|---|---|
| Next-track suggestion | **Wanted, but trusted little.** The longest thread found (djay Match, 4+ pages, 9 posters on one page) asks for crate scoping, a ±BPM tolerance, genre awareness and learning from history [S29]. rekordbox Radar is pitched at DJs who pick on the fly [S16]. 3 of 3 sources draw the line at "assistant fine, replacement not" (sync-debate analogue; "don't know about the crowd") [S34] | "No one wants to mix dubstep to country" [S29] | Our style term (added after Mike's feedback) and CD-chip scoping answer the two top complaints. Missing: play history and played-already removal, and a user BPM tolerance |
| Harmonic mixing | **A tool, not a rule.** 5 of 6 sources say energy and the crowd come first, key second [S34][S35]. MIK's own guide says "use your ears" [S35]. Key matters most for long blends in progressive/trance and less in open-format [S35] **[inf for open-format]** | Mixing in key forever is "boring" [S34] | Keep key a soft term in suggestions, but make it a **hard gate on long bass-swap blends** in the auto-mix (finding C.2) |
| Auto-mix quality | **Robotic = crossfades, early or late exits, level pops or dips, no structure.** 7 reviews or threads [S3][S4][S13][S36] | "Glorified crossfade features" [S13] | Our vocabulary avoids crossfades. Our remaining risks are dips and key clashes in blends |
| Cue/phrase/grid accuracy | **The top pain for mixed-era DJs.** An Engine DJ thread (9 participants) on grids "out of whack" for weddings; VDJ drifts after about 39 s; a rekordbox dynamic-grid loop bug; Serato's Lucid Beatgrids answers it [S28] | Grids work only on "tracks that have a steady tempo" [S28] | Our single constant grid per track is the same weakness (Monster Mash, grid confidence 0.29). A piecewise grid is a known-hard problem that the field is now solving |
| Phrase markers | Wanted: 16/32/64-bar markers and a countdown to the next phrase [S28] | - | Deck's "sync area · 16 bars left" already does this. **A selling point** |
| Live track ID | Shazam fails in blends and loud rooms. Users want a full timestamped tracklist with honest gaps [S25][S30] | "It was built for a different problem" [S25] | Deck's set log is the right artefact. It needs honest "unknown" rows and blend rows |
| Recording and tracklists | **Wanted widely.** Traktor users request timestamped CUE/CSV/JSON export; Engine has no history export; rekordbox mobile added timestamps in 2025 [S17][S19] | - | Export CUE and Mixcloud-format text (recommendation 8) |
| Copyright | Takedowns on YouTube/SoundCloud/Twitch push DJs to Mixcloud [S37] | - | See section 7 |
| iPad / second screen | iPad DJing is accepted for mobile sets. Serato users asked for years for an iPad library or second screen; Serato Remote can't browse [S9][S38] | djay reviews: 3 of 10 praise iPad use, 2 complain about the subscription, 2 about crashes, 2 about battery [S38] | A **second-screen companion** is a known, under-served request |

**Top requests across all themes (ranked by how often they appeared):**
1. Suggestions scoped to a crate, with genre sense, BPM tolerance and history.
2. Grids that follow drifting tempo.
3. Phrase markers and a countdown.
4. Automix that is phrase- and stem-aware, has no dips, and can be edited.
5. Timestamped tracklists exported to CUE and Mixcloud.
6. Track ID that survives blends and loud rooms.
7. An iPad second screen.
8. Key as a soft guide, not a rule.

Our tools touch 1, 3, 4, 5, 6 and 7.

---

## 5. The auto-mix, judged (C)

### 5.1 Audit of the final render [local]

Source: `mixes/Halloween Mix - full.render.json` and `.txt` (144:40, 66 songs, 65 joins, seed 1003).

| Measure | Value | Target (recipes or reviews) | Verdict |
|---|---|---|---|
| Join types | 19 bass_swap_8, 14 slam, 12 bass_swap_16, 8 echo_out, 6 brake_cut, 5 chop, 1 loop_roll | Mixed vocabulary, 16-32-bar blends for house and disco [S14] | Good variety; blends too short |
| 32-bar progressive blends | 0 | Used on disco/house with 32-bar beat-only intros | Missing (the vocal model shrinks the windows) |
| Joins dipping more than 2 LU after the fix passes | **19 / 65** (pass 1: 48, pass 2: 26) | 0 audible lulls; "volume pops and dips" is the top VDJ automix complaint [S36] | **Main defect** |
| Dips by type | 5 of 5 chops, 5 of 19 bass_swap_8, 4 of 12 bass_swap_16, 3 of 8 echo_out, 1 slam, 1 brake | - | Chops and blends, not the effect exits |
| Where the dip falls | 9 after the overlap, 8 during, 2 before | - | B is entering too quietly or into a sparse bar |
| Deepest dips | join 40: 7.0 LU, join 17: 6.9, join 56: 5.3, join 28: 4.8, join 9: 4.6 | - | Hand-check these first |
| Bass-swap blends whose Camelot keys clash | **12 / 31** (6 same key, 6 ±1, 2 relative, 3 ±2, 2 ±7) | Bass swaps between different keys clash even with EQ [S14] | **Second defect** (some are detection errors) |
| Joins with a tempo gap over 6 % | 17 / 65 (26 %) | About 8 % in planned sets [S14]; "dropping tempo suddenly feels like lost energy" | Too many gear changes. The callouts are intended, but the cluster from 136 to 155 to 128 is not smooth |
| Beat alignment | 36 of 36 beat-matched joins within 10 ms | under 10 ms | Excellent |
| Loudness | -10.0 LUFS, -0.4 dBTP | matched to the discs | Good |
| Pairs labelled `quick_blend_echo` / `brake_cut` in `pairs.json` | 34 % / 31 % of 99,832 pairs | The recipes say keep quick_blend_echo out (it reads as a crossfade) | The label set feeding Deck still leans on these. Mike's "too many brake" complaint is upstream here |
| Time-stretch engine | Rubber Band R2 (the faster, lower-quality engine; R3 drifted) | R3 or a high-quality engine for vocals over 4 % | Possible artefacts on vocals at 3-6 % stretch **[inf]** |
| Listening QA | none; "nobody had listened to the final renders" (memory note) | - | **Biggest process gap** |

### 5.2 Vocabulary and parameters against the recipes

| Element | Recipe target [S14] | Renderer now | Gap |
|---|---|---|---|
| Echo-out | 3/4 or 1/2 beat, feedback 0.80-0.85, 3-4-bar tail, LP 5 kHz, send last 2 beats, dry cut | 0.75/0.5 beat, fb 0.81-0.91, 3-4 bars, LP 5 kHz, last 2 beats, 5 ms cut | **Matches** |
| Reverb throw | 1-2 s room, HP 250 Hz, at most 2 bars | room 0.6, HP 250, LP 7.5k, at most 2 bars | Matches |
| Slam | phrase-boundary exit, B on a hook, "drop on the four" for pickups, loudness-matched entry | hook entry; riser plus impact out of callouts | Drop-on-four and loudness matching not confirmed |
| Bass swap 16 | treble first (bars 4-8), bass at the phrase, A mids fade 8-16, low gains sum to at most 1 | B mids/highs at -6 dB, highs full by M/2, bass at M | Close |
| Bass swap 32 | for 32-bar beat-only intros | allowed, never chosen | Window detection |
| Chop | snare alignment under 10 ms, hard bass switch, B's first segment on the hook | A2/B2/A1/B, scratch stab | Loudness parity between segments (all 5 dip) |
| Brake | 1 beat or 1 bar, B under it | 1 bar, rate (1-t)^1.7 | OK |
| Loop roll | 1/2 to 1/4 to 1/8 to 1/16, HP rise, riser | as specified | OK, used once |
| Teasers | not in the recipes | about half of the flow joins | **Risk**: 30+ teasers in 144 min may read as gimmicky; "two per set reads as taste, ten as a nervous tic" (said of loop rolls) [S14] |
| Energy steps | ±1 on a 1-10 scale, plateaus of 3-4 tracks [S14] | tempo arc 119-129 plus a bonus for flavour | No energy model |
| Durations | house 3-4 min, hip-hop 24-32 bars | flow 150-215 s, hip-hop 55-95 s | OK |

### 5.3 What reviewers say makes auto-mixes sound robotic, mapped to us

| Robotic symptom (source) | Present in ours? | Evidence |
|---|---|---|
| Crossfade-like exits [S13][S36] | Mostly fixed: dry cuts, bass swaps, no `quick_blend_echo` in the plan | render log |
| Lulls and volume dips [S36] | **Yes**: 19 joins | `checks.lull_joins_over_2lu` |
| No energy management [S13] | **Partly**: tempo arc only; tempo jumps 136-155-128 | `.txt` |
| No phrase intelligence [S28] | No: an 8-bar lattice with a confidence score, entries on hooks | features |
| Vocal clashes [S14] | Reduced by the vocal term and chops; the EffNet "voice everywhere" bias shortens windows instead | README limitations |
| Key clashes in long blends | **Yes**: 12 of 31 | key audit |
| Same move again and again | Rotation plus variance; teasers frequent | plan |
| Mixing out too early or too late [S4] | Plays of 150-215 s; may cut big records short **[inf]** | plan |

### 5.4 Prioritised improvement list

| P | Change | Why | Effort | Expected effect |
|---|---|---|---|---|
| 1 | **Join review reel**: one 20 s clip per join (8 s before to 12 s after) concatenated with spoken or beeped numbers, plus a TSV to mark keep, fix or replace that the plan reads back | No one has listened; fastest way to find the bad 10 % | 1 d | Turns the owner's "needs work" into a list |
| 2 | **Key gate**: bass_swap and ramped_blend only when the key term is at least 0.65 after an optional ±1 st shift and both key confidences are at least 0.5; otherwise echo_out, slam or a short 4-bar swap on drums only | 12 of 31 clashes | 0.5 d | Removes the most "wrong-sounding" blends |
| 3 | **Demucs htdemucs stems** (offline, cached per track, about 20-40 s per track on MPS **[inf]**; for 373 tracks run overnight). Use (a) the vocal stem RMS per bar instead of EffNet voice, (b) drums/bass/other stems for *stem blends*: B drums only for 8 bars under A, then the bass swap, then the vocal hand-off; acapella-over-instrumental moments at callouts | Longer, cleaner windows (32-bar blends become possible) and fewer vocal clashes; DJ.Studio and djay already do this [S4][S10] | 3-5 d | Biggest audible quality jump |
| 4 | **Lull prevention at the source**: B's entry bar chosen by energy (first bar at least median minus 1.5 LU *with drums*); never end a blend in a B breakdown; chop segments loudness-matched to ±1 LU; A's mids held to the swap bar; remove the synthetic kick/hat filler | 17 of 19 dips are during or after; the filler may sound fake | 2-3 d | Most dips gone without fixes |
| 5 | **Energy model**: a per-bar energy index (short-term LUFS, onset density, low band, a drum-stem RMS once 3 exists), mapped to 1-10; the planner objective penalises steps over ±1 and rewards plateaus; tempo steps capped at about +2 % per flow join; callouts allowed only after a plateau | No energy management; MIK's convention [S14] | 2-3 d | A smoother arc |
| 6 | **Drop/hook detection**: novelty plus a jump in drum-stem energy after 8+ low bars marks a drop; label sections intro/build/drop/break/outro (or try `all-in-one`/allin1 structure labels, research E.1) | Better slam targets, double drops, and no mixing through a killer break [S14] | 2-4 d | Better cue points |
| 7 | **Teaser budget**: at most about 6 per hour, only into big records | Avoid the "nervous tic" effect | 0.25 d | Less gimmicky |
| 8 | **Stretch quality**: try Rubber Band R3 with per-segment re-anchoring every bar (to stop the drift) or `audio-separator` stems stretched separately | R2 artefacts on vocals | 1-2 d | Cleaner pitched vocals |
| 9 | **Automatic QA metrics** beyond LUFS: spectral-flux continuity, low-band sum over 1.1x (two basslines), simultaneous vocal-stem energy (vocal clash), key-chroma correlation over the overlap; fail the render if exceeded | Scalable listening proxy | 2 d | Regressions caught |
| 10 | **Small editor**: an HTML timeline over `plan_*.json` (drag the cue or exit bar, change the join type, re-render one join) | DJ.Studio's main advantage; reviewers say edits are needed [S13] | 4-6 d | Human in the loop |
| 11 | **Piecewise grid** for drifting tracks (local tempo is already computed by `local_tempo.py`) | Older and live tracks; the field's top pain [S28] | 3-5 d | Fewer forced brakes |

Total for P1-P5: **about 9-13 working days**. That roughly halves the defects measured above **[inf]**.

---

## 6. The Deck app, judged (D)

### 6.1 UX review (screenshots shots16-18 plus the README)

**Strengths**
* Glanceable in landscape: one playing panel and five picks fit on one screen.
* Disc/folder/track numbers match the CDJ display.
* Pitch is shown in deck units ("pitch +2.4 %").
* "Sync area in 0:57" answers the phrase-countdown request [S28].
* Minimal mode suits a dark booth.
* A manual "set by hand" fallback.
* Halloween colour-coding.

**Gaps**

| Gap | Seen where | Fix | Effort |
|---|---|---|---|
| "Key clash" appears on 3 of the 5 Full picks for Disturbia, including Easy ones | `shots18/full_moves.png` | Rank key clash below a no-clash pick of similar score; show the key verdict as an icon | 0.5 d |
| No played-already state; picks may suggest songs already played | code: `history` exists in the Recognizer but is not used to filter picks **[inf from the code read]** | Exclude played songs and the same artist within N songs; add a history strip | 1 d |
| "Position unknown" when set by hand gives no countdown | `shots18` | Let the DJ tap the waveform to set the position | 0.5 d |
| Pick reasons hidden behind a long-press | README | One short "why" line on the top pick | 0.5 d |
| No energy indicator | - | An energy 1-10 chip, up or down versus now | 0.5 d after C.5 |
| No request queue, no notes | - | "Requests" list (manual add); out of scope for the party | 1-2 d |
| Recording uses the room mic (crowd, PA colouring) | README | Optional USB audio input from the mixer's REC/booth out; still recognise from the mic | 1-2 d |
| Background capture "not yet verified" | README | Test with the screen locked | 0.25 d |

### 6.2 Robustness

* **Loud rooms.**
  * Wang's 2003 paper: about 50 % recognition at −9 dB SNR for a 15 s clip, about 80 % at 0 dB for a 5 s clip [S31].
  * Club tests found Shazam unreliable [S30].
  * Our README says only that very loud rooms "reduce matching".
  * The `catalogtool bench` tests rendered files, not a PA in a room. **No live-room accuracy figure exists** [local].
  * Booth placement helps a lot **[inf]**: the booth monitor is close to the iPad and carries the playing deck.
  * Action: the loud-room test rig (recommendation 6). Metrics: time to first ID, false switches per hour, accuracy at
    a given SPL.
* **Pitch range.**
  * Apple publishes no skew tolerance. WWDC22 says skew under 5 % "should be safe" [S39].
  * The catalogue has original and vinyl ±4 % variants. By interpolation **[inf]** that covers about ±8 % vinyl.
  * Master-tempo (key-lock) pitch is only covered by the `t` variants, and the default build omits them
    (`--variants o,r-4,r+4`). Fingerprints are weak on pure tempo change [S31].
  * Mike's 16 % fader range (the brief's fix) exceeds both.
  * Action: bench `t±4/±8` and `r±8/±12` and add those that raise recall. Cost: +47 MB per two variants, about 1 minute
    of build time.
* **Hysteresis.**
  * A blend switches after about 10 s of dominance; a hard cut after about 4-5 s.
  * For a 16-bar blend at 125 BPM (31 s) the panel changes about mid-blend. That is sensible.
  * Risks:
    * Short (8-bar, 15 s) blends switch late.
    * A 32-bar blend can show "also hearing" for a long time.
  * Note that the picks refresh only on a switch, so the DJ choosing the *next-next* track mid-blend sees stale picks
    **[inf]**. Consider pre-computing picks for the challenger as soon as "also hearing" appears.
* **Position.**
  * Developers report that custom-catalogue `predictedCurrentMatchOffset` runs 1-3 s late [S32].
  * The "sync area in 0:37" display could be off by a bar or more. Calibrate with a measured fixed offset per device.
* **Pitch by drift.**
  * Needs 20 s of matches, rounds to 0.5 %, and is only accepted between 0.85 and 1.15.
  * Fine for steady play. It resets on every song switch.

### 6.3 What would make it useful to a working DJ beyond this party

1. **Bring your own crate.** Build the catalogue on the device from the user's files (SHSignatureGenerator runs on iOS)
   or on the Mac, plus the analysis. Without this it is a one-party app.
2. **Any rig.** Its unique position is legacy CDJs, vinyl, and borrowed or house gear with no Pro DJ Link [S15]. Keep
   that as the pitch.
3. **Set log as the product.** A timestamped tracklist with pitch, "unknown" gaps and blend overlaps, exported to CUE,
   Mixcloud and YouTube chapters. This is the most-requested artefact [S19][S25].
4. **Learning.** Record actual transitions. After a few gigs, personal "you usually go X to Y" priors are what no
   generic recommender has (VirtualDJ's crowd data is the analogue [S3]).
5. **Request queue and notes** for mobile and wedding DJs.

### 6.4 Distribution

| Route | Fits | Limits | Source |
|---|---|---|---|
| Development install (current, paid team) | Mike's iPad | Profile valid 1 year; device must be registered (100 per family per year) | [S40] |
| Free Apple ID | - | 7-day expiry, 3 devices | [S40] |
| TestFlight internal | up to 100 App Store Connect users | 90-day builds; no review | [S40] |
| TestFlight external | up to 10,000 testers | Beta App Review; guideline 2.2 expects an app intended for public release | [S40] |
| Unlisted App Store | link-only | Full review; anyone with the link can install | [S40] |
| Public App Store | - | Full review; 5.2.1 IP and 2.5.14 mic-consent guidelines apply | [S39] |

### 6.5 Legal notes (not legal advice)

* **ShazamKit custom catalogues.**
  * Matching runs inside the app ("all on device") and signatures are "not invertible" [S39].
  * The licence clause forbids reusing *Shazam catalogue* content, building a competing recognition service, and
    marketing for compliance or royalty auditing [S41].
  * No clause found bans signatures of commercial recordings. The docs speak of audio "that you provide" [S39].
  * **[inf]** For a personal tool this is fine. For a product, ship *no* catalogue: generate it from the user's own
    files on their device. That mirrors rekordbox and Mixed In Key analysing a user's library [S41].
  * App Review 5.2.1 (copyrighted works) makes a bundled catalogue of 373 commercial tracks and their waveform snippets
    risky [S39].
* **Microphone.** Needs `NSMicrophoneUsageDescription` and a clear recording indicator (2.5.14). The REC badge
  satisfies the spirit; also add a first-run consent screen [S39].
* **Mixes of commercial tracks.**
  * US: a private party among friends is likely not a "public performance" [S42].
  * But copying and handing out a mix CD or MP3 implicates the reproduction and distribution rights. No clear safe
    harbour exists, though enforcement against private gifts is practically unheard of [S42] **[inf]**.
  * UK: the private-copying exception was quashed in 2015. The relevant licence is MCPS-PPL ProDub. A "ProMix" licence
    could not be verified [S42].
  * Pool tracks (DJcity and similar) are licensed "to promote new music only" [S42].
  * **Do not post the 144-minute mix publicly except on Mixcloud.** Mixcloud is licensed. Its rules: 15 minutes or
    more; at most 4 songs per artist (3 in a row); at most 3 per album [S37][S43]. Our mix has Rihanna 3 times and
    Nelly Furtado and Missy Elliott twice each **[local]**, which is within the limit.
  * SoundCloud requires permission for every track; Twitch's DJ programme covers live streams only [S42].
  * A product that *renders and distributes* mixes inherits this problem. DJ.Studio removed its YouTube feature for
    this reason [S10].

---

## 7. Opportunity assessment (E)

### 7.1 Segments and slices

| Slice | Who | Their alternative | Our edge | Market risk | Verdict |
|---|---|---|---|---|---|
| **Live booth companion** (hear, ID, pitch, next pick, how to join) | Open-format, mobile and wedding DJs on mixed or legacy gear; vinyl and CD DJs; DJs on house gear they can't link | Memory; rekordbox Related Tracks on a laptop; Beatport Track ID (ID only); NXTCue (laptop software only) | Works with *any* rig; join instructions; own crate with edits and bootlegs; offline | Small niche; Pro DJ Link gear already knows what's loaded [S15]; djay could add it quickly (it has ShazamKit and Match) [S4][S18] | **Best fit, but niche** |
| **Set-ID recorder** (auto timestamped tracklist from any rig, Mixcloud-ready) | Any DJ who records or streams from hardware without software | Software history (Serato/rekordbox), set79 after the fact, manual 1001TL | Live, offline, own crate; pitch and blend overlaps logged | Beatport and set79 may add it; low willingness to pay **[inf]** | **Good wedge feature, weak product alone** |
| **Auto-mix generator** | Hosts wanting party mixes; DJs prepping mixes | DJ.Studio (mature editor and export), Spotify Mix, Apple AutoMix, djay Automix | Richer automatic vocabulary; explained pair scores | Crowded; copyright on output; quality bar set by human DJs | **Keep personal** |

### 7.2 Moat (if pursued)
* **Weak:** ShazamKit (anyone can use it), and the standard features (BPM, key, Camelot).
* **Medium:** the directed pair score with *join geometry*: end tempo against start tempo, vocal-free windows, the
  pitch-fader value at the measured deck pitch, and the move. It is copyable but not commodity.
* **Potentially strong:** personal and aggregate *played-next* data, captured passively by the mic across gigs. Every
  set improves the suggestions without the DJ changing software. That is VirtualDJ's GeniusDJ data, but rig-agnostic
  [S3].

### 7.3 If pursued: 30/60/90-day plan

| Window | Goal | Deliverables | Exit test |
|---|---|---|---|
| **Days 1-30: validate** | Prove that a stranger's DJ gets value | Auto-mix P1-P5 (to finish the personal tool); Deck: on-device or Mac-side "import my crate" (signatures plus analysis), loud-room bench, history filtering, CUE/Mixcloud export; TestFlight internal to 5-10 DJs (3-4 open-format/mobile, 2 vinyl/CD) | At least 6 of 10 use it at 2+ gigs; ID within 15 s in at least 85 % of songs; at least 1 pick taken per 3 songs; interviews |
| **Days 31-60: harden** | Robust across rigs and rooms | Pitch variants ±8-12 %; challenger pre-compute; line-in recording; played-next learning; energy chip; onboarding and privacy policy; external TestFlight (Beta Review) | Retention: 50 % still using in week 6; false switches under 1 per hour |
| **Days 61-90: decide** | Price and position | Pricing test ($4.99/mo or about $49 one-time **[inf]**, next to djay $6.99/mo [S4] and MIK $58-99 [S7]); App Store submission with no bundled catalogue; optional Mac helper app for analysis | Willingness to pay from at least 30 % of testers; otherwise stop and keep it personal |

### 7.4 If not pursued: what to keep as a personal tool
* **Keep:**
  * the mixer pipeline (analysis, `score.py`, `plan.py`, `render.py`);
  * the Mike page as the "audition and send picks back" loop;
  * Deck for any future party on the same rig;
  * the join review reel as the standard QA step.
* **Retire:** the three old one-hour sets and the previews in `mixes/` (the memory note says they are safe to delete).
  Remove them only on the owner's say-so.
* **Maintain:** the one-year development profile expires on Oct 31, 2026, per the README. Re-sign before the next
  party.

---

## 8. Detailed recommendations, consolidated

| Priority | Item | Section | Effort |
|---|---|---|---|
| 1 | Join review reel plus a keep/fix sheet | 5.4 P1 | 1 d |
| 2 | Key gate on blends | 5.4 P2 | 0.5 d |
| 3 | Demucs stems for vocal timelines and stem blends (install it first: it is not in the venv) | 5.4 P3 | 3-5 d |
| 4 | Lull prevention at the source; drop the synthetic filler | 5.4 P4 | 2-3 d |
| 5 | Energy model and tempo-step cap in the planner | 5.4 P5 | 2-3 d |
| 6 | Deck loud-room bench plus wider pitch variants | 6.2 | 2 d |
| 7 | Deck history strip and played-song exclusion; demote key clashes | 6.1 | 1.5 d |
| 8 | Line-in recording; CUE and Mixcloud export | 6.1, 6.3 | 1-2 d |
| 9 | Played-next learning from Deck logs and Mike's chains | 7.2 | 2 d |
| 10 | Distribution and legal: no bundled catalogue in any public build; Mixcloud only for the mix | 6.4-6.5 | n/a |
| 11 | Drop/hook detection; teaser budget | 5.4 P6-7 | 2-4 d |
| 12 | Upstream label rebalancing in `score.py` (31 % brake_cut, 34 % quick_blend_echo), so Deck moves read like DJ moves | 5.1 | 1 d |
| 13 | Small plan editor (HTML timeline) | 5.4 P10 | 4-6 d |
| 14 | Piecewise grids for drifting tracks | 5.4 P11 | 3-5 d |

---

## Sources

Internal [local]: `_pool build/mixer/README.md`, `research.md`, `transition-recipes.md`, `pairs.json`,
`mixes/Halloween Mix - full.render.json` and `.txt`; `Deck app/README.md`, `Deck/Sources/Recognizer.swift` and
`Mixing.swift`; `Deck app/build/shots16`, `shots18`; `Mike page/index.html`; memory notes project-premixed-sets,
project-deck-ipad-app and project-mixer-toolkit.

External:
* S1 rekordbox plans, FAQ v7 and 7.2.16 release notes: https://rekordbox.com/en/plan/ ; https://rekordbox.com/en/support/faq/v7/ ; https://rekordbox.com/en/2026/07/rekordbox-v7216-release-information/ ; https://rekordbox.com/en/feature/overview/
* S2 Serato DJ Pro and pricing, AutoPlay: https://serato.com/dj/pro ; https://serato.com/dj/pricing ; https://support.serato.com/hc/en-us/articles/224969667 ; https://www.digitaldjtips.com/serato-dj-4-beta-library-improved/
* S3 VirtualDJ GeniusDJ / LiveFeedback and Automix manuals, forums: https://virtualdj.com/manuals/virtualdj/interface/database/geniusdj/livefeedback.html ; https://www.virtualdj.com/manuals/virtualdj/interface/browser/sideview/automix.html ; https://djworx.com/automix-no-need-welcome-dj-robot-overlords-just-yet/
* S4 Algoriddim djay Automix and Matching Songs, pricing: https://help.algoriddim.com/user-manual/djay-pro-mac/mixing-basics/using-automix ; https://www.algoriddim.com/djay-pro-mac ; https://tidal.com/partners/algoriddim ; https://community.algoriddim.com/t/automix-transitions-song-way-too-early/7516
* S5 Traktor Pro 4 and Cruise mode: https://sonicstate.com/amped/2024/07/18/ni-introduces-traktor-pro-4/ ; https://www.bonedo.de/artikel/traktor-pro-cruise-mode-verwenden
* S6 Mixxx 2.5 Auto DJ manual: https://manual.mixxx.org/2.5/en/chapters/djing_with_mixxx#auto-dj
* S7 Mixed In Key 11 Pro: https://mixedinkey.com/ ; https://wearecrossfader.co.uk/blog/mixed-in-key-11-pro-review/ ; https://www.digitaldjtips.com/mixed-in-key-11-pro/
* S8 Beatport Track ID (May 2026): https://www.beatportal.com/articles/1405405-beatport-launches-track-id-a-music-discovery-tool-built-for-djs ; https://sonicstate.com/news/2026/05/13/beatport-launches-track-id/
* S9 Now-playing tools, EarShot, NXTCue, Apple Music DJ-mix ID: https://obsproject.com/forum/resources/whats-now-playing.1683/ ; https://preview.nowplayingapp.com/ ; https://hunted.space/product/nxtcue ; https://musicbusinessworldwide.com/apple-music-is-now-using-shazam-technology-to-identify-tracks-in-dj-mixes-so-that-rightsholders-get-paid
* S10 DJ.Studio features, pricing, YouTube note: https://dj.studio/llms-full.txt ; https://rekkerd.org/dj-studio-daw-software-for-djs-sale/ ; https://dj.studio/blog/dj-with-youtube
* S11 Spotify Mix: https://www.androidauthority.com/spotify-playlists-custom-transitions-3588565/ ; https://www.engadget.com/2216279/how-to-use-spotify-mix-tool/
* S12 Apple Music AutoMix: https://musictech.com/news/gear/apple-music-automix-ai/ ; https://9to5mac.com/2025/06/16/automix-apple-music-ios-26/ ; https://heise.de/-11139247 ; https://9to5mac.com/2026/07/16/ios-27-makes-one-of-my-favorite-apple-music-features-even-better/
* S13 TechRadar on Spotify Mix vs AutoMix; Crossfader and Sound On Sound on DJ.Studio: https://www.techradar.com/audio/spotify/spotifys-new-rival-to-apple-musics-automix-is-here-to-upgrade-your-playlists-and-i-think-its-the-better-dj-too ; https://wearecrossfader.co.uk/blog/dj-studio-5-ways-to-transform-your-set-prep/ ; https://www.soundonsound.com/reviews/dj-studio
* S14 Our recipe research and its sources (DJ TechTools EQ theory, mixgraph BPM guide, MIK energy levels): `transition-recipes.md` ; https://djtechtools.com/2012/03/11/eq-critical-dj-techniques-theory/ ; https://www.mixgraph.io/learn/bpm-guide ; https://mixedinkey.com/harmonic-mixing-guide/sorting-playlists-by-energy-level/
* S15 Beat Link Trigger and PRO DJ LINK Bridge: https://github.com/Deep-Symmetry/beat-link-trigger ; https://rekordbox.com/en/2026/09/rekordbox-for-mac-windows-and-pro-dj-link-bridge-support-soundswitch/
* S16 rekordbox 7 Radar and Qosmo: https://qosmo.jp/en/r-and-d/pioneer-dj-rekordbox-ver7 ; https://www.digitaldjtips.com/rekordbox-7-public-beta/
* S17 rekordbox mobile recording: https://rekordbox.com/en/2025/10/recording-feature-rekordbox-for-ios-android/
* S18 djay ShazamKit integration: https://musictech.com/news/gear/algoriddim-djay-detect-tracks-with-shazam/ ; https://help.algoriddim.com/user-manual/djay-ios/dj-tools/performance-tools/shazam
* S19 Traktor timestamped history request; Engine setlist export: https://community.native-instruments.com/discussion/51279/timestamped-history-mix-recorder-performance-logs ; https://community.enginedj.com/t/export-setlist-on-prime/6198
* S20 RaveDJ: https://www.inverse.com/input/culture/this-ai-program-will-create-a-mashup-dj-set-from-any-songs-you-want
* S21 MIXO and Lexicon: https://mixmag.net/read/new-app-mixo-seamlessly-manages-your-music-across-devices-tech ; https://rekord.cloud/blog/lexicon-smart-playlists
* S22 Beatport Streaming and Beatport DJ: https://www.digitaldjtips.com/reviews/beatport-link-music-streaming-for-djs/ ; https://djmag.com/news/beatports-new-web-app-lets-you-dj-and-organise-sets-your-browser
* S23 Spotify AI DJ voice requests and sentiment: https://www.musicbusinessworldwide.com/spotify-expands-ai-dj-feature-with-voice-based-music-requests-for-premium-users ; https://community.spotify.com/t5/App-Features/The-AI-DJ-is-terrible/td-p/5615700
* S24 Shazam Auto Shazam: https://support.apple.com/guide/shazam/aside/dev450e1498e/web
* S25 set79 on Shazam and DJ mixes (vendor); 1001Tracklists IDs: https://set79.com/blog/why-shazam-doesnt-work-on-dj-mixes ; https://help.dj.studio/en/articles/8442966-how-to-use-1001tracklists-in-dj-studio
* S26 Mixgraph Live: https://mwm.ai/apps/mixgraph-dj-mixing-assistant/6762545406
* S27 Engine DJ 4.2 / 5.0: https://community.enginedj.com/t/engine-dj-v4-2-0-now-available-stems-recording-normalization-beatport-flac-more/60254 ; https://www.soundonsound.com/news/engine-dj-50-update-now-live
* S28 Phrase and grid accuracy threads; Serato Lucid Beatgrids: https://virtualdj.com/forums/257055/Wishes_and_new_features/Phrase_Analysis.html ; https://community.algoriddim.com/t/can-we-have-phrase-analysis/23688?page=2 ; https://community.enginedj.com/t/the-beatgrids-are-mostly-out-of-whack/63193 ; https://www.notebookcheck.net/Serato-DJ-finally-learns-how-to-follow-real-drummers.1399341.0.html
* S29 djay Match feature-request threads: https://community.algoriddim.com/t/improving-usability-of-related-matching-tracks/20855?page=3 ; https://community.algoriddim.com/t/full-blown-match-feature-like-related-tracks-in-rekordbox/23883/33.md
* S30 TVZ study, Shazam in clubs: https://www2.tvz.hr/publikacija/challenges-of-music-recommendation-software/
* S31 Wang 2003 (Shazam); fingerprint pitch/tempo weakness; JKU DJ-mix monitoring: https://www.princeton.edu/~cuff/ele201/files/Wang03-shazam.pdf ; https://arxiv.org/pdf/2309.03516 ; https://research.jku.at/en/publications/landmark-based-audio-fingerprinting-for-dj-mix-monitoring/
* S32 Apple developer forum on custom-catalogue offsets and query lengths: https://developer.apple.com/forums/thread/710225 ; https://developer.apple.com/forums/thread/728326
* S33 Panako: https://archives.ismir.net/ismir2021/latebreaking/000039.pdf ; https://joss.theoj.org/papers/10.21105/joss.04554.pdf
* S34 Digital DJ Tips on mixing in key; the sync debate: https://www.digitaldjtips.com/to-mix-in-key-or-not/ ; https://djclass.net/learn/when-to-use-sync
* S35 MIK workflow; DJTT and VDJ forums on MIK: https://mixedinkey.com/workflows/plan-a-dj-set-with-harmonic-mixing/ ; https://forum.djtechtools.com/t/mixed-in-key-worth-it/55683?page=2 ; https://virtualdj.com/forums/160477/General_Discussion/Mixed_in_Key.html
* S36 VirtualDJ automix volume complaints: https://virtualdj.com/forums/125807/Old_versions/Automix_pop_and_volume_issues.html
* S37 Mixcloud licensing; DDJT on uploading mixes: https://blog.mixcloud.com/2024/03/28/how-to-live-stream-music-without-copyright-takedown-issues/ ; https://www.digitaldjtips.com/questions-legally-upload-mixes-youtube/
* S38 djay App Store reviews; Serato second-screen requests; iPad gigging: https://apps.apple.com/us/app/djay-dj-app-mixer/id450527929?see-all=reviews ; https://serato.com/forum/discussion/1057837 ; https://www.digitaldjtips.com/questions-ipads-finally-gaining-acceptance-dj-use/
* S39 ShazamKit docs and WWDC21/22; App Review Guidelines: https://developer.apple.com/tutorials/data/documentation/shazamkit/shcustomcatalog.md ; https://developer.apple.com/tutorials/data/documentation/shazamkit/shmatchedmediaitem/frequencyskew.md ; https://developer.apple.com/videos/play/wwdc2021/10044/ ; https://developer.apple.com/videos/play/wwdc2022/10028/ ; https://developer.apple.com/app-store/review/guidelines/
* S40 TestFlight, memberships, devices, unlisted apps: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/ ; https://developer.apple.com/support/compare-memberships/ ; https://developer-rno.apple.com/help/account/register-devices/devices-overview ; https://developer.apple.com/support/unlisted-app-distribution
* S41 ShazamKit licence clause (compiled); rekordbox analysis precedent: https://lawinsider.com/clause/shazamkit/_1 ; https://rekordbox.com/en/feature/djing/
* S42 17 USC 101; UK private copying quashed; ProDub; SoundCloud; Twitch DJ Program; DJcity: https://www.bitlaw.com/source/17usc/101.html ; https://barkerbrettell.co.uk/copyright-exemption-for-private-use-regulations-quashed-2 ; https://www.freeindex.co.uk/media/listingpics/613/999/produblicence2024.pdf ; https://help.soundcloud.com/hc/en-us/articles/115003447327 ; https://www.musicbusinessworldwide.com/twitch-strikes-music-licensing-deals-with-all-three-majors-for-dj-livestreams1/ ; https://support.djcity.com/hc/en-us/articles/34409884914708-What-type-of-music-does-DJcity-provide
* S43 Mixcloud Featured Artist Rules: https://help.mixcloud.com/hc/en-us/articles/360004031080
