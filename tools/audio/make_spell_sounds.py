"""Spell sounds for the class skills and mage spells (abilities.json).
    python3 tools/audio/make_spell_sounds.py            (all)
    python3 tools/audio/make_spell_sounds.py ward_up    (one)
Writes assets/audio/spells/*.ogg (numpy + ffmpeg). Original, synthesised."""
import os
import subprocess
import sys

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "spells")
rng = np.random.default_rng(23)


def save(name, x, peak_db=-3.0):
	x = x / (np.max(np.abs(x)) or 1) * 10 ** (peak_db / 20)
	raw = (x * 32767).astype(np.int16).tobytes()
	os.makedirs(OUT, exist_ok=True)
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
		"-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, name + ".ogg")], input=raw, check=True)
	print("wrote", name)


def t_of(seconds):
	return np.arange(int(SR * seconds)) / SR


def band_noise(n, lo, hi):
	spec = np.fft.rfft(rng.standard_normal(n))
	f = np.fft.rfftfreq(n, 1 / SR)
	spec *= (f > lo) & (f < hi)
	x = np.fft.irfft(spec, n)
	return x / (np.std(x) + 1e-9)


def env(t, attack, decay):
	return np.minimum(t / max(attack, 1e-4), 1) * np.exp(-t / decay)


def sweep_noise(seconds, lo0, hi0, lo1, hi1, steps=24):
	"""Noise whose band moves from (lo0, hi0) to (lo1, hi1): a whoosh."""
	n = int(SR * seconds)
	out = np.zeros(n)
	w = n // steps
	for i in range(steps):
		k = i / max(steps - 1, 1)
		seg = band_noise(w * 2, lo0 + (lo1 - lo0) * k, hi0 + (hi1 - hi0) * k)[:w * 2]
		win = np.hanning(w * 2)
		a = i * w
		b = min(a + w * 2, n)
		out[a:b] += (seg * win)[:b - a]
	return out


def chime(freqs, seconds, decay):
	t = t_of(seconds)
	return sum(np.sin(2 * np.pi * f * t) * np.exp(-t / (decay * (1 - i * 0.12))) / (i + 1) for i, f in enumerate(freqs)) * env(t, 0.004, 99)


def rage_roar():
	t = t_of(1.2)
	growl = np.sin(2 * np.pi * (70 + 25 * np.sin(2 * np.pi * 7 * t)) * t) * (1 + 0.6 * np.sin(2 * np.pi * 31 * t))
	growl += band_noise(len(t), 120, 900) * 0.6
	fire = sweep_noise(1.2, 200, 1500, 600, 4000) * 0.5
	return (growl * env(t, 0.08, 0.5) + fire * env(t, 0.15, 0.6))


def lightning_zap():
	t = t_of(0.7)
	crack = band_noise(len(t), 1500, 12000) * env(t, 0.001, 0.05)
	# Crackle: random spikes thinning out.
	sp = (rng.random(len(t)) < 0.02 * np.exp(-t / 0.25)).astype(float) * rng.choice([-1, 1], len(t))
	crackle = np.convolve(sp, np.exp(-np.arange(80) / 12.0), mode="same")
	hum = np.sin(2 * np.pi * 110 * t) * np.sign(np.sin(2 * np.pi * 55 * t)) * env(t, 0.005, 0.18) * 0.3
	return crack + crackle * 0.8 + hum


def frost_cast():
	t = t_of(0.8)
	air = sweep_noise(0.8, 3000, 9000, 1500, 5000) * env(t, 0.05, 0.35) * 0.5
	return air + chime([1760, 2637, 3520], 0.8, 0.3) * 0.5


def ice_freeze():
	t = t_of(0.9)
	cracks = np.zeros(len(t))
	for _ in range(9):
		at = int(rng.uniform(0, 0.35) * SR)
		c = band_noise(2200, 2000, 9000) * np.exp(-np.arange(2200) / 260.0)
		cracks[at:at + 2200] += c[:len(t) - at] * rng.uniform(0.4, 1.0)
	ring = chime([2093, 3136, 4186], 0.9, 0.35) * 0.35
	return cracks + ring


def water_wave():
	t = t_of(1.4)
	rush = sweep_noise(1.4, 150, 1200, 400, 3000) * env(t, 0.18, 0.55)
	splash = band_noise(len(t), 600, 7000) * env(np.maximum(t - 0.35, 0), 0.01, 0.25) * (t > 0.35) * 0.7
	return rush + splash


def ward_up():
	t = t_of(1.3)
	shimmer = chime([523, 784, 1047, 1568], 1.3, 0.6)
	swell = sweep_noise(1.3, 2000, 6000, 3000, 9000) * env(t, 0.3, 0.5) * 0.25
	return shimmer * (1 + 0.3 * np.sin(2 * np.pi * 9 * t)) + swell


def ward_block():
	return chime([1318, 1976, 2637], 0.5, 0.15) + band_noise(int(SR * 0.5), 3000, 9000) * env(t_of(0.5), 0.001, 0.02) * 0.4


def teleport_out():
	t = t_of(0.6)
	suck = sweep_noise(0.6, 3000, 8000, 200, 1200) * env(t, 0.25, 0.4)
	return suck + np.sin(2 * np.pi * (900 - 700 * t / 0.6) * t) * env(t, 0.05, 0.25) * 0.5


def teleport_in():
	t = t_of(0.7)
	pop = band_noise(len(t), 200, 3000) * env(t, 0.002, 0.06)
	bloom = sweep_noise(0.7, 300, 1500, 2500, 8000) * env(t, 0.02, 0.3) * 0.6
	return pop + bloom + chime([880, 1320], 0.7, 0.25) * 0.4


def heal_burst():
	t = t_of(1.6)
	chord = chime([659, 831, 988, 1319, 1661], 1.6, 0.7)
	sparkle = band_noise(len(t), 5000, 11000) * env(t, 0.1, 0.4) * 0.15
	return chord + sparkle


def dark_cloud():
	t = t_of(2.2)
	rumble = band_noise(len(t), 40, 260) * env(t, 0.4, 1.2)
	breath = sweep_noise(2.2, 300, 1200, 100, 600) * env(t, 0.5, 0.9) * 0.6
	moan = np.sin(2 * np.pi * (98 + 6 * np.sin(2 * np.pi * 0.7 * t)) * t) * env(t, 0.6, 1.0) * 0.35
	return rumble + breath + moan


SOUNDS = {
	"rage_roar": (rage_roar, -2.0),
	"lightning_zap": (lightning_zap, -2.0),
	"frost_cast": (frost_cast, -4.0),
	"ice_freeze": (ice_freeze, -3.0),
	"water_wave": (water_wave, -2.0),
	"ward_up": (ward_up, -4.0),
	"ward_block": (ward_block, -5.0),
	"teleport_out": (teleport_out, -3.0),
	"teleport_in": (teleport_in, -3.0),
	"heal_burst": (heal_burst, -4.0),
	"dark_cloud": (dark_cloud, -3.0),
}


def main():
	names = sys.argv[1:] or list(SOUNDS)
	for n in names:
		f, db = SOUNDS[n]
		save(n, f(), db)


if __name__ == "__main__":
	main()
