@tool
class_name DataFiles
extends RefCounted
## Reading and writing the game's JSON data (data/*.json), which the Database editor
## (Godot toolbar → Database) edits. Converts between JSON values and Godot ones:
## colours are "#rrggbb" strings, sounds are res:// paths, enums are lowercase names.

const DIR := "res://data"
const ABILITIES := "res://data/abilities.json"
const ENEMIES := "res://data/enemies.json"
const PLAYER := "res://data/player.json"
const REGIONS := "res://data/regions.json"
const WORLD := "res://data/world.json"
const ITEMS := "res://data/items.json"
const APPEARANCE := "res://data/appearance.json"
const CLASSES := "res://data/classes.json"
const SKILL_TREES := "res://data/skill_trees.json"
const NPCS := "res://data/npcs.json"
const WEAPON_TYPES := "res://data/weapon_types.json"
const ANIMATIONS := "res://data/animations.json"
const EVENTS := "res://data/events.json"
const ACHIEVEMENTS := "res://data/achievements.json"

## Ability fields that need converting (everything else is a plain number/string/bool).
const ABILITY_COLORS := ["color", "projectile_color"]
const ABILITY_ENUMS := {
	"delivery": ["melee", "projectile", "heal_over_time"],
	"projectile_style": ["bolt", "arrow", "bullet"],
}
const ABILITY_FIELDS := [
	"id", "display_name", "description", "delivery", "color", "icon", "power", "mana_cost", "stamina_cost",
	"cooldown", "reach", "arc", "staggers", "knockback", "cast_time", "charge_time", "windup_time", "charge_power", "max_charge_level", "ticks",
	"tick_interval", "projectile_speed", "projectile_color", "projectile_style", "animation",
	"animation_speed", "hit_time", "recovery_time", "move_scale", "sounds", "hit_sound", "cast_loop_sound", "release_sound",
]
const ABILITY_STREAMS := ["hit_sound", "cast_loop_sound", "release_sound"]
const REGION_COLORS := ["fog_color", "sky_top", "sky_horizon", "sky_ground", "cloud_color", "cloud_shade", "sun_color", "grass_base", "grass_tip", "shadow_color"]
## Region fields that are sounds (res:// paths in the file).
const REGION_STREAMS := ["ambient_loop", "ambient_loop_night", "music", "music_night"]
const REGION_FIELDS := [
	"region_name", "fog_color", "fog_density", "fog_sky_affect", "sky_top", "sky_horizon", "sky_ground",
	"cloud_color", "cloud_shade", "cloud_coverage", "sun_color", "sun_energy", "ambient_energy",
	"shadow_strength", "shadow_color", "shadow_fill", "saturation", "contrast", "brightness", "god_rays", "grass_density", "grass_base",
	"grass_tip", "grass_height", "grass_ground_match", "ambient_loop", "ambient_loop_night", "ambient_volume_db", "wind_volume_db", "music", "music_night", "music_volume_db",
]


static func read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		push_error("DataFiles: couldn't read %s (not valid JSON)" % path)
	return data


static func write(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("DataFiles: couldn't write %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t", false) + "\n")


static func modified_time(path: String) -> int:
	return FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0


static func color_from(value: Variant, fallback := Color.WHITE) -> Color:
	if value is String and Color.html_is_valid(value):
		return Color.html(value)
	return fallback


static func color_to(c: Color) -> String:
	return "#" + c.to_html(c.a < 0.999)


static func stream_from(path: Variant) -> AudioStream:
	if path is String and not path.is_empty() and ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null


static func stream_to(stream: AudioStream) -> String:
	return stream.resource_path if stream else ""


# --- Abilities -------------------------------------------------------------------

static func ability_to_dict(ab: Ability) -> Dictionary:
	var d := {}
	for field: String in ABILITY_FIELDS:
		var v: Variant = ab.get(field)
		if field in ABILITY_COLORS:
			v = color_to(v)
		elif ABILITY_ENUMS.has(field):
			v = ABILITY_ENUMS[field][int(v)]
		elif field == "sounds":
			v = (v as Array).map(func(s: AudioStream) -> String: return stream_to(s))
		elif field in ABILITY_STREAMS:
			v = stream_to(v)
		d[field] = v
	return d


## Fills an Ability from its JSON entry (fields missing from the entry keep their defaults).
static func apply_ability(ab: Ability, d: Dictionary) -> void:
	for field: String in d:
		if not field in ABILITY_FIELDS:
			continue
		var v: Variant = d[field]
		if field in ABILITY_COLORS:
			ab.set(field, color_from(v))
		elif ABILITY_ENUMS.has(field):
			ab.set(field, maxi(ABILITY_ENUMS[field].find(String(v)), 0))
		elif field == "sounds":
			var list: Array[AudioStream] = []
			for p in v:
				var s := stream_from(p)
				if s:
					list.append(s)
			ab.sounds = list
		elif field in ABILITY_STREAMS:
			ab.set(field, stream_from(v))
		elif field in ["max_charge_level", "ticks"]:
			ab.set(field, int(v))
		else:
			ab.set(field, v)


# --- Regions ---------------------------------------------------------------------

static func region_to_dict(r: RegionAtmosphere, id: String, is_default := false) -> Dictionary:
	var d := {"id": id, "default": is_default, "chunks": [r.chunks.position.x, r.chunks.position.y, r.chunks.size.x, r.chunks.size.y]}
	for field: String in REGION_FIELDS:
		var v: Variant = r.get(field)
		if field in REGION_COLORS:
			v = color_to(v)
		elif field in REGION_STREAMS:
			v = stream_to(v)
		d[field] = v
	return d


static func region_from_dict(d: Dictionary) -> RegionAtmosphere:
	var r := RegionAtmosphere.new()
	var c: Array = d.get("chunks", [0, 0, 1, 1])
	if c.size() == 4:
		r.chunks = Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3]))
	for field: String in REGION_FIELDS:
		if not d.has(field):
			continue
		var v: Variant = d[field]
		if field in REGION_COLORS:
			r.set(field, color_from(v))
		elif field in REGION_STREAMS:
			r.set(field, stream_from(v))
		else:
			r.set(field, v)
	return r
