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

enum AI { IDLE, FIGHT, FLEE, RETURN, TALK, DEAD, FOLLOW, DOWNED }

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
var _heal_who: Node3D = null
var _fight_stuck := 0.0
var _rethink := 0.0
var _stuck_from := Vector3.ZERO
## Its spells and skills (data "abilities"), their cooldowns, and the one going off.
var _spells: Array[Ability] = []
var _spell_cooldowns := {}  # Ability -> seconds left
var _casting: Ability = null


func _ready() -> void:
	add_to_group("npcs")
	add_to_group("talkable")
	if not Engine.is_editor_hint():
		add_child(QuestMarker.new("", npc_id))
		DispositionDisc.attach(self)
	var patrol := get_node_or_null("Patrol")
	if patrol:
		for m in patrol.get_children():
			if m is Node3D:
				_patrol.append((m as Node3D).global_position)
	if not Engine.is_editor_hint():
		_fold_yaw()
	_home_yaw = model.rotation.y
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
	_spells = Database.abilities_for(data.get("abilities", []))
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
	return ai != AI.DEAD and ai != AI.DOWNED  # downed companions are out of the fight


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
	for ab: Ability in _spell_cooldowns:
		_spell_cooldowns[ab] = maxf(float(_spell_cooldowns[ab]) - delta, 0.0)
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
			if _attack_time >= 0.0:
				_attacking(delta)  # a heal cast while following
			else:
				move = _follow(delta)
				_heal_while_following()
		AI.DOWNED:
			move = _downed(delta)
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
	_unstick_in_fight(move, delta)
	_animate()
	_update_prompt()
	_update_head(delta)


func _look_for_threats() -> void:
	if leader and is_instance_valid(leader):
		var pick := _choose_target()
		if pick:
			target = pick
			ai = AI.FIGHT
			_show_weapon()
		return
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
		if node.has_meta("player_struck") and node.get("target") != self:
			continue  # the player's fight
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
	if bool(data.get("can_fight", false)) and (armed or not _spells.is_empty()):
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
	if leader and is_instance_valid(leader):
		_rethink -= delta
		if _rethink <= 0.0 or not _target_valid():
			_rethink = 0.5
			var pick := _choose_target()
			if pick == null:
				_calm_down()  # nothing that needs us: back to the player's side
				return Vector3.ZERO
			target = pick
	elif _target_valid() and target.has_meta("player_struck") and target.get("target") != self:
		_calm_down()  # the player took this one on: leave it to them
		return Vector3.ZERO
	if not _target_valid() or global_position.distance_to(anchor) > _f("leash_distance", 30.0):
		_calm_down()
		return Vector3.ZERO
	var to := target.global_position - global_position
	to.y = 0.0
	var spell := _pick_spell(to.length())
	if spell:
		_face(target.global_position, delta)
		_start_spell(spell)
		return Vector3.ZERO
	if to.length() <= _f("attack_range", 2.0) and armed:
		_face(target.global_position, delta)
		if _cooldown <= 0.0:
			_attack_time = 0.0
			_attack_hit = false
			_casting = null
			character.play_from(String(data.get("attack_animation", "attack_light_1")), 0.0, 0.1, _f("attack_animation_speed", 1.0))
		return Vector3.ZERO
	# Casters without a weapon (and archers: npcs.json keeps_distance) keep their distance.
	if (not armed or bool(data.get("keeps_distance", false))) and _has_ranged() and to.length() <= _ranged_reach() * 0.85:
		_face(target.global_position, delta)
		return Vector3.ZERO
	return to.normalized() * _f("run_speed", 4.0)


## A spell or skill it can use now: heals when hurt, projectiles in range (melee
## fighters use them from beyond arm's reach), ready and off cooldown.
func _pick_spell(distance: float) -> Ability:
	for ab: Ability in _spells:
		if float(_spell_cooldowns.get(ab, 0.0)) > 0.0 or _cooldown > 0.0:
			continue
		match ab.delivery:
			Ability.Delivery.HEAL_OVER_TIME:
				var who := _heal_target(ab)
				if who:
					_heal_who = who
					return ab
			Ability.Delivery.PROJECTILE:
				if distance <= ab.reach and (not armed or distance > _f("attack_range", 2.0) * 1.5):
					return ab
			Ability.Delivery.MELEE:
				if distance <= ab.reach:
					return ab
	return null


## How companions pick fights (npcs.json party settings in player.json "companions"):
## - only enemies the player has struck, or that are attacking the player or the party;
## - not the one the player is fighting (let them have it), unless the player is below
##   half health, it's a boss, or it's the only threat and it's attacking us;
## - not one that's nearly dead (the player should land the kill), unless it's on us.
func _choose_target() -> Node3D:
	if SafeArea.protects(self):
		return null  # nothing can be fought from a safe area
	var cfg: Dictionary = Database.player.get("companions", {})
	var help_below := float(cfg.get("help_below", 0.5))
	var leave_below := float(cfg.get("leave_kill_below", 0.25))
	var lstats := Combat.stats_of(leader)
	var leader_hurt := lstats != null and lstats.health / maxf(lstats.max_health, 1.0) < help_below
	var focus := _leader_focus()
	var best: Node3D = null
	var best_score := INF
	for n in get_tree().get_nodes_in_group(Combat.GROUP):
		var e := n as Node3D
		var st := Combat.stats_of(e)
		if e == null or st == null or st.is_dead() or st.team != Stats.Team.ENEMIES or e.is_in_group("practice_targets"):
			continue
		if e.has_method("is_alive") and not e.is_alive():
			continue
		if e.global_position.distance_to(leader.global_position) > float(cfg.get("range", 20.0)):
			continue
		var their_target = e.get("target")
		var on_us: bool = their_target == self
		var on_party: bool = on_us or their_target == leader or (their_target is Node and (their_target as Node).is_in_group("followers"))
		var struck := e.has_meta("player_struck")
		if not on_party and not struck:
			continue  # wait for the player to start it
		if bool(cfg.get("wait_for_player", true)) and not on_us and not _player_fighting():
			continue  # the player hasn't struck anything yet: hold back
		var boss := bool(Database.enemy(String(e.get("enemy_id"))).get("boss", false)) if e.get("enemy_id") != null else false
		var share := st.health / maxf(st.max_health, 1.0)
		if share < leave_below and not on_us and not leader_hurt and not boss:
			continue  # nearly dead: the player's kill
		var score := e.global_position.distance_to(global_position)
		if e == focus and not boss and not leader_hurt:
			if not on_us:
				continue  # the player's fight
			score += 50.0
		if their_target != null and their_target != leader and their_target != self:
			score -= 3.0  # help a friend first
		if score < best_score:
			best_score = score
			best = e
	return best


## The player has landed a blow in the last 20 seconds.
func _player_fighting() -> bool:
	var pc := leader.get_node_or_null("PlayerCombat") if leader else null
	return pc != null and Time.get_ticks_msec() - int(pc.get("last_strike_msec")) < 20000


## The enemy the player is fighting: their target, else what they hit last.
func _leader_focus() -> Node3D:
	var tg := leader.get_node_or_null("Targeting")
	var t = tg.get("target") if tg else null
	if t is Node3D and is_instance_valid(t) and Combat.is_alive(t):
		return t
	var pc := leader.get_node_or_null("PlayerCombat")
	var last = pc.get("last_struck") if pc else null
	if last is Node3D and is_instance_valid(last) and Combat.is_alive(last):
		return last
	return null


# --- Downed companions --------------------------------------------------------------
## Out of health while following: limps to cover (shared with any other downed companion,
## behind a rock or tree from the enemies), waits there out of the fight, and gets back
## up once healed above player.json companions.recover_share or when the fight is over.
static var _cover := Vector3.INF
static var _cover_time := 0
var _downed_quiet := 0.0


func is_downed() -> bool:
	return ai == AI.DOWNED


func _go_down() -> void:
	ai = AI.DOWNED
	target = null
	_attack_time = -1.0
	_casting = null
	_downed_quiet = 0.0
	stats.health = 1.0
	stats.health_changed.emit(stats.health, stats.max_health)
	FloatingText.spawn(self, "Down!", Color(1.0, 0.45, 0.35), 1.2)
	GameLog.post("%s is down and falls back to cover." % stats.display_name, Color(1.0, 0.6, 0.5))
	# Enemies let go of it.
	for n in get_tree().get_nodes_in_group(Combat.GROUP):
		if n.get("target") == self and n.has_method("_give_up"):
			var t = n.get("threat")
			if t is Dictionary:
				(t as Dictionary).erase(self)
			n.set("target", null)
	if Time.get_ticks_msec() - _cover_time > 20000 or _cover == Vector3.INF:
		_cover = _find_cover()
		_cover_time = Time.get_ticks_msec()


func _downed(delta: float) -> Vector3:
	var cfg: Dictionary = Database.player.get("companions", {})
	if stats.health >= stats.max_health * float(cfg.get("recover_share", 0.3)):
		_recover()
		return Vector3.ZERO
	# The fight is over (nothing fighting the party nearby): get back up.
	if _party_in_fight():
		_downed_quiet = 0.0
	else:
		_downed_quiet += delta
		if _downed_quiet > float(cfg.get("recover_after", 4.0)):
			stats.health = maxf(stats.health, stats.max_health * float(cfg.get("recover_share", 0.3)))
			stats.health_changed.emit(stats.health, stats.max_health)
			_recover()
			return Vector3.ZERO
	# Spread out a little around the shared cover spot.
	var spot := _cover + Vector3(sin(get_instance_id() % 7), 0, cos(get_instance_id() % 7)) * 1.2
	var to := spot - global_position
	to.y = 0.0
	if to.length() < 0.6:
		return Vector3.ZERO
	return to.normalized() * float(cfg.get("downed_speed", 1.6))


func _recover() -> void:
	ai = AI.FOLLOW if leader else AI.IDLE
	FloatingText.spawn(self, "Back on my feet!", Color(0.6, 1.0, 0.6), 1.0)
	_show_weapon()


func _party_in_fight() -> bool:
	var anchor: Node3D = leader if leader and is_instance_valid(leader) else self
	for n in get_tree().get_nodes_in_group(Combat.GROUP):
		var t = n.get("target")
		if t is Node and (t == anchor or (t as Node).is_in_group("followers")) and Combat.is_alive(n) \
				and (n as Node3D).global_position.distance_to(anchor.global_position) < 35.0:
			return true
	return false


## Somewhere the enemies can't see: try spots around (away from the enemies first) and
## prefer one where the line from the enemies is blocked by the world (rock, tree, wall).
func _find_cover() -> Vector3:
	var anchor: Node3D = leader if leader and is_instance_valid(leader) else self
	var foes := Vector3.ZERO
	var count := 0
	for n in get_tree().get_nodes_in_group(Combat.GROUP):
		var e := n as Node3D
		if e and Combat.is_alive(e) and Combat.is_enemy_of(self, e) and e.global_position.distance_to(anchor.global_position) < 40.0:
			foes += e.global_position
			count += 1
	var space := get_world_3d().direct_space_state
	if count == 0:
		return global_position
	foes /= count
	var away := anchor.global_position - foes
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.BACK
	var best := global_position + away * 10.0
	var best_score := -INF
	for angle in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5]:
		for dist in [8.0, 12.0, 16.0]:
			var flat: Vector3 = anchor.global_position + away.rotated(Vector3.UP, angle) * dist
			var q := PhysicsRayQueryParameters3D.create(flat + Vector3.UP * 20.0, flat + Vector3.DOWN * 40.0, 1)
			var ground := space.intersect_ray(q)
			if ground.is_empty():
				continue
			var spot: Vector3 = ground.position
			if spot.y < -4.5:
				continue  # not in the sea
			var look := PhysicsRayQueryParameters3D.create(foes + Vector3.UP * 1.5, spot + Vector3.UP * 1.0, 1)
			var blocked := not space.intersect_ray(look).is_empty()
			var score := spot.distance_to(foes) * 0.3 + (20.0 if blocked else 0.0) - absf(angle) * 2.0
			if score > best_score:
				best_score = score
				best = spot
	return best


## Combat.hit asks this: a companion never lands the killing blow while the player is
## around and doing fine (it leaves the enemy on 1 health).
func spares_kill(victim: Node) -> bool:
	if not bool(Database.player.get("companions", {}).get("leave_kills", true)):
		return false
	if leader == null or not is_instance_valid(leader):
		# Guards and other NPCs: leave the player's enemies to the player when they're near.
		var p := get_tree().get_first_node_in_group("player") as Node3D
		return p != null and victim.has_meta("player_struck") and Combat.is_alive(p) \
			and (victim as Node3D).global_position.distance_to(p.global_position) < 25.0
	var lstats := Combat.stats_of(leader)
	if lstats == null or lstats.is_dead():
		return false
	if victim is Node3D and (victim as Node3D).global_position.distance_to(leader.global_position) > 25.0:
		return false
	return lstats.health / maxf(lstats.max_health, 1.0) >= float(Database.player.get("companions", {}).get("help_below", 0.5)) * 0.6


## Following with a heal ready: patch up whoever needs it.
func _heal_while_following() -> void:
	if _cooldown > 0.0:
		return
	for ab: Ability in _spells:
		if ab.delivery != Ability.Delivery.HEAL_OVER_TIME or float(_spell_cooldowns.get(ab, 0.0)) > 0.0:
			continue
		var who := _heal_target(ab)
		if who:
			_heal_who = who
			_face(who.global_position, 1.0)
			_start_spell(ab)
			return


## Who a heal should go to: the most hurt of itself, its leader and the leader's other
## followers within the spell's reach, once they're below npcs.json `heal_below` (0.6).
func _heal_target(ab: Ability) -> Node3D:
	var below := _f("heal_below", 0.6)
	var group: Array = [self]
	if leader and is_instance_valid(leader):
		group.append(leader)
		for f in get_tree().get_nodes_in_group("followers"):
			if f != self and f.get("leader") == leader:
				group.append(f)
	var best: Node3D = null
	var best_share := below
	for n in group:
		var st := Combat.stats_of(n)
		if st == null or st.is_dead() or (n as Node3D).global_position.distance_to(global_position) > maxf(ab.reach, 4.0):
			continue
		var share := st.health / maxf(st.max_health, 1.0)
		if share < best_share:
			best_share = share
			best = n
	return best


func _has_ranged() -> bool:
	for ab: Ability in _spells:
		if ab.delivery == Ability.Delivery.PROJECTILE:
			return true
	return false


func _ranged_reach() -> float:
	var r := 0.0
	for ab: Ability in _spells:
		if ab.delivery == Ability.Delivery.PROJECTILE:
			r = maxf(r, ab.reach)
	return r


func _start_spell(ab: Ability) -> void:
	_casting = ab
	_attack_time = 0.0
	_attack_hit = false
	# Spells with a cast time play the casting loop first, then their own clip.
	var anim := ab.animation if ab.animation != "" else "cast_channel"
	character.play_from(anim, 0.0, 0.1, ab.animation_speed)
	if ab.cast_loop_sound and ab.cast_time > 0.0:
		Combat.play_sound(self, ab.cast_loop_sound, -8.0)


func _spell_goes_off(ab: Ability) -> void:
	var power := ab.power * (1.0 + 0.1 * (stats.level - 1))
	if ab.release_sound:
		Combat.play_sound(self, ab.release_sound, -4.0)
	elif ab.sounds.size() > 0:
		Combat.play_sound(self, ab.sounds.pick_random(), -4.0)
	match ab.delivery:
		Ability.Delivery.HEAL_OVER_TIME:
			var who: Node3D = _heal_who if _heal_who and is_instance_valid(_heal_who) and Combat.is_alive(_heal_who) else self
			var st := Combat.stats_of(who)
			if st:
				st.add_heal_over_time(power, ab.ticks, ab.tick_interval, ab)
				Effects.heal_glow(who, ab.ticks * ab.tick_interval)
				AbilityFX.landed(ab, who)
				Combat.heal_threat(self, power * ab.ticks)
			_heal_who = null
		Ability.Delivery.PROJECTILE:
			if _target_valid():
				var from := global_position + Vector3.UP * 1.4 - model.global_basis.z * 0.5
				Projectile.launch(from, self, target, ab, power, Combat.aim_point(target) - from)
		Ability.Delivery.MELEE:
			if _target_valid() and target.global_position.distance_to(global_position) <= ab.reach + 0.6:
				Combat.hit(self, target, power, ab.staggers, ab.knockback, Ability.applies_of(ab))


func _attacking(delta: float) -> void:
	if _casting:
		_spell_step(delta)
		return
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


func _spell_step(delta: float) -> void:
	var ab := _casting
	var anim := ab.animation if ab.animation != "" else "cast_channel"
	_attack_time += delta * ab.animation_speed
	if _target_valid() and ab.delivery != Ability.Delivery.HEAL_OVER_TIME:
		_face(target.global_position, delta)
	var fire_at := ab.cast_time + ab.hit_time
	if not _attack_hit and _attack_time >= fire_at:
		_attack_hit = true
		_spell_goes_off(ab)
	if _attack_time >= maxf(fire_at + 0.3, minf(character.get_animation_length(anim), fire_at + ab.recovery_time + 0.4)):
		_attack_time = -1.0
		_casting = null
		_spell_cooldowns[ab] = maxf(ab.cooldown, 1.5)
		_cooldown = _f("attack_cooldown", 1.5) * randf_range(0.6, 1.0)


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
	_casting = null
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
		_casting = null
		character.play_from("hit_react", 0.0, 0.05, 0.9)


func _on_damaged(_amount: float, source: Node, _crit: bool) -> void:
	_since_hurt = 0.0
	if leader and ai != AI.DOWNED and ai != AI.DEAD and stats.health <= 1.0:
		_go_down()
		return
	if ai == AI.DOWNED:
		return
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
		ai = AI.FIGHT if bool(data.get("can_fight", false)) and (armed or not _spells.is_empty()) else AI.FLEE
		_show_weapon()


func _on_died() -> void:
	ai = AI.DEAD
	angry_at_player = false
	target = null
	collision_layer = 0
	_walk = Vector3.ZERO
	character.play_from("death", 0.0, 0.15, 1.0)
	_casting = null
	# Its loot (gold, items it carries), like an enemy's.
	if int(data.get("gold_max", 0)) > 0 or not (data.get("loot", []) as Array).is_empty():
		LootBag.drop_for(data, Combat.world_root(self), global_position, self)
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
		# Companions don't die: at 0 health they go down and crawl to cover.
		if not stats.has_meta("own_immortal"):
			stats.set_meta("own_immortal", stats.immortal)
		stats.immortal = true
	else:
		remove_from_group("followers")
		if ai == AI.DOWNED:
			_recover()
		if stats.has_meta("own_immortal"):
			stats.immortal = bool(stats.get_meta("own_immortal"))
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


## Running at a fight but not getting anywhere (caught on a rock): after a moment, appear
## a little way from the target on the open side.
func _unstick_in_fight(move: Vector3, delta: float) -> void:
	if ai != AI.FIGHT or move.length() < 0.5 or not _target_valid():
		_fight_stuck = 0.0
		return
	if Vector2(get_real_velocity().x, get_real_velocity().z).length() > 0.6:
		_fight_stuck = 0.0
		return
	_fight_stuck += delta
	if _fight_stuck < 2.0:
		return
	_fight_stuck = 0.0
	var keep := _ranged_reach() * 0.6 if (not armed or bool(data.get("keeps_distance", false))) and _has_ranged() else _f("attack_range", 2.0) + 0.5
	var from_dir := global_position - target.global_position
	from_dir.y = 0.0
	from_dir = from_dir.normalized().rotated(Vector3.UP, randf_range(-1.2, 1.2)) if from_dir.length() > 0.1 else Vector3.BACK
	var spot := target.global_position + from_dir * (keep + Combat.radius_of(target))
	var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 6.0, spot + Vector3.DOWN * 12.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position + Vector3.UP * 0.05
		_walk = Vector3.ZERO


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

## A character turned in the level (the root rotated, e.g. to face the player) would walk
## sideways, since facing sets the model's own yaw: move that turn onto the model.
func _fold_yaw() -> void:
	var yaw := rotation.y
	if absf(yaw) < 0.0001:
		return
	rotation.y = 0.0
	model.rotation.y += yaw


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
	if ai == AI.DOWNED:
		if speed < 0.3:
			character.play("injured_idle" if character.has_animation("injured_idle") else "idle", 0.3)
		else:
			character.play("injured_walk" if character.has_animation("injured_walk") else "walking", 0.25, clampf(speed / float(Database.animations.get("injured", {}).get("speed", 0.8)), 0.6, 1.8))
		return
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
	var show: bool = player != null and can_talk() and ai != AI.TALK and player.get("talk_focus") == self
	_prompt.visible = show
	if show:
		var key := GameSettings.interact_label()
		var title := String(data.get("title", ""))
		_prompt.text = "%s  Talk to %s%s" % [key, data.get("name", ""), (" (%s)" % title) if title != "" else ""]
