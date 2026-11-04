class_name PlayerController
extends CharacterBody3D
## Player movement: camera-relative running, walking (hold Ctrl), sprinting with
## stamina, jumping, dodging and ledge grabbing. The character turns to face the way
## it moves (action-RPG style). Movement modes live in `state`; PlayerAnimator picks
## animations in NORMAL and plays the ones requested via `action_animation` otherwise.

signal jumped
## Emitted when a dodge starts, with the animation to play and the time to start it from.
signal dodged(anim: String, start_time: float)
## Asks the animator to play a specific animation (special moves).
signal action_animation(anim: String, start_time: float, blend: float, speed: float)

enum State { NORMAL, DODGE, HANG, LEDGE_CLIMB }

const WORLD_MASK := 1

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

@export_group("Ledges")
## Ledge height above the feet that can be grabbed while in the air.
@export var grab_reach_min := 1.5
@export var grab_reach_max := 2.5
## Hands above the feet in "hanging_idle", and feet distance from the wall face.
@export var hang_hands_height := 2.3
@export var hang_wall_distance := 0.3
## Hands position in the first frame of "hanging_climb_up" (above / in front of the feet).
@export var climb_hands_height := 1.35
@export var climb_hands_forward := 0.39
@export var shimmy_speed := 1.4
## How far onto the ledge the character stands after climbing up.
@export var climb_onto_distance := 0.35

@onready var stats: Stats = $Stats
@onready var camera_rig: ThirdPersonCamera = $CameraRig
@onready var model: Node3D = $Model
@onready var character: CharacterModel = $Model/Character
@onready var collision: CollisionShape3D = $CollisionShape3D

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

var _ledge_edge := Vector3.ZERO  # top edge at the wall face, at ledge height
var _ledge_normal := Vector3.ZERO  # horizontal, pointing out of the wall
var _grab_cooldown := 0.0
var _hang_time := 0.0
var _hop_anim := ""
var _hop_time := 0.0
var _hop_duration := 0.0
var _hop_motion := PackedVector3Array()
var _hop_start := Vector3.ZERO
var _hop_basis := Basis.IDENTITY
var _hop_target := {}
var _climb_time := 0.0
var _climb_duration := 0.0
var _climb_target := Vector3.ZERO


func _physics_process(delta: float) -> void:
	_dodge_cooldown_left = maxf(_dodge_cooldown_left - delta, 0.0)
	_grab_cooldown = maxf(_grab_cooldown - delta, 0.0)
	match state:
		State.NORMAL:
			_normal_movement(delta)
			move_and_slide()
		State.DODGE:
			_dodge_movement(delta)
			move_and_slide()
		State.HANG:
			_hang_movement(delta)
		State.LEDGE_CLIMB:
			_ledge_climb_movement(delta)


## True during the invulnerable part of a dodge.
func is_invulnerable() -> bool:
	return state == State.DODGE and _dodge_time >= iframe_start and _dodge_time <= iframe_end


func _input_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := camera_rig.get_flat_basis() * Vector3(input.x, 0, input.y)
	return direction.normalized() if direction.length() > 0.01 else Vector3.ZERO


func _forward() -> Vector3:
	var f := -model.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _normal_movement(delta: float) -> void:
	var direction := _input_direction()
	_update_sprint(direction != Vector3.ZERO, delta)

	if is_on_floor() and Input.is_action_just_pressed("dodge") and _try_dodge(direction):
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
		if velocity.y < 2.0 and _grab_cooldown <= 0.0:
			var ledge := _probe_ledge(global_position, _forward())
			if not ledge.is_empty():
				_start_hang(ledge)
				return
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
	var start := roll_anim_start if anim == "dodge_roll" else 0.0
	dodged.emit(anim, start)
	action_animation.emit(anim, start, 0.08, 1.0)
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
	return _sample_motion(_dodge_motion, t)


# --- Ledges ------------------------------------------------------------------

## Looks for a grabbable ledge in front of a body standing at `feet`. Returns
## {"edge": top edge point at the wall face, "normal": horizontal wall normal} or {}.
func _probe_ledge(feet: Vector3, forward: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var chest := feet + Vector3.UP * 1.4
	var wall := _ray(space, chest, chest + forward * 0.8)
	if wall.is_empty() or absf(wall.normal.y) > 0.3:
		return {}
	var normal: Vector3 = wall.normal
	normal.y = 0.0
	normal = normal.normalized()

	# Look down onto the top of the wall, just behind its face.
	var probe: Vector3 = wall.position - normal * 0.15
	var top := _ray(space, Vector3(probe.x, feet.y + grab_reach_max + 0.3, probe.z), Vector3(probe.x, feet.y + grab_reach_min - 0.2, probe.z))
	if top.is_empty() or top.normal.y < 0.7:
		return {}
	var reach: float = top.position.y - feet.y
	if reach < grab_reach_min or reach > grab_reach_max:
		return {}
	# Room for the hands: nothing directly above the edge.
	var edge := Vector3(wall.position.x, top.position.y, wall.position.z)
	if not _ray(space, edge + normal * 0.1 + Vector3.UP * 0.05, edge + normal * 0.1 + Vector3.UP * 0.5).is_empty():
		return {}
	return {"edge": edge, "normal": normal}


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK, [get_rid()])
	query.hit_back_faces = false
	return space.intersect_ray(query)


func _start_hang(ledge: Dictionary) -> void:
	_ledge_edge = ledge.edge
	_ledge_normal = ledge.normal
	state = State.HANG
	velocity = Vector3.ZERO
	is_sprinting = false
	_hang_time = 0.0
	_hop_anim = ""
	model.rotation.y = _yaw_of(-_ledge_normal)
	global_position = _hang_position(_ledge_edge)
	action_animation.emit("hanging_idle", 0.0, 0.15, 1.0)


func _hang_position(edge: Vector3) -> Vector3:
	return edge + _ledge_normal * hang_wall_distance - Vector3.UP * hang_hands_height


func _hang_movement(delta: float) -> void:
	_hang_time += delta
	if not _hop_anim.is_empty():
		_hop_movement(delta)
		return
	if Input.is_action_just_pressed("jump") or (Input.is_action_pressed("move_forward") and _hang_time > 0.35):
		if _try_climb_up():
			return
	if Input.is_action_pressed("move_back") or Input.is_action_just_pressed("walk"):
		_drop_from_ledge()
		return
	var side := Input.get_axis("move_left", "move_right")
	if absf(side) > 0.5:
		_try_hop(signf(side))


func _try_hop(dir: float) -> void:
	var anim := "hanging_hop_right" if dir > 0.0 else "hanging_hop_left"
	var motion := character.get_root_motion(anim)
	if motion.is_empty():
		return
	var right := (-_ledge_normal).cross(Vector3.UP)
	var offset := right * dir * motion[motion.size() - 1].length()
	# Blocked sideways at hand height?
	var space := get_world_3d().direct_space_state
	var hands := _ledge_edge + _ledge_normal * 0.2 - Vector3.UP * 0.3
	if not _ray(space, hands, hands + offset * 1.25).is_empty():
		return
	# Ledge must continue at about the same height.
	var target := _probe_ledge(global_position + offset, -_ledge_normal)
	if target.is_empty() or absf(target.edge.y - _ledge_edge.y) > 0.5 or target.normal.dot(_ledge_normal) < 0.8:
		return
	_hop_anim = anim
	_hop_time = 0.0
	_hop_motion = motion
	_hop_duration = _motion_end_time(motion) + 0.1
	_hop_start = global_position
	_hop_basis = model.global_transform.basis.orthonormalized()
	_hop_target = target
	action_animation.emit(anim, 0.0, 0.12, shimmy_speed)


func _hop_movement(delta: float) -> void:
	_hop_time += delta * shimmy_speed
	var t := minf(_hop_time / _hop_duration, 1.0)
	var target_pos := _hang_position(_hop_target.edge)
	var pos := _hop_start + _hop_basis * _sample_motion(_hop_motion, _hop_time)
	pos.y = lerpf(_hop_start.y, target_pos.y, t)
	global_position = pos
	if t >= 1.0:
		_ledge_edge = _hop_target.edge
		_ledge_normal = _hop_target.normal
		global_position = _hang_position(_ledge_edge)
		_hop_anim = ""
		action_animation.emit("hanging_idle", 0.0, 0.3, 1.0)


func _try_climb_up() -> bool:
	var target := _ledge_edge - _ledge_normal * climb_onto_distance
	# Room to stand on top?
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = collision.shape
	params.transform = Transform3D(Basis.IDENTITY, target + collision.position + Vector3.UP * 0.05)
	params.collision_mask = WORLD_MASK
	params.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty():
		return false
	_climb_target = target
	_climb_time = 0.0
	_climb_duration = character.get_animation_length("hanging_climb_up")
	# Line the climb clip's hands up with the edge.
	global_position = _ledge_edge + _ledge_normal * climb_hands_forward - Vector3.UP * climb_hands_height
	state = State.LEDGE_CLIMB
	action_animation.emit("hanging_climb_up", 0.0, 0.15, 1.0)
	return true


func _ledge_climb_movement(delta: float) -> void:
	_climb_time += delta
	if _climb_time >= _climb_duration - 0.05:
		global_position = _climb_target
		velocity = Vector3.ZERO
		state = State.NORMAL
		_grab_cooldown = 0.3
		action_animation.emit("idle", 0.0, 0.12, 1.0)


func _drop_from_ledge() -> void:
	global_position += _ledge_normal * 0.15
	velocity = Vector3.ZERO
	state = State.NORMAL
	_grab_cooldown = 0.5
	action_animation.emit("falling_loop", 0.0, 0.2, 1.0)


# --- Helpers -----------------------------------------------------------------

## Samples a root-motion curve (one offset per frame at 30 fps) at time t.
func _sample_motion(motion: PackedVector3Array, t: float) -> Vector3:
	var f := clampf(t * 30.0, 0.0, motion.size() - 1.0)
	var i := int(f)
	var j := mini(i + 1, motion.size() - 1)
	return motion[i].lerp(motion[j], f - i)


## Time (s) at which a root-motion curve has covered 98% of its distance.
func _motion_end_time(motion: PackedVector3Array) -> float:
	var total := motion[motion.size() - 1].length()
	for i in motion.size():
		if motion[i].length() >= total * 0.98:
			return i / 30.0
	return (motion.size() - 1) / 30.0


func _yaw_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)
