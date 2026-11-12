extends SceneTree
## Saves the icons that are drawn in code as pictures, so they can be drawn over:
##   assets/icons/abilities/<ability id>.png   (every ability in abilities.json)
##   assets/icons/statuses/<glyph>.png         (every glyph statuses.json uses, white)
##   assets/icons/custom/glyph_<name>.png      (items still using an old glyph name; the
##                                              items' "icon" is pointed at the picture)
## At player.json hud.icon_pixels (24), stepped like the in-game pixel icons. Existing
## pictures are left alone unless OVERWRITE=1.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/godot/export_icons.gd
## (needs a renderer, so not --headless). Then: python3 tools/art/sheets.py make

var _frames := 0
var _jobs: Array = []  # [path, Control]
var _vp: SubViewport
var _px := 24


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_start()
	elif _frames == 6:
		_save()
		quit()
	return false


func _start() -> void:
	var db := root.get_node("Database")
	_px = int((db.get("player") as Dictionary).get("hud", {}).get("icon_pixels", 24))
	if _px <= 0:
		_px = 24
	var overwrite := OS.get_environment("OVERWRITE") == "1"
	var ability_script = load("res://scripts/ui/ability_icon.gd")
	var item_script = load("res://scripts/ui/item_icon.gd")
	var status_script = load("res://scripts/ui/status_icons.gd")
	for id in db.get("abilities").keys():
		var path := "res://assets/icons/abilities/%s.png" % id
		if overwrite or not FileAccess.file_exists(path):
			var c: Control = ability_script.new()
			c.set("raw", true)
			c.set("ability", db.call("ability", id))
			_jobs.append([path, c])
	var glyphs := {}
	for st in db.get("statuses").values():
		var g := String((st as Dictionary).get("icon", ""))
		if g != "":
			glyphs[g] = true
	for g in glyphs:
		var path := "res://assets/icons/statuses/%s.png" % g
		if overwrite or not FileAccess.file_exists(path):
			var c = status_script.StatusIcon.new()
			c.raw = true
			c.glyph = g
			_jobs.append([path, c])
	# Items with an old glyph name: one picture per glyph + colour.
	var items_file := "res://data/items.json"
	var data = JSON.parse_string(FileAccess.get_file_as_string(items_file))
	var changed := false
	var list: Array = data.get("items", []) if data is Dictionary else data
	for it in list:
		var icon := String(it.get("icon", ""))
		if icon == "" or icon.begins_with("builtin:") or icon.begins_with("res://"):
			continue
		var col := String(it.get("icon_color", "#ffffff")).trim_prefix("#")
		var path := "res://assets/icons/custom/glyph_%s_%s.png" % [icon, col]
		if overwrite or not FileAccess.file_exists(path):
			var c: Control = item_script.new()
			c.set("raw", true)
			c.set("icon", icon)
			c.set("color", Color.html(col))
			_jobs.append([path, c])
		it["icon"] = path
		changed = true
	if changed:
		var f := FileAccess.open(items_file, FileAccess.WRITE)
		f.store_string(JSON.stringify(data, "\t", false) + "\n")
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.size = Vector2i(maxi(_px * _jobs.size(), 1), _px)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(_vp)
	for i in _jobs.size():
		var c: Control = _jobs[i][1]
		c.position = Vector2(i * _px, 0)
		c.size = Vector2(_px, _px)
		_vp.add_child(c)


func _save() -> void:
	if _jobs.is_empty():
		print("export_icons: nothing to export")
		return
	var img := _vp.get_texture().get_image()
	var step = load("res://scripts/combat/pixel_art.gd")
	for i in _jobs.size():
		var path: String = _jobs[i][0]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		var cut := img.get_region(Rect2i(i * _px, 0, _px, _px))
		step.call("step_image", cut)
		cut.save_png(ProjectSettings.globalize_path(path))
		print("wrote ", path)
