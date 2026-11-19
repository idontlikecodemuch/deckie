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

**How to see it work (no account, no music of your own needed).** Booth comes with a demo crate file of seven
public-domain songs (CC0), and https://deckie.io/demo plays the same songs out loud.

1. Open Booth. With no crate file open it shows a first screen explaining what it needs, with "Open a crate file"
   and "Try the demo crate".
2. Tap "Try the demo crate". Booth opens the demo crate file and says "The demo crate is open: 7 songs." Allow the microphone
   when asked.
3. On another device (a phone or a laptop), open https://deckie.io/demo, press play, and put that device near the
   iPad. Within a few seconds Booth names the song playing and shows picks for what could come next. The page plays
   the seven songs one after another; Booth follows each change.
4. Without playing anything: in the Crate tab, tap any song to set it as playing by hand. The Listen tab then shows
   the song and its picks.
5. "Leave the demo crate" (on the Listen tab while it waits for a song, and in the Crate tab) goes back to the first
   screen, where a DJ opens their own crate file.

Contact for questions: [NAME, PHONE AND EMAIL GO IN THE FORM'S CONTACT FIELDS, NOT HERE]. Publisher: App Hold Media.
