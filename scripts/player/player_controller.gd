class_name PlayerController
extends CharacterBody3D
## Player movement: camera-relative running, walking (hold Ctrl), sprinting with
## stamina, jumping, dodging, ledge grabbing, wall/ladder climbing and swimming. The character turns to face the way
## it moves (action-RPG style). Movement modes live in `state`; PlayerAnimator picks
## animations in NORMAL and plays the ones requested via `action_animation` otherwise.

signal jumped
## Emitted when a dodge starts, with the animation to play and the time to start it from.
signal dodged(anim: String, start_time: float)
## Asks the animator to play a specific animation (special moves).
signal action_animation(anim: String, start_time: float, blend: float, speed: float)
signal fatigue_changed(current: float, maximum: float)
## Respawned after dying or falling out of the world, with a reason ("drowned", "fell").
signal respawned(reason: String)

## A combat action (attack, cast, block) was cut short by a dodge, water or death.
signal action_interrupted

enum State { NORMAL, DODGE, HANG, LEDGE_CLIMB, WALL_CLIMB, LADDER, SWIM, ACTION, DEAD }

const WORLD_MASK := 1
const WATER_MASK := 8  # layer 4

@export_group("Movement")
@export var run_speed := 4.5
@export var walk_speed := 1.8
## Hurt (health under injured_health of max, poisoned, or weakened): a limp no faster than
## injured_speed (player.json movement).
## A fall longer than this many metres hurts (0 = never).
@export var fall_safe_height := 4.5
## Damage per metre past the safe height.
@export var fall_damage := 7.0
## A fall of this many metres is certain death (damage ramps up to it).
@export var fall_fatal_height := 22.0
@export var injured_speed := 2.2
## Sprinting while injured or weakened still helps, up to this speed (m/s).
@export var injured_sprint_speed := 4.6
@export var injured_health := 0.2
@export var sprint_speed := 8.0
@export var acceleration := 12.0
@export var air_control := 0.3
@export var turn_speed := 12.0
@export var jump_velocity := 5.0
@export var jump_stamina_cost := 0.0
## Stamina drained per second while sprinting.
@export var sprint_stamina_cost := 25.0
## Stamina needed before sprint can start again after running dry.
@export var sprint_restart_threshold := 20.0

@export_group("Dodge")
@export var dodge_stamina_cost := 0.0
@export var dodge_cooldown := 0.25
## Double-tapping a movement key within this time (s) rolls that way. 0 = off.
@export var double_tap_time := 0.3
## Locked on: dodge with the side/back hops instead of rolling (1 = on).
@export var lock_on_hops := 0.0
## 1 = any wall edge can be grabbed by jumping at it; 0 = only marked ones (see _marked).
@export var grab_any_ledge := 0.0
@export var roll_distance := 4.0
## Seconds the forward roll lasts before control returns.
@export var roll_duration := 0.7
## Where in "dodge_roll" to start (skips the clip's run-up).
@export var roll_anim_start := 0.4
## Invulnerable window, in seconds from the start of a dodge.
@export var iframe_start := 0.05
@export var iframe_end := 0.45
## A hit landing this soon (s) after the dodge's invulnerability starts is a perfect
## dodge: slow motion and a counter.
@export var perfect_dodge_window := 0.18

@export_group("Ledges")
## Ledge height above the feet that can be grabbed while in the air.
@export var grab_reach_min := 1.5
@export var grab_reach_max := 2.5
## Hanging and climbing up are lined up from the clips themselves: the character's
## fingertips are measured in "hanging_idle" and "hanging_climb_up" so they sit on the edge.
## Extra gap between the fingertips and the edge, if the hands should sit further back.
@export var hang_edge_gap := 0.0
@export var shimmy_speed := 1.4
## How far onto the ledge the character stands after climbing up (at least the body radius).
@export var climb_onto_distance := 0.4

@export_group("Climbing")
## Surfaces are climbable when their node is in the "climbable" group (jump onto them)
## or the "ladder" group (walk into them), or when the node (or a parent) is named with
## _climb (wall climbing) / _ladder. Ledges can be hung from and shimmied along when the
## node is in "grabbable"/"climbable" or named with _grab, _shimmy or _climb (Blender
## object names, e.g. "cliff_grab-col"), unless grab_any_ledge is on.
@export var wall_climb_speed := 1.0
@export var ladder_speed := 1.2
## Distance from the feet origin to the wall while climbing. Ladders are measured from
## the clip (fingertips on the rungs) instead.
@export var wall_climb_distance := 0.32
## How far above the origin the feet sit in the climbing clips.
@export var wall_climb_feet := 0.5
@export var ladder_feet := 1.15
## Climb speed (m/s) the clips look right at, for matching animation speed.
@export var wall_climb_anim_rate := 0.5
@export var ladder_anim_rate := 0.8

@export_group("Swimming")
@export var swim_speed := 2.2
## Sprinting while swimming: faster, and it uses stamina.
@export var swim_sprint_speed := 3.8
## Lava (WaterVolume.lava): swimming speed × this, share of max health lost per second while
## in it, and seconds of Burning after climbing out (player.json movement lava_*).
## A fall that hurts but doesn't kill leaves the player limping this long (s).
@export var fall_injury_seconds := 5.0
@export var lava_speed := 0.3
@export var lava_damage := 0.08
@export var lava_burn_seconds := 3.0
@export var swim_sprint_stamina_cost := 18.0
## Water deeper than this (surface above the feet) makes the character swim.
@export var swim_depth := 1.3
## Origin depth below the surface when treading water and when swimming forward.
@export var tread_depth := 1.45
@export var stroke_depth := 0.85

@export_group("Survival")
## Seconds of swimming far from land before fatigue sets in.
@export var fatigue_max := 25.0
## Fatigue drains this many times faster than it builds once back near land.
@export var fatigue_recovery := 3.0
## Share of max health lost per second while fully fatigued.
@export var fatigue_damage := 0.12
## Falling below this height (m) respawns the player at the last safe ground.
@export var kill_height := -80.0
## Seconds lying dead before respawning.
@export var death_time := 3.0

@onready var stats: Stats = $Stats
@onready var camera_rig: ThirdPersonCamera = $CameraRig
@onready var model: Node3D = $Model
@onready var character: CharacterModel = $Model/Character
@onready var collision: CollisionShape3D = $CollisionShape3D

var state := State.NORMAL
var is_sprinting := false
## Movement speed multiplier (Weakened slows you; PlayerProgress sets it).
var speed_scale := 1.0
## Movement speed multiplier from skills (PlayerProgress).
var skill_speed := 1.0
var _dying := false
var _going_home := false
var _stuck_air := 0.0
var _air_peak := -INF
## True when the character should keep facing a target (combat lock-on). Dodges
## then become left/right/back hops relative to the facing instead of turning to roll.
var lock_facing := false
## Locked-on target (set by Targeting): the character keeps facing it while moving.
var lock_target: Node3D = null
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _sprint_exhausted := false
var _sprint_toggle := false

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
var _climb_lift := 0.0  # model raised this much at the start of the climb-up, easing to 0
var _ladder_distance := 0.35

var _surface_normal := Vector3.ZERO  # wall/ladder being climbed
var _water = null  # WaterVolume or Ocean (both have surface_height()); untyped on purpose

## While in ACTION: share of run speed the player can still move at, and extra
## velocity the action adds (lunges). Set by PlayerCombat.
var action_move_scale := 0.0
var action_velocity := Vector3.ZERO

var fatigue := 0.0
var _last_safe := Vector3.ZERO
var _safe_timer := 0.0
var _push := Vector3.ZERO


func _ready() -> void:
	add_to_group("player")
	add_child(UnderwaterView.new())
	add_child(ScreenMood.new())
	_last_safe = global_position
	stats.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	talk_focus = _pick_talkable() if not GameSettings.menu_open else null
	RenderingServer.global_shader_parameter_set("player_position", global_position)
	_update_survival(delta)
	_dodge_cooldown_left = maxf(_dodge_cooldown_left - delta, 0.0)
	_grab_cooldown = maxf(_grab_cooldown - delta, 0.0)
	_watch_fall()
	if seat != null and _seated_tick():
		return
	match state:
		State.NORMAL:
			_normal_movement(delta)
			_apply_push(delta)
			move_and_slide()
		State.DODGE:
			_dodge_movement(delta)
			move_and_slide()
		State.HANG:
			_hang_movement(delta)
		State.LEDGE_CLIMB:
			_ledge_climb_movement(delta)
		State.WALL_CLIMB, State.LADDER:
			_climb_movement(delta)
		State.SWIM:
			_swim_movement(delta)
			move_and_slide()
		State.ACTION:
			_action_movement(delta)
			_apply_push(delta)
			move_and_slide()
		State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
			velocity.y -= gravity * delta
			move_and_slide()


## Remembers the highest point of a fall and hurts you when you land from too far up
## (player.json movement fall_safe_height / fall_damage / fall_fatal_height). Climbing,
## hanging, swimming and dying don't count.
func _watch_fall() -> void:
	if state == State.HANG or state == State.LEDGE_CLIMB or state == State.WALL_CLIMB \
			or state == State.LADDER or state == State.SWIM or state == State.DEAD:
		_air_peak = -INF
		return
	if not is_on_floor():
		_air_peak = maxf(_air_peak, global_position.y)
		return
	if _air_peak == -INF:
		return
	var drop := _air_peak - global_position.y
	_air_peak = -INF
	if fall_safe_height <= 0.0 or drop <= fall_safe_height or stats.is_dead():
		return
	var over := drop - fall_safe_height
	var amount := over * fall_damage
	if fall_fatal_height > fall_safe_height and drop >= fall_fatal_height:
		amount = maxf(amount, stats.health + stats.max_health)  # a killing fall
	amount = maxf(roundf(amount), 1.0)
	stats.take_damage(amount, null)
	FloatingText.spawn(self, "-%d" % int(amount), Color(0.95, 0.4, 0.35), 1.1)
	Effects.flash(model, Color(1.0, 0.4, 0.35), 0.18, 0.7)
	var cam := get_tree().get_first_node_in_group("player_camera")
	if cam:
		cam.call("shake", clampf(over / 10.0, 0.2, 0.8))
	GameLog.post("You hit the ground hard (%d)." % int(amount), Color(1.0, 0.6, 0.5))
	if state == State.NORMAL and not stats.is_dead():
		action_animation.emit("hit_react", 0.0, 0.15, 1.1)
	# Lives through it, but limps for a while (status "sprained": injured).
	if not stats.is_dead() and fall_injury_seconds > 0.0:
		stats.add_status("sprained", fall_injury_seconds)


func _apply_push(delta: float) -> void:
	if _push == Vector3.ZERO:
		return
	velocity.x += _push.x
	velocity.z += _push.z
	_push = _push.move_toward(Vector3.ZERO, 20.0 * delta)
	if state != State.NORMAL and state != State.ACTION:
		_push = Vector3.ZERO


## Jump / talk next to someone who can talk (and roughly faced) starts a conversation.
## The one thing Interact would use right now (its prompt is the only one shown).
var talk_focus: Node3D = null
## The Seat being sat on (null when standing) and which of its spots.
var seat: Node3D = null
var _seat_spot := 0


## Sits down on a seat (Seat.talk): stand at its front, face the way it faces, the SitPose
## lowers the hips onto it. Moving, jumping or dodging gets up.
func sit_on(s: Node3D, spot: int) -> void:
	if state != State.NORMAL or seat != null:
		return
	seat = s
	_seat_spot = spot
	s.call("take", spot, self)
	if s is PhysicsBody3D:
		add_collision_exception_with(s)
	global_position = s.call("feet_position", spot)
	velocity = Vector3.ZERO
	var f: Vector3 = s.call("facing")
	model.rotation.y = _yaw_of(f)
	var sp := character.sit_pose()
	if sp:
		var skel := character.get_skeleton()
		var hips := skel.find_bone("mixamorig_Hips")
		var hip_y := (skel.global_transform * skel.get_bone_global_pose(hips).origin).y - global_position.y if hips >= 0 else 0.95
		sp.forward = f
		sp.seat_drop = maxf(hip_y - (float(s.call("height")) + 0.08), 0.0)
		sp.seat_back = 0.38
		sp.ground = false
		sp.activity = "relax"
		sp.sitting = true
	action_animation.emit("idle", 0.0, 0.3, 1.0)


func stand_up() -> void:
	if seat == null:
		return
	if is_instance_valid(seat):
		seat.call("release", self)
		var was := seat
		# Collide with it again once clear of it.
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if is_instance_valid(was) and seat != was:
				remove_collision_exception_with(was))
	seat = null
	var sp := character.sit_pose()
	if sp:
		sp.sitting = false


## While seated: stay put; any move, jump or dodge stands up. True = skip normal movement.
func _seated_tick() -> bool:
	if not is_instance_valid(seat) or state != State.NORMAL:
		stand_up()
		return false
	velocity = Vector3.ZERO
	if _input_direction() != Vector3.ZERO or _pressed("jump") or _pressed("dodge"):
		stand_up()
		return false
	return true


func _try_talk() -> bool:
	var best := _pick_talkable()
	if best == null:
		return false
	velocity.x = 0.0
	velocity.z = 0.0
	best.call("talk", self)
	return true


## The closest talkable in reach (in front, or right beside).
func _pick_talkable() -> Node3D:
	var best: Node3D = null
	var best_d := 2.6
	var fwd := _forward()
	for n in get_tree().get_nodes_in_group("talkable"):
		var node := n as Node3D
		if node == null or not node.has_method("can_talk") or not node.can_talk():
			continue
		var to := node.global_position - global_position
		to.y = 0.0
		# Areas (events) measure from their edge.
		var d: float = node.call("talk_distance", global_position) if node.has_method("talk_distance") else to.length()
		if d < best_d and (d < 1.2 or fwd.dot(to.normalized()) > -0.2):
			best_d = d
			best = node
	return best


## True during the invulnerable part of a dodge.
func is_invulnerable() -> bool:
	return state == State.DODGE and _dodge_time >= iframe_start and _dodge_time <= iframe_end


## Just pressed, unless a menu is open.
func _pressed(action: String) -> bool:
	return Input.is_action_just_pressed(action) and not GameSettings.menu_open


## Double-tap a movement key: roll that way (keyboard; controllers use the dodge button).
const _TAP_DIRS := {"move_forward": Vector3(0, 0, -1), "move_back": Vector3(0, 0, 1), "move_left": Vector3(-1, 0, 0), "move_right": Vector3(1, 0, 0)}
var _last_tap := {}
var _tap_dodge := Vector3.ZERO


func _check_double_tap(event: InputEvent) -> void:
	if not event is InputEventKey or event.is_echo() or not event.is_pressed() or double_tap_time <= 0.0 or GameSettings.menu_open:
		return
	for action: String in _TAP_DIRS:
		if event.is_action_pressed(action):
			var now := Time.get_ticks_msec()
			if now - int(_last_tap.get(action, -100000)) <= double_tap_time * 1000.0:
				_tap_dodge = camera_rig.get_flat_basis() * _TAP_DIRS[action]
				_last_tap.erase(action)
			else:
				_last_tap.clear()
				_last_tap[action] = now


## A dodge asked for this frame: the dodge button (towards the movement) or a double-tap.
func _dodge_requested(direction: Vector3) -> Vector3:
	if _tap_dodge != Vector3.ZERO:
		var d := _tap_dodge.normalized()
		_tap_dodge = Vector3.ZERO
		return d
	if _pressed("dodge"):
		return direction if direction != Vector3.ZERO else Vector3(0, 0.001, 0)
	return Vector3.INF


func _unhandled_input(event: InputEvent) -> void:
	_check_double_tap(event)
	# Controller sprint is a toggle (the thumb is needed on the camera stick).
	if event.is_action_pressed("sprint") and GameSettings.is_gamepad_event(event) and not GameSettings.menu_open:
		_sprint_toggle = not _sprint_toggle


## Badly hurt, poisoned or weakened: limps (slower, injured walk).
func is_injured() -> bool:
	if stats.is_dead():
		return false
	if stats.health < stats.max_health * injured_health or stats.status_flag("injured"):
		return true
	var progress := get_node_or_null("Progress")
	return progress != null and progress.has_method("is_weakened") and bool(progress.call("is_weakened"))


func _input_direction() -> Vector3:
	if GameSettings.menu_open:
		return Vector3.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if stats.status_flag("confused") and input != Vector2.ZERO:
		# Confused: the controls are reversed and drift.
		input = (-input).rotated(sin(Time.get_ticks_msec() / 700.0) * 0.9)
	var direction := camera_rig.get_flat_basis() * Vector3(input.x, 0, input.y)
	return direction.normalized() if direction.length() > 0.01 else Vector3.ZERO


func _forward() -> Vector3:
	var f := -model.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _normal_movement(delta: float) -> void:
	var direction := _input_direction()
	_update_sprint(direction != Vector3.ZERO, delta)

	var dodge_dir := _dodge_requested(direction)
	if is_on_floor() and dodge_dir != Vector3.INF and _try_dodge(Vector3(dodge_dir.x, 0.0, dodge_dir.z)):
		return
	if _try_start_swim():
		return
	if _grab_cooldown <= 0.0 and direction.dot(_forward()) > 0.5 and _try_attach_surface(is_on_floor()):
		return

	# Wedged on steep rock (falling but not moving): jump still works, pushing off it.
	_stuck_air = _stuck_air + delta if not is_on_floor() and get_real_velocity().length() < 0.3 else 0.0
	if _stuck_air > 0.3 and _pressed("jump"):
		var col := get_last_slide_collision()
		var away := Vector3(col.get_normal().x, 0.0, col.get_normal().z) if col else -_forward()
		velocity = away.normalized() * 3.0 + Vector3.UP * jump_velocity
		_stuck_air = 0.0
		_grab_cooldown = 0.5
		jumped.emit()
	elif not is_on_floor():
		velocity.y -= gravity * delta
		if velocity.y < 2.0 and _grab_cooldown <= 0.0:
			var ledge := _probe_ledge(global_position, _forward())
			if not ledge.is_empty():
				_start_hang(ledge)
				return
			if _try_attach_surface(false):
				return
	elif _pressed("interact") and _try_talk():
		return  # E (or A on a controller) next to someone / something
	elif (_pressed("jump") or _pressed("interact")) and Time.get_ticks_msec() - DialogueBox.closed_at < 300:
		return  # the press that just closed a conversation
	elif _pressed("jump") and stats.use_stamina(jump_stamina_cost):
		velocity.y = jump_velocity
		jumped.emit()

	var speed := run_speed
	if is_sprinting:
		speed = sprint_speed
	elif Input.is_action_pressed("walk"):
		speed = walk_speed
	if is_injured():
		# Hobbled: limping, or a pained jog when sprinting.
		speed = minf(speed, injured_sprint_speed if is_sprinting else injured_speed)
	var target := direction * speed * speed_scale * skill_speed * stats.status_product("move_scale")
	var accel := acceleration if is_on_floor() else acceleration * air_control
	velocity.x = lerpf(velocity.x, target.x, accel * delta)
	velocity.z = lerpf(velocity.z, target.z, accel * delta)

	if lock_facing and lock_target and is_instance_valid(lock_target):
		face_toward(lock_target.global_position, delta)
	elif direction != Vector3.ZERO:
		model.rotation.y = lerp_angle(model.rotation.y, _yaw_of(direction), turn_speed * delta)


func _update_sprint(moving: bool, delta: float, swimming := false) -> void:
	if _sprint_exhausted and stats.stamina >= sprint_restart_threshold:
		_sprint_exhausted = false
	if not moving or _sprint_exhausted or Input.is_action_pressed("walk"):
		_sprint_toggle = false
	# Keyboard: hold to sprint. Controller: tap to toggle.
	var held := Input.is_action_pressed("sprint") and not GameSettings.gamepad and not GameSettings.menu_open
	var wants := (held or _sprint_toggle) and moving and not _sprint_exhausted
	if wants and (is_on_floor() or swimming) or wants and is_sprinting:
		is_sprinting = stats.drain_stamina((swim_sprint_stamina_cost if swimming else sprint_stamina_cost) * delta)
		if not is_sprinting:
			_sprint_exhausted = true
			_sprint_toggle = false
	else:
		is_sprinting = false


# --- Combat actions -----------------------------------------------------------

## Starts a combat action (PlayerCombat drives it). Only from normal movement on the
## ground, or chaining from another action.
## `in_air`: allowed while airborne too (the Hearthstone, so a player stuck "falling" on
## some geometry can always get home).
func start_action(move_scale := 0.0, in_air := false) -> bool:
	if knocked_down or stats.status_flag("frozen"):
		return false  # on the ground / frozen solid: nothing until free
	if state == State.ACTION:
		action_move_scale = move_scale
		return true
	if state != State.NORMAL or not (is_on_floor() or in_air):
		return false
	state = State.ACTION
	action_move_scale = move_scale
	action_velocity = Vector3.ZERO
	is_sprinting = false
	return true


func end_action() -> void:
	action_velocity = Vector3.ZERO
	if state == State.ACTION:
		state = State.NORMAL


## Turns the character to face a point (smoothly unless `instant`).
func face_toward(point: Vector3, delta := 0.0) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var yaw := _yaw_of(dir.normalized())
	model.rotation.y = yaw if delta <= 0.0 else lerp_angle(model.rotation.y, yaw, turn_speed * delta)


## Knocked off your feet (a troll's ground smash, a dragon's tail; abilities.json /
## enemies.json "applies" with status "knockdown"): limp on the ground for `seconds`,
## thrown along `push`, then the getting_up clip. Can't act or dodge meanwhile; still
## takes hits. Dodging through the blow (i-frames) avoids it altogether.
const GET_UP_SPEED := 1.6
var knocked_down := false
var _down_left := 0.0
var _getting_up := 0.0


func knock_down(push: Vector3, seconds := 1.6) -> void:
	if knocked_down or state not in [State.NORMAL, State.ACTION]:
		return
	if state == State.ACTION:
		action_interrupted.emit()  # whatever was being done stops
	state = State.ACTION
	action_move_scale = 0.0
	action_velocity = Vector3.ZERO
	is_sprinting = false
	knocked_down = true
	_down_left = maxf(seconds, 0.3)
	_getting_up = 0.0
	_push = Vector3.ZERO
	if Ragdoll.start(character, push + Vector3.UP * 2.5) == null:
		action_animation.emit("death", 0.0, 0.1, 1.4)  # no ragdoll: fall over
	FloatingText.spawn(self, "Knocked down!", Color(1.0, 0.7, 0.35), 1.1)


func _knocked_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	if _getting_up > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		_getting_up -= delta
		if _getting_up <= 0.0:
			knocked_down = false
			end_action()
		return
	_down_left -= delta
	# The body (and the camera) follows where the limp body went.
	var hips = Ragdoll.hips_of(character)
	if hips is Vector3:
		velocity.x = ((hips as Vector3).x - global_position.x) * 6.0
		velocity.z = ((hips as Vector3).z - global_position.z) * 6.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
	if _down_left > 0.0:
		return
	if hips is Vector3:
		global_position = Vector3((hips as Vector3).x, global_position.y, (hips as Vector3).z)
	Ragdoll.stop(character)
	velocity = Vector3(0, velocity.y, 0)
	if character.has_animation("getting_up"):
		# Played quickly: back in the fight in about a second.
		action_animation.emit("getting_up", 0.0, 0.05, GET_UP_SPEED)
		_getting_up = minf(character.get_animation_length("getting_up") * 0.7 / GET_UP_SPEED, 1.4)
	else:
		_getting_up = 0.3


## Up again at once (respawning, travelling).
func _clear_knockdown() -> void:
	if knocked_down:
		knocked_down = false
		Ragdoll.stop(character)
		if state == State.ACTION:
			end_action()


## Pushed by a hit (m/s, flat). Only while on foot.
func apply_knockback(push: Vector3) -> void:
	if state in [State.NORMAL, State.ACTION]:
		_push = push * 0.6


func is_alive() -> bool:
	return state != State.DEAD


## Called by Combat.hit: dodging makes the player untouchable, blocking softens hits.
func modify_incoming_damage(amount: float, source: Node) -> float:
	if state == State.DEAD:
		return 0.0
	if is_invulnerable():
		var combat_node := get_node_or_null("PlayerCombat")
		if _dodge_time - iframe_start <= perfect_dodge_window:
			# Dodged at the last moment: time slows and a counter is ready.
			FloatingText.spawn(self, "Perfect dodge!", Color(0.7, 0.95, 1.0), 1.2)
			TimeFX.slow_motion(self, 0.9)
			if combat_node:
				combat_node.call("grant_counter")
		else:
			FloatingText.spawn(self, "Dodged", Color(0.8, 0.9, 1.0), 0.8)
		return 0.0
	var combat := get_node_or_null("PlayerCombat")
	if combat:
		return combat.modify_incoming_damage(amount, source)
	return amount


func _action_movement(delta: float) -> void:
	if knocked_down:
		_knocked_movement(delta)
		return
	var direction := _input_direction()
	var dodge_dir := _dodge_requested(direction)
	if is_on_floor() and dodge_dir != Vector3.INF and _try_dodge(Vector3(dodge_dir.x, 0.0, dodge_dir.z)):
		action_interrupted.emit()
		return
	if _try_start_swim():
		action_interrupted.emit()
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	var target := direction * run_speed * action_move_scale + action_velocity
	velocity.x = lerpf(velocity.x, target.x, acceleration * delta)
	velocity.z = lerpf(velocity.z, target.z, acceleration * delta)


func _on_died() -> void:
	if _dying:
		return
	_dying = true
	var d: Dictionary = Database.player.get("death", {})
	var reason := "died"
	var wait := 0.0
	if fatigue >= fatigue_max:
		reason = "drowned"
		wait = float(d.get("drown_wait", 0.6))
	elif state in [State.HANG, State.LEDGE_CLIMB, State.WALL_CLIMB, State.LADDER, State.SWIM]:
		wait = 0.3
	else:
		if state == State.ACTION:
			action_interrupted.emit()
		state = State.DEAD
		is_sprinting = false
		action_animation.emit("death", 0.0, 0.15, 1.0)
		wait = death_time
	# Fallen in a fight: choose to wait for a companion to revive you, or go back to camp.
	var camp_cfg: Dictionary = Database.player.get("camp", {})
	if reason == "died" and state == State.DEAD and bool(camp_cfg.get("death_choice", true)):
		await get_tree().create_timer(wait).timeout
		if not is_inside_tree() or state != State.DEAD:
			_dying = false
			return
		var has_camp := GameSession.active() and not (GameSession.data.get("camp", {}) as Dictionary).is_empty()
		var choice := DeathChoice.open(self, "Return to camp" if has_camp or has_meta("camp") else "Return home", can_be_revived)
		GameSettings.menu_open = true
		var waiting: bool = await choice.chose
		while waiting:
			# Stay down until someone revives you or you give up.
			waiting = await choice.chose if is_instance_valid(choice) else false
			if state != State.DEAD:
				_dying = false
				return
		DeathChoice.close()
		GameSettings.menu_open = false
		if state != State.DEAD:
			_dying = false
			return
		wait = 0.0
	# The screen fades to black, home, then back in.
	var fade_out := float(d.get("fade_out", 1.2))
	await get_tree().create_timer(maxf(wait - fade_out * 0.5, 0.0)).timeout
	ScreenFade.to_black(self, fade_out)
	await get_tree().create_timer(fade_out + 0.1).timeout
	_dying = false
	if not is_inside_tree():
		return
	if state == State.DEAD or reason == "drowned" or stats.is_dead():
		_respawn(reason)
	if not is_inside_tree() or _going_home:
		return
	await get_tree().create_timer(0.2).timeout
	ScreenFade.clear(self, float(d.get("fade_in", 1.0)))


## Someone could come and revive you: a follower that's up, or another player (co-op).
func can_be_revived() -> bool:
	for f in get_tree().get_nodes_in_group("followers"):
		if f.get("leader") == self and Combat.is_alive(f):
			return true
	return Net.active and not Net.peers.is_empty()


## True while dead and waiting for help (followers come to revive).
func awaiting_help() -> bool:
	return state == State.DEAD and DeathChoice.is_waiting()


## A companion (or another player) brings you back where you fell: some health back,
## you get up, the choice panel goes away.
func revive(by: Node = null) -> void:
	if state != State.DEAD:
		return
	var cfg: Dictionary = Database.player.get("camp", {})
	stats.health = maxf(stats.max_health * float(cfg.get("revive_health", 0.4)), 1.0)
	stats.mana = maxf(stats.mana, stats.max_mana * float(cfg.get("revive_health", 0.4)))
	stats.emit_all()
	state = State.NORMAL
	_dying = false
	DeathChoice.close()
	GameSettings.menu_open = false
	action_animation.emit("getting_up" if character.has_animation("getting_up") else "idle", 0.0, 0.2, 1.0)
	Effects.heal_glow(self, 1.5)
	var who := String(by.get("display_name")) if by and by.get("display_name") != null else ""
	if who == "" and by:
		var st := Combat.stats_of(by)
		who = st.display_name if st else ""
	GameLog.post("%s revived you." % who if who != "" else "You were revived.", Color(0.7, 1.0, 0.7))
	respawned.emit("revived")


# --- Dodge -------------------------------------------------------------------

func _try_dodge(direction: Vector3) -> bool:
	if _dodge_cooldown_left > 0.0 or not stats.use_stamina(dodge_stamina_cost):
		return false

	var anim := "dodge_back"
	if lock_facing and lock_on_hops > 0.5:
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
func _probe_ledge(feet: Vector3, forward: Vector3, any_edge := false) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var chest := feet + Vector3.UP * 1.4
	var wall := _ray(space, chest, chest + forward * 0.8)
	if wall.is_empty() or absf(wall.normal.y) > 0.3:
		return {}
	if not any_edge and grab_any_ledge < 0.5 and not _marked(wall.collider as Node, "ledge"):
		return {}
	if ClimbLock.blocked_at(wall.position, true):
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


## Whether a surface is marked for a kind of climbing: "ledge" (hang / shimmy), "wall"
## (climb up and down) or "ladder". By group or by name (the node or up to 3 parents).
static func _marked(node: Node, kind: String) -> bool:
	var groups: Array = {"ledge": ["grabbable", "climbable"], "wall": ["climbable"], "ladder": ["ladder"]}[kind]
	var words: Array = {"ledge": ["_grab", "_shimmy", "_climb"], "wall": ["_climb"], "ladder": ["_ladder"]}[kind]
	var walk := node
	for i in 4:
		if walk == null:
			break
		for g: String in groups:
			if walk.is_in_group(g):
				return true
		var n := String(walk.name).to_lower()
		for w: String in words:
			if n.contains(w):
				return true
		walk = walk.get_parent()
	return false


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
	# Fingertips (character space, facing -Z) onto the edge. Character +Z points out of the wall.
	var hands: Vector3 = character.measure("hanging_idle", 0.0).get("hands", Vector3(0, 2.38, -0.05))
	return edge - _ledge_normal * (hands.z - hang_edge_gap) - Vector3.UP * hands.y


func _hang_movement(delta: float) -> void:
	_hang_time += delta
	if not _hop_anim.is_empty():
		_hop_movement(delta)
		return
	if _pressed("jump") or (Input.is_action_pressed("move_forward") and _hang_time > 0.35):
		if _try_climb_up():
			return
	if Input.is_action_pressed("move_back") or _pressed("walk"):
		_drop_from_ledge()
		return
	var side := Input.get_axis("move_left", "move_right")
	if absf(side) > 0.5:
		_try_hop(signf(side))


func _try_hop(dir: float) -> void:
	# A smooth shimmy if there's a clip for it; otherwise the bigger hop.
	var anim := "hanging_shimmy_right" if dir > 0.0 else "hanging_shimmy_left"
	if character.get_root_motion(anim).is_empty():
		anim = "hanging_hop_right" if dir > 0.0 else "hanging_hop_left"
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
	var length := character.get_animation_length("hanging_climb_up")
	var hands: Vector3 = character.measure("hanging_climb_up", 0.0).get("hands", Vector3(0, 1.4, -0.45))
	var feet: Vector3 = character.measure("hanging_climb_up", length).get("toes", Vector3(0, 2.0, -0.59))
	# Where the clip's feet end up past the edge, but far enough in for the body to fit.
	var target := _ledge_edge - _ledge_normal * maxf(climb_onto_distance, hands.z - feet.z)
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
	_climb_duration = length
	# The clip ends with its feet higher than its hands start. Place the body so the
	# feet finish exactly on the ledge, and raise the model at the start so the hands
	# begin on the edge; that lift eases away over the climb.
	var start := _ledge_edge - _ledge_normal * hands.z
	start.y = _ledge_edge.y - feet.y
	global_position = start
	_climb_lift = feet.y - hands.y
	model.position = Vector3(0, _climb_lift, 0)
	state = State.LEDGE_CLIMB
	action_animation.emit("hanging_climb_up", 0.0, 0.15, 1.0)
	return true


func _ledge_climb_movement(delta: float) -> void:
	_climb_time += delta
	var t := clampf(_climb_time / _climb_duration, 0.0, 1.0)
	model.position = Vector3(0, _climb_lift * (1.0 - smoothstep(0.0, 0.85, t)), 0)
	if _climb_time >= _climb_duration - 0.05:
		model.position = Vector3.ZERO
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


# --- Wall and ladder climbing ------------------------------------------------

## Attaches to a climbable wall (only while airborne) or a ladder in front.
func _try_attach_surface(on_ground: bool) -> bool:
	var space := get_world_3d().direct_space_state
	var chest := global_position + Vector3.UP * 1.2
	var hit := _ray(space, chest, chest + _forward() * 0.7)
	if hit.is_empty() or absf(hit.normal.y) > 0.3:
		return false
	var node := hit.collider as Node
	var ladder := _marked(node, "ladder")
	if not ladder and not _marked(node, "wall"):
		return false
	if ClimbLock.blocked_at(hit.position, true):
		return false
	if on_ground and not ladder:
		return false  # walls need a jump; ladders you just walk into
	_surface_normal = Vector3(hit.normal.x, 0, hit.normal.z).normalized()
	state = State.LADDER if ladder else State.WALL_CLIMB
	velocity = Vector3.ZERO
	is_sprinting = false
	model.rotation.y = _yaw_of(-_surface_normal)
	if ladder:
		_ladder_distance = _measure_ladder_distance()
	var dist := _ladder_distance if ladder else wall_climb_distance
	var pos: Vector3 = hit.position + _surface_normal * dist
	pos.y = global_position.y - ((ladder_feet if ladder else wall_climb_feet) if on_ground else 0.0)
	global_position = pos
	character.play("climbing_ladder" if ladder else "climbing_up_wall", 0.2, 0.0)
	return true


func _climb_movement(delta: float) -> void:
	var ladder := state == State.LADDER
	var feet := ladder_feet if ladder else wall_climb_feet
	var space := get_world_3d().direct_space_state

	if _pressed("jump"):
		_jump_off_surface()
		return
	if _pressed("walk"):
		_let_go()
		return

	var climb := Input.get_axis("move_back", "move_forward")

	# Reached the top: pull up onto it.
	if climb > 0.0:
		var ledge := _probe_ledge(global_position, -_surface_normal)
		if not ledge.is_empty() and ledge.edge.y - global_position.y < (2.4 if ladder else 2.2):
			_start_hang(ledge)
			_try_climb_up()
			return

	# Reached the bottom: step off.
	if climb < 0.0:
		var foot := global_position + Vector3.UP * feet
		var ground := _ray(space, foot + Vector3.UP * 0.1, foot - Vector3.UP * 0.2)
		if not ground.is_empty():
			global_position.y = ground.position.y
			state = State.NORMAL
			_grab_cooldown = 0.4
			return

	# Stay stuck to the surface; let go if it ends.
	var chest := global_position + Vector3.UP * (feet + 0.8)
	var hit := _ray(space, chest, chest - _surface_normal * 1.2)
	if hit.is_empty() or not _marked(hit.collider as Node, "ladder" if ladder else "wall"):
		_let_go()
		return
	_surface_normal = Vector3(hit.normal.x, 0, hit.normal.z).normalized()
	var dist := _ladder_distance if ladder else wall_climb_distance
	var flat: Vector3 = hit.position + _surface_normal * dist
	global_position = Vector3(flat.x, global_position.y, flat.z)
	model.rotation.y = _yaw_of(-_surface_normal)

	var speed := ladder_speed if ladder else wall_climb_speed
	global_position.y += climb * speed * delta
	var rate := speed / (ladder_anim_rate if ladder else wall_climb_anim_rate)
	if ladder:
		character.play("climbing_ladder", 0.2, climb * rate)  # plays backwards going down
	elif climb > 0.0:
		character.play("climbing_up_wall", 0.2, rate)
	elif climb < 0.0:
		character.play("climbing_down_wall", 0.2, rate)
	else:
		character.play(character.current_animation(), 0.2, 0.0)  # hold still on the wall


## Distance from the feet origin to the ladder so the fingertips meet the rungs
## (averaged over the climb cycle).
func _measure_ladder_distance() -> float:
	var length := character.get_animation_length("climbing_ladder")
	if length <= 0.0:
		return 0.35
	var total := 0.0
	for i in 4:
		total += character.measure("climbing_ladder", length * i / 4.0).get("hands", Vector3(0, 0, -0.35)).z
	return -total / 4.0


func _jump_off_surface() -> void:
	velocity = _surface_normal * 3.5 + Vector3.UP * 4.0
	model.rotation.y = _yaw_of(_surface_normal)
	global_position += _surface_normal * 0.15
	state = State.NORMAL
	_grab_cooldown = 0.6
	jumped.emit()


func _let_go() -> void:
	global_position += _surface_normal * 0.15
	velocity = Vector3.ZERO
	state = State.NORMAL
	_grab_cooldown = 0.6
	action_animation.emit("falling_loop", 0.0, 0.2, 1.0)


# --- Swimming ----------------------------------------------------------------

## Water containing a point: a WaterVolume, or the ocean below sea level. Null if dry.
func _water_at(point: Vector3) -> Node3D:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = WATER_MASK
	for hit in get_world_3d().direct_space_state.intersect_point(query, 4):
		if hit.collider is WaterVolume:
			return hit.collider
	var ocean := get_tree().get_first_node_in_group("ocean") as Ocean
	if ocean and point.y < ocean.surface_height():
		return ocean
	return null


func _is_lava(water) -> bool:
	return water is WaterVolume and (water as WaterVolume).lava


## Depth of water at the character's spot (surface to floor), capped at 10 m.
func _water_depth(water) -> float:
	var surface: float = water.surface_height()
	var top := Vector3(global_position.x, surface, global_position.z)
	var floor_hit := _ray(get_world_3d().direct_space_state, top, top - Vector3.UP * 10.0)
	return surface - floor_hit.position.y if not floor_hit.is_empty() else 10.0


func _try_start_swim() -> bool:
	var water = _water_at(global_position + Vector3.UP * 1.0)
	if water == null:
		return false
	if water.surface_height() - global_position.y < swim_depth or _water_depth(water) < swim_depth:
		return false
	_water = water
	state = State.SWIM
	is_sprinting = false
	velocity.y *= 0.3  # splash down softly
	return true


func _swim_movement(delta: float) -> void:
	if _water == null or not is_instance_valid(_water):
		state = State.NORMAL
		return
	var direction := _input_direction()
	_update_sprint(direction != Vector3.ZERO, delta, true)
	var target := direction * (swim_sprint_speed if is_sprinting else swim_speed) * speed_scale
	if _is_lava(_water):
		target *= lava_speed
	# Rivers carry you along.
	var current = _water.get("flow")
	if current is Vector3:
		target += current
	velocity.x = lerpf(velocity.x, target.x, 3.0 * delta)
	velocity.z = lerpf(velocity.z, target.z, 3.0 * delta)
	if direction != Vector3.ZERO:
		model.rotation.y = lerp_angle(model.rotation.y, _yaw_of(direction), turn_speed * 0.5 * delta)

	# Float at the surface: higher when treading, lower when stroking forward.
	var h_speed := Vector2(velocity.x, velocity.z).length()
	var stroke := clampf(h_speed / swim_speed, 0.0, 1.0)
	var target_y: float = _water.surface_height() - lerpf(tread_depth, stroke_depth, stroke)
	velocity.y = (target_y - global_position.y) * 4.0

	if stroke > 0.3:
		character.play("swimming", 0.4, clampf(h_speed / swim_speed, 0.6, 1.8))
	else:
		character.play("treading_water", 0.4)

	# Climb out at an edge.
	if _pressed("jump"):
		var feet := Vector3(global_position.x, _water.surface_height() - tread_depth, global_position.z)
		var ledge := _probe_ledge(feet, _forward(), true)
		if not ledge.is_empty():
			global_position = feet
			_start_hang(ledge)
			_try_climb_up()
			return

	# Left the water, or it got shallow enough to stand.
	var still_in := _water_at(Vector3(global_position.x, _water.surface_height() - 0.2, global_position.z)) != null
	if not still_in or _water_depth(_water) < swim_depth - 0.1:
		state = State.NORMAL


# --- Survival: fatigue, kill floor, respawn -----------------------------------

func _update_survival(delta: float) -> void:
	# Fall out of the world: back to safe ground.
	if global_position.y < kill_height:
		_respawn("fell")
		return

	# Remember where the player last stood on dry ground.
	_safe_timer += delta
	if state == State.NORMAL and is_on_floor() and _safe_timer > 0.5:
		_safe_timer = 0.0
		if _water_at(global_position + Vector3.UP * 0.5) == null:
			_last_safe = global_position

	# Lava burns while any of the body is in it (wading or swimming).
	var molten = _water_at(global_position + Vector3.UP * 0.15)
	if _is_lava(molten) and not stats.is_dead():
		stats.take_damage(stats.max_health * lava_damage * delta)
		if lava_burn_seconds > 0.0:
			stats.add_status("burning", lava_burn_seconds)

	# Fatigue: swimming far out at sea.
	var far := false
	if state == State.SWIM and _water is Ocean:
		var ocean := _water as Ocean
		far = ocean.distance_from_land(global_position) > ocean.fatigue_distance
	var before := fatigue
	if far:
		fatigue = minf(fatigue + delta, fatigue_max)
	else:
		fatigue = maxf(fatigue - delta * fatigue_recovery, 0.0)
	if fatigue != before:
		fatigue_changed.emit(fatigue, fatigue_max)
	if fatigue >= fatigue_max:
		stats.take_damage(stats.max_health * fatigue_damage * delta)


func _respawn(reason: String) -> void:
	_clear_knockdown()
	var spot := _last_safe + Vector3.UP * 0.3
	if reason in ["died", "drowned"]:
		# Dying: penalties, then home (where the hearthstone goes).
		var progress := get_node_or_null("Progress")
		if progress:
			progress.call("apply_death_penalty")
		# The last campfire you used, else home.
		var which := "home"
		var home: Dictionary = GameSession.data.get("home", {}) if GameSession.active() else {}
		var camp: Dictionary = GameSession.data.get("camp", {}) if GameSession.active() else (get_meta("camp", {}) as Dictionary)
		if not camp.is_empty():
			home = camp
			which = "camp"
		var scene := get_tree().current_scene
		var here := scene != null and String(home.get("scene", "")) == scene.scene_file_path
		var p: Array = home.get("position", [])
		if here and p.size() == 3:
			spot = Vector3(p[0], p[1], p[2]) + Vector3.UP * 0.3
		elif not home.is_empty() and not Net.active and GameSession.active():
			stats.restore()
			_going_home = true
			# Home is in another level: it fades in from black there.
			GameSession.travel_home.call_deferred(Color.BLACK, 0.0, float(Database.player.get("death", {}).get("fade_in", 1.0)), which)
	global_position = spot
	velocity = Vector3.ZERO
	state = State.NORMAL
	model.position = Vector3.ZERO
	_hop_anim = ""
	_water = null
	fatigue = 0.0
	fatigue_changed.emit(fatigue, fatigue_max)
	stats.restore()
	action_animation.emit("idle", 0.0, 0.0, 1.0)
	respawned.emit(reason)


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
