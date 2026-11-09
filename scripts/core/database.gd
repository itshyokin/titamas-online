extends Node
## The game's data (autoload "Database"), loaded from data/*.json: abilities, enemies and
## the player's stats and loadout. (Regions are read by AtmosphereManager itself so they
## also show in the editor.) Edit the files with the Database editor (Godot toolbar →
## Database). While the game runs from the editor, saved changes are picked up within a
## second: abilities update in place, enemies and the player re-apply their numbers.

## A data file was reloaded: "abilities", "enemies" or "player".
signal changed(which: String)

const FILES := {"abilities": DataFiles.ABILITIES, "enemies": DataFiles.ENEMIES, "player": DataFiles.PLAYER, "items": DataFiles.ITEMS,
	"appearance": DataFiles.APPEARANCE, "classes": DataFiles.CLASSES, "npcs": DataFiles.NPCS,
	"weapon_types": DataFiles.WEAPON_TYPES, "animations": DataFiles.ANIMATIONS, "events": DataFiles.EVENTS,
	"achievements": DataFiles.ACHIEVEMENTS}

const ENEMY_FIELDS := [
	"aggro_radius", "leash_distance", "wander_radius", "walk_speed", "run_speed", "attack_power",
	"attack_range", "attack_cooldown", "attack_animation", "attack_animation_speed", "attack_hit_time",
	"attack_arc", "corpse_time", "respawn_time", "loot_time", "knockback", "heavy_every", "heavy_power",
	"heavy_animation", "heavy_animation_speed", "heavy_hit_time", "ragdoll", "death_push", "fade_time",
]
const PLAYER_STATS := ["max_health", "max_mana", "max_stamina", "stamina_regen", "stamina_regen_delay", "mana_regen"]
const PLAYER_MOVEMENT := ["run_speed", "walk_speed", "sprint_speed", "jump_velocity", "sprint_stamina_cost", "swim_speed",
	"swim_sprint_speed", "swim_sprint_stamina_cost", "double_tap_time", "lock_on_hops", "grab_any_ledge"]
const PLAYER_COMBAT := ["tap_time", "quick_shot_power", "block_reduction", "lunge_range", "parry_window",
	"counter_window", "perfect_dodge_window", "cast_pushback", "interrupt_share", "proficiency_damage", "proficiency_speed",
	"arrow_gravity", "combat_linger", "block_arc"]  # world_* / gash_time are read from Database.player directly
const PLAYER_TARGETING := ["tab_range", "lock_range", "lose_range", "snap_range", "tab_selects", "attack_selects", "click_radius"]

var abilities := {}  # id -> Ability (the same objects for the whole session)
var enemies := {}  # id -> Dictionary
var player := {}
var items := {}  # id -> Dictionary (data/items.json entries)
## data/appearance.json: the character creator's choices (styles, colours, sizes).
var appearance := {}
var classes: Array = []  # data/classes.json entries, in order
var npcs := {}  # id -> Dictionary (data/npcs.json entries)
var weapon_types := {}  # id -> Dictionary (data/weapon_types.json entries)
## data/animations.json: clip import settings (used by the retarget tool), which clip
## plays for each role (CharacterModel.roles), head turning and strafing settings.
var animations := {}
## data/events.json: events (pages of commands, placed in levels with MapEvent), and the
## names of switches and variables.
var events := {}  # id -> Dictionary
var switches: Array = []  # [{id, name}]
var variables: Array = []  # [{id, name}]
## data/achievements.json entries, in order (the Achievements autoload uses them).
var achievements: Array = []

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
		"items":
			items.clear()
			for d: Dictionary in data.get("items", []):
				items[String(d.get("id", ""))] = d
		"appearance":
			appearance = data
		"classes":
			classes = data.get("classes", [])
		"animations":
			animations = data
			CharacterModel.roles = data.get("roles", {})
		"weapon_types":
			weapon_types.clear()
			for d in data.get("types", []):
				weapon_types[String(d.get("id", ""))] = d
		"events":
			events.clear()
			for d in data.get("events", []):
				events[String(d.get("id", ""))] = d
			switches = data.get("switches", [])
			variables = data.get("variables", [])
			if is_inside_tree():
				get_tree().call_group.call_deferred("map_events", "reload")
		"achievements":
			achievements = data.get("achievements", [])
		"npcs":
			npcs.clear()
			for d in data.get("npcs", []):
				npcs[String(d.get("id", ""))] = d


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


## Head-turning settings (data/animations.json "look"): range, max_yaw, max_pitch, speed, neck_share.
func look_settings() -> Dictionary:
	return animations.get("look", {})


## A weapon family (sword, bow, pistol...) from data/weapon_types.json ({} if unknown).
func weapon_type(id: String) -> Dictionary:
	return weapon_types.get(id, {})


## An event's data ({} if unknown).
func event(id: String) -> Dictionary:
	return events.get(id, {})


## An NPC's data ({} if unknown).
func npc(id: String) -> Dictionary:
	return npcs.get(id, {})


## A class entry from data/classes.json ({} if unknown).
func class_data(id: String) -> Dictionary:
	for c: Dictionary in classes:
		if String(c.get("id", "")) == id:
			return c
	return {}


## One entry of an appearance list ("hair_styles", "eyes", "heights"...) by id ({} if unknown).
func appearance_option(list: String, id: String) -> Dictionary:
	for o in appearance.get(list, []):
		if o is Dictionary and String(o.get("id", "")) == id:
			return o
	return {}


## Turns a saved look (ids and "#rrggbb" colours, see data/appearance.json "default")
## into what CharacterModel.apply_appearance() needs.
func resolve_appearance(look: Dictionary) -> Dictionary:
	var d: Dictionary = appearance.get("default", {})
	var get := func(key: String) -> String: return String(look.get(key, d.get(key, "")))
	var body: String = get.call("body")
	var placement: Dictionary = appearance.get("eye_placement", {})
	return {
		"body": body,
		"skin": Color.html(get.call("skin")) if Color.html_is_valid(get.call("skin")) else Color(0.8, 0.6, 0.45),
		"head": appearance_option("heads", get.call("head")),
		"face": appearance_option("faces", get.call("face")),
		"hair": appearance_option("hair_styles", get.call("hair")),
		"hair_color": Color.html(get.call("hair_color")) if Color.html_is_valid(get.call("hair_color")) else Color(0.25, 0.15, 0.1),
		"facial_hair": appearance_option("facial_hair", get.call("facial_hair")),
		"facial_color": Color.html(get.call("facial_color")) if Color.html_is_valid(get.call("facial_color")) else Color(0.25, 0.15, 0.1),
		"eyes": appearance_option("eyes", get.call("eyes")),
		"eye_color": Color.html(get.call("eye_color")) if Color.html_is_valid(get.call("eye_color")) else Color(0.3, 0.5, 0.8),
		"eye_placement": placement.get(body, {}),
		"underwear": appearance.get("underwear", {}),
		"height_scale": float(appearance_option("heights", get.call("height")).get("scale", 1.0)),
		"weight": float(appearance_option("builds", get.call("build")).get("weight", 0.0)),
	}


## An item's data ({} if there's no such item).
func item(id: String) -> Dictionary:
	return items.get(id, {})


## How many of an item fit in one backpack slot.
func stack_size(id: String) -> int:
	var d := item(id)
	var explicit := int(d.get("stack_max", 0))
	if explicit > 0:
		return explicit
	return 1 if String(d.get("slot", "")) != "" else 64


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
	if d.has("death_sounds"):
		var list: Array[AudioStream] = []
		for path in d.death_sounds:
			if ResourceLoader.exists(String(path)):
				list.append(load(String(path)))
		node.set("death_sounds", list)
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
	stats.stamina = minf(stats.stamina, stats.max_stamina)
	stats.set_base(stats.max_health if not s.has("max_health") else float(s.max_health),
		stats.max_mana if not s.has("max_mana") else float(s.max_mana))
	var m: Dictionary = player.get("movement", {})
	for field: String in PLAYER_MOVEMENT:
		if m.has(field):
			controller.set(field, float(m[field]))
	var c: Dictionary = player.get("combat", {})
	for field: String in PLAYER_COMBAT:
		if c.has(field):
			combat.set(field, float(c[field]))
	var targeting = combat.get("targeting") if combat else null
	if targeting == null and controller:
		targeting = controller.get_node_or_null("Targeting")
	if targeting:
		for field: String in PLAYER_TARGETING:
			if c.has(field):
				targeting.set(field, float(c[field]))
	if c.has("move_cancels_cast"):
		combat.set("move_cancels_cast", bool(c.move_cancels_cast))
	if c.has("perfect_dodge_window"):
		controller.set("perfect_dodge_window", float(c.perfect_dodge_window))
	var l: Dictionary = player.get("loadout", {})
	if l.has("light_combo"):
		combat.set("light_combo", abilities_for(l.light_combo))
	if l.has("heavy_attack"):
		combat.set("heavy_attack", ability(String(l.heavy_attack)))
	if l.has("ranged_attack"):
		combat.set("ranged_attack", ability(String(l.ranged_attack)))
	if l.has("spells"):
		combat.set("spells", abilities_for(l.spells))
