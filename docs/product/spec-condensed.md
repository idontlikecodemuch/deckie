# Deckie, condensed spec for approval

v0.4, Oct 26, 2026. This is the two-page version. The full spec is `01-spec.md`, the dated decisions and the
proposals are `00-decisions.md`, and the evidence is in `docs/research/` (six reports). Approving this approves the
full spec's direction; detail can be revised later.

## What it is

Deckie is a booth companion that listens. Beside decks that do not know the DJ's library, it hears what is playing,
names it from the DJ's own crate, reads the pitch fader, shows what could come next and how to bring it in, learns
how this DJ mixes, and writes the set's timestamped tracklist. The music never leaves the DJ's devices. It is an
App Hold Media product.

## Who it is for

DJs playing open-format on gear that does not know what is loaded: bar residents on house CDJs, mobile DJs on venue
or standalone gear, vinyl and CD DJs. Within that, the clearest starting point is the DJ with an unfamiliar crate:
new records in a familiar bag, a themed party, a handed-over selection, a new toy. Secondary: anyone recording a set
from hardware who wants the tracklist. Not for laptop DJs whose software already knows the track.

## The promise

Remember what works from your own crate, wherever you play. Recall, saved pairs and a finished tracklist have DJs'
own accounts behind them; live join advice is a hypothesis we test. Said concretely: "Your music stays on your iPad.
No account. No upload. Works with no signal." Privacy covers taste as well as audio: history, cues, saved pairs and
learned preferences are the DJ's, visible, exportable, deletable. Deckie never claims to be the only app that hears
the room; djay and Beatport Track ID do. The claim is own crate, offline, pitch, join, learning, tracklist.

## Principles

- Recommend, never prescribe. Options in the DJ's own words, never a verdict. A played join is not an endorsement.
- The DJ's content is theirs: audio, names, history, taste. No server, no bundled catalogue, no automatic lookups.
- Pitch is a first-class number; the matchable range follows the hardware.
- Everything is tunable, and tuning speaks the DJ's language.
- Less on screen, not more. Every sprint round that removed something was welcomed.

## Architecture (decided)

- One Swift analysis engine on iPhone, iPad and Mac, built on Apple's Music Understanding framework (OS 27, on
  device, offline) for beats, key, structure, instrument activity and loudness, plus our own grid fit, phrase
  lattice, mix windows and Camelot mapping ported from the Python. Graceful fallback levels for older devices. The
  Python stack stays in the lab as ground truth; it cannot ship (non-commercial model licences).
- One crate file per library, a package folder of about 10 KB per track, carrying analysis, names, preferences and
  history, never audio. Moves by iCloud Drive, AirDrop or Files.
- Recognition from a ShazamKit catalogue built from the user's own files. Identity is self-contained: content hash,
  signature, and an analysis descriptor for versions. Names come from tags, with an editor; public data only
  suggests corrections, on request.
- Preferences learned on device, in the crate file: twelve measurable dimensions, saved pairs outranking plays.
- One universal iOS app plus a native Mac app, roles as modes: Booth, Pocket, Desk. Web app much later.

## v1 features

Hear and identify; picks with the join and a "why" line, scoped to the current crate, joins that can start
mid-song; saved pairs with a note; crate import and a naming editor; onboarding under five minutes from a song
chain with move-word tiles; sliders in the DJ's vocabulary (pick difficulty, options, density, plus a "How you mix"
sheet); set recording with CUE and Mixcloud export; a "How you mix" page with undo.

## Staging

0. Baseline, this week: repo committed and self-contained, pipeline and app verified from the repo.
1. Measure, before engine code: Music Understanding against the Python features on the 373 tracks; ShazamKit
   signature cost and pitch tolerance on a device; regenerate Christopher's crate with the shipped engine.
2. The engine on the Mac and crate file v1; the iPad reads the crate file instead of bundled data.
3. The engine on iPad and iPhone; onboarding; sliders; learning.
4. Trial: five to ten DJs in three observed situations; pass mark is bringing it to a second gig.

## Decisions needed from Christopher

- P2. YouTube is not a mapping source; user-shared links may be resolved and shown, never stored.
- P5. Primary segment as above, narrower than "mobile and wedding".
- P6. Fingerprint lookups opt-in per batch, Mac first, never automatic.
- P7. Claim discipline as above.
- P8. Store name "Deckie: DJ Booth Companion", category Music; "Data Not Collected" only if true.
- P9. Profiles: one crate, several named preference sets, one active per gig; start with one.
- P10. Identity self-contained; public lookup an optional helper.
- Also yours: the final bundle id under App Hold Media; the attorney review of the DECKEE mark; a registrar check of
  deckie.dj; what you meant by "echo in" and "more bass range"; pricing (lean: one-time, $39 to $59).

## Not doing

The auto-mix as a product. A bundled catalogue. Cloud analysis of audio. YouTube, SoundCloud, Beatport or Bandcamp
as sources. Fingerprint lookups by default. Selling it as AI.
