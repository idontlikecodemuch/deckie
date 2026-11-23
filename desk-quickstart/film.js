// Deckie Desk's quick start (D46): a pure function of time. `await seek(t)` paints the moment t (in seconds).
// The picture of Desk is the real Windows and Linux window (desk-web, unchanged) captured frame by frame by
// capture/live.mjs while the real engine read generated songs; this file only frames it, moves the camera, draws the
// pointer where the capture clicked, and sets the captions. The iPad is a picture of Deckie on the iPad simulator, made
// for this film (capture/ipad.sh), or the site's own still when there is none.
// The plan it follows is storyboard.md. The look is the explainer film's (site/film): the booth's colours, Inter, and
// Pacifico for "you", "your" and "Deckie" only.

const W = 1920, H = 1080;
const C = { bg: '#0f0a17', bg2: '#1c1036', card: '#1d1530', line: '#30254a', tx: '#f2edf9', mut: '#ab9fc2', dim: '#76698f', acc: '#b490ff', ink: '#160f22' };
const UI = 'Inter', SCRIPT = 'Pacifico';
export const DURATION = 57.6;

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
  const times = MARKS.times || [];
  // The frame at a moment of the page's clock (Booth's stretch keeps real time, so its frames are not evenly spaced).
  const frameAt = (ms) => { let i = 0; while (i < times.length - 1 && times[i] < ms) i++; return i; };
  const runLen = F['run-finished'] - F['run-started'];
  const named = F['booth-named'];
  FRAME_KEYS = [
    [0, F['first-screen']],
    [3.6, F['first-screen']],
    [5.4, F['first-screen'] + 18],                 // the first screen, still a moment; the pointer comes in
    [7.8, F['add-drive'] + 4],                     // the name typed, Add drive clicked: the capture's own pace
    [8.8, F['drive-list'] + 6],
    [11.0, F['drive-list'] + 22],                  // the list held at half speed while the caption is read
    [11.8, F['choose-stick'] + 6],
    [12.4, F['run-started'] + 4],
    [22.4, F['run-started'] + runLen],             // the whole run in ten seconds
    [23.0, F['finished']],
    [26.4, F['finished'] + 60],
    [26.4 + 0.01, F['scroll']],                    // the scroll down to the buttons, Export and the box: real time
    [T_EXPORT = 26.4 + (F['export'] - F['scroll']) / 30, F['export']],
    [T_EXPORTED = 26.4 + (F['exported'] - F['scroll']) / 30, F['exported']],
    [36.0, F['exported'] + 74],
    // Booth: the crate's songs, the switch clicked, Desk getting the crate ready (shortened), then real time.
    [36.01, F['see-songs'] + 12],
    [45.0, F['see-songs'] + 12],
    [T_BOOTH = 46.4, F['booth']],
    [47.4, named],
    [DURATION, frameAt((times[named] || 0) + (DURATION - 47.4) * 1000)],
  ];
  const full = [640, 400, 1];
  const stop = mk('run-started').rect, leave = mk('run-started').leave || stop;
  const box = mk('exported').box || mk('exported').rect;
  const mid = (r) => [r[0] + r[2] / 2, r[1] + r[3] / 2];
  const pick = mk('drive-list').rect || [384, 250, 512, 300];
  const stage = [640, 330, 1.3];                                   // the run's top half: title, count, the song on stage
  // Stop at the top right and the line under the count ("You can stop at any time…"), together
    // Stop and the whole line under the count ("…You can stop at any time: songs already read stay in your crate.").
  const atStop = [640, (stop[1] + leave[1] + leave[3]) / 2, Math.min(1.3, 1280 / (leave[2] + 100))];
  CAM_KEYS = [
    [0, full], [4.0, full],
    [5.0, [640, 470, 1.45]], [7.2, [640, 470, 1.45]],  // the name and the three ways
    [8.2, full], [8.8, full],
    [9.6, [...mid(pick), 1.6]], [11.8, [...mid(pick), 1.6]],      // Add a drive's list
    [12.4, full], [12.8, full],
    [13.8, stage], [17.6, stage],
    [18.6, atStop], [22.4, atStop],
    [23.2, full], [Math.max(30.2, T_EXPORTED + 0.3), full],
    [Math.max(31.2, T_EXPORTED + 1.3), [mid(box)[0], mid(box)[1], 1.5]], [36.0, [mid(box)[0], mid(box)[1], 1.5]],
    [36.01, full], [48.6, full],

  ];
  // Stop and the line that says it keeps what was read, and the iPad box, ringed while their captions show.
  RINGS = [{ from: 18.6, to: 22.4, rect: stop },
           { from: Math.max(31.4, T_EXPORTED + 1.5), to: 35.8, rect: box }];
  await Promise.all([document.fonts.load(`800 40px ${UI}`), document.fonts.load(`400 40px ${UI}`), document.fonts.load(`40px ${SCRIPT}`),
    loadStill('booth', opts.booth), loadStill('icon', opts.icon), loadWords(opts.words)]);
}
let T_BOOTH = 46.4;
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
  const z = 1 + 0.04 * prog(t, 35.8, 45.0);
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
  { n: 1, from: 3.8, to: 12.0, name: ['Add your music'] },
  { n: 2, from: 12.0, to: 26.4, name: ['Desk reads', 'every song'] },
  { n: 3, from: 26.4, to: 36.0, name: ['Get the crate file', 'to your iPad'] },
  { n: 4, from: 36.0, to: 45.0, name: ['Open it', 'in Deckie'] },
  // Not a fifth step: the way for a DJ with no iPad. Its label stands where "Step n of 4" does, with no number.
  { n: 0, label: 'No iPad?', from: 45.0, to: 54.6, name: ['Switch Desk', 'to Booth'] },
];
// Captions: lines set by phrase, a few words to a line, never one word alone, each sentence on a new line.
const CAPS = [
  { from: 4.2, to: 8.2, lines: ['Name your crate,', 'then add a stick,', 'a CD or a folder.'] },
  { from: 8.4, to: 11.9, lines: ['Pick the one', 'your songs are on.'], note: ['Desk reads them', 'where they are.'] },
  { from: 12.4, to: 17.6, lines: ['Tempo, key and bars,', 'song by song.'] },
  { from: 17.8, to: 22.6, lines: ['Stop at any time.', 'Songs already read', 'stay in your crate.'] },
  { from: 22.8, to: 26.3, lines: ['When it’s done,', 'it tells you', 'what went in.'] },
  { from: 26.8, to: 30.8, lines: ['Export the crate file.', 'It’s small:', 'no music inside.'] },
  { from: 31.0, to: 35.9, lines: ['iCloud Drive, a stick', 'or a cable', 'gets it there.'], note: ['On a Mac,', 'AirDrop too.'] },
  { from: 36.4, to: 40.4, lines: ['Set the iPad', 'beside the decks.'], note: ['Open the crate file', 'from the Files app.'] },
  { from: 40.6, to: 44.9, lines: ['It names the song playing', 'and shows what', 'could come next.'] },
  { from: 45.4, to: 48.8, lines: ['Click Booth', 'at the top', 'of the window.'] },
  { from: 49.0, to: 54.4, lines: ['Desk listens', 'through the microphone', 'and names the song.'], note: ['The picks beside it', 'are the iPad’s own.'] },
];
const COL = 1336;
function inOut(t, a, b, d = 0.35) { return Math.min(prog(t, a, a + d), 1 - prog(t, b - d, b)); }

function drawStep(t) {
  for (const s of STEPS) {
    const a = inOut(t, s.from, s.to, 0.4);
    if (a <= 0) continue;
    ctx.save(); ctx.globalAlpha = a;
    const y = 250 + (1 - ease(prog(t, s.from, s.from + 0.5))) * 16;
    ctx.textAlign = 'left';
    if (s.n) {
      ctx.fillStyle = C.acc; ctx.beginPath(); ctx.arc(COL + 30, y - 18, 30, 0, Math.PI * 2); ctx.fill();
      ctx.font = `800 34px ${UI}`; ctx.fillStyle = C.ink; ctx.textAlign = 'center'; ctx.fillText(String(s.n), COL + 30, y - 6);
      ctx.textAlign = 'left';
      ctx.font = `600 20px ${UI}`; ctx.fillStyle = C.dim; ctx.fillText(`Step ${s.n} of 4`, COL + 78, y - 10);
    } else {
      ctx.font = `700 26px ${UI}`; ctx.fillStyle = C.acc; ctx.fillText(s.label, COL, y - 8);
    }
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
  const a = inOut(t, 0.2, 3.6, 0.5);
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
// ------------------------------------------------------------------ the brand frame
// The close, as the site's explainer film closes (site/film/film.js, the name and the tagline): Deckie's icon, the name
// written on stroke by stroke in the script face, then "Know Your Crate" with "Your" written in. The pen paths are the
// site film's time maps (site/film/words: words.json, and the *_map.png files strokes.py makes there): for every pixel
// of the word, the moment the pen passes it; a word at progress p shows the pixels already passed, so at p = 1 it is
// the font's own rendering.
const WORDS = {};
async function loadWords(dir) {
  if (!dir) return;
  try {
    const meta = await fetch(`${dir}/words.json`).then((r) => r.json());
    await Promise.all(['deckie', 'cap_your'].map(async (key) => {
      const m = meta[key], im = new Image(); im.src = `${dir}/${key}_map.png`; await im.decode();
      const c = document.createElement('canvas'); c.width = m.w; c.height = m.h;
      const x = c.getContext('2d', { willReadFrequently: true }); x.drawImage(im, 0, 0);
      const d = x.getImageData(0, 0, m.w, m.h).data, n = m.w * m.h;
      const tm = new Float32Array(n), cov = new Uint8Array(n);
      for (let i = 0; i < n; i++) { tm[i] = (d[i * 4] * 256 + d[i * 4 + 1]) / 65535; cov[i] = d[i * 4 + 2]; }
      WORDS[key] = { ...m, tm, cov, canvas: c, cx: x };
    }));
  } catch (e) { /* no maps: the name fades in instead */ }
}
const SOFT = 0.035;                          // how soft the pen's leading edge is, as a share of the whole word
const hexRgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
/// One script word from its time map, its text origin at (x, base), written to progress p (0 to 1); its advance.
function writtenWord(key, x, base, size, color, p) {
  const w = WORDS[key];
  if (!w) return 0;
  const s = size / w.S;
  if (p > 0) {
    const [r, g, b] = hexRgb(color), img = w.cx.createImageData(w.w, w.h), d = img.data, edge = Math.min(p, 1) * (1 + SOFT);
    for (let i = 0; i < w.w * w.h; i++) {
      const c = w.cov[i]; if (!c) continue;
      const a = p >= 1 ? 1 : (edge - w.tm[i]) / SOFT;
      if (a <= 0) continue;
      const o = i * 4; d[o] = r; d[o + 1] = g; d[o + 2] = b; d[o + 3] = a >= 1 ? c : c * a;
    }
    w.cx.putImageData(img, 0, 0);
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(w.canvas, x - w.ox * s, base - w.base * s, w.w * s, w.h * s);
  }
  return w.adv * s;
}
const BRAND = { from: 54.7, icon: 54.8, name: 55.05, nameDur: 1.3, tag: 56.1, your: 56.25, yourDur: 0.6 };
function drawBrand(t) {
  if (t < BRAND.from) return;
  ctx.save();
  // The icon: in with a small rise and scale.
  const ki = ease(prog(t, BRAND.icon, BRAND.icon + 0.6)), im = still.icon;
  if (im && ki > 0) {
    const size = 176 * (0.92 + 0.08 * ki), x = W / 2 - size / 2, y = 228 + (1 - ki) * 24;
    ctx.globalAlpha = ki;
    ctx.save(); ctx.shadowColor = 'rgba(0,0,0,0.5)'; ctx.shadowBlur = 50; ctx.shadowOffsetY = 18;
    rrect(x, y, size, size, size * 0.225); ctx.fillStyle = C.bg; ctx.fill(); ctx.restore();
    ctx.save(); rrect(x, y, size, size, size * 0.225); ctx.clip(); ctx.drawImage(im, x, y, size, size); ctx.restore();
  }
  // The name, written on.
  ctx.globalAlpha = 1;
  const nameSize = 200, dk = WORDS.deckie;
  if (dk) writtenWord('deckie', W / 2 - dk.adv * nameSize / dk.S / 2, 640, nameSize, C.tx, prog(t, BRAND.name, BRAND.name + BRAND.nameDur));
  else { ctx.globalAlpha = prog(t, BRAND.name, BRAND.name + 0.6); rich('Deckie', W / 2, 640, nameSize / 1.08, C.tx, 400, 'center'); }
  // The tagline: "Know" and "Crate" in Inter, "Your" written in, in the accent.
  const kt = ease(prog(t, BRAND.tag, BRAND.tag + 0.5));
  if (kt > 0) {
    const size = 54, y = 760 + (1 - kt) * 18, yr = WORDS.cap_your, ss = size * 1.08;
    ctx.globalAlpha = kt; ctx.font = `700 ${size}px ${UI}`; ctx.letterSpacing = `${-0.02 * size}px`; ctx.textBaseline = 'alphabetic'; ctx.textAlign = 'left';
    const know = 'Know ', crate = ' Crate';
    const wk = ctx.measureText(know).width, wc = ctx.measureText(crate).width, wy = yr ? yr.adv * ss / yr.S : ctx.measureText('Your').width;
    let x = W / 2 - (wk + wy + wc) / 2;
    ctx.fillStyle = C.tx; ctx.fillText(know, x, y); x += wk;
    if (yr) { ctx.globalAlpha = 1; writtenWord('cap_your', x, y + size * 0.02, ss, C.acc, prog(t, BRAND.your, BRAND.your + BRAND.yourDur)); ctx.globalAlpha = kt; }
    else { ctx.font = `${Math.round(ss)}px ${SCRIPT}`; ctx.fillStyle = C.acc; ctx.fillText('Your', x, y); ctx.font = `700 ${size}px ${UI}`; }
    x += wy;
    ctx.font = `700 ${size}px ${UI}`; ctx.fillStyle = C.tx; ctx.fillText(crate, x, y);
    ctx.letterSpacing = '0px';
  }
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
  // The window: in after the title, out to the left as the iPad comes in, back for Booth, gone for the brand frame.
  const winIn = ease(prog(t, 3.2, 4.0)), winOut = ease(prog(t, 35.6, 36.4));
  const winBack = ease(prog(t, 44.8, 45.6)), winEnd = ease(prog(t, 54.4, 55.0));
  const first = winIn * (1 - winOut), second = winBack * (1 - winEnd);
  const winA = Math.max(first, second);
  let r = null;
  if (first > 0) r = drawWindow(img, t, first, -winOut * 140 + (1 - winIn) * 40, 0.98 + 0.02 * winIn);
  else if (second > 0) r = drawWindow(img, t, second, (1 - winBack) * 140, 0.98 + 0.02 * winBack);
  const ipadA = ease(prog(t, 36.0, 36.8)) * (1 - ease(prog(t, 44.6, 45.2)));
  if (ipadA > 0) drawIPad(t, ipadA, (1 - ease(prog(t, 36.0, 36.8))) * 120);
  // The pointer shows while the DJ is clicking: the first screen to the stick, Export, and the Booth switch.
  const ptrA = Math.max(inOut(t, 4.2, 12.6, 0.3), inOut(t, T_EXPORT - 1.4, T_EXPORT + 0.9, 0.3), inOut(t, 45.6, T_BOOTH + 0.8, 0.3));
  if (r && winA > 0.99) drawPointer(r, f, t, ptrA);
  drawTitle(t);
  drawStep(t);
  drawCaption(t);
  drawBrand(t);
  return Math.round(f);
}
window.__film = { init, seek, DURATION };
