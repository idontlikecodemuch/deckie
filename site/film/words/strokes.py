# /// script
# dependencies = ["numpy", "scipy", "scikit-image", "pillow"]
# ///
"""Stroke plans for the script words, and the "time maps" the film draws them from.

Each word is a list of strokes (the pen stays down within a stroke and lifts between strokes). Each stroke is a list
of segments; a segment is a run of waypoints (pixel coordinates in the word's 360 px raster) that is snapped to the
word's centreline and followed along it. Between two segments of one stroke the pen is already on paper where the
next one starts (it is retracing a line it has drawn), so that move takes no time.

Output per word: <key>_map.png, the same size as the raster. Red and green hold, for every pixel of the letterforms,
the moment (0 to 65535) at which the pen passes nearest to it; blue holds the letterform's coverage. The film shows a
pixel once the pen has passed it, so a finished word is exactly the browser's own rendering of the font.
"""
import sys, json, heapq, numpy as np
from PIL import Image
from scipy.spatial import cKDTree

LIFT = 0.07          # share of the whole word's time spent on each pen lift
WORDS = {
 "deckie": [
   # 1. D: the stem, top to foot
   [[(180,212),(150,330),(141,392)]],
   # 2. D: the bowl, from the flag at top left, over, down the right side and back along the foot to the stem
   [[(105,178),(230,140),(335,230),(300,360),(200,407),(146,400)]],
   # 3. "eckie" in one line: e (through its eye, round and out), c (up its back to the hook; then on from the join),
   #    k (up into the loop and down the stem; the foot; then out along the arm and leg), i (up; then on from the join), e
   [[(417,368),(480,340),(492,300),(455,281),(410,330),(420,388),(460,410),(530,390),(551,381)],
    [(551,381),(555,330),(590,283),(628,300),(627,322)],
    [(551,381),(580,402),(640,400),(693,372)],
    [(693,372),(695,285),(735,265),(785,150),(770,110),(730,130),(700,240),(695,285)],
    [(693,372),(695,405)],
    [(693,372),(722,353),(740,315),(795,285),(808,305),(790,350),(772,378),(800,405),(850,392),(877,386)],
    [(877,386),(882,340),(895,284)],
    [(877,386),(895,410),(935,402),(965,378)],
    [(965,378),(1030,340),(1045,300),(1010,281),(968,320),(966,378),(985,402),(1020,410),(1055,398),(1077,372)]],
   # 4. the dot of the i, last
   [[(900,210),(906,207)]],
 ],
}
Y_LOW = [[(150,105),(132,180),(148,228),(185,212),(210,192),(220,150),(232,105)],              # y: down the left arm, round, up the right arm
         [(210,192),(208,238),(196,280),(190,330),(160,390),(128,400),(112,378),(135,320),(170,288),(196,280)],   # back down, the tail and its loop
         [(208,238),(240,230),(270,210),(298,200)]]                                              # out to the o
O_LOW = [[(298,200),(318,228),(345,238),(382,222),(395,172),(375,125),(350,110),(318,122),(300,165),(298,200)],   # o: anticlockwise from the join
         [(395,172),(430,170),(463,170)]]                                                        # the bar to the u
U_LOW = [[(463,170),(475,130),(488,105)],                                                        # u: up to its first top
         [(463,170),(465,205),(480,228),(515,208),(543,192),(555,145),(568,105)]]                # down, round and up to its second top
WORDS["low_you"] = [[*Y_LOW, *O_LOW, *U_LOW, [(543,192),(547,232)]]]                            # and down the last stem: one stroke, no lift
WORDS["low_your"] = [[*Y_LOW, *O_LOW, *U_LOW, [(543,192),(546,220),(565,238),(600,227),(635,215)],   # out to the r
                      [(635,215),(637,150),(655,103)], [(635,198),(637,240)],                    # r: up its stem; its foot
                      [(635,198),(665,182),(683,148),(700,133),(728,122),(730,160),(745,160)]]]  # r: over the shoulder to the drop
Y_CAP = [[(103,163),(135,128),(182,112),(204,140),(198,215),(188,268),(205,305),(250,305),(292,283),(315,253),(345,240),(355,185),(365,115)],
         [(345,240),(342,290),(338,335),(330,362),(322,410),(295,465),(240,495),(205,478),(202,450),(250,390),(300,363),(330,360)],
         [(338,335),(400,325),(432,318)]]
O_CAP = [[(432,320),(448,352),(478,365),(510,355),(528,325),(530,297),(512,258),(490,238),(458,243),(437,285),(432,320)],
         [(530,297),(570,295),(598,293)]]
U_CAP = [[(598,293),(606,255),(620,228)],
         [(598,293),(600,335),(612,352),(650,335),(678,312),(688,265),(700,228)]]
WORDS["cap_you"] = [[*Y_CAP, *O_CAP, *U_CAP, [(678,312),(681,372)]]]
WORDS["cap_your"] = [[*Y_CAP, *O_CAP, *U_CAP, [(678,312),(682,345),(698,360),(735,350),(768,338)],
                      [(768,338),(772,270),(788,225)], [(768,322),(770,360)],
                      [(768,322),(798,305),(818,272),(835,256),(862,245),(864,283),(882,283)]]]

# "Desk": D as in Deckie (stem, lift, bowl, lift); then "esk" in one line: e through its eye and out, up into the s,
# to its top and back, down its back, the tail to the left and back, on to the k; k as in Deckie.
WORDS["desk"] = [
   [[(180,212),(150,330),(141,392)]],
   [[(105,178),(230,140),(335,230),(300,360),(200,407),(146,400)]],
   [[(417,368),(480,340),(492,300),(455,281),(410,330),(420,388),(460,410),(530,390),(572,330),(592,322)],
    [(592,322),(600,285),(620,265)],
    [(592,322),(620,360),(632,402)],
    [(632,402),(610,410),(590,410)],
    [(632,402),(680,398),(715,372)],
    [(715,372),(716,290),(750,268),(800,160),(790,112),(760,112),(725,220),(716,290)],
    [(715,372),(716,410)],
    [(715,372),(745,352),(765,310),(790,292),(820,285),(830,305),(820,345),(795,362),(790,385),(810,405),(832,408)]],
]
# "Booth": B stem; lift; B's two bowls from the flag, with the short bar where they meet; lift; "ooth" in one line
# (each o anticlockwise, the bar between them, up and round the t's loop and down, on to the h: loop, foot, arch);
# lift; the t's crossbar last.
WORDS["booth"] = [
   [[(192,210),(165,330),(150,392)]],
   [[(105,183),(230,140),(310,140),(362,182),(352,220),(300,252),(290,268)],
    [(290,268),(247,270)],
    [(290,268),(322,318),(316,368),(270,395),(200,402),(156,398)]],
   [[(476,286),(455,282),(430,300),(405,345),(415,390),(445,410),(470,405),(495,375),(500,342),(488,310),(476,286)],
    [(500,342),(530,342),(562,342)],
    [(562,342),(565,375),(590,405),(615,410),(650,385),(662,342),(640,285),(615,282),(590,290),(567,320),(562,342)],
    [(662,342),(700,340),(750,333)],
    [(750,333),(755,272),(770,200),(800,140),(825,133),(838,170),(825,220),(800,255),(792,272)],
    [(750,333),(755,370),(775,400),(805,408),(850,395),(887,372)],
    [(887,372),(888,285),(920,265),(960,180),(975,130),(955,108),(925,120),(895,220),(888,285)],
    [(887,372),(888,405)],
    [(887,372),(915,355),(930,320),(950,300),(982,292),(983,330),(978,380),(975,400)]],
   [[(718,275),(755,272),(792,274),(845,268)]],
]

def graph_path(sk, tree, pts, a, b):
    """Shortest way along the centreline from the pixel nearest a to the pixel nearest b."""
    ia, ib = tree.query(a)[1], tree.query(b)[1]
    if ia == ib: return [ia]
    H, W = sk.shape
    idx = {tuple(p): i for i, p in enumerate(pts)}
    dist = {ia: 0.0}; prev = {}; pq = [(0.0, ia)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == ib: break
        if d > dist.get(u, 1e18): continue
        x, y = pts[u]
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if dx == 0 and dy == 0: continue
                v = idx.get((x + dx, y + dy))
                if v is None: continue
                nd = d + (1.41421 if dx and dy else 1.0)
                if nd < dist.get(v, 1e18): dist[v] = nd; prev[v] = u; heapq.heappush(pq, (nd, v))
    if ib not in prev: raise SystemExit(f"no centreline path from {a} to {b} (snapped {tuple(pts[ia])} -> {tuple(pts[ib])})")
    out = [ib]
    while out[-1] != ia: out.append(prev[out[-1]])
    return out[::-1]

def build(d, key, strokes, meta):
    cov = np.array(Image.open(f"{d}/{key}.png").convert("L"))
    sk = np.load(f"{d}/{key}_skel.npy")
    ys, xs = np.nonzero(sk); pts = np.stack([xs, ys], 1); tree = cKDTree(pts)
    runs = []                                    # per stroke: list of (points, cumulative length)
    for st in strokes:
        segs = []
        for wp in st:
            ids = []
            for a, b in zip(wp[:-1], wp[1:]):
                p = graph_path(sk, tree, pts, a, b); ids += p if not ids else p[1:]
            P = pts[ids].astype(float)
            segs.append(P)
        runs.append(segs)
    lens = [sum(max(np.sum(np.hypot(*np.diff(P, axis=0).T)), 1.0) for P in segs) for segs in runs]
    # a very short stroke (the dot) still needs a beat of its own
    lens_t = [max(L, 0.035 * sum(lens)) for L in lens]
    lifts = LIFT * (len(runs) - 1); total = sum(lens_t)
    allP, allT, table, t = [], [], [], 0.0
    for si, (segs, L, Lt) in enumerate(zip(runs, lens, lens_t)):
        t0 = t; share = (1 - lifts) * Lt / total; done = 0.0
        for P in segs:
            seg = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(P, axis=0).T))]) if len(P) > 1 else np.zeros(1)
            allP.append(P); allT.append(t0 + share * (done + seg) / max(L, 1e-9)); done += seg[-1] if len(P) > 1 else 0
        t = t0 + share
        table.append(dict(stroke=si + 1, start=round(t0, 3), end=round(t, 3), length_px=round(L)))
        t += LIFT if si < len(runs) - 1 else 0
    allP = np.concatenate(allP); allT = np.concatenate(allT)
    # centreline pixels the plan never visits would never be drawn: report them
    far = tree.query(allP)[0]  # (unused) keep tree warm
    miss = cKDTree(allP).query(pts)[0]
    missed = int((miss > 4).sum())
    ptree = cKDTree(allP)
    yy, xx = np.nonzero(cov > 0)
    dd, ii = ptree.query(np.stack([xx, yy], 1).astype(float))
    tm = np.zeros(cov.shape, float); tm[yy, xx] = allT[ii]
    # the dot: grow it outwards from its centre instead of all at once
    for si, (segs, L) in enumerate(zip(runs, lens)):
        if L < 20:
            c = np.concatenate(segs).mean(0); r = table[si]
            near = (np.hypot(xx - c[0], yy - c[1]) < 70) & (np.abs(allT[ii] - (r["start"] + r["end"]) / 2) <= (r["end"] - r["start"]) / 2 + 1e-6)
            rad = np.hypot(xx[near] - c[0], yy[near] - c[1]); tm[yy[near], xx[near]] = r["start"] + (r["end"] - r["start"]) * rad / max(rad.max(), 1)
    q = np.clip(np.round(tm * 65535), 0, 65535).astype(np.uint16)
    out = np.zeros(cov.shape + (3,), np.uint8); out[..., 0] = q >> 8; out[..., 1] = q & 255; out[..., 2] = cov
    Image.fromarray(out, "RGB").save(f"{d}/{key}_map.png")
    # proof sheet: the word at eight moments of the draw
    steps = [0.08, 0.2, 0.35, 0.5, 0.65, 0.8, 0.92, 1.0]
    sheet = Image.new("L", (cov.shape[1] * 4, cov.shape[0] * 2))
    for n, p in enumerate(steps):
        a = np.clip((p * 1.03 - tm) / 0.03, 0, 1) * cov
        sheet.paste(Image.fromarray(a.astype(np.uint8)), ((n % 4) * cov.shape[1], (n // 4) * cov.shape[0]))
    sheet.save(f"{d}/{key}_proof.png")
    meta[key]["strokes"] = table
    print(key, "strokes", len(runs), "centreline px missed", missed, "of", len(pts), table)

d = sys.argv[1]
meta = json.load(open(d + "/meta.json"))
for key, strokes in WORDS.items(): build(d, key, strokes, meta)
json.dump(meta, open(d + "/words.json", "w"), indent=1)
