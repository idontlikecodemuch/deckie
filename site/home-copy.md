# Deckie home page: copy document

Fifth draft, Nov 12, 2026.
hero, then a few sections that each make one point with a short headline and a line or two, a row of feature
panels, and a short about with a facts list at the end.

About 500 words on the page, as Christopher asked, down from about 1,700. Six sections after the hero.

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

An iPad beside the decks. It names the song, reads the pitch and shows what could come next.

**[Help us beta test]**   Coming soon

Layout: copy on the left, the film on the right, as in the app. "Nail the mix." is the larger line; the two sentences under it are small.

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

Layout: six tiles styled like the "next song" cards in Deckie Booth (the pick rows), in a row that scrolls
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

1. **Point it at your music.** Your own files: releases, edits, bootlegs, the songs on your burned CDs.
2. **It writes a crate file.** Tempo, key, bars and style for every song, and a fingerprint to recognise it by.
   No audio goes in it.
3. **Sort it into discs and folders.** In the order your player shows them, so the booth can say disc and track.
4. **Send it to your iPad.** AirDrop, iCloud Drive or Files. No server.

Layout: a small label "Deckie Desk, on your Mac" above the headline, as in the film. Desk screenshot on one side,
the four steps on the other, as tiles in the same style. One small line under the steps: "A crate is a group of your songs. It can be your
whole library."

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
| Deckie Booth | iPad. Listens beside the decks during a set |
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
written log of decisions) is no longer on the page. For a job application, that is what an evaluator's assistant
may look for. It could go in `llms.txt` only, as three lines, without lengthening the page.

## The review, and what I did with it

**Taken**

- "Burned CDs" overstated what Desk reads. Desk reads files, so it now says "the songs on your burned CDs".
- "Any decks it can hear" was too strong, since loud rooms reduce matching. Now just the list.
- "Collected" was inaccurate, because the booth keeps a local record of the set. Removed.
- The hero sentence had dropped the pitch fader, the thing no other app has. It is back, at the same length.
- "In the booth" is the heading, as Christopher suggested, and "Know the beat. Nail the mix." is the line under it.
- "Other apps can name a released song. Deckie names yours." carries the differentiator in one line.
- Four panels, not five: the wave joins the picks, and the last panel is "You pick", with search restored.
- "It doesn't beatmatch for you", so it reads as reassurance and not as a missing feature.
- "What it isn't" keeps its label, moves up to third, and closes on "Your music. Your mix." as the film sets it.
- "Desk reads your crate" as the heading, to avoid two script runs in one short line.
- The fingerprint is back in step 2, in plain words.
- The beta ask says what you need.

**Where I disagreed**

- **"Used to train anything" stays.** The review wanted "sent anywhere" only, on the grounds that naming training
  puts the worry on the page. Christopher asked for this section to address that worry directly, and the research
  shows DJs raise it in those terms. It is true, because nothing leaves the device. Both phrases are now in the
  line.
- **The About section stays, short.** The review wanted it folded into a list called "The facts". Christopher said
  a short about would be fine if it made sense. It is now the review's own two-sentence version of the problem and
  the answer, over the facts list.

**To verify before the page goes live**

- "Works with no signal": tested Nov 13 on the real iPad in airplane mode. One song, named correctly.
- The app's own screen says a song shows up after 5 to 10 seconds. "A few seconds in" is fair for that and should
  not get shorter.

## Fifth draft: what changed, and why

Christopher, Nov 12: "I still don't think "For decks that don't know your music." makes sense. maybe "Nail the mix""
So the hero's larger line is "Nail the mix." and the "In the booth" intro no longer opens with "Know the beat. Nail
the mix.", so the phrase is said once. Also from the same notes: the dictionary section is a purple panel with a few
dictionary words arriving on its right (their text is copied from the built dictionary by `site/home_terms.py`),
"About Deckie" is two columns, the footer is centred, and the app's icon sits to the left of the large "Deckie".

## Sixth change: one line for the dictionary

Christopher, Nov 12: "We need to resolve this cause it is on the website too. "DJ in plain English"? "DJ speak
translated" "DJ lingo in plain words" Something like that". Resolved as "DJ speak, in plain words." It is the
dictionary panel's line here, the dictionary page's lede, title and description, and the film's second dictionary
caption.
