@tool
class_name Ocean
extends Node3D
## The endless sea around the world. A large water plane follows the player so it
## never ends, and anything below `sea_level` counts as water for swimming.
## Players far from land build up fatigue (see PlayerController).

@export var sea_level := -5.0
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


func _ready() -> void:
	add_to_group("ocean")
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
