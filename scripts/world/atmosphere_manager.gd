@tool
class_name AtmosphereManager
extends Node
## Blends fog, sky colours and sunlight to match the region the player is in, and
## shows the region's name when entering it (WoW-style zone text).

## Regions come from this file (edited with the Database editor: Godot toolbar →
## Database → Regions). Changes show up within a second, in the editor and in game.
@export_file("*.json") var regions_file := DataFiles.REGIONS
# Filled from regions_file (not saved in the scene: the Database is the only copy).
var regions: Array[RegionAtmosphere] = []
## Used outside every region (open sea, unassigned land): the region marked "default".
var default_atmosphere: RegionAtmosphere
@export var environment_path: NodePath
@export var sun_path: NodePath
@export var target_path: NodePath
@export var chunk_size := 64.0
## Roughly how long a full change of atmosphere takes.
@export var blend_seconds := 4.0
## In the editor, show this region's look so it can be tuned live: 0, 1, ... = entries in
## Regions, -1 = the default (open sea). Edit the region's .tres and the view updates.
@export var editor_preview_region := 0

@export_group("Sound")
## Wind heard everywhere; each region sets how strong it is, and it gets stronger with height.
@export var wind_loop: AudioStream = preload("res://assets/audio/ambience/wind_loop.ogg")
## Extra wind (dB) at `windy_height` metres and above.
@export var altitude_wind_db := 16.0
@export var windy_height := 60.0
## Seconds to crossfade between region ambience.
@export var ambience_fade := 3.0

var current: RegionAtmosphere
## Grass clumps per square metre in the current region (read by the ChunkStreamer's grass).
var grass_density := 3.0

var _env: Environment
var _sky: ShaderMaterial
var _sun: DirectionalLight3D
var _target: Node3D
var _check_timer := 0.0
var _values := {}
var _label: Label
var _file_time := -1
var _preview_key := ""
var _file_check := 0.0
var _world_time := -1
## Rain, storms, fog and cloud shadows (Weather), made in _ready.
var weather: Weather
var _label_tween: Tween
var _beds: Array[AudioStreamPlayer] = []  # two players, crossfaded between regions
var _music: Array[AudioStreamPlayer] = []
var _ambience_night := false
var _night_check := 0.0
## Seconds music takes to cross between regions (and day / night).
@export var music_fade := 4.0
var _bed_index := 0
var _wind: AudioStreamPlayer

# Property name -> how it's applied.
const FIELDS := [
	"fog_color", "fog_density", "fog_sky_affect", "sky_top", "sky_horizon", "sky_ground",
	"cloud_color", "cloud_shade", "cloud_coverage", "sun_color", "sun_energy", "ambient_energy",
	"shadow_strength", "shadow_color", "shadow_fill", "night_sky_top", "night_sky_horizon", "night_fog", "stars",
	"sky_panorama_strength", "saturation", "contrast", "brightness", "god_rays",
	"grass_base", "grass_tip", "grass_density", "grass_height", "grass_ground_match",
]


func _ready() -> void:
	add_to_group("atmosphere")
	_load_regions()
	var world_env := get_node_or_null(environment_path) as WorldEnvironment
	if world_env:
		_env = world_env.environment
		if _env.sky:
			_sky = _env.sky.sky_material as ShaderMaterial
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_target = get_node_or_null(target_path) as Node3D
	if Engine.is_editor_hint():
		return
	_apply_ssao()
	GameSettings.graphics_changed.connect(_apply_ssao)
	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	var random_sounds := RandomAmbience.new()
	random_sounds.name = "RandomAmbience"
	random_sounds.atmosphere = self
	add_child(random_sounds)
	var leaves := LeafFall.new()
	leaves.name = "LeafFall"
	add_child(leaves)
	var wildlife := Wildlife.new()
	wildlife.name = "Wildlife"
	add_child(wildlife)
	_build_label()
	_build_audio()
	current = _region_at_target()
	if current:
		for f in FIELDS:
			_values[f] = current.get(f)
		_apply()
		_change_ambience(current, 0.5)


func _process(delta: float) -> void:
	_file_check += delta
	if _file_check > 1.0:
		_file_check = 0.0
		# Ambient occlusion settings (data/world.json) apply live as the Database saves them.
		if not Engine.is_editor_hint() and DataFiles.modified_time(DataFiles.WORLD) != _world_time:
			_apply_ssao()
		if DataFiles.modified_time(regions_file) != _file_time:
			_load_regions()
			if current and not Engine.is_editor_hint():
				current = region_at(_target.global_position) if _target else default_atmosphere
				_change_ambience(current, 1.0)
	if Engine.is_editor_hint():
		_editor_preview()
		return
	if _target == null:
		return
	_check_timer += delta
	if _check_timer > 0.25:
		_check_timer = 0.0
		var region := _region_at_target()
		if region and region != current:
			current = region
			_show_name(region.region_name)
			_change_ambience(region, ambience_fade)
		if weather and current:
			weather.set_region(current)
	if current == null:
		return
	_update_wind(delta)
	# Day turning to night (or back): the night sounds and music fade in.
	_night_check += delta
	if _night_check > 2.0:
		_night_check = 0.0
		if _is_night() != _ambience_night:
			_change_ambience(current, 6.0)
	var k := 1.0 - exp(-delta * 3.0 / maxf(blend_seconds, 0.01))
	for f in FIELDS:
		var goal: Variant = current.get(f)
		var now: Variant = _values.get(f, goal)
		_values[f] = (now as Color).lerp(goal, k) if goal is Color else lerpf(now, goal, k)
	_apply()


func _editor_preview() -> void:
	if _env == null:
		return
	var region: RegionAtmosphere = default_atmosphere
	if editor_preview_region >= 0 and editor_preview_region < regions.size() and regions[editor_preview_region]:
		region = regions[editor_preview_region]
	if region == null:
		return
	var changed := false
	for f in FIELDS:
		var v: Variant = region.get(f)
		if _values.get(f) != v:
			_values[f] = v
			changed = true
	var cycle := get_tree().get_first_node_in_group("world_cycle") as WorldCycle
	var key := "%.3f" % cycle.hour if cycle else ""
	if changed or key != _preview_key:
		_preview_key = key
		_apply()


## Reads regions_file. Keeps the current arrays if there's no file.
func _load_regions() -> void:
	_file_time = DataFiles.modified_time(regions_file)
	var data = DataFiles.read(regions_file)
	if not data is Dictionary:
		return
	var list: Array[RegionAtmosphere] = []
	var fallback: RegionAtmosphere = null
	for d: Dictionary in data.get("regions", []):
		var r := DataFiles.region_from_dict(d)
		if d.get("default", false):
			fallback = r
		else:
			list.append(r)
	regions = list
	if fallback:
		default_atmosphere = fallback
	_values.clear()  # editor preview re-applies


## The region at a world position (first match wins), or the default.
func region_at(point: Vector3) -> RegionAtmosphere:
	var cell := Vector2i(roundi(point.x / chunk_size), roundi(point.z / chunk_size))
	for r in regions:
		if r and r.chunks.has_point(cell):
			return r
	return default_atmosphere


func _region_at_target() -> RegionAtmosphere:
	return region_at(_target.global_position) if _target else default_atmosphere


func _apply() -> void:
	# Day/night: the time of day tints the region's look.
	var cycle := get_tree().get_first_node_in_group("world_cycle") as WorldCycle if is_inside_tree() else null
	var v: Dictionary = cycle.apply_time(_values) if cycle else _values
	if weather:
		v = weather.modify(v)
	if _env:
		_env.fog_light_color = v.fog_color
		_env.fog_density = v.fog_density
		_env.fog_sky_affect = v.fog_sky_affect
		_env.ambient_light_energy = v.ambient_energy
		# Shade colour: part of the ambient light is the region's shadow colour, so the
		# unlit sides are dark blue-grey instead of black (and ambient occlusion shows).
		_env.ambient_light_color = v.shadow_color
		_env.ambient_light_sky_contribution = 1.0 - clampf(float(v.shadow_fill), 0.0, 1.0)
		_env.adjustment_enabled = true
		_env.adjustment_saturation = v.saturation
		_env.adjustment_contrast = v.contrast
		_env.adjustment_brightness = v.brightness
		# God rays: light shafts through volumetric fog (Settings → Graphics can turn them off).
		var settings := get_node_or_null("/root/GameSettings")
		var rays_on: bool = settings == null or bool(settings.get("god_rays"))
		var rays: float = v.get("god_rays", 0.0)
		_env.volumetric_fog_enabled = rays_on and rays > 0.01
		if _env.volumetric_fog_enabled:
			_env.volumetric_fog_density = 0.012 * rays
			_env.volumetric_fog_albedo = (v.fog_color as Color).lerp(Color.WHITE, 0.5)
			_env.volumetric_fog_anisotropy = 0.7
			_env.volumetric_fog_length = 80.0
			_env.volumetric_fog_sky_affect = 0.0
	if _sky:
		_sky.set_shader_parameter("top_color", v.sky_top)
		_sky.set_shader_parameter("horizon_color", v.sky_horizon)
		_sky.set_shader_parameter("ground_color", v.sky_ground)
		_sky.set_shader_parameter("cloud_color", v.cloud_color)
		_sky.set_shader_parameter("cloud_shade", v.cloud_shade)
		_sky.set_shader_parameter("cloud_coverage", v.cloud_coverage)
		_sky.set_shader_parameter("sun_color", v.sun_color)
		_sky.set_shader_parameter("use_cycle", cycle != null)
		_sky.set_shader_parameter("cloud_darken", float(v.get("cloud_darken", 0.0)))
		_sky.set_shader_parameter("stars_amount", float(v.get("stars", 1.0)))
		var region_now: RegionAtmosphere = current if current else default_atmosphere
		var pano: Texture2D = region_now.sky_panorama if region_now else null
		_sky.set_shader_parameter("panorama", pano)
		_sky.set_shader_parameter("panorama_strength", float(v.get("sky_panorama_strength", 0.0)) if pano else 0.0)
		if cycle:
			_sky.set_shader_parameter("sun_direction", cycle.sun_direction)
			_sky.set_shader_parameter("moon_direction", cycle.moon_direction)
			_sky.set_shader_parameter("night_amount", 1.0 - cycle.daylight)
	if _sun:
		_sun.light_color = v.sun_color
		_sun.light_energy = v.sun_energy
		_sun.shadow_opacity = v.shadow_strength
	# Grass colours and density for GrassField.
	RenderingServer.global_shader_parameter_set("grass_base", v.grass_base)
	RenderingServer.global_shader_parameter_set("grass_tip", v.grass_tip)
	RenderingServer.global_shader_parameter_set("grass_height", v.grass_height)
	RenderingServer.global_shader_parameter_set("grass_ground_match", v.grass_ground_match)
	grass_density = v.grass_density


func _build_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.position = Vector2(-400, 90)
	_label.size = Vector2(800, 50)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 6)
	_label.modulate.a = 0.0
	layer.add_child(_label)


func _show_name(region_name: String) -> void:
	if region_name.is_empty() or _label == null:
		return
	_label.text = region_name
	if _label_tween:
		_label_tween.kill()
	_label_tween = create_tween()
	_label_tween.tween_property(_label, "modulate:a", 1.0, 0.8)
	_label_tween.tween_interval(2.5)
	_label_tween.tween_property(_label, "modulate:a", 0.0, 1.5)



# --- Ambience -----------------------------------------------------------------

func _build_audio() -> void:
	for i in 2:
		var bed := AudioStreamPlayer.new()
		bed.bus = &"Ambience"
		bed.volume_db = -80.0
		add_child(bed)
		_beds.append(bed)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = &"Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	_wind = AudioStreamPlayer.new()
	_wind.bus = &"Ambience"
	_wind.stream = AmbientLoops.looped(wind_loop)
	_wind.volume_db = -80.0
	add_child(_wind)
	if _wind.stream:
		_wind.play()


## Fades the old loop out and the region's one in (if they differ): its night loop
## after dark. Also the region's music.
func _change_ambience(region: RegionAtmosphere, fade: float) -> void:
	var night := _is_night()
	var loop := region.ambient_loop_night if night and region.ambient_loop_night else region.ambient_loop
	_ambience_night = night
	_crossfade(_beds, loop, region.ambient_volume_db, fade, true)
	var tune := region.music_night if night and region.music_night else region.music
	_crossfade(_music, tune, region.music_volume_db, maxf(fade, music_fade), false)


func _is_night() -> bool:
	var cycle := get_tree().get_first_node_in_group("world_cycle") as WorldCycle if is_inside_tree() else null
	return cycle != null and cycle.daylight < 0.35


## Two players crossfading: the playing one fades out, the other fades `stream` in.
func _crossfade(pair: Array[AudioStreamPlayer], stream: AudioStream, volume_db: float, fade: float, random_start: bool) -> void:
	if pair.is_empty():
		return
	var index := 0 if pair[0].playing and pair[0].volume_db > -59.0 else 1
	var old := pair[index] if pair[index].playing else pair[1 - index]
	var wanted := AmbientLoops.looped(stream) if stream else null
	if old.playing and wanted and old.stream == wanted:
		create_tween().tween_property(old, "volume_db", volume_db, fade)
		return
	if old.playing:
		var out := create_tween()
		out.tween_property(old, "volume_db", -60.0, fade)
		out.tween_callback(old.stop)
	if wanted == null:
		return
	var player := pair[1] if old == pair[0] else pair[0]
	player.stream = wanted
	player.volume_db = -60.0
	# Ambience starts somewhere random so it doesn't always begin the same way.
	player.play(randf() * maxf(wanted.get_length() - 1.0, 0.0) if random_start else 0.0)
	create_tween().tween_property(player, "volume_db", volume_db, fade)


func _update_wind(delta: float) -> void:
	if _wind == null or _target == null:
		return
	var height := clampf(_target.global_position.y / windy_height, 0.0, 1.0)
	var goal := current.wind_volume_db + altitude_wind_db * height
	var cycle := get_tree().get_first_node_in_group("world_cycle") as WorldCycle
	if cycle:
		goal += 9.0 * (cycle.wind - 1.0)
	_wind.volume_db = lerpf(_wind.volume_db, goal, 1.0 - exp(-delta * 1.5))


## Ambient occlusion (Settings → Graphics): contact shadows where things meet (grass
## roots, rocks on the ground, corners). Strength in data/world.json "ambient_occlusion"
## (Database → World). Forward+ only (the Compatibility renderer has none).
func _apply_ssao() -> void:
	if _env == null:
		return
	_world_time = DataFiles.modified_time(DataFiles.WORLD)
	var world = DataFiles.read(DataFiles.WORLD)
	var ao: Dictionary = world.get("ambient_occlusion", {}) if world is Dictionary else {}
	_env.ssao_enabled = GameSettings.ssao
	_env.ssao_radius = float(ao.get("radius", 2.0))
	_env.ssao_intensity = float(ao.get("intensity", 3.0))
	_env.ssao_power = float(ao.get("power", 1.6))
	_env.ssao_detail = float(ao.get("detail", 0.6))
	_env.ssao_horizon = float(ao.get("horizon", 0.06))
	# Share of the darkening that also applies in direct sunlight (otherwise only shade gets it).
	_env.ssao_light_affect = float(ao.get("light_affect", 0.45))
	# Godot only lets ssao_light_affect reach materials through this ("AO channel affect"):
	# at 0 the sunlit sides of rocks and trees never darken whatever light_affect says.
	_env.ssao_ao_channel_affect = 1.0
	# The terrain is mostly sunlit: its own share (the shared chunk material).
	var terrain := load("res://assets/materials/terrain/terrain.tres") as ShaderMaterial
	if terrain:
		terrain.set_shader_parameter("ao_light_affect", float(ao.get("terrain_light_affect", 0.85)))
