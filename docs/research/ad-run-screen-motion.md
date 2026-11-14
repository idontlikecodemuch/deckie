# Research AD: the run screen, moving

Dated Nov 14, 2026. A short design letter for the run screen (D37), after the owner watched a real run: keep every
element; make it more dynamic, "each song at a time, movement, like the waveforms expanding and contracting", not
necessarily accurate to the song, "more for visual enjoyment". This letter says what the reading changes, gives three
directions with a recommendation, and records what was built and measured.

Tags: [read] = the finding comes from the page or a search summary of it today; [inf] = my inference.

## In plain words

A **loading screen** is what someone watches while a computer works. **Perceived waiting time** is how long the wait
feels, which is not the same as how long it is. **Reduced motion** is the system setting (on the Mac and in browsers)
that asks apps to keep things still for people whom movement makes unwell. An **easing** is the shape of a movement
over time: starting fast and settling, or overshooting a little and coming back. A **beat** is one count of the
song's tempo; a **bar** is four beats; a **downbeat** is the first beat of a bar.

## What the reading says, and what it changes

1. **Motion can make a wait feel shorter, and the kind of motion matters.** A study of progress bars found that
   ribbing which moved backwards and pulses that quickened as the bar filled made the same wait feel about a tenth
   shorter. [read: AD1, AD2] The same group found people forgive slowness early in a wait more than late. [read: AD2]
   *Change*: steady, rhythmic movement on the stage, not just a picture that appears and sits.
2. **For short waits, extra animation can make the wait feel longer.** [read: AD2, a later finding reported there]
   Guidance on progress indicators puts looping animations at roughly two to ten seconds and real progress beyond
   that. [read: AD3, second-hand] *Change*: the movement is decoration beside the plain progress, never a replacement
   for it; the bar, the count and the time left stay as they are (D37).
3. **DJ software already moves waveforms in a way DJs read without thinking**: a coloured overview of the whole
   song, a zoomed waveform that scrolls past a fixed playhead, beat marks. [read: AD4, AD5] *Change*: a playhead
   travelling over the song's own wave is a familiar sight to a DJ; a scrolling zoomed wave would be too, but it needs
   detail the 64 values a song carries do not have. [inf]
4. **Music visualisers fall into two kinds**: those that follow each beat closely and those that move loosely with the
   overall flow. [read: AD6] *Change*: one of each, layered: a short pulse on each beat, and a slow breath over a few
   bars, so the stage both ticks and breathes.
5. **Reduced motion: minimise or remove animation; a fade is the usual stand-in.** Custom animation is the app's to
   handle. [read: AD7, AD8] *Change*: under reduced motion the stage shows the finished wave, still, and changes as a
   still picture would (the existing `holdStill`).
6. **Nothing may flash more than three times in a second.** [read: AD9] *Change*: the pulse is a change of size, not of
   brightness; it is held to at most one every 0.4 seconds (two and a half a second) by halving the pulse rate of
   fast songs; the playhead's glow travels smoothly and never blinks.
7. **Motion guidance keeps durations short and settling** (Material's tokens run from 50 ms to one second, with an
   easing that starts fast and settles). [read: AD10, second-hand] *Change*: the change from one song to the next
   takes under a second and settles with a small overshoot, so it feels like a spring, not a slide.

## Three directions

**A. The breathing wave.** The song on stage keeps moving after it lands. When the next song comes, its wave sweeps
in from the left, each stretch expanding or contracting from the last song's height to its own, with a small
overshoot. Then it breathes at the song's tempo: a quick swell on every beat that falls away, a bigger one on each
downbeat, and a slow breath every four bars. A soft glow travels across it like a playhead, two bars of the song's
tempo to a crossing. All of it built from the song's real wave, tempo and bars; one small drawing, one song at a time.

**B. The deck.** The stage becomes a DJ deck: the wave scrolls right to left past a fixed playhead at the song's
tempo, with beat marks passing under it, and a small overview above. Instantly familiar to a DJ, and the most
movement. But 64 values a song are too coarse for a zoomed view (it would show blocks), the scrolling never settles,
and it reads as "playing", which Desk is not doing.

**C. The whole screen in time.** The stage breathes as in A, and the rest of the screen keeps time with the song on
stage: the newest line on the wall, the tempo bar for that song and the key's cell on the wheel pulse on its beat.
The most alive, but it spreads attention across the screen (the owner asked for one song at a time), redraws the wall
and figures many times a second while the run is busy reading, and is the hardest to keep calm.

**Recommendation: A.** It is exactly what the owner described (expanding and contracting, one song at a time), it
keeps every element where it is, its movement comes from the song's own tempo, bars and loudness, and it is one small
drawing, so it costs little while Desk reads. C's idea can be added later to one more element if the stage alone
feels lonely. [inf]

## What was built (direction A)

The same motion on the Mac (`desk-app/Desk/Sources/RunScreen.swift`, values in `RunLook`) and in the Windows and
Linux window (`desk-web/run.js`, values in `desk.css`'s `:root`):

- **The change of song**: each of the 64 stretches moves from the last song's height to the new one's, starting from
  the left one after another (the old "drawing in from the left", now a sweep), with a small overshoot. The first
  song grows out of the middle line; a song with no wave sinks into it. Bar marks appear as the sweep passes.
- **The pulse**: on every beat of the song's tempo the wave swells and falls back; more on the first beat of each
  bar. Fast songs pulse every other beat and slow songs twice a beat, so a pulse comes every 0.4 to 1 second. Loud
  stretches move more than quiet ones because the swell is a share of their height.
- **The breath**: a slow swell over four bars. A song with no tempo only breathes, slowly.
- **The playhead**: a soft band of light crosses the wave every two bars of the song's tempo, lifting the wave a little
  where it passes.
- **Calm and light**: under reduced motion the finished wave, still. The drawing stops while the window is hidden or
  the run screen is gone. At most thirty frames a second, one small path a frame.

## What it costs (measured)

On generated songs only, on the same Mac, one run at a time, other work on the machine at the same time (so a few
per cent either way is noise):

| | before | after |
|---|---|---|
| Mac: stage frames a second during a run (15 short songs) | 8 to 11 | 22 to 24 |
| Mac: time to record a frame | about 100 µs | about 90 to 130 µs |
| Mac: main thread (all of the window's drawing) | 6.6 to 7.1% of one core | 6.6 to 7.6% of one core |
| Mac: whole app's CPU for the run (mostly the reading) | 81 to 83 s | 71 to 72 s |
| Mac: the run's length | 18 to 19 s | 15 to 17 s |
| Mac, again back to back with the machine busier: run length, app CPU, main thread | 24 s, 106 s, 7.0% | 23 s, 104 s, 8.2% |
| Windows and Linux pages, on the Mac: the web page's CPU from the first song to the finished screen (10 longer songs) | 0.5 s over 91 s (0.6%) | 1.7 s over 106 s (1.6%) |

The reading is not slower; the drawing stays a small share of one core. The scripted pass reports the Mac numbers
itself (`--window-check`, the line "stage drawing"); `DECKIE_RUN_BURST` makes it write stills of the run screen a
fraction of a second apart.

## Sources

- AD1. Harrison, Yeo, Hudson, "Faster progress bars: manipulating perceived duration with visual augmentations",
  CHI 2010: https://www.chrisharrison.net/index.php/Research/ProgressBars2
- AD2. Reports of that study and of later work on short waits:
  https://gizmodo.com/visual-tricks-can-make-downloads-seem-quicker-5513404 and
  https://www.sbs.com.au/news/article/making-downloads-faster-with-trickery/tjsw1rlli
- AD3. Summaries of progress-indicator guidance (looping animation for about 2 to 10 seconds):
  https://www.uxtigers.com/post/progress-indicators and https://usersnap.com/blog/progress-indicators/
- AD4. Serato, main waveform display: https://support.serato.com/hc/en-us/articles/224969307-Main-Waveform-Display
- AD5. rekordbox, waveform colours by frequency: https://rekordbox.com/en/feature/djing/
- AD6. On visualisers that follow each beat or the overall flow:
  https://blog.videobolt.net/post/how-to-create-audio-waveform-music-visualizers
- AD7. Apple, Human Interface Guidelines, Motion: https://developer.apple.com/design/human-interface-guidelines/motion
- AD8. On custom animation and reduced motion in SwiftUI: https://useyourloaf.com/blog/reducing-motion-of-animations/
- AD9. W3C, Understanding WCAG 2.2, Three flashes or below threshold:
  https://www.w3.org/WAI/WCAG22/Understanding/three-flashes-or-below-threshold.html
- AD10. Material 3 motion tokens, as summarised: https://m3.material.io/styles/motion/overview and
  https://skill-wiki.github.io/atom/android-compose/rule-motion-easing-tokens
