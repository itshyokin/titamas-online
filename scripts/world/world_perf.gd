class_name WorldPerf
extends Node
## Keeps the world cheap to run (made by AtmosphereManager; group "world_perf").
## Settings: data/world.json "performance" (Database → World → Performance), scaled by
## the player's View distance setting where it says so.
##
## - Far-off AI sleeps: enemies and NPCs that are idle and further than ai_sleep_distance
##   from every player stop thinking, moving and animating (their whole node is switched
##   off, which also takes them out of the physics world) until someone comes back within
##   ai_sleep_distance - ai_wake_margin. Anything fighting, chasing, following, talking
##   or dying stays awake. Joined co-op games leave enemies alone (the host runs them).
## - Props fade out with distance by size (see `prop_range`), so pebbles and bushes
##   aren't drawn across the whole map while big trees and rocks still are.
## - Hills hide what is behind them: each chunk gets a coarse, slightly sunken copy of
##   its ground as an occluder (`make_occluder`), and occlusion culling is switched on.
## - Counts for the F3 overlay (`awake`, `asleep`).

const FILE := "res://data/world.json"
const DEFAULTS := {
	"ai_sleep_distance": 90.0, "ai_wake_margin": 12.0,
	"prop_range_per_metre": 24.0, "prop_range_min": 45.0, "prop_range_fade": 6.0,
	"occlusion": true, "occluder_step": 4, "occluder_sink": 1.0,
	"props_per_frame": 12, "grass_range": 50.0,
}

static var _cfg := {}
static var _cfg_time := -1
static var _cfg_checked := 0

var awake := 0
var asleep := 0
var _check := 0.0
var _reload := 0.0


## world.json "performance", with defaults for anything missing.
static func settings() -> Dictionary:
	# The file is looked at once a second at most (the Database page saves into it).
	var now := Time.get_ticks_msec()
	if not _cfg.is_empty() and now - _cfg_checked < 1000:
		return _cfg
	_cfg_checked = now
	var t := DataFiles.modified_time(FILE)
	if t != _cfg_time or _cfg.is_empty():
		_cfg_time = t
		var d = DataFiles.read(FILE)
		var p = (d as Dictionary).get("performance", {}) if d is Dictionary else {}
		_cfg = DEFAULTS.duplicate()
		if p is Dictionary:
			_cfg.merge(p, true)
	return _cfg


## The player's View distance setting as a multiplier (1 = far).
static func view_scale() -> float:
	var loop := Engine.get_main_loop() as SceneTree
	var gs := loop.root.get_node_or_null("GameSettings") if loop else null
	return float(gs.call("view_distance_scale")) if gs and gs.has_method("view_distance_scale") else 1.0


## How far away a prop `size` metres across (its longest side, after scaling) is still drawn.
static func prop_range(size: float) -> float:
	var cfg := settings()
	return maxf(size * float(cfg.prop_range_per_metre), float(cfg.prop_range_min)) * view_scale()


## Sets the draw distance on every mesh of a placed prop. `size`: its longest side (m).
static func apply_prop_range(prop: Node3D, size: float) -> void:
	var cfg := settings()
	var limit := prop_range(size)
	var fade := float(cfg.prop_range_fade)
	for n in prop.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		g.visibility_range_end = limit
		g.visibility_range_end_margin = fade
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if fade > 0.0 else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


static func grass_range() -> float:
	return float(settings().grass_range) * view_scale()


## A coarse copy of a chunk's ground for occlusion culling: every `occluder_step`th
## terrain vertex, each put at the lowest ground around it and sunk a little more, so it
## always lies under the real ground and never hides something that should be seen.
## `heights`: the chunk's height grid (n x n, `spacing` m apart, corner at -chunk_size/2).
static func make_occluder(heights: PackedFloat32Array, n: int, spacing: float, chunk_size: float) -> OccluderInstance3D:
	var cfg := settings()
	if not bool(cfg.occlusion) or heights.size() != n * n or n < 3:
		return null
	var step := clampi(int(cfg.occluder_step), 1, 16)
	var sink := float(cfg.occluder_sink)
	var m := (n - 1) / step + 1
	if m < 2:
		return null
	var verts := PackedVector3Array()
	verts.resize(m * m)
	var half := chunk_size * 0.5
	for j in m:
		for i in m:
			var gx := mini(i * step, n - 1)
			var gz := mini(j * step, n - 1)
			var low := INF
			for dz in range(maxi(gz - step, 0), mini(gz + step, n - 1) + 1):
				for dx in range(maxi(gx - step, 0), mini(gx + step, n - 1) + 1):
					low = minf(low, heights[dz * n + dx])
			verts[j * m + i] = Vector3(gx * spacing - half, low - sink, gz * spacing - half)
	var indices := PackedInt32Array()
	for j in m - 1:
		for i in m - 1:
			var a := j * m + i
			indices.append_array([a, a + 1, a + m, a + 1, a + m + 1, a + m])
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(verts, indices)
	var inst := OccluderInstance3D.new()
	inst.name = "GroundOccluder"
	inst.occluder = occ
	return inst


func _ready() -> void:
	add_to_group("world_perf")
	_apply_occlusion()
	var gs := get_tree().root.get_node_or_null("GameSettings")
	if gs:
		gs.connect("graphics_changed", _apply_shadows)
	_apply_shadows.call_deferred()


## The Shadows setting: how far the sun's and moon's shadows reach, how sharp, or none.
func _apply_shadows() -> void:
	var gs := get_tree().root.get_node_or_null("GameSettings")
	var scene := get_tree().current_scene
	if gs == null or scene == null:
		return
	var option: Array = (gs.get("SHADOW_OPTIONS") as Dictionary).get(String(gs.get("shadows")), [4096, 1.0])
	var size := int(option[0])
	if size > 0:
		RenderingServer.directional_shadow_atlas_set_size(size, true)
	for n in scene.find_children("*", "DirectionalLight3D", true, false):
		var light := n as DirectionalLight3D
		if not light.has_meta("base_shadow_distance"):
			light.set_meta("base_shadow_distance", light.directional_shadow_max_distance)
			light.set_meta("base_shadow_on", light.shadow_enabled)
		light.shadow_enabled = bool(light.get_meta("base_shadow_on")) and size > 0
		if size > 0:
			light.directional_shadow_max_distance = float(light.get_meta("base_shadow_distance")) * float(option[1])


func _process(delta: float) -> void:
	_reload -= delta
	if _reload <= 0.0:
		_reload = 1.0
		_apply_occlusion()
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		_update_sleep()


func _apply_occlusion() -> void:
	var vp := get_viewport()
	var want := bool(settings().occlusion)
	if vp and vp.use_occlusion_culling != want:
		vp.use_occlusion_culling = want


func _exit_tree() -> void:
	# Nothing stays asleep when the level goes away (nodes may be reused).
	for n in get_tree().get_nodes_in_group(Combat.GROUP) + get_tree().get_nodes_in_group("npcs"):
		if n.has_meta("perf_asleep"):
			_set_asleep(n, false)


func _update_sleep() -> void:
	var cfg := settings()
	var sleep_at := float(cfg.ai_sleep_distance)
	var wake_at := maxf(sleep_at - float(cfg.ai_wake_margin), 0.0)
	var net := get_tree().root.get_node_or_null("Net")
	var client: bool = net != null and net.call("is_client")
	var watchers: Array[Vector3] = []
	for p in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("party_members"):
		if p is Node3D:
			watchers.append((p as Node3D).global_position)
	var cam := get_viewport().get_camera_3d()
	if cam:
		watchers.append(cam.global_position)
	awake = 0
	asleep = 0
	var seen := {}
	for n in get_tree().get_nodes_in_group(Combat.GROUP) + get_tree().get_nodes_in_group("npcs"):
		if seen.has(n) or not n is CharacterBody3D or n.is_in_group("player") or n.is_in_group("party_members") \
				or n.has_meta("talk_frozen"):
			continue
		seen[n] = true
		var body := n as CharacterBody3D
		var sleeping := body.has_meta("perf_asleep")
		var nearest := INF
		for w in watchers:
			nearest = minf(nearest, w.distance_to(body.global_position))
		if sleeping:
			if sleep_at <= 0.0 or nearest < wake_at or watchers.is_empty():
				_set_asleep(body, false)
				sleeping = false
		elif sleep_at > 0.0 and nearest > sleep_at and not client and not watchers.is_empty() and _can_sleep(body):
			_set_asleep(body, true)
			sleeping = true
		if sleeping:
			asleep += 1
		else:
			awake += 1


## Idle, on the ground it spawned on, and nobody's business right now.
func _can_sleep(body: Node) -> bool:
	if body.get("_settled") != true or body.is_in_group("followers"):
		return false
	if body.get("big") == true:
		return false  # dragons and the like are seen from far off: they keep moving
	if int(body.get("ai")) != 0:  # Enemy.AI.IDLE / Npc.AI.IDLE
		return false
	var target = body.get("target")
	if target != null and is_instance_valid(target):
		return false
	if body.get("leader") != null and is_instance_valid(body.get("leader")):
		return false
	return true


func _set_asleep(body: Node, on: bool) -> void:
	if on:
		body.set_meta("perf_asleep", true)
		body.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		body.remove_meta("perf_asleep")
		body.process_mode = Node.PROCESS_MODE_INHERIT
