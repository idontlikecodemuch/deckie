// Booth, the listening mode of Deckie Desk's window (research booth-in-desk; step 3, the designed screen, D44). A
// switch in the top bar opens it for the crate showing, and the whole window changes its ground (the owner's decision,
// Nov 21, 2026: the background changes between the two modes): while Booth shows, the page and the bar take
// Booth's ground (booth.css, desk.css's --booth-ground-* values), the heading says Booth and the switch is lit, so
// listening is never mistaken for the crate side.
//
// The screen is the iPad's Booth at home in Desk: the song playing, big (its name, artist, tempo, key, pitch, and its
// place along its wave), the picks for it as rows (name, artist, the tempo line, the keys, the move, what is
// unexpected), the iPad's More (the rest of the shortlist) and its Shuffle dial, which rolls the picks again at once
// (`booth.shuffle`). Calm and out of the way at the foot: the input, its level, Stop listening and the microphone
// sentence. The engine does all of it (docs/architecture/desk-protocol.md, "Listening"); this page sends what the DJ
// chooses and draws the `booth.*` events. No words and no design values of its own: words are DeskWords' (passed in
// as `t`), values desk.css's :root (read here with `num`, and by booth.css). Leaving the mode stops the microphone;
// so does closing the window (the engine's input closes).
//
// Motion is small and says something: a new song comes up with a short rise and the card's glow, new picks fade in
// one after another, and while listening a soft glow follows the level. None of it under reduced motion.
//
// While Desk reads music, listening waits: the mode says so and starts listening when the run ends; a run started from
// the mode leaves it, so the run screen shows.
(function () {
  "use strict";

  const root = document.documentElement;
  const css = (name) => getComputedStyle(root).getPropertyValue(name).trim();
  const num = (name) => parseFloat(css(name));
  const reduceQuery = window.matchMedia ? matchMedia("(prefers-reduced-motion: reduce)") : { matches: false };
  const reduced = () => reduceQuery.matches;
  /// Motion only for a window in front: one behind others gives no frames, and rows left at an animation's first frame
  /// would stay unseen (as run.js's bars, the real window, Nov 21, 2026).
  const moving = () => !reduced() && !document.hidden && (!document.hasFocus || document.hasFocus());
  const HEARING = ["listening", "nothingHeard", "nothingNow", "noSound"];

  window.DeskBooth = function (d) {
    const { el, t, mmss, request } = d;
    let on = false;          // the mode is showing
    let wanted = false;      // listening is wanted (the mode is on and nothing waits)
    let waiting = false;     // the mode is on while a run goes: listening waits
    let stopped = false;     // the DJ pressed Stop listening: the microphone is off until Start listening
    let crate = null;        // the crate the mode was opened on
    let view = { songsHere: false, busy: false };   // desk.js's latest render
    let inputs = [];
    let status = null;       // the last booth.state
    let heard = null;        // the last booth.heard, while the state says a song is named
    let playing = undefined; // the last booth.playing (undefined: the engine sends none, so the card follows booth.heard)
    let playingAt = 0;       // when it came (performance.now), to move the place on between events
    let picks = null;        // the last booth.picks, for the song playing shows
    let silent = false;
    let songs = null;        // songs the crate's index can name (booth.listen's reply)
    let shuffle = num("--booth-shuffle-start");
    let shownId = null;      // the song on the card, for its arrival
    let picksKey = "";       // the picks on screen, for their arrival
    let ticker = 0;

    // ---- the switch in the top bar, before the space that pushes the rest right: a dot that is lit while Booth
    // shows, and the mode's name
    const buttonDot = el("span", { class: "booth-button-dot", "aria-hidden": "true" });
    const buttonLabel = el("span");
    const button = el("button", { id: "booth-button", "aria-pressed": "false", hidden: true,
      on: { click: () => (on ? leave() : enter()) } }, buttonDot, buttonLabel);
    const bar = document.querySelector("header.bar");
    if (bar) bar.insertBefore(button, bar.querySelector(".grow"));

    // ---- the head: the mode's name and what it is doing, the crate, and the way back (always in view)
    const heading = el("h1", { id: "booth-heading" });
    const liveDot = el("span", { class: "booth-live-dot", "aria-hidden": "true" });
    const liveText = el("span", { id: "booth-live-text" });
    const live = el("span", { id: "booth-live", class: "booth-live" }, liveDot, liveText);
    const sub = el("p", { id: "booth-title", class: "booth-sub" });
    const leaveButton = el("button", { id: "booth-leave", class: "booth-leave", on: { click: () => leave() } });
    const head = el("div", { class: "booth-top" },
      el("div", { class: "booth-names" }, el("div", { class: "booth-heading-row" }, heading, live), sub), leaveButton);

    // ---- now playing: the song, big; before a song, the waiting line in its place
    const nowLabel = el("p", { class: "booth-group" });
    const title = el("h2", { id: "booth-song", class: "booth-song" });
    const artist = el("p", { id: "booth-artist", class: "booth-artist" });
    const tempo = el("span", { id: "booth-tempo", class: "booth-tempo" });
    const key = el("span", { id: "booth-key", class: "booth-key" });
    const pitch = el("span", { id: "booth-pitch", class: "booth-pitch" });
    const facts = el("p", { id: "booth-facts", class: "booth-facts" }, tempo, key, pitch);
    const note = el("p", { id: "booth-note", class: "booth-note", hidden: true });
    const wave = el("canvas", { id: "booth-wave", class: "booth-wave", "aria-hidden": "true" });
    const placeAt = el("span", { id: "booth-place" });
    const placeLeft = el("span", { id: "booth-left" });
    const times = el("p", { class: "booth-times" }, placeAt, placeLeft);
    const songPart = el("div", { id: "booth-song-part", class: "booth-song-part" }, title, artist, facts, note, wave, times);
    // The card with no song: a big line (waiting, stopped, a crate with no songs) and the plain one under it.
    const waitTitle = el("h2", { id: "booth-wait-title", class: "booth-wait-title" });
    const stateLine = el("p", { id: "booth-state", class: "booth-state", role: "status" });
    const progress = el("div", { id: "booth-progress", class: "progress", hidden: true }, el("div"));
    const again = el("button", { id: "booth-again", class: "main", hidden: true, on: { click: () => listen() } });
    const start = el("button", { id: "booth-start", class: "main", hidden: true, on: { click: () => listen() } });
    const waitPart = el("div", { id: "booth-wait-part", class: "booth-wait-part" }, waitTitle, stateLine, progress, again, start);
    const card = el("div", { id: "booth-card", class: "card booth-card" }, nowLabel, songPart, waitPart);
    const glow = el("div", { class: "booth-glow", "aria-hidden": "true" });
    const nowCol = el("div", { class: "booth-now" }, glow, card);

    // ---- the picks: the group, the Shuffle dial, the rows; More; how many more
    const picksTitle = el("p", { id: "booth-picks-title", class: "booth-group" });
    const dialName = el("span", { class: "booth-dial-name" });
    const dialValue = el("span", { id: "booth-dial-value", class: "booth-dial-value" });
    const dial = el("input", { id: "booth-shuffle", type: "range", min: "0", max: "1", step: css("--booth-shuffle-step"),
      value: String(shuffle), on: { input: () => showDial(), change: () => moveDial() } });
    const dialBox = el("label", { class: "booth-dial" }, dialName, dialValue, dial);
    const picksList = el("ol", { id: "booth-picks-list", class: "booth-list" });
    const picksEmpty = el("p", { id: "booth-picks-empty", class: "booth-quiet", hidden: true });
    const moreTitle = el("p", { id: "booth-more-title", class: "booth-group", hidden: true });
    const moreList = el("ol", { id: "booth-more-list", class: "booth-list more", hidden: true });
    const picksMore = el("p", { id: "booth-picks-more", class: "booth-quiet", hidden: true });
    const fewLine = el("p", { id: "booth-few", class: "booth-quiet", hidden: true });
    const picksCol = el("div", { id: "booth-picks", class: "booth-picks" },
      el("div", { class: "booth-picks-head" }, picksTitle, dialBox), picksList, picksEmpty, moreTitle, moreList, picksMore, fewLine);

    // ---- the foot: the input, its level, Stop listening, the microphone sentence; a line when no sound comes
    const select = el("select", { id: "booth-input", on: { change: () => { if (on && !waiting && !stopped) listen(); } } });
    const inputLabel = el("span", { class: "booth-input-label" });
    const meterFill = el("span", { class: "booth-meter-fill" });
    const meter = el("div", { id: "booth-meter", class: "booth-meter", role: "meter", "aria-valuemin": "0", "aria-valuemax": "100", "aria-valuenow": "0" }, meterFill);
    const stopButton = el("button", { id: "booth-stop", class: "small", hidden: true, on: { click: () => stopListening() } });
    const inputNote = el("p", { id: "booth-silent", class: "booth-input-note", hidden: true });
    const privacy = el("p", { id: "booth-privacy", class: "booth-privacy" });
    const foot = el("div", { class: "booth-foot" },
      el("div", { class: "booth-controls" }, el("label", { class: "booth-input-row" }, inputLabel, select), meter, stopButton),
      inputNote, privacy);
    const announce = el("div", { class: "sr", "aria-live": "polite", "aria-atomic": "true" });

    const section = el("section", { id: "booth", class: "screen booth", hidden: true, "aria-labelledby": "booth-heading" },
      head, el("div", { class: "booth-body" }, nowCol, picksCol), foot, announce);
    const main = document.querySelector("main");
    if (main && main.parentNode) main.parentNode.insertBefore(section, main.nextSibling);

    function words() {
      buttonLabel.textContent = t("booth.mode");
      button.title = t("booth.modeHelp");
      heading.textContent = t("booth.heading");
      leaveButton.textContent = t("booth.leave");
      nowLabel.textContent = t("booth.nowPlaying");
      picksTitle.textContent = t("booth.picksTitle");
      moreTitle.textContent = t("booth.moreTitle");
      dialName.textContent = t("booth.shuffle");
      dialBox.title = t("booth.shuffleHelp");
      inputLabel.textContent = t("booth.input");
      meter.setAttribute("aria-label", t("booth.level"));
      again.textContent = t("booth.tryAgain");
      start.textContent = t("booth.startListening");
      stopButton.textContent = t("booth.stopListening");
      privacy.textContent = t("booth.micPermission");
      showDial();
    }

    function show(yes) {
      on = yes;
      document.body.classList.toggle("booth-on", yes);
      root.classList.toggle("booth-on", yes);   // the ground is the whole window's: the page and the bar
      section.hidden = !yes;
      button.setAttribute("aria-pressed", String(yes));
      if (!yes) { clearInterval(ticker); ticker = 0; setLevel(0); }
    }

    async function enter() {
      const c = d.current();
      if (!c) return;
      crate = c.id; status = null; heard = null; playing = undefined; picks = null; silent = false; stopped = false;
      songs = null; shownId = null; picksKey = "";
      show(true); words(); draw();
      if (!view.songsHere) return;   // nothing to listen for: the card says so
      const r = await request("booth.inputs", null, { quiet: true });
      inputs = r.ok ? r.inputs || [] : [];
      fillInputs();
      if (!on) return;
      if (d.busy()) { waiting = true; draw(); return; }
      listen();
    }

    function fillInputs() {
      const keep = select.value;
      select.replaceChildren(...inputs.map((x) => el("option", { value: x.name, text: x.default ? t("booth.inputDefault", { name: x.name }) : x.name })));
      if (!inputs.length) select.append(el("option", { value: "", text: t("booth.noInputs") }));
      if (keep && inputs.some((x) => x.name === keep)) select.value = keep;
      select.disabled = !inputs.length;
    }

    function listen() {
      wanted = true; waiting = false; stopped = false; heard = null; playing = undefined; picks = null; silent = false;
      shownId = null; picksKey = ""; status = { state: "starting" };
      draw();
      request("booth.listen", { input: select.value || "", shuffle }, { quiet: true }).then((r) => {
        if (r.ok) { songs = typeof r.songs === "number" ? r.songs : null; drawPicks(); }
        else if (on) { status = { state: "error", error: { code: r.error && r.error.code === "busy" ? "busy" : (r.error && r.error.detail) || "failed" } }; draw(); }
      });
    }

    /// Stop listening, staying in the mode: the microphone is let go; the song stays, dimmed, with its picks.
    function stopListening() {
      wanted = false; stopped = true;
      request("booth.stop", null, { quiet: true });
      draw();
    }

    function leave() {
      if (!on) return;
      wanted = false; waiting = false; stopped = false;
      request("booth.stop", null, { quiet: true });
      show(false);
      d.render();
    }

    function showDial() {
      dialValue.textContent = t("booth.percent", { n: Math.round(Number(dial.value) * 100) });
      dial.setAttribute("aria-valuetext", dialValue.textContent);
    }
    /// The dial let go (or stepped with the keys): the picks are rolled again with it, as on the iPad.
    function moveDial() {
      shuffle = Number(dial.value);
      showDial();
      if (inputOn()) request("booth.shuffle", { shuffle }, { quiet: true });
    }

    function receive(m) {
      if (!on || (m.crate && m.crate !== crate)) return;
      if (m.event === "booth.state") {
        status = m;
        if (m.state !== "listening") heard = null;
        if (m.state === "stopped" && wanted && d.busy()) waiting = true;   // a run stopped it: listening waits
        draw();
      } else if (m.event === "booth.level") {
        const level = Math.max(0, Math.min(1, m.meter || 0)), pct = Math.round(level * 100);
        meterFill.style.width = pct + "%";
        meter.setAttribute("aria-valuenow", String(pct));
        meter.classList.toggle("clipping", (m.clipped || 0) > 0);
        setLevel(level);
        if (!!m.silent !== silent) { silent = !!m.silent; draw(); }
      } else if (m.event === "booth.heard") {
        heard = m;
        drawNow();
      } else if (m.event === "booth.playing") {
        playing = m; playingAt = performance.now();
        if (!m.song) picks = null;
        drawNow(); drawPicks();
      } else if (m.event === "booth.picks") {
        picks = m;
        drawPicks();
      }
    }

    /// The soft glow behind the song follows the level while listening (a still glow under reduced motion).
    function setLevel(level) {
      section.style.setProperty("--booth-level", String(inputOn() && !reduced() ? level : 0));
    }

    /// The input is on (the states the engine says it in).
    function inputOn() {
      return !!status && HEARING.includes(status.state) && !waiting && !stopped;
    }

    /// The song on the card: the shared rule's while the input is on (it stays while nothing is heard for a moment, as
    /// on the iPad), and kept, dimmed, after Stop listening. From an older engine: the raw reading.
    function shownSong() {
      if (playing === undefined) return !!heard && !!status && status.state === "listening" && !stopped ? heard : null;
      return playing && playing.song && (inputOn() || stopped) ? playing : null;
    }

    /// Where in the song it is now: the rule's place, moved on at its rate since the event (still while paused or not
    /// heard), within the song.
    function placeNow(s) {
      const song = s.song || {}, len = song.seconds || 0;
      let p = Math.max(0, s.place || 0);
      if (s === playing && !stopped && !playing.paused && !playing.notHeard) p += ((performance.now() - playingAt) / 1000) * (playing.rate || 1);
      return len > 0 ? Math.min(len, p) : p;
    }

    function signed(p) {
      const sign = p > 0.05 ? "pick.sign.plus" : p < -0.05 ? "pick.sign.minus" : "pick.sign.none";
      return t("pick.signed", { sign: t(sign), value: Math.abs(p).toFixed(1) });
    }

    function drawNow() {
      const shown = shownSong();
      songPart.hidden = !shown;
      waitPart.hidden = !!shown;
      card.classList.toggle("empty", !shown);
      if (!shown) { shownId = null; drawWait(); tick(); return; }
      const s = shown.song || {};
      if (s.id !== shownId) {
        if (shownId !== null || shown === playing) arrive();
        shownId = s.id;
        announce.textContent = t("booth.announce", { song: [s.title, s.artist].filter(Boolean).join(t("booth.join")) });
      }
      title.textContent = s.title || "";
      artist.textContent = s.artist || "";
      artist.hidden = !s.artist;
      const rate = shown === playing && playing.rate ? playing.rate : 1;
      tempo.textContent = s.bpm ? t("booth.tempo", { bpm: Math.round(s.bpm * rate) }) : "";
      tempo.hidden = !s.bpm;
      key.textContent = s.camelot ? t("booth.key", { camelot: s.camelot }) : "";
      key.hidden = !s.camelot;
      const p = shown === playing ? playing.pitch || 0 : 0;
      pitch.textContent = Math.abs(p) >= num("--booth-pitch-shown") ? t("booth.pitch", { pitch: signed(p) }) : "";
      pitch.hidden = !pitch.textContent;
      const notes = [];
      if (stopped) notes.push(t("booth.state.stopped"));
      else if (shown === playing) {
        if (playing.paused) notes.push(t("booth.paused"));
        else if (playing.notHeard) notes.push(t("booth.notHeard"));
        if (playing.alsoHearing) notes.push(t("booth.alsoHearing", { song: playing.alsoHearing }));
      }
      note.textContent = notes.join(t("booth.join"));
      note.hidden = !notes.length;
      // Not heard just now, paused, or stopped: the song stays, its names dimmed (the iPad's).
      card.classList.toggle("quiet", stopped || (shown === playing && (playing.paused || playing.notHeard)));
      // Stopped with the song kept: Start listening under it.
      start.hidden = !stopped;
      if (stopped) card.append(start); else waitPart.append(start);
      tick();
      if (!ticker) ticker = setInterval(tick, num("--booth-tick"));
    }

    /// The card with no song: what Booth is doing, in the words the tables have.
    function drawWait() {
      let big = t("booth.waitingTitle"), line = stateText(), warn = false;
      progress.hidden = true;
      if (!view.songsHere) { big = t("booth.heading"); line = t("booth.emptyCrate", { crate: d.shownName() }); }
      else if (waiting) { big = t("booth.state.starting"); }
      else if (stopped) { big = t("booth.state.stopped"); line = t("booth.stoppedHelp"); }
      else if (!status || status.state === "starting") { big = t("booth.state.starting"); line = ""; }
      else if (status.state === "index") {
        big = t("booth.state.starting");
        progress.hidden = false;
        progress.firstChild.style.width = (status.percent || 0) + "%";
      } else if (status.state === "error") { big = t("booth.state.stopped"); warn = true; }
      else if (status.state === "noSound") { warn = true; }
      else if (status.state === "listening") { line = t("booth.waitingHelp"); }
      waitTitle.textContent = big;
      stateLine.textContent = line;
      stateLine.hidden = !line;
      stateLine.classList.toggle("warn", warn);
      again.hidden = !(status && status.state === "error" && !waiting && !stopped && view.songsHere);
      start.hidden = !(stopped && view.songsHere);
    }

    function stateText() {
      if (waiting) return t("booth.waits");
      if (!status) return t("booth.state.starting");
      if (status.state === "index") return t("booth.state.index", { crate: d.shownName(), percent: status.percent || 0 });
      if (status.state === "error") {
        const code = (status.error && status.error.code) || "other";
        const k = `booth.error.${code}`;
        return t(d.has(k) ? k : "booth.error.other", { detail: (status.error && status.error.detail) || "" });
      }
      return t(`booth.state.${status.state}`, { crate: d.shownName() });
    }

    /// A new song: a short rise of its names and the card's glow (none under reduced motion).
    function arrive() {
      if (!moving()) return;
      for (const [node, cls] of [[songPart, "arrive"], [card, "moment"]]) {
        node.classList.remove(cls); void node.offsetWidth; node.classList.add(cls);
        setTimeout(() => node.classList.remove(cls), num("--booth-t-arrive") + num("--t-moment-after"));
      }
    }

    /// The place along the song: the time and the time left, and its wave with the part played lit and a line where
    /// the song is. A song the crate has no wave for: a thin line, with the place on it.
    function tick() {
      const shown = shownSong();
      if (!shown || !on) { clearInterval(ticker); ticker = 0; return; }
      const s = shown.song || {}, len = s.seconds || 0, at = placeNow(shown);
      placeAt.textContent = t("booth.place", { place: mmss(at), length: mmss(len) });
      placeLeft.textContent = len > 0 ? t("booth.left", { time: mmss(Math.max(0, len - at)) }) : "";
      drawWave(s.wave || [], s.bars || 0, len > 0 ? at / len : 0);
    }

    function drawWave(values, bars, share) {
      if (!window.DeskWave || wave.clientWidth === 0) return;
      const { ctx, w, h, dpr } = window.DeskWave.fit(wave);
      ctx.clearRect(0, 0, w, h);
      const H = window.DeskWave.barHeights(values, bars), mid = h / 2, room = h * num("--booth-wave-room");
      const x = Math.round(share * w), gap = num("--wave-bar-gap-share");
      if (!H.length) { ctx.fillStyle = css("--wave-none"); ctx.fillRect(0, Math.round(mid), w, Math.max(1, dpr)); }
      for (let k = 0; k < H.length; k++) {
        const x0 = (k * w) / H.length, slot = w / H.length, v = Math.max(dpr, H[k] * room);
        const played = (k + 0.5) / H.length <= share;
        ctx.fillStyle = css(played ? "--booth-wave-played" : (window.DeskWave.isQuiet(H[k]) ? "--booth-wave-quiet" : "--booth-wave-ahead"));
        ctx.fillRect(Math.round(x0), mid - v / 2, Math.max(dpr, Math.round(slot * (1 - gap))), v);
      }
      ctx.fillStyle = css("--booth-playhead");
      const pw = Math.max(1, Math.round(num("--booth-playhead-w") * dpr));
      ctx.fillRect(Math.min(w - pw, Math.max(0, x - Math.floor(pw / 2))), 0, pw, h);
    }

    /// One pick as a row: its name and artist, the tempo line and the move under them; the keys and what is unexpected
    /// at its side. "Keys may clash" is marked (it is in the move's words).
    function pickRow(p, i, animate) {
      const tags = (p.tags || []).map((x) => el("span", { class: "chip booth-tag", text: x }));
      const row = el("li", { class: "booth-pick" },
        el("div", { class: "booth-pick-main" },
          el("p", { class: "booth-pick-title", text: p.title || "" }),
          p.artist ? el("p", { class: "booth-pick-artist", text: p.artist }) : null,
          el("p", { class: "booth-pick-line" },
            el("span", { class: "booth-pick-bpm", text: p.bpmLine || "" }),
            p.moveLine ? el("span", { class: "booth-pick-move", text: p.moveLine }) : null)),
        el("div", { class: "booth-pick-side" },
          el("span", { class: "booth-pick-keys", text: p.keys || p.key || "" }),
          tags.length ? el("span", { class: "booth-tags" }, ...tags) : null));
      row.classList.toggle("clash", !!p.keysClash);
      if (animate) { row.classList.add("enter"); row.style.animationDelay = `calc(var(--booth-t-stagger) * ${i})`; }
      return row;
    }

    function drawPicks() {
      const shown = shownSong();
      const ready = !!shown && !!playing && shown === playing && !!picks && picks.for === playing.song.id;
      const list = ready ? picks.picks || [] : [];
      const more = ready ? picks.morePicks || [] : [];
      const k = ready ? [picks.for, picks.shuffle].concat(list.map((p) => p.id)).join(" ") : "";
      const animate = ready && k !== picksKey && moving();
      if (k !== picksKey || !ready) {
        picksList.replaceChildren(...list.map((p, i) => pickRow(p, i, animate)));
        moreList.replaceChildren(...more.map((p, i) => pickRow(p, i + list.length, animate)));
      }
      picksKey = k;
      // The class goes once the fade is over (a row is never left at the fade's first frame).
      if (animate) setTimeout(() => { for (const r of section.querySelectorAll(".booth-pick.enter")) r.classList.remove("enter"); }, num("--booth-t-enter-done"));
      picksEmpty.hidden = ready && list.length > 0;
      picksEmpty.textContent = ready ? t("booth.picksNone") : t("booth.picksWait");
      moreTitle.hidden = moreList.hidden = !more.length;
      const rest = ready ? Math.max(0, (picks.more || 0) - more.length) : 0;
      picksMore.hidden = !rest;
      picksMore.textContent = rest ? t("booth.picksMore", { n: rest }) : "";
      if (ready && typeof picks.shuffle === "number" && document.activeElement !== dial) { dial.value = String(picks.shuffle); showDial(); }
      const few = typeof songs === "number" && songs > 0 && songs < num("--booth-few-songs");
      fewLine.hidden = !few;
      fewLine.textContent = few ? t("booth.fewSongs", { crate: d.shownName(), n: songs }) : "";
      dial.disabled = !view.songsHere;
    }

    /// The state the head shows beside the mode's name: listening (lit), or not.
    function drawLive() {
      const hearing = inputOn();
      const getting = !!status && ["starting", "index"].includes(status.state) && !stopped;
      liveText.textContent = hearing ? t("booth.state.listening") : getting || waiting ? t("booth.state.starting") : t("booth.state.stopped");
      live.classList.toggle("on", hearing);
    }

    function draw() {
      if (!on) return;
      sub.textContent = t("booth.title", { crate: d.shownName() });
      drawLive();
      const hearing = inputOn();
      // The foot's line about the input: no sound coming (the state's own words) or none arriving at all, while a
      // song is on the card (with no song the card says it).
      const noSound = hearing && status.state === "noSound";
      const line = noSound ? stateText() : silent && hearing ? t("booth.silent") : "";
      inputNote.textContent = line;
      inputNote.hidden = !line || (!shownSong() && noSound);
      stopButton.hidden = !(view.songsHere && !stopped && !waiting && status && !["error", "stopped"].includes(status.state));
      select.disabled = !inputs.length || !view.songsHere;
      // The level shows only while the input is on.
      if (!hearing) { meterFill.style.width = "0%"; meter.setAttribute("aria-valuenow", "0"); meter.classList.remove("clipping"); setLevel(0); }
      section.classList.toggle("hearing", hearing);
      drawNow(); drawPicks();
    }

    /// From desk.js's render: the switch shows for any crate; another crate, or none, leaves the mode; a run started
    /// from the mode leaves it; a run that ends lets listening that waited start. A crate with no songs gets the plain
    /// line.
    function render(v) {
      view = v;
      words();
      button.hidden = !d.current() && !on;
      if (!on) return;
      const c = d.current();
      if (!c || c.id !== crate) { leave(); return; }
      if (v.busy && !waiting) { leave(); return; }
      if (!v.busy && waiting) { listen(); return; }
      draw();
    }

    window.addEventListener("resize", () => { if (on) tick(); });
    // The window going away: the engine stops when its input closes, but say it first where the page can.
    window.addEventListener("pagehide", () => { if (on) request("booth.stop", null, { quiet: true }); });

    return { receive, render, isOn: () => on };
  };
})();
