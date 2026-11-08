class_name PlayerCombat
extends Node
## The player's fighting, Fable style. One attack button; what it does depends on the
## weapon in use (primary or secondary, swapped with Swap weapon or hotbar keys 1 and 2):
##   Melee weapons: tap = quick swing (rapid taps chain the combo), hold = heavy blow.
##   Bows: tap = quick shot, hold = draw (harder the longer), release fires.
##   Crossbows and guns: each press fires, then the weapon reloads (a "Reloading" bar).
## Block (held) guards with melee weapons and aims with ranged ones (over the shoulder,
## zoomed, with a crosshair). Ranged weapons aim by hand (where the crosshair is, or at a
## locked target) only when the item has "auto_aim" off; by default shots home onto the target.
## Spells and items sit on the hotbar (boxes 3-10) and are cast with a cast bar.
## Weapon families (speed, power, combo, reload, sounds) are data/weapon_types.json; the
## class's "proficient" families hit harder and faster. Lives under Player, next to Targeting.

signal weapon_changed(slot: String)
signal combat_changed(in_combat: bool)
## The known abilities changed (data reloaded).
signal loadout_changed
## Short feedback for the HUD ("Not enough mana", "No target").
signal notice(text: String)
## A cast or charge was stopped ("Interrupted", "Cancelled").
signal cast_interrupted(reason: String)
signal aim_changed(aiming: bool)

@export_group("Abilities")
# Filled from data/player.json (loadout) by the Database. Weapons bring their own moves
# (data/weapon_types.json); these are the fallbacks (fists, a family without moves).
@export var light_combo: Array[Ability] = []
@export var heavy_attack: Ability
@export var ranged_attack: Ability
## The spellbook: abilities this character knows (put on the hotbar to use).
@export var spells: Array[Ability] = []

@export_group("Feel")
## Holding attack longer than this (s) starts charging instead of a quick attack.
@export var tap_time := 0.22
## A quick bow shot does this share of a full draw's power.
@export_range(0.0, 1.0) var quick_shot_power := 0.6
## Lunge towards a target this far away (m) when swinging.
@export var lunge_range := 6.5
## Where the heavy blow's clip pauses while charging (its wind-up).
@export var heavy_windup_time := 0.45
## Proficient weapon families: this much more damage...
@export var proficiency_damage := 0.15
## ...and this much faster swings, shots and reloads.
@export var proficiency_speed := 0.1
## Arrows and bolts fall this fast (m/s²) when aimed by hand.
@export var arrow_gravity := 6.0

@export_group("Block")
## Share of damage a block stops (hits from the front only).
@export_range(0.0, 1.0) var block_reduction := 0.75
## Stamina each blocked hit costs (0 = blocking is free; stamina is for sprinting).
@export var block_stamina_per_hit := 0.0
@export var block_arc := 150.0

@export_group("Parry, dodge and casting")
## Starting to block this soon (s) before a hit lands parries it: no damage, the attacker
## is staggered, and your next hit is a counter.
@export var parry_window := 0.25
## How long a counter stays ready after a parry or a perfect dodge.
@export var counter_window := 1.5
## A light hit while casting knocks the cast bar back this many seconds.
@export var cast_pushback := 0.35
## Hits at least this share of max health (or heavy hits) interrupt casts and charges.
@export var interrupt_share := 0.15
## Moving (or dodging) cancels a spell being cast.
@export var move_cancels_cast := true

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
const RELOAD_SOUND := preload("res://assets/audio/weapons/gun_reload.ogg")

var in_combat := false
## The weapon in use: its item ({} = bare hands) and family (data/weapon_types.json).
var weapon := {}
var weapon_type := {}
## Its moves.
var combo: Array[Ability] = []
var heavy: Ability = null
var shot: Ability = null

# Button state.
var _attack_down := false
var _press_time := 0.0

# Charging (heavy blow, bow draw).
var _charging: Ability = null
var _charge := 0.0

# Casting a spell from the hotbar (the bar fills, then it goes off).
var _casting: Ability = null
var _cast_time := 0.0
var _cast_glow: Node3D = null

# The action playing now (a swing, a shot, a spell going off).
var _current: Ability = null
var _time := 0.0
var _speed := 1.0  # animation speed multiplier (weapon speed, proficiency)
var _hit_done := false
var _swing_played := false
var _queued: Ability = null
var _target: Node3D = null
var _lunge := Vector3.ZERO
var _power := 0.0

var _blocking := false
var _block_started := 0  # msec
var _aiming := false
var _aim_pose := false
var _counter_until := 0  # msec: next hit is a counter
var _flourish := false  # this swing is a fully charged heavy
var _buffer_until := 0  # msec: an attack tapped during a dodge (-1 while it lasts)
# A plain channel (hearthstone and the like): a cast bar, then a callback.
var _channel: Ability = null
var _channel_time := 0.0
var _channel_done: Callable
var _cooldowns := {}  # Ability -> seconds left
var _combat_timer := 0.0

# Reloading (crossbows, guns): weapon slot -> id of the item in it that still needs reloading.
var _unloaded := {}
var _reload_left := 0.0
var _reload_total := 0.0

# Held weapons: slot -> {"hand": Node3D, "back": Node3D}
var _models := {}

# Where the crosshair points (updated each frame while a ranged weapon is out).
var aim_point := Vector3.ZERO
var aim_on_enemy := false


func _ready() -> void:
	Database.apply_player(player, stats, self)
	Database.changed.connect(func(which: String) -> void:
		if which == "player":
			Database.apply_player(player, stats, self)
		if which in ["player", "abilities", "weapon_types", "classes"]:
			_refresh_weapon()
			loadout_changed.emit())
	player.action_interrupted.connect(_cancel_all)
	player.respawned.connect(func(_reason: String) -> void: _cancel_all(); _set_combat(false))
	stats.damaged.connect(func(_a: float, _s: Node, _c: bool) -> void: _enter_combat())
	Combat.show_numbers(player)
	_equip_weapons.call_deferred()
	if inventory:
		inventory.equipment_changed.connect(_equip_weapons)
	character.body_changed.connect(_equip_weapons)


# --- Weapons -----------------------------------------------------------------

## The active weapon's moves and numbers, from its family.
func _refresh_weapon() -> void:
	var before := String(weapon.get("id", ""))
	weapon = inventory.active_weapon_item() if inventory else {}
	if String(weapon.get("id", "")) != before:
		_reload_left = 0.0  # a different weapon in hand
	weapon_type = Database.weapon_type(String(weapon.get("weapon_type", "")))
	combo = []
	heavy = null
	shot = null
	if is_ranged():
		shot = Database.ability(String(weapon_type.get("shot", "")))
		if shot == null:
			shot = ranged_attack
	else:
		var ids: Array = weapon_type.get("combo", [])
		combo = Database.abilities_for(ids) if not ids.is_empty() else light_combo.duplicate()
		heavy = Database.ability(String(weapon_type.get("heavy", ""))) if weapon_type.has("heavy") else null
		if heavy == null:
			heavy = heavy_attack


func active_slot() -> String:
	return inventory.active_weapon if inventory else "primary"


func is_ranged(type := weapon_type) -> bool:
	return String(type.get("category", "melee")) == "ranged"


## Manual aim (crosshair) only for items with auto_aim turned off.
func is_manual_aim() -> bool:
	return is_ranged() and not bool(weapon.get("auto_aim", true))


func is_proficient(type_id: String) -> bool:
	var cls := String(GameSession.data.get("class", "fighter")) if GameSession.active() else "fighter"
	return type_id in Database.class_data(cls).get("proficient", [])


## Swing / shot / reload speed of a weapon item (1 = normal).
func speed_of(item: Dictionary) -> float:
	var t := Database.weapon_type(String(item.get("weapon_type", "")))
	var k := float(t.get("speed", 1.0)) * float(item.get("speed", 1.0))
	if is_proficient(String(item.get("weapon_type", ""))):
		k *= 1.0 + proficiency_speed
	return maxf(k, 0.1)


## Damage multiplier of a weapon item.
func power_of(item: Dictionary) -> float:
	var t := Database.weapon_type(String(item.get("weapon_type", "")))
	var k := float(t.get("power", 1.0))
	if is_proficient(String(item.get("weapon_type", ""))):
		k *= 1.0 + proficiency_damage
	return k


## Rough damage per second of a weapon item, as if it were in use (for item tooltips).
func dps_of(item: Dictionary) -> float:
	var t := Database.weapon_type(String(item.get("weapon_type", "")))
	var attack := stats.attack - float(weapon.get("attack", 0.0)) + float(item.get("attack", 0.0))
	var speed := speed_of(item)
	var power := power_of(item)
	if is_ranged(t):
		var ab := Database.ability(String(t.get("shot", "")))
		if ab == null:
			ab = ranged_attack
		if ab == null:
			return 0.0
		var per_shot := (ab.power * (quick_shot_power if bool(t.get("draw", false)) else 1.0) + attack) * power
		var cycle := ab.recovery_time / maxf(ab.animation_speed * speed, 0.01) + float(t.get("reload", 0.0)) / speed + 0.15
		return per_shot / cycle
	var moves: Array[Ability] = Database.abilities_for(t.get("combo", [])) if t.has("combo") else light_combo
	if moves.is_empty():
		moves = light_combo
	var dmg := 0.0
	var secs := 0.0
	for ab in moves:
		dmg += (ab.power + attack) * power
		secs += ab.recovery_time / maxf(ab.animation_speed * speed, 0.01)
	return dmg / maxf(secs, 0.01)


## Primary ↔ secondary.
func swap_weapon() -> void:
	select_weapon("secondary" if active_slot() == "primary" else "primary")


func select_weapon(slot: String) -> void:
	if inventory == null or slot == active_slot():
		return
	if _current and not _hit_done:
		return  # mid-swing
	_cancel_all()
	player.end_action()
	_reload_left = 0.0
	inventory.set_active_weapon(slot)  # → equipment_changed → _equip_weapons
	var t := Database.weapon_type(String(inventory.equipped_item(slot).get("weapon_type", "")))
	var sound := String(t.get("swap_sound", ""))
	if not sound.is_empty() and ResourceLoader.exists(sound):
		Combat.play_sound(player, load(sound), -4.0)
	_enter_combat()
	weapon_changed.emit(slot)


## Builds the weapon models: the one in use goes in the hand while fighting; the other
## (and the one in use, when not fighting) is worn on the back.
func _equip_weapons() -> void:
	for slot in _models:
		for node: Node3D in _models[slot].values():
			if node and is_instance_valid(node):
				node.queue_free()
	_models.clear()
	_refresh_weapon()
	if inventory == null:
		_show_weapons()
		return
	var spine := character.bone_rest_position("mixamorig_Spine2")
	var flat := Vector3(0, 0, 1)
	for slot: String in Inventory.WEAPON_SLOTS:
		var item := inventory.equipped_item(slot)
		if item.is_empty():
			continue
		var t := Database.weapon_type(String(item.get("weapon_type", "")))
		var left := String(item.get("weapon_type", "")) == "bow"
		var fits: Array = item.get("fit", {}).get(character.body_key(), [])
		var hand := character.attach_fitted(fits[0] if not fits.is_empty() else
			{"bone": "mixamorig_LeftHand" if left else "mixamorig_RightHand", "grip": true}, String(item.get("model", "")))
		var back_model := WeaponModels.build(String(item.get("model", "")))
		var back: Node3D = null
		if back_model:
			if slot == "primary":
				# Hilt over the right shoulder.
				var blade := Vector3(-0.5, -0.86, 0).normalized()
				back = character.attach_to_bone(back_model, "mixamorig_Spine2",
					Transform3D(Basis(blade.cross(flat).normalized(), blade, flat), spine + Vector3(0.16, 0.22, 0.17)))
			else:
				var limb := Vector3(0.55, 0.83, 0).normalized()
				if not is_ranged(t):
					limb = Vector3(0.5, -0.86, 0).normalized()  # hilt over the left shoulder
				back = character.attach_to_bone(back_model, "mixamorig_Spine2",
					Transform3D(Basis(limb.cross(-flat).normalized(), limb, -flat), spine + Vector3(-0.02, -0.05, 0.21)))
		_models[slot] = {"hand": hand, "back": back}
	_show_weapons()


func _show_weapons() -> void:
	var slot := active_slot()
	for s: String in _models:
		var drawn := in_combat and s == slot
		var m: Dictionary = _models[s]
		if m.hand and is_instance_valid(m.hand):
			m.hand.visible = drawn
		if m.back and is_instance_valid(m.back):
			m.back.visible = not drawn
	# The shield only goes with a one-handed melee weapon.
	var hands := int(weapon_type.get("hands", 1))
	character.set_worn_visible("off_hand", not (in_combat and (is_ranged() or hands >= 2)))
	animator.idle_animation = "idle_armed" if in_combat and not is_ranged() and _models.has(slot) else "idle"


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
		swap_weapon()
	elif event.is_action_pressed("hotbar_1"):
		select_weapon("primary")
	elif event.is_action_pressed("hotbar_2"):
		select_weapon("secondary")
	else:
		for i in Inventory.HOTBAR_SIZE:
			if event.is_action_pressed("hotbar_%d" % (i + 3)):
				use_hotbar(i)
				get_viewport().set_input_as_handled()
				return


## Uses hotbar box `i` (0-7, the boxes after the two weapons).
func use_hotbar(i: int) -> void:
	if inventory == null or i < 0 or i >= inventory.hotbar.size():
		return
	var entry := String(inventory.hotbar[i])
	if entry.begins_with("ability:"):
		cast(Database.ability(entry.substr(8)))
	elif entry.begins_with("item:"):
		if stats.is_dead():
			return
		inventory.use_item(entry.substr(5))


func _physics_process(delta: float) -> void:
	for ab: Ability in _cooldowns.keys():
		_cooldowns[ab] -= delta
		if _cooldowns[ab] <= 0.0:
			_cooldowns.erase(ab)
	if in_combat:
		_combat_timer -= delta
		if _combat_timer <= 0.0 and _current == null and _charging == null and _casting == null and not _blocking and not _aiming:
			_set_combat(false)
	_update_reload(delta)
	_update_aim_point()

	var released := _attack_down and not Input.is_action_pressed("attack")
	if _attack_down:
		_press_time += delta
	if player.state != PlayerController.State.NORMAL and player.state != PlayerController.State.ACTION:
		if released:
			_attack_down = false
			# Tapped during a dodge: attack as soon as it ends.
			if player.state == PlayerController.State.DODGE:
				_buffer_until = -1  # pending until the dodge ends
		if _aiming:
			_set_aiming(false)
		return

	if _channel:
		_update_channel(delta)
		if released:
			_attack_down = false
		return
	if _casting:
		_update_cast(delta)
		if released:
			_attack_down = false
		return
	if _current:
		_update_action(delta)
	elif _blocking:
		_update_block(delta)
	_update_aim(delta)

	# Until the blow lands you're committed; after that, block or dodge cancel the rest.
	var busy := _current != null and not _hit_done
	var swinging := _current != null and _time < _current.recovery_time

	if _buffer_until < 0:
		_buffer_until = Time.get_ticks_msec() + 250  # the dodge just ended
	if _buffer_until > 0 and _current == null and _charging == null and not _attack_down:
		if Time.get_ticks_msec() <= _buffer_until:
			_tap()
		_buffer_until = 0

	# Attack button: tap or hold.
	var chargeable := not is_ranged() or bool(weapon_type.get("draw", false))
	if _charging:
		_update_charge(delta)
		if _charging and released:
			_attack_down = false
			_release_charge()
	elif _attack_down:
		if not chargeable:
			_attack_down = false  # crossbows and guns fire on the press
			_tap()
		elif released:
			_attack_down = false
			_tap()
		elif _press_time >= tap_time and not swinging and not _blocking:
			_begin_charge()

	# Block (melee weapons; ranged ones aim instead).
	if not is_ranged() and not GameSettings.menu_open and Input.is_action_pressed("block") and not busy \
			and not _blocking and _charging == null:
		_start_block()


# --- Abilities ---------------------------------------------------------------

func cooldown_left(ab: Ability) -> float:
	return _cooldowns.get(ab, 0.0)


func can_afford(ab: Ability) -> bool:
	return stats.mana >= ab.mana_cost and stats.stamina >= ab.stamina_cost


func is_blocking() -> bool:
	return _blocking


func is_aiming() -> bool:
	return _aiming


func _tap() -> void:
	if _casting:
		return
	if is_ranged():
		if shot == null:
			return
		if _current and _time < _current.recovery_time:
			return
		if _reload_left > 0.0:
			return
		if _needs_reload():
			_start_reload()
			return
		_current = null
		var full := not bool(weapon_type.get("draw", false))  # crossbows and guns: no draw
		if _start(shot, shot.power * (1.0 if full else quick_shot_power)):
			if float(weapon_type.get("reload", 0.0)) > 0.0:
				_unloaded[active_slot()] = String(weapon.get("id", ""))
		return
	if combo.is_empty():
		return
	# Mid-combo, the next tap is the next swing in the chain (it waits for this one's
	# recovery); after the last swing, or out of a combo, it starts again.
	var next: Ability = combo[0]
	if _current and combo.has(_current):
		next = combo[(combo.find(_current) + 1) % combo.size()]
	if _current and _time < _current.recovery_time:
		_queued = next  # chain into the next swing when this one allows
	elif _current == null or _time >= _current.recovery_time:
		_current = null
		_start(next, next.power)


## Is this one of the weapon's own moves (scaled by the weapon), or a spell?
func _is_weapon_move(ab: Ability) -> bool:
	return ab == shot or ab == heavy or combo.has(ab)


## Checks costs, picks a target and plays the ability. Returns false if it can't go.
func _start(ab: Ability, power: float, anim_start := 0.0) -> bool:
	if ab == null or cooldown_left(ab) > 0.0:
		return false
	if stats.mana < ab.mana_cost:
		notice.emit("Not enough mana")
		return false
	if stats.stamina < ab.stamina_cost:
		notice.emit("Too tired")
		return false
	var weapon_move := _is_weapon_move(ab)
	var target := _pick_target(ab, weapon_move)
	if ab.delivery == Ability.Delivery.PROJECTILE and not weapon_move and target == null:
		notice.emit("No target")
		return false
	if _blocking:
		_end_block()
	if not player.start_action(ab.move_scale):
		return false
	_aim_pose = false
	if ab.mana_cost > 0.0:
		stats.use_mana(ab.mana_cost)
	if ab.stamina_cost > 0.0:
		stats.use_stamina(ab.stamina_cost)
	_enter_combat()
	_target = target
	if weapon_move and is_manual_aim() and (_aiming or not targeting.is_locked()):
		player.face_toward(aim_point)
	elif target and target != player:
		player.face_toward(target.global_position)
	_speed = speed_of(weapon) if weapon_move else 1.0
	var total := power + _gear_power(ab)
	if weapon_move:
		total *= power_of(weapon)
	_begin_release(ab, total, anim_start)
	return true


## Extra power from equipment: weapon attack for swings and shots, spell power for spells
## (a quarter of it per heal tick).
func _gear_power(ab: Ability) -> float:
	if _is_weapon_move(ab):
		return stats.attack
	match ab.delivery:
		Ability.Delivery.HEAL_OVER_TIME:
			return stats.spell_power * 0.25
		_:
			return stats.spell_power


func _pick_target(ab: Ability, weapon_move: bool) -> Node3D:
	match ab.delivery:
		Ability.Delivery.MELEE:
			return targeting.pick_for_attack(lunge_range + ab.reach)
		Ability.Delivery.PROJECTILE:
			if weapon_move and is_manual_aim():
				return targeting.target if targeting.is_locked() else null
			return targeting.pick_for_attack(ab.reach)
		_:
			return player  # heals: allies come with co-op


## Plays the ability's clip; the effect lands at its hit_time.
func _begin_release(ab: Ability, power: float, anim_start := 0.0) -> void:
	_current = ab
	_time = anim_start
	_hit_done = anim_start >= ab.hit_time
	_swing_played = false
	_queued = null
	_power = power
	if ab.cooldown > 0.0:
		_cooldowns[ab] = ab.cooldown
	_lunge = Vector3.ZERO
	var speed := ab.animation_speed * _speed
	if ab.delivery == Ability.Delivery.MELEE and (_target == null or _target == player):
		# No target: a small step into the swing so it has some weight.
		_lunge = -player.model.global_basis.z * 1.4
	if ab.delivery == Ability.Delivery.MELEE and _target and _target != player:
		var to := _target.global_position - player.global_position
		to.y = 0.0
		var gap := to.length() - (ab.reach - 0.6)
		var until_hit := maxf((ab.hit_time - anim_start) / speed, 0.05)
		if gap > 0.0 and to.length() < lunge_range + ab.reach:
			_lunge = to.normalized() * minf(gap / until_hit, 10.0)
	player.action_move_scale = ab.move_scale
	player.action_animation.emit(ab.animation, anim_start, 0.08, speed)


func _update_action(delta: float) -> void:
	_time += delta * _current.animation_speed * _speed
	if _is_weapon_move(_current) and is_manual_aim() and (_aiming or not targeting.is_locked()):
		player.face_toward(aim_point, delta)
	elif _target and is_instance_valid(_target) and _target != player and not _hit_done:
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
		# Moving (or aiming again) after the recovery point ends the action early.
		if _move_input().length() > 0.1 or _aiming:
			_finish_action()
			return
	var length := character.get_animation_length(_current.animation)
	if _time >= maxf(length, _current.recovery_time):
		_finish_action()


func _land(ab: Ability) -> void:
	match ab.delivery:
		Ability.Delivery.MELEE:
			var fwd := -player.model.global_basis.z
			var power := _power
			var staggers := ab.staggers
			var push := ab.knockback
			if _flourish:
				power *= 1.3
				staggers = true
				push *= 1.6
			var countering := _use_counter()
			if countering:
				power *= 1.75
				staggers = true
				push *= 1.5
			var landed := false
			for n in Combat.enemies_near(player, player.global_position, ab.reach + 0.6):
				var to := n.global_position - player.global_position
				if absf(to.y) > 2.0:
					continue
				to.y = 0.0
				if to.length() > 0.5 and rad_to_deg(fwd.angle_to(to.normalized())) > ab.arc * 0.5:
					continue
				if Combat.hit(player, n, power, staggers, push) > 0.0:
					landed = true
					if countering:
						FloatingText.spawn(n, "Counter!", Color(1.0, 0.85, 0.3), 1.2)
			if landed and _flourish:
				FloatingText.spawn(player, "Flourish!", Color(1.0, 0.8, 0.3), 1.3)
				TimeFX.hit_stop(player, 0.14)
		Ability.Delivery.PROJECTILE:
			var weapon_move := _is_weapon_move(ab)
			var bolt := ab.projectile_style == Ability.ProjectileStyle.BOLT
			var from := _muzzle(weapon_move)
			var power := _power * (1.5 if _use_counter() else 1.0)
			if weapon_move and is_manual_aim():
				_fire_manual(from, ab, power)
			else:
				var target: Node3D = _target if _target and Combat.is_alive(_target) else null
				var dir := (aim_point - from) if weapon_move else _forward_direction()
				Projectile.launch(from, player, target, ab, power, dir)
			var fire := String(weapon_type.get("fire_sound", "")) if weapon_move else ""
			if not fire.is_empty() and ResourceLoader.exists(fire):
				Combat.play_sound(player, load(fire), -3.0)
			elif not bolt and weapon_move:
				Combat.play_sound(player, SHOT_SOUND, -4.0)
			elif ab.sounds.size() > 0:
				Combat.play_sound(player, ab.sounds[0], -3.0)
			if ab.projectile_style == Ability.ProjectileStyle.BULLET:
				Effects.sparks(Combat.world_root(player), from, Color(1.0, 0.75, 0.35), 0.8, -player.model.global_basis.z)
				var cam := get_tree().get_first_node_in_group("player_camera")
				if cam:
					cam.call("shake", 0.18)
			if weapon_move and float(weapon_type.get("reload", 0.0)) > 0.0:
				_start_reload.call_deferred()
		Ability.Delivery.HEAL_OVER_TIME:
			var who: Node3D = _target if _target else player
			var s := Combat.stats_of(who)
			if s:
				s.add_heal_over_time(_power, ab.ticks, ab.tick_interval, ab)
				Effects.heal_glow(who, ab.ticks * ab.tick_interval)
				if ab.sounds.size() > 0:
					Combat.play_sound(who, ab.sounds[0], -4.0)


## Hand-aimed shot: at the crosshair, or (locked on, not aiming) at the target with
## enough lift for arrows to arc onto it. Arrows and bolts drop; bullets fly straight.
func _fire_manual(from: Vector3, ab: Ability, power: float) -> void:
	var falls := ab.projectile_style == Ability.ProjectileStyle.ARROW
	var g := arrow_gravity if falls else 0.0
	var dir := aim_point - from
	if not _aiming and targeting.is_locked():
		var at := Combat.aim_point(targeting.target)
		dir = Projectile.ballistic(from, at, ab.projectile_speed, g) if falls else at - from
	Projectile.launch(from, player, null, ab, power, dir, g)


## Without a target, spells go where the character faces (level, slightly up for range).
func _forward_direction() -> Vector3:
	var fwd := -player.model.global_basis.z
	fwd.y = 0.0
	return (fwd.normalized() + Vector3.UP * 0.02).normalized()


## Where shots leave from: the bow hand, or a little in front of a gun or crossbow.
func _muzzle(weapon_move: bool) -> Vector3:
	if not weapon_move:
		return _hand_position(false)
	var bow := String(weapon.get("weapon_type", "")) == "bow"
	var p := _hand_position(not bow)
	if not bow:
		p += -player.model.global_basis.z * 0.45 + Vector3.UP * 0.05
	return p


## True (once) if a counter is ready from a parry or perfect dodge.
func _use_counter() -> bool:
	if Time.get_ticks_msec() <= _counter_until:
		_counter_until = 0
		return true
	return false


## After a parry or a perfect dodge: the next hit within counter_window is a counter.
func grant_counter() -> void:
	_counter_until = Time.get_ticks_msec() + int(counter_window * 1000.0)


func _finish_action() -> void:
	_current = null
	_queued = null
	_flourish = false
	player.end_action()


func _hand_position(right := true) -> Vector3:
	var skel := character.get_skeleton()
	var bone := skel.find_bone("mixamorig_RightHand" if right else "mixamorig_LeftHand")
	if bone < 0:
		return player.global_position + Vector3.UP * 1.4
	return skel.global_transform * skel.get_bone_global_pose(bone).origin


func _move_input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


# --- Charging (heavy blow, bow draw) ---------------------------------------------

func _begin_charge() -> void:
	var ab: Ability = shot if is_ranged() else heavy
	if ab == null or cooldown_left(ab) > 0.0 or _casting:
		return
	if not player.start_action(0.3 if is_ranged() else 0.15):
		return
	_aim_pose = false
	_charging = ab
	_charge = 0.0
	_enter_combat()
	if is_ranged():
		player.action_animation.emit("bow_aim", 0.0, 0.12, 1.0)
		Combat.play_sound(player, DRAW_SOUND, -6.0)
	else:
		player.action_animation.emit(heavy.animation, 0.0, 0.1, 1.0)


func _update_charge(delta: float) -> void:
	_charge += delta * speed_of(weapon)
	var ab := _charging
	if is_manual_aim() and (_aiming or not targeting.is_locked()):
		player.face_toward(aim_point, delta)
	elif targeting.has_target():
		player.face_toward(targeting.target.global_position, delta)
	if not is_ranged() and character.current_animation() == ab.animation and character.animation_position() >= heavy_windup_time:
		character.set_speed(0.0)  # hold the wind-up


func _charge_fraction() -> float:
	if _charging == null:
		return 0.0
	return clampf(_charge / maxf(_charging.charge_time, 0.01), 0.0, 1.0)


func _release_charge() -> void:
	var ab := _charging
	var k := _charge_fraction()
	character.set_speed(1.0)
	_charging = null
	player.end_action()
	if is_ranged():
		_start(ab, ab.power * lerpf(quick_shot_power, 1.0 + ab.charge_power, k))
	elif _start(ab, ab.power * (1.0 + ab.charge_power * k), heavy_windup_time):
		_flourish = k >= 0.98


func _cancel_charge() -> void:
	if _charging == null:
		return
	_charging = null
	character.set_speed(1.0)
	player.end_action()


# --- Spells (from the hotbar) ---------------------------------------------------

## Casts a spell: the cast bar fills over its cast_time (moving cancels it, hits push it
## back or interrupt it), then it goes off. Instant if it has no cast time.
func cast(ab: Ability) -> bool:
	if ab == null or stats.is_dead():
		return false
	if _casting or _channel or _charging:
		return false
	if _current and _time < _current.recovery_time:
		return false
	var left := cooldown_left(ab)
	if left > 0.0:
		notice.emit("%s isn't ready (%.0f s)" % [ab.display_name, ceilf(left)])
		return false
	if stats.mana < ab.mana_cost:
		notice.emit("Not enough mana")
		return false
	if ab.delivery == Ability.Delivery.PROJECTILE and targeting.pick_for_attack(ab.reach) == null:
		notice.emit("No target")
		return false
	if _current:
		_finish_action()
	if _blocking:
		_end_block()
	if _aiming:
		_set_aiming(false)
	if ab.cast_time <= 0.0:
		return _start(ab, ab.power)
	if not player.start_action(0.0 if move_cancels_cast else 0.3):
		notice.emit("Can't do that now")
		return false
	_aim_pose = false
	_casting = ab
	_cast_time = 0.0
	_enter_combat()
	player.action_animation.emit("cast_channel", 0.0, 0.2, 1.0)
	_cast_glow = Effects.hand_glow(ab.projectile_color)
	character.attach_to_hand(_cast_glow)
	return true


func _update_cast(delta: float) -> void:
	_cast_time += delta
	if move_cancels_cast and _move_input().length() > 0.5:
		_interrupt("Cancelled", false)
		return
	if targeting.has_target():
		player.face_toward(targeting.target.global_position, delta)
	if _cast_time >= _casting.cast_time:
		var ab := _casting
		_end_cast()
		player.end_action()
		_start(ab, ab.power)


func _end_cast() -> void:
	_casting = null
	if _cast_glow and is_instance_valid(_cast_glow):
		_cast_glow.get_parent().queue_free()  # the BoneAttachment holding it
	_cast_glow = null


## Casts something that isn't an ability (a hearthstone): the cast bar fills over
## `seconds`, then `on_done` runs. Moving, dodging or being hit stops it.
func channel(display: String, seconds: float, on_done: Callable) -> bool:
	if _channel or _current or _charging or _blocking or _casting:
		notice.emit("You're busy")
		return false
	if _aiming:
		_set_aiming(false)
	if not player.start_action(0.0):
		notice.emit("Can't do that now")
		return false
	_channel = Ability.new()
	_channel.display_name = display
	_channel.cast_time = seconds
	_channel_time = 0.0
	_channel_done = on_done
	player.action_animation.emit("cast_channel", 0.0, 0.2, 1.0)
	return true


func _update_channel(delta: float) -> void:
	_channel_time += delta
	if _move_input().length() > 0.5:
		_interrupt("Cancelled", false)
		return
	if _channel_time >= _channel.cast_time:
		var done := _channel_done
		_channel = null
		player.end_action()
		if done.is_valid():
			done.call()


func _stop_channel() -> void:
	if _channel:
		_channel = null
		player.end_action()


## Spells and channels: still filling the cast bar.
func is_casting() -> bool:
	return _channel != null or _casting != null


## What the HUD's cast bar shows: {"name", "fraction", "kind": cast/charge/reload}, or {}.
func bar_state() -> Dictionary:
	if _channel:
		return {"name": _channel.display_name, "fraction": clampf(_channel_time / maxf(_channel.cast_time, 0.01), 0.0, 1.0), "kind": "cast"}
	if _casting:
		return {"name": _casting.display_name, "fraction": clampf(_cast_time / maxf(_casting.cast_time, 0.01), 0.0, 1.0), "kind": "cast"}
	if _charging:
		return {"name": "Drawing" if is_ranged() else _charging.display_name, "fraction": _charge_fraction(), "kind": "charge"}
	if _reload_left > 0.0:
		return {"name": "Reloading", "fraction": 1.0 - _reload_left / maxf(_reload_total, 0.01), "kind": "reload"}
	return {}


# --- Reloading -----------------------------------------------------------------

func _start_reload() -> void:
	var t := float(weapon_type.get("reload", 0.0))
	if t <= 0.0 or _reload_left > 0.0 or not _needs_reload():
		return
	_reload_total = t / speed_of(weapon)
	_reload_left = _reload_total
	Combat.play_sound(player, RELOAD_SOUND, -6.0, 1.15 if String(weapon.get("weapon_type", "")) == "crossbow" else 1.0)


func _update_reload(delta: float) -> void:
	if _reload_left <= 0.0:
		return
	if stats.is_dead():
		_reload_left = 0.0
		return
	_reload_left -= delta
	if _reload_left <= 0.0:
		_reload_left = 0.0
		_unloaded.erase(active_slot())


## The weapon in use was fired and not reloaded since.
func _needs_reload() -> bool:
	return _unloaded.has(active_slot()) and _unloaded[active_slot()] == String(weapon.get("id", ""))


func is_loaded() -> bool:
	return not _needs_reload() and _reload_left <= 0.0


# --- Aiming (block with a ranged weapon) --------------------------------------------

func _update_aim(delta: float) -> void:
	var want := is_ranged() and not GameSettings.menu_open and Input.is_action_pressed("block")
	if want != _aiming:
		_set_aiming(want)
	if not _aiming:
		if _aim_pose and _current == null and _charging == null:
			_aim_pose = false
			player.end_action()
		return
	_enter_combat()
	player.face_toward(aim_point, delta)
	# Between shots, hold the aiming pose (walking slowly).
	if not _aim_pose and _current == null and _charging == null and player.start_action(0.45):
		_aim_pose = true
		player.action_animation.emit("bow_aim", 0.0, 0.12, 1.0)


func _set_aiming(on: bool) -> void:
	if on == _aiming:
		return
	_aiming = on
	var cam := get_tree().get_first_node_in_group("player_camera")
	if cam and cam.has_method("set_aiming"):
		cam.call("set_aiming", on)
	if not GameSettings.gamepad:
		if on:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif not Input.is_action_pressed("camera_look"):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not on and _aim_pose and _current == null and _charging == null:
		_aim_pose = false
		player.end_action()
	aim_changed.emit(on)


## The point under the crosshair (screen centre), within the shot's range, and whether
## an enemy is there.
func _update_aim_point() -> void:
	aim_on_enemy = false
	if not is_ranged():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		aim_point = player.global_position - player.model.global_basis.z * 20.0
		return
	var reach := shot.reach if shot else 40.0
	var dir := -cam.global_basis.z
	# Start level with the player, so nothing between the camera and the player counts.
	var origin := cam.global_position + dir * maxf(dir.dot(player.global_position - cam.global_position), 0.0)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach, 1 | targeting.enemy_mask)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		aim_point = origin + dir * reach
	else:
		aim_point = hit.position
		var node := hit.collider as Node
		while node and not node.is_in_group(Combat.GROUP):
			node = node.get_parent()
		aim_on_enemy = node != null and Combat.is_alive(node) and Combat.is_enemy_of(player, node)
	if not aim_on_enemy and targeting.is_locked() and not _aiming:
		aim_on_enemy = targeting.target.global_position.distance_to(player.global_position) <= reach


## Crosshair for the HUD: shown with a hand-aimed ranged weapon out; red on an enemy in range.
func crosshair() -> Dictionary:
	return {"visible": is_manual_aim() and (in_combat or _aiming), "red": aim_on_enemy, "aiming": _aiming}


# --- Blocking ----------------------------------------------------------------

func _start_block() -> void:
	if not player.start_action(0.0):
		return
	# Blocking cancels the end of a swing.
	_current = null
	_queued = null
	_flourish = false
	_blocking = true
	_block_started = Time.get_ticks_msec()
	_enter_combat()
	player.action_animation.emit("block", 0.0, 0.1, 1.0)


func _update_block(delta: float) -> void:
	if not Input.is_action_pressed("block") or GameSettings.menu_open or is_ranged():
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
			if Time.get_ticks_msec() - _block_started <= int(parry_window * 1000.0):
				_parry(source as Node3D)
				return 0.0
			if block_stamina_per_hit <= 0.0 or stats.use_stamina(block_stamina_per_hit):
				FloatingText.spawn(player, "Blocked", Color(0.8, 0.85, 0.9), 0.8)
				return amount * (1.0 - clampf(block_reduction + stats.block, 0.0, 0.95))
			notice.emit("Guard broken")
			_end_block()
			player.action_animation.emit("hit_react", 0.0, 0.05, 1.0)
			return amount
	# Hit while casting or charging: light hits push the cast back, big or heavy hits interrupt.
	var heavy_hit := Combat.incoming_heavy or amount >= interrupt_share * stats.max_health
	if _channel:
		_interrupt("Interrupted")
		return amount
	if _casting:
		if heavy_hit:
			_interrupt("Interrupted")
			return amount
		_cast_time = maxf(_cast_time - cast_pushback, 0.0)
	elif _charging:
		if heavy_hit:
			_interrupt("Interrupted")
			return amount
	elif _current and not _hit_done and heavy_hit:
		_interrupt("Interrupted")
		return amount
	# Flinch when standing still and not busy.
	if player.state == PlayerController.State.NORMAL and player.is_on_floor() \
			and Vector2(player.velocity.x, player.velocity.z).length() < 0.5:
		player.action_animation.emit("hit_react", 0.0, 0.05, 1.0)
	return amount


## Stops a cast, charge or wind-up.
func _interrupt(reason: String, flinch := true) -> void:
	var ab: Ability = _casting if _casting else (_charging if _charging else _current)
	_stop_channel()
	if _casting:
		_end_cast()
		player.end_action()
	_cancel_charge()
	if _current:
		_finish_action()
	_attack_down = false
	if ab and not _is_weapon_move(ab):
		_cooldowns[ab] = maxf(cooldown_left(ab), 0.5)  # a short lockout
	cast_interrupted.emit(reason)
	FloatingText.spawn(player, reason, Color(1.0, 0.45, 0.4), 0.9)
	if flinch:
		player.action_animation.emit("hit_react", 0.0, 0.05, 1.0)


func _parry(attacker: Node3D) -> void:
	FloatingText.spawn(player, "Parry!", Color(0.7, 0.9, 1.0), 1.3)
	Combat.play_sound(player, Combat.BLOCK_SOUND, 0.0, 1.15)
	Effects.sparks(Combat.world_root(player), _hand_position(false), Color(0.85, 0.95, 1.0), 2.0, Vector3.UP)
	TimeFX.hit_stop(player, 0.12)
	var cam := get_tree().get_first_node_in_group("player_camera")
	if cam:
		cam.call("shake", 0.3)
	if attacker and attacker.has_method("stagger"):
		attacker.call("stagger", 1.4)
	grant_counter()


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
	if _channel:
		cast_interrupted.emit("Cancelled")
		_channel = null
	if _casting:
		cast_interrupted.emit("Cancelled")
		_end_cast()
	_flourish = false
	if _charging:
		_charging = null
		character.set_speed(1.0)
	_current = null
	_queued = null
	_blocking = false
	_aim_pose = false
	_attack_down = false
	player.action_velocity = Vector3.ZERO
