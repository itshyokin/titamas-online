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

var _plane: MeshInstance3D
var _target: Node3D
var _streamer: ChunkStreamer


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


func _process(_delta: float) -> void:
	if _target and not Engine.is_editor_hint():
		# Snap so the wave vertices don't shimmer as the plane moves.
		var step := plane_size / 160.0
		var p := _target.global_position
		_plane.global_position = Vector3(snappedf(p.x, step), sea_level, snappedf(p.z, step))


## Water surface height (same interface as WaterVolume).
func surface_height() -> float:
	return sea_level


## Horizontal distance (m) from a point to the nearest land chunk. 0 when over land.
func distance_from_land(point: Vector3) -> float:
	if _streamer == null:
		return 0.0
	return _streamer.distance_to_land(point)
