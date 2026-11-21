// The listening mode of Deckie Desk's window (research booth-in-desk, step 1: hearing). A switch in the top bar, for a
// crate with songs, opens it: an input chooser, a level that moves, a plain state line and one large card with the
// song the engine hears (its tempo and key from the crate, its place as time). No picks, no waves, no recording yet.
// The engine does all of it (docs/architecture/desk-protocol.md, "Listening"); this page sends what the DJ chooses and
// draws the `booth.*` events. No words and no design values of its own: words are DeskWords' (passed in as `t`), values
// desk.css's :root (read by booth.css). Leaving the mode stops the microphone; so does closing the window (the
// engine's input closes).
//
// The song shown is the engine's current named song, reading by reading: not yet the iPad's switching rule.
//
// While Desk reads music, listening waits: the mode says so and starts listening when the run ends; a run started from
// the mode leaves it, so the run screen shows.
(function () {
  "use strict";

  window.DeskBooth = function (d) {
    const { $, el, t, mmss, request } = d;
    let on = false;          // the mode is showing
    let wanted = false;      // listening is wanted (the mode is on and nothing waits)
    let waiting = false;     // the mode is on while a run goes: listening waits
    let crate = null;        // the crate the mode was opened on
    let inputs = [];
    let status = null;       // the last booth.state
    let heard = null;        // the last booth.heard, while the state says a song is named
    let silent = false;

    // ---- the switch in the top bar, before the space that pushes the rest right
    const button = el("button", { id: "booth-button", "aria-pressed": "false", hidden: true,
      on: { click: () => (on ? leave() : enter()) } });
    const bar = document.querySelector("header.bar");
    if (bar) bar.insertBefore(button, bar.querySelector(".grow"));

    // ---- the mode's screen, beside main (hidden with it by booth.css while the mode shows)
    const select = el("select", { id: "booth-input", on: { change: () => { if (on && !waiting) listen(); } } });
    const meterFill = el("span", { class: "booth-meter-fill" });
    const meter = el("div", { id: "booth-meter", class: "booth-meter", role: "meter", "aria-valuemin": "0", "aria-valuemax": "100", "aria-valuenow": "0" }, meterFill);
    const stateLine = el("p", { id: "booth-state", class: "booth-state", role: "status" });
    const silentLine = el("p", { id: "booth-silent", class: "booth-silent", hidden: true });
    const again = el("button", { id: "booth-again", class: "small", hidden: true, on: { click: () => listen() } });
    const title = el("h2", { id: "booth-song", class: "booth-song" });
    const artist = el("p", { id: "booth-artist", class: "booth-artist mut" });
    const facts = el("p", { id: "booth-facts", class: "booth-facts" });
    const card = el("div", { id: "booth-card", class: "card booth-card", "aria-live": "polite" }, title, artist, facts);
    const heading = el("h1", { id: "booth-title" });
    const leaveButton = el("button", { id: "booth-leave", class: "small", on: { click: () => leave() } });
    const inputLabel = el("span", { class: "mut booth-input-label" });
    const section = el("section", { id: "booth", class: "screen booth", hidden: true, "aria-labelledby": "booth-title" },
      el("div", { class: "booth-top" }, heading, leaveButton),
      el("div", { class: "booth-input" }, el("label", { class: "booth-input-row" }, inputLabel, select), meter),
      stateLine, silentLine, again, card);
    const main = document.querySelector("main");
    if (main && main.parentNode) main.parentNode.insertBefore(section, main.nextSibling);

    function words() {
      button.textContent = t("booth.mode");
      button.title = t("booth.modeHelp");
      leaveButton.textContent = t("booth.leave");
      inputLabel.textContent = t("booth.input");
      meter.setAttribute("aria-label", t("booth.level"));
      again.textContent = t("booth.tryAgain");
      silentLine.textContent = t("booth.silent");
    }

    function show(yes) {
      on = yes;
      document.body.classList.toggle("booth-on", yes);
      section.hidden = !yes;
      button.setAttribute("aria-pressed", String(yes));
    }

    async function enter() {
      const c = d.current();
      if (!c) return;
      crate = c.id; status = null; heard = null; silent = false;
      show(true); words(); draw();
      const r = await request("booth.inputs", null, { quiet: true });
      inputs = r.ok ? r.inputs || [] : [];
      fillInputs();
      if (!on) return;
      if (d.busy()) { waiting = true; draw(); return; }
      listen();
    }

    function fillInputs() {
      const keep = select.value;
      select.replaceChildren(...inputs.map((x) => el("option", { value: x.name, text: x.default ? t("booth.inputDefault", { name: x.name }) : x.name })));
      if (!inputs.length) select.append(el("option", { value: "", text: t("booth.noInputs") }));
      if (keep && inputs.some((x) => x.name === keep)) select.value = keep;
      select.disabled = !inputs.length;
    }

    function listen() {
      wanted = true; waiting = false; heard = null; silent = false; status = { state: "starting" };
      draw();
      request("booth.listen", { input: select.value || "" }, { quiet: true }).then((r) => {
        if (!r.ok && on) { status = { state: "error", error: { code: r.error && r.error.code === "busy" ? "busy" : (r.error && r.error.detail) || "failed" } }; draw(); }
      });
    }

    function leave() {
      if (!on) return;
      wanted = false; waiting = false;
      request("booth.stop", null, { quiet: true });
      show(false);
      d.render();
    }

    function receive(m) {
      if (!on || (m.crate && m.crate !== crate)) return;
      if (m.event === "booth.state") {
        status = m;
        if (m.state !== "listening") heard = null;
        if (m.state === "stopped" && wanted && d.busy()) waiting = true;   // a run stopped it: listening waits
        draw();
      } else if (m.event === "booth.level") {
        const pct = Math.round(Math.max(0, Math.min(1, m.meter || 0)) * 100);
        meterFill.style.width = pct + "%";
        meter.setAttribute("aria-valuenow", String(pct));
        meter.classList.toggle("clipping", (m.clipped || 0) > 0);
        if (!!m.silent !== silent) { silent = !!m.silent; draw(); }
      } else if (m.event === "booth.heard") {
        heard = m;
        drawCard();
      }
    }

    function stateText() {
      if (waiting) return t("booth.waits");
      if (!status) return t("booth.state.starting");
      if (status.state === "index") return t("booth.state.index", { crate: d.shownName(), percent: status.percent || 0 });
      if (status.state === "error") {
        const code = (status.error && status.error.code) || "other";
        const key = `booth.error.${code}`;
        return t(d.has(key) ? key : "booth.error.other", { detail: (status.error && status.error.detail) || "" });
      }
      return t(`booth.state.${status.state}`, { crate: d.shownName() });
    }

    function drawCard() {
      const named = !!heard && !!status && status.state === "listening";
      card.classList.toggle("empty", !named);
      if (!named) { title.textContent = ""; artist.textContent = ""; facts.textContent = ""; return; }
      const s = heard.song || {};
      title.textContent = s.title || "";
      artist.textContent = s.artist || "";
      const parts = [];
      if (s.bpm) parts.push(t("booth.tempo", { bpm: Math.round(s.bpm) }));
      if (s.camelot) parts.push(t("booth.key", { camelot: s.camelot }));
      parts.push(t("booth.place", { place: mmss(Math.max(0, heard.place || 0)), length: mmss(s.seconds || 0) }));
      facts.replaceChildren(...parts.map((p) => el("span", { class: "booth-fact", text: p })));
    }

    function draw() {
      if (!on) return;
      heading.textContent = t("booth.title", { crate: d.shownName() });
      stateLine.textContent = stateText();
      stateLine.classList.toggle("error", !!status && status.state === "error" && !waiting);
      again.hidden = !(status && status.state === "error" && !waiting);
      // The input is on (noSound and nothingNow, added Nov 21, are the engine's: their own words say them).
      const hearing = !!status && ["listening", "nothingHeard", "nothingNow", "noSound"].includes(status.state) && !waiting;
      // No sound coming is said by the state line itself; the silent line would say it twice.
      silentLine.hidden = !(silent && hearing && status.state !== "noSound");
      // The level shows only while the input is on.
      if (!hearing) { meterFill.style.width = "0%"; meter.setAttribute("aria-valuenow", "0"); meter.classList.remove("clipping"); }
      drawCard();
    }

    /// From desk.js's render: the switch shows for a crate with songs; another crate, or none, leaves the mode; a run
    /// started from the mode leaves it; a run that ends lets listening that waited start.
    function render(v) {
      words();
      button.hidden = !v.songsHere && !on;
      if (!on) return;
      const c = d.current();
      if (!c || c.id !== crate || !v.songsHere) { leave(); return; }
      if (v.busy && !waiting) { leave(); return; }
      if (!v.busy && waiting) { listen(); return; }
      draw();
    }

    // The window going away: the engine stops when its input closes, but say it first where the page can.
    window.addEventListener("pagehide", () => { if (on) request("booth.stop", null, { quiet: true }); });

    return { receive, render, isOn: () => on };
  };
})();
