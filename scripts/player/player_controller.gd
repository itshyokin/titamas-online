class_name PlayerController
extends CharacterBody3D
## Player movement: camera-relative running, walking (hold Ctrl), sprinting with
## stamina, jumping and dodging. The character turns to face the way it moves
## (action-RPG style). Movement modes live in `state`; PlayerAnimator reads it.

signal jumped
## Emitted when a dodge starts, with the animation to play and the time to start it from.
signal dodged(anim: String, start_time: float)

enum State { NORMAL, DODGE }

@export_group("Movement")
@export var run_speed := 4.5
@export var walk_speed := 1.8
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

@export_group("Dodge")
@export var dodge_stamina_cost := 20.0
@export var dodge_cooldown := 0.25
@export var roll_distance := 4.0
## Seconds the forward roll lasts before control returns.
@export var roll_duration := 0.7
## Where in "dodge_roll" to start (skips the clip's run-up).
@export var roll_anim_start := 0.4
## Invulnerable window, in seconds from the start of a dodge.
@export var iframe_start := 0.05
@export var iframe_end := 0.45

@onready var stats: Stats = $Stats
@onready var camera_rig: ThirdPersonCamera = $CameraRig
@onready var model: Node3D = $Model
@onready var character: CharacterModel = $Model/Character

var state := State.NORMAL
var is_sprinting := false
## True when the character should keep facing a target (combat lock-on). Dodges
## then become left/right/back hops relative to the facing instead of turning to roll.
var lock_facing := false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _sprint_exhausted := false
var _dodge_anim := ""
var _dodge_time := 0.0
var _dodge_duration := 0.0
var _dodge_motion := PackedVector3Array()
var _dodge_basis := Basis.IDENTITY
var _dodge_cooldown_left := 0.0


func _physics_process(delta: float) -> void:
	_dodge_cooldown_left = maxf(_dodge_cooldown_left - delta, 0.0)
	match state:
		State.NORMAL:
			_normal_movement(delta)
		State.DODGE:
			_dodge_movement(delta)
	move_and_slide()


## True during the invulnerable part of a dodge.
func is_invulnerable() -> bool:
	return state == State.DODGE and _dodge_time >= iframe_start and _dodge_time <= iframe_end


func _input_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := camera_rig.get_flat_basis() * Vector3(input.x, 0, input.y)
	return direction.normalized() if direction.length() > 0.01 else Vector3.ZERO


func _normal_movement(delta: float) -> void:
	var direction := _input_direction()
	_update_sprint(direction != Vector3.ZERO, delta)

	if is_on_floor() and Input.is_action_just_pressed("dodge") and _try_dodge(direction):
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump") and stats.use_stamina(jump_stamina_cost):
		velocity.y = jump_velocity
		jumped.emit()

	var speed := run_speed
	if is_sprinting:
		speed = sprint_speed
	elif Input.is_action_pressed("walk"):
		speed = walk_speed
	var target := direction * speed
	var accel := acceleration if is_on_floor() else acceleration * air_control
	velocity.x = lerpf(velocity.x, target.x, accel * delta)
	velocity.z = lerpf(velocity.z, target.z, accel * delta)

	if direction != Vector3.ZERO and not lock_facing:
		model.rotation.y = lerp_angle(model.rotation.y, _yaw_of(direction), turn_speed * delta)


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


# --- Dodge -------------------------------------------------------------------

func _try_dodge(direction: Vector3) -> bool:
	if _dodge_cooldown_left > 0.0 or not stats.use_stamina(dodge_stamina_cost):
		return false

	var anim := "dodge_back"
	if lock_facing:
		# Pick a hop relative to where the character faces.
		var local := model.global_transform.basis.inverse() * direction
		if direction == Vector3.ZERO or local.z > 0.5:
			anim = "dodge_back"
		elif local.z < -0.5:
			anim = "dodge_roll"
		else:
			anim = "dodge_left" if local.x < 0.0 else "dodge_right"
	elif direction != Vector3.ZERO:
		model.rotation.y = _yaw_of(direction)  # turn and roll that way
		anim = "dodge_roll"

	_dodge_anim = anim
	_dodge_time = 0.0
	_dodge_basis = model.global_transform.basis.orthonormalized()
	_dodge_motion = character.get_root_motion(anim)
	if anim == "dodge_roll" or _dodge_motion.is_empty():
		_dodge_duration = roll_duration
	else:
		_dodge_duration = _motion_end_time(_dodge_motion) + 0.05
	is_sprinting = false
	state = State.DODGE
	dodged.emit(anim, roll_anim_start if anim == "dodge_roll" else 0.0)
	return true


func _dodge_movement(delta: float) -> void:
	var before := _dodge_offset(_dodge_time)
	_dodge_time += delta
	var after := _dodge_offset(_dodge_time)
	var step := _dodge_basis * (after - before) / delta
	velocity.x = step.x
	velocity.z = step.z
	if not is_on_floor():
		velocity.y -= gravity * delta
	if _dodge_time >= _dodge_duration:
		state = State.NORMAL
		_dodge_cooldown_left = dodge_cooldown


## Character-local offset (facing -Z) at time t into the dodge.
func _dodge_offset(t: float) -> Vector3:
	if _dodge_anim == "dodge_roll" or _dodge_motion.is_empty():
		var dist := roll_distance * smoothstep(0.0, roll_duration * 0.9, t)
		var dir := Vector3.FORWARD if _dodge_anim == "dodge_roll" else Vector3.BACK
		return dir * dist
	var f := clampf(t * 30.0, 0.0, _dodge_motion.size() - 1.0)
	var i := int(f)
	var j := mini(i + 1, _dodge_motion.size() - 1)
	return _dodge_motion[i].lerp(_dodge_motion[j], f - i)


## Time (s) at which a root-motion curve has covered 98% of its distance.
func _motion_end_time(motion: PackedVector3Array) -> float:
	var total := motion[motion.size() - 1].length()
	for i in motion.size():
		if motion[i].length() >= total * 0.98:
			return i / 30.0
	return (motion.size() - 1) / 30.0


func _yaw_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)
