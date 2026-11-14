# Deckie Desk's pages (Windows and Linux)

Plain HTML, CSS and JavaScript, no framework, no build step, nothing fetched from the network. Shown by the window in
`../desk-shell/` (D32).

- `index.html`: every screen: the first screen, the run, the finished screen, the songs, the sources panel, the
  crate menu, and the dialogs.
- `desk.js`: draws what the engine says and sends what the DJ does (`../docs/architecture/desk-protocol.md`). No
  Deckie logic and no words: the words arrive in the engine's first message, from `DeskWords` in the core, the list
  the Mac's Desk uses too. Elements with `data-w` get the word of that name.
- `run.js`: the run screen (D37): the song Desk just read on stage with its wave and what Desk found, the figures
  counted so far (music read, a tempo histogram, a wheel of keys), the crate as a wall of waves, the quiet line and
  the moments, from the engine's `run.songs`. Throttled, still while the window is hidden, and still under reduced
  motion; its colours, sizes and times are `desk.css`'s run-screen variables.
- `desk.css`: the look of the site and the booth (`../site/site.css`'s tokens: flat dark page, rounded surfaces, one
  lavender accent), laid out as a desktop window.

Keyboard: every action is a button; menus open with the arrow keys and close with Escape; a title or artist is fixed
in place with Enter or F2 (Escape leaves it); Ctrl+Z and Ctrl+Shift+Z (or Ctrl+Y) undo and redo. The run's progress is
a progress bar with its count read out, and the progress is said politely every tenth of the run or every minute. The wall of waves takes the focus: the arrow keys, Home and End move along its songs and say each one.

Opened in an ordinary browser the pages say they belong in Desk's window: they need the shell for the engine.
