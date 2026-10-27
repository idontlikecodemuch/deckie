# Deckie, condensed spec for approval

v0.5, Oct 27, 2026. The two-page version, rewritten to where we stand today so notes can be made against it.
The full spec is `01-spec.md`; the dated decisions and the open proposals are `00-decisions.md`; the evidence is in
`docs/research/` (nine reports) and the measurements in `docs/architecture/stage1-results.md`. The vocabulary, 144
terms in three registers, is a page: https://claude.ai/artifact/XtF38gtDMdrk2u6noURRYR.

## Where we are now

- Repo: 14 commits on `main`, self-contained, pipeline and app verified from it; not yet pushed (commit email to
  confirm). Research tracks A to H done; Codex community pass done; Codex vocabulary pass pending.
- Measured: Apple's Music Understanding framework reproduces the lab's beats (F 0.987), tempo, key (exact or a
  neighbour on 96 percent of confident keys) and loudness (within 0.04 LU), in about 12 s per track in the iOS 27
  simulator on this Mac. It reports one key per track even on songs that modulate. One ShazamKit signature matches
  within about plus or minus 4 percent of its own speed in every mode.
- Decided since v0.4: D11 (native engine on the framework, graceful fallbacks), D12 (tuning in the DJ's own words,
  onboarding from a song chain), D13 (key-change markers; the crate is Deckie's own richer format; interchange is an
  explicit, lossy button, never a sync). Eleven proposals wait below.

## What it is

Deckie is a booth companion that listens. Beside decks that do not know the DJ's library, it hears what is playing,
names it from the DJ's own crate, reads the pitch fader, shows what could come next and how to bring it in, learns
how this DJ mixes, and writes the set's timestamped tracklist. The music never leaves the DJ's devices. An App Hold
Media product.

## Who it is for

DJs playing open-format on gear that does not know what is loaded: bar residents on house CDJs, mobile DJs on venue
or standalone gear, vinyl and CD DJs. The clearest starting point is the DJ with an unfamiliar crate: new records in
a familiar bag, a themed party, a handed-over selection, a new toy; DJs describe "trying to work in a new tune" as
the hard part. Secondary: anyone recording a set from hardware who wants the tracklist. Not for laptop DJs whose
software already knows the track. Who may reject it: DJs who moved to CDJs to avoid screens, DJs who trust a small
familiar bag, mobile DJs for whom another device is setup burden.

## The promise

Remember what works from your own crate, wherever you play. Recall, saved pairs and a finished tracklist have DJs'
own accounts behind them; live join advice is a hypothesis we test, with different detail for beginners and
improvisers. Said concretely: "Your music stays on your iPad. No account. No upload. Works with no signal." Privacy
covers taste as well as audio: history, cues, saved pairs and learned preferences are the DJ's, visible, exportable,
deletable. Claim discipline: djay and Beatport Track ID also hear the room; Deckie's claim is own crate, offline,
pitch, join, learning, tracklist. Never sold as AI.

## Principles

- Recommend, never prescribe. Options in the DJ's own words, never a verdict. A played join is not an endorsement.
- The DJ's content is theirs: audio, names, history, taste. No server, no bundled catalogue, no automatic lookups.
- Pitch is a first-class number; the matchable range follows the hardware.
- Everything is tunable, and tuning speaks the DJ's language: the vocabulary page is the label source.
- Less on screen, not more.
- The crate is ours and richer than any player's format; other software gets a button, not a sync.

## Architecture (decided, measured)

- One Swift engine on iPhone, iPad and Mac on Apple's Music Understanding framework (OS 27) for beats, key,
  structure, instrument activity and loudness, plus our own grid fit, tempo and key segments, 8-bar lattice, mix
  windows and Camelot mapping ported from the lab. Fallback levels for older devices. The Python lab stays as
  ground truth and never ships (non-commercial model licences).
- The crate file: a package of about 10 KB per track, never audio. Tempo stored as segments in the industry's
  grid-marker shape (one for 89 percent of tracks, several for transition edits and rubato intros); key stored as
  segments too, which no player's format has, so the join reads the key at the mix windows, not the song's key.
- Recognition from a ShazamKit catalogue built from the user's own files: one signature per track, with the
  microphone signal transformed into several parallel matchers to cover the fader range (P11), and a
  nine-signature catalogue as the interim fix for the next gig. Identity is self-contained: content hash, signature,
  analysis descriptor; names from tags with an editor; public data only suggests corrections, on request.
- Preferences learned on device in the crate file: twelve dimensions, saved pairs outranking plays.
- One universal iOS app plus a native Mac app; roles Booth, Pocket, Desk. Web app much later.

## v1 features

Hear and identify; picks with the join and a "why" line in the DJ's words, scoped to the current crate, joins that
can start mid-song; saved pairs with a note; crate import and a naming editor; onboarding under five minutes from a
song chain with move-word tiles (long blend, echo out, echo in, hard cut, scratch in, and the rest); sliders in the
DJ's vocabulary, with a one-tap "widen the beat range" during a set; set recording with CUE and Mixcloud export;
rekordbox XML export and import as explicit buttons; a "How you mix" page with undo.

## Staging

0. Baseline: done Oct 26.
1. Measure before engine code: done Oct 27 (framework benchmark, ShazamKit pitch sweep, key over time, recognition
   solves). Remaining: a listening check for the vocal thresholds; regenerating Christopher's crate needs the engine.
2. Next: the engine on the Mac writing crate file v1, with parity tests against the 373 lab files; the two quick
   wins into the existing iPad app for Mike's next gig (nine-signature catalogue, finer tempo-only pitch reading);
   then the iPad reads the crate file instead of bundled data.
3. The engine on iPad and iPhone; onboarding; sliders; learning; the multi-stream listener.
4. Trial: five to ten DJs in three observed situations; the pass mark is bringing it to a second gig.

## Decisions needed from Christopher

- P2. YouTube is not a mapping source; user-shared links may be resolved and shown, never stored.
- P5. Primary segment as above, narrower than "mobile and wedding".
- P6. Fingerprint lookups opt-in per batch, Mac first, never automatic.
- P7. Claim discipline as above.
- P8. Store name "Deckie: DJ Booth Companion", category Music; "Data Not Collected" only if true.
- P9. Profiles: one crate, several named preference sets, one active per gig; start with one.
- P10. Identity self-contained; public lookup an optional helper.
- P11. Recognition: shift the microphone into parallel matchers, one signature per track; nine signatures interim.
- P12. Tempo segments in the grid-marker shape, so export and import are clean (narrowed by D13).
- Also yours: the final bundle id under App Hold Media; the attorney review of DECKEE; a registrar check of
  deckie.dj; the commit email; pricing (lean: one-time, $39 to $59).

## Not doing

The auto-mix as a product. A bundled catalogue. Cloud analysis of audio. YouTube, SoundCloud, Beatport or Bandcamp
as sources. Fingerprint lookups by default. Full interchange or live sync with other DJ software. Selling it as AI.
