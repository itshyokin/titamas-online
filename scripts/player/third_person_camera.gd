class_name ThirdPersonCamera
extends Node3D
## Orbiting third-person camera. Hold right mouse to look around, wheel to zoom.
## Sits on the player as a "CameraRig" with a SpringArm3D > Camera3D under it,
## and stays level (its yaw is independent of the character's facing).

@export var mouse_sensitivity := 0.25
@export var min_pitch := -70.0
@export var max_pitch := 35.0
@export var min_distance := 2.0
@export var max_distance := 10.0
@export var zoom_step := 0.75
@export var zoom_smoothing := 10.0

@onready var spring_arm: SpringArm3D = $SpringArm3D

var _yaw := 0.0
var _pitch := -15.0
var _target_distance := 5.0


func _ready() -> void:
	top_level = true  # don't inherit the character's rotation
	_target_distance = spring_arm.spring_length
	spring_arm.add_excluded_object(get_parent().get_rid())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_look"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_released("camera_look"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("zoom_in"):
		_target_distance = maxf(_target_distance - zoom_step, min_distance)
	elif event.is_action_pressed("zoom_out"):
		_target_distance = minf(_target_distance + zoom_step, max_distance)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, min_pitch, max_pitch)


func _process(delta: float) -> void:
	var owner_body := get_parent() as Node3D
	global_position = owner_body.global_position + Vector3(0, 1.6, 0)
	rotation_degrees = Vector3(_pitch, _yaw, 0)
	spring_arm.spring_length = lerpf(spring_arm.spring_length, _target_distance, zoom_smoothing * delta)


## Flat forward/right vectors of the camera, used for camera-relative movement.
func get_flat_basis() -> Basis:
	return Basis(Vector3.UP, deg_to_rad(_yaw))
