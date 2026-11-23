# Deckie home page: copy document

Sixth draft, Nov 16, 2026.
hero, then a few sections that each make one point with a short headline and a line or two, a row of feature
panels, and a short about with a facts list at the end.

About 500 words on the page, as the owner asked, down from about 1,700. Six sections after the hero.

This draft folds in a review by the agent that built the film and the page. What was taken from it, and where I
disagreed, is at the end.

Marks used below: *italic* words are set in the script face (you, your, Deckie, in headlines only). Lines starting
"Layout:" are notes for the build, not copy.

---

## Page title and description (for search and link previews)

- **Title:** Deckie: DJ booth companion for iPad and Mac. Know Your Crate
- **Description:** Deckie sits on an iPad beside your decks, names the song that is playing from your own crate,
  reads the pitch fader and shows what could come next. For CDJs, turntables and house decks. Coming soon.

---

## 1. Hero

*Deckie*

# Know *Your* Crate

Nail the mix.

Deckie Desk reads your music: tempo, key, bars and vocals. Deckie names what's playing, shows what could come next and how to mix it in.

*Coming soon.*

**[Help us beta test]**

Layout: copy on the left, the film on the right, as in the app. "Nail the mix." is the larger line; the sentences under it are small. "Coming soon." sits on its own line just under them, in italic at the same size, a shade quieter, not a pill (here the italic is the ordinary kind, not the script face). One button under it.

---

## 2. In the booth

## In the booth

Other apps can name a released song. Deckie names yours.

| Tile | Headline | Line |
|---|---|---|
| 1 | It names the song | From your crate, a few seconds in, with its disc, folder and track, as on your player. |
| 2 | It reads the pitch fader | It hears how fast the deck is running and shows the tempo the song is really playing at. |
| 3 | It shows what could come next | Picks from your crate, best first. Each says where to set the pitch and how you could bring it in. |
| 4 | It draws the transition | A wave of the end of this song over the start of the next, so you can see where they meet. |
| 5 | Shuffle | Turn it up for less obvious picks. At zero they stay in score order. |
| 6 | You pick | Pin the one you want. Or search the rest of your crate. |

Layout: six tiles styled like the "next song" cards in Deckie on the iPad (the pick rows), in a row that scrolls
sideways or a grid of three by two; each tile has a crop of the booth or a small drawn detail above the headline,
and animates in. On a phone they stack or scroll sideways. Tile headlines are subheads, so no script.

---

## 3. What it isn't

## What it isn't

- **It doesn't mix for you.** It plays nothing and touches nothing. It suggests. You mix.
- **It doesn't beatmatch for you.** It shows where the pitch fader could go. Your hands do the rest.
- **It doesn't take your music.** Nothing is uploaded. What you play isn't sent anywhere or used to train anything.
  No account. Works with no signal.
- **It doesn't replace your DJ software.** Keep what you use. Deckie sits beside it.

*Your* music. *Your* mix.

Layout: the four lines as a plain list with space between them, no boxes. The closing line is set large, as in the
film, with both "Your"s in script.

---

## 4. Before the gig

## Desk reads *your* crate

1. **Add your music.** A stick, a burned CD or a folder of your own files: releases, edits, bootlegs. Desk reads
   them where they are, in the order your player shows them.
2. **Desk reads every song.** Tempo, key, bars and style, and a fingerprint to recognise it by. Stop at any time: the
   songs already read stay in your crate.
3. **Get the crate file to your iPad.** It's small: no audio goes in it. AirDrop, iCloud Drive, a stick or a cable.
   No server.
4. **Open it in Deckie.** Set the iPad beside the decks. It names the song playing and shows what could come next.

**No iPad?** Switch Desk to Booth. It listens through the microphone, names the song and shows the picks.

Layout: a small label "Deckie Desk, on your Mac" above the headline, as in the film. Desk's quick start (the
one-minute silent film made for Desk) on one side, in a player with its poster that never plays by itself and loads
the film only when it is played; under it one small line, "The quick start: under a minute, no sound. The steps say the
same in words." The four steps on the other side, as tiles in the same style; they are the film's four steps, so a
visitor who cannot play it reads the same thing. Under them the "No iPad?" line, then one small line: "A crate is a
group of your songs. It can be your whole library."

---

## 5. The dictionary

## Every DJ starts somewhere

Bass swap. Echo out. Cut on the one. DJ speak, in plain words.

**[Open the dictionary]**

Layout: the three example words link straight to their entries.

---

## 6. About

## About *Deckie*

Most decks don't know your music: turntables, older CDJs, the venue's own gear. So you mix from memory. Deckie
is a second screen that knows your crate and puts what you know in front of you, when you need it.

It is two apps on one shared core. Everything runs on your own devices.

| | |
|---|---|
| Deckie | iPad. Listens beside the decks during a set |
| Deckie Desk | Mac. Prepares your crate before the gig |
| Works beside | CDJs, turntables, house decks |
| Your music | Stays on your devices |
| Status | In development. Coming soon |
| Made by | Christopher Shannon and App Hold Media |

Layout: two short paragraphs, then a plain two-column facts list in small type, like the specs at the foot of a product page.
In the HTML the list is a definition list, so a search engine or a reader's assistant gets each fact as a label and
a value. "App Hold Media" links to https://apphold.media.

---

## 7. Beta

## Help us beta test

We want working DJs to try Deckie on their own music and tell us what is wrong. You need your own music files, a
Mac and an iPad.

**[Help us beta test]**   Opens an email to info@apphold.media.

---

## Footer

deckie.io · Deckie. Know Your Crate · Made by Christopher Shannon and App Hold Media.

The screens show a demo crate file with invented song and artist names. The film's music was made for the film.

---

## What was cut from the old page, and where the facts went

- **"Three parts."** Each part now has its own section (2, 4 and 5).
- **"How to use it."** It is section 4.
- **The long "About the project".** Replaced by section 6: the problem and the answer in two sentences, and six
  facts. How it works is sections 2 and 4. Privacy is section 3. How it is built is not on the page.
- **The film described in words.** Kept, folded shut under the film, for anyone who cannot play it.
- **"Deckie, as in deckhand"** in the footer. Dropped; it was also the last nautical reference.

## For search engines and assistants

The visible page carries the facts. The same facts go, unchanged, into the page's structured data and the site's
plain-text summary file (`llms.txt`).

One open choice: how Deckie is built (a shared Swift core tested on three platforms, a Python lab for evaluation, a
written log of decisions) is no longer on the page. A reader's assistant may look for it. It could go in
`llms.txt` only, as three lines, without lengthening the page.

## The review, and what I did with it

**Taken**

- "Burned CDs" overstated what Desk reads. Desk reads files, so it now says "the songs on your burned CDs".
- "Any decks it can hear" was too strong, since loud rooms reduce matching. Now just the list.
- "Collected" was inaccurate, because the booth keeps a local record of the set. Removed.
- The hero sentence had dropped the pitch fader, the thing no other app has. It is back, at the same length.
- "In the booth" is the heading, as the owner suggested, and "Know the beat. Nail the mix." is the line under it.
- "Other apps can name a released song. Deckie names yours." carries the differentiator in one line.
- Four panels, not five: the wave joins the picks, and the last panel is "You pick", with search restored.
- "It doesn't beatmatch for you", so it reads as reassurance and not as a missing feature.
- "What it isn't" keeps its label, moves up to third, and closes on "Your music. Your mix." as the film sets it.
- "Desk reads your crate" as the heading, to avoid two script runs in one short line.
- The fingerprint is back in step 2, in plain words.
- The beta ask says what you need.

**Where I disagreed**

- **"Used to train anything" stays.** The review wanted "sent anywhere" only, on the grounds that naming training
  puts the worry on the page. The owner asked for this section to address that worry directly, and the research
  shows DJs raise it in those terms. It is true, because nothing leaves the device. Both phrases are now in the
  line.
- **The About section stays, short.** The review wanted it folded into a list called "The facts". The owner said
  a short about would be fine if it made sense. It is now the review's own two-sentence version of the problem and
  the answer, over the facts list.

**To verify before the page goes live**

- "Works with no signal": tested Nov 13 on the real iPad in airplane mode. One song, named correctly.
- The app's own screen says a song shows up after 5 to 10 seconds. "A few seconds in" is fair for that and should
  not get shorter.

## Fifth draft: what changed, and why

The owner decided on Nov 12 that "For decks that don't know your music." did not work as the hero's line and that
"Nail the mix." should replace it. So the hero's larger line is "Nail the mix." and the "In the booth" intro no longer opens with "Know the beat. Nail
the mix.", so the phrase is said once. Also from the same notes: the dictionary section is a purple panel with a few
dictionary words arriving on its right (their text is copied from the built dictionary by `site/home_terms.py`),
"About Deckie" is two columns, the footer is centred, and the app's icon sits to the left of the large "Deckie".

## Sixth change: one line for the dictionary

On Nov 12 the owner asked for one line for the dictionary, shared by the film and the website, and suggested three
directions (DJ talk in plain English, translated, or in plain words). Resolved as "DJ speak, in plain words." It is the
dictionary panel's line here, the dictionary page's lede, title and description, and the film's second dictionary
caption.

## Seventh change: the hero names the two parts

At the owner's request, Nov 16: the small lines under "Nail the mix." now say what each part does. Deckie Desk
reads the music (tempo, key, bars, vocals); Deckie Booth, on the iPad, names what's playing and suggests what
could come next and how to mix it in. Then, the same day: "reads", not "analyzes", as on the rest of the page;
"things like" cut; ", on your iPad" cut from the hero; and "Coming soon" is no longer a pill beside the button
but its own italic line under the paragraph. "Deckie", "Know Your Crate" and "Nail the mix." are unchanged. The page's
descriptions, structured data and `llms.txt` were brought in step.

## Eighth change: the iPad app is called Deckie

Nov 21, 2026 (D43): the iPad app is "Deckie" on screen since build 2, so the page calls it Deckie. The hero reads
"Deckie names what's playing"; the facts list's first row is "Deckie"; the descriptions, structured data, picture
descriptions and `llms.txt` say "Deckie, on an iPad beside the decks". The film still says "Deckie Booth, on your
iPad" (it is not re-rendered), so the written description of the film keeps its words.

## Ninth change: the film brought up to date, and the how-to

Nov 21, 2026. The iPad app is Deckie (D43), so the film was rendered again (its sixth cut, section 7o of letter V)
and the page now describes it as it is.

- **Film.** The iPad section's header is "Deckie on your iPad"; the old name is gone from the film, the poster, the
  fifteen-second clip and the written description folded under the film. The iPad's screens are a fresh recording of
  today's Deckie with the demo crate file "Gig Friday" (twelve generated songs, invented names, the same crate file
  as Desk's quick start). The search shot ("Or search the rest of your crate") is out of the film: twelve songs fill
  the picks, so there is no "More" to search; the search is still in the app and still on the page's "You pick"
  tile. In its place, one shot of Booth in Desk (D42, D44): "No iPad? Desk listens too."
- **Discs and folders.** Since D25, Desk reads a stick, a CD or a folder as it is and no longer has the DJ sort songs
  into discs. The film's caption "Sort your crate into discs and folders" became "It reads sticks, CDs and folders
  as they are", and the page's step 3 ("Sort it into discs and folders") is gone.
- **"Desk reads your crate" carries the how-to.** Desk's quick start, made for Desk (D46), is the section's picture,
  in place of the Desk still. The four steps now follow the film's four steps (add your music, Desk reads every song,
  the crate file to the iPad, open it in Deckie), keeping the page's facts: burned CDs, the fingerprint, no audio in
  the file, no server. Step 3 names a stick and a cable beside AirDrop and iCloud Drive, as the quick start does.
- **Booth in Desk.** One line under the steps, "No iPad? Switch Desk to Booth." It is the only new claim, and it is
  separable: the line, its style rule, the film's shot and the sentence in the description, the structured data and
  `llms.txt` can come out together.
- **Pictures.** The three tile pictures and the share card's iPad screen are from the new recording; the share card
  showed the old status bar name and tabs.
- **Structured data and `llms.txt`** say the same: Booth is Desk's listening mode, and the quick start is listed.

## Tenth change: Desk's own window in the film

Nov 23, 2026. The film's Desk shots (16 to 28 s) now show Desk's Mac window as it is today, with the crate "Gig
Friday", the same crate as the iPad shots: its songs, then its Sources panel with the stick, its folder and its songs
in the stick's order. Until now they showed a still from Nov 12, an older window with other names. The label and the
tag that travels to the iPad say "Gig Friday" (they said "Friday night"). The pictures leave out the window's toolbar:
Desk drew them itself, and without permission to record the screen the toolbar's buttons do not draw. The words on
screen, the timing and the sound did not change, so the written description under the film, the poster, the
fifteen-second clip and `llms.txt` stay as they were. Booth in Desk (55 to 59 s) is still Desk's pages. Desk's quick
start is unchanged: it still shows the Windows and Linux window, under the section's label "Deckie Desk, on your Mac".
