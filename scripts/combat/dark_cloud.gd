class_name DarkCloud
extends Node3D
## Dark Cloud (abilities.json ground.kind "cloud"): a black cloud on a spot for `seconds`.
## Everyone inside gets `status` (darkness: most attacks miss; enemies only notice what
## bumps into them and stumble about when their target is out of reach). The caster isn't
## blinded unless `blinds_caster`; friends are unless `blinds_allies` is off. When this
## game's player cast it, the bodies inside show as outlines through the cloud, coloured
## like the discs under them (player.json discs: hostile red, neutral grey, friendly green).

const PUFF_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(0.07, 0.05, 0.1, 0.85);
uniform sampler2D puff : filter_nearest;
uniform float fade = 1.0;
void vertex() {
	// Faces the camera, turning slowly on its own.
	float a = TIME * 0.15 + MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z;
	VERTEX.xy = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * VERTEX.xy;
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}
void fragment() {
	vec4 t = texture(puff, UV);
	ALBEDO = color.rgb * (0.7 + 0.3 * t.r);
	ALPHA = t.a * color.a * fade;
}
"""

const XRAY_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.2, 0.2, 1.0);
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = color.rgb;
	ALPHA = clamp(rim * 1.5 + 0.1, 0.0, 1.0) * color.a;
}
"""

var caster: Node3D = null
var radius := 5.0
var seconds := 8.0
var status := "darkness"
var blinds_caster := false
var blinds_allies := true
var outlines := true
var color := Color(0.16, 0.12, 0.22)

var _age := 0.0
var _tick := 0.0
var _puffs: Array[MeshInstance3D] = []
var _mat := ShaderMaterial.new()
var _outlined := {}  # body -> true
static var _puff_texture: Texture2D = null


func _ready() -> void:
	add_to_group("dark_clouds")
	_mat.shader = StatusLook.shader(PUFF_SHADER)
	_mat.set_shader_parameter("puff", _texture())
	_mat.set_shader_parameter("color", Color(color.darkened(0.55), 0.8))
	_mat.set_shader_parameter("fade", 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var count := clampi(int(radius * radius * 1.6), 16, 70)
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A dome: more puffs low down, smaller near the edge.
		var a := randf() * TAU
		var d := sqrt(randf()) * radius * 0.9
		var h := randf_range(0.1, 1.0) * (radius * 0.55 + 1.2) * (1.0 - 0.5 * d / radius)
		mi.position = Vector3(cos(a) * d, h, sin(a) * d)
		mi.scale = Vector3.ONE * randf_range(1.8, 3.2) * (1.0 - 0.35 * d / radius)
		mi.set_meta("drift", Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) * 0.15)
		mi.set_meta("home", mi.position)
		add_child(mi)
		_puffs.append(mi)


func _process(delta: float) -> void:
	_age += delta
	var fade := minf(_age / 0.6, 1.0)
	var leaving := maxf(_age - seconds, 0.0)
	if leaving > 0.0:
		fade = 1.0 - leaving / 1.0
		if fade <= 0.0:
			_clear_outlines()
			queue_free()
			return
	_mat.set_shader_parameter("fade", fade)
	var t := _age
	for i in _puffs.size():
		var mi := _puffs[i]
		var home: Vector3 = mi.get_meta("home")
		var drift: Vector3 = mi.get_meta("drift")
		mi.position = home + Vector3(sin(t * 0.6 + i) * drift.x, sin(t * 0.8 + i * 0.5) * drift.y, cos(t * 0.5 + i) * drift.z) * 4.0
	_tick -= delta
	if _tick <= 0.0 and leaving <= 0.0:
		_tick = 0.25
		_update_inside()
	elif leaving > 0.0 and not _outlined.is_empty():
		_clear_outlines()


func inside(point: Vector3) -> bool:
	var to := point - global_position
	if to.y < -1.5 or to.y > radius * 0.55 + 2.5:
		return false
	to.y = 0.0
	return to.length() <= radius


func _update_inside() -> void:
	var now := {}
	var seen := {}
	for n in get_tree().get_nodes_in_group("combatants") + get_tree().get_nodes_in_group("npcs"):
		var body := n as Node3D
		if body == null or seen.has(body) or not body.is_inside_tree():
			continue
		seen[body] = true
		if not inside(body.global_position):
			continue
		var st := Combat.stats_of(body)
		if st == null or st.is_dead():
			continue
		var ally := caster != null and is_instance_valid(caster) and not Combat.is_enemy_of(caster, body)
		if (body != caster or blinds_caster) and (body == caster or not ally or blinds_allies):
			st.add_status(status, 0.6, caster)
		if outlines and body != caster and _local_caster():
			now[body] = true
	for body in _outlined.keys():
		if not now.has(body):
			if is_instance_valid(body):
				StatusLook.set_layer(body, "xray", null)
			_outlined.erase(body)
	for body in now:
		if not _outlined.has(body):
			var m := ShaderMaterial.new()
			m.shader = StatusLook.shader(XRAY_SHADER)
			m.render_priority = 100
			m.set_shader_parameter("color", _disposition_color(body))
			StatusLook.set_layer(body, "xray", m)
			_outlined[body] = true


func _local_caster() -> bool:
	return caster != null and is_instance_valid(caster) and caster.is_in_group("player")


func _clear_outlines() -> void:
	for body in _outlined:
		if is_instance_valid(body):
			StatusLook.set_layer(body, "xray", null)
	_outlined.clear()


func _exit_tree() -> void:
	_clear_outlines()


## The colour of the disc under it (red hostile / grey neutral / green friendly).
func _disposition_color(body: Node3D) -> Color:
	var cfg: Dictionary = {}
	var db := get_node_or_null("/root/Database")
	if db:
		cfg = (db.get("player") as Dictionary).get("discs", {})
	var mood := "neutral"
	if Combat.is_enemy_of(caster, body):
		mood = "hostile"
	else:
		for c in body.get_children():
			if c.has_method("disposition"):
				mood = String(c.call("disposition"))
				break
		if mood == "neutral" and body.is_in_group("followers"):
			mood = "friendly"
	var fallback := {"hostile": "#d8332a", "neutral": "#9a9a9a", "friendly": "#3fbf4a"}
	return Color.html(String(cfg.get(mood, fallback[mood])))


static func _texture() -> Texture2D:
	if _puff_texture:
		return _puff_texture
	# A lumpy soft blob, 24 px with stepped alpha (the pixel look).
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.18
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var r := p.length() + noise.get_noise_2d(x * 0.75, y * 0.75) * 0.3
			var a := pow(clampf(1.0 - r, 0.0, 1.0), 0.8) * 1.5
			var shade := 0.5 + 0.5 * noise.get_noise_2d(x * 2.0 + 40.0, y * 2.0)
			img.set_pixel(x, y, Color(shade, shade, shade, clampf(a, 0.0, 1.0)))
	PixelArt.step_image(img)
	_puff_texture = ImageTexture.create_from_image(img)
	return _puff_texture
