// Injected before Desk's pages load (live.mjs): a stepped clock, so every frame of the capture is taken at an exact
// moment of the page's own time (performance.now, Date.now, timers, animation frames, CSS animations and transitions
// all run on it), and a stand-in for the window's shell that passes the page's messages to the real engine through
// the capture program and hands the engine's lines back. The pages themselves are not changed.
(function () {
  "use strict";
  let now = 0;
  const base = 1794600000000;
  performance.now = () => now;
  Date.now = () => base + now;
  let seq = 1;
  const timers = new Map();
  window.setTimeout = (fn, ms, ...args) => { const id = seq++; timers.set(id, { due: now + Math.max(0, Number(ms) || 0), fn, args, order: id }); return id; };
  window.clearTimeout = (id) => { timers.delete(id); };
  window.setInterval = (fn, ms, ...args) => { const id = seq++; const every = Math.max(1, Number(ms) || 0); timers.set(id, { due: now + every, fn, args, every, order: id }); return id; };
  window.clearInterval = window.clearTimeout;
  let frames = new Map();
  window.requestAnimationFrame = (fn) => { const id = seq++; frames.set(id, fn); return id; };
  window.cancelAnimationFrame = (id) => { frames.delete(id); };

  const seen = new WeakMap();
  function holdAnimations(at) {
    for (const a of document.getAnimations()) {
      if (!seen.has(a)) seen.set(a, at);
      try { a.pause(); a.currentTime = Math.max(0, now - seen.get(a)); } catch (e) {}
    }
  }
  /// Moves the clock on by ms: timers fall due in order, then one animation frame at the new time.
  window.__advance = function (ms) {
    const start = now, target = now + ms;
    for (let guard = 0; guard < 10000; guard++) {
      let next = null;
      for (const [id, t] of timers) if (t.due <= target && (!next || t.due < next[1].due || (t.due === next[1].due && t.order < next[1].order))) next = [id, t];
      if (!next) break;
      const [id, t] = next;
      now = Math.max(now, t.due);
      if (t.every) t.due += t.every; else timers.delete(id);
      try { t.fn(...t.args); } catch (e) { console.error(e); }
    }
    now = target;
    const run = frames; frames = new Map();
    for (const fn of run.values()) { try { fn(now); } catch (e) { console.error(e); } }
    holdAnimations(start + ms / 2);
    return now;
  };

  // The shell: every message goes out through the capture program's binding; lines come back through __feed.
  const shell = { onmessage: null, engine: "live" };
  shell.send = (text) => { try { window.__deskSend(String(text)); } catch (e) { console.error(e); } };
  window.deckieShell = shell;
  window.__feed = (lines) => { for (const l of lines) { try { shell.onmessage && shell.onmessage(l); } catch (e) { console.error(e); } } };
})();
