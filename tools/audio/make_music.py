"""Orchestral-style music for Titamas Online, written in the spirit of The Legend of
Dragoon's score (harp and strings, lonely woodwinds, choir, big timpani for battles), all
synthesised here from scratch (no samples):

    python3 tools/audio/make_music.py            # every track
    python3 tools/audio/make_music.py forest     # just one (forest, forest_night, monolith,
                                                 # singed_plains, singed_night, combat, boss)

Writes seamless loops to assets/audio/music/<name>.ogg (the reverb tail is wrapped onto
the start so the loop point can't be heard). Each track is a small score below: chords,
a melody and accompaniment patterns, played by the instruments in the Synth section.
"""
import os
import subprocess
import sys

import numpy as np
from scipy.signal import fftconvolve, butter, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "music")
rng = np.random.default_rng(1998)


# --- Synth ---------------------------------------------------------------------------------

def hz(m):
	return 440.0 * 2 ** ((m - 69) / 12)


def adsr(n, a, d, s, r):
	e = np.full(n, s, dtype=float)
	ia, idd, ir = int(a * SR), int(d * SR), int(r * SR)
	ia = min(ia, n)
	e[:ia] = np.linspace(0, 1, ia, endpoint=False) if ia else e[:ia]
	if idd and ia < n:
		k = min(idd, n - ia)
		e[ia:ia + k] = np.linspace(1, s, idd)[:k]
	if ir:
		k = min(ir, n)
		e[n - k:] *= np.linspace(1, 0, k) ** 1.5
	return e


def additive(f, n, amps, detune_cents=0.0, vib=0.0, vib_rate=5.2, vib_delay=0.25):
	"""Sum of harmonics (amps[k] for harmonic k+1), dropping any above 15 kHz."""
	tt = np.arange(n) / SR
	vib_env = np.clip((tt - vib_delay) / 0.4, 0, 1) * vib
	fm = f * 2 ** ((detune_cents + vib_env * 100 * np.sin(2 * np.pi * vib_rate * tt + rng.random() * 6)) / 1200)
	ph = 2 * np.pi * np.cumsum(fm) / SR
	out = np.zeros(n)
	for k, a in enumerate(amps):
		if a == 0 or f * (k + 1) > 15000:
			continue
		out += a * np.sin(ph * (k + 1) + rng.random() * 6.28)
	return out


def strings(f, dur, vel):
	n = int((dur + 0.5) * SR)
	amps = [1 / (k + 1) ** 1.15 for k in range(24)]
	x = sum(additive(f, n, amps, c, vib=0.06, vib_rate=5.0) for c in (-7, 0, 6))
	return x * adsr(n, 0.25, 0.3, 0.85, 0.5) * vel * 0.11


def strings_short(f, dur, vel):
	"""Spiccato / staccato ostinato."""
	n = int((min(dur, 0.25) + 0.12) * SR)
	amps = [1 / (k + 1) ** 1.0 for k in range(20)]
	x = sum(additive(f, n, amps, c) for c in (-5, 5))
	return x * adsr(n, 0.008, 0.08, 0.45, 0.1) * vel * 0.2


def pluck(f, dur, vel, bright=0.5, decay=0.996):
	"""Karplus-Strong string (harp, oud, pizzicato), worked a whole period at a time."""
	n = int((dur + 1.2) * SR)
	p = max(int(SR / f), 2)
	buf = rng.uniform(-1, 1, p)
	# Soften the attack noise for a rounder harp.
	for _ in range(int((1 - bright) * 10)):
		buf = 0.5 * (buf + np.roll(buf, 1))
	out = np.zeros(n)
	k = 0
	while k < n:
		m = min(p, n - k)
		out[k:k + m] = buf[:m]
		buf = decay * 0.5 * (buf + np.roll(buf, 1))
		k += p
	return out * adsr(n, 0.002, 0.0, 1.0, 0.25) * vel * 0.5


def flute(f, dur, vel):
	n = int((dur + 0.3) * SR)
	x = additive(f, n, [1.0, 0.18, 0.08, 0.03], vib=0.12, vib_rate=5.3, vib_delay=0.3)
	breath = sosfilt(butter(2, [min(f * 0.8, 9000), min(f * 3, 15000)], "band", fs=SR, output="sos"), rng.standard_normal(n)) * 0.08
	return (x + breath) * adsr(n, 0.06, 0.1, 0.8, 0.25) * vel * 0.32


def oboe(f, dur, vel):
	n = int((dur + 0.3) * SR)
	x = additive(f, n, [0.5, 1.0, 0.8, 0.55, 0.4, 0.3, 0.2, 0.12, 0.08, 0.05], vib=0.08, vib_rate=5.6)
	return x * adsr(n, 0.04, 0.1, 0.8, 0.2) * vel * 0.16


def brass(f, dur, vel):
	n = int((dur + 0.3) * SR)
	tt = np.arange(n) / SR
	swell = np.clip(tt / 0.12, 0, 1)
	out = np.zeros(n)
	ph = 2 * np.pi * np.cumsum(np.full(n, f)) / SR
	for k in range(14):
		if f * (k + 1) > 14000:
			break
		# Brighter as it swells: upper harmonics come in with the attack.
		out += np.sin(ph * (k + 1)) * (1 / (k + 1)) * swell ** (1 + k * 0.4)
	return out * adsr(n, 0.05, 0.2, 0.75, 0.2) * vel * 0.22


def choir(f, dur, vel, vowel="ah"):
	n = int((dur + 0.6) * SR)
	formants = {"ah": [(800, 1.0), (1150, 0.5), (2900, 0.18)], "oo": [(350, 1.0), (600, 0.4), (2400, 0.08)]}[vowel]
	amps = []
	for k in range(40):
		h = f * (k + 1)
		a = sum(g * np.exp(-((h - fc) / 160.0) ** 2) for fc, g in formants) + 0.03 / (k + 1)
		amps.append(a)
	x = sum(additive(f, n, amps, c, vib=0.1, vib_rate=4.8) for c in (-9, 0, 8))
	return x * adsr(n, 0.5, 0.3, 0.9, 0.7) * vel * 0.09


def bell(f, dur, vel):
	n = int((dur + 2.5) * SR)
	tt = np.arange(n) / SR
	out = np.zeros(n)
	for ratio, a, d in ((1.0, 1.0, 1.4), (2.76, 0.5, 2.2), (5.4, 0.25, 3.5), (8.93, 0.12, 5.0)):
		if f * ratio < 15000:
			out += a * np.sin(2 * np.pi * f * ratio * tt) * np.exp(-tt * d)
	return out * vel * 0.25 * adsr(n, 0.001, 0, 1, 0.05)


def timpani(f, dur, vel):
	n = int(1.6 * SR)
	tt = np.arange(n) / SR
	fm = f * (1 + 0.12 * np.exp(-tt * 30))
	body = np.sin(2 * np.pi * np.cumsum(fm) / SR) * np.exp(-tt * 3.2) + 0.4 * np.sin(2 * np.pi * np.cumsum(fm * 1.5) / SR) * np.exp(-tt * 5)
	hit = sosfilt(butter(2, 900, "low", fs=SR, output="sos"), rng.standard_normal(n)) * np.exp(-tt * 40) * 0.6
	return (body + hit) * vel * 0.6


def taiko(f, dur, vel):
	n = int(1.2 * SR)
	tt = np.arange(n) / SR
	fm = 70 * (1 + 0.8 * np.exp(-tt * 25))
	body = np.sin(2 * np.pi * np.cumsum(fm) / SR) * np.exp(-tt * 6)
	slap = sosfilt(butter(2, [150, 1500], "band", fs=SR, output="sos"), rng.standard_normal(n)) * np.exp(-tt * 30)
	return (body + slap * 0.7) * vel * 0.8


def frame_drum(f, dur, vel):
	"""f < 200: the deep 'doum'; otherwise the bright 'tek' at the rim."""
	tt = np.arange(int(0.5 * SR)) / SR
	if f < 200:
		x = np.sin(2 * np.pi * 95 * (1 + 0.5 * np.exp(-tt * 40)) * tt) * np.exp(-tt * 12)
		x += sosfilt(butter(2, 400, "low", fs=SR, output="sos"), rng.standard_normal(len(tt))) * np.exp(-tt * 30) * 0.3
	else:
		x = sosfilt(butter(2, [1800, 7000], "band", fs=SR, output="sos"), rng.standard_normal(len(tt))) * np.exp(-tt * 55)
		x += np.sin(2 * np.pi * 620 * tt) * np.exp(-tt * 45) * 0.4
	return x * vel * 0.9


def cymbal(f, dur, vel):
	n = int(2.5 * SR)
	tt = np.arange(n) / SR
	x = sosfilt(butter(2, 3500, "high", fs=SR, output="sos"), rng.standard_normal(n)) * np.exp(-tt * 1.6)
	return x * adsr(n, 0.25 if f > 0 else 0.001, 0, 1, 0.3) * vel * 0.12


def shaker(f, dur, vel):
	tt = np.arange(int(0.12 * SR)) / SR
	return sosfilt(butter(2, 5000, "high", fs=SR, output="sos"), rng.standard_normal(len(tt))) * np.exp(-tt * 40) * vel * 0.12


INSTRUMENTS = {
	"strings": strings, "spiccato": strings_short, "harp": lambda f, d, v: pluck(f, d, v * 1.7, 0.35, 0.9975),
	"pizz": lambda f, d, v: pluck(f, d, v * 1.2, 0.2, 0.990), "oud": lambda f, d, v: pluck(f, d, v * 1.8, 0.8, 0.994),
	"flute": flute, "oboe": oboe, "brass": brass, "choir": choir, "choir_oo": lambda f, d, v: choir(f, d, v, "oo"),
	"bell": bell, "timpani": timpani, "taiko": taiko, "drum": frame_drum, "cymbal": cymbal, "shaker": shaker,
}


# --- Score ---------------------------------------------------------------------------------

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def m(name):
	"""'C4', 'F#3', 'Bb2' -> midi."""
	base = NOTE[name[0]]
	i = 1
	while i < len(name) and name[i] in "#b":
		base += 1 if name[i] == "#" else -1
		i += 1
	return base + 12 * (int(name[i:]) + 1)


class Song:
	def __init__(self, bpm, bars, beats=4):
		self.bpm = bpm
		self.beat = 60.0 / bpm
		self.beats_per_bar = beats
		self.length = bars * beats * self.beat
		self.n = int(self.length * SR)
		self.tail = int(6 * SR)
		self.l = np.zeros(self.n + self.tail)
		self.r = np.zeros(self.n + self.tail)
		self.wet = {}  # instrument -> reverb send

	def play(self, inst, note, beat, beats, vel=0.8, pan=0.0, human=0.012):
		f = hz(m(note) if isinstance(note, str) else note)
		x = INSTRUMENTS[inst](f, beats * self.beat, vel * rng.uniform(0.9, 1.05))
		at = int(max(beat * self.beat + rng.normal(0, human), 0) * SR)
		end = min(at + len(x), len(self.l))
		if at >= end:
			return
		x = x[: end - at]
		gl, gr = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
		self.l[at:end] += x * gl
		self.r[at:end] += x * gr

	def chord(self, inst, notes, beat, beats, vel=0.7, spread=0.6):
		for i, nt in enumerate(notes):
			pan = (i / max(len(notes) - 1, 1) - 0.5) * spread
			self.play(inst, nt, beat, beats, vel, pan)

	def melody(self, inst, start_beat, notes, vel=0.8, pan=0.0):
		"""notes: [(note or None for a rest, beats), ...]."""
		b = start_beat
		for nt, length in notes:
			if nt is not None:
				self.play(inst, nt, b, length, vel, pan)
			b += length
		return b

	def render(self, name, reverb=0.35, room=2.6, peak_db=-1.5):
		dry = np.stack([self.l, self.r], 1)
		# Hall reverb: decaying noise, different on each side.
		ir_n = int(room * SR)
		tt = np.arange(ir_n) / SR
		ir_l = rng.standard_normal(ir_n) * np.exp(-tt * 6.9 / room)
		ir_r = rng.standard_normal(ir_n) * np.exp(-tt * 6.9 / room)
		lp = butter(1, 6000, "low", fs=SR, output="sos")
		ir_l, ir_r = sosfilt(lp, ir_l), sosfilt(lp, ir_r)
		ir_l /= np.sqrt(np.sum(ir_l ** 2))
		ir_r /= np.sqrt(np.sum(ir_r ** 2))
		pre = int(0.025 * SR)
		wl = np.concatenate([np.zeros(pre), fftconvolve(dry[:, 0] + dry[:, 1] * 0.3, ir_l)])[: len(dry)]
		wr = np.concatenate([np.zeros(pre), fftconvolve(dry[:, 1] + dry[:, 0] * 0.3, ir_r)])[: len(dry)]
		mix = dry * (1 - reverb * 0.5) + np.stack([wl, wr], 1) * reverb * 0.9
		# Seamless loop: everything past the end (tails) wraps onto the start.
		loop = mix[: self.n].copy()
		tail = mix[self.n:]
		k = min(len(tail), self.n)
		loop[:k] += tail[:k]
		# Gentle glue: soft saturation, then to the target peak.
		loop = np.tanh(loop / (np.max(np.abs(loop)) + 1e-9) * 1.4) / np.tanh(1.4)
		loop *= 10 ** (peak_db / 20)
		os.makedirs(OUT, exist_ok=True)
		pcm = (loop * 32767).astype(np.int16).tobytes()
		path = os.path.join(OUT, name + ".ogg")
		subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
			"-c:a", "libvorbis", "-q:a", "6", path], input=pcm, check=True)
		print("wrote %s (%.0f s)" % (name + ".ogg", self.length))


def triad(root, kind="maj", octave=4, inv=0):
	steps = {"maj": [0, 4, 7], "min": [0, 3, 7], "sus2": [0, 2, 7], "sus4": [0, 5, 7], "dim": [0, 3, 6],
		"maj7": [0, 4, 7, 11], "min7": [0, 3, 7, 10], "dom7": [0, 4, 7, 10], "add9": [0, 4, 7, 14], "m9": [0, 3, 7, 14]}[kind]
	r = m(root + str(octave))
	notes = [r + s for s in steps]
	for _ in range(inv):
		notes = notes[1:] + [notes[0] + 12]
	return notes


def arpeggio(song, inst, notes, bar, beats_per_note=0.5, vel=0.6, pattern=(0, 1, 2, 3, 2, 1, 0, 1), pan=0.0):
	b = bar * song.beats_per_bar
	count = int(song.beats_per_bar / beats_per_note)
	ext = notes + [n + 12 for n in notes]
	for i in range(count):
		song.play(inst, ext[pattern[i % len(pattern)] % len(ext)], b + i * beats_per_note, beats_per_note * 2, vel * (1.0 if i % 4 == 0 else 0.8), pan)


# --- Tracks --------------------------------------------------------------------------------

def forest(night=False):
	"""The starting forest: harp, warm strings, a lonely flute (LoD's quiet field themes)."""
	bpm = 66 if night else 78
	s = Song(bpm, 32)
	prog = [("F", "maj", 0), ("C", "maj", 1), ("D", "min", 0), ("Bb", "maj", 1), ("F", "maj", 1), ("G", "min", 0), ("C", "sus4", 0), ("C", "maj", 0),
		("D", "min", 0), ("Bb", "maj", 0), ("F", "maj", 0), ("C", "maj", 1), ("D", "min", 0), ("Bb", "maj", 1), ("G", "min", 0), ("A", "maj", 0)] * 2
	bass = ["F2", "E2", "D2", "D2", "A2", "G2", "C2", "C2", "D2", "Bb1", "F2", "E2", "D2", "D2", "G2", "A2"] * 2
	for bar, (root, kind, inv) in enumerate(prog):
		b = bar * 4
		ch = triad(root, kind, 3, inv)
		s.chord("strings", [n + 12 for n in ch], b, 4.0, 0.42 if not night else 0.32, 0.8)
		arpeggio(s, "harp", ch + [ch[0] + 12], bar, 0.5, 0.55 if not night else 0.45, (0, 1, 2, 3, 4, 3, 2, 1), -0.3)
		if not night:
			s.play("pizz", bass[bar], b, 1.5, 0.6, 0.1)
			s.play("pizz", bass[bar], b + 2, 1.0, 0.45, 0.1)
		else:
			s.play("strings", m(bass[bar]), b, 4.0, 0.35, 0.0)
	if not night:
		a = [("A5", 1.5), ("G5", 0.5), ("F5", 1), ("C5", 1), ("E5", 2), ("D5", 1), ("C5", 1), ("D5", 3), ("A4", 1), ("Bb4", 2), ("D5", 2),
			("C5", 1.5), ("A4", 0.5), ("F4", 2), ("G4", 1), ("A4", 1), ("Bb4", 1), ("D5", 1), ("C5", 4), (None, 4)]
		b2 = [("F5", 2), ("E5", 1), ("D5", 1), ("D5", 2), ("C5", 1), ("Bb4", 1), ("A4", 2), ("C5", 2), ("G5", 3), ("F5", 0.5), ("E5", 0.5),
			("F5", 1.5), ("E5", 0.5), ("D5", 2), ("F5", 1), ("Bb5", 1), ("A5", 2), ("G5", 1), ("F5", 1), ("E5", 4), (None, 4)]
		s.melody("flute", 0, a, 0.75, 0.15)
		s.melody("oboe", 32, b2, 0.7, -0.15)
		s.melody("flute", 64, a, 0.7, 0.15)
		s.melody("flute", 96, b2, 0.75, 0.1)
		s.melody("oboe", 96, [(n if n is None else m(n) - 12, d) for n, d in b2], 0.35, -0.2)
	else:
		for bar in range(0, 32, 4):
			s.play("bell", m("C6") if bar % 8 == 0 else m("A5"), bar * 4 + 3, 2, 0.25, 0.4)
	s.render("forest_night" if night else "forest", reverb=0.45 if night else 0.38)


def monolith():
	"""The Monolith: ancient and strange: choir, bells, a slow lydian shimmer."""
	s = Song(58, 16)
	prog = [("E", "maj7"), ("F#", "maj"), ("E", "maj7"), ("C#", "min7"), ("A", "maj7"), ("B", "sus4"), ("E", "add9"), ("F#", "maj")] * 2
	for bar, (root, kind) in enumerate(prog):
		b = bar * 4
		ch = triad(root, kind, 3)
		s.chord("choir_oo" if bar < 8 else "choir", ch, b, 4.0, 0.55, 0.9)
		s.play("strings", ch[0] - 12, b, 4.0, 0.4)
		for i, k in enumerate((0, 2, 1, 3) if len(ch) > 3 else (0, 2, 1, 2)):
			s.play("bell", ch[k] + 24, b + i, 1.5, 0.22 + 0.06 * (i == 0), 0.5 - i * 0.3)
	s.melody("flute", 16, [("B5", 3), ("A#5", 1), ("G#5", 4), ("F#5", 2), ("E5", 2), ("D#5", 4)], 0.55, 0.2)
	s.melody("flute", 48, [("G#5", 3), ("A#5", 1), ("B5", 4), ("C#6", 2), ("B5", 1), ("A#5", 1), ("G#5", 4)], 0.55, 0.2)
	for b in range(0, 64, 8):
		s.play("timpani", "E2", b, 2, 0.3)
	s.render("monolith", reverb=0.6, room=4.0)


def singed_plains(night=False):
	"""The desert: hijaz scale on D (D Eb F# G A Bb C), oud, frame drums, ney-like flute."""
	s = Song(84 if not night else 70, 32)
	for bar in range(32):
		b = bar * 4
		s.play("strings", "D2", b, 4.0, 0.4 if not night else 0.3, -0.2)
		s.play("strings", "A2", b, 4.0, 0.3, 0.2)
		if night:
			continue
		# Drums: doum . tek tek | doum tek . tek
		for beat, kind, v in ((0, "doum", 0.9), (1, "tek", 0.5), (1.5, "tek", 0.4), (2, "doum", 0.7), (2.5, "tek", 0.45), (3.5, "tek", 0.5)):
			s.play("drum", 60 if kind == "doum" else 90, b + beat, 0.5, v, 0.1, 0.006)
		s.play("shaker", 100, b + 0.75, 0.25, 0.4, 0.4)
		s.play("shaker", 100, b + 2.75, 0.25, 0.4, 0.4)
	oud = [("D4", 0.5), ("Eb4", 0.5), ("F#4", 0.5), ("G4", 0.5), ("A4", 1), ("G4", 0.5), ("F#4", 0.5)]
	for bar in range(0, 32, 2):
		if night and bar % 4:
			continue
		s.melody("oud", bar * 4, oud + [("Eb4", 1), ("D4", 1), (None, 2)], 0.55 if not night else 0.35, -0.35)
	a = [("A5", 2), ("Bb5", 1), ("A5", 1), ("G5", 1.5), ("F#5", 0.5), ("Eb5", 1), ("F#5", 2), ("G5", 1), ("A5", 1), ("D5", 4),
		("C6", 1.5), ("Bb5", 0.5), ("A5", 1), ("G5", 1), ("F#5", 1.5), ("G5", 0.5), ("A5", 2), ("G5", 1), ("F#5", 1), ("Eb5", 1), ("D5", 3), (None, 4)]
	if not night:
		s.melody("flute", 16, a, 0.7, 0.2)
		s.melody("flute", 80, a, 0.7, 0.2)
		for bar in range(12, 20):
			s.chord("choir", [m("D4"), m("F#4"), m("A4")] if bar % 2 == 0 else [m("Eb4"), m("G4"), m("Bb4")], bar * 4, 4.0, 0.4)
	else:
		s.melody("flute", 32, a, 0.45, 0.3)
	s.render("singed_plains_night" if night else "singed_plains", reverb=0.35 if not night else 0.5)


def combat():
	"""Battle: driving string ostinato, brass, timpani (LoD's battle energy)."""
	s = Song(152, 32)
	prog = [("E", "min"), ("C", "maj"), ("D", "maj"), ("B", "maj"), ("E", "min"), ("C", "maj"), ("A", "min"), ("B", "maj")] * 4
	for bar, (root, kind) in enumerate(prog):
		b = bar * 4
		ch = triad(root, kind, 3)
		for i in range(16):
			s.play("spiccato", ch[0] if i % 4 in (0, 3) else (ch[2] if i % 4 == 1 else ch[1] + 12), b + i * 0.25, 0.25, 0.55 if i % 4 == 0 else 0.4, -0.3)
		s.play("pizz", ch[0] - 12, b, 1, 0.8)
		s.play("timpani", ch[0] - 24 if ch[0] - 24 > 35 else ch[0] - 12, b, 1, 0.75)
		s.play("timpani", ch[0] - 24 if ch[0] - 24 > 35 else ch[0] - 12, b + 2.5, 1, 0.5)
		if bar % 2 == 1:
			s.chord("brass", [n + 12 for n in ch], b + 3, 1.0, 0.55, 0.5)
		if bar % 8 == 0:
			s.play("cymbal", 0, b, 2, 0.6)
	theme = [("E5", 1.5), ("B4", 0.5), ("E5", 1), ("F#5", 1), ("G5", 2), ("F#5", 1), ("E5", 1), ("D5", 1.5), ("A4", 0.5), ("D5", 1), ("E5", 1), ("F#5", 4),
		("G5", 1.5), ("E5", 0.5), ("G5", 1), ("A5", 1), ("B5", 2), ("A5", 1), ("G5", 1), ("A5", 1.5), ("F#5", 0.5), ("D#5", 2), ("E5", 4)]
	s.melody("brass", 32, theme, 0.75, 0.1)
	s.melody("strings", 32, theme, 0.45, -0.1)
	s.melody("brass", 96, theme, 0.8, 0.1)
	s.melody("flute", 96, [(m(n) + 12 if n else None, d) for n, d in theme], 0.4, 0.3)
	s.render("combat", reverb=0.28, room=2.0)


def boss():
	"""Boss: dark choir, taiko, low brass, bells (C minor)."""
	s = Song(126, 32)
	prog = [("C", "min"), ("Ab", "maj"), ("F", "min"), ("G", "maj"), ("C", "min"), ("Db", "maj"), ("Bb", "min"), ("G", "maj")] * 4
	for bar, (root, kind) in enumerate(prog):
		b = bar * 4
		ch = triad(root, kind, 3)
		s.chord("choir", ch, b, 4.0, 0.6, 0.9)
		s.chord("strings", [n - 12 for n in ch[:2]], b, 4.0, 0.45)
		for beat, v in ((0, 1.0), (0.75, 0.5), (1.5, 0.7), (2, 0.9), (3, 0.6), (3.5, 0.8)):
			s.play("taiko", 70, b + beat, 0.5, v, 0.0, 0.004)
		riff = [(ch[0] - 12, 0.75), (ch[0] - 12, 0.25), (ch[0] - 10, 0.5), (ch[1] - 12, 0.5), (ch[0] - 12, 1), (ch[2] - 24, 1)]
		s.melody("brass", b, riff, 0.6, -0.1)
		if bar % 4 == 3:
			s.play("bell", ch[0] + 24, b + 3, 2, 0.4, 0.4)
		if bar % 8 == 0:
			s.play("cymbal", 1, b - 1 if b else 0, 2, 0.7)
	top = [("G5", 2), ("Ab5", 1), ("G5", 1), ("Eb5", 2), ("D5", 1), ("C5", 1), ("Db5", 3), ("C5", 0.5), ("Bb4", 0.5), ("C5", 4),
		("Eb5", 2), ("F5", 1), ("G5", 1), ("Ab5", 2), ("Bb5", 1), ("Ab5", 1), ("G5", 3), ("F5", 1), ("G5", 4)]
	s.melody("strings", 32, [(m(n) + 12 if n else None, d) for n, d in top], 0.55, 0.2)
	s.melody("brass", 96, top, 0.7, 0.0)
	s.render("boss", reverb=0.32, room=2.6)


TRACKS = {"forest": forest, "forest_night": lambda: forest(True), "monolith": monolith, "singed_plains": singed_plains,
	"singed_night": lambda: singed_plains(True), "combat": combat, "boss": boss}

if __name__ == "__main__":
	wanted = sys.argv[1:] or list(TRACKS)
	for name in wanted:
		TRACKS[name]()
