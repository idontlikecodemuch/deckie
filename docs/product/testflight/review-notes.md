# Review notes for Beta App Review (draft)

Deckie Booth is a companion for DJs. It sits beside the decks, recognises which of the DJ's own songs is playing,
and suggests what could come next and how to mix it in.

**Why it uses the microphone.** Booth listens to the music in the room to recognise the song playing. It matches
what it hears against fingerprints in the DJ's own crate file (made on their computer by Deckie Desk), entirely on
the iPad. No sound, fingerprint or result is sent anywhere; Booth makes no network requests. The same microphone
input is saved as a recording of the DJ's set, on the iPad only, in the app's Documents folder (Files > On My iPad >
Deckie Booth > Sets), so the DJ can keep their set.

**Why it keeps running in the background (UIBackgroundModes: audio).** A DJ often lets the iPad lock during a set.
Background audio lets Booth keep listening and keep recording the set while the screen is locked, so the set's
recording has no gap and the song on screen is current when the DJ looks again. Booth plays no sound of its own.
The microphone indicator shows whenever it is listening, and the DJ can pause listening with the microphone button.

**Data.** Nothing leaves the device. There is no account and no sign-in, no analytics, no advertising and no
tracking. The privacy manifest declares no collected data.

**How to see it work.**

1. Open Booth. With no crate file open it shows a first screen explaining what it needs.
2. Tap "Open a crate file" and choose the sample crate file [LINK OR ATTACHMENT TO BE ADDED: a crate file made
   from music we own the rights to, saved to Files before review], or AirDrop it to the iPad and open it in Deckie
   Booth.
3. Allow the microphone. Play [THE SAMPLE'S MATCHING AUDIO, LINK TO BE ADDED] from another device near the iPad.
   Within about 10 seconds Booth names the song and shows picks for the next one.
4. Without playing anything: in the Crate tab, tap any song to set it as playing by hand. The Listen tab then shows
   the song and its picks.

Contact for questions: [NAME, PHONE AND EMAIL GO IN THE FORM'S CONTACT FIELDS, NOT HERE]. Publisher: App Hold Media.
