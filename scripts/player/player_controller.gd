class_name PlayerController
extends CharacterBody3D
## Milestone 1 movement: camera-relative running, sprinting with stamina, jumping.
## The character turns to face the way it moves (action-RPG style).

@export var walk_speed := 4.5
@export var sprint_speed := 8.0
@export var acceleration := 12.0
@export var air_control := 0.3
@export var turn_speed := 12.0
@export var jump_velocity := 5.0
@export var jump_stamina_cost := 10.0
## Stamina drained per second while sprinting.
@export var sprint_stamina_cost := 25.0
## Stamina needed before sprint can start again after running dry.
@export var sprint_restart_threshold := 20.0

@onready var stats: Stats = $Stats
@onready var camera_rig: ThirdPersonCamera = $CameraRig
@onready var model: Node3D = $Model

var is_sprinting := false
var _sprint_exhausted := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := camera_rig.get_flat_basis() * Vector3(input.x, 0, input.y)
	direction = direction.normalized() if direction.length() > 0.01 else Vector3.ZERO

	_update_sprint(direction != Vector3.ZERO, delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump") and stats.use_stamina(jump_stamina_cost):
		velocity.y = jump_velocity

	var speed := sprint_speed if is_sprinting else walk_speed
	var target := direction * speed
	var accel := acceleration if is_on_floor() else acceleration * air_control
	velocity.x = lerpf(velocity.x, target.x, accel * delta)
	velocity.z = lerpf(velocity.z, target.z, accel * delta)

	if direction != Vector3.ZERO:
		var target_yaw := atan2(-direction.x, -direction.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, turn_speed * delta)

	move_and_slide()


func _update_sprint(moving: bool, delta: float) -> void:
	if _sprint_exhausted and stats.stamina >= sprint_restart_threshold:
		_sprint_exhausted = false
	var wants := Input.is_action_pressed("sprint") and moving and not _sprint_exhausted
	if wants and is_on_floor() or wants and is_sprinting:
		is_sprinting = stats.drain_stamina(sprint_stamina_cost * delta)
		if not is_sprinting:
			_sprint_exhausted = true
	else:
		is_sprinting = false
