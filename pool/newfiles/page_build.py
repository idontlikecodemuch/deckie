import json
rows = json.load(open("newfiles/pool.json"))
import sys
LOCAL = "--local" in sys.argv
for r in rows:
    if "Milkshake 20" in r["title"]: r["rawbpm"] = True
    r["x"] = "(dirty)" in r["ver"].lower()
    r["dim"] = bool(r.get("grp")) and not r["rec"]
    if not LOCAL: r.pop("path", None)
nlib = sum(1 for r in rows if r["src"] == "lib"); ncand = len(rows) - nlib
import os
CLUB = json.load(open("newfiles/club.json")) if os.path.exists("newfiles/club.json") else json.load(open("newfiles/club_seed.json"))
clubdata = json.dumps(CLUB, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
data = json.dumps(rows, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
page = r'''<title>Two-Disc Pool</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@600;700&family=IBM+Plex+Sans:ital,wght@0,400;0,500;0,600;1,400&family=IBM+Plex+Mono:wght@500&display=swap">
<style>
/* Two era discs with live capacity meters and per-folder counts; rows are checkbox + text + tempo; overlaps warned at the top. */
:root{
  --bg:#f3f2ee; --surface:#ffffff; --fg:#19171a; --muted:#625c66; --line:#dcd8d3;
  --accent:#c2410c; --accent-ink:#ffffff; --sel:#fdece2; --cd1:#7c2d12; --cd2:#1e3a5f;
  --ok:#1b7f4b; --warn:#b45309; --bad:#b91c1c; --tag:#ece8e2;
  --display:"Barlow Condensed","Arial Narrow",sans-serif; --body:"IBM Plex Sans",system-ui,sans-serif; --mono:"IBM Plex Mono",ui-monospace,monospace;
}
@media (prefers-color-scheme: dark){ :root:not([data-theme="light"]){ --bg:#17151a; --surface:#211e24; --fg:#ece8ee; --muted:#a39daa; --line:#38333d; --accent:#fb923c; --accent-ink:#17151a; --sel:#3a2a22; --cd1:#fdba74; --cd2:#93c5fd; --ok:#4fcf8a; --warn:#f0a44a; --bad:#f87171; --tag:#2e2a33; color-scheme:dark } }
:root[data-theme="dark"]{ --bg:#17151a; --surface:#211e24; --fg:#ece8ee; --muted:#a39daa; --line:#38333d; --accent:#fb923c; --accent-ink:#17151a; --sel:#3a2a22; --cd1:#fdba74; --cd2:#93c5fd; --ok:#4fcf8a; --warn:#f0a44a; --bad:#f87171; --tag:#2e2a33; color-scheme:dark }
body{background:var(--bg);color:var(--fg);font-family:var(--body);font-size:15px;line-height:1.45;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));padding-block:0 48px}
.wrap{max-width:1000px;margin:0 auto}
header{padding-block:28px 10px}
h1{font-family:var(--display);font-size:clamp(34px,6vw,52px);line-height:1;margin:0 0 8px;letter-spacing:.01em;text-wrap:balance}
.lede{color:var(--muted);max-width:72ch;margin:0 0 6px}
.meters{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:10px;margin-block:12px}
.meter{background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:10px 12px}
.meter h3{font-family:var(--display);font-size:22px;margin:0;letter-spacing:.01em;display:flex;justify-content:space-between;align-items:baseline;gap:8px}
.meter h3 span{font:500 13px var(--mono);color:var(--muted)}
.meter .sub{font-size:12.5px;color:var(--muted);margin:2px 0 6px}
.meter .folders{font:500 11.5px var(--mono);color:var(--muted);margin-top:6px;line-height:1.6}
.bar{height:8px;background:var(--tag);border-radius:4px;overflow:hidden}
.bar i{display:block;height:100%;background:var(--ok);width:0;transition:width .2s}
.bar i.warn{background:var(--warn)} .bar i.bad{background:var(--bad)}
.overlap{background:var(--surface);border:1px solid var(--warn);border-radius:10px;padding:8px 12px;font-size:13px;margin-block:0 12px}
.overlap b{color:var(--warn)}
.toolbar{position:sticky;top:env(safe-area-inset-top,0px);z-index:5;background:var(--bg);padding-block:10px;border-bottom:1px solid var(--line);display:flex;flex-wrap:wrap;gap:8px;align-items:center}
.chips{display:flex;flex-wrap:wrap;gap:6px}
.chip{border:1px solid var(--line);background:var(--surface);color:var(--fg);border-radius:999px;padding:4px 11px;font:500 13px var(--body);cursor:pointer}
.chip[aria-pressed="true"]{background:var(--accent);color:var(--accent-ink);border-color:var(--accent)}
.chip:focus-visible,button:focus-visible,input:focus-visible,select:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
.search{flex:1 1 160px;min-width:0;border:1px solid var(--line);background:var(--surface);color:var(--fg);border-radius:8px;padding:6px 10px;font:14px var(--body)}
select{border:1px solid var(--line);background:var(--surface);color:var(--fg);border-radius:8px;padding:5px 8px;font:13px var(--body)}
.btn{border:1px solid var(--accent);background:var(--accent);color:var(--accent-ink);border-radius:8px;padding:6px 12px;font:600 13px var(--body);cursor:pointer}
.btn.quiet{background:var(--surface);color:var(--fg);border-color:var(--line)}
.status{font-size:12px;color:var(--muted);flex-basis:100%}
section.disc{margin-block:26px 0}
section.disc h2{font-family:var(--display);font-size:28px;margin:0 0 2px;letter-spacing:.01em}
section.disc h2 small{font:500 13px var(--mono);color:var(--muted);margin-left:8px}
section.disc>p{margin:0 0 10px;color:var(--muted);max-width:72ch}
h4.grp{font:600 12px var(--mono);letter-spacing:.08em;text-transform:uppercase;color:var(--muted);margin:16px 0 6px}
ol{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:5px}
.row{display:grid;grid-template-columns:26px minmax(0,1fr) 62px;}
body.haslocal .row{grid-template-columns:26px 30px minmax(0,1fr) 62px;gap:10px;align-items:start;background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:8px 12px}
.row.on{background:var(--sel);border-color:var(--accent)}
.row input{width:18px;height:18px;margin:3px 0 0;accent-color:var(--accent)}
.main{min-width:0}
.track{font-weight:600}
.ver{color:var(--fg);font-weight:400}
.meta{display:flex;flex-wrap:wrap;gap:4px 10px;font-size:12px;color:var(--muted);margin-top:3px;align-items:center}
.tag{font:600 10.5px var(--mono);letter-spacing:.06em;padding:1px 6px;border-radius:4px;background:var(--tag);color:var(--fg)}
.tag.hal{color:var(--accent)} .tag.x{color:var(--bad)} .tag.low{color:var(--warn)} .tag.list{color:var(--cd2)} .tag.rec{background:var(--accent);color:var(--accent-ink)} .tag.dup{color:var(--warn)} .tag.intro{color:var(--cd2)}
.pill{font:600 10.5px var(--mono);letter-spacing:.06em;padding:1px 6px;border-radius:4px;border:1px solid currentColor}
.pill.dS{color:var(--cd1)} .pill.dM{color:var(--cd2)}
.sw{border:1px solid var(--line);background:var(--surface);color:var(--muted);border-radius:999px;padding:0 8px;font:500 11px var(--body);cursor:pointer;line-height:18px}
.sw:hover{color:var(--fg);border-color:var(--fg)} .sw.ovr{color:var(--accent);border-color:var(--accent)}
.why{font-size:13px;color:var(--muted);margin-top:3px}
.bpm{font-family:var(--mono);font-size:14px;text-align:right;padding-top:3px;font-variant-numeric:tabular-nums}
.bpm small{display:block;font-size:10px;color:var(--muted);letter-spacing:.06em}
.row.hide{display:none}
.row.dim{opacity:.55} .row.dim.on{opacity:1}
.play{width:26px;height:26px;border-radius:50%;border:1px solid var(--line);background:var(--surface);color:var(--fg);font-size:11px;cursor:pointer;padding:0;margin-top:1px;line-height:1}
.play[aria-pressed="true"]{background:var(--accent);color:var(--accent-ink);border-color:var(--accent)}
.player{position:fixed;left:0;right:0;bottom:0;z-index:6;background:var(--surface);border-top:1px solid var(--line);padding:8px max(16px,env(safe-area-inset-right,0px)) calc(8px + env(safe-area-inset-bottom,0px)) max(16px,env(safe-area-inset-left,0px));display:flex;gap:12px;align-items:center;flex-wrap:wrap}
.player .np{font-size:13px;min-width:0;flex:1 1 240px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.player audio{flex:2 1 320px;min-width:0;height:36px}
body.haslocal{padding-bottom:96px}
.tabs{display:flex;gap:6px;margin:14px 0 0}
.tab{border:1px solid var(--line);background:var(--surface);color:var(--fg);border-radius:8px 8px 0 0;padding:8px 16px;font:600 14px var(--body);cursor:pointer}
.tab[aria-selected="true"]{background:var(--accent);color:var(--accent-ink);border-color:var(--accent)}
.song{margin-block:22px 0}
.song h3{font-family:var(--display);font-size:24px;margin:0 0 2px;letter-spacing:.01em}
.song h3 small{font:500 12px var(--mono);color:var(--muted);margin-left:8px}
.song>p{margin:0 0 8px;color:var(--muted);font-size:13px}
.opt{display:grid;grid-template-columns:26px minmax(0,1fr) auto;gap:10px;align-items:start;background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:8px 12px}
.opt.on{background:var(--sel);border-color:var(--accent)}
.opt input{width:18px;height:18px;margin:3px 0 0;accent-color:var(--accent)}
.opt .go{border:1px solid var(--accent);background:var(--accent);color:var(--accent-ink);border-radius:8px;padding:6px 12px;font:600 13px var(--body);text-decoration:none;white-space:nowrap}
.tag.official{color:var(--ok)} .tag.pool{color:var(--warn)} .tag.bootleg{color:var(--cd2)} .tag.free{color:var(--ok)} .tag.unv{color:var(--muted)}
.club-note{color:var(--muted);max-width:72ch;margin:8px 0 0}
details{margin-top:28px}
details summary{cursor:pointer;font-family:var(--display);font-size:24px;letter-spacing:.01em}
details summary small{font:500 13px var(--body);color:var(--muted);margin-left:8px}
details>p{color:var(--muted);margin:4px 0 10px;max-width:72ch}
@media (max-width:520px){ .row{grid-template-columns:24px minmax(0,1fr) 50px;padding:8px 10px;gap:8px} body.haslocal .row{grid-template-columns:24px 28px minmax(0,1fr) 50px} .bpm{font-size:13px} }
@media (prefers-reduced-motion: no-preference){ .row{transition:background .15s,border-color .15s} }
</style>
<div class="wrap">
<header>
  <h1>Two-Disc Pool</h1>
  <p class="lede">Everything in the folder, condensed to two MP3 CDs for Mike. <b>CD1 Singalongs</b> is anything the room sings: the classics kept as originals, and every version where the full chorus survives, pool intro edits included. <b>CD2 Mix-ins</b> is what he blends between them: house reworks where the vocal is a hook, transitions and tools, the covers, the long club mixes and the instrumental spikes. Halloween runs through both and gets an H in the file name. Inside each disc the tracks sit in eight BPM folders instead of six, so no folder holds more than about a dozen choices. Wherever you have a dance version, it takes the slot and the original is benched; the few originals kept at slow tempos are flagged <b>GET INTRO EDIT</b>, meaning a pool intro or club edit would let Mike bring them in. CD4 stays his house disc, so only five of its easiest blends are here. The ticks are my recommendation: change anything, add what E and Diana need, and the meters show whether it still fits. Greyed rows are benched duplicates of something kept, such as the plain cut where the intro version is in. The copy of this page saved in the playlist folder has play buttons and a scrubber; the published copy cannot reach the files.</p>
  <div class="meters">
    <div class="meter"><h3>CD1 &middot; Singalongs <span id="m1"></span></h3><div class="sub">Budget 690 MB, about 70 tracks. Folders:</div><div class="bar"><i id="b1"></i></div><div class="folders" id="f1"></div></div>
    <div class="meter"><h3>CD2 &middot; Mix-ins <span id="m2"></span></h3><div class="sub">Budget 690 MB, about 70 tracks. Folders:</div><div class="bar"><i id="b2"></i></div><div class="folders" id="f2"></div></div>
  </div>
  <div class="overlap" id="overlap" hidden></div>
  <div class="tabs" role="tablist"><button class="tab" type="button" role="tab" id="tab-pool" aria-selected="true" aria-controls="pooltab">Pool</button><button class="tab" type="button" role="tab" id="tab-club" aria-selected="false" aria-controls="clubtab">Club edit options</button></div>
</header>
<div id="clubtab" role="tabpanel" hidden>
  <p class="club-note">The slow originals still on the discs, each with versions a DJ can buy or download: official club remixes on stores, record-pool intro and club edits, and bootlegs with a real page. Every link opens the page where that version lives; nothing here has been auditioned. Tick "got it" once a file is in the folder and Claude will file it on the next pass.</p>
  <div id="clublist"></div>
</div>
<div id="pooltab" role="tabpanel">
<div class="toolbar" role="region" aria-label="Filters and actions">
  <div class="chips" id="chips">
    <button class="chip" type="button" data-f="all" aria-pressed="true">All</button>
    <button class="chip" type="button" data-f="S" aria-pressed="false">Singalongs</button>
    <button class="chip" type="button" data-f="M" aria-pressed="false">Mix-ins</button>
    <button class="chip" type="button" data-f="rec" aria-pressed="false">Recommended</button>
    <button class="chip" type="button" data-f="norec" aria-pressed="false">Not recommended</button>
    <button class="chip" type="button" data-f="new" aria-pressed="false">New downloads</button>
    <button class="chip" type="button" data-f="hal" aria-pressed="false">Halloween</button>
    <button class="chip" type="button" data-f="dup" aria-pressed="false">Duplicates</button>
    <button class="chip" type="button" data-f="sel" aria-pressed="false">Selected</button>
  </div>
  <select id="era" aria-label="Era"><option value="">Any era</option><option>pre-90s</option><option>90s</option><option>2000s</option><option>2010s</option><option>2020s</option></select>
  <input class="search" id="q" type="search" placeholder="Search title, remixer, source" aria-label="Search">
  <button class="btn quiet" type="button" id="reset">Reset to recommended</button>
  <button class="btn quiet" type="button" id="clear">Clear</button>
  <button class="btn" type="button" id="copy">Copy selected</button>
  <span class="status" id="status">Loading saved picks…</span>
</div>
<div id="list"></div>
<details id="lib"><summary>Everything else in the folder <small id="libn"></small></summary>
<p>The rest of the library, untouched by the four discs: compilations, the Eurodance collection and the old party CDs. Tempo here is the local detector only (shown with ~), so verify before trusting it. Searching above opens this list when something matches.</p>
<ol id="liblist"></ol>
</details>
</div>
</div>
<div class="player" id="player" hidden><span class="np" id="np">Nothing playing</span><audio id="audio" controls preload="none"></audio></div>
<script id="data" type="application/json">''' + data + r'''</script>
<script id="club" type="application/json">''' + clubdata + r'''</script>
<script>
(function(){
  const ITEMS = JSON.parse(document.getElementById('data').textContent);
  const LOCAL = ITEMS.some(i => i.path);
  if (LOCAL) { document.body.classList.add('haslocal'); document.getElementById('player').hidden = false; }
  const BUDGET = 690, DOT = ' · ';
  const LABEL = {S:'CD1 Singalongs', M:'CD2 Mix-ins'}, SHORT = {S:'SING', M:'MIX'}, IDX = {S:'1', M:'2'};
  const ovr = {}; try { Object.assign(ovr, JSON.parse(localStorage.getItem('twodisc-ovr') || '{}')); } catch(e) {}
  function eff(i){ return ovr[i.id] || i.disc; }
  let ovrRef = null, ovrChain = Promise.resolve();
  function persistOvr(){ try { localStorage.setItem('twodisc-ovr', JSON.stringify(ovr)); } catch(e) {} if (ovrRef) ovrChain = ovrChain.then(() => ovrRef.set({map: ovr, updatedAt: new Date().toISOString()}).catch(() => {})); }
  const FOLDERS = ['1 - under 90','2 - 90-99','3 - 100-109','4 - 110-119','5 - 120-124','6 - 125-129','7 - 130-134','8 - 135 plus'];
  const list = document.getElementById('list'), liblist = document.getElementById('liblist'), libdet = document.getElementById('lib');
  const byId = {}; ITEMS.forEach(i => byId[i.id] = i);
  const state = {sel:{}, f:'all', era:'', q:''};
  let db = null, docRef = null, writeChain = Promise.resolve(), dirty = false;
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }
  function rowHtml(i){
    const tags = [];
    if (i.rec) tags.push('<span class="tag rec">REC</span>');
    if (i.hal) tags.push('<span class="tag hal">HALLOWEEN</span>');
    (i.grp || []).forEach(g => tags.push('<span class="tag dup">' + esc(g.toUpperCase()) + '</span>'));
    if (i.intro) tags.push('<span class="tag intro">GET INTRO EDIT</span>');
    if (i.list) tags.push('<span class="tag list">LIST #' + i.list + '</span>');
    if (i.x) tags.push('<span class="tag x">EXPLICIT</span>');
    if (i.low) tags.push('<span class="tag low">' + i.kbps + ' KBPS</span>');
    if (i.dup) tags.push('<span class="tag">SAME TITLE ON A DISC</span>');
    const d = eff(i), other = d === 'S' ? 'M' : 'S';
    return '<li class="row' + (i.dim ? ' dim' : '') + '" data-id="' + i.id + '" data-disc="' + d + '" data-src="' + i.src + '" data-era="' + esc(i.era) + '" data-rec="' + (i.rec ? 1 : 0) + '" data-hal="' + (i.hal ? 1 : 0) + '" data-dup="' + ((i.grp && i.grp.length) ? 1 : 0) + '" data-text="' + esc((i.title + ' ' + i.ver + ' ' + i.srclabel + ' ' + i.kind + ' ' + (i.grp || []).join(' ')).toLowerCase()) + '">' +
      '<input type="checkbox" id="c-' + i.id + '" aria-label="Select ' + esc(i.title) + '">' + (LOCAL && i.path ? '<button class="play" type="button" data-play="' + i.id + '" aria-pressed="false" aria-label="Play ' + esc(i.title) + '">\u25B6</button>' : '') +
      '<div class="main"><label for="c-' + i.id + '"><span class="track">' + esc(i.title) + '</span>' + (i.ver ? ' <span class="ver">' + DOT + esc(i.ver) + '</span>' : '') + '</label>' +
      '<div class="meta"><span class="pill d' + d + '">' + SHORT[d] + '</span><span>' + esc(i.folder) + '</span>' + tags.join('') + '<span>' + esc(i.era) + '</span><span>' + esc(i.kind) + '</span><span>' + esc(i.srclabel) + '</span><span>' + esc(i.len) + DOT + i.mb.toFixed(1) + ' MB</span></div>' +
      (i.why ? '<div class="why">' + esc(i.why) + '</div>' : '') +
      (i.src !== 'lib' ? '<div class="meta"><button class="sw' + (ovr[i.id] ? ' ovr' : '') + '" type="button" data-sw="' + i.id + '">' + (ovr[i.id] ? 'back to ' + LABEL[i.disc] : 'move to ' + LABEL[other]) + '</button></div>' : '') + '</div>' +
      '<div class="bpm">' + (i.rawbpm ? '~' : '') + esc(i.bpm == null ? '?' : i.bpm) + '<small>BPM</small></div></li>';
  }
  function group(items, title, note){
    const sec = document.createElement('section'); sec.className = 'disc';
    const rec = items.filter(i => i.rec), more = items.filter(i => !i.rec);
    const byBpm = (a, b) => (a.bpm || 0) - (b.bpm || 0) || a.title.localeCompare(b.title);
    sec.innerHTML = '<h2>' + title + '<small>' + items.length + ' candidates</small></h2><p>' + note + '</p>' +
                    '<h4 class="grp">Recommended' + DOT + rec.length + '</h4><ol>' + rec.sort(byBpm).map(rowHtml).join('') + '</ol>' +
                    '<h4 class="grp">More options' + DOT + more.length + '</h4><ol>' + more.sort(byBpm).map(rowHtml).join('') + '</ol>';
    return sec;
  }
  function render(){
    const cand = ITEMS.filter(i => i.src !== 'lib');
    list.replaceChildren(
      group(cand.filter(i => eff(i) === 'S'), 'CD1 ' + DOT + ' Singalongs', 'The moments. Dance versions first; the originals they replace are down in the options with a note saying what took their place.'),
      group(cand.filter(i => eff(i) === 'M'), 'CD2 ' + DOT + ' Mix-ins', 'The bridges: reworks, transitions, tools, covers and long blends. Use "move to" on any row to send it to the other disc.'));
    const lib = ITEMS.filter(i => i.src === 'lib').sort((a, b) => a.title.localeCompare(b.title));
    liblist.innerHTML = lib.map(rowHtml).join('');
    document.getElementById('libn').textContent = lib.length + ' files';
    applySel(); applyFilter();
  }
  function applySel(){
    const tot = {S:[0,0,{}], M:[0,0,{}]}, grp = {};
    document.querySelectorAll('.row').forEach(li => {
      const on = !!state.sel[li.dataset.id]; li.classList.toggle('on', on); li.querySelector('input').checked = on;
      if (!on) return; const i = byId[li.dataset.id]; const t = tot[eff(i)]; t[0]++; t[1] += i.mb; t[2][i.folder] = (t[2][i.folder] || 0) + 1;
      (i.grp || []).forEach(g => { const k = g + ' @' + eff(i); (grp[k] = grp[k] || []).push(i.title + (i.ver ? ' (' + i.ver + ')' : '')); });   // a singalong plus a mix-in of the same song is by design; only same-disc doubles are flagged
    });
    ['S','M'].forEach(d => {
      const [n, mb, f] = tot[d]; document.getElementById('m' + IDX[d]).textContent = n + ' tracks' + DOT + Math.round(mb) + ' MB';
      const bar = document.getElementById('b' + IDX[d]); bar.style.width = Math.min(100, mb / BUDGET * 100) + '%';
      bar.className = mb > BUDGET ? 'bad' : (mb > BUDGET * 0.95 ? 'warn' : '');
      document.getElementById('f' + IDX[d]).textContent = FOLDERS.map(k => k.replace(/^\d - /, '') + ': ' + (f[k] || 0)).join(DOT);
    });
    const warn = Object.keys(grp).filter(g => grp[g].length > 1);
    const box = document.getElementById('overlap'); box.hidden = !warn.length;
    box.innerHTML = warn.length ? '<b>Doubles on the same disc:</b> ' + warn.map(g => esc(g.replace(/ x\d+ @[SM]$/, '')) + ' (' + LABEL[g.slice(-1)] + '): ' + grp[g].map(esc).join(' / ')).join('; ') + '.' : '';
  }
  function applyFilter(){
    const q = state.q.trim().toLowerCase(); let libHit = false;
    document.querySelectorAll('.row').forEach(li => {
      const f = state.f, d = li.dataset;
      const fOk = f === 'all' || (f === 'S' || f === 'M' ? d.disc === f : f === 'rec' ? d.rec === '1' : f === 'norec' ? d.rec === '0' && d.src !== 'lib' : f === 'new' ? d.src === 'new' : f === 'hal' ? d.hal === '1' : f === 'dup' ? d.dup === '1' : f === 'sel' ? !!state.sel[d.id] : true);
      const eOk = !state.era || d.era === state.era;
      const qOk = !q || d.text.includes(q);
      const show = fOk && eOk && qOk; li.classList.toggle('hide', !show);
      if (show && d.src === 'lib' && (q || f === 'sel')) libHit = true;
    });
    document.querySelectorAll('#pooltab section.disc').forEach(sec => { sec.querySelectorAll('h4.grp').forEach(h => { const ol = h.nextElementSibling; const any = ol.querySelector('.row:not(.hide)'); h.hidden = !any; ol.hidden = !any; }); sec.hidden = !sec.querySelector('.row:not(.hide)'); });
    if (libHit) libdet.open = true;
  }
  function setStatus(t){ document.getElementById('status').textContent = t; }
  function persist(){
    try { localStorage.setItem('twodisc-picks-v2', JSON.stringify(state.sel)); } catch(e) {}
    if (!docRef) return;
    dirty = true;
    writeChain = writeChain.then(async () => {
      if (!dirty) return; dirty = false;
      const body = {items: Object.keys(state.sel).filter(k => state.sel[k]), updatedAt: new Date().toISOString()};
      try { await docRef.set(body); setStatus('Saved' + DOT + body.items.length + ' picked'); }
      catch(e) { setStatus(e && e.code === 'invalid_argument' ? 'View-only here: picks stay in this browser only.' : 'Could not save to the shared list; picks kept in this browser.'); docRef = null; }
    });
  }
  function recommended(){ const s = {}; ITEMS.forEach(i => { if (i.rec) s[i.id] = true; }); return s; }
  document.addEventListener('change', e => {
    const li = e.target.closest('.row'); if (!li) return;
    state.sel[li.dataset.id] = e.target.checked; applySel(); if (state.f === 'sel') applyFilter(); persist();
  });
  document.getElementById('chips').addEventListener('click', e => {
    const b = e.target.closest('.chip'); if (!b) return;
    document.querySelectorAll('#chips .chip').forEach(c => c.setAttribute('aria-pressed', c === b ? 'true' : 'false'));
    state.f = b.dataset.f; applyFilter();
  });
  list.addEventListener('click', e => {
    const b = e.target.closest('.sw'); if (!b) return;
    const i = byId[b.dataset.sw]; const other = eff(i) === 'S' ? 'M' : 'S';
    if (other === i.disc) delete ovr[i.id]; else ovr[i.id] = other;
    persistOvr(); render();
    const li = list.querySelector('.row[data-id="' + i.id + '"]'); if (li) li.scrollIntoView({block: 'center'});
  });
  document.getElementById('era').addEventListener('change', e => { state.era = e.target.value; applyFilter(); });
  document.getElementById('q').addEventListener('input', e => { state.q = e.target.value; applyFilter(); });
  document.getElementById('reset').addEventListener('click', () => { state.sel = recommended(); applySel(); applyFilter(); persist(); });
  document.getElementById('clear').addEventListener('click', () => { state.sel = {}; applySel(); applyFilter(); persist(); });
  document.getElementById('copy').addEventListener('click', () => {
    const pick = ITEMS.filter(i => state.sel[i.id]);
    const line = i => 'CD' + IDX[eff(i)] + '  ' + i.folder.padEnd(13) + String(i.bpm == null ? '?' : i.bpm).padStart(3) + '  ' + i.len.padStart(5) + '  ' + (i.hal ? 'H ' : '  ') + i.title + (i.ver ? ' — ' + i.ver : '') + '  [' + i.srclabel + ']';
    const text = ['CD1 Singalongs', ...pick.filter(i => eff(i) === 'S').map(line), '', 'CD2 Mix-ins', ...pick.filter(i => eff(i) === 'M').map(line)].join('\n');
    const done = () => setStatus('Copied ' + pick.length + ' lines to the clipboard.');
    try { navigator.clipboard.writeText(text).then(done).catch(() => fallback(text)); } catch(e) { fallback(text); }
    function fallback(t){ const ta = document.createElement('textarea'); ta.value = t; ta.style.position = 'fixed'; ta.style.opacity = '0'; document.body.appendChild(ta); ta.select(); setStatus('Clipboard blocked: the list is selected below, press copy.'); }
  });

  // one shared player: starting a track stops whatever was playing
  const audio = document.getElementById('audio'); let playing = null;
  function srcFor(i){ return i.path.split('/').map(encodeURIComponent).join('/'); }
  function setPlaying(id){
    document.querySelectorAll('.play[aria-pressed="true"]').forEach(b => { b.setAttribute('aria-pressed', 'false'); b.textContent = '\u25B6'; });
    playing = id; if (!id) return;
    const b = document.querySelector('.play[data-play="' + id + '"]'); if (b) { b.setAttribute('aria-pressed', 'true'); b.textContent = '\u25A0'; }
  }
  document.addEventListener('click', e => {
    const b = e.target.closest('.play'); if (!b) return;
    const i = byId[b.dataset.play];
    if (playing === i.id && !audio.paused) { audio.pause(); return; }
    if (playing !== i.id) { audio.src = srcFor(i); document.getElementById('np').textContent = i.title + (i.ver ? ' \u00b7 ' + i.ver : '') + ' \u00b7 ' + (i.bpm == null ? '?' : i.bpm) + ' BPM'; }
    setPlaying(i.id); audio.play().catch(() => setStatus('Could not play ' + i.title + ': the file may have moved.'));
  });
  if (audio) { audio.addEventListener('ended', () => setPlaying(null)); audio.addEventListener('pause', () => { const b = playing && document.querySelector('.play[data-play="' + playing + '"]'); if (b) b.textContent = '\u25B6'; }); audio.addEventListener('play', () => { const b = playing && document.querySelector('.play[data-play="' + playing + '"]'); if (b) b.textContent = '\u25A0'; }); }

  // ---- club edit options tab ----
  const CLUB = JSON.parse(document.getElementById('club').textContent);
  const got = {}; try { Object.assign(got, JSON.parse(localStorage.getItem('clubedits-got') || '{}')); } catch(e) {}
  let gotRef = null, gotChain = Promise.resolve();
  function renderClub(){
    const songs = []; const by = {};
    CLUB.forEach(o => { if (!by[o.key]) { by[o.key] = {key:o.key, song:o.song, disc:o.disc, obpm:o.obpm, opts:[]}; songs.push(by[o.key]); } by[o.key].opts.push(o); });
    const order = {official:0, pool:1, bootleg:2, original:3};
    const html = [''].map(d => '<section class="disc">' +
      songs.map(s => '<div class="song"><h3>' + esc(s.song) + '<small>original ' + s.obpm + ' BPM' + DOT + s.opts.length + ' option' + (s.opts.length === 1 ? '' : 's') + '</small></h3><ol>' +
        s.opts.sort((a, b) => (order[a.kind] ?? 9) - (order[b.kind] ?? 9) || (b.verified - a.verified)).map(o => {
          const tags = ['<span class="tag ' + esc(o.kind) + '">' + esc(o.kind.toUpperCase()) + '</span>'];
          if (o.free) tags.push('<span class="tag free">FREE</span>');
          tags.push('<span class="tag ' + (o.verified ? 'official' : 'unv') + '">' + (o.verified ? 'PAGE CHECKED' : 'UNCHECKED') + '</span>');
          const meta = [o.bpm ? o.bpm + ' BPM' : '', o.length || '', o.where || '', o.source || ''].filter(Boolean).join(DOT);
          return '<li class="opt' + (got[o.id] ? ' on' : '') + '" data-id="' + o.id + '"><input type="checkbox" id="g-' + o.id + '" aria-label="Got it: ' + esc(o.version) + '"' + (got[o.id] ? ' checked' : '') + '>' +
            '<div class="main"><label for="g-' + o.id + '"><span class="track">' + esc(o.version) + '</span>' + (o.remixer ? ' <span class="ver">' + DOT + esc(o.remixer) + '</span>' : '') + '</label>' +
            '<div class="meta">' + tags.join('') + '<span>' + esc(meta) + '</span></div>' + (o.note ? '<div class="why">' + esc(o.note) + '</div>' : '') + '</div>' +
            '<a class="go" href="' + esc(o.url) + '" target="_blank" rel="noopener">Open</a></li>';
        }).join('') + '</ol></div>').join('') + '</section>').join('');
    document.getElementById('clublist').innerHTML = html || '<p class="club-note">No options yet.</p>';
  }
  function persistGot(){
    try { localStorage.setItem('clubedits-got', JSON.stringify(got)); } catch(e) {}
    if (!gotRef) return;
    gotChain = gotChain.then(() => gotRef.set({items: Object.keys(got).filter(k => got[k]), updatedAt: new Date().toISOString()}).catch(() => {}));
  }
  document.getElementById('clublist').addEventListener('change', e => { const li = e.target.closest('.opt'); if (!li) return; got[li.dataset.id] = e.target.checked; li.classList.toggle('on', e.target.checked); persistGot(); });
  function showTab(which){
    document.getElementById('pooltab').hidden = which !== 'pool'; document.getElementById('clubtab').hidden = which !== 'club';
    document.getElementById('tab-pool').setAttribute('aria-selected', which === 'pool' ? 'true' : 'false'); document.getElementById('tab-club').setAttribute('aria-selected', which === 'club' ? 'true' : 'false');
    try { localStorage.setItem('twodisc-tab', which); } catch(e) {}
  }
  document.getElementById('tab-pool').addEventListener('click', () => showTab('pool'));
  document.getElementById('tab-club').addEventListener('click', () => showTab('club'));
  renderClub();
  try { if (localStorage.getItem('twodisc-tab') === 'club' || location.hash === '#club') showTab('club'); } catch(e) {}

  let stored = null;
  try { stored = JSON.parse(localStorage.getItem('twodisc-picks-v2') || 'null'); } catch(e) { stored = null; }
  state.sel = stored || recommended();
  // one-time reshuffle: originals that now have a dance version in hand come off, whatever was saved before
  const BENCHED = ITEMS.filter(i => /^Benched:/.test(i.why || '')).map(i => i.id);
  const SWAPIN = ITEMS.filter(i => i.swapin).map(i => i.id);
  const MOVED = ITEMS.filter(i => i.moved).map(i => i.id);
  function migrate(){
    let flag = null; try { flag = localStorage.getItem('twodisc-mig6'); } catch(e) {}
    if (flag) return false;
    MOVED.forEach(id => { if (ovr[id]) { delete ovr[id]; } }); try { localStorage.setItem('twodisc-ovr', JSON.stringify(ovr)); } catch(e) {}
    let changed = false; BENCHED.forEach(id => { if (state.sel[id]) { delete state.sel[id]; changed = true; } });
    SWAPIN.forEach(id => { if (!state.sel[id]) { state.sel[id] = true; changed = true; } });
    try { localStorage.setItem('twodisc-mig6', '1'); } catch(e) {}
    return changed;
  }
  if (migrate()) { try { localStorage.setItem('twodisc-picks-v2', JSON.stringify(state.sel)); } catch(e) {} }
  render();
  (async () => {
    db = window.claude && window.claude.use ? await window.claude.use('db') : null;
    if (!db) { setStatus(LOCAL ? 'Local copy: picks are saved in this browser. When you are done, press Copy selected and paste the list to Claude.' : 'Shared save unavailable here; picks are kept in this browser.'); return; }
    docRef = db.doc('picks/twodisc2');
    gotRef = db.doc('picks/clubgot');
    ovrRef = db.doc('picks/ovr');
    ovrRef.onSnapshot(snap => { if (snap.exists && !snap.metadata.hasPendingWrites) { const m = (snap.data() || {}).map || {}; Object.keys(ovr).forEach(k => delete ovr[k]); Object.assign(ovr, m); let om = false; try { om = !localStorage.getItem('twodisc-mig6-ovr'); } catch(e) {} if (om) { let ch = false; MOVED.forEach(id => { if (ovr[id]) { delete ovr[id]; ch = true; } }); try { localStorage.setItem('twodisc-mig6-ovr', '1'); } catch(e) {} if (ch) persistOvr(); } try { localStorage.setItem('twodisc-ovr', JSON.stringify(ovr)); } catch(e) {} render(); } }, () => {});
    gotRef.onSnapshot(snap => { if (snap.exists && !snap.metadata.hasPendingWrites) { const d = snap.data() || {}; Object.keys(got).forEach(k => delete got[k]); (d.items || []).forEach(id => got[id] = true); renderClub(); try { localStorage.setItem('clubedits-got', JSON.stringify(got)); } catch(e) {} } }, () => {});
    docRef.onSnapshot(snap => {
      if (snap.exists) {
        const d = snap.data() || {}; const sel = {}; (d.items || []).forEach(id => sel[id] = true);
        if (!snap.metadata.hasPendingWrites) { state.sel = sel; let mig = false; try { mig = !localStorage.getItem('twodisc-mig6-db'); } catch(e) {} if (mig) { let ch = false; BENCHED.forEach(id => { if (state.sel[id]) { delete state.sel[id]; ch = true; } }); SWAPIN.forEach(id => { if (!state.sel[id]) { state.sel[id] = true; ch = true; } }); try { localStorage.setItem('twodisc-mig6-db', '1'); } catch(e) {} if (ch) persist(); } applySel(); if (state.f === 'sel') applyFilter(); try { localStorage.setItem('twodisc-picks-v2', JSON.stringify(state.sel)); } catch(e) {} }
        setStatus('Saved' + DOT + (d.items || []).length + ' picked' + (d.updatedAt ? DOT + new Date(d.updatedAt).toLocaleString() : ''));
      } else { setStatus('Starting from the recommended set. Tick, untick, then it saves on its own.'); if (!stored) persist(); }
    }, err => setStatus('Live sync stopped (' + (err && err.code || 'error') + '); picks still save when you tick.'));
  })();
})();
</script>
'''
out = "/Users/christophershannon/personal/90s2000 playlist/Two-Disc Pool.html" if LOCAL else "twodisc/two-disc-pool.html"
if LOCAL:   # a standalone file needs its own document skeleton; the published copy gets one from the platform
    head, body = page.split('<div class="wrap">', 1)
    page = '<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">\n' + head + '</head><body>\n<div class="wrap">' + body + '\n</body></html>\n'
open(out, "w", encoding="utf-8").write(page)
print(f"{out}: {len(page)/1e6:.2f} MB, {ncand} candidates + {nlib} library rows")
