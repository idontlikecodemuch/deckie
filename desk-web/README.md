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
  lavender accent), laid out as a desktop window; every value is a variable in its `:root` block.

## Words and design values (D36)

- **Words**: every word the pages show comes from one list, `DeskWords` in `../core/Sources/DeckieDesk/DeskWords.swift`
  (the Mac's Desk shows the same list), sent by the engine in its first message. Elements with `data-w` get the word of
  that name; desk.js and run.js ask for words by name with `t("name", { blank: value })`. Words built from parts are
  templates there with named blanks (`"songsCaption": "{crate}, {songs}"`); the separators between items are words
  too (`join.*`), and so are the marks desk.css draws with `content` (`glyph.*`, handed in as `--glyph-*`). The only
  words the pages hold are `PAGE_WORDS` at the top of desk.js, shown when the engine's are not there.
- **Design values**: every colour, size, space, type value, corner, shadow, opacity and time is a custom property in
  the one `:root` block at the top of `desk.css`, named by what it is for. The rules below it, and run.js's drawing,
  read them (`var(--name)`; `css()`, `num()`, `time()` in run.js); they hold none of their own.
- **To change one**: a word, in DeskWords' table (then rebuild the engine); a design value, in `desk.css`'s `:root`.
- **The rule**: the pages' scripts, index.html and desk.css's rules hold neither words nor design values. The core's
  `VariablesTests` fail when one creeps back in.

Keyboard: every action is a button; menus open with the arrow keys and close with Escape; a title or artist is fixed
in place with Enter or F2 (Escape leaves it); Ctrl+Z and Ctrl+Shift+Z (or Ctrl+Y) undo and redo. The run's progress is
a progress bar with its count read out, and the progress is said politely every tenth of the run or every minute. The wall of waves takes the focus: the arrow keys, Home and End move along its songs and say each one.

Opened in an ordinary browser the pages say they belong in Desk's window: they need the shell for the engine.
