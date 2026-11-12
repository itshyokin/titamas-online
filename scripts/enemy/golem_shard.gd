class_name GolemShard
extends Node3D
## A stalactite-like needle of stone a golem flings at someone who keeps their distance
## (Beast "shards"): flies fast and nearly straight, hits whoever it touches (a dodge
## roll's i-frames go through), sticks in the ground or a wall for a moment, then crumbles.

const HIT := preload("res://assets/audio/creatures/shard_hit.ogg")

var source: Node3D
var power := 8.0
var knockback := 2.0
var velocity := Vector3.ZERO
var gravity := 3.0
var color := Color(0.62, 0.66, 0.72)
var glow := false

var _mesh: MeshInstance3D
var _age := 0.0
var _stuck := -1.0


## Fires a shard from `from` toward `at` at `speed` m/s.
static func fire(from: Vector3, at: Vector3, speed: float, thrower: Node3D, shard_power: float, push: float, tint: Color, glowing := false) -> GolemShard:
	var s := GolemShard.new()
	s.source = thrower
	s.power = shard_power
	s.knockback = push
	s.color = tint
	s.glow = glowing
	var dir := (at - from).normalized()
	s.velocity = dir * speed
	# Lifted a little so the slight drop lands it on the aim point.
	var t := from.distance_to(at) / maxf(speed, 1.0)
	s.velocity.y += 0.5 * s.gravity * t
	Combat.world_root(thrower).add_child(s)
	s.global_position = from
	return s


## The needle mesh: a long thin crystal pointing along -Z.
static func needle_mesh(length := 1.1, radius := 0.12) -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = length
	c.radial_segments = 5
	c.rings = 1
	return c


func _ready() -> void:
	add_to_group("hostile_missiles")  # paused during conversations (DialogueBox)
	top_level = true
	_mesh = MeshInstance3D.new()
	_mesh.mesh = needle_mesh()
	_mesh.rotation.x = -PI * 0.5  # cylinder's +Y (the tip) along -Z
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.4
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 1.5
	_mesh.material_override = m
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_face(velocity)


func _face(dir: Vector3) -> void:
	if dir.length() > 0.01:
		look_at(global_position + dir, Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.RIGHT)


func _physics_process(delta: float) -> void:
	_age += delta
	if _stuck >= 0.0:
		_stuck += delta
		if _stuck > 1.5:
			scale = Vector3.ONE * maxf(1.0 - (_stuck - 1.5) * 3.0, 0.01)
		if _stuck > 1.85:
			queue_free()
		return
	var from := global_position
	velocity.y -= gravity * delta
	var to := from + velocity * delta
	_face(velocity)
	if is_instance_valid(source):
		for n in Combat.enemies_near(source, to, 1.6):
			if Combat.aim_point(n).distance_to(to) < 0.8 or n.global_position.distance_to(to) < 0.6:
				Combat.hit(source, n, power, false, knockback)
				_shatter(to)
				return
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		# Sticks in where it hit, tip first.
		global_position = hit.position - velocity.normalized() * 0.25
		_stuck = 0.0
		Combat.play_sound(self, HIT, -4.0, randf_range(1.0, 1.25))
		return
	global_position = to
	if _age > 4.0:
		queue_free()


func _shatter(at: Vector3) -> void:
	Combat.play_sound(self, HIT, 0.0, randf_range(0.9, 1.1))
	var bits := Effects.SparkBurst.new()
	bits.count = 14
	bits.speed = 4.0
	bits.out = -velocity.normalized()
	bits.color = color.lightened(0.2)
	bits.life = 0.45
	Combat.world_root(self).add_child(bits)
	bits.global_position = at
	queue_free()
