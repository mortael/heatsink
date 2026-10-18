#!/usr/bin/env python3
"""Paints the Rainside rooms: the foundry's outdoor yard on a rainy night, seen in 3/4 top-down view.

Everything else in HEATSINK is drawn in code at runtime. These rooms need per-pixel texture,
baked light and wet reflections, which are too slow to paint in GDScript on a phone, so this
script paints them once and the game loads the PNGs.

Run from the repo root:  python3 tools/street_art.py
Writes art/street/<layout>_{base,over,glow,neon}.png and scripts/street_data.gd.
Needs numpy and Pillow. Output is deterministic (fixed seeds).

Layers per layout (all 640x380, one art pixel = 2 world px, drawn with nearest filtering):
  base  the ground, buildings and props with their light baked in (drawn under everything)
  over  the parts of tall props that stand in front of the tiles north of them (coolant tanks,
        floodlight heads, crate stacks): drawn above actors and faded around the player
  glow  soft halos around light sources, drawn additive (bloom stand-in for phones and web)
  neon  the neon sign's tubes, drawn additive so the game can make them flicker
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

T = 24  # art px per tile (a world tile is 48 px)
ROOM_W, ROOM_H = 24, 13
OX, OY = 32, 28  # art px of room tile (0, 0)
W, H = 640, 380
WORLD_OFFSET = (-2 * OX, -2 * OY)  # where art pixel (0, 0) sits in world px
FACADE_TOP = OY + 14  # art y where the facade wall meets the roof eave
FACADE_BASE = OY + 3 * T  # art y where the facade meets the sidewalk
DOOR_TILES = [6, 12, 18]
# The night tint the game's CanvasModulate puts over this room; the base is painted brighter
# by the inverse so it ends up as painted while actors still read as lit by night.
NIGHT = np.array([0.62, 0.66, 0.84], np.float32)
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def tx(x):
	return OX + x * T


def ty(y):
	return OY + y * T


def col(*c):
	return np.array(c, np.float32)


def noise(h, w, scale, rng):
	"""Smooth value noise in 0..1."""
	sh, sw = max(2, h // scale + 2), max(2, w // scale + 2)
	small = (rng.random((sh, sw)) * 255).astype(np.uint8)
	img = Image.fromarray(small, "L").resize((sw * scale, sh * scale), Image.BICUBIC)
	return np.asarray(img, np.float32)[:h, :w] / 255.0


def blur(a, r):
	"""Gaussian blur of a float HxW or HxWx3 array (values may exceed 1)."""
	if a.ndim == 2:
		m = max(float(a.max()), 1e-6)
		img = Image.fromarray((a / m * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(r))
		return np.asarray(img, np.float32) / 255.0 * m
	return np.stack([blur(a[..., i], r) for i in range(3)], -1)


class Scene:
	"""One layout being painted. alb is lit by the light map; emis glows on its own."""

	def __init__(self, seed):
		self.rng = np.random.default_rng(seed)
		self.alb = np.zeros((H, W, 3), np.float32)
		self.emis = np.zeros((H, W, 3), np.float32)
		self.gnd = np.zeros((H, W), np.float32)  # 1 where open, wet ground shows (takes reflections)
		self.wet = np.zeros((H, W), np.float32)
		self.ov_alb = np.zeros((H, W, 3), np.float32)
		self.ov_emis = np.zeros((H, W, 3), np.float32)
		self.ov_a = np.zeros((H, W), np.float32)
		self.amb = np.zeros((H, W, 3), np.float32)  # per-pixel ambient (sky light)
		self.lights = []  # (x, y, ground x, ground y, colour, radius, strength)
		self.reflect = []  # (x, ground y, height, colour, strength, width)
		self.halos = []  # (x, y, radius, colour, strength) for the glow layer
		self.neon = np.zeros((H, W, 3), np.float32)

	# ------------------------------------------------------------ painting primitives

	def put(self, x0, y0, rgb, alpha, emis=None, ground=0.0, over_from=None):
		"""Composites a sprite (h x w x 3 albedo + h x w alpha) with its top-left at (x0, y0).
		Rows above art y `over_from` also go to the overlay layer."""
		h, w = alpha.shape
		X0, Y0 = max(0, x0), max(0, y0)
		X1, Y1 = min(W, x0 + w), min(H, y0 + h)
		if X1 <= X0 or Y1 <= Y0:
			return
		sx, sy = X0 - x0, Y0 - y0
		a = alpha[sy:sy + Y1 - Y0, sx:sx + X1 - X0][..., None]
		c = rgb[sy:sy + Y1 - Y0, sx:sx + X1 - X0]
		e = emis[sy:sy + Y1 - Y0, sx:sx + X1 - X0] if emis is not None else np.zeros_like(c)
		reg = (slice(Y0, Y1), slice(X0, X1))
		self.alb[reg] = self.alb[reg] * (1 - a) + c * a
		self.emis[reg] = self.emis[reg] * (1 - a) + e * a
		self.gnd[reg] = self.gnd[reg] * (1 - a[..., 0]) + ground * a[..., 0]
		if over_from is not None:
			oy1 = min(Y1, over_from)
			if oy1 > Y0:
				ra = a[: oy1 - Y0]
				oreg = (slice(Y0, oy1), slice(X0, X1))
				self.ov_alb[oreg] = self.ov_alb[oreg] * (1 - ra) + c[: oy1 - Y0] * ra
				self.ov_emis[oreg] = self.ov_emis[oreg] * (1 - ra) + e[: oy1 - Y0] * ra
				self.ov_a[oreg] = self.ov_a[oreg] * (1 - ra[..., 0]) + ra[..., 0]

	def sky(self, x0, y0, mask, top, bottom):
		"""Foliage and roofs catch the sky from above: ambient light that fades from top to bottom."""
		h, w = mask.shape
		X0, Y0, X1, Y1 = max(0, x0), max(0, y0), min(W, x0 + w), min(H, y0 + h)
		if X1 <= X0 or Y1 <= Y0:
			return
		m = mask[Y0 - y0:Y1 - y0, X0 - x0:X1 - x0][..., None] > 0.3
		k = np.linspace(0, 1, h, dtype=np.float32)[Y0 - y0:Y1 - y0, None, None]
		a = top * (1 - k) + bottom * k
		reg = (slice(Y0, Y1), slice(X0, X1))
		self.amb[reg] = np.where(m, np.broadcast_to(a, m.shape[:2] + (3,)), self.amb[reg])

	def shade(self, x0, y0, x1, y1, k, soft=3):
		"""Darkens the ground in a rectangle with soft edges (contact shadow / occlusion)."""
		m = np.zeros((H, W), np.float32)
		m[max(0, y0):min(H, y1), max(0, x0):min(W, x1)] = 1.0
		m = blur(m, soft)
		self.alb *= (1 - k * m)[..., None]

	def light(self, x, y, c, radius, strength, gx=None, gy=None, reflect=True, halo=True, rwidth=1.6):
		gx = x if gx is None else gx
		gy = y if gy is None else gy
		self.lights.append((x, y, gx, gy, c, radius, strength))
		if reflect:
			self.reflect.append((x, gy, max(4.0, gy - y), c, strength, rwidth))
		if halo:
			self.halos.append((x, y, radius * 0.35, c, strength))

	# ------------------------------------------------------------ final composite

	def render(self):
		yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
		lightmap = self.amb.copy()
		for (x, y, gx, gy, c, r, s) in self.lights:
			# Ground pixels take light from where the lamp stands; walls and props from the lamp itself.
			dx = np.where(self.gnd > 0.5, xx - gx, xx - x)
			dy = np.where(self.gnd > 0.5, yy - gy, yy - y)
			d2 = (dx * dx + dy * dy) / (r * r)
			f = s / (1.0 + 6.0 * d2) * np.clip(1.0 - d2 * 0.25, 0, 1)
			lightmap += f[..., None] * c
		img = self.alb * lightmap + self.emis
		img += self._reflections(yy, xx)
		over = self.ov_alb * lightmap + self.ov_emis
		# Rain haze: a faint blue lift that grows towards the bottom of the view.
		haze = (0.012 + 0.02 * (yy / H))[..., None] * col(0.5, 0.65, 1.0)
		img += haze
		over += haze
		# Vignette outside the room.
		rx = np.clip(np.maximum(OX - xx, xx - (OX + ROOM_W * T)) / 40.0, 0, 1)
		ry = np.clip(np.maximum(-yy, yy - (OY + ROOM_H * T)) / 40.0, 0, 1)
		vig = 1.0 - 0.75 * np.maximum(rx, ry) ** 1.2
		img *= vig[..., None]
		over *= vig[..., None]
		glow = np.zeros((H, W, 3), np.float32)
		for (x, y, r, c, s) in self.halos:
			d2 = ((xx - x) ** 2 + (yy - y) ** 2) / (r * r)
			glow += (s * 0.55 * np.exp(-d2 * 1.6))[..., None] * c
		glow += blur(self.neon, 3) * 1.1 + blur(self.neon, 9) * 0.8
		return img, over, glow

	def _reflections(self, yy, xx):
		"""Wet ground mirrors every light as a vertical streak below where it stands."""
		out = np.zeros((H, W, 3), np.float32)
		rng = np.random.default_rng(7)
		ripple_rows = rng.random(H).astype(np.float32)
		ripple = 0.35 + 0.65 * np.clip(ripple_rows[:, None] * 1.4 - 0.2 + 0.4 * noise(H, W, 6, rng), 0, 1)
		for (x, gy, h, c, s, wdt) in self.reflect:
			mid = gy + h * 1.1
			span = h * 1.3 + 8
			fy = np.exp(-((yy - mid) / span) ** 2) * (yy > gy)
			fx = np.exp(-((xx - x) / (wdt + 0.04 * (yy - gy).clip(0))) ** 2)
			out += (s * 0.55 * fx * fy)[..., None] * c
		wet = self.gnd * (0.35 + 0.65 * self.wet)
		return out * (wet * ripple)[..., None]


# ---------------------------------------------------------------- textures

def pavers(h, w, rng, base, bw=8, bh=5, jitter=0.18, mortar_k=0.38):
	yy, xx = np.mgrid[0:h, 0:w]
	row = yy // bh
	off = (row % 2) * (bw // 2)
	colm = (xx + off) // bw
	lx = (xx + off) % bw
	ly = yy % bh
	table = rng.random((h // bh + 2, w // bw + 3)).astype(np.float32)
	v = 1.0 - jitter + 2 * jitter * table[row, colm]
	img = base[None, None, :] * v[..., None]
	hue = rng.random((h // bh + 2, w // bw + 3, 3)).astype(np.float32) * 0.06 - 0.03
	img = img + hue[row, colm]
	img = np.where((ly == 1)[..., None], img * 1.18, img)
	img = np.where(((ly == bh - 1) | (lx == bw - 1))[..., None], img * 0.82, img)
	mortar = (lx == 0) | (ly == 0)
	img = np.where(mortar[..., None], base * mortar_k, img)
	img *= (0.85 + 0.3 * noise(h, w, 18, rng))[..., None]
	return img.astype(np.float32)


def bricks(h, w, rng, base, bw=7, bh=3):
	return pavers(h, w, rng, base, bw, bh, 0.22)


def rust_streaks(h, w, rng, strength=0.5):
	"""0..1 map of rust running down from the top in thin vertical streaks."""
	small = rng.random((max(2, h // 12), max(2, w // 2))).astype(np.float32)
	img = Image.fromarray((small * 255).astype(np.uint8), "L").resize((w, h), Image.BICUBIC)
	s = np.asarray(img, np.float32) / 255.0
	fall = np.linspace(1.0, 0.3, h, dtype=np.float32)[:, None]
	return np.clip((s - 0.45) * 2.5, 0, 1) * fall * strength


def rusty(img, rng, strength=0.5):
	h, w = img.shape[:2]
	r = rust_streaks(h, w, rng, strength)[..., None]
	return img * (1 - r) + col(0.36, 0.17, 0.08) * r


def concrete(h, w, rng, base, slab=24):
	"""Big poured slabs, one per tile, with seams, stains and the odd crack."""
	yy, xx = np.mgrid[0:h, 0:w]
	table = rng.random((h // slab + 2, w // slab + 2)).astype(np.float32)
	v = 0.9 + 0.2 * table[yy // slab, xx // slab]
	img = base[None, None, :] * v[..., None]
	img *= (0.8 + 0.4 * noise(h, w, 14, rng))[..., None]
	img *= (0.9 + 0.2 * rng.random((h, w))).astype(np.float32)[..., None]
	seam = (xx % slab == 0) | (yy % slab == 0)
	img = np.where(seam[..., None], base * 0.45, img)
	img = np.where(((xx % slab == 1) | (yy % slab == 1))[..., None], img * 1.12, img)
	# Hairline cracks: thresholded ridges of a noise field.
	n = noise(h, w, 10, rng)
	crack = np.abs(n - 0.5) < 0.012
	img = np.where(crack[..., None], img * 0.55, img)
	return img.astype(np.float32)


def deckplate(h, w, rng, base):
	"""Steel floor plate: diamond tread and rivets at the plate corners."""
	yy, xx = np.mgrid[0:h, 0:w]
	img = base[None, None, :] * (0.9 + 0.2 * noise(h, w, 16, rng))[..., None]
	tread = ((xx + (yy // 3) * 2) % 6 == 0) & (yy % 3 == 0)
	img = np.where(tread[..., None], img * 1.45, img)
	seam = (xx % 48 == 0) | (yy % 24 == 0)
	img = np.where(seam[..., None], base * 0.4, img)
	rivet = ((xx % 48 == 3) | (xx % 48 == 44)) & ((yy % 24 == 3) | (yy % 24 == 20))
	img = np.where(rivet[..., None], base * 1.8, img)
	return rusty(img.astype(np.float32), rng, 0.25)


def corrugated(h, w, rng, base, period=4):
	"""Corrugated sheet steel with vertical ribs."""
	xx = np.arange(w)[None, :]
	rib = np.array([1.25, 1.05, 0.8, 0.95], np.float32)[(xx % period) % 4]
	img = base[None, None, :] * rib[..., None] * np.ones((h, 1, 1), np.float32)
	img *= (0.85 + 0.3 * noise(h, w, 12, rng))[..., None]
	return rusty(img.astype(np.float32), rng, 0.55)


def hazard(h, w, phase=0, a=col(0.75, 0.6, 0.12), b=col(0.07, 0.07, 0.07)):
	yy, xx = np.mgrid[0:h, 0:w]
	k = ((xx + yy + phase) // 4) % 2 == 0
	return np.where(k[..., None], a, b).astype(np.float32)


# ---------------------------------------------------------------- props

def blob_mask(h, w, circles):
	img = Image.new("L", (w, h), 0)
	d = ImageDraw.Draw(img)
	for (cx, cy, r) in circles:
		d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
	return np.asarray(img, np.float32) / 255.0


def ellipse_mask(h, w, x0, y0, x1, y1):
	img = Image.new("L", (w, h), 0)
	ImageDraw.Draw(img).ellipse([x0, y0, x1, y1], fill=255)
	return np.asarray(img, np.float32) / 255.0


def rrect_mask(h, w, x0, y0, x1, y1, r):
	img = Image.new("L", (w, h), 0)
	ImageDraw.Draw(img).rounded_rectangle([x0, y0, x1, y1], r, fill=255)
	return np.asarray(img, np.float32) / 255.0


def tank(sc, tx0, ty0, c=col(0.3, 0.9, 1.0)):
	"""A coolant tank standing on tile (tx0, ty0): a steel drum taller than a Sink, with a gauge light."""
	rng = sc.rng
	x0, y0 = tx(tx0), ty(ty0)
	sc.shade(x0 - 2, y0 + 3, x0 + 26, y0 + 27, 0.55, 3)
	w, h = 24, 50
	body_top, body_bot = 9, 44  # y of the lid's centre line and of the base, in the sprite
	m = np.zeros((h, w), np.float32)
	m[body_top:body_bot, 2:22] = 1
	m = np.maximum(m, ellipse_mask(h, w, 2, body_top - 6, 21, body_top + 6))
	m = np.maximum(m, ellipse_mask(h, w, 2, body_bot - 5, 21, body_bot + 4))
	xx = np.arange(w, dtype=np.float32)[None, :]
	# Cylinder shading: lit from the upper left, a wet highlight stripe.
	cyl = 0.55 + 0.6 * np.clip(1 - np.abs((xx - 8) / 11.0), 0, 1)
	paint = col(0.28, 0.33, 0.36)
	rgb = paint[None, None, :] * cyl[..., None] * np.ones((h, 1, 1), np.float32)
	rgb = np.where((np.abs(xx - 7) < 1)[..., None], rgb * 1.5, rgb)
	rgb = rusty(rgb, rng, 0.4)
	# Bands.
	for by in (18, 30, 40):
		rgb[by:by + 2] *= 0.6
	rgb[22:26, 2:22] = hazard(4, 20)
	# Lid: a flat ellipse with a hatch, lighter (it faces the sky).
	lid = ellipse_mask(h, w, 3, body_top - 5, 20, body_top + 5)
	lid_rgb = np.ones((h, w, 3), np.float32) * col(0.36, 0.4, 0.44)
	hatch = ellipse_mask(h, w, 9, body_top - 2, 15, body_top + 2)
	lid_rgb = np.where((hatch > 0.5)[..., None], col(0.2, 0.22, 0.25), lid_rgb)
	rgb = np.where((lid > 0.5)[..., None], lid_rgb, rgb)
	# Ladder on the right.
	for ly in range(body_top + 4, body_bot, 3):
		rgb[ly, 16:19] = col(0.12, 0.12, 0.13)
	rgb[body_top + 3:body_bot, 16] = col(0.1, 0.1, 0.1)
	rgb[body_top + 3:body_bot, 19] = col(0.1, 0.1, 0.1)
	em = np.zeros((h, w, 3), np.float32)
	em[33:36, 6:9] = c * 1.4  # gauge light
	top = y0 + 20 - body_bot
	sc.put(x0, top, rgb, m, em, over_from=y0)
	sc.sky(x0, top, m, col(0.5, 0.58, 0.72), col(0.16, 0.2, 0.28))
	sc.light(x0 + 7, top + 34, c, 22, 0.7, x0 + 7, y0 + 21, rwidth=1.0)


def floodlight(sc, tx0, ty0, c=col(1.0, 0.68, 0.32)):
	"""A steel mast with a sodium floodlight on a concrete foot."""
	x0, y0 = tx(tx0), ty(ty0)
	cx, base = x0 + 12, y0 + 16
	sc.shade(x0 + 3, y0 + 9, x0 + 21, y0 + 23, 0.45, 2)
	foot = np.ones((8, 12), np.float32)
	frgb = np.ones((8, 12, 3), np.float32) * col(0.3, 0.3, 0.32)
	frgb[:2] *= 1.3
	frgb[2:4] = hazard(2, 12)
	sc.put(cx - 6, base - 6, frgb, foot)
	ph, pw = 50, 18
	m = np.zeros((ph, pw), np.float32)
	rgb = np.ones((ph, pw, 3), np.float32) * col(0.16, 0.16, 0.18)
	em = np.zeros((ph, pw, 3), np.float32)
	m[8:, 8:10] = 1  # mast
	rgb[:, 8] *= 1.6
	for ry in range(12, ph, 6):
		m[ry, 7:11] = 1  # bolts on the mast
	m[0:8, 1:17] = 1  # lamp housing, two heads
	rgb[0:2, 1:17] = col(0.3, 0.3, 0.33)
	rgb[2:8, 1:17] = col(0.1, 0.1, 0.11)
	em[3:7, 2:8] = c * 1.6
	em[3:7, 10:16] = c * 1.6
	em[4:6, 3:7] = col(1.0, 1.0, 0.85) * 2.0
	em[4:6, 11:15] = col(1.0, 1.0, 0.85) * 2.0
	top = base - ph
	sc.put(cx - 9, top, rgb, m, em, over_from=y0)
	sc.light(cx, top + 5, c, 70, 1.45, cx, base, rwidth=2.2)


def ore_wagon(sc, tx0, ty0, rng):
	"""A slag wagon parked north-south on two tiles, its load still glowing."""
	x0, y0 = tx(tx0), ty(ty0)
	w, h, lift = 24, 48, 7
	sc.shade(x0 + 1, y0 + 2, x0 + 23, y0 + 50, 0.55, 2)
	sh = h + lift
	m = np.zeros((sh, w), np.float32)
	m[1:sh - 3, 2:22] = 1
	m[sh - 3:sh, 4:9] = 1  # wheels
	m[sh - 3:sh, 15:20] = 1
	steel = col(0.25, 0.22, 0.2)
	rgb = np.ones((sh, w, 3), np.float32) * steel
	rgb[1:3] *= 1.5  # rim catching the rain
	rgb[:, 2:4] *= 1.3
	rgb[:, 20:22] *= 0.7
	front = sh - 12
	rgb[front:] *= 0.55  # end face of the tub
	for ry in range(front + 2, sh - 3, 3):
		rgb[ry, 4:20:4] = steel * 1.6  # rivets
	rgb[sh - 3:] = col(0.05, 0.05, 0.05)
	rgb = rusty(rgb, rng, 0.6)
	em = np.zeros((sh, w, 3), np.float32)
	# Slag load: glowing orange under a cracked dark crust.
	load = np.zeros((sh, w), bool)
	load[4:front - 1, 5:19] = True
	n = noise(sh, w, 3, rng)
	glow = np.clip((n - 0.45) * 3.0, 0, 1)
	crust = col(0.08, 0.05, 0.04)
	rgb = np.where(load[..., None], crust, rgb)
	em = np.where(load[..., None], (glow[..., None] ** 1.5) * col(1.0, 0.42, 0.1) * 1.4, em)
	sc.put(x0, y0 - lift, rgb, m, em, over_from=y0)
	sc.light(x0 + 12, y0 + 12, col(1.0, 0.45, 0.15), 40, 0.9, x0 + 12, y0 + 48, rwidth=4.0)


def crates(sc, tx0, ty0, rng):
	"""Two stacked steel crates on a 2x1 footprint."""
	x0, y0 = tx(tx0), ty(ty0)
	w, h = 48, 36
	sc.shade(x0 - 1, y0 + 4, x0 + 49, y0 + 26, 0.55, 2)
	m = np.zeros((h, w), np.float32)
	rgb = np.zeros((h, w, 3), np.float32)
	boxes = [(1, h - 22, 23, h - 1, col(0.32, 0.2, 0.12)), (24, h - 22, 47, h - 1, col(0.2, 0.25, 0.3)),
			 (8, h - 34, 32, h - 21, col(0.3, 0.28, 0.2))]
	for (bx0, by0, bx1, by1, c) in boxes:
		top = by0 + 7  # top face (lighter) above the front face
		m[by0:by1, bx0:bx1] = 1
		rgb[by0:top, bx0:bx1] = c * 1.3
		rgb[by0, bx0:bx1] = c * 1.8
		rgb[top:by1, bx0:bx1] = c * 0.75
		rgb[top + 2:by1 - 1, bx0 + 2:bx1 - 2] = c * 0.6
		rgb[top + 2:by1 - 1:3, bx0 + 2:bx1 - 2] = c * 0.8  # ribs
		rgb[top:top + 2, bx0:bx1] = hazard(2, bx1 - bx0)
		rgb[by0:by1, bx0] = c * 0.4
	rgb = rusty(rgb, rng, 0.5)
	sc.put(x0, y0 + 24 - h, rgb, m, over_from=y0)


def barrier(sc, tx0, ty0, n):
	"""A row of concrete crash barriers with hazard stripes, n tiles wide."""
	rng = sc.rng
	x0, y0 = tx(tx0), ty(ty0)
	w, h = n * T, 22
	sc.shade(x0 - 2, y0 + 8, x0 + w + 2, y0 + 26, 0.5, 2)
	m = np.zeros((h, w), np.float32)
	m[4:h - 1, 1:w - 1] = 1
	rgb = concrete(h, w, rng, col(0.36, 0.36, 0.37), 12)
	rgb[4:10] *= 1.25  # top face
	rgb[4] *= 1.3
	rgb[10:h - 1] = rgb[10:h - 1] * 0.75
	rgb[12:17, 1:w - 1] = hazard(5, w - 2)
	for sx in range(12, w, 12):
		m[4:h - 1, sx] = 0.0  # gaps between segments
	sc.put(x0, y0 + 24 - h, rgb, m, over_from=y0)


def scrap_bin(sc, tx0, ty0):
	rng = sc.rng
	x0, y0 = tx(tx0), ty(ty0)
	w, h = 48, 32
	sc.shade(x0 - 1, y0 + 6, x0 + 49, y0 + 26, 0.55, 2)
	m = np.zeros((h, w), np.float32)
	m[4:h - 1, 2:w - 2] = 1
	paint = col(0.3, 0.2, 0.12)
	rgb = np.ones((h, w, 3), np.float32) * paint
	rgb[4:6] = paint * 1.6
	rgb[16:] = paint * 0.65
	for x in range(6, w - 4, 6):
		rgb[17:h - 2, x] = paint * 0.4
	rgb[19:22, 16:32] = hazard(3, 16)
	# Scrap heap poking out of the top.
	heap = blob_mask(h, w, [(x, 8 + rng.random() * 3, 4 + rng.random() * 3) for x in range(6, w - 5, 5)])
	heap[12:] = 0
	scrap = col(0.3, 0.3, 0.32) * (0.5 + rng.random((h, w, 1)).astype(np.float32))
	rgb = np.where((heap > 0.5)[..., None] & (np.arange(h)[:, None, None] < 12), scrap, rgb)
	m = np.maximum(m, heap)
	rgb = rusty(rgb, rng, 0.6)
	sc.put(x0, y0 + 24 - h, rgb, m, over_from=y0)


def console(sc, tx0, ty0, c=col(0.35, 1.0, 0.6)):
	x0, y0 = tx(tx0), ty(ty0)
	w, h = 20, 34
	sc.shade(x0 + 1, y0 + 8, x0 + 23, y0 + 26, 0.5, 2)
	m = np.zeros((h, w), np.float32)
	m[:, 1:w - 1] = 1
	rgb = np.ones((h, w, 3), np.float32) * col(0.2, 0.21, 0.24)
	rgb[0:2] *= 1.6
	rgb[14:] *= 0.7
	rgb[24:27, 1:w - 1] = hazard(3, w - 2)
	em = np.zeros((h, w, 3), np.float32)
	em[3:12, 3:w - 3] = c * 0.75
	for y in range(4, 12, 2):
		em[y, 4:4 + (y * 7) % 10] = c * 1.4  # lines of readout
	em[16:18, 4:7] = col(1.0, 0.3, 0.2) * 1.3
	em[16:18, 9:12] = col(1.0, 0.8, 0.2) * 1.3
	sc.put(x0 + 2, y0 + 24 - h, rgb, m, em, over_from=y0)
	sc.light(x0 + 12, y0 + 24 - h + 8, c, 30, 0.8, x0 + 12, y0 + 24, rwidth=2.5)


def slag_spill(sc, x, y, r, rng):
	"""A glowing spill of slag on the ground that the rain hisses on."""
	size = int(r * 2 + 4)
	m = blob_mask(size, size, [(size / 2 + rng.normal() * r * 0.3, size / 2 + rng.normal() * r * 0.2, r * (0.5 + rng.random() * 0.4)) for _ in range(4)])
	n = noise(size, size, 2, rng)
	crust = col(0.06, 0.04, 0.03)
	rgb = np.ones((size, size, 3), np.float32) * crust
	hot = np.clip((n - 0.4) * 3, 0, 1) * blur(m, 1.5)
	em = (hot[..., None] ** 1.3) * col(1.0, 0.4, 0.08) * 1.5
	sc.put(int(x - size / 2), int(y - size / 2), rgb, m, em)
	sc.light(x, y - 2, col(1.0, 0.42, 0.12), r * 3, 0.8, x, y, rwidth=r * 0.4)


# ---------------------------------------------------------------- the foundry hall and the yard edges

def neon_text(sc, text, x, y, size, c, sub=None, subc=None):
	"""Neon tubes: crisp core in the neon layer plus colour light on everything near it."""
	font = ImageFont.truetype(FONT_BOLD, size)
	img = Image.new("L", (W, H), 0)
	d = ImageDraw.Draw(img)
	d.text((x, y), text, font=font, fill=255)
	bbox = d.textbbox((x, y), text, font=font)
	if sub:
		f2 = ImageFont.truetype(FONT_BOLD, max(6, size // 3))
		sb = d.textbbox((0, 0), sub, font=f2)
		sx = (bbox[0] + bbox[2]) // 2 - (sb[2] - sb[0]) // 2
		img2 = Image.new("L", (W, H), 0)
		ImageDraw.Draw(img2).text((sx, bbox[3] + 3), sub, font=f2, fill=255)
		m2 = np.asarray(img2, np.float32) / 255.0
		sc.neon += (m2 > 0.45)[..., None] * (subc if subc is not None else c) * 0.9
	m = np.asarray(img, np.float32) / 255.0
	core = (m > 0.45).astype(np.float32)
	inner = (blur(core, 0.6) > 0.8).astype(np.float32)
	sc.neon += core[..., None] * c * 1.1 + inner[..., None] * (col(1, 1, 1) - c) * 0.35
	return bbox, (bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2


def sign_board(sc, bbox, pad=5):
	"""Steel backing board on two struts behind a neon sign."""
	x0, y0, x1, y1 = bbox[0] - pad, bbox[1] - pad, bbox[2] + pad, bbox[3] + pad
	w, h = x1 - x0, y1 - y0
	rgb = np.ones((h, w, 3), np.float32) * col(0.08, 0.07, 0.07)
	rgb[:2] *= 2.0
	rgb[-2:] = hazard(2, w)
	sc.put(x0, y0, rgb, np.ones((h, w), np.float32))
	for lx in (x0 + 6, x1 - 8):
		lh = max(0, FACADE_TOP - y1 + 4)
		if lh > 0:
			sc.put(lx, y1, np.ones((lh, 2, 3), np.float32) * col(0.12, 0.12, 0.13), np.ones((lh, 2), np.float32))
	return (x0, y0, x1, y1)


def building(sc, style):
	rng = sc.rng
	# Roof: corrugated steel seen from above, wet and rust-streaked, from the top of the view to the eave.
	rh = FACADE_TOP
	roof = corrugated(rh, W, rng, style["roof"], 5)
	yy = np.arange(rh, dtype=np.float32)[:, None]
	roof *= (0.7 + 0.5 * (yy / rh))[..., None]
	roof += (np.clip(noise(rh, W, 12, rng) - 0.55, 0, 1) * 0.25)[..., None] * col(0.4, 0.5, 0.7)
	sc.put(0, 0, roof, np.ones((rh, W), np.float32))
	sc.amb[:rh] = col(0.3, 0.34, 0.46)
	# Smokestacks with a furnace glow at the mouth, and roof vents.
	for sxp in style["stacks"]:
		sw, shh = 14, 30
		m = np.zeros((shh, sw), np.float32)
		m[4:, 1:sw - 1] = 1
		m[:6] = ellipse_mask(6, sw, 0, 0, sw - 1, 5)
		xx = np.arange(sw, dtype=np.float32)[None, :]
		c = bricks(shh, sw, rng, col(0.3, 0.18, 0.13), 5, 3) * (0.6 + 0.6 * np.clip(1 - np.abs(xx - 5) / 8, 0, 1))[..., None]
		c[:6] = col(0.1, 0.06, 0.05)
		em = np.zeros((shh, sw, 3), np.float32)
		em[1:5, 3:sw - 3] = col(1.0, 0.45, 0.12) * 1.3
		sc.put(sxp, rh - shh + 4, c, m, em)
		sc.light(sxp + sw / 2, rh - shh + 6, col(1.0, 0.45, 0.15), 30, 0.7, reflect=False)
	for vx in style["vents"]:
		v = np.ones((8, 16, 3), np.float32) * col(0.2, 0.21, 0.23)
		v[0] *= 1.6
		v[3:7, 2:14:3] = col(0.06, 0.06, 0.07)
		sc.put(vx, rh - 16, v, np.ones((8, 16), np.float32))
	# Gutter and the shadow under it.
	eave = np.ones((3, W, 3), np.float32) * col(0.07, 0.06, 0.07)
	eave[0] = col(0.3, 0.3, 0.33)
	sc.put(0, rh - 1, eave, np.ones((3, W), np.float32))
	# Facade wall.
	fh = FACADE_BASE - FACADE_TOP - 2
	fy = FACADE_TOP + 2
	if style["wall"] == "brick":
		wall = rusty(bricks(fh, W, rng, style["wall_col"], 7, 3), rng, 0.35)
	else:
		wall = corrugated(fh, W, rng, style["wall_col"], 4)
	# Riveted steel skirt along the bottom, pipe along the top.
	wall[fh - 6:] = deckplate(6, W, rng, col(0.24, 0.24, 0.27))
	wall[fh - 6] *= 1.5
	wall[:3] *= 0.45
	pipe_y = 4
	wall[pipe_y:pipe_y + 3] = col(0.3, 0.3, 0.33)
	wall[pipe_y] *= 1.5
	wall[pipe_y + 2] *= 0.6
	for bx in range(10, W, 40):
		wall[pipe_y - 1:pipe_y + 4, bx:bx + 2] = col(0.12, 0.12, 0.13)
	sc.put(0, fy, wall, np.ones((fh, W), np.float32))
	sc.amb[fy:FACADE_BASE] = col(0.1, 0.12, 0.18)
	# Downpipes.
	for dx in style["downpipes"]:
		p = np.ones((fh - 8, 3, 3), np.float32) * col(0.26, 0.26, 0.29)
		p[:, 0] *= 1.5
		p[:, 2] *= 0.6
		sc.put(dx, fy + 6, rusty(p, rng, 0.5), np.ones((fh - 8, 3), np.float32))
	# Furnace-lit windows between the doors, and caged lamps.
	door_x = [tx(d) for d in DOOR_TILES]
	ww, wh = style["win"]
	wy = fy + 10
	x = 10
	slots = []
	while x + ww < W - 6:
		if not any(abs((x + ww / 2) - dx) < 24 + ww / 2 + 3 for dx in door_x):
			slots.append(x)
		x += ww + style["gap"]
	for wx in slots:
		window(sc, wx, wy, ww, wh, rng.random() < style["lit"], style)
	for dx in door_x:
		shutter(sc, dx)
	for i in range(len(slots) - 1):
		if i % 2 == 1:
			cage_lamp(sc, (slots[i] + ww + slots[i + 1]) // 2, wy - 1)


def window(sc, x, y, w, h, lit, style):
	"""A grid of small industrial panes; lit ones show the furnace glow inside."""
	rng = sc.rng
	frame_c = col(0.12, 0.12, 0.13)
	frame = np.ones((h + 2, w + 2, 3), np.float32) * frame_c
	em = np.zeros((h + 2, w + 2, 3), np.float32)
	glass = style["glass"]
	yy, xx = np.mgrid[0:h, 0:w]
	if lit:
		k = (0.55 + 0.6 * (yy / h)) * (0.8 + 0.4 * rng.random((h, w)))
		pane = glass[None, None, :] * k[..., None]
		pane = np.where((rng.random((h, w)) < 0.12)[..., None], pane * 0.3, pane)  # grime
		em[1:-1, 1:-1] = pane.astype(np.float32)
		sc.light(x + w / 2 + 1, y + h / 2, glass, 30 + w, 0.9, x + w / 2 + 1, FACADE_BASE, rwidth=w * 0.3)
	else:
		pane = np.ones((h, w, 3), np.float32) * col(0.05, 0.07, 0.1)
		pane = np.where((np.abs(xx - yy * 0.7 - 2) < 1)[..., None], col(0.2, 0.26, 0.36), pane)
		frame[1:-1, 1:-1] = pane
	grid = ((np.arange(w + 2)[None, :] % 4) == 0) | ((np.arange(h + 2)[:, None] % 4) == 0)
	frame = np.where(grid[..., None], frame_c, frame)
	em = np.where(grid[..., None], 0, em)
	if lit:
		frame = np.where(grid[..., None], frame_c, col(0.15, 0.1, 0.07))
	sc.put(x, y, frame, np.ones((h + 2, w + 2), np.float32), em)
	sill = np.ones((2, w + 4, 3), np.float32) * col(0.3, 0.3, 0.32)
	sc.put(x - 1, y + h + 2, sill, np.ones((2, w + 4), np.float32))


def shutter(sc, cx):
	"""A roller shutter at each door slot; the game draws its neon door over the slots that lead somewhere."""
	w, h = 34, 26
	x, y = int(cx - w / 2), FACADE_BASE - h
	rgb = hazard(h, w)
	inner = np.ones((h - 3, w - 6, 3), np.float32) * col(0.22, 0.22, 0.24)
	inner[::3] *= 0.55
	rgb[3:, 3:w - 3] = inner
	sc.put(x, y, rusty(rgb, sc.rng, 0.4), np.ones((h, w), np.float32))
	cage_lamp(sc, cx, y - 8, col(1.0, 0.6, 0.15))


def cage_lamp(sc, x, y, c=col(1.0, 0.75, 0.42)):
	m = np.zeros((7, 5), np.float32)
	m[1:6, 0:5] = 1
	m[0, 2] = 1
	rgb = np.ones((7, 5, 3), np.float32) * col(0.08, 0.08, 0.08)
	em = np.zeros((7, 5, 3), np.float32)
	em[2:5, 1:4] = c * 1.6
	em[3, 1:4] *= 0.4  # cage bar
	sc.put(x - 2, y, rgb, m, em)
	sc.light(x, y + 3, c, 26, 1.0, x, FACADE_BASE, rwidth=1.2)


def yard_walls(sc):
	"""Concrete yard walls on the left, right and bottom edges, with a gate at the entry."""
	rng = sc.rng
	stone = col(0.3, 0.3, 0.32)
	for side in (0, 1):
		xs, xe = (0, OX) if side == 0 else (tx(23), W)
		w, h = xe - xs, ty(12) - FACADE_BASE
		top = concrete(h, w, rng, stone * 1.1, 24)
		inner = xe - 4 if side == 0 else xs
		top[:, inner - xs:inner - xs + 4] = stone * 0.6  # the inner face, in shade
		for py in range(6, h, 24):
			top[py:py + 3, :] = hazard(3, w)  # warning bands on the wall cap
		sc.put(xs, FACADE_BASE, rusty(top, rng, 0.3), np.ones((h, w), np.float32))
		sc.amb[FACADE_BASE:ty(12), xs:xe] = col(0.14, 0.16, 0.22)
	# Bottom wall: we look at its cap and its north face rises over the last floor row.
	y0 = ty(12)
	h = H - y0 + 6
	tex = concrete(h, W, rng, stone, 24)
	tex[:3] *= 1.4  # cap edge
	tex[3:10] *= 0.7  # north face
	tex[4:7] = hazard(3, W)
	ex0, ex1 = tx(11), tx(13)
	gate = deckplate(h, ex1 - ex0, rng, col(0.2, 0.2, 0.22))
	tex[:, ex0:ex1] = gate
	for gx in (ex0 - 4, ex1):
		tex[:, gx:gx + 4] = col(0.35, 0.33, 0.3)
		tex[0:2, gx:gx + 4] = col(0.5, 0.48, 0.45)
	m = np.ones((h, W), np.float32)
	m[:6, ex0:ex1] = 0
	sc.put(0, y0 - 6, rusty(tex, rng, 0.3), m, over_from=y0)
	sc.amb[y0 - 6:, :] = col(0.14, 0.16, 0.22)
	for gx in (ex0 - 2, ex1 + 2):
		sc.light(gx, y0 - 6, col(1.0, 0.55, 0.15), 24, 0.9, gx, y0, rwidth=1.0)


def ground(sc, regions):
	rng = sc.rng
	ys = FACADE_BASE
	h = H - ys
	conc = concrete(h, W, rng, col(0.21, 0.21, 0.23))
	deck = deckplate(h, W, rng, col(0.19, 0.2, 0.23))
	g = conc.copy()
	for (kind, x0, y0, x1, y1) in regions:
		px0, py0, px1, py1 = tx(x0), ty(y0) - ys, tx(x1), ty(y1) - ys
		if kind == "deck":
			g[py0:py1, px0:px1] = deck[py0:py1, px0:px1]
			g[py0:py0 + 1, px0:px1] = col(0.35, 0.35, 0.38)
		elif kind == "rail":
			# Sleepers and two rails along a row.
			for sx in range(px0, px1, 6):
				g[py0 + 4:py1 - 4, sx:sx + 3] = col(0.2, 0.14, 0.1) * (0.8 + 0.4 * rng.random())
			for ry in (py0 + 7, py1 - 9):
				g[ry:ry + 2, px0:px1] = col(0.42, 0.42, 0.45)
				g[ry + 2, px0:px1] = col(0.08, 0.08, 0.09)
		elif kind == "stripe":
			g[py0:py1, px0:px1] = hazard(py1 - py0, px1 - px0) * 0.7 + g[py0:py1, px0:px1] * 0.3
	# Walkway in front of the hall: steel plate with a yellow edge line.
	g[0:T] = deck[0:T]
	g[T - 3:T - 1] = col(0.6, 0.5, 0.12)
	g[0:3] *= 0.5  # contact shadow under the facade
	sc.put(0, ys, g, np.ones((h, W), np.float32), ground=1.0)
	# Puddles.
	pn = noise(H, W, 26, rng) * 0.7 + noise(H, W, 9, rng) * 0.3
	puddle = np.clip((pn - 0.58) * 9.0, 0, 1)
	puddle[:ys] = 0
	sc.wet = np.maximum(sc.wet, puddle)
	smooth = blur(sc.alb, 1.2)
	sc.alb = sc.alb * (1 - 0.6 * puddle[..., None]) + smooth * 0.6 * puddle[..., None]
	sc.alb *= (1 - 0.35 * puddle)[..., None]
	sc.alb += (puddle * 0.03)[..., None] * col(0.3, 0.45, 0.8)
	sc.amb[ys:] = col(0.17, 0.2, 0.3)
	sc.amb[ys:] += (0.14 * puddle[ys:])[..., None] * col(0.3, 0.45, 0.8)


def lane_lines(sc, lines):
	"""Worn yellow lane paint: (x tile, y0 tile, y1 tile) vertical lines."""
	rng = sc.rng
	for (x, y0, y1) in lines:
		px = tx(x)
		for py in range(ty(y0) + 1, ty(y1) - 1):
			if rng.random() < 0.8:
				sc.alb[py, px - 1:px + 1] = col(0.6, 0.5, 0.15) * (0.6 + 0.4 * rng.random())


def drain(sc, x, y):
	px, py = tx(x) + 6, ty(y) + 8
	g = np.ones((7, 12, 3), np.float32) * col(0.05, 0.05, 0.06)
	for gx in range(1, 12, 2):
		g[1:-1, gx] = col(0.24, 0.24, 0.26)
	sc.put(px, py, g, np.ones((7, 12), np.float32))


# ---------------------------------------------------------------- layouts

STYLES = {
	"smelter": {"roof": col(0.2, 0.2, 0.23), "wall": "corrugated", "wall_col": col(0.27, 0.25, 0.24), "win": (17, 13), "gap": 12,
				"lit": 0.75, "glass": col(1.0, 0.55, 0.2), "stacks": [60, 230, 560], "vents": [140, 360], "downpipes": [100, 380, 620]},
	"coolant": {"roof": col(0.18, 0.2, 0.23), "wall": "corrugated", "wall_col": col(0.2, 0.26, 0.28), "win": (13, 13), "gap": 10,
				"lit": 0.7, "glass": col(0.5, 0.85, 1.0), "stacks": [420], "vents": [40, 200, 300, 520], "downpipes": [60, 330, 590]},
	"scrapyard": {"roof": col(0.19, 0.18, 0.19), "wall": "brick", "wall_col": col(0.3, 0.19, 0.15), "win": (13, 13), "gap": 16,
				  "lit": 0.6, "glass": col(1.0, 0.62, 0.3), "stacks": [30, 470, 590], "vents": [180], "downpipes": [210, 440]},
}

# '#' boundary (the hall fills rows 0-2), '.' floor. Props, every tile of them solid:
# 'v' slag wagon parked north-south (2 tiles tall), 'c' crate stack (2 tiles wide), 'T' coolant tank,
# 'L' floodlight mast, 'h' crash barrier run, 'd' scrap bin (2 wide), 'm' control console.
LAYOUTS = [
	{
		"name": "smelter", "style": "smelter", "seed": 11,
		"sign": ("SMELTER", "NO. 7", 446, 11, 19, col(1.0, 0.45, 0.12), col(1.0, 0.75, 0.3)),
		"ground": [("deck", 1, 4, 23, 7), ("rail", 1, 8, 23, 9)],
		"lanes": [(x, 4, 6) for x in (1, 4, 7, 10, 13, 16, 19, 22)],
		"spills": [(11.5, 10.3, 5), (4.2, 7.4, 3)],
		"lines": [
			"########################",
			"########################",
			"########################",
			"#......................#",
			"#.v.....v......v.....v.#",
			"#.v.....v......v.....v.#",
			"#......................#",
			"#......L.......L.......#",
			"#...................T..#",
			"#..hhh..........T......#",
			"#.....................T#",
			"#......................#",
			"########################",
		],
	},
	{
		"name": "coolant", "style": "coolant", "seed": 23,
		"sign": ("COOLANT", "PUMP HOUSE", 82, 11, 19, col(0.25, 0.9, 1.0), col(0.6, 1.0, 0.95)),
		"ground": [("deck", 1, 5, 23, 10)],
		"lanes": [],
		"spills": [(20.5, 11.2, 3)],
		"drains": [(5, 9), (12, 5), (18, 9)],
		"lines": [
			"########################",
			"########################",
			"########################",
			"#......................#",
			"#..L........m........L.#",
			"#......................#",
			"#......................#",
			"#..cc...T....cc...T....#",
			"#......................#",
			"#......................#",
			"#.hh......dd.......hh..#",
			"#......................#",
			"########################",
		],
	},
	{
		"name": "scrapyard", "style": "scrapyard", "seed": 37,
		"sign": ("SCRAP YARD", "KEEP OUT", 430, 11, 18, col(1.0, 0.22, 0.18), col(1.0, 0.7, 0.2)),
		"ground": [("stripe", 10, 5, 14, 6)],
		"lanes": [],
		"spills": [(8.5, 7.5, 4), (15.6, 9.5, 3), (3.5, 11.2, 3)],
		"drains": [(5, 7), (18, 7)],
		"lines": [
			"########################",
			"########################",
			"########################",
			"#......................#",
			"#.dd...............m...#",
			"#......................#",
			"#....T.....hh.....T....#",
			"#......................#",
			"#..cc......L......cc...#",
			"#......................#",
			"#.....T..........T.....#",
			"#......................#",
			"########################",
		],
	},
]


def props_of(lines):
	"""Groups prop tiles into objects: (kind, x, y, width) with x, y the top-left tile."""
	seen = set()
	out = []
	for y, row in enumerate(lines):
		for x, ch in enumerate(row):
			if ch in "#." or (x, y) in seen:
				continue
			seen.add((x, y))
			if ch == "v":
				seen.add((x, y + 1))
				out.append(("v", x, y, 1))
			elif ch in "cd":
				seen.add((x + 1, y))
				out.append((ch, x, y, 2))
			elif ch == "h":
				n = 1
				while x + n < len(row) and row[x + n] == "h":
					seen.add((x + n, y))
					n += 1
				out.append(("h", x, y, n))
			else:
				out.append((ch, x, y, 1))
	return out


def paint_layout(lay):
	sc = Scene(lay["seed"])
	style = STYLES[lay["style"]]
	ground(sc, lay["ground"])
	lane_lines(sc, lay["lanes"])
	for (x, y) in lay.get("drains", []):
		drain(sc, x, y)
	for (x, y, r) in lay.get("spills", []):
		slag_spill(sc, OX + x * T, OY + y * T, r, sc.rng)
	building(sc, style)
	text, sub, sx, sy, size, c, subc = lay["sign"]
	bbox, cx, cy = neon_text(sc, text, sx, sy, size, c, sub, subc)
	fb = (bbox[0], bbox[1], bbox[2], bbox[3] + (size // 3 + 4 if sub else 0))
	sign_board(sc, fb)
	# The neon lights the roof, the facade and the yard below it.
	sc.light(cx, cy + 6, c, 120, 1.0, cx, FACADE_BASE + 2, rwidth=10.0)
	sc.halos.append((cx, cy, 60, c, 0.5))
	yard_walls(sc)
	props = sorted(props_of(lay["lines"]), key=lambda p: p[2] + (1 if p[0] == "v" else 0))
	for (kind, x, y, n) in props:
		if kind == "v":
			ore_wagon(sc, x, y, sc.rng)
		elif kind == "c":
			crates(sc, x, y, sc.rng)
		elif kind == "T":
			tank(sc, x, y)
		elif kind == "L":
			floodlight(sc, x, y)
		elif kind == "h":
			barrier(sc, x, y, n)
		elif kind == "d":
			scrap_bin(sc, x, y)
		elif kind == "m":
			console(sc, x, y)
	img, over, glow = sc.render()
	sign = (fb[0] - 5, fb[1] - 5, fb[2] + 5, fb[3] + 5)
	return img, over, sc.ov_a, glow, sc.neon, sign, c


def to_png(rgb, alpha=None, compensate=False):
	a = np.clip(rgb, 0, None)
	if compensate:
		a = a / NIGHT
	a = np.clip(a, 0, 1)
	a = (a ** (1 / 1.15)) * 255  # a touch of gamma lift so the darks keep detail
	a = a.astype(np.uint8)
	if alpha is None:
		return Image.fromarray(a, "RGB")
	al = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
	return Image.fromarray(np.dstack([a, al]), "RGBA")


def collision_lines(lines):
	return ["".join("#" if ch != "." else "." for ch in row) for row in lines]


def main():
	out_dir = os.path.join(ROOT, "art", "street")
	os.makedirs(out_dir, exist_ok=True)
	entries = []
	for lay in LAYOUTS:
		assert len(lay["lines"]) == ROOM_H and all(len(r) == ROOM_W for r in lay["lines"]), lay["name"]
		img, over, ov_a, glow, neon, sign, sc_col = paint_layout(lay)
		n = lay["name"]
		to_png(img, compensate=True).save(os.path.join(out_dir, n + "_base.png"), optimize=True)
		to_png(over, ov_a, compensate=True).save(os.path.join(out_dir, n + "_over.png"), optimize=True)
		g = np.clip(glow, 0, 1)
		to_png(g, np.clip(g.max(-1) * 1.5, 0, 1)).save(os.path.join(out_dir, n + "_glow.png"), optimize=True)
		ne = np.clip(neon, 0, 1)
		to_png(ne, (ne.max(-1) > 0.02).astype(np.float32)).save(os.path.join(out_dir, n + "_neon.png"), optimize=True)
		entries.append((n, collision_lines(lay["lines"]), sign, sc_col))
	write_data(entries)
	print("painted", ", ".join(e[0] for e in entries))


def write_data(entries):
	ox, oy = WORLD_OFFSET
	out = [
		"class_name StreetData",
		"## Generated by tools/street_art.py: edit the layouts there and re-run it, not this file.",
		"## Collision grids and sign positions for the Rainside rooms; the art is in res://art/street/.",
		"",
		"const ART_SCALE := 2.0 # one art pixel is this many world px",
		"const ART_OFFSET := Vector2(%d, %d) # world px of art pixel (0, 0)" % (ox, oy),
		"const LAYOUTS := [",
	]
	for (n, lines, sign, c) in entries:
		x0, y0, x1, y1 = sign
		out.append("\t{")
		out.append('\t\t"name": "%s",' % n)
		out.append("\t\t\"sign\": Rect2(%d, %d, %d, %d), # world px" % (ox + 2 * x0, oy + 2 * y0, 2 * (x1 - x0), 2 * (y1 - y0)))
		out.append("\t\t\"sign_color\": Color(%.2f, %.2f, %.2f)," % tuple(float(v) for v in c))
		out.append('\t\t"lines": [')
		for row in lines:
			out.append('\t\t\t"%s",' % row)
		out.append("\t\t],")
		out.append("\t},")
	out.append("]")
	with open(os.path.join(ROOT, "scripts", "street_data.gd"), "w") as f:
		f.write("\n".join(out) + "\n")


if __name__ == "__main__":
	main()
