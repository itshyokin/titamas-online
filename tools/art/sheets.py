"""Sprite sheets for drawing over the game's pictures.

    python3 tools/art/sheets.py make     write art_sheets/<sheet>.png (+ _guide.png, .json)
    python3 tools/art/sheets.py split    write your edited sheets back into the game's files

Each sheet is a grid of equal cells (size in art_sheets/<sheet>.json and in the guide's
title); every picture sits in the top-left of its cell at its real size. Open the sheet in
your editor (Aseprite: File > Import Sprite Sheet, or just set the grid to the cell size),
draw on a layer over the old pictures, flatten, save over the same file, then run `split`.
Only cells you changed are written; a picture stays the same size as before (anything you
draw outside its own w x h in the cell is ignored). The _guide.png is a big copy with grid
lines and names: look at it, don't edit it.

Sheets:
  eyes, eyes_iris   eyes (32 x 24) and their iris masks (white where the eye colour goes)
  brows, noses, mouths, face_extras   face layers (64 x 80; colour = skin/hair multiplier
                    x128, see tools/art/make_face_parts.py; anime_* are drawn as they are)
  effects           ability / weather / insect sprites (white on clear; _N = N frames)
  item_icons        the 16 px item icons
  icons             ability icons, status glyphs (white), Codex tabs and old item glyphs (24 px)
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "art_sheets")


def files(folder, keep=lambda n: True):
	d = os.path.join(ROOT, folder)
	if not os.path.isdir(d):
		return []
	return [os.path.join(folder, f) for f in sorted(os.listdir(d)) if f.endswith(".png") and keep(f[:-4])]


def face(prefixes):
	return lambda n: any(n.startswith(p) for p in prefixes)


FACE = "assets/characters/face"
PARTS = ("brows_", "anime_brows_", "nose_", "anime_nose_", "mouth_", "anime_mouth_")


EYES = "assets/characters/eyes"


def eye_names():
	"""Eyes are the pictures that have a <name>_iris mask (an eye may itself end in _iris)."""
	names = {f[:-4] for f in os.listdir(os.path.join(ROOT, EYES)) if f.endswith(".png")}
	return sorted(n for n in names if n + "_iris" in names)


def sheets():
	eyes = eye_names()
	return {
		"eyes": [os.path.join(EYES, n + ".png") for n in eyes],
		"eyes_iris": [os.path.join(EYES, n + "_iris.png") for n in eyes],
		"brows": files(FACE, face(("brows_", "anime_brows_"))),
		"noses": files(FACE, face(("nose_", "anime_nose_"))),
		"mouths": files(FACE, face(("mouth_", "anime_mouth_"))),
		"face_extras": files(FACE, lambda n: not face(PARTS)(n)),
		"effects": files("assets/effects/builtin"),
		"item_icons": files("assets/icons/items"),
		"icons": files("assets/icons/abilities") + files("assets/icons/statuses") + files("assets/icons/codex") + files("assets/icons/custom", lambda n: n.startswith("glyph_")),
	}


def layout(entries):
	cw = max(e["w"] for e in entries)
	ch = max(e["h"] for e in entries)
	n = len(entries)
	cols = max(1, min(n, 16 if cw <= 32 else 8))
	rows = (n + cols - 1) // cols
	return cw, ch, cols, rows


def make():
	os.makedirs(OUT, exist_ok=True)
	open(os.path.join(OUT, ".gdignore"), "w").close()  # Godot leaves this folder alone
	for name, paths in sheets().items():
		if not paths:
			continue
		entries = []
		for p in paths:
			im = Image.open(os.path.join(ROOT, p)).convert("RGBA")
			entries.append({"name": os.path.basename(p)[:-4], "file": p, "w": im.width, "h": im.height, "img": im})
		cw, ch, cols, rows = layout(entries)
		sheet = Image.new("RGBA", (cw * cols, ch * rows), (0, 0, 0, 0))
		for i, e in enumerate(entries):
			sheet.paste(e["img"], ((i % cols) * cw, (i // cols) * ch))
			e["cell"] = i
		sheet.save(os.path.join(OUT, name + ".png"))
		meta = {"cell_w": cw, "cell_h": ch, "columns": cols, "rows": rows,
			"pictures": [{k: e[k] for k in ("name", "file", "w", "h", "cell")} for e in entries]}
		with open(os.path.join(OUT, name + ".json"), "w") as f:
			json.dump(meta, f, indent="\t")
		_guide(name, sheet, entries, cw, ch, cols, rows)
		print("wrote art_sheets/%s.png  (%d pictures, cells %d x %d, %d columns)" % (name, len(entries), cw, ch, cols))


def _guide(name, sheet, entries, cw, ch, cols, rows):
	scale = max(1, 96 // max(cw, ch)) * 2 if max(cw, ch) < 96 else 1
	band = 14
	gw, gh = cw * scale, ch * scale + band
	guide = Image.new("RGBA", (gw * cols, gh * rows + 22), (38, 38, 46, 255))
	draw = ImageDraw.Draw(guide)
	font = ImageFont.load_default()
	draw.text((4, 4), "%s: cells %d x %d px, %d columns (guide only: edit %s.png)" % (name, cw, ch, cols, name), fill=(230, 230, 230), font=font)
	checker = Image.new("RGBA", (gw, gh - band), (70, 70, 80, 255))
	cd = ImageDraw.Draw(checker)
	step = max(scale * 2, 4)
	for y in range(0, gh - band, step):
		for x in range(0, gw, step):
			if (x // step + y // step) % 2:
				cd.rectangle([x, y, x + step - 1, y + step - 1], fill=(85, 85, 96, 255))
	for i, e in enumerate(entries):
		x, y = (i % cols) * gw, (i // cols) * gh + 22
		guide.paste(checker, (x, y + band))
		cell = sheet.crop(((i % cols) * cw, (i // cols) * ch, (i % cols + 1) * cw, (i // cols + 1) * ch))
		big = cell.resize((gw, gh - band), Image.NEAREST)
		guide.alpha_composite(big, (x, y + band))
		# the picture's own size inside the cell
		draw.rectangle([x, y + band, x + e["w"] * scale - 1, y + band + e["h"] * scale - 1], outline=(255, 210, 90, 255))
		draw.rectangle([x, y, x + gw - 1, y + gh - 1], outline=(20, 20, 24, 255))
		label = e["name"] if len(e["name"]) * 6 < gw else e["name"][: max(gw // 6 - 1, 3)] + "…"
		draw.text((x + 3, y + 1), label, fill=(240, 240, 240), font=font)
	guide.save(os.path.join(OUT, name + "_guide.png"))


def split():
	changed = 0
	for name in sheets():
		meta_path = os.path.join(OUT, name + ".json")
		sheet_path = os.path.join(OUT, name + ".png")
		if not os.path.exists(meta_path) or not os.path.exists(sheet_path):
			continue
		meta = json.load(open(meta_path))
		sheet = Image.open(sheet_path).convert("RGBA")
		cw, ch, cols = meta["cell_w"], meta["cell_h"], meta["columns"]
		for e in meta["pictures"]:
			i = e["cell"]
			x, y = (i % cols) * cw, (i // cols) * ch
			cut = sheet.crop((x, y, x + e["w"], y + e["h"]))
			target = os.path.join(ROOT, e["file"])
			if os.path.exists(target):
				old = Image.open(target).convert("RGBA")
				if old.size == cut.size and old.tobytes() == cut.tobytes():
					continue
			cut.save(target)
			changed += 1
			print("updated", e["file"])
	print("%d picture(s) updated. Godot re-imports them when its window gets focus." % changed)


if __name__ == "__main__":
	what = sys.argv[1] if len(sys.argv) > 1 else ""
	if what == "make":
		make()
	elif what == "split":
		split()
	else:
		print(__doc__)
