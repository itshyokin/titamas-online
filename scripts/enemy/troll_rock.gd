class_name TrollRock
extends Node3D
## A boulder a troll throws (Beast "throw"): flies in an arc to where the target was
## going to be, with a red ring on the ground there so it can be seen coming and dodged.
## Hits whoever it touches hard (a dodge roll's i-frames go through it); landing near
## someone still hurts them a little, then it bursts into stones and dust.

const IMPACT := preload("res://assets/audio/creatures/rock_impact.ogg")
const RING := "res://assets/effects/builtin/ring.png"

var source: Node3D
var power := 20.0
var knockback := 6.0
var splash := 1.8
var velocity := Vector3.ZERO
var gravity := 14.0
var landing := Vector3.INF

var _marker: MeshInstance3D
var _mesh: MeshInstance3D
var _age := 0.0
var _spin := Vector3.ZERO
var _done := false


## Throws a rock from `from` so it comes down on `at` after about `seconds`.
static func throw_at(from: Vector3, at: Vector3, seconds: float, thrower: Node3D, rock_power: float, push: float, splash_radius: float) -> TrollRock:
	var r := TrollRock.new()
	r.source = thrower
	r.power = rock_power
	r.knockback = push
	r.splash = splash_radius
	var t := maxf(seconds, 0.4)
	r.velocity = (at - from) / t + Vector3.UP * 0.5 * r.gravity * t
	r.landing = at
	Combat.world_root(thrower).add_child(r)
	r.global_position = from
	return r


func _ready() -> void:
	add_to_group("hostile_missiles")  # paused during conversations (DialogueBox)
	top_level = true
	_mesh = MeshInstance3D.new()
	_mesh.mesh = BeastModel.rock_mesh(0.55)
	add_child(_mesh)
	_spin = Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6))
	if landing != Vector3.INF:
		_marker = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.orientation = PlaneMesh.FACE_Y
		q.size = Vector2.ONE * splash * 2.0
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_texture = AbilityFX.texture(RING)
		mat.albedo_color = Color(1.0, 0.25, 0.15, 0.0)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		PixelArt.crisp(mat)
		q.material = mat
		_marker.mesh = q
		_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Combat.world_root(self).add_child(_marker)
		var g := _ground(landing)
		_marker.global_position = (g if g != Vector3.INF else landing) + Vector3.UP * 0.06


func _ground(at: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 8.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else Vector3.INF


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _marker:
		var m := (_marker.mesh as QuadMesh).material as StandardMaterial3D
		m.albedo_color.a = minf(_age * 2.5, 0.85)
		_marker.scale = Vector3.ONE * lerpf(0.5, 1.0, minf(_age * 1.5, 1.0))
	var from := global_position
	velocity.y -= gravity * delta
	var to := from + velocity * delta
	_mesh.rotation += _spin * delta
	# Whoever it flies into.
	if is_instance_valid(source):
		for n in Combat.enemies_near(source, to, 0.9 + 0.5):
			if n.global_position.distance_to(to) < 0.9 + 0.6 or Combat.aim_point(n).distance_to(to) < 1.1:
				Combat.hit(source, n, power, true, knockback)
				_burst(to, n)
				return
	# The ground, a wall, a tree.
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_burst(hit.position, null)
		return
	global_position = to
	if _age > 6.0:
		_burst(global_position, null)


func _burst(at: Vector3, struck: Node3D) -> void:
	_done = true
	var root := Combat.world_root(self)
	Combat.play_sound(self, IMPACT, 4.0, randf_range(0.9, 1.1))
	# Close calls still hurt a little.
	if is_instance_valid(source):
		for n in Combat.enemies_near(source, at, splash):
			if n != struck:
				Combat.hit(source, n, power * 0.35, false, knockback * 0.5)
	var dust := Effects.SparkBurst.new()
	dust.count = 26
	dust.speed = 5.0
	dust.out = Vector3.UP
	dust.color = Color(0.62, 0.56, 0.46)
	dust.life = 0.7
	root.add_child(dust)
	dust.global_position = at + Vector3.UP * 0.2
	# A few stones flying off.
	for i in 6:
		var chip := Chip.new()
		chip.velocity = Vector3(randf_range(-4, 4), randf_range(3, 7), randf_range(-4, 4))
		root.add_child(chip)
		chip.global_position = at + Vector3.UP * 0.3
	var cam := get_tree().get_first_node_in_group("player_camera")
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if cam and player and player.global_position.distance_to(at) < 18.0:
		cam.call("shake", 0.3)
	if is_instance_valid(_marker):
		_marker.queue_free()
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()


## A stone broken off a rock: flies, falls, fades.
class Chip:
	extends MeshInstance3D
	var velocity := Vector3.ZERO
	var _age := 0.0
	var _spin := Vector3.ZERO

	func _ready() -> void:
		top_level = true
		mesh = BeastModel.rock_mesh(randf_range(0.1, 0.2))
		_spin = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func _physics_process(delta: float) -> void:
		_age += delta
		velocity.y -= 14.0 * delta
		var to := global_position + velocity * delta
		var q := PhysicsRayQueryParameters3D.create(global_position, to, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			global_position = to
			rotation += _spin * delta
		else:
			velocity = Vector3.ZERO
			global_position = hit.position + Vector3.UP * 0.05
		if _age > 2.2:
			scale = Vector3.ONE * maxf(1.0 - (_age - 2.2) * 2.0, 0.01)
		if _age > 2.7:
			queue_free()
