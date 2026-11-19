# Roadmap

What is planned, in rough order. Decisions live in `00-decisions.md`; this file is the list of work, not the
reasons. Items under "Recorded ideas" are written down so they are not lost; they are not agreed work.

Last updated: Nov 19, 2026.

## Now: the first test build

- Deckie Booth for iPad through TestFlight, with Apple's beta review, for outside testers.
- Deckie Desk sent to testers as files: a download for Mac (signed and notarised) and a zip for Windows.
- Booth opens on a screen that says what it does and what to do when no crate file is open.
- A demo: a small crate of freely licensed songs inside Booth, and a page on the site that plays them.
- A credits screen in both apps; the key model bundled in Desk.
- Tester notes, the review notes and a privacy page.

## Next

- The loading screen layout in Desk, the quick start, and the dictionary inside Desk.
- "Look up by sound" in Desk.
- The faster listener in Booth, after a test on a whole library; the "coming in" reading shown in Booth.
- Booth on a Mac laptop, as the iPad app in its own window (to be tried).
- Desk on Windows: signing, and a first launch that shows something at once.
- Real discs and sticks tested on Mac and Windows.

## Consistency: one source of truth

There are three Desks (Mac, Windows, Linux), one Booth and a website, all meant to share one visual language.
Today each holds its own copy of it, so a change to a colour, a corner radius, a shadow or a font is made five
times and can drift.

- **Design audit and inventory.** List every colour, type size, weight, spacing step, radius, shadow, icon and
  component in each of the five, and where they differ.
- **One set of design tokens.** A single file of named values (colours, type, spacing, radius, shadow, motion)
  that the Swift apps, the web pages of Desk and the site all read, so a change is made once.
- **One description of the interface.** For each feature and element: what it is, where it appears in each
  product, its states, and what it touches. When something is added, this says what else has to change. The
  word list is already shared this way; the interface should be too.
- **The type audit**, already begun, finished as part of the inventory.

## Later

- Booth inside Desk on a computer (many DJs bring a laptop, and the crate file is already on it); Booth for
  Windows is a rebuild, not a port.
- Desk inside Booth on the iPad: build a crate from a stick, or from music played into the iPad, for a DJ with
  no computer.
- The album workflow.
- Speed and memory work on the engine.

## Recorded ideas

Not agreed, not designed. Written down as heard.

- **The brake.** A transition seen in a set of 90s and 2000s songs: the playing song is slowed all the way to
  a stop, a beat of silence, then another song starts. Powerful, probably valuable even if not common. Booth
  does not suggest it today. It could be an option a DJ turns on. It needs a word; DJs say "brake" or "power
  down" for the slow-to-a-stop, which is different from a breakdown (a quiet section inside a song).
- **What comes after a brake.** Because the music stops, the next song need not match in tempo or key: truly
  any song could follow, though the same style, the same era or the same artist would feel most natural, or a
  random one.
- **Roll the dice.** A big button, or an occasional suggestion, that offers a brake and a surprise next song.
- **A practice game.** Most DJs play with their music at home. For someone new, returning or just bored, a
  game mode in the manner of a rhythm game: Booth sets a mix to make and scores how it went.
