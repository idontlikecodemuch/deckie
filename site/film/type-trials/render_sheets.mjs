import { chromium } from 'playwright';
import fs from 'node:fs';
const [,, dir, siteUrl, baseUrl] = process.argv;
const css = JSON.parse(fs.readFileSync(`${dir}/hero_css.json`, 'utf8'));
const b = await chromium.launch();
for (const [id, style] of Object.entries(css)) {
  const p = await b.newPage({ viewport: { width: 1440, height: 810 }, deviceScaleFactor: 1 });
  await p.goto(siteUrl, { waitUntil: 'domcontentloaded' }); await p.addStyleTag({ content: style });
  await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(500);
  await p.screenshot({ path: `${dir}/hero_${id}.png` }); await p.close();
}
for (const name of ['yeseva', 'playfair', 'pacifico', 'side_by_side', 'finalists']) {
  const p = await b.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
  await p.goto(`${baseUrl}/sheet_${name}.html`); await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(800);
  await p.screenshot({ path: `${dir}/out_${name}.png`, fullPage: true }); await p.close();
  console.log(name);
}
await b.close();
