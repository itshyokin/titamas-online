"""Golem sounds (Beast body "golem"):
    python3 tools/audio/make_golem_sounds.py
Writes assets/audio/creatures/golem_burst.ogg (bursting out of the ground), golem_groan.ogg
(grinding stone voice), shard_fire.ogg (a crystal shard whistling off), shard_hit.ogg,
golem_fuse.ogg (the gilded golem's rising hum before it blows) and gold_blast.ogg."""
import os
import subprocess

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "creatures")
rng = np.random.default_rng(11)


def t(sec):
	return np.arange(int(SR * sec)) / SR


def bandnoise(n, lo, hi):
	spec = np.fft.rfft(rng.standard_normal(n))
	f = np.fft.rfftfreq(n, 1 / SR)
	spec *= (f > lo) & (f < hi)
	x = np.fft.irfft(spec, n)
	return x / (np.std(x) + 1e-9)


def env(n, a, d):
	e = np.ones(n)
	ia, idd = max(int(SR * a), 1), max(int(SR * d), 1)
	e[:ia] = np.linspace(0, 1, ia)
	e[n - idd:] = np.linspace(1, 0, idd) ** 2
	return e


def crackles(n, rate, size=8.0):
	c = (rng.random(n) > 1.0 - rate) * rng.standard_normal(n) * size
	return np.convolve(c, np.exp(-np.arange(300) / 40), "same")


def save(name, x):
	x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
	os.makedirs(OUT, exist_ok=True)
	pcm = (np.stack([x, x], 1) * 32767).astype(np.int16).tobytes()
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
		"-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, name)], input=pcm, check=True)
	print("wrote", name)


def main():
	# Bursting out: a deep crack, rumble and falling stones.
	tt = t(2.0)
	rumble = bandnoise(len(tt), 25, 220) * np.exp(-tt * 1.6) * (1 - np.exp(-tt * 40))
	crack = bandnoise(len(tt), 300, 5000) * np.exp(-tt * 18)
	stones = crackles(len(tt), 0.0015) * np.exp(-tt * 1.2)
	save("golem_burst.ogg", rumble * 1.2 + crack * 0.8 + stones * 0.4)

	# Groan: slow grinding rock, a low pitched rasp.
	tt = t(1.8)
	f0 = 45 + 15 * np.sin(np.pi * tt / 1.8)
	ph = 2 * np.pi * np.cumsum(f0) / SR
	voice = sum(np.sign(np.sin(ph * k)) / k ** 1.3 for k in range(1, 6))
	grind = bandnoise(len(tt), 100, 1600) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 13 * tt)))
	save("golem_groan.ogg", (voice * 0.4 + grind * 0.5 + crackles(len(tt), 0.0008) * 0.3) * env(len(tt), 0.2, 0.6))

	# Shard: a glassy whistle falling in pitch, with an airy rush.
	tt = t(0.5)
	f = 2400 * np.exp(-tt * 2.2) + 700
	tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 5)
	save("shard_fire.ogg", tone * 0.6 + bandnoise(len(tt), 1500, 8000) * 0.4 * np.exp(-tt * 9))

	# Shard hit: a brittle crystal shatter.
	tt = t(0.45)
	ring = sum(np.sin(2 * np.pi * fr * tt) * np.exp(-tt * d) for fr, d in ((2900, 14), (4100, 18), (5300, 22)))
	save("shard_hit.ogg", ring * 0.5 + bandnoise(len(tt), 2000, 10000) * np.exp(-tt * 25) + crackles(len(tt), 0.006, 3))

	# Fuse: a hum rising in pitch and wobbling faster, crackling with energy.
	tt = t(1.6)
	f = 110 * 2 ** (tt / 1.6 * 2.0)
	wob = 1 + 0.4 * np.sin(2 * np.pi * np.cumsum(4 + tt * 14) / SR)
	ph = 2 * np.pi * np.cumsum(f) / SR
	hum = (np.sin(ph) + 0.5 * np.sin(ph * 2) + 0.25 * np.sin(ph * 3)) * wob
	save("golem_fuse.ogg", (hum * 0.6 + crackles(len(tt), 0.002, 4) * 0.4) * env(len(tt), 0.1, 0.05) * (0.4 + 0.6 * tt / 1.6))

	# Gold blast: a big boom with a bright shimmer and stones.
	tt = t(2.6)
	boom = bandnoise(len(tt), 20, 400) * np.exp(-tt * 2.5) * (1 - np.exp(-tt * 200))
	shimmer = sum(np.sin(2 * np.pi * fr * tt) for fr in (1320, 1760, 2640)) * np.exp(-tt * 3) * 0.15
	save("gold_blast.ogg", boom * 1.4 + shimmer + bandnoise(len(tt), 500, 6000) * np.exp(-tt * 8) * 0.5 + crackles(len(tt), 0.001) * 0.3)


if __name__ == "__main__":
	main()
