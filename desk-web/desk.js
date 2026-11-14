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

  // ---- words (DeskWords' rules: {name} blanks, name.zero/one/other by count, name.<code> by code)
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

  function applyWords(root) {
    for (const e of root.querySelectorAll("[data-w]")) e.textContent = t(e.dataset.w);
    for (const e of root.querySelectorAll("[data-w-label]")) e.setAttribute("aria-label", t(e.dataset.wLabel));
    for (const e of root.querySelectorAll("[data-w-title]")) e.title = t(e.dataset.wTitle);
    document.title = t("appName");
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
        if (m.protocol !== 2) message([`Protocol ${m.protocol} is not one this window knows (2).`]);
        break;
      case "state":
        if (undoLine && state && m.undo !== state.undo && m.undo !== "undoNames" && m.undo !== "undoCheck") undoLine = null;
        if (state && state.current && (!m.current || m.current.id !== state.current.id)) { stopListening(); selected = null; undoLine = null; dropCovers(); }
        state = m; break;
      case "songs": songs = m; tidyCovers(); break;
      case "run.started":
        dropCovers();
        finished = null; exportedPath = null; stopListening(); $("run-log").replaceChildren();
        run = { read: m.read, crateName: m.crateName, done: 0, total: 0, stage: "reading", remaining: null, lines: [] };
        askDisc(m.askName);
        break;
      case "audio.chunk":
        audioChunk(m); return;
      case "run.progress":
        if (!run) break;
        Object.assign(run, { done: m.done, total: m.total, stage: m.stage, remaining: m.remaining });
        if (m.line) addLine(m.line);
        updateRun(); return;
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
  function show(id) { for (const s of ["first", "run", "finished", "crate"]) $(s).hidden = s !== id; }
  const current = () => (state && state.current) || null;
  const hasSongs = () => !!(current() && current().hasSongs && songs && songs.crate === current().id);

  function render() {
    if (!hello || !state) return;
    const c = current();
    const busy = !!run || state.running;
    $("crate-name").textContent = c ? c.name : t("newCrate");
    $("crate-button").disabled = busy;
    $("add-label").textContent = c ? t("addMusicTo", { crate: c.name }) : t("addMusic");
    $("add-button").disabled = busy || (hello.analysis && !hello.analysis.ready);
    $("first-add").disabled = $("add-button").disabled;
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
      $("pending-text").textContent = t("stoppedReading", { read: p.name }) + (p.here ? "" : " " + t(p.musicCD ? "putDiscBack" : "putBack", { read: p.name }));
      $("carry-on").hidden = !p.here;
    }

    if (busy) { show("run"); updateRun(); $("status").hidden = true; return; }
    if (finished) { show("finished"); drawFinished(); $("status").hidden = true; return; }
    if (songsHere) { show("crate"); drawCrate(); return; }
    show("first");
    $("status").hidden = true;
    $("first-body").textContent = t("firstBody");
    if (hello.analysis && !hello.analysis.ready) $("first-body").textContent += " " + t("engineMissing", { detail: "" });
  }

  function drawFinished() {
    const r = finished;
    // The name the DJ gave the disc while it was read replaces the placeholder the report was written with.
    const named = (x) => (discRenamed && x === discRenamed.from ? discRenamed.to : x);
    $("finished-title").textContent = t("finishedTitle", { read: named(r.read), crate: named(r.crate) });
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
      if (counts.length) line(t("keysLine", { counts: counts.map(([k, c]) => t("keysCount", { n: c, from: keyFrom(k) })).join(", ") }));
      if (rep.keys_not_read > 0) line(n("keysNone", rep.keys_not_read));
      if (rep.keys_disagree > 0) line(n("keysDisagree", rep.keys_disagree));
      // The count is the list's (letter AA, 3.2): no title, no artist, or Desk's guess.
      const need = songs && songs.crate === (current() && current().id) ? songs.songs.filter((x) => x.needsName).length : rep.need_name;
      const d = r.disc;
      if (d && d.text !== "names") line(t(d.text === "none" ? "discNoNames" : "discDriveNoNames"));
      if (d && d.named > 0) line(n("discNamed", d.named));
      const named = el("p", { text: need ? n("needName", need) + " " : t("everySongHasAName") });
      if (need) named.append(el("button", { class: "link", text: t(d && d.text !== "names" ? "nameThem" : "showThem"),
        on: { click: () => { onlyNeedName = true; finished = null; render(); } } }));
      box.append(named);
      if (need) line(t("needNameHelp"), "mut");
      if (d && d.damaged_sectors > 0) line(t("discDamaged"), "mut");
      if ((local.libraries || []).length) line(t("librariesRead", { names: local.libraries.map((l) => programName(l.program)).join(", ") }), "mut");
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
    { key: "key", word: "colKey", get: (s) => (s.key ? s.key.camelot : ""), cell: keyCell },
    { key: "keyFrom", word: "colKeyFrom", get: (s) => (s.key ? programName(s.key.from) : ""), title: keyHelp, cls: "mut" },
    { key: "seconds", word: "colLength", get: (s) => s.seconds, show: (s) => mmss(s.seconds), num: true },
    { key: "where", word: "colWhere", get: (s) => placeLines(s).join(" · "), title: (s) => placeLines(s).join("\n") },
    { key: "notes", word: "colNotes", get: (s) => notes(s), cls: "mut" },
  ];

  function placeLines(s) {
    return s.places.map((p) => p.line || (p.folder ? p.folder : t("topOfMusicFolder")));
  }
  function keyHelp(s) {
    if (!s.key) return t("keyNotRead");
    return [s.key.camelot + " " + keyFrom(s.key.from)].concat(s.key.others.map((o) => t("keySays", { program: programName(o.from), camelot: o.camelot }))).join("; ");
  }
  function keyCell(s, td) {
    td.textContent = s.key ? s.key.camelot : t("none");
    td.title = keyHelp(s);
    if (s.key && s.key.uncertain) td.append(" ", el("span", { class: "unsure", text: "?", title: t("notSureOfKey"), "aria-label": t("notSureOfKey") }));
  }
  function notes(s) {
    return s.notes.map((c) => ({ needsName: t("needsNameNote"), damagedFrames: n("damagedFrames", s.damagedFrames),
      gridUnsure: t("gridUnsure"), vocalsNotRead: t("vocalsNotRead"), signed: t("signed") }[c] || c)).join(", ");
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
    $("songs-caption").textContent = c.name + ", " + n("songs", songs.songs.length);
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
        td.setAttribute("aria-label", t(col.word) + ": " + (col.get(s) || t("none")));
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
        ...others.map((o) => el("p", { class: "value", text: coded("factName", o.name) + ": " + o.value,
          title: o.from ? factFrom(o.from) : null }))));
    }
    const tags = (s.names && s.names.fileTags) || [];
    const left = Object.keys((s.names && s.names.leftOut) || {});
    if (tags.length || left.length) {
      body.append(el("div", { class: "fact facts-list" }, el("label", { text: t("fileTagsHeading") }),
        ...tags.map((o) => el("p", { class: "mut", text: o.name + ": " + o.value })),
        ...(left.length ? [el("p", { class: "from", text: t("leftOutLine", { what: left.map((r) => coded("leftOut", r)).join(", ") }) })] : [])));
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
    // LOOK UP SONG VIA ... GOES HERE (the note on D30): the one explicit lookup, by sound, beside Listen. Not built:
    // route A sends nothing anywhere. Its button, its sentence before anything is sent, and "What Desk has sent"
    // will sit in this row.
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
  }

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
    td.append(el("button", { text: "▶", title: t("listenTo", { title: s.title }), "aria-label": t("listenTo", { title: s.title }),
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
      const songTitle = (id) => { const s = songById(id); if (!s) return id; const pl = s.places[0]; return (pl && pl.number != null ? two(pl.number) + "  " : "") + s.title; };
      p.changes.forEach((c, i) => {
        const box = el("input", { type: "checkbox", "aria-label": t(c.field) + ": " + (c.after || ""), disabled: c.locked });
        box.checked = tool.ticks.has(i);
        box.addEventListener("change", () => { if (box.checked) tool.ticks.add(i); else tool.ticks.delete(i); updateApply(); });
        body.append(el("tr", null, el("td", null, box), el("td", { text: songTitle(c.song) }), el("td", { text: t(c.field) }),
          el("td", { class: c.locked ? "locked" : null, text: c.before || t("none") }),
          el("td", { class: c.locked ? "locked" : null, text: c.after || "" },
            c.note ? el("span", { class: "note", text: "  (" + t("changeNote." + c.note) + ")" }) : null)));
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
    const f = await request("shell.chooseFile", { purpose: "playlist", message: t("choosePlaylistMessage") }, { quiet: true });
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
            el("span", { class: "name", title: more > 0 ? t("alsoIn", { places: placeLines(s).join(", ") }) : null }, title, s && s.artist ? el("span", { class: "artist", text: s.artist }) : null),
            more > 0 ? el("span", { class: "dim", text: "+" + more }) : null,
            el("span", { class: "tools" },
              el("button", { class: "icon-btn", text: "↑", title: t("moveUp"), "aria-label": t("moveUp") + ": " + title, disabled: i === 0,
                on: { click: () => request("song.move", { song: song.id, source: src.name, folder: f.name, by: -1 }) } }),
              el("button", { class: "icon-btn", text: "↓", title: t("moveDown"), "aria-label": t("moveDown") + ": " + title, disabled: i === f.songs.length - 1,
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
    if (ok) request("source.remove", { source }, { errorWord: "couldntSave" });
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

  async function buildAddMenu(list, close) {
    const r = await request("drives.list", {}, { quiet: true });
    const drives = (r.ok && r.drives) || [];
    const cds = (r.ok && r.musicCDs) || [];
    if (!drives.length && !cds.length) list.append(el("li", { role: "none", class: "note", text: t("noDriveFound") }));
    for (const cd of cds) {
      const secs = Math.round(cd.seconds);
      const name = n("musicCDPlaceholder", cd.songs, { length: Math.floor(secs / 60) + ":" + two(secs % 60) });
      list.append(item(t("musicCDItem", { name, drive: cd.drive }), () => { close(true); request("run.addMusicCD", { location: cd.location }, { errorWord: "runStopped" }); }));
    }
    for (const d of drives) list.append(item(d.name, () => { close(true); addMusic(d.path, d.name); }));
    list.append(sep());
    list.append(item(t("chooseFolder"), () => { close(true); chooseAndAdd(); }));
  }
  menu($("add-button"), $("add-menu"), buildAddMenu);

  menu($("more-button"), $("more-menu"), (list, close) => {
    const songsHere = hasSongs();
    list.append(item(t("lookAgain"), async () => {
      close(true);
      const r = await request("lookAgain", {}, { errorWord: "runStopped" });
      if (r.ok) message(lookedAgainLines(r.summary));
    }, { disabled: !songsHere }));
    list.append(item(t("chooseLibrary"), async () => {
      close(true);
      const f = await request("shell.chooseFile", { purpose: "library", message: t("chooseLibraryMessage") }, { quiet: true });
      if (!f.ok || !f.path) return;
      const r = await request("library.choose", { path: f.path }, { errorWord: "couldntReadLibrary" });
      if (r.ok) message([t("libraryChosen", { program: programName(r.program) })]);
    }));
    list.append(sep());
    list.append(item(t("pasteList"), () => { close(true); openTool("paste"); }, { disabled: !songsHere }));
    list.append(item(t("namesFromFileNames"), () => { close(true); openTool("pattern"); }, { disabled: !songsHere }));
    list.append(item(t("namesFromPlaylist"), () => { close(true); openTool("playlist"); }, { disabled: !songsHere }));
    list.append(sep());
    list.append(item(t("importCrateFile"), () => { close(true); importCrate(); }));
    list.append(item(t("exportCrateFile"), () => { close(true); exportCrate(); }, { disabled: !songsHere }));
  });

  function lookedAgainLines(s) {
    const rep = s.report || {};
    const out = [];
    const counts = Object.entries(rep.keys_from || {}).sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1));
    if (counts.length) out.push(t("keysLine", { counts: counts.map(([k, c]) => t("keysCount", { n: c, from: keyFrom(k) })).join(", ") }));
    if (rep.keys_not_read > 0) out.push(n("keysNone", rep.keys_not_read));
    if (rep.keys_disagree > 0) out.push(n("keysDisagree", rep.keys_disagree));
    out.push(rep.need_name ? n("needName", rep.need_name) : t("everySongHasAName"));
    if ((s.libraries || []).length) out.push(t("librariesRead", { names: s.libraries.map((l) => programName(l.program)).join(", ") }));
    for (const f of s.failed || []) out.push(t("couldntReadLibrary", { detail: f }));
    if (s.rekordbox_locked) out.push(t("rekordboxLocked"));
    if (s.rekordbox_export) out.push(t("rekordboxExportNotRead"));
    return out;
  }

  // ---- what the DJ does
  function addMusic(path, name) {
    const fields = { path };
    if (name) fields.name = name;
    request("run.add", fields, { errorWord: "runStopped" });
  }
  async function chooseAndAdd() {
    const f = await request("shell.chooseFolder", { purpose: "addMusic", message: t("chooseSourceMessage") }, { quiet: true });
    if (f.ok && f.path) addMusic(f.path);
  }
  function nextDrop() { if (!run && !(state && state.running) && dropQueue.length) addMusic(dropQueue.shift()); }
  async function importCrate() {
    const f = await request("shell.chooseFile", { purpose: "import", message: t("importMessage") }, { quiet: true });
    if (f.ok && f.path) { finished = null; request("crate.import", { path: f.path }, { errorWord: "couldntOpen" }); }
  }
  async function exportCrate() {
    if (!hasSongs()) { message([t("nothingToSendYet")]); return; }
    const f = await request("shell.chooseFolder", { purpose: "export", message: t("exportMessage") }, { quiet: true });
    if (!f.ok || !f.path) return;
    const r = await request("crate.export", { folder: f.path }, { errorWord: "couldntExport" });
    if (!r.ok) return;
    exportedPath = r.path;
    if (finished) { render(); return; }
    const extra = el("div", null,
      el("p", null, el("button", { class: "link", text: t("openFolder"), on: { click: () => request("shell.openFolder", { path: parentOf(r.path) }, { quiet: true }) } })),
      el("h3", { text: t("toIPadTitle"), style: "margin-top:14px" }),
      el("ul", { class: "mut" }, el("li", { text: t("toIPadStick") }), el("li", { text: t("toIPadICloud") }), el("li", { text: t("toIPadCable") })));
    message([t("exportedTo", { folder: parentOf(r.path) })], extra);
  }

  $("first-add").addEventListener("click", () => {
    // The first screen's button opens the same menu as the bar's.
    $("add-button").click();
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
    document.body.textContent = "Deckie Desk's pages open inside Deckie Desk's window (deckie-desk), which starts the engine.";
    return;
  }
  shell.send(JSON.stringify({ type: "shell.ready" }));
})();
