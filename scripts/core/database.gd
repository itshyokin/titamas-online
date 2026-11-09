extends Node
## The game's data (autoload "Database"), loaded from data/*.json: abilities, enemies and
## the player's stats and loadout. (Regions are read by AtmosphereManager itself so they
## also show in the editor.) Edit the files with the Database editor (Godot toolbar →
## Database). While the game runs from the editor, saved changes are picked up within a
## second: abilities update in place, enemies and the player re-apply their numbers.

## A data file was reloaded: "abilities", "enemies" or "player".
signal changed(which: String)

const FILES := {"abilities": DataFiles.ABILITIES, "enemies": DataFiles.ENEMIES, "player": DataFiles.PLAYER, "items": DataFiles.ITEMS,
	"appearance": DataFiles.APPEARANCE, "classes": DataFiles.CLASSES, "skill_trees": DataFiles.SKILL_TREES, "quests": DataFiles.QUESTS, "npcs": DataFiles.NPCS,
	"weapon_types": DataFiles.WEAPON_TYPES, "animations": DataFiles.ANIMATIONS, "events": DataFiles.EVENTS,
	"achievements": DataFiles.ACHIEVEMENTS, "body_models": DataFiles.BODY_MODELS, "lore": DataFiles.LORE, "species": DataFiles.SPECIES, "statuses": DataFiles.STATUSES}

## Appearance lists filled from Body Models pieces by their "use" (see _merge_pieces).
const PIECE_LISTS := {"hair": "hair_styles", "facial_hair": "facial_hair", "head": "heads", "face": "faces"}
const PIECE_DIR := "res://assets/characters/lowpoly/"

const ENEMY_FIELDS := [
	"aggro_radius", "leash_distance", "wander_radius", "walk_speed", "run_speed", "attack_power",
	"attack_range", "attack_cooldown", "attack_animation", "attack_animation_speed", "attack_hit_time",
	"attack_arc", "corpse_time", "respawn_time", "loot_time", "knockback", "heavy_every", "heavy_power",
	"heavy_animation", "heavy_animation_speed", "heavy_hit_time", "ragdoll", "death_push", "fade_time",
]
const PLAYER_STATS := ["max_health", "max_mana", "max_stamina", "stamina_regen", "stamina_regen_delay", "mana_regen"]
const PLAYER_MOVEMENT := ["injured_speed", "injured_health", "run_speed", "walk_speed", "sprint_speed", "jump_velocity", "sprint_stamina_cost", "swim_speed",
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
## data/species.json "species": {id, name, description, head, build (-1 thin .. 1 heavy),
## height (scale), attributes {id: +n}, stats {stat: +n}, movement {run_speed... jump:
## multipliers}, racial [{ability, power_per_level}], traits}.
var species_list: Array = []
## data/statuses.json: status ailments, buffs and debuffs by id (see Stats.add_status).
var statuses := {}
## Codex lore entries (data/lore.json): {id, title, category, text, conditions}.
var lore: Array = []
## data/body_models.json (pieces built from the body .glb).
var body_models := {}
var _appearance_file := {}
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
## data/skill_trees.json trees, in order (see trees_for).
var skill_trees: Array = []
## data/quests.json quests (the Quests class reads them).
var quests: Array = []
## The top of data/quests.json (start_sound, complete_sound, sound_db).
var quest_settings := {}
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
			_appearance_file = data
			_merge_pieces()
		"lore":
			lore = data.get("entries", [])
		"species":
			species_list = data.get("species", [])
		"statuses":
			statuses.clear()
			for d in data.get("statuses", []):
				statuses[String(d.get("id", ""))] = d
		"body_models":
			body_models = data
			_merge_pieces()
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
		"skill_trees":
			skill_trees = data.get("trees", [])
		"quests":
			quests = data.get("quests", [])
			quest_settings = data
			Quests.revision += 1
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


## What a Body Models piece is for: its "use" (hair / facial_hair / head / face / "" = an
## item or other), guessed from the id when it has none (hair_*, beard / mustache / goatee).
static func piece_use(piece: Dictionary) -> String:
	if piece.has("use"):
		return String(piece.use)
	var id := String(piece.get("id", "")).to_lower()
	if id.begins_with("hair") or id.ends_with("_hair") or id.contains("hairstyle"):
		return "hair"
	for w in ["beard", "mustache", "moustache", "goatee", "stubble", "sideburn"]:
		if id.contains(w):
			return "facial_hair"
	return ""


## Shown name of a piece: its "name", else the id made readable (hair_long_wavy → Long wavy).
static func piece_name(piece: Dictionary) -> String:
	if String(piece.get("name", "")) != "":
		return String(piece.name)
	var id := String(piece.get("id", ""))
	for prefix in ["hair_", "hairstyle_"]:
		if id.begins_with(prefix):
			id = id.trim_prefix(prefix)
	return id.replace("_", " ").capitalize()


## appearance = appearance.json plus an option for every Body Models piece marked hair /
## facial hair / head / face (built to assets/characters/lowpoly/<id>_masc.scn). Options
## in appearance.json with the same id win (so one can be given a fit, hides, etc.).
func _merge_pieces() -> void:
	appearance = _appearance_file.duplicate(true)
	for piece in body_models.get("pieces", []):
		if not piece is Dictionary:
			continue
		var list_key: String = PIECE_LISTS.get(piece_use(piece), "")
		var id := String(piece.get("id", ""))
		if list_key == "" or id == "":
			continue
		var path := PIECE_DIR + id + "_masc.scn"
		if not ResourceLoader.exists(path):
			continue  # not built yet (Rebuild in Body Models)
		var list: Array = appearance.get(list_key, [])
		if list.any(func(o) -> bool: return o is Dictionary and String(o.get("id", "")) == id):
			continue
		var opt := {"id": id, "name": piece_name(piece), "fitted_masc": path, "fitted_femme": ""}
		if piece_use(piece) == "head":
			opt["hides"] = ["head"]
		list.append(opt)
		appearance[list_key] = list


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
	# One androgynous body for everyone (the femme body is kept only for old content;
	# appearance.json "bodies" lists the ones characters may use).
	var body: String = get.call("body")
	if not body in (appearance.get("bodies", ["masc"]) as Array):
		body = "masc"
	var placement: Dictionary = appearance.get("eye_placement", {})
	# The species sets the head, height and build (the look's own choices are kept only
	# for species that leave them out).
	# (NPC looks without a species keep their own height / build / head.)
	var sp := species_data(String(look.species)) if look.has("species") and not species_list.is_empty() else {}
	var head_id: String = String(sp.get("head", "")) if String(sp.get("head", "")) != "" else get.call("head")
	return {
		"body": body,
		"skin": Color.html(get.call("skin")) if Color.html_is_valid(get.call("skin")) else Color(0.8, 0.6, 0.45),
		"head": appearance_option("heads", head_id),
		"face": appearance_option("faces", get.call("face")),
		"hair": _hair_option(get.call("hair"), String(d.get("hair", ""))),
		"hair_color": Color.html(get.call("hair_color")) if Color.html_is_valid(get.call("hair_color")) else Color(0.25, 0.15, 0.1),
		"facial_hair": appearance_option("facial_hair", get.call("facial_hair")),
		"facial_color": Color.html(get.call("facial_color")) if Color.html_is_valid(get.call("facial_color")) else Color(0.25, 0.15, 0.1),
		"eyes": appearance_option("eyes", get.call("eyes")),
		"eye_color": Color.html(get.call("eye_color")) if Color.html_is_valid(get.call("eye_color")) else Color(0.3, 0.5, 0.8),
		"eye_placement": placement.get(body, {}),
		"underwear": appearance.get("underwear", {}),
		"height_scale": float(sp.get("height", appearance_option("heights", get.call("height")).get("scale", 1.0))),
		"weight": float(sp.get("build", appearance_option("builds", get.call("build")).get("weight", 0.0))),
	}


## A hair style by id; an unknown id (an old generated style) falls back to the default.
func _hair_option(id: String, fallback: String) -> Dictionary:
	var o := appearance_option("hair_styles", id)
	if o.is_empty() and id != "" and id != "bald":
		o = appearance_option("hair_styles", fallback)
	return o


## A species by id (the first one if unknown, {} if there are none).
func species_data(id: String) -> Dictionary:
	for sp: Dictionary in species_list:
		if String(sp.get("id", "")) == id:
			return sp
	return species_list[0] if not species_list.is_empty() else {}


## The species of a saved character (its look's "species").
func species_of(save: Dictionary) -> Dictionary:
	return species_data(String((save.get("look", {}) as Dictionary).get("species", "human")))


## Attributes from player.json: [[id, name, description, effects]].
func attribute_list() -> Array:
	var out := []
	for a: Dictionary in player.get("attributes", {}).get("list", []):
		out.append([String(a.get("id", "")), String(a.get("name", "")), String(a.get("description", "")), a.get("effects", {})])
	return out


## A character's attribute values: base + species + points spent at creation.
func attributes_for(save: Dictionary) -> Dictionary:
	var cfg: Dictionary = player.get("attributes", {})
	var base := int(cfg.get("base", 10))
	var sp: Dictionary = species_of(save).get("attributes", {})
	var spent: Dictionary = save.get("attribute_points", {})
	var out := {}
	for a: Array in attribute_list():
		out[a[0]] = base + int(sp.get(a[0], 0)) + int(spent.get(a[0], 0))
	return out


## Stat bonuses from attributes (each point above the base gives the attribute's effects).
func attribute_bonus(values: Dictionary) -> Dictionary:
	var base := int(player.get("attributes", {}).get("base", 10))
	var out := {}
	for a: Array in attribute_list():
		var n := int(values.get(a[0], base)) - base
		for stat: String in (a[3] as Dictionary):
			out[stat] = float(out.get(stat, 0.0)) + float(a[3][stat]) * n
	return out


## A class's skill trees, by their order.
func trees_for(class_id: String) -> Array:
	var out := skill_trees.filter(func(t: Dictionary) -> bool: return String(t.get("class", "")) == class_id)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 0)) < int(b.get("order", 0)))
	return out


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
	# The species' movement multipliers (walk / run / sprint / swim speeds, jump).
	var session := get_tree().root.get_node_or_null("GameSession")
	var sp_move: Dictionary = species_of(session.get("data")).get("movement", {}) if session and session.call("active") else {}
	for field: String in PLAYER_MOVEMENT:
		if m.has(field):
			var k := float(sp_move.get(field, 1.0))
			if field == "jump_velocity":
				k = sqrt(float(sp_move.get("jump", 1.0)))  # jump height scales with velocity squared
			controller.set(field, float(m[field]) * k)
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
