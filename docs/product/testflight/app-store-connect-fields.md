# App Store Connect: every field for Deckie, build 3

Draft, Nov 19, 2026; brought to build 3 on Nov 24, 2026. What the owner types when creating the app record and filling
TestFlight's test information, with the text to paste. No build has been sent to Apple yet. The build these describe:
Deckie 0.1.0 (3), bundle id `io.deckie.booth`, iPad only, iPadOS 17 or later, archived on Nov 24, 2026 from
`pc/testflight-3` (main as of that day). Builds 1 and 2 were never uploaded; the app was called Deckie Booth until
build 2.

**Done on Nov 24, 2026, in the developer account:** the explicit App ID `io.deckie.booth` is registered, and the App
Store Connect app record for it exists. The fields of section 1 that were typed then (the name, the SKU and the rest)
are as the owner entered them; the suggestions below stay as they were written, for reference.

**The App ID, corrected (Nov 24, 2026).** These notes said that automatic signing makes the App ID on the first device
build. It did not: every device build was signed with the team's wildcard development profile ("iOS Team Provisioning
Profile: *"), so no explicit App ID existed, and `io.deckie.booth` was missing from App Store Connect's Bundle ID list.
The step is to register it by hand first: Certificates, Identifiers & Profiles > Identifiers > + > App IDs > App,
Explicit, bundle id `io.deckie.booth`, no capabilities (the app uses ShazamKit with its own catalogues only, which needs
no capability). Then it appears in the New App form's list.

## 1. The app record (Apps > + > New App)

| Field | What to enter |
|---|---|
| Platforms | iOS (the app is iPad only; the build says so) |
| Name | `Deckie`. The App Store name must be unique across the whole store, and "Deckie" may already be taken; if App Store Connect refuses it, use `Deckie Booth` (the name of builds before 2). The name on the home screen is the build's own (`CFBundleDisplayName`, "Deckie") whichever store name is chosen. |
| Primary Language | English (U.S.) |
| Bundle ID | `io.deckie.booth` (pick it from the list; it is listed only once the explicit App ID is registered, above. Done Nov 24, 2026) |
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

App Privacy (the "nutrition label"): **Data Not Collected**. Deckie sends nothing over the internet; the set
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
| Sign-in required | **No** (untick "Sign-in required"; Deckie has no account and no sign-in) |
| Review Notes | the text of `review-notes.md`, below the title, with its last line ("Contact for questions: …") left out, since the contact fields hold it |

The demo instructions are in the review notes; the short form, if a field asks for it alone:

```
No account and no music needed. Tap "Try the demo crate" and allow the microphone. On another device open
https://deckie.io/demo/ and press play near the iPad; within a few seconds Deckie names the song and shows picks.
Or tap any song in the Crate tab to set it as playing. "Leave the demo crate" goes back to the first screen.
```

## 3. The build (TestFlight > the build)

| Field | What to enter |
|---|---|
| What to Test | the text of `what-to-test-build-3.md`, below the title |
| Export Compliance | no question should appear: the build's Info.plist sets `ITSAppUsesNonExemptEncryption` to NO. If App Store Connect asks anyway, answer **No** to "Does your app use encryption?" (more precisely: it uses none beyond what iPadOS itself provides, and it makes no network connections at all; the crate file's SHA-256 checks are hashing, not encryption). |

## 4. Before the upload (not fields, but the order)

1. deckie.io/privacy/ and deckie.io/demo/ published (TestFlight checks that the privacy URL opens). Both answer 200
   (checked Nov 24, 2026; deckie.io/demo without the slash is redirected to deckie.io/demo/).
2. The explicit App ID and the app record above created (done Nov 24, 2026).
3. Archive and upload from `deck-app/` (README, "TestFlight"). The Release archive of build 3 was made and checked on
   Nov 24, 2026, signed with what was already on the Mac (the development certificate and the wildcard development
   profile), with nothing changed in the developer account. The export for App Store Connect needs an Apple
   Distribution certificate and an App Store profile for `io.deckie.booth`; neither is on the Mac yet, so the export
   command carries `-allowProvisioningUpdates`, with which Xcode makes both on the first export, through an account
   with the Admin or App Manager role signed in to Xcode. That export is also the upload (`destination` `upload`).
4. Internal testers (the team) can test as soon as the build is processed; outside testers wait for Beta App Review.
