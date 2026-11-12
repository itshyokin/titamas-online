"""Running water for rivers, streams and waterfalls (ChunkStreamer._make_river):
    python3 tools/audio/make_river_sounds.py
Writes assets/audio/ambience/river_loop.ogg (babbling stream: soft rush plus little bubbling
plinks) and waterfall_loop.ogg (deep steady roar with spray hiss). Both loop seamlessly."""
import os
import subprocess

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "ambience")
rng = np.random.default_rng(41)


def periodic_band(n, lo, hi, tilt=0.0):
	spec = np.fft.rfft(rng.standard_normal(n))
	f = np.fft.rfftfreq(n, 1 / SR)
	spec *= (f > lo) & (f < hi)
	if tilt:
		spec *= np.where(f > 0, (np.maximum(f, 1) / 1000.0) ** -tilt, 0)
	x = np.fft.irfft(spec, n)
	return x / (np.std(x) + 1e-9)


def periodic_env(n, rate, depth, seed):
	r = np.random.default_rng(seed)
	sec = n / SR
	e = np.zeros(n)
	tt = np.arange(n) / SR
	for k in range(1, 6):
		cycles = max(1, int(round(rate * sec * k / 3)))
		e += np.sin(2 * np.pi * cycles * tt / sec + r.random() * 6.28) / k
	e = (e - e.min()) / (e.max() - e.min() + 1e-9)
	return 1 - depth + depth * e


def save(name, l, r=None, peak_db=-3.0):
	r = l if r is None else r
	x = np.stack([l, r], 1)
	x = x / (np.max(np.abs(x)) + 1e-9) * 10 ** (peak_db / 20)
	os.makedirs(OUT, exist_ok=True)
	pcm = (x * 32767).astype(np.int16).tobytes()
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
		"-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, name)], input=pcm, check=True)
	print("wrote", name)


def bubbles(n, per_sec, seed):
	"""Little rising plinks scattered through the loop (wrapping round the end)."""
	r = np.random.default_rng(seed)
	out = np.zeros(n)
	count = int(per_sec * n / SR)
	for _ in range(count):
		start = r.integers(0, n)
		dur = r.uniform(0.02, 0.06)
		m = int(dur * SR)
		tt = np.arange(m) / SR
		f0 = r.uniform(500, 1400)
		f = f0 * (1 + tt / dur * r.uniform(0.4, 1.2))
		ph = 2 * np.pi * np.cumsum(f) / SR
		s = np.sin(ph) * np.exp(-tt / (dur * 0.35)) * r.uniform(0.2, 1.0)
		idx = (start + np.arange(m)) % n
		out[idx] += s
	return out


def river():
	n = SR * 12
	rush_l = periodic_band(n, 200, 5000, tilt=0.7) * periodic_env(n, 0.3, 0.35, 1)
	rush_r = periodic_band(n, 200, 5000, tilt=0.7) * periodic_env(n, 0.3, 0.35, 2)
	low = periodic_band(n, 60, 300) * 0.5
	b_l = bubbles(n, 14, 3) * 0.55
	b_r = bubbles(n, 14, 4) * 0.55
	save("river_loop.ogg", rush_l + low + b_l, rush_r + low + b_r, -6.0)


def waterfall():
	n = SR * 10
	roar = periodic_band(n, 40, 900, tilt=0.4) * 1.2
	hiss_l = periodic_band(n, 1500, 12000, tilt=0.3) * 0.6 * periodic_env(n, 0.6, 0.2, 5)
	hiss_r = periodic_band(n, 1500, 12000, tilt=0.3) * 0.6 * periodic_env(n, 0.6, 0.2, 6)
	body_l = periodic_band(n, 300, 3000) * 0.8
	body_r = periodic_band(n, 300, 3000) * 0.8
	save("waterfall_loop.ogg", roar + hiss_l + body_l, roar + hiss_r + body_r, -3.0)


if __name__ == "__main__":
	river()
	waterfall()
