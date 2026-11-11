class_name Compass
extends Control
## Skyrim-style compass strip across the top of the screen: N / NE / E... and ticks
## turning with the camera, plus markers: quest givers (! / ?), home (⌂) and enemies
## fighting you (red). North is -Z. Settings: player.json hud.compass (Database →
## Player → HUD). Built by the HUD.

const HEIGHT := 34.0
const SPAN := 200.0  # degrees shown across the strip

const LETTERS := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_TOP)


func _cfg() -> Dictionary:
	var h = Database.player.get("hud", {})
	var c = h.get("compass", {}) if h is Dictionary else {}
	return c if c is Dictionary else {}


func _process(_delta: float) -> void:
	var cfg := _cfg()
	visible = bool(cfg.get("enabled", true)) and get_viewport().get_camera_3d() != null
	if not visible:
		return
	var w := get_viewport_rect().size.x * float(cfg.get("width", 0.4))
	size = Vector2(w, HEIGHT)
	position = Vector2((get_viewport_rect().size.x - w) * 0.5, 8.0)
	queue_redraw()


## Compass bearing (degrees, 0 = north / -Z, 90 = east / +X) of a flat direction.
static func bearing(dir: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(dir.x, -dir.z)), 360.0)


func _x_of(b: float, heading: float) -> float:
	var d := wrapf(b - heading, -180.0, 180.0)
	return size.x * 0.5 + d / (SPAN * 0.5) * size.x * 0.5


func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var font := ThemeDB.fallback_font
	var fwd := -cam.global_basis.z
	var heading := bearing(Vector3(fwd.x, 0, fwd.z))
	var mid := HEIGHT * 0.5
	# The band: dark in the middle, fading out at both ends.
	var steps := 24
	for i in steps:
		var x0 := size.x * i / steps
		var x1 := size.x * (i + 1) / steps
		var k := 1.0 - absf((i + 0.5) / steps * 2.0 - 1.0)
		draw_rect(Rect2(x0, mid - 9, x1 - x0, 18), Color(0, 0, 0, 0.45 * smoothstep(0.0, 0.5, k)))
	draw_line(Vector2(size.x * 0.08, mid + 9), Vector2(size.x * 0.92, mid + 9), Color(1, 1, 1, 0.25), 1.0)
	# Ticks and letters.
	for b in range(0, 360, 15):
		var x := _x_of(b, heading)
		if x < 0.0 or x > size.x:
			continue
		var fade := 1.0 - absf(x / size.x * 2.0 - 1.0)
		var a := smoothstep(0.0, 0.35, fade)
		if LETTERS.has(b):
			var text: String = LETTERS[b]
			var fs := 18 if text.length() == 1 else 13
			var col := Color(1.0, 0.86, 0.5, a) if text == "N" else Color(1, 1, 1, a * 0.95)
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			draw_string_outline(font, Vector2(x - tw * 0.5, mid + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, a * 0.8))
			draw_string(font, Vector2(x - tw * 0.5, mid + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		else:
			draw_line(Vector2(x, mid - 4), Vector2(x, mid + 4), Color(1, 1, 1, a * 0.5), 1.0)
	_draw_markers(heading, font)
	# Centre notch.
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.5 - 5, 0), Vector2(size.x * 0.5 + 5, 0), Vector2(size.x * 0.5, 6)]), Color(1, 0.9, 0.6, 0.9))


func _draw_markers(heading: float, font: Font) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var cfg := _cfg()
	var quest_range := float(cfg.get("quest_range", 150.0))
	var enemy_range := float(cfg.get("enemy_range", 40.0))
	var marks: Array = []  # [world pos, text, colour, size]
	for m in get_tree().get_nodes_in_group("quest_markers"):
		var l := m as Label3D
		if l and l.visible and l.text != "" and l.global_position.distance_to(player.global_position) < quest_range:
			marks.append([l.global_position, l.text, Color(1.0, 0.85, 0.25), 18])
	for n in get_tree().get_nodes_in_group(Combat.GROUP):
		var e := n as Node3D
		var st := Combat.stats_of(e)
		if e and st and not st.is_dead() and e.get("target") == player and Combat.is_enemy_of(player, e) \
				and e.global_position.distance_to(player.global_position) < enemy_range:
			marks.append([e.global_position, "●", Color(0.95, 0.25, 0.2), 12])
	# Nav points (event "Nav point" command).
	var nav := get_tree().get_first_node_in_group("hud")
	var markers := nav.get_node_or_null("NavMarkers") if nav else null
	if markers:
		for p: Dictionary in markers.call("points"):
			marks.append([p.position, "◆", p.color, 16])
	var session := get_tree().root.get_node_or_null("GameSession")
	if session and session.call("active"):
		var home: Dictionary = session.get("data").get("home", {})
		var scene := get_tree().current_scene
		if not home.is_empty() and scene and String(home.get("scene", "")) == scene.scene_file_path:
			var p: Array = home.get("position", [])
			if p.size() == 3:
				marks.append([Vector3(p[0], p[1], p[2]), "⌂", Color(0.6, 0.85, 1.0), 16])
	for mk: Array in marks:
		var d: Vector3 = mk[0] - player.global_position
		var x := _x_of(bearing(Vector3(d.x, 0, d.z)), heading)
		if x < 6.0 or x > size.x - 6.0:
			continue
		var text: String = mk[1]
		var fs: int = mk[3]
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		var y := HEIGHT * 0.5 + fs * 0.35
		draw_string_outline(font, Vector2(x - tw * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(x - tw * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, mk[2])
