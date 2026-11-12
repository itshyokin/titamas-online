@tool
class_name Campfire
extends StaticBody3D
## A campfire: a ring of stones, crossed logs, flickering flames, embers, a warm light and
## crackling. It's a checkpoint: using it (Interact) makes it where you come back if you
## fall, and offers a rest of some hours by the fire:
##   rest ≥ rested_hours (6)       health and mana full, ailments cured
##   rest ≥ well_rested_hours (8)  also "Well rested" (more damage and experience) for a while
##   shorter                       still heals, but you're "Tired" (slower, weaker) for a while
## The clock moves on by the hours rested; followers rest too. Settings: player.json "camp"
## (Database → Player → Campfires and falling). Followers sit around it in camp
## (SeatSpot / Npc rest). Names no autoloads (reads them through the tree).

const CRACKLE := "res://assets/audio/ambience/campfire_loop.ogg"
const FLAME_SHADER := "res://assets/materials/campfire_flame.gdshader"

## Shown in the prompt and messages ("Campfire" when empty).
@export var camp_name := "":
	set(value):
		camp_name = value
## At runtime, drops onto the ground under it (once the chunk there has loaded).
@export var snap_to_ground := true
@export var lit := true:
	set(value):
		lit = value
		_apply_lit()

var _light: OmniLight3D
var _flames: Array[MeshInstance3D] = []
var _embers: GPUParticles3D
var _sound: AudioStreamPlayer3D
var _prompt: Label3D
var _t := 0.0
var _pending_hours := 0
var _settled := false


func _ready() -> void:
	add_to_group("campfires")
	add_to_group("talkable")
	if not Engine.is_editor_hint():
		GrassField.clearings.append([Vector2(global_position.x, global_position.z), 1.6])
	collision_layer = 1
	_build()
	_apply_lit()


func display_name() -> String:
	return camp_name if camp_name != "" else "Campfire"


func _settings() -> Dictionary:
	var db := get_tree().root.get_node_or_null("Database") if is_inside_tree() else null
	var p = db.get("player") if db else null
	var d = (p as Dictionary).get("camp", {}) if p is Dictionary else {}
	return d if d is Dictionary else {}


# --- Building ----------------------------------------------------------------------

func _build() -> void:
	for c in get_children():
		if c.has_meta("built"):
			c.free()
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.43, 0.4)
	stone.roughness = 0.95
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf_range(-0.12, 0.12)
		var s := SphereMesh.new()
		s.radius = rng.randf_range(0.13, 0.18)
		s.height = s.radius * 1.3
		s.radial_segments = 7
		s.rings = 4
		_part(s, Vector3(cos(a), 0.06, sin(a)) * Vector3(0.55, 1, 0.55), stone, Vector3(0, a, 0), Vector3(1.0, 0.8, rng.randf_range(0.8, 1.2)))
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.2, 0.12)
	wood.roughness = 0.9
	var char_mat := StandardMaterial3D.new()
	char_mat.albedo_color = Color(0.08, 0.06, 0.05)
	for i in 4:
		var stick := CylinderMesh.new()
		stick.top_radius = 0.06
		stick.bottom_radius = 0.07
		stick.height = 0.75
		stick.radial_segments = 7
		var a := PI * 0.5 * i + 0.4
		_part(stick, Vector3(cos(a) * 0.12, 0.16, sin(a) * 0.12), wood, Vector3(0, -a, deg_to_rad(68)))
	var ash := CylinderMesh.new()
	ash.top_radius = 0.38
	ash.bottom_radius = 0.42
	ash.height = 0.04
	_part(ash, Vector3(0, 0.02, 0), char_mat)
	# Flames: crossed cards.
	_flames.clear()
	var flame_shader := load(FLAME_SHADER) as Shader
	for i in 3:
		var q := QuadMesh.new()
		q.size = Vector2(0.55, 0.85) * (1.0 if i == 0 else 0.8)
		var m := ShaderMaterial.new()
		m.shader = flame_shader
		m.set_shader_parameter("seed", float(i) * 3.7)
		var f := _part(q, Vector3(0, 0.5 if i == 0 else 0.42, 0), m, Vector3(0, PI / 3.0 * i, 0))
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flames.append(f)
	_light = OmniLight3D.new()
	_light.set_meta("built", true)
	_light.light_color = Color(1.0, 0.62, 0.3)
	_light.light_energy = 2.2
	_light.omni_range = 9.0
	_light.omni_attenuation = 1.3
	_light.shadow_enabled = true
	_light.position = Vector3(0, 0.7, 0)
	add_child(_light)
	var shape := CollisionShape3D.new()
	shape.set_meta("built", true)
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.7
	cyl.height = 0.4
	shape.shape = cyl
	shape.position.y = 0.2
	add_child(shape)
	if Engine.is_editor_hint():
		return
	_embers = GPUParticles3D.new()
	_embers.set_meta("built", true)
	_embers.amount = 18
	_embers.lifetime = 1.8
	_embers.position = Vector3(0, 0.4, 0)
	_embers.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3, 4, 3))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 0.4, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.3, 1.0))
	ramp.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	_embers.process_material = pm
	var dot := QuadMesh.new()
	dot.size = Vector2(0.04, 0.04)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.vertex_color_use_as_albedo = true
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dot.material = dm
	_embers.draw_pass_1 = dot
	add_child(_embers)
	if ResourceLoader.exists(CRACKLE):
		_sound = AudioStreamPlayer3D.new()
		_sound.set_meta("built", true)
		_sound.stream = load(CRACKLE)
		_sound.bus = &"Ambience"
		_sound.volume_db = -6.0
		_sound.max_distance = 22.0
		_sound.unit_size = 3.0
		_sound.position.y = 0.4
		add_child(_sound)
	_prompt = Label3D.new()
	_prompt.set_meta("built", true)
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.pixel_size = 0.003
	_prompt.font_size = 36
	_prompt.outline_size = 10
	_prompt.no_depth_test = true
	_prompt.position = Vector3.UP * 1.4
	_prompt.visible = false
	add_child(_prompt)


func _part(mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.set_meta("built", true)
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	add_child(mi)
	return mi


func _apply_lit() -> void:
	for f in _flames:
		if is_instance_valid(f):
			f.visible = lit
	if _light:
		_light.visible = lit
	if _embers:
		_embers.emitting = lit
	if _sound:
		if lit and is_inside_tree() and not _sound.playing:
			_sound.play()
		elif not lit:
			_sound.stop()


func _physics_process(_delta: float) -> void:
	if _settled or Engine.is_editor_hint() or not snap_to_ground:
		return
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 20.0, global_position + Vector3.DOWN * 60.0, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_settled = true
		global_position = hit.position


func _process(delta: float) -> void:
	_t += delta
	if _light and lit:
		_light.light_energy = 2.0 + sin(_t * 9.0) * 0.18 + sin(_t * 23.0 + 1.3) * 0.12
	if Engine.is_editor_hint() or _prompt == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var show: bool = player != null and player.get("talk_focus") == self
	_prompt.visible = show
	if show:
		_prompt.text = "%s  ·  Rest" % display_name()


# --- Using it ------------------------------------------------------------------------

func can_talk() -> bool:
	if Engine.is_editor_hint() or not is_visible_in_tree():
		return false
	var box = load("res://scripts/ui/dialogue_box.gd")
	return not bool(box.get("is_open")) and Time.get_ticks_msec() - int(box.get("closed_at")) > 300


func talk_distance(from: Vector3) -> float:
	var to := global_position - from
	to.y = 0.0
	return maxf(to.length() - 0.7, 0.0)


func talk(player: Node3D) -> void:
	if not can_talk():
		return
	var cfg := _settings()
	_mark_checkpoint(player)
	if player.has_method("face_toward"):
		player.call("face_toward", global_position)
	var options: Array = cfg.get("rest_hours", [2, 4, 6, 8])
	var choices: Array = []
	for h in options:
		var hours := int(h)
		choices.append(["Rest %d hour%s" % [hours, "" if hours == 1 else "s"], func() -> String:
			_pending_hours = hours
			return ""])
	choices.append(["Not now", func() -> String: return ""])
	_pending_hours = 0
	var box = load("res://scripts/ui/dialogue_box.gd")
	box.call("open", self, "", display_name(), [String(cfg.get("rest_text", "The fire crackles. Rest a while?"))],
		func() -> void:
			if _pending_hours > 0:
				rest(player, _pending_hours), choices)


## Where you come back if you fall: this fire (saved as GameSession.data "camp").
func _mark_checkpoint(player: Node3D) -> void:
	var session := get_tree().root.get_node_or_null("GameSession")
	var scene := get_tree().current_scene
	var spot := global_position + global_basis.z * 1.6
	var entry := {"scene": scene.scene_file_path if scene else "", "position": [spot.x, spot.y + 0.2, spot.z], "name": display_name()}
	var first := true
	if session and bool(session.call("active")):
		var d: Dictionary = session.get("data")
		var old: Dictionary = d.get("camp", {})
		first = old.get("position", []) != entry.position or old.get("scene", "") != entry.scene
		d["camp"] = entry
	else:
		player.set_meta("camp", entry)
	if first:
		var log_class = load("res://scripts/ui/game_log.gd")
		log_class.call("post", "%s: if you fall, you'll wake here." % display_name(), Color(1.0, 0.75, 0.45))


## Rests `hours` by the fire: fade, the clock moves on, the party recovers, then the
## rested / well rested / tired status.
func rest(player: Node3D, hours: int) -> void:
	var cfg := _settings()
	var fade = load("res://scripts/ui/screen_fade.gd")
	var out := float(cfg.get("fade_out", 0.9))
	fade.call("to_black", self, out, Color.BLACK)
	var menu := get_tree().root.get_node_or_null("GameSettings")
	if menu:
		menu.set("menu_open", true)
	await get_tree().create_timer(out + 0.2).timeout
	var cycle := get_tree().get_first_node_in_group("world_cycle")
	var game_hour := 60.0
	if cycle:
		var h := float(cycle.get("hour")) + hours
		var day := int(cycle.get("day"))
		while h >= 24.0:
			h -= 24.0
			day += 1
		cycle.set("hour", h)
		cycle.set("day", day)
		game_hour = float(cycle.get("day_length_minutes")) * 60.0 / 24.0
	var rested_at := int(cfg.get("rested_hours", 6))
	var well_at := int(cfg.get("well_rested_hours", 8))
	var buff_seconds := float(cfg.get("buff_hours", 1.0)) * game_hour
	var party: Array = [player] + get_tree().get_nodes_in_group("followers")
	for who in party:
		var st = who.get_node_or_null("Stats")
		if st == null:
			continue
		st.call("restore")
		for id in [String(cfg.get("tired_status", "tired")), String(cfg.get("well_rested_status", "well_rested"))]:
			st.call("remove_status", id)
		if hours >= rested_at:
			st.call("cure_all")
		if who == player:
			if hours >= well_at:
				st.call("add_status", String(cfg.get("well_rested_status", "well_rested")), buff_seconds)
			elif hours < rested_at:
				st.call("add_status", String(cfg.get("tired_status", "tired")), buff_seconds)
	var line := String(cfg.get("well_rested_text", "You wake well rested.")) if hours >= well_at else \
		(String(cfg.get("rested_text", "You wake rested.")) if hours >= rested_at else String(cfg.get("tired_text", "A short rest. You're still tired.")))
	var session := get_tree().root.get_node_or_null("GameSession")
	if session and bool(session.call("active")):
		session.call("save_game")
	await get_tree().create_timer(0.6).timeout
	if menu:
		menu.set("menu_open", false)
	fade.call("clear", self, float(cfg.get("fade_in", 1.4)))
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.call("notify", self, line, Color(1.0, 0.85, 0.55), 3.0)
	var log_class = load("res://scripts/ui/game_log.gd")
	log_class.call("post", "You rest %d hours by the fire. %s" % [hours, line], Color(1.0, 0.8, 0.5))
