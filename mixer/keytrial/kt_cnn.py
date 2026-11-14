#!/usr/bin/env python3
"""Key trial, phase 3: a small convolutional key model, FOR EVALUATION ONLY. Nothing trained here ships: the labels of
the training sets are CC BY-SA 4.0 and the audio is Beatport's and the labels'. No weights are committed.

  python kt_cnn.py cv     [--threads 3]    five artist-grouped folds on GiantSteps-MTG-key; every clip is scored by a
                                           model that never saw it or its artist  -> $CACHE/cnn_cv_mtg.npz
  python kt_cnn.py cross  [--threads 3]    train on MTG, score GiantSteps Key / GiantSteps+; train on GiantSteps Key,
                                           score MTG                              -> $CACHE/cnn_cross_*.npz
  python kt_cnn.py sections                each clip read in three parts by the model that never saw it (confidence signal)
  python kt_cnn.py cost                    parameters, operations, CPU time for a five-minute song (ONNX Runtime)

Design, after Korzeniowski and Widmer (EUSIPCO 2017: five 5x5 convolution layers, a dense projection per frame,
averaged over time; ISMIR 2018: stacked convolutions with pooling, trained on short snippets, pitch-shifted -4 to +7
semitones), scaled to a laptop CPU. Input: kt_extract's log-frequency spectrogram, 126 bins (55 Hz to 2,093 Hz, 24 to
the octave), 5 frames a second. Four blocks of two 3x3 convolutions (first layer 5x5) with batch normalisation and ELU,
2x2 max pooling after the first three; then one layer that reads the whole remaining frequency axis per time step (the
'dense projection per frame'), a 1x1 layer to the 24 keys, and the mean over time. Trained on random 30 s snippets with
a random shift of -4..+7 semitones (the spectrogram window moves two bins a semitone and the label's home note moves
with it), Adam, cross-entropy. Every setting below was fixed before any fold was scored; the only thing chosen by
measurement is the stopping epoch, on a validation slice of artists inside the training folds."""
import os, sys, time
import numpy as np
import torch, torch.nn as nn, torch.nn.functional as Fn
import kt
from kt_extract import NB_MODEL, BASE, SHIFT_LO, SHIFT_HI

WIDTH = 12            # feature maps in the first block (doubling to 8x)
SNIP = 150            # 30 s at 5 frames a second
EPOCHS = 120
BATCH = 32
LR, WD = 1e-3, 1e-4
DROP = 0.2
VAL_EVERY = 4
VAL_MOD = 7           # artist groups with number % 7 == 0 inside the training folds are the validation slice

class Net(nn.Module):
    def __init__(self, c=WIDTH, drop=DROP):
        super().__init__()
        def block(i, o, k1=3):
            return nn.Sequential(nn.Conv2d(i, o, k1, padding=k1 // 2, bias=False), nn.BatchNorm2d(o), nn.ELU(),
                                 nn.Conv2d(o, o, 3, padding=1, bias=False), nn.BatchNorm2d(o), nn.ELU())
        self.norm = nn.BatchNorm2d(1)
        self.b1, self.b2, self.b3, self.b4 = block(1, c, 5), block(c, 2 * c), block(2 * c, 4 * c), block(4 * c, 8 * c)
        self.drop = nn.Dropout2d(drop)
        self.proj = nn.Conv2d(8 * c, 48, (1, NB_MODEL // 8), bias=False)      # reads the whole frequency axis per time step
        self.pbn = nn.BatchNorm2d(48)
        self.out = nn.Conv2d(48, 24, 1)
    def forward(self, x):                      # x: (N, 1, T, 126)
        x = self.norm(x)
        x = self.drop(Fn.max_pool2d(self.b1(x), 2))
        x = self.drop(Fn.max_pool2d(self.b2(x), 2))
        x = self.drop(Fn.max_pool2d(self.b3(x), 2))
        x = self.drop(self.b4(x))
        x = Fn.elu(self.pbn(self.proj(x)))
        return self.out(x).mean(dim=(2, 3))    # (N, 24)

def load_L(clips):
    for c in clips:
        if "L" not in c: c["L"] = np.load(os.path.join(kt.CACHE, "feat", c["id"] + ".npz"))["L"]
    return clips

def crop(L, shift=0): return L[:, BASE - 2 * shift: BASE - 2 * shift + NB_MODEL]

def batch(clips, rng):
    X = np.zeros((len(clips), 1, SNIP, NB_MODEL), np.float32); y = np.zeros(len(clips), np.int64)
    for i, c in enumerate(clips):
        s = int(rng.integers(SHIFT_LO, SHIFT_HI + 1)); L = crop(c["L"], s); n = L.shape[0]
        if n >= SNIP: t0 = int(rng.integers(0, n - SNIP + 1)); X[i, 0] = L[t0:t0 + SNIP]
        else: X[i, 0] = np.resize(L, (SNIP, NB_MODEL))
        y[i] = (c["key"] % 12 + s) % 12 + 12 * (c["key"] // 12)
    return torch.from_numpy(X), torch.from_numpy(y)

@torch.no_grad()
def predict(model, clips, shifts=(0,)):
    """(N, 24) mean log-probabilities over whole clips. With several shifts the clip is read at each and the answers
    are rotated back to the clip's own pitch before averaging."""
    model.eval(); out = np.zeros((len(clips), 24), np.float32)
    for i, c in enumerate(clips):
        acc = np.zeros(24)
        for s in shifts:
            x = torch.from_numpy(crop(c["L"], s).astype(np.float32))[None, None]
            lp = Fn.log_softmax(model(x), dim=1)[0].numpy()
            acc += np.concatenate([np.roll(lp[:12], -s), np.roll(lp[12:], -s)])
        out[i] = acc / len(shifts)
    return out

def train(tr, va, seed, tag, epochs=EPOCHS):
    torch.manual_seed(seed); rng = np.random.default_rng(seed)
    model = Net(); opt = torch.optim.Adam(model.parameters(), lr=LR, weight_decay=WD)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=LR, total_steps=epochs * ((len(tr) + BATCH - 1) // BATCH))
    best = (-1, None, 0); t0 = time.time(); yv = np.array([c["key"] for c in va])
    for ep in range(1, epochs + 1):
        model.train(); order = rng.permutation(len(tr)); tot = 0.0
        for b in range(0, len(tr), BATCH):
            X, y = batch([tr[i] for i in order[b:b + BATCH]], rng)
            loss = Fn.cross_entropy(model(X), y); opt.zero_grad(); loss.backward(); opt.step(); sched.step(); tot += float(loss) * len(y)
        if ep % VAL_EVERY == 0 or ep == epochs:
            acc = float((predict(model, va).argmax(1) == yv).mean()) if len(va) else 0.0
            if acc >= best[0] and ep >= epochs // 3: best = (acc, {k: v.clone() for k, v in model.state_dict().items()}, ep)
            print(f"[{tag}] epoch {ep:3d} loss {tot / len(tr):.3f} val exact {100 * acc:.1f} (best {100 * best[0]:.1f} at {best[2]}) {time.time() - t0:.0f}s", flush=True)
    model.load_state_dict(best[1]); model.eval()
    return model, best[2], time.time() - t0

def split(clips):
    tr = [c for c in clips if c["group"] % VAL_MOD != 0]; va = [c for c in clips if c["group"] % VAL_MOD == 0]; return tr, va

def get(name, key="key"):
    allc = kt.load(name); fold, grp = kt.folds(allc)
    for c, f, g in zip(allc, fold, grp): c["fold"] = f; c["group"] = g
    have = [c for c in allc if os.path.exists(os.path.join(kt.CACHE, "feat", c["id"] + ".npz"))]
    return have

TTA = tuple(range(SHIFT_LO, SHIFT_HI + 1))

def main_cv():
    clips = load_L([c for c in get("mtg") if c["key"] is not None])
    ids = np.array([c["id"] for c in clips]); lp = np.zeros((len(clips), 24), np.float32); lp12 = np.zeros_like(lp); info = []
    for f in range(kt.NFOLD):
        te = [i for i, c in enumerate(clips) if c["fold"] == f]
        tr, va = split([c for c in clips if c["fold"] != f])
        model, ep, secs = train(tr, va, 100 + f, f"fold {f}")
        tc = [clips[i] for i in te]
        lp[te] = predict(model, tc); lp12[te] = predict(model, tc, TTA)
        y = np.array([c["key"] for c in tc])
        info.append((f, len(tr), len(va), len(te), ep, secs))
        print(f"[fold {f}] train {len(tr)} val {len(va)} test {len(te)} stop epoch {ep} {secs:.0f}s test exact {100 * (lp[te].argmax(1) == y).mean():.1f} "
              f"(12 shifts averaged {100 * (lp12[te].argmax(1) == y).mean():.1f})", flush=True)
        np.savez_compressed(os.path.join(kt.CACHE, "cnn_cv_mtg.npz"), ids=ids, lp=lp, lp12=lp12, done=np.array(f), info=np.array(info))
        torch.save(model.state_dict(), os.path.join(kt.CACHE, f"cnn_fold{f}.pt"))

def main_cross():
    mtg = load_L([c for c in get("mtg") if c["key"] is not None])
    gs = load_L([c for c in get("gs") if c["key"] is not None])
    gsp = load_L(get("gsplus"))
    gnames = set().union(*[c["names"] for c in gs + gsp])
    clean = [c for c in mtg if not (c["names"] & gnames)]
    print(f"MTG clips {len(mtg)}, sharing no artist or remixer name with the GiantSteps clips {len(clean)}", flush=True)
    tr, va = split(clean)
    model, ep, secs = train(tr, va, 200, "mtg->gs")
    torch.save(model.state_dict(), os.path.join(kt.CACHE, "cnn_mtg.pt"))
    np.savez_compressed(os.path.join(kt.CACHE, "cnn_cross_mtg_to_gs.npz"), gs_ids=np.array([c["id"] for c in gs]), gs_lp=predict(model, gs), gs_lp12=predict(model, gs, TTA),
                        gsp_ids=np.array([c["id"] for c in gsp]), gsp_lp=predict(model, gsp), gsp_lp12=predict(model, gsp, TTA), info=np.array([len(tr), len(va), ep, secs]))
    mnames = set().union(*[c["names"] for c in mtg])
    gclean = [c for c in gs if not (c["names"] & mnames)]
    print(f"GiantSteps Key clips {len(gs)}, sharing no name with MTG {len(gclean)}", flush=True)
    tr, va = split(gclean)
    model, ep, secs = train(tr, va, 201, "gs->mtg")
    np.savez_compressed(os.path.join(kt.CACHE, "cnn_cross_gs_to_mtg.npz"), ids=np.array([c["id"] for c in mtg]), lp=predict(model, mtg), lp12=predict(model, mtg, TTA),
                        info=np.array([len(tr), len(va), ep, secs]))

def main_sections():
    """Each clip cut in three equal parts, each read alone (12 shifts averaged) by the model that never saw the clip:
    the stability signal for the confidence tables."""
    def thirds(model, clips):
        out = np.zeros((len(clips), 3, 24), np.float32)
        for i, c in enumerate(clips):
            T = c["L"].shape[0]
            out[i] = predict(model, [{"L": c["L"][s * T // 3:(s + 1) * T // 3]} for s in range(3)], TTA)
        return out
    mtg = load_L([c for c in get("mtg") if c["key"] is not None]); sec = np.zeros((len(mtg), 3, 24), np.float32)
    for f in range(kt.NFOLD):
        model = Net(); model.load_state_dict(torch.load(os.path.join(kt.CACHE, f"cnn_fold{f}.pt"))); model.eval()
        te = [i for i, c in enumerate(mtg) if c["fold"] == f]; sec[te] = thirds(model, [mtg[i] for i in te])
    res = {"mtg_ids": np.array([c["id"] for c in mtg]), "mtg_sec": sec}
    p = os.path.join(kt.CACHE, "cnn_mtg.pt")
    if os.path.exists(p):
        model = Net(); model.load_state_dict(torch.load(p)); model.eval()
        for pre, name in (("gs", "gs"), ("gsp", "gsplus")):
            cl = load_L(get(name)); res[pre + "_ids"] = np.array([c["id"] for c in cl]); res[pre + "_sec"] = thirds(model, cl)
    np.savez_compressed(os.path.join(kt.CACHE, "cnn_sections.npz"), **res)

def main_cost():
    import onnxruntime as ort
    model = Net().eval(); n = sum(p.numel() for p in model.parameters())
    x = torch.zeros(1, 1, 1500, NB_MODEL)                                     # a five-minute song at 5 frames a second
    path = os.path.join(kt.CACHE, "cnn_cost.onnx")
    torch.onnx.export(model, x, path, input_names=["x"], output_names=["y"], dynamic_axes={"x": {2: "T"}}, opset_version=17, dynamo=False)
    size = os.path.getsize(path)
    for threads in (1, 4):
        so = ort.SessionOptions(); so.intra_op_num_threads = threads
        s = ort.InferenceSession(path, so, providers=["CPUExecutionProvider"]); xn = x.numpy()
        s.run(None, {"x": xn}); t0 = time.time()
        for _ in range(5): s.run(None, {"x": xn})
        print(f"ONNX Runtime, {threads} thread(s): {(time.time() - t0) / 5:.3f} s for a five-minute song (model only)")
    # the front end: one 16,384-point FFT every 0.2 s and a filterbank product
    import kt_extract as KE
    y = np.random.default_rng(0).standard_normal(44100 * 300).astype(np.float32); KE.logspec(y[:44100])
    t0 = time.time(); KE.logspec(y); print(f"front end (numpy FFT, one thread): {time.time() - t0:.3f} s for a five-minute song")
    print(f"parameters {n}, ONNX file {size / 1e6:.2f} MB (float32)")

if __name__ == "__main__":
    a = sys.argv
    torch.set_num_threads(int(a[a.index("--threads") + 1]) if "--threads" in a else 3)
    {"cv": main_cv, "cross": main_cross, "cost": main_cost, "sections": main_sections}[a[1]]()
