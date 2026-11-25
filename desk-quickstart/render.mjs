// Renders the quick start: film.html in headless Chrome, one frame at a time (film.js's seek), each frame handed to
// ffmpeg. Silent: the film has no sound track.
//
//   node render.mjs --work <capture folder> --out <file.mp4>            the whole film, 1920 by 1080, 30 frames a second
//   node render.mjs --work <capture folder> --stills <folder> --at 2,6,10   pictures of single moments (PNG)
//   node render.mjs --work <capture folder> --page walkthrough/sketch.html --stills <folder> --at 1,2,3,4,5
//   options: --from <s> --to <s> (a part only), --crf 20, --chrome <path>
import { spawn } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf("--" + k); return i >= 0 ? args[i + 1] : d; };
const HERE = dirname(fileURLToPath(import.meta.url));
const WORK = resolve(opt("work", ""));
const OUT = opt("out"), STILLS = opt("stills"), AT = opt("at");
const CHROME = opt("chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome");
const FPS = 30, CRF = opt("crf", "20");
if (!opt("work") || (!OUT && !STILLS)) { console.error("usage: node render.mjs --work <folder> (--out <mp4> | --stills <folder> --at 1,2)"); process.exit(2); }
const marks = JSON.parse(readFileSync(`${WORK}/marks.json`, "utf8"));
// The iPad: the picture capture/ipad.sh made of Deckie on the iPad simulator, else the site's own still (older).
const booth = opt("ipad", existsSync(`${WORK}/ipad.png`) ? `${WORK}/ipad.png` : resolve(HERE, "../site/assets/booth-listen.jpg"));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const PORT = 9800 + Math.floor(Math.random() * 150);
const chrome = spawn("nice", ["-n", "19", CHROME, "--headless=new", `--remote-debugging-port=${PORT}`,
  `--user-data-dir=${WORK}/chrome-render`, "--no-first-run", "--no-default-browser-check", "--hide-scrollbars",
  "--force-color-profile=srgb", "--allow-file-access-from-files", "--disable-extensions", "--mute-audio",
  "--disable-background-networking", "--disable-component-update", "--disable-sync", "--window-size=1920,1080", "about:blank"],
  { stdio: ["ignore", "ignore", "pipe"] });
chrome.stderr.on("data", () => {});
process.on("exit", () => { try { chrome.kill(); } catch (e) {} });
for (const s of ["uncaughtException", "unhandledRejection"]) process.on(s, (e) => { console.error(e); process.exit(1); });

let ws;
for (let i = 0; i < 100 && !ws; i++) {
  try { const t = (await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json()).find((x) => x.type === "page"); if (t) ws = new WebSocket(t.webSocketDebuggerUrl); } catch (e) {}
  if (!ws) await sleep(200);
}
await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
let id = 0; const waiting = new Map();
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.id && waiting.has(m.id)) { const [r, j] = waiting.get(m.id); waiting.delete(m.id); m.error ? j(new Error(JSON.stringify(m.error))) : r(m.result); }
  else if (m.method === "Runtime.exceptionThrown") console.error("page exception:", JSON.stringify(m.params.exceptionDetails).slice(0, 500));
  else if (m.method === "Runtime.consoleAPICalled" && m.params.type === "error") console.error("page:", m.params.args.map((a) => a.value || a.description).join(" "));
};
const cdp = (method, params = {}) => new Promise((r, j) => { const i = ++id; waiting.set(i, [r, j]); ws.send(JSON.stringify({ id: i, method, params })); });
const js = async (expr) => { const r = await cdp("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true }); if (r.exceptionDetails) throw new Error(JSON.stringify(r.exceptionDetails).slice(0, 600)); return r.result.value; };

await cdp("Runtime.enable");
await cdp("Page.enable");
await cdp("Emulation.setDeviceMetricsOverride", { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
// --page walkthrough/sketch.html draws the walkthrough sketch instead (its moments are its steps, 1 to 5).
await cdp("Page.navigate", { url: "file://" + resolve(HERE, opt("page", "film.html")) });
for (let i = 0; i < 100 && !(await js("!!window.__film")); i++) await sleep(100);
// The brand frame at the close: Deckie's icon, and the script word maps the site's film writes its name from
// (site/film/words: words.json is in git; the *_map.png files are made there by strokes.py, or copied to <work>/words).
// The plain icon (no word): the iPad app's own icon carries "Booth", and Desk's film shows Deckie's icon without it.
const icon = resolve(HERE, "../deck-app/tools/icon-base1024.png");
const words = opt("words", existsSync(`${WORK}/words/deckie_map.png`) ? `${WORK}/words` : resolve(HERE, "../site/film/words"));
if (!existsSync(`${words}/words.json`)) writeFileSync(`${words}/words.json`, readFileSync(resolve(HERE, "../site/film/words/words.json")));
await js(`window.__film.init(${JSON.stringify({ marks, work: WORK, booth: "file://" + booth, icon: "file://" + icon, words: "file://" + words })})`);
const duration = await js("window.__film.DURATION");
const shot = async (format) => Buffer.from((await cdp("Page.captureScreenshot", { format, quality: format === "jpeg" ? 95 : undefined, captureBeyondViewport: false })).data, "base64");

if (STILLS) {
  mkdirSync(STILLS, { recursive: true });
  for (const t of AT.split(",").map(Number)) {
    await js(`window.__film.seek(${t})`);
    writeFileSync(`${STILLS}/t${t.toFixed(1).padStart(5, "0")}.png`, await shot("png"));
  }
  console.error(`stills: ${AT}`);
} else {
  const from = +opt("from", 0), to = +opt("to", duration);
  const ff = spawn("nice", ["-n", "19", "ffmpeg", "-loglevel", "error", "-y", "-f", "image2pipe", "-framerate", String(FPS), "-c:v", "mjpeg", "-i", "-",
    "-c:v", "libx264", "-preset", "slow", "-crf", CRF, "-pix_fmt", "yuv420p", "-threads", "2", "-movflags", "+faststart", OUT], { stdio: ["pipe", "inherit", "inherit"] });
  const n = Math.round((to - from) * FPS);
  for (let k = 0; k < n; k++) {
    await js(`window.__film.seek(${from + k / FPS})`);
    const buf = await shot("jpeg");
    if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once("drain", r));
    if (k % 150 === 0) console.error(`frame ${k} of ${n}`);
  }
  ff.stdin.end();
  await new Promise((r) => ff.on("exit", r));
  console.error(`wrote ${OUT}: ${n} frames`);
}
ws.close();
process.exit(0);
