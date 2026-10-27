# Deckie v1 user flows

Oct 26, 2026. Low fidelity, no visuals. Sources: the spec and decisions in `docs/product/`, research C and E, the
community report, the Deck app and Mike's feedback log (BRIEF section 7). Anything beyond those is marked
**[inf]**.

Each step gives **Sees** (in research E's words), **Does**, **Stores** (only inside the crate file, never audio:
`crate.json` for names and analysis; `prefs.json` for preferences, sliders and profiles; `history`, per-device and
append-only; `signatures/`) and **Today** (where the Deck app already does it). Screen names are proposals
**[inf]**: Welcome, Booth (today's Listen tab), Crate (today's CDs tab), Set, How you mix, Tune (a popover); on
the Mac, Import, Names, Editor, Discs. Internal names never appear; every label has a plain gloss on long-press.

## 1. First run on the iPad, no crate

1. **Welcome.** Sees: "Deckie"; "Your music stays on your iPad. No account. No upload. Works with no signal.";
   two buttons, "Open a crate" and "Build a crate from files on this iPad"; one line naming the engine level (D11),
   such as "This iPad reads crates analysed on a Mac". Today: none; Mike's data is compiled in, so the first
   screen is the Booth's "Listening…".
2. **Open a crate.** Sees: the Files picker filtered to `.deckiecrate`, iCloud Drive's Deckie folder first; or
   AirDrop's "Open in Deckie". Continues at flow 3, step 3.
3. **Build from files.** Sees: the Files picker for a folder or files; "Analysing 12 of 373"; "Plug in to
   continue" on battery (spec 5.3); progress survives leaving the app. Stores: `crate.json` (analysis, names from
   tags and file names), `signatures/`; tracks a reduced engine analysed are marked for re-analysis. Today: none;
   the Mac does it (README, "Rebuild the data and the catalog").
4. **Names (iPad).** Sees: "N named from tags, M need a name", the "name these" list, a single-track rename
   sheet; no bulk edit, suggestions or lookups here (P6) **[inf]**. Does: names a few or taps "Later"; unnamed
   tracks keep their file name and still get picks. Stores: `crate.json`. Today: none.
5. Onboarding (flow 4), then the Booth.

## 2. Crate import on the Mac

1. **Import.** Sees: "Drop a folder or choose files"; a crate name, defaulting to the folder name **[inf]**.
   Today: `mixer/analyze.py` and `prep_data.py` from the terminal.
2. **Scan.** Sees: tracks found, exact duplicates dropped (content hash), versions grouped by work; "Analysing 120
   of 373". Stores: `crate.json`, sidecars, `signatures/` with the pitch variants so the iPad never computes
   them. Today: `analyze.py`, `catalogtool`.
3. **Names.** Sees: one row per track: Song, Artist, Version (remixer, edit kind, clean or dirty, intro,
   extended), Year, Disc or folder; rows the grammar guessed carry a small dot **[inf]**; "M need a name" is a
   filter. Today: none; the sprint used hand maps (98 original years, 105 new entries).
4. **Editor.** Sees: multi-select, a field panel, "Apply to 14 tracks", Undo and Redo naming the last change
   ("Undo: year 1998 on 14 tracks"). Stores: every edit in `crate.json`, never in the files or their tags (D3).
5. **Suggest a correction**, one switch, off by default. Sees: a "Suggested" column beside the DJ's own name from
   MusicBrainz and Discogs (titles only), "Use" per row, "Use all" per batch; nothing applies until tapped.
   Separately, per batch: "Look up untagged tracks by fingerprint", with "This tells a third party which records
   you own" and Cancel as the default (P6). Per row, "Listen to confirm" opens the public YouTube link MusicBrainz
   holds; shown, never stored (P2). Stores: accepted names in `crate.json`; CC0 text may be cached. Today: none.
6. **Discs.** Sees: disc name, folders, tracks numbered as on the CDJ ("CD1 / 6 - 125-129 / 06"); "Build a disc
   folder" writes the files in order plus a manifest; "Read a disc folder" matches a burned folder back by manifest
   or content hash. Stores: disc, folder and track location in `crate.json` (the primary identifier where discs
   exist); the manifest on the disc is a copy **[inf]**. Today: the `discs/` tooling; the CDs tab shows the result.
7. **Done.** Sees: "`<name>.deckiecrate` · 373 tracks · 3.6 MB" and "Send to iPad".

## 3. Moving the crate to the iPad

1. **Send (Mac).** Sees: iCloud Drive ("appears on your iPad in Deckie"), AirDrop, Files. Today: none; data is
   compiled into the app and reinstalled (README, "Install on the iPad").
2. **Arrival (iPad).** Sees: AirDrop's "Open in Deckie"; or the crate listed on Welcome or Crate; or "Open a
   crate" from Files.
3. **Open (iPad).** Sees: "Opening <name> · 373 tracks · analysed on a Mac · recognition ready" (signatures
   travel; the iPad has no audio to regenerate from) and the engine line; if the crate already exists here,
   "Keeping your saved pairs, history and settings". Stores: `crate.json` replaced per key by the newer;
   `prefs.json` and `history` merged by timestamp, history a union, never overwritten. Today: none.
4. Onboarding if no profile exists; otherwise the Booth.

## 4. Onboarding, under five minutes

Only steps 1 and 2 are required; the rest have Skip. Nothing asks the DJ for a number.

1. **Your gear** (30 s, three taps). Sees: deck type (CDJ, turntables, standalone or controller, other
   **[inf]**); pitch range as the fader's own steps, "±6 · ±10 · ±16 · wide" (Pioneer) or "±8 · ±16 · ±50"
   (Serato, Rane), by the deck answer; "Key lock: On · Off · Not sure". Stores: pitch cap and key lock in
   `prefs.json`. Today: 16 percent is a constant, set after Mike said "the range is wider for him".
2. **Your chain** (about two minutes). Sees: "Pick three to five songs in the order you'd play them" over the
   crate list with search; then one join at a time, "Lady → Keep On. How would you mix it?", and the tile grid:
   Blends (Long blend · 32 bars, Blend · 16 bars, Short blend · 8 bars, Filter fade; second tap "with a tempo
   ramp"); Effects out (Echo out, Reverb wash, Loop roll); Cuts (Hard cut, Chop, Backspin, Vinyl brake; second tap
   "scratch in", "tease first"); an escape row, Not sure · Something else · Half time. Does: a tap per join.
   Stores: each join as a told event in `history`, weighted like a saved pair **[inf]**, and its seeds in
   `prefs.json`; "Not sure" stores nothing; "Something else" stores a note for How you mix. Today: none.
3. **Have a recorded set?** (optional). Sees: "Pick one of your own sets, or a set whose style you like. It is
   analysed here and never leaves this iPad."; then "Found 14 joins from your crate". Stores: the set's measured
   tempo tolerance, key, style spread, energy arc, blend length and mix-in points in `prefs.json`, marked "from
   your set". Today: none; the Booth's own recordings make this routine after the first gig.
4. **Your sliders** (30 s, shown once, Skip at the top). Sees: eight sliders pre-set from the answers, each
   marked "from your chain" or "from your set": Picks (Easy ↔ Harder); Picks shown (3 · 5 · 10); On screen
   (Minimal · Simple · Full); Pitch range; Key (Off · Flag clashes · In key first); Style (Stay in lane ↔ Open
   format); First choice (Blends first ↔ Cuts first); Vocals (No clashes ↔ Overlap OK). Stores: positions in
   `prefs.json`; a moved slider is "set by you" and learning never moves it. Today: Simple / Full and Minimal
   exist; the rest are constants.
5. **How you mix** (flow 7), then "Go to the booth".

Listen and pick (A/B rendered joins) stays out: it needs the Mac renderer.

## 5. The Booth during a set

Landscape first; portrait stacks the two halves (ListenView).

1. **Listening.** Sees: "Listening…", "A song shows up after 5–10 seconds of music"; top-left the "Minimal"
   switch; top-right a status dot, "listening", "REC 0:00:12", the mic, "…". Today: PlayingPanel, MinimalToggle.
2. **Playing panel.** Sees: folder path ("CD1 / 6 - 125-129 /"), "06 · Lady", artist, "128 BPM" at the deck's
   pitch in amber, the whole-song wave with IN and SYNC, elapsed and remaining, "sync area in 0:37"; status
   "listening · sure · deck +3.2%"; "also hearing: …" during a blend. No countdown. Stores: a recognised event in
   `history` (time, track, deck pitch, confidence), today's `log.json`. Today: PlayingPanel, SongWave, Recognizer.
3. **Picks.** Sees: "Simple / Full" top-left, scope chips top-right; Easy and Harder, randomised, "More" on
   scroll; a saved pair for this song first, labelled "Saved" **[inf]**. Each card: folder path, "06 · Title",
   artist, "128 BPM · pitch +4.0%", one grey line with move and key ("Blend · 16 bars · in key", "Echo out · keys
   clash", "Needs a bridge" for today's "no beat-match · brake"), the join wave with numbered sync points, "0:32 ·
   3 syncs"; corner chips as today. Does: taps the wave to cycle the start point (as today, plus mid-song starts
   in v1); long-presses for the why ("pitch up 3 percent", "no vocal clash", "clean 16-bar intro"). Stores: shown and chose-another events in `history`, weakly weighted **[inf]**.
   Today: UpNextPanel, NextRow, JoinView, StartPoint; the why popover's internal strings ("stretch", "brake", a
   match score) are replaced.
4. **Pin.** Sees: the card moves to "Next" at the top with the orange bar; tap again to unpin. Stores: a pin
   event in `history` (pin-then-played and pin-unplayed weigh differently). Today: `sug.pin`.
5. **The join.** Sees: the panel switches once the new song out-matches the old (a blend after about 10 s, a cut
   in 4 to 5 s); the picks roll; the old song is not offered again this set. Stores: a played-next event with the
   measured blend length in bars, pitch and start offset; passive plays move defaults slowly (a played join is not
   an endorsement). Today: the switch and the log exist; learning and no-repeats do not.
6. **Save a pair with a note.** Sees: for about 20 s after a change, one small line on the playing panel, "Keep
   On after Lady · Save" **[inf: placement and timing]**; also "Save pair" in a card's long-press popover; then a
   one-line note ("bass swap at the breakdown") and, optionally, the move tiles. Stores: pair, note and move in
   `history` as a saved event, the top weight; defaults move at once. Today: none.
7. **Tune** (one tap, no settings page). Sees: a small "Tune" button beside Simple / Full **[inf]** opening tiles
   in move words: "Widen the range (±16)", "Fade" / "Blends first", "Hard cut" / "Cuts first", "Flag clashes" /
   "Any key", "Stay in lane" / "Open format" **[inf: the set]**. Does: one tap; the picks re-roll. Stores: the
   position in the active profile, "set by you". Today: none; Mike's live asks were applied by editing constants.
8. **Minimal and density.** Sees: "On screen: Minimal · Simple · Full" (spec 6.5 folds today's two controls into
   one **[inf]**); the count becomes Picks shown. Minimal keeps the playing wave and makes each pick a pill:
   title, artist, folder, "BPM · pitch", move. Stores: `prefs.json` (today UserDefaults). Today: MinimalToggle,
   PickControls, PlainPick.
9. **Scope chips.** Sees: a chip per disc or event in the crate, each on or off, plus "All" (today's CD1 / CD2 /
   All in the discs' colours). Stores: the scope with the gig in `history` **[inf]**. Today: PickControls.
10. **Room too loud.** Sees: "listening · unsure", or nothing; the Crate tab, a dense list by folder and number
    ("tap a song to set it as playing"). Does: taps the song; the Booth reads "set by hand", BPM at 0 percent, the
    picks roll. Stores: a set-by-hand event, flagged so no pitch is learned from it. Today: CDsView, `rec.setManual`.

## 6. Set recording, tracklist, export

1. **Recording.** Sees: "REC 0:12:34" on the status line (tap pauses and resumes); "Record while listening" and
   "Line in" in the "…" sheet. One engine feeds both. Stores: the set log in `history`
   (time in, seconds into the recording, track, location, pitch, confidence); the audio is the DJ's own file in
   Files (On My iPad > Deckie > Sets), never in the crate. Today: SetRecorder, `log.json`, `tracklist.txt`;
   line-in is new.
2. **Set.** Sees: the list of sets (also the Pocket role on the iPhone); a set's songs with time in, title,
   artist, location, pitch, and the recording's length; replace a wrong song from the crate, remove a false hit,
   nudge a time **[inf]**. Stores: the corrected log in `history`. Today: the files only, via the Files app.
3. **Export.** Sees: "Share tracklist" as CUE (times against the recording, performer, title) or Mixcloud text,
   plus the recording, through the share sheet. Stores: nothing new; exports sit beside the recording. Today:
   `tracklist.txt` is close to the Mixcloud form; CUE is new.

## 7. How you mix, and undo

Nothing in flows 7 and 8 exists today.

1. **Entry.** The end of onboarding; "…" on the Booth **[inf]**; the Set screen ("Learned from this set: 2
   changes").
2. **How you mix.** Sees: the active profile's name; one sentence per learned thing, with source and date: "You
   usually blend · 16 bars. From 23 joins over 3 gigs." "Pitch range ±6. Set by you." "Keys: clashes don't bother
   you. From your set, Oct 31."; the five sheet sliders with learned-default markers; "Your saved pairs (12)";
   one line, "This stays on your iPad. Only you benefit from it.", with "Export" and "Delete what Deckie learned".
   Does: reads; moves a slider; edits a pair's note. Stores: `prefs.json`.
3. **Undo.** Sees: "Undo" on each learned line; tapping shows the previous value and "undone, Oct 26", and the
   row stays so it can be redone. Stores: the previous value restored in `prefs.json` from a short per-dimension
   change list **[inf]**; the picks re-roll.
4. **Delete.** Sees: "Delete what Deckie learned" asks once and names what goes (preferences, saved pairs,
   history); names and analysis stay. Stores: those parts of the crate emptied.

## 8. Profiles (P9, proposed)

1. **Start with one.** A new user never chooses: onboarding creates the first profile, and no name is shown until
   a second exists **[inf]**. Stores: one preference set in `prefs.json`.
2. **New profile.** From How you mix: a name ("Wedding", "Deep night") and one of three starts, "Copy this one",
   "From a recorded set" (flow 4.3), "From a new chain" (flow 4.2). Stores: a second named set in `prefs.json`;
   crate and history stay shared.
3. **For this gig.** Sees: once two profiles exist, the active name as a chip in Tune **[inf]**; one tap
   switches, the picks re-roll, and learning writes to the active one. Stores: the active profile in
   `prefs.json`; `history` events carry it.

## Deliberately absent

Every sprint round that removed something was welcomed; these stay out.

- **Everywhere:** no account, sign-in, upload, cloud, bundled catalogue or discovery; no "AI" wording; no
  internal names; no "brake" alone, no "filter out"; no "safe / left-field" (they describe the record, not the
  join); no numbers asked of the DJ; no lookups that run on their own; no notifications.
- **Welcome:** no tour, no permissions wall; the mic is asked for when listening starts.
- **Booth:** no headings beyond Easy, Harder, Next; no shuffle; no countdown; no chips the DJ cannot read; no
  orange fills; no confidence numbers or match scores competing with the deck's display **[inf: the score
  leaves the why popover]**; no verdicts ("not mixable" becomes the option "Needs a bridge"); no "was that
  good?" prompt after a join; nothing that moves without a reason; no settings page.
- **Picks:** no more than the chosen count; no repeats within a set; nothing outside the scope.
- **Onboarding:** no A/B listening on the iPad; no genre or era questionnaire; no sliders before the chain.
- **Mac Editor:** no automatic renames; no writes to tags or files; no YouTube data stored; no silent lookups.
- **Set:** no sharing, posting or upload from the app; an export is a file the DJ holds.
- **How you mix:** no scores, percentages or "mixing personality"; sentences only.

## Open questions for Christopher

1. Do the chain's joins (flow 4.2) count as saved pairs, or only as seeds?
2. Where does "Save pair" live: the line after a change, the long-press popover, or both? Attention is the cost.
3. Fold Minimal and Simple / Full into one "On screen" control as the spec says, or keep Mike's two controls?
4. Scope chips for a crate with no discs: folders, events, or playlists?
5. The set log: in the crate, beside the recording, or both (today both)?
6. The iPad import: single-track rename only, or the whole editor?
7. Tune: which tiles, and where on the Booth?
8. The why line: one grey line always visible, as today, or long-press only?
9. First profile: unnamed until a second exists, or named at the end of onboarding?
10. Still yours from the spec: what "echo in" and "more bass range" meant; the Mixcloud text format; whether the
    iPhone Pocket role ships set recording in v1.
