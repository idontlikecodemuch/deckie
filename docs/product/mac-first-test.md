# Deckie Desk for Mac, first test

Nov 25, 2026. What a tester of Deckie Desk for Mac is told, written to `docs/product/voice.md`. The Windows page is
`windows-first-test.md`; most of what it says about adding music, the crate file and the iPad is true here too. How
the disk image is made is in `desk-app/README.md`, "Releasing Desk for Mac".

Words on this page that are ours, said once: a **crate file** is the one file Deckie writes about your songs (tempo,
bars, key, style, vocals; never the songs). **Deckie** is the iPad app that uses it beside the decks. **Deckie
Desk** is the program that makes it.

## What you need

- A Mac with Apple silicon (M1 or later). Macs with an Intel processor are not supported yet.
- macOS 14 Sonoma or later.

## How to start it

1. Open `Deckie Desk.dmg`. A window shows Deckie Desk and your Applications folder.
2. Drag Deckie Desk onto Applications.
3. Open Deckie Desk from Applications. The first time, the Mac says it was downloaded from the internet and asks if
   you want to open it. Click Open.

To remove it, drag Deckie Desk from Applications to the Trash.

## The microphone question

Deckie Desk can listen to the song playing and name it from your crate. The first time you switch on Booth, the
Mac asks whether Deckie Desk may use the microphone. Say yes if you want to try listening; everything else works
without it. What it hears is not kept or sent anywhere. You can change your answer in System Settings > Privacy &
Security > Microphone.

The Mac may also ask before Deckie Desk reads a folder such as Desktop or Documents, or a USB stick. That is the
Mac checking with you; say yes for the music you add.

## Your music stays on your Mac

Deckie Desk reads your songs where they are. Nothing is uploaded, nothing is copied, and no song is changed. It
needs no account and works with no internet. The one thing that uses the internet is "Look up songs via
MusicBrainz", and only when you ask for it.

## If something goes wrong

Please tell the person who gave you Deckie what you clicked and what the Mac or the window said (a screenshot
helps), and which Mac and macOS you have (Apple menu > About This Mac). If the Mac says Deckie Desk "cannot be
opened" or "is damaged", say that word for word: it is the most useful thing this test can tell us.

## For whoever hands this to a tester

- Hand out only what the notarise stage of `desk-app/tools/release-mac.sh` made: it ends with the notarised,
  stapled app checked and Gatekeeper accepting it. A disk image from the default run (no notarisation) opens only
  after the tester overrides Gatekeeper, and should not be handed out.
- Notarisation goes through Xcode's signed-in account (decided Nov 25, 2026), which notarises the app only. The disk
  image is signed with Developer ID but not itself notarised; the app inside it is the notarised part. On the build
  Mac, Gatekeeper rejects a copy of such an image marked as downloaded ("Unnotarized Developer ID"). Whether a
  tester's Mac then warns before opening the image is not known until it is tried on a second Mac. If it does, hand
  out `Deckie Desk.zip` instead: double-click it, then drag Deckie Desk to Applications.
- Proven on the build Mac, Nov 25, 2026: the Developer ID signature with the hardened runtime and its one
  entitlement; the app reading songs end to end under the hardened runtime (with a trial signature); the disk image
  mounting with the app inside verifying; Xcode's Developer ID re-sign keeping the runtime and the entitlement. Not
  proven: Apple's answer, Gatekeeper's yes, opening on a second Mac, and the microphone question under the release
  signature, which needs a person at the Mac.
