class_name Npc
extends CharacterBody3D
## A friendly character: villager, guard, quest giver, companion. Everything about it
## (name, look, gear, behaviour, whether it fights, its lines) comes from its entry in
## data/npcs.json (Database → NPCs); place scenes/npcs/npc.tscn in a level and set
## **Npc Id**.
##
## Behaviour: stand, wander near home, or patrol (Marker3D children of a "Patrol" node
## under it, walked in order). When enemies come close, NPCs that can fight and hold a
## weapon fight them (and enemies fight back); the rest run away until it's safe.
## Walk up and press Interact (E, A) to hear its lines.
##
## Followers (can_follow in its entry): talking offers "Follow me" / "Wait here". A follower
## keeps beside the player, runs to catch up, joins fights against enemies going for the
## player, and turns up next to the player if left far behind. Saved with the character.

enum AI { IDLE, FIGHT, FLEE, RETURN, TALK, DEAD, FOLLOW }

## Which entry in data/npcs.json this is.
@export var npc_id := "villager"

const TALK_RANGE := 2.6
## Beyond this (m) from the player, a follower catches up by appearing behind them.
const FOLLOW_TELEPORT := 35.0

signal follow_changed(following: bool)

@onready var stats: Stats = $Stats
@onready var character: CharacterModel = $Model/Character
@onready var model: Node3D = $Model

var ai := AI.IDLE
var data := {}
## A placed event showing this NPC on one of its pages (MapEvent "npc:<id>"): talking
## runs that page. Otherwise the NPC's own `event` (data/npcs.json) if it has one, else
## its lines.
var event_owner: Node = null
var target: Node3D = null  # who it's fighting or fleeing from
## The player hit it in danger mode: it fights (or flees from) them until it calms down.
var angry_at_player := false
## Looks at the player when they're this close (m); Database → Animations → Head turning overrides it.
const LOOK_RANGE := 6.0
var _gesture_wait := 0.5
var _player_looking := false
var armed := false

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _home := Vector3.ZERO
var _home_yaw := 0.0
var _wander_to := Vector3.ZERO
var _patrol: Array[Vector3] = []
var _patrol_index := 0
var _wait := 0.0
var _scan := 0.0
var _cooldown := 0.0
var _attack_time := -1.0
var _attack_hit := false
var _stagger := 0.0
var _walk := Vector3.ZERO
var _push := Vector3.ZERO
var _settled := false
var _plate: Nameplate
var _prompt: Label3D
var _weapon: Node3D
## The player it's following (null if not).
var leader: Node3D = null
var _since_hurt := 99.0
var _stuck_time := 0.0
var _stuck_from := Vector3.ZERO


func _ready() -> void:
	add_to_group("npcs")
	add_to_group("talkable")
	_home_yaw = model.rotation.y
	var patrol := get_node_or_null("Patrol")
	if patrol:
		for m in patrol.get_children():
			if m is Node3D:
				_patrol.append((m as Node3D).global_position)
	_apply_data(true)
	Database.changed.connect(func(which: String) -> void:
		if which == "npcs" or which == "appearance" or which == "items":
			_apply_data(false))
	stats.damaged.connect(_on_damaged)
	stats.died.connect(_on_died)
	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.pixel_size = 0.003
	_prompt.font_size = 36
	_prompt.outline_size = 10
	_prompt.no_depth_test = true
	_prompt.position = Vector3.UP * 2.55
	_prompt.visible = false
	add_child(_prompt)


## (Re)reads its entry: stats, look, gear, behaviour.
func _apply_data(refill: bool) -> void:
	data = Database.npc(npc_id)
	if data.is_empty():
		push_warning("Npc: no entry '%s' in data/npcs.json" % npc_id)
		return
	stats.display_name = String(data.get("name", "NPC"))
	stats.level = int(data.get("level", 1))
	stats.team = Stats.Team.PLAYERS
	stats.immortal = bool(data.get("immortal", false))
	var share := stats.health / maxf(stats.max_health, 1.0)
	stats.max_health = float(data.get("max_health", 100.0))
	stats.health = stats.max_health if refill else stats.max_health * share
	stats.health_changed.emit(stats.health, stats.max_health)
	# Only NPCs that fight are combatants (enemies go after them; they can be hurt).
	var fights := bool(data.get("can_fight", false))
	if fights and not is_in_group(Combat.GROUP):
		add_to_group(Combat.GROUP)
	elif not fights and is_in_group(Combat.GROUP):
		remove_from_group(Combat.GROUP)
	if fights and _plate == null:
		_plate = Nameplate.attach(self)
		Combat.show_numbers(self)
	if _plate:
		_plate.visible = fights
	_dress.call_deferred()


func _dress() -> void:
	character.take_off_all()
	character.apply_appearance(Database.resolve_appearance(data.get("look", {})))
	var eq: Dictionary = data.get("equipment", {})
	for slot in ["head", "shoulders", "chest", "hands", "legs", "feet", "off_hand"]:
		var item := Database.item(String(eq.get(slot, "")))
		if not item.is_empty():
			character.wear(item, slot)
	if _weapon and is_instance_valid(_weapon):
		_weapon.queue_free()
	_weapon = null
	var main := Database.item(String(eq.get("primary", eq.get("main_hand", ""))))
	armed = not main.is_empty()
	if armed:
		var fits: Array = main.get("fit", {}).get(character.body_key(), [])
		_weapon = character.attach_fitted(fits[0] if not fits.is_empty() else {"bone": "mixamorig_RightHand", "grip": true}, String(main.get("model", "")))
		_show_weapon()


## Weapons stay in hand unless the NPC's entry says to keep them away until a fight.
func _show_weapon() -> void:
	if _weapon and is_instance_valid(_weapon):
		_weapon.visible = ai == AI.FIGHT or not bool(data.get("weapon_hidden", false))


func _f(key: String, fallback: float) -> float:
	return float(data.get(key, fallback))


func aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


func is_alive() -> bool:
	return ai != AI.DEAD


# --- Talking ---------------------------------------------------------------------

func can_talk() -> bool:
	if DialogueBox.is_open or Time.get_ticks_msec() - DialogueBox.closed_at < 300:
		return false
	return ai != AI.DEAD and ai != AI.FIGHT and ai != AI.FLEE and not data.is_empty()


## Starts a conversation with the player.
func talk(player: Node3D) -> void:
	if not can_talk():
		return
	var lines: Array = data.get("dialogue", [])
	if lines.is_empty():
		lines = ["..."]
	ai = AI.TALK
	_walk = Vector3.ZERO
	_face(player.global_position, 0.0)
	if player.has_method("face_toward"):
		player.face_toward(global_position)
	character.play("idle", 0.25)
	# An event instead of plain lines.
	var runner: EventRunner = null
	if event_owner and is_instance_valid(event_owner):
		runner = event_owner.call("start", player, self)
	elif String(data.get("event", "")) != "":
		runner = MapEvent.run_event(String(data.event), self, player, String(data.get("name", "")))
	if runner:
		runner.finished.connect(_end_talk)
		return
	var choices := []
	if can_follow():
		if leader:
			choices = [["Wait here", func() -> String:
				follow(null)
				return String(data.get("wait_line", "I'll wait here."))], ["Keep following", func() -> String: return ""]]
		else:
			choices = [["Follow me", func() -> String:
				follow(player)
				return String(data.get("follow_line", "Lead the way."))], ["Goodbye", func() -> String: return ""]]
	DialogueBox.open(self, String(data.get("name", "")), String(data.get("title", "")), lines, func() -> void:
		if ai == AI.TALK:
			ai = AI.FOLLOW if leader else AI.IDLE
			_wait = randf_range(1.0, 3.0), choices)


func _end_talk() -> void:
	if ai == AI.TALK:
		ai = AI.FOLLOW if leader else AI.IDLE
		_wait = randf_range(1.0, 3.0)


# --- Physics and AI ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _settled:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 60.0, global_position + Vector3.DOWN * 100.0, 1)
		var ground := get_world_3d().direct_space_state.intersect_ray(q)
		if ground.is_empty():
			return
		_settled = true
		global_position = ground.position + Vector3.UP * 0.05
		_home = global_position
		_wander_to = _home
		if _saved_as_follower():
			var p := get_tree().get_first_node_in_group("player") as Node3D
			if p:
				follow(p, true)
	if data.is_empty():
		return
	_regen(delta)
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.5
	_scan -= delta
	if _scan <= 0.0 and ai in [AI.IDLE, AI.RETURN, AI.FOLLOW]:
		_scan = 0.3
		_look_for_threats()
	var move := Vector3.ZERO
	match ai:
		AI.IDLE:
			move = _idle(delta)
		AI.FIGHT:
			move = _fight(delta)
		AI.FLEE:
			move = _flee(delta)
		AI.RETURN:
			move = _return_home()
		AI.FOLLOW:
			move = _follow(delta)
		AI.TALK, AI.DEAD:
			pass
	_walk.x = lerpf(_walk.x, move.x, 10.0 * delta)
	_walk.z = lerpf(_walk.z, move.z, 10.0 * delta)
	velocity.x = _walk.x + _push.x
	velocity.z = _walk.z + _push.z
	_push = _push.move_toward(Vector3.ZERO, 16.0 * delta)
	if move.length() > 0.1:
		_face(global_position + move, delta)
	move_and_slide()
	_animate()
	_update_prompt()
	_update_head(delta)


func _look_for_threats() -> void:
	var radius := _f("aggro_radius", 12.0)
	var nearest: Node3D = null
	var best := radius
	var leader_target: Node3D = null
	if leader and is_instance_valid(leader):
		var tg := leader.get_node_or_null("Targeting")
		var pc := leader.get_node_or_null("PlayerCombat")
		if tg and pc and pc.get("in_combat"):
			leader_target = tg.get("target")
	for n in get_tree().get_nodes_in_group(Combat.GROUP):
		var node := n as Node3D
		var s := Combat.stats_of(node)
		if node == null or s == null or s.is_dead() or s.team != Stats.Team.ENEMIES or node.is_in_group("practice_targets"):
			continue
		if node.has_method("is_alive") and not node.is_alive():
			continue
		var d := node.global_position.distance_to(global_position)
		if leader and is_instance_valid(leader):
			# Following: help with whatever is fighting the player (or us), or what the player attacks.
			var their_target = node.get("target")
			var involved: bool = their_target == leader or their_target == self or node == leader_target
			if not involved or node.global_position.distance_to(leader.global_position) > 18.0:
				continue
			d = minf(d, radius - 0.01)
		if d < best:
			best = d
			nearest = node
	if nearest == null:
		return
	target = nearest
	if bool(data.get("can_fight", false)) and armed:
		ai = AI.FIGHT
	else:
		ai = AI.FLEE
		FloatingText.spawn(self, "Help!", Color(1.0, 0.85, 0.5), 0.9)
	_show_weapon()


func _idle(delta: float) -> Vector3:
	_wait -= delta
	if _wait > 0.0:
		return Vector3.ZERO
	match String(data.get("behaviour", "stand")):
		"wander":
			var to := _wander_to - global_position
			to.y = 0.0
			if to.length() < 0.4:
				_wait = randf_range(2.0, 6.0)
				var a := randf() * TAU
				_wander_to = _home + Vector3(cos(a), 0, sin(a)) * randf() * _f("wander_radius", 4.0)
				return Vector3.ZERO
			return to.normalized() * _f("walk_speed", 1.2)
		"patrol":
			if _patrol.is_empty():
				return Vector3.ZERO
			var to := _patrol[_patrol_index] - global_position
			to.y = 0.0
			if to.length() < 0.5:
				_patrol_index = (_patrol_index + 1) % _patrol.size()
				_wait = randf_range(1.5, 3.5)
				return Vector3.ZERO
			return to.normalized() * _f("walk_speed", 1.2)
		_:
			# Standing: drift back to the spot and face the way it was placed.
			var to := _home - global_position
			to.y = 0.0
			if to.length() > 0.5:
				return to.normalized() * _f("walk_speed", 1.2)
			model.rotation.y = lerp_angle(model.rotation.y, _home_yaw, 3.0 * delta)
			return Vector3.ZERO


func _target_valid() -> bool:
	return target != null and is_instance_valid(target) and Combat.is_alive(target) \
		and (not target.has_method("is_alive") or target.is_alive())


func _fight(delta: float) -> Vector3:
	if _stagger > 0.0:
		_stagger -= delta
		return Vector3.ZERO
	if _attack_time >= 0.0:
		_attacking(delta)
		return Vector3.ZERO
	var anchor := leader.global_position if leader and is_instance_valid(leader) else _home
	if not _target_valid() or global_position.distance_to(anchor) > _f("leash_distance", 30.0):
		_calm_down()
		return Vector3.ZERO
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() <= _f("attack_range", 2.0):
		_face(target.global_position, delta)
		if _cooldown <= 0.0:
			_attack_time = 0.0
			_attack_hit = false
			character.play_from(String(data.get("attack_animation", "attack_light_1")), 0.0, 0.1, _f("attack_animation_speed", 1.0))
		return Vector3.ZERO
	return to.normalized() * _f("run_speed", 4.0)


func _attacking(delta: float) -> void:
	var anim := String(data.get("attack_animation", "attack_light_1"))
	_attack_time += delta * _f("attack_animation_speed", 1.0)
	if not _attack_hit and _target_valid():
		_face(target.global_position, delta * 0.5)
	if not _attack_hit and _attack_time >= _f("attack_hit_time", 0.32):
		_attack_hit = true
		if _target_valid() and target.global_position.distance_to(global_position) <= _f("attack_range", 2.0) + 0.6:
			Combat.hit(self, target, _f("attack_power", 8.0), false, 2.5)
	if _attack_time >= maxf(character.get_animation_length(anim), _f("attack_hit_time", 0.32) + 0.2):
		_attack_time = -1.0
		_cooldown = _f("attack_cooldown", 1.5) * randf_range(0.8, 1.2)


func _flee(_delta: float) -> Vector3:
	if not _target_valid():
		_calm_down()
		return Vector3.ZERO
	var away := global_position - target.global_position
	away.y = 0.0
	if away.length() > _f("aggro_radius", 10.0) + 6.0:
		_calm_down()
		return Vector3.ZERO
	return away.normalized() * _f("run_speed", 4.5)


func _calm_down() -> void:
	angry_at_player = false
	target = null
	_attack_time = -1.0
	ai = AI.FOLLOW if leader else AI.RETURN
	_show_weapon()


func _return_home() -> Vector3:
	var to := _home - global_position
	to.y = 0.0
	if to.length() < 0.8:
		ai = AI.IDLE
		_wait = randf_range(1.0, 3.0)
		return Vector3.ZERO
	return to.normalized() * _f("run_speed", 4.0) * 0.6


# --- Being hit ------------------------------------------------------------------------

func apply_knockback(push: Vector3) -> void:
	if ai != AI.DEAD:
		_push = push


func stagger(seconds := 0.6) -> void:
	if ai == AI.FIGHT:
		_stagger = seconds
		_attack_time = -1.0
		character.play_from("hit_react", 0.0, 0.05, 0.9)


func _on_damaged(_amount: float, source: Node, _crit: bool) -> void:
	_since_hurt = 0.0
	# Attacked by the player (danger mode): turn on them, and stop following them.
	if source and source.is_in_group("player") and not angry_at_player:
		angry_at_player = true
		if leader == source:
			follow(null, true)
		if ai != AI.DEAD:
			ai = AI.IDLE  # so the check below starts the fight
	# Hit by an enemy: fight back (or run).
	if ai in [AI.IDLE, AI.RETURN, AI.TALK, AI.FOLLOW] and source is Node3D and Combat.is_enemy_of(self, source):
		target = source
		ai = AI.FIGHT if bool(data.get("can_fight", false)) and armed else AI.FLEE
		_show_weapon()


func _on_died() -> void:
	ai = AI.DEAD
	angry_at_player = false
	target = null
	collision_layer = 0
	_walk = Vector3.ZERO
	character.play_from("death", 0.0, 0.15, 1.0)
	await get_tree().create_timer(6.0).timeout
	model.visible = false
	await get_tree().create_timer(maxf(_f("respawn_time", 30.0) - 6.0, 0.0)).timeout
	global_position = _home
	if leader and is_instance_valid(leader):
		_appear_near_leader()
	stats.restore()
	collision_layer = 2
	model.visible = true
	ai = AI.FOLLOW if leader else AI.IDLE
	character.play("idle", 0.0)


# --- Following -----------------------------------------------------------------------

func can_follow() -> bool:
	return bool(data.get("can_follow", false))


## Starts (or stops, with null) following a player.
func follow(who: Node3D, quietly := false) -> void:
	leader = who
	if leader:
		add_to_group("followers")
		ai = AI.FOLLOW
		_stuck_time = 0.0
	else:
		remove_from_group("followers")
		_home = global_position  # waits here
		_wander_to = _home
		ai = AI.IDLE
		_wait = 2.0
	if not quietly:
		_remember_follower(leader != null)
	follow_changed.emit(leader != null)


func _saved_as_follower() -> bool:
	var session := get_tree().root.get_node_or_null("GameSession")
	return session != null and session.call("active") and npc_id in (session.get("data") as Dictionary).get("followers", [])


func _remember_follower(on: bool) -> void:
	var session := get_tree().root.get_node_or_null("GameSession")
	if session == null or not session.call("active"):
		return
	var d: Dictionary = session.get("data")
	var list: Array = d.get("followers", [])
	list.erase(npc_id)
	if on:
		list.append(npc_id)
	d["followers"] = list
	session.call("save_game")


## Where a follower stands relative to the player: behind and to one side (each
## follower its own side and distance).
func _follow_spot() -> Vector3:
	var index := get_tree().get_nodes_in_group("followers").find(self)
	var basis := (leader.get_node("Model") as Node3D).global_basis if leader.has_node("Model") else leader.global_basis
	var back := basis.z
	back.y = 0.0
	back = back.normalized()
	var side := Vector3.UP.cross(back).normalized()
	var lane := 1.0 if index % 2 == 0 else -1.0
	return leader.global_position + back * (2.0 + 0.9 * (index / 2)) + side * lane * 1.3


func _follow(delta: float) -> Vector3:
	if leader == null or not is_instance_valid(leader):
		follow(null)
		return Vector3.ZERO
	var to_leader := leader.global_position - global_position
	var far := Vector2(to_leader.x, to_leader.z).length()
	if far > FOLLOW_TELEPORT or (far > 12.0 and absf(to_leader.y) > 8.0):
		_appear_near_leader()
		return Vector3.ZERO
	# The player is swimming or climbing: wait at the edge, catch up afterwards.
	var leader_state = leader.get("state")
	if leader_state != null and leader_state not in [PlayerController.State.NORMAL, PlayerController.State.ACTION, PlayerController.State.DODGE]:
		_face(leader.global_position, delta)
		return Vector3.ZERO
	var to := _follow_spot() - global_position
	to.y = 0.0
	if to.length() < 0.7:
		_stuck_time = 0.0
		var leader_dir := -(leader.get_node("Model") as Node3D).global_basis.z if leader.has_node("Model") else Vector3.FORWARD
		_face(global_position + leader_dir, delta * 0.5)
		return Vector3.ZERO
	# Stuck behind something while the player gets away: catch up by appearing nearby.
	_stuck_time += delta
	if _stuck_time > 2.5:
		if global_position.distance_to(_stuck_from) < 1.0 and far > 6.0:
			_appear_near_leader()
			return Vector3.ZERO
		_stuck_time = 0.0
		_stuck_from = global_position
	var leader_speed := Vector2(leader.velocity.x, leader.velocity.z).length() if leader is CharacterBody3D else 0.0
	var speed := clampf(leader_speed, _f("walk_speed", 1.2), _f("run_speed", 4.2))
	if far > 7.0 or to.length() > 4.0:
		speed = _f("run_speed", 4.2) * 1.25  # catching up
	return to.normalized() * minf(speed, to.length() * 4.0)


## Puts a follower just behind the player, on the ground.
func _appear_near_leader() -> void:
	var spot := _follow_spot()
	var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 4.0, spot + Vector3.DOWN * 10.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	global_position = (hit.position + Vector3.UP * 0.05) if not hit.is_empty() else leader.global_position
	_walk = Vector3.ZERO
	_stuck_time = 0.0
	_stuck_from = global_position


## Out of a fight for a few seconds: health comes back.
func _regen(delta: float) -> void:
	_since_hurt += delta
	if _since_hurt > 5.0 and ai != AI.FIGHT and ai != AI.DEAD and stats.health < stats.max_health:
		stats.heal(stats.max_health * 0.08 * delta)


# --- Looks -----------------------------------------------------------------------------

func _face(point: Vector3, delta: float) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var yaw := atan2(-dir.x, -dir.z)
	model.rotation.y = yaw if delta <= 0.0 else lerp_angle(model.rotation.y, yaw, 8.0 * delta)


func _animate() -> void:
	if ai == AI.DEAD or _attack_time >= 0.0 or _stagger > 0.0:
		return
	var current := character.current_animation()
	# Let a talking gesture finish.
	if ai == AI.TALK and current.begins_with("talk_") and character.animation_position() < character.get_animation_length(current) - 0.25:
		return
	if current == "hit_react" and character.animation_position() < 0.4:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.3:
		character.play("idle_armed" if ai == AI.FIGHT else "idle", 0.25)
	elif speed < 2.6:
		character.play("walking", 0.2, clampf(speed / 1.4, 0.6, 1.5))
	else:
		character.play("running", 0.2, clampf(speed / 4.5, 0.8, 1.4))


## Looks at the player when they come close (or at whoever it's fighting), and while
## talking also nods along, gestures now and then, and has the player look back.
func _update_head(delta: float) -> void:
	var look := character.head_look()
	if look == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var at: Node3D = null
	if ai == AI.TALK:
		at = player
	elif ai == AI.FIGHT and target and is_instance_valid(target):
		at = target
	elif player and ai in [AI.IDLE, AI.RETURN, AI.FOLLOW] \
			and player.global_position.distance_to(global_position) < float(Database.look_settings().get("range", LOOK_RANGE)):
		at = player
	look.forward = -model.global_basis.z
	look.looking = at != null
	look.talking = ai == AI.TALK
	if at:
		look.target_position = _head_of(at)
	# Gestures while talking.
	if ai == AI.TALK:
		_gesture_wait -= delta
		if _gesture_wait <= 0.0 and character.current_animation() == "idle":
			_gesture_wait = randf_range(1.5, 3.5)
			character.play(_random_talk(), 0.3)
	else:
		_gesture_wait = randf_range(0.4, 1.0)
	# The player looks back at whoever they're talking to.
	if player and (ai == AI.TALK or _player_looking):
		var pc := player.get_node_or_null("Model/Character") as CharacterModel
		var plook := pc.head_look() if pc else null
		if plook:
			_player_looking = ai == AI.TALK
			plook.looking = _player_looking
			plook.forward = -(player.get_node("Model") as Node3D).global_basis.z
			plook.target_position = _head_of(self)


## One of the talk_1, talk_2... clips this body has.
func _random_talk() -> String:
	var n := 1
	while character.has_animation("talk_%d" % (n + 1)):
		n += 1
	return "talk_%d" % randi_range(1, n)


## Roughly where a character's eyes are.
func _head_of(who: Node3D) -> Vector3:
	var cm := who.get_node_or_null("Model/Character") as CharacterModel
	var skel := cm.get_skeleton() if cm else null
	if skel:
		var bone := skel.find_bone("mixamorig_Head")
		if bone >= 0:
			return skel.global_transform * skel.get_bone_global_pose(bone).origin + Vector3.UP * 0.08
	return Combat.aim_point(who) + Vector3.UP * 0.4


## "E  Talk" over its head while the player is close and could talk.
func _update_prompt() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var show := player != null and can_talk() and ai != AI.TALK \
		and player.global_position.distance_to(global_position) <= TALK_RANGE
	_prompt.visible = show
	if show:
		var key := GameSettings.interact_label()
		var title := String(data.get("title", ""))
		_prompt.text = "%s  Talk to %s%s" % [key, data.get("name", ""), (" (%s)" % title) if title != "" else ""]
