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
the loss asks two things: that z_A equal z_B turned by the known shift (the pair differs by exactly its shift), and
that every |z| be 1 (every answer is decided). No label is used. (A first form, the batch's mean of z_A conj(z_B)
turned back by the shift to be 1, did not move from its starting value in five passes: with every answer undecided at
the start, z is 0 and that form has no slope there. The second term gives one.) The model is then trained on the
human-labelled recordings as in letter X3, starting from those weights instead of from nothing."""
import os, sys, json, time, collections, warnings
warnings.filterwarnings("ignore")
import numpy as np
import kt, kt_ship as KS, kt_prof as KPF, kt_x

FMA = os.path.join(kt.DATA, "fma")
# A second body of open audio (added Nov 14 for the owner's question on club music): excerpts of about a minute from
# the middle of each track of the Internet Archive's netlabel releases whose own licence is CC BY, CC0 or public
# domain and whose tags name a club style exactly (techno, house, electro, drum and bass, trance, breaks, dubstep,
# garage, acid, hardcore, dance): $DECKIE_KT_DATA/ia/usable.json and audio/<id>.mp3; features in $CACHE/open_ia.
#
# THE CLUB LEAN, fixed on Nov 14 before the netlabel clips were read and before any score with it was looked at:
# the share of minor among the untrained three-answer reader's key answers on those club clips. It is candidate (c)
# of the owner's four; whatever it comes out at is what is offered, and it is the one recommended if it lies above
# the pinned 55.2. (Leans of 65 and 85 percent, from published counts of the test collections' own shop, had been
# scored by then and are reported beside it; they are not chosen by their scores.)
CORPORA = {"fma": (FMA, "open"), "ia": (os.path.join(kt.DATA, "ia"), "open_ia")}
ELECTRONIC = "Electronic"
SSL_EPOCHS, SSL_SNIP = 12, 72   # passes over the open clips with no labels; snippet length, 14 s
PSEUDO_CAP = 2000          # pseudo-labelled clips the small model is given (CPU time), drawn at random with seed 0

def feat_one(item):
    tid, path, sub = item
    import soundfile as sf, librosa, kt_three as T, kt_extract as KE
    out = os.path.join(kt.CACHE, sub, tid + ".npz")
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

def main_feats(jobs, corpus="fma"):
    root, sub = CORPORA[corpus]
    os.makedirs(os.path.join(kt.CACHE, sub), exist_ok=True)
    use = json.load(open(os.path.join(root, "usable.json")))
    todo = [(t, os.path.join(root, "audio", t + ".mp3"), sub) for t in use if os.path.exists(os.path.join(root, "audio", t + ".mp3"))]
    todo.sort(key=lambda it: ELECTRONIC not in use[it[0]]["tops"])          # electronic first: THE LEAN needs them all
    from multiprocessing import Pool
    bad = []
    with Pool(jobs) as pool:
        for k, (tid, err) in enumerate(pool.imap_unordered(feat_one, todo, chunksize=8), 1):
            if err: bad.append((tid, err))
            if k % 1000 == 0: print(k, flush=True)
    print(f"tracks usable {len(use)}, with audio {len(todo)}, not read {len(bad)} {bad[:3]}")

def load_open(with_L=False, corpus="fma"):
    root, sub = CORPORA[corpus]
    use = json.load(open(os.path.join(root, "usable.json"))); rows = []
    artists = sorted({v["artist"] for v in use.values()})
    for tid, v in use.items():
        p = os.path.join(kt.CACHE, sub, tid + ".npz")
        if not os.path.exists(p): continue
        z = np.load(p); t = np.zeros(24, np.float32); k = int(z["key"])
        if k >= 0: t[k] = 1
        r = {"id": "open" + tid, "pa": z["pa"], "pb": z["pb"], "answer": str(z["answer"]), "key": k, "target": t, "kind": "pseudo",
             "electronic": ELECTRONIC in v["tops"], "tops": v["tops"], "licence": v["licence"], "group": (100000 if corpus == "fma" else 200000) + artists.index(v["artist"]), "path": p,
             "styles": v.get("styles", [])}
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
                diff = zA - zB * torch.complex(torch.cos(d), torch.sin(d))
                mag = lambda z: torch.sqrt(z.real ** 2 + z.imag ** 2 + 1e-8)
                loss = (diff.real ** 2 + diff.imag ** 2).mean() + ((1 - mag(zA)) ** 2 + (1 - mag(zB)) ** 2).mean()
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
    elif mode in ("club", "clubonly"):
        # The owner's question of Nov 14: does more real club music move the scores? The netlabel club excerpts the
        # untrained reader gave a key (all of them), added to the chosen model's training mix ("club"), or alone
        # ("clubonly"). Fixed before training: a retrained model replaces the shipped one only by the rule above
        # main_ship, against the shipped reader instead of the untrained one.
        ia = [r for r in load_open(with_L=True, corpus="ia") if r["key"] >= 0]
        print(f"club excerpts with a key from the untrained reader: {len(ia)}", flush=True)
        tr = (list(tr_real) + list(pse) + ia) if mode == "club" else ia
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
    import kt_three as T
    SA = np.array([T.scores24(x) for x in D["F"]["c_A"]]); SB = np.array([T.scores24(x) for x in D["F"]["c_B"]])
    a, b = SA.argmax(1), SB.argmax(1); same_home = a % 12 == b % 12
    kind = np.where(same_home & (a == b), 0, np.where(same_home, 1, 2)); conf = SA.max(1) + SB.max(1)
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

# ---------------------------------------------------------------------------------------------------------------
# The model as it ships: batch normalisation folded into the convolutions, every number rounded to a 16-bit float,
# no reading at several pitch shifts, a long song read in stretches of 600 frames. core/Sources/DeckieCore/Key/
# LearnedKey.swift computes exactly this; `export` writes the file it loads, `fixture` the values its test reads.
STRETCH, SHORTEST = 600, 16

def folded(model):
    """the numbers in the order LearnedKey.swift reads them, as float16."""
    import torch
    def bn(b): sc = b.weight / torch.sqrt(b.running_var + b.eps); return sc, b.bias - b.running_mean * sc
    out = []; sc, sh = bn(model.norm); out += [sc.detach().numpy().ravel(), sh.detach().numpy().ravel()]
    for blk in (model.b1, model.b2, model.b3, model.b4):
        for ci, bi in ((0, 1), (3, 4)):
            sc, sh = bn(blk[bi]); out += [(blk[ci].weight * sc[:, None, None, None]).detach().numpy().ravel(), sh.detach().numpy().ravel()]
    sc, sh = bn(model.pbn); out += [(model.proj.weight * sc[:, None, None, None]).detach().numpy().ravel(), sh.detach().numpy().ravel()]
    out += [model.out.weight.detach().numpy().ravel(), model.out.bias.detach().numpy().ravel()]
    return np.concatenate(out).astype(np.float16)

SHAPES = [(12, 1, 5, 5), (12, 12, 3, 3), (24, 12, 3, 3), (24, 24, 3, 3), (48, 24, 3, 3), (48, 48, 3, 3), (96, 48, 3, 3), (96, 96, 3, 3), (48, 96, 1, 15), (24, 48, 1, 1)]

def shipped_scores(L126, flat):
    """(24,) scores of one spectrogram (frames, 126) from the folded float16 numbers: what LearnedKey.swift computes."""
    import torch, torch.nn.functional as Fn
    v = torch.from_numpy(flat.astype(np.float32)); at = 2; layers = []
    for o, i, kh, kw in SHAPES:
        w = v[at:at + o * i * kh * kw].reshape(o, i, kh, kw); at += o * i * kh * kw; b = v[at:at + o]; at += o; layers.append((w, b))
    assert at == len(v)
    def stretch(x):
        x = torch.from_numpy(np.ascontiguousarray(x, dtype=np.float32))[None, None] * v[0] + v[1]
        for blk in range(4):
            for j in (0, 1):
                w, b = layers[2 * blk + j]; x = Fn.elu(Fn.conv2d(x, w, b, padding=(w.shape[2] // 2, w.shape[3] // 2)))
            if blk < 3: x = Fn.max_pool2d(x, 2)
        x = Fn.elu(Fn.conv2d(x, *layers[8])); return Fn.conv2d(x, *layers[9]).mean(dim=(2, 3))[0].numpy().astype(np.float64)
    n = L126.shape[0]
    if n < 8: return None
    tot = np.zeros(24); wsum = 0; a = 0
    with torch.no_grad():
        while a < n:
            m = min(STRETCH, n - a)
            if m < SHORTEST and a > 0: break
            tot += stretch(L126[a:a + m]) * m; wsum += m; a += m
    return tot / wsum

def shipped_probs(scores, lean, T):
    lp = scores - scores.max(); lp = lp - np.log(np.exp(lp).sum()); lp = lp.copy(); lp[12:] += lean
    return softmax((lp / T)[None])[0]

def main_export(mode):
    """python kt_x4.py export <mode>: the chosen model's numbers as shipped, its temperature on the validation artists,
    its scores on the three sets as shipped -> x4_shipped_results.md, and the file core/.models/deckie-key-<version>.f16."""
    import torch, base64, hashlib, kt_cnn as C, kt_three as T3, kt_extract as KE
    torch.set_num_threads(1)
    share = json.load(open(os.path.join(kt.HERE, "x4_lean.json")))["lean_minor_share"]
    z = np.load(os.path.join(kt.CACHE, f"x4_cnn_{mode}.npz")); tm = float(z["train_minor"]); lean = float(np.log(share / (1 - share)) - np.log(tm / (1 - tm)))
    model = C.Net(); model.load_state_dict(torch.load(os.path.join(kt.CACHE, f"x4_cnn_{mode}.pt"))); model.eval()
    flat = folded(model); raw = flat.astype("<f2").tobytes(); digest = hashlib.sha256(raw).hexdigest()
    # temperature: on the validation artists' recordings, read as shipped
    real = KS.with_L(KS.load_real()); va = [r for r in real if r["group"] % 5 == 0]; yv = np.array([int(r["target"].argmax()) for r in va])
    S = np.array([shipped_scores(C.crop(r["L"].astype(np.float32)), flat) for r in va]); lp = S - S.max(1, keepdims=True); lp = lp - np.log(np.exp(lp).sum(1, keepdims=True)); lp[:, 12:] += lean
    Tm = temperature(lp, yv, lean_weights(yv, share))
    sys.stdout = KS._Tee(os.path.join(kt.HERE, "x4_shipped_results.md"))
    print(f"model {mode}: {len(flat)} numbers, {len(raw)} bytes as 16-bit floats, SHA-256 {digest}; lean {lean:+.4f} (THE LEAN {100 * share:.1f} percent minor, training mix {100 * tm:.1f}); temperature {Tm:.3f} on {len(va)} validation recordings (exact there {100 * (lp.argmax(1) == yv).mean():.1f})")
    sets = KS.test_sets(); names = {"MTG, 1,270": "mtg", "GiantSteps+, 468": "gsplus", "GiantSteps Key, 604": "gs"}
    for D in sets:
        cl = {c["id"]: c for c in C.get(names[D["name"]])}; clips = [cl[i] for i in D["ids"]]; C.load_L(clips); y = D["key"]
        P = np.array([shipped_probs(shipped_scores(C.crop(c["L"].astype(np.float32)), flat), lean, Tm) for c in clips])
        np.save(os.path.join(kt.CACHE, f"x4_shipped_{names[D['name']]}.npy"), P)
        kind, k, h = three(P); uk, ukey, uh, _ = untrained(D); v = KS.row_of(k, y); cov = float((uk == 0).mean())
        print(f"\n**{D['name']}**\n\n| reader | key shown, percent of songs | shown keys right | shown keys' home note right | home note only, percent | those home notes right | not sure | every song given a key: exact | major | minor | shown keys right at the untrained reader's coverage | expected by its own confidence: shown keys |\n|---|" + "---:|" * 11)
        print("| untrained three-answer reader | " + " | ".join(f"{x:.1f}" for x in answer_row(uk, ukey, uh, y)) + f" | | | | {100 * (ukey[uk == 0] == y[uk == 0]).mean():.1f} | |")
        if "apple" in D:
            ap = KS.row_of(D["apple"], y); print(f"| Apple (every song given a key) | 100.0 | {ap[0]:.1f} | {ap[5]:.1f} | | | | {ap[0]:.1f} | {ap[1]:.1f} | {ap[2]:.1f} | | |")
        print("| the learned reader as shipped | " + " | ".join(f"{x:.1f}" for x in answer_row(kind, k, h, y)) + f" | {v[0]:.1f} | {v[1]:.1f} | {v[2]:.1f} | {top_precision(P.max(1), k, y, cov):.1f} | {100 * P.max(1)[kind == 0].mean():.1f} |")
        print("\n| shown at least this sure | songs shown, percent | shown keys right | the reader's own mean confidence |\n|---:|---:|---:|---:|")
        for t in (0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9):
            sel = P.max(1) >= t
            if sel.any(): print(f"| {t:.1f} | {100 * sel.mean():.1f} | {100 * (k[sel] == y[sel]).mean():.1f} | {100 * P.max(1)[sel].mean():.1f} |")
    # the file the Swift reader loads (core/.models is not in the repository), and the values LearnedKey.swift pins
    out = os.path.join(kt.HERE, "..", "..", "core", ".models"); os.makedirs(out, exist_ok=True)
    open(os.path.join(out, f"deckie-key-{digest[:8]}.f16"), "wb").write(raw)
    print(f"\nwrote core/.models/deckie-key-{digest[:8]}.f16; pin in LearnedKey.Model: name deckie-key-{digest[:8]}, bytes {len(raw)}, SHA-256 {digest}, minor lean {lean!r}, temperature {Tm!r}")

def synthetic_flat():
    """A model of made-up numbers that Swift and Python can both write down exactly (the Swift test makes the same):
    a linear congruential generator, s = s * 1664525 + 1013904223 mod 2^32 from 12345; each draw is
    v = (s >> 8) mod 2001 - 1000; a weight is v / 1000 * 1.7 / sqrt(inputs to one output), a bias v / 1000 * 0.05,
    both rounded to 32-bit floats; the input's scale is 1 and its shift 0."""
    st = 12345; out = [1.0, 0.0]
    def draw(n):
        nonlocal st; v = np.zeros(n)
        for i in range(n):
            st = (st * 1664525 + 1013904223) & 0xFFFFFFFF; v[i] = ((st >> 8) % 2001) - 1000
        return v
    for o, i, kh, kw in SHAPES:
        out += list(np.float32(draw(o * i * kh * kw) / 1000.0 * (1.7 / np.sqrt(float(i * kh * kw))))); out += list(np.float32(draw(o) / 1000.0 * 0.05))
    return np.array(out, dtype=np.float32)

def main_fixture():
    """python kt_x4.py fixture: the reference's values for the made-up model on the generated clips of
    three_answer.json -> core/Tests/DeckieCoreTests/Fixtures/learned_key.json (no trained number is in it)."""
    import kt_three as T3, kt_extract as KE
    flat = synthetic_flat(); lean, Tm = 0.1, 0.05; cases = []
    for nm, seed, chords, det in T3.FIXTURE_CLIPS:
        if chords is None: continue
        spec = [[(T3.inc_of(m, det), 3 if j == 0 else 2) for j, m in enumerate(ch)] for ch in chords]; y = T3.synth(seed, spec, 20)
        L = KE.logspec(y)[:, KE.BASE:KE.BASE + KE.NB_MODEL].astype(np.float32); sc = shipped_scores(L, flat); pr = shipped_probs(sc, lean, Tm); kind, k, h = three(pr[None])
        cases.append({"name": nm, "frames": int(L.shape[0]), "spectrogram_rows": {str(i): [float(x) for x in L[i]] for i in (0, 1, 50, L.shape[0] - 1)},
                      "scores": [float(x) for x in sc], "probabilities": [float(x) for x in pr], "answer": ("key", "home", "none")[int(kind[0])], "key": int(k[0]), "home": int(h[0])})
        print(nm, cases[-1]["answer"], cases[-1]["key"], f"{pr.max():.3f}", f"score spread {sc.max() - sc.min():.4f}")
    json.dump({"about": "written by mixer/keytrial/kt_x4.py fixture: the learned key reader's reference values, for a model of made-up numbers (kt_x4.synthetic_flat), on the generated clips of three_answer.json",
               "minor_lean": lean, "temperature": Tm, "numbers": int(len(flat)), "numbers_sum": float(flat.astype(np.float64).sum()), "cases": cases},
              open(os.path.join(kt.HERE, "..", "..", "core", "Tests", "DeckieCoreTests", "Fixtures", "learned_key.json"), "w"), indent=0)

def main_parity(mode, tool, every=10):
    """python kt_x4.py parity <mode> "<swift tool> --learned": every tenth recording of the three outside sets, decoded
    here and piped to the Swift reader; its 24 probabilities and its answer against this file's on the same samples."""
    import torch, subprocess, struct, kt_cnn as C, kt_extract as KE, key_parity as KP
    torch.set_num_threads(1)
    share = json.load(open(os.path.join(kt.HERE, "x4_lean.json")))["lean_minor_share"]
    z = np.load(os.path.join(kt.CACHE, f"x4_cnn_{mode}.npz")); tm = float(z["train_minor"]); lean = float(np.log(share / (1 - share)) - np.log(tm / (1 - tm)))
    model = C.Net(); model.load_state_dict(torch.load(os.path.join(kt.CACHE, f"x4_cnn_{mode}.pt"))); model.eval(); flat = folded(model)
    Tm = float(open(os.path.join(kt.HERE, "..", "..", "core", "Sources", "DeckieCore", "Key", "LearnedKey.swift")).read().split("pinnedTemperature = ")[1].split("\n")[0])
    p = subprocess.Popen(tool.split(), stdin=subprocess.PIPE, stdout=subprocess.PIPE); n = same = 0; worst = 0.0; secs = 0.0; kinds = collections.Counter()
    for name in ("mtg", "gsplus", "gs"):
        for c in C.get(name)[::every]:
            y, _ = KP.load44(c["path"]); L = KE.logspec(y)[:, KE.BASE:KE.BASE + KE.NB_MODEL].astype(np.float32)
            pr = shipped_probs(shipped_scores(L, flat), lean, Tm); kind, k, h = three(pr[None]); t0 = time.time()
            p.stdin.write(struct.pack("<q", len(y))); p.stdin.write(y.astype("<f4").tobytes()); p.stdin.flush()
            got = p.stdout.readline().decode().rstrip("\n").split("\t"); secs += time.time() - t0
            q = np.array([float(x) for x in got[2:]]); worst = max(worst, float(np.abs(q - pr).max())); n += 1; kinds[got[0]] += 1
            same += int(got[0] == ("key", "home", "none")[int(kind[0])] and int(got[1]) == int(k[0]))
    p.stdin.write(struct.pack("<q", -1)); p.stdin.close(); p.wait()
    print(f"recordings {n}: the Swift reader's answer and likeliest key equal the Python reference's on {same}; largest difference in any probability {worst:.5f}; answers {dict(kinds)}; Swift time {secs / n:.2f} s a two-minute recording (pipe included)")

def main_apple():
    """python kt_x4.py apple: the learned reader as shipped beside Apple, song by song, on the 1,270 MTG clips Apple
    read (the probabilities `export` kept): on the songs it shows and on those it declines, by major and minor, at
    60 to 100 percent shown, with the sign test on the songs where one is right and the other wrong
    -> x4_apple_results.md."""
    sys.stdout = KS._Tee(os.path.join(kt.HERE, "x4_apple_results.md"))
    M = KS.test_sets()[0]; y = M["key"]; ap = M["apple"]; P = np.load(os.path.join(kt.CACHE, "x4_shipped_mtg.npy"))
    kind, k, h = three(P); conf = P.max(1); ok = k == y; aok = ap == y; mi = y >= 12
    def line(name, sel):
        n = int(sel.sum()); g, l, pv = kt.paired(aok[sel], ok[sel])
        return f"| {name} | {n} | {100 * n / len(y):.1f} | {100 * ok[sel].mean():.1f} | {100 * aok[sel].mean():.1f} | {100 * (ok[sel].mean() - aok[sel].mean()):+.1f} | {g} | {l} | {pv:.3g} |"
    head = "| songs | count | percent of the 1,270 | ours right | Apple right | ours minus Apple | only ours right | only Apple right | sign test p |\n|---|---:|---:|---:|---:|---:|---:|---:|---:|"
    shown = kind == 0
    print("**As it ships (a key shown at one half or more)**\n\n" + head)
    for nm, base in (("all", np.ones(len(y), bool)), ("major", ~mi), ("minor", mi)):
        print(line(f"{nm}: shown a key", shown & base)); print(line(f"{nm}: declined (ours forced to name its likeliest key)", ~shown & base)); print(line(f"{nm}: every song", base))
    print(f"\nOf the songs shown a key, {100 * mi[shown].mean():.1f} percent are minor; of those declined, {100 * mi[~shown].mean():.1f}; of all, {100 * mi.mean():.1f}.")
    print(f"What ours answers: minor on {100 * (k >= 12).mean():.1f} percent of all songs; Apple on {100 * (ap >= 12).mean():.1f}.")
    order = np.argsort(-conf)
    for nm, base in (("all songs", np.ones(len(y), bool)), ("major songs", ~mi), ("minor songs", mi)):
        print(f"\n**The most confident share shown, {nm}** (the share is of all 1,270; the row counts the {nm} among them)\n\n" + head)
        for c in (60, 70, 80, 90, 100):
            sel = np.zeros(len(y), bool); sel[order[:int(round(len(y) * c / 100))]] = True
            print(line(f"{c} percent shown", sel & base))
    w1 = lambda pred, sel: (lambda s: s["exact"] + s["fifth"] + s["relative"])(kt.stats(pred[sel], y[sel]))
    allsel = np.ones(len(y), bool); r = KS.row_of(k, y); a = KS.row_of(ap, y)
    print("\n**What could be measured**\n\n| measure | ours | Apple |\n|---|---|---|")
    print(f"| the bar as written: every song given a key, exact on the major half and on the minor half | {r[1]:.1f} and {r[2]:.1f} | {a[1]:.1f} and {a[2]:.1f} |")
    print(f"| every song given a key, exact | {r[0]:.1f} | {a[0]:.1f} |")
    print(f"| every song given a key, the mean of the two halves | {r[3]:.1f} | {a[3]:.1f} |")
    print(f"| keys shown ({100 * shown.mean():.1f} percent of songs), exact, Apple on the same songs | {100 * ok[shown].mean():.1f} | {100 * aok[shown].mean():.1f} |")
    print(f"| every song given a key, within one step on the wheel | {w1(k, allsel):.1f} | {w1(ap, allsel):.1f} |")
    print(f"| keys shown, within one step on the wheel, Apple on the same songs | {w1(k, shown):.1f} | {w1(ap, shown):.1f} |")
    print(f"| every song, the home note right | {r[5]:.1f} | {a[5]:.1f} |")

def pinned():
    t = open(os.path.join(kt.HERE, "..", "..", "core", "Sources", "DeckieCore", "Key", "LearnedKey.swift")).read()
    return float(t.split("pinnedMinorLean = ")[1].split("\n")[0]), float(t.split("pinnedTemperature = ")[1].split("\n")[0])

def releaned(P, share, tm):
    """the shipped probabilities with the lean set to a share of minor keys (None: no lean at all)."""
    lean0, T = pinned(); lp = T * np.log(P + 1e-300); lp[:, 12:] -= lean0
    if share is not None: lp[:, 12:] += np.log(share / (1 - share)) - np.log(tm / (1 - tm))
    return softmax(lp / T)

def kinds_row(pred, true):
    s = kt.stats(pred, true); return [s["exact"], s["parallel"], s["relative"] + s["fifth"], s["other"], s["exact"] + s["relative"] + s["fifth"]]

def main_dj(extra=()):
    """python kt_x4.py dj [share ...]: the DJ's view of right and wrong (exact; right home note, wrong mode; a
    neighbour on the wheel; anything else) for the reader as shipped and Apple, and every candidate lean on every
    measure -> x4_dj_results.md. Extra shares of minor (percent) are added to the candidates."""
    sys.stdout = KS._Tee(os.path.join(kt.HERE, "x4_dj_results.md"))
    sets = KS.test_sets(); M = sets[0]; y = M["key"]; ap = M["apple"]; tm = float(np.load(os.path.join(kt.CACHE, "x4_cnn_mix.npz"))["train_minor"])
    P = {n: np.load(os.path.join(kt.CACHE, f"x4_shipped_{n}.npy")) for n in ("mtg", "gsplus", "gs")}
    kind, k, h = three(P["mtg"]); shown = kind == 0; home = kind == 1; mi = y >= 12
    f = lambda v: " | ".join(f"{x:.1f}" for x in v)
    print("**What right and wrong mean to a DJ (MTG, 1,270 clips; percent of the songs in the row)**\n\n| reader, songs | songs | exact (home note and mode) | right home note, wrong mode | a neighbour on the wheel (relative key, or a fifth away) | anything else | within one step on the wheel (exact or a neighbour) |\n|---|---:|---:|---:|---:|---:|---:|")
    print(f"| ours, the keys it shows | {int(shown.sum())} | {f(kinds_row(k[shown], y[shown]))} |")
    print(f"| Apple, on those same songs | {int(shown.sum())} | {f(kinds_row(ap[shown], y[shown]))} |")
    print(f"| ours, every song (forced to name a key) | {len(y)} | {f(kinds_row(k, y))} |")
    print(f"| Apple, every song | {len(y)} | {f(kinds_row(ap, y))} |")
    for nm, sel in (("major songs", ~mi), ("minor songs", mi)):
        print(f"| ours, the keys it shows, {nm} | {int((shown & sel).sum())} | {f(kinds_row(k[shown & sel], y[shown & sel]))} |")
        print(f"| Apple, on those same songs | {int((shown & sel).sum())} | {f(kinds_row(ap[shown & sel], y[shown & sel]))} |")
    hk = k[home]; hy = y[home]; par = (hk % 12 == hy % 12) & (hk != hy)
    print(f"\nHome-note answers: {int(home.sum())} songs ({100 * home.mean():.1f} percent). The home note shown is right on {100 * (h[home] == hy % 12).mean():.1f} percent of them. "
          f"Had the reader named its likeliest key there instead: exact {100 * (hk == hy).mean():.1f}, right home note with the wrong mode {100 * par.mean():.1f} ({int(par.sum())} songs), a neighbour {100 * (kinds_row(hk, hy)[2]) / 100:.1f}, anything else {kinds_row(hk, hy)[3]:.1f}.")
    allpar = (k % 12 == y % 12) & (k != y)
    print(f"Wrong-mode errors if every song were given a key: {int(allpar.sum())}. Shown as a key: {int((allpar & shown).sum())}. Avoided by a home-note answer: {int((allpar & home).sum())}. Avoided by not sure: {int((allpar & (kind == 2)).sum())}.")
    print(f"Apple's wrong-mode errors over every song: {int(((ap % 12 == y % 12) & (ap != y)).sum())}.")
    # leans
    cands = [("no lean at all (the training mix, %.1f percent minor)" % (100 * tm), None), ("as pinned now: 55.2, open electronic music of the Free Music Archive as the reader hears it", 0.552)]
    cands += [("65: a published count of one dance chart (letter X)", 0.65), ("85: the published share of the GiantSteps Key set (Knees and others, 2015)", 0.85)]
    cands += [(f"{x:g}: {why}", x / 100) for x, why in extra]
    print("\n**Every candidate lean, the reader as shipped otherwise (percent)**\n\n| lean to this share of minor | MTG: major half | minor half | bar as written (36.5 / 70.6) | every song exact | mean of halves | within one step | key shown | shown keys right | Apple right on those songs | shown keys within one step | home note only | GiantSteps+: every song | shown | shown right | GiantSteps Key: every song | shown | shown right |\n|---|" + "---:|" * 2 + "---|" + "---:|" * 14)
    apr = KS.row_of(ap, y)
    for name, share in cands:
        Q = releaned(P["mtg"], share, tm); kd, kk, hh = three(Q); r = KS.row_of(kk, y); sh = kd == 0
        bar = "passes" if r[1] >= apr[1] - 5 and r[2] >= apr[2] - 5 else ("fails: " + ", ".join(x for x in ((f"major {apr[1] - 5 - r[1]:.1f} short" if r[1] < apr[1] - 5 else ""), (f"minor {apr[2] - 5 - r[2]:.1f} short" if r[2] < apr[2] - 5 else "")) if x))
        row = f"| {name} | {r[1]:.1f} | {r[2]:.1f} | {bar} | {r[0]:.1f} | {r[3]:.1f} | {r[4]:.1f} | {100 * sh.mean():.1f} | {100 * (kk[sh] == y[sh]).mean():.1f} | {100 * (ap[sh] == y[sh]).mean():.1f} | {kinds_row(kk[sh], y[sh])[4]:.1f} | {100 * (kd == 1).mean():.1f} |"
        for D, n in ((sets[1], "gsplus"), (sets[2], "gs")):
            Q = releaned(P[n], share, tm); kd, kk, hh = three(Q); sh = kd == 0
            row += f" {100 * (kk == D['key']).mean():.1f} | {100 * sh.mean():.1f} | {100 * (kk[sh] == D['key'][sh]).mean():.1f} |"
        print(row)
    print(f"| Apple | {apr[1]:.1f} | {apr[2]:.1f} | | {apr[0]:.1f} | {apr[3]:.1f} | {apr[4]:.1f} | 100 | {apr[0]:.1f} | | {apr[4]:.1f} | | | | | | | |")

def main_club():
    """python kt_x4.py club: the netlabel club excerpts as the untrained reader hears them: how many it gave a key, the
    share of minor among those by style, and THE CLUB LEAN (see the top) -> x4_club_results.md, x4_club_lean.json."""
    sys.stdout = KS._Tee(os.path.join(kt.HERE, "x4_club_results.md"))
    rows = load_open(corpus="ia"); n = len(rows); c = collections.Counter(r["answer"] for r in rows); keyed = [r for r in rows if r["key"] >= 0]
    print(f"club excerpts read {n}: a key {c['key']} ({100 * c['key'] / n:.1f} %), home note only {c['home']} ({100 * c['home'] / n:.1f} %), not sure {c['none']} ({100 * c['none'] / n:.1f} %)")
    print(f"licences: {dict(collections.Counter(r['licence'] for r in rows))}; releases' creators {len({r['group'] for r in rows})}")
    print("\n| style (a release's own tag; a release may carry several) | excerpts | given a key | minor among those, percent |\n|---|---:|---:|---:|")
    for g, _ in collections.Counter(t for r in rows for t in r["styles"]).most_common():
        sub = [r for r in rows if g in r["styles"]]; k = [r for r in sub if r["key"] >= 0]
        print(f"| {g} | {len(sub)} | {len(k)} | {100 * np.mean([r['key'] >= 12 for r in k]):.1f} |")
    share = float(np.mean([r["key"] >= 12 for r in keyed]))
    # one creator with many releases should not set the share: the same, each creator counted once
    by = collections.defaultdict(list)
    for r in keyed: by[r["group"]].append(r["key"] >= 12)
    per = float(np.mean([np.mean(v) for v in by.values()]))
    print(f"| all | {n} | {len(keyed)} | {100 * share:.1f} |")
    print(f"\nTHE CLUB LEAN: minor share among the reader's key answers on the {len(keyed)} club excerpts it gave a key: {100 * share:.1f} percent (each of the {len(by)} creators counted once: {100 * per:.1f})")
    json.dump({"club_minor_share": share, "per_creator": per, "excerpts_with_a_key": len(keyed)}, open(os.path.join(kt.HERE, "x4_club_lean.json"), "w"))

def main_retrain(modes):
    """python kt_x4.py retrain <mode> ...: retrained models read as shipped (folded, 16-bit, no pitch shifts, THE LEAN,
    temperature on the validation artists), against the shipped reader -> x4_retrain_results.md. Writes no model file.
    The rule, fixed before these were scored: a retrained model replaces the shipped one if, showing keys on the same
    share of songs as the shipped reader does (its most confident ones), its shown keys are right more often on MTG
    and on at least one of the other two sets, and not worse by more than a point on the third."""
    import torch, kt_cnn as C
    torch.set_num_threads(1)
    share = json.load(open(os.path.join(kt.HERE, "x4_lean.json")))["lean_minor_share"]
    sets = KS.test_sets(); names = {"MTG, 1,270": "mtg", "GiantSteps+, 468": "gsplus", "GiantSteps Key, 604": "gs"}
    real = KS.with_L(KS.load_real()); va = [r for r in real if r["group"] % 5 == 0]; yv = np.array([int(r["target"].argmax()) for r in va])
    out = {}; notes = []
    for mode in modes:
        z = np.load(os.path.join(kt.CACHE, f"x4_cnn_{mode}.npz")); tm = float(z["train_minor"]); lean = float(np.log(share / (1 - share)) - np.log(tm / (1 - tm)))
        model = C.Net(); model.load_state_dict(torch.load(os.path.join(kt.CACHE, f"x4_cnn_{mode}.pt"))); model.eval(); flat = folded(model)
        flat = flat.astype("<f2").astype(np.float32)
        S = np.array([shipped_scores(C.crop(r["L"].astype(np.float32)), flat) for r in va]); lp = S - S.max(1, keepdims=True); lp = lp - np.log(np.exp(lp).sum(1, keepdims=True)); lp[:, 12:] += lean
        Tm = temperature(lp, yv, lean_weights(yv, share))
        notes.append(f"{mode}: training mix {100 * tm:.1f} percent minor, lean {lean:+.3f}, temperature {Tm:.3f}, stopped at pass {int(z['info'][2])}, exact on the validation artists {100 * (lp.argmax(1) == yv).mean():.1f}")
        for D in sets:
            f = os.path.join(kt.CACHE, f"x4_retrain_{mode}_{names[D['name']]}.npy")
            if not os.path.exists(f):
                cl = {c["id"]: c for c in C.get(names[D["name"]])}; clips = [cl[i] for i in D["ids"]]; C.load_L(clips)
                np.save(f, np.array([shipped_probs(shipped_scores(C.crop(c["L"].astype(np.float32)), flat), lean, Tm) for c in clips]))
            out[mode, D["name"]] = np.load(f)
    sys.stdout = KS._Tee(os.path.join(kt.HERE, "x4_retrain_results.md"))
    print("Retrained models read as shipped, against the shipped reader. " + "; ".join(notes) + ".")
    wins = {m: [] for m in modes}
    for D in sets:
        y = D["key"]; P0 = np.load(os.path.join(kt.CACHE, f"x4_shipped_{names[D['name']]}.npy")); kind0, k0, h0 = three(P0); cov = float((kind0 == 0).mean())
        print(f"\n**{D['name']}**\n\n| reader | key shown, percent of songs | shown keys right | shown keys' home note right | home note only, percent | those home notes right | not sure | every song given a key: exact | major | minor | shown keys right at the shipped reader's coverage ({100 * cov:.1f}) | expected by its own confidence: shown keys |\n|---|" + "---:|" * 11)
        for name, P in [("the shipped reader", P0)] + [(f"retrained: {m}", out[m, D["name"]]) for m in modes]:
            kind, k, h = three(P); v = KS.row_of(k, y); tp = top_precision(P.max(1), k, y, cov)
            print(f"| {name} | " + " | ".join(f"{x:.1f}" for x in answer_row(kind, k, h, y)) + f" | {v[0]:.1f} | {v[1]:.1f} | {v[2]:.1f} | {tp:.1f} | {100 * P.max(1)[kind == 0].mean():.1f} |")
            if name == "the shipped reader": base = tp
            else: wins[name[11:]].append(tp - base)
    print()
    for m in modes:
        d = wins[m]; ok = d[0] > 0 and max(d[1:]) > 0 and min(d[1:]) >= -1
        print(f"{m}: at the shipped reader's coverage, shown keys right {d[0]:+.1f} on MTG, {d[1]:+.1f} on GiantSteps+, {d[2]:+.1f} on GiantSteps Key: {'replaces the shipped reader by the rule' if ok else 'does not replace the shipped reader by the rule'}.")

def main_record(mode):
    """python kt_x4.py record <mode>: every recording the chosen model learned from, with its page and its licence
    -> core/.models/deckie-key-<version>-credits.tsv, beside the model's file and, like it, not in the repository
    (titles and pages name people). It is the credit CC BY asks for and the record D15 asks for; DEPENDENCIES.md,
    section 13, gives its hash and its counts."""
    import zipfile, io, csv, hashlib
    real = KS.load_real(); fsl = json.load(open(os.path.join(KS.FSL, "metadata.json")))
    z = zipfile.ZipFile(os.path.join(os.path.dirname(kt.DATA), "fmameta", "fma_metadata.zip"))
    r = csv.reader(io.TextIOWrapper(z.open("fma_metadata/raw_tracks.csv"), encoding="utf-8")); h = next(r); ix = {k: i for i, k in enumerate(h)}
    fma = {row[0]: (row[ix["track_title"]].strip(), row[ix["track_url"]] or row[ix["album_url"]] or row[ix["artist_url"]], row[ix["license_title"]], row[ix["license_url"]]) for row in r}
    rows = []
    for x in real:
        if x["source"] == "fsl":
            m = fsl[x["id"]]; lic = m.get("license", "")
            rows.append(("Freesound Loop Dataset", x["id"], m.get("name", "").strip(), f"https://freesound.org/s/{x['id']}/", x["licence"], lic, "human key label (the set's annotators)"))
        elif x["source"] == "fmak":
            t = fma[x["id"][4:]]; rows.append(("Free Music Archive (FMAK key label)", x["id"][4:], t[0], t[1], t[2], t[3], "human key label (FMAK, CC BY 4.0)"))
        else: rows.append(("Open Well-Tempered Clavier, Book 1", x["id"][3:], "", "https://welltemperedclavier.org/", "CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/", "key from the title"))
    if mode in ("mix", "pseudo", "ssl"):
        opened = load_open(); rng = np.random.default_rng(0)
        if mode == "ssl": use, how = opened, "no label (pitch-shifted pairs)"
        else:
            pse = [q for q in opened if q["key"] >= 0]; use = [pse[i] for i in rng.permutation(len(pse))[:PSEUDO_CAP]]; how = "key named by the untrained reader"
        for q in use:
            t = fma[q["id"][4:]]; rows.append(("Free Music Archive", q["id"][4:], t[0], t[1], t[2], t[3], how))
        if mode == "pseudo": rows = [x for x in rows if x[0] == "Free Music Archive"]
    out = os.path.join(kt.HERE, "..", "..", "core", ".models"); os.makedirs(out, exist_ok=True)
    clean = lambda v: " ".join(str(v).split())
    body = "source\tid\ttitle\tpage\tlicence\tlicence_page\tused_as\n" + "".join("\t".join(clean(v) for v in x) + "\n" for x in rows)
    open(os.path.join(out, "deckie-key-2b4fe8fa-credits.tsv"), "w", encoding="utf-8").write(body)
    print(len(rows), "recordings;", dict(collections.Counter(x[0] for x in rows)), "; licences", dict(collections.Counter(x[4] for x in rows).most_common(12)), "; SHA-256", hashlib.sha256(body.encode()).hexdigest())

if __name__ == "__main__":
    a = sys.argv
    if a[1] == "feats": main_feats(int(a[a.index("--jobs") + 1]) if "--jobs" in a else 4, a[a.index("--corpus") + 1] if "--corpus" in a else "fma")
    elif a[1] == "pseudo": main_pseudo()
    elif a[1] == "cnn": main_cnn(a[2], int(a[a.index("--threads") + 1]) if "--threads" in a else 4)
    elif a[1] == "report": main_report()
    elif a[1] == "ship": main_ship()
    elif a[1] == "export": main_export(a[2])
    elif a[1] == "record": main_record(a[2])
    elif a[1] == "retrain": main_retrain(a[2:])
    elif a[1] == "parity": main_parity(a[2], a[3])
    elif a[1] == "fixture": main_fixture()
    elif a[1] == "apple": main_apple()
    elif a[1] == "club": main_club()
    elif a[1] == "dj": main_dj([(float(x.split("=")[0]), x.split("=")[1]) for x in a[2:]])
