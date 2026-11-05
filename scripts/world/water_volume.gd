@tool
class_name WaterVolume
extends Area3D
## A box of swimmable water. The top of the box is the water surface.
## Sits on physics layer 4 ("water"), which the player checks to start swimming.

const WATER_LAYER := 8  # layer 4

@export var size := Vector3(8, 2, 8):
	set(value):
		size = value
		_rebuild()
## Draw a flat surface at the top of the box. Off when the water's look comes from
## elsewhere (e.g. a Blender water plane in a chunk).
@export var show_surface := true:
	set(value):
		show_surface = value
		_rebuild()
@export var water_material: Material = preload("res://assets/materials/water.tres"):
	set(value):
		water_material = value
		_rebuild()

var _shape: CollisionShape3D
var _mesh: MeshInstance3D


func _ready() -> void:
	collision_layer = WATER_LAYER
	collision_mask = 0
	monitoring = false
	_rebuild()


## World height of the water surface.
func surface_height() -> float:
	return global_position.y + size.y * 0.5


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape == null:
		_shape = CollisionShape3D.new()
		add_child(_shape)
	var box := BoxShape3D.new()
	box.size = size
	_shape.shape = box
	if not show_surface:
		if _mesh:
			_mesh.queue_free()
			_mesh = null
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		add_child(_mesh)
	# Visible surface: a flat plane at the top of the volume.
	var plane := PlaneMesh.new()
	plane.size = Vector2(size.x, size.z)
	plane.subdivide_width = int(size.x / 2.0)
	plane.subdivide_depth = int(size.z / 2.0)
	plane.material = water_material
	_mesh.mesh = plane
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.position = Vector3(0, size.y * 0.5, 0)
