// Deckie Desk's window on Windows and Linux (D32): draws what the engine says and sends what the DJ does
// (docs/architecture/desk-protocol.md). No Deckie logic and no words of its own: the words arrive in the engine's
// first message (DeskWords), and every rule (which crate shows, undo, naming a source) is the engine's.
(function () {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const el = (tag, props, ...kids) => {
    const e = document.createElement(tag);
    if (props) for (const [k, v] of Object.entries(props)) {
      if (v == null || v === false) continue;
      if (k === "text") e.textContent = v;
      else if (k === "on") for (const [ev, fn] of Object.entries(v)) e.addEventListener(ev, fn);
      else if (k === "class") e.className = v;
      else e.setAttribute(k, v === true ? "" : v);
    }
    for (const kid of kids) if (kid != null) e.append(kid);
    return e;
  };

  /// A number from desk.css's :root (a time in milliseconds, written there without its unit).
  const num = (name) => parseFloat(getComputedStyle(document.documentElement).getPropertyValue(name));
  /// One of index.html's drawings (`icon-<name>`), at the size its class gives it.
  const icon = (name, cls) => {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("class", cls || "way-icon"); svg.setAttribute("aria-hidden", "true");
    const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
    use.setAttribute("href", `#icon-${name}`);
    svg.append(use);
    return svg;
  };

  // ---- words (DeskWords' rules: {name} blanks, name.zero/one/other by count, name.<code> by code)
  // The only words the pages hold: they show when the engine's words are not there (the pages opened in a browser) or
  // may not be the words this page knows (another protocol). Every other word is DeskWords', from the engine.
  const PAGE_WORDS = {
    notInShell: "Deckie Desk's pages open inside Deckie Desk's window (deckie-desk), which starts the engine.",
    protocol: "Protocol {protocol} is not one this window knows ({known}).",
  };
  let W = {};
  const fill = (tpl, v) => tpl.replace(/\{(\w+)\}/g, (m, k) => (v && v[k] != null ? String(v[k]) : m));
  // {thisComputer} in any word: "this Mac" or "this computer", by the kind the engine says this computer is.
  let computer = "other";
  const withComputer = (v) => Object.assign({ thisComputer: W["thisComputer." + computer] ?? W["thisComputer.other"] ?? "" }, v || {});
  const t = (key, v) => fill(W[key] ?? key, withComputer(v));
  const n = (key, count, v) => {
    const form = count === 0 && W[key + ".zero"] != null ? "zero" : count === 1 ? "one" : "other";
    return fill(W[key + "." + form] ?? W[key + ".other"] ?? key, withComputer(Object.assign({ n: String(count) }, v || {})));
  };
  const coded = (key, code) => W[key + "." + code] ?? fill(W[key + ".other"] ?? code, { code });
  const reason = (code) => W["reason." + code] ?? code.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
  const keyFrom = (code) => coded("keyFrom", code);
  const programName = (code) => coded("programName", code);
  const duration = (s) => {
    const all = Math.round(s);
    if (all < 60) return n("seconds", all);
    const m = Math.floor(all / 60), r = all % 60;
    return r === 0 ? n("minutes", m) : t("durationJoin", { minutes: n("minutes", m), seconds: n("seconds", r) });
  };
  const rate = (pm) => (pm >= 10 ? pm.toFixed(0) : pm.toFixed(1));
  const mmss = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
  const two = (x) => String(x).padStart(2, "0");
  const timeLeft = (s) => (s < 45 ? t("timeLeftUnderMinute") : n("timeLeft", Math.max(1, Math.round(s / 60))));

  /// The words of a chooser's buttons, for the shell (where the system's chooser takes them: Linux's GTK).
  const chooserWords = (folders) => ({ accept: t(folders ? "shell.choose" : "shell.open"), cancel: t("shell.cancel") });
  /// Items joined by the word named `key` (DeskWords' join.*): the separators are words too.
  const join = (key, items) => items.join(t(key));
  // A numbered list of words (name.1, name.2, ... to the first gap), as DeskWords.list.
  const list = (prefix) => { const out = []; for (let i = 1; W[prefix + "." + i] != null; i++) out.push(t(prefix + "." + i)); return out; };

  function applyWords(root) {
    for (const e of root.querySelectorAll("[data-w]")) e.textContent = t(e.dataset.w);
    for (const e of root.querySelectorAll("[data-w-label]")) e.setAttribute("aria-label", t(e.dataset.wLabel));
    for (const e of root.querySelectorAll("[data-w-title]")) e.title = t(e.dataset.wTitle);
    document.title = t("appName");
    // The marks desk.css draws with `content` (a menu's tick, a folder, the sort arrows) are words too: handed to the
    // CSS as custom properties, so the style sheet holds none.
    for (const [prop, key] of [["--glyph-checked", "glyph.checked"], ["--glyph-folder", "glyph.folder"],
                               ["--glyph-sort-up", "glyph.sortUp"], ["--glyph-sort-down", "glyph.sortDown"]]) {
      document.documentElement.style.setProperty(prop, JSON.stringify(t(key)));
    }
  }

  // ---- what the engine said last; the page keeps nothing else beyond what is on screen
  let hello = null, state = null, songs = null;
  let run = null;          // the run going: { read, crateName, done, total, stage, remaining, lines }
  let finished = null;     // the finished screen's report, until the DJ moves on
  let exportedPath = null; // where the last crate file went, shown on the finished screen
  let onlyNeedName = false, showSources = false;
  let sort = { key: "title", dir: 1 };
  let selected = null;
  const dropQueue = [];
  // Adding music (research AE): the count going (its path, name and the crate name typed meanwhile), and the run's
  // report when Stop ended it.
  let adding = null;

  // ---- talking: to the shell, which passes the engine's lines through
  const shell = window.deckieShell;
  const replies = new Map();
  let nextId = 1;
  function request(type, fields, opts) {
    const id = nextId++;
    const msg = Object.assign({ id, type }, fields || {});
    return new Promise((resolve) => {
      replies.set(id, (r) => {
        if (!r.ok && !(opts && opts.quiet)) showError(r.error || {}, opts && opts.errorWord);
        resolve(r);
      });
      shell.send(JSON.stringify(msg));
    });
  }
  window.desk = { request, render: () => render() };   // for the shell's tour and for tests

  // The run screen (D37, run.js): the song on stage, the figures, the wall of waves, the quiet line and the moments.
  const politely = (text) => { const a = $("run-announce"); a.textContent = ""; setTimeout(() => { a.textContent = text; }, 30); };
  const screen = window.DeskRunScreen({ $, el, t, n, mmss, list, timeLeft, announce: politely });

  function showError(e, word) {
    if (e.code === "busy") return;
    let text;
    if (e.code === "engine_missing") text = t("engineMissing", { detail: e.detail || "" });
    else if (word) text = t(word, { detail: e.detail || "" });
    else text = e.detail || e.code || "";
    message([text]);
  }

  function receive(m) {
    if (m.re != null && replies.has(m.re)) { const f = replies.get(m.re); replies.delete(m.re); f(m); return; }
    switch (m.event) {
      case "hello":
        hello = m; W = m.words || {}; computer = m.computer || "other";
        applyWords(document);
        if (m.protocol !== 2) message([fill(PAGE_WORDS.protocol, { protocol: m.protocol, known: 2 })]);
        break;
      case "state":
        if (undoLine && state && m.undo !== state.undo && m.undo !== "undoNames" && m.undo !== "undoCheck" && m.undo !== "undoLookup") undoLine = null;
        if (state && state.current && (!m.current || m.current.id !== state.current.id)) { stopListening(); selected = null; undoLine = null; dropCovers(); }
        state = m; break;
      case "songs": songs = m; tidyCovers(); break;
      case "run.started":
        dropCovers();
        finished = null; exportedPath = null; stopListening(); $("run-log").replaceChildren();
        run = { read: m.read, crateName: m.crateName, done: 0, total: 0, stage: "reading", remaining: null, lines: [] };
        askDisc(m.askName);
        screen.start(m);
        break;
      case "audio.chunk":
        audioChunk(m); return;
      case "lookup.started":
        if (lookup) { lookup.step = "progress"; lookup.progress = { done: 0, total: m.songs, found: 0 }; drawLookup(); }
        return;
      case "lookup.progress":
        if (lookup) { lookup.progress = { done: m.done, total: m.total, found: m.found }; drawLookup(); }
        return;
      case "lookup.finished":
        lookupFinished(m); return;
      case "run.songs":
        if (run) screen.songs(m);
        return;
      case "run.progress":
        if (!run) break;
        Object.assign(run, { done: m.done, total: m.total, stage: m.stage, remaining: m.remaining });
        if (m.line) addLine(m.line);
        updateRun(); screen.progress(run); return;
      case "run.finished":
        dropCovers();
        run = null; finished = m.report; $("disc-ask").hidden = true; announce(t("finishedTitle", { read: m.report.read, crate: m.report.crate }));
        setTimeout(nextDrop, 0);
        break;
      case "run.failed":
        dropCovers();
        run = null; message([t("runStopped", { detail: m.detail || "" })]);
        break;
      case "shell.dropped":
        for (const p of m.paths || []) dropQueue.push(p);
        nextDrop();
        break;
      case "add.counting":
        if (adding && samePath(adding.path, m.path || "")) { adding.songs = m.songs; drawCounting(); }
        return;
      case "add.counted":
        counted(m); return;
      case "shell.engineGone":
        run = null; message([t("engineGone")]);
        break;
    }
    render();
  }
  if (shell) shell.onmessage = (text) => { try { receive(JSON.parse(text)); } catch (e) { console.error(e, text); } };

  // ---- the run's list
  function addLine(l) {
    let s;
    if (l.kind === "started") s = n("lineStarted", l.files, { unchanged: l.unchanged, queued: l.queued });
    else if (l.kind === "read") s = t("lineRead", { rel: l.rel, seconds: Number(l.seconds).toFixed(1) });
    else if (l.kind === "reused") s = t("lineReadBefore", { rel: l.rel });
    else if (l.kind === "notRead") s = t("lineNotRead", { rel: l.rel, reason: reason(l.reason).toLowerCase() });
    else if (l.kind === "discDamaged") s = t("lineDiscDamaged", { number: l.number });
    if (!s) return;
    run.lines.push(s);
    if (run.lines.length > 400) run.lines.shift();
    const log = $("run-log");
    log.append(el("li", { text: s, title: s }));
    while (log.children.length > 400) log.firstChild.remove();
    log.scrollTop = log.scrollHeight;
  }

  function updateRun() {
    if (!run) return;
    $("run-reading").textContent = t("runReading", { read: run.read, crate: run.crateName });
    const bar = $("run-bar");
    if (run.total > 0) {
      const pct = Math.round((run.done / run.total) * 100);
      bar.classList.remove("waiting");
      bar.firstElementChild.style.width = pct + "%";
      bar.setAttribute("aria-valuenow", String(pct));
      bar.setAttribute("aria-valuetext", n("songsOf", run.total, { done: run.done, total: run.total }));
      $("run-count").textContent = n("songsOf", run.total, { done: run.done, total: run.total });
    } else {
      bar.classList.add("waiting"); bar.removeAttribute("aria-valuenow"); $("run-count").textContent = "";
    }
    $("run-stage").textContent = t({ reading: "stageReading", finishing: "stageFinishing", saving: "stageSaving" }[run.stage] || "stageReading");
    $("run-left").textContent = run.remaining != null ? timeLeft(run.remaining) : "";
  }

  // ---- drawing
  function show(id) {
    for (const s of ["first", "run", "finished", "crate"]) $(s).hidden = s !== id;
    $("crate-add").hidden = true;
  }
  const current = () => (state && state.current) || null;
  const hasSongs = () => !!(current() && current().hasSongs && songs && songs.crate === current().id);

  /// The crate's name as the window shows it: the crate showing (with a name given during a run), or the new crate's.
  const shownName = () => (current() ? current().name : (state && state.newName) || t("defaultCrateName"));

  function render() {
    if (!hello || !state) return;
    const c = current();
    const busy = !!run || state.running;
    $("crate-name").textContent = shownName();
    $("run-name").textContent = shownName();
    $("crate-button").disabled = busy;
    $("add-label").textContent = t("addMusic");
    $("add-button").disabled = busy || (hello.analysis && !hello.analysis.ready);
    drawWays($("first-ways"), true, $("add-button").disabled);
    $("run-stop").disabled = !!state.stopping;
    $("run-stopping").hidden = !state.stopping;
    if (document.activeElement !== $("first-name")) $("first-name").value = state.newName || "";
    $("more-button").disabled = busy;
    $("undo").disabled = busy || !state.undo;
    $("redo").disabled = busy || !state.redo;
    $("undo").textContent = state.undo ? t("undoNamed", { action: t(state.undo) }) : t("undo");
    $("redo").textContent = state.redo ? t("redoNamed", { action: t(state.redo) }) : t("redo");
    const songsHere = hasSongs();
    $("sources-button").hidden = !songsHere;
    $("sources-button").disabled = busy;
    $("sources-button").textContent = showSources ? t("hideSources") : t("sources");
    $("sources-button").setAttribute("aria-pressed", String(showSources));
    $("log-button").hidden = !songsHere;
    $("log-button").disabled = busy;
    $("export-button").hidden = !songsHere;
    $("export-button").disabled = busy;

    // a run that stopped
    const p = state.pending;
    $("pending").hidden = !p || busy;
    if (p) {
      $("pending-text").textContent = p.here ? t("stoppedReading", { read: p.name })
        : t("pendingLine", { stopped: t("stoppedReading", { read: p.name }), putBack: t(p.musicCD ? "putDiscBack" : "putBack", { read: p.name }) });
      $("carry-on").hidden = !p.here;
    }

    if (busy) { show("run"); updateRun(); $("status").hidden = true; return; }
    if (finished) { show("finished"); drawFinished(); $("status").hidden = true; return; }
    if (songsHere) {
      show("crate"); drawCrate();
      $("crate-add").hidden = false;
      $("crate-add-label").textContent = t("addMoreMusicTo", { crate: shownName() });
      drawWays($("crate-ways"), false, busy);
      return;
    }
    show("first");
    $("status").hidden = true;
    $("first-body").textContent = t("firstBody");
    if (hello.analysis && !hello.analysis.ready) $("first-body").textContent = t("firstBodyEngineMissing", { body: t("firstBody"), missing: t("engineMissing", { detail: "" }) });
  }

  function drawFinished() {
    const r = finished;
    // The name the DJ gave the disc while it was read replaces the placeholder the report was written with.
    const named = (x) => (discRenamed && x === discRenamed.from ? discRenamed.to : x);
    const stopped = r.stopped === true;
    $("finished-title").textContent = stopped ? n("stoppedTitle", r.went_in, { read: named(r.read), crate: named(r.crate) })
      : t("finishedTitle", { read: named(r.read), crate: named(r.crate) });
    $("finished-stopped").hidden = !stopped;
    $("finished-carryon").hidden = !(stopped && state.pending && state.pending.here);
    // Take this back out: the source just read, while it is in the crate (research AE, problem 13).
    $("finished-takeout").hidden = !(current() && (current().sources || []).includes(named(r.read)));
    screen.finished(Object.assign({}, r, { read: named(r.read) }));
    const box = $("finished-summary");
    box.replaceChildren();
    const line = (text, cls) => box.append(el("p", { text, class: cls }));
    const notIn = Object.values(r.not_in || {}).reduce((a, b) => a + b, 0);
    line(notIn === 0 ? t("everySongWentIn") : n("wentIn", r.went_in));
    if (notIn > 0) {
      line(n("didntGoIn", notIn));
      for (const k of Object.keys(r.not_in).sort()) line(t("reasonCount", { reason: reason(k), n: r.not_in[k] }), "indent");
    }
    if (r.folders_left_out > 0) line(n("foldersLeftOut", r.folders_left_out), "mut");
    const local = r.local;
    if (local) {
      const rep = local.report || {};
      const counts = Object.entries(rep.keys_from || {}).sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1));
      if (counts.length) line(t("keysLine", { counts: join("join.keysCounts", counts.map(([k, c]) => t("keysCount", { n: c, from: keyFrom(k) }))) }));
      if (rep.keys_not_read > 0) line(n("keysNone", rep.keys_not_read));
      // Deckie's own reader (D33, D36): of the songs with no key, those it is not sure of; and those with a home note.
      if (rep.keys_not_sure > 0) line(n("keysNotSure", rep.keys_not_sure), "indent");
      if (rep.keys_home_note > 0) line(n("keysHomeNote", rep.keys_home_note));
      if (rep.keys_disagree > 0) line(n("keysDisagree", rep.keys_disagree));
      // The count is the list's (letter AA, 3.2): no title, no artist, or Desk's guess.
      const need = songs && songs.crate === (current() && current().id) ? songs.songs.filter((x) => x.needsName).length : rep.need_name;
      const d = r.disc;
      if (d && d.text !== "names") line(t(d.text === "none" ? "discNoNames" : "discDriveNoNames"));
      if (d && d.named > 0) line(n("discNamed", d.named));
      const named = el("p", { text: need ? t("needNameLead", { needName: n("needName", need) }) : t("everySongHasAName") });
      if (need) named.append(el("button", { class: "link", text: t(d && d.text !== "names" ? "nameThem" : "showThem"),
        on: { click: () => { onlyNeedName = true; finished = null; render(); } } }));
      box.append(named);
      if (need) line(t("needNameHelp"), "mut");
      if (d && d.damaged_sectors > 0) line(t("discDamaged"), "mut");
      if ((local.libraries || []).length) line(t("librariesRead", { names: join("join.libraries", local.libraries.map((l) => programName(l.program))) }), "mut");
      for (const f of local.failed || []) line(t("couldntReadLibrary", { detail: f }), "mut");
      if (local.rekordbox_locked) line(t("rekordboxLocked"), "mut");
      if (local.rekordbox_export) line(t("rekordboxExportNotRead"), "mut");
    }
    line(t("took", { duration: duration(r.seconds), rate: rate(r.songs_per_minute) }), "mut");
    $("finished-log").hidden = !(notIn > 0 || r.damaged > 0);
    $("exported").hidden = !exportedPath;
    if (exportedPath) $("exported-text").textContent = t("exportedTo", { folder: parentOf(exportedPath) });
  }

  const parentOf = (p) => p.replace(/[\\/][^\\/]*[\\/]?$/, "") || p;

  // ---- the songs table
  const columns = [
    { key: "listen", word: "listen", get: () => "", cell: listenCell, label: true, nosort: true },
    { key: "why", word: "colWhy", get: (s) => (s.nameReason ? t("nameReason." + s.nameReason) : ""), cls: "why", onlyNeed: true },
    { key: "title", word: "colTitle", get: (s) => s.title, edit: "title", guess: "title" },
    { key: "artist", word: "colArtist", get: (s) => s.artist || "", edit: "artist", guess: "artist" },
    { key: "bpm", word: "colTempo", get: (s) => s.bpm, show: (s) => (s.bpm != null ? s.bpm.toFixed(1) : t("none")), num: true },
    { key: "key", word: "colKey", get: (s) => (s.key ? s.key.camelot : s.homeNote ? s.homeNote.camelot[0] : ""), cell: keyCell },
    { key: "keyFrom", word: "colKeyFrom", get: (s) => (s.key ? programName(s.key.from) : ""), title: keyHelp, cls: "mut" },
    { key: "seconds", word: "colLength", get: (s) => s.seconds, show: (s) => mmss(s.seconds), num: true },
    { key: "where", word: "colWhere", get: (s) => join("join.places", placeLines(s)), title: (s) => placeLines(s).join("\n") },
    { key: "notes", word: "colNotes", get: (s) => notes(s), cls: "mut" },
  ];

  function placeLines(s) {
    return s.places.map((p) => p.line || (p.folder ? p.folder : t("topOfMusicFolder")));
  }
  function keyHelp(s) {
    // No key: the home note alone (D36), a song Deckie read and is not sure of (D33), or a key not read here.
    if (!s.key && s.homeNote) return t("homeNoteHelp", { minor: s.homeNote.camelot[0], major: s.homeNote.camelot[1] });
    if (!s.key) return t(s.keyState === "not_sure" ? "keyDeckieNotSure" : "keyNotRead");
    return join("join.keyHelp", [t("keyHelpFirst", { camelot: s.key.camelot, from: keyFrom(s.key.from) })].concat(s.key.others.map((o) => t("keySays", { program: programName(o.from), camelot: o.camelot }))));
  }
  function keyCell(s, td) {
    td.textContent = s.key ? s.key.camelot : s.homeNote ? t("homeNote", { note: s.homeNote.note }) : t("none");
    td.title = keyHelp(s);
    if (s.key && s.key.uncertain) td.append(" ", el("span", { class: "unsure", text: t("glyph.notSure"), title: t("notSureOfKey"), "aria-label": t("notSureOfKey") }));
  }
  function notes(s) {
    return join("join.notes", s.notes.map((c) => ({ needsName: t("needsNameNote"), damagedFrames: n("damagedFrames", s.damagedFrames),
      gridUnsure: t("gridUnsure"), vocalsNotRead: t("vocalsNotRead"), signed: t("signed") }[c] || c)));
  }

  const shownColumns = () => columns.filter((c) => !c.onlyNeed || onlyNeedName);

  function drawCrate() {
    const c = current();
    // the header, once per draw (cheap)
    const head = $("songs-head");
    head.replaceChildren(...shownColumns().map((col) => {
      const th = el("th", { scope: "col", "aria-sort": sort.key === col.key ? (sort.dir > 0 ? "ascending" : "descending") : "none" });
      if (col.label) th.append(el("span", { class: "sr", text: t(col.word) }));
      else th.append(el("button", { text: t(col.word), on: { click: () => { sort = { key: col.key, dir: sort.key === col.key ? -sort.dir : 1 }; drawCrate(); } } }));
      return th;
    }));
    let list = songs.songs.slice();
    if (onlyNeedName) list = list.filter((s) => s.needsName);
    const col = columns.find((x) => x.key === sort.key);
    list.sort((a, b) => {
      const x = col.get(a), y = col.get(b);
      if (x == null && y == null) return 0;
      if (x == null) return -sort.dir;
      if (y == null) return sort.dir;
      return (typeof x === "number" ? x - y : String(x).localeCompare(String(y), undefined, { sensitivity: "base", numeric: true })) * sort.dir;
    });
    const body = $("songs-body");
    const focusId = document.activeElement && document.activeElement.closest && document.activeElement.closest("td") ?
      [document.activeElement.closest("tr").dataset.id, document.activeElement.closest("td").dataset.col] : null;
    body.replaceChildren(...list.map((s) => songRow(s)));
    $("songs").setAttribute("aria-rowcount", String(list.length + 1));
    $("songs-caption").textContent = t("songsCaption", { crate: c.name, songs: n("songs", songs.songs.length) });
    $("songs-empty").hidden = list.length > 0;
    $("songs-empty").textContent = list.length ? "" : t("everySongHasAName");
    visibleOrder = list.map((x) => x.id);
    if (focusId) { const td = body.querySelector(`tr[data-id="${CSS.escape(focusId[0])}"] td[data-col="${focusId[1]}"]`); if (td) td.focus(); }

    // the line at the bottom
    $("status").hidden = false;
    $("status-songs").textContent = n("songs", songs.songs.length);
    $("status-unsigned").textContent = songs.unsigned > 0 ? t("cantBeRecognised", { n: songs.unsigned }) : "";
    const unnamed = songs.songs.filter((s) => s.needsName).length;
    const nn = $("status-needname");
    nn.hidden = !(unnamed > 0 || onlyNeedName);
    nn.textContent = onlyNeedName ? t("showAllSongs") : n("needNameCount", unnamed);
    nn.setAttribute("aria-pressed", String(onlyNeedName));
    $("status-only").hidden = !onlyNeedName;
    const ni = $("status-notin");
    ni.hidden = !(songs.notIn > 0);
    ni.textContent = n("filesDidntGoIn", songs.notIn);

    $("side").hidden = !showSources;
    if (showSources) drawSources();
    drawNeedBar(list);
    drawNames();
    drawPlayer();
    drawUndoLine();
  }

  function songRow(s) {
    const tr = el("tr", { "data-id": s.id, "aria-selected": String(selected === s.id) });
    tr.addEventListener("click", () => select(s.id));
    for (const col of shownColumns()) {
      const guess = col.guess && s.names && s.names[col.guess] && s.names[col.guess].guess;
      const td = el("td", { "data-col": col.key, class: [col.num ? "num" : "", col.cls || "", col.edit ? "editable" : "", guess ? "guess" : ""].join(" ").trim() || null });
      if (col.cell) col.cell(s, td);
      else td.textContent = col.show ? col.show(s) : col.get(s);
      if (col.title) td.title = col.title(s);
      if (col.edit) {
        td.tabIndex = 0;
        td.setAttribute("aria-label", t("cellLabel", { column: t(col.word), value: col.get(s) || t("none") }));
        td.addEventListener("dblclick", () => editCell(td, s, col));
        td.addEventListener("keydown", (e) => {
          if (e.key === "Enter" || e.key === "F2") { e.preventDefault(); editCell(td, s, col); }
          else if (e.key === "ArrowDown" || e.key === "ArrowUp") {
            e.preventDefault();
            const row = e.key === "ArrowDown" ? tr.nextElementSibling : tr.previousElementSibling;
            const next = row && row.querySelector(`td[data-col="${col.key}"]`);
            if (next) next.focus();
          } else if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
            const other = tr.querySelector(`td[data-col="${col.key === "title" ? "artist" : "title"}"]`);
            if (other) { e.preventDefault(); other.focus(); }
          }
        });
      }
      tr.append(td);
    }
    return tr;
  }

  // A name fix in place: Enter or leaving the field keeps it (one step of undo), Escape leaves it as it was.
  function editCell(td, s, col) {
    if (td.querySelector("input")) return;
    const before = col.get(s) || "";
    const input = el("input", { type: "text", value: before, "aria-label": t(col.word) });
    input.value = before;
    td.replaceChildren(input);
    input.focus(); input.select();
    let done = false;
    const finish = (keep) => {
      if (done) return; done = true;
      const v = input.value.trim();
      if (keep && v !== before && !(col.edit === "title" && !v)) {
        request("song.fix", { song: s.id, [col.edit]: v }, { errorWord: "couldntSave" });
      } else { td.textContent = before || ""; td.focus(); }
    };
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); finish(true); }
      else if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); finish(false); }
    });
    input.addEventListener("blur", () => finish(true));
  }

  // ---- naming a song (research AA, route A): the panel for one song, Listen, the list and its tools
  let visibleOrder = [];
  let undoLine = null;      // { text } after a batch of names, until the next change
  let offer = null;         // { song, text, split } while "Split into artist, title and version?" is asked

  function select(id) {
    if (selected !== id) { offer = null; if (listening && listening.song !== id) stopListening(); }
    selected = id;
    for (const r of $("songs-body").children) r.setAttribute("aria-selected", String(r.dataset.id === id));
    drawNames();
  }
  const songById = (id) => (songs && songs.songs.find((x) => x.id === id)) || null;
  const factFrom = (code) => coded("factFrom", code);

  /// The small line under a fact: where it came from; a guess says so; nothing found says so.
  function fromLine(f) {
    if (!f || f.value == null) return { text: t("factNotFound"), guess: false };
    const from = f.from ? factFrom(f.from) : t("factNotFound");
    if (f.checked) return { text: t("factChecked", { from }), guess: false };
    if (f.guess) return { text: t("factGuess", { from }), guess: true };
    return { text: from, guess: false };
  }

  function drawNames() {
    const panel = $("names");
    const s = selected && songById(selected);
    panel.hidden = !s || !hasSongs();
    if (panel.hidden) return;
    const body = $("names-body");
    const keep = document.activeElement && document.activeElement.dataset && document.activeElement.dataset.field;
    body.replaceChildren(coverBox(s));
    const fields = [["title", "title"], ["artist", "artist"], ["version", "version"]];
    fields.forEach(([field, word], i) => {
      const f = s.names ? s.names[field] : { value: s[field], from: s.nameFrom };
      const line = fromLine(f);
      const id = "fact-" + field;
      const input = el("input", { type: "text", id, "data-field": field, autocomplete: "off", spellcheck: "false",
        class: line.guess ? "guess" : null, placeholder: field === "title" ? s.file.replace(/\.[^.]+$/, "") : null });
      input.value = field === "title" && offer && offer.song === s.id ? offer.text : (f && f.value != null ? f.value : "");
      input.addEventListener("keydown", (e) => {
        if (e.key === "Enter") { e.preventDefault(); commitFact(s, field, input, i === fields.length - 1); }
        else if (e.key === "Escape") { e.preventDefault(); input.value = f && f.value != null ? f.value : ""; input.blur(); }
      });
      input.addEventListener("change", () => commitFact(s, field, input, false, true));
      const box = el("div", { class: "fact" }, el("label", { for: id, text: t(word) }), input,
        el("p", { class: "from" + (line.guess ? " guess" : ""), text: line.text }));
      if (field === "title" && offer && offer.song === s.id) {
        box.append(el("div", { class: "offer", role: "group" }, el("p", { text: t("splitOffer") }),
          el("button", { class: "small main", text: t("split"), on: { click: () => {
            const o = offer; offer = null;
            const fix = { song: o.song, title: o.split.title };
            if (o.split.artist) fix.artist = o.split.artist;
            if (o.split.version) fix.version = o.split.version;
            request("song.fix", fix, { errorWord: "couldntSave" });
          } } }),
          el("button", { class: "small", text: t("keepAsTyped"), on: { click: () => {
            const o = offer; offer = null; request("song.fix", { song: o.song, title: o.text }, { errorWord: "couldntSave" });
          } } })));
      }
      body.append(box);
    });
    // A song's facts (D34): release, year, label and genre as fields like the names, each with where it came from;
    // the rest listed, read-only. Everything here goes to the iPad.
    for (const field of ["release", "year", "label", "genre"]) {
      const f = s.names ? s.names[field] : null;
      const id = "fact-" + field;
      const input = el("input", { type: "text", id, "data-field": field, autocomplete: "off", spellcheck: "false",
        placeholder: field === "genre" ? t("genreHint") : null });
      input.value = f && f.value != null ? f.value : "";
      input.addEventListener("keydown", (e) => {
        if (e.key === "Enter") { e.preventDefault(); commitSongFact(s, field, input); }
        else if (e.key === "Escape") { e.preventDefault(); input.value = f && f.value != null ? f.value : ""; input.blur(); }
      });
      input.addEventListener("change", () => commitSongFact(s, field, input));
      body.append(el("div", { class: "fact" }, el("label", { for: id, text: t(field) }), input,
        el("p", { class: "from", text: fromLine(f).text })));
    }
    const others = (s.names && s.names.others) || [];
    if (others.length) {
      body.append(el("div", { class: "fact facts-list" }, el("label", { text: t("moreFacts") }),
        ...others.map((o) => el("p", { class: "value", text: t("moreFactLine", { name: coded("factName", o.name), value: o.value }),
          title: o.from ? factFrom(o.from) : null }))));
    }
    const tags = (s.names && s.names.fileTags) || [];
    const left = Object.keys((s.names && s.names.leftOut) || {});
    if (tags.length || left.length) {
      body.append(el("div", { class: "fact facts-list" }, el("label", { text: t("fileTagsHeading") }),
        ...tags.map((o) => el("p", { class: "mut", text: t("fileTagLine", { name: o.name, value: o.value }) })),
        ...(left.length ? [el("p", { class: "from", text: t("leftOutLine", { what: join("join.leftOut", left.map((r) => coded("leftOut", r))) }) })] : [])));
    }
    body.append(el("div", { class: "fact" }, el("label", { text: t("whereLabel") }),
      ...placeLines(s).map((l, i) => el("p", { class: i ? "mut" : "value", text: l }))));
    body.append(el("p", { class: "facts-line", text: t("lengthLine", { length: mmss(s.seconds) }) }));
    body.append(el("p", { class: "facts-line", text: t("fileLine", { file: s.file }) }));
    const foot = el("div", { class: "foot" });
    foot.append(el("button", { class: "main small", text: listening && listening.song === s.id ? t("stopListening") : t("listen"),
      on: { click: () => (listening && listening.song === s.id ? stopListening() : listen(s)) } }));
    if (s.nameReason === "guess") {
      foot.append(el("button", { class: "small", text: t("looksRight"), title: t("looksRightHelp"),
        on: { click: () => checkSongs([s.id]) } }));
    }
    // "Look up via MusicBrainz" (D36): the one step that uses the internet, in its own colour. The sentence comes
    // the first time; after that it sits under the button, and the button acts at once. A lookup by sound (AcoustID)
    // would sit beside it, feeding the same review.
    foot.append(netButton(t("lookupOne"), () => lookupSong(s)));
    const info = lookupInfo.get(s.id);
    if (info && info.explained && info.what && info.what.length) {
      foot.append(el("p", { class: "lookup-under" }, t("lookupUnderLead", { under: t("lookupUnder", { what: join("join.lookupWhat", info.what.map(([k, v]) => t("lookupWhat." + k, { value: v }))) }) }),
        el("button", { class: "link", type: "button", text: t("lookupSentLink"), on: { click: showSent } })));
    } else if (!info) {
      lookupInfoFor(s.id);
    }
    body.append(foot);
    if (keep) { const k = body.querySelector(`[data-field="${keep}"]`); if (k) k.focus(); }
  }

  // ---- a song's cover (D36): asked for by the song's id, only when the song says it has one, and only for the song
  // whose names are showing. The engine answers with the picture's bytes inside the reply (it is at most 24 KB); the
  // page shows them from a data: address, so it is never told a path and nothing is fetched. A song without a cover,
  // and one whose cover is still on its way, gets an empty square of the same size (desk.css's --cover-size), so the
  // fields below never jump.
  const covers = new Map();   // song id to a data: address, null (asked: none to show) or false (asked, not answered)
  const coversKept = 200;     // the most the page holds on to; the oldest go first
  let coversAge = 0;          // raised when the covers are dropped, so an answer that was on its way is left out

  /// Drops every cover kept: another crate is showing, or a run may have changed the songs' pictures.
  function dropCovers() { covers.clear(); coversAge += 1; }
  /// Drops the covers of songs that are gone or say they have none now.
  function tidyCovers() {
    for (const id of [...covers.keys()]) { const s = songById(id); if (!s || s.cover !== true) covers.delete(id); }
  }

  function coverBox(s) {
    const has = s.cover === true;          // an engine from before D36 sends no `cover`: no cover, and nothing asked
    const kept = has ? covers.get(s.id) : null;
    if (typeof kept === "string") {
      const img = el("img", { src: kept, alt: t("cover"), draggable: "false" });
      const box = el("div", { class: "cover", id: "names-cover" }, img);
      // Bytes the web view cannot draw are no cover.
      img.addEventListener("error", () => { covers.set(s.id, null); if (box.isConnected) box.replaceWith(coverBox(s)); });
      return box;
    }
    if (has && kept === undefined) askCover(s.id);
    // Still on its way: the empty square, said to be nothing yet. None: the same square, labelled.
    return has && kept !== null ? el("div", { class: "cover none", id: "names-cover", "aria-hidden": "true" })
      : el("div", { class: "cover none", id: "names-cover", role: "img", "aria-label": t("noCover") });
  }

  async function askCover(id) {
    const age = coversAge;
    covers.set(id, false);
    const r = await request("song.cover", { song: id }, { quiet: true });
    if (age !== coversAge || covers.get(id) !== false) return;
    // Anything but a JPEG in base64 is no cover: an engine that does not know the request, a missing file.
    const ok = r.ok && r.cover === true && r.type === "image/jpeg" && typeof r.data === "string" && /^[A-Za-z0-9+/]+={0,2}$/.test(r.data);
    covers.set(id, ok ? "data:image/jpeg;base64," + r.data : null);
    while (covers.size > coversKept) covers.delete(covers.keys().next().value);
    // Only the square is redrawn, so a name being typed is not disturbed.
    const box = $("names-cover"), s = songById(id);
    if (selected === id && box && s) box.replaceWith(coverBox(s));
  }

  /// Return on a fact: a change is the DJ's name (one step of undo); Return on Desk's guess as it is checks it; Return
  /// on the last field moves to the next song in the list, so twenty songs can be named without the mouse.
  async function commitFact(s, field, input, last, quiet) {
    const v = input.value.trim();
    const f = s.names ? s.names[field] : null;
    const before = f && f.value != null ? f.value : "";
    if (v !== before && !(field === "title" && !v)) {
      if (field === "title") {
        const sp = await request("name.split", { text: v }, { quiet: true });
        if (sp.ok && sp.split) { offer = { song: s.id, text: v, split: sp }; drawNames(); return; }
      }
      await request("song.fix", { song: s.id, [field]: v }, { errorWord: "couldntSave" });
    } else if (!quiet && f && f.guess && v === before) {
      await request("song.check", { songs: [s.id], field }, { errorWord: "couldntSave" });
    }
    if (last && !quiet) {
      const i = visibleOrder.indexOf(s.id);
      const next = visibleOrder[i + 1] || (onlyNeedName ? visibleOrder.find((x) => x !== s.id) : null);
      if (next) { select(next); const ti = $("fact-title"); if (ti) ti.focus(); }
    }
  }

  /// Return on one of a song's facts (D34): a change is the DJ's (one step of undo); an empty field clears it.
  function commitSongFact(s, field, input) {
    const v = input.value.trim();
    const f = s.names ? s.names[field] : null;
    const before = f && f.value != null ? f.value : "";
    if (v === before) return;
    request("song.fix", { song: s.id, facts: { [field]: v } }, { errorWord: "couldntSave" });
  }

  function checkSongs(ids) {
    request("song.check", { songs: ids }, { errorWord: "couldntSave" }).then((r) => {
      if (r.ok && r.songs) { undoLine = { text: n("namesChecked", r.songs) }; render(); }
    });
  }

  function drawNeedBar(list) {
    $("need-bar").hidden = !onlyNeedName;
    if (!onlyNeedName) return;
    $("need-title").textContent = t("needsNameFilter", { n: list.length });
    const guesses = list.filter((x) => x.nameReason === "guess").map((x) => x.id);
    const b = $("need-check");
    b.hidden = !guesses.length;
    b.textContent = n("looksRightAll", guesses.length);
    b.onclick = () => checkSongs(guesses);
    const l = $("need-lookup");
    l.hidden = !list.length;
    l.replaceChildren(globe(), n("lookupNeedsName", list.length));
    l.onclick = () => openLookup({ scope: "songs" });
  }

  // ---- "Look up songs via MusicBrainz" (D36; letter AA, 3.8 to 3.12). The engine does the lookup; this page only
  // shows the sentence, the count, and the review, and sends back what the DJ ticked.
  let lookup = null;        // { step: "ask"|"progress"|"review", fields, plan, review, choices: Map, progress }
  const lookupInfo = new Map();   // song id -> { explained, what } for the line under the button
  const SVGNS = "http://www.w3.org/2000/svg";
  function globe() {
    const s = document.createElementNS(SVGNS, "svg");
    s.setAttribute("viewBox", "0 0 24 24"); s.setAttribute("fill", "none"); s.setAttribute("stroke", "currentColor");
    s.setAttribute("aria-hidden", "true"); s.setAttribute("class", "net-icon");
    for (const d of ["M3 12h18", "M12 3c2.6 2.8 3.9 5.8 3.9 9s-1.3 6.2-3.9 9c-2.6-2.8-3.9-5.8-3.9-9S9.4 5.8 12 3z"]) {
      const p = document.createElementNS(SVGNS, "path"); p.setAttribute("d", d); s.append(p);
    }
    const c = document.createElementNS(SVGNS, "circle"); c.setAttribute("cx", "12"); c.setAttribute("cy", "12"); c.setAttribute("r", "9"); s.prepend(c);
    return s;
  }
  function netButton(text, onclick, cls) {
    const b = el("button", { class: "small net" + (cls ? " " + cls : ""), type: "button", on: { click: onclick } });
    b.append(globe(), text);
    return b;
  }

  // What one song would send, and whether the sentence was shown once: asked of the engine (nothing leaves).
  const asking = new Set();
  async function lookupInfoFor(id) {
    if (asking.has(id)) return;
    asking.add(id);
    const r = await request("lookup.plan", { scope: "song", song: id }, { quiet: true });
    asking.delete(id);
    if (!r.ok) return;
    lookupInfo.set(id, { explained: r.explained, what: r.plan.what || [], nothing: r.plan.nothingToSend > 0 });
    if (selected === id) drawNames();
  }

  async function lookupSong(s) {
    const r = await request("lookup.plan", { scope: "song", song: s.id }, { errorWord: "couldntOpen" });
    if (!r.ok) return;
    lookupInfo.set(s.id, { explained: r.explained, what: r.plan.what || [], nothing: r.plan.nothingToSend > 0 });
    // Once the sentence has been read, one song is looked up at once; a batch or a disc always asks (letter AA, 3.8).
    if (r.explained && !r.plan.nothingToSend && r.available) { openLookup({ scope: "song", song: s.id }, r, true); return; }
    openLookup({ scope: "song", song: s.id }, r);
  }

  /// The choices the dialog offers: the songs that need a name, the song selected, each source, each music CD.
  function lookupOptions(fields) {
    const out = [];
    const need = songs.songs.filter((x) => x.needsName).length;
    if (need) out.push({ key: "need", label: t("lookupScope.need", { label: t("lookupChoice.needsName"), n: need }), fields: { scope: "songs" } });
    const sel = selected && songById(selected);
    if (sel) out.push({ key: "song:" + sel.id, label: t("lookupScope.song", { label: t("lookupChoice.song"), title: sel.title }), fields: { scope: "song", song: sel.id } });
    for (const src of songs.sources) {
      const disc = (state.discs || []).includes(src.name);
      out.push({ key: (disc ? "disc:" : "source:") + src.name, label: disc ? t("lookupScope.disc", { label: t("lookupDisc").replace(/…$/, ""), source: src.name }) : t("lookupScope.source", { source: src.name, songs: n("songs", src.songs) }),
        fields: disc ? { scope: "disc", source: src.name } : { scope: "songs", source: src.name } });
    }
    const want = fields.scope === "song" ? "song:" + fields.song : fields.scope === "disc" ? "disc:" + fields.source
      : fields.source ? "source:" + fields.source : "need";
    if (!out.some((o) => o.key === want) && fields.scope === "song") {
      const s = songById(fields.song);
      out.unshift({ key: want, label: t("lookupScope.song", { label: t("lookupChoice.song"), title: s ? s.title : "" }), fields });
    }
    return { out, want: out.some((o) => o.key === want) ? want : (out[0] && out[0].key) };
  }

  async function openLookup(fields, planned, goNow) {
    if (!hasSongs()) return;
    lookup = { step: "ask", fields, plan: null, review: null, choices: new Map(), progress: null, available: true };
    const d = $("lookup");
    const sel = $("lookup-scope");
    const { out, want } = lookupOptions(fields);
    sel.replaceChildren(...out.map((o) => el("option", { value: o.key, text: o.label, selected: o.key === want })));
    sel.onchange = () => { const o = out.find((x) => x.key === sel.value); if (o) planLookup(o.fields); };
    $("lookup-scope-wrap").hidden = fields.scope === "song" && out.length < 2;
    drawLookup();
    if (!d.open) d.showModal();
    if (planned) { lookup.plan = planned.plan; lookup.available = planned.available; drawLookup(); }
    else await planLookup((out.find((o) => o.key === want) || {}).fields || fields);
    if (goNow) startLookup();
  }

  async function planLookup(fields) {
    if (!lookup) return;
    lookup.fields = fields;
    const r = await request("lookup.plan", fields, { errorWord: "couldntOpen" });
    if (!lookup || !r.ok) return;
    lookup.plan = r.plan; lookup.available = r.available;
    drawLookup();
  }

  function startLookup() {
    if (!lookup || !lookup.plan) return;
    if (!lookup.available) { lookup.step = "review"; lookup.review = null; lookup.failure = "notOnThisComputer"; drawLookup(); return; }
    lookup.step = "progress";
    lookup.progress = { done: 0, total: lookup.plan.songs, found: 0 };
    drawLookup();
    request("lookup.start", {}, { errorWord: "couldntOpen" }).then((r) => { if (!r.ok && lookup) { lookup.step = "ask"; drawLookup(); } });
  }

  function lookupFinished(m) {
    if (!lookup) lookup = { step: "review", fields: {}, plan: null, choices: new Map() };
    lookup.step = "review"; lookup.review = m.review; lookup.summary = m.summary; lookup.failure = null;
    lookup.choices = new Map();
    for (const s of m.review.songs) {
      if (s.chosen == null) continue;
      const c = s.candidates[s.chosen];
      lookup.choices.set(s.song, { candidate: s.chosen, fields: new Set(c.changes.filter((x) => x.tick && !x.locked).map((x) => x.field)) });
    }
    if (!$("lookup").open) $("lookup").showModal();
    drawLookup();
    announce(m.summary || "");
  }

  function lookupTicked() {
    let total = 0;
    if (lookup && lookup.choices) for (const c of lookup.choices.values()) if (c.candidate >= 0) total += c.fields.size;
    return total;
  }

  function lengthWords(c, song) {
    if (c.seconds == null) return t("lookupLengthUnknown");
    const len = mmss(c.seconds), d = c.difference;
    if (d == null) return len;
    if (Math.abs(d) < 1) return t("lookupLengthSame", { length: len });
    const diff = Math.abs(d) < 60 ? n("seconds", Math.round(Math.abs(d))) : mmss(Math.abs(d));
    return t(d > 0 ? "lookupLengthLonger" : "lookupLengthShorter", { length: len, difference: diff });
  }

  function drawLookup() {
    if (!lookup) return;
    const L = lookup;
    $("lookup-ask").hidden = L.step !== "ask";
    $("lookup-progress").hidden = L.step !== "progress";
    $("lookup-review").hidden = L.step !== "review";
    const go = $("lookup-go"), cancel = $("lookup-cancel");
    go.hidden = false; cancel.hidden = false;
    if (L.step === "ask") {
      $("lookup-title").textContent = t("lookupSheetTitle");
      const box = $("lookup-sentence");
      box.replaceChildren(...((L.plan && L.plan.sentence) || []).map((x, i) => el("p", { text: x, class: i ? "mut" : null })));
      go.textContent = t("lookupGo");
      go.disabled = !L.plan || (L.plan.songs - L.plan.nothingToSend) <= 0;
      cancel.textContent = t("lookupNotNow");
    } else if (L.step === "progress") {
      $("lookup-title").textContent = t("lookupProgressTitle");
      const p = L.progress || { done: 0, total: 0, found: 0 };
      const pct = p.total ? Math.round((p.done / p.total) * 100) : 0;
      const bar = $("lookup-bar");
      bar.firstElementChild.style.width = pct + "%";
      bar.setAttribute("aria-valuenow", String(pct));
      $("lookup-count").textContent = t("lookupCountLine", { progress: n("lookupProgress", p.total, { done: p.done }), found: n("lookupProgressFound", p.found) });
      go.hidden = true;
      cancel.textContent = t("lookupStop");
    } else {
      $("lookup-title").textContent = t("lookupReviewTitle");
      $("lookup-summary").textContent = L.failure ? fill(coded("lookupFailure", L.failure), withComputer()) : (L.summary || "");
      const r = L.review;
      $("lookup-disc").textContent = r && r.scope === "disc" && !r.failure ? coded("lookupDiscMatch", r.discMatch || "none") : "";
      $("lookup-disc").hidden = !$("lookup-disc").textContent;
      drawLookupSongs();
      const total = lookupTicked();
      go.textContent = n("lookupApply", total);
      go.disabled = total === 0;
      cancel.textContent = t("cancel");
    }
  }

  function drawLookupSongs() {
    const box = $("lookup-songs");
    box.replaceChildren();
    const r = lookup.review;
    if (!r) return;
    const single = r.scope === "song";
    for (const s of r.songs) {
      const card = el("section", { class: "lookup-song", "aria-label": s.title });
      card.append(el("h3", null, s.title, el("span", { class: "len", text: t("lookupYourSong", { length: mmss(s.seconds) }) })));
      if (s.outcome !== "found") {
        let text = coded("lookupOutcome", s.outcome);
        if (s.outcome === "nothing" && single) text = t("lookupNothingOne");
        if (s.outcome === "failed" && s.failure) text = t("lookupOutcomeFailed", { outcome: text, failure: fill(coded("lookupFailure", s.failure), withComputer()) });
        card.append(el("p", { class: "outcome", text }));
        box.append(card);
        continue;
      }
      if (s.several) card.append(el("p", { class: "outcome", text: t("lookupSeveral") }));
      else if (s.chosen == null) card.append(el("p", { class: "outcome", text: t("lookupNoneFits") }));
      const choice = lookup.choices.get(s.song) || { candidate: -1, fields: new Set() };
      const table = el("table");
      table.append(el("thead", null, el("tr", null, el("th", null, el("span", { class: "sr", text: t("lookupUseThis") })),
        el("th", { text: t("colTitle") }), el("th", { text: t("colArtist") }), el("th", { text: t("colRelease") }),
        el("th", { text: t("colYear") }), el("th", { text: t("label") }), el("th", { text: t("colLength") }))));
      const tb = el("tbody");
      const pick = (i) => {
        const c = s.candidates[i];
        lookup.choices.set(s.song, { candidate: i, fields: new Set(i < 0 ? [] : c.changes.filter((x) => x.tick && !x.locked).map((x) => x.field)) });
        drawLookup();
      };
      s.candidates.forEach((c, i) => {
        const name = "pick-" + s.song;
        const radio = el("input", { type: "radio", name, value: String(i), "aria-label": t("lookupUseThisLabel", { label: t("lookupUseThis"), title: c.title }) });
        radio.checked = choice.candidate === i;
        radio.addEventListener("change", () => pick(i));
        const notes = join("join.lookupNotes", (c.notes || []).map((x) => coded("lookupNote", x)));
        const tr = el("tr", { class: [c.otherVersion ? "other" : "", choice.candidate === i ? "using" : ""].join(" ").trim() || null },
          el("td", null, radio),
          el("td", null, c.version ? t("lookupCandidateTitle", { title: c.title, version: c.version }) : c.title, notes ? el("div", { class: "notes", text: notes }) : null),
          el("td", { text: c.artist || "" }), el("td", { text: c.release || "" }), el("td", { text: c.year || "" }),
          el("td", { text: c.label || "" }),
          el("td", { class: c.fit === "fits" ? "fits" : c.fit === "off" ? "off" : null, text: lengthWords(c) }));
        tb.append(tr);
      });
      const none = el("input", { type: "radio", name: "pick-" + s.song, value: "-1", "aria-label": t("lookupNoneOfThese") });
      none.checked = choice.candidate < 0;
      none.addEventListener("change", () => pick(-1));
      tb.append(el("tr", null, el("td", null, none), el("td", { colspan: "6", class: "mut", text: t("lookupNoneOfThese") })));
      table.append(tb);
      card.append(table);
      if (choice.candidate >= 0) {
        const c = s.candidates[choice.candidate];
        const ticks = el("div", { class: "ticks", role: "group", "aria-label": t("lookupUsing") });
        for (const ch of c.changes) {
          const box2 = el("input", { type: "checkbox", disabled: ch.locked });
          box2.checked = choice.fields.has(ch.field) && !ch.locked;
          box2.addEventListener("change", () => { if (box2.checked) choice.fields.add(ch.field); else choice.fields.delete(ch.field); drawLookup(); });
          ticks.append(el("label", null, box2, el("span", { text: t("lookupTickField", { field: t(ch.field) }) }),
            ch.before ? el("span", { class: "before", text: t("lookupTickBefore", { before: ch.before }) }) : null, el("span", { text: ch.after || "" }),
            ch.note ? el("span", { class: "note", text: t("lookupTickNote", { note: coded("changeNote", ch.note) }) }) : null));
        }
        if (c.changes.length) card.append(ticks);
      }
      box.append(card);
    }
  }

  $("lookup-go").addEventListener("click", () => {
    if (!lookup) return;
    if (lookup.step === "ask") { startLookup(); return; }
    if (lookup.step === "review" && lookup.review) {
      const choices = [];
      for (const [song, c] of lookup.choices) if (c.candidate >= 0 && c.fields.size) choices.push({ song, candidate: c.candidate, fields: [...c.fields] });
      request("lookup.apply", { choices }, { errorWord: "couldntSave" }).then((r) => {
        if (r.ok && r.songs) { undoLine = { text: n("lookupApplied", r.songs) }; render(); }
      });
      closeLookup();
    }
  });
  function closeLookup() {
    const was = lookup;
    lookup = null;
    if ($("lookup").open) $("lookup").close("cancel");
    if (was && was.step === "review") request("lookup.close", {}, { quiet: true });
    lookupInfo.clear();
    if (selected) drawNames();
  }
  $("lookup-cancel").addEventListener("click", (e) => {
    e.preventDefault();
    if (lookup && lookup.step === "progress") { request("lookup.stop", {}, { quiet: true }); return; }
    closeLookup();
  });
  $("lookup").addEventListener("cancel", (e) => {
    // Escape while it goes stops it (what was found is kept); otherwise it closes.
    e.preventDefault();
    $("lookup-cancel").click();
  });
  $("lookup-sent-link").addEventListener("click", showSent);

  async function showSent() {
    const r = await request("lookup.sent", {}, { errorWord: "couldntOpen" });
    if (!r.ok) return;
    const list = $("sent-list");
    const items = (r.sent || []).slice().reverse();
    list.replaceChildren(...items.map((x) => el("li", null,
      el("div", { text: t("lookupSentLine", { kind: coded("sentKind", x.kind),
        fields: join("join.sentFields", (x.fields || []).map(([k, v]) => fill(coded("sentField", k), { value: v }))) }) }),
      el("div", { class: "mut", text: t("lookupSentAnswer", { time: new Date(x.at).toLocaleString(), answer: coded("sentAnswer", x.answer) }) }),
      el("div", { class: "addr", text: x.address }))));
    $("sent-empty").hidden = items.length > 0;
    $("sent-clear").disabled = items.length === 0;
    const d = $("sent");
    if (!d.open) d.showModal();
  }
  $("sent-clear").addEventListener("click", async () => {
    const r = await request("lookup.clearSent", {}, { errorWord: "couldntSave" });
    if (r.ok) showSent();
  });

  function drawUndoLine() {
    const u = $("undo-line");
    u.hidden = !undoLine || !state.undo;
    if (!u.hidden) $("undo-line-text").textContent = undoLine.text;
  }

  // ---- Listen (D33). The page is never told where a file is: the engine sends the song's sound over the same
  // channel as every other message, in chunks, and it is played from a blob: address only this page can open.
  let listening = null;    // { song, title, token, chunks: [], of, type, kind, decoded, url, start, ready }
  const audio = $("audio");

  async function listen(s, decoded) {
    stopListening();
    const me = { song: s.id, title: s.title, chunks: [], ready: false, decoded: !!decoded };
    listening = me;
    drawPlayer(); drawNames(); markListening();
    const r = await request("song.audio", { song: s.id, decoded: !!decoded }, { quiet: true });
    if (listening !== me) return;
    if (!r.ok) {
      stopListening();
      const e = r.error || {};
      if (e.code === "not_here") message([t("listenPutBack", { source: e.detail || "" })]);
      else if (e.code === "cannot_decode") message([t("listenCantPlay", { kind: e.detail || "" })]);
      else message([t("listenCouldntPlay", { title: s.title, detail: e.detail || "" })]);
      return;
    }
    Object.assign(me, { token: r.token, of: r.chunks, type: r.type, kind: r.kind, start: r.start });
    // A type this web view says it cannot play: ask for it turned into WAV, which every web view plays.
    if (!decoded && !audio.canPlayType(r.type)) { me.token = null; listen(s, true); return; }
    me.chunks.length = r.chunks;
    for (const c of pendingChunks.splice(0)) audioChunk(c);
  }
  const pendingChunks = [];

  function audioChunk(m) {
    const me = listening;
    if (!me) return;
    if (!me.token) { pendingChunks.push(m); return; }
    if (m.token !== me.token) return;
    const bin = atob(m.data);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    me.chunks[m.index] = bytes;
    if (me.chunks.filter(Boolean).length < me.of) { drawPlayer(); return; }
    me.url = URL.createObjectURL(new Blob(me.chunks, { type: me.type }));
    me.chunks = [];
    audio.src = me.url;
    audio.onloadedmetadata = () => {
      if (listening !== me) return;
      me.ready = true;
      try { audio.currentTime = Math.min(me.start || 0, Math.max(0, (audio.duration || 0) - 1)); } catch (e) {}
      audio.play().catch(() => {});
      drawPlayer();
    };
    audio.onerror = () => {
      if (listening !== me) return;
      const s = songById(me.song);
      if (!me.decoded && s) listen(s, true);
      else { stopListening(); message([t("listenCantPlay", { kind: me.kind || "" })]); }
    };
  }

  function stopListening() {
    if (!listening) return;
    const was = listening;
    listening = null;
    audio.pause();
    audio.removeAttribute("src");
    audio.load();
    if (was.url) URL.revokeObjectURL(was.url);
    pendingChunks.length = 0;
    drawPlayer(); markListening();
    if (selected === was.song) drawNames();
  }

  function markListening() {
    for (const b of document.querySelectorAll("td.listen button")) {
      b.setAttribute("aria-pressed", String(!!listening && b.closest("tr").dataset.id === listening.song));
    }
  }

  function listenCell(s, td) {
    td.classList.add("listen");
    td.append(el("button", { text: t("glyph.play"), title: t("listenTo", { title: s.title }), "aria-label": t("listenTo", { title: s.title }),
      "aria-pressed": String(!!listening && listening.song === s.id),
      on: { click: (e) => { e.stopPropagation(); select(s.id); listening && listening.song === s.id ? stopListening() : listen(s); } } }));
  }

  function drawPlayer() {
    const p = $("player");
    p.hidden = !listening;
    if (!listening) return;
    const me = listening;
    const ready = me.ready && isFinite(audio.duration);
    $("player-title").textContent = me.title;
    $("player-play").disabled = !ready;
    $("player-play").textContent = !ready || audio.paused ? t("play") : t("pause");
    $("player-back").disabled = !ready;
    $("player-forward").disabled = !ready;
    const scrub = $("player-scrub");
    scrub.disabled = !ready;
    scrub.setAttribute("aria-label", t("listenPosition", { title: me.title }));
    if (ready) {
      if (!scrubbing) scrub.value = String(Math.round((audio.currentTime / audio.duration) * 1000));
      const time = t("listenTime", { position: mmss(audio.currentTime), length: mmss(audio.duration) });
      $("player-time").textContent = time;
      scrub.setAttribute("aria-valuetext", time);
    } else {
      $("player-time").textContent = t("listenGettingReady", { title: me.title });
    }
  }
  let scrubbing = false;
  $("player-play").addEventListener("click", () => { if (audio.paused) audio.play().catch(() => {}); else audio.pause(); });
  $("player-back").addEventListener("click", () => { audio.currentTime = Math.max(0, audio.currentTime - 30); });
  $("player-forward").addEventListener("click", () => { audio.currentTime = Math.min(audio.duration || 0, audio.currentTime + 30); });
  $("player-stop").addEventListener("click", stopListening);
  $("player-scrub").addEventListener("input", (e) => {
    scrubbing = true;
    if (isFinite(audio.duration)) audio.currentTime = (Number(e.target.value) / 1000) * audio.duration;
  });
  $("player-scrub").addEventListener("change", () => { scrubbing = false; });
  for (const ev of ["timeupdate", "play", "pause", "ended", "durationchange"]) audio.addEventListener(ev, () => drawPlayer());
  $("names-close").addEventListener("click", () => { stopListening(); selected = null; render(); });

  // ---- naming many songs at once: a preview with a tick per field, then one step of undo (letter AA, 3.6)
  let tool = null;   // { kind, preview, ticks: Set, path }

  function toolMenu(list, close) {
    const go = (kind) => () => { close(true); openTool(kind); };
    list.append(item(t("pasteList"), go("paste")));
    list.append(item(t("namesFromFileNames"), go("pattern")));
    list.append(item(t("namesFromPlaylist"), go("playlist")));
    list.append(sep());
    list.append(item(t("lookupMany"), () => { close(true); openLookup({ scope: "songs" }); }, { class: "net-item" }));
    list.append(item(t("lookupSentLink"), () => { close(true); showSent(); }, { class: "net-item" }));
  }
  menu($("tools-button"), $("tools-menu"), toolMenu);

  function openTool(kind) {
    if (!hasSongs()) return;
    const sources = songs.sources.map((x) => x.name);
    const sel = selected && songById(selected);
    const first = (sel && sel.places[0] && sel.places[0].source) ||
      (songs.songs.find((x) => x.needsName && x.places[0] && x.places[0].source) || {}).places?.[0]?.source || sources[0];
    tool = { kind, preview: null, ticks: new Set(), path: null };
    $("tool-title").textContent = t({ paste: "pasteList", pattern: "namesFromFileNames", playlist: "namesFromPlaylist" }[kind]).replace(/…$/, "");
    const src = $("tool-source");
    src.replaceChildren(...sources.map((x) => el("option", { value: x, text: x, selected: x === first })));
    $("tool-paste").hidden = kind !== "paste";
    $("tool-pattern").hidden = kind !== "pattern";
    $("tool-playlist").hidden = kind !== "playlist";
    $("tool-text").value = "";
    $("tool-file").textContent = "";
    $("tool-empty").checked = true;
    $("tool-preview").tBodies[0].replaceChildren();
    $("tool-problem").textContent = "";
    updateApply();
    const d = $("tool");
    d.returnValue = "";
    d.onclose = () => {
      if (d.returnValue === "ok" && tool && tool.preview && !tool.preview.problem) {
        const ticks = [...tool.ticks];
        request("names.apply", { ticks }, { errorWord: "couldntSave" }).then((r) => {
          if (r.ok && r.songs) { undoLine = { text: n("namesAdded", r.songs) }; render(); }
        });
      }
      tool = null;
    };
    d.showModal();
    if (kind === "paste") $("tool-text").focus();
    if (kind === "pattern") { $("tool-pattern-input").value = ""; refreshTool().then(() => $("tool-pattern-input").focus()); }
  }

  let toolTimer = null;
  const refreshSoon = () => { clearTimeout(toolTimer); toolTimer = setTimeout(refreshTool, 250); };
  async function refreshTool() {
    if (!tool) return;
    const fields = { tool: tool.kind, source: $("tool-source").value, onlyEmpty: $("tool-empty").checked };
    if (tool.kind === "paste") fields.text = $("tool-text").value;
    if (tool.kind === "pattern") fields.pattern = $("tool-pattern-input").value || undefined;
    if (tool.kind === "playlist") { if (!tool.path) { drawPreview(null); return; } fields.path = tool.path; }
    const me = tool;
    const r = await request("names.preview", fields, { errorWord: "couldntOpen" });
    if (tool !== me || !r.ok) return;
    if (tool.kind === "pattern" && r.patterns) {
      $("tool-patterns").replaceChildren(...r.patterns.map((p) => el("option", { value: p })));
      if (!$("tool-pattern-input").value) $("tool-pattern-input").value = r.patterns[0];
    }
    tool.preview = r.preview;
    tool.ticks = new Set(r.preview.changes.map((c, i) => (c.tick ? i : -1)).filter((i) => i >= 0));
    drawPreview(r.preview);
  }

  function drawPreview(p) {
    const body = $("tool-preview").tBodies[0];
    body.replaceChildren();
    const prob = $("tool-problem");
    prob.textContent = "";
    prob.classList.toggle("mut", !(p && p.problem));
    if (p) {
      if (p.problem === "counts") prob.textContent = t("countsDiffer", { songs: n("songs", p.songs), lines: n("lines", p.lines) });
      else if (p.problem === "empty") prob.textContent = t("listEmpty");
      else if (p.problem === "noMatch") prob.textContent = t("patternFitsNone");
      else if (p.tool === "pattern") prob.textContent = t("patternFits", { fits: p.lines, songs: p.songs });
      else if (p.tool === "playlist") prob.textContent = p.lengthsDiffer == null ? t("playlistNoLengths") : (p.lengthsDiffer === 0 ? t("lengthsAllMatch") : n("lengthsDiffer", p.lengthsDiffer));
      if (!p.problem && !p.changes.length) prob.textContent = t("nothingToChange");
      const songTitle = (id) => { const s = songById(id); if (!s) return id; const pl = s.places[0]; return pl && pl.number != null ? t("toolSongTitle", { number: two(pl.number), title: s.title }) : s.title; };
      p.changes.forEach((c, i) => {
        const box = el("input", { type: "checkbox", "aria-label": t("toolTickLabel", { field: t(c.field), value: c.after || "" }), disabled: c.locked });
        box.checked = tool.ticks.has(i);
        box.addEventListener("change", () => { if (box.checked) tool.ticks.add(i); else tool.ticks.delete(i); updateApply(); });
        body.append(el("tr", null, el("td", null, box), el("td", { text: songTitle(c.song) }), el("td", { text: t(c.field) }),
          el("td", { class: c.locked ? "locked" : null, text: c.before || t("none") }),
          el("td", { class: c.locked ? "locked" : null, text: c.after || "" },
            c.note ? el("span", { class: "note", text: t("toolChangeNote", { note: t("changeNote." + c.note) }) }) : null)));
      });
    }
    updateApply();
  }

  function updateApply() {
    const b = $("tool-apply");
    const count = tool && tool.preview && !tool.preview.problem ? tool.ticks.size : 0;
    b.disabled = count === 0;
    b.textContent = n("useNames", count);
  }

  $("tool-text").addEventListener("input", refreshSoon);
  $("tool-pattern-input").addEventListener("input", refreshSoon);
  $("tool-source").addEventListener("change", refreshTool);
  $("tool-empty").addEventListener("change", refreshTool);
  $("tool-choose").addEventListener("click", async () => {
    const f = await request("shell.chooseFile", Object.assign({ purpose: "playlist", message: t("choosePlaylistMessage") }, chooserWords(false)), { quiet: true });
    if (!f.ok || !f.path || !tool) return;
    tool.path = f.path;
    $("tool-file").textContent = f.path.replace(/^.*[\\/]/, "");
    refreshTool();
  });
  $("undo-line-button").addEventListener("click", () => { undoLine = null; request("edit.undo"); });

  // ---- a music CD with no name of its own: asked once, in passing
  let discAsked = null;
  let discRenamed = null;   // { from, to }: the disc's placeholder and the name the DJ gave
  function askDisc(name) {
    discAsked = name || null;
    const f = $("disc-ask");
    f.hidden = !name;
    if (name) { $("disc-ask-input").value = name; }
  }
  $("disc-ask").addEventListener("submit", (e) => {
    e.preventDefault();
    const v = $("disc-ask-input").value.trim();
    $("disc-ask").hidden = true;
    if (v && discAsked && v !== discAsked) discRenamed = { from: discAsked, to: v };
    if (v && discAsked && v !== discAsked) request("run.nameDisc", { source: discAsked, name: v }, { errorWord: "couldntSave" });
  });

  // ---- the sources panel
  function drawSources() {
    const tree = $("tree");
    const byId = new Map(songs.songs.map((s) => [s.id, s]));
    tree.replaceChildren(...songs.sources.map((src) => {
      const li = el("li", { class: "src" });
      li.append(el("div", { class: "row" },
        el("span", { class: "name", text: n("sourceLine", src.songs, { name: src.name }) }),
        el("span", { class: "tools" },
          el("button", { class: "icon-btn", text: t("rename"), "aria-label": t("renameTitle", { name: src.name }),
            on: { click: () => askName(t("renameTitle", { name: src.name }), src.name, (v) => request("source.rename", { source: src.name, name: v }, { errorWord: "couldntSave" })) } }),
          el("button", { class: "icon-btn danger", text: t("removeFromCrate"), "aria-label": t("removeTitle", { source: src.name, crate: current().name }),
            on: { click: () => askRemove(src.name) } }))));
      const ul = el("ul");
      for (const f of src.folders) {
        const fl = el("li", { class: "folder" });
        const fname = f.name || t("topFolder");
        fl.append(el("div", { class: "row" },
          el("span", { class: "name", text: fname }),
          el("span", { class: "tools" },
            f.name ? el("button", { class: "icon-btn", text: t("rename"), "aria-label": t("renameFolderTitle", { folder: f.name }),
              on: { click: () => askName(t("renameFolderTitle", { folder: f.name }), f.name, (v) => request("folder.rename", { source: src.name, folder: f.name, name: v }, { errorWord: "couldntSave" })) } }) : null)));
        const sl = el("ul");
        f.songs.forEach((song, i) => {
          const s = byId.get(song.id);
          const title = s ? s.title : song.id;
          const more = s ? s.places.length - 1 : 0;
          sl.append(el("li", { class: "song" }, el("div", { class: "row" },
            el("span", { class: "n", text: song.number != null ? two(song.number) : t("none") }),
            el("span", { class: "name", title: more > 0 ? t("alsoIn", { places: join("join.alsoIn", placeLines(s)) }) : null }, title, s && s.artist ? el("span", { class: "artist", text: s.artist }) : null),
            more > 0 ? el("span", { class: "dim", text: t("sourceSongMore", { n: more }) }) : null,
            el("span", { class: "tools" },
              el("button", { class: "icon-btn", text: t("glyph.moveUp"), title: t("moveUp"), "aria-label": t("songActionLabel", { action: t("moveUp"), title }), disabled: i === 0,
                on: { click: () => request("song.move", { song: song.id, source: src.name, folder: f.name, by: -1 }) } }),
              el("button", { class: "icon-btn", text: t("glyph.moveDown"), title: t("moveDown"), "aria-label": t("songActionLabel", { action: t("moveDown"), title }), disabled: i === f.songs.length - 1,
                on: { click: () => request("song.move", { song: song.id, source: src.name, folder: f.name, by: 1 }) } })))));
        });
        fl.append(sl);
        ul.append(fl);
      }
      li.append(ul);
      return li;
    }));
    if (songs.musicFolderSongs) {
      tree.append(el("li", { class: "src" }, el("div", { class: "row" },
        el("span", { class: "name", text: t("musicFolderName") }),
        el("span", { class: "tools" }, el("button", { class: "icon-btn danger", text: t("removeMusicFolder"), on: { click: () => askRemove(null) } })))));
    }
    $("tree-empty").hidden = songs.sources.length > 0 || songs.musicFolderSongs;
  }

  async function askRemove(source) {
    const r = await request("source.removeCount", { source });
    if (!r.ok) return;
    const ok = await confirmIt(t("removeTitle", { source: source == null ? t("musicFolderName") : source, crate: current().name }),
      n("removeBody", r.songs), t("remove"));
    if (ok) await request("source.remove", { source }, { errorWord: "couldntSave" });
    return ok;
  }

  // ---- dialogs
  function askName(title, value, then) {
    const d = $("ask");
    $("ask-title").textContent = title;
    $("ask-input").value = value;
    d.returnValue = "";
    d.onclose = () => { const v = $("ask-input").value.trim(); if (d.returnValue === "ok" && v && v !== value) then(v); };
    d.showModal();
    $("ask-input").select();
  }
  function confirmIt(title, body, okWord) {
    return new Promise((resolve) => {
      const d = $("confirm");
      $("confirm-title").textContent = title;
      $("confirm-body").textContent = body;
      $("confirm-ok").textContent = okWord;
      d.returnValue = "";
      d.onclose = () => resolve(d.returnValue === "ok");
      d.showModal();
    });
  }
  /// A message: its lines, and any buttons beside OK.
  function message(lines, extra) {
    const d = $("message");
    const body = $("message-body");
    body.replaceChildren(...lines.map((l) => el("p", { text: l })));
    if (extra) body.append(extra);
    if (!d.open) d.showModal();
  }
  function showLog() {
    const log = songs && songs.importLog;
    $("log-read").textContent = log ? t("readOn", { by: log.builtBy, at: log.builtAt, seen: log.filesSeen, songs: log.songs }) : t("noRecord");
    const groups = $("log-groups");
    groups.replaceChildren();
    if (log) {
      const by = {};
      for (const e of log.entries) (by[e.reason] = by[e.reason] || []).push(e);
      const keys = Object.keys(by).sort();
      if (!keys.length) groups.append(el("p", { text: t("everySongWentIn") }));
      for (const k of keys) {
        groups.append(el("section", null, el("h3", { text: t("reasonCount", { reason: reason(k), n: by[k].length }) }),
          el("ul", null, ...by[k].map((e) => el("li", null, el("code", { text: e.rel, title: e.rel }), el("span", { class: "mut", text: e.message }))))));
      }
    }
    $("log").showModal();
  }
  function announce(text) { $("announce").textContent = ""; setTimeout(() => { $("announce").textContent = text; }, 30); }

  // ---- menus
  function menu(button, list, build) {
    const close = (refocus) => {
      list.hidden = true; button.setAttribute("aria-expanded", "false");
      document.removeEventListener("mousedown", outside, true);
      if (refocus) button.focus();
    };
    const outside = (e) => { if (!list.contains(e.target) && e.target !== button && !button.contains(e.target)) close(false); };
    const items = () => [...list.querySelectorAll("[role^=menuitem]:not([disabled])")];
    const open = async (focusLast) => {
      list.replaceChildren(); await build(list, close);
      list.hidden = false; button.setAttribute("aria-expanded", "true");
      document.addEventListener("mousedown", outside, true);
      const all = items(); if (all.length) (focusLast ? all[all.length - 1] : all[0]).focus();
    };
    button.addEventListener("click", () => (list.hidden ? open(false) : close(true)));
    button.addEventListener("keydown", (e) => { if (e.key === "ArrowDown" || e.key === "ArrowUp") { e.preventDefault(); open(e.key === "ArrowUp"); } });
    list.addEventListener("keydown", (e) => {
      const all = items(); const i = all.indexOf(document.activeElement);
      if (e.key === "ArrowDown") { e.preventDefault(); all[(i + 1) % all.length].focus(); }
      else if (e.key === "ArrowUp") { e.preventDefault(); all[(i - 1 + all.length) % all.length].focus(); }
      else if (e.key === "Home") { e.preventDefault(); all[0].focus(); }
      else if (e.key === "End") { e.preventDefault(); all[all.length - 1].focus(); }
      else if (e.key === "Escape") { e.preventDefault(); close(true); }
      else if (e.key === "Tab") close(false);
    });
  }
  const item = (text, fn, extra) => el("li", { role: "none" }, el("button", Object.assign({ role: "menuitem", tabindex: "-1", text, on: { click: fn } }, extra || {})));
  const sep = () => el("li", { role: "separator" });

  menu($("crate-button"), $("crate-menu"), (list, close) => {
    const c = current();
    for (const x of state.crates) {
      list.append(el("li", { role: "none" }, el("button", { role: "menuitemradio", tabindex: "-1", "aria-checked": String(!!c && x.id === c.id), text: x.name,
        on: { click: () => { close(true); finished = null; request("crate.show", { crate: x.id }); } } })));
    }
    if (state.crates.length) list.append(sep());
    list.append(item(t("newCrate"), () => { close(true); finished = null; request("crate.new"); }));
    if (c) {
      list.append(sep());
      list.append(item(t("renameCrate"), () => { close(false); askName(t("renameTitle", { name: c.name }), c.name, (v) => request("crate.rename", { crate: c.id, name: v }, { errorWord: "couldntRename" })); }));
      list.append(item(t("deleteCrate"), async () => {
        close(false);
        if (await confirmIt(t("deleteCrateTitle", { name: c.name }), t(hello.deletesForGood ? "deleteCrateBodyForGood" : "deleteCrateBody"), t("delete"))) {
          finished = null; request("crate.delete", { crate: c.id }, { errorWord: "couldntDelete" });
        }
      }));
    }
  });

  menu($("add-button"), $("add-menu"), buildWaysMenu);
  menu($("finished-add"), $("finished-add-menu"), buildWaysMenu);

  menu($("more-button"), $("more-menu"), (list, close) => {
    const songsHere = hasSongs();
    list.append(item(t("lookAgain"), async () => {
      close(true);
      const r = await request("lookAgain", {}, { errorWord: "runStopped" });
      if (r.ok) message(lookedAgainLines(r.summary));
    }, { disabled: !songsHere }));
    list.append(item(t("chooseLibrary"), async () => {
      close(true);
      const f = await request("shell.chooseFile", Object.assign({ purpose: "library", message: t("chooseLibraryMessage") }, chooserWords(false)), { quiet: true });
      if (!f.ok || !f.path) return;
      const r = await request("library.choose", { path: f.path }, { errorWord: "couldntReadLibrary" });
      if (r.ok) message([t("libraryChosen", { program: programName(r.program) })]);
    }));
    list.append(sep());
    list.append(item(t("pasteList"), () => { close(true); openTool("paste"); }, { disabled: !songsHere }));
    list.append(item(t("namesFromFileNames"), () => { close(true); openTool("pattern"); }, { disabled: !songsHere }));
    list.append(item(t("namesFromPlaylist"), () => { close(true); openTool("playlist"); }, { disabled: !songsHere }));
    list.append(sep());
    list.append(item(t("lookupMany"), () => { close(true); openLookup({ scope: "songs" }); }, { disabled: !songsHere, class: "net-item" }));
    list.append(item(t("lookupSentLink"), () => { close(true); showSent(); }, { class: "net-item" }));
    list.append(sep());
    list.append(item(t("importCrateFile"), () => { close(true); importCrate(); }));
    list.append(item(t("exportCrateFile"), () => { close(true); exportCrate(); }, { disabled: !songsHere }));
  });

  function lookedAgainLines(s) {
    const rep = s.report || {};
    const out = [];
    const counts = Object.entries(rep.keys_from || {}).sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1));
    if (counts.length) out.push(t("keysLine", { counts: join("join.keysCounts", counts.map(([k, c]) => t("keysCount", { n: c, from: keyFrom(k) }))) }));
    if (rep.keys_not_read > 0) out.push(n("keysNone", rep.keys_not_read));
    if (rep.keys_disagree > 0) out.push(n("keysDisagree", rep.keys_disagree));
    out.push(rep.need_name ? n("needName", rep.need_name) : t("everySongHasAName"));
    if ((s.libraries || []).length) out.push(t("librariesRead", { names: join("join.libraries", s.libraries.map((l) => programName(l.program))) }));
    for (const f of s.failed || []) out.push(t("couldntReadLibrary", { detail: f }));
    if (s.rekordbox_locked) out.push(t("rekordboxLocked"));
    if (s.rekordbox_export) out.push(t("rekordboxExportNotRead"));
    return out;
  }

  // ---- adding music: the three ways, the same everywhere (DeskAddMusic.ways, from the engine's first message)
  const ways = () => (hello && hello.addWays) || [];

  /// The three ways as buttons: the first screen's (main) and the crate screen's row.
  function drawWays(box, main, disabled) {
    box.replaceChildren(...ways().map((w) => el("button", { class: main ? "main way" : "small way", title: t(w.help), disabled: disabled || null,
      on: { click: () => addWay(w.id) } }, icon(w.icon), el("span", { text: t(w.word) }))));
  }
  /// The three ways as a menu's items: the bar's Add music and the finished screen's Add more music.
  function buildWaysMenu(list, close) {
    for (const w of ways()) {
      list.append(el("li", { role: "none" }, el("button", { role: "menuitem", tabindex: "-1", title: t(w.help),
        on: { click: () => { close(true); addWay(w.id); } } }, icon(w.icon), el("span", { text: t(w.word) }))));
    }
  }

  function addWay(id) {
    if (run || (state && state.running)) return;
    if (id === "folder") chooseAndAdd();
    else pickFrom(id);
  }

  /// Add drive's list (sticks, cards and drives, each with its size) and Add CD's (music CDs and data CDs).
  async function pickFrom(id) {
    const r = await request("drives.list", {}, { quiet: true });
    const drives = ((r.ok && r.drives) || []).filter((d) => (d.kind || "drive") === (id === "cd" ? "cd" : "drive"));
    const cds = id === "cd" ? (r.ok && r.musicCDs) || [] : [];
    const d = $("pick");
    $("pick-title").textContent = t(id === "cd" ? "chooseCDTitle" : "chooseDriveTitle");
    $("pick-body").textContent = t(id === "cd" ? "chooseCDBody" : "chooseDriveBody");
    const list = $("pick-list");
    list.replaceChildren();
    const row = (iconName, name, detail, fn) => list.append(el("li", null, el("button", { class: "pick-row", type: "button",
      on: { click: () => { d.close("cancel"); fn(); } } }, icon(iconName, "pick-icon"),
      el("span", { class: "pick-text" }, el("span", { text: name }), detail ? el("span", { class: "mut small", text: detail }) : null))));
    for (const cd of cds) {
      const secs = Math.round(cd.seconds);
      const name = n("musicCDPlaceholder", cd.songs, { length: Math.floor(secs / 60) + ":" + two(secs % 60) });
      row("disc", t("musicCDItem", { name, drive: cd.drive }), null,
        () => request("run.addMusicCD", { location: cd.location }, { errorWord: "runStopped" }));
    }
    for (const x of drives) {
      const detail = join("join.places", [x.size, x.big ? t("driveBigNote") : null].filter(Boolean));
      row(id === "cd" ? "disc" : "drive", id === "cd" ? t("dataCDItem", { name: x.name }) : x.name, detail, () => chooseDrive(x));
    }
    $("pick-empty").hidden = cds.length + drives.length > 0;
    $("pick-empty").textContent = t(id === "cd" ? "noCDIn" : "noDriveIn");
    d.showModal();
  }

  /// A drive from the list: a big one offers a folder inside it first; any other is counted, then read.
  function chooseDrive(x) {
    if (x.big) { bigDrive(x); return; }
    countThenAdd(x.path, x.name);
  }

  /// A big drive: choose the folder the music is in (the chooser opens inside it, saying why), or read it whole.
  function bigDrive(x) {
    const d = $("bigdrive");
    $("bigdrive-title").textContent = t("bigDriveTitle", { name: x.name });
    $("bigdrive-body").textContent = t("bigDriveBody", { size: x.size || "" });
    d.returnValue = "";
    d.onclose = async () => {
      if (d.returnValue === "whole") countThenAdd(x.path, x.name);
      if (d.returnValue !== "folder") return;
      const f = await request("shell.chooseFolder", Object.assign({ purpose: "addMusic", start: x.path,
        message: t("bigDriveChooser", { name: x.name }) }, chooserWords(true)), { quiet: true });
      if (f.ok && f.path) countThenAdd(f.path, samePath(f.path, x.path) ? x.name : null);
    };
    d.showModal();
  }
  /// Two paths for the same folder, whichever way the slashes lean (Windows' choosers give backslashes, Foundation
  /// forward slashes) and with or without a slash at the end.
  const pathKey = (p) => p.replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase();
  const samePath = (a, b) => pathKey(a) === pathKey(b);

  /// Counts the songs first; the count shows rising once it takes longer than a moment. Above the line Desk asks,
  /// with the count and about how long reading takes, before reading anything (research AE, finding 3).
  async function countThenAdd(path, name) {
    adding = { path, name, songs: 0, shown: false };
    const mine = adding;
    setTimeout(() => { if (adding === mine && !mine.done) { mine.shown = true; openCounting(); } }, num("--count-show-after"));
    const r = await request("add.count", name ? { path, name } : { path }, { errorWord: "runStopped" });
    if (!r.ok && adding === mine) adding = null;
  }
  function openCounting() {
    const d = $("askread");
    $("askread-counting").hidden = false; $("askread-ask").hidden = true; $("askread-start").hidden = true;
    $("askread-title").textContent = t("counting");
    drawCounting();
    d.returnValue = "";
    d.onclose = () => {
      const a = adding;
      if (!a) return;
      if (d.returnValue === "start") { adding = null; addMusic(a.path, a.name, a.crateName); return; }
      if (!a.done) request("add.countStop", {}, { quiet: true });
      adding = null;
    };
    if (!d.open) d.showModal();
  }
  function drawCounting() {
    if (!adding) return;
    $("askread-count").textContent = n("countingSoFar", adding.songs);
    $("askread-name").textContent = adding.name || "";
  }
  function counted(m) {
    const a = adding;
    if (!a || !samePath(a.path, m.path || "")) return;
    a.done = true; a.name = a.name || m.name;
    const d = $("askread");
    if (m.stopped) { adding = null; if (d.open) d.close("cancel"); return; }
    if (!m.ask) {
      adding = null;
      if (d.open) { d.onclose = null; d.close("cancel"); }
      addMusic(a.path, a.name);
      return;
    }
    // The question: how many songs, about how long, and which crate they go into (a new one's name to type).
    if (!d.open) openCounting();
    $("askread-title").textContent = n("askReadTitle", m.songs, { name: a.name });
    $("askread-body").textContent = t("askReadBody", { about: m.about });
    const isNew = !current();
    $("askread-new").hidden = !isNew;
    $("askread-into").hidden = isNew;
    $("askread-into").textContent = t("intoCrate", { crate: shownName() });
    $("askread-name-input").value = shownName();
    $("askread-name-input").oninput = () => { a.crateName = $("askread-name-input").value; };
    $("askread-start").textContent = n("askReadStart", m.songs);
    $("askread-start").hidden = false;
    $("askread-counting").hidden = true; $("askread-ask").hidden = false;
    $("askread-name-input").select();
  }

  // ---- what the DJ does
  function addMusic(path, name, crateName) {
    const fields = { path };
    if (name) fields.name = name;
    // A new crate takes the first screen's name (or the one typed in the question), never the source's.
    if (!current()) fields.crateName = crateName || $("first-name").value || (state && state.newName) || "";
    request("run.add", fields, { errorWord: "runStopped" });
  }
  async function chooseAndAdd() {
    const f = await request("shell.chooseFolder", Object.assign({ purpose: "addMusic", message: t("chooseSourceMessage") }, chooserWords(true)), { quiet: true });
    if (f.ok && f.path) addChosen(f.path);
  }
  /// A folder chosen or dropped: the top of a big drive offers a folder inside it first; anything else is counted.
  async function addChosen(path) {
    const r = await request("drives.list", {}, { quiet: true });
    const x = ((r.ok && r.drives) || []).find((d) => samePath(d.path, path));
    if (x && x.big) { bigDrive(x); return; }
    countThenAdd(path, x ? x.name : null);
  }
  function nextDrop() { if (!run && !(state && state.running) && !adding && dropQueue.length) addChosen(dropQueue.shift()); }

  /// The crate's name, renamed from the header or the run screen: the crate showing (during a run it is applied when
  /// the run ends), or the new crate's name on the first screen.
  function renameShown() {
    const c = current();
    const name = shownName();
    askName(t("renameTitle", { name }), name, (v) => {
      if (c) request("crate.rename", { crate: c.id, name: v }, { errorWord: "couldntRename" });
      else request("crate.newName", { name: v }, { quiet: true });
    });
  }
  async function importCrate() {
    const f = await request("shell.chooseFile", Object.assign({ purpose: "import", message: t("importMessage") }, chooserWords(false)), { quiet: true });
    if (f.ok && f.path) { finished = null; request("crate.import", { path: f.path }, { errorWord: "couldntOpen" }); }
  }
  async function exportCrate() {
    if (!hasSongs()) { message([t("nothingToSendYet")]); return; }
    const f = await request("shell.chooseFolder", Object.assign({ purpose: "export", message: t("exportMessage") }, chooserWords(true)), { quiet: true });
    if (!f.ok || !f.path) return;
    const r = await request("crate.export", { folder: f.path }, { errorWord: "couldntExport" });
    if (!r.ok) return;
    exportedPath = r.path;
    if (finished) { render(); return; }
    const extra = el("div", null,
      el("p", null, el("button", { class: "link", text: t("openFolder"), on: { click: () => request("shell.openFolder", { path: parentOf(r.path) }, { quiet: true }) } })),
      el("h3", { class: "to-ipad-title", text: t("toIPadTitle") }),
      el("ul", { class: "mut" }, el("li", { text: t("toIPadStick") }), el("li", { text: t("toIPadICloud") }), el("li", { text: t("toIPadCable") })));
    message([t("exportedTo", { folder: parentOf(r.path) })], extra);
  }

  $("crate-name-button").addEventListener("click", renameShown);
  $("run-name-button").addEventListener("click", renameShown);
  $("run-stop").addEventListener("click", () => request("run.stop", {}, { quiet: true }));
  $("first-name").addEventListener("change", () => request("crate.newName", { name: $("first-name").value }, { quiet: true }));
  $("finished-carryon").addEventListener("click", () => request("run.carryOn", {}, { errorWord: "runStopped" }));
  $("finished-takeout").addEventListener("click", async () => {
    if (finished && await askRemove(finished.read)) { finished = null; render(); }
  });
  $("first-import").addEventListener("click", importCrate);
  $("carry-on").addEventListener("click", () => request("run.carryOn", {}, { errorWord: "runStopped" }));
  $("undo").addEventListener("click", () => request("edit.undo"));
  $("redo").addEventListener("click", () => request("edit.redo"));
  $("sources-button").addEventListener("click", () => { showSources = !showSources; render(); });
  $("side-close").addEventListener("click", () => { showSources = false; render(); $("sources-button").focus(); });
  $("log-button").addEventListener("click", showLog);
  $("export-button").addEventListener("click", exportCrate);
  $("finished-export").addEventListener("click", exportCrate);
  $("finished-log").addEventListener("click", showLog);
  $("finished-songs").addEventListener("click", () => { finished = null; render(); });
  $("exported-open").addEventListener("click", () => exportedPath && request("shell.openFolder", { path: parentOf(exportedPath) }, { quiet: true }));
  $("status-needname").addEventListener("click", () => { onlyNeedName = !onlyNeedName; render(); });
  $("status-notin").addEventListener("click", showLog);

  // Undo and redo from the keyboard, except while typing.
  document.addEventListener("keydown", (e) => {
    const typing = e.target && (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.tagName === "SELECT");
    if (!typing && e.key === " " && !e.ctrlKey && !e.metaKey && selected && hasSongs() && !document.querySelector("dialog[open]")
        && !(e.target && e.target.tagName === "BUTTON")) {
      e.preventDefault();
      const s = songById(selected);
      if (s) (listening && listening.song === s.id ? stopListening() : listen(s));
      return;
    }
    if (typing || !(e.ctrlKey || e.metaKey) || document.querySelector("dialog[open]")) return;
    const k = e.key.toLowerCase();
    if (k === "z" && !e.shiftKey && !$("undo").disabled) { e.preventDefault(); request("edit.undo"); }
    else if (((k === "z" && e.shiftKey) || k === "y") && !$("redo").disabled) { e.preventDefault(); request("edit.redo"); }
  });

  // A folder held over the window. The page is never told a folder's path; the shell is, where the system's web
  // view hands it over (WebView2 through postMessageWithAdditionalObjects; WebKitGTK as file URIs).
  let dragDepth = 0;
  const hasFiles = (e) => e.dataTransfer && [...e.dataTransfer.types].some((x) => x === "Files" || x === "text/uri-list");
  document.addEventListener("dragenter", (e) => { if (!hasFiles(e)) return; e.preventDefault(); dragDepth++; if (!run) $("drop").hidden = false; });
  document.addEventListener("dragover", (e) => { if (hasFiles(e)) e.preventDefault(); });
  document.addEventListener("dragleave", () => { if (--dragDepth <= 0) { dragDepth = 0; $("drop").hidden = true; } });
  document.addEventListener("drop", (e) => {
    e.preventDefault(); dragDepth = 0; $("drop").hidden = true;
    if (run || (state && state.running)) return;
    const uris = (e.dataTransfer.getData("text/uri-list") || "").split(/\r?\n/).filter((u) => u.startsWith("file:"));
    if (uris.length) { request("shell.droppedUris", { uris }, { quiet: true }); return; }
    const wv = window.chrome && window.chrome.webview;
    if (wv && wv.postMessageWithAdditionalObjects && e.dataTransfer.files.length) {
      wv.postMessageWithAdditionalObjects(JSON.stringify({ deckieDrop: true }), e.dataTransfer.files);
      return;
    }
    message([t("chooseSourceMessage")]);
  });

  if (!shell) {
    document.body.textContent = PAGE_WORDS.notInShell;
    return;
  }
  shell.send(JSON.stringify({ type: "shell.ready" }));
})();
