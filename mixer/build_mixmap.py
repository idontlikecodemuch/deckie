#!/usr/bin/env python3
"""Build the two-disc mix map page: both CDs in disc order, SVG lines from each track's end to
its best next tracks (from mixer/recs.json), coloured by suggested transition."""
import json, os, re, sys, html
MIX = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(MIX)
MUSIC_ROOT = os.environ.get("DECKIE_MUSIC_ROOT", "/Users/christophershannon/personal/90s2000 playlist")  # where the audio lives; never inside the repo
ROOT = MUSIC_ROOT
OUT_HTML = sys.argv[1]
TOPN, MINSCORE = 5, 0.55

recs = json.load(open(os.path.join(MIX, "recs.json")))
cands = {c["id"]: c for c in json.load(open(os.path.join(MIX, "candidates.json")))}
pd = json.load(open(os.path.join(REPO, "web-player", "data.json")))
page = pd["tracks"] if isinstance(pd, dict) else pd
sel = [t for t in page if t.get("selected")]

# burned file names from the CDs v3 folders, keyed by (disc, folder, number)
names = {}
for disc, dname in (("1", "CD1 Singalongs"), ("2", "CD2 Mix-ins")):
    base = os.path.join(ROOT, "CDs v3", dname)
    for folder in sorted(os.listdir(base)):
        fp = os.path.join(base, folder)
        if not os.path.isdir(fp): continue
        for fn in sorted(os.listdir(fp)):
            m = re.match(r"(\d\d) (.+)\.mp3$", fn)
            if m: names[(disc, folder, int(m.group(1)))] = m.group(2)

# track numbers: the disc build sorted each folder by (pool bpm, title.lower())
pool = {r["id"]: r for r in json.load(open(os.path.join(REPO, "pool", "newfiles", "pool.json")))}
num = {}
for disc in ("1", "2"):
    for folder in sorted({t["folder"] for t in sel if t["disc"] == disc}):
        rows = sorted([pool[t["id"]] for t in sel if t["disc"] == disc and t["folder"] == folder],
                      key=lambda r: (r["bpm"], r["title"].lower()))
        for i, r in enumerate(rows):
            num[r["id"]] = i + 1
tracks = []
for t in sel:
    r = recs.get(t["id"])
    t["fi"] = num[t["id"]]
    key = (t["disc"], t["folder"], t["fi"])
    deck = t.get("deck") or t["title"]
    burned = names.get(key, "")
    # use the burned file name only when it is the same track (numbers shift once a folder changes)
    nm = burned if burned and burned.lstrip("H ").lower()[:10] == deck.lower()[:10] else (("H " if t.get("hal") else "") + deck)
    hal = nm.startswith("H ")
    if hal: nm = nm[2:]
    feat = json.load(open(os.path.join(MIX, "features", t["id"] + ".json")))
    lt = feat.get("local_tempo", {})
    tracks.append({"id": t["id"], "disc": t["disc"], "folder": t["folder"], "n": t["fi"], "name": nm, "hal": hal,
                   "len": t.get("len"), "bpm": round(feat["bpm"], 1), "bpm_in": round(lt.get("bpm_in", feat["bpm"]), 1),
                   "bpm_out": round(lt.get("bpm_out", feat["bpm"]), 1), "key": feat["key"]["camelot"],
                   "keyc": feat["key"]["confidence"], "in_ok": bool(lt.get("in_trusted", True)),
                   "out_ok": bool(lt.get("out_trusted", True)), "fade": bool(feat.get("fade_out")),
                   "steady_in_bar": lt.get("steady_in_bar")})
ids = {t["id"] for t in tracks}
# edges from pairs.json (every directed pair >= 0.45) so near-misses are available on tap: up to MAXPER per track
MAXPER = 999
pairs = json.load(open(os.path.join(MIX, "pairs.json")))["pairs"]
keyof = {t["id"]: next((f for f in [json.load(open(os.path.join(MIX, "features", t["id"] + ".json")))["key"]["camelot"]]), "") for t in tracks}
per = {}
edges = []
for e in sorted(pairs, key=lambda e: -e["score"]):
    if e["a"] not in ids or e["b"] not in ids or e["score"] < MINSCORE: continue
    if per.get(e["a"], 0) >= MAXPER: continue
    per[e["a"]] = per.get(e["a"], 0) + 1
    edges.append({"a": e["a"], "b": e["b"], "s": round(e["score"], 3), "tr": e["suggested_transition"],
                  "st": e["stretch_pct"], "m": e["multiplier"], "ka": keyof[e["a"]], "kb": keyof[e["b"]], "why": e["reasons"]})
tracks.sort(key=lambda t: (t["disc"], t["folder"], t["n"]))
print(f"{len(tracks)} tracks, {len(edges)} edges")
DATA = json.dumps({"tracks": tracks, "edges": edges}, ensure_ascii=False, separators=(",", ":"))

HTML = r'''<title>Halloween Mix Map</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>
:root{--bg:#f6f2fb;--fg:#1d1430;--muted:#6b5f80;--card:#ffffff;--line:#e3dbee;--accent:#7a3fd1;--accent2:#ff8c2b;--hal:#ff8c2b;
 --blend:#1f9d5a;--ramp:#15918f;--sweep:#d6a300;--echo:#ef7d1a;--cut:#d93a4c;--dim:0.08;--panel:#ffffff;--shadow:0 8px 30px rgba(40,20,80,.14)}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#140d22;--fg:#f1eaff;--muted:#a393c4;--card:#1d1430;--line:#30244a;--accent:#b08cff;--accent2:#ff9d4d;--hal:#ff9d4d;
 --blend:#3fd38a;--ramp:#36c9c6;--sweep:#f0c23b;--echo:#ff9a4a;--cut:#ff6b7a;--panel:#1d1430;--shadow:0 8px 30px rgba(0,0,0,.5);color-scheme:dark}}
:root[data-theme="dark"]{--bg:#140d22;--fg:#f1eaff;--muted:#a393c4;--card:#1d1430;--line:#30244a;--accent:#b08cff;--accent2:#ff9d4d;--hal:#ff9d4d;
 --blend:#3fd38a;--ramp:#36c9c6;--sweep:#f0c23b;--echo:#ff9a4a;--cut:#ff6b7a;--panel:#1d1430;--shadow:0 8px 30px rgba(0,0,0,.5);color-scheme:dark}
*{box-sizing:border-box}
body{background:var(--bg);color:var(--fg);font:14px/1.35 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;margin:0}
.wrap{padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));padding-block:14px 120px;max-width:1240px;margin:0 auto}
h1{font-size:22px;margin:0 0 2px;letter-spacing:.2px;text-wrap:balance}
h1 span{color:var(--accent2)}
.sub{color:var(--muted);margin:0 0 12px;font-size:13px}
.controls{display:flex;flex-wrap:wrap;gap:10px 18px;align-items:center;background:var(--card);border:1px solid var(--line);border-radius:12px;padding:10px 14px;margin-bottom:14px}
.controls label{display:flex;align-items:center;gap:8px;font-size:13px;color:var(--muted)}
.controls input[type=range]{accent-color:var(--accent);width:120px}
.controls output{color:var(--fg);font-variant-numeric:tabular-nums;min-width:2.6em}
.controls input[type=checkbox]{accent-color:var(--accent)}
.legend{display:flex;flex-wrap:wrap;gap:6px 14px;font-size:12px;color:var(--muted);margin:0 0 10px}
.legend i{display:inline-block;width:22px;height:0;border-top:3px solid;vertical-align:middle;margin-right:6px;border-radius:2px}
.legend i.dash{border-top-style:dashed}.legend i.dot{border-top-style:dotted}
.map{position:relative}
.cols{display:grid;grid-template-columns:1fr 1fr;gap:0 110px}
@media (max-width:760px){.cols{grid-template-columns:1fr;gap:28px 0}}
.disc{min-width:0}
.disc h2{font-size:15px;margin:0 0 6px;padding:6px 10px;background:var(--accent);color:#fff;border-radius:8px;display:flex;justify-content:space-between}
.disc h2 small{font-weight:400;opacity:.85}
.folder{font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);margin:10px 0 3px 10px}
.row{display:grid;grid-template-columns:26px minmax(0,1fr) 46px 32px;gap:0 8px;align-items:center;padding:4px 10px;border-radius:8px;cursor:pointer;line-height:1.25;position:relative;transition:background .12s}
.row:hover,.row.hot{background:var(--card);box-shadow:inset 0 0 0 1px var(--line)}
.row.pin{background:var(--card);box-shadow:inset 0 0 0 2px var(--accent)}
.row.far{opacity:.28}
.row .n{color:var(--muted);font-variant-numeric:tabular-nums;font-size:12px}
.row .nm{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.row .nm b{font-weight:600}
.row .nm .v{color:var(--muted)}
.row .hal .nm b{color:var(--hal)}
.row.hal .nm b::before{content:"🎃 ";font-size:11px}
.row .bpm{text-align:right;font-variant-numeric:tabular-nums;font-size:12px;color:var(--muted)}
.row .bpm.chg{color:var(--echo)}
.row .key{font-size:11px;color:var(--muted);text-align:right}
.row .key.unsure{opacity:.55}
.row.noout .bpm::after{content:"";position:absolute;right:6px;top:6px;width:6px;height:6px;border-radius:50%;background:var(--echo)}
svg.lines{position:absolute;inset:0;width:100%;height:100%;pointer-events:none;overflow:visible}
svg.lines path{fill:none;stroke-width:1.6;stroke-linecap:round;transition:opacity .15s}
svg.lines path.in{stroke-dasharray:2 5}
svg.lines path.dim{opacity:var(--dim)!important}
svg.lines path.hot{stroke-width:2.8}
.panel{position:fixed;left:0;right:0;bottom:0;background:var(--panel);border-top:1px solid var(--line);box-shadow:var(--shadow);max-height:46vh;overflow:auto;padding:10px max(16px,env(safe-area-inset-right,0px)) calc(12px + env(safe-area-inset-bottom,0px)) max(16px,env(safe-area-inset-left,0px));transform:translateY(102%);transition:transform .2s}
.panel.open{transform:none}
.panel h3{margin:0 0 2px;font-size:15px}
.panel .meta{color:var(--muted);font-size:12px;margin-bottom:8px}
.panel .close{position:absolute;right:14px;top:8px;border:0;background:var(--line);color:var(--fg);border-radius:14px;width:28px;height:28px;cursor:pointer;font-size:15px}
.panel .grp{font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);margin:10px 0 4px}
.m{display:grid;grid-template-columns:44px minmax(0,1fr);gap:2px 10px;padding:6px 0;border-top:1px solid var(--line)}
.m .sc{font-weight:700;font-variant-numeric:tabular-nums;color:var(--accent)}
.m .t{font-weight:600}
.m .t small{font-weight:400;color:var(--muted)}
.m .why{color:var(--muted);font-size:12px;grid-column:2}
.tag{display:inline-block;font-size:11px;padding:1px 7px;border-radius:10px;color:#fff;margin-left:6px;vertical-align:1px}
@media (min-width:1000px){.panel{left:auto;right:16px;bottom:16px;width:380px;max-height:70vh;border:1px solid var(--line);border-radius:14px;transform:translateX(calc(100% + 32px))}}
@media print{.controls,.panel{display:none}.wrap{padding-block:0}.row{break-inside:avoid}}
</style>
<div class="wrap">
<h1>Halloween Mix Map <span>CD1 + CD2</span></h1>
<p class="sub">Each line runs from the end of one track to the start of another that it mixes into well, by measured tempo at the ends, key, energy, vocal overlap, phrase length and groove. Fainter lines are near-misses (0.55 to 0.7). Tap a track to see its matches and why.</p>
<div class="controls">
 <label>Min score <input id="minS" type="range" min="0.55" max="0.95" step="0.01" value="0.55"><output id="minSo">0.55</output></label>
 <label>Lines per track <input id="topN" type="range" min="1" max="12" step="1" value="3"><output id="topNo">3</output></label>
 <label><input id="xdisc" type="checkbox" checked> across discs</label>
 <label><input id="blendsOnly" type="checkbox"> blends only (no brakes or cuts)</label>
 <label><input id="showIn" type="checkbox"> also show incoming (dotted)</label>
</div>
<div class="legend">
 <span><i style="border-color:var(--blend)"></i>bass-swap blend, 16 or 32 bars</span>
 <span><i style="border-color:var(--ramp)"></i>blend with a tempo ramp</span>
 <span><i style="border-color:var(--sweep)"></i>filter-sweep exit</span>
 <span><i style="border-color:var(--echo)"></i>short blend, echo out</span>
 <span><i class="dash" style="border-color:var(--cut)"></i>brake or cut, no beat-match</span>
 <span><i class="dot" style="border-color:var(--muted)"></i>incoming</span>
 <span>Orange BPM = tempo differs at the ends &middot; orange dot = no steady beat at the end</span>
</div>
<div class="map" id="map">
 <svg class="lines" id="svg"></svg>
 <div class="cols" id="cols"></div>
</div>
</div>
<div class="panel" id="panel"><button class="close" id="close" aria-label="Close">&times;</button><div id="pbody"></div></div>
<script id="data" type="application/json">__DATA__</script>
<script>
const D=JSON.parse(document.getElementById('data').textContent);
const T=Object.fromEntries(D.tracks.map(t=>[t.id,t]));
const COLOR={bass_swap_16:'var(--blend)',bass_swap_32:'var(--blend)',ramped_blend:'var(--ramp)',filter_sweep:'var(--sweep)',quick_blend_echo:'var(--echo)',brake_cut:'var(--cut)'};
const LABEL={bass_swap_16:'16-bar bass swap',bass_swap_32:'32-bar bass swap',ramped_blend:'blend with tempo ramp',filter_sweep:'filter-sweep exit',quick_blend_echo:'short blend, echo out',brake_cut:'brake / cut'};
const cols=document.getElementById('cols'),svg=document.getElementById('svg'),panel=document.getElementById('panel'),pbody=document.getElementById('pbody');
const FOLD={"1 - under 90":"Under 90","2 - 90-99":"90–99","3 - 100-109":"100–109","4 - 110-119":"110–119","5 - 120-124":"120–124","6 - 125-129":"125–129","7 - 130-134":"130–134","8 - 135 plus":"135+"};
function esc(s){return String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]))}
function splitName(n){const m=n.match(/^(.*?)(\s\([^()]*\))?$/);return m?[m[1],m[2]||'']:[n,'']}
for(const disc of ['1','2']){
 const tr=D.tracks.filter(t=>t.disc===disc);const el=document.createElement('section');el.className='disc';
 const mins=tr.reduce((a,t)=>{const [m,s]=(t.len||'0:0').split(':').map(Number);return a+m*60+s},0);
 el.innerHTML=`<h2><span>${disc==='1'?'CD1 Singalongs':'CD2 Mix-ins'}</span><small>${tr.length} tracks · ${Math.round(mins/60)} min</small></h2>`;
 let f='';for(const t of tr){if(t.folder!==f){f=t.folder;const h=document.createElement('div');h.className='folder';h.textContent=FOLD[f]||f;el.appendChild(h)}
  const [nm,v]=splitName(t.name);const r=document.createElement('div');r.className='row'+(t.hal?' hal':'')+(t.out_ok?'':' noout');r.dataset.id=t.id;
  const chg=Math.abs(t.bpm_in-t.bpm_out)/t.bpm>0.02;
  r.innerHTML=`<span class="n">${String(t.n).padStart(2,'0')}</span><span class="nm"><b>${esc(nm)}</b><span class="v">${esc(v)}</span></span><span class="bpm${chg?' chg':''}" title="${chg?'tempo '+t.bpm_in+' in → '+t.bpm_out+' out':'measured BPM'}">${chg?t.bpm_out:t.bpm}</span><span class="key${t.keyc<0.5?' unsure':''}" title="Camelot key${t.keyc<0.5?' (unsure)':''}">${t.key}</span>`;
  el.appendChild(r)}
 cols.appendChild(el)}
const rows=Object.fromEntries([...document.querySelectorAll('.row')].map(r=>[r.dataset.id,r]));
const ctl={minS:document.getElementById('minS'),topN:document.getElementById('topN'),xdisc:document.getElementById('xdisc'),blendsOnly:document.getElementById('blendsOnly'),showIn:document.getElementById('showIn')};
let pinned=null,hot=null,edgesShown=[];
function activeEdges(){const minS=+ctl.minS.value,topN=+ctl.topN.value;const per={};const out=[];
 for(const e of D.edges){if(e.s<minS)continue;if(!ctl.xdisc.checked&&T[e.a].disc!==T[e.b].disc)continue;if(ctl.blendsOnly.checked&&e.tr==='brake_cut')continue;
  per[e.a]=(per[e.a]||0);if(per[e.a]>=topN)continue;per[e.a]++;out.push(e)}
 return out}
function anchor(id,side){const r=rows[id].getBoundingClientRect(),m=document.getElementById('map').getBoundingClientRect();
 return {x:(side==='r'?r.right:r.left)-m.left,y:r.top+r.height/2-m.top}}
function draw(){edgesShown=activeEdges();const focus=pinned||hot;const showIn=ctl.showIn.checked;
 const m=document.getElementById('map');svg.setAttribute('viewBox',`0 0 ${m.clientWidth} ${m.clientHeight}`);
 const stacked=window.innerWidth<=760;let s='';
 const list=focus&&showIn?edgesShown.concat(D.edges.filter(e=>e.b===focus&&e.s>=+ctl.minS.value&&!edgesShown.includes(e)).map(e=>Object.assign({_in:true},e))):edgesShown;
 for(const e of list){const A=T[e.a],B=T[e.b];let p1,p2,d;
  if(A.disc===B.disc&&!stacked){const side=A.disc==='1'?'l':'r';p1=anchor(e.a,side);p2=anchor(e.b,side);const dx=(side==='l'?-1:1)*Math.min(90,22+Math.abs(p2.y-p1.y)*0.18);
   d=`M${p1.x},${p1.y} C${p1.x+dx},${p1.y} ${p2.x+dx},${p2.y} ${p2.x},${p2.y}`}
  else if(!stacked){p1=anchor(e.a,A.disc==='1'?'r':'l');p2=anchor(e.b,B.disc==='1'?'r':'l');const mx=(p1.x+p2.x)/2;d=`M${p1.x},${p1.y} C${mx},${p1.y} ${mx},${p2.y} ${p2.x},${p2.y}`}
  else{p1=anchor(e.a,'r');p2=anchor(e.b,'r');const dx=Math.min(70,18+Math.abs(p2.y-p1.y)*0.08);d=`M${p1.x},${p1.y} C${p1.x+dx},${p1.y} ${p2.x+dx},${p2.y} ${p2.x},${p2.y}`}
  const isHot=focus&&(e.a===focus||(e._in&&e.b===focus));const dim=focus&&!isHot;const op=dim?0:(0.12+Math.max(0,e.s-0.55)/0.45*0.88);
  const dash=e.tr==='brake_cut'?' stroke-dasharray="6 5"':(e.m!=='1'?' stroke-dasharray="1.5 4"':'');
  s+=`<path d="${d}" stroke="${COLOR[e.tr]||'var(--muted)'}" style="opacity:${op.toFixed(2)}"${dash} class="${isHot?'hot':''}${e._in?' in':''}${dim?' dim':''}"></path>`}
 svg.innerHTML=s;
 for(const id in rows){const r=rows[id];r.classList.toggle('pin',id===pinned);r.classList.toggle('hot',id===hot&&id!==pinned);
  const near=!focus||id===focus||list.some(e=>(e.a===focus&&e.b===id)||(e._in&&e.b===focus&&e.a===id));r.classList.toggle('far',!!focus&&!near)}}
function showPanel(id){const t=T[id];const outs=D.edges.filter(e=>e.a===id).sort((a,b)=>b.s-a.s);const ins=D.edges.filter(e=>e.b===id).sort((a,b)=>b.s-a.s);
 const item=e=>{const o=T[e.a===id?e.b:e.a];return `<div class="m"><span class="sc">${e.s.toFixed(2)}</span><span class="t">${esc(o.name)} <small>CD${o.disc} · ${o.bpm} · ${o.key}</small><span class="tag" style="background:${COLOR[e.tr]}">${LABEL[e.tr]||e.tr}</span></span><span class="why">${e.why.map(esc).join(' · ')}</span></div>`};
 const notes=[];if(!t.out_ok)notes.push('no steady beat at the end: echo out, do not blend');if(!t.in_ok)notes.push(t.steady_in_bar?`beat starts at bar ${t.steady_in_bar}: cut in there`:'no steady beat at the start');if(t.fade)notes.push('fades out: mix out at the last chorus');
 pbody.innerHTML=`<h3>${esc(t.name)}</h3><div class="meta">CD${t.disc} · ${FOLD[t.folder]||t.folder} · track ${String(t.n).padStart(2,'0')} · ${t.len} · ${t.bpm_in===t.bpm_out?t.bpm+' BPM':t.bpm_in+' → '+t.bpm_out+' BPM'} · key ${t.key}${t.keyc<0.5?' (unsure)':''}${notes.length?'<br>'+notes.map(esc).join(' · '):''}</div>
 <div class="grp">Mixes into (${outs.length})</div>${outs.map(item).join('')||'<div class="m"><span></span><span class="why">no match above 0.55 on the discs</span></div>'}
 <div class="grp">Comes well after (${ins.length})</div>${ins.map(item).join('')||'<div class="m"><span></span><span class="why">none above 0.55</span></div>'}`;
 panel.classList.add('open')}
cols.addEventListener('click',ev=>{const r=ev.target.closest('.row');if(!r)return;const id=r.dataset.id;if(pinned===id){pinned=null;panel.classList.remove('open')}else{pinned=id;showPanel(id)}draw()});
cols.addEventListener('mouseover',ev=>{const r=ev.target.closest('.row');if(!r||pinned)return;hot=r.dataset.id;draw()});
cols.addEventListener('mouseleave',()=>{if(!pinned){hot=null;draw()}});
document.getElementById('close').addEventListener('click',()=>{pinned=null;hot=null;panel.classList.remove('open');draw()});
for(const k in ctl){ctl[k].addEventListener('input',()=>{document.getElementById('minSo').textContent=(+ctl.minS.value).toFixed(2);document.getElementById('topNo').textContent=ctl.topN.value;draw()})}
window.addEventListener('resize',()=>requestAnimationFrame(draw));
draw();
</script>'''
open(OUT_HTML, "w", encoding="utf-8").write(HTML.replace("__DATA__", DATA.replace("</", "<\\/")))
print("wrote", OUT_HTML, os.path.getsize(OUT_HTML), "bytes")
