"""Face parts for the character creator: noses, mouths, brows and extras (freckles,
wrinkles, scars...), as pixel-art layers laid over the whole face.

Every picture is 64 x 80 px and covers the same face area (appearance.json
"face_area": centre height, width, tall), seen from the FRONT (the character's right is
on the left of the picture). The game stacks the chosen layers into one picture and lays
it on the face like the eyes (CharacterModel._build_face).

Colours are MULTIPLIERS, not colours: 128 grey = the skin (or hair) as it is, darker
shades it, lighter lightens it (x2 at 255). So one drawing works on every skin tone.
Brows use the hair colour the same way (appearance.json lists them with "tint": "hair").
Transparent pixels leave the face alone.

    python3 tools/art/make_face_parts.py

Draw your own at the same size (start from one of these) and add an entry to
appearance.json "noses" / "mouths" / "brows" / "face_extras": {id, name, texture}.
"""
import os, random
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "characters", "face")
W, H = 64, 80

# Landmarks (px) for the default face area (centre y 1.70 m, 0.15 m wide, 0.20 m tall).
CX = 32           # middle of the face
EYE_Y = 29        # eye line
EYE_DX = 15       # eye centres at CX +- EYE_DX
BROW_Y = 16
NOSE_TOP, NOSE_TIP = 26, 43
MOUTH_Y = 61
CHIN_Y = 71


def m(v, r=None, g=None):
	"""A multiplier colour: v (or r, g, v as blue) x 128, fully opaque."""
	if r is None:
		return (int(v * 128), int(v * 128), int(v * 128), 255)
	return (min(255, int(r * 128)), min(255, int(g * 128)), min(255, int(v * 128)), 255)


SHADE = m(0.80)          # soft shadow
DARK = m(0.62)           # crease / line
LIP_LINE = m(0.55, 0.62, 0.55)
LIP = m(0.88, 1.12, 0.86)  # reddish
LIP_HI = m(1.0, 1.22, 0.98)
HIGHLIGHT = m(1.12)
FRECKLE = m(0.70, 0.84, 0.72)
SCAR = m(1.12, 1.30, 1.10)
SCAR_EDGE = m(0.78, 0.86, 0.78)
BLUSH = m(0.92, 1.16, 0.94)
BROW = m(0.85)
BROW_DARK = m(0.70)


def new():
	return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def px(im, x, y, c):
	if 0 <= x < W and 0 <= y < H:
		im.putpixel((int(x), int(y)), c)


def both(im, x, y, c):
	"""A pixel and its mirror across the middle of the face."""
	px(im, x, y, c)
	px(im, 2 * CX - 1 - x, y, c)


def hline(im, x0, x1, y, c):
	for x in range(x0, x1 + 1):
		px(im, x, y, c)


# --- Noses ---------------------------------------------------------------------------------

def nose_straight():
	im = new()
	for y in range(NOSE_TOP + 4, NOSE_TIP - 1):
		px(im, CX + 2, y, SHADE)  # shadow down one side of the ridge
	for y in range(NOSE_TOP + 6, NOSE_TIP - 2):
		px(im, CX - 1, y, HIGHLIGHT)
	hline(im, CX - 3, CX + 2, NOSE_TIP + 1, SHADE)
	both(im, CX - 4, NOSE_TIP, DARK)  # nostrils
	both(im, CX - 3, NOSE_TIP, DARK)
	return im


def nose_button():
	im = new()
	for y in range(NOSE_TIP - 5, NOSE_TIP - 1):
		px(im, CX + 2, y, SHADE)
	px(im, CX - 1, NOSE_TIP - 3, HIGHLIGHT)
	px(im, CX, NOSE_TIP - 3, HIGHLIGHT)
	hline(im, CX - 2, CX + 1, NOSE_TIP, SHADE)
	both(im, CX - 3, NOSE_TIP - 1, DARK)
	return im


def nose_hooked():
	im = new()
	for y in range(NOSE_TOP + 3, NOSE_TIP - 1):
		bump = 1 if NOSE_TOP + 8 <= y <= NOSE_TOP + 11 else 0
		px(im, CX + 2 + bump, y, SHADE)
	px(im, CX - 1, NOSE_TOP + 9, HIGHLIGHT)
	px(im, CX - 1, NOSE_TOP + 10, HIGHLIGHT)
	hline(im, CX - 3, CX + 2, NOSE_TIP + 1, DARK)
	both(im, CX - 4, NOSE_TIP, DARK)
	return im


def nose_broad():
	im = new()
	for y in range(NOSE_TOP + 6, NOSE_TIP - 1):
		px(im, CX + 3, y, SHADE)
		px(im, CX - 4, y, SHADE)
	hline(im, CX - 5, CX + 4, NOSE_TIP + 1, SHADE)
	for dx in (6, 5):
		both(im, CX - dx, NOSE_TIP, DARK)
	both(im, CX - 6, NOSE_TIP - 1, SHADE)
	return im


def nose_pointed():
	im = new()
	for y in range(NOSE_TOP + 2, NOSE_TIP):
		px(im, CX + 1, y, SHADE)
	px(im, CX, NOSE_TIP, SHADE)
	px(im, CX - 1, NOSE_TIP - 4, HIGHLIGHT)
	both(im, CX - 3, NOSE_TIP + 1, DARK)
	return im


# --- Mouths --------------------------------------------------------------------------------

def mouth(curve=0, width=7, upper=1, lower=1, smirk=False):
	"""curve > 0 smiles (corners up), < 0 frowns; upper/lower = lip thickness in px."""
	im = new()
	for x in range(CX - width, CX + width):
		t = abs((x + 0.5) - CX) / width  # 0 middle .. 1 corner
		lift = curve * t * t
		if smirk and x < CX:
			lift *= 0.2
		y = round(MOUTH_Y - lift)
		px(im, x, y, LIP_LINE)
		for k in range(1, upper + 1):
			if t < 0.85:
				px(im, x, y - k, LIP)
		for k in range(1, lower + 1):
			if t < 0.75:
				px(im, x, y + k, LIP_HI if k == 1 and t < 0.4 else LIP)
	if lower:
		hline(im, CX - 2, CX + 1, MOUTH_Y + lower + 1 - (0 if curve >= 0 else 0), SHADE)  # under the lower lip
	return im


INNER = m(0.28, 0.36, 0.30)
TEETH = m(1.7)


def open_mouth(width, depth, curve=0.0, teeth=False):
	"""An open mouth (talking frames, surprise): dark inside between the lips."""
	im = new()
	top = MOUTH_Y - depth // 2
	bot = top + depth
	for x in range(CX - width, CX + width):
		t = abs((x + 0.5) - CX) / width
		lift = curve * t * t
		y0 = round(top - lift + t * t * depth * 0.35)
		y1 = round(bot - lift - t * t * depth * 0.45)
		if y1 < y0:
			y0 = y1 = round((y0 + y1) / 2)
		px(im, x, y0 - 1, LIP)
		for y in range(y0, y1 + 1):
			px(im, x, y, TEETH if teeth and y == y0 and t < 0.6 else INNER)
		px(im, x, y1 + 1, LIP_HI if t < 0.4 else LIP)
	hline(im, CX - 2, CX + 1, bot + 2, SHADE)
	return im


# --- Brows (tinted with the hair colour) ---------------------------------------------------

def brows(thick=1, arch=1.5, tilt=0.0, gap=3, length=11):
	im = new()
	for side in (0, 1):
		for i in range(length):
			t = i / (length - 1)  # 0 inner .. 1 outer
			y = BROW_Y - arch * (1 - (2 * t - 1) ** 2) + tilt * (1 - t) * 3
			x_off = gap + i
			x = CX - 1 - x_off if side == 0 else CX + x_off
			for k in range(thick):
				px(im, x, round(y) + k, BROW_DARK if k == 0 and t < 0.7 else BROW)
	return im


# --- Extras --------------------------------------------------------------------------------

def freckles():
	im = new()
	rnd = random.Random(7)
	for _ in range(26):
		x = rnd.randint(9, 24)
		y = rnd.randint(36, 48)
		px(im, x, y, FRECKLE)
		px(im, 2 * CX - 1 - x + rnd.randint(-1, 1), y + rnd.randint(-1, 1), FRECKLE)
	for _ in range(6):  # over the nose
		px(im, CX + rnd.randint(-4, 3), rnd.randint(34, 39), FRECKLE)
	return im


def wrinkles():
	im = new()
	for y, a, b in ((6, 20, 43), (9, 22, 41)):  # forehead
		for x in range(a, b + 1):
			if (x * 7 + y) % 9:
				px(im, x, y + (1 if CX - 4 < x < CX + 3 else 0), SHADE)
	for k in range(3):  # crow's feet
		both(im, 3 + k, EYE_Y - 2 + k * 2 - k // 2, SHADE)
		both(im, 4 + k, EYE_Y - 1 + k * 2 - k // 2, SHADE)
	for y in range(NOSE_TIP - 2, MOUTH_Y + 3):  # nose-to-mouth lines
		x = CX - 7 - (y - NOSE_TIP + 2) // 4
		both(im, x, y, SHADE)
	both(im, CX - 11, EYE_Y + 6, SHADE)  # under the eyes
	both(im, CX - 10, EYE_Y + 7, SHADE)
	return im


def scar_eye():
	"""A scar down through the character's left eye (right side of the picture)."""
	im = new()
	x0 = CX + EYE_DX + 1
	for y in range(EYE_Y - 13, EYE_Y + 14):
		x = x0 + (y - EYE_Y) // 6
		px(im, x, y, SCAR)
		px(im, x + 1, y, SCAR_EDGE)
		if (y % 5) == 0:
			px(im, x - 1, y, SCAR_EDGE)
			px(im, x + 2, y, SCAR_EDGE)
	return im


def scar_cheek():
	"""A slash across the character's right cheek (left side of the picture)."""
	im = new()
	for i in range(16):
		x = 10 + i
		y = 52 - i * 0.55
		px(im, x, round(y), SCAR)
		px(im, x, round(y) + 1, SCAR_EDGE)
		if i % 4 == 1:
			px(im, x, round(y) - 2, SCAR_EDGE)
			px(im, x, round(y) + 2, SCAR_EDGE)
	return im


def scar_lip():
	im = new()
	for y in range(MOUTH_Y - 6, MOUTH_Y + 4):
		px(im, CX + 4, y, SCAR)
		px(im, CX + 5, y, SCAR_EDGE)
	return im


def blush():
	im = new()
	for y in range(40, 47):
		for x in range(8, 19):
			d = ((x - 13) / 5.5) ** 2 + ((y - 43) / 3.2) ** 2
			if d < 1.0 and (x + y) % 2 == 0 or d < 0.45:
				both(im, x, y, BLUSH)
	return im


def tired_eyes():
	im = new()
	for side_x in (CX - EYE_DX, CX + EYE_DX - 1):
		for dx in range(-6, 6):
			x = side_x + dx
			px(im, x, EYE_Y + 7 + (1 if abs(dx) > 4 else 0), SHADE)
		for dx in range(-4, 4):
			px(im, side_x + dx, EYE_Y + 8, m(0.88, 0.92, 0.95))
	return im


def beauty_mark():
	im = new()
	px(im, CX + 9, MOUTH_Y - 4, m(0.45))
	return im


def chin_dimple():
	im = new()
	px(im, CX, CHIN_Y - 2, SHADE)
	px(im, CX - 1, CHIN_Y - 1, SHADE)
	px(im, CX, CHIN_Y - 1, DARK)
	return im


def stubble_shadow():
	"""A five o'clock shadow over the jaw and upper lip."""
	im = new()
	rnd = random.Random(3)
	for y in range(MOUTH_Y - 6, H - 4):
		for x in range(6, W - 6):
			jaw = y > MOUTH_Y + 1 or abs(x + 0.5 - CX) > 9 and y > NOSE_TIP + 6 or MOUTH_Y - 5 <= y <= MOUTH_Y - 2 and abs(x + 0.5 - CX) < 8
			if jaw and rnd.random() < 0.55:
				px(im, x, y, m(0.84, 0.86, 0.86))
	return im


PARTS = {
	"nose_straight": nose_straight, "nose_button": nose_button, "nose_hooked": nose_hooked,
	"nose_broad": nose_broad, "nose_pointed": nose_pointed,
	"mouth_neutral": lambda: mouth(0, 7, 1, 1), "mouth_smile": lambda: mouth(2.2, 7, 1, 1),
	"mouth_frown": lambda: mouth(-1.6, 7, 1, 1), "mouth_full": lambda: mouth(0.4, 7, 2, 2),
	"mouth_thin": lambda: mouth(0, 6, 0, 0), "mouth_smirk": lambda: mouth(2.0, 7, 1, 1, smirk=True),
	"mouth_wide": lambda: mouth(1.0, 9, 1, 1),
	"mouth_talk_small": lambda: open_mouth(5, 2), "mouth_talk_wide": lambda: open_mouth(6, 4, teeth=True),
	"mouth_open_wide": lambda: open_mouth(6, 6, teeth=True),
	"brows_natural": lambda: brows(2, 1.2, 0.0), "brows_thin": lambda: brows(1, 1.6, 0.0),
	"brows_thick": lambda: brows(3, 0.8, 0.0, 2, 12), "brows_arched": lambda: brows(2, 2.6, 0.0),
	"brows_angry": lambda: brows(2, 0.4, 1.2), "brows_worried": lambda: brows(2, 0.8, -1.0),
	"freckles": freckles, "wrinkles": wrinkles, "scar_eye": scar_eye, "scar_cheek": scar_cheek,
	"scar_lip": scar_lip, "blush": blush, "tired_eyes": tired_eyes, "beauty_mark": beauty_mark,
	"chin_dimple": chin_dimple, "stubble_shadow": stubble_shadow,
}

if __name__ == "__main__":
	os.makedirs(OUT, exist_ok=True)
	for name, fn in PARTS.items():
		fn().save(os.path.join(OUT, name + ".png"))
	print("Wrote %d face parts to %s" % (len(PARTS), os.path.normpath(OUT)))
