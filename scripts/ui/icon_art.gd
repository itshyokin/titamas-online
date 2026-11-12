class_name IconArt
## Hand-drawn (or exported) pictures that replace the icons drawn in code:
##   assets/icons/abilities/<ability id>.png   an ability's icon (AbilityIcon)
##   assets/icons/statuses/<glyph>.png         a status glyph (StatusIcons), drawn white:
##                                             the status colour still shows round it
## The first set was exported from the code drawings (tools/godot/export_icons.gd) so they
## look the same; draw over them (art_sheets/, tools/art/sheets.py). Missing = drawn in code.
## Names no autoloads.

const ABILITIES := "res://assets/icons/abilities/"
const STATUSES := "res://assets/icons/statuses/"

static var _cache := {}  # path -> Texture2D or null


static func ability(id: String) -> Texture2D:
	return texture(ABILITIES + id + ".png") if id != "" else null


static func status(glyph: String) -> Texture2D:
	return texture(STATUSES + glyph + ".png") if glyph != "" else null


static func texture(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(path)) == OK:
			tex = ImageTexture.create_from_image(img)
	_cache[path] = tex
	return tex


## Forget loaded pictures (after redrawing them).
static func clear() -> void:
	_cache.clear()
