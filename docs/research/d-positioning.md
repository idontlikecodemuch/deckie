# Track D: who Deckie is for and why (positioning and what DJs want)

Research report, Oct 26, 2026. Extends `docs/competitive-analysis.md` section 4 (cited as [S#] there); does not
redo it. New sources are [D#] at the end. **[inf]** marks inference; **[U]** marks a figure seen only in a search
snippet or a secondary page. Tool limits: reddit.com is unreachable, so subreddit sizes come from GummySearch and DJ
quotes come from forums that could be read (DJ TechTools, Digital DJ Tips, VirtualDJ, Algoriddim, Serato, Engine DJ);
Pioneer's forum, The Knot and the BLS pages block fetches, so their figures are [U]. Nothing was scraped.

---

## 1. One-page summary

### Positioning statement (April Dunford's shape)

**For** DJs who play on gear that does not know their library (vinyl, CD, legacy CDJs, borrowed or house decks,
standalone players) and who pick across genres and eras, **Deckie** is a **booth companion that listens**: a second
screen beside the decks. **Unlike** Beatport Track ID or Shazam inside djay (global catalogue, nothing about the
join), rekordbox Related Tracks, djay Match or Mixed In Key's DJ Mix mode (need a laptop running that software), or
memory and a crate list, Deckie **identifies what is playing from the DJ's own crate, edits, bootlegs, live sets and
burned CDs included, offline, reads the pitch fader, shows what could come next with the join (pitch value, join
waveform, move), learns how this DJ mixes, and writes the set's timestamped tracklist**, with the music never leaving
the DJ's devices.

| Dunford line | Content | Evidence |
|---|---|---|
| Competitive alternatives | Memory and a crate list; Beatport Track ID (free, microphone, Beatport catalogue) [D1][D2]; Shazam in djay [D3]; rekordbox Related Tracks, djay Match, MIK DJ Mix mode on a laptop [S1][S4][S7]; CDJ History and DJM-REC (Pioneer gear only) [D4]; hand-typed Mixcloud tracklists [D5][D6] | §3 |
| Unique attributes | Hears the room on any rig; matches the DJ's own crate offline (ShazamKit custom catalogues match "within your app" [D7]); pitch readout; join advice; per-DJ learning; set recording with tracklist; no account, no upload | spec §3, [D7] |
| Value | The next record and the join without a laptop or a network; a tracklist that otherwise gets typed by hand [D5][D8]; no repeat sets at a residency [D9][D10]; nobody else holds the library [D11] | §3 |
| Who cares | DJs whose rig cannot say what is loaded and whose repertoire is wide enough that the next pick is the hard part: open-format bar residents and mobile DJs on house or legacy gear; vinyl and CD DJs | §2 |
| Market category | "DJ booth companion" (second screen), App Store category Music, beside djay, rekordbox and Beatport [D12][D13][D14]. Not a DJ app, not a library manager | §6 |

### Jobs-to-be-done statement

**When** I am behind decks that do not know my crate and the floor is up, **I want to** see which record I already
own fits next and how to bring it in, **so that** the floor stays full and I leave with the tracklist, without my
music going anywhere. Evidence: "I will have to play some country... and top 40 and rap and rnb" [D15]; "Being aware
of the last time you played your tracks" [D10]; "Need to be able to easily export a history list to a text file"
[D8]; a library that "sits on third-party services you can't fully examine or control" [D11].

### Primary segment and why

Define the segment by the rig first and the music second: **DJs playing open-format without software that knows
what is loaded**. That is bar and club residents on house CDJs and mixers, mobile and wedding DJs when they are on
venue gear or standalone players, and vinyl and CD DJs. Mike is the type specimen.

Why not "mobile and wedding" as spec v0.1 §2 has it: the census says most DJs, mobile DJs included, play a controller
with a laptop [D16][D17], and the laptop already knows the track; for them only the picks, the join and the tracklist
are new [inf]. Why not "vinyl and CD" alone: no census reports a vinyl share; CDJs and separates were about 10 percent
in 2021 and "around a quarter" of DJs were off the laptop in 2022 [D16][D17]; it is the best technical fit but a
smaller, more specialist group [inf]. The intersection is small, which matches the "best fit, but niche" verdict, and
it is the one place where every Deckie feature is new rather than one of them.

### A correction to the baseline claim

The competitive analysis says no major DJ app identifies the playing track through a microphone. Two do. djay's
Shazam feature can "identify the music playing through your device's microphone" and load or Match the result [D3].
Beatport Track ID (May 12, 2026, built with seeqnc) is free in the Beatport app, listens to "the audio reaching your
phone's microphone", is "optimized to recognize tracks that have been pitch-shifted, time-stretched, or edited", and
matches "against the Beatport catalog" [D1][D2]. Neither says where recognition runs; seeqnc is a cloud recognition
platform, so server-side matching is likely [inf]. Neither knows a track outside its catalogue, so unreleased edits
and bootlegs stay "ID" [D18]; neither knows the DJ's disc and folder, reads the pitch fader or says how to do the
join. **Deckie's claim is therefore: identifies from the DJ's own crate, including bootlegs and edits, offline, with a
pitch readout and join advice.** "Hears the room" is table stakes.

---

## 2. Segments

Sizes are from the Digital DJ Tips Global DJ Census (15,000 to 36,000 self-selected respondents a year, skewed to
engaged hobbyists) and US wedding and labour data. No source counts vinyl or CD DJs.

| Segment | Size signal | Gear | Pain | Fit |
|---|---|---|---|---|
| Open-format, mobile and wedding | 15 percent "adopt more of a mobile DJ style" (2020, n=35,073) [D19]; second-largest group after bedroom (2024) [D17]; 63 percent of mobile DJs played a wedding, average US$697 a show (2017, n=7,095) [D20]; about 70 percent of US couples hire a DJ, average $1,689 [U][D21]; 7,190 payroll DJs excluding radio in the US, self-employed not counted (BLS May 2023) [U][D22] | Controller plus laptop for most; all-in-ones; house gear at venues | Decades and genres in one night; requests; song choice over flow; searching a wide library | Picks across eras, history, tracklist. Identification is new only off the laptop. Primary when on house, standalone or legacy gear |
| Vinyl and CD | No census share. CDJs and separates about 10 percent (2021, n=32,027) [D16]; "around a quarter" off the laptop (2022, n=21,000) [D17]; vinyl is no longer the default but "remains part of club, house, techno, hip-hop, scratch and specialist scenes" [D23] | Turntables, CDJ-1000/800-class players, house mixers; no link, no history | No record of what was played; promos come back "Unknown"; tracklists typed by hand; pitch and key by ear | Strongest technical fit: every feature is new. Smaller, specialist; some will call assistance cheating [inf] |
| Bar and club residents | "Appreciable numbers... holding down club residences" (2024) [D17]; fourth-ranked DJ type (2019, n=36,014) [D24]; only 25 percent of all respondents have regular public gigs (2022) [D17] | House CDJs (often older) and mixer; some bring a USB | Repeating the set for the same regulars; when was this last played; unplayed gems | Good: history strip, no repeats, picks from their crate on whatever the bar owns. Kuvo venues make "stays on my iPad" concrete |
| Bedroom and hobbyist | Biggest single group (2022, 2024) [D17]; "nearly half of you never or rarely play in public" (2023) [D25]; more than half spent $1,500 to $5,000 on kit (2024) [D17]; three-quarters earn under 10 percent of income from DJing [D17][D25] | Controller plus laptop | Learning what mixes with what; "Looking For" and "Struggling" top r/Beatmatch [D26] | Weak for the microphone story; the join lesson and a practice tracklist could sell at a hobby price. Large, low willingness to pay [inf] |

---

## 3. Where they talk and what they ask for

**Where.** r/DJs: 317k members, up 9.2 percent a year, top topics "Struggling", "Equipment", "Hard Time" (GummySearch,
Oct 19, 2026) [D27]. r/Beatmatch: 220k, up 17.1 percent, "Looking For", "Struggling", "Setup" [D26]. Digital DJ Tips:
"over 150,000" members, census "over 22,000 entries" in 2026 [D28][D29]. DJ TechTools forum: long threads, busiest
2010 to 2017 [D15]. Pioneer DJ forums: history and export requests [D4][D30]. VirtualDJ forums: the mobile and
wedding crowd [D31]. Algoriddim community: the djay Match thread [S29] and a subscription thread [D32]. Serato forum:
the iPad library thread [D33]. Engine DJ community [D8]. Discords: Crossfader about 13.5k members, DJ Mag about 5.8k
[D34], not searchable from here.

**What they ask for**, new evidence only, ranked by frequency across the reachable sources:

1. **Tracklists and history from any rig.** Engine DJ: "This is a must for Prime, as I'm doing it manually today";
   "Need to be able to easily export a history list to a text file" [D8]. rekordbox users asked to import history with
   per-track timestamps, "would help with billing" [U][D30]. VirtualDJ users paste "artist, title and time" into
   Mixcloud by hand [D5]. Serato's tip for "tracks you played off CD or vinyl" is to insert them into History manually
   [U][D35]. Mixcloud (Aug 2026): "every artist on your tracklist gets a shot at being discovered by someone"; its
   fingerprinting "will not create a tracklist for you" [D6][D36].
2. **Identification that survives the mix, and its limits.** Shazam and SoundHound were "60 to 70 percent successful"
   on DJ sets in DJ TechTools' test [D37]. Beatport Track ID "won't catch every dubplate or unreleased ID" [U][D38];
   "ID" in a tracklist means a track no catalogue has [D18]. This is the gap an own-crate catalogue fills.
3. **Open-format selection pressure.** "I will have to play some country... and top 40 and rap and rnb"; the advice:
   "have the next tune lined up" and bring a friend [D15]. Wedding libraries: "Put your music into play lists like
   disco, 2016 pop, rock, hip hop etc." [D39]. VirtualDJ's wedding threads put song choice above flow [D31].
4. **Residency repetition.** A nightly resident: "what can I do so I won't repeat the same set everyday?" [D9]. "Being aware of the last time you played your tracks"; "gems hiding in your library right now
   that you've never played" [D10].
5. **Suggestions from the DJ's own library and history** (theme 1 in [S29]). Next for Traktor "takes your play history
   into account" [D40]; keyid's author found other key detectors "almost always wrong" [D41]; NXTCue sells next-track
   picks that read "what's already playing in your software" for $19 [D42].
6. **An iPad beside the decks.** Serato users asked for "a real library 'mirroring' in serato remote"; staff: "This
   isn't planned at the moment" (38 posts) [D33]; Serato Remote is discontinued [D43]. In Oct 2026 a djay user is
   building an iPad companion with "library browse and load" [D44].
7. **Subscriptions, no.** "As a personal choice, I don't like subscriptions... anywhere"; "I'd rather pay $50/year for
   now, or even $30" [D32]; djay reviews already logged the complaint [S38].
8. **Not "AI".** "Nearly 80 percent of respondents still don't use AI tools at all"; users use them for "music discovery
   and playlist creation" [D29]. djay now calls itself "DJ App & AI Mixer" [D12]. Deckie should say "hears" and "your
   crate", not "AI" [inf].

---

## 4. Willingness to pay and comparables

Checked Oct 26, 2026, USD. [U] means a snippet or reseller rather than the vendor's page.

| Product | Price | Model | Source |
|---|---|---|---|
| djay Pro | $6.99/mo, $49.99/yr, a $29.99 option; free tier | Subscription | App Store [D12] |
| rekordbox | Free; Core $12/mo or $120/yr; Creative $18/mo or $180/yr; Professional $36/mo or $360/yr; Cloud Option $9 to $11/mo extra | Subscription | rekordbox.com [D45] |
| Serato DJ Pro / Suite | $11.99/mo or $299 one-time; Suite $14.99/mo or $499 | Both | serato.com [D46] |
| Mixed In Key 11 / Pro | $58 / $99 (Mar 2025); £58 (Aug 2026) [U]; site hides prices by region | One-time | [D47][D48] |
| DJ.Studio | Studio $99, Pro $119 to $129, Pro + Stems $149 to $169, Ultimate $209, 12 months of updates; about $29/mo | Both | [D49]; Capterra [U][D50] |
| Beatport Track ID | Free in the app; streaming Essential $10.99/mo or $109/yr, Advanced $15.99, Professional $29.99, Pro+ $34.99 | Free feature | [D2][D51] |
| Lexicon DJ | Essential about $10.49/mo or $249 lifetime; Ultimate about $20.99/mo or $499 lifetime | Both | [U][D52] |
| NXTCue | $19 one-time (was $29) | One-time | [D42] |
| set79 | $8 per 3 set analyses or $10.90/mo | Pay per use | [U][D53] |
| Traktor Pro 4 / VirtualDJ | about $99 one-time / about $19/mo | One-time / subscription | [U][D49] |

**Reading.** Three anchors. (a) Identification alone is $0: Shazam, djay and Beatport give it away, so Deckie cannot
charge for "what is this". (b) A DJ utility bought once sits at $19 to $99; Mixed In Key at $58 is the closest shape:
an analysis tool that makes the DJ better, bought once. (c) DJ-app subscriptions run $7 to $12 a month and draw open
resentment [D32][S38]. The budget is a hobby budget (7 percent earn most of their income from DJing [D17][D25]) but
gear-shaped (more than half spent $1,500 to $5,000 on kit [D17]) [inf]. **Recommendation [inf]:** price like Mixed In
Key, not djay: one-time in the $39 to $59 band including the Mac analyser, with a lifetime option beside any later
subscription as Serato and Lexicon do. Keep the day 61 to 90 test ($4.99/mo against about $49) and the 30 percent bar.

---

## 5. Privacy as a selling point

**Does it land?** Partly, and only when said concretely. DJs object when a vendor holds their files or play data:
rekordbox Cloud Library Sync "sits on third-party services you can't fully examine or control"; "Click the wrong thing
and you're in trouble" [D11]; the 2014 Pioneer forum complaint that a required Kuvo account that would "share tracks
name is a privacy problem" [U][D54], answered with "no playlists are publicized" [D55]; and ID culture, where an
unreleased edit is currency [D18]. Store labels show the contrast: Beatport links Search History and User Content to
the user [D14]; rekordbox links email, user and device IDs and usage [D13]; djay uses identifiers to track [D12]. But
privacy was never the top ask in any thread; "no account", "no upload" and "works with no signal" were [inf].

**How to say it.** Say what it does, not "privacy": "Your music stays on your iPad. No account. No upload. Works in a
basement with no signal." Add the proof: an App Store label of **Data Not Collected**, which Deckie can carry because
"data that is processed only on device is not 'collected' and does not need to be disclosed" [D56]. The label is rare
and fragile: of 474,669 apps studied, 97 percent showing "Data Not Collected" had policies suggesting otherwise, and
trust fell when label and behaviour disagreed [D57]. So the policy must say the same, and crash reporting must be off
or opt-in under Apple's product-improvement exemption [D56]. Do not lead with "AI" [D29].

---

## 6. App Store realities

- **Microphone.** A specific `NSMicrophoneUsageDescription` is required and read by reviewers [D58]. 2.5.14 requires
  "explicit user consent" and "a clear visual and/or audible indication when recording" of any user activity,
  microphone included [D59]. Deckie
  listens all night and logs the set, so it needs a persistent on-screen "listening" state, a separate consent for set
  recording (which also captures voices), and the orange microphone indicator will show throughout [D60].
- **Background.** Listening and recording while the iPad sleeps needs the audio background mode and the idle timer
  off in the booth [inf; Apple's page could not be read by this tool].
- **Data rules.** 5.1.1(i): a privacy policy link in metadata and in the app even if nothing is collected.
  5.1.1(iii): request only what the core function needs and "use the out-of-process picker or a share sheet" for
  files, which fits crate import. 5.1.2(i): disclose sharing "with third-party AI", moot on device [D59].
- **Content rules.** 5.2.2 and 5.2.3: no using a service's content outside its terms, no ability to "save, convert,
  or download media from third-party sources (such as Apple Music, YouTube, SoundCloud...)" [D59]. Deckie imports only
  files the user already holds; this bounds track B's YouTube question to metadata.
- **Recognition risk.** ShazamKit custom catalogues are on device ("matching custom catalogs takes place within your
  app") and need no ShazamKit App Service [D7]; no recognition-app rejection was found [D61]; risk is low [inf]. The
  real risk is 2.3.1(a): features must be "accessible for review" [D59], and a reviewer has no crate and the simulator
  has no microphone. Ship a small royalty-free demo crate and a review video.
- **Metadata.** 2.3.7: names up to 30 characters, no trademarked terms in keywords (avoid "rekordbox", "CDJ",
  "Shazam"), no "unverifiable product claims" in subtitles [D59]. "Deckie: DJ Booth Companion" (26) fits.
- **Category.** Music, with djay, rekordbox and Beatport [D12][D13][D14].

---

## 7. Naming: items still owed

`docs/naming/05-deckie.md` is the deep report; this summarises it. DECKEE (Deckee Pty Ltd, boating safety) is
registered for class 9 software: US Reg. 6993660 (serial 79317019) with narrow boating goods; IR 1605323 protected in
the EU, UK, NZ, Canada and Jersey with broad "computer software, downloadable software (apps)"; Australian
registrations 2119248 and 2119251 (2020). Both stores rank DECKEE first for "deckie". Cheap, reversible buys
(deckie.dj after a registrar check, deckie.io, getdeckie.com, the handle deckieapp) are fine now; deckie.com
($59,888), any filing and any public launch wait for an attorney's read of DECKEE.

**New today.**
- **DECKEE re-verified on TSDR, Oct 26, 2026:** "LIVE/REGISTRATION/Issued and Active", registered Mar 7, 2023 under
  Section 66(a) from IR 1605323, IR renewal Jul 6, 2031 [D62]. The US Section 71 window (Mar 7, 2028 to Mar 7, 2029)
  is the first point where the goods could narrow or lapse; diary it.
- **deckie.dj:** NXDOMAIN at the .dj authoritative servers again today (control mixo.dj answers); the registry has no
  WHOIS or RDAP (whois.nic.dj does not resolve), so availability is still unconfirmed [verified with dig]. .dj runs
  from about $55 (Netim) to about $196 a year [U][D63]; 101domain lists $129.99, renewal $143.99, "Anyone can register
  a .dj domain" [D64]; one registrar says each application goes to the registry for approval and generic names are
  reserved [U][D63]. Budget $60 to $130 a year and expect a delay.
- **Positioning fit:** the diminutive says helper, not autopilot, which matches "recommend, never prescribe"; "DJ"
  belongs in the subtitle, which is what 2.3.7 allows.

**Still owed** (05 §6, unchanged): attorney opinion on coexistence and partial non-use cancellation; USPTO, EUIPO, UK
IPO, TMview and IP Australia searches by hand; the registrar check; Instagram, Threads, Facebook and Reddit handles;
Resident Advisor, 1001Tracklists and Spotify artist searches; the autocorrect test; OpenCorporates; the spelling test.

---

## 8. Open questions

1. Does Beatport Track ID match on device or on a server? It decides whether "offline" is a differentiator or a
   detail [D1][D2].
2. How many DJs play off the laptop in 2026? Last public figure "around a quarter" (2022) [D17]; the 59-page 2026
   census PDF may split CDJ, standalone and vinyl.
3. Will anyone but Mike use the pitch readout? Test with the vinyl and CD DJs in the trial before wider variants.
4. Do laptop-based mobile DJs want a second screen for picks when the laptop shows the library? Browsing yes [D33];
   picks untested.
5. Reddit and Discord are unread: have a person pull ten threads each from r/DJs and r/Beatmatch and ask in the
   Crossfader Discord before spec v0.2 locks the segment.
6. Data Not Collected versus crash logs, and whether an iPhone-only "set recorder" SKU is the cheaper way in for the
   vinyl and CD segment (links to track A's one-binary question).

---

## Sources

- D1 Beatport, "Beatport Launches Track ID" (May 12, 2026): https://www.beatportal.com/articles/1405405-beatport-launches-track-id-a-music-discovery-tool-built-for-djs
- D2 GearNews, "Beatport Track ID Recognizes Tracks in the Mix": https://www.gearnews.com/beatport-track-id-dj-tech/ ; Sonicstate: https://sonicstate.com/news/2026/05/13/beatport-launches-track-id/ ; iMusician (May 21, 2026): https://imusician.pro/en/resources/blog/beatport-track-id-feature
- D3 Algoriddim, djay for iOS manual, Shazam: https://help.algoriddim.com/user-manual/djay-ios/dj-tools/performance-tools/shazam
- D4 Pioneer DJ forum, "Played tracks in CDJ 2000nxs" (blocked; title only): https://forums.pioneerdj.com/hc/en-us/community/posts/360007334686-Played-tracks-in-CDJ-2000nxs ; DJM-REC: https://apps.apple.com/us/app/djm-rec-dj-live-recording-app/id1292535659
- D5 VirtualDJ forum, "Tracklist for Mixcloud" (Oct 2021): https://virtualdj.com/forums/243472/General_Discussion/Tracklist_for_Mixcloud.html
- D6 Mixcloud help, "How do I manually add a tracklist to my shows?": https://help.mixcloud.com/hc/en-us/articles/360004053959-How-do-I-manually-add-a-tracklist-to-my-shows
- D7 Apple WWDC21, "Explore ShazamKit" transcript: https://developer.apple.com/videos/play/wwdc2021/10044/
- D8 Engine DJ community, "Export setlist on Prime" (2017, 8 posts): https://community.enginedj.com/t/export-setlist-on-prime/6198
- D9 Digital DJ Tips, "How Do I Keep My Nightly Residency Fresh?" (Nov 2017): https://www.digitaldjtips.com/questions-keep-nightly-residency-fresh/
- D10 DJ TechTools, "The Regulars Notice" (Sep 4, 2017): https://djtechtools.com/2017/09/04/regulars-notice-avoid-playing-dj-set-every-week/
- D11 Digital DJ Tips, "Should DJs Use Rekordbox's Cloud Library Sync?" (Apr 16, 2026): https://www.digitaldjtips.com/rekordbox-cloud-library-sync-advice/
- D12 App Store, djay (category, IAPs, privacy label): https://apps.apple.com/us/app/djay-dj-app-ai-mixer/id450527929
- D13 App Store, rekordbox: https://apps.apple.com/us/app/rekordbox-dj-app-dj-mixer/id1487048203
- D14 App Store, Beatport: https://apps.apple.com/us/app/beatport-music-for-djs-app/id1543739988
- D15 DJ TechTools forum, "Help, I have an open format event I'm playing at tonight" (Jun 2011, 20+ posts): https://forum.djtechtools.com/t/help-i-have-an-open-format-event-im-playing-at-tonight/25209
- D16 Digital DJ Tips, Global DJ Census 2021 results (n=32,027): https://www.digitaldjtips.com/global-dj-census-2021-results/
- D17 Digital DJ Tips, 2022 census (n=21,000): https://www.digitaldjtips.com/here-are-the-results-from-our-2022-census-the-biggest-dj-survey-in-the-world/ ; 2024 census (n≈15,000): https://www.digitaldjtips.com/census-results-2024/
- D18 MixTracklist, "What Is a Track ID?": https://mixtracklist.com/guides/what-is-a-track-id ; CrateWire: https://cratewire.com/guides/what-does-id-mean-in-dj-sets
- D19 Digital DJ Tips, 2020 census (n=35,073): https://www.digitaldjtips.com/highlights-from-the-global-digital-dj-census-2020/
- D20 Digital DJ Tips, mobile DJ census 2017 (n=7,095): https://www.digitaldjtips.com/2017/11/the-mobile-dj-census-results-are-in/
- D21 The Knot, average DJ and band cost (blocked; via snippets and Brite): https://www.theknot.com/content/average-cost-wedding-band-dj ; https://brite.co/blog/how-much-is-a-dj-for-a-wedding/ ; The Knot 2026 study (10,474 couples, $34,200 average wedding): https://www.theknot.com/content/average-wedding-cost
- D22 BLS OES 27-2091 Disc Jockeys, Except Radio, May 2023 (7,190; blocked, via snippet): https://www.bls.gov/oes/2023/may/oes272091.htm
- D23 DJWORX, "DJing With Vinyl": https://djworx.com/djing-with-vinyl/
- D24 Digital DJ Tips, 2019 census (n=36,014): https://www.digitaldjtips.com/final-results-are-in-for-the-worlds-biggest-digital-dj-survey/
- D25 Digital DJ Tips, 2023 census (n≈20,000): https://www.digitaldjtips.com/here-are-the-results-from-our-2023-census-the-biggest-dj-survey-in-the-world/
- D26 GummySearch, r/Beatmatch: https://gummysearch.com/r/Beatmatch
- D27 GummySearch, r/DJs: https://gummysearch.com/r/DJs/
- D28 Digital DJ Tips, "4 Surprising Facts About DJs In 2025": https://www.digitaldjtips.com/4-facts-djs-in-2025/
- D29 Digital DJ Tips, "5 DJ Trends To Watch In 2026 (According To 22,000 DJs)": https://www.digitaldjtips.com/5-facts-about-djs-2026-census/
- D30 Pioneer DJ forum, "Import Track History" (blocked; via snippet): https://forums.pioneerdj.com/hc/en-us/community/posts/205225793-Import-Track-History
- D31 VirtualDJ forums, "Wedding DJ" and "Song Selection or Flow": https://virtualdj.com/forums/206880/general_discussion/wedding_dj.html ; https://www.virtualdj.com/forums/180052/General_Discussion/Song_Selection_or_Flow_which_has_priority___.html
- D32 Algoriddim community, "Subscription or Purchase Option" (May 2025, 23+ posts): https://community.algoriddim.com/t/subscription-or-purchase-option/35582
- D33 Serato forum, "Library in serato remote" (2013 to 2014, 38 posts): https://serato.com/forum/discussion/1177637
- D34 Discord listings, Crossfader: https://discord.com/servers/crossfader-834657748720943144 ; DJ Mag: https://discord.com/invite/djmag
- D35 Serato, "Pro Tips: Serato DJ Playlists" (via snippet): https://serato.com/latest/blog/17233/pro-tips-serato-dj-playlists
- D36 Mixcloud blog, "Your mixes need tracklists" (Aug 27, 2026): https://www.mixcloud.com/blog/2026/08/27/your-mixes-need-tracklists-here-s-what-they-re-doing-for-you/
- D37 DJ TechTools, "DJ Trainspotting" (2015): https://djtechtools.com/2015/10/08/dj-trainspotting-how-to-find-out-what-a-dj-is-playing/
- D38 Rave Quarters on Track ID (via snippet): https://www.ravequarters.com/post/beatport-just-built-the-track-id-tool-djs-actually-need
- D39 DJ TechTools forum, "Advice on music library for a Wedding DJ" (Oct 2016): https://forum.djtechtools.com/t/advice-on-music-library-for-a-wedding-dj/74920
- D40 DJ TechTools forum, "Introducing Next for Traktor" (Nov 2016): https://forum.djtechtools.com/t/introducing-next-for-traktor-a-track-recommendation-software/75100
- D41 keyid (GitHub): https://github.com/xdave/keyid
- D42 NXTCue: https://www.nxtcuedj.com/
- D43 Serato Remote (discontinued): https://serato.com/remote
- D44 Algoriddim community, "I am creating an iPad companion app for Djay Pro" (Oct 2026): https://community.algoriddim.com/t/i-am-creating-an-ipad-companion-app-for-djay-pro/43509
- D45 rekordbox plans: https://rekordbox.com/en/plan/
- D46 Serato pricing: https://serato.com/dj/pricing
- D47 Digital DJ Tips, Mixed In Key 11 Pro (Mar 31, 2025): https://www.digitaldjtips.com/mixed-in-key-11-pro/
- D48 Future Sound Academy, Mixed In Key 2026 (via snippet): https://www.futuresoundacademy.com/blog/mixed-in-key-2026
- D49 DJ.Studio, "2026 DJ Software Subscriptions Compared" (Apr 17, 2026): https://dj.studio/blog/dj-software-subscriptions-buyers-guide
- D50 Capterra, DJ.Studio pricing (via snippet): https://www.capterra.com/p/10017266/DJ-Studio/
- D51 Beatport Streaming plans: https://stream.beatport.com/
- D52 Lexicon DJ pricing (prices hidden on fetch; via snippet): https://www.lexicondj.com/pricing
- D53 set79: https://set79.com/
- D54 Pioneer DJ forum, "Rekordbox 3 need Kuvo account - privacy issue" (2014; blocked, via snippet): https://forums.pioneerdj.com/hc/en-us/community/posts/203070089--OPEN-Rekordbox-3-need-Kuvo-account-privacy-issue
- D55 DJWORX, "Pioneer KUVO" (2014): https://djworx.com/pioneer-kuvo-connect-clubs-cloud/
- D56 Apple, App privacy details (definition of "collect"; on-device exemption): https://developer.apple.com/app-store/app-privacy-details/
- D57 Balash et al., "Honesty is the Best Policy: On the Accuracy of Apple Privacy Labels Compared to Apps' Privacy Policies", PoPETs 2024: https://par.nsf.gov/biblio/10577928-honesty-best-policy-accuracy-apple-privacy-labels-compared-apps-privacy-policies ; label-trust interviews: https://par.nsf.gov/biblio/10399852
- D58 Apple, NSMicrophoneUsageDescription: https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription
- D59 Apple, App Review Guidelines (2.3.1, 2.3.7, 2.5.14, 4.2, 5.1.1, 5.1.2, 5.2.2, 5.2.3): https://developer.apple.com/app-store/review/guidelines/
- D60 Apple support, orange and green indicators: https://support.apple.com/en-us/HT211876
- D61 App Store 4.3 rejection guides (no recognition-app cases found): https://www.appsubmitter.io/app-rejection-guides/app-store-guideline-4-3-spam/
- D62 USPTO TSDR, serial 79317019 (DECKEE): https://tsdr.uspto.gov/statusview/sn79317019
- D63 .dj price comparisons (tldes.com; tld-list blocked): https://tldes.com/dj ; https://tld-list.com/tld/dj
- D64 101domain, .dj registration: https://www.101domain.com/dj.htm
