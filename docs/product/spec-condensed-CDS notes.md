# Deckie, condensed spec for approval

v0.6, Oct 27, 2026 (afternoon). The two-page version for notes. New since v0.5: key over time settled on Apple's
detector run on windows; the vocal signal settled on Apple's instrument activity with a listening set; a
"Crate from discs and albums" section from the ingestion research.
The full spec is `01-spec.md`; the dated decisions and the open proposals are `00-decisions.md`; the evidence is in
`docs/research/` (nine reports) and the measurements in `docs/architecture/stage1-results.md`. The vocabulary, 144
terms in three registers, is a page: https://claude.ai/artifact/XtF38gtDMdrk2u6noURRYR.

## Where we are now

- Repo: 22 commits on `main`, self-contained, pipeline and app verified from it; not yet pushed (commit email to
  confirm). Research tracks A to K done; Codex community pass done; Codex vocabulary pass pending.
- Measured: Apple's Music Understanding framework reproduces the lab's beats (F 0.987), tempo, key (exact or a
  neighbour on 96 percent of confident keys) and loudness (within 0.04 LU), in about 12 s per track in the iOS 27
  simulator on this Mac. It reports one key per track even on songs that modulate. One ShazamKit signature matches
  within about plus or minus 4 percent of its own speed in every mode. Apple's key detector run on 30-second
  windows finds every tested modulation with clean controls, where a lightweight estimator of our own flagged chord
  changes as key changes; Apple's vocal activity is right more often than the lab's detector where they disagree.
- Decided since v0.4: D11 (native engine on the framework, graceful fallbacks), D12 (tuning in the DJ's own words,
  onboarding from a song chain), D13 (key-change markers; the crate is Deckie's own richer format; interchange is an
  explicit, lossy button, never a sync). Eleven proposals wait below.

## What it is

Deckie is a booth companion that listens. Beside decks that do not know the DJ's library, it hears what is playing,
names it from the DJ's own crate, reads the pitch fader, shows what could come next and how to bring it in, learns
how this DJ mixes, and writes the set's timestamped tracklist. The music never leaves the DJ's devices. An App Hold
Media product.

## Who it is for [should be broadened]

[This is for any DJ who wants its functionality. From beginners to veterans with obscure CDJ sets. We don't need to be too prescriptive. We should also do a voice exercise where we build a framework for how we talk about the product and the language we use. ]

bar residents on house CDJs, mobile DJs on venue
or standalone gear, vinyl and CD DJs. The clearest starting point is the DJ with an unfamiliar crate: new records in
a familiar bag, a themed party, a handed-over selection, a new toy; DJs describe "trying to work in a new tune" as
the hard part. Secondary: anyone recording a set from hardware who wants the tracklist. Not for laptop DJs whose
software already knows the track. Who may reject it: DJs who moved to CDJs to avoid screens, DJs who trust a small
familiar bag, mobile DJs for whom another device is setup burden.

## The promise

Remember what works from your own crate [is this our primary value? It's information. Like rediscovering your crate or getting info you never thought a burned CD collection or vinyl collection could have. Its also kind of like training wheels or bumpers for people who might need it ]

, wherever you play. Recall, saved pairs and a finished tracklist have DJs'
own accounts behind them; live join advice is a hypothesis we test, with different detail for beginners and
improvisers. Said concretely: "Your music stays on your iPad. No account. No upload. Works with no signal." Privacy
covers taste as well as audio: history, cues, saved pairs and learned preferences are the DJ's, visible, exportable,
deletable. Claim discipline: djay and Beatport Track ID also hear the room; Deckie's claim is own crate, offline,
pitch, join, learning, tracklist. Never sold as AI.

## Principles

- Recommend, never prescribe. Options in the DJ's own words, never a verdict. [this feels over stated. We can say it once and simply. Over explaining here makes it look like we are lying] A played join is not an endorsement.
- The DJ's content is theirs: audio, names, history, taste. No server, no bundled catalogue, no automatic lookups. [lookups happen when they add music to the crate. It is automatic. need to refine the language]
- Pitch is a first-class number; the matchable range follows the hardware. [what does this mean]
- Everything is tunable, and tuning speaks the DJ's language: the vocabulary page is the label source.
- Less on screen, not more. [but is customizable - more for if you want to play with your crate, make a set before you spin it, or more if you like all that info - can also be super simple, clean, no distractions but the music]
- The crate is ours and richer than any player's format; other software gets a button, not a sync. [we need to be really clear about our differentiator here. Right now its only key, portability, ease, and cost - and thats fine. it may grow or evolve but we should just say it - not aspirationalize. ]

## Architecture (decided, measured)

- One Swift engine on iPhone, iPad and Mac on Apple's Music Understanding framework (OS 27) for beats, key,
  structure, instrument activity and loudness, plus our own grid fit [what does this mean?], tempo and key segments, 8-bar lattice, mix
  windows and Camelot [what does this mean?] mapping ported from the lab. Key segments: Apple's key analysis on windows, seeded with the
  song key, with a hysteresis rule and a key-stability confidence. Vocal signal: Apple's instrument activity,
  calibrated on a 40-track listening set Christopher [this isn't about me. one, I am not a DJ, two this has to work for any music taste, style, dj style, experience level etc. ] labels; a vocal stem (HTDemucs, MIT) later as an optional pass. [we need some vocal thing eventually lets figure it out and clearly define it] Fallback levels for older devices. The Python lab stays as
  ground truth and never ships (non-commercial model licences).
- The crate file: a package of about 10 KB per track, never audio. Tempo stored as segments in the industry's
  grid-marker shape (one for 89 percent of tracks, several for transition edits and rubato intros); key stored as
  segments too, which no player's format has, so the join reads the key at the mix windows, not the song's key.
- Recognition from a ShazamKit catalogue built from the user's own files: one signature per track, with the
  microphone signal transformed into several parallel matchers to cover the fader range (P11), and a
  nine-signature catalogue as the interim fix for the next gig. Identity is self-contained: content hash, signature,
  analysis descriptor; names from tags with an editor; public data only suggests corrections, on request. [this feels jargon-y]
- Preferences learned on device in the crate file: twelve dimensions, saved pairs outranking plays. [should we define those 12 dimensions? we need to gut check that with a music person or DJ. Is that enough? Too many? fine for now but maybe not prescriptive on the number. ]
- One universal iOS app plus a native Mac app; roles Booth, Pocket, Desk. Web app much later. [eventually we will need to make this usable on PC and Linux. A lot of DJs don't use Macs - at least for the analysis ]

## Crate from discs and albums (new; track K)

Mike's library is hundreds of burned MP3 CDs of obscure edits with inconsistent tags, plus albums. The Mac app
gets a "Crate from discs" flow with two queues. Attended: insert a disc, burst-read it to a folder, eject, swap;
about 4 to 5 minutes per disc, halved with a second USB drive. Unattended: hash, dedupe, analyze, sign, name. An
audio CD arrives as the AIFF tracks macOS already exposes plus its table of contents, CD-Text and ISRC codes; an MP3
CD is a file copy. Time for 100 discs: about 8 attended hours either way, plus about 30 unattended hours of analysis
for MP3 discs at today's 12 seconds per track, less if the framework runs several tracks in parallel. Naming, in the
order the product allows: tags and file names first (they are what the CDJ displays); for commercial albums one
disc-id request to MusicBrainz names the whole album without sending audio, on request only; CD-Text where a burner
wrote it; AcoustID as the opt-in route for untagged ordinary songs; and for obscure edits the DJ's own name, which
is fine because identity is hash plus signature plus analysis. Continuous home-burned mixes are split by running the
crate's own recognition over the file plus the analysis's section, tempo and key boundaries, with the sprint's cue
sheet as the template. The iPad cannot read any optical drive; it consumes the crate and reads USB sticks through
Files. YouTube: confirmed no for any automated pull; a hand-triggered "find on YouTube" link per track is all that
survives, and it is not faster than typing.

[this feels the least resolved. ]

## v1 features

Hear and identify; crate from discs and albums on the Mac; picks with the join and a "why" line in the DJ's words, scoped to the current crate, joins that
can start mid-song; saved pairs with a note; crate import and a naming editor; onboarding under five minutes from a
song chain with move-word tiles (long blend, echo out, echo in, hard cut, scratch in, and the rest); sliders in the
DJ's vocabulary, with a one-tap "widen the beat range" during a set; set recording with CUE and Mixcloud export;
rekordbox XML export and import as explicit buttons; a "How you mix" page with undo.

## Staging

0. Baseline: done Oct 26.
1. Measure before engine code: done Oct 27 (framework benchmark, ShazamKit pitch sweep, key over windows,
   recognition solves, vocal signal, disc ingestion). Remaining: the 40-track vocal listening set, labelled by
   Christopher; regenerating Christopher's crate needs the engine.
2. Next: the engine on the Mac writing crate file v1, with parity tests against the 373 lab files; the two quick
   wins into the existing iPad app for Mike's next gig (nine-signature catalogue, finer tempo-only pitch reading);
   then the iPad reads the crate file instead of bundled data.
3. The engine on iPad and iPhone; onboarding; sliders; learning; the multi-stream listener.
4. Trial: five to ten DJs in three observed situations; the pass mark is bringing it to a second gig.

## Decisions needed from Christopher

- P2. YouTube is not a mapping source; user-shared links may be resolved and shown, never stored. [but can they be analyzed? This is the largest repository of music]
- P5. Primary segment as above, narrower than "mobile and wedding". [this is for any DJ we speak to what it does and let the DJ decide]
- P6. Fingerprint lookups opt-in per batch, Mac first, never automatic. [Inorder to build the crate we need to identify. It is user initiated - but that is a choice ]
- P7. Claim discipline as above.
- P8. Store name "Deckie: DJ Booth Companion", category Music; "Data Not Collected" only if true. [needs work "DJ booth companion" is boring. ]
- P9. Profiles: one crate, several named preference sets, one active per gig; start with one.
- P10. Identity self-contained; public lookup an optional helper. [we need to clarify what does and doesnt have lookup]
- P11. Recognition: shift the microphone into parallel matchers, one signature per track; nine signatures interim.[what does this mean?]
- P12. Tempo segments in the grid-marker shape, so export and import are clean (narrowed by D13).
- P13. The v1 vocal signal is Apple's instrument activity, calibrated on a listening set; a stem pass later.
- P14. "Crate from discs" on the Mac as above; the iPad consumes the crate. [there are a bunch of ways to create your crate. We need to name them]
- Also yours: the final bundle id under App Hold Media; the attorney review of DECKEE; a registrar check of
  deckie.dj; the commit email; pricing (lean: one-time, $39 to $59).

## Not doing

The auto-mix as a product. A bundled catalogue. Cloud analysis of audio. YouTube, SoundCloud, Beatport or Bandcamp
as sources. Fingerprint lookups by default. Full interchange or live sync with other DJ software. Selling it as AI. [see above]
