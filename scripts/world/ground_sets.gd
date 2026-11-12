@tool
class_name GroundSets
## Ground sets: other trios of terrain textures (desert: sand / desert stone / cliff...).
## A Blender terrain painted with set "desert" exports its material as "terrain_desert";
## ChunkStreamer asks material("desert") for it, a copy of terrain.tres with the set's three
## textures. The standard set is terrain.tres itself (grass / dirt / cliff).
## Data: data/ground.json (Database tab Ground Sets), re-read when it changes.
## Names no autoloads, so it works in the editor preview and in tests.

const FILE := "res://data/ground.json"
const BASE := "res://assets/materials/terrain/terrain.tres"
## What the standard set's three layers sound like underfoot.
const STANDARD_SURFACES := ["grass", "dirt", "stone"]
const PARAMS := ["tex_r", "tex_g", "tex_b"]

static var _sets := {}  # id -> Dictionary
static var _stamp := -1
static var _checked_msec := -100000
static var _materials := {}  # id -> ShaderMaterial


## The id a chunk material name stands for: "terrain_desert" → "desert", "terrain" → "".
static func id_of_material(mat_name: String) -> String:
	return mat_name.trim_prefix("terrain_") if mat_name.begins_with("terrain_") else ""


static func set_data(id: String) -> Dictionary:
	_refresh()
	return _sets.get(id, {})


static func ids() -> Array:
	_refresh()
	return _sets.keys()


## The shared material for a set (null if there is no such set).
static func material(id: String) -> ShaderMaterial:
	_refresh()
	if not _sets.has(id):
		return null
	if not _materials.has(id):
		var base := load(BASE) as ShaderMaterial
		if base == null:
			return null
		var mat := base.duplicate() as ShaderMaterial
		mat.resource_name = "terrain_" + id
		_materials[id] = mat
		_apply(id)
	return _materials[id]


## Every set material built so far (AtmosphereManager copies live settings onto them).
static func built() -> Array:
	return _materials.values()


## Footstep surface for paint (dirt share, cliff share) on this set's ground.
static func surface(id: String, paint: Vector2, normal_y: float) -> String:
	var names: Array = STANDARD_SURFACES
	var d := set_data(id)
	if not d.is_empty():
		names = []
		var layers: Array = d.get("layers", [])
		for i in 3:
			var layer: Dictionary = layers[i] if i < layers.size() else {}
			names.append(String(layer.get("surface", STANDARD_SURFACES[i])))
	if paint.y > 0.5 or normal_y < 0.7:
		return names[2]
	if paint.x > 0.5:
		return names[1]
	return names[0]


## Grass density × for chunks of this set (sand: 0).
static func grass_scale(id: String) -> float:
	var d := set_data(id)
	return float(d.get("grass", 1.0)) if not d.is_empty() else 1.0


## The three textures of a set ("" = standard), for the region map's colours.
static func textures(id: String) -> Array:
	var mat: ShaderMaterial = material(id) if id != "" else load(BASE) as ShaderMaterial
	var out := []
	for p in PARAMS:
		out.append(mat.get_shader_parameter(p) if mat else null)
	return out


static func _refresh() -> void:
	var now := Time.get_ticks_msec()
	if _stamp != -1 and now - _checked_msec < 1000:
		return
	_checked_msec = now
	var stamp := FileAccess.get_modified_time(FILE) if FileAccess.file_exists(FILE) else 0
	if stamp == _stamp:
		return
	_stamp = stamp
	_sets.clear()
	if stamp != 0:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if parsed is Dictionary:
			for d in parsed.get("sets", []):
				if d is Dictionary and String(d.get("id", "")) != "":
					# The Database page may save layers as {"0": ..} if a set had none yet.
					var layers = d.get("layers", [])
					if layers is Dictionary:
						d["layers"] = [layers.get("0", {}), layers.get("1", {}), layers.get("2", {})]
					elif not layers is Array:
						d["layers"] = []
					_sets[String(d.id)] = d
	# Edits in the Database show on chunks already in the world.
	for id in _materials.keys():
		_apply(id)


static func _apply(id: String) -> void:
	var mat: ShaderMaterial = _materials.get(id)
	var d: Dictionary = _sets.get(id, {})
	if mat == null or d.is_empty():
		return
	var base := load(BASE) as ShaderMaterial
	var layers: Array = d.get("layers", [])
	for i in 3:
		var layer: Dictionary = layers[i] if i < layers.size() else {}
		var path := String(layer.get("texture", ""))
		var tex: Texture2D = load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
		mat.set_shader_parameter(PARAMS[i], tex if tex else base.get_shader_parameter(PARAMS[i]))
	for key in ["tile_size", "tile_size_b"]:
		if d.has(key) and float(d[key]) > 0.0:
			mat.set_shader_parameter(key, float(d[key]))
		else:
			mat.set_shader_parameter(key, base.get_shader_parameter(key))
