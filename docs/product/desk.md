# Deckie Desk: what it does, step by step

A working document for review. First written Nov 13, 2026, from the app's code at commit e808e13 and one run of the
app on five generated songs. It describes Desk as it is today and as it should be, side by side, so each line can be
agreed, changed or struck.

Who it is for: any DJ with their own music files and a Mac. Desk is the only way to make a crate file, and Deckie
Booth does nothing without one. So if Desk is hard to use, Deckie is hard to use.

How to read it: **Today** is what the app does now. **Should be** is the proposal. Anything marked **Open** is a
choice for the owner. The decisions it rests on are D21 (crate and crate file), D24 (the same song), D25 (Desk
reads, it does not manage) and D26 (a source is shown by its own name), in `00-decisions.md`.

---

## 1. What Desk is for

One job: read a DJ's crate and write a crate file that the booth can use.

| Desk does | Desk does not |
|---|---|
| Read songs from a folder, a drive or a data CD | Mix or edit music |
| Play a song so the DJ can name it by ear, with a scrub bar (D33) | |
| Work out tempo, key, bars, style and vocals for each song | Organise a library (D25) |
| Make the fingerprints the booth recognises songs by | Burn discs or write to a drive |
| Find copies of the same recording (D24) | Send anything to a server |
| Let the DJ fix a name it read wrongly | Replace the DJ's own software |
| Hand the crate file to the iPad | |

---

## 2. The flow

As built (Nov 14, 2026, after the owner's first real use and research AE). The Mac's window and the Windows and Linux
window do the same steps with the same words; the shared parts are DeckieDesk's `DeskAddMusic`, `DeskDrives`,
`DeskSession` and `DeskRun`.

| # | The DJ does | Desk does |
|---|---|---|
| 1 | Opens Desk | The first screen: the crate's icon, "Your crate starts here.", a field "Into a new crate called [My crate]" (numbered when taken), and three buttons: **Add drive**, **Add CD**, **Add folder** |
| 2a | Add drive | Lists the sticks, cards and drives plugged in, each with an icon, its name and its size. A drive bigger than 256 GB is not read whole: "Big Drive is a big drive. It holds 2 TB. Reading a whole drive can take hours, so choose the folder your music is in." with **Choose a folder…** (the chooser opens inside the drive) and **Read the whole drive** |
| 2b | Add CD | Lists the music CDs and data CDs in a drive, or "There's no CD in a drive. Put one in." |
| 2c | Add folder, or drops a folder, drive or disc on the window | The system's folder chooser. The top of a big drive gets the big drive's question first |
| 3 | Waits a moment | Desk counts the songs first, the count rising after a moment ("Looking for songs… 1,204 songs so far"). Above 1,000 songs it asks: "Read 4,812 songs from Big Drive? That's about 9 hours of reading on this Mac. You can stop at any time, and songs already read stay in your crate." with the new crate's name to type, **Cancel** and **Read 4,812 songs**. Below the line it starts at once |
| 4 | Waits, or renames, or stops | The run screen, with the crate's icon and name above it (click to rename; the name is applied when the run ends) and **Stop**. Stop finishes the songs being read and keeps every song read |
| 5 | Reads the finished screen | "Stick 3 is in Gig Friday", or after Stop "Stopped: 120 songs from Big Drive are in Gig Friday" with **Carry on**. Then **Send to iPad** (Mac) or **Export crate file…** (Windows, Linux), **Add more music** (the same three ways), **Take this back out** (one step of undo), **What didn't go in**, **See the songs** |

Everywhere after that, the same three ways: the toolbar's **Add music** menu, the File menu (Mac), the finished
screen's **Add more music**, and a row under the songs, "Add more music to Gig Friday: Add drive, Add CD, Add folder".
The window's header shows the crate's icon and name at all times; a click renames it, as one step of undo. A new crate
is never named after the first thing read.

The two thresholds are named values with an environment variable each for tests: a big drive is over 256 GB
(`DeskAddMusic.bigDriveBytes`, research AE: sticks and cards are mostly 8 to 256 GB, a DJ's backup drive 500 GB and
up; `DECKIE_DESK_BIG_DRIVE_BYTES`), and Desk asks above 1,000 songs (`DeskAddMusic.askAboveSongs`, the review's
placeholder until real first runs on ordinary laptops are timed; `DECKIE_DESK_ASK_ABOVE_SONGS`). The time is estimated
from the runs timed on this computer, else 6 songs a minute.

### Settled Nov 13 (D28)

- **Desk keeps its crates itself.** They live in the app's own storage, not among the DJ's music. Desk never asks
  where to save.
- **A crate file appears only when the DJ sends or exports one.** A crate file made elsewhere comes in with "Import
  crate file…", as a copy.
- **A DJ can have several crates.** Desk opens on the most recent one. The header always says which crate is showing,
  with a menu beside it to switch and "New crate" at the end of it.
- **Adding music adds to the crate that is showing.**
- **Desk saves as it goes, and every change can be undone**, a rename of the crate included. Music that was added is
  undone by taking that source back out, after a confirmation.
- **A song read for one crate is not read again for another.**

**Not designed yet**: albums (the owner: "We will need to figure out the album workflow but we can do that later").

**Open**

- Whether "With a rekordbox collection…" stays on the first screen (Mac). Proposal: move it to the File menu.
- The crate's icon is a placeholder (Deckie's record in its line form, one named asset) until the design pass.

---

## 3. Every word on screen

**These words are placeholders (D28).** Every word is in DeskWords (`core/Sources/DeckieDesk/DeskWords.swift`), one
list for both windows; the copy audit changes that file. The rule (voice.md): the DJ's own words, plain, sentence
case. A crate is the songs; a crate file is the file.

### The first screen

| Word | Where |
|---|---|
| Your crate starts here. | Title |
| Add your music. Desk reads the tempo, key and bars of every song and writes a crate file, a small file you send to your iPad. Your music never leaves this Mac. | Below it |
| Into a new crate called [My crate] | The new crate's name |
| Add drive · Add CD · Add folder | The three ways, everywhere music is added |
| With a rekordbox collection… · Import crate file… | Below them (the rekordbox route on the Mac only) |
| Drop a folder here to add it | The last line |

### Adding music

| Word | Where |
|---|---|
| Add a drive · The sticks, cards and drives plugged in now. Desk reads one as it is. | Add drive's list; each row "Stick 3", "16 GB" |
| Big drive: you choose a folder in it | Under a big drive in the list |
| No stick, card or drive is plugged in. Plug one in, or add a folder. | An empty list |
| Add a CD · The CDs in a drive now. Desk reads one as it is. · There's no CD in a drive. Put one in. | Add CD's list |
| Big Drive is a big drive · It holds 2 TB. Reading a whole drive can take hours, so choose the folder your music is in. · Choose a folder… · Read the whole drive | A big drive's question |
| Choose the folder your music is in on Big Drive. Desk reads only that folder. | The chooser inside a big drive |
| Looking for songs… · 1,204 songs so far | The count |
| Read 4,812 songs from Big Drive? · That's about 9 hours of reading on this Mac. You can stop at any time, and songs already read stay in your crate. · Read 4,812 songs | The question before a large read |

### While it works

| Word | Where |
|---|---|
| (the crate's icon and name) · Stop | Above the run screen; Stop's help: "Stop reading. Songs already read stay in your crate." |
| Stopping once the songs being read are done… | After Stop |
| Reading your crate · Adding Stick 3 to Gig Friday | Title and line |
| 12 of 240 songs · About 4 minutes left | Progress |

### The finished screen

| Word | Where |
|---|---|
| Stick 3 is in Gig Friday | Title |
| Stopped: 120 songs from Big Drive are in Gig Friday · The rest isn't read yet. Carry on whenever you like: the songs already read are not read again. · Carry on | After Stop |
| Send to iPad · Add more music · Take this back out · What didn't go in · See the songs | Actions |

### The toolbar and the header

| Word | Where |
|---|---|
| (the crate's icon) Gig Friday | The header, at all times; click: "Rename Gig Friday", button **Rename** |
| Add music | The toolbar's menu of the three ways, with its words and a plus |
| Sources | Now a list icon, not a drive's (it was the same drive icon as Add music) |
| Send to iPad · What didn't go in · Name songs | As before |
| Add more music to Gig Friday · Add drive · Add CD · Add folder | The row under the songs |

Rename buttons say **Rename**, not OK, everywhere (the crate, a source, a folder).

### The table and the side panel

| Today | Should be | Why |
|---|---|---|
| Title, Artist, Tempo, Key, Bars, Length, Vocals, Notes | The same | Keep |
| Disc (column) | Source | D26 |
| Names (panel heading) | Names | Keep |
| What Deckie found | What Desk found | The app's own name |
| Same recording as | Also in your crate as | Plainer |
| Where is this crate's music? | Where is this music? | |

### The bottom line

| Today | Should be |
|---|---|
| 240 tracks | 240 songs |
| 240 with signatures | (gone when all have them) or "12 can't be recognised yet" |
| 3 files not in the crate or with a note | 3 files didn't go in |
| Unsaved changes | (gone if Desk saves as it goes) |

### Messages

| Today | Should be |
|---|---|
| Could not open the crate: … | Couldn't open that crate file. … |
| Could not save the crate: … | Couldn't save the crate file. … |
| The build stopped: … | Desk stopped before it finished. … Songs already read are kept. |
| Every file went in cleanly. | Every song went in. |
| This crate carries no import log. | No record of what didn't go in. |

### The Sources panel (being built, D25 and D26)

Title "Sources". It lists what Desk read, each by its own name, with its folders and songs in order. It is for
corrections: a name, or an order Desk read wrongly.

---

## 4. What each step needs

What has to be true for each step to work, and what the DJ sees if it is not.

| Step | Needs | If it is missing |
|---|---|---|
| Opening Desk | A Mac with Apple silicon, macOS 14 or later | **Today: does not open on another DJ's Mac at all** (section 5) |
| Reading songs | Files Desk can read: MP3, WAV, AIFF, FLAC, AAC, Apple Lossless | Listed in "What didn't go in", counted by kind |
| | Not a rights-protected download from a streaming service | Listed, with the reason said plainly |
| Tempo, bars, vocals | The two models inside the app | Nothing to install; they ship in it |
| Fingerprints | The music still where it was when it was read | Today: asks "Where is this crate's music?" |
| Copies | The music still there, as above | Same |
| Names | The file's own tags, or its file name | The DJ fixes it in the table |
| Sources | The drive or CD plugged in while Desk reads it | Not needed afterwards |
| Sending to the iPad | AirDrop, iCloud Drive or a cable | The share sheet offers what the Mac has |
| The booth using it | The crate file on the iPad, opened in Deckie Booth | The booth's first screen says there is none yet |

What a step depends on from the steps before it:

| To do this | These must be done first |
|---|---|
| Picks in the booth | Reading |
| The booth naming a song | Reading, fingerprints |
| One row per song, "also on" | Reading, copies |
| A place for every song | Reading from a source, or from a folder |

Today the DJ has to know this table. With one run, they do not.

---

## 5. Getting Desk onto a DJ's Mac

| | Today | Needed |
|---|---|---|
| Signing | Ad hoc: opens only on the Mac that built it | A Developer ID certificate, and Apple's notarisation |
| How a DJ gets it | They can't | A download, or TestFlight for Mac. **Open** |
| Intel Macs | Not supported; never tried | **Open**: support them or say so |
| Size | Not measured | Measure |
| Updates | None | TestFlight gives this; a download needs its own way |

---

## 6. What is not known

- How long a first run takes on a real library on another Mac. The five generated songs took 1.8 seconds each, but
  they are short. The one-run version will time itself and say.
- Whether the order Desk reads from a source is the order every player shows. To be checked on real discs.
- Whether a deck running several percent fast or slow is recognised. The fingerprints are made at the song's own
  speed; the ones for other speeds are planned and not built. This decides whether Deckie works behind real decks,
  and it is Desk's work to do.
- How Desk behaves with tens of thousands of songs.

---

## 7. Order of work proposed

1. One run and the words: sections 2 and 3.
2. Signing and notarisation: section 5.
3. Fingerprints at other speeds: section 6.

Reading sources (D25, D26) is being built now.
