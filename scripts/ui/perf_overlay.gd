class_name PerfOverlay
extends PanelContainer
## F3: what the game is costing right now (made by the HUD, hidden until asked for).
## Frame time is the average and the worst frame of the last second: a steady average
## with a high "worst" is a hiccup. Script and physics are the game's own work per
## frame; the rest of a frame is drawing.

var _label: Label
var _frames := 0
var _sum := 0.0
var _worst := 0.0
var _script := 0.0
var _physics := 0.0
var _left := 0.0
var _last_usec := 0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Left edge, under the player's bars and status icons.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(12.0, 170.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	set_process(false)


func toggle() -> void:
	visible = not visible
	set_process(visible)
	_last_usec = Time.get_ticks_usec()
	_frames = 0
	_sum = 0.0
	_worst = 0.0
	_script = 0.0
	_physics = 0.0
	_left = 0.0


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0
	_last_usec = now
	_frames += 1
	_sum += ms
	_worst = maxf(_worst, ms)
	_script += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_left -= delta
	if _left > 0.0:
		return
	_left = 1.0
	var n := maxf(float(_frames), 1.0)
	var lines := PackedStringArray()
	lines.append("%d fps    frame %.1f ms  (worst %.1f)" % [int(Engine.get_frames_per_second()), _sum / n, _worst])
	lines.append("game logic %.1f ms    physics %.1f ms" % [_script / n, _physics / n])
	lines.append("draw calls %d    objects %d" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
	lines.append("triangles %dk    video memory %d MB" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0), int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)])
	lines.append("nodes %d    physics bodies %d" % [int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))])
	var perf := get_tree().get_first_node_in_group("world_perf")
	if perf:
		lines.append("enemies / NPCs awake %d, asleep %d" % [int(perf.get("awake")), int(perf.get("asleep"))])
	var streamer := get_tree().get_first_node_in_group("chunk_streamer")
	if streamer:
		lines.append("chunks %d (+%d loading)    props waiting %d" % [(streamer.call("get_loaded_cells") as Array).size(), (streamer.get("_pending") as Dictionary).size(), (streamer.get("_prop_queue") as Array).size()])
	var atmos := get_tree().get_first_node_in_group("atmosphere")
	var weather = atmos.get("weather") if atmos else null
	if weather:
		lines.append("weather %s    cover map %s" % [String(weather.get("type_id")), "on" if weather.get("cover") and weather.get("cover").get("active") else "off"])
	var vp := get_viewport()
	lines.append("%s    render scale %d%%    occlusion %s" % [RenderingServer.get_current_rendering_method(), int(round(vp.scaling_3d_scale * 100.0)), "on" if vp.use_occlusion_culling else "off"])
	_label.text = "\n".join(lines)
	_frames = 0
	_sum = 0.0
	_worst = 0.0
	_script = 0.0
	_physics = 0.0
