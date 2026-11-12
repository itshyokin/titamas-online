"""Desert ambience for the Singed Plains (and any hot, dry region):
    python3 tools/audio/make_desert_sounds.py
Writes assets/audio/ambience/desert_day_loop.ogg (dry gusting wind with sand hiss and a high
whistle), desert_night_loop.ogg (cool low wind and sparse crickets), and one-shots for
regions.json random_sounds: hawk_cry.ogg, sand_gust.ogg, lava_rumble.ogg."""
import os
import subprocess

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "ambience")
rng = np.random.default_rng(23)


def t(sec):
	return np.arange(int(SR * sec)) / SR


def periodic_band(n, lo, hi, tilt=0.0):
	"""Band noise that wraps seamlessly (made in frequency space over the whole loop)."""
	spec = np.fft.rfft(rng.standard_normal(n))
	f = np.fft.rfftfreq(n, 1 / SR)
	spec *= (f > lo) & (f < hi)
	if tilt:
		spec *= np.where(f > 0, (np.maximum(f, 1) / 1000.0) ** -tilt, 0)
	x = np.fft.irfft(spec, n)
	return x / (np.std(x) + 1e-9)


def periodic_env(n, rate, depth, seed):
	"""A slow wobble that wraps: a sum of sines with whole cycles over the loop."""
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


def env(n, a, d):
	e = np.ones(n)
	ia, idd = max(int(SR * a), 1), max(int(SR * d), 1)
	e[:ia] = np.linspace(0, 1, ia)
	e[n - idd:] = np.linspace(1, 0, idd) ** 2
	return e


def main():
	# Day: dry wind in gusts, a hiss of blown sand on the strong ones, a thin whistle.
	n = SR * 30
	gust = periodic_env(n, 0.25, 0.8, 1)
	low = periodic_band(n, 50, 700, 0.6) * gust
	hiss = periodic_band(n, 2500, 9000) * gust ** 3 * 0.35
	tt = np.arange(n) / SR
	whistle_f = 820 + 120 * np.sin(2 * np.pi * 2 * tt / 30)
	whistle = np.sin(2 * np.pi * np.cumsum(whistle_f) / SR) * gust ** 4 * 0.05
	lo2 = periodic_band(n, 50, 700, 0.6) * periodic_env(n, 0.25, 0.8, 2)
	save("desert_day_loop.ogg", low + hiss + whistle, lo2 + hiss * 0.9 + whistle, -6.0)

	# Night: soft cool wind and a few far-off crickets.
	n = SR * 30
	wind = periodic_band(n, 40, 400, 0.8) * periodic_env(n, 0.15, 0.6, 3) * 0.6
	tt = np.arange(n) / SR
	crick = np.zeros(n)
	for start in rng.uniform(0, 29, 26):
		i0 = int(start * SR)
		chirp = t(0.18)
		c = np.sin(2 * np.pi * 4300 * chirp) * (np.sin(2 * np.pi * 45 * chirp) > 0) * env(len(chirp), 0.01, 0.05)
		crick[i0:i0 + len(c)] += c[: max(0, min(len(c), n - i0))] * rng.uniform(0.04, 0.1)
	save("desert_night_loop.ogg", wind + crick, wind * 0.9 + np.roll(crick, 900), -9.0)

	# Hawk: a high descending screech, twice.
	cry = np.zeros(int(SR * 2.2))
	for at, length in ((0.0, 0.8), (1.0, 1.0)):
		tt = t(length)
		f = 2600 - 900 * (tt / length) ** 0.7
		v = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.3 * np.sin(4 * np.pi * np.cumsum(f) / SR)
		v *= env(len(tt), 0.04, 0.35) * (1 + 0.3 * np.sin(2 * np.pi * 38 * tt))
		i0 = int(at * SR)
		cry[i0:i0 + len(v)] += v[: len(cry) - i0]
	breath = np.convolve(rng.standard_normal(len(cry)), np.ones(20) / 20, "same") * 0.05
	save("hawk_cry.ogg", cry * 0.6 + breath * (np.abs(cry) > 0.05), peak_db=-6.0)

	# Sand gust: a rush of wind with grains hissing past.
	tt = t(3.0)
	e = np.sin(np.pi * tt / 3.0) ** 2
	g = periodic_band(len(tt), 100, 1200, 0.5) * e + periodic_band(len(tt), 3000, 10000) * e ** 2 * 0.5
	save("sand_gust.ogg", g, np.roll(g, 600), -4.0)

	# Lava rumble: a deep bubbling growl with pops.
	tt = t(3.5)
	rumble = periodic_band(len(tt), 20, 160) * env(len(tt), 0.6, 1.5)
	pops = np.zeros(len(tt))
	for at in rng.uniform(0.3, 3.0, 9):
		i0 = int(at * SR)
		p = t(0.12)
		b = np.sin(2 * np.pi * (180 + 300 * p) * p) * np.exp(-p * 40)
		pops[i0:i0 + len(b)] += b[: len(pops) - i0] * rng.uniform(0.3, 0.7)
	save("lava_rumble.ogg", rumble + pops, peak_db=-5.0)


if __name__ == "__main__":
	main()
