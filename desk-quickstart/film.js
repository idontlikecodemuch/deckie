// Deckie Desk's quick start, first cut: a pure function of time. `await seek(t)` paints the moment t (in seconds).
// The picture of Desk is the real Windows and Linux window (desk-web, unchanged) captured frame by frame by
// capture/live.mjs while the real engine read generated songs; this file only frames it, moves the camera, draws the
// pointer where the capture clicked, and sets the captions. The booth is the site's own capture (site/assets).
// The plan it follows is storyboard.md. The look is the explainer film's (site/film): the booth's colours, Inter, and
// Pacifico for "you", "your" and "Deckie" only.

const W = 1920, H = 1080;
const C = { bg: '#0f0a17', bg2: '#1c1036', card: '#1d1530', line: '#30254a', tx: '#f2edf9', mut: '#ab9fc2', dim: '#76698f', acc: '#b490ff', ink: '#160f22' };
const UI = 'Inter', SCRIPT = 'Pacifico';
export const DURATION = 52.5;

const canvas = document.getElementById('film');
const ctx = canvas.getContext('2d');

// ------------------------------------------------------------------ small helpers
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, p) => a + (b - a) * p;
const ease = (p) => { p = clamp(p); return p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2; };
const prog = (t, a, b) => clamp((t - a) / (b - a));
/// A value from keys [[t, v], …], eased between keys (or linear, for capture frames).
function keyed(keys, t, smooth = true) {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    if (t <= keys[i][0]) {
      const p = (t - keys[i - 1][0]) / Math.max(1e-6, keys[i][0] - keys[i - 1][0]);
      const a = keys[i - 1][1], b = keys[i][1], q = smooth ? ease(p) : p;
      return Array.isArray(a) ? a.map((x, k) => lerp(x, b[k], q)) : lerp(a, b, q);
    }
  }
  return keys[keys.length - 1][1];
}
function rrect(x, y, w, h, r) {
  ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}

// ------------------------------------------------------------------ type
// One line of copy: Inter, except "you", "your" and "Deckie", which are Pacifico ("you" and "your" in the accent).
const SCRIPT_RE = /\b(You|you|Your|your|Deckie)\b(?!['’\w])/g;
function rich(str, x, y, size, color, weight = 800, align = 'left') {
  const parts = []; let last = 0, m;
  SCRIPT_RE.lastIndex = 0;
  while ((m = SCRIPT_RE.exec(str))) { if (m.index > last) parts.push([str.slice(last, m.index), false]); parts.push([m[0], true]); last = m.index + m[0].length; }
  if (last < str.length) parts.push([str.slice(last), false]);
  const fontOf = (s) => s ? `${Math.round(size * 1.08)}px ${SCRIPT}` : `${weight} ${size}px ${UI}`;
  const track = (s) => s ? 0 : -0.02 * size;
  let width = 0;
  for (const [s, sc] of parts) { ctx.font = fontOf(sc); ctx.letterSpacing = `${track(sc)}px`; width += ctx.measureText(s).width + (sc ? size * 0.14 : 0); }
  let cx = align === 'center' ? x - width / 2 : x;
  ctx.textBaseline = 'alphabetic'; ctx.textAlign = 'left';
  for (const [s, sc] of parts) {
    ctx.font = fontOf(sc); ctx.letterSpacing = `${track(sc)}px`;
    ctx.fillStyle = sc && s !== 'Deckie' ? C.acc : color;
    ctx.fillText(s, cx, y + (sc ? size * 0.02 : 0));
    cx += ctx.measureText(s).width + (sc ? size * 0.14 : 0);
  }
  ctx.letterSpacing = '0px';
  return width;
}

// ------------------------------------------------------------------ the capture
let MARKS = null, WORK = '', CAP = { w: 1280, h: 800, dpr: 2 }, F = {};
const cache = new Map();
function frameImage(n) {
  n = Math.max(0, Math.min(MARKS.frames - 1, Math.round(n)));
  if (cache.has(n)) return cache.get(n);
  const im = new Image();
  im.src = `file://${WORK}/frames/f${String(n).padStart(5, '0')}.jpg`;
  const p = im.decode().then(() => im);
  cache.set(n, p);
  if (cache.size > 12) cache.delete(cache.keys().next().value);
  return p;
}
const still = {};
async function loadStill(key, src) { const im = new Image(); im.src = src; await im.decode(); still[key] = im; }

// The capture's own moments, by name (capture/live.mjs's marks).
const mk = (label) => MARKS.marks.find((m) => m.label === label);

// Film time to capture frame: keys [film seconds, capture frame], linear between keys, so a stretch plays at the
// speed its keys say and two equal frames hold a picture.
let FRAME_KEYS = [];
// The camera inside the window: [film seconds, [centre x, centre y, zoom]] in the window's own pixels (1280 by 800).
let CAM_KEYS = [];
// The pointer: every click the capture made, with where it landed and its capture frame.
let CLICKS = [];
// When the film reaches Export's click and the exported box (set from the capture's marks).
let T_EXPORT = 31, T_EXPORTED = 32;

export async function init(opts) {
  MARKS = opts.marks; WORK = opts.work;
  CAP = { w: MARKS.size[0], h: MARKS.size[1], dpr: MARKS.size[2] };
  for (const m of MARKS.marks) F[m.label] = m.frame;
  CLICKS = MARKS.marks.filter((m) => m.click).map((m) => ({ frame: m.frame, x: m.click[0], y: m.click[1] }));
  const runLen = F['run-finished'] - F['run-started'];
  FRAME_KEYS = [
    [0, F['first-screen']],
    [4.2, F['first-screen']],
    [6.0, F['first-screen'] + 18],                 // the first screen, still a moment; the pointer comes in
    [8.4, F['add-drive'] + 4],                     // the name typed, Add drive clicked: the capture's own pace
    [9.4, F['drive-list'] + 6],
    [11.6, F['drive-list'] + 22],                  // the list held at half speed while the caption is read
    [12.6, F['choose-stick'] + 6],
    [13.4, F['run-started'] + 4],
    [25.4, F['run-started'] + runLen],             // the whole run in twelve seconds
    [26.0, F['finished']],
    [29.6, F['finished'] + 60],
    [29.6 + 0.01, F['scroll']],                    // the scroll down to the buttons, Export and the box: real time
    [T_EXPORT = 29.6 + (F['export'] - F['scroll']) / 30, F['export']],
    [T_EXPORTED = 29.6 + (F['exported'] - F['scroll']) / 30, F['exported']],
    [38.8, F['exported'] + 74],
    [DURATION, F['exported'] + 74],
  ];
  const full = [640, 400, 1];
  const stop = mk('run-started').rect, box = mk('exported').box || mk('exported').rect;
  const mid = (r) => [r[0] + r[2] / 2, r[1] + r[3] / 2];
  const pick = mk('drive-list').rect || [384, 250, 512, 300];
  const stage = [640, 330, 1.3];                                   // the run's top half: title, count, the song on stage
  // Stop at the top right, and the lines under the count from their start
  const atStop = [stop[0] + stop[2] + 30 - 1280 / 1.35 / 2, stop[1] - 40 + 800 / 1.35 / 2, 1.35];
  CAM_KEYS = [
    [0, full], [4.6, full],
    [5.6, [640, 470, 1.45]], [7.8, [640, 470, 1.45]],  // the name and the three ways
    [8.8, full], [9.4, full],
    [10.2, [...mid(pick), 1.6]], [12.4, [...mid(pick), 1.6]],      // Add a drive's list
    [13.2, full], [13.8, full],
    [14.8, stage], [18.6, stage],
    [19.6, atStop], [24.6, atStop],
    [25.6, full], [Math.max(33.4, T_EXPORTED + 0.3), full],
    [Math.max(34.4, T_EXPORTED + 1.3), [mid(box)[0], mid(box)[1], 1.6]], [38.8, [mid(box)[0], mid(box)[1], 1.6]],
    [DURATION, [mid(box)[0], mid(box)[1], 1.6]],
  ];
  // The Stop button and the iPad box, ringed while their captions show.
  RINGS = [{ from: 19.6, to: 25.0, rect: stop }, { from: Math.max(34.6, T_EXPORTED + 1.5), to: 38.6, rect: box }];
  await Promise.all([document.fonts.load(`800 40px ${UI}`), document.fonts.load(`400 40px ${UI}`), document.fonts.load(`40px ${SCRIPT}`),
    loadStill('booth', opts.booth)]);
}
let RINGS = [];

// ------------------------------------------------------------------ the window
const WIN = { x: 70, y: 186, w: 1200 };
WIN.h = Math.round(WIN.w * 800 / 1280);
const BAR = 36;
function camRect(t) {
  let [cx, cy, z] = keyed(CAM_KEYS, t);
  const vw = CAP.w / z, vh = CAP.h / z;
  cx = clamp(cx, vw / 2, CAP.w - vw / 2); cy = clamp(cy, vh / 2, CAP.h - vh / 2);
  return { x: cx - vw / 2, y: cy - vh / 2, w: vw, h: vh, z };
}
/// Page pixels to film pixels, through the camera.
function toFilm(r, px, py) { return [WIN.x + (px - r.x) / r.w * WIN.w, WIN.y + (py - r.y) / r.h * WIN.h]; }

function drawWindow(img, t, alpha, dx = 0, scale = 1) {
  ctx.save();
  ctx.globalAlpha = alpha;
  const cx = WIN.x + WIN.w / 2, cy = WIN.y + WIN.h / 2;
  ctx.translate(cx + dx, cy); ctx.scale(scale, scale); ctx.translate(-cx, -cy);
  // shadow and frame
  ctx.save(); ctx.shadowColor = 'rgba(0,0,0,0.55)'; ctx.shadowBlur = 60; ctx.shadowOffsetY = 24;
  rrect(WIN.x, WIN.y - BAR, WIN.w, WIN.h + BAR, 14); ctx.fillStyle = '#16101f'; ctx.fill(); ctx.restore();
  ctx.save(); rrect(WIN.x, WIN.y - BAR, WIN.w, WIN.h + BAR, 14); ctx.clip();
  // the title bar: the window's name, and three plain controls
  ctx.fillStyle = '#1a1424'; ctx.fillRect(WIN.x, WIN.y - BAR, WIN.w, BAR);
  ctx.font = `500 15px ${UI}`; ctx.fillStyle = C.mut; ctx.textAlign = 'left'; ctx.fillText('Deckie Desk', WIN.x + 18, WIN.y - BAR / 2 + 5);
  ctx.strokeStyle = C.dim; ctx.lineWidth = 1.4;
  const bx = WIN.x + WIN.w - 26, by = WIN.y - BAR / 2;
  ctx.beginPath(); ctx.moveTo(bx - 5, by - 5); ctx.lineTo(bx + 5, by + 5); ctx.moveTo(bx + 5, by - 5); ctx.lineTo(bx - 5, by + 5); ctx.stroke();
  ctx.strokeRect(bx - 50, by - 5, 10, 10);
  ctx.beginPath(); ctx.moveTo(bx - 95, by); ctx.lineTo(bx - 85, by); ctx.stroke();
  // the page, through the camera
  const r = camRect(t);
  if (img) { ctx.imageSmoothingQuality = 'high'; ctx.drawImage(img, r.x * CAP.dpr, r.y * CAP.dpr, r.w * CAP.dpr, r.h * CAP.dpr, WIN.x, WIN.y, WIN.w, WIN.h); }
  // rings round what the caption names
  for (const ring of RINGS) {
    const a = prog(t, ring.from, ring.from + 0.4) * (1 - prog(t, ring.to - 0.3, ring.to));
    if (a <= 0) continue;
    const [x0, y0] = toFilm(r, ring.rect[0], ring.rect[1]), [x1, y1] = toFilm(r, ring.rect[0] + ring.rect[2], ring.rect[1] + ring.rect[3]);
    const pad = 8 + 3 * Math.sin((t - ring.from) * 4);
    ctx.globalAlpha = alpha * a; ctx.strokeStyle = C.acc; ctx.lineWidth = 3;
    rrect(x0 - pad, y0 - pad, x1 - x0 + 2 * pad, y1 - y0 + 2 * pad, 16); ctx.stroke();
    ctx.globalAlpha = alpha;
  }
  ctx.restore();
  ctx.restore();
  return r;
}

// ------------------------------------------------------------------ the pointer
const TRAVEL = 20;   // capture frames the pointer takes to reach a click
function pointerAt(f) {
  if (!CLICKS.length) return null;
  let pos = [CLICKS[0].x - 160, CLICKS[0].y + 140];
  let press = 0;
  for (const c of CLICKS) {
    if (f < c.frame - TRAVEL) break;
    const p = ease((f - (c.frame - TRAVEL)) / TRAVEL);
    pos = [lerp(pos[0], c.x, p), lerp(pos[1], c.y, p)];
    if (f >= c.frame) { pos = [c.x, c.y]; press = f - c.frame; }
  }
  return { pos, press };
}
function drawPointer(r, f, t, alpha) {
  const p = pointerAt(f);
  if (!p || alpha <= 0) return;
  const [x, y] = toFilm(r, p.pos[0], p.pos[1]);
  ctx.save(); ctx.globalAlpha = alpha;
  if (p.press < 14) {
    const q = p.press / 14;
    ctx.strokeStyle = C.acc; ctx.lineWidth = 3; ctx.globalAlpha = alpha * (1 - q);
    ctx.beginPath(); ctx.arc(x, y, 10 + 30 * q, 0, Math.PI * 2); ctx.stroke(); ctx.globalAlpha = alpha;
  }
  const s = 1.25 * (p.press < 4 ? 0.9 : 1);
  ctx.translate(x, y); ctx.scale(s, s);
  ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(0, 24); ctx.lineTo(6, 18.5); ctx.lineTo(10, 27); ctx.lineTo(13.5, 25.5); ctx.lineTo(9.6, 17.2); ctx.lineTo(17, 17); ctx.closePath();
  ctx.fillStyle = '#ffffff'; ctx.strokeStyle = '#0b0710'; ctx.lineWidth = 1.6; ctx.lineJoin = 'round';
  ctx.shadowColor = 'rgba(0,0,0,0.4)'; ctx.shadowBlur = 6; ctx.shadowOffsetY = 2;
  ctx.fill(); ctx.shadowColor = 'transparent'; ctx.stroke();
  ctx.restore();
}

// ------------------------------------------------------------------ the iPad
function drawIPad(t, alpha, dx) {
  const im = still.booth; if (!im) return;
  const w = 1150, h = Math.round(w * im.height / im.width), bez = 26;
  const x = 90 + dx, y = (H - h) / 2;
  const z = 1 + 0.04 * prog(t, 38.6, 48.2);
  ctx.save(); ctx.globalAlpha = alpha;
  ctx.save(); ctx.shadowColor = 'rgba(0,0,0,0.55)'; ctx.shadowBlur = 70; ctx.shadowOffsetY = 26;
  rrect(x - bez, y - bez, w + 2 * bez, h + 2 * bez, 44); ctx.fillStyle = '#08060c'; ctx.fill(); ctx.restore();
  rrect(x - bez, y - bez, w + 2 * bez, h + 2 * bez, 44); ctx.strokeStyle = '#2a2236'; ctx.lineWidth = 2; ctx.stroke();
  rrect(x, y, w, h, 16); ctx.clip();
  const sw = im.width / z, sh = im.height / z;
  ctx.drawImage(im, (im.width - sw) * 0.3, (im.height - sh) * 0.5, sw, sh, x, y, w, h);
  ctx.restore();
}

// ------------------------------------------------------------------ the words
// Steps: the number and the step's name stand at the top of the column for as long as the step lasts.
const STEPS = [
  { n: 1, from: 4.4, to: 12.8, name: ['Add your music'] },
  { n: 2, from: 12.8, to: 29.6, name: ['Desk reads', 'every song'] },
  { n: 3, from: 29.6, to: 38.8, name: ['Get the crate file', 'to your iPad'] },
  { n: 4, from: 38.8, to: 48.2, name: ['Open it in', 'Deckie Booth'] },
];
// Captions: lines set by phrase, a few words to a line, never one word alone.
const CAPS = [
  { from: 4.8, to: 8.5, lines: ['Name your crate,', 'then add a stick,', 'a CD or a folder.'] },
  { from: 8.7, to: 12.7, lines: ['Pick the one', 'your songs are on.'], note: ['Desk reads them', 'where they are.'] },
  { from: 13.2, to: 19.2, lines: ['Tempo, key, bars', 'and vocals,', 'song by song.'] },
  { from: 19.4, to: 25.4, lines: ['Stop at any time.', 'Songs already read', 'stay in your crate.'] },
  { from: 25.6, to: 29.5, lines: ['When it’s done,', 'it tells you', 'what went in.'] },
  { from: 30.0, to: 33.9, lines: ['Export the crate file.', 'It’s small:', 'no music inside.'] },
  { from: 34.1, to: 38.7, lines: ['A stick, iCloud Drive', 'or a cable', 'gets it there.'] },
  { from: 39.2, to: 43.4, lines: ['Set the iPad', 'beside the decks.'] },
  { from: 43.6, to: 48.0, lines: ['It names the song playing', 'and shows what', 'could come next.'] },
];
const COL = 1336;
function inOut(t, a, b, d = 0.35) { return Math.min(prog(t, a, a + d), 1 - prog(t, b - d, b)); }

function drawStep(t) {
  for (const s of STEPS) {
    const a = inOut(t, s.from, s.to, 0.4);
    if (a <= 0) continue;
    ctx.save(); ctx.globalAlpha = a;
    const y = 250 + (1 - ease(prog(t, s.from, s.from + 0.5))) * 16;
    ctx.fillStyle = C.acc; ctx.beginPath(); ctx.arc(COL + 30, y - 18, 30, 0, Math.PI * 2); ctx.fill();
    ctx.font = `800 34px ${UI}`; ctx.fillStyle = C.ink; ctx.textAlign = 'center'; ctx.fillText(String(s.n), COL + 30, y - 6);
    ctx.textAlign = 'left';
    ctx.font = `600 20px ${UI}`; ctx.fillStyle = C.dim; ctx.fillText(`Step ${s.n} of 4`, COL + 78, y - 10);
    s.name.forEach((line, i) => rich(line, COL, y + 66 + i * 58, 50, C.tx, 800));
    ctx.restore();
  }
}
function drawCaption(t) {
  for (const c of CAPS) {
    const a = inOut(t, c.from, c.to);
    if (a <= 0) continue;
    ctx.save(); ctx.globalAlpha = a;
    const y0 = 520 + (1 - ease(prog(t, c.from, c.from + 0.45))) * 14;
    c.lines.forEach((line, i) => rich(line, COL, y0 + i * 52, 40, C.tx, 600));
    if (c.note) c.note.forEach((line, i) => rich(line, COL, y0 + c.lines.length * 52 + 34 + i * 40, 30, C.mut, 500));
    ctx.restore();
  }
}

function drawTitle(t) {
  const a = inOut(t, 0.2, 4.2, 0.5);
  if (a <= 0) return;
  ctx.save(); ctx.globalAlpha = a; ctx.textAlign = 'left';
  const rise = (1 - ease(prog(t, 0.2, 0.9))) * 20;
  ctx.font = `128px ${SCRIPT}`; ctx.fillStyle = C.tx;
  const w = ctx.measureText('Deckie Desk').width;
  ctx.fillText('Deckie Desk', W / 2 - w / 2, 430 + rise);
  ctx.font = `600 26px ${UI}`; ctx.fillStyle = C.mut; ctx.textAlign = 'center'; ctx.letterSpacing = '4px';
  ctx.fillText('QUICK START', W / 2, 500 + rise); ctx.letterSpacing = '0px';
  const b = prog(t, 1.0, 1.5);
  ctx.globalAlpha = a * b;
  ['From your music', 'to the booth', 'in four steps.'].forEach((line, i) => rich(line, W / 2, 640 + i * 60, 46, C.tx, 700, 'center'));
  ctx.restore();
}
function drawEnd(t) {
  const a = prog(t, 48.4, 49.0);
  if (a <= 0) return;
  ctx.save(); ctx.globalAlpha = a;
  ['Your music never leaves', 'this computer.'].forEach((line, i) => rich(line, W / 2, 480 + i * 74, 62, C.tx, 800, 'center'));
  ctx.globalAlpha = a * prog(t, 49.4, 50.0);
  rich('Know Your Crate', W / 2, 700, 36, C.mut, 700, 'center');
  ctx.restore();
}

function background(t) {
  const g = ctx.createRadialGradient(W * 0.35, H * 0.45, 100, W * 0.5, H * 0.5, W * 0.75);
  g.addColorStop(0, '#1a1129'); g.addColorStop(1, C.bg);
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
}

// ------------------------------------------------------------------ one moment
export async function seek(t) {
  const f = keyed(FRAME_KEYS, t, false);
  const img = await frameImage(f);
  background(t);
  // The window: in after the title, out to the left as the iPad comes in, gone for the end card.
  const winIn = ease(prog(t, 3.8, 4.6)), winOut = ease(prog(t, 38.6, 39.4));
  const winA = winIn * (1 - winOut);
  let r = null;
  if (winA > 0) r = drawWindow(img, t, winA, -winOut * 140 + (1 - winIn) * 40, 0.98 + 0.02 * winIn);
  const ipadA = ease(prog(t, 38.8, 39.6)) * (1 - ease(prog(t, 47.9, 48.5)));
  if (ipadA > 0) drawIPad(t, ipadA, (1 - ease(prog(t, 38.8, 39.6))) * 120);
  // The pointer shows while the DJ is clicking: the first screen to the stick, and Export.
  const ptrA = Math.max(inOut(t, 4.8, 13.4, 0.3), inOut(t, T_EXPORT - 1.4, T_EXPORT + 0.9, 0.3));
  if (r && winA > 0.99) drawPointer(r, f, t, ptrA);
  drawTitle(t);
  drawStep(t);
  drawCaption(t);
  drawEnd(t);
  return Math.round(f);
}
window.__film = { init, seek, DURATION };
