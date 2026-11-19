# Notes for testers (draft)

## What you need

- An iPad with iPadOS 17 or later, and the TestFlight app.
- Deckie Desk on your computer, from deckie.io: for Mac, or for Windows PC.
- Some of your own music on that computer.

## Make a crate file and get it onto the iPad

1. Open Deckie Desk and add a folder of your music. Desk reads it and writes a crate file: what it learns about
   your songs, never the songs themselves. It ends in `.deckie`.
2. Send the crate file to the iPad:
   - **AirDrop** (Mac): Desk sends the crate file through the share sheet; choose AirDrop, then your iPad. On the
     iPad, choose Deckie Booth if asked.
   - **Files**: save the crate file to iCloud Drive, or copy it to the iPad with a cable (Finder on a Mac, or the
     Apple Devices app on Windows, into Deckie Booth's files). Then in Booth tap "Open a crate file" and pick it.
3. Booth opens it and says how many songs it holds. Allow the microphone when asked.

You only do this once per crate file. Booth remembers the last one you opened.

## Your set recordings

Booth records each set from its microphone while it listens. The recordings stay on the iPad: open the Files app,
then On My iPad > Deckie Booth > Sets. Each set has its recording (`.aac`), a list of the songs Booth named, and a
log. Tap REC on the Listen screen to pause or resume recording.

## Deckie Desk on a Windows PC

Desk for Windows is not signed yet, so Windows is careful with it the first time:

- The first launch can take a while with nothing on screen. Wait for it; it is only slow the first time.
- Windows may show a blue box, "Windows protected your PC". Click **More info**, then **Run anyway**.

A crate file made on a PC has no song fingerprints yet, so Booth cannot name songs from it. Set the song playing by
hand: tap it in the Crate tab.

## Your privacy

Booth hears the room on the iPad and nothing leaves it. No account, no upload. Desk reads your music on your computer
and keeps it there.

## Telling us what you found

Use TestFlight's Send Beta Feedback (take a screenshot in Booth and share it), or reply to your invitation.
Most useful: what Booth named wrong or late, and which picks you would or would not play.
