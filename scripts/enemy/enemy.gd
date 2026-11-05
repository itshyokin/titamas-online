class_name Enemy
extends CharacterBody3D
## A basic melee enemy. Wanders near its spawn point; chases players who come close
## or hit it; attacks with a telegraphed swing (dodge or block it); gives up and
## walks home if dragged too far (healing to full); dies, then respawns later.
## The Stats child holds its name, level and health.

enum AI { IDLE, CHASE, ATTACK, STAGGER, RETURN, DEAD }

@export_group("Behaviour")
## Players closer than this are noticed.
@export var aggro_radius := 12.0
## Too far from home (m) and it gives up the chase.
@export var leash_distance := 35.0
@export var wander_radius := 5.0
@export var walk_speed := 1.4
@export var run_speed := 4.0
@export var turn_speed := 8.0

@export_group("Attack")
@export var attack_power := 9.0
@export var attack_range := 2.0
@export var attack_cooldown := 1.6
@export var attack_animation := "attack_light_1"
## Slower than the player's version, so the wind-up can be seen and dodged.
@export var attack_animation_speed := 0.75
## Seconds into the clip (at speed 1) when the hit lands.
@export var attack_hit_time := 0.32
@export var attack_arc := 110.0

@export_group("Death")
## Seconds before the body disappears, and before it comes back.
@export var corpse_time := 6.0
@export var respawn_time := 25.0

@onready var stats: Stats = $Stats
@onready var character: CharacterModel = $Model/Character
@onready var model: Node3D = $Model

var ai := AI.IDLE
var target: Node3D = null

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _home := Vector3.ZERO
var _wander_to := Vector3.ZERO
var _wait := 0.0
var _attack_time := 0.0
var _attack_hit := false
var _cooldown := 0.0
var _stagger := 0.0
var _plate: Nameplate
var _settled := false  # ground found under the spawn point
var _swing_sound: AudioStream = preload("res://assets/audio/combat/swing_1.ogg")


func _ready() -> void:
	add_to_group(Combat.GROUP)
	_home = global_position
	_wander_to = _home
	_wait = randf_range(0.5, 3.0)
	stats.damaged.connect(_on_damaged)
	stats.died.connect(_on_died)
	Combat.show_numbers(self)
	_plate = Nameplate.attach(self)
	_equip.call_deferred()


func _equip() -> void:
	character.attach_to_hand(WeaponModels.sword())


func aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


func _physics_process(delta: float) -> void:
	if not _settled:
		# Wait for the ground (chunks stream in) before moving.
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 60.0, global_position + Vector3.DOWN * 100.0, 1)
		var ground := get_world_3d().direct_space_state.intersect_ray(q)
		if ground.is_empty():
			return
		_settled = true
		global_position = ground.position + Vector3.UP * 0.05
		_home = global_position
		_wander_to = _home
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.5
	var move := Vector3.ZERO
	match ai:
		AI.IDLE:
			move = _idle(delta)
		AI.CHASE:
			move = _chase(delta)
		AI.ATTACK:
			_attacking(delta)
		AI.STAGGER:
			_stagger -= delta
			if _stagger <= 0.0:
				ai = AI.CHASE
		AI.RETURN:
			move = _return_home(delta)
		AI.DEAD:
			pass
	velocity.x = lerpf(velocity.x, move.x, 10.0 * delta)
	velocity.z = lerpf(velocity.z, move.z, 10.0 * delta)
	if move.length() > 0.1:
		_face(global_position + move, delta)
	move_and_slide()
	_animate()


# --- States -------------------------------------------------------------------

func _idle(delta: float) -> Vector3:
	var seen := _nearest_player(aggro_radius)
	if seen:
		_engage(seen)
		return Vector3.ZERO
	_wait -= delta
	if _wait > 0.0:
		return Vector3.ZERO
	var to := _wander_to - global_position
	to.y = 0.0
	if to.length() < 0.4:
		_wait = randf_range(2.0, 5.0)
		var a := randf() * TAU
		_wander_to = _home + Vector3(cos(a), 0, sin(a)) * randf() * wander_radius
		return Vector3.ZERO
	return to.normalized() * walk_speed


func _chase(_delta: float) -> Vector3:
	if not _target_valid():
		_give_up()
		return Vector3.ZERO
	if global_position.distance_to(_home) > leash_distance:
		_give_up()
		return Vector3.ZERO
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() <= attack_range:
		if _cooldown <= 0.0:
			_start_attack()
		else:
			_face(target.global_position, get_physics_process_delta_time())
		return Vector3.ZERO
	return to.normalized() * run_speed


func _start_attack() -> void:
	ai = AI.ATTACK
	_attack_time = 0.0
	_attack_hit = false
	_face(target.global_position, 0.0)
	character.play_from(attack_animation, 0.0, 0.1, attack_animation_speed)


func _attacking(delta: float) -> void:
	_attack_time += delta * attack_animation_speed
	if not _attack_hit and _target_valid():
		_face(target.global_position, delta * 0.5)  # tracks slowly, so side-steps work
	if not _attack_hit and _attack_time >= attack_hit_time - 0.12 and _attack_time - delta * attack_animation_speed < attack_hit_time - 0.12:
		Combat.play_sound(self, _swing_sound, -6.0, 0.85)
	if not _attack_hit and _attack_time >= attack_hit_time:
		_attack_hit = true
		if _target_valid():
			var to := target.global_position - global_position
			var fwd := -model.global_basis.z
			to.y = 0.0
			if to.length() <= attack_range + 0.6 and rad_to_deg(fwd.angle_to(to.normalized())) <= attack_arc * 0.5:
				Combat.hit(self, target, attack_power)
	if _attack_time >= character.get_animation_length(attack_animation):
		_cooldown = attack_cooldown * randf_range(0.8, 1.2)
		ai = AI.CHASE


func _return_home(delta: float) -> Vector3:
	var to := _home - global_position
	to.y = 0.0
	if to.length() < 0.6:
		ai = AI.IDLE
		_wait = randf_range(1.0, 3.0)
		return Vector3.ZERO
	stats.heal(stats.max_health * 0.5 * delta)
	return to.normalized() * run_speed


## Interrupts the wind-up of an attack (heavy hits).
func stagger() -> void:
	if ai == AI.DEAD:
		return
	ai = AI.STAGGER
	_stagger = 0.7
	character.play_from("hit_react", 0.0, 0.05, 0.8)
	FloatingText.spawn(self, "Staggered", Color(1.0, 0.8, 0.4), 0.8)


func _engage(who: Node3D) -> void:
	if ai == AI.DEAD or ai == AI.RETURN:
		return
	target = who
	var s := Combat.stats_of(who)
	if s and not s.died.is_connected(_on_target_died):
		s.died.connect(_on_target_died)
	if ai == AI.IDLE:
		ai = AI.CHASE


func _give_up() -> void:
	target = null
	ai = AI.RETURN


func _target_valid() -> bool:
	return target != null and is_instance_valid(target) and Combat.is_alive(target) \
		and (not target.has_method("is_alive") or target.is_alive())


func _nearest_player(radius: float) -> Node3D:
	var best: Node3D = null
	var best_d := radius
	for n in Combat.enemies_near(self, global_position, radius):
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var d := n.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


# --- Events -------------------------------------------------------------------

func _on_damaged(_amount: float, source: Node, _crit: bool) -> void:
	if ai == AI.RETURN or ai == AI.DEAD:
		return
	if source is Node3D and target == null:
		_engage(source)
	if ai == AI.CHASE and _cooldown > 0.0:
		character.play_from("hit_react", 0.0, 0.05, 1.0)


func _on_target_died() -> void:
	if ai != AI.DEAD:
		_give_up()


func _on_died() -> void:
	ai = AI.DEAD
	target = null
	collision_layer = 0
	velocity = Vector3.ZERO
	character.play_from("death", 0.0, 0.15, 1.0)
	await get_tree().create_timer(corpse_time).timeout
	model.visible = false
	await get_tree().create_timer(maxf(respawn_time - corpse_time, 0.0)).timeout
	_respawn()


func _respawn() -> void:
	global_position = _home
	velocity = Vector3.ZERO
	stats.restore()
	collision_layer = 4
	model.visible = true
	ai = AI.IDLE
	_wait = randf_range(1.0, 3.0)
	character.play("idle", 0.0)


# --- Animation ----------------------------------------------------------------

func _face(point: Vector3, delta: float) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var yaw := atan2(-dir.x, -dir.z)
	model.rotation.y = yaw if delta <= 0.0 else lerp_angle(model.rotation.y, yaw, turn_speed * delta)


func _animate() -> void:
	if ai == AI.ATTACK or ai == AI.DEAD or ai == AI.STAGGER:
		return
	var current := character.current_animation()
	if current == "hit_react" and character.animation_position() < 0.4:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.3:
		character.play("idle_armed" if target else "idle", 0.25)
	elif speed < 2.6:
		character.play("walking", 0.2, clampf(speed / 1.4, 0.6, 1.5))
	else:
		character.play("running", 0.2, clampf(speed / 4.5, 0.8, 1.4))
