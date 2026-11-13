// Deckie explainer, fourth cut (76 s): a pure function of time. window.seek(t) paints frame t (lib/motion.js).
// Timing is in beats (u) at 120 bpm, so one beat is half a second and one bar is two seconds.
// The plan this file follows is docs/shotlist.md. Every screen is a real capture: the booth frames are a
// simulator recording, the Desk stills come from Desk's own --snapshot mode, the dictionary stills are the
// vocabulary page in a headless browser. Nothing on a screen is drawn by this file.
import * as M from './lib/motion.js';

const { W, H, E, prog, lerp, clamp, springU, springKeys, SPRING, font, layout, glyph, text, fill, rrect } = M;

// The booth app's own colours (deck-app Model.swift, Theme). One accent.
const C = { warm: '#f6eede', bg: '#0f0a17', bg2: '#1c1036', card: '#1d1530', line: '#30254a', tx: '#f2edf9', mut: '#ab9fc2', dim: '#76698f', acc: '#b490ff', ink: '#160f22' };
const DISPLAY = 'Display', UI = 'UI';   // both Inter: ExtraBold for headlines, lighter for the smaller lines
const TRK = -0.025;                     // headline tracking, in ems

// ------------------------------------------------------------------ the script words, written on screen
// Three words are set in Pacifico wherever they stand in headline copy: "you", "your" (either case) and "Deckie".
// Each is drawn from a "time map" (assets/words, made by strokes.py): for every pixel of the word, the moment the
// pen passes it. A word at progress p shows the pixels the pen has passed, so at p = 1 it is the browser's own
// rendering of the font and nothing else. p is a function of the beat, so the film stays a pure function of time.
const SCRIPT_RE = /\b(You|you|Your|your|Deckie)\b(?!['’\w])/g;
const SCRIPT_K = 1.08, SCRIPT_DY = 0.02;     // the script is set 8 percent larger and a touch lower, to sit with Inter
const WORDKEY = { Deckie: 'deckie', you: 'low_you', your: 'low_your', You: 'cap_you', Your: 'cap_your' };
const WORDS = {};
async function loadWords() {
  const meta = await fetch('assets/words/words.json').then((r) => r.json());
  await Promise.all(Object.entries(meta).map(async ([key, m]) => {
    const im = new Image(); im.src = `assets/words/${key}_map.png`; await im.decode();
    const c = document.createElement('canvas'); c.width = m.w; c.height = m.h;
    const x = c.getContext('2d', { willReadFrequently: true }); x.drawImage(im, 0, 0);
    const d = x.getImageData(0, 0, m.w, m.h).data, n = m.w * m.h;
    const t = new Float32Array(n), cov = new Uint8Array(n);
    for (let i = 0; i < n; i++) { t[i] = (d[i * 4] * 256 + d[i * 4 + 1]) / 65535; cov[i] = d[i * 4 + 2]; }
    WORDS[key] = { ...m, t, cov, scratch: c, sctx: x, done: new Map() };
  }));
}
const SOFT = 0.035;                          // how soft the pen's leading edge is, as a share of the whole word
function wordCanvas(key, color, p) {
  const w = WORDS[key];
  if (p >= 1 && w.done.has(color)) return w.done.get(color);
  const [r, g, b] = M.hexRgb(color), n = w.w * w.h;
  const img = w.sctx.createImageData(w.w, w.h), d = img.data, edge = p * (1 + SOFT);
  for (let i = 0; i < n; i++) {
    const c = w.cov[i]; if (!c) continue;
    const a = p >= 1 ? 1 : (edge - w.t[i]) / SOFT;
    if (a <= 0) continue;
    const o = i * 4; d[o] = r; d[o + 1] = g; d[o + 2] = b; d[o + 3] = a >= 1 ? c : c * a;
  }
  if (p >= 1) {
    const c = document.createElement('canvas'); c.width = w.w; c.height = w.h; c.getContext('2d').putImageData(img, 0, 0);
    w.done.set(color, c); return c;
  }
  w.sctx.putImageData(img, 0, 0); return w.scratch;
}
// Draw one script word with its text origin at (x, base); returns how far the line advances.
function scriptWord(ctx, word, x, base, size, color, p) {
  const key = WORDKEY[word], w = WORDS[key];
  if (!w) return 0;
  const s = size / w.S;
  if (p > 0) { ctx.imageSmoothingQuality = 'high'; ctx.drawImage(wordCanvas(key, color, Math.min(p, 1)), x - w.ox * s, base - w.base * s, w.w * s, w.h * s); }
  return w.adv * s;
}
// One headline line. Inter throughout, except the three script words, which are found by themselves. `draw` says when
// the line's script words are written: { u, at (beat the first one starts), dur (beats each), gap (beats between) }.
// "you" and "your" are in the accent colour; "Deckie" takes the colour of its line.
function rich(ctx, str, x, y, size, color, draw = null) {
  let cx = x, last = 0, n = 0, m;
  const f = font(size, 800, DISPLAY), tr = TRK * size;
  const plain = (t) => { if (!t) return; text(ctx, t, cx, y, f, color, 'left', tr); ctx.font = f; ctx.letterSpacing = `${tr}px`; cx += ctx.measureText(t).width; ctx.letterSpacing = '0px'; };
  SCRIPT_RE.lastIndex = 0;
  while ((m = SCRIPT_RE.exec(str))) {
    plain(str.slice(last, m.index));
    const p = draw ? clamp((draw.u - (draw.at + n * ((draw.dur || 0.7) + (draw.gap || 0.2)))) / (draw.dur || 0.7)) : 1;
    cx += scriptWord(ctx, m[0], cx, y + size * SCRIPT_DY, size * SCRIPT_K, m[0] === 'Deckie' ? color : C.acc, p) + size * 0.02;
    last = m.index + m[0].length; n++;
  }
  plain(str.slice(last));
}

// ------------------------------------------------------------------ booth frames (image sequence, loaded on demand)
const BOOTH_N = 1976, BW = 1600, BH = 1102;
// film seconds -> frame of the 30 fps simulator recording. Real time unless noted.
function boothF(t) {
  let f;
  if (t < 12) f = 500 + (t - 4) * 30;                  // what it is: a named song, its position line moving
  else if (t < 48) f = 249 + (t - 31) * 30;            // Listening, then the song is named at t = 31 (frame 249); picks, Simple
  else if (t < 52) f = 1048 + (t - 49) * 30;           // Full; Shuffle moves at t = 49 (frame 1048)
  else if (t < 55) f = 1287 + (t - 53) * 30;           // a pick is pinned at t = 53 (frame 1287)
  else if (t < 56.6) f = 1512 + (t - 55.5) * 30;       // the list scrolls to More at t = 55.5 (frame 1512)
  else if (t < 60) f = 1678 + (t - 57) * 30;           // the search fills at t = 57 (frame 1678)
  else f = 600 + (t - 68) * 30;                        // end card
  return clamp(Math.round(f), 100, BOOTH_N - 1);
}
const cache = new Map();
function loadFrame(i) {
  if (cache.has(i)) { const v = cache.get(i); cache.delete(i); cache.set(i, v); return v.p; }
  const im = new Image();
  const rec = { im, ok: false, p: null };
  rec.p = new Promise((res) => { im.onload = () => { rec.ok = true; res(); }; im.onerror = () => res(); });
  im.src = `assets/booth/f${String(i).padStart(4, '0')}.jpg`;
  cache.set(i, rec);
  while (cache.size > 48) cache.delete(cache.keys().next().value);
  return rec.p;
}
function boothImg(t) {
  const r = cache.get(boothF(t));
  if (r && r.ok) return r.im;
  loadFrame(boothF(t));
  let best = null;                                      // preview only: the newest loaded frame
  for (const v of cache.values()) if (v.ok) best = v.im;
  return best;
}
// The harness assigns window.seek; wrap it so every frame's booth images are decoded before it paints.
let rawSeek = null;
Object.defineProperty(window, 'seek', {
  configurable: true,
  get() { return rawSeek && (async (t) => { await Promise.all([loadFrame(boothF(t)), loadFrame(boothF(t + 1 / 60))]); rawSeek(t); }); },
  set(f) { rawSeek = f; },
});

// ------------------------------------------------------------------ helpers
function backdrop(ctx) {
  const g = ctx.createLinearGradient(W, 0, 0, H);
  g.addColorStop(0, C.bg2); g.addColorStop(0.75, C.bg);
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
}
const wrapCache = new Map();
function wrap(ctx, str, f, maxW) {
  const key = `${f}|${maxW}|${str}`;
  if (wrapCache.has(key)) return wrapCache.get(key);
  ctx.font = f;
  const lines = []; let cur = '';
  for (const w of str.split(' ')) {
    const tryS = cur ? `${cur} ${w}` : w;
    if (ctx.measureText(tryS).width > maxW && cur) { lines.push(cur); cur = w; } else cur = tryS;
  }
  if (cur) lines.push(cur);
  wrapCache.set(key, lines);
  return lines;
}
// A real capture in a rounded card. cam = [cx, cy, z] in source pixels: the crop keeps the card's aspect.
// srcH limits the usable height of the source (the dictionary stills are cut above the second term).
function card(ctx, img, box, cam, { radius = 22, srcH = null, alpha = 1 } = {}) {
  const [x, y, w, h] = box;
  if (!img || w < 2 || h < 2) return null;
  const iw = img.width, ih = srcH || img.height;
  const [cx0, cy0, z] = cam || [iw / 2, ih / 2, 1];
  let sw = iw / z, sh = sw * (h / w);
  if (sh > ih) { sh = ih; sw = sh * (w / h); }
  const sx = clamp(cx0 - sw / 2, 0, iw - sw), sy = clamp(cy0 - sh / 2, 0, ih - sh);
  ctx.save();
  ctx.globalAlpha *= alpha;
  ctx.shadowColor = 'rgba(0,0,0,0.55)'; ctx.shadowBlur = 70; ctx.shadowOffsetY = 26;
  rrect(ctx, x, y, w, h, radius); ctx.fillStyle = C.ink; ctx.fill();
  ctx.shadowColor = 'transparent';
  rrect(ctx, x, y, w, h, radius); ctx.clip();
  ctx.drawImage(img, sx, sy, sw, sh, x, y, w, h);
  ctx.restore();
  ctx.save(); ctx.globalAlpha *= alpha;
  rrect(ctx, x, y, w, h, radius); ctx.strokeStyle = C.line; ctx.lineWidth = 2; ctx.stroke();
  ctx.restore();
  // source pixel -> screen, for callouts
  return (px, py) => [x + ((px - sx) / sw) * w, y + ((py - sy) / sh) * h, w / sw];
}
// An accent outline around a source-pixel rect, springing on at u0 and off at u1.
function callout(ctx, map, u, u0, u1, [px, py, pw, ph]) {
  if (!map || u < u0 || u > u1 + 0.5) return;
  const k = springU(u, u0, SPRING.snappy) * (1 - prog(u, u1, u1 + 0.5));
  if (k <= 0.01) return;
  const [x, y, s] = map(px, py);
  const w = pw * s, h = ph * s, grow = (1 - Math.min(k, 1)) * 26;
  ctx.save(); ctx.globalAlpha = clamp(k);
  rrect(ctx, x - 10 - grow, y - 8 - grow, w + 20 + 2 * grow, h + 16 + 2 * grow, 16);
  ctx.strokeStyle = C.acc; ctx.lineWidth = 5; ctx.stroke();
  ctx.restore();
}

// ------------------------------------------------------------------ captions (the left column carries the story with the sound off)
const COL_X = 96, COL_W = 610;
// Three named sections. Each header is drawn at one fixed place and size for as long as its section lasts.
const HEAD_Y = 322, HEAD_SIZE = 44;          // header baseline and type size, the same in every shot
const TITLE_Y = 428, TITLE_LH = 82;          // first headline baseline and line height, the same in every shot
const SECTIONS = [
  [32, 56, 'Deckie Desk, on your Mac'],
  [56, 118, 'Deckie Booth, on your iPad'],
  [118, 128, 'The dictionary'],
];
const CAPS = [
  // [in, out, title ('|' = line break), smaller line, beats each script word takes to write]
  [8, 13, 'Deckie knows|your crate.', 'It listens from an iPad beside the decks.', 1.1],
  [13, 18, 'It names the song,|reads the pitch|fader, shows what|could come next.', ''],
  [32, 42, 'Desk reads your|crate and writes|a crate file.', 'Edits, bootlegs and burned CDs included. No audio goes in the file.'],
  [42, 50, 'Sort your crate|into discs and|folders.', 'In the order your player shows them.'],
  [50, 56, 'Send the crate|file to your iPad.', 'AirDrop, iCloud Drive or Files. No server.'],
  [56, 62, 'Put the iPad by|the decks. Play.', 'A song shows up after a few seconds of music.'],
  [62, 68, 'It names the song|from your crate.', 'Disc, folder and track, as on your player.', 0.9],
  [68, 76, 'It reads the|pitch fader.', 'This deck runs 3 percent fast, so the tempo reads 128 BPM.'],
  [76, 82, 'What could come|next, best first.', ''],
  [82, 90, 'Where to set the|pitch. How you|could bring it in.', 'Every pick says both, on one line.'],
  [90, 96, 'The wave shows|the transition.', 'The end of this song over the start of that one.'],
  [96, 104, 'Turn up Shuffle|for less obvious|picks.', 'At zero they stay in score order.'],
  [104, 110, 'Pin the one|you want.', '', 0.9],
  [110, 118, 'Or search the rest|of your crate.', 'More lists every other song, by score.'],
  [118, 122, 'Every word, said|three ways.', ''],
  [122, 124, 'Plain words.', ''],
  [124, 126, 'The DJ’s word.', ''],
  [126, 128, 'What Deckie|does with it.', ''],
];
function headers(ctx, u) {
  for (const [s0, s1, label] of SECTIONS) {
    if (u < s0 - 0.1 || u > s1) continue;
    const k = clamp(springU(u, s0, SPRING.snappy)), out = E.inCubic(prog(u, s1 - 0.7, s1));
    ctx.save(); ctx.globalAlpha = k * (1 - out);
    // a subhead, not headline copy: Inter only, and it fades in where it stands, so it never moves
    text(ctx, label, COL_X, HEAD_Y, font(HEAD_SIZE, 700, DISPLAY), C.mut, 'left', -0.015 * HEAD_SIZE);
    ctx.restore();
  }
}
function captions(ctx, u) {
  for (let i = 0; i < CAPS.length; i++) {
    const [u0, u1, title, sub, wdur] = CAPS[i];
    if (u < u0 - 0.1 || u > u1) continue;
    const out = E.inCubic(prog(u, u1 - (u1 - u0 <= 2 ? 0.35 : 0.7), u1));
    const fS = font(36, 500, UI);
    const tl = title.split('|'), sl = sub ? wrap(ctx, sub, fS, COL_W - 20) : [];
    tl.forEach((ln, j) => {
      const k = springU(u, u0 + j * 0.14, SPRING.snappy);
      if (k <= 0) return;
      ctx.save(); ctx.globalAlpha = clamp(k) * (1 - out);
      // a line's script words wait for the script words on the lines above it, so the pen is in one place at a time
      const before = tl.slice(0, j).join(' ').match(SCRIPT_RE)?.length || 0, wd = wdur || 0.7;
      rich(ctx, ln, COL_X, TITLE_Y + j * TITLE_LH + (1 - k) * 46 - out * 30, 70, C.warm, { u, at: u0 + 0.2 + before * (wd + 0.2), dur: wd });
      ctx.restore();
    });
    const y = TITLE_Y + tl.length * TITLE_LH;
    sl.forEach((ln, j) => {
      const k = springU(u, u0 + 0.5 + j * 0.14, SPRING.gentle);
      if (k <= 0) return;
      ctx.save(); ctx.globalAlpha = clamp(k) * (1 - out);
      text(ctx, ln, COL_X, y + j * 50 + (1 - k) * 24 - out * 30, fS, C.mut);
      ctx.restore();
    });
  }
}

// ------------------------------------------------------------------ card boxes
const MAIN = [760, 174, 1064, 733];            // the booth card (1600 x 1102 source)
const DESK = [760, 208, 1064, 665];            // the Desk card (1280 x 800 window)
const VOC = [760, 290, 1064, 499];             // the dictionary card (2560 x 1200 crop)
const SUITE = { desk: [96, 330, 540, 338], booth: [690, 314, 540, 372], voc: [1284, 372, 540, 253] };
const SEND = { desk: [760, 140, 672, 420], booth: [1290, 560, 534, 368] };

// ------------------------------------------------------------------ S1 hook (u 0..12): pure type and two turning platters
function platter(ctx, cx, cy, r, ang, label) {
  ctx.save(); ctx.translate(cx, cy);
  ctx.beginPath(); ctx.arc(0, 0, r, 0, M.TAU); ctx.fillStyle = '#120c1d'; ctx.fill();
  ctx.strokeStyle = C.line; ctx.lineWidth = 2;
  for (let i = 1; i <= 7; i++) { ctx.beginPath(); ctx.arc(0, 0, r * (0.42 + i * 0.075), 0, M.TAU); ctx.stroke(); }
  ctx.rotate(ang);
  ctx.beginPath(); ctx.arc(0, 0, r * 0.34, 0, M.TAU); ctx.fillStyle = label; ctx.fill();
  ctx.fillStyle = C.ink; ctx.fillRect(r * 0.08, -5, r * 0.22, 10);          // the label's mark, so the turn reads
  ctx.beginPath(); ctx.arc(0, 0, 9, 0, M.TAU); ctx.fillStyle = C.bg; ctx.fill();
  ctx.restore();
}
const HOOK = [[0, 'CDJs.'], [1.5, 'Turntables.'], [3, 'The house decks.']];
function sceneHook(ctx, u, t, shiftX) {
  ctx.save(); ctx.translate(shiftX, 0);
  const kp = springU(u, -0.6, SPRING.gentle);
  platter(ctx, 1500, 330 + (1 - kp) * 80, 300, t * M.TAU * 0.55, C.acc);
  platter(ctx, 1260, 870 + (1 - kp) * 80, 230, t * M.TAU * 0.55 + 1, '#5a6cc0');
  const size = 150, f = font(size, 800, DISPLAY), track = TRK * size;
  HOOK.forEach(([u0, w], i) => {
    const L = layout(ctx, w, f, track);
    L.glyphs.forEach((g, j) => {
      const k = springU(u, u0 - (i === 0 ? 0.3 : 0) + j * 0.025, SPRING.bouncy);
      if (k <= 0) return;
      const dim = u > 5 ? lerp(1, 0.38, prog(u, 5, 6)) : 1;
      ctx.save(); ctx.globalAlpha = dim;
      glyph(ctx, g.ch, COL_X + g.cx, 300 + i * 158 + (1 - k) * 120, f, C.warm, k, k);
      ctx.restore();
    });
  });
  const f2 = font(92, 800, DISPLAY);
  ['None of them know', 'your music.'].forEach((ln, j) => {
    const k = springU(u, 5 + j * 0.2, SPRING.snappy);
    if (k <= 0) return;
    ctx.save(); ctx.globalAlpha = clamp(k);
    rich(ctx, ln, COL_X, 800 + j * 104 + (1 - k) * 60, 92, C.acc, { u, at: 5.45, dur: 1.1 });
    ctx.restore();
  });
  ctx.restore();
}

// ------------------------------------------------------------------ S3 two lines (u 18..24), then the name and the tagline (u 24..32)
const TWO = [[18, 'Know the beat.'], [20, 'Nail the mix.']];
function sceneTwo(ctx, u) {
  const out = E.inCubic(prog(u, 23.5, 24.2));
  TWO.forEach(([u0, ln], i) => {
    const k = springU(u, u0, SPRING.snappy);
    if (k <= 0) return;
    ctx.save(); ctx.globalAlpha = clamp(k) * (1 - out);
    rich(ctx, ln, COL_X, 470 + i * 200 + (1 - k) * 80 - out * 80, 170, C.warm);
    ctx.restore();
  });
}
// The tagline, under the name wherever the name stands alone: sentence case, "your" written in.
function tagline(ctx, u, u0, y, size, alpha = 1) {
  const k = springU(u, u0, SPRING.snappy);
  if (k <= 0) return;
  ctx.save(); ctx.globalAlpha = clamp(k) * alpha;
  rich(ctx, 'Know your crate.', COL_X + 6, y + (1 - k) * 30, size, C.warm, { u, at: u0 + 0.2, dur: 1.0 });
  ctx.restore();
}
function wordmark(ctx, u, u0, base, size, alpha = 1, dur = 2.6) {
  ctx.save(); ctx.globalAlpha = alpha;
  scriptWord(ctx, 'Deckie', COL_X, base, size, C.warm, clamp((u - u0) / dur));
  ctx.restore();
}
function sceneName(ctx, u) {
  const out = E.inCubic(prog(u, 31.2, 32));
  ctx.save(); ctx.translate(0, -out * 120);
  wordmark(ctx, u, 24, 520, 330, 1 - out);
  tagline(ctx, u, 26.4, 690, 96, 1 - out);
  const ka = springU(u, 28, SPRING.snappy);
  if (ka > 0) { ctx.save(); ctx.globalAlpha = clamp(ka) * (1 - out); text(ctx, 'deckie.io', COL_X + 8, 850 + (1 - ka) * 30, font(60, 700, UI), C.mut, 'left', -1); ctx.restore(); }
  ctx.restore();
}

// ------------------------------------------------------------------ S4 the crate file, as a stencilled label (u 33..43); it becomes the chip that travels (u 42..48)
const HASDESK = () => !!DESK_READY;
const LABEL_ITEMS = [[35, 'Tempo'], [35.5, 'Key'], [36, 'Bars'], [36.5, 'Style'], [37, 'Fingerprints']];
function crateLabel(ctx, u) {
  if (u < 33.4 || u > 43.4) return;
  const B = HASDESK() ? [1150, 430, 640, 356] : [800, 260, 860, 478];
  const k = springU(u, 33.6, SPRING.snappy), out = E.inCubic(prog(u, 41.5, 42.3));
  if (k <= 0) return;
  const [x, y, w, h] = B, sc = w / 760;
  ctx.save();
  ctx.translate(x + w / 2, y + h / 2); ctx.scale(lerp(0.8, 1, Math.min(k, 1.05)) * (1 - out * 0.55), lerp(0.8, 1, Math.min(k, 1.05)) * (1 - out * 0.55)); ctx.translate(-w / 2, -h / 2);
  ctx.globalAlpha = clamp(k) * (1 - out);
  ctx.shadowColor = 'rgba(0,0,0,0.5)'; ctx.shadowBlur = 60; ctx.shadowOffsetY = 20;
  ctx.fillStyle = C.card; ctx.fillRect(0, 0, w, h);
  ctx.shadowColor = 'transparent';
  ctx.strokeStyle = C.warm; ctx.lineWidth = 4; ctx.strokeRect(14, 14, w - 28, h - 28);
  text(ctx, 'Friday night', 44 * sc, 112 * sc, font(80 * sc, 800, DISPLAY), C.warm, 'left', TRK * 80 * sc);
  text(ctx, 'Crate file', 46 * sc, 160 * sc, font(34 * sc, 600, UI), C.mut);
  ctx.fillStyle = C.line; ctx.fillRect(44 * sc, 190 * sc, w - 88 * sc, 3);
  const pos = [[44, 280], [262, 280], [400, 280], [44, 362], [226, 362]];
  LABEL_ITEMS.forEach(([u0, word], i) => {
    const ki = springU(u, u0, SPRING.snappy);
    if (ki <= 0) return;
    ctx.save(); ctx.globalAlpha *= clamp(ki);
    text(ctx, word, pos[i][0] * sc, (pos[i][1] + (1 - ki) * 24) * sc, font(54 * sc, 800, DISPLAY), C.tx, 'left', TRK * 54 * sc);
    ctx.restore();
  });
  ctx.restore();
}
function fileChip(ctx, u) {
  const k = prog(u, 50.3, 50.9), out = prog(u, 54.2, 55);
  if (k <= 0 || out >= 1) return;
  const p = E.inOutCubic(prog(u, 51.4, 54));
  const from = HASDESK() ? [1100, 360] : [1200, 510];
  const cx = lerp(from[0], 1557, p), y = lerp(from[1], 744, p) - Math.sin(p * Math.PI) * 110;
  const w = 372, h = 96;
  ctx.save(); ctx.globalAlpha = clamp(k) * (1 - out);
  ctx.translate(cx, y); ctx.rotate(Math.sin(p * Math.PI) * -0.07);
  ctx.shadowColor = 'rgba(0,0,0,0.5)'; ctx.shadowBlur = 40; ctx.shadowOffsetY = 14;
  ctx.fillStyle = C.card; ctx.fillRect(-w / 2, -h / 2, w, h);
  ctx.shadowColor = 'transparent';
  ctx.strokeStyle = C.warm; ctx.lineWidth = 3; ctx.strokeRect(-w / 2 + 7, -h / 2 + 7, w - 14, h - 14);
  text(ctx, 'Friday night', -w / 2 + 26, 4, font(38, 800, DISPLAY), C.warm, 'left', -1);
  text(ctx, 'Crate file', -w / 2 + 27, 32, font(20, 600, UI), C.mut);
  ctx.restore();
}

// ------------------------------------------------------------------ S11 the promise (u 96..104)
const YOURS = [[128, 'Your music'], [130, 'Your mix']];
const PROMISE = ['It never leaves your devices.', 'No account. No upload. Works with no signal.'];
function scenePromise(ctx, u) {
  const out = prog(u, 135.4, 136);
  YOURS.forEach(([u0, ln], i) => {
    const k = springU(u, u0, SPRING.snappy);
    if (k <= 0) return;
    ctx.save(); ctx.globalAlpha = clamp(k) * (1 - out);
    rich(ctx, ln, COL_X, 390 + i * 256 + (1 - k) * 70 - out * 60, 170, C.warm, { u, at: u0 + 0.15, dur: 1.1 });
    ctx.restore();
  });
  PROMISE.forEach((ln, i) => {
    const k = springU(u, 132 + i * 0.5, SPRING.gentle);
    if (k <= 0) return;
    ctx.save(); ctx.globalAlpha = clamp(k) * (1 - out);
    text(ctx, ln, COL_X + 6, 800 + i * 66 + (1 - k) * 24 - out * 60, font(46, 500, UI), C.mut);
    ctx.restore();
  });
}

// ------------------------------------------------------------------ S12 end card (u 104..120)
function sceneEnd(ctx, u) {
  wordmark(ctx, u, 136, 430, 300, 1, 2.2);
  tagline(ctx, u, 138.4, 580, 84);
  const k2 = springU(u, 141, SPRING.snappy);
  if (k2 > 0) { ctx.save(); ctx.globalAlpha = clamp(k2); text(ctx, 'Coming soon.', COL_X + 6, 740 + (1 - k2) * 30, font(84, 800, DISPLAY), C.mut, 'left', TRK * 84); ctx.restore(); }
  const k3 = springU(u, 148, SPRING.bouncy);
  if (k3 > 0) {
    ctx.save(); ctx.translate(COL_X + 290, 900); ctx.scale(lerp(0.7, 1, k3), lerp(0.7, 1, k3)); ctx.globalAlpha = clamp(k3);
    ctx.fillStyle = C.acc; ctx.fillRect(-290, -56, 580, 112);
    text(ctx, 'Help us beta test', 0, 19, font(54, 800, DISPLAY), C.ink, 'center', -1);
    ctx.restore();
    ctx.save(); ctx.globalAlpha = clamp(k3); text(ctx, 'deckie.io', COL_X + 620, 920, font(60, 700, UI), C.warm, 'left', -1); ctx.restore();
  }
}

// ------------------------------------------------------------------ the film
const mixBox = (a, b, k) => a.map((v, i) => lerp(v, b[i], k));
const OFF_R = (b) => [W + 80, b[1], b[2], b[3]];
const OFF_L = (b) => [-b[2] - 80, b[1], b[2], b[3]];

// Booth card: where it sits over the film (spring between boxes), and its camera over the 1600 x 1102 frame.
function boothBox(u) {
  if (u >= 135.5) return springKeys(u, [[136, [1180, 1200, 644, 444]], [136.6, [1180, 318, 644, 444]]], { stiffness: 150, damping: 22 });
  if (u < 30) return springKeys(u, [[7.6, OFF_R(MAIN)], [7.7, MAIN], [17.6, OFF_R(MAIN)]], { stiffness: 150, damping: 22 });
  return springKeys(u, [[49.6, OFF_R(SEND.booth)], [50, SEND.booth], [55.4, MAIN], [117.5, [MAIN[0], H + 120, MAIN[2], MAIN[3]]]], { stiffness: 150, damping: 22 });
}
const BFULL = [800, 551, 1];
function boothCam(u) {
  return springKeys(u, [
    [0, BFULL],
    [68, [400, 400, 1.75]],        // the playing panel: status line, song, tempo
    [76, [1210, 400, 1.7]],        // the picks
    [82, [1250, 330, 1.9]],        // one pick: tempo, pitch, the move; then its wave
    [96, [1200, 300, 1.55]],       // the Shuffle dial and the list under it
    [110, [1180, 400, 1.35]],      // More and its search
    [117, BFULL],
  ], { stiffness: 90, damping: 20 });
}
function deskBox(u) {
  return springKeys(u, [[31.6, OFF_R(SEND.desk)], [32, SEND.desk], [41.8, DESK], [49.8, SEND.desk], [55, OFF_L(SEND.desk)]], { stiffness: 150, damping: 22 });
}
function vocBox(u) {
  return springKeys(u, [[117.4, [VOC[0], -VOC[3] - 120, VOC[2], VOC[3]]], [117.6, VOC], [127.6, [VOC[0], H + 100, VOC[2], VOC[3]]]], { stiffness: 150, damping: 22 });
}
const VOC_H = 1200;
function vocCam(u) {
  return springKeys(u, [[0, [883, 650, 1.45]], [122, [890, 880, 2.6]], [124, [1528, 900, 2.6]], [126, [2068, 880, 2.6]]], { stiffness: 110, damping: 21 });
}
// Desk stills (from Desk's --snapshot): the table for "reads your crate", the table with the Discs panel for "discs and folders".
let DESKCAM = [[0, [1280, 800, 1]]], DESK_READY = false;
function deskImg(u, IMG) { return u >= 42 && u < 50 && IMG.desk_discs ? IMG.desk_discs : IMG.desk_open; }
function deskCam(u) { return u >= 42 && u < 50 ? springKeys(u, [[42, [900, 562, 1]], [44.5, [1150, 540, 1.3]]], { stiffness: 90, damping: 20 }) : springKeys(u, DESKCAM, { stiffness: 90, damping: 20 }); }

// Every accent, with its sound. Kept sparse: the bed carries the pulse, the accents mark the steps.
const HITS = [
  [0, 'CDJs', 'thud', { gain: 0.3 }], [1.5, 'Turntables', 'pop', { pitch: 'A4' }], [3, 'The house decks', 'pop', { pitch: 'C5' }],
  [5, 'None of them know your music', 'thud'],
  [7.7, 'the booth whips in', 'whoosh', { len: 0.5 }], [8, 'Deckie knows your crate', 'tick'], [13, 'what it does', 'tick'],
  [18, 'Know the beat', 'thud', { gain: 0.3 }], [20, 'Nail the mix', 'bell', { pitch: 'A5' }],
  [24, 'Deckie', 'impact', { gain: 0.45 }], [26.4, 'Know your crate', 'tick'],
  [32, 'step 1', 'impact', { gain: 0.5 }], [35, 'tempo', 'tick'], [35.5, 'key', 'tick'], [36, 'bars', 'tick'], [36.5, 'style', 'tick'], [37, 'fingerprints', 'tick'],
  [42, 'discs and folders', 'click'],
  [50, 'step 2', 'bell', { pitch: 'A5' }], [51.4, 'crate file leaves', 'whoosh', { len: 0.7, from: 500, to: 2600 }], [54, 'crate file lands', 'pop', { pitch: 'E5' }],
  [56, 'step 3', 'bell', { pitch: 'C6' }], [62, 'the song is named', 'bell', { pitch: 'E6' }],
  [68, 'pitch fader', 'tick'], [76, 'picks', 'tick'], [82, 'one pick', 'tick'], [90, 'the wave', 'tick'],
  [98, 'Shuffle moves', 'whoosh', { len: 0.4, from: 800, to: 2200 }], [106, 'pin', 'pop', { pitch: 'E5' }], [110, 'More', 'tick'], [114, 'search', 'type', { len: 0.5 }],
  [117.6, 'the dictionary drops in', 'whoosh', { len: 0.5 }], [122, 'plain', 'tick'], [124, 'DJ', 'tick'], [126, 'Deckie', 'tick'],
  [128, 'Your music', 'thud', { gain: 0.3 }], [130, 'Your mix', 'bell', { pitch: 'A5' }], [132, 'the promise', 'tick'],
  [136, 'Deckie', 'impact', { gain: 0.6 }], [138.4, 'Know your crate', 'tick'], [141, 'Coming soon', 'pop', { pitch: 'A4' }], [148, 'Help us beta test', 'bell', { pitch: 'E6' }],
];

const images = { v_type_08: 'assets/vocab/v_type_08.png' };
const deskCfg = await fetch('assets/desk/desk.json').then((r) => (r.ok ? r.json() : null)).catch(() => null);
if (deskCfg) { Object.assign(images, deskCfg.images); DESKCAM = deskCfg.cam; DESK_READY = true; }
await loadWords();

M.film({
  fonts: [font(100, 800, DISPLAY), font(40, 500, UI)],
  images, hits: HITS, samples: 16,
  draw(ctx, u, t, IMG) {
    backdrop(ctx);
    // S1 hook, whipping out left as the booth card whips in
    if (u < 9.5) sceneHook(ctx, u, t, -springU(u, 7.6, { stiffness: 150, damping: 22 }) * (W + 200));
    // cards
    if (DESK_READY && u >= 31.5 && u < 57) card(ctx, deskImg(u, IMG), deskBox(u), deskCam(u));
    if (u >= 117 && u < 130) card(ctx, IMG.v_type_08, vocBox(u), vocCam(u), { srcH: VOC_H });
    if ((u >= 7 && u < 20) || (u >= 49.5 && u < 119) || u >= 135.5) {
      const map = card(ctx, boothImg(t), boothBox(u), u >= 135.5 || u < 30 ? BFULL : boothCam(u));
      callout(ctx, map, u, 69, 75, [356, 122, 250, 38]);         // "sure · deck +3.0%"
      callout(ctx, map, u, 70.5, 75, [58, 506, 150, 50]);        // 128 BPM
      callout(ctx, map, u, 82.6, 89.4, [806, 346, 300, 82]);     // tempo, pitch and the move
      callout(ctx, map, u, 90.4, 95.4, [1190, 236, 410, 170]);   // the wave
      callout(ctx, map, u, 98, 102.5, [940, 116, 280, 46]);      // Shuffle
      callout(ctx, map, u, 106, 109.4, [786, 216, 814, 126]);    // NEXT
      callout(ctx, map, u, 114.2, 117, [790, 262, 690, 56]);     // the search field
    }
    crateLabel(ctx, u);
    fileChip(ctx, u);
    headers(ctx, u);
    captions(ctx, u);
    if (u >= 18 && u < 24.4) sceneTwo(ctx, u);
    if (u >= 24 && u < 32.2) sceneName(ctx, u);
    if (u >= 128 && u < 136.2) scenePromise(ctx, u);
    if (u >= 136) sceneEnd(ctx, u);
  },
});
