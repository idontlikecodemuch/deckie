// Pictures of the quick start where a DJ meets it (D46): Desk's Windows and Linux window (the pages in desk-web/,
// unchanged) in headless Chrome, talking to the real engine with fresh scratch storage, so the first screen offers the
// card. It also checks the card's ways out, and says what it found:
//   card.png      the first screen with the card (the film can play)
//   menu.png      the ⋯ menu, with "Watch the quick start"
//   player.png    the player, a few seconds into the film
//   words.png     the first screen when the web view says it cannot play the film: the poster and the steps in words
//   words-player.png  the player after the film failed while playing: the steps, no dead player
//   hidden.png    the first screen after Hide, and again after the engine is started anew on the same storage
//
//   node card.mjs --engine <deckie-desk-engine> --pages <desk-web folder> --work <scratch folder> [--w 1280 --h 800]
//
// Nothing is sent over the network and nothing of a DJ's is read: the engine's storage and its view of DJ programs
// are scratch folders, and lookups are off.
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync, rmSync, readFileSync, existsSync } from "node:fs";
import { createInterface } from "node:readline";

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf("--" + k); return i >= 0 ? args[i + 1] : d; };
const ENGINE = opt("engine"), PAGES = opt("pages"), WORK = opt("work");
const W = +opt("w", 1280), H = +opt("h", 800);
const CHROME = opt("chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome");
if (!ENGINE || !PAGES || !WORK) { console.error("usage: node card.mjs --engine <engine> --pages <desk-web> --work <folder>"); process.exit(2); }
const OUT = `${WORK}/card`;
rmSync(`${WORK}/card-home`, { recursive: true, force: true });
for (const d of [OUT, `${WORK}/card-home`, `${WORK}/card-dj`, `${WORK}/card-chrome`]) mkdirSync(d, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const failures = [];
const check = (ok, what) => { console.error(`${ok ? "ok  " : "FAIL"} ${what}`); if (!ok) failures.push(what); };

// ---- the engine, as the window starts it
let engine = null, fromEngine = [];
function startEngine() {
  fromEngine = [];
  engine = spawn("nice", ["-n", "19", ENGINE], { stdio: ["pipe", "pipe", "ignore"], env: Object.assign({}, process.env, {
    DECKIE_DESK_HOME: `${WORK}/card-home`, DECKIE_DJ_HOME: `${WORK}/card-dj`, DECKIE_LOOKUP_OFF: "1", DECKIE_NO_BOXES: "1",
    DECKIE_DESK_COMPUTER: "other" }) });
  createInterface({ input: engine.stdout }).on("line", (l) => fromEngine.push(l));
}

// ---- Chrome
const PORT = 9300 + Math.floor(Math.random() * 90);
const chrome = spawn("nice", ["-n", "19", CHROME, "--headless=new", `--remote-debugging-port=${PORT}`, `--user-data-dir=${WORK}/card-chrome`,
  "--no-first-run", "--no-default-browser-check", "--hide-scrollbars", "--force-color-profile=srgb", "--disable-extensions",
  "--mute-audio", "--autoplay-policy=no-user-gesture-required", "--disable-sync", "--disable-background-networking",
  "--disable-component-update", "--no-pings", `--window-size=${W},${H}`, "about:blank"], { stdio: ["ignore", "ignore", "ignore"] });
process.on("exit", () => { try { chrome.kill(); } catch (e) {} try { engine && engine.kill(); } catch (e) {} });
for (const s of ["uncaughtException", "unhandledRejection"]) process.on(s, (e) => { console.error(e); process.exit(1); });
let ws;
for (let i = 0; i < 100 && !ws; i++) {
  try { const t = (await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json()).find((x) => x.type === "page"); if (t) ws = new WebSocket(t.webSocketDebuggerUrl); } catch (e) {}
  if (!ws) await sleep(200);
}
await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
let id = 0; const waiting = new Map(); const fromPage = [];
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.id && waiting.has(m.id)) { const [r, j] = waiting.get(m.id); waiting.delete(m.id); m.error ? j(new Error(JSON.stringify(m.error))) : r(m.result); return; }
  if (m.method === "Runtime.bindingCalled" && m.params.name === "__deskSend") fromPage.push(m.params.payload);
  else if (m.method === "Runtime.exceptionThrown") { console.error("page exception:", JSON.stringify(m.params.exceptionDetails).slice(0, 300)); failures.push("page exception"); }
};
const cdp = (method, params = {}) => new Promise((r, j) => { const i = ++id; waiting.set(i, [r, j]); ws.send(JSON.stringify({ id: i, method, params })); });
const js = async (expr) => { const r = await cdp("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true }); if (r.exceptionDetails) throw new Error(JSON.stringify(r.exceptionDetails).slice(0, 400)); return r.result.value; };
await cdp("Runtime.enable"); await cdp("Page.enable");
await cdp("Runtime.addBinding", { name: "__deskSend" });
await cdp("Emulation.setDeviceMetricsOverride", { width: W, height: H, deviceScaleFactor: 2, mobile: false });
await cdp("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "dark" }] });

// The window's shell, as live.mjs gives it: the page's messages to the engine, the engine's lines back.
const SHELL = `(function(){ const s = { onmessage: null, engine: "live" }; s.send = (t) => window.__deskSend(String(t));
  window.deckieShell = s; window.__feed = (lines) => { for (const l of lines) { try { s.onmessage && s.onmessage(l); } catch (e) { console.error(e); } } }; })();`;
let pump = null;
/// The window opened anew: a fresh engine on the same storage (its first message is what the page draws from), and the
/// pages loaded with `extraScript` run first.
async function open(extraScript = "") {
  if (pump) clearInterval(pump);
  if (engine) { engine.stdin.end(); await sleep(300); engine.kill(); }
  startEngine();
  const sid = await cdp("Page.addScriptToEvaluateOnNewDocument", { source: SHELL + extraScript });
  await cdp("Page.navigate", { url: "file://" + PAGES.replace(/\/$/, "") + "/index.html" });
  pump = setInterval(async () => {
    while (fromPage.length) { const t = fromPage.shift(); try { const m = JSON.parse(t); if (m.type && m.type.startsWith("shell.")) continue; } catch (e) {} engine.stdin.write(t + "\n"); }
    if (fromEngine.length) { const lines = fromEngine.splice(0); try { await js(`__feed(${JSON.stringify(lines)})`); } catch (e) {} }
  }, 30);
  for (let i = 0; i < 100 && !(await js("!!(window.desk && document.getElementById('add-label').textContent)").catch(() => false)); i++) await sleep(100);
  await sleep(600);
  await cdp("Page.removeScriptToEvaluateOnNewDocument", { identifier: sid.identifier });
}
const shot = async (name) => writeFileSync(`${OUT}/${name}`, Buffer.from((await cdp("Page.captureScreenshot", { format: "png" })).data, "base64"));
const state = () => js("window.desk.quickStart.state()");
const click = (sel) => js(`document.querySelector(${JSON.stringify(sel)}).click()`);

// 1. A Desk never opened: the card, with the poster and the play button.
await open();
let s = await state();
check(s.offered && s.mode === "film" && s.player, `the first screen offers the card with a play button (${JSON.stringify(s)})`);
check(await js("document.getElementById('qs-poster-img').naturalWidth > 0"), "the poster is drawn");
await shot("card.png");

// 2. The ⋯ menu has the quick start.
await click("#more-button"); await sleep(300);
const items = await js("[...document.querySelectorAll('#more-menu [role=menuitem]')].map(function (b) { return b.textContent; })");
check(items.includes("Watch the quick start"), `the ⋯ menu has "Watch the quick start" (${items.length} items)`);
await shot("menu.png");
await js("document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))"); await js("document.getElementById('more-menu').hidden = true");

// 3. The player: the film plays from the card.
await click("#qs-play");
for (let i = 0; i < 60 && !(await js("document.getElementById('film-video').currentTime > 3")); i++) await sleep(100);
check(await js("document.getElementById('film').open && document.getElementById('film-video').currentTime > 0"), "the film plays in the player");
await js("document.getElementById('film-video').pause()");
await shot("player.png");
await js("document.getElementById('film').close()");
check(JSON.parse(readFileSync(`${WORK}/card-home/quick-start.json`, "utf8")).played === true, "the engine remembers the film was played");

// 4. A web view that cannot play H.264 (as WebKitGTK may be): the card shows the poster and the steps, no play button.
await open("HTMLMediaElement.prototype.canPlayType = function () { return ''; };");
s = await state();
check(s.offered && s.mode === "words" && !s.player && s.steps === 4, `with no decoder the card shows the four steps, no player (${JSON.stringify(s)})`);
await shot("words.png");

// 5. The film fails while playing (a file the web view takes and cannot decode): the player turns to the steps.
await open("");
await click("#qs-play"); await sleep(400);
await js("document.getElementById('film-video').dispatchEvent(new Event('error'))"); await sleep(200);
s = await state();
check(s.mode === "words" && await js("!document.getElementById('film-words').hidden && document.getElementById('film-video').hidden"),
  "a film that errs in the player is replaced by its steps");
await shot("words-player.png");
await js("document.getElementById('film').close()");

// 6. A film file that is not there at all: found out quietly, before play.
await open("Object.defineProperty(HTMLMediaElement.prototype, 'src', { set(v) { this.setAttribute('src', String(v).replace('deckie-desk-quick-start.mp4', 'not-there.mp4')); }, get() { return this.getAttribute('src'); } });");
for (let i = 0; i < 30 && (await state()).mode !== "words"; i++) await sleep(100);
check((await state()).mode === "words", "a missing film file turns the card to the steps before play");

// 7. Hide: remembered by the engine, so a Desk opened again does not offer the card.
await open("");
await click("#qs-hide"); await sleep(400);
check(!(await state()).offered, "Hide takes the card away");
check(JSON.parse(readFileSync(`${WORK}/card-home/quick-start.json`, "utf8")).dismissed === true, "the engine remembers the card was hidden");
await open("");
check(!(await state()).offered, "Desk opened again does not offer the card");
check(await js("!document.getElementById('first').hidden"), "the first screen still shows");
await shot("hidden.png");

console.error(failures.length ? `FAILED: ${failures.length}` : "all passed");
ws.close(); chrome.kill(); engine.stdin.end();
setTimeout(() => process.exit(failures.length ? 1 : 0), 800);
