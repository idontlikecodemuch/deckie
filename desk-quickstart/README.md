# Deckie Desk's quick start

A first cut of the film a DJ could watch the first time they open Deckie Desk, and a sketch of the alternative, a
walkthrough over the real screens. The reasons, the options and the recommendation are research letter AG
(`docs/research/ag-desk-quick-start.md`); the beats and their words are `storyboard.md`. Nothing here is wired into
Desk yet: that waits for the owner's choice.

## What is here

- `storyboard.md`: every beat of the film: the picture, the caption and its seconds.
- `film.html`, `film.js`: the film, drawn on a canvas as a pure function of time (`film.seek(t)`). It frames the
  capture, moves the camera, draws the pointer where the capture clicked, rings what a caption names, and sets the
  captions. The look is the explainer film's (`site/film/`): the booth's colours, Inter, and Pacifico for "you",
  "your" and "Deckie" only. It has no sound.
- `render.mjs`: renders the film (or single pictures of it) in headless Chrome, frame by frame, into ffmpeg.
- `capture/songs.py`: twelve generated songs with invented titles and acts (made the way the demo crate's names are);
  drums, bass and chords made from nothing. Never a real song or artist.
- `capture/live.mjs` and `capture/clock.js`: the capture. Desk's Windows and Linux window (the pages in `desk-web/`,
  unchanged) in headless Chrome, talking to the real engine (`deckie-desk-engine`) on the generated songs, clicked
  through as a DJ would: the new crate's name typed, Add drive, the stick, the whole run, the finished screen,
  Export crate file, the box "To get it to your iPad". Every frame is taken on a stepped clock, so animations are
  exact. Words name "this computer", as Windows and Linux do (`DECKIE_DESK_COMPUTER=other`).
- `walkthrough/sketch.html`, `sketch.js`: the in-app walkthrough sketch (option B): five boxes over frames of the same
  capture. Pictures only.

## What it does not touch

The engine runs with its storage, its view of DJ programs and its drives in the work folder (`DECKIE_DESK_HOME`,
`DECKIE_DJ_HOME`, `DECKIE_DESK_DRIVES`), with `DECKIE_LOOKUP_OFF=1`, at `nice -n 19` and two jobs. Chrome runs with its
own profile in the work folder and no network services. Nothing is read from a DJ's music or from Desk's own storage.

## Re-rendering

With Node, ffmpeg, Python 3 with numpy, and Google Chrome. One heavy step at a time.

    W=.scratch/quick-start                                   # the work folder, outside git
    python3 desk-quickstart/capture/songs.py $W/songs
    mkdir -p "$W/drives/Friday stick" && cp $W/songs/*.mp3 "$W/drives/Friday stick/"
    (cd core && nice -n 19 swift build --product deckie-desk-engine -j 2)

    # ONNX Runtime and the two models: wherever this machine has them (here, desk-app/Vendor of the main checkout)
    export DECKIE_ONNXRUNTIME_LIB=…/libonnxruntime.1.31.1.dylib
    export DECKIE_BEAT_THIS_MODEL=…/models/beat_this_final0.onnx DECKIE_YAMNET_MODEL=…/models/yamnet.onnx
    nice -n 19 node desk-quickstart/capture/live.mjs --engine $PWD/core/.build/debug/deckie-desk-engine \
        --pages $PWD/desk-web --work $W                      # about 4 minutes; frames, marks.json

    nice -n 19 node desk-quickstart/render.mjs --work $W --out $W/deckie-desk-quick-start-1080p.mp4
    nice -n 19 ffmpeg -i $W/deckie-desk-quick-start-1080p.mp4 -vf scale=1280:-2 -c:v libx264 -preset slow \
        -crf 27 -pix_fmt yuv420p -movflags +faststart $W/deckie-desk-quick-start-phone.mp4
    nice -n 19 ffmpeg -i $W/deckie-desk-quick-start-1080p.mp4 \
        -vf "fps=1/2.5,scale=480:-1,tile=4x6:padding=6:color=0x222222" -frames:v 1 $W/contact-sheet.png
    nice -n 19 node desk-quickstart/render.mjs --work $W --page walkthrough/sketch.html --stills $W/walkthrough --at 1,2,3,4,5

The film reads the capture's `marks.json` (what happened at which frame, and where each click landed), so a new
capture with different timings still lines up; only the seconds in `film.js` and `storyboard.md` are fixed.

## Known limits of this cut

- The Mac's own window (`desk-app/`) is not in it: the Mac was locked, and that window can only be captured
  unlocked. The film shows the Windows and Linux window, with "Export crate file…" where the Mac has "Send to iPad".
- The stand-in drive is a folder on this Mac's disk, so the drive list gives "Friday stick" that disk's size
  (494 GB). Disk images that would give a stick's size could not be made here.
- After Export, the pages say "The crate file is in" and the folder's whole path. The capture shortens that one line
  to the folder's own name, "Documents", so no path on this Mac is in a film. It is the only change made to a page.
- The finished screen is taller than a 1280 by 800 window, so the capture scrolls down to its buttons.
- The booth beat is a still from the site's own capture of Deckie Booth (`site/assets/booth-listen.jpg`, the demo
  crate), not a recording made for this film; the step of opening the crate file on the iPad is not shown.
