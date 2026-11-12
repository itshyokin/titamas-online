"""Campfire crackle loop (Campfire):
    python3 tools/audio/make_campfire_sounds.py
Writes assets/audio/ambience/campfire_loop.ogg: a low breathy roar with random pops and
crackles, seamless."""
import os
import subprocess

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "ambience")
rng = np.random.default_rng(7)


def periodic_band(n, lo, hi):
	spec = np.fft.rfft(rng.standard_normal(n))
	f = np.fft.rfftfreq(n, 1 / SR)
	spec *= (f > lo) & (f < hi)
	x = np.fft.irfft(spec, n)
	return x / (np.std(x) + 1e-9)


def crackles(n, per_sec, seed, loud=1.0):
	r = np.random.default_rng(seed)
	out = np.zeros(n)
	for _ in range(int(per_sec * n / SR)):
		start = r.integers(0, n)
		m = int(r.uniform(0.002, 0.012) * SR)
		burst = r.standard_normal(m) * np.exp(-np.arange(m) / (m * 0.25)) * r.uniform(0.1, 1.0) ** 2 * loud
		idx = (start + np.arange(m)) % n
		out[idx] += burst
	return out


def save(name, l, r, peak_db=-4.0):
	x = np.stack([l, r], 1)
	x = x / (np.max(np.abs(x)) + 1e-9) * 10 ** (peak_db / 20)
	os.makedirs(OUT, exist_ok=True)
	pcm = (x * 32767).astype(np.int16).tobytes()
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
		"-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, name)], input=pcm, check=True)
	print("wrote", name)


if __name__ == "__main__":
	n = SR * 10
	roar = periodic_band(n, 60, 500) * 0.25
	hiss = periodic_band(n, 2000, 9000) * 0.05
	save("campfire_loop.ogg", roar + hiss + crackles(n, 22, 1) + crackles(n, 2, 3, 2.5), roar + hiss + crackles(n, 22, 2) + crackles(n, 2, 4, 2.5))
