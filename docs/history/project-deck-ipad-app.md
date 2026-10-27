---
name: project-deck-ipad-app
description: The Deck iPad app (ShazamKit recognition + next-song picks) built Oct 24, 2026 in "Deck app/", installed on Chris's iPad Air; how to rebuild and reinstall
metadata:
  type: project
---

"Deck app/" in the playlist folder is a native iPadOS app (SwiftUI, xcodegen project.yml, bundle io.christophershannon.deck, team 566NNM5HT8 App Hold Media LLC, automatic signing) that listens through the mic, recognises any of the 347 catalogue tracks with a ShazamKit custom catalog (original + vinyl ±4% signatures, 47 MB), reads the deck pitch, and shows what could come next with the mixer's pair scores: Easy and Harder picks, Simple (2+1) / Full (3+2), a Minimal toggle (top-left) that hides the waveforms, CD1/CD2/All chips, a CDs tab and the mix map. It also records each listening session (AAC + JSON log + tracklist under Documents/Sets, reachable from Files). Installed on Chris's iPad Air (4th gen, UDID 00008101-001E410921A3001E) on Oct 24, 2026 after he signed in to Xcode; a free-ID 7-day limit does not apply (paid account).

**Why:** it sits on a stand by Mike's CDJ-1000MK3 at the Halloween party so he can see recognised tracks and options without looking at his phone.

**How to apply:** data refresh = `tools/prep_data.py` (uses the mixer venv) after the selection or analysis changes; rebuild and reinstall with the iPad unlocked and connected: `xcodebuild -project Deck.xcodeproj -scheme Deck -configuration Release -destination 'id=<UDID>' -derivedDataPath build/dd-dev -allowProvisioningUpdates -allowProvisioningDeviceRegistration build` then `xcrun devicectl device install app --device <UDID> build/dd-dev/Build/Products/Release-iphoneos/Deck.app`. The `-allowProvisioningDeviceRegistration` flag was the missing piece the first time. The live-mic path was never tested in the simulator (no audio input there); test on the iPad with a real speaker. Related: [[project-mixer-toolkit]].
