class_name Weather
extends Node3D
## Weather (made by AtmosphereManager): each region lists the weather it can have with
## weights (Database → Regions → Weather); a spell of weather lasts weather_minutes_min..max
## and then another is picked. Types are data/weather.json (Database → Weather): how they
## change clouds, sun, ambient light, fog and colour, plus rain (streaks around the camera,
## wet ground through the global `wetness`), snow (flakes around the camera; `frost` = snow
## lying in patches and frosted grass through the global `snow_cover`, not under roofs or
## trees), lightning with thunder, a looping sound and
## how strong cloud shadows are. Changes blend over transition_seconds.
## Events set it with the command "weather" {type, minutes} (Weather.force).
## Cloud shadows: a 3x3 grid of decals (dark patches from a seamless noise texture) that
## drifts with the sky's clouds (global cloud_offset) and follows the camera.
## Under cover (`shelter`, 0–1): when the camera is inside an indoors SafeArea box or has a
## roof over it (a ray straight up against the world), the weather's sounds are quieter
## and muffled. What is drawn goes by the cover map (`cover`, RainCover): streaks only
## above the highest solid thing at each spot, so from indoors the rain still falls
## outside the door; splashes lie on that surface; the ground is only wet under open sky.
## With the cover map switched off, rain and splashes simply stop under cover.
## Settings: weather.json "indoors" (Database → Weather Settings → Indoors).

const FILE := "res://data/weather.json"
const BUS := &"Weather"
const FIELDS := ["cloud_coverage", "cloud_darken", "sun_scale", "ambient_scale", "fog_add", "saturation_scale",
	"rain", "wetness", "snow", "frost", "wind_add", "cloud_shadows"]

var data := {}
var type_id := "clear"
## Blended values in use now (FIELDS).
var values := {}
var _goal := {}
var _left := 0.0
var _region: RegionAtmosphere
var _forced := false
var _file_time := -1
var _file_check := 0.0
var _sound: AudioStreamPlayer
var _sound_path := ""
var _rain: GPUParticles3D
var _splash: GPUParticles3D
var _splash_tex: Texture2D
var _lightning := 0.0
var _flash := 0.0
var _shadows: Array[Decal] = []
var _shadow_size := 96.0
var _thunder: Array[AudioStream] = []
## How far under cover the camera is (0 = open sky, 1 = indoors), blended over time.
var shelter := 0.0
## The same for the player's own spot (rain splashes at their feet).
var player_shelter := 0.0
var _cam_covered := false
var _player_covered := false
var _shelter_check := 0.0
var _bus := -1
## The cover map (see RainCover).
var cover: RainCover
var _rain_mat: ShaderMaterial
var _snow: GPUParticles3D
var _snow_mat: ShaderMaterial
var _splash_mat: ShaderMaterial
var _lowpass: AudioEffectLowPassFilter


func _ready() -> void:
	_load()
	values = _type_values("clear")
	_goal = values.duplicate()
	_build_bus()
	_sound = AudioStreamPlayer.new()
	_sound.bus = BUS if _bus >= 0 else &"Ambience"
	_sound.volume_db = -60.0
	add_child(_sound)
	cover = RainCover.new()
	cover.name = "RainCover"
	add_child(cover)
	_build_rain()
	_build_snow()
	_build_splashes()
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
	_file_check -= delta
	if _file_check <= 0.0:
		_file_check = 1.0  # the Database page saves into it: look once a second
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
	RenderingServer.global_shader_parameter_set("snow_cover", clampf(float(values.frost), 0.0, 1.0))
	_update_shelter(delta)
	_update_cover()
	_update_rain()
	_update_snow()
	_update_splashes()
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
	_rain_mat = ShaderMaterial.new()
	_rain_mat.shader = preload("res://assets/materials/rain_streak.gdshader")
	_rain_mat.set_shader_parameter("tint", Color(0.75, 0.82, 0.95, 0.35))
	q.material = _rain_mat
	_rain.draw_pass_1 = q
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)


func _update_rain() -> void:
	var amount := clampf(float(values.rain), 0.0, 1.0)
	# With the cover map the streaks hide themselves under roofs; without it, rain stops under cover.
	var on: bool = amount > 0.03 and GameSettings.get("weather_effects") != false and (cover.active or shelter < 0.5)
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
	_rain_mat.set_shader_parameter("streak_up", -pm.direction)


# --- Snow -----------------------------------------------------------------------------

## Flakes drifting down around the camera: slow, wandering, leaning with the wind. They
## use the rain's shader as round dots, so none are drawn under roofs.
func _build_snow() -> void:
	_snow = GPUParticles3D.new()
	_snow.amount = 2600
	_snow.lifetime = 7.0
	_snow.preprocess = 3.0
	_snow.visibility_aabb = AABB(Vector3(-24, -24, -24), Vector3(48, 40, 48))
	_snow.local_coords = false
	_snow.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 5, 16)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 22.0
	pm.initial_velocity_min = 1.3
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.14
	_snow.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	_snow_mat = ShaderMaterial.new()
	_snow_mat.shader = preload("res://assets/materials/rain_streak.gdshader")
	_snow_mat.set_shader_parameter("tint", Color(0.96, 0.98, 1.0, 0.9))
	_snow_mat.set_shader_parameter("round_dot", 1.0)
	q.material = _snow_mat
	_snow.draw_pass_1 = q
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_snow)


func _update_snow() -> void:
	if _snow == null:
		return
	var amount := clampf(float(values.snow), 0.0, 1.0)
	var on: bool = amount > 0.03 and GameSettings.get("weather_effects") != false and (cover.active or shelter < 0.5)
	_snow.emitting = on
	if not on:
		return
	_snow.amount_ratio = amount
	var cam := get_viewport().get_camera_3d()
	if cam:
		_snow.global_position = cam.global_position + Vector3.UP * 7.0 - cam.global_basis.z * 5.0
	var pm := _snow.process_material as ParticleProcessMaterial
	var wind := float(values.wind_add)
	# Blizzards drive the flakes sideways and faster.
	pm.direction = Vector3(wind * 1.4, -1, wind * 0.6).normalized()
	pm.initial_velocity_min = 1.3 + wind * 3.0
	pm.initial_velocity_max = 2.4 + wind * 5.0


## Rings of spray where the rain lands, on the ground and on water around the player.
func _build_splashes() -> void:
	_splash = GPUParticles3D.new()
	_splash.amount = 260
	_splash.lifetime = 0.45
	_splash.visibility_aabb = AABB(Vector3(-14, -2, -14), Vector3(28, 6, 28))
	_splash.local_coords = false
	_splash.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(11, 0.05, 11)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.35
	pm.scale_max = 1.0
	var curve := Curve.new()  # the ring spreads out as it fades
	curve.add_point(Vector2(0.0, 0.25))
	curve.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.55))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	_splash.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	q.orientation = PlaneMesh.FACE_Y  # lies flat on the ground
	_splash_mat = ShaderMaterial.new()
	_splash_mat.shader = preload("res://assets/materials/rain_splash.gdshader")
	_splash_mat.set_shader_parameter("ring", _ring_texture())
	q.material = _splash_mat
	_splash.draw_pass_1 = q
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_splash)


func _update_splashes() -> void:
	if _splash == null:
		return
	var amount := clampf(float(values.rain), 0.0, 1.0)
	var on: bool = amount > 0.08 and GameSettings.get("weather_effects") != false \
		and (cover.active or (shelter < 0.5 and player_shelter < 0.5))
	_splash_mat.set_shader_parameter("on_cover", 1.0 if cover.active else 0.0)
	_splash.emitting = on
	if not on:
		return
	_splash.amount_ratio = amount
	# Sits on whatever the player is standing in (ground, shallows, the sea surface).
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	if player == null or cam == null:
		return
	_splash.global_position = Vector3(cam.global_position.x, player.global_position.y + 0.06, cam.global_position.z) \
		- Vector3(cam.global_basis.z.x, 0.0, cam.global_basis.z.z).normalized() * 4.0


## A soft ring, drawn in code.
func _ring_texture() -> Texture2D:
	if _splash_tex:
		return _splash_tex
	var n := 10  # a few big pixels
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var d := p.length()
			var a := clampf(1.0 - absf(d - 0.72) / 0.26, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, PixelArt.step_alpha(a)))
	_splash_tex = ImageTexture.create_from_image(img)
	return _splash_tex


# --- Under cover -----------------------------------------------------------------------

## The weather's own bus (feeds Ambience, so that volume slider still rules it), with a
## low-pass filter that closes as the camera goes under cover.
func _build_bus() -> void:
	_bus = AudioServer.get_bus_index(BUS)
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, BUS)
		AudioServer.set_bus_send(_bus, &"Ambience")
	for i in AudioServer.get_bus_effect_count(_bus):
		if AudioServer.get_bus_effect(_bus, i) is AudioEffectLowPassFilter:
			_lowpass = AudioServer.get_bus_effect(_bus, i) as AudioEffectLowPassFilter
	if _lowpass == null:
		_lowpass = AudioEffectLowPassFilter.new()
		AudioServer.add_bus_effect(_bus, _lowpass)
	_apply_shelter_sound()


func _exit_tree() -> void:
	# Leave the bus open for whatever plays next (another level's weather).
	shelter = 0.0
	_apply_shelter_sound()


## The cover map is kept up while it rains or the ground is wet.
func _update_cover() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var needed: bool = float(values.rain) > 0.03 or float(values.wetness) > 0.02 or float(values.snow) > 0.03 or float(values.frost) > 0.01
	cover.update(cam.global_position, get_world_3d(), needed, data.get("indoors", {}))


func _update_shelter(delta: float) -> void:
	var cfg: Dictionary = data.get("indoors", {})
	_shelter_check -= delta
	if _shelter_check <= 0.0:
		_shelter_check = 0.15
		var cam := get_viewport().get_camera_3d()
		var player := get_tree().get_first_node_in_group("player") as Node3D
		_cam_covered = cam != null and covered_at(cam.global_position, cfg)
		_player_covered = player != null and covered_at(player.global_position + Vector3.UP * 1.9, cfg)
	var step := delta / maxf(float(cfg.get("fade_seconds", 0.6)), 0.01)
	shelter = move_toward(shelter, 1.0 if _cam_covered else 0.0, step)
	player_shelter = move_toward(player_shelter, 1.0 if _player_covered else 0.0, step)
	_apply_shelter_sound()


## `point` is under cover: inside an indoors SafeArea box, or (roof check) something of
## the world is straight above it within roof_height metres.
func covered_at(point: Vector3, cfg: Dictionary = {}) -> bool:
	if cfg.is_empty():
		cfg = data.get("indoors", {})
	if SafeArea.indoors_at(point):
		return true
	if not bool(cfg.get("roof_check", true)) or not is_inside_tree():
		return false
	var q := PhysicsRayQueryParameters3D.create(point, point + Vector3.UP * float(cfg.get("roof_height", 30.0)), 1)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _apply_shelter_sound() -> void:
	if _bus < 0 or _bus >= AudioServer.bus_count or _lowpass == null:
		return
	var cfg: Dictionary = data.get("indoors", {})
	var k := smoothstep(0.0, 1.0, shelter)
	AudioServer.set_bus_volume_db(_bus, float(cfg.get("muffle_db", -9.0)) * k)
	var index := -1
	for i in AudioServer.get_bus_effect_count(_bus):
		if AudioServer.get_bus_effect(_bus, i) == _lowpass:
			index = i
	if index < 0:
		return
	AudioServer.set_bus_effect_enabled(_bus, index, k > 0.01)
	# The filter closes from wide open down to the muffled cutoff (heard as pitch, so in octaves).
	_lowpass.cutoff_hz = 16000.0 * pow(clampf(float(cfg.get("muffle_cutoff", 1200.0)), 100.0, 16000.0) / 16000.0, k)


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
		p.bus = BUS if _bus >= 0 else &"Ambience"
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
