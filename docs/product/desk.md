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
| Read songs from a folder, a drive or a data CD | Play, mix or edit music |
| Work out tempo, key, bars, style and vocals for each song | Organise a library (D25) |
| Make the fingerprints the booth recognises songs by | Burn discs or write to a drive |
| Find copies of the same recording (D24) | Send anything to a server |
| Let the DJ fix a name it read wrongly | Replace the DJ's own software |
| Hand the crate file to the iPad | |

---

## 2. The flow

### Today: six steps, three of them easy to miss

| # | The DJ does | Desk does | What goes wrong |
|---|---|---|---|
| 1 | Opens Desk | Shows "Your crate starts here." and three buttons | |
| 2 | Presses "New crate from folder…", picks the music folder, picks where the file goes, presses "Build" | Analyses every song, with a progress bar and minutes left | Two file choosers in a row, the second with no clear reason |
| 3 | Presses "Make signatures" | Makes the fingerprints | **If skipped, the booth never names a song, and nothing says why** |
| 4 | Presses "Find copies" | Links copies of the same recording | If skipped, copies show as separate songs |
| 5 | Presses "Save" | Writes the changes | Easy to forget after steps 3 and 4 |
| 6 | Presses "Show in Finder", then AirDrops the file or puts it in iCloud Drive | Opens Finder | Nothing says what to do next |

### Should be: three steps

| # | The DJ does | Desk does |
|---|---|---|
| 1 | Opens Desk and presses "Add music" | Offers a folder, or a drive or CD that is plugged in |
| 2 | Waits | Does everything in one run: analysis, fingerprints, copies, save. One progress bar. Says how long is left |
| 3 | Presses "Send to iPad" | Opens the Mac's share sheet, so AirDrop is one click |

After step 2 a finished screen says: how many songs went in, how many did not and why, and what to do next.

Adding more music later is the same step 1. Songs already done are not done again.

### Settled Nov 13 (D28)

- **Desk keeps its crates itself.** They live in the app's own storage, not among the DJ's music, where a crate
  file could be mistaken for a music file and moved or deleted. Desk never asks where to save.
- **A crate file appears only when the DJ sends or exports one.** "Send to iPad" and "Export crate file…" make it.
  A crate file made elsewhere comes in with "Import crate file…", as a copy.
- **A DJ can have several crates.** Desk opens on the most recent one. The window always says which crate is
  showing, with a menu to switch and "New crate" at the end of it.
- **Add music adds to the crate that is showing**, and says so: "Add music to Friday night". There is no separate
  question about which crate.
- **Desk saves as it goes, and every change can be undone.** A name fix, a rename or a reorder undoes with
  Command-Z. Music that was added is undone by removing that source or folder from the crate, after a confirmation.
- **A song read for one crate is not read again for another.** Desk keeps what it worked out for each file, so
  adding the same stick to a second crate is quick.

**Open**

- Whether "With a rekordbox collection…" stays on the first screen. Proposal: move it to the File menu.

---

## 3. Every word on screen

**These words are placeholders (D28).** A separate audit will set every word across the site, the film, Desk and
the booth together, in one copy and design reference. Until then the tables below are proposals, and the apps keep
every word in one list each, by name, so the audit changes one file.

The rule (voice.md): the DJ's own words, plain, sentence case. A crate is the songs; a crate file is the file. No
word of ours where a plain one exists.

### The first screen

| Today | Should be | Why |
|---|---|---|
| Your crate starts here. | Your crate starts here. | Keep |
| Point Deckie at a folder of music. It reads the beat, the key, the structure and the loudness of every track and writes a crate, a small file you move to the iPad. The music never leaves this Mac. | Add your music. Desk reads the tempo, key and bars of every song and writes a crate file, a small file you send to your iPad. Your music never leaves this Mac. | "Crate" was used for the file; "track" becomes "song" |
| New crate from folder… | Add music | The DJ adds music; the file follows |
| With a rekordbox collection… | (File menu) Add names from rekordbox… | Open, above |
| Open a crate… | Open a crate file… | D21 |

### While it works

| Today | Should be | Why |
|---|---|---|
| Building the crate | Reading your crate | Desk reads the crate and writes the file |
| 12 of 240 tracks | 12 of 240 songs | |
| about 4 min left | About 4 minutes left | |
| Build (the button in the file chooser) | Start | |

### The toolbar

| Today | Should be | Why |
|---|---|---|
| New crate from folder | Add music | |
| Open crate | Open crate file | D21 |
| Save | (gone: Desk saves as it goes) | Open: or keep it |
| Make signatures | (gone: part of the one run) | "Signature" is our word |
| Find copies | (gone: part of the one run) | |
| Import log | What didn't go in | Says what it is |
| Show in Finder | Send to iPad | The next thing a DJ wants |

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
