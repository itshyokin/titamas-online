class_name Enemy
extends CharacterBody3D
## A basic melee enemy. Wanders near its spawn point; chases players who come close
## or hit it; attacks with a telegraphed swing (dodge or block it); gives up and
## walks home if dragged too far (healing to full); dies, then respawns later.
## The Stats child holds its name, level and health.

enum AI { IDLE, CHASE, ATTACK, STAGGER, RETURN, DEAD, DOWN }

## Which entry in data/enemies.json this is (name, level, health, speeds, attack...).
## Edit those with the Database editor; the values below are only fallbacks.
@export var enemy_id := "bandit"
## This game's player (or a follower) hit it since it last spawned: its death gives them experience.
var tagged_by_player := false

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

## How hard its hits push (m/s).
@export var knockback := 3.0

@export_group("Heavy attack")
## Every Nth attack is a slow heavy one: it flashes orange first, staggers, and interrupts
## spells. 0 = never. Parrying it leaves the enemy wide open.
@export var heavy_every := 3
@export var heavy_power := 1.8
@export var heavy_animation := "attack_heavy"
@export var heavy_animation_speed := 0.7
@export var heavy_hit_time := 0.68

@export_group("Story (events)")
## Not in the level until this switch is on (an event turns it on: a boss bursting out).
@export var appear_switch := ""
## Rises out of the ground (dust, rocks, a rumble) when it appears during play.
@export var emerge := false
## Turned on when this one is killed (an event page can wait for it).
@export var defeat_switch := ""
## 1 is added to this variable each time this one is killed ("kill 3 bandits").
@export var defeat_variable := ""
## Never comes back once killed, even after saving and loading.
@export var stays_dead := false

@export_group("Death")
## Seconds before the body disappears, and before it comes back.
@export var corpse_time := 12.0
@export var respawn_time := 90.0
## A body with loot left on it stays up to this long before sinking (s).
@export var loot_time := 60.0
## Goes limp when it dies (1), else plays the death animation (0).
@export var ragdoll := 1.0
## How hard the killing blow throws the body (m/s).
@export var death_push := 2.5
## Seconds the body takes to fade away.
@export var fade_time := 2.0
## One of these plays when it dies.
@export var death_sounds: Array[AudioStream] = [
	preload("res://assets/audio/combat/death_grunt_1.ogg"),
	preload("res://assets/audio/combat/death_grunt_2.ogg"),
	preload("res://assets/audio/combat/death_grunt_3.ogg"),
]
var _killer_dir := Vector3.ZERO
var _loot: LootBag = null

@onready var stats: Stats = $Stats
@onready var character: CharacterModel = get_node_or_null("Model/Character")
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
var _attack_count := 0
var _heavy := false
var _anim := ""
var _anim_speed := 1.0
var _hit_time := 0.3
var _walk := Vector3.ZERO  # steering velocity (knockback is added on top)
# Co-op: on a joined game the enemy copies the host (Net) instead of thinking.
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_anim := ""
var _net_seen := false
var _push := Vector3.ZERO
var _swing_sound: AudioStream = preload("res://assets/audio/combat/swing_1.ogg")
var _heavy_sound: AudioStream = preload("res://assets/audio/combat/swing_heavy.ogg")


func _ready() -> void:
	# Turned in the level (root rotated): move that turn onto the model, since facing sets
	# the model's own yaw (otherwise it walks sideways).
	if absf(rotation.y) > 0.0001:
		model.rotation.y += rotation.y
		rotation.y = 0.0
	add_to_group(Combat.GROUP)
	Database.apply_enemy(self, enemy_id, true)
	Database.changed.connect(func(which: String) -> void:
		if which == "enemies":
			Database.apply_enemy(self, enemy_id)
		if which in ["enemies", "appearance", "items"] and stats and not stats.is_dead():
			_equip())
	_home = global_position
	_wander_to = _home
	_wait = randf_range(0.5, 3.0)
	stats.damaged.connect(_on_damaged)
	stats.died.connect(_on_died)
	Combat.show_numbers(self)
	_plate = Nameplate.attach(self)
	DispositionDisc.attach(self)
	_equip.call_deferred()
	if not appear_switch.is_empty() or stays_dead:
		add_to_group("event_watchers")
		_check_story.call_deferred(false)


# --- Story: appearing on a switch, staying dead -------------------------------------

var _present := true
var _emerging := false


## EventState changed (a switch flipped): appear if our switch just came on.
func refresh() -> void:
	_check_story(true)


func _check_story(animate: bool) -> void:
	var gone := stays_dead and EventState.is_defeated(EventState.node_key(self))
	var want := not gone and (appear_switch.is_empty() or EventState.get_switch(appear_switch))
	if want == _present or _emerging:
		return
	if want and animate and emerge:
		_emerge()
	else:
		_set_present(want)


## In the level or not: hidden, not thinking, not targetable, no collision.
func _set_present(on: bool) -> void:
	_present = on
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	collision_layer = 4 if on and ai != AI.DEAD else 0
	if on:
		add_to_group(Combat.GROUP)
	else:
		remove_from_group(Combat.GROUP)


## Bursts up out of the ground: the earth shakes and splits, rocks fly, then it comes
## for the nearest player.
func _emerge() -> void:
	_emerging = true
	var root := Combat.world_root(self)
	var top := _home
	var depth := 2.0 + float(Combat.radius_of(self)) * 2.5
	_set_present(true)
	process_mode = Node.PROCESS_MODE_DISABLED  # no AI while it climbs out
	global_position = top - Vector3.UP * depth
	Cutscene.shake(self, 1.8, 0.35)
	Combat.play_sound(self, preload("res://assets/audio/creatures/ground_smash.ogg"), 8.0, 0.8)
	Effects.shockwave(root, top, 6.0, Color(0.7, 0.62, 0.48))
	for i in 14:
		var chip := TrollRock.Chip.new()
		chip.velocity = Vector3(randf_range(-6, 6), randf_range(6, 11), randf_range(-6, 6))
		root.add_child(chip)
		chip.global_position = top + Vector3.UP * 0.4
	var tw := get_tree().create_tween()  # it's switched off meanwhile, so not its own tween
	tw.tween_property(self, "global_position", top, 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	Effects.shockwave(root, top, 4.0, Color(0.7, 0.62, 0.48))
	_emerging = false
	process_mode = Node.PROCESS_MODE_INHERIT
	var p := _nearest_player(aggro_radius * 3.0)
	if p:
		_engage(p)


## Killed: tells the events (switch, variable) and remembers it if it stays dead.
## Returns true when it should never respawn.
func _record_death() -> bool:
	if not defeat_variable.is_empty():
		EventState.set_var(defeat_variable, EventState.get_var(defeat_variable) + 1.0)
	if stays_dead:
		EventState.mark_defeated(EventState.node_key(self))
	if not defeat_switch.is_empty():
		EventState.set_switch(defeat_switch, true)
	return stays_dead


## Dresses it from its enemies.json entry: "look" (same as NPCs and the creator: face,
## hair, eyes...) and "equipment" (worn gear; primary = the weapon in hand). Without them
## the old plain body (skin_color) and the "weapon" choice.
func _equip() -> void:
	if character == null:
		return
	var d := Database.enemy(enemy_id)
	var look = d.get("look", {})
	var eq: Dictionary = d.get("equipment", {}) if d.get("equipment") is Dictionary else {}
	character.take_off_all()
	if look is Dictionary and not (look as Dictionary).is_empty():
		character.apply_appearance(Database.resolve_appearance(look))
	for slot in ["head", "shoulders", "chest", "hands", "legs", "feet", "off_hand"]:
		var item := Database.item(String(eq.get(slot, "")))
		if not item.is_empty():
			character.wear(item, slot)
	if _weapon_node and is_instance_valid(_weapon_node):
		_weapon_node.queue_free()
	_weapon_node = null
	var main := Database.item(String(eq.get("primary", "")))
	if not main.is_empty():
		var fits: Array = main.get("fit", {}).get(character.body_key(), [])
		_weapon_node = character.attach_fitted(fits[0] if not fits.is_empty() else {"bone": "mixamorig_RightHand", "grip": true}, String(main.get("model", "")))
	elif String(d.get("weapon", "sword")) == "sword":
		_weapon_node = character.attach_to_hand(WeaponModels.sword())


var _weapon_node: Node3D = null


func aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


func _is_puppet() -> bool:
	var net := get_tree().root.get_node_or_null("Net")
	return net != null and net.call("is_client")


func _physics_process(delta: float) -> void:
	if _is_puppet():
		_puppet_update(delta)
		return
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
	if stats.status_flag("confused") and ai in [AI.CHASE, AI.ATTACK]:
		# Confused: stumbles about instead of fighting.
		var t := Time.get_ticks_msec() / 900.0 + float(get_instance_id() % 100)
		move = Vector3(cos(t), 0, sin(t * 1.3)) * walk_speed
		ai = AI.CHASE
	else:
		_update_threat(delta)
		move = _ai_move(delta)
	_walk.x = lerpf(_walk.x, move.x, 10.0 * delta)
	_walk.z = lerpf(_walk.z, move.z, 10.0 * delta)
	velocity.x = _walk.x + _push.x
	velocity.z = _walk.z + _push.z
	_push = _push.move_toward(Vector3.ZERO, 16.0 * delta)
	if move.length() > 0.1:
		_face(global_position + move, delta)
	move_and_slide()
	_animate()


func _ai_move(delta: float) -> Vector3:
	var move := Vector3.ZERO
	match ai:
		AI.DOWN:
			_down_left -= delta
			if _down_left <= 0.0:
				_get_up()
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
	return move


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
	_attack_count += 1
	_heavy = heavy_every > 0 and _attack_count % heavy_every == 0 and character.has_animation(heavy_animation)
	_anim = heavy_animation if _heavy else attack_animation
	_anim_speed = heavy_animation_speed if _heavy else attack_animation_speed
	_hit_time = heavy_hit_time if _heavy else attack_hit_time
	_face(target.global_position, 0.0)
	character.play_from(_anim, 0.0, 0.1, _anim_speed)
	if _heavy:
		# The tell: an orange flash, so the player knows to dodge or parry.
		Effects.flash(model, Color(1.0, 0.55, 0.1), 0.45, 0.65)
		FloatingText.spawn(self, "!", Color(1.0, 0.6, 0.2), 1.2)


func _attacking(delta: float) -> void:
	_attack_time += delta * _anim_speed
	if not _attack_hit and _target_valid():
		_face(target.global_position, delta * 0.5)  # tracks slowly, so side-steps work
	if not _attack_hit and _attack_time >= _hit_time - 0.12 and _attack_time - delta * _anim_speed < _hit_time - 0.12:
		Combat.play_sound(self, _heavy_sound if _heavy else _swing_sound, -6.0 if not _heavy else -3.0, 0.85)
	if not _attack_hit and _attack_time >= _hit_time:
		_attack_hit = true
		if _target_valid():
			var to := target.global_position - global_position
			var fwd := -model.global_basis.z
			to.y = 0.0
			if to.length() <= attack_range + 0.6 and rad_to_deg(fwd.angle_to(to.normalized())) <= attack_arc * 0.5:
				Combat.hit(self, target, attack_power * (heavy_power if _heavy else 1.0), _heavy, knockback * (2.0 if _heavy else 1.0), Database.enemy(enemy_id).get("applies", []))
	if _attack_time >= character.get_animation_length(_anim):
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


## Pushed by a hit (m/s, flat).
func apply_knockback(push: Vector3) -> void:
	if ai != AI.DEAD and ai != AI.DOWN:
		_push = push


var _down_left := 0.0


## Knocked off its feet (heavy hits with a "knockdown" chance): goes limp, thrown along
## `push`, lies there a moment, then gets up (role "getting_up" if there's a clip).
func knock_down(push: Vector3, seconds := 1.8) -> void:
	if ai == AI.DEAD or ai == AI.DOWN or _is_puppet():
		return
	var rag := Ragdoll.start(character, push + Vector3.UP * 2.5)
	if rag == null:
		stagger(1.2)
		return
	ai = AI.DOWN
	_down_left = seconds
	_walk = Vector3.ZERO
	FloatingText.spawn(self, "Knocked down", Color(1.0, 0.75, 0.35), 0.9)


func _get_up() -> void:
	var hips = Ragdoll.hips_of(character)
	if hips is Vector3:
		global_position = Vector3(hips.x, global_position.y, hips.z)
	Ragdoll.stop(character)
	if character.has_animation("getting_up"):
		character.play_from("getting_up", 0.0, 0.05, 1.0)
		ai = AI.STAGGER
		_stagger = character.get_animation_length("getting_up") * 0.9
	else:
		ai = AI.STAGGER
		_stagger = 0.5
		character.play_from("hit_react", 0.0, 0.1, 0.8)


## Interrupts the wind-up of an attack (heavy hits; a parry staggers for longer).
func stagger(seconds := 0.7) -> void:
	if ai == AI.DEAD or ai == AI.DOWN:
		return
	ai = AI.STAGGER
	_stagger = seconds
	character.play_from("hit_react", 0.0, 0.05, 0.8)
	FloatingText.spawn(self, "Staggered", Color(1.0, 0.8, 0.4), 0.8)


func _engage(who: Node3D) -> void:
	if ai == AI.DEAD or ai == AI.RETURN:
		return
	target = who
	var s := Combat.stats_of(who)
	if s and not s.died.is_connected(_on_target_died.bind(who)):
		s.died.connect(_on_target_died.bind(who))
	if ai == AI.IDLE:
		ai = AI.CHASE


func _give_up() -> void:
	threat.clear()
	target = null
	ai = AI.RETURN


func _target_valid() -> bool:
	if target != null and is_instance_valid(target):
		var pc = target.get_node_or_null("PlayerCombat")
		if pc and pc.call("is_stealthed") and target.global_position.distance_to(global_position) > 4.0:
			return false  # slipped away in stealth
		if SafeArea.protects(target):
			return false  # stepped into a safe area
	return target != null and is_instance_valid(target) and Combat.is_alive(target) \
		and (not target.has_method("is_alive") or target.is_alive())


func _nearest_player(radius: float) -> Node3D:
	var best: Node3D = null
	var best_d := radius
	for n in Combat.enemies_near(self, global_position, radius):
		if n.has_method("is_alive") and not n.is_alive():
			continue
		if SafeArea.protects(n):
			continue  # left alone in safe areas
		var d := n.global_position.distance_to(global_position)
		# A stealthed player goes unnoticed unless right next to it.
		var pc = n.get_node_or_null("PlayerCombat")
		if pc and pc.call("is_stealthed") and d > float(Database.player.get("combat", {}).get("stealth_notice", 1.8)):
			continue
		if d < best_d:
			best_d = d
			best = n
	return best


# --- Events -------------------------------------------------------------------

# --- Threat ---------------------------------------------------------------------------
## Who it's angriest at: damage (and healing of its foes) adds threat; it goes after the
## biggest threat, switching when someone passes the current target by `threat_switch`
## (player.json combat, 1.1 = 10 % more). The player's damage counts × player_threat.
var threat := {}  # Node3D -> float
var _threat_check := 0.0


func add_threat(who: Node, amount: float) -> void:
	if who == null or not who is Node3D or ai == AI.DEAD or SafeArea.protects(who):
		return
	threat[who] = float(threat.get(who, 0.0)) + amount
	if target == null and ai != AI.RETURN:
		_engage(who)


func _note_damage(amount: float, source: Node) -> void:
	if source is Node3D:
		var k := float(Database.player.get("combat", {}).get("player_threat", 1.0)) if source.is_in_group("player") else 1.0
		add_threat(source, amount * k)


## Every half second: turn on whoever has built up more threat than the current target.
func _update_threat(delta: float) -> void:
	_threat_check -= delta
	if _threat_check > 0.0 or threat.is_empty():
		return
	_threat_check = 0.5
	for who in threat.keys():
		if not is_instance_valid(who) or not Combat.is_alive(who) or (who.has_method("is_alive") and not who.is_alive()) \
				or (who as Node3D).global_position.distance_to(global_position) > leash_distance + 10.0:
			threat.erase(who)
	if ai != AI.CHASE:
		return
	var best: Node3D = null
	var best_t := 0.0
	for who in threat:
		if float(threat[who]) > best_t:
			best_t = float(threat[who])
			best = who
	if best == null or best == target:
		return
	var cur := float(threat.get(target, 0.0)) if _target_valid() else 0.0
	if best_t > cur * float(Database.player.get("combat", {}).get("threat_switch", 1.1)):
		_engage(best)


func _on_damaged(_amount: float, source: Node, _crit: bool) -> void:
	_note_damage(_amount, source)
	if source is Node3D:
		var away := global_position - (source as Node3D).global_position
		away.y = 0.0
		_killer_dir = away.normalized()
	if ai == AI.RETURN or ai == AI.DEAD:
		return
	if source is Node3D and target == null:
		_engage(source)
	if ai == AI.CHASE and _cooldown > 0.0:
		character.play_from("hit_react", 0.0, 0.05, 1.0)


func _on_target_died(who: Node = null) -> void:
	if ai == AI.DEAD:
		return
	threat.erase(who)
	if who != null and who != target:
		return  # someone it fought earlier
	# Next angriest-at, else the nearest foe, else go home.
	var next: Node3D = null
	var best_t := 0.0
	for foe in threat:
		if is_instance_valid(foe) and Combat.is_alive(foe) and float(threat[foe]) > best_t:
			best_t = float(threat[foe])
			next = foe
	if next == null:
		next = _nearest_player(aggro_radius)
	if next:
		target = null
		_engage(next)
	else:
		_give_up()


func _on_died() -> void:
	ai = AI.DEAD
	_loot = LootBag.drop_for(Database.enemy(enemy_id), Combat.world_root(self), global_position, self)
	credit_kill()
	var forever := _record_death()
	target = null
	collision_layer = 0
	velocity = Vector3.ZERO
	_walk = Vector3.ZERO
	if not death_sounds.is_empty():
		Combat.play_sound(self, death_sounds.pick_random(), 2.0, randf_range(0.92, 1.08))
	var rag: Ragdoll = null
	if ragdoll > 0.5:
		rag = Ragdoll.start(character, _killer_dir * death_push + Vector3.UP * 0.8)
	if rag == null:
		character.play_from("death", 0.0, 0.15, 1.0)
	await get_tree().create_timer(corpse_time).timeout
	# A body with loot left on it stays a while longer (and while someone's looking through it).
	var waited := corpse_time
	while is_instance_valid(_loot) and (_loot.open or waited < loot_time):
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if is_instance_valid(_loot):
		_loot.queue_free()
	_loot = null
	# Fade away, then gone.
	await _fade_body(1.0)
	model.visible = false
	Ragdoll.stop(character)
	_fade_body(0.0, 0.0)
	if forever:
		_set_present(false)
		return
	await get_tree().create_timer(maxf(respawn_time - waited, 5.0)).timeout
	_respawn()


## Fades every mesh of the body to `to` transparency (1 = gone) over fade_time.
func _fade_body(to: float, seconds := -1.0) -> void:
	var t := fade_time if seconds < 0.0 else seconds
	var tween := create_tween().set_parallel(true)
	for mi in model.find_children("*", "GeometryInstance3D", true, false):
		if seconds == 0.0:
			(mi as GeometryInstance3D).transparency = to
		else:
			tween.tween_property(mi, "transparency", to, maxf(t, 0.01))
	if seconds == 0.0:
		tween.kill()
		return
	await tween.finished


## Experience for the player who fought it (each game credits its own player).
func credit_kill() -> void:
	if not tagged_by_player:
		return
	tagged_by_player = false
	var progress := get_tree().get_first_node_in_group("player_progress")
	if progress:
		progress.call("credit_kill", self)


func _respawn() -> void:
	tagged_by_player = false
	global_position = _home
	velocity = Vector3.ZERO
	stats.restore()
	collision_layer = 4
	model.visible = true
	ai = AI.IDLE
	_wait = randf_range(1.0, 3.0)
	character.play("idle", 0.0)


# --- Co-op ------------------------------------------------------------------------

## Host: [path, x, y, z, yaw, animation, speed, health, max health, ai, model visible]
func net_state(path: NodePath) -> Array:
	var p := global_position
	return [path, p.x, p.y, p.z, model.rotation.y, character.current_animation(), character.get_speed(),
		stats.health, stats.max_health, ai, model.visible]


## Joined game: copy the host's enemy.
func apply_net_state(s: Array) -> void:
	_net_pos = Vector3(s[1], s[2], s[3])
	_net_yaw = s[4]
	if not _net_seen:
		_net_seen = true
		global_position = _net_pos
	var anim := String(s[5])
	if anim != _net_anim and anim != "":
		_net_anim = anim
		if anim in ["idle", "idle_armed", "walking", "running"]:
			character.play(anim, 0.2, float(s[6]))
		else:
			character.play_from(anim, 0.0, 0.1, float(s[6]))
	var was_dead := stats.is_dead()
	stats.max_health = float(s[8])
	stats.health = float(s[7])
	stats.health_changed.emit(stats.health, stats.max_health)
	ai = int(s[9]) as AI
	model.visible = bool(s[10])
	collision_layer = 0 if ai == AI.DEAD else 4
	if not was_dead and stats.is_dead():
		target = null


func _puppet_update(delta: float) -> void:
	if not _net_seen:
		return
	var t := 1.0 - exp(-12.0 * delta)
	global_position = global_position.lerp(_net_pos, t)
	model.rotation.y = lerp_angle(model.rotation.y, _net_yaw, t)


## Joined game: hits on this enemy go to the host (only our own player's); the host
## applies them and sends back the damage.
func forward_hit(source: Node3D, power: float, stagger: bool, knockback: float) -> bool:
	if not _is_puppet():
		return false
	if source is PlayerController:
		get_tree().root.get_node("Net").call("request_hit", self, power, stagger, knockback)
	return true


# --- Animation ----------------------------------------------------------------

func _face(point: Vector3, delta: float) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var yaw := atan2(-dir.x, -dir.z)
	model.rotation.y = yaw if delta <= 0.0 else lerp_angle(model.rotation.y, yaw, turn_speed * delta)


func _animate() -> void:
	if ai == AI.ATTACK or ai == AI.DEAD or ai == AI.STAGGER or ai == AI.DOWN:
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
