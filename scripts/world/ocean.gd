@tool
class_name Ocean
extends Node3D
## The endless sea around the world. A large water plane follows the player so it
## never ends, and anything below `sea_level` counts as water for swimming.
## Players far from land build up fatigue (see PlayerController).

@export var sea_level := -5.0
## Take the sea level from data/world.json "sea_level" (Database → World), re-read live.
@export var use_world_sea_level := true
## Size of the visible water plane (it follows the target, so this is just the view range).
@export var plane_size := 2400.0
@export var water_material: Material = preload("res://assets/materials/water.tres")
@export var target_path: NodePath
## Used to know where land is (the chunk grid).
@export var streamer_path: NodePath
## How far from the nearest land chunk (m) before fatigue starts building.
@export var fatigue_distance := 48.0

@export_group("Sound")
## Waves on the shore, loudest at the coast and fading inland and with height.
@export var surf_loop: AudioStream = preload("res://assets/audio/ambience/surf_loop.ogg")
@export_range(-40.0, 6.0) var surf_volume_db := -4.0
## Surf fades out this far (m) from the open sea...
@export var surf_range := 110.0
## ...and this high (m) above sea level.
@export var surf_height := 70.0

var _plane: MeshInstance3D
var _target: Node3D
var _streamer: ChunkStreamer
var _surf: AudioStreamPlayer
var _surf_timer := 0.0
var _surf_goal := -80.0
var _sea_check := 0.0

const WORLD_FILE := "res://data/world.json"
static var _world_level := -5.0
static var _world_time := -1
static var _world_checked := -100000


## Sea level from data/world.json (−5 when it isn't set). Looks at the file once a second at most.
static func world_sea_level() -> float:
	var now := Time.get_ticks_msec()
	if _world_time != -1 and now - _world_checked < 1000:
		return _world_level
	_world_checked = now
	var t := FileAccess.get_modified_time(WORLD_FILE) if FileAccess.file_exists(WORLD_FILE) else 0
	if t != _world_time:
		_world_time = t
		var d = JSON.parse_string(FileAccess.get_file_as_string(WORLD_FILE)) if t != 0 else null
		_world_level = float((d as Dictionary).get("sea_level", -5.0)) if d is Dictionary else -5.0
	return _world_level


func _ready() -> void:
	add_to_group("ocean")
	if use_world_sea_level:
		sea_level = world_sea_level()
	_target = get_node_or_null(target_path) as Node3D
	_streamer = get_node_or_null(streamer_path) as ChunkStreamer
	_plane = MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(plane_size, plane_size)
	# Enough vertices near the player for gentle waves; far away nobody can tell.
	mesh.subdivide_width = 160
	mesh.subdivide_depth = 160
	mesh.material = water_material
	_plane.mesh = mesh
	_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_plane)
	_plane.global_position = Vector3(0, sea_level, 0)
	if not Engine.is_editor_hint() and surf_loop:
		_surf = AudioStreamPlayer.new()
		_surf.bus = &"Ambience"
		_surf.stream = AmbientLoops.looped(surf_loop)
		_surf.volume_db = -80.0
		add_child(_surf)
		_surf.play(randf() * maxf(surf_loop.get_length() - 1.0, 0.0))


func _process(delta: float) -> void:
	_sea_check -= delta
	if use_world_sea_level and _sea_check <= 0.0:
		_sea_check = 1.0
		sea_level = world_sea_level()
		if _plane and (_target == null or Engine.is_editor_hint()):
			_plane.global_position.y = sea_level
	if _target and not Engine.is_editor_hint():
		# Snap so the wave vertices don't shimmer as the plane moves.
		var step := plane_size / 160.0
		var p := _target.global_position
		_plane.global_position = Vector3(snappedf(p.x, step), sea_level, snappedf(p.z, step))
		_update_surf(p, delta)


func _update_surf(p: Vector3, delta: float) -> void:
	if _surf == null:
		return
	_surf_timer -= delta
	if _surf_timer <= 0.0:
		_surf_timer = 0.3
		var away := _streamer.distance_to_sea(p) if _streamer else 0.0
		var near := clampf(1.0 - away / surf_range, 0.0, 1.0)
		near *= clampf(1.0 - (p.y - sea_level) / surf_height, 0.0, 1.0)
		# Equal-power style fade: stays full near the coast, drops off further in.
		_surf_goal = surf_volume_db + linear_to_db(maxf(near * near, 0.0001)) if near > 0.0 else -80.0
	_surf.volume_db = lerpf(_surf.volume_db, _surf_goal, 1.0 - exp(-delta * 2.0))


## Water surface height (same interface as WaterVolume).
func surface_height() -> float:
	return sea_level


## Horizontal distance (m) from a point to the nearest land chunk. 0 when over land.
func distance_from_land(point: Vector3) -> float:
	if _streamer == null:
		return 0.0
	return _streamer.distance_to_land(point)
