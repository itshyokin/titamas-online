class_name Weather
extends Node3D
## Weather (made by AtmosphereManager): each region lists the weather it can have with
## weights (Database → Regions → Weather); a spell of weather lasts weather_minutes_min..max
## and then another is picked. Types are data/weather.json (Database → Weather): how they
## change clouds, sun, ambient light, fog and colour, plus rain (streaks around the camera,
## wet ground through the global `wetness`), lightning with thunder, a looping sound and
## how strong cloud shadows are. Changes blend over transition_seconds.
## Events set it with the command "weather" {type, minutes} (Weather.force).
## Cloud shadows: a 3x3 grid of decals (dark patches from a seamless noise texture) that
## drifts with the sky's clouds (global cloud_offset) and follows the camera.

const FILE := "res://data/weather.json"
const FIELDS := ["cloud_coverage", "cloud_darken", "sun_scale", "ambient_scale", "fog_add", "saturation_scale",
	"rain", "wetness", "wind_add", "cloud_shadows"]

var data := {}
var type_id := "clear"
## Blended values in use now (FIELDS).
var values := {}
var _goal := {}
var _left := 0.0
var _region: RegionAtmosphere
var _forced := false
var _file_time := -1
var _sound: AudioStreamPlayer
var _sound_path := ""
var _rain: GPUParticles3D
var _lightning := 0.0
var _flash := 0.0
var _shadows: Array[Decal] = []
var _shadow_size := 96.0
var _thunder: Array[AudioStream] = []


func _ready() -> void:
	_load()
	values = _type_values("clear")
	_goal = values.duplicate()
	_sound = AudioStreamPlayer.new()
	_sound.bus = &"Ambience"
	_sound.volume_db = -60.0
	add_child(_sound)
	_build_rain()
	_build_shadows()


func _load() -> void:
	_file_time = DataFiles.modified_time(FILE)
	var d = DataFiles.read(FILE)
	data = d if d is Dictionary else {}
	_thunder.clear()
	for p in data.get("thunder", []):
		if ResourceLoader.exists(String(p)):
			_thunder.append(load(String(p)))


func type_data(id: String) -> Dictionary:
	for t: Dictionary in data.get("types", []):
		if String(t.get("id", "")) == id:
			return t
	return {}


func _type_values(id: String) -> Dictionary:
	var t := type_data(id)
	var out := {}
	for f: String in FIELDS:
		out[f] = float(t.get(f, 1.0 if f.ends_with("_scale") else 0.0))
	return out


## The region changed (or the weather ran out): pick from its list.
func set_region(region: RegionAtmosphere) -> void:
	if region == _region:
		return
	_region = region
	if not _forced:
		_pick()


## An event sets the weather for `minutes` (0 = until the next region / pick).
func force(id: String, minutes := 0.0) -> void:
	if type_data(id).is_empty():
		push_warning("Weather: no type '%s' in %s" % [id, FILE])
		return
	_forced = minutes > 0.0
	_start(id, minutes * 60.0 if minutes > 0.0 else _spell_seconds())


func _spell_seconds() -> float:
	if _region == null:
		return 600.0
	return randf_range(_region.weather_minutes_min, maxf(_region.weather_minutes_max, _region.weather_minutes_min)) * 60.0


func _pick() -> void:
	var options: Array = _region.weather if _region else []
	var total := 0.0
	for o in options:
		total += maxf(float((o as Dictionary).get("weight", 1.0)), 0.0)
	var id := "clear"
	if total > 0.0:
		var r := randf() * total
		for o in options:
			r -= maxf(float((o as Dictionary).get("weight", 1.0)), 0.0)
			if r <= 0.0:
				id = String((o as Dictionary).get("type", "clear"))
				break
	_start(id, _spell_seconds())


func _start(id: String, seconds: float) -> void:
	type_id = id
	_left = seconds
	_goal = _type_values(id)
	var t := type_data(id)
	_lightning = float(t.get("lightning_every", 0.0)) * randf_range(0.5, 1.2)
	var path := String(t.get("sound", ""))
	if path != _sound_path:
		_sound_path = path
		_crossfade(load(path) if path != "" and ResourceLoader.exists(path) else null, float(t.get("sound_db", -8.0)))


func _crossfade(stream: AudioStream, db: float) -> void:
	var tween := create_tween()
	tween.tween_property(_sound, "volume_db", -60.0, 3.0)
	tween.tween_callback(func() -> void:
		if stream == null:
			_sound.stop()
			return
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		_sound.stream = stream
		_sound.play())
	if stream:
		tween.tween_property(_sound, "volume_db", db, 4.0)


func _process(delta: float) -> void:
	if DataFiles.modified_time(FILE) != _file_time:
		_load()
		_goal = _type_values(type_id)
	_left -= delta
	if _left <= 0.0:
		_forced = false
		_pick()
	var k := 1.0 - exp(-delta * 3.0 / maxf(float(data.get("transition_seconds", 25.0)), 0.1))
	for f: String in FIELDS:
		values[f] = lerpf(float(values.get(f, 0.0)), float(_goal.get(f, 0.0)), k)
	RenderingServer.global_shader_parameter_set("wetness", clampf(float(values.wetness), 0.0, 1.0))
	_update_rain()
	_update_lightning(delta)
	_update_shadows()


## Applies the weather to a region's look (after the day/night cycle).
func modify(v: Dictionary) -> Dictionary:
	var out := v.duplicate()
	out.cloud_coverage = clampf(float(v.cloud_coverage) + float(values.cloud_coverage), 0.0, 1.0)
	out.cloud_darken = clampf(float(values.cloud_darken), 0.0, 1.0)
	out.sun_energy = float(v.sun_energy) * float(values.sun_scale) + _flash * 4.0
	out.ambient_energy = float(v.ambient_energy) * float(values.ambient_scale) + _flash * 1.5
	out.fog_density = float(v.fog_density) + float(values.fog_add)
	out.saturation = float(v.saturation) * float(values.saturation_scale)
	out.god_rays = float(v.get("god_rays", 0.0)) * float(values.sun_scale)
	var grey := clampf(float(values.cloud_darken) * 0.5, 0.0, 1.0)
	out.sky_top = (v.sky_top as Color).lerp((v.cloud_shade as Color).darkened(0.35), grey)
	out.sky_horizon = (v.sky_horizon as Color).lerp((v.cloud_shade as Color).darkened(0.2), grey)
	return out


# --- Rain -----------------------------------------------------------------------------

func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 3000
	_rain.lifetime = 1.1
	_rain.visibility_aabb = AABB(Vector3(-20, -25, -20), Vector3(40, 40, 40))
	_rain.local_coords = false
	_rain.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 1, 16)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 20.0
	pm.gravity = Vector3(0, -9.8, 0)
	_rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.015, 0.45)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 0.82, 0.95, 0.35)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = mat
	_rain.draw_pass_1 = q
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)


func _update_rain() -> void:
	var amount := clampf(float(values.rain), 0.0, 1.0)
	var on: bool = amount > 0.03 and GameSettings.get("weather_effects") != false
	_rain.emitting = on
	if not on:
		return
	_rain.amount_ratio = amount
	var cam := get_viewport().get_camera_3d()
	if cam:
		_rain.global_position = cam.global_position + Vector3.UP * 12.0 - cam.global_basis.z * 6.0
	var pm := _rain.process_material as ParticleProcessMaterial
	var wind := float(values.wind_add)
	pm.direction = Vector3(wind * 0.25, -1, wind * 0.1).normalized()


# --- Lightning ------------------------------------------------------------------------

func _update_lightning(delta: float) -> void:
	_flash = maxf(_flash - delta * 6.0, 0.0)
	var every := float(type_data(type_id).get("lightning_every", 0.0))
	if every <= 0.0 or float(values.rain) < 0.5:
		return
	_lightning -= delta
	if _lightning > 0.0:
		return
	_lightning = every * randf_range(0.5, 1.5)
	_flash = 1.0
	# A second flicker, then thunder after the distance delay.
	get_tree().create_timer(0.12).timeout.connect(func() -> void: _flash = 0.7)
	if not _thunder.is_empty():
		var p := AudioStreamPlayer.new()
		p.stream = _thunder.pick_random()
		p.bus = &"Ambience"
		p.volume_db = randf_range(-6.0, 0.0)
		add_child(p)
		p.finished.connect(p.queue_free)
		get_tree().create_timer(randf_range(0.4, 2.5)).timeout.connect(p.play)


# --- Cloud shadows ---------------------------------------------------------------------

func _build_shadows() -> void:
	var cfg: Dictionary = data.get("cloud_shadows", {})
	if not bool(cfg.get("enabled", true)):
		return
	_shadow_size = float(cfg.get("size", 96.0))
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	var ramp := Gradient.new()
	var shade := Color.html(String(cfg.get("color", "#1d2738")))
	ramp.set_color(0, Color(shade, 0.0))
	ramp.set_offset(0, 0.45)
	ramp.set_color(1, Color(shade, 1.0))
	ramp.set_offset(1, 0.7)
	tex.color_ramp = ramp
	for i in 9:
		var d := Decal.new()
		d.texture_albedo = tex
		d.size = Vector3(_shadow_size, 400.0, _shadow_size)
		d.albedo_mix = 1.0
		d.upper_fade = 0.0
		d.lower_fade = 0.0
		d.normal_fade = 0.0
		d.distance_fade_enabled = false
		d.cull_mask = 0xFFFFF
		d.top_level = true
		add_child(d)
		_shadows.append(d)


func _update_shadows() -> void:
	if _shadows.is_empty():
		return
	var cfg: Dictionary = data.get("cloud_shadows", {})
	var cycle := get_tree().get_first_node_in_group("world_cycle") as WorldCycle
	var day := cycle.daylight if cycle else 1.0
	var strength := float(cfg.get("strength", 0.35)) * float(values.cloud_shadows) * smoothstep(0.2, 0.6, day)
	var cam := get_viewport().get_camera_3d()
	var visible_now: bool = strength > 0.01 and cam != null and GameSettings.get("cloud_shadows") != false
	for d in _shadows:
		d.visible = visible_now
	if not visible_now:
		return
	# The pattern drifts with the sky's clouds; the 3x3 tiles follow the camera.
	var offset: Vector2 = cycle.get("_cloud_offset") if cycle else Vector2(Time.get_ticks_msec() / 1000.0 * 0.004, 0.0)
	var drift := offset * _shadow_size * 1.5
	var origin := Vector2(cam.global_position.x, cam.global_position.z) - drift
	var snapped := (origin / _shadow_size).floor() * _shadow_size + drift
	var i := 0
	for x in range(-1, 2):
		for z in range(-1, 2):
			var d := _shadows[i]
			d.global_position = Vector3(snapped.x + (x + 0.5) * _shadow_size, cam.global_position.y, snapped.y + (z + 0.5) * _shadow_size)
			d.modulate = Color(1, 1, 1, strength)
			i += 1
