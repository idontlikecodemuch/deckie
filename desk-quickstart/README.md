# Deckie Desk's quick start

Desk's opening video (D46): a silent film of 57.6 seconds, captions in the picture, that a DJ starts from the card on
Desk's first screen, or from the Help menu (Mac) or the "⋯" menu (Windows and Linux). The reasons and the options are
research letter AG (`docs/research/ag-desk-quick-start.md`); the beats and their words are `storyboard.md`. The film
that ships, 720p, its poster and the card's picture are in `desk-web/quick-start/`; this folder is how they are made.

## What is here

- `storyboard.md`: every beat of the film: the picture, the caption and its seconds.
- `film.html`, `film.js`: the film, drawn on a canvas as a pure function of time (`film.seek(t)`). It frames the
  capture, moves the camera, draws the pointer where the capture clicked, rings what a caption names, and sets the
  captions. The look is the explainer film's (`site/film/`): the booth's colours, Inter, and Pacifico for "you",
  "your" and "Deckie" only. It closes as that film does: Deckie's icon (the app icon in `deck-app/`), the name written
  on stroke by stroke, and "Know Your Crate". The pen paths are the site film's word maps: `site/film/words/words.json`
  is in git; the `*_map.png` files are made there by `strokes.py` (or copied into `<work>/words/`, which `render.mjs`
  prefers). Without them the name fades in instead. It has no sound.
- `render.mjs`: renders the film (or single pictures of it) in headless Chrome, frame by frame, into ffmpeg.
- `capture/songs.py`: twelve generated songs with invented titles and acts (made the way the demo crate's names are);
  steady-beat dance tracks of drums, bass and chords made from nothing. Never a real song or artist.
- `capture/live.mjs` and `capture/clock.js`: the capture. Desk's Windows and Linux window (the pages in `desk-web/`,
  unchanged) in headless Chrome, talking to the real engine (`deckie-desk-engine`) on the generated songs, clicked
  through as a DJ would: the new crate's name typed, Add drive, the stick, the whole run, the finished screen,
  Export crate file, the box "To get it to your iPad", the crate's songs, then **Booth**: Desk listening, naming the
  song playing and showing its picks on its violet ground. Every frame is taken on a stepped clock, so animations are
  exact; once Booth listens, the clock keeps real time with the engine's listener (marks.json `times`). Words name
  "this computer", as Windows and Linux do (`DECKIE_DESK_COMPUTER=other`). The quick start's own card is hidden in the
  capture's storage, so the film does not show itself.
- `capture/ipad.sh`: the iPad picture: Deckie on the iPad simulator (a Debug build installed there), Booth naming a song
  of the crate file the capture exported, with its picks. The simulator records while the Mac is locked.
- `capture/card.mjs`: pictures of the quick start where a DJ meets it, in the same window with the real engine and fresh
  storage: the first screen with the card, the "⋯" menu, the player, the card when the web view cannot play the film
  (the poster and the four steps in words), the player when the film fails while playing, and the first screen after
  Hide (also after the engine is started again). It checks each and says what it found.
- `card-poster.sh`, `card-window.jpg`, `card-plain.jpg` (Nov 24, 2026): the card's own picture. The poster is the
  film's title frame, unreadable at card size and under the play button, so the card shows a picture with nothing to
  read behind the button. Two candidates, cut from the film that ships with ffmpeg alone: "window" (Desk's window on
  the crate's songs, softened and dimmed) and "plain" (the film's ground and violet glow, no words). The one that
  ships is `desk-web/quick-start/card.jpg`, a copy of `card-window.jpg`; to swap, copy `card-plain.jpg` over it. The
  player, and the card where the film cannot play (the steps in words), keep the poster.
- `walkthrough/sketch.html`, `sketch.js`: the in-app walkthrough sketch from the first cut (option B, not chosen).

## What it does not touch

The engine runs with its storage, its view of DJ programs and its drives in the work folder (`DECKIE_DESK_HOME`,
`DECKIE_DJ_HOME`, `DECKIE_DESK_DRIVES`), with `DECKIE_LOOKUP_OFF=1`, at `nice -n 19` and two jobs. Chrome runs with its
own profile in the work folder and no network services. Nothing is read from a DJ's music or from Desk's own storage.

## Re-rendering

With Node, ffmpeg, Python 3 with numpy, and Google Chrome. One heavy step at a time.

    W=$PWD/.scratch/quick-start-2                            # the work folder, outside git
    python3 desk-quickstart/capture/songs.py $W/songs
    mkdir -p "$W/drives/Friday stick" "$W/booth" && cp $W/songs/*.mp3 "$W/drives/Friday stick/"
    # Booth's input: one of the stick's songs as sound, from its first beat, named as the input list will show it
    ffmpeg -ss 15 -i "$W/songs/05 Ember Motel - Static Garden.mp3" -ac 1 -ar 44100 -f wav "$W/booth/Microphone"
    (cd core && nice -n 19 swift build --product deckie-desk-engine -j 2)

    # ONNX Runtime and the two models: wherever this machine has them (here, desk-app/Vendor of the main checkout)
    export DECKIE_ONNXRUNTIME_LIB=…/libonnxruntime.1.31.1.dylib
    export DECKIE_BEAT_THIS_MODEL=…/models/beat_this_final0.onnx DECKIE_YAMNET_MODEL=…/models/yamnet.onnx
    nice -n 19 node desk-quickstart/capture/live.mjs --engine $PWD/core/.build/debug/deckie-desk-engine \
        --pages $PWD/desk-web --work $W                      # about 5 minutes; frames, marks.json
    nice -n 19 desk-quickstart/capture/ipad.sh <iPad simulator udid> $W   # writes $W/ipad.png

    nice -n 19 node desk-quickstart/render.mjs --work $W --out $W/deckie-desk-quick-start-1080p.mp4
    # the film that ships: 720p, H.264 Main 3.1 (the pages ask the web view for exactly this), no sound, about 1.7 MB
    nice -n 19 ffmpeg -i $W/deckie-desk-quick-start-1080p.mp4 -vf scale=1280:720:flags=lanczos -c:v libx264 \
        -profile:v main -level 3.1 -preset slow -crf 28 -pix_fmt yuv420p -movflags +faststart -an \
        desk-web/quick-start/deckie-desk-quick-start.mp4
    nice -n 19 ffmpeg -ss 2.4 -i $W/deckie-desk-quick-start-1080p.mp4 -frames:v 1 -vf scale=1280:720 -q:v 4 \
        desk-web/quick-start/poster.jpg
    # the card's picture: both candidates from the film that ships, then the chosen one beside the poster
    sh desk-quickstart/card-poster.sh && cp desk-quickstart/card-window.jpg desk-web/quick-start/card.jpg
    nice -n 19 ffmpeg -i $W/deckie-desk-quick-start-1080p.mp4 \
        -vf "fps=1/2.5,scale=480:-1,tile=4x6:padding=6:color=0x222222" -frames:v 1 $W/contact-sheet.png
    nice -n 19 node desk-quickstart/capture/card.mjs --engine $PWD/core/.build/debug/deckie-desk-engine \
        --pages $PWD/desk-web --work $W                      # $W/card/*.png, and a check of the card

The film reads the capture's `marks.json` (what happened at which frame, where each click landed, and each frame's
moment), so a new capture with different timings still lines up; only the seconds in `film.js` and `storyboard.md` are
fixed. When the film's length changes, `DeskQuickStart.filmSeconds` in the core changes with it.

## Known limits of this cut

- **Nov 23, 2026: no Mac cut yet.** With the Mac unlocked, Desk's window was pictured from inside the app
  (`desk-app/README.md`, Pictures). macOS has not allowed Deckie Desk (or the tools that drove it) to record the screen,
  so the window server gives no picture of it, and a picture the app draws itself has no toolbar buttons and no share
  sheet. The Mac cut's own steps are exactly those: Send to iPad in the toolbar, the share sheet and AirDrop, and
  the Booth switch in the toolbar. A cut without them would be weaker than this one, so none was made. With Screen
  Recording allowed for Deckie Desk, `Snapshot.capture` takes the whole window, sheet included, and a Mac cut can be
  made from stills of each state. The share sheet's AirDrop list shows nearby people's devices, so that frame has to
  be staged with none in range, or cut.

- The Mac's own window (`desk-app/`) is not in it: the Mac was locked, and that window can only be captured unlocked.
  The one film serves the Mac too, so its captions are true on a Mac: "Export the crate file" (the Mac's File menu has
  it), "iCloud Drive, a stick or a cable" with "On a Mac, AirDrop too", "Click Booth at the top of the window", and
  and the brand frame says nothing about a computer. A Mac cut would show Send to iPad in step 3.
- The engine ran on this Mac, so the box "To get it to your iPad" in the picture lists the Mac's ways (AirDrop first);
  on Windows and Linux the box lists that computer's ways. The caption names the ways all three share.
- The stand-in drive is a folder on this Mac's disk, so the drive list gives "Friday stick" that disk's size.
- Booth hears a song file, not a room: the engine's own stand-in for an input (`DECKIE_BOOTH_SOUND`) plays one of the
  stick's songs to the listener as if the microphone heard it, so the input list shows the file's name, "Microphone".
  Everything else on the Booth screen (the song named, its place, the picks, the Shuffle dial) is the engine's own.
- The iPad picture is the simulator, fed the same song from its file (the app's Debug test hook); its small status
  line says "test file".
