@tool
class_name AtmosphereManager
extends Node
## Blends fog, sky colours and sunlight to match the region the player is in, and
## shows the region's name when entering it (WoW-style zone text).

@export var regions: Array[RegionAtmosphere] = []
## Used outside every region (open sea, unassigned land).
@export var default_atmosphere: RegionAtmosphere
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

var _env: Environment
var _sky: ShaderMaterial
var _sun: DirectionalLight3D
var _target: Node3D
var _check_timer := 0.0
var _values := {}
var _label: Label
var _label_tween: Tween
var _beds: Array[AudioStreamPlayer] = []  # two players, crossfaded between regions
var _bed_index := 0
var _wind: AudioStreamPlayer

# Property name -> how it's applied.
const FIELDS := [
	"fog_color", "fog_density", "fog_sky_affect", "sky_top", "sky_horizon", "sky_ground",
	"cloud_color", "cloud_shade", "cloud_coverage", "sun_color", "sun_energy", "ambient_energy",
	"shadow_strength", "saturation", "contrast", "brightness",
]


func _ready() -> void:
	var world_env := get_node_or_null(environment_path) as WorldEnvironment
	if world_env:
		_env = world_env.environment
		if _env.sky:
			_sky = _env.sky.sky_material as ShaderMaterial
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_target = get_node_or_null(target_path) as Node3D
	if Engine.is_editor_hint():
		return
	_build_label()
	_build_audio()
	current = _region_at_target()
	if current:
		for f in FIELDS:
			_values[f] = current.get(f)
		_apply()
		_change_ambience(current, 0.5)


func _process(delta: float) -> void:
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
	if current == null:
		return
	_update_wind(delta)
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
	if changed:
		_apply()


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
	if _env:
		_env.fog_light_color = _values.fog_color
		_env.fog_density = _values.fog_density
		_env.fog_sky_affect = _values.fog_sky_affect
		_env.ambient_light_energy = _values.ambient_energy
		_env.adjustment_enabled = true
		_env.adjustment_saturation = _values.saturation
		_env.adjustment_contrast = _values.contrast
		_env.adjustment_brightness = _values.brightness
	if _sky:
		_sky.set_shader_parameter("top_color", _values.sky_top)
		_sky.set_shader_parameter("horizon_color", _values.sky_horizon)
		_sky.set_shader_parameter("ground_color", _values.sky_ground)
		_sky.set_shader_parameter("cloud_color", _values.cloud_color)
		_sky.set_shader_parameter("cloud_shade", _values.cloud_shade)
		_sky.set_shader_parameter("cloud_coverage", _values.cloud_coverage)
		_sky.set_shader_parameter("sun_color", _values.sun_color)
	if _sun:
		_sun.light_color = _values.sun_color
		_sun.light_energy = _values.sun_energy
		_sun.shadow_opacity = _values.shadow_strength


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
	_wind = AudioStreamPlayer.new()
	_wind.bus = &"Ambience"
	_wind.stream = AmbientLoops.looped(wind_loop)
	_wind.volume_db = -80.0
	add_child(_wind)
	if _wind.stream:
		_wind.play()


## Fades the old region's loop out and the new one in (if they differ).
func _change_ambience(region: RegionAtmosphere, fade: float) -> void:
	var old := _beds[_bed_index]
	if old.playing and old.stream == region.ambient_loop:
		create_tween().tween_property(old, "volume_db", region.ambient_volume_db, fade)
		return
	if old.playing:
		var out := create_tween()
		out.tween_property(old, "volume_db", -60.0, fade)
		out.tween_callback(old.stop)
	if region.ambient_loop == null:
		return
	var stream := AmbientLoops.looped(region.ambient_loop)
	_bed_index = 1 - _bed_index
	var bed := _beds[_bed_index]
	bed.stream = stream
	bed.volume_db = -60.0
	# Start somewhere random so the loop doesn't always begin the same way.
	bed.play(randf() * maxf(stream.get_length() - 1.0, 0.0))
	create_tween().tween_property(bed, "volume_db", region.ambient_volume_db, fade)


func _update_wind(delta: float) -> void:
	if _wind == null or _target == null:
		return
	var height := clampf(_target.global_position.y / windy_height, 0.0, 1.0)
	var goal := current.wind_volume_db + altitude_wind_db * height
	_wind.volume_db = lerpf(_wind.volume_db, goal, 1.0 - exp(-delta * 1.5))
