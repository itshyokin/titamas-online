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


## Danger mode (the player toggles it): this game's player may target and hit friendly
## NPCs that can fight. An NPC they hit gets angry (`angry_at_player`) and fights back.
static var danger_mode := false


static func is_enemy_of(a: Node, b: Node) -> bool:
	var sa := stats_of(a)
	var sb := stats_of(b)
	if sa == null or sb == null:
		return false
	if sa.team != sb.team:
		return true
	# Same side: only the player and NPCs, through danger mode or an NPC's anger.
	if a.is_in_group("player") and b.is_in_group("npcs"):
		return danger_mode or bool(b.get("angry_at_player"))
	if b.is_in_group("player") and a.is_in_group("npcs"):
		return bool(a.get("angry_at_player"))
	return false


## Where to aim at a combatant (its chest).
## How far a body reaches out from its origin (big beasts: melee counts from their side, not their centre).
static func radius_of(node: Node) -> float:
	var r = node.get("body_radius") if node else null
	return float(r) if r != null else 0.0


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
				and not (node.has_method("is_downed") and node.is_downed()) \
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
## `applies`: statuses the blow may give, [{status, chance (0–1), seconds}].
static func hit(source: Node3D, target: Node3D, power: float, stagger := false, knockback := 0.0, applies: Array = [], element := "") -> float:
	var ts := stats_of(target)
	if ts == null or ts.is_dead():
		return 0.0
	if safe_between(source, target):
		_safe_notice(source, target)
		return 0.0
	# Warded (statuses.json "invulnerable"): nothing gets through.
	if ts.status_flag("invulnerable"):
		_warded(target)
		return 0.0
	# Co-op: some targets are worked out on another machine (see Net).
	if target.has_method("forward_hit") and target.forward_hit(source, power, stagger, knockback):
		if source is PlayerController:
			_tag(source, target)
			impact(source, target, stagger, false, 0.0)  # the feel stays local
		return 0.0
	var ss := stats_of(source)
	# Blinded: some blows miss.
	if ss and randf() < ss.status_value("miss_chance"):
		FloatingText.spawn(target, "Miss", Color(0.8, 0.8, 0.85), 0.9)
		return 0.0
	var amount := scaled_power(power, ss.level if ss else 1, ts.level)
	if ss:
		amount *= ss.damage_scale  # Weakened
		amount *= ss.status_product("damage_scale")  # Well rested / Tired
	amount *= randf_range(0.9, 1.1)
	var crit := randf() < CRIT_CHANCE + (ss.crit_bonus if ss else 0.0)
	if crit:
		amount *= CRIT_MULTIPLIER
	# Elements: fire / frost / water / shock / earth / holy / arcane against what the target
	# is weak to or resists (enemies.json / npcs.json "elements" {element: ×}).
	var elem := element_scale(target, element)
	amount *= elem
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
	# Companions leave the killing blow to the player.
	if source and source.has_method("spares_kill") and amount >= ts.health and source.spares_kill(target):
		if ts.health <= 1.0:
			return 0.0
		amount = ts.health - 1.0
	_tag(source, target)
	if elem >= 1.25:
		FloatingText.spawn(target, String(_combat_settings().get("effective_text", "Effective!")), Color(1.0, 0.65, 0.25), 0.9)
	elif elem <= 0.8:
		FloatingText.spawn(target, String(_combat_settings().get("resisted_text", "Resisted")), Color(0.7, 0.72, 0.78), 0.9)
	ts.take_damage(amount, source, crit)
	var blocked := amount < before * 0.75
	play_sound(target, BLOCK_SOUND if blocked else HIT_SOUND, -2.0)
	if not blocked:
		play_sound(target, IMPACT_SOUND, -10.0, randf_range(0.8, 1.0))
	if stagger and not blocked and target.has_method("stagger"):
		target.stagger()
	impact(source, target, stagger or crit, blocked, knockback)
	for a in applies:
		if a is Dictionary and randf() < float(a.get("chance", 1.0)) and not blocked:
			if String(a.get("status", "")) == "knockdown":
				# Thrown off their feet (enemies that can be).
				if target.has_method("knock_down") and source:
					var away := target.global_position - source.global_position
					away.y = 0.0
					target.call("knock_down", away.normalized() * maxf(knockback, 3.0) * 1.5, float(a.get("seconds", 1.8)))
			else:
				ts.add_status(String(a.get("status", "")), float(a.get("seconds", 8.0)), source)
	return amount


## How hard `element` hits `target` (1 = normal): its "elements" entry in its data file.
static func element_scale(target: Node, element: String) -> float:
	if element == "" or target == null:
		return 1.0
	var d: Dictionary = {}
	var db := target.get_node_or_null("/root/Database")
	if db == null:
		return 1.0
	var eid = target.get("enemy_id")
	var nid = target.get("npc_id")
	if eid is String and eid != "":
		d = db.call("enemy", eid)
	elif nid is String and nid != "":
		d = db.call("npc", nid)
	var el = d.get("elements", {})
	return float((el as Dictionary).get(element, 1.0)) if el is Dictionary else 1.0


static var _ward_sound: AudioStream = null


static func _warded(target: Node3D) -> void:
	if _ward_sound == null and ResourceLoader.exists("res://assets/audio/spells/ward_block.ogg"):
		_ward_sound = load("res://assets/audio/spells/ward_block.ogg")
	if _ward_sound:
		play_sound(target, _ward_sound, -6.0, randf_range(0.9, 1.1))
	FloatingText.spawn(target, "Warded", Color(0.6, 0.8, 1.0), 0.8)


## Safe areas (SafeArea boxes): no blow lands between the two sides while the one on the
## players' side stands in one, whichever of them swings. Practice targets still take hits.
static func safe_between(source: Node, target: Node) -> bool:
	if source == null or not is_instance_valid(source) or target.is_in_group("practice_targets"):
		return false
	var ss := stats_of(source)
	var ts := stats_of(target)
	if ss == null or ts == null or ss.team == ts.team:
		return false
	return SafeArea.protects(source) or SafeArea.protects(target)


static var _safe_notice_at := 0


## Tells the player why their blow did nothing (at most every few seconds).
static func _safe_notice(source: Node, target: Node3D) -> void:
	if not source.is_in_group("player"):
		return
	var now := Time.get_ticks_msec()
	if now - _safe_notice_at < 3000:
		return
	_safe_notice_at = now
	var cfg: Dictionary = Database.player.get("safe_areas", {})
	var text := String(cfg.get("blocked_text", "You can't fight from a safe area."))
	if not text.is_empty() and target.is_inside_tree():
		target.get_tree().call_group("hud", "show_message", text, 2.0, Color(0.85, 0.85, 0.9))


## Remembers that this game's player (or a follower) fought an enemy, so its death gives
## them experience.
static func _tag(source: Node, target: Node) -> void:
	if source and source.is_in_group("player"):
		target.set_meta("player_struck", true)  # companions join in once the player has
		var pc := source.get_node_or_null("PlayerCombat")
		if pc:
			pc.set("last_struck", target)
			pc.set("last_strike_msec", Time.get_ticks_msec())
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
		Effects.blood(world_root(target), at, -dir + Vector3.UP * 0.4, blood_color_of(target), 1.5 if heavy else 1.0)
	if knockback > 0.0 and dir != Vector3.ZERO and target.has_method("apply_knockback"):
		target.apply_knockback(dir * knockback * (0.3 if blocked else 1.0))
	var player_hit := target is PlayerController
	if source is PlayerController or player_hit:
		TimeFX.hit_stop(target, HIT_STOP_HEAVY if heavy else HIT_STOP_LIGHT)
		var cam := target.get_tree().get_first_node_in_group("player_camera")
		if cam:
			var strength := (0.45 if heavy else 0.25) if player_hit else (0.35 if heavy else 0.12)
			cam.call("shake", strength * (0.5 if blocked else 1.0))


## What a creature bleeds (enemies.json / npcs.json `blood_color`, player.json combat
## `blood_color`; "" or "none" = nothing, for dummies, ghosts and the like).
static func blood_color_of(node: Node) -> Color:
	if node == null:
		return Color(0, 0, 0, 0)
	var text := ""
	var own = node.get("blood_color")
	if own != null and own is String:
		text = own
	elif node.is_in_group("player") or node.is_in_group("remote_players"):
		text = String(Database.player.get("combat", {}).get("blood_color", "#7e0d10"))
	elif node.get("enemy_id") != null:
		text = String(Database.enemy(String(node.get("enemy_id"))).get("blood_color", "#7e0d10"))
	elif node.get("npc_id") != null:
		text = String(Database.npc(String(node.get("npc_id"))).get("blood_color", "#7e0d10"))
	if text == "" or text == "none":
		return Color(0, 0, 0, 0)
	return Color.html(text)


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


## Floating damage/heal numbers above a combatant, driven by its Stats signals. Hits of a
## point or more show at once; trickles (fatigue, regeneration, heal-over-time per frame)
## are added up and shown as one number about once a second, never as "0"s.
static func show_numbers(node: Node3D) -> void:
	var s := stats_of(node)
	if s == null:
		return
	s.damaged.connect(func(amount: float, _source: Node, crit: bool) -> void:
		var color := Color(1.0, 0.85, 0.3) if s.team == Stats.Team.ENEMIES else Color(1.0, 0.3, 0.25)
		if amount >= 1.0:
			FloatingText.spawn(node, ("%d!" % amount) if crit else str(int(round(amount))), color, 1.4 if crit else 1.0)
		else:
			_trickle(node, "dmg", amount, color, "%d"))
	s.blood_paid.connect(func(amount: float) -> void:
		FloatingText.spawn(node, "-%d" % maxi(int(round(amount)), 1), Color(0.75, 0.25, 0.85), 0.85))
	s.healed.connect(func(amount: float) -> void:
		if amount >= 1.0:
			FloatingText.spawn(node, "+%d" % int(round(amount)), Color(0.45, 1.0, 0.45), 0.9)
		else:
			_trickle(node, "heal", amount, Color(0.45, 1.0, 0.45), "+%d"))


## Adds a small amount to a running total on the node; shows it once it's at least 1 and
## a second has passed since the last one.
static func _trickle(node: Node3D, kind: String, amount: float, color: Color, fmt: String) -> void:
	var key := "_trickle_" + kind
	var total := float(node.get_meta(key, 0.0)) + amount
	var now := Time.get_ticks_msec()
	if total >= 1.0 and now - int(node.get_meta(key + "_at", 0)) >= 1000:
		FloatingText.spawn(node, fmt % int(total), color, 0.85)
		total -= floorf(total)
		node.set_meta(key + "_at", now)
	node.set_meta(key, total)


## Healing draws enemies' attention: every enemy already fighting the healer's side
## within 40 m gains threat on the healer (player.json combat heal_threat, × healing).
static func heal_threat(healer: Node3D, amount: float) -> void:
	if healer == null or not healer.is_inside_tree():
		return
	var k := float(Database.player.get("combat", {}).get("heal_threat", 0.5))
	for n in healer.get_tree().get_nodes_in_group(GROUP):
		if n.has_method("add_threat") and is_enemy_of(n, healer) and (n as Node3D).global_position.distance_to(healer.global_position) < 40.0 \
				and n.get("target") != null:
			n.call("add_threat", healer, amount * k)


static func _combat_settings() -> Dictionary:
	var c = Database.player.get("combat", {})
	return c if c is Dictionary else {}
