# Quick start storyboard

The film recommended in research AG (option C): 52.5 seconds, silent, captions in the picture, 1080p. It is started
by the DJ (a line on the first screen, and the Help menu or the "…" menu), never by itself. The pictures are the real
Windows and Linux window, captured by `capture/live.mjs`; the booth is the site's own capture. The window sits on the
left, the step and its caption on the right. The pointer is drawn where the capture really clicked.

Words follow `docs/product/voice.md`: sentence case, "songs", a crate is the songs and a crate file is the file,
"this computer" on Windows and Linux. Lines are broken by phrase, a few words to a line, never one word alone.
Pacifico for "you", "your" and "Deckie" only.

| # | Seconds | Picture | Step (top of the column) | Caption |
|---|---|---|---|---|
| 0 | 0.0 to 4.2 | Title card on the dark background, no window | | **Deckie Desk** (script), QUICK START, then: From your music / to the booth / in four steps. |
| 1a | 4.2 to 8.6 | The first screen. The pointer goes to the name field; "Gig Friday" is typed over "My crate"; the camera moves in on the name and the three buttons | 1 · Step 1 of 4 · Add your music | Name your crate, / then add a stick, / a CD or a folder. |
| 1b | 8.6 to 12.8 | The pointer clicks **Add drive**; "Add a drive" opens with Friday stick; the camera moves in on the list; the pointer clicks Friday stick | (same) | Pick the one / your songs are on. *Smaller:* Desk reads them / where they are. |
| 2a | 12.8 to 19.2 | The run screen: "Reading your crate", the count rising, the song on stage with its tempo, key and bars; the camera on the top half. The whole run (12 songs, about 2 minutes) plays in 12 seconds | 2 · Desk reads / every song | Tempo, key, bars / and vocals, / song by song. |
| 2b | 19.2 to 25.4 | The camera moves to **Stop** and the line under the count ("You can leave this running…"); Stop is ringed | (same) | Stop at any time. / Songs already read / stay in your crate. |
| 2c | 25.4 to 29.6 | The finished screen: "Friday stick is in Gig Friday", one line a song, the counts | (same) | When it's done, / it tells you / what went in. |
| 3a | 29.6 to about 33 | The finished screen scrolls to its buttons; the pointer clicks **Export crate file…**; "The crate file is in Documents." and the box "To get it to your iPad" appear | 3 · Get the crate file / to your iPad | Export the crate file. / It's small: / no music inside. |
| 3b | about 33 to 38.8 | The camera moves in on "To get it to your iPad" (a stick or card, iCloud Drive, a cable); the box is ringed | (same) | A stick, iCloud Drive / or a cable / gets it there. |
| 4a | 38.8 to 43.5 | The window slides out; an iPad comes in with Deckie Booth naming a song, picks beside it (the demo crate) | 4 · Open it in / Deckie Booth | Set the iPad / beside the decks. |
| 4b | 43.5 to 48.2 | The iPad, a slow push in | (same) | It names the song playing / and shows what / could come next. |
| 5 | 48.2 to 52.5 | End card, no picture | | Your music never leaves / this computer. *Smaller:* Know Your Crate |

**Where the words come from.** "Desk reads every song", "tempo, key and bars", "your music never leaves this
computer" and "Songs already read stay in your crate" are Desk's own words (DeskWords: `firstBody`, `stopRunHelp`).
"A stick, iCloud Drive or a cable" summarises the box the window shows (`toIPadStick`, `toIPadICloud`,
`toIPadCable`). "No music inside" is D21: a crate file holds what Desk found, never audio (the one exported in the
capture is 248 KB for 12 songs, 25 MB of music).

**For the Mac.** The same film serves until the Mac's window can be captured (it needs the Mac unlocked). The Mac
version would change beat 3: "Send to iPad", the share sheet, AirDrop; caption "Send it to your iPad. / AirDrop
is one click." The Mac's finished screen has no "To get it to your iPad" box yet (letter AE, problem 15).

**Not shown, on purpose.** Add CD and Add folder (named in the caption, not clicked: one way is enough to teach
the three), the question before a read of more than 1,000 songs, naming songs, Sources, the rekordbox route, several
crates. A quick start shows the one path; the rest is found on the screens.
