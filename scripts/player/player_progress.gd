class_name PlayerProgress
extends Node
## Experience, levels and death penalties. Lives under Player as "Progress".
##
## Kills give experience (enemies.json "xp", or kill_xp_base + kill_xp_per_level × the
## enemy's level; more for tougher enemies, little or nothing for much weaker ones).
## Each level (up to max_level) needs xp_to_next[level - 1] and adds health, mana,
## attack and spell power (data/player.json "leveling", Database → Player).
## Dying sends you home (where the hearthstone goes) and costs a share of carried gold,
## and leaves you Weakened for a while: less damage and less maximum health
## (player.json "death"). Level, experience and the Weakened timer are saved with the
## character.
##
## Skill points (Database → Skill Trees, player.json leveling skill_points_start /
## skill_points_per_level): spent on the class's tree skills (`rank_up`), saved as
## data.skill_ranks {skill id: rank}. Skills raise stats (Stats.set_skill_bonus), teach
## abilities (added to PlayerCombat.spells) or switch on passives (`passive(key)` = rank,
## for game code to check).

signal xp_changed(xp: int, needed: int, level: int, max_level: bool)
signal leveled_up(level: int)
signal weakened_changed(seconds_left: float)
## Skill ranks or free points changed.
signal skills_changed

const LEVEL_SOUND := preload("res://assets/audio/weapons/swap_bow.ogg")

@onready var player: PlayerController = get_parent()
@onready var stats: Stats = get_node("../Stats")

var level := 1
var xp := 0
## skill id -> rank
var skill_ranks := {}
var _skill_spells: Array[Ability] = []
## Unix time the Weakened debuff wears off (0 = not weakened).
var weakened_until := 0.0
## Without a saved character (F6): Weakened counts down from here instead.
var _weakened_left := 0.0


func _ready() -> void:
	add_to_group("player_progress")
	if GameSession.active():
		level = clampi(int(GameSession.data.get("level", 1)), 1, max_level())
		xp = int(GameSession.data.get("xp", 0))
		weakened_until = float(GameSession.data.get("weakened_until", 0.0))
		var ranks = GameSession.data.get("skill_ranks", {})
		if ranks is Dictionary:
			for k in ranks:
				skill_ranks[String(k)] = int(ranks[k])
	_apply_level()
	_apply_skills.call_deferred()
	_apply_weakened()
	stats.restore.call_deferred()  # start full, once gear and levels are on
	Database.changed.connect(func(which: String) -> void:
		if which == "player":
			_apply_level()
		if which in ["player", "skill_trees", "abilities", "species"]:
			_apply_skills.call_deferred())
	_emit.call_deferred()


func _leveling() -> Dictionary:
	return Database.player.get("leveling", {})


func max_level() -> int:
	return int(_leveling().get("max_level", 10))


## Experience needed to go from `at_level` to the next (0 at max level).
func needed(at_level := level) -> int:
	if at_level >= max_level():
		return 0
	var table: Array = _leveling().get("xp_to_next", [])
	if table.is_empty():
		return 100 * at_level
	return int(table[mini(at_level - 1, table.size() - 1)])


func is_max_level() -> bool:
	return level >= max_level()


## Stats from levels: base stats (player.json) are applied by the Database; levels add on.
func _apply_level() -> void:
	var l := _leveling()
	var steps := float(level - 1)
	stats.level = level
	stats.set_level_bonus({
		"health": steps * float(l.get("health_per_level", 12.0)),
		"mana": steps * float(l.get("mana_per_level", 8.0)),
		"attack": steps * float(l.get("attack_per_level", 1.0)),
		"spell_power": steps * float(l.get("spell_power_per_level", 1.0)),
	})


func _emit() -> void:
	xp_changed.emit(xp, needed(), level, is_max_level())


## Experience a kill is worth.
func xp_for_kill(enemy_level: int, enemy_data: Dictionary) -> int:
	var l := _leveling()
	var base := float(enemy_data.get("xp", 0))
	if base <= 0.0:
		base = float(l.get("kill_xp_base", 15)) + float(l.get("kill_xp_per_level", 10)) * enemy_level
	var diff := enemy_level - level
	if diff <= -5:
		return 0  # far too weak to learn anything from
	return maxi(roundi(base * clampf(1.0 + 0.15 * diff, 0.25, 1.6)), 1)


## Called when an enemy this player fought dies.
func credit_kill(enemy: Node) -> void:
	var s := Combat.stats_of(enemy)
	if s == null:
		return
	var data: Dictionary = Database.enemy(String(enemy.get("enemy_id"))) if "enemy_id" in enemy else {}
	var ach := get_node_or_null("/root/Achievements")
	if ach:
		ach.call("count_kill", String(enemy.get("enemy_id")) if "enemy_id" in enemy else "")
	Quests.count_kill(String(enemy.get("enemy_id")) if "enemy_id" in enemy else "")
	var amount := xp_for_kill(s.level, data)
	if amount > 0:
		add_xp(amount, s.display_name)


func add_xp(amount: int, from := "") -> void:
	if amount <= 0 or is_max_level():
		return
	# Statuses like Well rested give more.
	var st := player.get_node_or_null("Stats") as Stats if player else null
	if st:
		amount = maxi(roundi(amount * st.status_product("xp_scale")), 1)
	xp += amount
	FloatingText.spawn(player, "+%d XP" % amount, Color(0.75, 0.55, 1.0), 0.9)
	GameLog.post("You gain %d experience%s." % [amount, (" (%s)" % from) if not from.is_empty() else ""], Color(0.78, 0.62, 1.0))
	while not is_max_level() and xp >= needed():
		xp -= needed()
		level += 1
		_on_level_up()
	if is_max_level():
		xp = 0
	_save()
	_emit()


func _on_level_up() -> void:
	_apply_level()
	_apply_skills()  # racial abilities grow with the level
	stats.restore()
	Effects.burst(Combat.world_root(player), player.global_position + Vector3.UP, Color(1.0, 0.85, 0.35), 1.6)
	Combat.play_sound(player, LEVEL_SOUND, -2.0, 1.3)
	FloatingText.spawn(player, "Level %d!" % level, Color(1.0, 0.85, 0.35), 1.6)
	var hud := player.get_node_or_null("HUD")
	if hud:
		hud.call("show_message", "You reached level %d!" % level, 3.0)
	GameLog.post("You reached level %d!" % level, Color(1.0, 0.85, 0.35))
	leveled_up.emit(level)
	if points_free() > 0:
		GameLog.post("You have %d skill point%s to spend (%s)." % [points_free(), "" if points_free() == 1 else "s", GameSettings.binding_label("skills")], Color(1.0, 0.85, 0.35))
	skills_changed.emit()
	var net := get_tree().root.get_node_or_null("Net")
	if net and net.get("active"):
		net.call("send_info")


func _save() -> void:
	if GameSession.active():
		GameSession.data["skill_ranks"] = skill_ranks.duplicate()
		GameSession.data["level"] = level
		GameSession.data["xp"] = xp
		GameSession.data["weakened_until"] = weakened_until


# --- Death -------------------------------------------------------------------------

## Death penalties: lose a share of carried gold, and Weakened for a while.
func apply_death_penalty() -> void:
	var d: Dictionary = Database.player.get("death", {})
	var inventory := player.get_node_or_null("Inventory") as Inventory
	var lost := 0
	if inventory:
		lost = floori(inventory.gold * float(d.get("gold_loss", 0.1)))
		if lost > 0:
			inventory.add_gold(-lost)
	var seconds := float(d.get("weakened_seconds", 120.0))
	if GameSession.active():
		weakened_until = Time.get_unix_time_from_system() + seconds
	_weakened_left = seconds
	_apply_weakened()
	_save()
	var text := "You died. You are Weakened for %s%s." % [_duration(seconds), (" and lost %d gold" % lost) if lost > 0 else ""]
	GameLog.post(text, Color(1.0, 0.5, 0.45))


func weakened_left() -> float:
	if GameSession.active():
		return maxf(weakened_until - Time.get_unix_time_from_system(), 0.0)
	return _weakened_left


func is_weakened() -> bool:
	return weakened_left() > 0.0


func _apply_weakened() -> void:
	var d: Dictionary = Database.player.get("death", {})
	var on := is_weakened()
	stats.damage_scale = float(d.get("weakened_damage", 0.8)) if on else 1.0
	stats.set_max_health_scale(float(d.get("weakened_health", 0.8)) if on else 1.0)
	if "speed_scale" in player:
		player.set("speed_scale", float(d.get("weakened_speed", 0.85)) if on else 1.0)
	weakened_changed.emit(weakened_left())


var _was_weakened := false


func _process(delta: float) -> void:
	if _weakened_left > 0.0:
		_weakened_left = maxf(_weakened_left - delta, 0.0)
	var on := is_weakened()
	if on != _was_weakened:
		_was_weakened = on
		_apply_weakened()
		if not on:
			GameLog.post("You are no longer Weakened.", Color(0.7, 1.0, 0.7))


static func _duration(seconds: float) -> String:
	var s := ceili(seconds)
	return ("%d min" % (s / 60)) if s % 60 == 0 else "%d:%02d" % [s / 60, s % 60]


# --- Skills ------------------------------------------------------------------------

## This character's class's skill trees (Database.trees_for).
func trees() -> Array:
	var cls := String(GameSession.data.get("class", "")) if GameSession.active() else ""
	if cls.is_empty():
		cls = String(Database.player.get("default_class", "fighter"))
	return Database.trees_for(cls)


func skill(id: String) -> Dictionary:
	for t: Dictionary in trees():
		for n: Dictionary in t.get("nodes", []):
			if String(n.get("id", "")) == id:
				return n
	return {}


func tree_of(id: String) -> Dictionary:
	for t: Dictionary in trees():
		for n: Dictionary in t.get("nodes", []):
			if String(n.get("id", "")) == id:
				return t
	return {}


func rank(id: String) -> int:
	return int(skill_ranks.get(id, 0))


func points_total() -> int:
	var l := _leveling()
	return int(l.get("skill_points_start", 1)) + (level - 1) * int(l.get("skill_points_per_level", 1))


func points_spent(tree_id := "") -> int:
	var total := 0
	for id: String in skill_ranks:
		var n := skill(id)
		if n.is_empty():
			continue
		if tree_id != "" and String(tree_of(id).get("id", "")) != tree_id:
			continue
		total += int(skill_ranks[id]) * int(n.get("cost", 1))
	return total


func points_free() -> int:
	return maxi(points_total() - points_spent(), 0)


## Why a skill can't take another rank ("" = it can).
func cant_rank(id: String) -> String:
	var n := skill(id)
	if n.is_empty():
		return "Unknown skill"
	if rank(id) >= int(n.get("max_rank", 1)):
		return "Fully learned"
	if level < int(n.get("min_level", 1)):
		return "Needs level %d" % int(n.get("min_level", 1))
	var above := int(n.get("points_above", 0))
	if points_spent(String(tree_of(id).get("id", ""))) < above:
		return "Needs %d points in %s" % [above, tree_of(id).get("name", "this tree")]
	# Saturn-style: a rank in each skill it's linked from.
	for req in n.get("requires", []):
		var r := skill(String(req))
		if not r.is_empty() and rank(String(req)) < 1:
			return "Needs %s" % r.get("name", req)
	if points_free() < int(n.get("cost", 1)):
		return "No skill points"
	return ""


func rank_up(id: String) -> bool:
	if cant_rank(id) != "":
		return false
	skill_ranks[id] = rank(id) + 1
	_apply_skills()
	_save()
	var n := skill(id)
	GameLog.post("%s: rank %d." % [n.get("name", id), rank(id)], Color(1.0, 0.85, 0.35))
	return true


## Gives every point back.
func respec() -> void:
	skill_ranks.clear()
	_apply_skills()
	_save()


## Rank of the skills with this passive key (0 = none), for game code: passive("cleave").
func passive(key: String) -> int:
	var total := 0
	for id: String in skill_ranks:
		var n := skill(id)
		if String(n.get("effect", "")) == "passive" and String(n.get("key", "")) == key:
			total += int(skill_ranks[id])
	return total


func _apply_skills() -> void:
	var bonus := {}
	var learn: Array[Ability] = []
	# Species and attributes (base + species + points spent at creation) add to the same
	# bonuses as skills; the species' racial abilities are learned, stronger each level.
	var save: Dictionary = GameSession.data if GameSession.active() else {}
	var sp := Database.species_of(save)
	var attrs := Database.attributes_for(save)
	stats.set("attributes", attrs)
	for src: Dictionary in [Database.attribute_bonus(attrs), sp.get("stats", {})]:
		for key: String in src:
			bonus[key] = float(bonus.get(key, 0.0)) + float(src[key])
	var racial := {}
	for r in sp.get("racial", []):
		var ab := Database.ability(String((r as Dictionary).get("ability", "")))
		if ab:
			learn.append(ab)
			racial[ab.id] = float(r.get("power_per_level", 1.0)) * (level - 1)
	for id: String in skill_ranks:
		var n := skill(id)
		var r := int(skill_ranks[id])
		if n.is_empty() or r <= 0:
			continue
		match String(n.get("effect", "stat")):
			"stat":
				var key := String(n.get("stat", "attack"))
				bonus[key] = float(bonus.get(key, 0.0)) + float(n.get("per_rank", 0.0)) * r
			"ability":
				var ab := Database.ability(String(n.get("ability", "")))
				if ab:
					learn.append(ab)
	stats.set_skill_bonus(bonus)
	if "skill_speed" in player:
		player.set("skill_speed", 1.0 + float(bonus.get("move_speed", 0.0)) / 100.0)
	var combat := player.get_node_or_null("PlayerCombat") as PlayerCombat
	if combat:
		combat.set("racial_power", racial)
		for ab in _skill_spells:
			if not ab in learn:
				combat.spells.erase(ab)
		for ab in learn:
			if not ab in combat.spells:
				combat.spells.append(ab)
		_skill_spells = learn
		_offer_to_hotbar(learn)
		combat.loadout_changed.emit()
	skills_changed.emit()


## Newly learned abilities (skill tree, racial) go into the first free hotbar box, once each:
## ids already offered are kept in the save (`hotbar_offered`), so one the player took off
## the bar doesn't come back.
var _offered_memory: Array = []

func _offer_to_hotbar(learn: Array[Ability]) -> void:
	var inv := player.get_node_or_null("Inventory")
	if inv == null:
		return
	var offered: Array = GameSession.data.get_or_add("hotbar_offered", []) if GameSession.active() else _offered_memory
	for ab in learn:
		if ab.id in offered:
			continue
		offered.append(ab.id)
		inv.call("add_to_hotbar", "ability:" + ab.id)
