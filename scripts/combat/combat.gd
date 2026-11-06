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
## Returns the damage dealt.
static func hit(source: Node3D, target: Node3D, power: float, stagger := false) -> float:
	var ts := stats_of(target)
	if ts == null or ts.is_dead():
		return 0.0
	var ss := stats_of(source)
	var amount := scaled_power(power, ss.level if ss else 1, ts.level)
	amount *= randf_range(0.9, 1.1)
	var crit := randf() < CRIT_CHANCE
	if crit:
		amount *= CRIT_MULTIPLIER
	# Armour: each point takes a little off (100 armour halves damage).
	amount *= 100.0 / (100.0 + maxf(ts.armor, 0.0))
	var before := amount
	if target.has_method("modify_incoming_damage"):
		amount = target.modify_incoming_damage(amount, source)
	if amount <= 0.0:
		return 0.0
	amount = maxf(roundf(amount), 1.0)
	ts.take_damage(amount, source, crit)
	var blocked := amount < before * 0.75
	play_sound(target, BLOCK_SOUND if blocked else HIT_SOUND, -2.0)
	if not blocked:
		play_sound(target, IMPACT_SOUND, -10.0, randf_range(0.8, 1.0))
	if stagger and not blocked and target.has_method("stagger"):
		target.stagger()
	return amount


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
