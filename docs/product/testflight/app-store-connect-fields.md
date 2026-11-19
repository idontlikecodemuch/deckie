# App Store Connect: every field for Deckie Booth, build 1

Draft, Nov 19, 2026. What the owner types when creating the app record and filling TestFlight's test information,
with the text to paste. Nothing here has been sent to Apple. The build these describe: Deckie Booth 0.1.0 (1), bundle
id `io.deckie.booth`, iPad only, iPadOS 17 or later, archived from `pc/booth-build-1`.

## 1. The app record (Apps > + > New App)

| Field | What to enter |
|---|---|
| Platforms | iOS (the app is iPad only; the build says so) |
| Name | `Deckie Booth` |
| Primary Language | English (U.S.) |
| Bundle ID | `io.deckie.booth` (pick it from the list; automatic signing made the App ID on the first device build. If it is not listed, add it under Certificates, Identifiers & Profiles > Identifiers first) |
| SKU | `DECKIE-BOOTH-IPAD` (any text; never shown to anyone, cannot be changed later) |
| User Access | Full Access |

Then, on the app's page (App Information), the fields TestFlight needs before outside testers:

| Field | What to enter |
|---|---|
| Subtitle (optional) | `DJ booth companion` |
| Category, primary | Music |
| Category, secondary (optional) | Utilities |
| Content Rights | **Yes**, it contains third-party content, and yes, the rights are held: the demo crate names seven songs by other artists and holds their fingerprints (no audio); all seven are CC0, credited in the app (Credits) and in `site/demo/CREDITS.md`. A careful "Yes" is safer than "No" here; the owner's call. |
| Age Rating | Answer None to every question (no violence, no mature themes, no gambling, no unrestricted web access, no user-generated content); the result is 4+. |
| Privacy Policy URL | `https://deckie.io/privacy/` |

App Privacy (the "nutrition label"): **Data Not Collected**. Booth sends nothing over the internet; the set
recordings stay on the iPad. This matches `deck-app/Deck/PrivacyInfo.xcprivacy`.

## 2. TestFlight > Test Information

| Field | What to enter |
|---|---|
| Beta App Description | the text of `beta-description.md`, below the title |
| Feedback Email | `info@apphold.media` (the address deckie.io shows) |
| Marketing URL (optional) | `https://deckie.io/` |
| Privacy Policy URL | `https://deckie.io/privacy/` |
| Licence Agreement | leave Apple's standard licence |

Beta App Review Information (only outside testers need it, but fill it once):

| Field | What to enter |
|---|---|
| First name, last name, phone, email | the owner's own contact details, typed in the form; they are not shown to testers |
| Sign-in required | **No** (untick "Sign-in required"; Booth has no account and no sign-in) |
| Review Notes | the text of `review-notes.md`, below the title, with its last line ("Contact for questions: …") left out, since the contact fields hold it |

The demo instructions are in the review notes; the short form, if a field asks for it alone:

```
No account and no music needed. Tap "Try the demo crate" and allow the microphone. On another device open
https://deckie.io/demo/ and press play near the iPad; within a few seconds Booth names the song and shows picks.
Or tap any song in the Crate tab to set it as playing. "Leave the demo crate" goes back to the first screen.
```

## 3. The build (TestFlight > the build)

| Field | What to enter |
|---|---|
| What to Test | the text of `what-to-test-build-1.md`, below the title |
| Export Compliance | no question should appear: the build's Info.plist sets `ITSAppUsesNonExemptEncryption` to NO. If App Store Connect asks anyway, answer **No** to "Does your app use encryption?" (more precisely: it uses none beyond what iPadOS itself provides, and it makes no network connections at all; the crate file's SHA-256 checks are hashing, not encryption). |

## 4. Before the upload (not fields, but the order)

1. deckie.io/privacy/ and deckie.io/demo/ published (TestFlight checks that the privacy URL opens).
2. The app record above created.
3. Archive and upload from `deck-app/` (README, "TestFlight"); the export needs an Apple Distribution certificate,
   which Xcode makes on the first export with an Admin or App Manager account. The archive itself was proved on
   Nov 19, 2026 with the development certificate.
4. Internal testers (the team) can test as soon as the build is processed; outside testers wait for Beta App Review.
