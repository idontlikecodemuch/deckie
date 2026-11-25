# What to test, build 4 (draft)

Thanks for trying Deckie on the iPad. New in this build: Deckie names the next song sooner after a quick change,
it no longer silences other music playing on the iPad, it keeps going through a call or a change of input, and REC
always says what the recording is really doing.
The app's icon is redrawn sharp, with its dark ground to every corner. Please try these and tell us how each went:

1. **The demo crate.** Tap "Try the demo crate", then on a phone or laptop open deckie.io/demo, press play and put it
   near the iPad. How soon does Deckie name each song? When you tap another song on the page, how many seconds until
   Deckie shows it? This build should be about 2 seconds quicker than before at a straight cut from one song to the
   next.
2. **The picks.** With a demo song named, would you play the picks next? Most should be the same key or the next key
   round the wheel; one song (Street of love) is there to show keys that may clash.
3. **Naming the song in a real set.** Play from your own crate in the room. Does Deckie name the right song, and how
   soon? Does it keep up when you mix from one song to the next, both with a quick cut and with a long blend? Does it
   ever show a wrong song, even for a moment?
4. **A DJ app on the same iPad.** If you DJ from an app on this iPad, start it playing, then start listening in
   Deckie. Does your music keep playing at the same volume? (Before this build, Deckie silenced it.)
5. **A call, Siri or an alarm.** While Deckie listens, let a call or an alarm come in, or ask Siri something. Does the
   corner say "interrupted", and does Deckie start listening again by itself afterwards? Is the set's recording one
   file in Files, with the gap noted in its log?
6. **A sound interface.** If you use an audio interface or a mixer's USB sound, plug it in or out while Deckie
   listens. Does it carry on with the new input? With an interface of more than two inputs, Deckie hears and records
   inputs 1 and 2 (where mixers usually send the master): is that what you hear in the recording?
7. **Stop.** Tap Stop in the corner of the Listen screen. Does the microphone turn off, and does it say how much of
   the set was saved? Find the set in Files, On My iPad > Deckie > Sets (named "Deckie set" and the date). Tap Start
   listening: does it pick up again?
8. **REC.** Watch the small REC in the corner: "REC 0:12:34" while it records, "REC paused", "REC waiting" during a
   silence, "not recording" while listening is stopped, "REC off" when set recording is off. Does it always match what
   is happening? Tap REC and untick "Record each set": does it stay off after you close and reopen Deckie?
9. **Locked iPad.** Lock the iPad during a set and unlock it later. Did it keep listening, and is the set's recording
   one complete file in Files under Deckie > Sets?
10. **Getting a crate file in.** Make one with Deckie Desk, send it to the iPad by AirDrop or save it to Files, then
    open it (tap "Open a crate file", or open it from Files). Did it open? How long did it take?
11. **Setting a song by hand.** When the room is too loud, tap a song in the Crate tab. Do the picks follow?

Known in this build:

- The demo crate's seven songs are public-domain dance music, chosen to show the picks working, not as a DJ's crate.
- Interruptions, other music on the iPad, interfaces with many inputs and a locked screen have been tried only in
  Apple's iPad simulator so far, not on a real iPad. Tell us what happens on yours.
- A crate file made on a Windows PC now carries the song fingerprints Deckie listens for, but none has been tried on
  an iPad yet. If Deckie cannot name songs from one, set them by hand in the Crate tab and tell us.
- The look and the words are still being worked on.
