#!/usr/bin/env python3
"""Key trial: learned key profiles, FOR EVALUATION ONLY. The smallest trained whole-key reader there is: the profile
match of letter R, with the profile numbers learned from labelled clips instead of taken from a paper.

For each source chroma (12 numbers, scaled to sum 12) there is one learned major profile and one learned minor profile
(12 numbers each, plus one offset for minor). A key's score is the sum over sources of profile . chroma, with the chroma
rotated to that key's home note, so the same numbers serve all twelve home notes and a clip teaches all of them at
once. The 24 scores go through a softmax; the fit is plain multinomial logistic regression (L-BFGS, weight decay 0.01,
fixed before the run). 'B' uses row B's chroma alone (25 numbers); 'AB' rows A and B (49); 'all' adds the bass,
middle and melody registers, the bass line and the top line (169)."""
import numpy as np, torch

SRC = {"B": ("c_B",), "AB": ("c_A", "c_B"), "all": ("c_A", "c_B", "r_bass", "r_mid", "r_mel", "bassline", "topline")}
WD = 0.01

def design(F, which):
    """(N, 12 home notes, sources * 12): each source rotated to each home note."""
    parts = []
    for k in SRC[which]:
        X = F[k] / (F[k].sum(1, keepdims=True) + 1e-12) * 12
        parts.append(np.stack([np.roll(X, -t, axis=1) for t in range(12)], axis=1))
    return torch.tensor(np.concatenate(parts, axis=2), dtype=torch.float64)

def scores(X, W, b):
    maj = X @ W[0]; mi = X @ W[1] + b                 # (N, 12) each
    return torch.cat([maj, mi], dim=1)                # key = home note + 12 * minor

def fit(F, key, which, equal_modes=False):
    """equal_modes: major and minor clips weigh the same in the fit, so the learned minor offset carries no share of
    the training set's mix of modes (a set that is 70 or 85 percent minor otherwise teaches 'when in doubt, minor')."""
    torch.set_num_threads(1); torch.manual_seed(0)
    X = design(F, which); y = torch.tensor(key, dtype=torch.long)
    W = torch.zeros((2, X.shape[2]), dtype=torch.float64, requires_grad=True); b = torch.zeros(1, dtype=torch.float64, requires_grad=True)
    opt = torch.optim.LBFGS([W, b], max_iter=500, tolerance_grad=1e-9, tolerance_change=1e-12, line_search_fn="strong_wolfe")
    mi = (y >= 12).double(); w = torch.ones(len(y), dtype=torch.float64)
    if equal_modes: w = mi / (2 * mi.mean()) + (1 - mi) / (2 * (1 - mi.mean()))
    def closure():
        opt.zero_grad(); loss = (torch.nn.functional.cross_entropy(scores(X, W, b), y, reduction="none") * w).mean() + WD * (W ** 2).sum(); loss.backward(); return loss
    opt.step(closure)
    return W.detach(), b.detach()

def predict(F, model, which):
    with torch.no_grad(): return torch.log_softmax(scores(design(F, which), *model), dim=1).numpy()
