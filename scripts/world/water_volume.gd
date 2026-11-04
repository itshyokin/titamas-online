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
@export var color := Color(0.2, 0.45, 0.6, 0.55):
	set(value):
		color = value
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
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		add_child(_mesh)
	var box := BoxShape3D.new()
	box.size = size
	_shape.shape = box
	# Visible surface: a flat plane at the top of the volume.
	var plane := PlaneMesh.new()
	plane.size = Vector2(size.x, size.z)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.2
	plane.material = mat
	_mesh.mesh = plane
	_mesh.position = Vector3(0, size.y * 0.5, 0)
