"""Anime-style face parts for the character creator (original drawings, pixel look).

Eyes  -> assets/characters/eyes/anime_*.png (+ _iris.png masks), 32 x 24, outer corner on
         the right like make_eyes.py; the iris is drawn in greys and tinted by the eye
         colour (mask = white where it's tinted).
Parts -> assets/characters/face/anime_*.png, 64 x 80 face layers like make_face_parts.py.
         Noses and brows are skin / hair multipliers (128 grey = unchanged); mouths and
         some extras are drawn in real colours (appearance.json "tint": "none").

    python3 tools/art/make_anime_face.py
"""
import math, os
from PIL import Image, ImageDraw

HERE = os.path.dirname(__file__)
EYES = os.path.join(HERE, "..", "..", "assets", "characters", "eyes")
FACE = os.path.join(HERE, "..", "..", "assets", "characters", "face")
W, H = 32, 24
S = 8

LINE = (26, 16, 20, 255)
LID_LOW = (92, 52, 50, 255)
WHITE = (248, 244, 238, 255)


# --- Eyes -------------------------------------------------------------------------------

def opening(w, h, top, bot, lift, p=1.0, x0=0.10, x1=0.92, cy=0.58):
	"""Top lid (inner -> outer) and bottom lid (outer -> inner) point lists."""
	tops, bots = [], []
	for i in range(41):
		t = i / 40
		x = (x0 + (x1 - x0) * t) * w
		s = math.sin(math.pi * t) ** p
		tilt = -lift * h * t
		tops.append((x, cy * h - top * h * s + tilt))
		bots.append((x, cy * h + bot * h * s + tilt * 0.4))
	return tops, bots[::-1]


def anime_eye(name, top=0.40, bot=0.26, lift=0.06, p=0.75, iris_w=0.40, iris_h=0.44, pupil="round",
              lash=3.0, flick=True, low_lash=False, highlights=2, star=False, cover=0.0, x1=0.92):
	w, h = W * S, H * S
	tops, bots = opening(w, h, top, bot, lift, p, x1=x1)
	shape = Image.new("L", (w, h), 0)
	ImageDraw.Draw(shape).polygon(tops + bots, fill=255)
	eye = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	ImageDraw.Draw(eye).polygon(tops + bots, fill=WHITE)
	# Iris: a tall oval, darker at the top (shadow of the lid), clipped to the opening.
	cx = w * 0.50
	cy = h * (0.58 - lift * 0.35) + h * 0.02
	rx, ry = iris_w * w * 0.5, iris_h * h
	layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	mask = Image.new("L", (w, h), 0)
	ld = ImageDraw.Draw(layer)
	md = ImageDraw.Draw(mask)
	for k in range(int(ry * 2)):
		y = cy - ry + k
		t = k / (ry * 2)
		g = int(120 + 120 * t)  # dark top -> light bottom
		half = rx * math.sqrt(max(0.0, 1 - ((y - cy) / ry) ** 2))
		ld.line([(cx - half, y), (cx + half, y)], fill=(g, g, g, 255))
	md.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)
	ld.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], outline=(60, 60, 60, 255), width=S)
	# Pupil.
	if pupil == "round":
		pr = rx * 0.48
		ld.ellipse([cx - pr, cy - pr * 1.15, cx + pr, cy + pr * 1.15], fill=(14, 10, 14, 255))
		md.ellipse([cx - pr, cy - pr * 1.15, cx + pr, cy + pr * 1.15], fill=0)
	elif pupil == "slit":
		pw = max(rx * 0.16, S * 1.1)
		ld.ellipse([cx - pw, cy - ry * 0.92, cx + pw, cy + ry * 0.92], fill=(14, 10, 14, 255))
		md.ellipse([cx - pw, cy - ry * 0.92, cx + pw, cy + ry * 0.92], fill=0)
	elif pupil == "small":
		pr = rx * 0.25
		ld.ellipse([cx - pr, cy - pr, cx + pr, cy + pr], fill=(14, 10, 14, 255))
		md.ellipse([cx - pr, cy - pr, cx + pr, cy + pr], fill=0)
	# Highlights.
	spots = [(cx + rx * 0.35, cy - ry * 0.40, rx * 0.30)]
	if highlights > 1:
		spots.append((cx - rx * 0.38, cy + ry * 0.42, rx * 0.16))
	for hx, hy, hr in spots:
		if star:
			pts = []
			for i in range(8):
				a = math.pi * i / 4 - math.pi / 2
				r = hr * (1.5 if i % 2 == 0 else 0.45)
				pts.append((hx + r * math.cos(a), hy + r * math.sin(a)))
			ld.polygon(pts, fill=(255, 255, 255, 255))
			md.polygon(pts, fill=0)
		else:
			ld.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=(255, 255, 255, 255))
			md.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=0)
	# A heavy lid covering the top of the iris (sleepy / cool looks).
	if cover > 0:
		lid_y = min(p[1] for p in tops) + cover * (top + bot) * h
		cut = Image.new("L", (w, h), 255)
		ImageDraw.Draw(cut).rectangle([0, 0, w, lid_y], fill=0)
		shape = Image.composite(shape, Image.new("L", (w, h), 0), cut)
		eye.putalpha(Image.composite(eye.getchannel("A"), Image.new("L", (w, h), 0), cut))
	clipped = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	clipped.paste(layer, (0, 0), Image.composite(layer.getchannel("A"), Image.new("L", (w, h), 0), shape))
	eye = Image.alpha_composite(eye, clipped)
	mask = Image.composite(mask, Image.new("L", (w, h), 0), shape)
	d = ImageDraw.Draw(eye)
	lw = int(lash * S)
	if cover > 0:
		lid_y = min(p[1] for p in tops) + cover * (top + bot) * h
		xs = [p[0] for p in tops if p[1] <= lid_y]
		line = [(min(xs), lid_y), (max(xs), lid_y - lift * h * 0.4)] if xs else tops
		d.line(line, fill=LINE, width=lw)
	else:
		d.line(tops, fill=LINE, width=lw, joint="curve")
	if flick:
		ox, oy = tops[-1]
		d.polygon([(ox - S * 4, oy - S * 1.2), (ox + S * 2.2, oy - S * 3.2), (ox + S * 0.4, oy + S * 1.2)], fill=LINE)
		d.line([(ox - S * 7, oy - S * 2), (ox - S * 2, oy - S * 3.5)], fill=LINE, width=S)
	low = bots[4:-10]
	d.line(low, fill=LINE if low_lash else LID_LOW, width=max(S, lw // 3), joint="curve")
	save_eye(name, eye, mask)


def closed_eye(name, curve=1.0, lash=3.0, happy=True):
	"""Shut eyes: happy ^ arcs (curve > 0) or calm downward arcs with lashes."""
	w, h = W * S, H * S
	eye = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	d = ImageDraw.Draw(eye)
	pts = []
	for i in range(31):
		t = i / 30
		x = (0.14 + 0.74 * t) * w
		y = h * 0.55 - (1 if happy else -1) * curve * h * 0.28 * math.sin(math.pi * t) - 0.05 * h * t
		pts.append((x, y))
	d.line(pts, fill=LINE, width=int(lash * S), joint="curve")
	if not happy:
		for t in (0.55, 0.75, 0.92):
			x, y = pts[int(t * 30)]
			d.line([(x, y), (x + S * 1.5, y + S * 3)], fill=LINE, width=S)
	save_eye(name, eye, Image.new("L", (w, h), 0))


def dot_eye(name, r=0.20):
	w, h = W * S, H * S
	eye = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	d = ImageDraw.Draw(eye)
	cx, cy, rr = w * 0.5, h * 0.55, r * h
	d.ellipse([cx - rr * 0.8, cy - rr, cx + rr * 0.8, cy + rr], fill=(20, 14, 16, 255))
	d.ellipse([cx - rr * 0.1, cy - rr * 0.7, cx + rr * 0.35, cy - rr * 0.2], fill=(255, 255, 255, 255))
	save_eye(name, eye, Image.new("L", (w, h), 0))


def spiral_eye(name):
	w, h = W * S, H * S
	eye = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	d = ImageDraw.Draw(eye)
	cx, cy = w * 0.5, h * 0.55
	pts = []
	for i in range(150):
		a = i * 0.12
		r = 0.3 * S + a * S * 0.4
		pts.append((cx + r * math.cos(a), cy + r * math.sin(a) * 0.9))
	d.line(pts, fill=LINE, width=int(1.6 * S))
	save_eye(name, eye, Image.new("L", (w, h), 0))


def save_eye(name, eye, mask):
	eye = eye.resize((W, H), Image.BOX)
	eye.putalpha(eye.getchannel("A").point(lambda v: 255 if v >= 110 else 0))
	mask = mask.resize((W, H), Image.BOX).point(lambda v: 255 if v >= 120 else 0)
	eye.save(os.path.join(EYES, name + ".png"))
	mask.save(os.path.join(EYES, name + "_iris.png"))


# --- Face layers (64 x 80, see make_face_parts.py for the landmarks) ----------------------

FW, FH = 64, 80
CX, EYE_Y, BROW_Y, NOSE_TIP, MOUTH_Y = 32, 29, 16, 43, 61


def m(v, r=None, g=None):
	if r is None:
		return (int(v * 128), int(v * 128), int(v * 128), 255)
	return (min(255, int(r * 128)), min(255, int(g * 128)), min(255, int(v * 128)), 255)


def layer():
	return Image.new("RGBA", (FW, FH), (0, 0, 0, 0))


def px(im, x, y, c):
	x, y = int(round(x)), int(round(y))
	if 0 <= x < FW and 0 <= y < FH:
		im.putpixel((x, y), c)


def both(im, x, y, c):
	px(im, x, y, c)
	px(im, 2 * CX - 1 - x, y, c)


# Noses (skin multipliers): small marks, as in anime.
def nose_dot():
	im = layer()
	px(im, CX + 1, NOSE_TIP - 1, m(0.66))
	return im


def nose_hook():
	im = layer()
	for y in range(NOSE_TIP - 5, NOSE_TIP):
		px(im, CX + 2, y, m(0.72))
	px(im, CX + 1, NOSE_TIP, m(0.62))
	px(im, CX, NOSE_TIP, m(0.70))
	return im


def nose_shadow():
	im = layer()
	for y in range(NOSE_TIP - 6, NOSE_TIP + 1):
		for x in range(CX + 1, CX + 1 + max(1, (y - NOSE_TIP + 7) // 2)):
			px(im, x, y, m(0.82))
	px(im, CX - 1, NOSE_TIP - 2, m(1.12))
	return im


# Mouths (real colours).
DARK = (110, 34, 40, 255)
INSIDE = (150, 46, 52, 255)
TONGUE = (232, 112, 118, 255)
TOOTH = (250, 246, 240, 255)


def mouth_cat():
	im = layer()  # :3
	for x, y in [(-5, 0), (-4, 1), (-3, 1), (-2, 0), (-1, -1), (0, -1), (1, 0), (2, 1), (3, 1), (4, 0)]:
		px(im, CX + x, MOUTH_Y + y, DARK)
	return im


def mouth_open_smile():
	im = layer()
	for y in range(0, 6):
		half = int(round(5.5 * math.sqrt(max(0.0, 1 - (y / 6) ** 2))))
		for x in range(-half, half):
			c = DARK if x in (-half, half - 1) or y in (0, 5) else (TONGUE if y >= 3 and abs(x + 0.5) < half - 1.5 else INSIDE)
			px(im, CX + x, MOUTH_Y - 1 + y, c)
	return im


def mouth_fang():
	im = mouth_open_smile_small()
	px(im, CX + 2, MOUTH_Y, TOOTH)
	px(im, CX + 2, MOUTH_Y + 1, TOOTH)
	return im


def mouth_open_smile_small():
	im = layer()
	for y in range(0, 4):
		half = int(round(3.6 * math.sqrt(max(0.0, 1 - (y / 4) ** 2))))
		for x in range(-half, half):
			c = DARK if x in (-half, half - 1) or y in (0, 3) else INSIDE
			px(im, CX + x, MOUTH_Y - 1 + y, c)
	return im


def mouth_o():
	im = layer()  # a small round "oh"
	ring = [(-1, -2), (0, -2), (-2, -1), (1, -1), (-2, 0), (1, 0), (-2, 1), (1, 1), (-1, 2), (0, 2)]
	for (x, y) in ring:
		px(im, CX + x, MOUTH_Y + y, DARK)
	for (x, y) in [(-1, -1), (0, -1), (-1, 0), (0, 0), (-1, 1), (0, 1)]:
		px(im, CX + x, MOUTH_Y + y, INSIDE)
	return im


def mouth_tongue():
	im = layer()
	for x in range(-4, 4):
		px(im, CX + x, MOUTH_Y, DARK)
	for (x, y) in [(0, 1), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2), (1, 3)]:
		px(im, CX + x, MOUTH_Y + y, TONGUE)
	px(im, CX + 3, MOUTH_Y + 1, DARK)
	px(im, CX + 2, MOUTH_Y + 3, DARK)
	return im


def mouth_wavy():
	im = layer()
	for x in range(-6, 6):
		px(im, CX + x, MOUTH_Y + (0 if (x // 2) % 2 == 0 else 1), DARK)
	return im


def mouth_small_smile():
	im = layer()
	for x in range(-3, 3):
		px(im, CX + x, MOUTH_Y + (1 if -2 <= x <= 1 else 0), DARK)
	return im


def mouth_shout():
	im = layer()
	for y in range(0, 7):
		half = int(round(1 + y * 0.8))
		for x in range(-half, half):
			c = DARK if x in (-half, half - 1) or y == 6 else (TONGUE if y >= 4 else INSIDE)
			px(im, CX + x, MOUTH_Y - 3 + y, c)
	return im


# Brows (hair multipliers).
def brows_anime(arch=2.0, tilt=0.0, length=9, gap=4, thick=2):
	im = layer()
	for side in (0, 1):
		for i in range(length):
			t = i / (length - 1)
			y = BROW_Y + 3 - arch * math.sin(math.pi * t) + tilt * (1 - t) * 3
			x = CX - 1 - gap - i if side == 0 else CX + gap + i
			for k in range(thick):
				px(im, x, y + k, m(0.75))
	return im


def brows_dots():
	im = layer()  # round "maro" brows
	for side_x in (CX - 13, CX + 10):
		for x in range(side_x, side_x + 4):
			for y in (BROW_Y, BROW_Y + 1):
				px(im, x, y, m(0.7))
	return im


# Extras.
def blush_lines():
	im = layer()
	for k in range(4):
		for j in range(3):
			both(im, 10 + k * 3 + j, 44 - j, (226, 96, 104, 255) if j < 2 else (240, 140, 146, 255))
	return im


def sweat_drop():
	im = layer()
	pts = [(54, 10), (54, 11), (53, 12), (54, 12), (55, 12), (53, 13), (54, 13), (55, 13), (54, 14)]
	for x, y in pts:
		px(im, x, y, (150, 205, 245, 255))
	px(im, 53, 13, (240, 250, 255, 255))
	for x, y in [(54, 9), (52, 12), (56, 12), (52, 13), (56, 13), (53, 14), (55, 14), (54, 15)]:
		px(im, x, y, (60, 110, 170, 255))
	return im


def tears():
	im = layer()
	for side_x in (CX - 13, CX + 12):
		for y in range(EYE_Y + 6, EYE_Y + 14):
			px(im, side_x, y, (150, 205, 245, 255))
		px(im, side_x, EYE_Y + 14, (110, 170, 230, 255))
	return im


def anger_mark():
	im = layer()  # the popping-vein cross on the forehead
	c = (210, 40, 50, 255)
	ox, oy = 48, 3
	for (x, y) in [(2, 0), (2, 1), (0, 2), (1, 2), (5, 0), (5, 1), (6, 2), (7, 2), (0, 5), (1, 5), (2, 6), (2, 7), (6, 5), (7, 5), (5, 6), (5, 7)]:
		px(im, ox + x, oy + y, c)
	return im


def whiskers():
	im = layer()
	for k, dy in enumerate((-2, 0, 2)):
		for i in range(5):
			both(im, 6 + i, 46 + dy - (i * (1 - k)) // 4, m(0.6))
	return im


PARTS = {
	"anime_nose_dot": nose_dot, "anime_nose_hook": nose_hook, "anime_nose_shadow": nose_shadow,
	"anime_mouth_cat": mouth_cat, "anime_mouth_grin": mouth_open_smile, "anime_mouth_fang": mouth_fang,
	"anime_mouth_o": mouth_o, "anime_mouth_tongue": mouth_tongue, "anime_mouth_wavy": mouth_wavy,
	"anime_mouth_smile": mouth_small_smile, "anime_mouth_shout": mouth_shout,
	"anime_brows_soft": lambda: brows_anime(1.8), "anime_brows_high": lambda: brows_anime(2.6, 0, 9, 4, 2),
	"anime_brows_angry": lambda: brows_anime(0.5, 1.4, 9, 3, 2), "anime_brows_sad": lambda: brows_anime(0.6, -1.3, 9, 4, 2),
	"anime_brows_dots": brows_dots,
	"anime_blush": blush_lines, "anime_sweat": sweat_drop, "anime_tears": tears, "anime_anger": anger_mark,
	"anime_whiskers": whiskers,
}

if __name__ == "__main__":
	os.makedirs(EYES, exist_ok=True)
	os.makedirs(FACE, exist_ok=True)
	anime_eye("anime_bright")
	anime_eye("anime_soft", top=0.42, bot=0.30, lift=0.0, p=0.6, iris_h=0.46, flick=False, lash=2.6)
	anime_eye("anime_sharp", top=0.26, bot=0.16, lift=0.12, p=1.1, iris_h=0.40, highlights=1, lash=3.2)
	anime_eye("anime_upturned", top=0.34, bot=0.20, lift=0.20, p=1.0, iris_h=0.42, lash=3.2)
	anime_eye("anime_droopy", top=0.36, bot=0.24, lift=-0.10, p=0.9, iris_h=0.42, flick=False, lash=2.8)
	anime_eye("anime_sleepy", top=0.40, bot=0.26, lift=0.04, cover=0.45, highlights=1, flick=False)
	anime_eye("anime_sparkle", top=0.42, bot=0.30, lift=0.04, p=0.65, iris_h=0.46, star=True)
	anime_eye("anime_small_iris", top=0.38, bot=0.28, lift=0.02, iris_w=0.22, iris_h=0.26, pupil="small", highlights=1, flick=False, lash=2.4)
	anime_eye("cat_slit", top=0.36, bot=0.24, lift=0.14, p=0.9, iris_w=0.48, iris_h=0.44, pupil="slit", highlights=1, lash=3.2)
	anime_eye("cat_slit_round", top=0.44, bot=0.32, lift=0.02, p=0.6, iris_w=0.52, iris_h=0.48, pupil="slit", highlights=1, lash=2.8)
	closed_eye("closed_happy", happy=True)
	closed_eye("closed_calm", happy=False, curve=0.6)
	dot_eye("dot_eyes")
	spiral_eye("dizzy")
	for name, fn in PARTS.items():
		fn().save(os.path.join(FACE, name + ".png"))
	print("Wrote 14 eye styles and %d face parts" % len(PARTS))
