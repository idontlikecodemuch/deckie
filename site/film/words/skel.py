# /// script
# dependencies = ["numpy", "scipy", "scikit-image", "pillow"]
# ///
"""Skeleton of each rasterised word, drawn large with a coordinate grid, so strokes can be planned by eye."""
import sys, json, numpy as np
from PIL import Image, ImageDraw
from skimage.morphology import skeletonize
d = sys.argv[1]
meta = json.load(open(d + "/meta.json"))
for w in meta:
    im = np.array(Image.open(f"{d}/{w}.png").convert("L"))
    sk = skeletonize(im > 110)
    np.save(f"{d}/{w}_skel.npy", sk)
    k = 2
    out = Image.fromarray(np.where(im > 110, 70, 0).astype(np.uint8)).convert("RGB").resize((im.shape[1] * k, im.shape[0] * k), Image.NEAREST)
    dr = ImageDraw.Draw(out)
    ys, xs = np.nonzero(sk)
    for x, y in zip(xs, ys): dr.rectangle([x * k, y * k, x * k + 1, y * k + 1], fill=(255, 255, 0))
    for gx in range(0, im.shape[1], 50):
        dr.line([gx * k, 0, gx * k, out.size[1]], fill=(90, 90, 160) if gx % 100 else (150, 150, 255)); dr.text((gx * k + 3, 3), str(gx), fill=(200, 200, 255))
    for gy in range(0, im.shape[0], 50):
        dr.line([0, gy * k, out.size[0], gy * k], fill=(90, 90, 160) if gy % 100 else (150, 150, 255)); dr.text((3, gy * k + 3), str(gy), fill=(200, 200, 255))
    out.save(f"{d}/{w}_skel.png"); print(w, im.shape)
