class_name PlayerAnimator
extends Node
## Picks the character's animation from the player's movement each physics frame.
## Lives under Player; drives the CharacterModel at Player/Model/Character.

## Horizontal speed (m/s) the walk and run cycles were authored at; used to match feet to ground.
@export var walk_anim_speed := 1.4
@export var run_anim_speed := 4.5
## Below this speed the character idles; above walk_max it runs.
@export var idle_max := 0.3
@export var walk_max := 2.6
## Jump clip timing (seconds into "jumping"): take-off and touch-down.
@export var jump_takeoff := 0.62
@export var jump_touchdown := 1.2
## Falling longer than this plays the heavy landing.
@export var hard_landing_time := 0.6

@onready var player: PlayerController = get_parent()
@onready var character: CharacterModel = get_node("../Model/Character")

var _air_time := 0.0
var _was_on_floor := true
var _landing_lock := 0.0
var _jump_air := 0.0  # expected airtime of the current jump; 0 when not jumping


func _ready() -> void:
	player.jumped.connect(_on_jumped)
	player.dodged.connect(_on_dodged)


func _physics_process(delta: float) -> void:
	var h_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var on_floor := player.is_on_floor()
	if player.state != PlayerController.State.NORMAL:
		# Special moves play their own animations (started by signals).
		_was_on_floor = on_floor
		_air_time = 0.0
		_landing_lock = 0.0
		return

	if on_floor:
		if not _was_on_floor:
			_on_landed(h_speed)
		_air_time = 0.0
		if _landing_lock > 0.0 and h_speed < walk_max:
			_landing_lock -= delta  # let the landing finish unless the player runs off
		else:
			_landing_lock = 0.0
			_ground_animation(h_speed)
	else:
		_air_time += delta
		var anim := character.current_animation()
		if anim == "jumping":
			if _air_time > _jump_air + 0.15:  # fell further than a normal jump
				character.play("falling_loop", 0.3)
		elif _air_time > 0.25 and player.velocity.y < 0.0:
			character.play("falling_loop", 0.25)
	_was_on_floor = on_floor


func _ground_animation(h_speed: float) -> void:
	if h_speed < idle_max:
		character.play("idle", 0.25)
	elif h_speed < walk_max:
		character.play("walking", 0.2, clampf(h_speed / walk_anim_speed, 0.6, 1.6))
	else:
		character.play("running", 0.2, clampf(h_speed / run_anim_speed, 0.8, 1.6))


func _on_jumped() -> void:
	# Skip the clip's crouch and stretch its airborne part over the physics jump.
	_jump_air = 2.0 * player.jump_velocity / player.gravity
	var speed := (jump_touchdown - jump_takeoff) / _jump_air
	character.play_from("jumping", jump_takeoff, 0.1, speed)


func _on_dodged(anim: String, start_time: float) -> void:
	_jump_air = 0.0
	character.play_from(anim, start_time, 0.08)


func _on_landed(h_speed: float) -> void:
	var from_jump := _jump_air > 0.0 and _air_time < _jump_air + 0.4
	_jump_air = 0.0
	if h_speed >= walk_max:
		return  # keep running through the landing
	if from_jump:
		character.play_from("jumping", jump_touchdown, 0.1)
		_landing_lock = 0.35
	elif _air_time >= hard_landing_time:
		character.play_from("falling_land", 0.0, 0.1)
		_landing_lock = 0.45
