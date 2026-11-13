"""Sounds for the TitanTech Emitter (an energy revolver).
    python3 tools/audio/make_emitter_sounds.py
Writes assets/audio/weapons/emitter_shot.ogg and emitter_swap.ogg (numpy + ffmpeg).
Original, synthesised."""
import os
import subprocess

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "weapons")
rng = np.random.default_rng(41)


def save(name, x, peak_db=-3.0):
	x = x / (np.max(np.abs(x)) or 1) * 10 ** (peak_db / 20)
	raw = (x * 32767).astype(np.int16).tobytes()
	os.makedirs(OUT, exist_ok=True)
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
		"-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, name + ".ogg")], input=raw, check=True)
	print("wrote", name)


def t_of(seconds):
	return np.arange(int(SR * seconds)) / SR


def shot():
	t = t_of(0.42)
	# A bright zap sweeping down, a buzzy square edge, a little crackle, a soft thump.
	f = 2600 * np.exp(-t * 11) + 260
	phase = 2 * np.pi * np.cumsum(f) / SR
	zap = np.sin(phase) * np.exp(-t * 9)
	buzz = np.sign(np.sin(phase * 0.5)) * 0.25 * np.exp(-t * 14)
	crackle = rng.standard_normal(len(t)) * (rng.random(len(t)) < 0.06) * np.exp(-t * 18) * 0.6
	thump = np.sin(2 * np.pi * 90 * t) * np.exp(-t * 22) * 0.7
	ring = np.sin(2 * np.pi * 1320 * t) * np.exp(-t * 5) * 0.12
	return zap + buzz + crackle + thump + ring


def swap():
	t = t_of(0.5)
	# Powering up: a rising hum and a click.
	f = 180 + 900 * t
	hum = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.minimum(t * 6, 1) * np.exp(-t * 3) * 0.6
	click = np.zeros_like(t)
	n = int(0.012 * SR)
	click[:n] = rng.standard_normal(n) * np.linspace(1, 0, n)
	return hum + click


if __name__ == "__main__":
	save("emitter_shot", shot(), -2.0)
	save("emitter_swap", swap(), -6.0)
