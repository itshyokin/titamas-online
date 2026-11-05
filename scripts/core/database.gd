extends Node
## The game's data (autoload "Database"), loaded from data/*.json: abilities, enemies and
## the player's stats and loadout. (Regions are read by AtmosphereManager itself so they
## also show in the editor.) Edit the files with the Database editor (Godot toolbar →
## Database). While the game runs from the editor, saved changes are picked up within a
## second: abilities update in place, enemies and the player re-apply their numbers.

## A data file was reloaded: "abilities", "enemies" or "player".
signal changed(which: String)

const FILES := {"abilities": DataFiles.ABILITIES, "enemies": DataFiles.ENEMIES, "player": DataFiles.PLAYER}

const ENEMY_FIELDS := [
	"aggro_radius", "leash_distance", "wander_radius", "walk_speed", "run_speed", "attack_power",
	"attack_range", "attack_cooldown", "attack_animation", "attack_animation_speed", "attack_hit_time",
	"attack_arc", "corpse_time", "respawn_time",
]
const PLAYER_STATS := ["max_health", "max_mana", "max_stamina", "stamina_regen", "stamina_regen_delay", "mana_regen"]
const PLAYER_MOVEMENT := ["run_speed", "walk_speed", "sprint_speed", "jump_velocity", "sprint_stamina_cost"]
const PLAYER_COMBAT := ["tap_time", "quick_shot_power", "block_reduction", "lunge_range"]

var abilities := {}  # id -> Ability (the same objects for the whole session)
var enemies := {}  # id -> Dictionary
var player := {}

var _times := {}
var _watch := 0.0


func _ready() -> void:
	for which: String in FILES:
		_load(which)


func _process(delta: float) -> void:
	# Live reload while testing from the editor.
	if not OS.has_feature("editor"):
		return
	_watch += delta
	if _watch < 1.0:
		return
	_watch = 0.0
	for which: String in FILES:
		if DataFiles.modified_time(FILES[which]) != _times.get(which, 0):
			_load(which)
			changed.emit(which)


func _load(which: String) -> void:
	var path: String = FILES[which]
	_times[which] = DataFiles.modified_time(path)
	var data = DataFiles.read(path)
	if data == null:
		return
	match which:
		"abilities":
			for d: Dictionary in data.get("abilities", []):
				var id := String(d.get("id", ""))
				if id.is_empty():
					continue
				if not abilities.has(id):
					abilities[id] = Ability.new()
				DataFiles.apply_ability(abilities[id], d)
		"enemies":
			enemies.clear()
			for d: Dictionary in data.get("enemies", []):
				enemies[String(d.get("id", ""))] = d
		"player":
			player = data


func ability(id: String) -> Ability:
	if not abilities.has(id):
		if not id.is_empty():
			push_warning("Database: no ability '%s' in %s" % [id, DataFiles.ABILITIES])
		return null
	return abilities[id]


func abilities_for(ids: Array) -> Array[Ability]:
	var out: Array[Ability] = []
	for id in ids:
		var ab := ability(String(id))
		if ab:
			out.append(ab)
	return out


func enemy(id: String) -> Dictionary:
	return enemies.get(id, {})


## Copies the enemy entry's numbers onto an Enemy (and its Stats and model).
func apply_enemy(node: Node, id: String, refill := false) -> void:
	var d := enemy(id)
	if d.is_empty():
		push_warning("Database: no enemy '%s' in %s" % [id, DataFiles.ENEMIES])
		return
	for field: String in ENEMY_FIELDS:
		if d.has(field):
			node.set(field, d[field])
	var stats := Combat.stats_of(node)
	if stats:
		stats.display_name = String(d.get("name", stats.display_name))
		stats.level = int(d.get("level", stats.level))
		var share := stats.health / maxf(stats.max_health, 1.0)
		stats.max_health = float(d.get("max_health", stats.max_health))
		stats.health = stats.max_health if refill else stats.max_health * share
		stats.health_changed.emit(stats.health, stats.max_health)
	var character := node.get_node_or_null("Model/Character")
	if character and d.has("skin_color"):
		character.set("skin_color", DataFiles.color_from(d.skin_color))


## Copies the player entry onto the player's Stats, controller and combat.
func apply_player(controller: Node, stats: Stats, combat: Node) -> void:
	if player.is_empty():
		return
	var s: Dictionary = player.get("stats", {})
	for field: String in PLAYER_STATS:
		if s.has(field):
			stats.set(field, float(s[field]))
	stats.health = minf(stats.health, stats.max_health)
	stats.mana = minf(stats.mana, stats.max_mana)
	stats.stamina = minf(stats.stamina, stats.max_stamina)
	stats.emit_all()
	var m: Dictionary = player.get("movement", {})
	for field: String in PLAYER_MOVEMENT:
		if m.has(field):
			controller.set(field, float(m[field]))
	var c: Dictionary = player.get("combat", {})
	for field: String in PLAYER_COMBAT:
		if c.has(field):
			combat.set(field, float(c[field]))
	var l: Dictionary = player.get("loadout", {})
	if l.has("light_combo"):
		combat.set("light_combo", abilities_for(l.light_combo))
	if l.has("heavy_attack"):
		combat.set("heavy_attack", ability(String(l.heavy_attack)))
	if l.has("ranged_attack"):
		combat.set("ranged_attack", ability(String(l.ranged_attack)))
	if l.has("spells"):
		combat.set("spells", abilities_for(l.spells.slice(0, 4)))
