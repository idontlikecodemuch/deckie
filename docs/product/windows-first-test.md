# Deckie for PC, first test

Nov 13, 2026. The page that goes with the first Windows program (decision D29): what a tester is told. The same
words ship in the zip as `READ ME FIRST.txt` (source: `core/Tools/windows/READ ME FIRST.txt`); change both
together. Written to `docs/product/voice.md`: plain, short, sentence case, "songs", and no words we do not use.
What was built and what is proven is in `docs/research/y-windows-builder.md`.

Words on this page that are ours, said once: a **crate file** is the one file Deckie writes about a DJ's songs
(tempo, bars, style, vocals; never the songs). **Deckie Booth** is the iPad app that uses it beside the decks.

## What this is

Deckie is a DJ booth companion. Deckie Booth, on an iPad, sits beside your decks. To do that it needs a crate
file: everything Deckie knows about your songs, and never the songs themselves.

This program makes that crate file from a folder of music on your PC.

Your music stays on this PC. No account. No upload. It works with no internet.

## How to use it

1. Unzip the whole Deckie folder first (right-click the zip, "Extract All"). It will not work from inside the zip.
2. Drag your music folder onto "Make Crate File". Or double-click "Make Crate File" and it will ask for the folder.
3. A window opens and shows each song as it is read, and about how long is left. You can keep using the PC. It
   will be busy, and the fan may run.
4. When it finishes, the window says how many songs went in, how many did not and why, and where the crate file
   is. Press Enter to close it.

The crate file appears next to your music folder, with the folder's name. For a folder called "My Music" you get
`My Music.deckiecrate`, the crate file, and `My Music Deckie log.txt`, a short log of the run. Nothing is written
inside your music folder, and no song is changed.

## "Windows protected your PC"

The first time you start it, Windows may show a blue box that says "Windows protected your PC". Windows shows this
for any new program it has not seen many times before. This test version is not yet signed with a publisher's
certificate, which is what makes that box go away.

To continue: click "More info", then "Run anyway".

If you would rather not, that is fine. Tell the person who gave you Deckie.

## How long it takes

It reads every song from start to end, so it takes a while the first time. These are estimates, not promises
(`docs/research/p-machine-estimates.md`; none of these machines has been measured):

| PC | A song | 1,000 songs |
|---|---|---|
| A laptop from the last two or three years | about 5 seconds | 1 to 1.5 hours |
| An older laptop with 8 GB of memory | about 15 seconds | about 4 hours |

You can leave it running. If you close the window or the PC turns off, nothing is lost: start it again with the
same folder and it carries on where it stopped. The second time is quick. It only reads songs that are new or
changed.

## What it does not do yet

A crate file made on a PC is not complete yet. Two things are missing:

- **Song recognition.** Deckie Booth will not yet name the song that is playing from a crate file made on a PC.
  You pick the song yourself.
- **Key.** A crate file made on a PC has no key yet, unless your files already carry one.

Both are being worked on. Tempo, bars, style and vocals are all there.

| | File types |
|---|---|
| Reads | MP3, FLAC, WAV, AIFF |
| Not yet | M4A and AAC (iTunes purchases, Apple Lossless), WMA, Ogg and Opus |
| Never | copy-protected files (old iTunes Store purchases, Apple Music downloads); only Apple's own apps play those |

Files it cannot read are counted and listed at the end. Nothing is skipped without telling you.

It does not read audio CDs. It does not mix, and it does not change, move or copy your music.

## Getting the crate file to your iPad

The crate file is one small file (about 4 KB a song). Any of these work:

- Email it to yourself, and open the attachment on the iPad.
- Put it in iCloud Drive, OneDrive, Google Drive or Dropbox on the PC, and open it from the Files app on the iPad.
- Plug the iPad into the PC with its cable, open iTunes or the Apple Devices app, and drop it into Deckie Booth's
  files.

Opening a PC-made crate file needs a version of Deckie Booth that knows this one-file form. The person who gave
you this will tell you when yours does.

## If something goes wrong

Please send two things to the person who gave you Deckie:

1. The log file next to your music folder ("... Deckie log.txt").
2. A photo or screenshot of the window, if it shows a message.

What is in the log: the version of the program, what kind of PC this is (Windows version, processor count,
memory), how many songs were found and how long they took, and the files that could not be added, each with its
name and the reason. That is all. No song audio, nothing about the songs that went in, and not the name of your
Windows account.

To remove Deckie: delete its folder. It installed nothing. It keeps its notes on what it has already read in a
folder called "Deckie" under your Windows account's local app data, which you can delete too.

## For whoever hands this to a tester

- The zip is the artifact `Deckie-for-PC-first-test` of a run of the workflow `pc-package`. It is not a release.
- Two things on this page are not proven on a real PC, only on GitHub's Windows machine: that the blue box
  appears and "Run anyway" is enough; and the times. The letter says which claims are which.
- The iPad cannot open the one-file form until Deckie Booth is built against the current core and its document
  type takes a plain file (`docs/architecture/crate-format.md`, "The single-file form"). Until then the tester can
  make the crate file and send the log, which is what this first test is for.
