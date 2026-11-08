class_name Combat
extends RefCounted
## Shared combat rules: finding targets, working out damage, hitting, and the
## feedback that goes with it (numbers, sounds). Anything that fights is a node in the
## "combatants" group with a Stats child.

const GROUP := "combatants"
const CRIT_CHANCE := 0.1
const CRIT_MULTIPLIER := 1.5
const HIT_SOUND := preload("res://assets/audio/combat/hit_body.ogg")
const IMPACT_SOUND := preload("res://assets/audio/combat/hit_impact.ogg")
const BLOCK_SOUND := preload("res://assets/audio/combat/block_hit.ogg")
## Hit-stop (seconds of freeze) when the player lands or takes a blow.
const HIT_STOP_LIGHT := 0.045
const HIT_STOP_HEAVY := 0.09

## True while a heavy (staggering) hit is being worked out, so whoever is hit can tell
## it from a light one in modify_incoming_damage (interrupting casts, breaking guard).
static var incoming_heavy := false


## Where to put short-lived things (sounds, numbers, bolts): the running level.
static func world_root(from: Node) -> Node:
	var tree := from.get_tree()
	return tree.current_scene if tree.current_scene else tree.root


static func stats_of(node: Node) -> Stats:
	if node == null or not is_instance_valid(node):
		return null
	return node.get_node_or_null("Stats") as Stats


static func is_alive(node: Node) -> bool:
	var s := stats_of(node)
	return s != null and not s.is_dead()


static func is_enemy_of(a: Node, b: Node) -> bool:
	var sa := stats_of(a)
	var sb := stats_of(b)
	return sa != null and sb != null and sa.team != sb.team


## Where to aim at a combatant (its chest).
static func aim_point(node: Node3D) -> Vector3:
	if node.has_method("aim_point"):
		return node.aim_point()
	return node.global_position + Vector3.UP * 1.2


## Living enemies of `who` within `radius` of `center`.
static func enemies_near(who: Node, center: Vector3, radius: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in who.get_tree().get_nodes_in_group(GROUP):
		var node := n as Node3D
		if node and node != who and is_alive(node) and is_enemy_of(who, node) \
				and node.global_position.distance_to(center) <= radius:
			out.append(node)
	return out


## Level-scaled damage. Each level adds 8%; fighting above or below your level adds
## or takes 5% per level (capped).
static func scaled_power(power: float, attacker_level: int, defender_level: int) -> float:
	var level_scale := 1.0 + 0.08 * (attacker_level - 1)
	var gap := clampf(1.0 + 0.05 * (attacker_level - defender_level), 0.6, 1.4)
	return power * level_scale * gap


## Hits `target` for `power` (before scaling) from `source`. The target can lessen it
## (dodging, blocking) by having `modify_incoming_damage(amount, source) -> float`.
## `knockback` pushes the target away (m/s) if it has `apply_knockback(velocity)`.
## Returns the damage dealt.
static func hit(source: Node3D, target: Node3D, power: float, stagger := false, knockback := 0.0) -> float:
	var ts := stats_of(target)
	if ts == null or ts.is_dead():
		return 0.0
	# Co-op: some targets are worked out on another machine (see Net).
	if target.has_method("forward_hit") and target.forward_hit(source, power, stagger, knockback):
		if source is PlayerController:
			_tag(source, target)
			impact(source, target, stagger, false, 0.0)  # the feel stays local
		return 0.0
	var ss := stats_of(source)
	var amount := scaled_power(power, ss.level if ss else 1, ts.level)
	if ss:
		amount *= ss.damage_scale  # Weakened
	amount *= randf_range(0.9, 1.1)
	var crit := randf() < CRIT_CHANCE
	if crit:
		amount *= CRIT_MULTIPLIER
	# Armour: each point takes a little off (100 armour halves damage).
	amount *= 100.0 / (100.0 + maxf(ts.armor, 0.0))
	var before := amount
	if target.has_method("modify_incoming_damage"):
		incoming_heavy = stagger
		amount = target.modify_incoming_damage(amount, source)
		incoming_heavy = false
	if amount <= 0.0:
		return 0.0
	amount = maxf(roundf(amount), 1.0)
	_tag(source, target)
	ts.take_damage(amount, source, crit)
	var blocked := amount < before * 0.75
	play_sound(target, BLOCK_SOUND if blocked else HIT_SOUND, -2.0)
	if not blocked:
		play_sound(target, IMPACT_SOUND, -10.0, randf_range(0.8, 1.0))
	if stagger and not blocked and target.has_method("stagger"):
		target.stagger()
	impact(source, target, stagger or crit, blocked, knockback)
	return amount


## Remembers that this game's player (or a follower) fought an enemy, so its death gives
## them experience.
static func _tag(source: Node, target: Node) -> void:
	if source and (source.is_in_group("player") or source.is_in_group("followers")) and "tagged_by_player" in target:
		target.set("tagged_by_player", true)


## The feel of a blow landing: sparks, a white flash, a push, and for the player a
## split-second freeze and a camera shake.
static func impact(source: Node3D, target: Node3D, heavy: bool, blocked := false, knockback := 0.0) -> void:
	if target == null or not target.is_inside_tree():
		return
	var dir := Vector3.ZERO
	if source and is_instance_valid(source):
		dir = target.global_position - source.global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	var at := aim_point(target) - dir * 0.3
	var color := Color(0.75, 0.85, 1.0) if blocked else Color(1.0, 0.7, 0.3)
	Effects.sparks(world_root(target), at, color, 1.6 if heavy else 1.0, -dir + Vector3.UP * 0.6)
	if not blocked:
		Effects.flash(target, Color(1, 1, 1), 0.14 if heavy else 0.1, 0.8 if heavy else 0.6)
	if knockback > 0.0 and dir != Vector3.ZERO and target.has_method("apply_knockback"):
		target.apply_knockback(dir * knockback * (0.3 if blocked else 1.0))
	var player_hit := target is PlayerController
	if source is PlayerController or player_hit:
		TimeFX.hit_stop(target, HIT_STOP_HEAVY if heavy else HIT_STOP_LIGHT)
		var cam := target.get_tree().get_first_node_in_group("player_camera")
		if cam:
			var strength := (0.45 if heavy else 0.25) if player_hit else (0.35 if heavy else 0.12)
			cam.call("shake", strength * (0.5 if blocked else 1.0))


## A one-shot 3D sound at a node's position (the player frees itself when done).
static func play_sound(at: Node3D, stream: AudioStream, volume_db := 0.0, pitch := 1.0) -> void:
	if stream == null or at == null or not at.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = &"SFX"
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.unit_size = 8.0
	p.max_distance = 60.0
	Combat.world_root(at).add_child(p)
	p.global_position = at.global_position + Vector3.UP
	p.finished.connect(p.queue_free)
	p.play()


## Floating damage/heal numbers above a combatant, driven by its Stats signals.
static func show_numbers(node: Node3D) -> void:
	var s := stats_of(node)
	if s == null:
		return
	s.damaged.connect(func(amount: float, _source: Node, crit: bool) -> void:
		var color := Color(1.0, 0.85, 0.3) if s.team == Stats.Team.ENEMIES else Color(1.0, 0.3, 0.25)
		FloatingText.spawn(node, ("%d!" % amount) if crit else str(int(amount)), color, 1.4 if crit else 1.0))
	s.healed.connect(func(amount: float) -> void:
		FloatingText.spawn(node, "+%d" % int(round(amount)), Color(0.45, 1.0, 0.45), 0.9))
