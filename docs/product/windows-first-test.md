# Deckie Desk for Windows, first test

Nov 14, 2026 (the first version of this page, Nov 13, was for the program without a window). The page that goes
with the first Windows program (decisions D29 and D32): what a tester is told. The same words ship in the zip as
`READ ME FIRST.txt` (source: `core/Tools/windows/READ ME FIRST.txt`); change both together. Written to
`docs/product/voice.md`: plain, short, sentence case, "songs", and no words we do not use. What was built and what
is proven is in `docs/research/y-windows-builder.md` and the check-ins
(`docs/research/briefs/checkin-windows-builder.md`).

Words on this page that are ours, said once: a **crate file** is the one file Deckie writes about a DJ's songs
(tempo, bars, key, style, vocals; never the songs). **Deckie Booth** is the iPad app that uses it beside the decks.
**Deckie Desk** is the program that makes the crate file. The **WebView2 Runtime** is a part of Windows, from
Microsoft, that draws a web page inside a program's own window; Deckie Desk's window is drawn by it.

## What this is

Deckie is a DJ booth companion. Deckie Booth, on an iPad, sits beside your decks. To do that it needs a crate
file: everything Deckie knows about your songs, and never the songs themselves.

Deckie Desk is the program that makes the crate file, from the music on your PC.

Your music stays on this PC. No account. No upload. It works with no internet.

## How to start it

1. Unzip the whole Deckie folder first (right-click the zip, "Extract All"). It will not work from inside the zip.
2. Open the new folder and double-click "Deckie Desk".

Deckie Desk opens in a window of its own. Nothing is installed, and it does not ask for an administrator password.
It needs Windows 10 or Windows 11, 64-bit.

## "Windows protected your PC"

The first time you start it, Windows may show a blue box that says "Windows protected your PC". Windows shows this
for any new program it has not seen many times before. This test version is not yet signed with a publisher's
certificate, which is what makes that box go away.

To continue: click "More info", then "Run anyway".

If you would rather not, that is fine. Tell the person who gave you Deckie.

## If it says it needs "WebView2"

Deckie Desk's window is drawn by a free part of Windows from Microsoft, the WebView2 Runtime. Windows 11 has it
built in. On Windows 10 it arrives with Microsoft Edge's updates, and Microsoft says the vast majority of Windows
10 PCs have it. A few do not.

If yours does not, Deckie Desk says so when you start it, and offers to open Microsoft's own page for it,
`https://developer.microsoft.com/microsoft-edge/webview2/consumer/`. Choose "Download WebView2" there, install it,
and start Deckie Desk again. Deckie downloads nothing by itself.

Or use "Make Crate File" instead. It needs nothing else.

## Adding music

1. Click "Add music". Pick a USB stick, an SD card or a CD from the list, or "Choose a folder…" for a folder on
   this PC. You can also drag a folder onto the window.
2. The window shows each song as it is read, and about how long is left. You can keep using the PC. It will be
   busy, and the fan may run.
3. When it finishes, the window says how many songs went in, how many files did not and why, and which songs
   still need a name.

Add more music the same way. Each stick, disc or folder you add keeps its own name, its folders and the order of
its songs, and they all go into one crate. Nothing is written inside your music folders, and no song is changed,
moved or copied.

## Getting the crate file to your iPad

Click "Export crate file…" and choose where it goes. You get one small file named after your crate, such as
`Friday night.deckiecrate` (about 4 KB a song). Any of these work:

- A USB stick or SD card: export the crate file onto it, plug it into the iPad, and open it from the Files app.
- iCloud Drive: with iCloud for Windows, export the crate file into your iCloud Drive folder. It shows in Files on
  the iPad.
- A cable: connect the iPad, open the Apple Devices app, choose the iPad, then Files, and drag the crate file onto
  Deckie Booth.
- Email it to yourself, and open the attachment on the iPad.

Deckie Booth opens the file as it is.

## How long it takes

It reads every song from start to end, so it takes a while the first time. These are estimates, not promises
(`docs/research/p-machine-estimates.md`; none of these machines has been measured):

| PC | A song | 1,000 songs |
|---|---|---|
| A laptop from the last two or three years | about 5 seconds | 1 to 1.5 hours |
| An older laptop with 8 GB of memory | about 15 seconds | about 4 hours |

You can leave it running. If you close the window or the PC turns off, nothing that was read is lost: start Deckie
Desk again and choose "Carry on". Adding the same music again is quick. It only reads songs that are new or
changed.

## What does not work yet

- **Song recognition.** Deckie Booth names the song that is playing by a sound fingerprint of each song, kept in
  the crate file. When this page was written (Nov 14, 2026), Deckie Desk for Windows did not write one yet, so with
  a crate file made on a PC you pick the song in the booth yourself. It is being built. Your version tells you
  which it is: if the line under your songs says some "can't be recognised yet", those have no fingerprint.
- **Key, on some songs.** Deckie reads each song's key itself, and takes a key your files or your DJ program
  already hold. Where Deckie is sure, it shows the key. Where it found the home note but not whether the song is
  major or minor, it shows the home note. Where it is not sure, it shows no key and tells you how many songs that
  is. It does not guess.
- **Looking up names.** A song with no name in its file is listed as needing one. You can type it, paste a list,
  or take names from the file names or a playlist. Nothing is looked up on the internet in this version.
- **This test has not been tried on many PCs yet.** Reading a music CD, and dragging a folder onto the window, are
  the two things least tried.

| | File types |
|---|---|
| Reads | MP3, FLAC, WAV, AIFF, and M4A (AAC and Apple Lossless, such as iTunes purchases) |
| Not yet | WMA, Ogg and Opus |
| Never | copy-protected files (old iTunes Store purchases, Apple Music downloads); only Apple's own apps play those |

A few M4A files do not say exactly where their music starts. Deckie still reads them: their beats may sit a touch
late (up to 0.05 seconds).

Files it cannot read are counted and listed. Nothing is skipped without telling you. Deckie does not mix, and it
does not change your music.

## "Make Crate File", the other way

The same folder holds a second program, "Make Crate File". It has no window of its own: drag your music folder
onto it, and it reads the folder and writes the crate file next to it (`My Music.deckiecrate` for a folder called
"My Music"), with a short log beside it. It needs nothing from Windows but Windows.

Use it if Deckie Desk will not open on your PC, or if you prefer it. It makes a crate file from one folder. Deckie
Desk does more: several sticks and folders in one crate, names, and listening to a song to name it.

## If something goes wrong

Please tell the person who gave you Deckie:

1. What you clicked, and what the window said. A photo or screenshot helps.
2. Which Windows you have (Windows 10 or 11).

If Deckie Desk does not open at all and says nothing, say that too. It is the most useful thing we can learn from
this test.

To remove Deckie: delete its folder. It installed nothing. It keeps your crates, and its notes on what it has
already read, in two folders called "Deckie Desk" and "Deckie" under your Windows account's app data (type
`%LOCALAPPDATA%` into the address bar of a folder window), and the window's own small storage in a folder called
"deckie-desk.exe" under `%APPDATA%`. You can delete those too.

## For whoever hands this to a tester

- The zip is the artifact `Deckie-Desk-for-Windows-first-test` of a run of the workflow `pc-package` on the branch
  `pc/package-desk`. It is not a release. The check-in names the run, the zip's size and its SHA-256; when this
  page was written that was run 43581053583, 128,981,732 bytes.
- **What is proven, and where.** On GitHub's Windows machine (Windows Server, not a DJ's Windows 10 or 11), from
  the unzipped folder with nothing on the path but Windows: Deckie Desk starts, its window is made, the page shows
  the engine's words, a small generated music folder is added through the page, the run finishes, and the exported
  crate file is one file that the core's validator reads. No person has seen the window: the machine has no
  screen.
- **Not proven anywhere yet**, each to be tried on a real PC in the order the check-in gives: the blue box and
  "Run anyway"; antivirus; a real double click and that no console window shows; the icon in Explorer and on the
  taskbar; a PC without the WebView2 Runtime (the message box and Microsoft's page); an account without
  administrator rights; Windows 10; dragging a folder onto the window; a music CD; the times in the table.
- **The two "not yet" points are true of `main` on Nov 14, 2026.** Recognition: a PC-made crate file carries no
  fingerprint, and Deckie's own fingerprint (D35) was being put into the crate file by another session when this
  was written; the page is worded so that it stays true when that lands (the window itself says which songs
  cannot be recognised). Key: Deckie's own reader gives a key, a home note or "not sure" on every computer (D33,
  D36), so the earlier page's "no key yet" no longer holds.
- **The iPad.** Deckie Booth opens both forms of a crate file, the Mac's package and the one file a PC writes
  (`docs/architecture/crate-format.md`, "The single-file form"). Opening one exported by Deckie Desk for Windows on
  a real iPad has not been tried in this work.
