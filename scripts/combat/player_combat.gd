class_name PlayerCombat
extends Node
## The player's fighting: light combo (left mouse), heavy attack (E), block (hold Q),
## and spells on the number keys. Lives under Player, next to Targeting.
## Abilities are data (Ability resources); this node runs their timing.

signal cast_started(ability: Ability, duration: float)
## `ok` is false when the cast was interrupted.
signal cast_finished(ability: Ability, ok: bool)
signal combat_changed(in_combat: bool)
## Short feedback for the HUD ("Not enough mana", "Out of range").
signal notice(text: String)

## Light attacks, in combo order: pressing attack again in time plays the next one.
@export var light_combo: Array[Ability] = [
	preload("res://data/abilities/slash_1.tres"),
	preload("res://data/abilities/slash_2.tres"),
]
@export var heavy_attack: Ability = preload("res://data/abilities/heavy_strike.tres")
## Spells on keys 1, 2, ...
@export var spells: Array[Ability] = [
	preload("res://data/abilities/firebolt.tres"),
	preload("res://data/abilities/mend.tres"),
]

@export_group("Block")
## Share of damage a block stops (hits from the front only).
@export_range(0.0, 1.0) var block_reduction := 0.75
@export var block_stamina_per_hit := 15.0
@export var block_arc := 150.0

@export_group("Combat state")
## Seconds after the last attack or hit before the weapon is put away.
@export var combat_linger := 6.0
## Lunge towards a target this far away (m) when attacking.
@export var lunge_range := 6.5

@onready var player: PlayerController = get_parent()
@onready var targeting: Targeting = get_node("../Targeting")
@onready var stats: Stats = get_node("../Stats")
@onready var character: CharacterModel = get_node("../Model/Character")
@onready var animator: PlayerAnimator = get_node("../PlayerAnimator")

var in_combat := false

var _current: Ability = null   # attack or spell release playing now
var _time := 0.0
var _hit_done := false
var _swing_played := false
var _queued: Ability = null
var _target: Node3D = null
var _lunge := Vector3.ZERO

var _casting: Ability = null
var _cast_left := 0.0
var _cast_target: Node3D = null
var _hand_glow: Node3D = null

var _blocking := false
var _cooldowns := {}  # Ability -> seconds left
var _combat_timer := 0.0
var _hand_weapon: Node3D
var _back_weapon: Node3D
var _attack_pressed := false


func _ready() -> void:
	player.action_interrupted.connect(_on_interrupted)
	player.respawned.connect(func(_reason: String) -> void: _cancel_all(); _set_combat(false))
	stats.damaged.connect(func(_a: float, _s: Node, _c: bool) -> void: _enter_combat())
	Combat.show_numbers(player)
	_equip_weapon.call_deferred()


func _equip_weapon() -> void:
	_hand_weapon = WeaponModels.sword()
	character.attach_to_hand(_hand_weapon)
	# Sheathed across the back: hilt over the right shoulder, blade down to the left hip.
	_back_weapon = WeaponModels.sword()
	var spine := character.bone_rest_position("mixamorig_Spine2")
	var blade := Vector3(-0.5, -0.86, 0).normalized()
	var flat := Vector3(0, 0, 1)
	var basis := Basis(blade.cross(flat).normalized(), blade, flat)
	character.attach_to_bone(_back_weapon, "mixamorig_Spine2", Transform3D(basis, spine + Vector3(0.16, 0.22, 0.17)))
	_show_weapon()


func _show_weapon() -> void:
	if _hand_weapon:
		_hand_weapon.visible = in_combat
		_back_weapon.visible = not in_combat
	animator.idle_animation = "idle_armed" if in_combat else "idle"


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		# Clicking an enemy selects it; the click is also an attack.
		if event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			targeting.click_select(event.position)
		_attack_pressed = true


func _physics_process(delta: float) -> void:
	for ab: Ability in _cooldowns.keys():
		_cooldowns[ab] -= delta
		if _cooldowns[ab] <= 0.0:
			_cooldowns.erase(ab)
	if in_combat:
		_combat_timer -= delta
		if _combat_timer <= 0.0 and _current == null and _casting == null and not _blocking:
			_set_combat(false)

	var attack := _attack_pressed
	_attack_pressed = false
	if player.state != PlayerController.State.NORMAL and player.state != PlayerController.State.ACTION:
		return

	if _casting:
		_update_cast(delta)
	elif _current:
		_update_action(delta)
	elif _blocking:
		_update_block(delta)

	# New input.
	var busy := _casting != null or (_current != null and _time < _current.recovery_time)
	if attack:
		var next: Ability = light_combo[0]
		if _current and light_combo.has(_current) and _hit_done:
			next = light_combo[(light_combo.find(_current) + 1) % light_combo.size()]
		if busy or _blocking:
			if _current and not _casting:
				_queued = next  # chain into the next swing when this one allows
		else:
			_start(next)
	elif Input.is_action_just_pressed("heavy_attack"):
		if busy:
			_queued = heavy_attack
		else:
			_start(heavy_attack)
	elif Input.is_action_pressed("block") and not busy and not _blocking:
		_start_block()
	else:
		for i in spells.size():
			if Input.is_action_just_pressed("ability_%d" % (i + 1)) and not busy:
				_start(spells[i])
				break


# --- Abilities ---------------------------------------------------------------

func cooldown_left(ab: Ability) -> float:
	return _cooldowns.get(ab, 0.0)


func can_afford(ab: Ability) -> bool:
	return stats.mana >= ab.mana_cost and stats.stamina >= ab.stamina_cost


## The keys and abilities on the action bar, in order.
func action_bar() -> Array:
	var out := [["LMB", light_combo[0]], ["E", heavy_attack]]
	for i in spells.size():
		out.append([str(i + 1), spells[i]])
	return out


func is_blocking() -> bool:
	return _blocking


func _start(ab: Ability) -> bool:
	if ab == null:
		return false
	if cooldown_left(ab) > 0.0:
		return false
	if stats.mana < ab.mana_cost:
		notice.emit("Not enough mana")
		return false
	if stats.stamina < ab.stamina_cost:
		notice.emit("Too tired")
		return false

	var target: Node3D = null
	match ab.delivery:
		Ability.Delivery.MELEE:
			target = targeting.pick_for_attack(lunge_range + ab.reach)
		Ability.Delivery.PROJECTILE:
			target = targeting.pick_for_attack(ab.reach)
			if target == null:
				notice.emit("Out of range" if targeting.has_target() else "No target")
				return false
		Ability.Delivery.HEAL_OVER_TIME:
			target = player  # allies come with co-op

	if _blocking:
		_end_block()
	if not player.start_action(0.0 if ab.cast_time > 0.0 else ab.move_scale):
		return false
	if ab.mana_cost > 0.0:
		stats.use_mana(ab.mana_cost)
	if ab.stamina_cost > 0.0:
		stats.use_stamina(ab.stamina_cost)
	_enter_combat()
	_target = target
	if target and target != player:
		player.face_toward(target.global_position)

	if ab.cast_time > 0.0:
		_casting = ab
		_cast_left = ab.cast_time
		_cast_target = target
		player.action_animation.emit("cast_channel", 0.0, 0.2, 1.0)
		_hand_glow = Effects.hand_glow(ab.projectile_color)
		character.attach_to_hand(_hand_glow)
		if ab.sounds.size() > 0:
			Combat.play_sound(player, ab.sounds[0], -6.0, 0.8)
		cast_started.emit(ab, ab.cast_time)
		return true
	_begin_release(ab)
	return true


## Plays the ability's clip; the effect lands at its hit_time.
func _begin_release(ab: Ability) -> void:
	_current = ab
	_time = 0.0
	_hit_done = false
	_swing_played = false
	_queued = null
	if ab.cooldown > 0.0:
		_cooldowns[ab] = ab.cooldown
	_lunge = Vector3.ZERO
	if ab.delivery == Ability.Delivery.MELEE and _target and _target != player:
		var to := _target.global_position - player.global_position
		to.y = 0.0
		var gap := to.length() - (ab.reach - 0.6)
		if gap > 0.0 and to.length() < lunge_range + ab.reach:
			_lunge = to.normalized() * minf(gap / maxf(ab.hit_time / ab.animation_speed, 0.05), 10.0)
	player.action_move_scale = ab.move_scale
	player.action_animation.emit(ab.animation, 0.0, 0.08, ab.animation_speed)


func _update_action(delta: float) -> void:
	_time += delta * _current.animation_speed
	if _target and is_instance_valid(_target) and _target != player and not _hit_done:
		player.face_toward(_target.global_position, delta)
	player.action_velocity = _lunge if not _hit_done else Vector3.ZERO

	if not _swing_played and _time >= _current.hit_time - 0.12:
		_swing_played = true
		if _current.sounds.size() > 0 and _current.delivery == Ability.Delivery.MELEE:
			Combat.play_sound(player, _current.sounds.pick_random(), -3.0)
	if not _hit_done and _time >= _current.hit_time:
		_hit_done = true
		_land(_current)

	if _time >= _current.recovery_time:
		if _queued:
			var next := _queued
			_queued = null
			_current = null
			if not _start(next):
				_finish_action()
			return
		# Moving after the recovery point ends the action early.
		if Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.1:
			_finish_action()
			return
	var length := character.get_animation_length(_current.animation)
	if _time >= maxf(length, _current.recovery_time):
		_finish_action()


func _land(ab: Ability) -> void:
	match ab.delivery:
		Ability.Delivery.MELEE:
			var fwd := -player.model.global_basis.z
			var hits := 0
			for n in Combat.enemies_near(player, player.global_position, ab.reach + 0.6):
				var to := n.global_position - player.global_position
				if absf(to.y) > 2.0:
					continue
				to.y = 0.0
				if to.length() > 0.5 and rad_to_deg(fwd.angle_to(to.normalized())) > ab.arc * 0.5:
					continue
				Combat.hit(player, n, ab.power, ab.staggers)
				hits += 1
			if hits > 0:
				_enter_combat()
		Ability.Delivery.PROJECTILE:
			if _target and Combat.is_alive(_target):
				var hand := _hand_position()
				Projectile.launch(hand, player, _target, ab)
				if ab.sounds.size() > 0:
					Combat.play_sound(player, ab.sounds[0], -3.0)
		Ability.Delivery.HEAL_OVER_TIME:
			var who: Node3D = _target if _target else player
			var s := Combat.stats_of(who)
			if s:
				s.add_heal_over_time(ab.power, ab.ticks, ab.tick_interval, ab)
				Effects.heal_glow(who, ab.ticks * ab.tick_interval)
				if ab.sounds.size() > 0:
					Combat.play_sound(who, ab.sounds[0], -4.0)


func _finish_action() -> void:
	_current = null
	_queued = null
	player.end_action()


func _hand_position() -> Vector3:
	var skel := character.get_skeleton()
	var bone := skel.find_bone("mixamorig_RightHand")
	if bone < 0:
		return player.global_position + Vector3.UP * 1.4
	return skel.global_transform * skel.get_bone_global_pose(bone).origin


# --- Casting -----------------------------------------------------------------

func _update_cast(delta: float) -> void:
	var moving := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.1
	if moving or Input.is_action_just_pressed("jump"):
		_interrupt_cast("Interrupted")
		return
	if _cast_target and is_instance_valid(_cast_target) and _cast_target != player:
		player.face_toward(_cast_target.global_position, delta)
	_cast_left -= delta
	if _cast_left > 0.0:
		return
	var ab := _casting
	_end_cast_visuals()
	if ab.delivery == Ability.Delivery.PROJECTILE:
		if not Combat.is_alive(_cast_target):
			cast_finished.emit(ab, false)
			_casting = null
			_finish_action()
			return
		if _cast_target.global_position.distance_to(player.global_position) > ab.reach + 2.0:
			notice.emit("Out of range")
			cast_finished.emit(ab, false)
			_casting = null
			_finish_action()
			return
	_casting = null
	_target = _cast_target
	cast_finished.emit(ab, true)
	_begin_release(ab)


func _interrupt_cast(message: String) -> void:
	if _casting == null:
		return
	var ab := _casting
	_casting = null
	_end_cast_visuals()
	notice.emit(message)
	cast_finished.emit(ab, false)
	_finish_action()


func _end_cast_visuals() -> void:
	if _hand_glow and is_instance_valid(_hand_glow):
		_hand_glow.get_parent().queue_free()  # the BoneAttachment holding it
	_hand_glow = null


# --- Blocking ----------------------------------------------------------------

func _start_block() -> void:
	if stats.stamina < block_stamina_per_hit * 0.5:
		notice.emit("Too tired")
		return
	if not player.start_action(0.0):
		return
	_blocking = true
	_enter_combat()
	player.action_animation.emit("block", 0.0, 0.1, 1.0)


func _update_block(delta: float) -> void:
	if not Input.is_action_pressed("block"):
		_end_block()
		return
	_enter_combat()
	if targeting.has_target():
		player.face_toward(targeting.target.global_position, delta)


func _end_block() -> void:
	_blocking = false
	player.end_action()


## Called (through the controller) when the player is hit.
func modify_incoming_damage(amount: float, source: Node) -> float:
	_enter_combat()
	if _blocking and source is Node3D:
		var to := (source as Node3D).global_position - player.global_position
		to.y = 0.0
		var fwd := -player.model.global_basis.z
		if to.length() < 0.01 or rad_to_deg(fwd.angle_to(to.normalized())) <= block_arc * 0.5:
			if stats.use_stamina(block_stamina_per_hit):
				FloatingText.spawn(player, "Blocked", Color(0.8, 0.85, 0.9), 0.8)
				return amount * (1.0 - block_reduction)
			notice.emit("Guard broken")
			_end_block()
			player.action_animation.emit("hit_react", 0.0, 0.05, 1.0)
			return amount
	# Flinch when standing still and not busy.
	if player.state == PlayerController.State.NORMAL and player.is_on_floor() \
			and Vector2(player.velocity.x, player.velocity.z).length() < 0.5:
		player.action_animation.emit("hit_react", 0.0, 0.05, 1.0)
	return amount


# --- Combat state ------------------------------------------------------------

func _enter_combat() -> void:
	_combat_timer = combat_linger
	if not in_combat:
		_set_combat(true)


func _set_combat(value: bool) -> void:
	in_combat = value
	_show_weapon()
	combat_changed.emit(value)


func _on_interrupted() -> void:
	_cancel_all()


func _cancel_all() -> void:
	if _casting:
		var ab := _casting
		_casting = null
		_end_cast_visuals()
		cast_finished.emit(ab, false)
	_current = null
	_queued = null
	_blocking = false
	player.action_velocity = Vector3.ZERO
