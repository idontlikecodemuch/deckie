// The quick start's capture: Deckie Desk's Windows and Linux window (the pages in desk-web/, unchanged) in headless
// Chrome, talking to the real engine (core's deckie-desk-engine) on generated songs, clicked through as a DJ would,
// one picture per frame on a stepped clock. Nothing is sent over the network and nothing of a DJ's is read: the
// engine's storage, its view of DJ programs and its drives are scratch folders.
//
//   node live.mjs --engine <deckie-desk-engine> --pages <desk-web folder> --work <scratch folder>
//
// <work> must hold drives/<a folder per stand-in drive> (songs.py's songs in "Friday stick") and, for the Booth beat,
// <work>/booth/Microphone: a song of that drive as sound, which the engine plays to its listener as if the computer's
// microphone heard it (the engine's own stand-in for an input, DECKIE_BOOTH_SOUND; the input list then shows the file's
// name, "Microphone"). It writes <work>/frames/f00000.jpg onward, <work>/marks.json (what happened at which frame,
// where each click landed, in the page's own pixels, and each frame's moment on the page's clock) and
// <work>/engine.jsonl (every line the engine sent, with its time).
//
// The page's clock is stepped, a thirtieth of a second a frame, so every animation is exact. While Booth listens the
// engine hears the stand-in in real time, so from there on each frame moves the page's clock on by the real time it
// took; the film plays that stretch by those moments (marks.json `times`).
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync, readFileSync, createWriteStream, rmSync } from "node:fs";
import { createInterface } from "node:readline";

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf("--" + k); return i >= 0 ? args[i + 1] : d; };
const ENGINE = opt("engine"), PAGES = opt("pages"), WORK = opt("work");
const W = +opt("w", 1280), H = +opt("h", 800), DPR = +opt("dpr", 2), FPS = 30, STEP = 1000 / FPS;
const CRATE = opt("crate", "Gig Friday"), DRIVE = opt("drive", "Friday stick");
const CHROME = opt("chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome");
if (!ENGINE || !PAGES || !WORK) { console.error("usage: node live.mjs --engine <engine> --pages <desk-web> --work <folder>"); process.exit(2); }

const FRAMES = `${WORK}/frames`;
rmSync(FRAMES, { recursive: true, force: true });
rmSync(`${WORK}/desk-home`, { recursive: true, force: true });
for (const d of [FRAMES, `${WORK}/desk-home`, `${WORK}/dj-home`, `${WORK}/Documents`, `${WORK}/chrome-profile`]) mkdirSync(d, { recursive: true });
// The quick start's own card (D46) is hidden, as it is for a DJ who has seen it: the film does not show itself.
writeFileSync(`${WORK}/desk-home/quick-start.json`, JSON.stringify({ dismissed: true, played: true }));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- the engine, at low priority, in scratch folders, with no lookups
const engineLog = createWriteStream(`${WORK}/engine.jsonl`);
const t0 = Date.now();
const env = Object.assign({}, process.env, {
  DECKIE_DESK_HOME: `${WORK}/desk-home`, DECKIE_DJ_HOME: `${WORK}/dj-home`, DECKIE_LOOKUP_OFF: "1",
  DECKIE_DESK_COMPUTER: "other", DECKIE_DESK_JOBS: "2", DECKIE_DESK_DRIVES: `${WORK}/drives`,
  DECKIE_DESK_BIG_DRIVE_BYTES: String(4e12),           // the stand-in drives are folders on this Mac's disk
  DECKIE_BOOTH_SOUND: `${WORK}/booth/Microphone`,      // Booth's input: a song of the stick, heard as if by the microphone
});
const engine = spawn("nice", ["-n", "19", ENGINE], { stdio: ["pipe", "pipe", "pipe"], env });
engine.stderr.on("data", (d) => process.stderr.write("[engine] " + d));
const fromEngine = [];      // lines waiting for the next frame
const seenEvents = [];
let pageReady = false;
createInterface({ input: engine.stdout }).on("line", (line) => {
  engineLog.write(JSON.stringify({ at: Date.now() - t0, line }) + "\n");
  fromEngine.push(line);
  try { const m = JSON.parse(line); if (m.event) seenEvents.push(m.event); } catch (e) {}
});
const toEngine = (text) => engine.stdin.write(text + "\n");

// ---- Chrome
const PORT = 9400 + Math.floor(Math.random() * 400);
const chrome = spawn("nice", ["-n", "19", CHROME, "--headless=new", `--remote-debugging-port=${PORT}`,
  `--user-data-dir=${WORK}/chrome-profile`, "--no-first-run", "--no-default-browser-check", "--hide-scrollbars",
  "--force-color-profile=srgb", "--disable-extensions", "--disable-background-timer-throttling",
  "--disable-renderer-backgrounding", "--mute-audio", "--disable-sync", "--disable-background-networking",
  "--disable-component-update", "--no-pings", `--window-size=${W},${H}`, "about:blank"], { stdio: ["ignore", "ignore", "pipe"] });
chrome.stderr.on("data", () => {});
// Whatever happens, the Chrome and the engine started here end with this program.
process.on("exit", () => { try { chrome.kill(); } catch (e) {} try { engine.kill(); } catch (e) {} });
for (const s of ["uncaughtException", "unhandledRejection"]) process.on(s, (e) => { console.error(e); process.exit(1); });
for (const s of ["SIGINT", "SIGTERM"]) process.on(s, () => process.exit(1));
let ws;
for (let i = 0; i < 100 && !ws; i++) {
  try {
    const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
    const t = list.find((x) => x.type === "page");
    if (t) ws = new WebSocket(t.webSocketDebuggerUrl);
  } catch (e) {}
  if (!ws) await sleep(200);
}
await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
let id = 0; const waiting = new Map();
const fromPage = [];
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.id && waiting.has(m.id)) { const [r, j] = waiting.get(m.id); waiting.delete(m.id); m.error ? j(new Error(JSON.stringify(m.error))) : r(m.result); return; }
  if (m.method === "Runtime.bindingCalled" && m.params.name === "__deskSend") fromPage.push(m.params.payload);
  else if (m.method === "Runtime.consoleAPICalled" && m.params.type === "error") console.error("page:", m.params.args.map((a) => a.value || a.description).join(" "));
  else if (m.method === "Runtime.exceptionThrown") console.error("page exception:", JSON.stringify(m.params.exceptionDetails).slice(0, 400));
};
const cdp = (method, params = {}) => new Promise((r, j) => { const i = ++id; waiting.set(i, [r, j]); ws.send(JSON.stringify({ id: i, method, params })); });
const js = async (expr) => { const r = await cdp("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true }); if (r.exceptionDetails) throw new Error(JSON.stringify(r.exceptionDetails).slice(0, 500)); return r.result.value; };

// ---- the shell's part: requests starting "shell." are answered here, the rest go to the engine
const lastRequest = {};
const pageLog = createWriteStream(`${WORK}/page.jsonl`);
function shellMessage(text) {
  pageLog.write(JSON.stringify({ at: Date.now() - t0, frame, text }) + "\n");
  let m; try { m = JSON.parse(text); } catch (e) { return; }
  if (m.type) lastRequest[m.type] = m;
  if (!m.type || !m.type.startsWith("shell.")) { toEngine(text); return; }
  const reply = (fields) => fromEngine.push(JSON.stringify(Object.assign({ re: m.id, ok: true }, fields)));
  switch (m.type) {
    case "shell.ready": pageReady = true; break;
    case "shell.chooseFolder": reply({ path: m.purpose === "export" ? `${WORK}/Documents` : `${WORK}/drives/${DRIVE}` }); break;
    case "shell.chooseFile": reply({ cancelled: true }); break;
    case "shell.openFolder": reply({}); break;
    default: if (m.id != null) reply({ ok: false, error: { code: "unknown_type", detail: m.type } });
  }
}

await cdp("Runtime.enable");
await cdp("Page.enable");
await cdp("Runtime.addBinding", { name: "__deskSend" });
await cdp("Emulation.setDeviceMetricsOverride", { width: W, height: H, deviceScaleFactor: DPR, mobile: false });
await cdp("Emulation.setEmulatedMedia", { features: [{ name: "prefers-reduced-motion", value: "no-preference" }, { name: "prefers-color-scheme", value: "dark" }] });
await cdp("Page.addScriptToEvaluateOnNewDocument", { source: readFileSync(new URL("./clock.js", import.meta.url), "utf8") });
await cdp("Page.navigate", { url: "file://" + PAGES.replace(/\/$/, "") + "/index.html" });
for (let i = 0; i < 50 && (await js("document.readyState")) !== "complete"; i++) await sleep(100);

// ---- frames
let frame = 0;
const marks = [];
const times = [];          // each frame's moment on the page's clock, in milliseconds
let pageNow = 0;
let realTime = false, lastReal = 0;
const mark = (label, extra = {}) => { marks.push(Object.assign({ frame, label }, extra)); console.error(`frame ${frame}: ${label}`); };
async function tick() {
  while (fromPage.length) shellMessage(fromPage.shift());
  if (pageReady && fromEngine.length) { const lines = fromEngine.splice(0); await js(`__feed(${JSON.stringify(lines)})`); }
  // A thirtieth of a second a frame; in real time (Booth listening), the real time this frame took.
  let step = STEP;
  if (realTime) { const now = Date.now(); step = Math.max(STEP, now - lastReal); lastReal = now; }
  pageNow = await js(`__advance(${step})`);
  times.push(Math.round(pageNow));
  // The one place the pages show a folder's whole path, "The crate file is in …": the work folder's path on this
  // Mac is not for a film, so the line says only the folder's own name, "Documents". The only change to the page.
  await js(`(function(){ const e = document.getElementById('exported-text'), p = ${JSON.stringify(WORK + "/")}; if (e && e.textContent.indexOf(p) >= 0) e.textContent = e.textContent.split(p).join(''); })()`);
  const shot = await cdp("Page.captureScreenshot", { format: "jpeg", quality: 94, captureBeyondViewport: false });
  writeFileSync(`${FRAMES}/f${String(frame).padStart(5, "0")}.jpg`, Buffer.from(shot.data, "base64"));
  frame++;
}
const hold = async (n) => { for (let i = 0; i < n; i++) await tick(); };
async function until(test, max = 9000, after = 0) {
  for (let i = 0; i < max && !(await test()); i++) await tick();
  await hold(after);
}
const shown = (sel) => js(`(function(){ const e = document.querySelector(${JSON.stringify(sel)}); if (!e) return false; const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && !e.closest('[hidden]'); })()`);
async function rectOf(expr) {
  return js(`(function(){ const e = ${expr}; if (!e) return null; const r = e.getBoundingClientRect(); return [r.x, r.y, r.width, r.height]; })()`);
}
/// A real click (mouse moved, pressed, released) in the middle of the element, as a DJ's would be. It waits until
/// the element has stopped moving (a screen drawn again, or sliding in, would otherwise take the release elsewhere),
/// and presses and releases within one frame.
async function click(label, expr) {
  let r = null;
  for (let i = 0; i < 120; i++) {
    const now = await rectOf(expr);
    if (now && r && now.every((v, k) => Math.abs(v - r[k]) < 0.5)) break;
    r = now;
    await tick();
  }
  if (!r) throw new Error("nothing to click for " + label);
  const x = r[0] + r[2] / 2, y = r[1] + r[3] / 2;
  mark(label, { click: [x, y], rect: r });
  await cdp("Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
  await cdp("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "left", clickCount: 1 });
  await cdp("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button: "left", clickCount: 1 });
  await tick();
}
const q = (sel) => `document.querySelector(${JSON.stringify(sel)})`;

// 1. The first screen
await until(() => shown("#first-ways button"), 600, 0);
mark("first-screen");
await hold(45);

// 2. The new crate's name, typed over "My crate"
await click("name-field", q("#first-name"));
await js(`(function(){ const f = document.getElementById('first-name'); f.focus(); f.select(); })()`);
mark("typing");
for (const ch of CRATE) { await cdp("Input.insertText", { text: ch }); await hold(3); }
// Leaving the field commits the name (its own change event), and the screen is drawn again before the next click.
await js(`document.getElementById('first-name').blur()`);
mark("typed");
await hold(30);

// 3. Add drive, then the stick
await click("add-drive", `document.querySelectorAll('#first-ways button')[0]`);
await until(() => shown("#pick-list .pick-row"), 900, 0);
mark("drive-list", { rect: await rectOf(q("#pick")) });
await hold(40);
await click("choose-stick", `[...document.querySelectorAll('#pick-list .pick-row')].find(function (b) { return b.textContent.indexOf(${JSON.stringify(DRIVE)}) >= 0; })`);

// 4. The run, to its end
await until(() => seenEvents.includes("run.started"), 9000, 0);
await until(() => shown("#run-stop"), 300, 0);
mark("run-started", { rect: await rectOf(q("#run-stop")), leave: await rectOf(q("#run .leave")) });
await until(() => seenEvents.includes("run.finished"), 60000, 0);
mark("run-finished");
await until(() => shown("#finished-export"), 600, 0);
mark("finished", { rect: await rectOf(q("#finished-title")) });
await hold(75);

// 5. Export crate file, and the box that says how to get it to the iPad. The finished screen is taller than the
// window, so the DJ scrolls down to its buttons first, with the mouse wheel, a little each frame.
const toIPad = `document.querySelector('#finished .to-ipad')`;
async function scrollToShow(expr, margin = 30) {
  for (let i = 0; i < 300; i++) {
    const r = await rectOf(expr);
    if (!r || r[1] + r[3] <= H - margin) break;
    await cdp("Input.dispatchMouseEvent", { type: "mouseWheel", x: W / 2, y: H / 2, deltaX: 0, deltaY: Math.min(24, r[1] + r[3] - (H - margin)) });
    await tick();
  }
  await hold(8);
}
mark("scroll");
await scrollToShow(q("#finished-export"));
await hold(20);
await click("export", q("#finished-export"));
await until(() => shown("#exported"), 900, 0);
if (!(await shown("#exported"))) throw new Error("the crate file was not exported");
await hold(15);
await scrollToShow(toIPad);
mark("exported", { rect: await rectOf(q("#exported")), box: await rectOf(toIPad), then: await rectOf(q(".to-ipad-then")) });
await hold(75);

// 6. The songs
await click("see-songs", q("#finished-songs"));
await hold(45);
mark("songs");

// 7. Booth: the switch in the bar; Desk listens (the stand-in), names the song playing and shows the picks. From the
// click on, the page's clock keeps real time with the engine's listener.
await click("booth", q("#booth-button"));
realTime = true; lastReal = Date.now();
mark("booth-on");
await until(() => js(`(function(){ const e = document.getElementById('booth-song'); return !!(e && e.textContent.trim() && !e.closest('[hidden]')); })()`), 3000, 0);
mark("booth-named", { rect: await rectOf(q("#booth-song")), picks: await rectOf(`document.querySelector('.booth-picks')`) });
const namedAt = Date.now();
while (Date.now() - namedAt < 14000) await tick();
mark("booth-end");

writeFileSync(`${WORK}/marks.json`, JSON.stringify({ size: [W, H, DPR], fps: FPS, frames: frame, marks, times }, null, 1));
console.error(`done: ${frame} frames`);
ws.close();
chrome.kill();
engine.stdin.end();
setTimeout(() => process.exit(0), 1500);
