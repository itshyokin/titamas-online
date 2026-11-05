class_name Projectile
extends Node3D
## A spell bolt or arrow. With a target it homes in (lock-on aiming); without one it flies
## straight and hits the first enemy or wall in its path.

const BOLT_BURST_SOUND := preload("res://assets/audio/combat/fireball_hit.ogg")
const ARROW_HIT_SOUND := preload("res://assets/audio/combat/arrow_hit.ogg")
const MAX_RANGE := 60.0

var source: Node3D
var target: Node3D
var ability: Ability
var power := 10.0
var direction := Vector3.FORWARD

var _last_aim := Vector3.ZERO
var _travelled := 0.0
var _arrow := false


static func launch(from: Vector3, by: Node3D, at: Node3D, what: Ability, hit_power: float, dir := Vector3.ZERO) -> Projectile:
	var p := Projectile.new()
	p.source = by
	p.target = at
	p.ability = what
	p.power = hit_power
	if dir != Vector3.ZERO:
		p.direction = dir.normalized()
	Combat.world_root(by).add_child(p)
	p.global_position = from
	if at:
		p.direction = (Combat.aim_point(at) - from).normalized()
	p._face()
	return p


func _ready() -> void:
	_arrow = ability.projectile_style == Ability.ProjectileStyle.ARROW
	var color := ability.projectile_color
	if _arrow:
		add_child(WeaponModels.arrow())
	else:
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
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 2.0
		light.omni_range = 4.0
		add_child(light)
		add_child(Effects.trail(color))
	_last_aim = Combat.aim_point(target) if is_instance_valid(target) else global_position + direction * MAX_RANGE


func _face() -> void:
	if direction.length() > 0.01 and absf(direction.normalized().dot(Vector3.UP)) < 0.999:
		look_at(global_position + direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	var step := ability.projectile_speed * delta
	if target != null:
		if is_instance_valid(target) and Combat.is_alive(target):
			_last_aim = Combat.aim_point(target)
		var to := _last_aim - global_position
		if to.length() <= step + 0.2:
			_hit(target if is_instance_valid(target) else null)
			return
		direction = to.normalized()
	# Walls stop it.
	var from := global_position
	var next := from + direction * step
	var query := PhysicsRayQueryParameters3D.create(from, next, 1)
	var wall := get_world_3d().direct_space_state.intersect_ray(query)
	if not wall.is_empty():
		global_position = wall.position
		_hit(null)
		return
	# Free flight: the first enemy close to the path.
	if target == null:
		for n in Combat.enemies_near(source, next, 0.9) if is_instance_valid(source) else []:
			if absf(Combat.aim_point(n).y - next.y) < 1.2:
				_hit(n)
				return
	global_position = next
	_face()
	_travelled += step
	if _travelled > MAX_RANGE or (target != null and _travelled > MAX_RANGE * 2.0):
		queue_free()


func _hit(who: Node3D) -> void:
	if who and Combat.is_alive(who) and is_instance_valid(source):
		Combat.hit(source, who, power, ability.staggers)
	if _arrow:
		Combat.play_sound(self, ARROW_HIT_SOUND, -6.0)
	else:
		Effects.burst(Combat.world_root(self), global_position, ability.projectile_color)
		Combat.play_sound(self, BOLT_BURST_SOUND, -3.0)
	queue_free()
