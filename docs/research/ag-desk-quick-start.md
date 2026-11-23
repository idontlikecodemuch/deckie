# Research AG: how a DJ learns Deckie Desk the first time

Dated Nov 16, 2026, at main 500be1c. A research letter with a first cut: what good first-run help looks like, what a
new Desk DJ has to understand and where today's screens already say it, three options and one recommendation. The
storyboard of the recommended quick start, its first cut and a sketch of the in-app walkthrough are in
`desk-quickstart/`. Nothing in Desk was changed.

The request: a "how to" or "quick start" video for when Desk is first opened, or a full walkthrough in the app, so
people know what to do. The form was left open.

**Tags.** [read] = I opened the page for this letter; [snip] = seen only through a search summary; [code] = read in
Desk's code or word list; [ran] = seen in a capture made for this letter; [inf] = my inference. Sources S1 to S12
are at the end.

## In plain words

Most help that pops up on its own gets skipped, and what is learned from it is soon forgotten. Help works when the DJ
asks for it, when it is short, and when it sits on the screen where the DJ needs it. So the recommendation is in two
small parts: a **silent film of under a minute** with captions, which the DJ starts from a line on the first screen
and can play again from the Help menu (the "…" menu on Windows and Linux), and **three short lines added to Desk's
own screens** where they leave a step unsaid today (that Stop keeps what was read; on the Mac, how the crate file
gets to the iPad; what to do in the booth). A
step-by-step tour over the interface is not recommended for now: Desk has one obvious path, and a tour would cover
words that are already on the screen.

---

## 1. What good first-run help looks like

Four forms, with an example of each.

**A short film the DJ chooses to watch.** Ableton Live opens its Learn View the first time, a panel of lessons that
"combine video content with written explanations"; it can be closed and opened again from the Help menu, and
returns to the last page visited (S1, [read]). Audacity's first window is a welcome with a link to a video and a
"Don't show this again at start up" box; it can be reopened from the Help menu (S2, [snip]). What the research on
instructional film says: shorter is better, show the length before it plays, and put the words on screen, because
many people watch without sound (S3, [read]; letter V, section 1). Video "moves at the creator's pace" (S3), so it
works for a picture of the whole job, not for a step the DJ is doing at that moment.

**A step-by-step tour over the real interface** (coach marks: a box pointing at a button, Next, Next, Done). Nielsen
Norman Group's review: tours that open by themselves interrupt people who "want to start using the product right
away", are skipped, and are forgotten (S4, [read]). The only figures with a stated method are one vendor's 2026
benchmark of 256 web tours: half or more finish a tour of one or two steps, 38 percent one of three to five, 8
percent one of nine or more; and 69 percent finish a tour the person opened themselves against 23 percent of tours
that started on their own (S5, [read]). The vendor warns that the second gap is mostly who chooses to open a tour.
These are web products, not desktop programs [inf], but the direction agrees with S4.

**Coaching in the screens themselves.** Help written into the empty or waiting screen, at the moment it is needed:
an empty list that says how to fill it (S6, [read]), a tip that appears after the action it explains (Figma's text
tip, in S4). Apple's guidance asks the same of onboarding: "teach through interactivity", keep it brief and optional,
and if it is skipped do not show it again but "make sure it's easy for people to find" later (S7, [read]). Ableton's
Info View, which names whatever the pointer is over, is the desktop version of this (S1, [read]).

**A checklist.** A short list of the steps to a first result, ticked as they are done. Common in web products (S8,
[snip]); its known weakness is that people finish the list and still do not keep using the product (S9, [snip]).
For Desk the checklist is four lines long and the screens already lead from one to the next [inf], so it adds little.

**What DJ programs do.** rekordbox's first launch is a run of setup windows and an account; its manual and tutorials
are outside the program (S10, [snip]). Mixed In Key keeps its how-to on its site (S11, [snip]). Neither teaches in
the program's own screens [snip, so this may be out of date].

**What tends to be resented or skipped** (S4, S5, S7; [inf] where marked):
- Help that starts by itself and must be dismissed before work can begin.
- Long tours: completion falls with every step (S5).
- Sound that plays without being asked [inf: a DJ may open Desk in a room with music on, or late at night].
- Help that can't be found again after it was dismissed (S7).
- Film that is out of date with the screens [inf: Desk's words are placeholders until the copy audit, D28 and D36,
  so a film must be cheap to remake; this one is made by code from the real pages and remakes in minutes].
- Anything that needs the internet: Desk must work with none (Ableton's lessons do need it, S1).

---

## 2. What a new Desk DJ has to understand, in order

What today's screens say, from the word list (`core/Sources/DeckieDesk/DeskWords.swift`) [code] and the capture of
the Windows and Linux window made for this letter [ran].

| # | The DJ has to understand | Where today's screens say it | Gap |
|---|---|---|---|
| 1 | What Desk is for: it reads the music and writes a small crate file for the iPad; the music stays here | First screen: "Add your music. Desk reads the tempo, key and bars of every song and writes a crate file, a small file you send to your iPad. Your music never leaves this computer." | **Said.** Nothing says why: that the booth needs this file to name songs and suggest what's next |
| 2 | The three ways to add music: a drive (stick or card), a CD, a folder; or drop a folder | First screen's three buttons and "Drop a folder here to add it"; Add drive's "The sticks, cards and drives plugged in now. Desk reads one as it is." | **Said.** "As it is" is the only hint that nothing is copied or moved |
| 3 | What happens while it reads, and that they can stop and keep what was read | Run screen: "Reading your crate", the count, the time left, what Desk is listening for, the song just read with its tempo, key and bars, and Stop. Under the count: "You can leave this running. If Desk is closed, you can carry on from here next time." "Songs already read stay in your crate" is said only in Stop's hover tip and in the question before a read of more than 1,000 songs | **Mostly.** Leaving and carrying on are said; that Stop keeps what was read is not, on a read under 1,000 songs, except to someone who hovers over Stop |
| 4 | What "done" looks like | Finished screen: "Friday stick is in Gig Friday", the counts, "Next, send the crate file to your iPad." | **Said** |
| 5 | How the crate file gets to the iPad | Windows and Linux: after Export, "To get it to your iPad" with three ways (a stick or card, iCloud Drive, a cable). Mac: Send to iPad opens the share sheet; nothing after it | **Said on Windows and Linux. Not on the Mac** (AE problem 15) |
| 6 | What to do in the booth: open the crate file in Deckie Booth, put the iPad beside the decks, it names the song playing and shows what could come next | Nowhere in Desk | **Not said.** The booth's own empty screen says "No crate file yet" (voice.md), but a DJ who has not installed the booth yet is never told |

So Desk already teaches steps 1, 2 and 4 in its own words. The gaps are 3, 5 on the Mac, and 6, and the whole picture
in one go: that Desk is the first half of a two-part job.

---

## 3. Options

### Option A: a quick-start film only

A film of under a minute (the first cut is 52 seconds), silent, with captions burned into the picture, made from
captures of the real window. On the first screen, under the buttons, one line: "New to Desk? Watch the quick start (1 minute)". It opens in the
window, plays, and closes back to the first screen. It never plays by itself. Also in the Help menu (Mac) and the
"…" menu (Windows and Linux) as "Quick start film", so it plays again any time. The line on the first screen shows
until the first crate has songs, then goes.

- Ships inside the app: an H.264 file played by the system (the Mac's own player; a `<video>` element in the Windows
  and Linux pages). The first cut is 52.5 seconds at 1080p and **6.9 MB**. Budget: **12 MB** at most; the app
  already carries ONNX Runtime and two models, about 140 MB on the Mac [measured in the main checkout's
  `desk-app/Vendor`], so the film adds well under a tenth.
- Works with no internet.
- Cost to keep: re-render when a screen changes; the source is in `desk-quickstart/` and runs in minutes.
- Weakness: it is watched once, away from the moment each step happens.

### Option B: a walkthrough over the real screens

Five boxes, each pointing at the real control, on the first screen, the run screen and the finished screen
(the sketch is `desk-quickstart/walkthrough/`). Started from the same line on the first screen, or the Help menu,
never by itself. Each box: a title and one or two sentences, Skip and Next.

- Ships as words in DeskWords and a small overlay in each window; no film, almost no size.
- Weakness: it repeats words that are already on the screen (steps 1, 2 and 4 above), and S5 says a five-step tour
  is finished by fewer than half of those who start it. It also needs building twice, once per window.

### Option C (recommended): the film, plus three lines in the screens

Option A's film, started by the DJ, and three short lines added where a step goes unsaid today:

1. **Run screen**, in the line under the count that already says "You can leave this running…": "You can stop at
   any time. Songs already read stay in your crate." (the words of `stopRunHelp`, made visible).
2. **Mac finished screen**, after Send to iPad: the Windows box "To get it to your iPad", adapted: "AirDrop it, or
   save it to iCloud Drive and open it from Files on the iPad."
3. **Both finished screens**, one line under the iPad step: "Then open it in Deckie Booth, and set the iPad beside
   the decks."

| | Where it lives | Plays again | Length | Sound | Ships as | Size |
|---|---|---|---|---|---|---|
| A | A line on the first screen; Help menu (Mac), "…" menu (Windows, Linux) | Yes, from the menu, any time | Under a minute (this cut 52 s) | Silent, captions in the picture | H.264 in the app | 6.9 MB at 1080p (first cut), budget 12 MB |
| B | Same entry points; boxes over the real screens | Yes, from the menu | 4 to 5 steps | None | Words in DeskWords, an overlay | Under 50 KB [inf] |
| C | A's film, and three lines in the run and finished screens of both windows | Film from the menu; the lines are always there | Under a minute, plus three sentences | Silent | As A, and three sentences in DeskWords | As A |

**Why C.** The film gives the whole picture, which is the one thing the screens can't (S1, S2, S3: a short, chosen,
captioned film); it is chosen, not imposed, which is where most of S5's skipping comes from; it is silent because a
DJ's room may already have music in it. The three lines put the missing steps at the moment they matter, the way S4,
S6 and S7 ask, and they stay useful after the film is forgotten. A tour is left out because Desk's path is short and
already worded on screen, and a tour that repeats those words is the kind that is skipped (S4, S5). It can be
revisited once real DJs have tried Desk: if they get stuck at a particular step, a single pointer there is cheaper
than a tour.

**Open for the owner.** Whether the film's first-screen line goes once the first crate has songs, or stays as a
small link; whether the film also goes on the site; whether the Mac film should be made from the Mac window (needs
an unlocked Mac) or the same film serves both, with "Export crate file" shown and the Mac's "Send to iPad" named in a
caption.

---

## 4. The first cut, measured

The source, the storyboard and how to re-render are in `desk-quickstart/` (its README). The renders stay out of git.
[ran, measured]

| | |
|---|---|
| Length | 52.5 seconds: a title, four steps, an end card |
| Master | 1920 by 1080, H.264, 30 frames a second, no sound: 6.9 MB |
| Phone copy | 1280 by 720, H.264: 3.0 MB |
| Capture | The Windows and Linux window (desk-web, unchanged) at 1280 by 800, talking to the real engine built from main, reading 12 generated songs (25 MB of music, 17 minutes) from a stand-in stick in 1 minute 58 seconds; every frame on a stepped clock, so it is exact and re-makeable |
| The crate file it exported | 248 KB for the 12 songs, which is why the film can say "small: no music inside" |
| Render | About 3 minutes for the capture's run, 3 minutes for the film, at the lowest priority, one at a time |

**What the film shows that is not true of the app yet.** Nothing in Desk's screens: every picture of Desk is the
real window. Three things are staged or borrowed, and are said in the README: the line "The crate file is in
Documents." is shortened from the full path of the work folder; the stand-in stick is a folder on this computer's
disk, so the list gives it that disk's size (494 GB); the booth is a still of the demo crate from the site, and
the step of opening the crate file on the iPad is not shown. The Mac window is not in the film, because it can only
be captured with the Mac unlocked; for the Mac, beat 3 would show Send to iPad.

**The walkthrough sketch** (option B) is five pictures in `desk-quickstart/walkthrough/` (rendered to the work
folder): the first screen's name and three ways, the stick in Add a drive, Stop, Export crate file, and the box "To
get it to your iPad", each dimmed around one control with a box of one or two sentences, Skip and Next.

---

## 5. Nov 21, 2026: the film becomes Desk's opening video

**What changed.** The owner chose the film as Desk's opening video (D46). It was remade against Desk as it is today,
and wired into both windows. Plain statements of what moved, and why:

- **Desk changed under the first cut.** Since Nov 16 the run screen gained an explainer line above the song card and
  the title "Reading {source}", the finished screen a wall of the crate's songs, and Desk gained Booth (D42 to D44):
  it can listen through the computer's microphone, name the song playing and show the picks, on a violet ground. The
  iPad app is now called Deckie and its listening mode Booth (D43), so the first cut's "Deckie Booth" is gone from
  the film, the storyboard and Desk.
- **The film's path now has an answer for a DJ with no iPad.** After the four steps, a beat labelled "No iPad?" shows
  Booth in Desk: the switch in the bar, Desk getting the crate ready, the song named, its picks. It is captured from
  the real pages and engine, the listener fed one of the generated songs through the engine's own stand-in for an
  input.
- **The iPad is current.** The first cut borrowed the site's still of an older build. This one is a picture of Deckie
  in the iPad simulator naming a song of the very crate file the capture exported.
- **The words are true on a Mac.** The Mac's window could not be captured (the Mac was locked), so the one film serves
  all three systems; no caption says "this computer" or names a button only one window has.
- **Length.** 58 seconds, against 52.5: the Booth beat added 9.6 seconds and the rest was tightened (the run plays in
  10 seconds instead of 12).
- **How it is offered.** As option C said, it is started by the DJ: a card at the top of the first screen (poster,
  play button, "New to Desk?", "Watch the quick start (1 minute)", Hide), then the Help menu or the "⋯" menu. It does
  not play by itself; one constant in the core would make it play once on the very first open. The card stays until
  hidden, rather than going once the first crate has songs: the first screen is not shown once a crate has songs, so
  the card is seen only while a DJ has none, and Hide is one click.
- **When the film cannot play.** WebKitGTK on Linux may have no H.264 decoder, and any player can fail; the card and
  the player then show the poster and the film's four steps in words, with one plain line, never a dead player. Each
  window's own check (`deckie-desk --check`, run in CI on Linux and Windows) now says whether the film loads in that
  web view and tries the fall-back.
- **The three lines.** Checked against today's screens: the run screen still said that Stop keeps what was read only in
  Stop's tooltip; the Mac's finished screen still had nothing after Send to iPad; neither finished screen said what
  happens in the booth. All three are added (D46). The third reads "Then open it in Deckie on the iPad, and set the
  iPad beside the decks."
- **Measured.** The film as shipped: 1280 by 720, H.264 Main, no sound, 1.7 MB, with a 26 KB poster, against a
  budget of 12 MB. The capture read 12 generated songs (25 MB of music) and exported a crate file for them.

**Nov 23, 2026: the close.** On the owner's decision the end card ("Your music never leaves your computer.") was
replaced by a brand frame: Deckie's icon, the name written on in the script face, and "Know Your Crate", as the site's
explainer film closes. The privacy sentence stays on Desk's first screen, where it was already said; a quick start ends
on the name. The film is now 57.6 seconds; the bundled 720p file is still 1.7 MB and the poster is unchanged.

**Nov 23, 2026: seen in the Mac app.** The quick start was looked at in the running Mac app for the first time, on
scratch storage (`--quick-start-walk`, desk-app/README.md). The card, the film in its sheet, Help > Watch the quick
start, Hide and both fall-backs (a file that is not a film, no file) work. Three things looked wrong and were fixed: at
the smallest window the first screen did not fit (the body cut short with "…", the last line below the window), the
three tiles of the ways in were three heights, and the sheet's steps in words were squeezed to half their width. A Mac
cut of the film was not made: without Screen Recording permission for Deckie Desk, the toolbar (Send to iPad, the
Booth switch) and the share sheet cannot be pictured, and those are the Mac cut's own steps.

**Still open for the owner.** Silent, or with a quiet bed of music; one film, or a Mac cut made from the Mac's own
window once it can be captured unlocked; whether the film plays by itself on the very first open (built, switched
off); whether the film also goes on the site.

---

## Sources

- S1 Ableton, Live 12 manual, "First Steps" (Learn View, Info View). https://www.ableton.com/en/live-manual/12/first-steps/ [read]
- S2 Audacity's welcome dialog: source documentation and the older manual's Interface preferences. https://doxy.audacityteam.org/class_splash_dialog.html ; https://forum.audacityteam.org/t/inert-persistent-welcome-to-audacity-window/31804 [snip]
- S3 Nielsen Norman Group, "Instructional Video Guidelines". https://www.nngroup.com/articles/instructional-video-guidelines/ [read]
- S4 Nielsen Norman Group, "Onboarding Tutorials vs. Contextual Help". https://www.nngroup.com/articles/onboarding-tutorials/ [read]
- S5 Produktly, "SaaS Onboarding & In-App Engagement Benchmarks 2026". https://produktly.com/research/saas-onboarding-benchmarks-2026 [read]
- S6 Nielsen Norman Group, "Designing Empty States in Complex Applications". https://www.nngroup.com/articles/empty-state-interface-design/ [read]
- S7 Apple Human Interface Guidelines, Onboarding. https://developer.apple.com/design/human-interface-guidelines/onboarding [read, through the page's data file]
- S8 Appcues, "Onboarding UX: patterns, best practices, and real examples". https://www.appcues.com/blog/user-onboarding-guide [snip]
- S9 Usercall, "Onboarding UX best practices that actually increase activation (not just checklist completion)". https://www.usercall.co/post/onboarding-ux-best-practices-that-actually-increase-activation-not-just-checklist-completion [snip]
- S10 rekordbox 7.2.14 introduction (first launch). https://cdn.rekordbox.com/files/20260409151246/rekordbox7.2.14_introduction_EN.pdf [snip]
- S11 Mixed In Key, "How to use Mixed In Key". https://mixedinkey.com/workflows/how-to-use-mixed-in-key/ [snip]
- S12 Nielsen Norman Group, "Video Usability". https://www.nngroup.com/articles/video-usability/ [snip]
