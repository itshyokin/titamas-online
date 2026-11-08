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

signal xp_changed(xp: int, needed: int, level: int, max_level: bool)
signal leveled_up(level: int)
signal weakened_changed(seconds_left: float)

const LEVEL_SOUND := preload("res://assets/audio/weapons/swap_bow.ogg")

@onready var player: PlayerController = get_parent()
@onready var stats: Stats = get_node("../Stats")

var level := 1
var xp := 0
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
	_apply_level()
	_apply_weakened()
	stats.restore.call_deferred()  # start full, once gear and levels are on
	Database.changed.connect(func(which: String) -> void:
		if which == "player":
			_apply_level())
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
	var amount := xp_for_kill(s.level, data)
	if amount > 0:
		add_xp(amount, s.display_name)


func add_xp(amount: int, from := "") -> void:
	if amount <= 0 or is_max_level():
		return
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
	stats.restore()
	Effects.burst(Combat.world_root(player), player.global_position + Vector3.UP, Color(1.0, 0.85, 0.35), 1.6)
	Combat.play_sound(player, LEVEL_SOUND, -2.0, 1.3)
	FloatingText.spawn(player, "Level %d!" % level, Color(1.0, 0.85, 0.35), 1.6)
	var hud := player.get_node_or_null("HUD")
	if hud:
		hud.call("show_message", "You reached level %d!" % level, 3.0)
	GameLog.post("You reached level %d!" % level, Color(1.0, 0.85, 0.35))
	leveled_up.emit(level)
	var net := get_tree().root.get_node_or_null("Net")
	if net and net.get("active"):
		net.call("send_info")


func _save() -> void:
	if GameSession.active():
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
