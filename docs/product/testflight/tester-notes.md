# Notes for testers (draft)

## What you need

- An iPad with iPadOS 17 or later, and the TestFlight app.
- Deckie Desk on your computer, from deckie.io: for Mac, or for Windows PC.
- Some of your own music on that computer.

## Try the demo crate first

You can see Deckie work before making a crate file of your own, with no music of your own.

1. Open Deckie and tap **Try the demo crate**. Allow the microphone when asked.
2. On a phone or a laptop, open **deckie.io/demo** and press play. Put that device near the iPad, with the volume up.
3. Within a few seconds Deckie names the song playing and shows what could come next. The page plays seven songs, one
   after another; Deckie follows each change.
4. When you are done, tap **Leave the demo crate** (on the Listen screen while it waits for a song, or in the Crate tab) to
   go back to the first screen and open your own crate file.

The demo crate's songs are dance music their artists have put in the public domain (CC0); the page and Deckie's Credits list
them.

## Make a crate file and get it onto the iPad

1. Open Deckie Desk and add a folder of your music. Desk reads it and writes a crate file: what it learns about
   your songs, never the songs themselves. It ends in `.deckie`.
2. Send the crate file to the iPad:
   - **AirDrop** (Mac): Desk sends the crate file through the share sheet; choose AirDrop, then your iPad. On the
     iPad, choose Deckie if asked.
   - **Files**: save the crate file to iCloud Drive, or copy it to the iPad with a cable (Finder on a Mac, or the
     Apple Devices app on Windows, into Deckie's files). Then in Deckie tap "Open a crate file" and pick it.
3. Deckie opens it and says how many songs it holds. Allow the microphone when asked.

You only do this once per crate file. Deckie remembers the last one you opened.

## Your set recordings

Deckie records each set from its microphone while it listens. The recordings stay on the iPad: open the Files app,
then On My iPad > Deckie > Sets. Each set has its recording (`.aac`), a list of the songs Deckie named, and a
log.

The small **REC** in the top corner of the Listen screen says what recording is doing: "REC 0:12:34" while it records,
"REC paused", or "REC off". Tap it for its menu:

- **Pause recording, keep listening** or **Resume recording**, for this set.
- **Record each set**, ticked when on. Untick it and Deckie stops recording, until you tick it again; it remembers
  your choice the next time you open it. Deckie still names songs with recording off.

## Stopping

When the set is over, tap **Stop** in the top corner of the Listen screen. Deckie turns the microphone off and saves
the set's recording in Files. The last song stays on screen with its picks. Tap **Start listening** to listen again;
a new set recording starts with it.

## Deckie Desk on a Windows PC

Desk for Windows is not signed yet, so Windows is careful with it the first time:

- The first launch can take a while with nothing on screen. Wait for it; it is only slow the first time.
- Windows may show a blue box, "Windows protected your PC". Click **More info**, then **Run anyway**.

A crate file made on a PC has no song fingerprints yet, so Deckie cannot name songs from it. Set the song playing by
hand: tap it in the Crate tab.

## Your privacy

Deckie hears the room on the iPad and nothing leaves it. No account, no upload. Desk reads your music on your computer
and keeps it there.

## Telling us what you found

Use TestFlight's Send Beta Feedback (take a screenshot in Deckie and share it), or reply to your invitation.
Most useful: what Deckie named wrong or late, and which picks you would or would not play.
