@tool
class_name WorldCycle
extends Node
## Time of day and wind (one per world). Moves the sun across the sky from east to west,
## brings out the moon and stars at night, and tints the region's sky, fog and light for
## dawn, day, dusk and night (AtmosphereManager asks it via apply_time()). Wind strength
## wanders between calm and gusty and drives tree and grass sway, the wind sound and the
## clouds. Settings come from data/world.json (Database → World).
## In the editor, set Preview Hour to see any time of day.

const WORLD_FILE := "res://data/world.json"

@export var sun_path: NodePath
## Editor only: which hour to show (the game starts at the World data's start hour).
@export_range(0.0, 24.0, 0.25) var preview_hour := 10.0:
	set(value):
		preview_hour = value
		if Engine.is_editor_hint():
			hour = value

## Current time, 0–24.
var hour := 10.0
var day := 1
## 0 calm ... 1 normal ... 2 very windy.
var wind := 1.0
## 1 at full day, 0 at night; and how much of a sunrise/sunset glow there is (0–1).
var daylight := 1.0
var twilight := 0.0
var sun_direction := Vector3.UP
var moon_direction := Vector3.DOWN

# From world.json.
var day_length_minutes := 24.0
var start_hour := 9.0
var sun_height := 65.0
var wind_min := 0.4
var wind_max := 1.5
var gust_seconds := 25.0
var night_brightness := 0.3

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
## How fast clouds drift (sky units per second at wind 1).
@export var cloud_speed := 0.01
var _cloud_offset := Vector2.ZERO
var _wind_time := 0.0
var _file_time := -1
var _file_check := 0.0

const NIGHT_SKY := Color(0.02, 0.035, 0.09)
const NIGHT_HORIZON := Color(0.07, 0.09, 0.18)
const NIGHT_FOG := Color(0.06, 0.08, 0.14)
const DUSK_HORIZON := Color(1.0, 0.52, 0.32)
const DUSK_SUN := Color(1.0, 0.55, 0.3)
const MOON_COLOR := Color(0.62, 0.72, 1.0)


func _ready() -> void:
	add_to_group("world_cycle")
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.light_color = MOON_COLOR
	_moon.shadow_enabled = true
	_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_moon)
	_load()
	hour = preview_hour if Engine.is_editor_hint() else start_hour
	_update(0.0)


func _process(delta: float) -> void:
	_file_check += delta
	if _file_check > 1.0:
		_file_check = 0.0
		if DataFiles.modified_time(WORLD_FILE) != _file_time:
			_load()
	if not Engine.is_editor_hint():
		hour += delta * 24.0 / maxf(day_length_minutes * 60.0, 1.0)
		if hour >= 24.0:
			hour -= 24.0
			day += 1
	_update(delta)


func _load() -> void:
	_file_time = DataFiles.modified_time(WORLD_FILE)
	var d = DataFiles.read(WORLD_FILE)
	if not d is Dictionary:
		return
	day_length_minutes = float(d.get("day_length_minutes", day_length_minutes))
	start_hour = float(d.get("start_hour", start_hour))
	sun_height = float(d.get("sun_height", sun_height))
	night_brightness = float(d.get("night_brightness", night_brightness))
	var w: Dictionary = d.get("wind", {})
	wind_min = float(w.get("calm", wind_min))
	wind_max = float(w.get("gusty", wind_max))
	gust_seconds = float(w.get("gust_seconds", gust_seconds))


## "Day 3, 14:05"
func clock_text() -> String:
	var h := int(hour)
	var m := int((hour - h) * 60.0)
	return "Day %d  %02d:%02d" % [day, h, m]


func _update(delta: float) -> void:
	# Sun: rises in the east (+X) at 6, highest in the south (+Z) at noon, sets in the west at 18.
	var angle := (hour - 6.0) / 12.0 * PI
	var tilt := deg_to_rad(sun_height)
	sun_direction = Vector3(cos(angle), sin(angle) * sin(tilt), sin(angle) * cos(tilt)).normalized()
	moon_direction = -sun_direction
	var s := sun_direction.y
	# Daylight lingers a little after sunset (dusk) and arrives before sunrise (dawn).
	daylight = smoothstep(-0.25, 0.12, s)
	twilight = clampf(1.0 - absf(s + 0.03) / 0.3, 0.0, 1.0)
	if _sun:
		_aim(_sun, sun_direction)
		_sun.visible = s > -0.05
	_aim(_moon, moon_direction if moon_direction.y > 0.0 else Vector3(moon_direction.x, 0.05, moon_direction.z).normalized())
	var night := 1.0 - daylight
	_moon.light_energy = 0.35 * night * smoothstep(-0.05, 0.15, moon_direction.y)
	_moon.visible = _moon.light_energy > 0.01

	# Wind: slow smooth wandering between calm and gusty, plus quick gusts.
	if not Engine.is_editor_hint():
		_wind_time += delta
	var slow := 0.5 + 0.5 * sin(_wind_time / gust_seconds * TAU * 0.37) * cos(_wind_time / gust_seconds * TAU * 0.13 + 1.3)
	var quick := 0.12 * sin(_wind_time * 0.9) * sin(_wind_time * 0.37 + 2.0)
	wind = clampf(lerpf(wind_min, wind_max, slow) + quick, 0.0, 2.5)
	RenderingServer.global_shader_parameter_set("wind_strength", wind)
	# Clouds drift one way; wind only changes how fast.
	if not Engine.is_editor_hint():
		_cloud_offset += Vector2(1.0, 0.4) * cloud_speed * maxf(wind, 0.2) * delta
		_cloud_offset = _cloud_offset.posmod(1000.0)
	RenderingServer.global_shader_parameter_set("cloud_offset", _cloud_offset)


func _aim(light: DirectionalLight3D, towards: Vector3) -> void:
	# A directional light shines along its -Z: point -Z away from the sun/moon.
	var up := Vector3.UP if absf(towards.y) < 0.98 else Vector3.FORWARD
	light.global_transform = Transform3D(Basis.looking_at(-towards, up), Vector3.ZERO)


## Tints the region's look for the time of day. AtmosphereManager calls this with its
## blended values each frame and applies the result.
func apply_time(v: Dictionary) -> Dictionary:
	var out := v.duplicate()
	var night := 1.0 - daylight
	var glow := twilight * 0.85
	# Region night colours (RegionAtmosphere night_*), else the defaults.
	var night_sky: Color = v.get("night_sky_top", NIGHT_SKY)
	var night_horizon: Color = v.get("night_sky_horizon", NIGHT_HORIZON)
	var night_fog: Color = v.get("night_fog", NIGHT_FOG)
	out.sky_top = (v.sky_top as Color).lerp(night_sky, night)
	var horizon := (v.sky_horizon as Color).lerp(DUSK_HORIZON, glow * 0.7)
	out.sky_horizon = horizon.lerp(night_horizon, night * (1.0 - glow * 0.5))
	out.fog_color = (v.fog_color as Color).lerp(DUSK_HORIZON.darkened(0.15), glow * 0.5).lerp(night_fog, night * (1.0 - glow * 0.4))
	out.cloud_color = (v.cloud_color as Color).lerp(Color(1.0, 0.65, 0.5), glow * 0.6).lerp(Color(0.16, 0.18, 0.26), night)
	out.cloud_shade = (v.cloud_shade as Color).lerp(Color(0.55, 0.35, 0.4), glow * 0.5).lerp(Color(0.07, 0.08, 0.13), night)
	out.sun_color = (v.sun_color as Color).lerp(DUSK_SUN, glow)
	out.sun_energy = float(v.sun_energy) * smoothstep(-0.03, 0.25, sun_direction.y)
	out.ambient_energy = float(v.ambient_energy) * lerpf(night_brightness, 1.0, daylight)
	if v.has("shadow_color"):
		out.shadow_color = (v.shadow_color as Color).lerp(Color(0.12, 0.15, 0.26), night * 0.6)
	out.god_rays = float(v.get("god_rays", 0.0)) * (0.4 + 0.6 * daylight) * (1.0 + glow)
	return out
