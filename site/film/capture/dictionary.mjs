import { chromium } from 'playwright';
const [,, base, out] = process.argv;
const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 1280, height: 600 }, deviceScaleFactor: 2, reducedMotion: 'reduce' });
// the word of the day follows the date, so the capture pins the clock
await ctx.addInitScript(() => { const D = Date, fixed = new D(2026, 10, 12, 12).getTime(); window.Date = class extends D { constructor(...a) { super(...(a.length ? a : [fixed])); } static now() { return fixed; } }; });
const p = await ctx.newPage();
await p.goto(base + '/dictionary/', { waitUntil: 'load' }); await p.waitForTimeout(900);
await p.screenshot({ path: `${out}/d_top.png` });
console.log('word of the day text:', await p.evaluate(() => (document.querySelector('[class*=feature], [class*=pinned], [id*=today]') || {}).innerText?.slice(0, 80)));
const q = await p.$('input[type=search]');
const word = 'echo';
for (let i = 1; i <= word.length; i++) { await q.fill(word.slice(0, i)); await p.waitForTimeout(250); }
await p.evaluate(() => { const i = document.querySelector('input[type=search]'); scrollTo(0, i.getBoundingClientRect().top + scrollY - 90); }); await p.waitForTimeout(500);
await p.screenshot({ path: `${out}/d_echo.png` });
console.log(JSON.stringify(await p.evaluate(() => { const c = document.getElementById('echo-out'); const r = (e) => { if (!e) return null; const b = e.getBoundingClientRect(); return [Math.round(b.left * 2), Math.round(b.top * 2), Math.round(b.width * 2), Math.round(b.height * 2)]; };
  return { card: r(c), word: r(c.querySelector('.dx-word')), def: r(c.querySelector('.dx-def')), dj: r(c.querySelector('.dx-dj')), input: r(document.querySelector('input[type=search]')), shown: [...document.querySelectorAll('.dx-card')].filter(e => e.offsetParent && !e.hidden).length }; })));
await b.close();
