#!/usr/bin/env python3
"""Cut AI-made sprite sheets into the per-actor atlases the Rainside room draws.

Each source sheet has four rows (down, up, left, right) of frames: idle 2, walk 4, then one or
two attack poses. The frames are not on a strict grid and some touch their neighbour, so each row
is split on its empty columns and a run that holds several frames is cut at its thinnest columns.
Every frame is placed with its feet on one anchor point and the whole actor is scaled by one
factor, so walking does not wobble. Writes art/actors/<name>.png and scripts/figure_data.gd.

Usage: python3 tools/actor_sprites.py <folder with the source sheets>
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "actors")
RES = 2 # atlas pixels per world pixel, so the art stays sharp when the window is scaled up
PAD = 2

# name: (frames per row, height of the standing front view in world px)
ACTORS = {
	"sink_riveter": (7, 50),
	"sink_furnace": (7, 50),
	"sink_arclight": (7, 50),
	"clinker": (6, 30),
	"sparkhound": (7, 50),
	"slagspitter": (7, 38),
	"slag_mortar": (7, 44),
	"linesman": (8, 58),
	"forgewarden": (7, 74),
}
# Weapons sheet, top to bottom: length in world px and the grip as a fraction of the cut-out.
WEAPONS = [("rivet_gun", 30, (0.36, 0.62)), ("slag_maul", 44, (0.12, 0.5)), ("coil_gun", 34, (0.3, 0.6))]


def runs(mask, gap):
	"""[start, end) runs of True, bridging holes up to gap long."""
	out, start, holes = [], None, 0
	for i, v in enumerate(mask):
		if v:
			if start is None:
				start = i
			holes = 0
		elif start is not None:
			holes += 1
			if holes > gap:
				out.append((start, i - holes + 1))
				start, holes = None, 0
	if start is not None:
		out.append((start, len(mask) - holes))
	return out


def split_row(alpha, n):
	"""Column ranges of the n frames in one row."""
	prof = alpha.sum(0)
	blobs = [b for b in runs(prof > 0, 4) if prof[b[0]:b[1]].sum() > 400]
	total = sum(b - a for a, b in blobs)
	est = total / n
	ks = [max(1, round((b - a) / est)) for a, b in blobs]
	while sum(ks) != n: # fix rounding on the run whose width is furthest off
		err = [(b - a) / est - k for (a, b), k in zip(blobs, ks)]
		if sum(ks) < n:
			ks[int(np.argmax(err))] += 1
		else:
			i = int(np.argmin([e if k > 1 else 9e9 for e, k in zip(err, ks)]))
			ks[i] -= 1
	frames = []
	for (a, b), k in zip(blobs, ks):
		cuts = [a]
		w = (b - a) / k
		for j in range(1, k):
			lo, hi = int(a + w * (j - 0.3)), int(a + w * (j + 0.3))
			cuts.append(lo + int(np.argmin(prof[lo:hi])))
		cuts.append(b)
		frames += list(zip(cuts[:-1], cuts[1:]))
	return frames


def cut(img, alpha, x0, x1, y0, y1):
	"""The frame's pixels trimmed to its own box, and its feet point inside that box."""
	sub = alpha[y0:y1, x0:x1]
	ys, xs = np.nonzero(sub)
	bx0, bx1, by0, by1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
	box = sub[by0:by1, bx0:bx1].astype(float)
	h = by1 - by0
	torso = box[int(h * 0.3):int(h * 0.9)]
	cx = (torso.sum(0) * np.arange(box.shape[1])).sum() / max(1.0, torso.sum())
	return img.crop((x0 + bx0, y0 + by0, x0 + bx1, y0 + by1)), (cx, h)


def build(name, src, n, height):
	img = Image.open(src).convert("RGBA")
	a = np.array(img)[..., 3] > 40
	rows = [r for r in runs(a.sum(1) > 2, 6) if r[1] - r[0] > 40]
	assert len(rows) == 4, (name, rows)
	grid = []
	for y0, y1 in rows:
		grid.append([cut(img, a, x0, x1, y0, y1) for x0, x1 in split_row(a[y0:y1], n)])
	scale = height * RES / float(np.median([f[1][1] for f in grid[0][:6]]))
	left = right = top = 0.0
	for row in grid:
		for im, (cx, h) in row:
			left, right, top = max(left, cx * scale), max(right, (im.width - cx) * scale), max(top, h * scale)
	cw, ch = int(2 * max(left, right)) + 2 * PAD, int(top) + 2 * PAD
	atlas = Image.new("RGBA", (cw * n, ch * 4), (0, 0, 0, 0))
	for r, row in enumerate(grid):
		for c, (im, (cx, h)) in enumerate(row):
			s = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
			atlas.alpha_composite(s, (c * cw + round(cw / 2 - cx * scale), r * ch + ch - PAD - s.height))
	atlas.save(os.path.join(OUT, name + ".png"))
	return {"cell": (cw, ch), "frames": n}


def weapons(src):
	from scipy import ndimage # the maul head reaches below the top of the coil gun, so cut by shape
	img = Image.open(src).convert("RGBA")
	a = np.array(img)[..., 3] > 40
	lab, _ = ndimage.label(ndimage.binary_dilation(a, iterations=2))
	parts = [(sl, i + 1) for i, sl in enumerate(ndimage.find_objects(lab)) if (lab[sl] == i + 1).sum() > 500]
	parts.sort(key=lambda p: p[0][0].start)
	assert len(parts) == len(WEAPONS), parts
	px = np.array(img)
	out = {}
	for (sl, i), (name, length, grip) in zip(parts, WEAPONS):
		piece = px[sl].copy()
		piece[lab[sl] != i] = 0
		im = Image.fromarray(piece)
		scale = length * RES / im.width
		s = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
		s.save(os.path.join(OUT, name + ".png"))
		out[name] = (s.width * grip[0], s.height * grip[1])
	return out


def write_data(figs, guns):
	lines = [
		"# Generated by tools/actor_sprites.py; do not edit by hand.",
		"class_name FigureData",
		"",
		"const RES := %d" % RES,
		"const PAD := %d" % PAD,
		"const FIGURES := {",
	]
	for k, v in figs.items():
		lines.append('\t"%s": {"cell": Vector2(%d, %d), "frames": %d},' % (k, v["cell"][0], v["cell"][1], v["frames"]))
	lines += ["}", "const WEAPONS := { # grip point in atlas pixels"]
	for k, (gx, gy) in guns.items():
		lines.append('\t"%s": Vector2(%.1f, %.1f),' % (k, gx, gy))
	lines.append("}")
	with open(os.path.join(ROOT, "scripts", "figure_data.gd"), "w") as f:
		f.write("\n".join(lines) + "\n")


def main():
	src = sys.argv[1]
	os.makedirs(OUT, exist_ok=True)
	figs = {k: build(k, os.path.join(src, k + ".png"), n, h) for k, (n, h) in ACTORS.items()}
	write_data(figs, weapons(os.path.join(src, "weapons.png")))


if __name__ == "__main__":
	main()
