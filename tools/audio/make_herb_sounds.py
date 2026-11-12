"""Picking herbs: python3 tools/audio/make_herb_sounds.py -> assets/audio/sfx/pick_herb.ogg
(a leafy rustle and a soft stem snap)."""
import os
import subprocess

import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "sfx")


def main():
	rng = np.random.default_rng(5)
	tt = np.arange(int(0.6 * SR)) / SR
	rustle = sosfilt(butter(2, [1500, 8000], "band", fs=SR, output="sos"), rng.standard_normal(len(tt)))
	rustle *= (np.sin(np.pi * np.clip(tt / 0.45, 0, 1)) ** 2) * (0.6 + 0.4 * (rng.random(len(tt)) > 0.97))
	snap = np.zeros(len(tt))
	i0 = int(0.28 * SR)
	k = np.arange(int(0.05 * SR)) / SR
	snap[i0:i0 + len(k)] = sosfilt(butter(2, [900, 4000], "band", fs=SR, output="sos"), rng.standard_normal(len(k))) * np.exp(-k * 120) * 3
	x = rustle * 0.5 + snap
	x = x / np.max(np.abs(x)) * 0.7
	pcm = (np.stack([x, x], 1) * 32767).astype(np.int16).tobytes()
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
		"-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, "pick_herb.ogg")], input=pcm, check=True)
	print("wrote pick_herb.ogg")


if __name__ == "__main__":
	main()
