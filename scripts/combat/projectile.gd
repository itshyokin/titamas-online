class_name Projectile
extends Node3D
## A spell bolt that homes in on its target, then bursts and deals damage.

const BURST_SOUND := preload("res://assets/audio/combat/fireball_hit.ogg")

var source: Node3D
var target: Node3D
var ability: Ability

var _last_aim := Vector3.ZERO
var _light: OmniLight3D
var _life := 0.0


static func launch(from: Vector3, by: Node3D, at: Node3D, what: Ability) -> Projectile:
	var p := Projectile.new()
	p.source = by
	p.target = at
	p.ability = what
	Combat.world_root(by).add_child(p)
	p.global_position = from
	return p


func _ready() -> void:
	var color := ability.projectile_color
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.lightened(0.5)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	sphere.material = mat
	core.mesh = sphere
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 2.0
	_light.omni_range = 4.0
	add_child(_light)
	add_child(Effects.trail(color))
	_last_aim = Combat.aim_point(target) if is_instance_valid(target) else global_position


func _physics_process(delta: float) -> void:
	_life += delta
	if is_instance_valid(target) and Combat.is_alive(target):
		_last_aim = Combat.aim_point(target)
	var to := _last_aim - global_position
	var step := ability.projectile_speed * delta
	if to.length() <= step + 0.2 or _life > 6.0:
		_burst()
		return
	global_position += to.normalized() * step


func _burst() -> void:
	if is_instance_valid(target) and Combat.is_alive(target) and is_instance_valid(source):
		Combat.hit(source, target, ability.power, ability.staggers)
	Effects.burst(Combat.world_root(self), global_position, ability.projectile_color)
	Combat.play_sound(self, BURST_SOUND, -3.0)
	queue_free()
