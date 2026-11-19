# TestFlight paperwork: Deckie Booth, build 1

Drafts for approval, Nov 19, 2026. Nothing here has been sent to Apple. Each file is the text for one box in App Store
Connect or one page for testers; copy it in once approved.

| File | Where it goes |
|---|---|
| `beta-description.md` | TestFlight > Test Information > Beta App Description |
| `what-to-test-build-1.md` | TestFlight > the build > What to Test |
| `review-notes.md` | TestFlight > Test Information > Beta App Review Information > Review Notes |
| `tester-notes.md` | The page or email testers get with their invitation |
| `privacy-policy.md` | deckie.io/privacy (TestFlight asks for a privacy policy URL for outside testers) |
| `app-store-connect-fields.md` | Every field of the app record and TestFlight's test information, with the text to enter |

The build: Deckie Booth 0.1.0 (1), bundle id `io.deckie.booth`, iPad only, iPadOS 17 or later, publisher App Hold
Media. No account, no sign-in, no network use in Booth. Set recording is on until the DJ turns it off: tap REC on
the Listen screen (since `pc/booth-build-1`; the choice is remembered). The demo crate shows as "Demo crate" in the
Crate tab. The Release archive was proved on Nov 19, 2026 (`pc/booth-build-1`): 3.8 MB app, no library data, the demo
crate file and the privacy manifest inside, no `deck` URL scheme.

Still to settle before the upload: deckie.io/demo and deckie.io/privacy published (the demo crate file is in the app
since `pc/booth-demo`; the page that plays its songs is in `site/demo/`, the privacy page in `site/privacy/`, both
built by `site/build.sh` and not yet uploaded), and the contact details for the review form.
