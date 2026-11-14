#!/usr/bin/env python3
"""Research X4: a key reader trained without anyone labelling anything, on audio that could back shipped weights.

  python kt_x4.py feats [--jobs 4]          the untrained three-answer reader and the model's spectrogram on every
                                            openly licensed Free Music Archive clip  -> $CACHE/open/<id>.npz
  OMP_NUM_THREADS=1 python kt_x4.py pseudo  what the reader's confident answers are worth as labels: counts, the share
                                            of minor keys (THE LEAN, fixed here), learned profiles taught on them
  python kt_x4.py cnn pseudo|mix|ssl [--threads 4]   the small model: taught on pseudo-labels only; on the 1,080
                                            human-labelled recordings plus pseudo-labels; pretrained with no labels at
                                            all on pitch-shifted pairs and then given the human-labelled recordings
  OMP_NUM_THREADS=1 python kt_x4.py report  every table of letter X4 -> x4_results.md

Open audio. $DECKIE_KT_DATA/fma/usable.json and audio/<track id>.mp3: the 30-second clips (fma_large.zip) of the
Free Music Archive tracks whose own licence is CC BY, CC0 or public domain (8,352; tracks.csv of fma_metadata.zip).
"Electronic" means the track's genres include the archive's top-level genre Electronic.

Pseudo-labels. A clip's label is the untrained three-answer reader's answer when that answer is a key (its two
readings agree on home note and mode). Clips with a home note only, or not sure, get no label and are not used.
Nothing human is in them, and the reader was fitted to nothing.

THE LEAN, fixed before any test score was looked at (letter X4, section 3). The share of minor keys that a trained
reader should lean to is the share of minor among the untrained reader's key answers on the openly licensed
ELECTRONIC clips. It touches no test collection and no published count. It is applied in two ways, both reported
once: the training clips weighed so that minor clips are that share of the fit (learned profiles); and a finished
model's minor answers raised as if its training mix had held that share (the small model).

Self-supervised pretraining, after STONE (Kong et al., ISMIR 2024), written here from the paper's idea, not from its
code: two snippets of one recording are in the same key; a snippet shifted by c semitones is in the key c semitones
away. The model's 24 answers are folded to 12 key signatures (a major key and its relative minor share one), each
snippet's 12 probabilities are turned into one point on the circle of fifths (z = sum_k p_k exp(2 pi i 7 k / 12)), and
the loss asks the batch's mean of z_A conj(z_B), turned back by the known shift, to be 1: that needs every answer to be
decided (|z| near 1) and every pair to differ by exactly its shift. No label is used. The model is then trained on the
human-labelled recordings as in letter X3, starting from those weights instead of from nothing."""
import os, sys, json, time, collections, warnings
warnings.filterwarnings("ignore")
import numpy as np
import kt, kt_ship as KS, kt_prof as KPF, kt_x

FMA = os.path.join(kt.DATA, "fma")
ELECTRONIC = "Electronic"
SSL_EPOCHS, SSL_SNIP = 12, 72   # passes over the open clips with no labels; snippet length, 14 s
PSEUDO_CAP = 2000          # pseudo-labelled clips the small model is given (CPU time), drawn at random with seed 0

def feat_one(item):
    tid, path = item
    import soundfile as sf, librosa, kt_three as T, kt_extract as KE
    out = os.path.join(kt.CACHE, "open", tid + ".npz")
    if os.path.exists(out): return tid, None
    try:
        y, sr = sf.read(path, dtype="float32", always_2d=True); y = y.mean(axis=1)
        if sr != 44100: y = librosa.resample(y, orig_sr=sr, target_sr=44100, res_type="soxr_hq")
        r = T.read(y)
        np.savez_compressed(out, pa=r["pa"], pb=r["pb"], sa=r["sa"].astype(np.float32), sb=r["sb"].astype(np.float32),
                            answer=r["answer"], key=np.int16(r["key"]), home=np.int16(r["home"]), L=KE.logspec(y).astype(np.float16))
        return tid, None
    except Exception as ex:
        return tid, str(ex)[:80]

def main_feats(jobs):
    os.makedirs(os.path.join(kt.CACHE, "open"), exist_ok=True)
    use = json.load(open(os.path.join(FMA, "usable.json")))
    todo = [(t, os.path.join(FMA, "audio", t + ".mp3")) for t in use if os.path.exists(os.path.join(FMA, "audio", t + ".mp3"))]
    todo.sort(key=lambda it: ELECTRONIC not in use[it[0]]["tops"])          # electronic first: THE LEAN needs them all
    from multiprocessing import Pool
    bad = []
    with Pool(jobs) as pool:
        for k, (tid, err) in enumerate(pool.imap_unordered(feat_one, todo, chunksize=8), 1):
            if err: bad.append((tid, err))
            if k % 1000 == 0: print(k, flush=True)
    print(f"tracks usable {len(use)}, with audio {len(todo)}, not read {len(bad)} {bad[:3]}")

def load_open(with_L=False):
    use = json.load(open(os.path.join(FMA, "usable.json"))); rows = []
    artists = sorted({v["artist"] for v in use.values()})
    for tid, v in use.items():
        p = os.path.join(kt.CACHE, "open", tid + ".npz")
        if not os.path.exists(p): continue
        z = np.load(p); t = np.zeros(24, np.float32); k = int(z["key"])
        if k >= 0: t[k] = 1
        r = {"id": "open" + tid, "pa": z["pa"], "pb": z["pb"], "answer": str(z["answer"]), "key": k, "target": t, "kind": "pseudo",
             "electronic": ELECTRONIC in v["tops"], "tops": v["tops"], "licence": v["licence"], "group": 100000 + artists.index(v["artist"]), "path": p}
        if with_L: r["L"] = z["L"]
        rows.append(r)
    return rows

def lean(rows):
    """THE LEAN (see the top): minor share among the reader's key answers on the electronic clips."""
    e = [r for r in rows if r["electronic"] and r["key"] >= 0]
    return float(np.mean([r["key"] >= 12 for r in e])), len(e)

def curve(lp, true, covs=(100, 90, 80, 70, 60, 50)):
    pr = np.exp(lp - lp.max(1, keepdims=True)); pr /= pr.sum(1, keepdims=True); pred = pr.argmax(1); order = np.argsort(-pr.max(1)); out = []
    for c in covs:
        s = order[:max(1, int(round(len(true) * c / 100)))]; out.append(100 * float((pred[s] == true[s]).mean()))
    return out

def main_pseudo():
    rows = load_open(); sets = KS.test_sets(); real = [r for r in KS.load_real() if r["source"] in ("fsl", "fmak")]
    n = len(rows); c = collections.Counter(r["answer"] for r in rows)
    print(f"open clips read {n}: a key {c['key']} ({100 * c['key'] / n:.1f} %), home note only {c['home']} ({100 * c['home'] / n:.1f} %), not sure {c['none']} ({100 * c['none'] / n:.1f} %)")
    print(f"licences: {dict(collections.Counter(r['licence'] for r in rows))}; artists {len({r['group'] for r in rows})}")
    print("\n| top-level genre | clips | given a key | minor among those, percent |\n|---|---:|---:|---:|")
    for g, _ in collections.Counter(t for r in rows for t in r["tops"]).most_common(12):
        sub = [r for r in rows if g in r["tops"]]; k = [r for r in sub if r["key"] >= 0]
        print(f"| {g} | {len(sub)} | {len(k)} | {100 * np.mean([r['key'] >= 12 for r in k]):.1f} |")
    allk = [r for r in rows if r["key"] >= 0]
    print(f"| all | {n} | {len(allk)} | {100 * np.mean([r['key'] >= 12 for r in allk]):.1f} |")
    share, ne = lean(rows)
    print(f"\nTHE LEAN: minor share among the reader's key answers on the {ne} electronic clips it gave a key: {100 * share:.1f} percent")
    json.dump({"lean_minor_share": share, "electronic_clips_with_a_key": ne}, open(os.path.join(kt.HERE, "x4_lean.json"), "w"))
    # the human-labelled part of the open clips (FMAK songs are FMA tracks): how right the pseudo-labels are there
    fmak = json.load(open(os.path.join(kt.DATA, "fmak", "usable.json"))); hit = tot = home = 0; byans = collections.Counter()
    for r in rows:
        v = fmak.get(r["id"][4:])
        if not v: continue
        k = kt.key_of(v["label"].replace("Major", "major")); byans[r["answer"]] += 1
        if k is None or r["key"] < 0: continue
        tot += 1; hit += int(r["key"] == k); home += int(r["key"] % 12 == k % 12)
    print(f"\nOf the open clips, {sum(byans.values())} are FMAK songs with an expert key ({dict(byans)}). Where the reader gave a key ({tot}), it is the expert's on {100 * hit / max(1, tot):.1f} percent (home note {100 * home / max(1, tot):.1f}).")
    # learned profiles taught on pseudo-labels
    out = []
    def run(name, train, **kw):
        m = KS.fit_profiles(train, "AB", **kw)
        for D in sets: out.append((name, D["name"], KS.row_of(KPF.predict(D["F"], m, "AB").argmax(1), D["key"])))
    pse = allk; ele = [r for r in allk if r["electronic"]]
    run(f"pseudo-labels only, all genres ({len(pse)})", pse)
    run(f"pseudo-labels only, electronic ({len(ele)})", ele)
    run(f"human-labelled real base (1,081)", real)
    run(f"human-labelled + pseudo-labels, all genres", real + pse)
    run(f"human-labelled + pseudo-labels, electronic", real + ele)
    run(f"human-labelled real base, weighed to THE LEAN ({100 * share:.1f} percent minor)", real, minor_share=share)
    run(f"human-labelled + electronic pseudo-labels, weighed to THE LEAN", real + ele, minor_share=share)
    np.save(os.path.join(kt.CACHE, "x4_profiles.npy"), np.array([(a, b, *v) for a, b, v in out], dtype=object), allow_pickle=True)
    for D in sets:
        print(f"\n**{D['name']}**: learned profiles (49 numbers)\n\n| taught on | " + KS.HEAD[2:] + "\n|---|" + "---:|" * 8)
        for a, b, v in out:
            if b == D["name"]: print(f"| {a} | " + " | ".join(f"{x:.1f}" for x in v) + " |")

def main_cnn(mode, threads):
    import torch, torch.nn.functional as Fn, kt_cnn as C
    torch.set_num_threads(threads)
    real = KS.with_L(KS.load_real()); va = [r for r in real if r["group"] % 5 == 0]; tr_real = [r for r in real if r["group"] % 5 != 0]
    rng = np.random.default_rng(0)
    opened = load_open(with_L=True)
    pse = [r for r in opened if r["key"] >= 0]; pse = [pse[i] for i in rng.permutation(len(pse))[:PSEUDO_CAP]]
    tests = {}
    for name, label in (("mtg", "key"), ("gs", "key"), ("gsplus", "key_modal")):
        cl = [c for c in C.get(name) if c.get(label) is not None]; C.load_L(cl); tests[name] = (cl, np.array([c[label] for c in cl]))
    yv = np.array([int(r["target"].argmax()) for r in va])
    def batch(rows, rng, snip=C.SNIP):
        X = np.zeros((len(rows), 1, snip, C.NB_MODEL), np.float32); Y = np.zeros((len(rows), 24), np.float32); S = np.zeros(len(rows), np.int64)
        for i, r in enumerate(rows):
            s = int(rng.integers(C.SHIFT_LO, C.SHIFT_HI + 1)); L = C.crop(r["L"], s); n = L.shape[0]
            if n >= snip: t0 = int(rng.integers(0, n - snip + 1)); X[i, 0] = L[t0:t0 + snip]
            else: X[i, 0] = np.resize(L, (snip, C.NB_MODEL))
            if "target" in r: Y[i] = np.concatenate([np.roll(r["target"][:12], s), np.roll(r["target"][12:], s)])
            S[i] = s
        return torch.from_numpy(X), torch.from_numpy(Y), torch.from_numpy(S)
    model = C.Net(); torch.manual_seed(400)
    info = {}
    if mode == "ssl":
        # pretraining on pitch-shifted pairs of every open clip, no labels (see the top)
        EP = SSL_EPOCHS; SN = SSL_SNIP
        opt = torch.optim.Adam(model.parameters(), lr=C.LR, weight_decay=C.WD)
        steps = EP * ((len(opened) + C.BATCH - 1) // C.BATCH); sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=C.LR, total_steps=steps)
        ang = torch.tensor(2 * np.pi * 7 * np.arange(12) / 12, dtype=torch.float32); t0 = time.time()
        def z_of(logits):
            p = Fn.softmax(logits, dim=1); sig = p[:, :12] + torch.roll(p[:, 12:], shifts=-9, dims=1)     # major k with minor k + 9
            return torch.complex((sig * torch.cos(ang)).sum(1), (sig * torch.sin(ang)).sum(1))
        for ep in range(1, EP + 1):
            model.train(); order = rng.permutation(len(opened)); tot = 0.0; nb = 0
            for b in range(0, len(opened), C.BATCH):
                rows = [opened[i] for i in order[b:b + C.BATCH]]
                XA, _, SA = batch(rows, rng, SN); XB, _, SB = batch(rows, rng, SN)
                zA, zB = z_of(model(XA)), z_of(model(XB))
                d = (SA - SB).float() * (2 * np.pi * 7 / 12)                     # A's key is B's turned by the shift difference
                r = (zA * torch.conj(zB) * torch.complex(torch.cos(-d), torch.sin(-d))).mean()
                loss = 0.5 * torch.abs(1 - r) ** 2
                opt.zero_grad(); loss.backward(); opt.step(); sched.step(); tot += float(loss); nb += 1
            # how the 12 signatures line up with the human-labelled validation loops (reported, not used to choose)
            model.eval()
            with torch.no_grad():
                lp = C.predict(model, va); sig = np.exp(lp)[:, :12] + np.roll(np.exp(lp)[:, 12:], -9, axis=1)
                tsig = np.where(yv < 12, yv, (yv - 12 + 3) % 12); off = collections.Counter((sig.argmax(1) - tsig) % 12).most_common(1)[0]
            print(f"[no labels] pass {ep} loss {tot / nb:.4f}; validation loops whose signature is a fixed turn away: {100 * off[1] / len(yv):.1f} % (turn {off[0]}) {time.time() - t0:.0f}s", flush=True)
        info["pretrain_seconds"] = time.time() - t0; info["pretrain_clips"] = len(opened); info["signature_agreement"] = off[1] / len(yv)
        torch.save(model.state_dict(), os.path.join(kt.CACHE, "x4_ssl_pre.pt"))
        tr = list(tr_real)
    elif mode == "pseudo": tr = list(pse)
    else: tr = list(tr_real) + list(pse)
    opt = torch.optim.Adam(model.parameters(), lr=C.LR, weight_decay=C.WD)
    steps = C.EPOCHS * ((len(tr) + C.BATCH - 1) // C.BATCH); sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=C.LR, total_steps=steps)
    best = (-1, None, 0); t0 = time.time()
    for ep in range(1, C.EPOCHS + 1):
        model.train(); order = rng.permutation(len(tr))
        for b in range(0, len(tr), C.BATCH):
            X, Y, _ = batch([tr[i] for i in order[b:b + C.BATCH]], rng)
            loss = -(Y * Fn.log_softmax(model(X), dim=1)).sum(1).mean(); opt.zero_grad(); loss.backward(); opt.step(); sched.step()
        if ep % C.VAL_EVERY == 0 or ep == C.EPOCHS:
            acc = float((C.predict(model, va).argmax(1) == yv).mean())          # chosen on human-labelled real loops only
            if acc >= best[0] and ep >= C.EPOCHS // 3: best = (acc, {k: v.clone() for k, v in model.state_dict().items()}, ep)
            print(f"[{mode}] pass {ep} real validation {100 * acc:.1f} (best {100 * best[0]:.1f} at {best[2]}) {time.time() - t0:.0f}s", flush=True)
    model.load_state_dict(best[1]); model.eval()
    res = {"info": np.array([len(tr), len(va), best[2], best[0], time.time() - t0]), "extra": json.dumps(info),
           "train_minor": np.array(float(np.mean([r["target"][12:].sum() for r in tr])))}
    res["va_lp"] = C.predict(model, va, C.TTA); res["va_y"] = yv; res["va_ids"] = np.array([r["id"] for r in va])
    torch.save(model.state_dict(), os.path.join(kt.CACHE, f"x4_cnn_{mode}.pt"))
    for name, (cl, y) in tests.items():
        lp = C.predict(model, cl, C.TTA); res[name + "_ids"] = np.array([c["id"] for c in cl]); res[name + "_lp"] = lp
        print(f"[{mode}] {name} exact {100 * (lp.argmax(1) == y).mean():.1f}", flush=True)
    np.savez_compressed(os.path.join(kt.CACHE, f"x4_cnn_{mode}.npz"), **res)

def main_report():
    sys.stdout = KS._Tee(os.path.join(kt.HERE, "x4_results.md"))
    sets = KS.test_sets(); M = sets[0]; names = {"mtg": "MTG, 1,270", "gsplus": "GiantSteps+, 468", "gs": "GiantSteps Key, 604"}
    share = json.load(open(os.path.join(kt.HERE, "x4_lean.json")))["lean_minor_share"]
    ap = KS.row_of(M["apple"], M["key"])
    print(f"THE LEAN (fixed before scoring): {100 * share:.1f} percent minor\n")
    print("| reader | trained on | set | " + KS.HEAD[2:] + " bar as written | key right at 100 / 90 / 80 / 70 / 60 / 50 percent shown |\n|---|---|---|" + "---:|" * 8 + "---|---|")
    print("| Apple | | MTG, 1,270 | " + " | ".join(f"{x:.1f}" for x in ap) + " | | |")
    runs = [("ship_cnn_0.npz", "the 1,080 human-labelled recordings (letter X3)"), ("x4_cnn_pseudo.npz", "pseudo-labels only"),
            ("x4_cnn_mix.npz", "human-labelled + pseudo-labels"), ("x4_cnn_ssl.npz", "pretrained with no labels, then the human-labelled recordings")]
    for fn, what in runs:
        p = os.path.join(kt.CACHE, fn)
        if not os.path.exists(p): continue
        z = np.load(p); tm = float(z["train_minor"]) if "train_minor" in z.files else 0.543
        for leaned in (False, True):
            for D, key in zip(sets, ("mtg", "gsplus", "gs")):
                pos = {i: k for k, i in enumerate(z[key + "_ids"])}; lp = z[key + "_lp"][np.array([pos[i] for i in D["ids"]])].copy()
                if leaned: lp[:, 12:] += np.log(share / (1 - share)) - np.log(tm / (1 - tm))
                v = KS.row_of(lp.argmax(1), D["key"]); bar = ""
                if key == "mtg": bar = "passes" if v[1] >= ap[1] - 5 and v[2] >= ap[2] - 5 else f"fails (major {v[1] - ap[1] + 5:+.1f}, minor {v[2] - ap[2] + 5:+.1f} against the bar)"
                print(f"| small model{', leaned to THE LEAN' if leaned else ''} | {what} (training mix {100 * tm:.0f} % minor; stopped at pass {int(z['info'][2])}) | {names[key]} | " +
                      " | ".join(f"{x:.1f}" for x in v) + f" | {bar} | " + " / ".join(f"{x:.1f}" for x in curve(lp, D["key"])) + " |")

# ---------------------------------------------------------------------------------------------------------------
# The reader that could ship: confidence made honest, three answers from it, compared with the untrained reader.
#
# Rules fixed before any of these scores was looked at:
#  * The learned candidate of each kind is the one taught on the most lawful data with THE LEAN: human-labelled
#    recordings plus the electronic pseudo-labels (profiles), human-labelled plus pseudo-labels (small model).
#  * Confidence: the model's probabilities, sharpened or softened by one number (a temperature) fitted on
#    human-labelled recordings the model did not learn from (profiles: each fifth of the artists predicted by a model
#    taught on the other four fifths; small model: its validation artists), weighed to THE LEAN.
#  * Three answers: a key when its probability is at least one half (more likely right than wrong); otherwise the
#    home note when the two keys on one note together reach one half; otherwise not sure.
#  * A learned reader "beats" the untrained one if, showing keys on the same share of songs as the untrained reader
#    does (its most confident ones), its shown keys are right more often on MTG and on at least one of the other two
#    sets, and not worse by more than a point on the third.
def softmax(lp):
    p = np.exp(lp - lp.max(1, keepdims=True)); return p / p.sum(1, keepdims=True)

def temperature(lp, y, w):
    best = (1e9, 1.0)
    for T in np.exp(np.linspace(np.log(0.2), np.log(5), 97)):
        p = softmax(lp / T); nll = float(-(w * np.log(p[np.arange(len(y)), y] + 1e-12)).sum() / w.sum())
        if nll < best[0]: best = (nll, float(T))
    return best[1]

def lean_weights(y, share):
    m = (y >= 12).astype(float); return m * (share / m.mean()) + (1 - m) * ((1 - share) / (1 - m.mean()))

def three(p, t_key=0.5, t_home=0.5):
    """-> answer kind (0 key, 1 home note, 2 not sure), key, home note."""
    k = p.argmax(1); ph = p[:, :12] + p[:, 12:]; h = ph.argmax(1)
    kind = np.where(p.max(1) >= t_key, 0, np.where(ph.max(1) >= t_home, 1, 2))
    return kind, k, np.where(kind == 0, k % 12, h)

def untrained(D):
    a, b = D["R"]["A"].argmax(1), D["R"]["B"].argmax(1); same_home = a % 12 == b % 12
    kind = np.where(same_home & (a == b), 0, np.where(same_home, 1, 2)); conf = D["R"]["A"].max(1) + D["R"]["B"].max(1)
    return kind, b, b % 12, conf

def answer_row(kind, k, h, y):
    n = len(y); key = kind == 0; hm = kind == 1
    return [100 * key.mean(), 100 * (k[key] == y[key]).mean() if key.any() else 0, 100 * (k[key] % 12 == y[key] % 12).mean() if key.any() else 0,
            100 * hm.mean(), 100 * (h[hm] == y[hm] % 12).mean() if hm.any() else 0, 100 * (kind == 2).mean()]

def top_precision(conf, pred, y, share):
    s = np.argsort(-conf)[:max(1, int(round(len(y) * share)))]; return 100 * float((pred[s] == y[s]).mean())

def main_ship():
    sys.stdout = KS._Tee(os.path.join(kt.HERE, "x4_ship_results.md"))
    sets = KS.test_sets(); share = json.load(open(os.path.join(kt.HERE, "x4_lean.json")))["lean_minor_share"]
    real = [r for r in KS.load_real() if r["source"] in ("fsl", "fmak")]; ele = [r for r in load_open() if r["key"] >= 0 and r["electronic"]]
    yr = np.array([int(r["target"].argmax()) for r in real]); gr = np.array([r["group"] for r in real])
    Fof = lambda rows: {"c_A": np.array([r["pa"] for r in rows], dtype=np.float64), "c_B": np.array([r["pb"] for r in rows], dtype=np.float64)}
    cands = []
    # learned profiles: temperature from out-of-fold predictions of the human-labelled recordings
    oof = np.zeros((len(real), 24))
    for f in range(5):
        tr = [r for r, g in zip(real, gr) if g % 5 != f]; te = np.where(gr % 5 == f)[0]
        m = KS.fit_profiles(tr + ele, "AB", minor_share=share); oof[te] = KPF.predict(Fof([real[i] for i in te]), m, "AB")
    Tp = temperature(oof, yr, lean_weights(yr, share)); m = KS.fit_profiles(real + ele, "AB", minor_share=share)
    np.savez(os.path.join(kt.CACHE, "x4_profiles_ship.npz"), W=m[0].numpy(), b=m[1].numpy(), T=Tp)
    print(f"THE LEAN {100 * share:.1f} percent minor. Learned profiles: {len(real)} human-labelled + {len(ele)} electronic pseudo-labels; temperature {Tp:.3f} (out-of-fold exact on the human-labelled recordings {100 * (oof.argmax(1) == yr).mean():.1f})")
    cands.append(("learned profiles (49 numbers)", lambda D: KPF.predict(D["F"], m, "AB") / Tp))
    for fn, what in (("x4_cnn_mix.npz", "small model, human-labelled + pseudo-labels"), ("x4_cnn_ssl.npz", "small model, pretrained with no labels"), ("ship_cnn_0.npz", "small model, human-labelled only (X3)")):
        p = os.path.join(kt.CACHE, fn)
        if not os.path.exists(p): continue
        z = np.load(p); tm = float(z["train_minor"]) if "train_minor" in z.files else 0.543; shift = np.log(share / (1 - share)) - np.log(tm / (1 - tm))
        def leaned(lp, shift=shift): lp = lp.copy(); lp[:, 12:] += shift; return lp
        if "va_lp" in z.files: T = temperature(leaned(z["va_lp"]), z["va_y"], lean_weights(z["va_y"], share))
        else: T = 1.0
        print(f"{what}: temperature {T:.3f}{'' if 'va_lp' in z.files else ' (no validation answers kept; not calibrated)'}")
        key = {"MTG, 1,270": "mtg", "GiantSteps+, 468": "gsplus", "GiantSteps Key, 604": "gs"}
        def f(D, z=z, T=T, leaned=leaned, key=key):
            pos = {i: k for k, i in enumerate(z[key[D["name"]] + "_ids"])}; return leaned(z[key[D["name"]] + "_lp"][np.array([pos[i] for i in D["ids"]])]) / T
        cands.append((what + ", leaned", f))
    for D in sets:
        y = D["key"]; uk, ukey, uh, uconf = untrained(D); cov = float((uk == 0).mean())
        print(f"\n**{D['name']}**\n\n| reader | key shown, percent of songs | shown keys right | shown keys' home note right | home note only, percent | those home notes right | not sure | every song given a key: exact | major | minor | bar as written | shown keys right at the untrained reader's coverage ({100 * cov:.1f}) | expected by its own confidence there |\n|---|" + "---:|" * 9 + "---|---:|---:|")
        v = KS.row_of(ukey, y)
        print("| untrained three-answer reader (ships now) | " + " | ".join(f"{x:.1f}" for x in answer_row(uk, ukey, uh, y)) + f" | {v[0]:.1f} | {v[1]:.1f} | {v[2]:.1f} | | {100 * (ukey[uk == 0] == y[uk == 0]).mean():.1f} | |")
        if "apple" in D:
            ap = KS.row_of(D["apple"], y); print(f"| Apple (every song given a key) | 100.0 | {ap[0]:.1f} | {ap[5]:.1f} | | | | {ap[0]:.1f} | {ap[1]:.1f} | {ap[2]:.1f} | | | |")
        for name, f in cands:
            lp = f(D); p = softmax(lp); kind, k, h = three(p); v = KS.row_of(k, y); bar = ""
            if "apple" in D: bar = "passes" if v[1] >= ap[1] - 5 and v[2] >= ap[2] - 5 else f"fails (major {v[1] - ap[1] + 5:+.1f}, minor {v[2] - ap[2] + 5:+.1f})"
            s = np.argsort(-p.max(1))[:max(1, int(round(len(y) * cov)))]
            print(f"| {name} | " + " | ".join(f"{x:.1f}" for x in answer_row(kind, k, h, y)) + f" | {v[0]:.1f} | {v[1]:.1f} | {v[2]:.1f} | {bar} | {top_precision(p.max(1), k, y, cov):.1f} | {100 * p.max(1)[s].mean():.1f} |")
        # the learned reader checked by the untrained one: a key only where both name the same key
        for name, f in cands[:2]:
            p = softmax(f(D)); kind, k, h = three(p); both = (kind == 0) & (ukey == k) & (uk == 0)
            print(f"| {name}, and the untrained reader names the same key | {100 * both.mean():.1f} | {100 * (k[both] == y[both]).mean():.1f} | | | | | | | | | | |")

if __name__ == "__main__":
    a = sys.argv
    if a[1] == "feats": main_feats(int(a[a.index("--jobs") + 1]) if "--jobs" in a else 4)
    elif a[1] == "pseudo": main_pseudo()
    elif a[1] == "cnn": main_cnn(a[2], int(a[a.index("--threads") + 1]) if "--threads" in a else 4)
    elif a[1] == "report": main_report()
    elif a[1] == "ship": main_ship()
