# Deckie Desk's pages (Windows and Linux)

Plain HTML, CSS and JavaScript, no framework, no build step, nothing fetched from the network. Shown by the window in
`../desk-shell/` (D32).

- `index.html`: every screen: the first screen, the run, the finished screen, the songs, the sources panel, the
  crate menu, and the dialogs.
- `desk.js`: draws what the engine says and sends what the DJ does (`../docs/architecture/desk-protocol.md`). No
  Deckie logic and no words: the words arrive in the engine's first message, from `DeskWords` in the core, the list
  the Mac's Desk uses too. Elements with `data-w` get the word of that name.
- `desk.css`: the look of the site and the booth (`../site/site.css`'s tokens: flat dark page, rounded surfaces, one
  lavender accent), laid out as a desktop window.

Keyboard: every action is a button; menus open with the arrow keys and close with Escape; a title or artist is fixed
in place with Enter or F2 (Escape leaves it); Ctrl+Z and Ctrl+Shift+Z (or Ctrl+Y) undo and redo. The run's progress is
a progress bar with its count read out.

Opened in an ordinary browser the pages say they belong in Desk's window: they need the shell for the engine.
