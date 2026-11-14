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
  const t = (key, v) => fill(W[key] ?? key, v || {});
  const n = (key, count, v) => {
    const form = count === 0 && W[key + ".zero"] != null ? "zero" : count === 1 ? "one" : "other";
    return fill(W[key + "." + form] ?? W[key + ".other"] ?? key, Object.assign({ n: String(count) }, v || {}));
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
        hello = m; W = m.words || {};
        applyWords(document);
        if (m.protocol !== 1) message([`Protocol ${m.protocol} is not one this window knows (1).`]);
        break;
      case "state": state = m; break;
      case "songs": songs = m; break;
      case "run.started":
        finished = null; exportedPath = null;
        run = { read: m.read, crateName: m.crateName, done: 0, total: 0, stage: "reading", remaining: null, lines: [] };
        break;
      case "run.progress":
        if (!run) break;
        Object.assign(run, { done: m.done, total: m.total, stage: m.stage, remaining: m.remaining });
        if (m.line) addLine(m.line);
        updateRun(); return;
      case "run.finished":
        run = null; finished = m.report; announce(t("finishedTitle", { read: m.report.read, crate: m.report.crate }));
        setTimeout(nextDrop, 0);
        break;
      case "run.failed":
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
      $("pending-text").textContent = t("stoppedReading", { read: p.name }) + (p.here ? "" : " " + t("putBack", { read: p.name }));
      $("carry-on").hidden = !p.here;
    }

    if (busy) { show("run"); updateRun(); $("status").hidden = true; return; }
    if (finished) { show("finished"); drawFinished(); $("status").hidden = true; return; }
    if (songsHere) { show("crate"); drawCrate(); return; }
    show("first");
    $("status").hidden = true;
    const mac = (hello.platform || "").startsWith("macos");
    $("first-body").textContent = t(mac ? "firstBody" : "firstBodyComputer");
    if (hello.analysis && !hello.analysis.ready) $("first-body").textContent += " " + t("engineMissing", { detail: "" });
  }

  function drawFinished() {
    const r = finished;
    $("finished-title").textContent = t("finishedTitle", { read: r.read, crate: r.crate });
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
      const named = el("p", { text: rep.need_name ? n("needName", rep.need_name) + " " : t("everySongHasAName") });
      if (rep.need_name) named.append(el("button", { class: "link", text: t("showThem"), on: { click: () => { onlyNeedName = true; finished = null; render(); } } }));
      box.append(named);
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
    { key: "title", word: "colTitle", get: (s) => s.title, edit: "title" },
    { key: "artist", word: "colArtist", get: (s) => s.artist || "", edit: "artist" },
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

  function drawCrate() {
    const c = current();
    // the header, once per draw (cheap)
    const head = $("songs-head");
    head.replaceChildren(...columns.map((col) => {
      const th = el("th", { scope: "col", "aria-sort": sort.key === col.key ? (sort.dir > 0 ? "ascending" : "descending") : "none" });
      th.append(el("button", { text: t(col.word), on: { click: () => { sort = { key: col.key, dir: sort.key === col.key ? -sort.dir : 1 }; drawCrate(); } } }));
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
  }

  function songRow(s) {
    const tr = el("tr", { "data-id": s.id, "aria-selected": String(selected === s.id) });
    tr.addEventListener("click", () => { selected = s.id; for (const r of $("songs-body").children) r.setAttribute("aria-selected", String(r.dataset.id === s.id)); });
    for (const col of columns) {
      const td = el("td", { "data-col": col.key, class: [col.num ? "num" : "", col.cls || "", col.edit ? "editable" : ""].join(" ").trim() || null });
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
    if (!drives.length) list.append(el("li", { role: "none", class: "note", text: t("noDriveFound") }));
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
    const typing = e.target && (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA");
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
