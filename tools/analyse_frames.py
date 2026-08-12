#!/usr/bin/env python3
"""Look for flicker and leftover pixels in a per-frame capture.

Builds a static background (the per-pixel mode across the sequence), then
reports the moving blobs in each frame. A sprite that vanishes, shrinks or
leaves debris shows up as a break in the pattern.

    python3 tools/analyse_frames.py shots/frames
"""
import glob, sys
import numpy as np
from PIL import Image

d = sys.argv[1] if len(sys.argv) > 1 else "shots/frames"
files = sorted(glob.glob(f"{d}/f*.png"))
arr = np.stack([np.asarray(Image.open(f).convert("RGB")).astype(np.int16) for f in files])
n, h, w, _ = arr.shape
print(f"{n} frames, {w}x{h}")

# Per-pixel median is the static scenery: sprites are a minority everywhere.
bg = np.median(arr, axis=0)
Image.fromarray(bg.astype(np.uint8)).save(f"{d}/_background.png")

def blobs(mask, gap=10):
    """Group set pixels into row-bands, then column-runs within each band."""
    ys, xs = np.nonzero(mask)
    if len(ys) == 0:
        return []
    order = np.argsort(ys)
    ys, xs = ys[order], xs[order]
    out, start = [], 0
    for k in range(1, len(ys) + 1):
        if k == len(ys) or ys[k] - ys[k - 1] > gap:
            by, bx = ys[start:k], xs[start:k]
            xo = np.argsort(bx)
            bx2, by2 = bx[xo], by[xo]
            s2 = 0
            for j in range(1, len(bx2) + 1):
                if j == len(bx2) or bx2[j] - bx2[j - 1] > gap:
                    out.append((by2[s2:j].min(), by2[s2:j].max(),
                                bx2[s2:j].min(), bx2[s2:j].max(), j - s2))
                    s2 = j
            start = k
    return out

for i in range(n):
    mask = np.abs(arr[i] - bg).sum(axis=2) > 40
    bs = blobs(mask)
    desc = "  ".join(f"[y{y0}-{y1} x{x0}-{x1} n{cnt}]" for y0, y1, x0, x1, cnt in bs)
    print(f"{i:3d} {len(bs)} blob(s) {desc}")
