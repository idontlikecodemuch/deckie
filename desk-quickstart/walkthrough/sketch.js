// A sketch of the in-app walkthrough (option B in research AG): five boxes over the real Windows and Linux window,
// each pointing at one control. Pictures only; nothing here is built into Desk. `seek(n)` draws step n (1 to 5) over
// a frame of the quick start's capture (capture/live.mjs), so the screens are the real ones.
const W = 1920, H = 1080;
const C = { bg: '#0f0a17', card: '#241a36', line: '#3a2d55', tx: '#f2edf9', mut: '#c3b8d6', dim: '#8d80a6', acc: '#b490ff', ink: '#160f22' };
const UI = 'Inter', SCRIPT = 'Pacifico';
const canvas = document.getElementById('film');
const ctx = canvas.getContext('2d');
let MARKS, WORK, F = {}, R = {};

// The words of each step: a title and one or two sentences, then "1 of 5", Skip and Next (Done on the last).
export const STEPS = [
  { frame: () => F.typed + 25, target: () => union(R['name-field'], R['add-drive'], R.ways),
    title: 'Start with your music', body: ['Name the crate, then add the stick,', 'CD or folder your songs are on.', 'Desk reads them where they are.'] },
  { frame: () => F['drive-list'] + 30, target: () => R['choose-stick'],
    title: 'Pick one to read', body: ['Desk counts the songs first.', 'Before a long read, it asks.'] },
  { frame: () => F['run-started'] + 700, target: () => R.stop,
    title: 'Stop whenever you like', body: ['Songs already read stay in your crate.', 'Carry on later from the same place.'] },
  { frame: () => F.export - 2, target: () => R.export,
    title: 'Export the crate file', body: ['A small file with what Desk found,', 'never the music itself.'] },
  { frame: () => F.exported + 60, target: () => R.box,
    title: 'Open it in Deckie Booth', body: ['Put it on your iPad one of these ways,', 'open it in Deckie Booth, and set', 'the iPad beside the decks.'] },
];
function union(...rs) {
  rs = rs.filter(Boolean);
  const x0 = Math.min(...rs.map((r) => r[0])), y0 = Math.min(...rs.map((r) => r[1]));
  const x1 = Math.max(...rs.map((r) => r[0] + r[2])), y1 = Math.max(...rs.map((r) => r[1] + r[3]));
  return [x0, y0, x1 - x0, y1 - y0];
}
function rrect(x, y, w, h, r) {
  ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}
function rich(str, x, y, size, color, weight) {
  const re = /\b(You|you|Your|your|Deckie)\b(?!['’\w])/g; let last = 0, m, cx = x;
  const put = (s, sc) => { ctx.font = sc ? `${Math.round(size * 1.08)}px ${SCRIPT}` : `${weight} ${size}px ${UI}`; ctx.fillStyle = sc && s !== 'Deckie' ? C.acc : color; ctx.fillText(s, cx, y); cx += ctx.measureText(s).width + (sc ? size * 0.14 : 0); };
  while ((m = re.exec(str))) { if (m.index > last) put(str.slice(last, m.index), false); put(m[0], true); last = m.index + m[0].length; }
  if (last < str.length) put(str.slice(last), false);
}

export const DURATION = STEPS.length;
export async function init(o) {
  MARKS = o.marks; WORK = o.work;
  for (const m of MARKS.marks) { F[m.label] = m.frame; if (m.rect) R[m.label] = m.rect; }
  R.stop = MARKS.marks.find((m) => m.label === 'run-started').rect;
  R.export = MARKS.marks.find((m) => m.label === 'export').rect;
  R.box = MARKS.marks.find((m) => m.label === 'exported').box;
  R['add-drive'] = MARKS.marks.find((m) => m.label === 'add-drive').rect;
  R.ways = [R['add-drive'][0], R['add-drive'][1], 1280 - 2 * R['add-drive'][0], R['add-drive'][3]];
  await Promise.all([document.fonts.load(`800 40px ${UI}`), document.fonts.load(`40px ${SCRIPT}`)]);
}

export async function seek(n) {
  const s = STEPS[Math.max(1, Math.min(STEPS.length, Math.round(n))) - 1];
  const f = Math.round(s.frame());
  const im = new Image(); im.src = `file://${WORK}/frames/f${String(f).padStart(5, '0')}.jpg`; await im.decode();
  const k = H / 800;                            // the window fills the picture's height: 800 page pixels to 1080
  const top = 0, left = (W - 1280 * k) / 2;
  ctx.fillStyle = C.bg; ctx.fillRect(0, 0, W, H);
  ctx.drawImage(im, left, top, 1280 * k, 800 * k);
  // the dimmed page with the control left clear
  const t = s.target(), pad = 10;
  const [x, y, w, h] = [left + t[0] * k - pad, top + t[1] * k - pad, t[2] * k + 2 * pad, t[3] * k + 2 * pad];
  ctx.save();
  // the clear hole is drawn as a second shape of the same path (rrect starts a new path, so it is not used here)
  ctx.beginPath(); ctx.rect(0, 0, W, H);
  ctx.moveTo(x + 18, y); ctx.arcTo(x + w, y, x + w, y + h, 18); ctx.arcTo(x + w, y + h, x, y + h, 18); ctx.arcTo(x, y + h, x, y, 18); ctx.arcTo(x, y, x + w, y, 18); ctx.closePath();
  ctx.fillStyle = 'rgba(8,5,14,0.72)'; ctx.fill('evenodd');
  rrect(x, y, w, h, 18); ctx.strokeStyle = C.acc; ctx.lineWidth = 3; ctx.stroke();
  ctx.restore();
  // the box: below the control if there is room, else above
  const bw = 640, lines = s.body.length, bh = 120 + lines * 38 + 70;
  let bx = Math.max(40, Math.min(W - bw - 40, x + w / 2 - bw / 2));
  let by = y + h + 28; const below = by + bh < H - 30;
  if (!below) by = y - 28 - bh;
  ctx.save(); ctx.shadowColor = 'rgba(0,0,0,0.6)'; ctx.shadowBlur = 40; ctx.shadowOffsetY = 12;
  rrect(bx, by, bw, bh, 22); ctx.fillStyle = C.card; ctx.fill(); ctx.restore();
  rrect(bx, by, bw, bh, 22); ctx.strokeStyle = C.line; ctx.lineWidth = 1.5; ctx.stroke();
  // a small arrow to the control
  const ax = Math.max(bx + 40, Math.min(bx + bw - 40, x + w / 2));
  ctx.beginPath();
  if (below) { ctx.moveTo(ax - 14, by); ctx.lineTo(ax, by - 14); ctx.lineTo(ax + 14, by); }
  else { ctx.moveTo(ax - 14, by + bh); ctx.lineTo(ax, by + bh + 14); ctx.lineTo(ax + 14, by + bh); }
  ctx.fillStyle = C.card; ctx.fill();
  ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
  ctx.font = `600 18px ${UI}`; ctx.fillStyle = C.dim; ctx.fillText(`${STEPS.indexOf(s) + 1} of ${STEPS.length}`, bx + 32, by + 44);
  rich(s.title, bx + 32, by + 92, 34, C.tx, 800);
  s.body.forEach((line, i) => rich(line, bx + 32, by + 140 + i * 38, 25, C.mut, 500));
  // Skip and Next
  const fy = by + bh - 62, last = STEPS.indexOf(s) === STEPS.length - 1;
  ctx.font = `600 22px ${UI}`; ctx.fillStyle = C.mut; ctx.fillText('Skip', bx + 32, fy + 32);
  const label = last ? 'Done' : 'Next'; const lw = ctx.measureText(label).width + 52;
  rrect(bx + bw - 32 - lw, fy, lw, 46, 23); ctx.fillStyle = C.acc; ctx.fill();
  ctx.fillStyle = C.ink; ctx.font = `700 22px ${UI}`; ctx.fillText(label, bx + bw - 32 - lw + 26, fy + 31);
  return f;
}
window.__film = { init, seek, DURATION };
