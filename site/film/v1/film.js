// Deckie explainer: a pure function of time. window.seek(t) paints frame t (lib/motion.js).
// Timing is in beats (u) at 120 bpm, so one beat is half a second and one bar is two seconds.
// The plan this file follows is docs/shotlist.md. Every screen is a real capture: the booth frames are a
// simulator recording, the Desk stills come from Desk's own --snapshot mode, the dictionary stills are the
// vocabulary page in a headless browser. Nothing on a screen is drawn by this file.
import * as M from './lib/motion.js';

const { W, H, E, prog, lerp, clamp, springU, springKeys, SPRING, font, layout, glyph, text, fill, rrect } = M;

// The booth app's own colours (deck-app Model.swift, Theme). One accent.
const C = { bg: '#0f0a17', bg2: '#1c1036', card: '#1d1530', line: '#30254a', tx: '#f2edf9', mut: '#ab9fc2', dim: '#76698f', acc: '#b490ff', ink: '#160f22' };
const DISPLAY = 'Display', UI = 'UI';

// ------------------------------------------------------------------ booth frames (image sequence, loaded on demand)
const BOOTH_N = 1976, BW = 1600, BH = 1102;
// film seconds -> frame of the 30 fps simulator recording. Real time unless noted.
function boothF(t) {
  let f;
  if (t < 16) f = 500 + (t - 6) * 30;                  // promise + suite: a recognised song, cursor moving
  else if (t < 35.5) f = 200;                          // behind the Desk chapter: the Listening screen
  else if (t < 46) f = 159 + (t - 36) * 30;            // listening, then the song is named at t = 39 (frame 249)
  else if (t < 58) f = t < 48 ? 868 + (t - 48) * 30    // Simple to Full at t = 48 (frame 868)
    : 868 + (t - 48) * (180 / 7);                      // a touch slow, so Shuffle moves at t = 55 (frame 1048)
  else if (t < 62) f = 1287 + (t - 59) * 30;           // pin at t = 59 (frame 1287)
  else if (t < 63.6) f = 1512 + (t - 62.5) * 30;       // scroll to More at t = 62.5 (frame 1512)
  else if (t < 66.2) f = 1678 + (t - 64.2) * 30;       // the search fills at t = 64.2 (frame 1678)
  else f = 1000 + (t - 76) * 30;                       // end card: Full list, cursor moving
  return clamp(Math.round(f), 0, BOOTH_N - 1);
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
  [12, 18, null, 'A booth companion that listens.', 'Deckie sits on an iPad beside the decks.'],
  [18, 24, null, 'It works from your own crate.', 'Your music stays on your devices.'],
  [32, 40, '1', 'Desk reads your crate and writes a crate file.', 'Deckie Desk, on your Mac.'],
  [40, 48, '1', 'Tempo, key, bars, style, fingerprints.', 'No audio goes into the crate file.'],
  [48, 56, '1', 'Sort songs into discs and folders.', 'In the order your player shows them.'],
  [56, 64, '1', 'The import log says what was left out, and why.', ''],
  [64, 72, '2', 'Send the crate file to your iPad.', 'AirDrop, iCloud Drive or Files.'],
  [72, 78, '3', 'Put the iPad by the decks. Play.', 'A song shows up after a few seconds of music.'],
  [78, 84, '3', 'It names the song from your crate.', 'Disc, folder and track number, as on your player.'],
  [84, 92, '3', 'It reads the pitch fader.', 'This deck runs 3 percent fast, so the tempo reads 128 BPM.'],
  [92, 100, '3', 'What could come next, best first.', 'Simple shows five picks. Full shows ten.'],
  [100, 108, '3', 'Where to set the pitch. How you could bring it in.', 'The wave: the end of this song over the start of that one.'],
  [108, 116, '3', 'Turn up Shuffle for less obvious picks.', 'At zero the picks stay in score order.'],
  [116, 124, '3', 'Tap a pick to pin it as next.', ''],
  [124, 132, '3', 'Or search the rest of the crate.', 'More lists every other song, by score.'],
  [132, 140, null, 'The dictionary.', 'Every word Deckie uses, said three ways.'],
  [140, 142, null, 'Plain words.', ''],
  [142, 144, null, 'The DJ’s word.', ''],
  [144, 146, null, 'What Deckie does with it.', ''],
];
function captions(ctx, u) {
  for (let i = 0; i < CAPS.length; i++) {
    const [u0, u1, num, title, sub] = CAPS[i];
    if (u < u0 - 0.1 || u > u1) continue;
    const out = E.inCubic(prog(u, u1 - (u1 - u0 <= 2 ? 0.35 : 0.7), u1));
    const fT = font(74, 750, DISPLAY), fS = font(36, 500, UI);
    const tl = wrap(ctx, title, fT, COL_W), sl = sub ? wrap(ctx, sub, fS, COL_W - 20) : [];
    const blockH = tl.length * 82 + (sl.length ? 30 + sl.length * 50 : 0);
    let y = 560 - blockH / 2 + 60;
    // the step number holds across captions of the same step; it only springs when the step changes
    if (num) {
      const first = i === 0 || CAPS[i - 1][2] !== num, last = i === CAPS.length - 1 || CAPS[i + 1][2] !== num;
      const kin = first ? springU(u, u0, SPRING.bouncy) : 1, kout = last ? 1 - out : 1;
      ctx.save(); ctx.globalAlpha = clamp(kin) * kout;
      const ny = y - 96;
      rrect(ctx, COL_X, ny - 62 + (1 - kin) * 30, 84, 84, 42); ctx.fillStyle = C.acc; ctx.fill();
      text(ctx, num, COL_X + 42, ny + 2 + (1 - kin) * 30, font(54, 800, DISPLAY), C.ink, 'center');
      text(ctx, 'of 3', COL_X + 104, ny - 6 + (1 - kin) * 30, font(30, 600, UI), C.dim);
      ctx.restore();
    }
    tl.forEach((ln, j) => {
      const k = springU(u, u0 + j * 0.14, SPRING.snappy);
      if (k <= 0) return;
      ctx.save(); ctx.globalAlpha = clamp(k) * (1 - out);
      text(ctx, ln, COL_X, y + j * 82 + (1 - k) * 46 - out * 30, fT, C.tx, 'left', -1.2);
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
const SEND = { desk: [760, 150, 520, 325], booth: [1290, 560, 534, 368] };

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
const HOOK = [[0, 'CDJs.'], [2, 'Turntables.'], [4, 'The house decks.']];
function sceneHook(ctx, u, t, shiftX) {
  ctx.save(); ctx.translate(shiftX, 0);
  const kp = springU(u, -0.6, SPRING.gentle);
  platter(ctx, 1500, 330 + (1 - kp) * 80, 300, t * M.TAU * 0.55, C.acc);
  platter(ctx, 1260, 870 + (1 - kp) * 80, 230, t * M.TAU * 0.55 + 1, '#5a6cc0');
  const size = 148, f = font(size, 800, DISPLAY), track = -0.035 * size;
  HOOK.forEach(([u0, w], i) => {
    const L = layout(ctx, w, f, track);
    L.glyphs.forEach((g, j) => {
      const k = springU(u, u0 - (i === 0 ? 0.3 : 0) + j * 0.025, SPRING.bouncy);
      if (k <= 0) return;
      const dim = u > 7 ? lerp(1, 0.38, prog(u, 7, 8)) : 1;
      ctx.save(); ctx.globalAlpha = dim;
      glyph(ctx, g.ch, COL_X + g.cx, 300 + i * 158 + (1 - k) * 120, f, C.tx, k, k);
      ctx.restore();
    });
  });
  const f2 = font(92, 780, DISPLAY);
  ['None of them know', 'your music.'].forEach((ln, j) => {
    const k = springU(u, 7 + j * 0.2, SPRING.snappy);
    if (k <= 0) return;
    ctx.save(); ctx.globalAlpha = clamp(k);
    text(ctx, ln, COL_X, 800 + j * 104 + (1 - k) * 60, f2, C.acc, 'left', -2);
    ctx.restore();
  });
  ctx.restore();
}

// ------------------------------------------------------------------ S3 suite labels (u 24..32)
function suiteLabels(ctx, u) {
  const out = prog(u, 31.2, 32);
  const kh = springU(u, 24, SPRING.snappy);
  ctx.save(); ctx.globalAlpha = clamp(kh) * (1 - out);
  text(ctx, 'Deckie comes in three parts.', COL_X, 200 + (1 - kh) * 40, font(76, 780, DISPLAY), C.tx, 'left', -1.5);
  ctx.restore();
  const L = [[SUITE.desk, 'Deckie Desk', 'On your Mac. It makes the crate file.', 25],
    [SUITE.booth, 'Deckie, in the booth', 'On your iPad, beside the decks.', 26],
    [SUITE.voc, 'The dictionary', 'Every word, said three ways.', 27]];
  for (const [b, name, sub, u0] of L) {
    const k = springU(u, u0, SPRING.snappy);
    if (k <= 0) continue;
    ctx.save(); ctx.globalAlpha = clamp(k) * (1 - out);
    text(ctx, name, b[0], 790 + (1 - k) * 30, font(46, 750, DISPLAY), C.tx, 'left', -0.6);
    text(ctx, sub, b[0], 842 + (1 - k) * 30, font(29, 500, UI), C.mut);
    ctx.restore();
  }
}

// ------------------------------------------------------------------ S5 the crate file travels (u 64..72)
function fileChip(ctx, u) {
  const k = springU(u, 65, SPRING.bouncy), out = prog(u, 70.6, 71.4);
  if (k <= 0 || out >= 1) return;
  const p = E.inOutCubic(prog(u, 66.5, 69.5));
  const cx = lerp(1020, 1557, p), y = lerp(500, 744, p) - Math.sin(p * Math.PI) * 90;
  const w = 372, h = 92;
  ctx.save(); ctx.globalAlpha = clamp(k) * (1 - out);
  ctx.translate(cx, y); ctx.scale(lerp(0.6, 1, Math.min(k, 1.1)), lerp(0.6, 1, Math.min(k, 1.1))); ctx.rotate(Math.sin(p * Math.PI) * -0.06);
  ctx.shadowColor = 'rgba(0,0,0,0.5)'; ctx.shadowBlur = 40; ctx.shadowOffsetY = 14;
  rrect(ctx, -w / 2, -h / 2, w, h, 22); ctx.fillStyle = C.acc; ctx.fill();
  ctx.shadowColor = 'transparent';
  text(ctx, 'Friday night', -w / 2 + 28, -4, font(34, 750, DISPLAY), C.ink);
  text(ctx, 'crate file · no audio', -w / 2 + 28, 30, font(23, 600, UI), '#3b2a63');
  ctx.restore();
}

// ------------------------------------------------------------------ S8 the promise (u 146..152)
const PROMISE = [[146, 'Your music stays on your devices.'], [148, 'No account. No upload.'], [150, 'Works with no signal.']];
function scenePromise(ctx, u) {
  const out = prog(u, 151.4, 152);
  PROMISE.forEach(([u0, ln], i) => {
    const k = springU(u, u0, SPRING.snappy);
    if (k <= 0) return;
    ctx.save(); ctx.globalAlpha = clamp(k) * (1 - out);
    text(ctx, ln, COL_X, 380 + i * 150 + (1 - k) * 70 - out * 60, font(104, 780, DISPLAY), i === 2 || u < PROMISE[i + 1][0] ? C.tx : C.mut, 'left', -2.4);
    ctx.restore();
  });
}

// ------------------------------------------------------------------ S9 end card (u 152..168)
function sceneEnd(ctx, u, t) {
  const size = 300, f = font(size, 800, DISPLAY);
  const L = layout(ctx, 'Deckie', f, -0.04 * size);
  const base = 470;
  L.glyphs.forEach((g, j) => {
    const p = E.outBack(prog(u, 152 + j * 0.07, 152.9 + j * 0.07), 1.4);
    if (p <= 0) return;
    ctx.save(); ctx.beginPath(); ctx.rect(0, 0, W, base + L.desc + 8); ctx.clip();
    glyph(ctx, g.ch, COL_X + g.cx, base + (1 - p) * (L.asc + 60), f, C.tx);
    ctx.restore();
  });
  const k1 = springU(u, 153.4, SPRING.snappy);
  if (k1 > 0) { ctx.save(); ctx.globalAlpha = clamp(k1); text(ctx, 'DJ booth companion', COL_X + 8, 570 + (1 - k1) * 30, font(54, 600, UI), C.mut); ctx.restore(); }
  const k2 = springU(u, 156, SPRING.bouncy);
  if (k2 > 0) { ctx.save(); ctx.globalAlpha = clamp(k2); text(ctx, 'Coming soon.', COL_X + 4, 760 + (1 - k2) * 50, font(96, 780, DISPLAY), C.acc, 'left', -2); ctx.restore(); }
  const k3 = springU(u, 164, SPRING.bouncy);
  if (k3 > 0) {
    ctx.save(); ctx.translate(COL_X + 250, 880); ctx.scale(lerp(0.7, 1, k3), lerp(0.7, 1, k3)); ctx.globalAlpha = clamp(k3);
    rrect(ctx, -250, -52, 500, 104, 52); ctx.fillStyle = C.acc; ctx.fill();
    text(ctx, 'Help us beta test', 0, 16, font(46, 750, DISPLAY), C.ink, 'center', -0.5);
    ctx.restore();
  }
}

// ------------------------------------------------------------------ the film
const mixBox = (a, b, k) => a.map((v, i) => lerp(v, b[i], k));
const OFF_R = (b) => [W + 80, b[1], b[2], b[3]];
const OFF_L = (b) => [-b[2] - 80, b[1], b[2], b[3]];

// Booth card: where it sits over the film (spring between boxes), and its camera over the 1600 x 1102 frame.
function boothBox(u) {
  const keys = [
    [11.4, OFF_R(MAIN)], [11.5, MAIN],           // whips in as the hook whips out
    [24, SUITE.booth], [31.4, OFF_R(SUITE.booth)],
    [63.6, OFF_R(SEND.booth)], [64, SEND.booth], [71, MAIN],
    [131.5, [MAIN[0], H + 120, MAIN[2], MAIN[3]]],   // drops out as the dictionary drops in
  ];
  if (u >= 151.5) return springKeys(u, [[152, [1180, 1200, 644, 444]], [152.6, [1180, 318, 644, 444]]], { stiffness: 150, damping: 22 });
  return springKeys(u, keys, { stiffness: 150, damping: 22 });
}
const BFULL = [800, 551, 1];
function boothCam(u) {
  return springKeys(u, [
    [0, BFULL],
    [84, [400, 400, 1.75]],        // the playing panel: status line, song, tempo
    [92, BFULL],
    [100, [1250, 330, 1.9]],       // the first picks: tempo, pitch, move, join wave
    [108, [1200, 300, 1.55]],      // the Shuffle dial and the list under it
    [116, [1150, 330, 1.5]],
    [124, [1180, 400, 1.35]],
    [131, BFULL],
  ], { stiffness: 90, damping: 20 });
}
function deskBox(u) {
  return springKeys(u, [
    [23.9, OFF_L(SUITE.desk)], [24.4, SUITE.desk], [31, DESK],
    [63.5, SEND.desk], [71.2, OFF_L(SEND.desk)],
  ], { stiffness: 150, damping: 22 });
}
function vocBox(u) {
  return springKeys(u, [
    [24.5, OFF_R(SUITE.voc)], [25.2, SUITE.voc], [31.2, [W + 700, SUITE.voc[1], SUITE.voc[2], SUITE.voc[3]]],
    [131.4, [VOC[0], -VOC[3] - 120, VOC[2], VOC[3]]], [131.6, VOC],
    [145.6, [VOC[0], H + 100, VOC[2], VOC[3]]],
  ], { stiffness: 150, damping: 22 });
}
const VOC_H = 1200;
function vocImg(u, IMG) {
  if (u < 134) return IMG.v_top;
  const i = Math.min(8, 1 + Math.floor((u - 134) / 0.5));   // one letter every half beat: "echo out"
  return IMG[`v_type_0${i}`];
}
function vocCam(u) {
  return springKeys(u, [[0, [883, 650, 1.45]], [140, [890, 880, 2.6]], [142, [1528, 900, 2.6]], [144, [2068, 880, 2.6]]], { stiffness: 110, damping: 21 });
}
// Desk stills by shot (file names from Desk's --snapshot), and the camera over the 2560 x 1600 window.
function deskImg(u, IMG) {
  if (u < 36) return IMG.desk_open;
  if (u < 48) return IMG.desk_row;
  if (u < 52) return IMG.desk_discs;
  if (u < 56) return IMG.desk_discs_track;
  if (u < 64) return IMG.desk_log;
  return IMG.desk_open;
}
let DESKCAM = [[0, [1280, 800, 1]]];
function deskCam(u) { return springKeys(u, DESKCAM, { stiffness: 90, damping: 20 }); }

// Every accent, with its sound. Kept sparse: the bed carries the pulse, the accents mark the steps.
const HITS = [
  [0, 'CDJs', 'thud', { gain: 0.3 }], [2, 'Turntables', 'pop', { pitch: 'A4' }], [4, 'The house decks', 'pop', { pitch: 'C5' }],
  [7, 'None of them know your music', 'thud'],
  [11.5, 'whip to the booth', 'whoosh', { len: 0.5 }], [12, 'booth card lands', 'tick'],
  [18, 'your own crate', 'tick'],
  [24, 'three parts', 'whoosh', { len: 0.4, from: 2400, to: 600 }], [25, 'Desk', 'pop', { pitch: 'A4' }], [26, 'booth', 'pop', { pitch: 'C5' }], [27, 'dictionary', 'pop', { pitch: 'E5' }],
  [32, 'step 1', 'impact', { gain: 0.5 }], [40, 'what the crate file holds', 'tick'], [48, 'discs', 'click'], [56, 'import log', 'click'],
  [64, 'step 2', 'bell', { pitch: 'A5' }], [66.5, 'crate file leaves', 'whoosh', { len: 0.7, from: 500, to: 2600 }], [69.5, 'crate file lands', 'pop', { pitch: 'E5' }],
  [72, 'step 3', 'bell', { pitch: 'C6' }], [78, 'the song is named', 'bell', { pitch: 'E6' }],
  [84, 'pitch fader', 'tick'], [92, 'picks', 'tick'], [96, 'Simple to Full', 'click'], [100, 'pick line', 'tick'],
  [110, 'Shuffle moves', 'whoosh', { len: 0.4, from: 800, to: 2200 }], [118, 'pin', 'pop', { pitch: 'E5' }], [124, 'More', 'tick'], [128.4, 'search', 'type', { len: 0.5 }],
  [131.5, 'whip to the dictionary', 'whoosh', { len: 0.5 }], [134, 'typing echo out', 'type', { len: 1.9 }], [140, 'three ways', 'tick'],
  [146, 'stays on your devices', 'thud', { gain: 0.3 }], [148, 'no account', 'pop', { pitch: 'A4' }], [150, 'no signal', 'pop', { pitch: 'C5' }],
  [152, 'Deckie', 'impact', { gain: 0.6 }], [156, 'Coming soon', 'bell', { pitch: 'A5' }], [164, 'Help us beta test', 'bell', { pitch: 'E6' }],
];

const images = { booth_listening: 'assets/booth_listening.png', v_top: 'assets/vocab/v_top.png' };
for (let i = 1; i <= 8; i++) images[`v_type_0${i}`] = `assets/vocab/v_type_0${i}.png`;
const deskCfg = await fetch('assets/desk/desk.json').then((r) => (r.ok ? r.json() : null)).catch(() => null);
if (deskCfg) { Object.assign(images, deskCfg.images); DESKCAM = deskCfg.cam; }

M.film({
  fonts: [font(100, 800, DISPLAY), font(40, 500, UI)],
  images, hits: HITS, samples: 16,
  draw(ctx, u, t, IMG) {
    backdrop(ctx);
    // S1 hook, whipping out left as the booth card whips in
    if (u < 13) sceneHook(ctx, u, t, -springU(u, 11.4, { stiffness: 150, damping: 22 }) * (W + 200));
    // cards
    if (u >= 23.5 && u < 73) card(ctx, deskImg(u, IMG), deskBox(u), deskCam(u));
    if (u >= 24 && u < 33) card(ctx, vocImg(u, IMG), vocBox(u), [1280, 600, 1], { srcH: VOC_H });
    if (u >= 131 && u < 148) {
      card(ctx, vocImg(u, IMG), vocBox(u), vocCam(u), { srcH: VOC_H });
    }
    if (u >= 11 && u < 133 || u >= 151.5) {
      const bi = boothImg(t);
      const map = card(ctx, bi, boothBox(u), u >= 151.5 ? BFULL : boothCam(u));
      callout(ctx, map, u, 85, 91, [356, 122, 250, 38]);       // "sure · deck +3.0%"
      callout(ctx, map, u, 86.5, 91, [58, 506, 150, 50]);      // 128 BPM
      callout(ctx, map, u, 96, 99, [786, 116, 150, 46]);       // Simple / Full
      callout(ctx, map, u, 101, 104, [806, 292, 250, 58]);     // tempo, pitch and the move
      callout(ctx, map, u, 104, 107.4, [1150, 222, 450, 124]); // the join wave
      callout(ctx, map, u, 109, 114, [940, 116, 280, 46]);     // Shuffle
      callout(ctx, map, u, 118, 122.5, [786, 216, 814, 126]);  // NEXT
      callout(ctx, map, u, 128.2, 131, [790, 262, 690, 56]);   // the search field
    }
    if (u >= 24 && u < 32.2) suiteLabels(ctx, u);
    fileChip(ctx, u);
    captions(ctx, u);
    if (u >= 146 && u < 152.2) scenePromise(ctx, u);
    if (u >= 152) sceneEnd(ctx, u, t);
  },
});
