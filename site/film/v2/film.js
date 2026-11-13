// Deckie explainer, final cut (60 s): a pure function of time. window.seek(t) paints frame t (lib/motion.js).
// Timing is in beats (u) at 120 bpm, so one beat is half a second and one bar is two seconds.
// The plan this file follows is docs/shotlist.md. Every screen is a real capture: the booth frames are a
// simulator recording, the Desk stills come from Desk's own --snapshot mode, the dictionary stills are the
// vocabulary page in a headless browser. Nothing on a screen is drawn by this file.
import * as M from './lib/motion.js';

const { W, H, E, prog, lerp, clamp, springU, springKeys, SPRING, font, layout, glyph, text, fill, rrect } = M;

// The booth app's own colours (deck-app Model.swift, Theme). One accent.
const C = { warm: '#f6eede', bg: '#0f0a17', bg2: '#1c1036', card: '#1d1530', line: '#30254a', tx: '#f2edf9', mut: '#ab9fc2', dim: '#76698f', acc: '#b490ff', ink: '#160f22' };
const DISPLAY = 'Display', UI = 'UI', SCRIPT = 'Script';   // Inter for headlines and text; Pacifico for the name and for the words about the DJ
const TRK = -0.025;                                        // headline tracking, in ems
// One line that may mix the two faces: '{...}' marks words about the DJ, set in the script, in the accent colour.
// The script is drawn 8 percent larger and a touch lower so its x-height and baseline sit with the headline face.
const SCRIPT_K = 1.08, SCRIPT_DY = 0.02;
function segs(str) { return str.split(/(\{[^}]*\})/).filter(Boolean).map((t) => (t[0] === '{' ? { t: t.slice(1, -1), sc: true } : { t, sc: false })); }
function rich(ctx, str, x, y, size, color, scriptColor = '#b490ff') {
  let cx = x;
  for (const g of segs(str)) {
    const f = g.sc ? font(size * SCRIPT_K, 400, SCRIPT) : font(size, 800, DISPLAY), tr = g.sc ? 0 : TRK * size;
    text(ctx, g.t, cx, y + (g.sc ? size * SCRIPT_DY : 0), f, g.sc ? scriptColor : color, 'left', tr);
    ctx.font = f; ctx.letterSpacing = `${tr}px`; cx += ctx.measureText(g.t).width + (g.sc ? size * 0.04 : 0); ctx.letterSpacing = '0px';
  }
}

// ------------------------------------------------------------------ booth frames (image sequence, loaded on demand)
const BOOTH_N = 1976, BW = 1600, BH = 1102;
// film seconds -> frame of the 30 fps simulator recording. Real time unless noted.
function boothF(t) {
  let f;
  if (t < 12) f = 500 + (t - 4) * 30;                  // the answer: a named song, its position line moving
  else if (t < 34.2) f = 249 + (t - 27) * 30;          // Listening, then the song is named at t = 27 (frame 249)
  else if (t < 40) f = 459 + (t - 34.2) * 30;          // the picks, Simple
  else if (t < 42.4) f = 1048 + (t - 41) * 30;         // Full; Shuffle moves at t = 41 (frame 1048)
  else if (t < 46) f = 1287 + (t - 43) * 30;           // a pick is pinned at t = 43 (frame 1287)
  else f = 600 + (t - 52) * 30;                        // end card
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
const CAPS = [
  // [in, out, step number or null, title, sub]
  [8, 13, null, 'Deckie knows|{your crate.}', 'A booth companion on an iPad, listening beside the decks.'],
  [13, 18, null, 'It names the song,|reads the pitch|fader, shows what|could come next.', ''],
  [32, 42, '1', 'Desk reads your crate and writes a crate file.', 'Edits, bootlegs and burned CDs included.'],
  [42, 48, '2', 'Send it to your iPad.', 'AirDrop, iCloud Drive or Files.'],
  [48, 54, '3', 'Put it by the decks. Play.', 'A song shows up after a few seconds of music.'],
  [54, 60, '3', 'It names the song|from {your crate.}', 'Disc, folder and track, as on your player.'],
  [60, 68, '3', 'It reads the pitch fader.', 'This deck runs 3 percent fast, so the tempo reads 128 BPM.'],
  [68, 74, '3', 'What could come|next, best first.', ''],
  [74, 80, '3', 'Where to set the pitch. How you could bring it in.', 'The wave: the end of this song over the start of that one.'],
  [80, 88, '3', 'Shuffle for less|obvious picks. Pin|{the one you want.}', ''],
  [88, 90, null, 'The dictionary.', 'The third part: every word, three ways.'],
  [90, 92, null, 'Plain words.', ''],
  [92, 94, null, 'The DJ’s word.', ''],
  [94, 96, null, 'What Deckie does with it.', ''],
];
function captions(ctx, u) {
  for (let i = 0; i < CAPS.length; i++) {
    const [u0, u1, num, title, sub] = CAPS[i];
    if (u < u0 - 0.1 || u > u1) continue;
    const out = E.inCubic(prog(u, u1 - (u1 - u0 <= 2 ? 0.35 : 0.7), u1));
    const fT = font(70, 800, DISPLAY), fS = font(36, 500, UI);
    const tl = title.includes('|') ? title.split('|') : wrap(ctx, title, fT, COL_W - 30), sl = sub ? wrap(ctx, sub, fS, COL_W - 20) : [];
    const blockH = tl.length * 82 + (sl.length ? 30 + sl.length * 50 : 0);
    let y = 560 - blockH / 2 + 60;
    // the step number holds across captions of the same step; it only springs when the step changes
    if (num) {
      const first = i === 0 || CAPS[i - 1][2] !== num, last = i === CAPS.length - 1 || CAPS[i + 1][2] !== num;
      const kin = first ? springU(u, u0, SPRING.bouncy) : 1, kout = last ? 1 - out : 1;
      ctx.save(); ctx.globalAlpha = clamp(kin) * kout;
      const ny = y - 96;
      text(ctx, num, COL_X, ny + 6 + (1 - kin) * 30, font(96, 800, DISPLAY), C.acc, 'left', -2);
      text(ctx, '/3', COL_X + 58, ny + 6 + (1 - kin) * 30, font(44, 800, DISPLAY), C.dim);
      const part = { 1: 'DECKIE DESK · ON YOUR MAC', 3: 'DECKIE · ON YOUR IPAD' }[num];
      if (part) text(ctx, part, COL_X + 136, ny - 6 + (1 - kin) * 30, font(25, 650, UI), C.mut, 'left', 3);
      ctx.restore();
    }
    tl.forEach((ln, j) => {
      const k = springU(u, u0 + j * 0.14, SPRING.snappy);
      if (k <= 0) return;
      ctx.save(); ctx.globalAlpha = clamp(k) * (1 - out);
      rich(ctx, ln, COL_X, y + j * 82 + (1 - k) * 46 - out * 30, 70, C.warm);
      ctx.restore();
    });
    y += tl.length * 82 + 30 - 30;
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
  ['None of them know', '{your music.}'].forEach((ln, j) => {
    const k = springU(u, 5 + j * 0.2, SPRING.snappy);
    if (k <= 0) return;
    ctx.save(); ctx.globalAlpha = clamp(k);
    rich(ctx, ln, COL_X, 800 + j * 104 + (1 - k) * 60, 92, C.acc);
    ctx.restore();
  });
  ctx.restore();
}

// ------------------------------------------------------------------ a stamp: stencilled words in a ruled box, a few degrees off square
function stamp(ctx, str, x, y, size, k, { color = C.acc, rot = -0.05, alpha = 1 } = {}) {
  if (k <= 0) return;
  const f = font(size, 800, DISPLAY);
  ctx.font = f; ctx.letterSpacing = `${size * 0.1}px`;
  const w = ctx.measureText(str).width; ctx.letterSpacing = '0px';
  const padX = size * 0.42, padY = size * 0.3, h = size * 0.78 + padY * 2;
  ctx.save();
  ctx.translate(x + (w + padX * 2) / 2, y - h / 2 + padY); ctx.rotate(rot); ctx.scale(lerp(1.5, 1, Math.min(k, 1)), lerp(1.5, 1, Math.min(k, 1)));
  ctx.globalAlpha = clamp(k) * alpha;
  ctx.strokeStyle = color; ctx.lineWidth = Math.max(4, size * 0.07);
  ctx.strokeRect(-(w + padX * 2) / 2, -h / 2, w + padX * 2, h);
  text(ctx, str, -w / 2, size * 0.36, f, color, 'left', size * 0.1);
  ctx.restore();
}

// ------------------------------------------------------------------ S3 what it is not (u 18..24), then the name (u 24..32)
const ISNT = [[18, 'Not an AI DJ.', C.warm], [20, 'No sync button.', C.warm], [22, 'It suggests. {You mix.}', C.acc]];
function sceneIsnt(ctx, u) {
  const out = E.inCubic(prog(u, 23.5, 24.2));
  ISNT.forEach(([u0, ln, col], i) => {
    const k = springU(u, u0, SPRING.snappy);
    if (k <= 0) return;
    ctx.save(); ctx.globalAlpha = clamp(k) * (1 - out) * (i < 2 && u >= 22 ? lerp(1, 0.45, prog(u, 22, 23)) : 1);
    rich(ctx, ln, COL_X, 360 + i * 190 + (1 - k) * 80 - out * 80, 150, col);
    ctx.restore();
  });
}
function wordmark(ctx, u, u0, base, size, alpha = 1) {
  const f = font(size, 400, SCRIPT);
  const L = layout(ctx, 'Deckie', f, 0);
  L.glyphs.forEach((g, j) => {
    const p = E.outBack(prog(u, u0 + j * 0.07, u0 + 0.9 + j * 0.07), 1.4);
    if (p <= 0) return;
    ctx.save(); ctx.globalAlpha = alpha; ctx.beginPath(); ctx.rect(0, 0, W, base + L.desc + 30); ctx.clip();
    glyph(ctx, g.ch, COL_X + g.cx, base + (1 - p) * (L.asc + L.desc + 90), f, C.warm);
    ctx.restore();
  });
}
function sceneName(ctx, u) {
  const out = E.inCubic(prog(u, 31.2, 32));
  ctx.save(); ctx.translate(0, -out * 120);
  wordmark(ctx, u, 24, 520, 330, 1 - out);
  const k1 = springU(u, 25.4, SPRING.snappy);
  if (k1 > 0) { ctx.save(); ctx.globalAlpha = clamp(k1) * (1 - out); text(ctx, 'DJ booth companion', COL_X + 6, 640 + (1 - k1) * 30, font(60, 600, UI), C.mut); ctx.restore(); }
  stamp(ctx, 'COMING SOON', COL_X + 4, 850, 84, springU(u, 27, SPRING.bouncy), { alpha: 1 - out });
  const ka = springU(u, 28, SPRING.snappy);
  if (ka > 0) { ctx.save(); ctx.globalAlpha = clamp(ka) * (1 - out); text(ctx, 'deckie.io', 1010, 836 + (1 - ka) * 30, font(60, 700, UI), C.warm, 'left', -1); ctx.restore(); }
  ctx.restore();
}

// ------------------------------------------------------------------ S4 the crate file, as a stencilled label (u 33..43); it becomes the chip that travels (u 42..48)
const HASDESK = () => !!DESK_READY;
const LABEL_ITEMS = [[35, 'TEMPO'], [35.5, 'KEY'], [36, 'BARS'], [36.5, 'STYLE'], [37, 'FINGERPRINTS']];
function crateLabel(ctx, u) {
  if (u < 33.4 || u > 43.4) return;
  const B = HASDESK() ? [1150, 420, 640, 440] : [800, 220, 860, 588];
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
  text(ctx, 'FRIDAY NIGHT', 44 * sc, 110 * sc, font(76 * sc, 800, DISPLAY), C.warm, 'left', 3);
  text(ctx, 'CRATE FILE', 46 * sc, 158 * sc, font(30 * sc, 650, UI), C.mut, 'left', 5);
  ctx.fillStyle = C.line; ctx.fillRect(44 * sc, 190 * sc, w - 88 * sc, 3);
  const pos = [[44, 270], [270, 270], [430, 270], [44, 350], [250, 350]];
  LABEL_ITEMS.forEach(([u0, word], i) => {
    const ki = springU(u, u0, SPRING.snappy);
    if (ki <= 0) return;
    ctx.save(); ctx.globalAlpha *= clamp(ki);
    text(ctx, word, pos[i][0] * sc, (pos[i][1] + (1 - ki) * 24) * sc, font(50 * sc, 800, DISPLAY), C.tx, 'left', 2);
    ctx.restore();
  });
  stamp(ctx, 'NO AUDIO', 44 * sc, 478 * sc, 62 * sc, springU(u, 39, SPRING.bouncy));
  ctx.restore();
}
function fileChip(ctx, u) {
  const k = prog(u, 42.3, 42.9), out = prog(u, 46.2, 47);
  if (k <= 0 || out >= 1) return;
  const p = E.inOutCubic(prog(u, 43.4, 46));
  const from = HASDESK() ? [1470, 640] : [1200, 510];
  const cx = lerp(from[0], 1557, p), y = lerp(from[1], 744, p) - Math.sin(p * Math.PI) * 110;
  const w = 372, h = 96;
  ctx.save(); ctx.globalAlpha = clamp(k) * (1 - out);
  ctx.translate(cx, y); ctx.rotate(Math.sin(p * Math.PI) * -0.07);
  ctx.shadowColor = 'rgba(0,0,0,0.5)'; ctx.shadowBlur = 40; ctx.shadowOffsetY = 14;
  ctx.fillStyle = C.card; ctx.fillRect(-w / 2, -h / 2, w, h);
  ctx.shadowColor = 'transparent';
  ctx.strokeStyle = C.warm; ctx.lineWidth = 3; ctx.strokeRect(-w / 2 + 7, -h / 2 + 7, w - 14, h - 14);
  text(ctx, 'FRIDAY NIGHT', -w / 2 + 26, 2, font(36, 800, DISPLAY), C.warm, 'left', 2);
  text(ctx, 'CRATE FILE · NO AUDIO', -w / 2 + 27, 30, font(17, 650, UI), C.mut, 'left', 2.5);
  ctx.restore();
}

// ------------------------------------------------------------------ S11 the promise (u 96..104)
const PROMISE = [[96, '{Your music} never leaves your devices.'], [99, 'No account. No upload.'], [101, 'Works with no signal.']];
function scenePromise(ctx, u) {
  const out = prog(u, 103.4, 104);
  PROMISE.forEach(([u0, ln], i) => {
    const k = springU(u, u0, SPRING.snappy);
    if (k <= 0) return;
    ctx.save(); ctx.globalAlpha = clamp(k) * (1 - out);
    rich(ctx, ln, COL_X, 380 + i * 150 + (1 - k) * 70 - out * 60, 86, i === 2 || u < PROMISE[i + 1][0] ? C.warm : C.mut);
    ctx.restore();
  });
}

// ------------------------------------------------------------------ S12 end card (u 104..120)
function sceneEnd(ctx, u) {
  wordmark(ctx, u, 104, 450, 300);
  const k1 = springU(u, 105.4, SPRING.snappy);
  if (k1 > 0) { ctx.save(); ctx.globalAlpha = clamp(k1); text(ctx, 'DJ booth companion', COL_X + 6, 552 + (1 - k1) * 30, font(52, 600, UI), C.mut); ctx.restore(); }
  stamp(ctx, 'COMING SOON', COL_X + 4, 740, 76, springU(u, 108, SPRING.bouncy));
  const k3 = springU(u, 116, SPRING.bouncy);
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
  if (u >= 103.5) return springKeys(u, [[104, [1180, 1200, 644, 444]], [104.6, [1180, 318, 644, 444]]], { stiffness: 150, damping: 22 });
  if (u < 30) return springKeys(u, [[7.6, OFF_R(MAIN)], [7.7, MAIN], [17.6, OFF_R(MAIN)]], { stiffness: 150, damping: 22 });
  return springKeys(u, [[41.6, OFF_R(SEND.booth)], [42, SEND.booth], [47.4, MAIN], [87.5, [MAIN[0], H + 120, MAIN[2], MAIN[3]]]], { stiffness: 150, damping: 22 });
}
const BFULL = [800, 551, 1];
function boothCam(u) {
  return springKeys(u, [
    [0, BFULL],
    [60, [400, 400, 1.75]],        // the playing panel: status line, song, tempo
    [68, [1210, 400, 1.7]],        // the picks
    [74, [1250, 330, 1.9]],        // one pick: tempo, pitch, move, join wave
    [80, [1200, 300, 1.55]],       // the Shuffle dial and the list under it
    [87, BFULL],
  ], { stiffness: 90, damping: 20 });
}
function deskBox(u) {
  return springKeys(u, [[31.6, OFF_R(SEND.desk)], [32, SEND.desk], [47, OFF_L(SEND.desk)]], { stiffness: 150, damping: 22 });
}
function vocBox(u) {
  return springKeys(u, [[87.4, [VOC[0], -VOC[3] - 120, VOC[2], VOC[3]]], [87.6, VOC], [95.6, [VOC[0], H + 100, VOC[2], VOC[3]]]], { stiffness: 150, damping: 22 });
}
const VOC_H = 1200;
function vocCam(u) {
  return springKeys(u, [[0, [883, 650, 1.45]], [90, [890, 880, 2.6]], [92, [1528, 900, 2.6]], [94, [2068, 880, 2.6]]], { stiffness: 110, damping: 21 });
}
// Desk stills by shot (from Desk's --snapshot), and the camera over the 2560 x 1600 window.
let DESKCAM = [[0, [1280, 800, 1]]], DESK_READY = false;
function deskImg(u, IMG) { return u < 37 ? IMG.desk_open : IMG.desk_row || IMG.desk_open; }
function deskCam(u) { return springKeys(u, DESKCAM, { stiffness: 90, damping: 20 }); }

// Every accent, with its sound. Kept sparse: the bed carries the pulse, the accents mark the steps.
const HITS = [
  [0, 'CDJs', 'thud', { gain: 0.3 }], [1.5, 'Turntables', 'pop', { pitch: 'A4' }], [3, 'The house decks', 'pop', { pitch: 'C5' }],
  [5, 'None of them know your music', 'thud'],
  [7.7, 'the booth whips in', 'whoosh', { len: 0.5 }], [8, 'Deckie knows your crate', 'tick'], [13, 'what it does', 'tick'],
  [18, 'Not an AI DJ', 'thud', { gain: 0.3 }], [20, 'No sync button', 'thud', { gain: 0.3 }], [22, 'It suggests. You mix.', 'bell', { pitch: 'A5' }],
  [24, 'Deckie', 'impact', { gain: 0.45 }], [27, 'Coming soon stamp', 'thud'],
  [32, 'step 1', 'impact', { gain: 0.5 }], [35, 'tempo', 'tick'], [35.5, 'key', 'tick'], [36, 'bars', 'tick'], [36.5, 'style', 'tick'], [37, 'fingerprints', 'tick'],
  [39, 'No audio stamp', 'thud'],
  [42, 'step 2', 'bell', { pitch: 'A5' }], [43.4, 'crate file leaves', 'whoosh', { len: 0.7, from: 500, to: 2600 }], [46, 'crate file lands', 'pop', { pitch: 'E5' }],
  [48, 'step 3', 'bell', { pitch: 'C6' }], [54, 'the song is named', 'bell', { pitch: 'E6' }],
  [60, 'pitch fader', 'tick'], [68, 'picks', 'tick'], [74, 'one pick', 'tick'],
  [82, 'Shuffle moves', 'whoosh', { len: 0.4, from: 800, to: 2200 }], [86, 'pin', 'pop', { pitch: 'E5' }],
  [87.6, 'the dictionary drops in', 'whoosh', { len: 0.5 }], [90, 'plain', 'tick'], [92, 'DJ', 'tick'], [94, 'Deckie', 'tick'],
  [96, 'never leaves your devices', 'thud', { gain: 0.3 }], [99, 'no account', 'pop', { pitch: 'A4' }], [101, 'no signal', 'pop', { pitch: 'C5' }],
  [104, 'Deckie', 'impact', { gain: 0.6 }], [108, 'Coming soon stamp', 'thud'], [116, 'Help us beta test', 'bell', { pitch: 'E6' }],
];

const images = { v_type_08: 'assets/vocab/v_type_08.png' };
const deskCfg = await fetch('assets/desk/desk.json').then((r) => (r.ok ? r.json() : null)).catch(() => null);
if (deskCfg) { Object.assign(images, deskCfg.images); DESKCAM = deskCfg.cam; DESK_READY = true; }

M.film({
  fonts: [font(100, 800, DISPLAY), font(40, 500, UI), font(100, 400, SCRIPT)],
  images, hits: HITS, samples: 16,
  draw(ctx, u, t, IMG) {
    backdrop(ctx);
    // S1 hook, whipping out left as the booth card whips in
    if (u < 9.5) sceneHook(ctx, u, t, -springU(u, 7.6, { stiffness: 150, damping: 22 }) * (W + 200));
    // cards
    if (DESK_READY && u >= 31.5 && u < 49) card(ctx, deskImg(u, IMG), deskBox(u), deskCam(u));
    if (u >= 87 && u < 98) card(ctx, IMG.v_type_08, vocBox(u), vocCam(u), { srcH: VOC_H });
    if ((u >= 7 && u < 20) || (u >= 41.5 && u < 89) || u >= 103.5) {
      const map = card(ctx, boothImg(t), boothBox(u), u >= 103.5 || u < 30 ? BFULL : boothCam(u));
      callout(ctx, map, u, 61, 67, [356, 122, 250, 38]);        // "sure · deck +3.0%"
      callout(ctx, map, u, 62.5, 67, [58, 506, 150, 50]);       // 128 BPM
      callout(ctx, map, u, 74.6, 77, [806, 346, 300, 82]);      // tempo, pitch and the move
      callout(ctx, map, u, 77, 79.6, [1190, 236, 410, 170]);    // the join wave
      callout(ctx, map, u, 82, 85, [940, 116, 280, 46]);        // Shuffle
      callout(ctx, map, u, 86, 87.6, [786, 216, 814, 126]);     // NEXT
    }
    crateLabel(ctx, u);
    fileChip(ctx, u);
    captions(ctx, u);
    if (u >= 18 && u < 24.4) sceneIsnt(ctx, u);
    if (u >= 24 && u < 32.2) sceneName(ctx, u);
    if (u >= 96 && u < 104.2) scenePromise(ctx, u);
    if (u >= 104) sceneEnd(ctx, u);
  },
});
