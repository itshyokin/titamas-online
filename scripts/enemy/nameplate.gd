class_name Nameplate
extends Node3D
## Name, level and health bar floating over a combatant. Faces the camera and only
## shows when the camera is close enough, or when the combatant is hurt or targeted.

@export var show_distance := 30.0
@export var width := 0.9

var stats: Stats
var targeted := false

var _label: Label3D
var _fill: MeshInstance3D
var _back: MeshInstance3D
var _bar_holder: Node3D


static func attach(to: Node3D, height := 2.15) -> Nameplate:
	var plate := Nameplate.new()
	plate.name = "Nameplate"
	plate.position = Vector3.UP * height
	to.add_child(plate)
	return plate


func _ready() -> void:
	stats = Combat.stats_of(get_parent())
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.0035
	_label.font_size = 40
	_label.outline_size = 10
	_label.position = Vector3.UP * 0.16
	_label.no_depth_test = true
	add_child(_label)
	_bar_holder = Node3D.new()
	add_child(_bar_holder)
	_back = _bar(Color(0, 0, 0, 0.6), 0.09, 0)
	_fill = _bar(Color(0.85, 0.15, 0.12), 0.06, 1)
	if stats:
		stats.health_changed.connect(_on_health)
		_on_health(stats.health, stats.max_health)
	_refresh_label()


func _bar(color: Color, height: float, priority: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = priority
	q.material = m
	mi.mesh = q
	mi.scale = Vector3(width, height, 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_holder.add_child(mi)
	return mi


func _refresh_label() -> void:
	if stats == null:
		return
	_label.text = "%s  (%d)" % [stats.display_name, stats.level]
	_label.modulate = Color(1.0, 0.45, 0.4) if stats.team == Stats.Team.ENEMIES else Color(0.5, 0.9, 1.0)


func _on_health(current: float, maximum: float) -> void:
	var k := clampf(current / maxf(maximum, 1.0), 0.0, 1.0)
	_fill.scale.x = width * k
	_fill.position.x = -width * (1.0 - k) * 0.5
	# Allies and other players: green to red as they get hurt. Enemies stay red.
	if stats and stats.team != Stats.Team.ENEMIES:
		((_fill.mesh as QuadMesh).material as StandardMaterial3D).albedo_color = HealthColors.of(k)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or stats == null:
		return
	var dist := cam.global_position.distance_to(global_position)
	var hurt := stats.health < stats.max_health
	visible = not stats.is_dead() and dist > 2.5 and (targeted or dist < show_distance * (1.5 if hurt else 1.0))
	if visible:
		# Face the camera (the bar is two flat quads, so turn the holder, not each quad).
		_bar_holder.global_basis = cam.global_basis
