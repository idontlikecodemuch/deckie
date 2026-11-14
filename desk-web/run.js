// The run screen of Deckie Desk's window on Windows and Linux (D37): draws what Desk is really doing and what it really
// found, from the engine's `run.songs` events (docs/architecture/desk-protocol.md, "The run screen"). Nothing here is
// decoration: every wave is a song Desk read, every number is counted by the engine, every sentence is one the engine
// said is true, or a line about the step Desk is on. No words of its own: they are the engine's (DeskWords), passed in.
//
// Drawing is throttled (the stage at most thirty frames a second and only while something moves, the wall at most
// every --t-wall) and stops while the window is hidden. Under reduced motion nothing moves: the same pictures, still.
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
  const WAVE = 64;
  /// How tall a wave value (0 to 99) is drawn, from 0 to 1: one curve for every song (--wave-curve), so loud and
  /// quiet parts stand apart, and songs still compare.
  let curve = 1;
  const readCurve = () => { curve = parseFloat(css("--wave-curve")) || 1; };
  const shape = (v) => Math.pow(Math.max(0, v) / 99, curve);

  // A CSS colour as red, green, blue and alpha (0 to 255), for drawing into image data.
  const probe = document.createElement("canvas"); probe.width = probe.height = 1;
  const probeCtx = probe.getContext("2d", { willReadFrequently: true });
  function rgba(color) {
    probeCtx.clearRect(0, 0, 1, 1); probeCtx.fillStyle = "#000"; probeCtx.fillStyle = color; probeCtx.fillRect(0, 0, 1, 1);
    const d = probeCtx.getImageData(0, 0, 1, 1).data;
    return [d[0], d[1], d[2], d[3]];
  }
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
    function songLine(s) {
      const name = s.artist ? t("wallSongBy", { number: s.number, title: s.title, artist: s.artist }) : t("wallSong", { number: s.number, title: s.title });
      return [name, bpmText(s), keyText(s.key), mmss(s.seconds), whereText(s)].join(t("join.wallSong"));
    }
    function noteText(note) {
      const v = Object.assign({}, note.values || {});
      if (v.mode) v.mode = t("mode." + v.mode);
      if (v.n) v.n = Number(v.n).toLocaleString();
      if (note.code === "finished") v.duration = musicTime(Number(v.seconds || 0));
      const key = (note.kind === "moment" ? "moment." : "fact.") + note.code;
      return note.n != null ? n(key, note.n, v) : t(key, v);
    }
    function musicTime(s) {
      const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
      return h > 0 ? t("figHoursMinutes", { h, m }) : t("figMinutes", { m });
    }

    // ---- the song on stage
    const stage = $("stage"), stageCanvas = $("stage-wave");
    let queue = [], onStage = null, skipped = 0, timer = 0, raf = 0, lastFrame = 0;

    function holdFor(waiting) {
      const hold = time("--t-hold"), min = time("--t-hold-min");
      return Math.max(min, hold / (1 + waiting));
    }
    function nextSong(now) {
      const max = num("--stage-queue-max");
      if (queue.length > max) {
        // Falling behind: the oldest waiting go straight to the wall (they are on it already), and the stage says how many.
        const drop = queue.length - Math.floor(max / 2);
        queue.splice(0, drop);
        skipped += drop;
      }
      const song = queue.shift();
      // Under reduced motion a song stays at least --t-hold-still, so the stage changes as a still picture would.
      const hold = reduced() ? Math.max(time("--t-hold-still"), holdFor(queue.length)) : holdFor(queue.length);
      const ticker = reduced() || hold < num("--stage-ticker");
      onStage = { song, at: now, hold, draw: ticker ? 0 : Math.min(time("--t-draw"), hold * num("--stage-draw-share")) };
      showFacts(song, ticker);
      $("stage-more").textContent = skipped > 0 ? n("stageMore", skipped) : (song.wave.length ? "" : t("stageNoWave"));
      if (queue.length === 0) skipped = 0;
      stage.classList.add("has-song");
    }
    function showFacts(s, quick) {
      const facts = stage.querySelector(".stage-facts");
      const fill = () => {
        $("stage-title").textContent = s.title;
        $("stage-artist").textContent = s.artist || "";
        $("stage-before").hidden = !s.before;
        $("stage-tempo").textContent = bpmText(s);
        const key = $("stage-key");
        key.textContent = keyText(s.key);
        key.classList.toggle("quiet", s.key.kind !== "key");
        $("stage-bars").textContent = s.bars != null ? String(s.bars) : t("none");
        $("stage-length").textContent = mmss(s.seconds);
        $("stage-where").textContent = whereText(s);
        stageCanvas.setAttribute("aria-label", t("stageWaveLabel", { title: s.title }));
        stage.classList.remove("out");
      };
      if (quick || !facts.textContent.trim()) { fill(); return; }
      stage.classList.add("out");
      setTimeout(fill, time("--t-fade") * num("--stage-swap-share"));
    }
    function drawStage(now) {
      if (!onStage || document.hidden) return;
      const { ctx, w, h } = fit(stageCanvas);
      const s = onStage.song, wave = s.wave;
      readCurve();
      const p = onStage.draw > 0 ? Math.min(1, (now - onStage.at) / onStage.draw) : 1;
      ctx.clearRect(0, 0, w, h);
      const markH = Math.round(h * num("--stage-mark-h")), waveH = h - markH, mid = waveH / 2, slot = w / WAVE, edge = p * w;
      ctx.fillStyle = css("--wave-none");
      ctx.fillRect(0, Math.round(mid), Math.round(edge), num("--stage-line-h"));
      if (wave.length) {
        // The wave: mirrored, through the middle of each stretch, drawn in from the left as far as `p`.
        const shown = Math.min(WAVE, Math.ceil(p * WAVE));
        const least = num("--stage-wave-min"), room = num("--stage-wave-room");
        const half = (i) => Math.max(least, shape(wave[i]) * waveH * room);
        ctx.beginPath();
        ctx.moveTo(0, mid - half(0));
        for (let i = 0; i < shown; i++) ctx.lineTo(Math.min(edge, (i + 0.5) * slot), mid - half(i));
        ctx.lineTo(edge, mid - half(shown - 1));
        ctx.lineTo(edge, mid + half(shown - 1));
        for (let i = shown - 1; i >= 0; i--) ctx.lineTo(Math.min(edge, (i + 0.5) * slot), mid + half(i));
        ctx.lineTo(0, mid + half(0));
        ctx.closePath();
        ctx.fillStyle = css("--wave");
        ctx.fill();
      }
      // Its bars marked: a cut through the wave every 8 bars and a mark below it, a longer one every 32.
      if (s.bars) {
        const dpr = Math.min(window.devicePixelRatio || 1, 2);
        const tickW = num("--stage-tick-w") * dpr, strongW = num("--stage-tick-strong-w") * dpr, gap = num("--stage-tick-gap") * dpr;
        const shortMark = num("--stage-tick-short");
        for (let b = 8; b < s.bars; b += 8) {
          const x = Math.round((b / s.bars) * w);
          if (x > edge) break;
          const strong = b % 32 === 0;
          ctx.clearRect(x, 0, strong ? strongW : tickW, waveH);
          ctx.fillStyle = strong ? css("--wave-tick-strong") : css("--wave-tick");
          ctx.fillRect(x, waveH + gap, tickW, strong ? markH - gap : (markH - gap) * shortMark);
        }
      }
    }
    function tick(now) {
      raf = 0;
      if (document.hidden) return;
      if (!onStage || now - onStage.at >= onStage.hold) { if (queue.length) nextSong(now); }
      // At most thirty frames a second, and always the first and the last of a wave's drawing in.
      const last = onStage && !onStage.drawn && now - onStage.at >= onStage.draw;
      if (now - lastFrame >= num("--stage-frame") || !onStage || now - onStage.at < num("--stage-first-frames") || last) { drawStage(now); lastFrame = now; if (last) onStage.drawn = true; }
      schedule(now);
    }
    /// Keeps the stage going only while something moves or waits: a frame while a wave draws in, else one timer.
    function schedule(now) {
      clearTimeout(timer); timer = 0;
      if (document.hidden || !onStage && !queue.length) return;
      if (onStage && now - onStage.at < onStage.draw) { raf = raf || requestAnimationFrame(tick); return; }
      if (queue.length) {
        const wait = onStage ? Math.max(0, onStage.at + onStage.hold - now) : 0;
        timer = setTimeout(() => { raf = raf || requestAnimationFrame(tick); }, wait);
      }
    }
    const kick = () => { if (!raf && !document.hidden) raf = requestAnimationFrame(tick); };

    // ---- what Desk has found so far
    const histCanvas = $("fig-tempos"), wheel = $("fig-keys");
    let latestBin = -1;
    function drawFigures() {
      const f = figures;
      if (!f || document.hidden) return;
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
      const withTempo = f.songs - f.noTempo;
      let top = 0; f.tempos.forEach((c, i) => { if (c > f.tempos[top]) top = i; });
      const text = withTempo > 0 && f.slowest != null
        ? t("figTemposText", { songs: n("songs", withTempo), low: Math.round(f.slowest), high: Math.round(f.fastest),
            mode: Math.round(f.tempoLow + top * f.tempoStep + f.tempoStep / 2) })
        : t("figTemposNone");
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

    // ---- the crate filling up: one line a song, as they joined, top to bottom, then the next column
    function Wall(canvas, nameEl) {
      let layout = null, pick = -1, dirty = false, wtimer = 0, newest = -1;
      function plan(w, h, count, dpr) {
        const waveMin = num("--wall-wave-min") * dpr;
        const colMin = num("--wall-col-min") * dpr;
        const denseMin = num("--wall-dense-col-min") * dpr;
        const gap = Math.round(num("--wall-gap") * dpr);
        const maxCols = Math.max(1, Math.floor((w + gap) / (colMin + gap)));
        for (let cols = 1; cols <= maxCols; cols++) {
          const rows = Math.ceil(count / cols);
          if (h / rows >= waveMin) return { mode: "wave", cols, rows, lh: h / rows, gap, cw: (w - gap * (cols - 1)) / cols };
        }
        // Too many for waves: each song a line of brightness, as thin as one pixel; columns as narrow as --wall-dense-col-min.
        const dgap = Math.max(1, Math.round(num("--wall-dense-gap") * dpr));
        const maxDense = Math.max(1, Math.floor((w + dgap) / (denseMin + dgap)));
        const line = Math.max(1, num("--wall-dense-line") * dpr);
        const cols = Math.min(maxDense, Math.max(1, Math.ceil(count / Math.max(1, Math.floor(h / line)))));
        const rows = Math.ceil(count / cols);
        return { mode: "dense", cols, rows, lh: Math.max(1, h / rows), gap: dgap, cw: (w - dgap * (cols - 1)) / cols, tall: rows > h };
      }
      function draw() {
        wtimer = 0; dirty = false;
        if (document.hidden || !canvas.isConnected || canvas.offsetParent === null) return;
        const { ctx, w, h, dpr } = fit(canvas);
        const count = songs.length;
        ctx.clearRect(0, 0, w, h);
        if (!count) { layout = null; return; }
        const L = plan(w, h, count, dpr);
        if (L.tall) {
          // More songs than pixel rows even at the narrowest columns: the wall grows taller, one pixel a song.
          canvas.style.height = Math.ceil(L.rows / dpr) + "px";
          return soon();
        }
        readCurve();
        layout = Object.assign(L, { w, h, dpr });
        const img = ctx.createImageData(w, h), px = img.data;
        const cWave = rgba(css("--wave")), cQuiet = rgba(css("--wave-quiet")), cNew = rgba(css("--wave-new")),
              cPick = rgba(css("--wave-pick")), cNone = rgba(css("--wave-none"));
        const room = num("--wall-wave-room"), leastHalf = num("--wall-wave-min-half"), quiet = num("--wall-dense-quiet");
        const dim = num("--wall-dense-dim"), bright = num("--wall-dense-bright");
        const put = (x, y, c, a) => { const o = (y * w + x) * 4; px[o] = c[0]; px[o + 1] = c[1]; px[o + 2] = c[2]; px[o + 3] = Math.round(c[3] * a); };
        for (let i = 0; i < count; i++) {
          const s = songs[i], col = Math.floor(i / L.rows), row = i % L.rows;
          const x0 = Math.round(col * (L.cw + L.gap)), x1 = Math.min(w, Math.round(col * (L.cw + L.gap) + L.cw));
          const y0 = Math.floor(row * L.lh), y1 = Math.min(h, Math.max(y0 + 1, Math.floor((row + 1) * L.lh)));
          if (y0 >= h) continue;
          const c = i === pick ? cPick : i === newest ? cNew : cWave;
          const cw = x1 - x0, wave = s.wave;
          if (!wave.length) { const y = Math.floor((y0 + y1) / 2); for (let x = x0; x < x1; x++) put(x, y, cNone, 1); continue; }
          if (L.mode === "wave") {
            const mid = (y0 + y1 - 1) / 2, lineRoom = (y1 - y0) * room;
            for (let x = x0; x < x1; x++) {
              const v = shape(wave[Math.min(WAVE - 1, Math.floor(((x - x0) / cw) * WAVE))]);
              const half = Math.max(leastHalf, v * lineRoom);
              for (let y = Math.max(y0, Math.round(mid - half)); y <= Math.min(y1 - 1, Math.round(mid + half)); y++) put(x, y, c, 1);
            }
          } else {
            for (let x = x0; x < x1; x++) {
              const v = shape(wave[Math.min(WAVE - 1, Math.floor(((x - x0) / cw) * WAVE))]);
              const cc = c === cWave ? (v < quiet ? cQuiet : cWave) : c;
              for (let y = y0; y < y1; y++) put(x, y, cc, dim + bright * v);
            }
          }
        }
        ctx.putImageData(img, 0, 0);
      }
      function soon() {
        if (dirty) return;
        dirty = true;
        if (!wtimer) wtimer = setTimeout(draw, time("--t-wall"));
      }
      function at(ev) {
        if (!layout) return -1;
        const r = canvas.getBoundingClientRect();
        const x = (ev.clientX - r.left) * layout.dpr, y = (ev.clientY - r.top) * layout.dpr;
        const col = Math.floor(x / (layout.cw + layout.gap)), row = Math.floor(y / layout.lh);
        const i = col * layout.rows + row;
        return col >= 0 && col < layout.cols && row >= 0 && row < layout.rows && i < songs.length ? i : -1;
      }
      function choose(i, say) {
        pick = i;
        nameEl.textContent = i >= 0 ? songLine(songs[i]) : "";
        if (say && i >= 0) env.announce(nameEl.textContent);
        draw();
      }
      canvas.addEventListener("mousemove", (e) => { const i = at(e); if (i !== pick) choose(i, false); });
      canvas.addEventListener("mouseleave", () => { if (document.activeElement !== canvas) choose(-1, false); });
      canvas.addEventListener("click", (e) => { canvas.focus(); choose(at(e), false); });
      canvas.addEventListener("blur", () => choose(-1, false));
      canvas.addEventListener("keydown", (e) => {
        if (!songs.length) return;
        const rows = layout ? layout.rows : songs.length;
        const moves = { ArrowDown: 1, ArrowUp: -1, ArrowRight: rows, ArrowLeft: -rows, PageDown: 10, PageUp: -10 };
        let i = pick < 0 ? (e.key === "End" ? songs.length - 1 : 0) : pick;
        if (e.key in moves) { if (pick >= 0) i = Math.max(0, Math.min(songs.length - 1, pick + moves[e.key])); }
        else if (e.key === "Home") i = 0;
        else if (e.key === "End") i = songs.length - 1;
        else if (e.key === "Escape") { choose(-1, false); return; }
        else return;
        e.preventDefault();
        choose(i, true);
      });
      window.addEventListener("resize", soon);
      return {
        added(i) { newest = i; soon(); },
        now: draw, soon,
        label(text) { canvas.setAttribute("aria-label", text); },
        settle() { pulse(canvas, "settle"); },
        reset() { pick = -1; newest = -1; nameEl.textContent = ""; layout = null; canvas.style.height = ""; },
      };
    }
    const runWall = Wall($("run-wall"), $("run-wall-name"));
    const doneWall = Wall($("done-wall"), $("done-wall-name"));

    // ---- the quiet line under the progress, and the moments
    const saying = $("run-saying");
    let sayTimer = 0, lastSaid = "", fresh = [], bags = {}, pendingMoment = null;
    function stepList() {
      const lists = step === "saving" ? ["saying.saving"] : step === "finishing" ? ["saying.finishing"]
        : info.musicCD ? ["saying.disc", "saying.reading"] : ["saying.reading"];
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
      env.announce(text);
      pendingMoment = text;
      clearTimeout(sayTimer);
      nextSaying();
      const motion = { first: stage, songs: $("run-bar"), hour: $("fig-music"), wheel: wheel, disc: $("run-wall") }[note.code];
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

    return {
      /// A run started: everything from the last one goes.
      start(m) {
        songs = []; figures = null; queue = []; onStage = null; skipped = 0; fresh = []; lastNote = null; pendingMoment = null;
        info = { read: m.read, musicCD: !!m.musicCD }; step = "reading"; spoken = { done: -1, at: 0 };
        stage.classList.remove("has-song", "out");
        for (const id of ["stage-title", "stage-artist", "stage-tempo", "stage-key", "stage-bars", "stage-length", "stage-where", "stage-more"]) $(id).textContent = "";
        saying.textContent = ""; lastSaid = ""; $("done-wall-card").dataset.settled = "";
        runWall.reset(); doneWall.reset(); runWall.now();
        $("run-wall-name").textContent = "";
        runWall.label(t("wallEmpty"));
        nextSaying();
      },
      /// The engine's `run.songs`.
      songs(m) {
        for (const s of m.songs || []) {
          songs.push(s);
          queue.push(s);
          if (s.bpm != null && figures) latestBin = Math.max(0, Math.min(figures.tempos.length - 1, Math.floor((s.bpm - figures.tempoLow) / figures.tempoStep)));
        }
        if (m.figures) figures = m.figures;
        for (const note of m.notes || []) {
          if (note.kind === "moment") moment(note);
          else { fresh = fresh.filter((x) => x.code !== note.code); fresh.push(note); if (fresh.length > 6) fresh.shift(); }
        }
        if ((m.songs || []).length) {
          runWall.added(songs.length - 1);
          runWall.label(t("wallLabel", { title: t("wallTitle"), songs: n("songs", songs.length) }));
          kick();
        }
        drawFigures();
      },
      /// A `run.progress`: the step Desk is on, and the plain progress for screen readers.
      progress(run) {
        if (run.stage !== step) { step = run.stage; clearTimeout(sayTimer); nextSaying(); }
        speakProgress(run);
      },
      /// The finished screen: the run's songs as a wall of waves, and the run's last moment.
      finished(report) {
        const card = $("done-wall-card");
        card.hidden = !songs.length;
        if (!songs.length) return;
        clearTimeout(sayTimer); clearTimeout(timer); queue = [];
        $("done-wall-title").textContent = t("wallTitleDone", { read: report.read });
        $("done-moment").textContent = lastNote || "";
        $("done-moment").hidden = !lastNote;
        doneWall.label(t("wallLabel", { title: t("wallTitleDone", { read: report.read }), songs: n("songs", songs.length) }));
        requestAnimationFrame(() => { doneWall.now(); if (!card.dataset.settled) { card.dataset.settled = "1"; doneWall.settle(); } });
      },

    };
  };
})();
