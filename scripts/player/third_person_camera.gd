class_name ThirdPersonCamera
extends Node3D
## Orbiting third-person camera. Hold right mouse (or the right stick) to look around,
## wheel to zoom. While locked onto a target it swings round behind the player to keep
## the target in view (Fable style).
## Sits on the player as a "CameraRig" with a SpringArm3D > Camera3D under it,
## and stays level (its yaw is independent of the character's facing).

@export var mouse_sensitivity := 0.25
@export var min_pitch := -70.0
@export var max_pitch := 35.0
@export var min_distance := 2.0
@export var max_distance := 10.0
@export var zoom_step := 0.75
@export var zoom_smoothing := 10.0
## Right stick turn speed, degrees per second at full tilt.
@export var stick_speed := 150.0
## How quickly the camera swings round to frame a locked target.
@export var lock_follow := 5.0

@onready var spring_arm: SpringArm3D = $SpringArm3D

var _yaw := 0.0
var _pitch := -15.0
var _target_distance := 5.0
var _trauma := 0.0  # 0..1, from hits; decays
var _shake_time := 0.0


func _ready() -> void:
	add_to_group("player_camera")
	top_level = true  # don't inherit the character's rotation
	_target_distance = spring_arm.spring_length
	spring_arm.add_excluded_object(get_parent().get_rid())


func _unhandled_input(event: InputEvent) -> void:
	if GameSettings.menu_open:
		return
	if event.is_action_pressed("camera_look"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_released("camera_look"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("zoom_in"):
		_target_distance = maxf(_target_distance - zoom_step, min_distance)
	elif event.is_action_pressed("zoom_out"):
		_target_distance = minf(_target_distance + zoom_step, max_distance)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := mouse_sensitivity * GameSettings.camera_sensitivity
		var invert := -1.0 if GameSettings.invert_camera_y else 1.0
		_yaw -= event.relative.x * sens
		_pitch = clampf(_pitch - event.relative.y * sens * invert, min_pitch, max_pitch)


func _process(delta: float) -> void:
	var owner_body := get_parent() as Node3D
	global_position = owner_body.global_position + Vector3(0, 1.6, 0)
	var lock: Node3D = owner_body.get("lock_target")
	if lock and is_instance_valid(lock):
		# Look from behind the player towards the target, a little from above.
		var to := lock.global_position - owner_body.global_position
		to.y = 0.0
		if to.length() > 0.5:
			var want_yaw := rad_to_deg(atan2(-to.x, -to.z))
			_yaw = rad_to_deg(lerp_angle(deg_to_rad(_yaw), deg_to_rad(want_yaw), 1.0 - exp(-lock_follow * delta)))
			var rise := lock.global_position.y - owner_body.global_position.y
			var want_pitch := clampf(-14.0 + rad_to_deg(atan2(rise, maxf(to.length(), 1.0))) * 0.5, min_pitch, max_pitch)
			_pitch = lerpf(_pitch, want_pitch, 1.0 - exp(-2.0 * delta))
	elif not GameSettings.menu_open:
		var stick := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
		if stick.length() > 0.0:
			var speed := stick_speed * GameSettings.camera_sensitivity * delta
			var invert := -1.0 if GameSettings.invert_camera_y else 1.0
			_yaw -= stick.x * speed
			_pitch = clampf(_pitch - stick.y * speed * 0.7 * invert, min_pitch, max_pitch)
	rotation_degrees = Vector3(_pitch, _yaw, 0)
	if _trauma > 0.0:
		# Shake: trauma squared, so small knocks are subtle and big ones punchy.
		_shake_time += delta * 40.0
		var k := _trauma * _trauma * 2.5 * GameSettings.screen_shake
		rotation_degrees += Vector3(sin(_shake_time * 1.3) * k, sin(_shake_time * 0.9 + 2.0) * k, sin(_shake_time * 1.1 + 4.0) * k * 0.5)
		_trauma = maxf(_trauma - delta * 2.2, 0.0)
	spring_arm.spring_length = lerpf(spring_arm.spring_length, _target_distance, zoom_smoothing * delta)


## Shakes the view; strength 0..1 adds up (Settings → Graphics → Screen shake scales it).
func shake(strength: float) -> void:
	_trauma = clampf(_trauma + strength, 0.0, 1.0)


## Flat forward/right vectors of the camera, used for camera-relative movement.
func get_flat_basis() -> Basis:
	return Basis(Vector3.UP, deg_to_rad(_yaw))
