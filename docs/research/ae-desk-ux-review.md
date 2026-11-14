# Research AE: a usability review of Deckie Desk

Dated Nov 14, 2026. A review and research letter: no code changed, no commit. It answers three findings from the
first real use of Desk on the owner's own music the same day, walks the whole flow as a first-time and a returning
DJ, and ranks what else gets in the way. It builds on `docs/product/desk.md` (partly out of date: the one run, the
finished screen, several crates and Send to iPad are now built), `voice.md`, and decisions D21, D25, D26, D28, D30,
D31, D36 and D39.

**How it was done.** The Mac app's code (`desk-app/Desk/Sources/`), the shared word list
(`core/Sources/DeckieDesk/DeskWords.swift`), the drive listing for every system (`DeskDrives.swift`) and the
Windows and Linux pages (`desk-web/`) were read. The built app was run once in its scripted window mode on four
generated 40-second songs in a scratch storage folder (`DECKIE_DESK_HOME`); it read them in 11 seconds, and every
step of the check passed. The Mac was locked, so the app could only save pictures of the window's frame with the
toolbar items blank (`.scratch/ux-review/shots/check1/`); what the toolbar shows is therefore read from the code and
from earlier frames in `.scratch/desk-window/` and `.scratch/naming/`, and is marked [code] below. No DJ's music
was used.

**Tags.** [read] = I opened the page today; [snip] = seen only through a search summary; [code] = read in Desk's
code; [ran] = seen in the run above; [inf] = my inference, with the reasoning. Sources are numbered S1, S2 and so on
at the end.

**Words used.** A **heuristic** is a rule of thumb for judging a screen; this review uses Nielsen's ten (S1), cited
as H1 to H10: H1 visibility of system status, H2 match with the real world, H3 user control and freedom, H4
consistency and standards, H5 error prevention, H6 recognition rather than recall, H7 flexibility and efficiency, H8
minimal design, H9 help with errors, H10 help and documentation. **Severity** runs 1 to 4: 1 cosmetic, 2 minor
(slows a DJ down), 3 major (a DJ gets stuck or makes a mistake that costs time), 4 serious (costs hours, or a DJ
gives up). A **toolbar** is the row of buttons along the top of the window; a **sheet** is a panel that slides down
over the window and must be answered before going on. All words proposed for the screen are placeholders until the
copy audit (D28, D36).

---

## 1. The flow, step by step

### A first-time DJ

| Step | What the DJ sees | What they expect | Where it goes wrong |
|---|---|---|---|
| Open Desk | A box icon, "Your crate starts here.", one line of explanation, three buttons: "Add music", "With a rekordbox collection…", "Import crate file…". Top left, a menu labelled "New crate". [code] | One obvious first move | Mostly right. "New crate" at top left reads like a button, but it is the crate menu. The rekordbox route is a minority path given first-screen weight (desk.md already leaves it open). |
| Add music | A drop-down menu: each music CD, then every mounted CD, stick, card or external drive by its bare name, then "Choose a folder…". [code] | "Pick where my music is" | A stick, a 2 TB backup drive and a data CD look the same: a name, no icon, no size. Choosing any of them **starts reading at once**, with no count and no question (finding 3). |
| Choose a folder | The system's folder chooser, "Choose the folder your music is in. It becomes a source, named after the folder." Button "Add". [code] | Same | Good wording. Nothing stops choosing the top of a large drive or the home folder. |
| The run | "Reading your crate", "Adding Gig Friday to Gig Friday", a bar, songs done of songs found, time left, a quiet line, waves. [ran, code] | To see progress and to be able to stop | **No Stop button.** The only way out is to quit Desk ("If Desk is closed, you can carry on from here next time"). While Desk lists the files before reading, it shows only a spinner with no count. |
| Finished | "Gig Friday is in Gig Friday", counts, keys, names, time taken; "Next, send the crate file to your iPad."; buttons Send to iPad, What didn't go in, See the songs. [ran] | "Done. Now what? Can I add the other stick?" | **No way to add more from here** (finding 1). The title repeats one name twice because the crate was silently named after the folder (finding 2). |
| The crate | A table of songs, a names panel on the right, a status line. Toolbar: crate menu, then icons. [code] | A clear "add more" | The Add music button is in the toolbar as an **icon only**: a drive with a plus. The Sources button beside it is also a drive icon. [code; inf, below] |
| Send to iPad | The Mac's share sheet. [code] | AirDrop, then the booth opens it | Works. Nothing on the Mac says how to open it on the iPad, or what to do without AirDrop (the Windows pages do say). |

### A returning DJ

Desk opens on the most recent crate (D28). To add tonight's new stick they need the toolbar icon, the File menu
("Add music to Gig Friday"), or the Sources panel's button, which shows only when the crate has no sources. To make
a second crate they open the crate menu, choose "New crate", land back on the first screen with no name asked, and
the crate is named after whatever they add first. Renaming is in the same menu, in a dialog with "OK". Taking a
wrong source back out is in the Sources panel after selecting the source.

### Why "Add music" was not found (finding 1)

[code] The toolbar's Add music is a SwiftUI menu with a label "Add music to {crate}" and the symbol
`externaldrive.badge.plus`. Toolbar labels on the Mac show as icons only unless the item asks for its title
(the crate menu does, with `.labelStyle(.titleAndIcon)`; Add music does not). So the words "Add music to Gig Friday"
appear only as a tooltip. [inf] The icon says "add a drive" more than "add music", sits next to Sources' plain drive
icon, and the frame captured today shows three icon-sized pills at the right of the toolbar and nothing readable.
Apple's own guidance prefers symbols in toolbars but also says to make every toolbar item a menu-bar command,
because a toolbar "can't be the only place" for a command (S2, [read]); Desk does have it in the File menu, which a
first-time DJ rarely opens. The finished screen, where the DJ is when they think of the next stick, has no add button
at all. The Windows and Linux pages show the same menu with its words, "Add music to Gig Friday ▾", so this is a
Mac problem plus a finished-screen problem.

---

## 2. What other software does

**DJ programs.** rekordbox adds music by dragging files or folders from Finder or Explorer into the collection,
which starts analysis; older manuals also have File > Import > Folder (S3, [snip]). Serato DJ Pro does the same: drop
files or folders onto the All crate or the Files panel; it reads music where it lives and does not copy it (S4,
[snip]). Engine DJ: drag from Finder or Explorer into the collection; each drive has its own collection (S5, [snip]).
Mixed In Key: drop files or folders anywhere on the window to queue them (S6, [snip]). MusicBrainz Picard has two
separate buttons, Add Files and Add Folder (S7, [snip]). **None of them asks "which device"**: they take whatever
is dropped, and none offers a whole drive by name. Drag and drop is the common route, and Desk on the Mac does not
take a drop (the Windows pages do). [code]

**Photo importers: device versus folder.** Image Capture lists connected devices in a sidebar under "Devices";
selecting one shows its items before anything is copied, then "Download" or "Download All" (S8, [snip]).
Lightroom Classic's import has a Source panel with devices and, separately, Files; it treats a card as a device
only when it thinks it is removable, and offers "Eject after import" only then. Users report cards that the system
calls an external drive appearing only under Files (S9, [snip]). [inf] Two lessons: show what was found before
committing, and the "is it removable?" signal is wrong often enough that a design must not depend on it.

**Music CDs.** Apple Music lets a person choose what happens when a CD goes in, including "Ask to Import CD" (S10,
[snip]). Desk already asks the disc's name in passing while it reads, without making the run wait: a good pattern
to copy for the crate's name.

**Platform guidance.** Apple: onboarding should let people "start using your app … immediately", and "postpone
nonessential setup … provide reasonable default settings" (S11, [read]). Use a determinate progress bar and "if
people can interrupt a process without causing negative side effects, include a Cancel button" (S12, [read]). Alerts:
"avoid displaying alerts for common, undoable actions", and button titles should "describe the result" rather
than say OK (S13, [read]). A new document is "Untitled" until named (S14, [read]). Microsoft's confirmation guidance
(written for Windows 7, still sound): a confirmation is worth it only when there is a real reason not to go on and
the DJ sometimes will not; give the information needed to answer; prefer undo and prevention where they can replace
the question (S15, [read]). Nielsen Norman Group: undo is the stronger safety net, confirmations for serious and
costly actions only (S16, [snip]).

**Guarding against choosing a 2 TB drive**, from the above: (1) **look first, then ask**: list the files (fast:
no audio is decoded) and show the count of songs, the hours of music and a time estimate before reading anything,
only when the run is big; (2) **let it stop**: a Stop that keeps what was read; (3) **let it be undone**: "Take
this back out" for a run that should not have happened. Desk has (3) in the Sources panel and none of (1) or (2).

---

## 3. The three findings

### Finding 1: "a way to go back and add more songs to the crate"

**Option A: say it in words, where the DJ is.** The toolbar button shows its words: "+ Add music" (icon and title,
as the crate menu already does). The finished screen gets a second row of actions: **Send to iPad** (main) and
**Add more music**, which opens the same choices as the first screen. The bottom of the song table gets a quiet line
"Add more music to Gig Friday" that does the same. The File menu keeps "Add music to Gig Friday", with a shortcut
(Command-Shift-A).
*Size: small.*

**Option B: a sources sidebar.** A narrow column on the left, always shown, listing the crate's sources by their
own names with song counts, and "+ Add music" at its foot, the way Image Capture lists devices and the Music app
lists playlists. The present Sources panel's corrections move into it.
*Size: medium; it is a layout change for the design pass.*

**Option C: drop to add.** The window takes a folder, a drive or files dropped on it, as every DJ program does, with
a line in the status bar "Drop a folder here to add it".
*Size: medium on the Mac; the Windows pages already do it.*

**Recommendation: A now, C next, B with the design pass.** A is a few lines and answers the finding directly; C
matches what DJs already do in rekordbox and Serato; B is the long-term home for "what is in this crate".

### Finding 2: the crate was named after the folder

What happens now [code]: "New crate" makes no crate; the crate is made when music is first added, named after that
source. Adding more sources later keeps the first source's name, so a crate called "Friday stick" can hold three
sticks and a folder, and the finished title reads "Friday stick is in Friday stick".

**Option A: name it on the adding step.** When Add music makes a new crate, the review step (finding 3, option B)
shows "Into a new crate called [ My crate ]" with the field selected, so typing replaces it. When a crate already
exists, the line reads "Into [ Gig Friday ▾ ]", a menu of crates with "New crate…" at the end (this is the
owner's own suggestion in D28). The run's title then reads "Adding Friday stick to Gig Friday".

**Option B: name it when it is made.** "New crate" asks at once, "Name this crate", placeholder "Friday gig", and
a first crate made from the first screen is called "My crate" without asking.

**Option C: neutral default, rename in place.** Never use the source's name. The first crate is "My crate", later
ones "Crate 2", "Crate 3"; clicking the crate's name at top left (or on the finished screen) edits it in place, like
renaming a playlist in the Music app. Apple's "Untitled" pattern (S14).

| | When the name is chosen | Default | Renaming later |
|---|---|---|---|
| A | At the moment of adding, with the source in front of them | "My crate", editable | Crate menu, and the name at top left |
| B | Before any music, with nothing in front of them | "My crate" for the first | Same |
| C | Whenever they like | "My crate", "Crate 2" | Click the name |

**Recommendation: A, with C's neutral default and click-to-rename.** A asks once, at a moment that already has a
step, and never blocks; the default "My crate" fits the many DJs whose crate is their whole library (D21), and the
source keeps its own name in the Sources panel (D26), so a crate and a source no longer share one. Also: the rename
dialog's button should say "Rename", not "OK" (S13).

### Finding 3: "add disk", "add drive", "add folder"

**What Desk does now** [code]: Mac lists every mounted volume that is removable, ejectable or not internal: sticks,
cards, data CDs **and external hard drives and SSDs**, by name only. Windows lists only drives Windows calls
removable, plus CD drives with a disc; a USB hard drive that Windows calls fixed is not listed and has to be chosen
as a folder. So the two systems already disagree about big drives.

**Option A: three entries, each with its own icon.** The first screen's one button becomes three equal buttons, and
the toolbar's Add music menu gets three sections:
- **A CD** (disc icon): each disc in the drive. "Music CD, 14 songs, 71 min" or, for a data CD, its name and "CD".
  None in: "Put a CD in."
- **A USB stick or card** (stick icon): each small removable drive, by name, with its size: "Friday stick · 16 GB".
  None: "Plug in a stick or card."
- **A folder** (folder icon): "Choose a folder…", opening the system's chooser. Big drives are reached only here.

**Option B: one button, then a "Where is your music?" sheet.** Add music opens a sheet with three large tiles, the
same three as A, each listing below it what is plugged in now, and greyed with a plain line when there is none. The
review step (below) is the same sheet's second page.

**Option C: keep one menu, but sorted, labelled and guarded.** One Add music menu as now, with section headings
and icons, sizes beside each drive; a big drive opens the folder chooser on that drive instead of reading it.

**What happens when a big or internal drive is chosen** (any option). Desk never reads the Mac's or PC's own disk
as a whole. A big drive in the list, or the top of one chosen in the folder chooser, opens the chooser at that
drive with "This drive is big. Choose the folder your music is in." If the DJ chooses the top anyway, Desk **looks
first**: it lists the music files without reading them (a spinner with a rising count: "Looking… 4,812 songs so
far"), then asks:

> **Read 4,812 songs from Big Drive?**
> That's about 310 hours of music. Reading them takes about 9 hours on this Mac. You can stop at any time, and
> songs already read stay in your crate.
> [Choose a folder instead] [Cancel] [Read 4,812 songs]

The numbers are illustrative. The estimate is the song count times the rate Desk already measures on each computer
("songs a minute" on the finished screen), less the songs it has read before (D28: those are quick). The question
appears only above a threshold (placeholders: more than 1,000 songs or more than an hour of reading), so a stick
never sees it (S15: confirm only when the DJ might say no). The run screen gets a **Stop** button ("Stop reading.
Songs already read stay in your crate."), and the finished screen of a run gets "Take this back out", the existing
remove-source action, undoable (S12, S16).

**Telling a stick from a big drive.**

| Signal | Mac | Windows | How reliable |
|---|---|---|---|
| Size | `volumeTotalCapacity` | `GetDiskFreeSpaceEx` | **Reliable.** The best single signal. Sticks and cards are mostly 8 to 256 GB; DJ backup drives 500 GB and up. A 512 GB stick or a 256 GB SSD sits on the line. [inf] |
| Removable flag | `volumeIsRemovable`, or Disk Arbitration's media-removable key | `GetDriveType` = `DRIVE_REMOVABLE` | **Unreliable.** On Mac it describes the media, not the device; one report has a stick and a 1 TB disk disagreeing (S17, [snip]). On Windows it comes from a bit the device's firmware sets; Microsoft's own page lists a "flash drive" under fixed (S18, [read]); some sticks shipped as fixed (S19, [snip]). |
| Bus | Disk Arbitration's device protocol ("USB", "Thunderbolt") (S17, [snip]) | Storage bus type, or the removal policy Microsoft points to (S18, [read]) | **Partly.** Tells external from internal well; does not tell a USB stick from a USB SSD. Thunderbolt means a big drive. |
| Format | `volumeLocalizedFormatDescription` | Volume file system | **A hint.** Sticks and cards are usually FAT32 or exFAT (what CDJs read); Mac backup drives are usually APFS or Mac OS Extended. [inf] |
| Internal | `volumeIsInternal`, root file system | System drive letter | **Reliable.** Never offer these as a source. |

**Rule proposed:** internal or the system disk: never listed. External and at most 256 GB (a variable): "stick or
card". External and larger: "drive", folder chooser first. No signal decides alone what is read: the
look-first question catches a stick that is really big, and a drive that is really a stick only costs one extra
choice. The same rule on both systems also mends the Mac and Windows difference.

**Recommendation: B on the first screen, C in the toolbar and File menu.** B teaches the three kinds of source once,
in the DJ's first minute, with icons that match the owner's "add disk, add drive, add folder"; C keeps a returning
DJ to one click. Both share the guard: big drives go through a folder, anything big is counted and asked about first,
every run can be stopped and taken back out. Option A is the cheap version of B if the sheet waits for the design
pass.

---

## 4. Everything else, ranked

| # | Problem | Where | Heuristic | Sev. | Proposed fix | Size |
|---|---|---|---|---|---|---|
| 1 | No way to stop a run except quitting Desk | Run screen (Mac and Windows) | H3 | 4 | Stop button; songs read are kept; "Carry on" already exists | Small to medium |
| 2 | A whole drive starts reading at once, with no count or time | Add music | H5, H1 | 4 | Look first, ask above a threshold (finding 3) | Medium |
| 3 | Add music is an unlabelled drive icon in the toolbar, next to Sources' drive icon | Toolbar (Mac) | H6, H4 | 3 | Show its words; give Sources a list icon | Small |
| 4 | No "add more" on the finished screen | Finished screen | H3, H7 | 3 | "Add more music" beside Send to iPad | Small |
| 5 | Crate silently named after its first source; "X is in X" | Run, finished, crate menu | H2, H1 | 3 | Finding 2 | Small to medium |
| 6 | Sticks, data CDs and big drives look the same in the list: name only | Add music menu | H6, H2 | 3 | Icons, kinds and sizes (finding 3) | Medium |
| 7 | Mac lists external hard drives; Windows hides them | Drive list | H4 | 2 | One size-based rule in `DeskDrives` | Small |
| 8 | The Mac window takes no drop; every DJ program adds by dragging | Crate and first screen (Mac) | H7, H4 | 2 | Accept folders, drives and files; queue them | Medium |
| 9 | While Desk lists the files, only a spinner, no count | Run screen | H1 | 2 | "Looking for songs… 1,204 so far" | Small |
| 10 | Can't add a second stick while one is reading; buttons greyed | Toolbar during a run | H7 | 2 | Queue: "Next: Stick 4", as the Windows pages do for drops | Medium |
| 11 | "Name songs" and the MusicBrainz lookup sit behind an unlabelled text-cursor icon | Toolbar (Mac) | H6 | 2 | Label it; also a link from "N songs still need a name" (already partly there) | Small |
| 12 | "N can't be recognised yet" says nothing about why or what to do | Status line | H9 | 2 | Make it a link: which songs, why (file moved, read before fingerprints), "Read again" | Small |
| 13 | Taking a wrong source back out is hidden in the Sources panel | Sources panel | H3 | 2 | "Take this back out" on the finished screen, undoable | Small |
| 14 | "New crate" with no name lands back on the first screen, and the crate menu's label then says "New crate" | Crate menu | H2, H4 | 2 | Finding 2; label "No crate yet" or the new name | Small |
| 15 | No help after Send to iPad: how to open it in the booth, what to do without AirDrop | Finished screen, Send (Mac) | H10 | 2 | The Windows pages' "To get it to your iPad" box, adapted | Small |
| 16 | The rekordbox route is two file choosers in a row, given first-screen weight | First screen | H8, H2 | 2 | Move to the File menu (desk.md's open item); one sheet explaining both steps | Small |
| 17 | Our words leak: "recognition signatures" (Where is this music?), "Signatures", "Engine", "LUFS" in the names panel | Crate, inspector | H2 | 1 | Copy audit; fold engineering rows away | Small |
| 18 | Rename dialogs say "OK" | Crate menu, Sources | H4 | 1 | "Rename" | Small |

---

## 5. Proposed order of work: a DJ's first ten minutes

**First batch: being able to find things and get out** (all small; one agent, one day) [inf]
1. Add music shows its words in the toolbar; Sources gets a different icon; Name songs is labelled (problems 3, 11).
2. "Add more music" and "Take this back out" on the finished screen (4, 13).
3. A Stop button on the run screen, keeping what was read (1).
4. A count while Desk looks for songs (9).
5. Rename buttons say "Rename"; the crate menu never says "New crate" as a name (14, 18).

**Second batch: the costly mistake and the name** (medium)
6. The look-first question with count, hours and time, above a threshold (2).
7. The size-based drive rule shared by Mac and Windows; big drives go through a folder (6, 7).
8. Naming on the adding step, "My crate" by default, click to rename (5, finding 2).

**Third batch: the shape of the window** (medium, with the design pass)
9. The "Where is your music?" sheet with three tiles (finding 3, option B).
10. Drop to add on the Mac, and a queue for a second stick (8, 10).
11. A sources sidebar (finding 1, option B), and help after Send to iPad (15).

Still to learn: how long a real first run takes on an ordinary DJ laptop, which sets the look-first threshold, and
whether DJs say "stick", "USB" or "drive" out loud (D26 already asks the second about "source").

---

## Sources

- S1 Nielsen Norman Group, "10 Usability Heuristics for User Interface Design". https://www.nngroup.com/articles/ten-usability-heuristics/ [read]
- S2 Apple Human Interface Guidelines, Toolbars. https://developer.apple.com/design/human-interface-guidelines/toolbars [read, through the page's data file]
- S3 rekordbox manuals on adding music to Collection. https://manualslib.fr/manual/49852/Pioneer-Dj-Ddj-Rr.html?page=14 ; https://docs.pioneerdj.com/manuals/DDJ_FLX2_DRI1917A_manual/?Page=78 [snip]
- S4 Serato support, Library and Files panel. https://support.serato.com/hc/en-us/articles/360001447735-Library-Files-Panel ; https://support.serato.com/hc/en-us/articles/223446528 [snip]
- S5 Engine DJ, "Adding music and exporting to a drive". https://enginedj.com/kb/solutions/69000844056/engine-dj-adding-music-and-exporting-to-a-drive [snip]
- S6 Mixed In Key workflows. https://mixedinkey.com/workflows/analyze-your-music-library/ ; https://www.148apps.com/app/954885838/ [snip]
- S7 MusicBrainz Picard, Quick Start. https://picard.musicbrainz.org/quick-start [snip]
- S8 Apple, Image Capture User Guide, transfer images. https://support.apple.com/en-us/guide/image-capture/imgcp1003/8.0/mac/13.0 [snip]
- S9 Adobe, Lightroom Classic import help, and a bug report on removable devices. https://helpx.adobe.com/lightroom-classic/help/importing-photos-lightroom-basic-workflow.html ; https://community.adobe.com/t5/lightroom-classic-bugs/import-sometimes-fails-to-eject-drives-it-considers-removable-mac-only/idi-p/13772345 [snip; the help page refused a direct read]
- S10 Apple, Music User Guide, importing from CDs. https://support.apple.com/guide/music/mus2935/mac [snip]
- S11 Apple Human Interface Guidelines, Onboarding. https://developer.apple.com/design/human-interface-guidelines/onboarding [read]
- S12 Apple Human Interface Guidelines, Progress indicators. https://developer.apple.com/design/human-interface-guidelines/progress-indicators [read]
- S13 Apple Human Interface Guidelines, Alerts. https://developer.apple.com/design/human-interface-guidelines/alerts [read]
- S14 Apple Human Interface Guidelines, File management. https://developer.apple.com/design/human-interface-guidelines/file-management [read]
- S15 Microsoft, Windows desktop guidelines, Confirmations. https://learn.microsoft.com/en-us/windows/win32/uxguide/mess-confirm [read]
- S16 Nielsen Norman Group, "Confirmation Dialogs Can Prevent User Errors" and "Preventing User Errors". https://www.nngroup.com/articles/confirmation-dialog/ ; https://www.nngroup.com/articles/user-mistakes/ [snip]
- S17 Apple Disk Arbitration guide; Apple Developer Forums on volume type; JUCE forum report on removable USB drives. https://developer.apple.com/library/mac/documentation/DriversKernelHardware/Conceptual/DiskArbitrationProgGuide/ArbitrationBasics/ArbitrationBasics.html ; https://developer.apple.com/forums/thread/122391 ; https://forum.juce.com/t/br-isonremovabledrive-inconsistent-for-usb-storage-devices/45776 [snip]
- S18 Microsoft, GetDriveTypeW. https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getdrivetypew [read]
- S19 SanDisk forums, drives configured as fixed disks. https://forums.sandisk.com/t/which-sandisk-usb-flash-drives-are-a-fixed-disk-and-which-are-seen-as-removable-drives/32991 [snip]
