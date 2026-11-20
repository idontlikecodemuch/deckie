# TestFlight paperwork: Deckie for iPad, build 2

Drafts for approval, Nov 19, 2026. Nothing here has been sent to Apple. Each file is the text for one box in App Store
Connect or one page for testers; copy it in once approved.

| File | Where it goes |
|---|---|
| `beta-description.md` | TestFlight > Test Information > Beta App Description |
| `what-to-test-build-2.md` | TestFlight > the build > What to Test (`what-to-test-build-1.md` is build 1's, kept as it was) |
| `review-notes.md` | TestFlight > Test Information > Beta App Review Information > Review Notes |
| `tester-notes.md` | The page or email testers get with their invitation |
| `privacy-policy.md` | deckie.io/privacy (TestFlight asks for a privacy policy URL for outside testers) |
| `app-store-connect-fields.md` | Every field of the app record and TestFlight's test information, with the text to enter |

The build: Deckie 0.1.0 (2), bundle id `io.deckie.booth` (unchanged, so it updates build 1 in place), iPad only,
iPadOS 17 or later, publisher App Hold Media. The app was called Deckie Booth until build 2; on the home screen, in
Settings and in Files it is now Deckie. No account, no sign-in, no network use in the app. Stop, in the corner of the
Listen screen, turns the microphone off and ends and saves the set's recording; Start listening starts again
(`pc/booth-build-2`). Set recording is on until the DJ turns it off: tap REC (the choice is remembered). The demo
crate shows as "Demo crate" in the Crate tab, and its seven songs were chosen again so most go together. The Release
archive was proved on Nov 19, 2026 for build 1 (`pc/booth-build-1`: 3.8 MB app, no library data, the demo crate file
and the privacy manifest inside, no `deck` URL scheme); build 2 has been built for the simulator in Release, not
archived.

Still to settle before the upload: deckie.io/demo and deckie.io/privacy published with build 2's changes (the demo
page's new songs and the app's new name; `site/demo/`, `site/privacy/`, built by `site/build.sh` and not yet
uploaded), and the contact details for the review form.
