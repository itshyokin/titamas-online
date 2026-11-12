class_name RegionMap
extends CanvasLayer
## The region map (action "map", M): a top-down picture of the region you're in, drawn
## from the level's terrain chunks (heights, Blender paint, water), with you, home,
## quest givers (! / ?), companions and bosses marked. Mouse wheel zooms, drag pans,
## M / Esc closes. Built once per level the first time it's opened.

const SEA := Color(0.16, 0.3, 0.42)
const WATER := Color(0.25, 0.45, 0.6)
const PAPER := Color(0.08, 0.08, 0.1, 0.92)

static var _cache := {}  # chunk_dir -> {texture, origin: Vector2, metres: float (per pixel), size}

var _panel: PanelContainer
var _view: MapView
var _title: Label
var _open := false


func _ready() -> void:
	layer = 15
	visible = false
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_corner_radius_all(10)
	style.border_color = Color(0.85, 0.75, 0.5, 0.6)
	style.set_border_width_all(2)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.anchor_left = 0.12
	_panel.anchor_right = 0.88
	_panel.anchor_top = 0.08
	_panel.anchor_bottom = 0.92
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.65))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_view = MapView.new()
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_view)
	var legend := Label.new()
	legend.text = "▲ You    ⌂ Home    ! Quest    ? Turn in    ● Companion    ☠ Boss        Wheel: zoom · Drag: pan · M / Esc: close"
	legend.add_theme_font_size_override("font_size", 14)
	legend.modulate = Color(1, 1, 1, 0.75)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(legend)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("map") and (_open or not GameSettings.menu_open):
		toggle()
		get_viewport().set_input_as_handled()
	elif _open and (event.is_action_pressed("menu") or (event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE)):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	_open = not _open
	visible = _open
	GameSettings.menu_open = _open
	if _open:
		_show()


func is_open() -> bool:
	return _open


func _show() -> void:
	var streamer := get_tree().get_first_node_in_group("chunk_streamer")
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if streamer == null or player == null:
		_title.text = "No map for this place"
		_view.map = {}
		return
	var map := build(streamer)
	_view.map = map
	_view.player = player
	# The region you're in (the open sea shows everything).
	var atmo := get_tree().get_first_node_in_group("atmosphere")
	var region: Resource = atmo.call("region_at", player.global_position) if atmo else null
	var cs := float(streamer.get("chunk_size"))
	var title := ""
	var rect := Rect2(map.origin, map.size)
	if region and region.get("chunks") is Rect2i and not (atmo.get("default_atmosphere") == region):
		var c: Rect2i = region.get("chunks")
		rect = Rect2(Vector2(c.position) * cs - Vector2.ONE * cs * 0.5, Vector2(c.size) * cs)
		title = String(region.get("region_name"))
	if title == "":
		title = String(region.get("region_name")) if region else ""
	_title.text = title if title != "" else "Map"
	_view.region = rect
	_view.zoom = 1.0
	_view.pan = Vector2.ZERO
	_view.queue_redraw()


## Builds (once per level) the map picture from every chunk's terrain grid.
static func build(streamer: Node) -> Dictionary:
	var dir := String(streamer.get("chunk_dir"))
	if _cache.has(dir):
		return _cache[dir]
	var cs := float(streamer.get("chunk_size"))
	var spacing := 2.0
	var n := int(streamer.call("_paint_grid_size"))
	var cells := {}  # Vector2i -> path
	var da := DirAccess.open(dir)
	if da:
		for f in da.get_files():
			var file := f.trim_suffix(".remap").trim_suffix(".import")
			if not file.begins_with("chunk_") or not (file.ends_with(".glb") or file.ends_with(".tscn") or file.ends_with(".scn")):
				continue
			var parts := file.get_basename().trim_prefix("chunk_").split("_")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				cells[Vector2i(int(parts[0]), int(parts[1]))] = dir.path_join(file)
	if cells.is_empty():
		return {}
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := -lo
	for c: Vector2i in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	# One pixel per grid point (2 m); a chunk's edge points are shared with its neighbour.
	var per := n - 1
	var w := (hi.x - lo.x + 1) * per + 1
	var h := (hi.y - lo.y + 1) * per + 1
	var height := PackedFloat32Array()
	height.resize(w * h)
	height.fill(-1000.0)
	var paint := PackedVector2Array()
	paint.resize(w * h)
	var water := PackedFloat32Array()
	water.resize(w * h)
	water.fill(-1000.0)
	var fourth := PackedFloat32Array()  # 4th paint layer
	fourth.resize(w * h)
	var ground := PackedByteArray()  # index into ground_ids per pixel
	ground.resize(w * h)
	var ground_ids: Array = [""]
	var half := cs * 0.5
	for c: Vector2i in cells:
		var scene := load(cells[c]) as PackedScene
		if scene == null:
			continue
		var chunk := scene.instantiate() as Node3D
		var grids: Array = streamer.call("_read_terrain", chunk)
		var gid := ChunkStreamer.ground_of(chunk)
		if not gid in ground_ids:
			ground_ids.append(gid)
		var gi := ground_ids.find(gid)
		var p: PackedVector2Array = grids[0]
		var hs: PackedFloat32Array = grids[1]
		var f4: PackedFloat32Array = grids[2] if grids.size() > 2 else PackedFloat32Array()
		var ox := (c.x - lo.x) * per
		var oy := (c.y - lo.y) * per
		for gz in n:
			for gx in n:
				var k := gz * n + gx
				var i := (oy + gz) * w + ox + gx
				if not hs.is_empty():
					height[i] = maxf(height[i], hs[k])
				if not p.is_empty():
					paint[i] = p[k]
				if not f4.is_empty():
					fourth[i] = f4[k]
				ground[i] = gi
		# Lakes and rivers: meshes named *-water, filled across their extent.
		for node in chunk.find_children("*-water", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			var box := mi.transform * mi.mesh.get_aabb()
			var x0 := clampi(int((box.position.x + half) / spacing), 0, n - 1)
			var x1 := clampi(int((box.end.x + half) / spacing) + 1, 0, n - 1)
			var z0 := clampi(int((box.position.z + half) / spacing), 0, n - 1)
			var z1 := clampi(int((box.end.z + half) / spacing) + 1, 0, n - 1)
			for gz in range(z0, z1 + 1):
				for gx in range(x0, x1 + 1):
					var i := (oy + gz) * w + ox + gx
					water[i] = maxf(water[i], box.end.y)
		chunk.free()
	# Colours from the terrain's own textures (grass / dirt / cliff, or a ground set's).
	var palettes := {}  # set id -> [3 colours]
	for id in ground_ids:
		var tex := [Color(0.35, 0.55, 0.25), Color(0.5, 0.4, 0.28), Color(0.5, 0.5, 0.5), Color(0.35, 0.55, 0.25)]
		var texs: Array = GroundSets.textures(id)
		for t in 4:
			var tx = texs[t]
			if tx is Texture2D:
				var img := (tx as Texture2D).get_image()
				if img:
					img = img.duplicate()
					if img.is_compressed():
						img.decompress()
					img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
					tex[t] = img.get_pixel(0, 0)
		palettes[id] = tex
	var sea_level := -5.0
	var image := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var i := y * w + x
			var hh := height[i]
			if hh <= -999.0 or hh < sea_level:
				var depth := clampf((sea_level - maxf(hh, sea_level - 20.0)) / 20.0, 0.0, 1.0)
				image.set_pixel(x, y, SEA.lerp(SEA.darkened(0.35), depth))
				continue
			if water[i] > hh:
				image.set_pixel(x, y, WATER.lerp(WATER.darkened(0.3), clampf((water[i] - hh) / 3.0, 0.0, 1.0)))
				continue
			var pv := paint[i]
			var tex: Array = palettes[ground_ids[ground[i]]]
			var pa := fourth[i]
			var col: Color = tex[0] * maxf(1.0 - pv.x - pv.y - pa, 0.0) + tex[1] * pv.x + tex[2] * pv.y + tex[3] * pa
			# Steep ground reads as cliff; light from the north-west for relief.
			var hx := height[mini(i + 1, y * w + w - 1)] - height[maxi(i - 1, y * w)]
			var hz := height[mini(i + w, w * h - 1)] - height[maxi(i - w, 0)]
			hx = 0.0 if absf(hx) > 500.0 else hx
			hz = 0.0 if absf(hz) > 500.0 else hz
			var slope := Vector2(hx, hz).length() / (spacing * 2.0)
			col = col.lerp(tex[2], clampf((slope - 0.7) * 1.5, 0.0, 0.8))
			var shade := clampf(1.0 - (hx + hz) * 0.12, 0.6, 1.3)
			col = Color(col.r * shade, col.g * shade, col.b * shade)
			image.set_pixel(x, y, col)
	image.resize(w * 3, h * 3, Image.INTERPOLATE_BILINEAR)
	var map := {
		"texture": ImageTexture.create_from_image(image),
		"origin": Vector2(lo.x * cs - half, lo.y * cs - half),
		"size": Vector2((hi.x - lo.x + 1) * cs, (hi.y - lo.y + 1) * cs),
	}
	_cache[dir] = map
	return map


## Draws the map picture and the markers.
class MapView:
	extends Control
	var map := {}
	var region := Rect2()
	var player: Node3D
	var zoom := 1.0
	var pan := Vector2.ZERO
	var _drag := false

	func _ready() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _process(_d: float) -> void:
		if is_visible_in_tree():
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = minf(zoom * 1.2, 6.0)
		elif mb and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = maxf(zoom / 1.2, 1.0)
			if zoom <= 1.0:
				pan = Vector2.ZERO
		elif mb and mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
		elif event is InputEventMouseMotion and _drag:
			pan += (event as InputEventMouseMotion).relative / _scale()

	## Screen pixels per metre.
	func _scale() -> float:
		if region.size.x <= 0.0:
			return 1.0
		return minf(size.x / region.size.x, size.y / region.size.y) * zoom

	## World (x, z) → point on this control.
	func to_view(world: Vector3) -> Vector2:
		var s := _scale()
		var centre := region.get_center() - pan
		return size * 0.5 + (Vector2(world.x, world.z) - centre) * s

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), SEA.darkened(0.3))
		if map.is_empty() or not map.has("texture"):
			return
		var tex: Texture2D = map.texture
		var a := to_view(Vector3(map.origin.x, 0, map.origin.y))
		var b := to_view(Vector3(map.origin.x + map.size.x, 0, map.origin.y + map.size.y))
		draw_texture_rect(tex, Rect2(a, b - a), false)
		# The region's border.
		var ra := to_view(Vector3(region.position.x, 0, region.position.y))
		var rb := to_view(Vector3(region.end.x, 0, region.end.y))
		draw_rect(Rect2(ra, rb - ra), Color(1.0, 0.9, 0.6, 0.5), false, 2.0)
		var font := ThemeDB.fallback_font
		var marks: Array = []  # [world, text, colour, size, label]
		var tree := get_tree()
		for m in tree.get_nodes_in_group("quest_markers"):
			var l := m as Label3D
			if l and l.visible and l.text != "":
				marks.append([l.global_position, l.text, Color(1.0, 0.85, 0.25), 22, ""])
		var session := tree.root.get_node_or_null("GameSession")
		if session and session.call("active"):
			var home: Dictionary = session.get("data").get("home", {})
			var scene := tree.current_scene
			if not home.is_empty() and scene and String(home.get("scene", "")) == scene.scene_file_path:
				var p: Array = home.get("position", [])
				if p.size() == 3:
					marks.append([Vector3(p[0], p[1], p[2]), "⌂", Color(0.6, 0.85, 1.0), 22, String(home.get("name", "Home"))])
		for f in tree.get_nodes_in_group("followers"):
			var st := Combat.stats_of(f)
			marks.append([(f as Node3D).global_position, "●", Color(0.45, 1.0, 0.5), 14, st.display_name if st else ""])
		for n in tree.get_nodes_in_group(Combat.GROUP):
			var id = n.get("enemy_id")
			if id != null and Combat.is_alive(n) and bool(Database.enemy(String(id)).get("boss", false)):
				var st := Combat.stats_of(n)
				marks.append([(n as Node3D).global_position, "☠", Color(1.0, 0.4, 0.35), 22, st.display_name if st else ""])
		for mk: Array in marks:
			var at := to_view(mk[0])
			var text: String = mk[1]
			var fs: int = mk[3]
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pos := at + Vector2(-tw * 0.5, fs * 0.35)
			draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
			draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, mk[2])
			var label: String = mk[4]
			if label != "":
				var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
				var lp := at + Vector2(-lw * 0.5, fs * 0.35 + 15)
				draw_string_outline(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
				draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9))
		# You: an arrow pointing the way you face.
		if player and is_instance_valid(player):
			var at := to_view(player.global_position)
			var model := player.get_node_or_null("Model") as Node3D
			var fwd := -(model.global_basis.z if model else player.global_basis.z)
			var dir := Vector2(fwd.x, fwd.z).normalized()
			if dir.length() < 0.1:
				dir = Vector2.UP
			var side := Vector2(-dir.y, dir.x)
			var pts := PackedVector2Array([at + dir * 13.0, at - dir * 8.0 + side * 8.0, at - dir * 4.0, at - dir * 8.0 - side * 8.0])
			draw_colored_polygon(pts, Color(1.0, 0.95, 0.4))
			pts.append(pts[0])
			draw_polyline(pts, Color(0, 0, 0, 0.9), 2.0)
