// Rasterise each script word in the film's own browser, so the drawn-in word is the same rendering as the static one.
import { chromium } from 'playwright';
import fs from 'node:fs';
const [,, fontFile, out] = process.argv;
const fontUrl = 'data:font/woff2;base64,' + fs.readFileSync(fontFile).toString('base64');
const S = 360, PAD = 90, WORDS = ['Deckie', 'you', 'your', 'You', 'Your', 'Desk', 'Booth'];
const b = await chromium.launch({ args: ['--font-render-hinting=none', '--disable-lcd-text'] });
const p = await b.newPage();
await p.setContent(`<style>@font-face{font-family:Script;src:url(${fontUrl}) format('woff2')}</style><canvas id=c></canvas>`);
await p.evaluate(() => document.fonts.load('400 100px Script', 'Deckie your You'));
const meta = {};
for (const w of WORDS) {
  const r = await p.evaluate(([w, S, PAD]) => {
    const c = document.getElementById('c'), x = c.getContext('2d');
    x.font = `400 ${S}px Script`; const m = x.measureText(w);
    const W = Math.ceil(m.actualBoundingBoxLeft + m.actualBoundingBoxRight) + PAD * 2, H = Math.ceil(m.actualBoundingBoxAscent + m.actualBoundingBoxDescent) + PAD * 2;
    c.width = W; c.height = H; x.fillStyle = '#000'; x.fillRect(0, 0, W, H);
    x.font = `400 ${S}px Script`; x.fillStyle = '#fff';
    const ox = PAD + m.actualBoundingBoxLeft, base = PAD + m.actualBoundingBoxAscent;
    x.fillText(w, ox, base);
    return { png: c.toDataURL('image/png'), w: W, h: H, ox, base, adv: m.width, space: x.measureText(' ').width };
  }, [w, S, PAD]);
  const key = { Deckie: 'deckie', Desk: 'desk', Booth: 'booth' }[w] || (w[0] === 'Y' ? 'cap_' : 'low_') + w.toLowerCase();
  fs.writeFileSync(`${out}/${key}.png`, Buffer.from(r.png.split(',')[1], 'base64'));
  meta[key] = { word: w, space: r.space, w: r.w, h: r.h, ox: r.ox, base: r.base, adv: r.adv, S };
}
fs.writeFileSync(`${out}/meta.json`, JSON.stringify(meta, null, 1));
console.log(JSON.stringify(meta));
await b.close();
