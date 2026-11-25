# TestFlight paperwork: Deckie for iPad, build 4

Drafts for approval, Nov 19, 2026; brought to build 3 on Nov 24, 2026, and to build 4 the same day. Build 3 was
uploaded to TestFlight on Nov 24, 2026, the first upload; it has had no testers. Build 4 is the next upload and differs
from build 3 only by the icon (below). Each file is the text for one box in App Store Connect or one page for
testers; copy it in once approved.

| File | Where it goes |
|---|---|
| `beta-description.md` | TestFlight > Test Information > Beta App Description |
| `what-to-test-build-4.md` | TestFlight > the build > What to Test (`what-to-test-build-1.md` to `-3.md` are the earlier builds', kept as they were; build 4's is build 3's with one line on the icon) |
| `review-notes.md` | TestFlight > Test Information > Beta App Review Information > Review Notes |
| `tester-notes.md` | The page or email testers get with their invitation |
| `privacy-policy.md` | deckie.io/privacy (TestFlight asks for a privacy policy URL for outside testers) |
| `app-store-connect-fields.md` | Every field of the app record and TestFlight's test information, with the text to enter |

The build: Deckie 0.1.0 (4), bundle id `io.deckie.booth`, iPad only, iPadOS 17 or later, publisher App Hold Media.
Builds 1 and 2 were never uploaded; build 3 was uploaded and has had no testers, so build 4 is the first testers
get. The app was called Deckie Booth until build 2; on the home screen, in Settings and in Files it is Deckie. No account, no sign-in, no network use in the app. Stop,
in the corner of the Listen screen, turns the microphone off and ends and saves the set's recording; Start listening
starts again. Set recording is on until the DJ turns it off: tap REC (the choice is remembered). The demo crate shows
as "Demo crate" in the Crate tab. New in build 3 (`what-to-test-build-3.md`): listener A names the next song sooner
after a cut (D41); other music on the iPad keeps playing while Deckie listens; a call, Siri, an alarm or a change of
input stops listening cleanly and it starts again by itself; REC says what the recording is really doing; the set's
files are named "Deckie set <date>". New in build 4 (Nov 24, 2026, `pc/ipad-icon`): the icon picture is redrawn from
`site/icon.svg` at 1024 pixels, sharp, with the dark ground filling the whole square, and carries the word "Booth" in
the brand script across the record (decided Nov 24, 2026; placement chosen Nov 25, 2026); build 3's had its corners drawn in on white and was an
enlarged small picture, so white could show at the corners iPadOS rounds.

The Release archive of build 3 was made and checked on Nov 24, 2026 (`pc/testflight-3`: a 3.9 MB app, arm64 only, no
library data, the demo crate file and the privacy manifest inside, no `deck` URL scheme, the 1024-point icon with no
alpha channel), signed with the development certificate already on the Mac. The explicit App ID `io.deckie.booth` and
the App Store Connect app record were made by hand on Nov 24, 2026. deckie.io/demo/ and deckie.io/privacy/ are
published and answer 200 (Nov 24, 2026).

The Release archive of build 4 was made on Nov 24, 2026 and made again with the chosen icon and checked on Nov 25, 2026
(`pc/ipad-icon`: a 3.4 MB app, arm64 only, version 0.1.0 build 4, the redrawn icon with "Booth" opaque to every corner
in the app and in its asset catalogue), the same way, with nothing changed in the developer account.

Still to do: the export and upload of build 4 (`deck-app/README.md`, "TestFlight"), on the owner's word; the contact
details for the review form.
