import { chromium } from 'playwright';
const [,, url, out] = process.argv;
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 2, colorScheme: 'dark' });
await p.goto(url); await p.waitForSelector('article.term');
await p.screenshot({ path: `${out}/v_top.png` });
await p.click('button.chip[data-g="moves"]'); await p.waitForTimeout(200);
await p.screenshot({ path: `${out}/v_moves.png` });
await p.click('button.chip[data-g="moves"]');
const word = 'echo out';
for (let i = 1; i <= word.length; i++) {
  await p.fill('#q', word.slice(0, i)); await p.waitForTimeout(120);
  await p.screenshot({ path: `${out}/v_type_${String(i).padStart(2, '0')}.png` });
}
await p.fill('#q', 'crate file'); await p.waitForTimeout(150);
await p.screenshot({ path: `${out}/v_cratefile.png` });
await p.fill('#q', 'pitch fader'); await p.waitForTimeout(150);
await p.screenshot({ path: `${out}/v_pitch.png` });
console.log(await p.textContent('#count'));
await b.close();
