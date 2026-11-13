# Research V: the explainer film and the "coming soon" page

Dated Nov 11 and 12, 2026, at main c6c659c plus the working tree. What was looked up before making the film and the page,
the first cut and why it was built that way, the owner's notes on it, the second cut and the reason for every cut and
every word, the claims made and their source, and how every screen was captured. Nothing here is a decision; the
choices that belong to the owner are listed near the end. Tags: [measured] = run on this Mac for this work; [inf] =
my inference; [unverified] = could not be checked here.

The deliverables: `site/index.html` (the page, for deckie.io, not deployed), `site/assets/deckie-explainer.mp4` (the
film, fifth cut, 76 seconds),
`site/assets/deckie-15s.mp4` (its first fifteen seconds as a clip of their own) and `site/film/` (the film's source:
`film.js`, `shotlist.md`, capture scripts, the stroke plans in `words/`; the earlier cuts' sources are kept in
`site/film/v1/` and `v2/`).

## In plain words

An explainer film is a short video that says what a product is and how to use it. The advice from the people who
measure these things is consistent: keep it near a minute, open on the viewer's problem and not on a logo, say the
answer in one sentence, show the real product doing one job, and end on one clear next step. Most people will watch
without sound, so the words have to be on the screen.

Three cuts were made. The first was 84 seconds and walked through everything. The owner liked the look and found it
"a little long and over explained", a bit generic in design, and wanted it to say what Deckie is and is not, in DJ
words, to DJs who distrust anything that claims to mix for them. The second cut is 60 seconds. Its first fifteen
seconds stand alone: the problem, what Deckie is, what it is not, the name, "coming soon". The remaining 45 show the
three parts and the things only Deckie does. That cut was first set in a stencil typeface; after a trial of three
other faces the owner chose plain heavy headlines with a script, Pacifico (sections 7a and 7b). He then found the 60-second
copy had gone "a little far", so the third cut, 76 seconds, puts back the explanation a working DJ needs, sets
exactly three words in the script ("you", "your", "Deckie") and writes each of them on screen stroke by stroke
(section 7c). A sixth round refined the copy and the headers: a tagline, "Know your crate.", the app names Deckie
Desk and Deckie Booth, no boxed stamps, and section headers that stay in one place (section 7d). A seventh set the app names in the headers in the script,
written in, put the tagline in title case, "Know Your Crate", and re-broke every line so that none holds a single
word (section 7e). An eighth made the header's "on your Mac" smaller and grey and produced three soundtracks
to choose between (section 7f). A ninth merged two of them into soundtrack D (section 7g) and made the site ready
to upload: tabs, an "About the project" layer, the credit, the beta email, and a clean folder to deploy (section
7h). A tenth restyled both pages from Deckie Booth's Simple view: flat, rounded, fewer boxes, less purple (section
7i). That is the film and the site as they stand.

Every screen in the film is a capture of the real apps. The music under it was made by a program for the film; none
of the owner's music is in the film, on the page or in the repository.

## 1. What the research says about explainer films

Sources are numbered [n] at the end. Most are written by companies that sell video work, so the numbers are planning
figures, not laws; where a number traces to a study, the study is named.

**Length.** One to two minutes is the range everyone gives [1]; 60 to 90 seconds for a first-time visitor on a
home page, with 60 to 75 called ideal by two sources [3][4]. Wistia's own data (13 million videos, its 2026 report)
puts average engagement at 52 percent for videos under one minute, meaning the typical viewer watches about half
[2]. A page-top film longer than 90 seconds loses people [3]. So: under 90 seconds, and the important things in the
first half.

**Shape.** The same four beats everywhere: the problem the viewer knows (by about 20 seconds), the answer in one
sentence, how it works (from about 30 seconds), one call to action [1]. One source times a 60 to 75 second cut as pain
5 to 8 seconds, answer 10 to 15, the real product 20 to 30, the close 5 to 8 [3]. Open on the pain, never on the
logo [3][4].

**One job.** The most repeated mistake is trying to show everything: "cramming three features into 90 seconds" [3],
"showing too many features" [4]. The craft guide for screen recordings says to script "the 3 to 5 clicks that
complete the job" and that a film is not scripted until its point fits in one sentence [5].

**The real product.** Viewers trust the real interface more than abstract drawings [3]; the examples singled out as
best keep real screens visible and animate only the moment that matters (Slack), follow one journey from start to
result instead of listing tools (Wix), or show a hand-over between two places as a visible movement (HubSpot) [4].
The weak ones in the same lists are weak for the opposite reasons: a memorable animation with no next step (Zendesk),
a feeling with no product in it (Wise, Grammarly), a feature marathon (Mixpanel, 11 minutes) [6].

**Screen recordings.** Frame the recording (padding, rounded corners, a soft shadow) so it reads as a product and not
a raw capture; zoom to the thing being talked about ("the single biggest quality jump"); cut pauses; use believable
demo data, never live records; keep on-screen text under about ten words; 1080p H.264 is the right export [5].

**Sound off.** Assume the film plays muted [5]. The study usually cited is Verizon Media and Publicis Media's 2019
survey of 5,616 US adults [7]; the well-known "69 percent watch with sound off in public" figure is attributed to it
by secondary pages, and I could not open the original report [unverified]. One vendor says 80 percent of LinkedIn
and Facebook views are silent [3], unsourced. The practical rule does not depend on the exact number: the words go on
the screen, and narration and music are extras.

**Voice.** A human voice where trust is at stake; a synthetic voice only if disclosed [3]. Deckie's own voice guide
rules out hype, and there is no approved human voice for it, so the film has none (see section 3).

**The close.** One specific next step; "learn more" weakens it [3][6].

## 2. The first cut (84 seconds), and why it was built that way

The source is `site/film/v1/` (`shotlist.md` has every shot). In outline:

| Time | What it showed | Why it was there |
|---|---|---|
| 0 to 6 s | "CDJs. Turntables. The house decks. None of them know your music." | Open on the pain, not the logo [3][4]. The pain is research D's segment in the DJ's own nouns |
| 6 to 12 s | The booth screen; "A booth companion that listens." "It works from your own crate." | The answer in one sentence, early [1]; real product on screen [3] |
| 12 to 16 s | "Deckie comes in three parts": Desk, the booth, the dictionary | The brief asked for the suite |
| 16 to 32 s | Desk, four captions: the crate file, what it holds, discs and folders, the import log | Step 1 of "how to use it"; one caption per Desk feature |
| 32 to 36 s | "Send the crate file to your iPad." | Step 2 |
| 36 to 66 s | The booth, eight captions: listening, the song named, the pitch fader, picks, Simple and Full, one pick's line and wave, Shuffle, pin, More and search | Step 3; "zoom to the thing being talked about" [5], one idea per caption |
| 66 to 73 s | The dictionary: "echo out" typed, then its three columns | The brief asked for the dictionary |
| 73 to 76 s | "Your music stays on your devices. No account. No upload. Works with no signal." | voice.md's privacy line |
| 76 to 84 s | "Deckie. DJ booth companion. Coming soon. Help us beta test" | One next step [3][6] |

What the research changed in it: 84 seconds because 60 to 90 is the range; no voice because it must work muted and
no voice has been chosen; the name held back until second 6; real screens in framed cards with a push-in on each
point; a new caption, shot or move at least every four seconds [8].

Where it went wrong, seen afterwards. It followed the "how it works" beat too faithfully and turned into a feature
tour, the mistake the same sources warn about ("cramming three features into 90 seconds" [3]). Nineteen captions
gave every feature the same weight, so the things only Deckie does were no louder than Simple and Full. It never said
what Deckie is not, although the positioning research and the spec both lead with that. And it looked like any
well-behaved product film: a neutral grotesque typeface, rounded cards, a purple gradient.

## 3. The owner's notes on the first cut (Nov 11)

"It looks good!", then six notes, in his words where quoted:

1. "It's a little long and over explained. Have it cut down generally. Keep the core elements and market
   differentiators."
2. "It also all looks a bit 'AI' designed. Give it a bit more character. Maybe a nautical headline font or a
   reference." Deckie as in deckhand.
3. "Also say what it is and isn't in the language (from the research)."
4. "Make sure it realizes the audience."
5. "Make the first 15 seconds can stand alone."
6. "Also all this, current and past needs to be documented well with reasoning for language and storyboard." This
   letter.

Two cautions came with them from the session coordinating the work: the name has an open trademark question with
DECKEE, a boating mark (D9), so a nautical look should stay a reference and not become a theme; and the cut should be
checked end to end, with the sound-to-picture check run.

## 4. The second cut (60 seconds)

The plan is `site/film/shotlist.md`; the film is `site/film/film.js`. One beat is half a second.

### The storyboard, with the reason for each shot

| Time | On screen | Words | Why |
|---|---|---|---|
| 0 to 4 s | Type; two turning platters | "CDJs. Turntables. The house decks." then "None of them know your music." | The same opening as the first cut, two seconds faster. It names the audience by their gear (note 4): a DJ on any of the three knows in two seconds that this is about them |
| 4 to 9 s | The booth, a song named, picks listed | "Deckie knows your crate. A booth companion on an iPad, listening beside the decks." then "It names the song, reads the pitch fader, shows what could come next." | What it is, in one line that answers the line before it (they do not know your music; Deckie knows your crate). The second caption is the three things the spec's "What it is" lists first |
| 9 to 12 s | Type only, full width | "Not an AI DJ." "No sync button." "It suggests. You mix." | What it is not (note 3), placed before the name so a sceptical DJ hears it before deciding to leave (note 4). Sources in section 5 |
| 12 to 16 s | The name, large | "Deckie. DJ booth companion." and a stamp, "COMING SOON" | Closes the fifteen seconds (note 5): by now a viewer has the problem, the product, what it is not, the name and that it is coming |
| 16 to 21 s | Desk's table, and over it a stencilled label that fills in word by word | "1/3, Deckie Desk, on your Mac. Desk reads your crate and writes a crate file. Edits, bootlegs and burned CDs included." Label: "FRIDAY NIGHT, crate file: TEMPO, KEY, BARS, STYLE, FINGERPRINTS", stamped "NO AUDIO" | Part one of three. The owner's teaching sentence, the first differentiator (the crate is your own, burned CDs and edits included) and the fourth (no audio leaves) in one shot |
| 21 to 24 s | The label shrinks to a tag and travels to the iPad | "2/3. Send it to your iPad. AirDrop, iCloud Drive or Files." | The one moment the two apps meet. Kept short |
| 24 to 30 s | The booth: "Listening…", then the song appears at 27 s | "3/3, Deckie, on your iPad. Put it by the decks. Play." then "It names the song from your crate. Disc, folder and track, as on your player." | Part two of three, and the core: recognition, shown happening in real time |
| 30 to 34 s | Push in on the playing panel; outlines on "deck +3.0%" and "128 BPM" | "It reads the pitch fader. This deck runs 3 percent fast, so the tempo reads 128 BPM." | The second differentiator, shown as two numbers a DJ already reads |
| 34 to 40 s | The picks; then one pick's line and its wave | "What could come next, best first." then "Where to set the pitch. How you could bring it in. The wave: the end of this song over the start of that one." | The third differentiator |
| 40 to 44 s | Shuffle moves to 60 percent; a pick becomes NEXT | "Shuffle for less obvious picks. Pin the one you want." | Two controls that show the DJ stays in charge, in one shot |
| 44 to 48 s | The dictionary entry "Echo out", its three columns in turn | "The dictionary. The third part: every word, three ways." "Plain words." "The DJ's word." "What Deckie does with it." | Part three of three, in four seconds |
| 48 to 52 s | Type only | "Your music never leaves your devices." "No account. No upload." "Works with no signal." | The fourth differentiator, said once, plainly |
| 52 to 60 s | The name, the booth beside it | "Deckie. DJ booth companion." "COMING SOON" (stamp), "Help us beta test" | The same close as the fifteen-second card, plus the one next step |

### What was cut, and why

| Cut from the first cut | Why | Where it lives now |
|---|---|---|
| The separate "three parts" scene (4 s) | It showed three small pictures before the viewer cared about any of them | Each part is labelled where it is used: "1/3, Deckie Desk, on your Mac"; "3/3, Deckie, on your iPad"; "the third part" on the dictionary. The page has the three cards |
| Discs and folders in Desk | Housekeeping, not a reason to want Deckie | The page's Desk card no longer lists it either; it is in the README |
| The import log | Same | Nowhere in the film or page |
| "Tempo, key, bars, style, fingerprints" as its own caption | A list read aloud | It became the label's own lettering, read at a glance |
| Simple and Full | A setting | Cut |
| More and the search | The owner asked for core and differentiators; searching a list is neither | Cut from the film. The shot remains in the first cut's source |
| The dictionary being typed into (4 s) | Watching typing explains nothing | The entry is already on screen; the four seconds go to its three columns |
| "It works from your own crate. Your music stays on your devices." at second 9 | Said again at the end | Once, at 48 s |
| Sub-lines under most captions | Over-explaining was the note | Six of fourteen captions now have none |

Nineteen captions became fourteen, and the words on screen went from about 300 to about 230 [measured, counted from the two film.js files]. The booth chapter went
from 30 seconds to 20.

### The first fifteen seconds as a clip

`site/assets/deckie-15s.mp4` is the film's first 15 seconds, the sound faded over the last half second (it measures
-16.5 LUFS, quieter than the whole film because the introduction is the quiet part of the music). At 15 seconds the
last frame is the name card, held, with the stamp on it. What a viewer who stops there has been told: this is for DJs
on CDJs, turntables and house decks; those decks do not know your music; Deckie does, from an iPad beside them; it
names the song, reads the pitch fader and shows what could come next; it is not an AI DJ and has no sync button; you
mix; it is called Deckie; it is coming soon. The music is written so that its first eight bars (16 seconds) are an
introduction of their own and the full beat arrives with step 1.

## 5. The words

### What it is and is not, and where each line comes from

Note 3 asked for this "in the language (from the research)". Each line below is on the page; the first three of the
"is not" lines are also in the film.

| Line | Source |
|---|---|
| **Is:** "A second screen beside the decks. CDJs, turntables, the house gear: anything that does not show what is loaded." | Research D: the category is "DJ booth companion" (second screen); the segment is "gear that does not know their library" |
| **Is:** "Your crate, known. Built from your own files. Edits, bootlegs and burned CDs included." | spec-condensed, "What is different about Deckie today: it knows your crate, burned CDs and edits included"; D4 |
| **Is:** "The pitch fader, read from the room. In percent, the way the deck says it." | spec-condensed principle: "reads it from the room and reports it as a fader percentage" |
| **Is:** "What could come next, and how you could bring it in. Where to set the pitch, the move, the join." | spec-condensed, "What it is"; voice.md's "bring it in" |
| **Is:** "Yours. Your music never leaves your devices. No account. No upload. Works with no signal." | voice.md's privacy line; D3 |
| **Is not:** "Not an AI DJ. It plays nothing and mixes nothing. It suggests. You mix." | spec-condensed: "Not sold as AI"; principle "Deckie suggests; the DJ decides"; the competitive analysis on automix ("glorified crossfade features") |
| **Is not:** "No sync button. It never touches your decks or your mixer. It only listens." | Research E: "sync" is the software tempo lock that replaces beatmatching; voice.md keeps the word for that and nothing else. Deckie has no connection to the decks at all |
| **Is not:** "Not a lookup of what you play. It knows your crate, not the world's, and what you play trains nobody's model." | spec-condensed principle: "it never looks up what you play"; P7 (others hear the room against a global catalogue); the note on D3 and the community research's "I'm not helping train ai for free" |
| **Is not:** "Not a DJ app or a library manager. Keep the ones you have." | Research D, market category line: "Not a DJ app, not a library manager" |
| **Is not:** "Not for everyone. If you went to CDJs to get away from screens, skip it." | spec-condensed, "Who it is for": "Some will not want it: DJs who moved to CDJs to get away from screens" |

One tension, stated: voice.md says never to use "AI" where a DJ can see it. That rule is about not describing Deckie
as AI. "Not an AI DJ" uses the word to say the opposite, in the phrase DJs themselves use for the thing they
distrust, and the owner asked for it by name. It appears once in the film and once on the page.

### The captions of the second cut, word by word

| Words | Source and reason |
|---|---|
| "CDJs. Turntables. The house decks." | Research D's gear list in booth nouns. "The house decks" is how a resident says the club's own gear |
| "None of them know your music." | Research D: "gear that does not know their library". "Your music" and not "your library", because the next line introduces "crate" |
| "Deckie knows your crate." | The differentiator in four words, answering the line above. "Crate" in the owner's Nov 11 sense: a group of your songs |
| "A booth companion on an iPad, listening beside the decks." | "DJ booth companion" is the decided subtitle (voice.md, P8). "Listening" is what it does; "beside the decks" is where it sits (spec: "Deckie listens beside the decks") |
| "It names the song, reads the pitch fader, shows what could come next." | The first three verbs of the spec's "What it is". "Names", never "IDs" (voice.md) |
| "Not an AI DJ." "No sync button." "It suggests. You mix." | Section above. "You mix" is the last word of the fifteen seconds on purpose |
| "Desk reads your crate and writes a crate file." | The owner's teaching sentence, Nov 11, word for word |
| "Edits, bootlegs and burned CDs included." | spec-condensed and D4: these are first-class, and no catalogue-based tool knows them |
| "TEMPO, KEY, BARS, STYLE, FINGERPRINTS", "NO AUDIO" | The owner's description of the crate file, Nov 11; D3 |
| "Send it to your iPad. AirDrop, iCloud Drive or Files." | desk-app README. "It" because the crate file was named one line earlier; the film never says "crate" for the file |
| "Put it by the decks. Play." | Two instructions, the only imperatives in the film, because this is the how-to step |
| "It names the song from your crate. Disc, folder and track, as on your player." | Standing principle: disc, folder and track location is the primary identifier where discs exist |
| "It reads the pitch fader. This deck runs 3 percent fast, so the tempo reads 128 BPM." | The numbers on the captured screen, each labelled as fader pitch or tempo |
| "What could come next, best first." | D19's one ranked list. "Could", never "should" |
| "Where to set the pitch. How you could bring it in." | voice.md: "bring it in" is the booth's phrase; the pick's line gives the pitch value and the move |
| "The wave: the end of this song over the start of that one." | D18. The word "join" is not used on screen (voice.md) |
| "Shuffle for less obvious picks. Pin the one you want." | D19; "the one you want" keeps the choice with the DJ |
| "The dictionary. The third part: every word, three ways." "Plain words." "The DJ's word." "What Deckie does with it." | D12's "dictionary"; the vocabulary page's three registers |
| "Your music never leaves your devices." "No account. No upload." "Works with no signal." | voice.md's line; "never leaves" is the README's verb, and "devices" because Desk is on the Mac |
| "DJ booth companion", "COMING SOON", "Help us beta test" | The decided subtitle; the brief |

Words kept out, following voice.md: "join" as a noun, "sync" for anything Deckie does, "track ID", "smart", "magic",
"you should", any verdict, any exclamation mark. The film calls the iPad app "Deckie, on your iPad", because the
desk-app README's "Deckie Booth" is not a decided name.

Two words the film could not avoid, because they are on the captured screens: the booth's status bar and tab still
say "Deck" and "CDs", and a song on the disc named House is shown as "CD2 / 125-134". These are the build as it is.

## 6. The audience, and what the cut does about it

Who is watching (note 4): working DJs of any kind. What the research says about them:

- They distrust tools that take the mixing away. Reviewers and forums call consumer automix "glorified crossfade
  features" and "one step up from a jukebox" (competitive analysis, S3 and S13). The community pass found evidence
  for wanting help remembering their own music, and weaker evidence for wanting live instructions on how to mix.
- They distrust tools that feed on their choices: "I'm not helping train ai for free" (community pass).
- A screen in the booth is "both welcome and mocked" (community pass); some went to CDJs to get away from one.
- They talk in actions and numbers: bring it in, the pitch in percent, bars.

What the cut does, point for point: it says "Not an AI DJ", "No sync button" and "You mix" inside the first twelve
seconds; every claim about picks carries "could"; the numbers shown are the ones on the deck (percent, BPM); the
privacy line is said plainly and once; the page tells the DJ who hates screens to skip it, which is the spec's own
position and costs nothing with the people it will not suit. The film gives no reason to think Deckie plays, mixes
or decides anything, because it does not.

## 7. Character: the stencil, the stamp, and how far the nautical reference goes

This section records the second cut as first built, in the stencil. The type was changed on Nov 12 (sections 7a and
7b); the stamps, the label and the reasoning about the nautical reference still apply.

Note 2 asked for more character, "maybe a nautical headline font or a reference". What was done:

- **Headings in a stencil typeface** (Stardos Stencil, bold). Stencil lettering is what is painted on record crates,
  flight cases and cargo, and on ships' hulls and gear. So it is at home in a DJ's world first and reads as
  nautical second. It replaces the neutral grotesque that made the first cut look like any product film.
- **"COMING SOON" and "NO AUDIO" as stamps**: stencilled capitals in a ruled box, a few degrees off square.
- **The crate file as a stencilled label**, with its contents as its lettering.
- **A warm white for the stencilled words**, against the app's own purples, and square corners on the page where
  the first pass had pills.
- **One line on the page, in the footer: "Deckie, as in deckhand."**

What was not done, on purpose: no anchors, rope, waves, flags, compass roses or sailor's talk. A working DJ would
find those twee, and there is a second reason. D9 records that DECKEE, a boating-safety app, is registered for
software in several countries and that the name waits on an attorney's review. The naming history
(`docs/naming/00-shortlist.md`) also records a live US registration of DECKHAND for software, the reason the earlier
name was dropped. A nautical theme would move Deckie toward the first mark's field, and "deckhand" used as a tagline
would put the second mark's word beside a software product. So the word "deckhand" appears once, small, as an
explanation of the name, and is not in the film; an earlier version of this cut had "Your deckhand in the booth" on
both name cards and it was taken out for this reason. How far to take the reference is listed for the owner below.

Typefaces and their licences (the licence files are in `site/fonts/`):

| Typeface | Used for | Licence | Why it may be used here |
|---|---|---|---|
| Stardos Stencil, Bold | Headings on the page; titles, stamps and the name in the film | SIL Open Font License 1.1 (`LICENSE-StardosStencil.txt`) | The OFL allows use, embedding and redistribution, commercial included, when the licence travels with the font file. The name "Stardos" is reserved, so the file is shipped unmodified |
| Inter | Body text on the page; the smaller lines in the film | SIL Open Font License 1.1 (`LICENSE-Inter.txt`) | Same |

Both came from the Fontsource packages on npm. Other stencil faces looked at and passed over: Saira Stencil One
(reads as sport), Big Shoulders Stencil (too condensed to read at caption size), Allerta Stencil (thin). Inter Tight,
the first cut's heading face, is no longer shipped.

## 7a. The type trial of Nov 12: Yeseva One, Playfair Display and Pacifico

After the second cut the owner asked, in his words: "Have it try Yeseva One, Playfair and Pacifico on a few frames
and give me two choices before we make the final video and choice. Also a few font styles - capitalization, weights,
etc." No film was rendered for this and neither the film nor the page was changed; the choice is his.

**What was made.** Five frames, each set in every treatment: the opening ("CDJs. Turntables. The house decks. None
of them know your music."), what it is not ("Not an AI DJ. No sync button. It suggests. You mix."), the name card
with the COMING SOON stamp, the Desk step frame with the crate-file label and the NO AUDIO stamp, and the page's
hero. The film frames are layout copies of the film's own (same positions, sizes and colours) drawn as web pages;
the hero is the real page with only the headline face swapped. Body text and small labels stay in Inter in every
row. The sheets are in `site/film/type-trials/`, with the script that makes them:

- `1-yeseva-one.png`, `2-playfair-display.png`, `3-pacifico.png`: one sheet per face, the current Stardos Stencil
  frames as the first row of each.
- `4-side-by-side.png`: the current film against the strongest treatment of each face.
- `5-two-finalists-larger.png`: the two recommended treatments at half size.

**The fifteen treatments.** Yeseva One and Pacifico each have one weight, so their rows vary case, tracking and size;
Playfair Display has a full range of weights, an italic and a small-caps companion.

| Row | Treatment | What the frames show |
|---|---|---|
| REF | Stardos Stencil Bold, sentence case | The current film |
| Y1 | Yeseva One, sentence case | Heavy, warm, round; the name is strong; captions hold at one third size |
| Y2 | Yeseva One, all caps, tracked 4 percent | Loses the round lower-case shapes that give it character; lines get long and must shrink a fifth |
| Y3 | Yeseva One, title case | Reads as a headline about someone else; "A Crate File" looks shouted. Sentence case is also voice.md's rule |
| Y4 | Yeseva One, sentence case, tight and 8 percent larger | Slightly more presence than Y1; the longest caption comes close to the screen card |
| P1 | Playfair Display Black 900, sentence case | Sharp and dense; close to Y1 but cooler, with thinner hairlines |
| P2 | Playfair Display Bold 700 italic throughout | Elegant and slow to read; the italic capital J in "CDJs" and "DJ" has a swash that makes the word hard to recognise |
| P3 | Playfair Display ExtraBold 800, all caps, tracked 5 percent | Reads as a film poster or a wine label; small on screen |
| P4 | Playfair Display SC Bold (small caps) | The same problem as all caps, and "DECKIE" stops looking like a name |
| P5 | Playfair Display Medium 500, sentence case | Thin strokes fade on the dark ground at caption size |
| P6 | Playfair Display Black 900 for headlines; ExtraBold 800 italic for the name and the one accent line | Two voices: plain statements upright, the name and "It suggests. You mix." in italic |
| C1 | Pacifico for everything, sentence case | A script at caption size is slow; "AI DJ" and "CDJs" are hard to make out; the stamps stop reading as stamps |
| C2 | Pacifico, all caps | Not usable: a connected script is not drawn to be set in capitals |
| C3 | Pacifico for the name and the stamps; headlines in Inter ExtraBold | The name is friendly; the script stamps look like a café sign |
| C4 | Pacifico for the name only; headlines and stamps in Inter | The cleanest way to use Pacifico, and the headlines are back to the neutral grotesque of the first cut |

**The two recommended treatments.**

1. **Yeseva One, sentence case (row Y1).** Headlines, captions, the step numerals and the name in Yeseva One at its
   one weight, sentence case, normal tracking, in the warm white. Stamps ("COMING SOON", "NO AUDIO") and the
   crate-file label's lettering in Yeseva One capitals tracked 7 percent inside the ruled box, as now. Body and small
   labels in Inter. Why: it is the heaviest of the three, so the captions survive a phone and a muted autoplay, which
   is where the research says most viewers will meet the film (section 1); and its fat, round letters look like a
   record label or a club-night poster, which gives the character the owner asked for in something working DJs
   already own boxes of.
2. **Playfair Display, Black for headlines with the italic kept for the name and the accent line (row P6).**
   Headlines and captions in Playfair Display Black 900, sentence case; "Deckie" and the one line per scene that is
   Deckie's own voice ("None of them know your music.", "It suggests. You mix.") in ExtraBold 800 italic; stamps and
   the label in ExtraBold 800 capitals tracked 8 percent; body in Inter. Why: it is the only one of the three with a
   real range, and the italic lets the film say "You mix" in a different voice from the facts around it, which is the
   line a sceptical DJ most needs to hear (section 6). The cost is thinner hairlines than Yeseva One at the same
   size, so it wants checking on a phone before it is final, and the italic must stay off any line containing "DJ".

**Pacifico does not work for this, said plainly.** As a headline face it fails the first test the research sets:
words on screen that a muted viewer can read at once. It also brings a surf-shop mood that a working DJ would read
as a toy, and it is the most nautical-feeling of the three at a time when the name's trademark questions (section 7)
argue for less of that, not more. If the owner wants it anyway, row C4 (the name only) is the way to use it; the
headlines then need a face of their own, and Inter there is what he called "a bit AI designed".

**Against the stencil.** Either finalist gives up the crate and flight-case meaning of stencil lettering. The stamps
and the label still work, as rubber stamps and a printed label, and both finalists read faster than the stencil at
caption size. Either also ends the nautical reference in the type, leaving only the footer line.

**Licences.** All three are under the SIL Open Font License 1.1, confirmed from the licence file inside each
Fontsource package (version 5.3.0), which allows use, embedding and redistribution, commercial included, with the
licence shipped beside the font.

| Typeface | Weights in the package | Licence | Reserved font name |
|---|---|---|---|
| Yeseva One | Regular 400 only | SIL OFL 1.1 | "Yeseva" |
| Playfair Display | Variable, 400 to 900, upright and italic | SIL OFL 1.1 | "Playfair Display" |
| Playfair Display SC | 400, 700, 900 | SIL OFL 1.1 | "Playfair Display" |
| Pacifico | Regular 400 only | SIL OFL 1.1 | none stated |

None of the three is in `site/fonts/` yet; the chosen one goes in with its licence file when the choice is made, and
Stardos Stencil comes out.

## 7b. The owner's choice (Nov 12): Inter headlines, Pacifico for the name and for "you"

The phrase rule in this section was replaced later the same day by the three-word rule in 7c; the typefaces, the
domain and the reasoning about character stand.

His words, on seeing the trial: "Lets use C4 and use Pacifico for anything that is about the user, ex. 'you mix'.
Also the domain is deckie.io. It is purchased and on my bluehost."

So the final type is row C4 of the trial, with one addition that is his own idea and the best thing in it:

- **Headlines, captions, step numbers, stamps and labels: Inter ExtraBold (800)**, sentence case, tracked 2.5
  percent tight, in the warm white. Stamps and the crate-file label are Inter ExtraBold capitals tracked 10 percent
  in the ruled box.
- **The name "Deckie": Pacifico**, in the warm white.
- **The words that are about the DJ: Pacifico, in the accent colour.** The rule applied: a phrase goes into the
  script when it names the DJ or what is the DJ's own ("you", "your music", "your crate", "the one you want") *and*
  that phrase is the point of its line. A "your" that is only grammar stays in Inter. The script is never used on a
  line's "DJ" or "CDJs" (the script's capital J is hard to read), never on stamps or labels, and never for more than
  one phrase on screen at a time. The accent colour was already reserved for meaning (voice.md: "one accent colour,
  used only for meaning"); the meaning it now carries with the script is "this part is yours".

Every place the script is used:

| Where | Line | In the script | Why this one |
|---|---|---|---|
| Film, 2.5 s | "None of them know your music." | "your music." | The whole point of the opening: the music is the DJ's and the decks do not know it |
| Film, 4 s | "Deckie knows your crate." | "your crate." | The answer to the line before; the crate is the DJ's own |
| Film, 11 s | "It suggests. You mix." | "You mix." | The owner's own example; the last thing said before the name |
| Film, 27 s | "It names the song from your crate." | "your crate." | The differentiator: not from a catalogue, from yours |
| Film, 40 s | "Shuffle for less obvious picks. Pin the one you want." | "the one you want." | The choice stays with the DJ |
| Film, 48 s | "Your music never leaves your devices." | "Your music" | The promise is about what is theirs |
| Film, name cards (12 s, 52 s) | "Deckie" | the name | The name |
| Page, headline | "For decks that don't know your music." | "your music." | As in the film's opening |
| Page, "It isn't" | "It suggests. You mix." | "You mix." | As in the film |
| Page, top bar | "Deckie" | the name | The name |

Where it was held back on purpose: "Desk reads your crate and writes a crate file" (the owner's teaching sentence;
its point is the crate file), "Send it to your iPad", "as on your player", "never leaves your devices", "How you
could bring it in" (grammar, or the point is elsewhere), and "Not an AI DJ", "The DJ's word", "CDJs." (the J).

**How the two faces sit on one line.** Where a script phrase follows Inter words on the same line ("It suggests.
You mix.", "from your crate.", "Your music never leaves…"), both are drawn on one baseline, with the script 8
percent larger and 2 percent of the type size lower, so the two x-heights and baselines agree, and with a small
extra space after a script phrase because its last stroke trails. This was checked on rendered frames at full size
and at phone size (section 12).

**Does it carry enough character?** Yes, in my judgment, and more than the trial's C4 row suggested. In the trial
the script appeared only in the name, and the Inter headlines did look like the neutral first cut. With the script
on the six "you" phrases, each of the film's key frames has one hand-written lavender phrase against plain heavy
type, and the idea behind it (the plain voice is Deckie, the handwriting is you) does work that a headline face
alone could not. Two honest limits: the frames with no "you" phrase (the pitch fader, the dictionary, the Desk step)
are plain Inter and depend on the stamps, the label and the screens for their character; and Pacifico is a very
widely used face, so the character comes from how it is used here, not from the face being unusual. I would not
reopen the headline face. If anything were revisited it would be swapping Pacifico for a less familiar script with
the same weight, keeping the rule.

**What this means for the nautical reference.** The stencil is gone, so the type no longer nods to the name. The
only reference left is the page's footer line, "Deckie, as in deckhand", still listed for the owner below.

**The domain.** deckie.io, owned by the owner and on his host. The page now carries it as its canonical address and
in its sharing tags (title, description, poster image, the fifteen-second clip), and prints it in the footer; the
film prints "deckie.io" on the name card at 14 s, so the fifteen-second clip ends with somewhere to go, and beside
"Help us beta test" on the end card. Nothing has been deployed, and D9's attorney review still stands ahead of a
public launch.

**Fonts shipped.** `site/fonts/` now holds Inter and Pacifico with their licence files (`LICENSE-Inter.txt`,
`LICENSE-Pacifico.txt`), both SIL Open Font License 1.1; Stardos Stencil and its licence file were removed. The
stencil version of the film's source is not kept in the repository; the type-trial sheets show its frames.

## 7c. Round five (Nov 12): copy in between, three script words, and the words written on screen

The owner's words on the 60-second film in its final type: "Copy wise it went a little far. Lets go somewhere in
between the first video and this version. Pacifico for "you" your" "Deckie". Also, when doable please have the
Pacifico words draw in. Have the agent decide how to draw each word that is chosen once rewritten, what strokes are
needed in what order."

Three things followed: a third cut of the copy (76 seconds), a simpler script rule that replaces the one in 7b, and
the script words written on screen stroke by stroke. Everything he had not reversed was kept: the first fifteen
seconds standing alone, what it is and is not in the research's words, Inter ExtraBold headlines, no voice, the demo
crate file, deckie.io on the name card and the end card.

### The third storyboard, with the reason for each line

The plan is `site/film/shotlist.md`; the film is `site/film/film.js`. The second cut's source is kept in
`site/film/v2/`, the first in `site/film/v1/`. Words set in the script are shown *like this*.

| Time | On screen | Words | Why |
|---|---|---|---|
| 0 to 4 s | Type; two turning platters | "CDJs. Turntables. The house decks." then "None of them know *your* music." | Unchanged. It names the audience by their gear |
| 4 to 9 s | The booth, a song named, picks listed | "*Deckie* knows *your* crate. A booth companion on an iPad, listening beside the decks." then "It names the song, reads the pitch fader, shows what could come next." | Unchanged. What it is, in the spec's three verbs |
| 9 to 12 s | Type only | "Not an AI DJ." "No sync button." "It suggests. *You* mix." | Unchanged. What it is not, before the name |
| 12 to 16 s | The name being written | "*Deckie*. DJ booth companion." Stamp "COMING SOON"; "deckie.io" | Unchanged in content; the name is now written, not raised. Closes the fifteen seconds |
| 16 to 21 s | Desk's table; the crate-file label filling in | "1/3, Deckie Desk, on your Mac. Desk reads *your* crate and writes a crate file. Edits, bootlegs and burned CDs included." | Unchanged |
| 21 to 25 s | Desk's table with its Discs panel, the camera moving onto the panel | "Sort it into discs and folders. In the order your player shows them." | **Back from the first cut.** It is the reason the booth can say "disc, folder and track, as on your player" a few shots later, which is the thing a CD DJ most needs to see; without it that line is a claim with nothing behind it |
| 25 to 28 s | The tag travels from Desk to the iPad | "2/3. Send the crate file to *your* iPad. AirDrop, iCloud Drive or Files. No server." | "The crate file" is named again (the second cut said "it", two shots after the file was last named), and "No server" is back from the page |
| 28 to 31 s | The booth: "Listening…" | "3/3, Deckie, on your iPad. Put it by the decks. Play. A song shows up after a few seconds of music." | Unchanged |
| 31 to 34 s | The song appears at 31 s | "It names the song from *your* crate. Disc, folder and track, as on your player." | Unchanged |
| 34 to 38 s | Push in on the playing panel; outlines on "deck +3.0%" and "128 BPM" | "It reads the pitch fader. This deck runs 3 percent fast, so the tempo reads 128 BPM." | Unchanged |
| 38 to 41 s | The picks | "What could come next, best first." | Unchanged |
| 41 to 45 s | One pick; outline on its tempo, pitch and move | "Where to set the pitch. How *you* could bring it in. Every pick says both, on one line." | **Split back out.** The second cut gave this and the wave one caption and six seconds; a DJ reading it had two outlines and two ideas at once |
| 45 to 48 s | The same pick; outline on its wave | "The wave shows the transition. The end of this song over the start of that one." | **Back as its own shot**, three seconds. "Transition" is voice.md's word for the thing between two tracks; "join" is not used |
| 48 to 52 s | Shuffle goes to 60 percent at 49 s | "Turn up Shuffle for less obvious picks. At zero they stay in score order." | **The second line is back.** Without it "Shuffle" reads as random; with it a DJ sees the order is theirs to set |
| 52 to 55 s | A pick becomes NEXT at 53 s | "Pin the one *you* want." | Its own shot again, three seconds |
| 55 to 59 s | The list scrolls to More; the search fills at 57 s | "Or search the rest of *your* crate. More lists every other song, by score." | **Back from the first cut.** The picks are a shortlist; this is the answer to "what if the record I want is not on it" |
| 59 to 64 s | The dictionary entry "Echo out"; then its three columns | "The dictionary. The third part: every word Deckie uses, said three ways." "Plain words." "The DJ's word." "What *Deckie* does with it." | One second longer on the opening view, and the first cut's fuller line under it |
| 64 to 68 s | Type only | "*Your* music never leaves *your* devices." "No account. No upload." "Works with no signal." | Unchanged |
| 68 to 76 s | The name being written, the booth beside it | "*Deckie*. DJ booth companion." "COMING SOON", "Help us beta test", "deckie.io" | Unchanged in content |

### What came back from the first cut, and what stayed cut

| From the first cut | In the third cut? | Why |
|---|---|---|
| Discs and folders in Desk | Back, 4 s | It is what makes "as on your player" true, and it shows Desk doing something a DJ would do |
| The pick's line and its wave as two shots | Back, 4 s and 3 s | Two ideas, two outlines; one at a time |
| "At zero the picks stay in score order" | Back, as the Shuffle shot's second line | It says the DJ sets the order |
| Pin as its own shot | Back, 3 s | It was sharing a caption with Shuffle |
| More and the search | Back, 4 s | The way to a record that is not a pick |
| "No server" on the send step | Back | Two words that answer a sceptic |
| The dictionary's fuller line | Back, as the smaller line | "Every word Deckie uses" says what the dictionary is for |
| The separate "three parts" scene | Stays cut | The three parts are labelled where each is used; a scene of three thumbnails explained nothing |
| The import log | Stays cut | Housekeeping. On neither the film nor the page |
| "Tempo, key, bars, style, fingerprints" as a caption | Stays cut | The label's own lettering says it |
| Simple and Full | Stays cut | A setting |
| The dictionary being typed into | Stays cut | Watching typing explains nothing |
| "It works from your own crate. Your music stays on your devices." at second 9 | Stays cut | Said once, at 64 s |

The three cuts side by side [measured, counted from the three film.js files]: 84 seconds, 19 captions, about 300
words on screen; 60 seconds, 14 captions, about 230 words; 76 seconds, 18 captions, about 285 words. The third cut
is longer than the midpoint in time because the shots that came back are ones where the screen has to be seen
doing something; in words it sits nearer the first cut than the second, and no line in it is said twice.

### The script rule (replaces the rule in 7b)

Pacifico is used for exactly three words wherever they stand in headline copy: **"you"**, **"your"** and
**"Deckie"**. The single word only, never the phrase around it.

How the edges were settled, each the same way everywhere:

- **Capitals count.** "You" and "Your" at the start of a sentence are the same words.
- **Only the exact words.** "yours", "you're", "yourself" and "you'll" are different words and stay in Inter. None
  occurs in a headline today; the page's "Yours." is a bold lead-in inside a list, not a heading.
- **Every "your" in a headline, whether or not it is the point of the line.** "Send the crate file to *your* iPad"
  is set in script like "None of them know *your* music". The owner's rule names the words, not their weight, and a
  rule that needs a judgment each time would not be applied evenly by the next person to write a headline.
- **Headline copy means**: the film's large lines (the opening, the captions' first lines, the "is not" lines, the
  promise, the name) and the page's headings (h1, h2, h3) and top-bar name. It does not include the film's smaller
  second lines, the small capital labels ("DECKIE DESK · ON YOUR MAC"), stamps, the crate-file label, buttons, or
  body text on the page. So "as on your player" and "Every word Deckie uses" stay in Inter: they are not headlines.
- **"Deckie" inside "Deckie Desk"** is the same word and is set in script in a heading (the page's Desk card).
- **Colour.** "you" and "your" are in the accent colour, which now means one thing: you. "Deckie" takes the colour
  of the line it is in (the warm white), so the name is in its own hand without claiming the accent. On the two lines
  that are in the accent colour throughout ("None of them know your music.", "It suggests. You mix.") the script word
  is told apart by its face alone.
- **Fit.** A lone script word inside an Inter line is set 8 percent larger and 2 percent of the type size lower, with
  a hair of extra space after it; checked on rendered frames at full and at phone size (section 12).

Where the words fall in the film: *your* at 2.7 s, 4.7 s, 16 s, 25 s, 31 s, 55 s and twice at 64 s; *you* at 11 s
("You"), 41 s and 52 s; *Deckie* at 4 s, 12 s (the name), 63 s and 68 s (the name). On the page: *your* in the
headline and in two "how to use it" steps, *you* in "What it shows you in the booth", *Deckie* in the top bar and in
the two card titles "Deckie Desk" and "Deckie".

### The words written on screen

**How it is done.** Pacifico is a filled outline face, not a pen line, so a word cannot simply be traced. Each word
was rasterised once in the film's own browser at 360 pixels. Its centreline was found (a skeleton of the filled
shape), and a pen path was planned along that centreline by hand: which way each letter is entered, where the pen
retraces a line it has already drawn, where it lifts. For every pixel of the word, the moment the pen passes nearest
to it was stored in an image (a "time map"). The film shows a pixel once the pen has passed it. So a half-written
word shows exactly the part of the real letterforms the pen has covered, at full stroke width, and a finished word
is the browser's own rendering of the font with nothing drawn over it. The word's progress is a function of the
beat, so the film is still a pure function of time and renders frame-exact. The plans and maps are in
`site/film/words/` (`strokes.py` holds the paths; `words.json` the timings).

**The strokes, word by word.** Shares are of the word's own writing time.

| Word | Stroke | Path | Share | Why this way |
|---|---|---|---|---|
| Deckie | 1 | The D's stem, top to foot | 5% | A capital D is started with its upright |
| | lift | | 7% | |
| | 2 | The D's bowl: from the flag at top left, over the top, down the right side, back along the foot to the stem | 15% | The second stroke of a written D; it ends where the stem's foot is waiting |
| | lift | | 7% | Pacifico's D does not join the e |
| | 3 | "eckie" in one line. e: in through the eye, round the back, out along the base. c: up its back to the hook, then on from the join along the base. k: up the stem and round the loop from its right side, over the top and back down; the foot; then out along the arm, the knot and the leg. i: up to its top, then on from the join along the base. e: through the eye, round, out to the tail | 57% | These five letters are joined in the face, so the pen does not leave the paper. Where a letter needs the pen to go back down a line it has just drawn (the c's back, the k's stem, the i), that return takes no time, because nothing new appears |
| | lift | | 7% | |
| | 4 | The dot of the i, grown from its centre | 3% | Dots last, as in handwriting |
| you, your | 1 (only) | y: down the left arm, round the bowl, up the right arm; back down into the tail, round its loop (down the right side, up the left) and out. o: anticlockwise from the join, all the way round; then the bar across to the u. u: up to its first top; down, round and up to its second top; then, for "you", down the last stem, or for "your", out along the base to the r. r: up its stem; its foot; over the shoulder to the drop | 100% | The whole word is joined in Pacifico, so it is one stroke with no lift. The o is drawn anticlockwise because that is how a written o goes |
| You, Your | 1 (only) | Y: from the flag at top left, down and round the bowl, up the right arm to its top; back down the stem, into the tail and round its loop; out along the bar to the o. Then o, u and r as above | 100% | Pacifico's capital Y joins its o, so there is no lift here either |

**How long each takes, and why.** At 120 BPM one beat is half a second. A word that takes longer than about a
beat and a half makes its line read late, so only the name is given more.

| Where | Word | Starts | Takes | Reason |
|---|---|---|---|---|
| Opening, "None of them know your music." | your | 2.7 s | 0.55 s | The first script word in the film; slow enough to be seen written |
| "Deckie knows your crate." | Deckie, then your | 4.1 s, 4.75 s | 0.55 s each | Written one after the other, so the pen is in one place at a time |
| "It suggests. You mix." | You | 11.15 s | 0.6 s | The last word before the name; the owner's example |
| Name card | Deckie | 12.0 s | 1.3 s | The one place the writing is the event. The subtitle, the stamp and the address follow at 13.2, 13.7 and 14.2 s, so the card is complete before 15 s |
| "It names the song from your crate." | your | 31.1 s | 0.45 s | The differentiator, so a little slower than the routine ones |
| "Pin the one you want." | you | 52.1 s | 0.45 s | The same |
| Routine captions ("Desk reads your crate…", "…to your iPad", "How you could bring it in", "…of your crate", "What Deckie does with it") | your, you, Deckie | 0.1 s after the caption | 0.35 s | A flick of the pen. See below |
| "Your music never leaves your devices." | Your, then your | 64.1 s, 64.9 s | 0.55 s each | One after the other |
| End card | Deckie | 68.0 s | 1.1 s | A little quicker than the first time |

**When the same word comes round again.** "your" appears eight times. Writing each one out at the pace of the first
would turn a nice moment into a wait. Leaving the later ones static would make the film inconsistent, and the owner
asked for the words to draw in. So every script word is written, but the routine ones take 0.35 seconds, about as long as the caption's own
lines take to settle, and read as a flick; the slower writing is kept for the
places where the word is the point.

**The first fifteen seconds** have four draws in them (your, Deckie and your, You, the name). Every one is finished
before its line is replaced, and the name card holds complete for the last second and a half; the clip was checked
frame by frame (section 12).

**On the page.** The true stroke-by-stroke writing is not used on the page. Doing it there would mean replacing
real, selectable heading text with a drawn picture, loading the maps, and running script before the headline can be
read, on a page whose first job is to load fast and read plainly. Instead each script word is wiped in from left to
right, once, the first time its heading comes into view: 0.6 seconds for "you" and "your", 0.9 for "Deckie". It is
an approximation of writing, not the strokes. It is skipped entirely for visitors who ask for reduced motion, and a
word is only hidden once its heading is being watched for, so with no script, or if anything fails, every word is
simply there. Checked four ways: normal, phone width, reduced motion, script off (section 12).

**Nothing was left static for being undoable.** All five word forms draw cleanly. Two small imperfections, visible
only in a paused frame: where the pen crosses a line it has already drawn (the eye of the e, the loop of the k and
of the y), a few pixels at the crossing appear with the first pass and not the second; and the leading edge of the
stroke is a soft band, not a pen-shaped tip.

## 7d. Round six (Nov 12): copy and header refinement

The owner on the third cut: "this is looking good! Stroke animations look good". Then six notes, verbatim:

- ":10 - "not an AI DJ" begs the question if it is. "No sync button" what does that mean? This whole screen could be
  rewritten"
- ":15 (and other places) - I don't like the "coming soon" treatment in the box. Remove that treatment throughout.
  This frame doesn't need coming soon. can keep it at the end."
- ":16 (and other places) - Refine the header. spacing between the 1/3 is off. Does it need "/3" at all? Also for
  each section explination the header needs to appear int he same place. It keeps jumping up and down but small
  movements."
- "1:07 make it "Your music your mix""
- "Overall lets use sentence case for subheads"
- "Needs a copy refinement too. ex. "DJ booth companion". Wasn't this determined? What are the three platforms?
  Deckie (or Deckie Deck?)."

He then settled the copy in conversation with the coordinating session: "Lets simplify it to - Know the beat. Nail
the mix."; "I like "Know Your Crate" as the final tagline. We can test this with DJs but for now."; "We keep "your
music your mix" at 1:07"; and, on the label's stamp, "Is the "NO AUDIO" necessary?" The film is still 76 seconds;
its source is `site/film/film.js`, with the third cut kept in `site/film/v3/`. The writing of the script words is
unchanged in technique.

### Each change, and its reason

| Where | Was | Now | Reason |
|---|---|---|---|
| 9 to 12 s | "Not an AI DJ." "No sync button." "It suggests. You mix." | "Know the beat." "Nail the mix." | His words. A denial raises the question it denies, and "sync button" needed explaining. The new lines say what a DJ gets, in two beats. "AI" is now nowhere in the film or on the page, which is also voice.md's rule; the exception argued for in section 5 is withdrawn |
| 12 to 16 s, name card | "Deckie. DJ booth companion." boxed "COMING SOON", deckie.io | "Deckie." then "Know your crate." with "your" written in, then deckie.io | The tagline is decided (below). No "coming soon" here, as he asked. The shot before ends "Nail the mix." and this one answers how: know your crate |
| Section headers | A large numeral, "/3", and a small capital label ("DECKIE · ON YOUR IPAD"), placed above a caption block that was centred, so it moved whenever the caption's line count changed | Three named sections in sentence case, "Deckie Desk, on your Mac", "Deckie Booth, on your iPad", "The dictionary", at one fixed place and size; the headline under it also starts at one fixed line | His note. The count is gone (it also clashed with "the third part"). The jump he saw was the centring: measured below |
| The send step | Its own numbered step, "2/3" | A caption under "Deckie Desk, on your Mac" | It is something Desk's side does; three sections, not three steps plus parts |
| The iPad app's name | "Deckie", "Deckie, on your iPad" | "Deckie Booth" | Decided Oct 29: Deckie is the whole product, Deckie Desk the Mac app, Deckie Booth the iPad app. Deckie Pocket (iPhone) is a name only and is not in the film or on the page |
| Boxed stamps | "COMING SOON" (twice), "NO AUDIO" on the crate-file label | None. The end card says "Coming soon." in plain heavy type, in the muted colour, under the tagline | He disliked the treatment "throughout", and "NO AUDIO" was the same treatment |
| "No audio" | A stamp on the label, and on the travelling tag | One plain sentence in shot 5's smaller line: "Edits, bootlegs and burned CDs included. No audio goes in the file." | The stamp was not necessary; the fact still is, once, where the crate file is introduced. It fits as the second sentence of that line (three short lines at caption size). The promise at 1:07 carries the rest |
| Crate-file label | Capitals: "FRIDAY NIGHT", "CRATE FILE", "TEMPO KEY BARS STYLE FINGERPRINTS" | Sentence case: "Friday night", "Crate file", "Tempo Key Bars Style Fingerprints"; the box is shorter now the stamp is gone | Sentence case for everything that is ours. Capitals inside the captured app screens are the app's and stay |
| 16 to 21 s, smaller line | "A booth companion on an iPad, listening beside the decks." (at 4 s) | "It listens from an iPad beside the decks." | "Booth companion" is no longer on screen anywhere (below) |
| 21 to 25 s | "Sort it into discs and folders." | "Sort your crate into discs and folders." | "It" pointed at the crate file of the line before; what is sorted is the crate |
| 28 s | "Put it by the decks. Play." | "Put the iPad by the decks. Play." | "It" had no clear owner after the section change |
| 59 s | "The dictionary." as headline, with a line under it | "The dictionary" is the section header; the headline is "Every word, said three ways." | The header now does the naming |
| 64 to 68 s (1:07) | "Your music never leaves your devices." "No account. No upload." "Works with no signal." as three headlines | "Your music" / "Your mix" on two lines, both "Your"s written in; beneath, smaller: "It never leaves your devices." "No account. No upload. Works with no signal." | His line. He typed it without punctuation; two lines with no full stops avoids choosing a comma or a full stop for him, and reads as a pair. The privacy promise stays, as he agreed, in the smaller lines |
| End card | Name, "DJ booth companion", boxed "COMING SOON", button, deckie.io | Name, "Know your crate.", "Coming soon.", "Help us beta test", deckie.io | As above |

### The tagline

voice.md listed four candidates for "the tagline and the store line": "Know your crate.", "Your crate, mixed.",
"Next record, your crate.", "Everything your crate can tell you.", and said "the descriptive subtitle "DJ booth
companion" stays for search". Proposal P8 had the store name as "Deckie: DJ Booth Companion". So "DJ booth
companion" was only ever the descriptive subtitle; the earlier cuts used it on screen because no tagline had been
picked. On Nov 12 the owner chose "Know your crate", for now, to be tested with DJs. It is set in sentence case with
a full stop, as voice.md wrote it: "Know your crate.", with "your" in the script and written in. It is under the
name on the name card and the end card, beside the name in the page's top bar, in the page's footer and in its
sharing title. "DJ booth companion" remains in the page's title and description, for search, and nowhere on screen.

### The script rule, one addition

Section headers are subheads, not headline copy, so they are set in Inter throughout: no script "your" in "on your
Mac", no script "Deckie" in "Deckie Desk". And "Deckie" is set in the script only where it stands as the product's
own name ("Deckie knows your crate.", "What Deckie does with it.", the name cards), never inside the app names
Deckie Desk and Deckie Booth, which are names of their own. The page follows: its card titles "Deckie Desk" and
"Deckie Booth" are Inter. Newly written instances this round use the existing stroke plans with new timings: the
tagline's "your" takes 0.5 s (from 13.3 s and from 69.3 s), and the two "Your"s at 1:04 take 0.55 s each, the second
starting a second after the first (64.1 s and 65.1 s).

### The header, measured

Measured on lossless frames rendered from the film at 22 moments across all three sections, including frames in the
middle of a change of caption (20.9, 21.05, 24.9, 25.1, 30.95, 31.1, 40.9, 41.1 and 58.9 s) [measured]:

| Header | Left edge | Top of letters | Bottom of letters | Frames measured |
|---|---|---|---|---|
| Deckie Desk, on your Mac | x = 98 | y = 287 | y = 331 | 7, all identical |
| Deckie Booth, on your iPad | x = 98 | y = 287 | y = 331 (330 in one frame, as it begins to fade at 58.9 s) | 13 |
| The dictionary | x = 97 | y = 287 | y = 331 | 2, identical |

The one-pixel difference in the left edge is the shape of the letter T against a D, not a move. The header's
baseline is y = 322 and its size 44 px in every shot; it fades in where it stands and does not rise into place. The
headline's first line sits on y = 428 in every settled frame measured (its letters' bottom edge reads 428, or 439
where the line has a descender). In the third cut the block under the header was centred on its own height, so by that cut's code the header's
baseline sat anywhere from about y = 330 (three headline lines and two smaller ones) to about y = 436 (two
headline lines alone) [inf, worked out from the code, not measured on frames].

### The page

The same changes: the tagline beside the name; "Coming soon" as plain accent-coloured type above the headline and in
the beta box, no box; the iPad app called Deckie Booth; small labels ("On your Mac", "Plain", "DJ", "Deckie") in
sentence case; and the "It isn't" list rewritten without "AI" or "sync button": "It doesn't play or mix.", "It
doesn't beatmatch for you.", "It doesn't look up what you play.", "Not a DJ app or a library manager.", "Not for
everyone." The line about training a model is now "what you play stays with you".

## 7e. Round seven (Nov 12): larger written headers, the tagline in title case, and line breaks

The owner's words, verbatim: "Agree with all your notes. * Make the headers a bit larger * use "Know Your Crate" *
booth screen is fine for now. Also, Deckie Desk and Deckie Booth should be Pacifica and drawn in. Also in headers
should be white. "your" on "on your mac" is fine not in script. Change "It listens from an iPad beside the decks."
to "It listens beside the decks" or "in your booth" maybe "hear" - it hears whats playing. Open to suggestions.
Watch line breaks :5, :17, :23, :27, :33, :57 all have lines with orphan words. it should be a few words and if its
the beginning of a sentence no single words on the previous line. There are some design best practices for this."

The film is still 76 seconds (`site/film/film.js`; the fourth cut is kept in `site/film/v4/`).

### Each change, and its reason

| Where | Was | Now | Reason |
|---|---|---|---|
| Section headers | 44 px, muted, Inter throughout | 48 px Inter in the headline white; the app name before the comma, "Deckie Desk" or "Deckie Booth", set whole in Pacifico at 60 px and written on screen | His note. This overrules the round-six ruling that "Deckie" stays in Inter inside the app names. The script is set larger than the Inter beside it because at this size it needs the extra to carry the same weight. "The dictionary" stays in Inter (he named the two apps), white, at the same size |
| When the header's name is written | (not written) | Once, as the section opens: "Deckie" over 0.6 s, then "Desk" or "Booth" over 0.45 s, then ", on your Mac" fades in where it stands. It then holds still for the whole section | Written again at every shot it would be a tic, and it would fight the headline's own written words; once marks the change of section, which is the header's job |
| ", on your Mac" / ", on your iPad" | Inter | Inter, "your" not in script | His note; headers remain outside the "you / your" rule |
| Tagline | "Know your crate." | "Know Your Crate", title case, no full stop, "Your" written in | He has typed it this way each time. It is a tagline, not a subhead, so the sentence-case rule does not reach it; he typed no full stop and a title-case line does not want one |
| 4 to 6 s, smaller line | "It listens from an iPad beside the decks." | "It hears what’s playing." | Short, it says how Deckie knows, and it leads into "It names the song…". The fallback, if he prefers the place to be stated, is "It listens beside the decks."; his other offer was "in your booth" |
| The booth screen's own labels ("Deck", "CDs") | | Left | "booth screen is fine for now" |
| Line breaks | Headlines broken by hand; smaller lines wrapped by width | Every line in the film broken by hand to the rule below | His note |

### The line-break rule, and where it comes from

The rule, as he put it and as it is now applied to every block of words in the film and every heading on the page:

1. No line of a single word, anywhere in a block, the last line included.
2. Each line carries a few words, and the lines of a block are of roughly even length.
3. A new sentence inside a block starts a line; its first word is never left alone at the end of the line before.
4. Lines break at the joins of phrases: after punctuation, before a conjunction or a preposition. An article stays
   with its noun, a preposition with its object, an adjective with its noun, and names and terms are never split
   ("Deckie Desk", "crate file", "pitch fader").

Sources. Subtitling has the most worked-out version of this, because a caption is read once, quickly, and cannot
be re-read. Netflix's Timed Text Style Guide says a line should be broken "after punctuation marks", "before
conjunctions" and "before prepositions", and that a break should not separate "a noun from an article", "a noun
from an adjective", "a first name from a last name", "a verb from a subject pronoun", "a prepositional verb from
its preposition" or "a verb from an auxiliary, reflexive pronoun or negation" [9]. On the page, the browser's own
controls are used: `text-wrap: balance` for headings ("best balances the number of characters on each line") and
`text-wrap: pretty` for running text, which exists for the case "when the number of orphans should be kept to a
minimum" [10]; non-breaking spaces hold names and the last two words of a block together where those are not
enough. In print the short last line is called a widow or an orphan; I did not fetch a typography source for
that term and use only the two above.

Before and after, for every block that was re-broken (a slash marks a line break):

| Time | Before | After | What was wrong |
|---|---|---|---|
| 6.5 s (his :05) | It names the song, / reads the pitch / fader, shows what / could come next. | It names the song, / reads the pitch, / shows what could / come next. | "pitch / fader" split a term. **Reworded**: "the pitch fader" became "the pitch" here, which is what DJs call the setting; the full term comes at 34 s. "reads the pitch fader," does not fit the column on one line |
| 16 s (his :17) | Desk reads your / crate and writes / a crate file. | Desk reads / your crate / and writes / a crate file. | "your / crate" split a possessive from its noun |
| 16 s, smaller | Edits, bootlegs and burned CDs / included. No audio goes in the / file. | Edits, bootlegs and burned CDs too. / No audio goes in the file. | A one-word last line, and a sentence starting mid-line. **Reworded**: "included" became "too" |
| 21 s (his :23) | Sort your crate / into discs and / folders. | Sort your crate / into discs / and folders. | One-word last line |
| 21 s, smaller | In the order your player shows / them. | In the order / your player shows them. | One-word last line |
| 25 s (his :27) | Send the crate / file to your iPad. | Send the file / to your iPad. | "crate / file" split a term. **Reworded**: "the crate file" became "the file"; it is named in full in the two lines before it, and "Send the crate file" does not fit the column on one line |
| 25 s, smaller | AirDrop, iCloud Drive or Files. No / server. | AirDrop, iCloud Drive or Files. / No server. | A sentence's first word alone at the end of a line; one-word last line |
| 28 s | Put the iPad by / the decks. Play. | Put the iPad / by the decks / and press play. | "by / the decks" split a preposition from its object, and "Play." was a one-word sentence tacked on. **Reworded** to one sentence |
| 28 s, smaller | A song shows up after a few / seconds of music. | A song shows up / after a few seconds of music. | "a few / seconds" |
| 31 s (his :33), smaller | Disc, folder and track, as on your / player. | Disc, folder and track, / as on your player. | One-word last line |
| 34 s, smaller | This deck runs 3 percent fast, so / the tempo reads 128 BPM. | This deck runs 3 percent fast, / so the tempo reads 128 BPM. | Conjunction left at the end of a line |
| 38 s | What could come / next, best first. | What could / come next, / best first. | "come / next" |
| 41 s | Where to set the / pitch. How you / could bring it in. | Where to set / the pitch. / How you could / bring it in. | "the / pitch"; a sentence starting mid-line |
| 45 s, smaller | The end of this song over the / start of that one. | The end of this song / over the start of that one. | "the / start" |
| 48 s | Turn up Shuffle / for less obvious / picks. | Turn up Shuffle / for less / obvious picks. | One-word last line |
| 55 s (his :57), smaller | More lists every other song, by / score. | More lists every other song, / by score. | One-word last line |
| 59 s | Every word, said / three ways. | Every word, / said three ways. | Break moved to the comma |

Left as they were, having been checked: "Deckie knows / your crate.", "It names the song / from your crate.", "It
reads the / pitch fader.", "The wave shows / the transition.", "Pin the one / you want.", "Or search the rest / of
your crate.", "What Deckie / does with it.", "Know the beat. / Nail the mix.", "Your music / Your mix", and the
single-line blocks. **One exception, kept on purpose and flagged for him:** the opening, "CDJs." / "Turntables." /
"The house decks.", has two lines of one word. They are three separate things arriving one to a beat, a list and
not a broken sentence, and he did not mark the opening; if the rule is to have no exception, the fix is one line,
"CDJs. Turntables." over "The house decks."

On the page the same rule was checked by a script that finds every line of every heading, paragraph and list item
at 1440 and 390 pixels wide and reports any line holding one word: none remain at either width [measured]. Two
things were reworded to get there: the bold lead-in "Yours." became "It stays yours.", and the step "Open Deckie
Booth, put the iPad by the decks and play" became "…and press play".

### New stroke plans: "Desk" and "Booth"

Made the same way as the others (`site/film/words/strokes.py`). Shares are of the word's own writing time.

| Word | Stroke | Path | Share | Why this way |
|---|---|---|---|---|
| Desk | 1 | The D's stem, top to foot | 7% | As in "Deckie" |
| | lift | | 7% | |
| | 2 | The D's bowl, from the flag at top left round to the foot | 21% | As in "Deckie" |
| | lift | | 7% | The D does not join the e |
| | 3 | "esk" in one line. e: in through the eye, round and out along the base, rising into the s. s: up to its top; then down its back; the tail out to the left; then on from the turn along the base to the k. k: up the stem, round the loop and back down; the foot; then the arm, the knot and the leg | 58% | The three letters are joined in the face. Where the pen returns along a line it has drawn (the s's top, its tail, the k's stem) the return takes no time |
| Booth | 1 | The B's stem, top to foot | 5% | A capital B starts with its upright |
| | lift | | 7% | |
| | 2 | The B's upper bowl from the flag at top left, over and in to the waist; the short bar at the waist; then the lower bowl, round and back along the foot to the stem | 18% | The two bowls are one movement in handwriting |
| | lift | | 7% | The B does not join the o |
| | 3 | "ooth" in one line. First o: from its top, anticlockwise, all the way round; the bar across. Second o: anticlockwise from the join; the bar across to the t. t: up the stem, round its loop and back; down, round the foot and across to the h. h: up the stem, round the loop and back down; the foot; then the arch and down | 54% | Joined in the face |
| | lift | | 7% | |
| | 4 | The t's crossbar, left to right | 3% | Crossbars last, as in handwriting |

Timing: in each header "Deckie" takes 0.6 s and "Desk" or "Booth" 0.45 s, starting as the section opens (16.05 s
and 28.05 s). On the page the two app names are set in Pacifico in the card titles and in the third "how to use it"
step, and are wiped in like the other script words.

### The header, measured again

Measured on lossless frames at 22 moments across the three sections, including frames part-way through a change of
caption (20.95, 21.1, 24.95, 25.1, 30.95, 31.1, 40.95, 41.1 and 58.9 s) [measured]:

| Header | Left | Right | Top | Bottom | Frames |
|---|---|---|---|---|---|
| Deckie Desk, on your Mac | x = 99 | x = 712 | y = 266 | y = 331 | 7, all identical |
| Deckie Booth, on your iPad | x = 99 | x = 737 | y = 266 | y = 331 | 13, all identical |
| The dictionary | x = 97 | x = 424 | y = 284 | y = 331 | 2, identical |

The baseline is y = 322 for all three, as in round six. The bottom reading of 331 is the comma (and, in "The
dictionary", the tail of the y) below the baseline; the script names have no descenders, so they sit on 322. The top
is higher for the two app names (266 against 284) because the script's k and h are taller than Inter's capitals;
that is the letters' height, not a move. The longer header ends 23 pixels short of the screen card at x = 760. The
headline's first line moved down by 12 pixels, to y = 440 in every shot, to give the taller header room.

### The page

The headline is now the tagline, "Know Your Crate", with "Your" in the script. The old headline's thought moved into
the line under it: "For decks that don't know your music. Deckie sits on an iPad beside them, names the song, reads
the pitch fader and shows what could come next. You do the mixing." The tagline no longer sits beside the name in
the top bar, so the first screen says it once; it appears again only in the footer.

## 7f. Round eight (Nov 12): the header's qualifier, and three soundtracks to choose from

The owner's words, verbatim: "Headlines, make the "on you..." smaller and grey. Watch the padding next to the
screengrabs. If it needs to drop to two lines thats fine. Music - Make it a little dancier (house) or scratchier.
More true to the audience. At :15 in particular it starts feeling very stock. This should be DJ influenced. even the
dings are ehh. Its nice that there are auditory notes but dings might not be it. Id like to hear 3 variations."

Picture and copy are otherwise approved ("Almost there!"). The picture below is in every file; the sound is not yet
chosen, so `site/assets/deckie-explainer.mp4` keeps the sound it had and the three new ones are separate files.

### The header

| | Was | Now |
|---|---|---|
| App name | Pacifico, white, 60 px, written in | Unchanged |
| Qualifier | ", on your Mac" in white Inter at 48 px | "on your Mac" in grey Inter at 34 px, no comma, on the same line and baseline |
| "The dictionary" | White Inter, 48 px | Unchanged: it is the name, and has no qualifier |

One line was kept. With the qualifier smaller the longer header is 552 pixels wide, so it does not need a second
line, and a second line would have pushed every headline down. Measured on frames from the finished picture at 17
moments [measured]:

| Header | Left | Right | Top | Bottom | Gap to the screen card (x = 760) |
|---|---|---|---|---|---|
| Deckie Desk on your Mac | 99 | 626 | 266 | 328 | 134 px (was 48) |
| Deckie Booth on your iPad | 99 | 651 | 266 | 328 | 109 px (was 23) |
| The dictionary | 97 | 424 | 284 | 331 | 336 px |

Identical in every frame of each section; the baseline is still y = 322 (the bottom reads 328 now that the comma is
gone). The same gap was measured for every caption block. Three blocks were re-broken to open it up: "Edits,
bootlegs / and burned CDs too. / No audio goes in the file." (its widest line had ended 48 px from the card), "Or
search / the rest / of your crate." and "It names the song, / reads the pitch, / and shows what / could come next."
The narrowest gap anywhere is now 63 px, beside "It names the song," at 6.5 s; every other block clears the card by
83 px or more. The page already sets "On your Mac" and "On your iPad, in the booth" small and grey above the script
names, so it needed no change.

### What was wrong with the sound, and the brief for three

The sound until now ("0, current, bells") is a tidy synthesised bed with bell, pop and tick accents: explainer
music. He asked for something this audience would play or hear in a booth, called out the beat's entry at 16 s as
"very stock", and liked that steps are marked by sound but not the "dings". So each variation had to: sound like a
DJ's music; make the 16-second entry a DJ's move, a different one in each; mark the picture's 42 accents with sounds
from a booth, played into the track on the grid; and, where it costs nothing, do what the picture is saying.

All three are 120 BPM, the film's own grid, so no picture timing changed. Everything is synthesised by
`site/film/sound/score.py` from oscillators and noise: no samples, no recordings, no third-party sounds, nothing
from anyone's music, and no figure taken from a known record (the chords are a plain A minor, F, D minor, E minor
round; the bass lines follow the roots). The scratch sounds are made the way a scratch is made: a two-second
sound (a made "ahh": a saw chord and noise through three vowel-like filters) is read back at whatever speed and
direction a hand-position curve says, so its pitch rises and falls with the hand, and a second curve opens and shuts
the fader. A rewind is the last two seconds of the track itself played backwards with the platter speeding up; a
platter stop is the track slowing to nothing. I did not look up how house grooves or scratches are built for this;
the designs rest on general knowledge of both, and no source is cited because none was used.

**A. House.** Four-on-the-floor kick, a clap with a snare under it on two and four, an open hat on every off-beat,
swung closed hats, a rolling off-beat bass with an octave lift, and chord stabs off the beat, all ducking to the kick.
The first sixteen seconds are that groove heard through a closed filter that opens bar by bar, a clap fill, and the
drop on the one at 16 s with the bass arriving. The accents are percussion inside the groove: congas tuned low to high
for lists of three (the opening's three nouns, the label's five words, the dictionary's three columns), a rimshot for
a single point, a clap for emphasis, a hat roll when Shuffle moves, a shaker when the crate file travels. The kick
drops out for the dictionary and the end card comes back in full. Why for working DJs: it is the plainest statement
of the thing most of them play, and nothing in it sounds like a notification.

**B. Scratch.** A broken beat (kick on one, a pushed kick, snare on two and four) with a short funk bass and vinyl
crackle throughout, starting with the needle going down. The accents are scratches and cuts: a quick forward push
for a single point, a forward-and-back "baby" for a headline, a chirp (fader shut at the turn) in pairs, a
fader-chopped drag under the name, a three-push tear when Shuffle moves, and at the pitch-fader shot a push that
slows so its pitch falls. Sections change on a rewind: the track spins back for half a second and the beat lands on
the one, which is how the beat enters at 16 s. "Your music / Your mix" is two scratches over hats, and the film ends
with the record being stopped. Why for working DJs: it is the sound of hands on a record, which is what the film's
last word, "You mix", is about; and it is the furthest from stock.

**C. Jackin'.** A rawer house groove: heavier clap, harder swing, rimshots and a shaker off the beat, short organ
stabs for both bass and chords. The sections change on DJ moves and the sound does what the picture says. The entry:
the drums play low-passed, the lows are then pulled out bar by bar, there is one beat of nothing, and the full groove
is cut in on the one at 16 s. Into Deckie Booth the lows come out for two beats and return on the one. At the
pitch-fader shot the chords are nudged up three percent for a bar. At the wave shot ("The wave shows the
transition") a second groove is blended in over five beats and the bass is swapped at the phrase. Into the
dictionary, whose entry on screen is "Echo out", the track is echoed out. "Your music / Your mix" plays through a
filter that opens into the end card, and the film goes out on an echo. The accents are a cue-button click with a
short filter blip. Why for working DJs: every transition in it is a move they make, in the order the film talks
about them.

**The accents, by kind.**

| Picture | A, House | B, Scratch | C, Jackin' |
|---|---|---|---|
| A single point (most captions) | Rimshot, or conga with a rim | One forward push | Cue click and filter blip |
| A list of three or five | Congas, low to high | Pushes, each longer (higher) | Blips, each higher |
| A headline or the name | Clap, or kick and stab | Baby scratch; a chopped drag under the name | Kick and organ stab |
| The beat's entry, 16 s | Filter opens, clap fill, drop | Rewind, beat on the one | Lows out, one beat silent, cut in |
| Deckie Booth, 28 s | Open hat and sub on the one | Rewind | Lows out for two beats, back on the one |
| Pitch fader, 34 s | Conga | A push that slows: the pitch falls | Chords nudged up 3 percent for a bar |
| The wave, 45 s | Conga | Chopped drag | A second groove blended in; bass swapped |
| Shuffle moves, 49 s | Hat roll | Tear | Click roll and a rising blip |
| The dictionary, 59 s | Open hat; the kick drops out | Rewind; drums alone | Echo out |
| End | Final stab, echo tail | The record is stopped | Echo out |

### What could be measured, since none of this was heard

Neither I nor the session coordinating this can listen. Each soundtrack was measured instead; the pictures are in
`site/film/sound/` (`sound-A.png`, `sound-B.png`, `sound-C.png`, and `sound-0-current-bells.png` for comparison):
a spectrogram with the section entries and the 42 accents marked, and the level over time.

| | 0, current (bells) | A, House | B, Scratch | C, Jackin' |
|---|---|---|---|---|
| Loudness of the mix | -14.0 LUFS | -14.1 | -14.0 | -14.1 |
| True peak of the mix | -1.2 dBTP | -1.2 | -1.2 | -1.1 |
| Sample peak of the film file after AAC | -1.3 dBFS | -1.2 | -1.0 | -1.2 |
| Accents within 20 ms of a sound onset | 38 of 42 | 41 of 42 | 36 of 42 | 41 of 42 |
| Median distance | 2.0 ms | 4.5 ms | 4.5 ms | 2.0 ms |
| Level step at 16 s (the two seconds after against the two before) | +3.1 dB | +6.9 dB | +4.7 dB | +17.9 dB |
| The same below 150 Hz | +2.9 dB | +6.9 dB | +5.5 dB | +48.7 dB |

Reading it. All three make the entry at 16 s a bigger step than the current sound does; C's is by far the largest
because the lows are removed and then a beat is silent just before it. In all three the one accent the detector
calls late is the very first, at 0.0 s: an onset cannot be detected on the first sample of a file, and the sound is
there (the first 60 ms measure -15 to -20 dB). B's other five are scratches, which begin with a hand speeding up
and not with a click, so the detector places them 23 to 28 ms early; that is the nature of the sound and inside what
an eye and ear take as together. B's film file peaks at -1.0 dBFS after AAC encoding, at the limit asked for and not
under it; if B is chosen its master should come down a quarter of a decibel. The fifteen-second clips measure -17 to
-19 LUFS, because the first fifteen seconds are the quiet part of each track.

What measurement cannot say: whether any of these is good. A spectrogram shows that a kick, a hat and a bass are
where they should be and that nothing clips; it does not show whether the groove moves, whether the made "ahh"
sounds like a scratch or like a toy, or whether the congas are charming or cheap. My own pick, for him to overrule
by ear, is **C**: it has the strongest entry at 16 s, which was his one specific complaint; it is the only one in
which the sound enacts the product (the pitch nudge, the blend and bass swap, the echo out); and its accents are the
cleanest against the picture. Its risk is the cue click and blip, which are the nearest of the three to the "dings"
he disliked. **A** is the safe choice. **B** is the boldest and the likeliest to sound wrong, because a convincing
scratch is the hardest of these sounds to synthesise.

### Files

`site/assets/variations/`: `deckie-explainer-A-house.mp4`, `deckie-explainer-B-scratch.mp4`,
`deckie-explainer-C-jackin.mp4`, each with its fifteen-second clip (`deckie-15s-A-house.mp4` and so on), and
`deckie-explainer-0-current-bells.mp4`, the same picture with the sound it had before, for comparison. The main
file `site/assets/deckie-explainer.mp4` has the new header picture and the current sound until he chooses.

## 7g. Round nine (Nov 12): soundtrack D, in between

The owner, on the three: "Nice! I like the intro of 1 and the later part of 3. They are similar though. Please make
something in between." 1 and 3 are A (house) and C (jackin').

**D, in between.** One record, not two spliced: C's drum kit, swing and organ stabs from the first bar to the last,
with A's way of opening. For the first sixteen seconds that groove, organ included, is heard through a closed filter
that opens bar by bar; the drums stop for a clap fill; and at 16 s the record is simply all the way in, on the one,
with the bass arriving. So the join is a DJ bringing a record in: the same sounds before and after, only the filter
and the bass change. From there it is C's body with every one of its moves: the lows pulled for two beats into
Deckie Booth, the chords nudged up three percent at the pitch-fader shot, a second groove blended in and the bass
swapped at the wave shot, the echo out into the dictionary, the filter under "Your music / Your mix", and out on an
echo.

**The entry at 16 s** is A's drop after the fill, not C's pull-the-lows-and-cut. He named A's intro as the part he
liked, and C's entry needs the beat before it to be empty, which would cut a hole in the filter opening.

**The accents** are A's percussion played in the groove, throughout: congas low to high for lists, a rimshot for a
single point, a clap for emphasis, a hat roll when Shuffle moves, a shaker as the crate file travels. C's cue click
and blip are gone. He called the old dings "ehh", and the click and blip were the nearest thing left to them; a conga
in a house groove is part of the record.

Measured, with the same caveat as before that none of it has been heard:

| | D |
|---|---|
| Loudness of the film's sound | -14.1 LUFS |
| Sample peak of the film file after AAC | -1.6 dBFS (the master was limited a little lower than the others so the encoded file stays under -1) |
| Accents within 20 ms of a sound onset | 41 of 42, median 3.1 ms; the one outside is the very first, at 0.0 s, which no detector can place |
| Level step at 16 s | +6.7 dB overall, +6.9 dB below 150 Hz |
| The fifteen-second clip | Mastered on its own to -14.0 LUFS (it measured -18.4 as a cut of the film), peak -1.1 dBFS |

The picture is in `site/film/sound/sound-D.png`. D is now the sound of `site/assets/deckie-explainer.mp4` and
`deckie-15s.mp4`. A, B, C and the bells version stay in `site/assets/variations/` with the same picture, so he can
still switch; that folder is not part of the upload.

One caption changed with it: "Or search / the rest / of your crate." read choppy on three lines and is back on two,
"Or search the rest / of your crate.", which clears the screen card by 78 px.

## 7h. The site made ready (Nov 12)

The owner: "Then we should be good to put it up on the website. The website needs to have enough info about the
project for an AI to read it and make it look good. I am putting the coming soon website up for a job application. I
also want the website to include the vocabulary as a tab". Later the same day: "Credit: Christopher Shannon and App
Hold Media with a link to AppHold.media." and "Beta button a prefilled email to info@apphold.media"; and the name
is "fine for now".

The test set for the page: a person, or a program reading only the HTML, should come away knowing what Deckie is,
who it is for, what is different, how it works, what exists today, and that it was made with care. Everything is in
visible text. Nothing is hidden, repeated for search, or addressed to a machine.

### What was added

- **Two tabs** in the top bar, Home and Dictionary. The dictionary page (`site/dictionary/`, made by another
  session from `docs/vocabulary/`) reuses the home page's fonts, colours and top bar.
- **"What the film shows, in words"**: thirteen numbered lines under the film, folded by default, so a reader who
  cannot play video has its content. The words are on screen in the film, so there is no captions track.
- **"About the project"**: six short parts. The problem; how it works; what is different; privacy; how it is built;
  where it stands.
- **The credit**, by his instruction the one place a person is named: "Made by Christopher Shannon and App Hold
  Media", the company linked to apphold.media, at the end of "Where it stands" and in the footer.
- **The beta button** opens an email to info@apphold.media with the subject "Deckie beta" and a five-line body
  (what decks, which Mac and iPad, and the real requirements: own music files, a Mac, an iPad). The address is
  also shown as text beside it, for anyone without a mail program set up.
- **For machines**: one h1 and ordered headings; header, nav, main and footer landmarks; alt text on every image; a
  title and description; the canonical address https://deckie.io/; Open Graph and Twitter card tags with absolute
  image addresses; structured data (schema.org SoftwareApplication, with the two apps as parts, the author and the
  publisher; no rating, price or release date, because there is none); a favicon; `robots.txt` allowing everything;
  `sitemap.xml` with the two pages; and `llms.txt`.
- **llms.txt** follows the convention proposed by Jeremy Howard in September 2024 [11]: a Markdown file at the site
  root with the name as its one heading, a summary in a blockquote, plain paragraphs of detail, then lists of links,
  with an "Optional" list for what a reader short of room may skip. Ours has the summary, the project's own words
  (library, crate, crate file; the app names), the status stated exactly, the two pages, and the film as optional.
- **No analytics, no cookies, no requests to any other site.** Fonts are served from the site with their licences.

### Claims in "About the project", with their source

| Claim | Source | Checked here |
|---|---|---|
| For DJs on gear that does not know what is loaded | Research D | Wording from the research |
| Desk writes tempo and beat grid, key, bars and sections, vocals, loudness, style and a fingerprint; no audio | D3, D13; a crate file read here | [measured] earlier (section 10) |
| Booth matches what it hears against the crate file's fingerprints, on the iPad | deck-app README ("fully offline") | [measured] through the file-test path only |
| Pitch read in percent; tempo follows | README; research H | [measured] |
| Every other song scored on tempo within reach, key, vocal-free stretches, loudness and style; best tenth is the shortlist | D18, D19; deck-app README | Scoring inputs from the README; shortlist [measured] on screen |
| Shuffle from score order to a fair shuffle; pin; search | D19 | [measured] |
| Other apps hear a room; Deckie does not claim to be the only one | P7; research D | Wording |
| Names edits, bootlegs, live sets and burned CDs with disc, folder and track | D4; D20 | Disc, folder, track [measured]; a burned CD [unverified] |
| No account, no upload, no server; works with no signal; what is played is not sent anywhere | D3; voice.md | [unverified] here |
| Key as a warning; major against minor the weak part | D17; standing principles | Wording |
| Shared Swift core builds and passes its tests on macOS, Linux and Windows | D14; `.github/workflows/core-linux.yml`, `core-windows.yml` | Workflows exist; not re-run here [unverified today] |
| Core gives the lab's scores on 373 songs and 138,608 pairs | D14 | From the decision log |
| Crate file documented, about 4 KB a song before fingerprints | Note on D13; `docs/architecture/crate-format.md` | From the log |
| Beat This!, YAMNet, ONNX Runtime, ShazamKit; dependencies listed with licences | desk-app README; `DEPENDENCIES.md` | Desk's engine check ran here [measured] |
| 21 decisions; about twenty lettered research notes | `00-decisions.md` (D1 to D21); `docs/research/` (letters A to V with gaps, nineteen files, and two community passes) | Counted |
| Desk builds crate files, renames, sorts into discs and folders | desk-app README; D20 | Build and discs [measured]; renaming from the README |
| Booth names the song, reads pitch, ranks picks, writes down the set | deck-app README | All but the written set [measured] |
| Used for one night behind real decks | Research S | From the research |
| Tested with a crate of 2,327 songs | deck-app README | From the README |
| Not yet: beta, App Store, Windows and Linux Desk, learning how a DJ mixes, the whole fader range from a crate file; some labels still from the first night | D5, D12, P11, P17; deck-app README; section 11 | Labels [measured] |

The page says "ONNX Runtime" and no more. D3's note requires a build of it without usage reporting before anything
reaches a user; that is a rule for release, not a fact about today's builds, so the page does not claim it.

### The folder to upload

`site/build.sh` assembles `site/dist/`: the two pages, the pictures the page uses (resized to the size they are
shown), the film re-encoded for the web (the same 1920 x 1080 at 60 frames a second, 9.5 MB against 18 MB, with the
start of the file arranged so it plays before it has all arrived), the fifteen-second clip, the fonts and their
licences, `robots.txt`, `sitemap.xml`, `llms.txt`, the favicons and an optional `.htaccess` (send to https, the
right types for fonts and video, sensible caching; each block is skipped if the host lacks the module). It leaves
out the film's sources, the variations, the contact sheets and the type trials, checks that every file the home
page points at is in the build, and never deletes: an earlier build is set aside. Twenty files, 13 MB. Nothing was
uploaded.

Checks on the built folder [measured]: one h1; all four images have alt text; no console errors; no request leaves
the site; every link on the home page resolves, the Dictionary tab included; no line of one word in any heading,
paragraph or list item at 1440 or 390 pixels; nothing hidden with reduced motion or with script off. Lighthouse:
accessibility 100, best practices 100, SEO 100, performance 74, measured on this Mac while other work was running,
so the performance figure is a floor. An HTML checker reported only matters of taste (lower-case doctype, inline
styles) and no structural error.

## 7i. Round ten (Nov 12): the site takes its look from Deckie Booth's Simple view

The owner: "Can you have the fable agent use more design language from the simple version of the ipad app? I feel
like it is more rounded edges, more subtle, more negative space, less purple. This should feel much more clean. Feel
free to give it your recommendations on that."

A visual pass only. The copy, the structure, the film and its sound, and the machine-readable files did not change;
the page's outline of headings is the same as in 7h.

### What the Simple view is made of

Read from the app's source (`deck-app/Deck/Sources/Model.swift`, `ListenView.swift`, `SuggestionsView.swift`) and
checked against two captures of the Simple view, at rest and with a song named (`site/film/round10/
app-simple-at-rest.jpg`, `app-simple-song-named.jpg`), with pixel colours sampled from the second [measured].

| In the app | Value | On the site (`site/site.css`) |
|---|---|---|
| The page | `Theme.bg`, #0f0a17, flat. The gradient `Theme.backdrop` exists in the code and is not used by the Listen view | `--bg: #0f0a17`, flat. The purple gradient is gone |
| A pick's card | White at 4.5 percent over the page (it samples as #1a1420), corner radius 16, no outline | `--surface`, `--r-card: 16px`, no border: the dictionary's terms, the pictures' frames |
| The playing panel | The one large tinted surface, radius 24 | `--r-panel: 24px`: the film's frame and the beta panel, the one panel on the page. It is not tinted; "less purple" |
| Buttons and chips | Capsules; white at 7 percent; a chip that is off has a hairline in the dim colour at 40 percent, one that is on is filled with its colour at 28 percent | `--control`, `--r-pill`: buttons, tabs, the "Coming soon" label, the dictionary's chips (on: the accent at 28 percent) |
| The search field | Radius 12, white at 6 percent, a 1 px line in `Theme.line` | `--field`, `--r-field: 12px`, `--hair`: the dictionary's search, the only hairline kept |
| Text | #f2edf9, #ab9fc2 and #76698f | `--tx`, `--mut`, and `--dim` at #8b7fa6: the app's dimmest grey fails the contrast rule for small text on this page (about 3.9 to 1), so the site's is a step lighter |
| Accent | Lavender #b490ff for the playing panel's tint and the disc colour; orange for "pinned" and the prominent button | `--acc: #b490ff` only. The site keeps the film's one accent and does not bring in the app's orange |
| Spacing | 20 by 14 inside a pick, 10 between picks, 30 between groups, 30 inside the panel | 28 to 32 inside a surface, 12 between terms, 64 to 120 between sections |
| Type | The system face; a song title heavy, a pick's title semibold, labels regular | Inter. ExtraBold for the page's one headline only; section headings a step lighter and smaller; body regular |
| Dividers | None | None: the rules between list items, steps and sections are gone |

Where the app and the old site disagreed, the app won: the flat page, no outlines, the radii, the capsules. The
headline white is now the app's #f2edf9 where the film's warm white had been used.

### What changed on the pages

- **Less purple.** Lavender is left on the script "you" and "your", the one primary button, ordinary links and the
  focus ring. The active tab, the "Coming soon" label, step numbers, list markers and the dictionary's column labels
  are neutral. The dictionary's gold and lavender column labels became grey; its several hundred "see also" and
  "jump to" links are grey with a faint underline.
- **Rounded and soft.** Squared, outlined boxes became filled surfaces with no stroke, or no box at all.
- **Fewer boxes, more space.** "It is / It isn't", the three parts, the steps, "What it shows you" and "About the
  project" are now text on the page in columns. Only the dictionary's terms, the pictures and the beta panel are
  surfaces. Sections are 64 to 120 px apart (they were 44 to 88), the page is narrower (1040 px), and running text
  is held to about 37 rem.
- **One stylesheet.** `site/site.css` serves both pages; the home page's inline styles and the dictionary
  generator's own copy are gone, so the two cannot drift. `site/dictionary/build.py` now links it; `terms.json` was
  not touched, and the generator's check reports both of its files up to date.
- **Kept.** The script rule, the line-break rule, sentence-case subheads, the tagline, the credit, the beta email,
  the wipe-in and its reduced-motion and no-script behaviour, and the rule keeping the hero headline on one line on
  a narrow phone (the dictionary's headline now has the same rule).

### The film

Not re-rendered. `site/film/round10/film-stills-now-left-new-look-right.png` shows five frames as they are now beside
the same frames in the new look (name card, a Deckie Desk shot, a Deckie Booth shot, "Your music / Your mix", the
end card); the single frames are `film-new-look-*.png` and the changed drawing code is `film-new-look.js`. In the
new look the background is the flat page colour, the screen cards have no outline or drop shadow and a radius of 24,
the crate-file label and its travelling tag are rounded filled surfaces with no ruled box, the end card's button is
a capsule, and the headline white is the app's. A re-render would be those five changes in `film.js`, one render of
about eight minutes, a new fifteen-second clip and poster, and the usual checks; no timing, copy or sound changes.

How the current film sits on the new page, said plainly: acceptably, not perfectly. Its frames have the purple
gradient, so its top-right corner is visibly more purple than the page around it, and its poster shows an outlined
screen card. Inside a rounded frame it reads as a picture with its own lighting. If the film is to match, it needs
the re-render.

One thing the stills show about the new look: with the outline gone, the Deckie Booth screen has no edge against the
page (its own background is the page's colour), so it floats. That is how the app looks on an iPad, but in the film
it loses the sense of a device. A faint surface behind it would fix that; it is a choice for the re-render.

### Checks on the rebuilt folder [measured]

- No sideways scroll at 320, 390 or 1440 px on either page (a 5 px overflow at 320 was found and fixed).
- No line of one word in any heading, paragraph or list item of the home page at 1440, 390 or 320 px. On the
  dictionary: none at 1440 or 390; two at 320 ("Recommend, / not prescribe" and one "Also called" line).
- One h1, alt text on all images, no console errors, no request leaves the site, every link resolves, nothing hidden
  with reduced motion or with script off; the outline of headings is unchanged.
- Contrast, against the 4.5 to 1 asked of small text: text on the page 17.0; secondary 7.9 on the page and 7.2 on a
  surface; dim 5.3 on the page and 4.9 on a surface; a link 7.8; the button's text on the accent 7.4; a tab's or
  chip's text 6.8.
- Lighthouse on the home page: performance 96, accessibility 100, best practices 100, SEO 100.
- The build is 21 files, 12,996,018 bytes; `site.css` is the one new file.

## 7j. Round eleven (Nov 12): a shorter home page, the app's layout in the hero, a real dictionary, a waveform behind

The owner: "This is looking better. The home page is too long. Copy needs to be cut down by at least half. Probably
more. The hero area lets mirror the app design with the left being the copy and the right (next songs) being the
explainer video. Logo on hero area also needs to be bigger but maybe scroll and stick in the nav. The dictionary is
for regular people and DJs. "what deckie does with it" is important for us and maybe for the user but is much less
important than the first two and the language and design should reflect this. The structure needs to be more
engaging and usable for a dictionary. There has to be a best practice on this online and we even did some of this on
the mobile app. Lets also add a subtle faintly visible waveform animation fixed to the background. That will allow
the foreground elements to stand out a bit."

During the round he also judged the "About the project" material "weird and too long", and the home page's body copy
is being rewritten as a separate document (`site/home-copy.md`, by the coordinating session). So this round built
the layout and left the body in a trimmed state, section by section, ready to be replaced.

### The home page

- **Length.** About 1,720 visible words before; 346 now [measured]. "What it shows you in the booth", the two
  dictionary entries and "About the project" are off the page; the is / is-not lists are three lines each; every
  part and step is one or two lines. Each section is its own `<section>` with an id, so its text can be swapped
  without touching the layout.
- **The About material** was first moved to a page of its own and then, on his word, taken off the site. The text is
  parked outside the site folder and its claims table stays in 7h. `llms.txt` still carries the summary, the words,
  the status and the credit.
- **The hero** follows Deckie Booth's Listen view: the left is where the app has the playing panel, and holds the
  name, the tagline, two sentences and the beta button; the right is where the app lists what could come next, and
  holds the film on a rounded surface of the panel's radius. The gap is the app's 52, and the right has the larger
  share (about 1.2 to 0.8). Below 980 px it stacks, copy first. "Watch how it works" is gone: the film is beside it.
- **The name.** A large "Deckie" in the script (up to 116 px) heads the left column and is written in. "Know Your
  Crate" stays the page's one h1; the large name is the logo and is marked as decoration for screen readers, because
  the bar's small name, which is always in the page, is the link that says "Deckie, home". The bar is sticky. On the
  home page its small name is hidden while the large one is in view and fades in once that has scrolled away (an
  IntersectionObserver; no movement, so nothing to turn off for reduced motion, and no change of layout). With
  script off the small name simply shows always. On the dictionary it is always there.

### The dictionary, as a dictionary

What was looked up. Advice on online glossaries is mostly from practitioners, and it agrees: letter navigation at
the top with the terms in alphabetical order under it; letters with no entries shown as inactive; a search box
beside the alphabet; short entries written for readers and not for experts; cross-links between related terms;
anchors per entry [12]. No single standard was found. In Deckie Booth itself the nearest thing to a lookup is the
long-press on a pick, which opens a small popover of plain reasons ("long-press for why"), and the search field
over More; there is no dictionary or help screen in the app's source, so which screen he meant by "we even did some
of this on the mobile app" is a question for him. The pattern taken from the app is that one: the short answer
first, the detail small and second.

What was built (`site/dictionary/build.py`; `docs/vocabulary/terms.json` was not edited):

- **Lookup first.** A large search field that filters as you type over the word, its meaning, the DJs' wording and
  the "also called" names; an A to Z bar under it, with empty letters greyed; topics as a folded filter. The bar
  sticks under the top bar. Every entry is real HTML in the page and has its own link.
- **A to Z, not by topic.** A reader with a word in mind expects the alphabet; the nine topics were Deckie's own
  filing. They remain as the filter. Words beginning with a digit sit under "#".
- **The entry.** The word; then its meaning in plain words, larger, with no label, as the definition; then "DJs
  say", with where the word comes from; then "Also called"; then, smaller and greyer, "In Deckie", one note; then
  "See also". The three equal columns are gone. The "Planned" mark appears only inside the Deckie note. The note is
  shown in full and not cut to a sentence: the median note is 128 characters, and a cut one would often lose its
  point; it is demoted by size and colour instead.
- **A list, not cards.** One column about 46 rem wide, entries separated by space. An entry reached by its link is
  lifted onto a surface so the eye finds it.
- **Start here.** Seven words a new DJ meets first, as links at the top: BPM, beatmatching, pitch fader, blend,
  phrase, key, crate.
- **The intro** is two sentences. The explanation of A and B, the Planned mark and where the words come from moved
  to the foot of the page.
- The structured data (a set of defined terms) stays, with a description that no longer says "three ways".

### The waveform

One fixed canvas behind everything, added by the shared script: mirrored vertical bars, three pixels wide on a
seven-pixel step, as Deckie Booth draws a song's wave. The heights are made by arithmetic (a slow shape for
sections, a faster one for phrases, a fixed value per bar, every fourth bar taller), not taken from any recording.
It drifts left at five pixels a second, redrawn ten times a second; it stops while the tab is hidden and is a still
wave under reduced motion; it takes no pointer events and is hidden from screen readers; with script off there is
no wave. Bars are white at 2.8 to 5.8 percent. So that surfaces stand clear of it, the surface colour is now solid
(#1a1420, what the app's 4.5 percent white comes to on the page).

Honestly: in the stills (`site/film/round11/hero-top.png` and `hero-top-12s-later.png`) it reads as a waveform, a
band of bars across the middle of the screen, and not as noise. It is visible behind the hero's paragraph and
between sections; secondary text over its brightest bar is about 7 to 1, well inside the rule. Twelve seconds apart
the two stills differ by sixty pixels of drift, which is the intent: it should not be noticed moving. Cost: the
home page's Lighthouse performance went from 96 to 92, with layout shift at 0.002; that run was on a busy machine.

### Also

- **A page for a wrong address**, `404.html`, in the site's look, with links home and to the dictionary, and an
  `ErrorDocument 404 /404.html` line in `.htaccess`. Its links are from the web root, so the path in that line and
  in the page must be changed if the site is served from a folder inside another site.
- The dictionary's two one-word lines at 320 px are gone with the new layout.

### Checks on the rebuilt folder [measured]

- No sideways scroll at 320, 390 or 1440 px on the home page, the dictionary or the 404 page.
- One-word lines: none on the home page at any of the three widths; none in the dictionary's entries. Two remain:
  the last "Start here" chip sits alone on its row at 390 px (it is a button, not a line of prose), and the 404
  page's headline breaks "That / page isn't in / the crate." at 320 px.
- One h1; alt text on all three images; no console errors; no request leaves the site; every link resolves; nothing
  hidden with reduced motion or script off.
- Lighthouse, home page: performance 92, accessibility 100, best practices 100, SEO 100.
- The build is 23 files, 12,976,767 bytes. New: `site.js`, `404.html`.

## 7k. Round twelve (Nov 12): the home page from the copy document, tiles and motion in the manner of a pick

The owner: "let's get it to about 500 words. Lets add some animations and some tiles. again using the "next song"
visual styling. Also the background can be more obvious. The hero design should still be closer to the app. the left
sizing and the light purple bg."

The home page's words are now those of `site/home-copy.md` (fourth draft, written by the coordinating session and
reconciled with a review from this one), set exactly; no word was changed to make a line break. The visible page is
598 words by the browser's count, which includes the bar, the alt-free labels, the folded film line and the footer;
the body copy is about 500 [measured]. The dictionary was not touched this round.

### The hero, measured from the app

From `ListenView.swift`: in landscape the playing panel is 42 percent of the width, the gap to the picks is 52, and
the panel is a rounded rectangle of radius 24 filled with the accent at 24 percent (top left) to 8 percent (bottom
right) over `Theme.card` #1d1530, padded 30 at the sides and 44 at the top. Sampled from the capture, that surface
is #2a234c near the top and #241c41 lower down. The site's hero is that: a left panel at 42 percent with the same
fill, radius and padding, holding the name, the tagline, "For decks that don't know / your music." and the button,
as the app's panel holds the song; a gap of 52; the film on the right where the picks are. It is the one purple
surface on the page. The bar's contents now start at the content edge at all times: on the home page the bar's
small name takes no room until the large one has scrolled away, and the tabs slide over as it fades in.

### Tiles, after the pick card

From `SuggestionsView.swift` (Simple): a pick is white at 4.5 percent, radius 16, padded 20 by 14, 10 apart; a small
top line (16, semibold) in the disc's colour; the title at 25 semibold; the tempo and pitch line in amber at 85
percent; the move in the muted grey; the wave on the right; a pinned pick has an orange bar, 4 wide, at its left.
The tiles take that anatomy: a small coloured top line as the label, the headline as the title, the line in the
muted grey, and a small real detail above. The details are crops of the booth (the named song, a pick, a pinned
pick), the deck's own reading in the app's amber ("128 BPM · deck +3.0%"), a drawn two-lane wave in the app's two
disc colours, and a drawn Shuffle dial. The "You pick" tile carries the pinned bar. The Desk steps and the
dictionary teaser are the same card. For rhythm, "What it isn't" and the About are plain type, and the closing
"Your music. Your mix." is set large with both "Your"s in the script.

### Motion, and why each

| What | When | Why |
|---|---|---|
| Tiles and steps rise 18 px and fade in, a row at a time, 80 ms apart | As each comes into view, once | The app's picks arrive with each new song; it leads the eye along the row |
| The wave in its tile is drawn left to right over 1.4 s | With its tile | It is a picture of time passing |
| The pitch tile counts from 124.3 to 128 BPM and from +0.0 to +3.0 percent over 1.2 s | With its tile | It shows the reading being taken |
| The Shuffle dial slides to 60 percent and two rows swap | With its tile | It shows what the dial does |
| The script words are wiped in | As before | Unchanged |
| The background wave drifts | Always | The only thing that does not stop |

All of it moves by transform, opacity or clip only. The states the page ships with are the finished ones; script
adds the starting states, so with script off nothing is hidden, and under reduced motion nothing is added at all.

### The wave, stronger

Two layers now, both faintly lavender: a back layer of wider bars, taller and slower (three pixels a second, 2 to
4.5 percent), and a front layer (seven pixels a second, 4.5 to 10 percent). It reads as a waveform at a glance
(`site/film/round12/wave-old-left-new-right.png`). Over its brightest point, secondary text is 6.4 to 1 and the
dimmest text 5.0 to 1; to hold that, the dim grey was lightened a step (#978bb0). Surfaces are solid and sit above it.

### The film beside the purple panel

Better than before, not matched. The film's own purple gradient now has a purple neighbour, so it no longer looks
like the one tinted thing on a neutral page; but its outlined screen card and its darker, bluer purple are still
different from the panel's. The re-render in the new look remains the fix.

### Checks on the rebuilt folder [measured]

No sideways scroll at 320, 390 or 1440 px. No line of one word on the home page at any of the three. One h1; alt
text on all four images; no console errors; no request leaves the site; every link resolves, the three dictionary
words included. Nothing hidden with reduced motion or with script off. Contrast: text on the panel 9.8, its
paragraph 6.0; a tile's label 6.7; the amber reading 10.2. Lighthouse: performance 96, accessibility 100, best
practices 100, SEO 100; layout shift 0.001. The build is 23 files, about 12.85 MB; it copied the dictionary as it
stood at the time (141 entries).

## 7l. Round thirteen (Nov 12): a wider film, "Nail the mix.", the icon, a purple dictionary panel, a wave that moves

The owner: "This is looking great!" Then, verbatim: "I think the video can be wider and the horizontal padding in
the hero lessened. Make sure its best practice. Not worried about the coloring or spacing. In the app the left side
is smaller than the right anyway. I still don't think "For decks that don't know your music." makes sense. maybe
"Nail the mix". Video - :22 change the line break to "in the order your / player shows them." The dictionary
section - make the purple and add an animated gif of some of the terms to the right. About Deckie make 2 columns.
Center footer. The background: can we have the waveform increase and decrease in size a bit. Like its actually
moving instead of just panning." Later: "Also I really like the app icon. Lets have it to the left of the "Deckie"
in the hero"; that it can go other places on the site but not in the film; on the film, "It's looking good other
than the line break"; and, watching the dictionary panel, "The animation of the dictionary section is weird. the top
moves up alone till it disappears then the rest jump up. Can just be one or two if easier".

### Hero

At 1440 px wide the panel was 418 px and the film 578; they are now 398 and 738 [measured]. The width came from
three places: the page's content width (1160 to 1280), the split (42 : 58 to 35 : 65) and the gap (52 to 32); the
panel's inner padding is a little less. What was applied as practice: a maximum content width, so the row does not
stretch on very wide screens; the film is never drawn larger than its 1920 px; its 16 : 9 box is reserved, so nothing
shifts when it loads (layout shift 0.001); the two sides are centred on each other; the panel's text column stays
under about 45 characters; it stacks below 980 px, copy first; and the button's lower edge is at 533 px in a 1440 by
900 window, 512 px at 1280 by 720 and 423 px on a 390 by 844 phone, so the headline and the button are in view
without scrolling at all three [measured].

The panel's larger line is now "Nail the mix." The "In the booth" intro is "Other apps can name a released song.
Deckie names yours.", so the phrase is said once. `site/home-copy.md` is marked as the fifth draft with his words.

### The app's icon

The icon is `deck-app/Deck/Assets.xcassets/AppIcon.appiconset/icon1024.png`: an orange record with a lavender label
on a dark rounded square. Desk has no icon of its own in the repository. The 1024 px file is itself soft (it was
enlarged from a small picture), so it was redrawn as vectors, `site/icon.svg`, to the same measures and colours. It
sits to the left of the large "Deckie" in the hero, as tall as about three quarters of the type size, centred a
touch low so it lines up with the lower-case letters, with empty alt text because the word beside it says the name.
A line stylisation in the film's manner (`site/icon-line.svg`: a dark record, grey rings, a lavender label with the
platter's mark) was tried in the same place (`site/film/round13/icon-stylised-hero.png`); the icon as it is was
built, because it is the thing he said he likes and it is the one warm colour on the panel. To switch, change the
file name. It was not animated: its rings are whole circles, so a turn would not show.

Elsewhere, two places: beside the small name in the sticky bar (and so on the 404 page), where it keeps the mark
recognisable once the hero has scrolled away; and as the favicon and touch icon, so a browser tab shows the app's
own icon. Not in the beta panel or the footer, where it would be a third and fourth copy on one page, and not in the
link-preview picture, which stays the film's poster. The dictionary page's bar is the other session's file and does
not have it yet. Nothing was added to the film.

### The film

One change: at 0:22 the smaller line breaks "In the order your / player shows them." A sheet of all sixteen caption
blocks from the new file (`site/film/round13/film-captions-recheck.png`) was made to confirm no other break moved;
it was made and not looked at closely. The file is 76.0 s, 60 frames a second, -14.1 LUFS, peak -1.6 dBFS; the clip
15.0 s at -14.0 LUFS. A version in the round-ten look had already started rendering when he closed that question
("looking good other than the line break"); it was left to finish and set aside, unchecked, as
`site/assets/variations/deckie-explainer-new-look-set-aside.mp4`. The film stays as it is.

### The dictionary panel

The section is now a panel with the playing panel's fill and radius: the copy on the left, and on the right real
entries from the dictionary as small cards (the topic, the word, its plain meaning, and the dictionary's own drawing
of the move). He asked for an animated GIF; it was built in the page instead, because it stays sharp, weighs almost
nothing, can stand still for reduced motion, and each card links to its entry. The words are bass swap, echo out,
cut on the one, blend and key lock. Their text is not typed into the page: `site/home_terms.py`, run by the build,
copies it from the built dictionary page, which is itself made from `docs/vocabulary/terms.json`.

Its motion was rebuilt after his note. Two cards show. Every 4.2 seconds the whole column moves up by one card in a
single eased move of 0.6 s; the leaving card fades as it goes and the next is already underneath, so nothing jumps.
The panel's height is fixed to the tallest pair, measured, so the page never shifts (the panel and the page were the
same height in every one of eight frames across a swap [measured]; `site/film/round13/dictionary-swap-frames.png`).
It waits while the pointer or the keyboard is on it, runs only while on screen with the tab showing, and with reduced
motion or no script all five cards are simply listed.

### About, footer

"About Deckie" is two columns: the two paragraphs on the left, the facts on the right, stacking on a phone. The
footer is centred.

### The wave, moving

Each bar's height is now its fixed shape times three slow movements: a swell about every nine seconds (the whole
wave between 56 and 100 percent of its height), a ripple that travels along the bars, and a soft pulse at 122 beats
a minute (six percent). All are sines, so nothing flickers. The pan is slower (4 and 2 pixels a second). It redraws
thirty times a second; one redraw takes 0.13 ms, the page held 60 frames a second with none dropped over four
seconds [measured], and Lighthouse performance is 95. Under reduced motion it is one still frame, at the swell's
peak; it stops while the tab is hidden. Over its tallest, brightest moment the dimmest text is 5.0 to 1 and
secondary text 6.4 to 1. Trough and peak: `site/film/round13/wave-trough-left-peak-right.png`.

### Checks on the rebuilt folder [measured]

No sideways scroll at 320, 390 or 1440 px; no line of one word on the home page at any of the three; one h1; every
picture has alt text except the two icons, which are decoration beside the word; no console errors; no request
leaves the site; nothing hidden with reduced motion or script off. Contrast on the panel's cards: meaning 8.5, label
8.4. Lighthouse: performance 95, accessibility 100, best practices 100, SEO 100; layout shift 0.001. The visible page
is 706 words by the browser's count, of which about 95 are the five dictionary cards. The build is 26 files,
about 12.9 MB, and copied the dictionary in the other session's new card layout.

## 7m. Round fourteen (Nov 12): one line for the dictionary, the dictionary shot remade, the outlines measured

The owner, on the film and the site: "I realized the video has to be updated for the dictionary. The copy can be
updated too." And: "the outline for the 'search' section is not over the search its off a bit." On the first
caption tried, "Every word / in plain words.": "a little clunky". Then: "We need to resolve this cause it is on the
website too. 'DJ in plain English'? 'DJ speak translated' 'DJ lingo in plain words' Something like that."

### The line

"DJ speak, in plain words." It is used in the film and on both pages. It keeps "plain words", which is what every
entry in the dictionary does first, and "DJ speak" names the thing a newcomer is on the outside of. "Plain English"
was left because the dictionary may not stay in one language; "lingo" reads older than "speak"; "translated"
promises a second language rather than a simpler one. "DJ speak, translated." was not set as a still: on the built
caption the chosen line sits in two even lines and nothing about it asked for the comparison.

### The film: shot 17, 59 to 64 s

Header "The dictionary". Three captions on the beats that were already there:

| Beats | Caption | Behind it |
|---|---|---|
| 118 to 122 | Every DJ / starts somewhere. | the top of the dictionary page |
| 122 to 124 | DJ speak, / in plain words. | the search field with "echo" typed |
| 124 to 128 | Then how it's used / on the decks. | the Echo out card |

The page is captured from the built site with the clock pinned to 12 Nov 2026, so the word of the day is the same
every time (`site/film/capture/dictionary.mjs`). The picture sits a little further right and a little smaller
(box x 784, was 760), which leaves about 71 px between caption and picture, the same as the other shots; before it
was 47 to 49 px. The camera on the search step was pulled back so the whole field and the typed word are in frame.

One thing is stale inside the picture: the top-of-page capture was taken before the page's own line changed, so the
small grey line under the headline in the film still reads the old sentence. At film size it is about 9 px tall
and cannot be read. A new capture needs another render; it is listed for the owner in section 13.

### The outlines, measured [measured]

Each outline was laid over the recording frame it points at and compared with the edges of the thing itself.

| Outline | Was | Now | Off by |
|---|---|---|---|
| Search field | 790, 262, 690, 56 | 791, 226, 687, 58 | 36 px low |
| Pick line | 806, 346, 300, 82 | 812, 351, 250, 64 | ran over the artist line below |
| Wave | y 236 | y 243 | 7 px high |
| Pitch, BPM, Shuffle, NEXT | | unchanged | within a few pixels |

Before and after: `site/film/round14/search-outline-on-recording-before.png`,
`other-outlines-on-recording.png`, `film-all-captions.png`.

### The site

- Home, dictionary panel: "Bass swap. Echo out. Cut on the one." then "DJ speak, in plain words." A term in that
  line no longer breaks across lines; at phone width "Cut on the one." had been split after "Cut".
- Dictionary page: under the headline, "Why not here? DJ speak, in plain words."; the title and the descriptions
  for search and sharing say the same; the app icon sits beside the wordmark in the bar.
- `llms.txt`, the JSON-LD description on the dictionary page, the text folded under the film, `home-copy.md` and
  `shotlist.md` follow.
- Found while checking: the home panel's moving cards were started by a script that looked for an element by a
  name the dictionary page also uses, so on the dictionary page, with motion on, the whole word list was wrapped and
  the page was 6,354 px too wide at desktop width. The script now looks for the home panel only. This had been
  there since round thirteen; the round thirteen check ran before that script was added.

### Checks [measured]

Film: 76.0 s, 60 frames a second, -14.1 LUFS, peak -1.6 dBFS. Picture against sound D: 41 of 42 hits within
20 ms, median 2.0 ms; the one outside is the first sample at 0.0 s. The first 15 s did not change, so the 15 s clip
is the same file. Every caption's breaks were read on one sheet (`film-all-captions.png`) and the dictionary shot
at half-second steps (`film-dictionary-shot-half-seconds.png`).

Site, on the rebuilt folder: no sideways scroll at 320, 390 or 1440 px on either page; no line of one word on the
home page at any of the three; one h1; no console errors; no request leaves the site; nothing hidden with reduced
motion or script off. The build is 26 files, 13,063,553 bytes.

Left alone, because the dictionary page's layout is the other session's: at 390 and 320 px some "See also" rows
end on one chip, and at 320 px the label "Moves" sits on a line by itself above "Heard from DJs".

## 8. Other choices, unchanged from the first cut

- **No voice.** The research says a film must work muted and that a synthetic voice needs disclosing; no voice has
  been chosen for Deckie. A voice can be laid over the same cut later.
- **Music made for the film.** A plain 120 BPM bed synthesised by a script, with small sounds on the steps, mixed to
  -14 LUFS. No recording of anyone's music is involved.
- **Sixteen by nine only.** A tall cut for phones would be a second layout, not a crop.
- **The booth's own colours** (the app's Theme values), one accent.
- **Tracklist.** The set recorder writes a tracklist only while listening through the microphone, and this Mac's
  sound was muted, so none could be made here [measured]. Neither cut shows one, and the second-pass page no longer
  mentions it.

## 9. Claims on the page and in the film, with their source

Claim discipline P7 is kept: neither says Deckie is the only thing that hears the room.

| Claim | Source | Checked here |
|---|---|---|
| Names the playing song from the DJ's own crate | README; D4 | [measured] in the simulator, from a file fed to the same recogniser (section 10) |
| Edits, bootlegs and burned CDs included | spec-condensed; D4 | [unverified]: the demo crate file was built from files; nothing was played from a burned CD |
| Reads the pitch fader | README; research H | [measured]: a file played 3 percent fast read as "deck +3.0%" to "+3.1%" |
| Picks with pitch and move, the join wave, Shuffle, pin | D18, D19 | [measured], all on screen in the recording |
| Crate file holds tempo, key, bars, style, fingerprints and no audio | D3; the owner, Nov 11 | [measured] by reading a crate file |
| Moves by AirDrop, iCloud Drive or Files; no server | desk-app README | [unverified] |
| No account, no upload, works with no signal | voice.md; D3 | [unverified] |
| Plays nothing, mixes nothing, never touches the decks | The app has a microphone input and no output to the decks | [inf] from the build |
| Never looks up what you play; what you play trains nobody's model | spec-condensed principle; D3 and its notes; D15 | [unverified] |
| Needs your own music files, an iPad and a Mac | D11, P17 | The beta as it stands [inf] |

## 10. How the screens were captured

- **The demo crate file.** The small crate file was copied to a scratch folder (the original was only read) and every
  title, artist, file name and folder in the copy was replaced with an invented one, so that no real artist or
  song is named and the owner's library is not shown. The analysis numbers are untouched. The invented names are
  two-word combinations from word lists; none was checked against real acts [unverified].
- **Six original tracks.** No music exists on this Mac, so six short tracks were synthesised by script (house, lo-fi
  and tabla patterns, 96 to 128 BPM). Deckie Desk analysed them with its real engine (`--build`, 28 seconds of
  analysis for the six) and made their fingerprints (`--sign`); the six were added to the demo crate file. The song
  recognised in the film, "First Light", is one of them. [measured]
- **The booth.** The Release build ran in the iPad Pro 11-inch simulator, driven by its `-deckURL` hooks and recorded
  with `xcrun simctl io recordVideo`. Recognition is real: the app's file-test path fed "First Light", played 3
  percent fast, to the same recogniser the microphone feeds, and the song was named about five seconds later. The
  status line in the recording therefore says "test file" where a booth would say "sure". The microphone path was
  not exercised: the simulator had no live microphone and the Mac was muted. [measured]
- **The dictionary.** `docs/vocabulary/index.html` in a headless browser, dark theme, with "echo out" in the search.
  The capture is cut above the second term on the page, for the reason in section 11.
- **Deckie Desk.** Desk's own `--snapshot` mode, run once the Mac was unlocked (it was locked through the first two
  passes). The frames came from the mode's fallback, not from the window server: the table and the Discs panel are
  drawn as the app draws them, but the toolbar, the inspector beside the table, the selected row's highlight and the
  import log sheet are not, and the area where the inspector sits is black [measured]. The film therefore uses the
  left 1780 by 1112 pixels of the first frame, which is the title bar and the table and nothing else, behind the
  stencilled label; the page's Desk card uses the table and the Discs panel from the Discs frame, cropped the same
  way. All thirteen frames were looked at: every title and artist is one of the invented names, the footer reads
  "244 tracks, Friday night, 244 with signatures", and no path or real name appears [measured]. A capture of the
  whole window needs Screen Recording permission for Deckie Desk on this Mac, which is the owner's to grant.

## 11. Things found on the way

1. **Twenty dictionary entries name a person.** `docs/vocabulary/terms.json` has 20 terms whose text names the owner
   or the first night's DJ (for example fade, filter fade, chop, echo in, tempo, pitch range, style). The film and
   the page show only an entry that names nobody. If the dictionary is to be public, those 20 need rewording.
   [measured]
2. **The booth still shows its sprint words.** "Deck" in the status bar, a "CDs" tab, "CD1 / CD2" for discs that now
   have names, and a "Mix map" tab that opens the first party's bundled map. A new DJ would meet all four.
3. **The booth's microphone hook stalls in a headless simulator.** `deck://mic` with no microphone attached left the
   app on "Listening…" with later hooks never running. The file test works. [measured]
4. **Desk does not split "Artist - Title" file names.** The six untagged WAV files came in with the whole file name
   as the title and no artist; they were fixed in the copy, as a DJ would fix them in Desk. [measured]
5. **Desk's `--snapshot` has three traps on this Mac (macOS 26.6).** The window does not open while the Mac is
   locked, so the mode waits for ever. Started from a shell, or through `open` without
   `-NSTreatUnknownArgumentsAsOpen NO`, the two paths on its command line are taken as files to open and the window
   never appears, locked or not. And without Screen Recording permission the window server gives the app nothing, so
   it falls back to the table-only picture while its message says "unlock the Mac". `site/film/capture/desk.sh`
   carries the working command. [measured]

## 12. Checks run on the final film

Run on the fifth cut (Nov 12, round seven):

- **Sound against picture.** 38 of 42 accents fall within 20 milliseconds of a sound's onset, median 2.0 ms. The
  four outside are the three "whoosh" sounds, which have no sharp onset, and the soft tick under the end card's
  tagline (46 ms from the nearest measured onset; it sits in the tail of the end card's impact). [measured]
- **Loudness.** -14.0 LUFS integrated, true peak -1.3 dBTP. [measured]
- **The file.** H.264, 1920 x 1080, 60 frames a second, 76.0 seconds, stereo AAC; the clip is 15.0 seconds and ends
  on the name, "Know Your Crate" and deckie.io. [measured]
- **The picture.** `site/film/round7-contact-sheet.png` holds 29 frames from the finished file: every distinct
  caption block at rest, both app-name headers part-way through being written, and the name and end cards. Each was
  looked at at 880 pixels wide, large enough to read every line and see the edges of the script letters, and 24
  lossless stills were looked at at half size before the render. No clipped letter and no line of one word was
  found outside the opening (section 7e). The frames between those were not reviewed this round; the film has not
  been seen in real time, and the sound was measured, not heard.
- **The header's position.** Section 7e.
- **At phone size.** Seven frames at 390 pixels wide: the headlines, the tagline, "Your music / Your mix" and the
  end card read. The header reads, its Inter part more easily than the script name, whose strokes are thin at that
  size. The smaller lines and the words inside the app screens do not, as before. [measured]
- **The page.** Rendered at 1440 and 390 pixels wide after scrolling its whole length, and again with reduced motion
  and with script switched off: no sideways scroll, nothing fails to load, no script word left hidden; and no line
  of one word in any heading, paragraph or list item at either width.

## 13. For the owner to decide

1. Settled Nov 12: "Help us beta test" opens an email to info@apphold.media; the credit is Christopher Shannon and
   App Hold Media; the name is fine for now.
2. Whether anything is published at deckie.io before the DECKEE review that D9 puts ahead of a public launch (the
   domain itself is settled: section 7b).
1b. Settled Nov 12: the film stays in its current look (section 7l).
1c. Open: the film's picture of the dictionary's top still carries the page's old small line under the headline
    (section 7m). It cannot be read at film size; a fresh capture costs one more render.
1a. Soundtrack D (section 7g) is in place as the presumptive final; A, B, C and the bells version are kept to switch to.
2a. The tagline "Know Your Crate" is in place "for now"; he means to test it with DJs.
2b. The opening's two one-word lines, "CDJs." and "Turntables.", kept as a list (7e); say if the rule has no exception.
2c. The smaller line at 4 s: "It hears what's playing.", or his "It listens beside the decks."
3. Whether every "your" in a headline should be in script, as built, or only the ones that carry the line (7c).
   As built there are eight in the film. He named the words; the evenness is my reading.
3a. Whether to keep the last nautical reference, "Deckie, as in deckhand" in the page's footer, given DECKEE (boating)
   and DECKHAND (software). "Deckhand" in a tagline is the part to ask the attorney about.
4. The headline. The page uses "For decks that don't know your music." None of voice.md's four tagline candidates is
   used, because none has been picked.
6. Whether the beta asks for "an iPad and a Mac", and which iPadOS and macOS versions.
8. Whether the film should get a voice, and whose.
9. Whether to grant Deckie Desk Screen Recording permission on this Mac, so its whole window (toolbar, inspector,
   import log) can be captured; the film and page now show only its table and Discs panel.
10. Whether to re-record recognition through the microphone with the Mac's sound on, which would remove "test file"
   from the status line and give a real tracklist to show.


## Sources

1. Wistia, "Explained: A Marketer's Guide to Explainer Videos", https://wistia.com/blog/explainer-videos
2. Wistia, optimal video length, citing its 2026 State of Video report, https://wistia.com/learn/marketing/optimal-video-length
3. Vidpros, "SaaS Explainer Video: What Works and What Wastes Budget", https://vidpros.com/saas-explainer-video/
4. Content Beta, best 60-second explainer videos, https://www.contentbeta.com/blog/best-60-second-explainer-videos/
5. Screenhance, "How to Make a Product Demo Video", https://screenhance.com/blog/how-to-make-a-product-demo-video
6. Supademo, SaaS explainer video examples, https://supademo.com/blog/saas-explainer-video
7. 3Play Media on the Verizon Media and Publicis Media caption survey (2019, 5,616 US adults),
   https://www.3playmedia.com/blog/verizon-media-and-publicis-media-find-viewers-want-captions/
8. The motion-reel production checklist used to build the film (frame-exact render, contact sheets at phone size,
   a new event every two to four seconds, sound on the measured beat grid).

9. Netflix, Timed Text Style Guide: General Requirements, section 4, Line Treatment,
   https://partnerhelp.netflixstudios.com/hc/en-us/articles/215758617
10. MDN, the CSS `text-wrap` property, https://developer.mozilla.org/en-US/docs/Web/CSS/text-wrap

11. The llms.txt proposal, https://llmstxt.org/

12. Advice on glossary pages (letter navigation, search, short entries, cross-links), from a search of practitioner
    guides; among them the archived usability.gov glossary and notes from the 2021 Federal Plain Language Summit,
    https://www.lireo.com/2021-federal-plain-language-summit-online-glossaries/

From this repository: `docs/product/voice.md`, `docs/product/spec-condensed.md`, `docs/product/00-decisions.md` (D3,
D4, D9, D12, D15, D18, D19, P7, P8), `docs/research/d-positioning.md`, `docs/research/e-dj-vocabulary.md`,
`docs/research/codex-community.md`, `docs/competitive-analysis.md`, `docs/naming/00-shortlist.md`,
`docs/vocabulary/terms.json`.
