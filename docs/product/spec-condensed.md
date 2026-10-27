# Deckie, condensed spec for approval

v0.7, Oct 27, 2026 (evening). Rewritten after Christopher's notes on v0.6 (`spec-condensed-CDS notes.md`): plain
words, each principle said once, the audience is any DJ, the promise is information, the differentiator is stated as
it is today. Where a note asked "what does this mean", the answer is now in the sentence. New: the ways to build a
crate are named, and a first voice framework is in `voice.md`. The full spec is `01-spec.md`, the decisions and
proposals `00-decisions.md`, the evidence `docs/research/`, the measurements `docs/architecture/stage1-results.md`,
the vocabulary https://claude.ai/artifact/XtF38gtDMdrk2u6noURRYR.

## Where we are now

24 commits on `main`, self-contained, not yet pushed (commit email to confirm). Research tracks A to K done, both
Codex passes done. Measured: Apple's music analysis reproduces our reference analysis on beats, tempo, key and
loudness; run on 30-second windows it finds every tested key change; its vocal reading is right more often than our
old one; one recognition signature matches within about 4 percent of its own speed. Decided: the engine (D11), the
DJ's own words for tuning (D12), key markers and the crate as our own format (D13). Proposals wait at the end.

## What it is

Deckie listens beside the decks. It names the track from the DJ's own crate, reads the pitch fader (the slider that
speeds a record up or slows it down), shows what could come next and how to bring it in, learns how this DJ mixes,
and writes the set's tracklist. The music never leaves the DJ's devices. An App Hold Media product.

## Who it is for

Any DJ who wants what it does, from a beginner with a first controller to a veteran playing obscure burned CDs on
old CDJs. We describe what it does and let DJs decide. From the research, the people who get the most from it are
DJs on gear that does not know their library, and DJs working unfamiliar music into a familiar bag. Some will not
want it: DJs who moved to CDJs to get away from screens, and mobile DJs for whom another device is a burden.

## What it gives you

Information you never had about music you already own. Your crate, analysed: the tempo at the start and the end of
every track, the key and where it changes, where the vocals are, where the clean intro and outro are, what mixes
into what and at which fader setting. For a burned-CD or vinyl collection, that information has never existed. For a
beginner it is bumpers: a safe next record and a way to bring it in. For a veteran it is memory: the pairs that
worked, the tracklist written for you, the crate rediscovered.

Said plainly: "Your music stays on your iPad. No account. No upload. Works with no signal." Your history and taste
are yours too, visible, exportable, deletable. Other apps also hear the room (djay, Beatport Track ID); none knows
your crate, reads your pitch, or shows you how to bring the next one in. Not sold as AI.

## Principles

- Deckie suggests; the DJ decides.
- The DJ's music, names, history and taste stay on the DJ's devices. Deckie looks things up only while you build
  your crate and only when you tell it to; it never looks up what you play.
- The pitch fader is the number DJs work with, so Deckie reads it from the room and reports it as a fader
  percentage, and the records it calls matchable are the ones within the reach of the fader on your gear (6, 10 or
  16 percent, your choice).
- Everything is tunable, in DJ words.
- The screen is as calm or as busy as you want: nothing but the music in the booth, or everything, for playing with
  your crate or building a set before you spin.
- What is different about Deckie today: it knows your crate, burned CDs and edits included; it knows key, including
  where a song changes key, which no player's file format carries; it travels in one file; it is easy; it is cheap.
  That is the list. It may grow.

## How it works

- One analysis engine on iPhone, iPad and Mac, built on Apple's music analysis framework (iOS and macOS 27), which
  finds beats, bars, tempo, key, sections, instrument activity and loudness on the device. On top we add our own
  steps: fitting a steady beat grid (a ruler of evenly spaced beats, what DJ software calls a beatgrid) to the beats
  it found; splitting the track into tempo segments where the speed changes and key segments where the key changes;
  the 8-bar phrase ruler DJs count in; the mix-in and mix-out windows, the best stretches to bring a track in and
  to hand over; and the Camelot code for each key, the DJ convention that numbers the 24 keys around a clock so
  neighbours mix smoothly. Older devices get a reduced engine or read a crate analysed elsewhere. The Python
  research code stays as our reference and never ships (licences).
- Key: Apple's detector on the whole track and again on 30-second windows, with a rule that opens a new key segment
  only when the key moves outside the current key's family and stays there. Measured: every tested key change found;
  9 of 60 ordinary songs got a second segment, and a stability score turns those into "key uncertain" rather than a
  wrong answer.
- Vocals: Apple's instrument activity says, every 50 milliseconds, how much singing, drums and bass are playing. We
  calibrate it against tracks labelled by ear by DJs across styles, not by us. The open problem is sampled and
  chopped vocals, which it reads as not singing; a real vocal separation (HTDemucs, MIT licence) comes later as an
  optional pass. "Vocal" needs a definition the product can keep: what the vocal slider means.
- The crate file: about 10 KB per track, never audio: names, analysis, tempo and key segments, preferences, history.
  Moves by iCloud Drive, AirDrop or Files. Richer than any player's format; other software gets an export and an
  import button, not a sync.
- Recognition: Apple's ShazamKit, matching the room against a catalogue built from your own files, one signature
  per track. A signature only matches within about 4 percent of its own speed, so to cover a fader at plus or minus
  16 percent the app listens through several matchers at once, each hearing the room sped up or slowed down by a
  different amount, and settles on the one that hits. For the next gig, a simpler stand-in: nine signatures per
  track.
- Naming: a track's identity is its own, a hash of the file plus its signature and analysis, so nothing depends on a
  database. Its name comes from the file's tags and name, and you can edit it. Lookups exist in three places only:
  when you add a commercial CD, one request names the whole album; when you ask, an audio fingerprint names an
  untagged ordinary song; edits and mixes are named by you. Nothing is looked up during a set.
- Learning: Deckie learns how you mix from what you play, pin and save, on the device. What it learns today, about a
  dozen things, to be gut-checked with DJs and not a fixed number: how far you push the tempo; your fader range and
  key lock; how much key matters to you; genre and era spread; energy arc; blend length; cut styles; effects; how
  you handle vocals; phrase alignment; loops; where you mix in and the tempo you feel.
- Apps: one iOS app (iPad booth view, iPhone pocket view) and a Mac app for building the crate. Windows and Linux
  for building the crate later; the analysis engine is Apple's, so that means a second engine, which is the honest
  cost.

## Ways to build a crate

1. From files and folders on the Mac, or files on the iPad.
2. From discs with a USB drive on the Mac: commercial audio CDs, burned audio CDs, burned MP3 CDs, continuous mix
   CDs. Draft flow: insert, read in a burst, eject, swap, about 4 to 5 minutes a disc, while analysis and naming
   run unattended behind. A hundred MP3 discs: about 8 attended hours plus about 30 unattended hours of analysis at
   today's speed. The iPad cannot read optical drives. (Least resolved; see `docs/research/k-cd-and-album-ingestion.md`.)
3. From albums and purchases already on the Mac or in Music.
4. From a USB stick, the CDJ's own crate, on Mac or iPad.
5. From another DJ app's export (rekordbox XML), keeping your grids and cue points.
6. Later: from a recorded set, to learn how you mix, not to add tracks.

## v1 features

Hear and identify; build the crate any of the ways above; picks with the transition and a one-line reason in DJ
words, limited to the crate or folder you choose, including transitions that start mid-song; saved pairs with a
note; a naming editor; onboarding under five minutes from a short song chain with move tiles; sliders in DJ words,
with a one-tap "widen the beat range" during a set; set recording with CUE and Mixcloud export; rekordbox export and
import buttons; a "How you mix" page with undo.

## Staging

0. Baseline: done Oct 26.
1. Measure before engine code: done Oct 27. Remaining: a vocal listening set labelled by DJs.
2. Next: the engine on the Mac writing crate file v1, checked against the 373 reference tracks; the two quick wins
   into the existing iPad app for Mike's next gig (nine signatures, a finer pitch reading); then the iPad reads the
   crate file.
3. The engine on iPad and iPhone; onboarding; sliders; learning; the multi-matcher listener.
4. Trial with DJs in three observed situations; the pass mark is bringing it to a second gig.

## Decisions needed from Christopher

- P2. YouTube. Deckie analyses any file you own and never asks where it came from. It cannot pull audio or titles
  from YouTube itself: the terms and the App Store rules forbid it. A per-track link to check a version is all.
- P5. Withdrawn: the audience is any DJ.
- P6. Fingerprint lookups happen while you build the crate, started by you, never during a set.
- P7. Claim discipline: other apps hear the room; ours knows your crate, your pitch and the transition.
- P8. Store name and subtitle. "DJ Booth Companion" is the descriptive subtitle search engines want; candidates for
  the line that sells: "Deckie: Know Your Crate", "Deckie: Your Crate, Mixed", "Deckie: Next Record, Your Crate",
  "Deckie: Mix From Your Crate". Category Music. "Data Not Collected" only if true.
- P9. Profiles: one crate, several named ways of mixing, one active per gig; start with one.
- P10. Lookups: the three listed under Naming, and no others.
- P11. Recognition across the fader range: several matchers hearing the room at different speeds, one signature per
  track; nine signatures per track as the stand-in for the next gig.
- P12. Tempo segments stored in the shape DJ software uses for grid markers, so export and import are clean.
- P13. Vocals: Apple's reading, calibrated by DJs' ears across styles; a separation pass later; define "vocal".
- P14. The six ways to build a crate above, with the disc flow as a draft.
- P15. The voice framework in `voice.md`.
- Also yours: the bundle id under App Hold Media; the attorney review of DECKEE; a registrar check of deckie.dj; the
  commit email; pricing (lean: one-time, $39 to $59); and one vocabulary call, "filter out" (DJs say it; Mike did not
  understand it) against "filter sweep" (the tutorial word).

## Not doing

The auto-mix as a product. A bundled catalogue of other people's music. Analysing audio in the cloud. Pulling audio
or titles from YouTube, SoundCloud, Beatport or Bandcamp. Lookups during a set. Live sync with other DJ software.
Selling it as AI.
