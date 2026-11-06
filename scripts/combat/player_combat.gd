class_name PlayerCombat
extends Node
## The player's fighting, Fable style: one attack button whose meaning depends on the
## mode (melee, ranged, magic), tapped for a quick attack or held to charge.
##   Melee: tap = quick swing (rapid taps chain the combo), hold = heavy blow.
##   Ranged: tap = quick shot, hold = draw (harder the longer), release fires.
##   Magic: tap = cast the selected spell, hold = charge it to higher levels.
## Block is held on its own button. Lives under Player, next to Targeting.
## Abilities are data (data/abilities.json, via the Database autoload); this node runs their timing.

enum Mode { MELEE, RANGED, MAGIC }

signal mode_changed(mode: Mode)
signal spell_changed(index: int)
## Charging started (`ability`), and how full it is each frame (0..1, `level` for spells).
signal charge_started(ability: Ability)
signal charge_progress(fraction: float, level: int)
signal charge_ended
signal combat_changed(in_combat: bool)
## The equipped abilities changed (data reloaded).
signal loadout_changed
## Short feedback for the HUD ("Not enough mana", "No target").
signal notice(text: String)

@export_group("Abilities")
# Filled from data/player.json (loadout) and data/abilities.json by the Database.
## Quick melee swings, in combo order: tapping again in time plays the next one.
@export var light_combo: Array[Ability] = []
## Held melee attack.
@export var heavy_attack: Ability
## Bow shot (tap = quick shot at reduced power, hold = draw).
@export var ranged_attack: Ability
## Equipped spells (up to four), chosen with spell previous/next.
@export var spells: Array[Ability] = []

@export_group("Feel")
## Holding attack longer than this (s) starts charging instead of a quick attack.
@export var tap_time := 0.22
## A quick shot does this share of a full draw's power.
@export_range(0.0, 1.0) var quick_shot_power := 0.6
## Lunge towards a target this far away (m) when swinging.
@export var lunge_range := 6.5
## Where the heavy blow's clip pauses while charging (its wind-up).
@export var heavy_windup_time := 0.45

@export_group("Block")
## Share of damage a block stops (hits from the front only).
@export_range(0.0, 1.0) var block_reduction := 0.75
## Stamina each blocked hit costs (0 = blocking is free; stamina is for sprinting).
@export var block_stamina_per_hit := 0.0
@export var block_arc := 150.0

@export_group("Combat state")
## Seconds after the last attack or hit before the weapon is put away.
@export var combat_linger := 6.0

@onready var player: PlayerController = get_parent()
@onready var targeting: Targeting = get_node("../Targeting")
@onready var stats: Stats = get_node("../Stats")
@onready var character: CharacterModel = get_node("../Model/Character")
@onready var animator: PlayerAnimator = get_node("../PlayerAnimator")
@onready var inventory: Inventory = get_node_or_null("../Inventory")

const DRAW_SOUND := preload("res://assets/audio/combat/bow_draw.ogg")
const SHOT_SOUND := preload("res://assets/audio/combat/arrow_fire.ogg")

var mode := Mode.MELEE
var spell_index := 0
var in_combat := false

# Button state.
var _attack_down := false
var _press_time := 0.0

# Charging.
var _charging: Ability = null
var _charge := 0.0
var _charge_glow: Node3D = null

# The action playing now (a swing, a shot, a cast).
var _current: Ability = null
var _time := 0.0
var _hit_done := false
var _swing_played := false
var _queued: Ability = null
var _target: Node3D = null
var _lunge := Vector3.ZERO
var _power := 0.0
var _level := 1

var _blocking := false
var _cooldowns := {}  # Ability -> seconds left
var _combat_timer := 0.0

# Held items.
var _sword_hand: Node3D
var _sword_back: Node3D
var _bow_hand: Node3D
var _bow_back: Node3D


func _ready() -> void:
	Database.apply_player(player, stats, self)
	Database.changed.connect(func(which: String) -> void:
		if which == "player":
			Database.apply_player(player, stats, self)
			spell_index = clampi(spell_index, 0, maxi(spells.size() - 1, 0))
		if which == "player" or which == "abilities":
			loadout_changed.emit())
	player.action_interrupted.connect(_cancel_all)
	player.respawned.connect(func(_reason: String) -> void: _cancel_all(); _set_combat(false))
	stats.damaged.connect(func(_a: float, _s: Node, _c: bool) -> void: _enter_combat())
	Combat.show_numbers(player)
	_equip_weapons.call_deferred()
	if inventory:
		inventory.equipment_changed.connect(_equip_weapons)
	character.body_changed.connect(_equip_weapons)


## Builds the weapon models from what's equipped (main hand, ranged, off hand), each
## twice: in the hand (shown while fighting in that mode) and worn on the back.
func _equip_weapons() -> void:
	for node in [_sword_hand, _sword_back, _bow_hand, _bow_back]:
		if node and is_instance_valid(node):
			node.queue_free()
	_sword_hand = null
	_sword_back = null
	_bow_hand = null
	_bow_back = null
	var spine := character.bone_rest_position("mixamorig_Spine2")
	var flat := Vector3(0, 0, 1)
	var main := inventory.equipped_item("main_hand") if inventory else {}
	if not main.is_empty():
		var fits: Array = main.get("fit", {}).get(character.body_key(), [])
		_sword_hand = character.attach_fitted(fits[0] if not fits.is_empty() else {"bone": "mixamorig_RightHand", "grip": true}, String(main.get("model", "")))
		var back := WeaponModels.build(String(main.get("model", "")))
		if back:
			# Worn on the back: hilt over the right shoulder.
			var blade := Vector3(-0.5, -0.86, 0).normalized()
			_sword_back = character.attach_to_bone(back, "mixamorig_Spine2",
				Transform3D(Basis(blade.cross(flat).normalized(), blade, flat), spine + Vector3(0.16, 0.22, 0.17)))
	var ranged := inventory.equipped_item("ranged") if inventory else {}
	if not ranged.is_empty():
		var fits: Array = ranged.get("fit", {}).get(character.body_key(), [])
		_bow_hand = character.attach_fitted(fits[0] if not fits.is_empty() else {"bone": "mixamorig_LeftHand", "grip": true}, String(ranged.get("model", "")))
		var back := WeaponModels.build(String(ranged.get("model", "")))
		if back:
			var limb := Vector3(0.55, 0.83, 0).normalized()
			_bow_back = character.attach_to_bone(back, "mixamorig_Spine2",
				Transform3D(Basis(limb.cross(-flat).normalized(), limb, -flat), spine + Vector3(0.0, -0.05, 0.2)))
	_show_weapons()


func has_ranged_weapon() -> bool:
	return inventory == null or inventory.equipped.has("ranged")


func _show_weapons() -> void:
	var drawn := in_combat
	var sword_out := drawn and mode == Mode.MELEE
	var bow_out := drawn and mode == Mode.RANGED
	if _sword_hand:
		_sword_hand.visible = sword_out
	if _sword_back:
		_sword_back.visible = not sword_out
	if _bow_hand:
		_bow_hand.visible = bow_out
	if _bow_back:
		_bow_back.visible = not bow_out
	# The shield shares the left arm with the bow.
	character.set_worn_visible("off_hand", not bow_out)
	animator.idle_animation = "idle_armed" if sword_out and _sword_hand else "idle"


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if GameSettings.menu_open:
		return
	if event.is_action_pressed("attack"):
		# Clicking an enemy selects it; the click is also an attack.
		if event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			targeting.click_select(event.position)
		if not _attack_down:
			_attack_down = true
			_press_time = 0.0
	elif event.is_action_pressed("cycle_mode"):
		set_mode((mode + 1) % 3 if not spells.is_empty() else (mode + 1) % 2)
	elif event.is_action_pressed("spell_next"):
		select_spell(spell_index + 1)
	elif event.is_action_pressed("spell_prev"):
		select_spell(spell_index - 1)


func set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	_cancel_charge()
	mode = new_mode
	_show_weapons()
	mode_changed.emit(mode)


func select_spell(index: int) -> void:
	if spells.is_empty():
		return
	spell_index = posmod(index, spells.size())
	spell_changed.emit(spell_index)
	set_mode(Mode.MAGIC)


func selected_spell() -> Ability:
	return spells[spell_index] if spell_index < spells.size() else null


func _physics_process(delta: float) -> void:
	for ab: Ability in _cooldowns.keys():
		_cooldowns[ab] -= delta
		if _cooldowns[ab] <= 0.0:
			_cooldowns.erase(ab)
	if in_combat:
		_combat_timer -= delta
		if _combat_timer <= 0.0 and _current == null and _charging == null and not _blocking:
			_set_combat(false)

	var released := _attack_down and not Input.is_action_pressed("attack")
	if _attack_down:
		_press_time += delta
	if player.state != PlayerController.State.NORMAL and player.state != PlayerController.State.ACTION:
		if released:
			_attack_down = false
		return

	if _current:
		_update_action(delta)
	elif _blocking:
		_update_block(delta)

	var busy := _current != null and _time < _current.recovery_time

	# Attack button: tap or hold.
	if _charging:
		_update_charge(delta)
		if released:
			_attack_down = false
			_release_charge()
	elif _attack_down:
		if released:
			_attack_down = false
			_tap()
		elif _press_time >= tap_time and not busy and not _blocking:
			_begin_charge()

	# Block.
	if not GameSettings.menu_open and Input.is_action_pressed("block") and not busy and not _blocking and _charging == null:
		_start_block()


# --- Abilities ---------------------------------------------------------------

func cooldown_left(ab: Ability) -> float:
	return _cooldowns.get(ab, 0.0)


func can_afford(ab: Ability) -> bool:
	return stats.mana >= ab.mana_cost and stats.stamina >= ab.stamina_cost


func is_blocking() -> bool:
	return _blocking


## The ability the attack button uses in the current mode (tap version).
func mode_ability(which: Mode = mode) -> Ability:
	match which:
		Mode.MELEE:
			return light_combo[0] if not light_combo.is_empty() else null
		Mode.RANGED:
			return ranged_attack
		_:
			return selected_spell()


func _tap() -> void:
	match mode:
		Mode.MELEE:
			if light_combo.is_empty():
				return
			var next: Ability = light_combo[0]
			if _current and light_combo.has(_current) and _hit_done:
				next = light_combo[(light_combo.find(_current) + 1) % light_combo.size()]
			if _current and _time < _current.recovery_time:
				_queued = next  # chain into the next swing when this one allows
			elif _current == null or _time >= _current.recovery_time:
				_current = null
				_start(next, next.power)
		Mode.RANGED:
			if not has_ranged_weapon():
				notice.emit("No ranged weapon equipped")
				return
			if _current == null or _time >= _current.recovery_time:
				_current = null
				_start(ranged_attack, ranged_attack.power * quick_shot_power, 1, 0.0)
		Mode.MAGIC:
			var spell := selected_spell()
			if spell and (_current == null or _time >= _current.recovery_time):
				_current = null
				_start(spell, spell.power, 1)


## Checks costs, picks a target and plays the ability. Returns false if it can't go.
func _start(ab: Ability, power: float, level := 1, anim_start := 0.0) -> bool:
	if ab == null or cooldown_left(ab) > 0.0:
		return false
	if stats.mana < ab.mana_cost * level:
		notice.emit("Not enough mana")
		return false
	if stats.stamina < ab.stamina_cost:
		notice.emit("Too tired")
		return false
	var target := _pick_target(ab)
	if ab.delivery == Ability.Delivery.PROJECTILE and ab.projectile_style == Ability.ProjectileStyle.BOLT and target == null:
		notice.emit("No target")
		return false
	if _blocking:
		_end_block()
	if not player.start_action(ab.move_scale):
		return false
	if ab.mana_cost > 0.0:
		stats.use_mana(ab.mana_cost * level)
	if ab.stamina_cost > 0.0:
		stats.use_stamina(ab.stamina_cost)
	_enter_combat()
	_target = target
	if target and target != player:
		player.face_toward(target.global_position)
	_begin_release(ab, power + _gear_power(ab), level, anim_start)
	return true


## Extra power from equipment: weapon attack for swings and shots, spell power for spells
## (a quarter of it per heal tick).
func _gear_power(ab: Ability) -> float:
	match ab.delivery:
		Ability.Delivery.MELEE:
			return stats.attack
		Ability.Delivery.PROJECTILE:
			return stats.attack if ab.projectile_style == Ability.ProjectileStyle.ARROW else stats.spell_power
		_:
			return stats.spell_power * 0.25


func _pick_target(ab: Ability) -> Node3D:
	match ab.delivery:
		Ability.Delivery.MELEE:
			return targeting.pick_for_attack(lunge_range + ab.reach)
		Ability.Delivery.PROJECTILE:
			return targeting.pick_for_attack(ab.reach)
		_:
			return player  # heals: allies come with co-op


## Plays the ability's clip; the effect lands at its hit_time.
func _begin_release(ab: Ability, power: float, level: int, anim_start := 0.0) -> void:
	_current = ab
	_time = anim_start
	_hit_done = anim_start >= ab.hit_time
	_swing_played = false
	_queued = null
	_power = power
	_level = level
	if ab.cooldown > 0.0:
		_cooldowns[ab] = ab.cooldown
	_lunge = Vector3.ZERO
	if ab.delivery == Ability.Delivery.MELEE and _target and _target != player:
		var to := _target.global_position - player.global_position
		to.y = 0.0
		var gap := to.length() - (ab.reach - 0.6)
		var until_hit := maxf((ab.hit_time - anim_start) / ab.animation_speed, 0.05)
		if gap > 0.0 and to.length() < lunge_range + ab.reach:
			_lunge = to.normalized() * minf(gap / until_hit, 10.0)
	player.action_move_scale = ab.move_scale
	player.action_animation.emit(ab.animation, anim_start, 0.08, ab.animation_speed)


func _update_action(delta: float) -> void:
	_time += delta * _current.animation_speed
	if _target and is_instance_valid(_target) and _target != player and not _hit_done:
		player.face_toward(_target.global_position, delta)
	elif targeting.is_locked():
		player.face_toward(targeting.target.global_position, delta)
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
			if not _start(next, next.power):
				_finish_action()
			return
		# Moving after the recovery point ends the action early.
		if _move_input().length() > 0.1:
			_finish_action()
			return
	var length := character.get_animation_length(_current.animation)
	if _time >= maxf(length, _current.recovery_time):
		_finish_action()


func _land(ab: Ability) -> void:
	match ab.delivery:
		Ability.Delivery.MELEE:
			var fwd := -player.model.global_basis.z
			for n in Combat.enemies_near(player, player.global_position, ab.reach + 0.6):
				var to := n.global_position - player.global_position
				if absf(to.y) > 2.0:
					continue
				to.y = 0.0
				if to.length() > 0.5 and rad_to_deg(fwd.angle_to(to.normalized())) > ab.arc * 0.5:
					continue
				Combat.hit(player, n, _power, ab.staggers)
		Ability.Delivery.PROJECTILE:
			var from := _hand_position(ab.projectile_style == Ability.ProjectileStyle.BOLT)
			var target: Node3D = _target if _target and Combat.is_alive(_target) else null
			var aim := _free_aim_direction(from)
			Projectile.launch(from, player, target, ab, _power, aim)
			if ab.projectile_style == Ability.ProjectileStyle.ARROW:
				Combat.play_sound(player, SHOT_SOUND, -4.0)
			elif ab.sounds.size() > 0:
				Combat.play_sound(player, ab.sounds[0], -3.0)
		Ability.Delivery.HEAL_OVER_TIME:
			var who: Node3D = _target if _target else player
			var s := Combat.stats_of(who)
			if s:
				s.add_heal_over_time(_power, ab.ticks, ab.tick_interval, ab)
				Effects.heal_glow(who, ab.ticks * ab.tick_interval)
				if ab.sounds.size() > 0:
					Combat.play_sound(who, ab.sounds[0], -4.0)


## Without a target, shots go where the character faces (level, slightly up for range).
func _free_aim_direction(_from: Vector3) -> Vector3:
	var fwd := -player.model.global_basis.z
	fwd.y = 0.0
	return (fwd.normalized() + Vector3.UP * 0.02).normalized()


func _finish_action() -> void:
	_current = null
	_queued = null
	player.end_action()


func _hand_position(right := true) -> Vector3:
	var skel := character.get_skeleton()
	var bone := skel.find_bone("mixamorig_RightHand" if right else "mixamorig_LeftHand")
	if bone < 0:
		return player.global_position + Vector3.UP * 1.4
	return skel.global_transform * skel.get_bone_global_pose(bone).origin


func _move_input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


# --- Charging ----------------------------------------------------------------

func _begin_charge() -> void:
	if mode == Mode.RANGED and not has_ranged_weapon():
		notice.emit("No ranged weapon equipped")
		_attack_down = false
		return
	var ab: Ability
	match mode:
		Mode.MELEE:
			ab = heavy_attack
		Mode.RANGED:
			ab = ranged_attack
		_:
			ab = selected_spell()
	if ab == null or cooldown_left(ab) > 0.0:
		return
	if stats.mana < ab.mana_cost:
		notice.emit("Not enough mana")
		_attack_down = false
		return
	if not player.start_action(0.3 if mode != Mode.MELEE else 0.15):
		return
	_charging = ab
	_charge = 0.0
	_enter_combat()
	match mode:
		Mode.MELEE:
			player.action_animation.emit(heavy_attack.animation, 0.0, 0.1, 1.0)
		Mode.RANGED:
			player.action_animation.emit("bow_aim", 0.0, 0.12, 1.0)
			Combat.play_sound(player, DRAW_SOUND, -6.0)
		Mode.MAGIC:
			player.action_animation.emit("cast_channel", 0.0, 0.2, 1.0)
			_charge_glow = Effects.hand_glow(ab.projectile_color)
			character.attach_to_hand(_charge_glow)
	charge_started.emit(ab)


func _update_charge(delta: float) -> void:
	_charge += delta
	var ab := _charging
	if targeting.has_target():
		player.face_toward(targeting.target.global_position, delta)
	if mode == Mode.MELEE and character.current_animation() == ab.animation and character.animation_position() >= heavy_windup_time:
		character.set_speed(0.0)  # hold the wind-up
	charge_progress.emit(_charge_fraction(), _charge_level())


func _charge_fraction() -> float:
	if _charging == null:
		return 0.0
	if mode == Mode.MAGIC:
		var levels := maxi(_charging.max_charge_level, 1)
		return clampf(_charge / (_charging.charge_time * levels), 0.0, 1.0)
	return clampf(_charge / maxf(_charging.charge_time, 0.01), 0.0, 1.0)


func _charge_level() -> int:
	if _charging == null or mode != Mode.MAGIC:
		return 1
	var level := 1 + int(_charge / maxf(_charging.charge_time, 0.01))
	level = mini(level, maxi(_charging.max_charge_level, 1))
	# Only as many levels as there's mana for.
	while level > 1 and stats.mana < _charging.mana_cost * level:
		level -= 1
	return level


func _release_charge() -> void:
	var ab := _charging
	var k := _charge_fraction()
	var level := _charge_level()
	_end_charge_visuals()
	_charging = null
	charge_ended.emit()
	match mode:
		Mode.MELEE:
			player.end_action()
			_start(ab, ab.power * (1.0 + ab.charge_power * k), 1, heavy_windup_time)
		Mode.RANGED:
			player.end_action()
			var power := ab.power * lerpf(quick_shot_power, 1.0 + ab.charge_power, k)
			_start(ab, power, 1, 0.0)
		Mode.MAGIC:
			player.end_action()
			var levels := maxi(ab.max_charge_level, 1)
			var level_k := float(level - 1) / maxf(levels - 1, 1)
			_start(ab, ab.power * (1.0 + ab.charge_power * level_k), level, 0.0)


func _cancel_charge() -> void:
	if _charging == null:
		return
	_charging = null
	_end_charge_visuals()
	charge_ended.emit()
	player.end_action()


func _end_charge_visuals() -> void:
	character.set_speed(1.0)
	if _charge_glow and is_instance_valid(_charge_glow):
		_charge_glow.get_parent().queue_free()  # the BoneAttachment holding it
	_charge_glow = null


# --- Blocking ----------------------------------------------------------------

func _start_block() -> void:
	if not player.start_action(0.0):
		return
	_blocking = true
	_enter_combat()
	player.action_animation.emit("block", 0.0, 0.1, 1.0)


func _update_block(delta: float) -> void:
	if not Input.is_action_pressed("block") or GameSettings.menu_open:
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
			if block_stamina_per_hit <= 0.0 or stats.use_stamina(block_stamina_per_hit):
				FloatingText.spawn(player, "Blocked", Color(0.8, 0.85, 0.9), 0.8)
				return amount * (1.0 - clampf(block_reduction + stats.block, 0.0, 0.95))
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
	_show_weapons()
	combat_changed.emit(value)


func _cancel_all() -> void:
	if _charging:
		_charging = null
		_end_charge_visuals()
		charge_ended.emit()
	_current = null
	_queued = null
	_blocking = false
	_attack_down = false
	player.action_velocity = Vector3.ZERO
