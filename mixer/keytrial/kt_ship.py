#!/usr/bin/env python3
"""Research X3: readers trained ONLY on data that could ship, scored on real dance music they never saw.

  python kt_ship.py feats [--jobs 4]      features of the real, openly licensed training audio (Freesound Loop Dataset
                                          loops under CC0 or CC BY with an agreed human key; any classical folder present)
  OMP_NUM_THREADS=1 python kt_ship.py profiles     learned profiles (49 numbers) on every mix -> ship_results.tsv
  python kt_ship.py cnn [--threads 3]     the small convolutional model on three mixes       -> $CACHE/ship_cnn_*.npz
  OMP_NUM_THREADS=1 python kt_ship.py report       every table of letter X3

Rules (the owner's, Nov 13): real, openly licensed audio is the base; program-written music (kt_made.py) is a
supplement at 0, 10, 25, 50 and 100 percent of the mix; nothing is chosen and no score is reported on made-up music:
the convolutional model's stopping pass is chosen on real loops of uploaders it did not train on, and every score is
on the three GiantSteps sets, which no reader here saw in training.

Real base. $DECKIE_KT_DATA/fsl: annotations.zip and metadata.json of the Freesound Loop Dataset (Zenodo 3967852) and
audio/<freesound id>.wav for the loops used: those whose annotators (one to three) agree on a key and a mode, not
discarded, under CC0 1.0 or CC BY 3.0. A loop is repeated to at least 24 s before it is read (it is a loop). Loops are
grouped by uploader. Their key labels are not spread evenly (C is commonest), which the learned profiles do not see
(the same numbers serve every home note) and the convolutional model has evened out by pitch shifts."""
import os, sys, json, re, zipfile, collections, time, warnings
warnings.filterwarnings("ignore")
import numpy as np
import kt, kt_x, kt_prof as KPF, kt_mode as KM

PC = {"c": 0, "c#": 1, "d": 2, "d#": 3, "e": 4, "f": 5, "f#": 6, "g": 7, "g#": 8, "a": 9, "a#": 10, "b": 11}
SHARES = (0, 10, 25, 50, 100)
FSL = os.path.join(kt.DATA, "fsl")

def fsl_usable():
    """freesound id -> key (0..23), licence, uploader, for the loops that may be used (see above)."""
    z = zipfile.ZipFile(os.path.join(FSL, "annotations.zip")); meta = json.load(open(os.path.join(FSL, "metadata.json")))
    ann = collections.defaultdict(list)
    for n in z.namelist():
        if n.endswith(".json"): ann[n.split("sound-")[1][:-5]].append(json.loads(z.read(n)))
    out = {}
    for sid, L in sorted(ann.items(), key=lambda x: int(x[0])):
        L = [d for d in L if not d.get("discard")]
        ks = {(d["key"], d["mode"]) for d in L if d["key"] in PC and d["mode"] in ("maj", "min")}
        if not ks or len({(d["key"], d["mode"]) for d in L}) > 1 or sid not in meta: continue
        lic = meta[sid].get("license", "")
        if "/licenses/by/" in lic or "publicdomain/zero" in lic:
            k, mo = next(iter(ks)); out[sid] = {"key": PC[k] + (12 if mo == "min" else 0), "licence": "CC0 1.0" if "zero" in lic else "CC BY 3.0", "uploader": meta[sid]["username"]}
    return out

def fmak_usable():
    """FMA track id -> key, licence, artist, for the FMAK songs whose own audio licence allows commercial use: written
    by fetch (see README): $DECKIE_KT_DATA/fmak/usable.json, from FMAK's labels (Zenodo 10719860, CC BY 4.0) joined
    with the Free Music Archive's per-track licence (tracks.csv): CC BY, CC0 or public domain only."""
    p = os.path.join(kt.DATA, "fmak", "usable.json")
    if not os.path.exists(p): return {}
    out = {}
    for tid, v in json.load(open(p)).items():
        k = kt.key_of(v["label"].replace("Major", "major"))
        if k is not None: out["fmak" + tid] = {"key": k, "licence": v["licence"], "uploader": "fmak:" + v["artist"], "path": os.path.join(kt.DATA, "fmak", "audio", tid + ".mp3"), "genre": v["genre"]}
    return out

def wtc_usable():
    """The Open Well-Tempered Clavier, Book 1 (CC0): 48 recordings, the key from each title."""
    p = os.path.join(kt.DATA, "wtc", "tracks.json")
    if not os.path.exists(p): return {}
    out = {}
    for i, (name, title, g) in enumerate(json.load(open(p))):
        pc = kt.PC[g[2]] + (1 if g[3] and "sharp" in g[3] else -1 if g[3] and "flat" in g[3] else 0)
        out[f"wtc{i:02d}"] = {"key": pc % 12 + (12 if g[4] == "minor" else 0), "licence": "CC0 1.0", "uploader": "wtc", "path": os.path.join(kt.DATA, "wtc", "audio", f"{i:02d}.mp3")}
    return out

def feat_one(item):
    sid, path = item
    import soundfile as sf, librosa, kt_three as T, kt_extract as KE
    out = os.path.join(kt.CACHE, "fsl", sid + ".npz")
    if os.path.exists(out): return sid, None
    try:
        y, sr = sf.read(path, dtype="float32", always_2d=True); y = y.mean(axis=1)
        if sr != 44100: y = librosa.resample(y, orig_sr=sr, target_sr=44100, res_type="soxr_hq")
        dur = len(y) / 44100
        if dur < 0.75: return sid, "shorter than 0.75 s"
        y = np.tile(y, int(np.ceil(24 * 44100 / len(y))))[:max(len(y), 24 * 44100)]
        r = T.read(y)
        np.savez_compressed(out, pa=r["pa"], pb=r["pb"], L=KE.logspec(y).astype(np.float16), dur=np.float32(dur))
        return sid, None
    except Exception as ex:
        return sid, str(ex)

def main_feats(jobs):
    os.makedirs(os.path.join(kt.CACHE, "fsl"), exist_ok=True)
    use = fsl_usable(); todo = [(s, os.path.join(FSL, "audio", s + ".wav")) for s in use if os.path.exists(os.path.join(FSL, "audio", s + ".wav"))]
    more = {**fmak_usable(), **wtc_usable()}; todo += [(s, v["path"]) for s, v in more.items() if os.path.exists(v["path"])]; use = {**use, **more}
    from multiprocessing import Pool
    bad = []
    with Pool(jobs) as pool:
        for sid, err in pool.imap_unordered(feat_one, todo, chunksize=4):
            if err: bad.append((sid, err))
    print(f"loops usable {len(use)}, with audio {len(todo)}, not read {len(bad)} {bad[:5]}")

def load_real(sources=("fsl", "fmak", "wtc")):
    use = {}
    if "fsl" in sources: use.update(fsl_usable())
    if "fmak" in sources: use.update(fmak_usable())
    if "wtc" in sources: use.update(wtc_usable())
    rows = []
    ups = sorted({v["uploader"] for v in use.values()})
    for sid, v in use.items():
        p = os.path.join(kt.CACHE, "fsl", sid + ".npz")
        if os.path.exists(p):
            z = np.load(p); t = np.zeros(24, np.float32); t[v["key"]] = 1
            rows.append({"id": sid, "pa": z["pa"], "pb": z["pb"], "target": t, "group": ups.index(v["uploader"]), "licence": v["licence"], "dur": float(z["dur"]), "kind": "real",
                         "source": "fmak" if sid.startswith("fmak") else "wtc" if sid.startswith("wtc") else "fsl"})
    return rows

def load_made(n=10 ** 9):
    rows = []
    d = os.path.join(kt.CACHE, "made")
    for i in range(n):
        p = os.path.join(d, f"{i}.npz")
        if not os.path.exists(p): break
        z = np.load(p); rows.append({"id": f"made{i}", "pa": z["pa"], "pb": z["pb"], "target": z["target"], "kind": str(z["kind"]), "group": -1})
    return rows

def load_scores():
    """the rendered public-domain chorales (kt_scores.py)."""
    rows = []; d = os.path.join(kt.CACHE, "made")
    for f in sorted(os.listdir(d)):
        if f.startswith("s"):
            z = np.load(os.path.join(d, f)); rows.append({"id": "made" + f[:-4], "pa": z["pa"], "pb": z["pb"], "target": z["target"], "kind": "score", "group": -1})
    return rows

def with_L(rows):
    for r in rows:
        if "L" not in r:
            p = os.path.join(kt.CACHE, "made", r["id"][4:] + ".npz") if r["id"].startswith("made") else os.path.join(kt.CACHE, "fsl", r["id"] + ".npz")
            r["L"] = np.load(p)["L"]
    return rows

def mix(real, made, share, rng):
    """the real base plus made-up clips so that they are `share` percent of the whole (100: made-up only, as many as
    the real base)."""
    if share == 0: return list(real)
    if share == 100: return [made[i] for i in rng.permutation(len(made))[:len(real)]]
    m = int(round(len(real) * share / (100 - share)))
    return list(real) + [made[i] for i in rng.permutation(len(made))[:m]]

# ---- learned profiles with soft targets (a 'mode open' clip counts half toward each mode on its home note)
def fit_profiles(rows, which="AB", equal_modes=False, minor_share=None):
    """minor_share: weigh the clips so that minor ones are that share of the fit (a published share of minor keys in
    dance music, never one measured on a test set)."""
    import torch
    torch.set_num_threads(1)
    F = {"c_A": np.array([r["pa"] for r in rows]), "c_B": np.array([r["pb"] for r in rows])}
    X = KPF.design(F, which); T = torch.tensor(np.array([r["target"] for r in rows]), dtype=torch.float64)
    W = torch.zeros((2, X.shape[2]), dtype=torch.float64, requires_grad=True); b = torch.zeros(1, dtype=torch.float64, requires_grad=True)
    minor = T[:, 12:].sum(1); w = torch.ones(len(rows), dtype=torch.float64)
    if equal_modes: minor_share = 0.5
    if minor_share is not None: w = minor * (minor_share / minor.mean()) + (1 - minor) * ((1 - minor_share) / (1 - minor.mean()))
    opt = torch.optim.LBFGS([W, b], max_iter=500, tolerance_grad=1e-9, tolerance_change=1e-12, line_search_fn="strong_wolfe")
    def closure():
        opt.zero_grad(); lp = torch.log_softmax(KPF.scores(X, W, b), dim=1)
        loss = (-(T * lp).sum(1) * w).mean() + KPF.WD * (W ** 2).sum(); loss.backward(); return loss
    opt.step(closure)
    return W.detach(), b.detach()

def test_sets():
    M = kt_x.load_set("mtg"); apple = kt.apple_keys(); sel = np.array([i in apple for i in M["ids"]])
    M = {"name": "MTG, 1,270", "F": KM.sub(M["F"], sel), "key": M["key"][sel], "ids": [i for i, s in zip(M["ids"], sel) if s], "apple": np.array([apple[i] for i, s in zip(M["ids"], sel) if s])}
    P = kt_x.load_set("gsplus", "key_modal"); P["name"] = "GiantSteps+, 468"
    G = kt_x.load_set("gs"); G["name"] = "GiantSteps Key, 604"
    return [M, P, G]

def row_of(pred, true):
    r = kt_x.four(pred, true); return [r[k] for k in ("exact", "ex_maj", "ex_min", "mean", "w1", "home", "mh_maj", "mh_min")]

HEAD = "| exact: all | major | minor | mean of halves | within one step | home note | mode given home: major | minor |"

def main_profiles():
    allreal, made = load_real(), load_made(); sets = test_sets(); out = []; preds = {}
    by = lambda *src: [r for r in allreal if r["source"] in src]
    kinds = collections.Counter(r["kind"] for r in made)
    for src, nm in (("fsl", "Freesound loops"), ("fmak", "FMAK songs"), ("wtc", "Well-Tempered Clavier")):
        rs = by(src)
        print(f"{nm}: {len(rs)} clips, {sum(r['target'][12:].sum() > 0.5 for r in rs)} minor, licences {dict(collections.Counter(r['licence'] for r in rs))}, groups {len({r['group'] for r in rs})}, median length {np.median([r['dur'] for r in rs]):.0f} s")
    print(f"made-up clips {len(made)} {dict(kinds)}")
    def run(tag, share_label, rows_of, reps, eqs=(False, True), keep=None):
        for eq in eqs:
            acc = collections.defaultdict(list)
            for rep in range(reps):
                model = fit_profiles(rows_of(rep), "AB", eq)
                for D in sets:
                    p = KPF.predict(D["F"], model, "AB").argmax(1); acc[D["name"]].append(row_of(p, D["key"]))
                    if rep == 0 and keep is not None: preds[(eq, keep, D["name"])] = p
            for D in sets: out.append((tag, "modes equal" if eq else "as the mix is", share_label, D["name"], np.mean(acc[D["name"]], axis=0)))
    # 1. each real source, and together
    for src, nm in ((("fsl",), "Freesound loops (710)"), (("fmak",), "FMAK songs, CC BY / CC0 / public domain (371)"), (("wtc",), "Well-Tempered Clavier, CC0 (48)"),
                    (("fsl", "fmak"), "loops + FMAK songs (1,081)"), (("fsl", "fmak", "wtc"), "loops + FMAK songs + Clavier (1,129)")):
        run("real only: " + nm, "0", lambda rep, src=src: by(*src), 1)
    base = by("fsl", "fmak")
    # 1b. the real base weighed to a published share of minor keys in dance music: 65 percent (a Beatport top 100 of
    # 2023, letter X's S45), 70 (the plain-key clips of the Beatport EDM Key Dataset as its authors published it),
    # 85 (GiantSteps Key, Knees et al. 2015). The second is the test set's own share and is shown for that reason only.
    for share in (0.65, 0.70, 0.85):
        acc = {}
        model = fit_profiles(base, "AB", False, minor_share=share)
        for D in sets: out.append(("real only: loops + FMAK songs (1,081)", f"weighed to {int(100 * share)} percent minor", "0", D["name"], np.array(row_of(KPF.predict(D["F"], model, "AB").argmax(1), D["key"]))))
    # 2. the made-up share, on the real base (loops + FMAK songs)
    for share in SHARES:
        run("real base (loops + FMAK songs) + made-up", str(share), lambda rep, share=share: mix(base, made, share, np.random.default_rng(100 * share + rep)), 1 if share == 0 else 3, keep=share)
    # 2b. the same with public-domain chorales rendered by our synthesiser in place of program-written music
    scores = load_scores(); print(f"rendered chorales {len(scores)}, {sum(r['target'][12:].sum() > 0.5 for r in scores)} minor")
    for share in SHARES[1:]:
        run("real base + rendered public-domain chorales", str(share), lambda rep, share=share: mix(base, scores, share, np.random.default_rng(100 * share + rep)), 3)
    # 3. which made-up kinds earn their place: at 25 percent, one kind left out at a time, and one kind alone
    for label, keep in [("without " + k, lambda r, k=k: r["kind"] != k) for k in kinds] + [("only " + k, lambda r, k=k: r["kind"] == k) for k in kinds]:
        sub = [r for r in made if keep(r)]
        run("real base + made-up, " + label, "25", lambda rep, sub=sub: mix(base, sub, 25, np.random.default_rng(900 + rep)), 3, eqs=(True,))
    with open(os.path.join(kt.HERE, "ship_results.tsv"), "w") as fh:
        fh.write("training_data\tfit\tmade_up_share_percent\tset\texact\tmajor\tminor\tmean_of_halves\twithin_one_step\thome\tmode_home_major\tmode_home_minor\n")
        for a, b, c, d, v in out: fh.write(f"{a}\t{b}\t{c}\t{d}\t" + "\t".join(f"{x:.2f}" for x in v) + "\n")
    np.savez_compressed(os.path.join(kt.CACHE, "ship_profile_preds.npz"), **{f"{int(e)}|{s}|{n}": p for (e, s, n), p in preds.items()})
    for D in sets:
        print(f"\n**{D['name']}**: learned profiles (49 numbers) fitted on shippable data only\n\n| training data | fit | made-up share | " + HEAD[2:] + "\n|---|---|---|" + "---:|" * 8)
        for a, b, c, d, v in out:
            if d == D["name"]: print(f"| {a} | {b} | {c} % | " + " | ".join(f"{x:.1f}" for x in v) + " |")
    # drift: what the reader had right with no made-up music and gets wrong with it, by kind of error
    for D in sets:
        print(f"\n**Drift on {D['name']}** (learned profiles, modes equal): clips right with no made-up music and wrong with it, by the kind of the new error; and clips gained\n\n| made-up share | lost: fifth | relative | parallel | other | lost in all | gained | net |\n|---|---:|---:|---:|---:|---:|---:|---:|")
        b0 = preds[(True, 0, D["name"])]
        for share in SHARES[1:]:
            p = preds[(True, share, D["name"])]; lost = (b0 == D["key"]) & (p != D["key"]); gained = (b0 != D["key"]) & (p == D["key"])
            c = collections.Counter(kt.relation(int(a), int(b)) for a, b in zip(p[lost], D["key"][lost]))
            print(f"| {share} % | {c['fifth']} | {c['relative']} | {c['parallel']} | {c['other']} | {int(lost.sum())} | {int(gained.sum())} | {int(gained.sum()) - int(lost.sum()):+d} |")

# ---- the convolutional model on shippable mixes
def main_cnn(threads):
    import torch, torch.nn.functional as Fn, kt_cnn as C
    torch.set_num_threads(threads)
    real, made = with_L(load_real()), load_made()
    va = [r for r in real if r["group"] % 5 == 0]; tr_real = [r for r in real if r["group"] % 5 != 0]
    print(f"real loops: training {len(tr_real)}, validation (other uploaders) {len(va)}", flush=True)
    tests = {}
    for name, label in (("mtg", "key"), ("gs", "key"), ("gsplus", "key_modal")):
        cl = [c for c in C.get(name) if c.get(label) is not None]; C.load_L(cl); tests[name] = (cl, np.array([c[label] for c in cl]))
    def batch(rows, rng):
        X = np.zeros((len(rows), 1, C.SNIP, C.NB_MODEL), np.float32); Y = np.zeros((len(rows), 24), np.float32)
        for i, r in enumerate(rows):
            s = int(rng.integers(C.SHIFT_LO, C.SHIFT_HI + 1)); L = C.crop(r["L"], s); n = L.shape[0]
            if n >= C.SNIP: t0 = int(rng.integers(0, n - C.SNIP + 1)); X[i, 0] = L[t0:t0 + C.SNIP]
            else: X[i, 0] = np.resize(L, (C.SNIP, C.NB_MODEL))
            Y[i] = np.concatenate([np.roll(r["target"][:12], s), np.roll(r["target"][12:], s)])
        return torch.from_numpy(X), torch.from_numpy(Y)
    yv = np.array([int(r["target"].argmax()) for r in va])
    for share in (0, 25, 100):
        rng = np.random.default_rng(share); tr = with_L(mix(tr_real, made, share, rng))
        torch.manual_seed(300 + share); model = C.Net(); opt = torch.optim.Adam(model.parameters(), lr=C.LR, weight_decay=C.WD)
        steps = C.EPOCHS * ((len(tr) + C.BATCH - 1) // C.BATCH); sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=C.LR, total_steps=steps)
        best = (-1, None, 0); t0 = time.time()
        for ep in range(1, C.EPOCHS + 1):
            model.train(); order = rng.permutation(len(tr))
            for b in range(0, len(tr), C.BATCH):
                X, Y = batch([tr[i] for i in order[b:b + C.BATCH]], rng)
                loss = -(Y * Fn.log_softmax(model(X), dim=1)).sum(1).mean(); opt.zero_grad(); loss.backward(); opt.step(); sched.step()
            if ep % C.VAL_EVERY == 0 or ep == C.EPOCHS:
                acc = float((C.predict(model, va).argmax(1) == yv).mean())          # chosen on real loops only
                if acc >= best[0] and ep >= C.EPOCHS // 3: best = (acc, {k: v.clone() for k, v in model.state_dict().items()}, ep)
                print(f"[made-up {share} %] pass {ep} real validation {100 * acc:.1f} (best {100 * best[0]:.1f} at {best[2]}) {time.time() - t0:.0f}s", flush=True)
        model.load_state_dict(best[1]); model.eval(); res = {"info": np.array([len(tr), len(va), best[2], best[0], time.time() - t0])}
        for name, (cl, y) in tests.items():
            lp = C.predict(model, cl, C.TTA); res[name + "_ids"] = np.array([c["id"] for c in cl]); res[name + "_lp"] = lp
            print(f"[made-up {share} %] {name} exact {100 * (lp.argmax(1) == y).mean():.1f}", flush=True)
        np.savez_compressed(os.path.join(kt.CACHE, f"ship_cnn_{share}.npz"), **res)

class _Tee:
    def __init__(self, path): self.fh = open(path, "w"); self.out = sys.stdout
    def write(self, x): self.fh.write(x); self.out.write(x)
    def flush(self): self.fh.flush(); self.out.flush()

def main_report():
    sys.stdout = _Tee(os.path.join(kt.HERE, "ship_cnn_results.md"))      # the tables, kept beside ship_results.tsv
    sets = test_sets(); M = sets[0]
    real = load_real(); tr = [r for r in real if r["group"] % 5 != 0]
    global TRAIN_MINOR
    TRAIN_MINOR = float(np.mean([r["target"][12:].sum() for r in tr])); print(f"minor share of the model's real training clips: {100 * TRAIN_MINOR:.1f} percent\n")
    print("| reader | trained on | set | " + HEAD[2:] + " bar as written |\n|---|---|---|" + "---:|" * 8 + "---|")
    ap = row_of(M["apple"], M["key"]); print("| Apple | | MTG, 1,270 | " + " | ".join(f"{x:.1f}" for x in ap) + " | |")
    names = {"mtg": "MTG, 1,270", "gsplus": "GiantSteps+, 468", "gs": "GiantSteps Key, 604"}
    base = {}
    for share in (0, 25, 100):
        p = os.path.join(kt.CACHE, f"ship_cnn_{share}.npz")
        if not os.path.exists(p): continue
        z = np.load(p)
        for D, key in zip(sets, ("mtg", "gsplus", "gs")):
            pos = {i: k for k, i in enumerate(z[key + "_ids"])}; lp = z[key + "_lp"][np.array([pos[i] for i in D["ids"]])]; pred = lp.argmax(1)
            v = row_of(pred, D["key"]); bar = ""
            if key == "mtg":
                bar = "passes" if v[1] >= ap[1] - 5 and v[2] >= ap[2] - 5 else f"fails (major {v[1] - ap[1] + 5:+.1f}, minor {v[2] - ap[2] + 5:+.1f} against the bar)"; base[share] = pred
            print(f"| small convolutional model | real (loops, FMAK songs, Clavier) + {share} % made-up (stopped at pass {int(z['info'][2])}, real validation {100 * z['info'][3]:.1f}) | {names[key]} | " + " | ".join(f"{x:.1f}" for x in v) + f" | {bar} |")
            # the same model leaned toward minor after the fact: its minor answers' log-probabilities raised as if
            # the training mix had held the stated share of minor clips (a prior shift; no retraining)
            if share == 0:
                m = TRAIN_MINOR
                for target in (0.65, 0.70, 0.85):
                    lp2 = lp.copy(); lp2[:, 12:] += np.log(target / (1 - target)) - np.log(m / (1 - m)); v2 = row_of(lp2.argmax(1), D["key"]); bar2 = ""
                    if key == "mtg": bar2 = "passes" if v2[1] >= ap[1] - 5 and v2[2] >= ap[2] - 5 else f"fails (major {v2[1] - ap[1] + 5:+.1f}, minor {v2[2] - ap[2] + 5:+.1f} against the bar)"
                    print(f"| small convolutional model | real only, leaned to {int(100 * target)} percent minor after training | {names[key]} | " + " | ".join(f"{x:.1f}" for x in v2) + f" | {bar2} |")
    if 0 in base:
        print("\n**Drift on MTG, convolutional model**: clips right with no made-up music and wrong with it\n\n| made-up share | lost: fifth | relative | parallel | other | lost in all | gained | net |\n|---|---:|---:|---:|---:|---:|---:|---:|")
        for share in (25, 100):
            if share not in base: continue
            p = base[share]; lost = (base[0] == M["key"]) & (p != M["key"]); gained = (base[0] != M["key"]) & (p == M["key"])
            c = collections.Counter(kt.relation(int(a), int(b)) for a, b in zip(p[lost], M["key"][lost]))
            print(f"| {share} % | {c['fifth']} | {c['relative']} | {c['parallel']} | {c['other']} | {int(lost.sum())} | {int(gained.sum())} | {int(gained.sum()) - int(lost.sum()):+d} |")

if __name__ == "__main__":
    a = sys.argv
    if a[1] == "feats": main_feats(int(a[a.index("--jobs") + 1]) if "--jobs" in a else 4)
    elif a[1] == "profiles": main_profiles()
    elif a[1] == "cnn": main_cnn(int(a[a.index("--threads") + 1]) if "--threads" in a else 3)
    elif a[1] == "report": main_report()
