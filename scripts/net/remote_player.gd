class_name RemotePlayer
extends CharacterBody3D
## Another player in co-op, as seen on this machine: copies the position, facing,
## animation, health and gear their game sends (Net). On the host, enemies can target
## it; their hits are passed on to that player's game (forward_hit), which works out
## blocking, dodging and armour on the real character.

const LERP := 12.0

var peer_id := 0
var stats: Stats
var character: CharacterModel
var model: Node3D

var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _anim_seq := -1
var _has_state := false
var _sword: Node3D  # primary weapon
var _bow: Node3D  # secondary weapon
var _plate: Nameplate


static func create(id: int, info: Dictionary) -> RemotePlayer:
	var r := RemotePlayer.new()
	r.name = str(id)
	r.peer_id = id
	r.collision_layer = 0
	r.collision_mask = 0
	r.stats = Stats.new()
	r.stats.name = "Stats"
	r.stats.team = Stats.Team.PLAYERS
	r.stats.max_mana = 0.0
	r.add_child(r.stats)
	r.model = Node3D.new()
	r.model.name = "Model"
	r.add_child(r.model)
	var body := (load("res://assets/models/characters/base_bodies.scn") as PackedScene).instantiate()
	body.name = "Character"
	body.set_script(load("res://scripts/player/character_model.gd"))
	r.model.add_child(body)
	r.character = body as CharacterModel
	r.set_meta("info", info)
	return r


func _ready() -> void:
	add_to_group(Combat.GROUP)
	add_to_group("party_members")
	apply_info(get_meta("info", {}))
	_plate = Nameplate.attach(self)
	_target_pos = global_position


func aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


func is_alive() -> bool:
	return not stats.is_dead()


## Name, look, level and what they're wearing.
func apply_info(info: Dictionary) -> void:
	stats.display_name = String(info.get("name", "Player"))
	stats.level = int(info.get("level", 1))
	character.take_off_all()
	var look: Dictionary = info.get("look", {}) if info.get("look") is Dictionary else {}
	character.apply_appearance(Database.resolve_appearance(look))
	# Their backpack with their own achievement pins (sent with their info).
	character.set_backpack(PlayerGear.look_flag(look, "show_backpack"),
		Backpack.pins_of(info.get("pins", []) if info.get("pins") is Array else [], Database.achievements))
	var eq: Dictionary = info.get("equipment", {})
	for slot in ["head", "shoulders", "chest", "hands", "legs", "feet", "off_hand"]:
		if slot == "head" and not PlayerGear.look_flag(look, "show_helmet"):
			continue
		var item := Database.item(String(eq.get(slot, "")))
		if not item.is_empty():
			character.wear(item, slot)
	for node in [_sword, _bow]:
		if node and is_instance_valid(node):
			node.queue_free()
	_sword = _hand_weapon(Database.item(String(eq.get("primary", eq.get("main_hand", "")))))
	_bow = _hand_weapon(Database.item(String(eq.get("secondary", eq.get("ranged", "")))))
	if _plate:
		_plate.call("_refresh_label")


func _hand_weapon(item: Dictionary) -> Node3D:
	if item.is_empty():
		return null
	var bone := "mixamorig_LeftHand" if String(item.get("weapon_type", "")) == "bow" else "mixamorig_RightHand"
	var fits: Array = CharacterModel.fits_for(item, character.body_key())
	var node := character.attach_fitted(fits[0] if not fits.is_empty() else {"bone": bone, "grip": true}, String(item.get("model", "")))
	if node:
		node.visible = false
	return node


## [x, y, z, yaw, animation, animation number, position in it, speed, health, max health,
##  drawn (0 none, 1 primary, 2 secondary)]
func apply_state(s: Array) -> void:
	_target_pos = Vector3(s[0], s[1], s[2])
	_target_yaw = s[3]
	if not _has_state:
		_has_state = true
		global_position = _target_pos
		model.rotation.y = _target_yaw
	var anim := String(s[4])
	if int(s[5]) != _anim_seq and anim != "":
		_anim_seq = int(s[5])
		character.play_from(anim, float(s[6]), 0.12, 1.0)
	character.set_speed(float(s[7]) if float(s[7]) > 0.0 else 1.0)
	var was_dead := stats.is_dead()
	stats.max_health = float(s[9])
	stats.health = float(s[8])
	stats.health_changed.emit(stats.health, stats.max_health)
	if not was_dead and stats.is_dead():
		stats.died.emit()
	var drawn := int(s[10])
	if _sword and is_instance_valid(_sword):
		_sword.visible = drawn == 1
	if _bow and is_instance_valid(_bow):
		_bow.visible = drawn == 2


func _physics_process(delta: float) -> void:
	if not _has_state:
		return
	var t := 1.0 - exp(-LERP * delta)
	global_position = global_position.lerp(_target_pos, t)
	model.rotation.y = lerp_angle(model.rotation.y, _target_yaw, t)
	velocity = (_target_pos - global_position) * LERP  # so enemies can read how it moves


## Host only: an enemy's hit on this player is passed to their game to work out.
func forward_hit(source: Node3D, power: float, stagger: bool, knockback: float) -> bool:
	var net := get_tree().root.get_node_or_null("Net")
	if net and net.get("is_host") and source:
		net.call("forward_attack", peer_id, source, power, stagger, knockback)
	return true
