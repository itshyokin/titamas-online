"""Placeholder desert ground textures (seamless, 1024 px): sand_color.png and
desert_stone_color.png in assets/materials/terrain/. Replace them with real ones any time
(same names, or pick others in Database -> Ground Sets).

    python tools/art/make_desert_ground.py
"""
import os

import numpy as np
from PIL import Image

N = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "materials", "terrain")
rng = np.random.default_rng(7)


def noise(scale: float, power: float = 2.0) -> np.ndarray:
	"""Seamless noise: white noise filtered in frequency space (wraps at the edges)."""
	f = np.fft.fftfreq(N)
	fx, fy = np.meshgrid(f, f)
	r = np.sqrt(fx * fx + fy * fy) * N / scale
	amp = 1.0 / (1.0 + r ** power)
	spec = np.fft.fft2(rng.standard_normal((N, N))) * amp
	out = np.real(np.fft.ifft2(spec))
	out -= out.min()
	return out / out.max()


def colorize(t: np.ndarray, stops: list) -> np.ndarray:
	xs = [s[0] for s in stops]
	img = np.zeros((N, N, 3))
	for c in range(3):
		img[..., c] = np.interp(t, xs, [s[1][c] for s in stops])
	return img


def save(img: np.ndarray, name: str) -> None:
	Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(os.path.join(OUT, name))
	print("wrote", name)


def sand() -> None:
	big = noise(4)
	mid = noise(24)
	grain = rng.random((N, N))
	# Wind ripples: wavy stripes that wrap (whole number of waves across the tile).
	y, x = np.mgrid[0:N, 0:N] / N
	warp = noise(6) * 2.0
	ripple = 0.5 + 0.5 * np.sin(2 * np.pi * (34 * y + 3 * x + warp))
	t = 0.45 * big + 0.25 * mid + 0.15 * ripple + 0.15 * grain
	img = colorize(t, [(0.0, (168, 132, 88)), (0.45, (206, 172, 120)), (0.75, (226, 196, 146)), (1.0, (240, 218, 172))])
	# Scattered dark grains and pebbles.
	speck = grain > 0.985
	img[speck] *= 0.62
	save(img, "sand_color.png")


def desert_stone() -> None:
	# Slabs: cellular (Voronoi-like) cells from wrapped distance to random points.
	pts = rng.random((70, 2)) * N
	y, x = np.mgrid[0:N, 0:N].astype(np.float32)
	d1 = np.full((N, N), 1e9, np.float32)
	d2 = np.full((N, N), 1e9, np.float32)
	cell = np.zeros((N, N), np.int32)
	for i, (px, py) in enumerate(pts):
		dx = np.abs(x - px)
		dx = np.minimum(dx, N - dx)
		dy = np.abs(y - py)
		dy = np.minimum(dy, N - dy)
		d = np.sqrt(dx * dx + dy * dy)
		closer = d < d1
		d2 = np.where(closer, d1, np.minimum(d2, d))
		cell = np.where(closer, i, cell)
		d1 = np.where(closer, d, d1)
	edge = np.clip((d2 - d1) / 10.0, 0, 1)  # 0 at cracks
	tone = rng.random(len(pts))[cell]
	layers = 0.5 + 0.5 * np.sin(2 * np.pi * (18 * y / N + noise(5) * 1.5))  # sandstone banding
	t = 0.35 * tone + 0.25 * noise(16) + 0.2 * layers + 0.2 * rng.random((N, N))
	img = colorize(t, [(0.0, (128, 84, 58)), (0.4, (170, 112, 74)), (0.7, (196, 140, 96)), (1.0, (222, 176, 128))])
	img *= (0.45 + 0.55 * edge)[..., None]
	# Sand settled in the cracks.
	fill = (1 - edge)[..., None] * 0.5
	img = img * (1 - fill) + np.array([206, 172, 120]) * fill
	save(img, "desert_stone_color.png")


if __name__ == "__main__":
	sand()
	desert_stone()
