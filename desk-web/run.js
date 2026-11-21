// The run screen of Deckie Desk's window on Windows and Linux (D37): draws what Desk is really doing and what it really
// found, from the engine's `run.songs` events (docs/architecture/desk-protocol.md, "The run screen"). Every wave is a
// song Desk read, every number is counted by the engine, every sentence is one the engine said is true, or a line
// about the step Desk is on. The song on stage moves for the pleasure of it (letter AD): it pulses and breathes at its
// own tempo, built from its own wave and bars. No words of its own: they are the engine's (DeskWords), passed in.
//
// Drawing is throttled (the stage at most thirty frames a second while the run goes, the wall at most every --t-wall).
// While the window is hidden, or behind others where the window gives no animation frames (a WKWebView or WebView2 not
// in front), nothing moves, but what is shown never falls behind: the stage takes the latest song, still, the figures
// and the wall are drawn as the songs come, so the window is right whenever it is looked at (a picture of it included).
// No state waits for an animation frame. Under reduced motion nothing moves: the same pictures, still.
// Colours, sizes, shares and times are the CSS variables in desk.css's :root; the numbers left here are the drawing's
// own arithmetic (64 points a wave, a mark every 8 bars and a longer one every 32, twelve keys round the wheel).
(function () {
  "use strict";

  const root = document.documentElement;
  const css = (name) => getComputedStyle(root).getPropertyValue(name).trim();
  const time = (name) => parseFloat(css(name)) || 0;
  /// A number from desk.css's :root (a size in CSS pixels, a share, a count): every number the drawing uses is one.
  const num = (name) => parseFloat(css(name));
  const reduceQuery = window.matchMedia ? matchMedia("(prefers-reduced-motion: reduce)") : { matches: false };
  const reduced = () => reduceQuery.matches;
  /// A song's wave as separate bars, each 0 to 1 of the room (RunSong.barHeights in the core does the same): one bar
  /// a bar of music when the song has fewer bars than the wave has values, else one a value; stretched to the song's
  /// own range, its tenth-quietest value in a hundred at --wave-bar-floor and its loudest at the top, a level song (values within
  /// --wave-range-min of each other) standing at full height. The quiet bars (under --wave-quiet-share of the room
  /// above the floor) take the quiet tone, so breakdowns and intros stand apart.
  function barHeights(wave, bars) {
    if (!wave || !wave.length) return [];
    const n = wave.length, floor = Math.max(0, Math.min(1, num("--wave-bar-floor"))), rangeMin = Math.max(num("--wave-range-min"), 1e-9);
    let v = wave.map((x) => Math.max(0, Math.min(99, x)));
    if (bars > 0 && bars < n) {
      const all = v;
      v = [];
      for (let i = 0; i < bars; i++) {
        const a = Math.floor((i * n) / bars), e = Math.max(a + 1, Math.floor(((i + 1) * n) / bars));
        v.push(Math.max(...all.slice(a, Math.min(e, n))));
      }
    }
    // The quiet end is the song's tenth-quietest value in a hundred: a silent lead-in or tail does not squash the rest.
    const sorted = v.slice().sort((a, b) => a - b);
    const hi = sorted[sorted.length - 1], lo = Math.min(sorted[Math.floor(sorted.length / 10)], hi - rangeMin);
    return v.map((x) => floor + (1 - floor) * Math.max(0, Math.min(1, (x - lo) / (hi - lo))));
  }
  const isQuiet = (hgt) => hgt < num("--wave-bar-floor") + (1 - num("--wave-bar-floor")) * num("--wave-quiet-share");

  /// A canvas sized to its box in device pixels; its context, width and height.
  function fit(canvas) {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = Math.max(1, Math.round(canvas.clientWidth * dpr)), h = Math.max(1, Math.round(canvas.clientHeight * dpr));
    if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
    return { ctx: canvas.getContext("2d"), w, h, dpr };
  }
  /// Adds a class for one moment's motion, then takes it away. Nothing under reduced motion (the CSS has none).
  function pulse(node, cls) {
    if (!node || reduced()) return;
    node.classList.remove(cls); void node.offsetWidth; node.classList.add(cls);
    setTimeout(() => node.classList.remove(cls), time("--t-moment") + time("--t-moment-after"));
  }

  window.DeskRunScreen = function (env) {
    const { $, el, t, n, mmss } = env;
    let songs = [], figures = null, info = { read: "", musicCD: false }, step = "reading";
    let lastNote = null;          // the run's finished moment, for the finished screen

    // ---- words for what Desk found
    const bpmText = (s) => (s.bpm != null ? t("bpmValue", { bpm: s.bpm.toFixed(1) }) : t("none"));
    function keyText(k) {
      if (!k || k.kind === "none") return t("keyNotSureValue");
      if (k.kind === "home") return t("homeNoteValue", { note: k.name });
      const key = t("keyValue", { camelot: k.camelot, note: k.name, mode: t(k.minor ? "mode.minor" : "mode.major") });
      return k.uncertain ? t("keyWithDoubt", { key, doubt: t("keyNotSure") }) : key;
    }
    const whereText = (s) => s.place || (s.folder ? s.folder : t("topOfMusicFolder"));
    /// The song's name as the walls say it ("Artist – Title").
    const rowName = (s) => (s.artist ? t("wallRowName", { artist: s.artist, title: s.title }) : s.title);
    /// What Desk found, as the wall's row shows it after the name: tempo, key and length.
    const rowFacts = (s) => [bpmText(s), keyText(s.key), mmss(s.seconds)];
    function songLine(s) {
      // The song's name, then what Desk found and where it is: the line a screen reader hears for a row.
      return [rowName(s), ...rowFacts(s), whereText(s)].join(t("join.wallSong"));
    }
    function noteText(note) {
      const v = Object.assign({}, note.values || {});
      if (v.mode) v.mode = t("mode." + v.mode);
      // A count is written by n(), grouped as this computer writes numbers ("1,000").
      if (note.n != null) delete v.n;
      if (note.code === "finished") v.duration = musicTime(Number(v.seconds || 0));
      const key = (note.kind === "moment" ? "moment." : "fact.") + note.code;
      return note.n != null ? n(key, note.n, v) : t(key, v);
    }
    function musicTime(s) {
      const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
      return h > 0 ? t("figHoursMinutes", { h, m }) : t("figMinutes", { m });
    }

    // ---- the song card (the owner's note, Nov 20, 2026): the song being worked on, its parts filling in as Desk
    // works them out. Drawn from the engine's last `run.progress` (its `working`, each with its parts) and its
    // `run.songs` (a song done). The card keeps its song while it is worked on; done, the song stays complete on the
    // card --t-card-done, then goes to the wall and the card takes the next. Several at once: the card has the one
    // furthest along, the rest are rows under it. Every name and fact on the card is its song's.
    const stage = $("stage"), stageCanvas = $("stage-wave"), cardEl = $("song-card");
    let onStage = null, timer = 0, raf = 0, lastFrame = 0, running = false;
    let run = null;                 // the last run.progress, as desk.js keeps it
    let card = { rel: null, done: null, doneUntil: 0, doneTimer: 0, next: null };
    /// The songs shown as rows under the card at the last draw.
    let shownRows = new Set();
    const NOW_STEPS = ["hash", "decode", "resample", "key", "beatthis", "spectral", "structure", "loudness", "vocal", "windows"];
    const nowReading = (x) => x.step === "started" || x.step === "reading";
    /// The song's name as RunNow.name gives it: the name Desk has, else its file name without the ending.
    function nowName(x) {
      if (x.title) return x.title;
      const last = String(x.rel || "").split("/").pop();
      const dot = last.lastIndexOf(".");
      return dot > 0 ? last.slice(0, dot) : last;
    }
    const nowStage = (x) => (nowReading(x) ? t("nowOpening") : env.coded("nowStage", x.step));
    function nowLine(x, total) {
      if (nowReading(x)) return x.number != null ? t("nowReadingDisc", { number: x.number, total }) : t("nowReading");
      return x.number != null ? t("nowStageOf", { number: x.number, total, stage: nowStage(x) }) : t("nowStageAlone", { stage: nowStage(x) });
    }
    /// How far through the song, 0 to 1 (RunNow.share): the share read while it is read, then its steps done, each an
    /// equal share; within a step that says how far it is (`within`, an addition of Nov 21, 2026: the beat model's
    /// chunks done), toward the next step's place in proportion. An entry without `within` gives the step's place.
    function nowShare(x) {
      if (nowReading(x)) return x.read != null ? Math.max(0, Math.min(1, x.read)) : 0;
      const i = NOW_STEPS.indexOf(x.step);
      if (i < 0) return 1;
      const within = typeof x.within === "number" ? Math.max(0, Math.min(1, x.within)) : 0;
      return Math.min(1, (i + 1 + within) / NOW_STEPS.length);
    }
    const hasParts = (x) => x.seconds != null || x.bpm != null || x.bars != null || x.key != null || x.wave != null;
    /// The songs being worked on: `working` (an addition to protocol 2), else `now` alone (an engine before it).
    const workingList = () => (!run ? [] : run.working && run.working.length ? run.working : run.now ? [run.now] : []);
    /// RunNow.cardSong: the card's song while it is worked on; else the furthest along, the first taken of equals.
    function cardSong(list, keep) {
      const kept = keep && list.find((x) => x.rel === keep);
      if (kept) return kept;
      let best = null;
      for (const x of list) if (!best || nowShare(x) > nowShare(best)) best = x;
      return best;
    }
    /// One fact in its place on the card: its words, or a quiet placeholder until it is worked out.
    function fact(id, text, cls) {
      const d = $(id);
      d.classList.toggle("pending", text == null);
      d.classList.toggle("quiet", !!cls && cls.quiet);
      d.textContent = text == null ? "" : text;
    }
    /// The card for `x` (a song worked on, or a song done and still on the card): its name, step and parts.
    function fillCard(x, done) {
      cardEl.classList.remove("no-song");
      cardEl.dataset.rel = x.rel || "";
      // The name it had while it was worked on, done or not: the card's song does not change its name as it finishes.
      $("now-title").textContent = nowName(x);
      $("now-artist").textContent = x.artist || "";
      const disc = $("now-disc");
      disc.toggleAttribute("hidden", !run || !run.musicCD);   // an svg has no .hidden
      disc.classList.toggle("turning", !!run && run.musicCD && !done);
      $("now-line").textContent = nowLine(done ? Object.assign({}, x, { step: "windows" }) : x, run ? run.total : 0);
      const pct = done ? 100 : Math.round(nowShare(x) * 100);
      const bar = $("now-bar");
      bar.firstElementChild.style.width = pct + "%";
      bar.setAttribute("aria-valuenow", String(pct));
      const f = done || x;
      fact("stage-tempo", f.bpm != null ? bpmText(f) : (done ? t("none") : null));
      fact("stage-key", f.key ? keyText(f.key) : (done ? keyText(null) : null), { quiet: f.key ? f.key.kind !== "key" : !!done });
      fact("stage-bars", f.bars != null ? String(f.bars) : (done ? t("none") : null));
      fact("stage-length", f.seconds != null ? mmss(f.seconds) : null);
      fact("stage-where", f.place || f.folder != null ? whereText(f) : null);
      $("stage-more").textContent = done && !(done.wave || []).length ? t("stageNoWave") : "";
      stageCanvas.setAttribute("aria-label", t("stageWaveLabel", { title: nowName(x) }));
      // The wave once its loudness is measured: swept in from the left, then moving with the song.
      const wave = f.wave || [];
      // Whose wave the canvas holds (a check reads it: the wave is always the card's song's).
      stageCanvas.dataset.rel = wave.length ? x.rel || "" : "";
      if (!wave.length) { onStage = null; waveSpace(); return; }
      if (!onStage || onStage.rel !== x.rel || !onStage.heights.length) {
        const now = performance.now(), still = reduced() || document.hidden;
        onStage = { rel: x.rel, song: { bpm: f.bpm, bars: f.bars, wave }, at: now, hold: time("--t-hold"),
          draw: still ? 0 : time("--t-draw"), heights: barHeights(wave, f.bars), from: [] };
        readLook(); drawStage(now); lastFrame = now; kick();
      }
    }
    /// The card with no song: the step alone (between songs, before the first, while the crate is finished and saved).
    function emptyCard(word) {
      cardEl.classList.add("no-song");
      cardEl.dataset.rel = "";
      $("now-title").textContent = ""; $("now-artist").textContent = "";
      $("now-disc").toggleAttribute("hidden", !run || !run.musicCD);
      $("now-disc").classList.remove("turning");
      $("now-line").textContent = t(word);
      for (const id of ["stage-tempo", "stage-key", "stage-bars", "stage-length", "stage-where"]) fact(id, null);
      $("stage-more").textContent = "";
      stageCanvas.dataset.rel = "";
      onStage = null;
      waveSpace();
    }
    /// The wave's place before its loudness is measured: the centre line alone, quietly.
    function waveSpace() {
      if (!look) readLook();
      const { ctx, w, h } = fit(stageCanvas);
      ctx.clearRect(0, 0, w, h);
      if (cardEl.classList.contains("no-song")) return;
      const waveH = h - Math.round(h * look.markH);
      ctx.fillStyle = look.none;
      ctx.fillRect(0, Math.round(waveH / 2 - look.lineH / 2), w, look.lineH);
    }
    function drawRows(list) {
      shownRows = new Set(list.map((x) => x.rel));
      const rows = $("now-rows");
      rows.hidden = !list.length;
      $("now-rows-title").textContent = list.length ? n("alsoWorkingOn", list.length) : "";
      $("now-list").replaceChildren(...list.map((x) => el("li", { "data-rel": x.rel },
        el("span", { class: "now-name" }, el("b", { text: nowName(x) }), x.artist ? el("span", { class: "mut", text: " " + x.artist }) : null),
        el("span", { class: "mut now-step", text: nowStage(x) }))));
    }
    /// The song done on the card goes to the wall (its row lit a moment), and the card is free for the next.
    function endDone() {
      clearTimeout(card.doneTimer); card.doneTimer = 0;
      if (!card.done) return;
      onWall.push(card.done);
      card.done = null; card.rel = null;
      runWall.added(onWall.length - 1);
      runWall.label(t("wallLabel", { title: t("wallTitle"), songs: n("songs", onWall.length) }));
    }
    /// The card and the rows, now.
    function drawCard() {
      if (!run) return;
      const list = workingList();
      if (run.stage !== "reading") {
        // The read is over: the card's song goes to the wall now, and the wall is drawn now, not on its throttle.
        endDone(); runWall.now();
        emptyCard(run.stage === "saving" ? "stageSaving" : "stageFinishing"); drawRows([]); drawAhead(); return;
      }
      if (card.done && performance.now() < card.doneUntil) {
        // Called again when the moment is over (a timer may come a little early: it is set again for the rest).
        clearTimeout(card.doneTimer);
        card.doneTimer = setTimeout(drawCard, Math.max(0, card.doneUntil - performance.now()) + 1);
        fillCard(card.now, card.done);
        // A song taken while the card holds the one just done is the card's next song, not one worked on alongside:
        // it is no row (read one at a time, a row would come and go with every song). Songs already rows stay rows.
        if (!card.next) {
          const next = cardSong(list.filter((x) => x.rel !== card.rel && !shownRows.has(x.rel)), null);
          card.next = next ? next.rel : null;
        }
        drawRows(list.filter((x) => x.rel !== card.rel && x.rel !== card.next));
        drawAhead();
        return;
      }
      endDone();
      const x = cardSong(list, card.rel || card.next);
      card.next = null;
      card.rel = x ? x.rel : null;
      if (x) { card.number = x.number; card.now = x; fillCard(x, null); } else emptyCard("stageReading");
      drawRows(list.filter((y) => !x || y.rel !== x.rel));
      drawAhead();
    }
    function drawAhead() {
      const ahead = $("now-ahead");
      ahead.hidden = !(run && run.ahead && run.stage === "reading");
      ahead.textContent = ahead.hidden ? "" : t("nowAheadDisc");
    }
    /// A song done (`run.songs`): the card's own song stays complete on the card a moment, then goes to the wall;
    /// any other song (a row, or one worked out before) goes to the wall at once.
    let onWall = [];
    function songDone(s) {
      // Its parts may come with its "done" rather than before it (the progress that carried them can be passed
      // over): the song done has them, so it stays on the card complete all the same.
      const onCard = card.rel && s.rel === card.rel && card.now && (hasParts(card.now) || hasParts(s)) && !card.done;
      if (onCard) {
        card.done = s; card.doneUntil = performance.now() + time("--t-card-done");
        drawCard();
        return;
      }
      onWall.push(s);
      runWall.added(onWall.length - 1);
    }
    /// The stage's values, read from desk.css once a song rather than every frame.
    let look = null;
    function readLook() {
      look = {
        markH: num("--stage-mark-h"), least: num("--stage-wave-min"), room: num("--stage-wave-room"), lineH: num("--stage-line-h"),
        none: css("--wave-none"), wave: css("--wave"), tick: css("--wave-tick"), tickStrong: css("--wave-tick-strong"),
        tickW: num("--stage-tick-w"), strongW: num("--stage-tick-strong-w"), tickGap: num("--stage-tick-gap"), tickShort: num("--stage-tick-short"),
        frame: num("--stage-frame"), gapShare: num("--wave-bar-gap-share"), quiet: css("--wave-quiet"),
        fastest: time("--t-beat-fastest"), slowest: time("--t-beat-slowest"), inBar: num("--stage-beats-in-bar"),
        pulse: num("--stage-pulse"), downbeat: num("--stage-pulse-downbeat"), fall: num("--stage-pulse-fall"),
        breath: num("--stage-breath"), breathBars: num("--stage-breath-bars"), breathNoTempo: time("--t-breath-no-tempo"),
        stagger: num("--stage-sweep-stagger"), overshoot: num("--stage-morph-overshoot"),
        playBars: num("--stage-playhead-bars"), playNoTempo: time("--t-playhead-no-tempo"), playW: num("--stage-playhead-w"),
        lift: num("--stage-playhead-lift"), glow: css("--stage-playhead-glow"), clear: css("--stage-playhead-clear"),
      };
    }
    // How the song on stage moves (letter AD), the same arithmetic as the Mac's StageMotion: the sweep from the last
    // song's wave to this one's, a pulse on each beat of its tempo, a slow breath over a few bars, and a playhead
    // crossing it. Times in ms, each held to nothing or more; every index held to the wave it reads, however short.
    function beatOf(bpm, L) {
      if (bpm == null || !isFinite(bpm) || bpm <= 0) return null;
      let b = 60000 / bpm, turns = 0;
      while (b < L.fastest && turns < 16) { b *= 2; turns++; }
      while (b > L.slowest && turns < 32) { b /= 2; turns++; }
      return b;
    }
    /// Bar i of n's height in a song's bars (another song's bars, sampled to n), 0 with none.
    function shapeAt(heights, i, n) {
      if (!heights || !heights.length || n <= 0) return 0;
      return heights[Math.max(0, Math.min(heights.length - 1, Math.floor((i * heights.length) / n)))];
    }
    function motion(st, now, still, L) {
      const e = isFinite(now - st.at) ? Math.max(0, now - st.at) : 0, sweep = Math.max(0, st.draw || 0);
      const beat = beatOf(st.song.bpm, L);
      const m = { e, sweep, still, front: still || sweep <= 0 ? 1 : Math.max(0, Math.min(1, e / Math.max(sweep * L.stagger, 1e-9))), swell: 0, playhead: null };
      if (still) return m;
      if (beat) {
        const ph = e / beat, k = Math.floor(ph), frac = ph - k;
        const pulse = (k % L.inBar === 0 ? L.downbeat : L.pulse) * Math.exp(-L.fall * frac);
        m.swell = pulse + L.breath * 0.5 * (1 - Math.cos((2 * Math.PI * ph) / (L.inBar * L.breathBars)));
      } else {
        m.swell = L.breath * 0.5 * (1 - Math.cos((2 * Math.PI * e) / L.breathNoTempo));
      }
      const cross = beat ? beat * L.inBar * L.playBars : L.playNoTempo;
      if (e >= sweep && cross > 0) { const t = (e - sweep) / cross; m.playhead = t - Math.floor(t); }
      return m;
    }
    function heightAt(m, i, n, from, to, L) {
      const target = shapeAt(to, i, n);
      if (m.still || m.sweep <= 0) return target;
      const start = (i / Math.max(1, n - 1)) * m.sweep * L.stagger, span = Math.max(m.sweep * (1 - L.stagger), 1e-9);
      const x = Math.max(0, Math.min(1, (m.e - start) / span)), c = L.overshoot;
      const eased = 1 + (c + 1) * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2);
      const was = shapeAt(from, i, n);
      return Math.max(0, was + (target - was) * eased);
    }
    function drawStage(now) {
      if (!onStage) return;
      if (!look) readLook();
      const L = look, { ctx, w, h, dpr } = fit(stageCanvas);
      const s = onStage.song, still = reduced() || document.hidden;
      const m = motion(onStage, now, still, L);
      ctx.clearRect(0, 0, w, h);
      const markH = Math.round(h * L.markH), waveH = h - markH, edge = m.front * w;
      if (waveH <= 0) return;
      ctx.fillStyle = L.none;
      ctx.fillRect(0, Math.round(waveH / 2 - L.lineH / 2), w, L.lineH);   // the centre line
      // The wave: a bar each, mirrored about a centre line, each growing or shrinking from the last song's height to this
      // one's, then breathing with the song; the quiet ones in the quiet tone; the playhead a band of light.
      const H = onStage.heights, N = H.length;
      if (N) {
        const slot = w / N, barW = Math.max(1, slot * (1 - L.gapShare));
        const playX = m.playhead != null ? m.playhead * w : null;
        const norm = 1 + L.downbeat + L.breath + L.lift;
        for (let i = 0; i < N; i++) {
          const base = heightAt(m, i, N, onStage.from, H, L);
          const cx = (i + 0.5) * slot;
          const d = playX != null ? Math.abs(cx - playX) / w / L.playW : 1;
          const lift = d < 1 ? L.lift * (1 - d) : 0;
          const v = Math.max(L.least, base * ((1 + m.swell + lift) / norm) * waveH * L.room);
          const x = cx - barW / 2;
          ctx.fillStyle = isQuiet(H[i]) ? L.quiet : L.wave;
          ctx.fillRect(x, waveH / 2 - v / 2, barW, v);   // mirrored about the centre line
          if (d < 1) { ctx.globalAlpha = 1 - d; ctx.fillStyle = L.glow; ctx.fillRect(x, waveH / 2 - v / 2, barW, v); ctx.globalAlpha = 1; }
        }
      }
      // Its bars marked as the sweep passes: a cut through the wave every 8 bars and a mark below it, a longer one every 32.
      if (s.bars) {
        const scale = Math.min(dpr, 2);
        const tickW = L.tickW * scale, strongW = L.strongW * scale, gap = L.tickGap * scale;
        for (let b = 8; b < s.bars; b += 8) {
          const x = Math.round((b / s.bars) * w);
          if (x > edge) break;
          const strong = b % 32 === 0;
          ctx.fillStyle = strong ? L.tickStrong : L.tick;
          ctx.fillRect(x, waveH + gap, tickW, Math.max(0, strong ? markH - gap : (markH - gap) * L.tickShort));
        }
      }
    }
    /// Whether the stage is moving: a song on it, the run going, the window showing, the stage on screen, and motion
    /// allowed. Under reduced motion it draws once a song.
    const moving = () => running && !!onStage && !document.hidden && !reduced() && stage.offsetParent !== null;
    function tick(now) {
      raf = 0; clearTimeout(late); late = 0;
      if (!look) readLook();
      // At most one frame every --stage-frame ms.
      if (now - lastFrame >= look.frame || now < lastFrame) { drawStage(now); lastFrame = now; }
      schedule(now);
    }
    /// Keeps the card's wave going: a frame every --stage-frame ms while it moves.
    function schedule(now) {
      clearTimeout(timer); timer = 0;
      if (document.hidden || !onStage || !moving()) return;
      timer = setTimeout(kick, Math.max(0, look.frame - (now - lastFrame)));
    }
    /// The next step: on the next animation frame, or, when none comes within --t-frame-late (the window hidden or
    /// not in front), at once without one, so a song read is on the stage whether or not anything is drawing frames.
    let late = 0;
    function kick() {
      if (raf) return;
      raf = requestAnimationFrame(tick);
      clearTimeout(late);
      late = setTimeout(() => { if (raf) { cancelAnimationFrame(raf); raf = 0; tick(performance.now()); } }, time("--t-frame-late"));
    }

    // ---- what Desk has found so far
    const histCanvas = $("fig-tempos"), wheel = $("fig-keys");
    let latestBin = -1;
    function drawFigures() {
      const f = figures;
      if (!f) return;
      $("fig-music-value").textContent = musicTime(f.seconds);
      // Tempos: one bar a bin over the whole range, each as tall as its count against the fullest.
      const { ctx, w, h } = fit(histCanvas);
      ctx.clearRect(0, 0, w, h);
      const most = Math.max(1, ...f.tempos), slot = w / f.tempos.length, barW = Math.max(num("--hist-bar-min-w"), slot - num("--hist-bar-gap"));
      const base = num("--hist-baseline"), least = num("--hist-bar-min"), headroom = num("--hist-top");
      ctx.fillStyle = css("--wave-none"); ctx.fillRect(0, h - base, w, base);
      f.tempos.forEach((c, i) => {
        if (!c) return;
        const bh = Math.max(least, (c / most) * (h - headroom));
        ctx.fillStyle = i === latestBin ? css("--wave-new") : css("--wave");
        ctx.fillRect(i * slot, h - bh, barW, bh);
      });
      const text = temposText(f);
      $("fig-tempos-text").textContent = text;
      histCanvas.setAttribute("aria-label", text);
      drawWheel(f);
      $("fig-needname").textContent = f.needName.toLocaleString();
      $("fig-samefile").textContent = f.sameFile.toLocaleString();
      $("fig-copies").textContent = f.copies != null ? f.copies.toLocaleString() : t("figCopiesLater");
      $("fig-copies").classList.toggle("later", f.copies == null);
      $("fig-notin").textContent = f.notIn.toLocaleString();
      const ni = $("run-notin");
      ni.hidden = !(f.notIn > 0);
      ni.textContent = n("filesDidntGoIn", f.notIn);
    }
    /// The tempos figure in words, as RunFigures.temposText says it on the Mac: one tempo once ("1 song, 118 BPM"); a
    /// range alone when no tempo is shared; else the tempo most share (the engine counts it), held within the range.
    function temposText(f) {
      const withTempo = f.songs - f.noTempo;
      if (!(withTempo > 0) || f.slowest == null) return t("figTemposNone");
      const low = Math.round(f.slowest), high = Math.round(f.fastest), songs = n("songs", withTempo);
      if (withTempo === 1 || low === high) return t("figTemposOne", { songs, bpm: low });
      if (f.mostTempo == null) return t("figTemposRange", { songs, low, high });
      return t("figTemposText", { songs, low, high, mode: Math.min(high, Math.max(low, f.mostTempo)) });
    }
    // The wheel of the twelve home notes round the circle of fifths: the outer ring major, the inner minor, a dot inside
    // for a song whose home note alone Desk found. A key that has turned up is filled, brighter the more songs it has.
    const FIFTHS = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5];
    const noteName = (pc) => t("noteName." + (pc + 1));
    let wheelCells = null;
    function arc(r0, r1, a0, a1) {
      const c = num("--wheel-center");
      const p = (r, a) => [c + r * Math.cos(a), c + r * Math.sin(a)].map((v) => v.toFixed(2)).join(" ");
      return `M${p(r1, a0)} A${r1} ${r1} 0 0 1 ${p(r1, a1)} L${p(r0, a1)} A${r0} ${r0} 0 0 0 ${p(r0, a0)} Z`;
    }
    function buildWheel() {
      const ns = "http://www.w3.org/2000/svg";
      wheel.replaceChildren();
      const c = num("--wheel-center"), trim = num("--wheel-cell-gap"), homeR = num("--wheel-home-r");
      wheel.setAttribute("viewBox", `0 0 ${2 * c} ${2 * c}`);
      const rings = [["major", num("--wheel-major-in"), num("--wheel-major-out")], ["minor", num("--wheel-minor-in"), num("--wheel-minor-out")]];
      wheelCells = { major: [], minor: [], home: [] };
      FIFTHS.forEach((pc, i) => {
        const a0 = ((i - 0.5) * 30 - 90) * Math.PI / 180 + trim, a1 = ((i + 0.5) * 30 - 90) * Math.PI / 180 - trim;
        for (const [ring, r0, r1] of rings) {
          const path = document.createElementNS(ns, "path");
          path.setAttribute("d", arc(r0, r1, a0, a1));
          const title = document.createElementNS(ns, "title");
          path.append(title);
          wheel.append(path);
          wheelCells[ring][pc] = path;
        }
        const am = (i * 30 - 90) * Math.PI / 180;
        const dot = document.createElementNS(ns, "circle");
        dot.setAttribute("cx", (c + homeR * Math.cos(am)).toFixed(2)); dot.setAttribute("cy", (c + homeR * Math.sin(am)).toFixed(2));
        wheel.append(dot);
        wheelCells.home[pc] = dot;
      });
    }
    function drawWheel(f) {
      if (!wheelCells) buildWheel();
      const most = Math.max(1, ...f.major, ...f.minor);
      const fillMin = num("--wheel-fill-min"), fillRange = num("--wheel-fill-range"), emptyOpacity = css("--wheel-empty-opacity");
      const dotBase = num("--wheel-dot-base"), dotMax = num("--wheel-dot-max");
      for (const ring of ["major", "minor"]) {
        f[ring].forEach((c, pc) => {
          const cell = wheelCells[ring][pc];
          cell.setAttribute("fill", c ? css("--acc") : css("--wheel-empty"));
          cell.setAttribute("fill-opacity", c ? (fillMin + fillRange * (c / most)).toFixed(2) : emptyOpacity);
          cell.firstChild.textContent = t("wheelCell", { note: noteName(pc), mode: t(ring === "major" ? "mode.major" : "mode.minor"), songs: n("songs", c) });
        });
      }
      f.home.forEach((c, pc) => {
        const dot = wheelCells.home[pc];
        dot.setAttribute("r", c ? String(Math.min(dotMax, dotBase + Math.sqrt(c))) : "0");
        dot.setAttribute("fill", css("--wheel-home"));
      });
      const homes = f.home.reduce((a, b) => a + b, 0);
      const parts = [t("figKeysText", { n: f.keysFound })];
      if (homes) parts.push(n("figHomeOnly", homes));
      if (f.noKey) parts.push(n("figNoKey", f.noKey));
      const text = parts.join(t("join.keysFigure"));
      $("fig-keys-text").textContent = text;
      wheel.setAttribute("aria-label", text);
    }

    // ---- the crate filling up: a row a song, as they joined, top to bottom, each its wave as one continuous shape,
    // mirrored about the row's middle, across the whole width (the owner's note, Nov 20, 2026: no name column). The
    // rows scroll inside the card; only the rows in view are drawn, on one canvas that stays in view (position:
    // sticky), so a crate of thousands draws as fast as a dozen. Pointing at a row, a tap on it, or the arrow keys
    // light it up, fade its wave back and write the song's name in the row, centred over the wave (the owner's note,
    // Nov 21, 2026), with its tempo, key and length after it when the whole line fits. A screen reader hears the
    // full line, where included, from the hidden text beside the wall (nameEl).
    function Wall(canvas, nameEl, listOf) {
      const scroller = canvas.parentElement, space = scroller.querySelector(".wall-space");
      let pick = -1, wtimer = 0, newest = -1, newestTimer = 0, follow = true;
      let pickAt = 0, fadeRaf = 0;   // when the row was pointed at, for its wave's fade
      /// How far the pointed-at row's wave has faded, 0 to 1: at once under reduced motion.
      const faded = () => (reduced() ? 1 : Math.min(1, (performance.now() - pickAt) / Math.max(1, time("--t-fade"))));
      /// The pointed-at row's words, centred: the name, then its facts in the quieter colour when the whole line fits;
      /// else the name alone, shortened with an ellipsis if it must be.
      function drawRowName(ctx, s, w, mid, dpr) {
        const name = rowName(s), sep = t("join.wallSong"), rest = sep + rowFacts(s).join(sep);
        const room = w - 2 * num("--wall-name-pad") * dpr;
        if (room <= 0) return;
        ctx.font = `${css("--fw-wall-name")} ${num("--fs-note") * dpr}px ${css("--body")}`;
        ctx.textBaseline = "middle";
        ctx.textAlign = "left";
        const wName = ctx.measureText(name).width, wRest = ctx.measureText(rest).width;
        if (wName + wRest <= room) {
          const x = Math.round((w - wName - wRest) / 2);
          ctx.fillStyle = css("--tx"); ctx.fillText(name, x, mid);
          ctx.fillStyle = css("--mut"); ctx.fillText(rest, x + wName, mid);
          return;
        }
        let text = name;
        if (wName > room) {
          const dots = t("glyph.ellipsis");
          let lo = 0, hi = name.length;
          while (lo < hi) { const m = Math.ceil((lo + hi) / 2); if (ctx.measureText(name.slice(0, m).trimEnd() + dots).width <= room) lo = m; else hi = m - 1; }
          text = name.slice(0, lo).trimEnd() + dots;
        }
        ctx.fillStyle = css("--tx");
        ctx.textAlign = "center";
        ctx.fillText(text, Math.round(w / 2), mid);
      }
      const pitch = () => num("--wall-row-h") + num("--wall-row-gap");
      /// The rows on this wall: the songs that have gone to it, in the order they went.
      const count = () => listOf().length;
      function draw() {
        wtimer = 0;
        // Sized first, shown or not, so the card is the rows' height from the start (one empty row before any song).
        const all = count(), P = pitch(), rowH = num("--wall-row-h");
        const total = all * P;
        const view = Math.min(num("--wall-max-h"), Math.max(rowH, total));
        scroller.style.height = view + "px";
        canvas.style.height = view + "px";
        space.style.height = Math.max(0, total - view) + "px";
        if (!canvas.isConnected || canvas.offsetParent === null) return;
        const { ctx, w, h, dpr } = fit(canvas);
        ctx.clearRect(0, 0, w, h);
        if (!all) return;
        const top = scroller.scrollTop;
        const floor = num("--wave-bar-floor"), quietShare = num("--wave-quiet-share"), pad = num("--wall-row-pad") * dpr;
        const ring = Math.max(1, Math.round(num("--wall-pick-ring") * dpr));
        const cPick = css("--wave-pick"), cWave = css("--wave"), cQuiet = css("--wave-quiet"), cNew = css("--wave-new"),
              cNone = css("--wave-none"), cRow = css("--wall-row-bg"), cRowPick = css("--wall-row-pick"), cRing = css("--wall-pick-edge");
        const first = Math.max(0, Math.floor(top / P)), last = Math.min(all - 1, Math.ceil((top + view) / P));
        const fade = faded(), pickAlpha = 1 - (1 - num("--wall-pick-wave-fade")) * fade;
        // In device pixels, each bar from the end of the last to the start of the next: no gaps and no seams.
        for (let i = first; i <= last; i++) {
          const s = listOf()[i], y0 = Math.round((i * P - top) * dpr), hRow = Math.round(rowH * dpr), mid = y0 + hRow / 2;
          ctx.fillStyle = i === pick ? cRowPick : cRow;
          ctx.fillRect(0, y0, w, hRow);
          const H = barHeights(s.wave, s.bars), room = hRow - 2 * pad;
          // The row pointed at: its wave, in the pick colour, fades back behind its name.
          ctx.globalAlpha = i === pick ? pickAlpha : 1;
          if (!H.length) { ctx.fillStyle = cNone; ctx.fillRect(0, Math.round(mid), w, Math.max(1, dpr)); }
          for (let k = 0; k < H.length; k++) {
            const x0 = Math.round((k * w) / H.length), x1 = Math.round(((k + 1) * w) / H.length);
            const v = Math.max(dpr, H[k] * room);
            ctx.fillStyle = i === pick ? cPick : i === newest ? cNew : (H[k] < floor + (1 - floor) * quietShare ? cQuiet : cWave);
            ctx.fillRect(x0, mid - v / 2, x1 - x0, v);   // mirrored about the row's middle
          }
          ctx.globalAlpha = 1;
          // The row pointed at: a ring round it, and the song's name in it.
          if (i === pick) {
            ctx.strokeStyle = cRing; ctx.lineWidth = ring; ctx.strokeRect(ring / 2, y0 + ring / 2, w - ring, hRow - ring);
            drawRowName(ctx, s, w, mid, dpr);
          }
        }
        // The fade under way: drawn again on the next frame until it is done.
        if (pick >= 0 && fade < 1 && !fadeRaf) fadeRaf = requestAnimationFrame(() => { fadeRaf = 0; draw(); });
      }
      function soon() { if (!wtimer) wtimer = setTimeout(draw, time("--t-wall")); }
      function at(ev) {
        const r = canvas.getBoundingClientRect();
        const y = ev.clientY - r.top + scroller.scrollTop;
        const i = Math.floor(y / pitch());
        return i >= 0 && i < count() && (y - i * pitch()) < num("--wall-row-h") ? i : -1;
      }
      /// Keeps row i in view.
      function reveal(i) {
        const P = pitch(), view = scroller.clientHeight;
        if (i * P < scroller.scrollTop) scroller.scrollTop = i * P;
        else if ((i + 1) * P > scroller.scrollTop + view) scroller.scrollTop = (i + 1) * P - view;
      }
      function choose(i, say) {
        if (i !== pick) pickAt = performance.now();
        pick = i;
        nameEl.textContent = i >= 0 ? songLine(listOf()[i]) : "";
        if (say && i >= 0) env.announce(nameEl.textContent);
        if (i >= 0) reveal(i);
        draw();
      }
      scroller.addEventListener("scroll", () => {
        follow = scroller.scrollTop + scroller.clientHeight >= scroller.scrollHeight - pitch();
        draw();
      }, { passive: true });
      canvas.addEventListener("mousemove", (e) => { const i = at(e); if (i !== pick) choose(i, false); });
      canvas.addEventListener("mouseleave", () => { if (document.activeElement !== canvas) choose(-1, false); });
      canvas.addEventListener("click", (e) => { canvas.focus(); choose(at(e), false); });
      canvas.addEventListener("blur", () => choose(-1, false));
      canvas.addEventListener("keydown", (e) => {
        const all = count();
        if (!all) return;
        const moves = { ArrowDown: 1, ArrowUp: -1, ArrowRight: 1, ArrowLeft: -1, PageDown: 10, PageUp: -10 };
        let i = pick < 0 ? (e.key === "End" ? all - 1 : 0) : pick;
        if (e.key in moves) { if (pick >= 0) i = Math.max(0, Math.min(all - 1, pick + moves[e.key])); }
        else if (e.key === "Home") i = 0;
        else if (e.key === "End") i = all - 1;
        else if (e.key === "Escape") { choose(-1, false); return; }
        else return;
        e.preventDefault();
        choose(i, true);
      });
      window.addEventListener("resize", soon);
      return {
        // A song joined: drawn soon, and, when the rows were at their end, the newest kept in view.
        added(i) {
          // The row lit a moment, so the eye sees where the song went.
          newest = i;
          clearTimeout(newestTimer);
          newestTimer = setTimeout(() => { newest = -1; draw(); }, time("--t-wall-new"));
          if (follow) { const P = pitch(); setTimeout(() => { scroller.scrollTop = Math.max(0, (i + 1) * P - scroller.clientHeight); draw(); }, 0); }
          soon();
        },
        now: draw, soon,
        label(text) { canvas.setAttribute("aria-label", text); },
        settle() { pulse(canvas, "settle"); },
        // A new run: the last run's picture goes at once, drawn or not (a hidden canvas keeps its old bitmap otherwise,
        // squeezed into one empty row when the run screen shows).
        reset() {
          pick = -1; newest = -1; follow = true; nameEl.textContent = ""; scroller.scrollTop = 0;
          canvas.getContext("2d").clearRect(0, 0, canvas.width, canvas.height);
        },
      };
    }
    const runWall = Wall($("run-wall"), $("run-wall-name"), () => onWall);
    const doneWall = Wall($("done-wall"), $("done-wall-name"), () => songs);

    // ---- the quiet line under the progress, and the moments
    const saying = $("run-saying");
    let sayTimer = 0, lastSaid = "", fresh = [], bags = {}, pendingMoment = null;
    function stepList() {
      const lists = step === "saving" ? ["saying.saving"] : step === "finishing" ? ["saying.finishing"]
        : info.musicCD ? ["saying.disc", "saying.reading"] : ["saying.reading", "saying.folder"];
      return lists.flatMap((p) => env.list(p));
    }
    function fromBag(name, list) {
      // Every line once before any comes round again, and never the same line twice running.
      let bag = bags[name];
      if (!bag || !bag.length) { bag = bags[name] = list.slice().sort(() => Math.random() - 0.5); }
      let i = bag.findIndex((x) => x !== lastSaid);
      if (i < 0) i = 0;
      return bag.splice(i, 1)[0];
    }
    function nextSaying() {
      let text = null, moment = false;
      if (pendingMoment) { text = pendingMoment; moment = true; pendingMoment = null; }
      else if (fresh.length && !(saying.dataset.kind === "fact" && Math.random() < num("--saying-fact-skip"))) {
        text = noteText(fresh.shift());
        saying.dataset.kind = "fact";
      } else {
        const list = stepList();
        if (list.length) text = fromBag(step + (info.musicCD ? "-disc" : ""), list);
        saying.dataset.kind = "step";
      }
      if (text && text !== lastSaid) say(text, moment);
      clearTimeout(sayTimer);
      sayTimer = setTimeout(nextSaying, time("--t-saying"));
    }
    function say(text, moment) {
      lastSaid = text;
      const set = () => { saying.textContent = text; saying.classList.toggle("moment", !!moment); saying.classList.remove("out"); };
      if (reduced() || !saying.textContent) { set(); return; }
      saying.classList.add("out");
      setTimeout(set, time("--t-fade"));
    }
    function moment(note) {
      const text = noteText(note);
      if (note.code === "finished") { lastNote = text; return; }
      // A moment about one song is not said: the card is the song being worked on, not that one.
      if (!note.song) {
        env.announce(text);
        pendingMoment = text;
        clearTimeout(sayTimer);
        nextSaying();
      }
      const motion = { songs: $("run-bar"), hour: $("fig-music"), wheel: wheel, disc: $("run-wall") }[note.code];
      if (note.code === "disc") runWall.settle();
      else pulse(motion, "moment");
    }

    // ---- screen readers: the plain progress now and then, politely
    let spoken = { done: -1, at: 0 };
    function speakProgress(run) {
      if (!run.total) return;
      const now = Date.now(), step10 = Math.max(1, Math.round(run.total / 10));
      if (run.done - spoken.done < step10 && now - spoken.at < 60000 && run.done < run.total) return;
      spoken = { done: run.done, at: now };
      env.announce(t("announceProgress", { songs: n("songsOf", run.total, { done: run.done, total: run.total }),
        left: run.remaining != null ? env.timeLeft(run.remaining) : "" }));
    }

    document.addEventListener("visibilitychange", () => {
      if (document.hidden) return;
      drawFigures(); runWall.now(); doneWall.now(); kick();
    });
    // Reduced motion turned on or off while the stage shows: still at once, or moving again.
    if (reduceQuery.addEventListener) reduceQuery.addEventListener("change", kick);

    return {
      /// A run started: everything from the last one goes.
      start(m) {
        songs = []; figures = null; onStage = null; fresh = []; lastNote = null; pendingMoment = null; running = true;
        onWall = []; clearTimeout(card.doneTimer); card = { rel: null, done: null, doneUntil: 0, doneTimer: 0, next: null };
        shownRows = new Set();
        info = { read: m.read, musicCD: !!m.musicCD }; step = "reading"; spoken = { done: -1, at: 0 };
        run = { stage: "reading", total: 0, musicCD: !!m.musicCD, working: null, now: null, ahead: null };
        saying.textContent = ""; lastSaid = ""; $("done-wall-card").dataset.settled = "";
        runWall.reset(); doneWall.reset(); runWall.now();
        $("run-wall-name").textContent = "";
        runWall.label(t("wallEmpty"));
        drawCard();
        nextSaying();
      },
      /// The engine's `run.songs`: songs done. The card's own song stays on it a moment; the rest go to the wall.
      songs(m) {
        for (const s of m.songs || []) {
          songs.push(s);
          if (s.bpm != null && figures) latestBin = Math.max(0, Math.min(figures.tempos.length - 1, Math.floor((s.bpm - figures.tempoLow) / figures.tempoStep)));
          songDone(s);
        }
        if (m.figures) figures = m.figures;
        // Facts about one song are not said (the card is the song being worked on); facts about the run are.
        for (const note of m.notes || []) {
          if (note.kind === "moment") moment(note);
          else if (!note.song) { fresh = fresh.filter((x) => x.code !== note.code); fresh.push(note); if (fresh.length > 6) fresh.shift(); }
        }
        if (onWall.length) runWall.label(t("wallLabel", { title: t("wallTitle"), songs: n("songs", onWall.length) }));
        drawFigures();
      },
      /// A `run.progress` (desk.js's `run`): the card and the rows, the step Desk is on, and the plain progress for
      /// screen readers.
      progress(r) {
        run = r;
        drawCard();
        if (r.stage !== step) { step = r.stage; clearTimeout(sayTimer); nextSaying(); }
        speakProgress(r);
      },
      /// The finished screen: the run's songs as a wall of waves, and the run's last moment.
      finished(report) {
        const wallCard = $("done-wall-card");
        wallCard.hidden = !songs.length;
        if (!songs.length) return;
        running = false;
        clearTimeout(sayTimer); clearTimeout(timer); clearTimeout(card.doneTimer);
        card.done = null; card.doneTimer = 0; card.next = null; onWall = songs.slice();
        $("done-wall-title").textContent = t("wallTitleDone", { read: report.read });
        // "That's the lot" only for a run that read everything (the engine sends it only then).
        const note = report.stopped === true ? null : lastNote;
        $("done-moment").textContent = note || "";
        $("done-moment").hidden = !note;
        doneWall.label(t("wallLabel", { title: t("wallTitleDone", { read: report.read }), songs: n("songs", songs.length) }));
        // Drawn now, not on an animation frame, which a window not in front may never give; and again once the page
        // has laid the screen out, so every song in is on the wall at once.
        doneWall.now(); setTimeout(doneWall.now, 0);
        if (!wallCard.dataset.settled) { wallCard.dataset.settled = "1"; doneWall.settle(); }
      },

    };
  };
})();
