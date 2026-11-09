class_name Effects
extends RefCounted
## Simple particle effects for spells and hits, built in code (no assets needed).


static func _particle_material(color: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func _quad(size: float, color: Color) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _particle_material(color)
	return q


static func _fade_ramp(color: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(color, 1.0))
	g.set_color(1, Color(color.darkened(0.3), 0.0))
	return g


## Glowing sparks trailing behind a moving bolt.
static func trail(color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.35
	p.local_coords = false
	p.mesh = _quad(0.16, color)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.color_ramp = _fade_ramp(color)
	return p


## A one-off burst of sparks and light (spell impact).
static func burst(parent: Node, at: Vector3, color: Color, size := 1.0) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.global_position = at
	var p := CPUParticles3D.new()
	p.amount = int(48 * size)
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 0.95
	p.mesh = _quad(0.22 * size, color)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0 * size
	p.initial_velocity_max = 5.0 * size
	p.gravity = Vector3(0, -4, 0)
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.color_ramp = _fade_ramp(color)
	holder.add_child(p)
	p.emitting = true
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = 6.0 * size
	holder.add_child(light)
	var tween := holder.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.4)
	tween.tween_interval(0.5)
	tween.tween_callback(holder.queue_free)


## Quick sparks where a blow lands (no light, so many can go off at once).
static func sparks(parent: Node, at: Vector3, color: Color, size := 1.0, toward := Vector3.UP) -> void:
	var p := CPUParticles3D.new()
	parent.add_child(p)
	p.global_position = at
	p.amount = int(14 * size) + 4
	p.lifetime = 0.35
	p.one_shot = true
	p.explosiveness = 1.0
	p.mesh = _quad(0.09 * size, color)
	p.direction = toward if toward.length() > 0.01 else Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 3.0 * size
	p.initial_velocity_max = 7.0 * size
	p.gravity = Vector3(0, -9, 0)
	p.damping_min = 4.0
	p.damping_max = 8.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.color_ramp = _fade_ramp(color)
	p.emitting = true
	p.finished.connect(p.queue_free)


## A metal-on-stone strike: bright streaking sparks thrown off the surface (stretched
## along their flight), a few slower embers, and a quick flash of light. `size` scales
## the count and speed (player.json combat "spark_size").
static func strike_sparks(parent: Node, at: Vector3, normal: Vector3, size := 1.0, color := Color(1.0, 0.78, 0.35)) -> void:
	var out := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var burst := SparkBurst.new()
	burst.count = int(26 * size) + 6
	burst.speed = 6.5 * size
	burst.out = out
	burst.color = color
	parent.add_child(burst)
	burst.global_position = at + out * 0.03
	# A brief flash.
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 3.5
	light.omni_range = 2.5
	parent.add_child(light)
	light.global_position = at + out * 0.2
	var t := light.create_tween()
	t.tween_property(light, "light_energy", 0.0, 0.18)
	t.tween_callback(light.queue_free)


## Sparks as plain meshes moved by hand (bright streaks stretched along their flight,
## falling and fading), so they show the same in every renderer.
class SparkBurst:
	extends Node3D
	var count := 30
	var speed := 6.5
	var out := Vector3.UP
	var color := Color(1.0, 0.78, 0.35)
	var life := 0.45
	var _age := 0.0
	var _sparks: Array = []  # [MeshInstance3D, velocity]
	var _mat: StandardMaterial3D

	func _ready() -> void:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_color = Color(1.0, 0.95, 0.75)
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.018, 0.018, 0.14)
		mesh.material = _mat
		var side := out.cross(Vector3.UP if absf(out.y) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(out).normalized()
		for i in count:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			var a := randf() * TAU
			var spread := randf() * 1.1
			var dir := (out + (side * cos(a) + up * sin(a)) * spread + Vector3.UP * 0.35).normalized()
			_sparks.append([mi, dir * speed * randf_range(0.45, 1.0)])

	func _process(delta: float) -> void:
		_age += delta
		var k := _age / life
		if k >= 1.0:
			queue_free()
			return
		_mat.albedo_color = Color(1.0, 0.95, 0.75).lerp(color, minf(k * 2.0, 1.0))
		_mat.albedo_color.a = 1.0 - k * k
		for s: Array in _sparks:
			var mi: MeshInstance3D = s[0]
			var v: Vector3 = s[1]
			v.y -= 12.0 * delta
			v *= 1.0 - minf(3.0 * delta, 0.5)
			s[1] = v
			mi.position += v * delta
			if v.length() > 0.05:
				mi.look_at(mi.global_position + v, Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT)


## Flashes every mesh under `node` a colour for a moment (being hit, a wind-up warning).
static func flash(node: Node, color := Color(1, 1, 1), seconds := 0.12, strength := 0.75) -> void:
	if node == null or not node.is_inside_tree():
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, strength)
	mat.no_depth_test = false
	var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
	for mi: MeshInstance3D in meshes:
		if mi.is_visible_in_tree() and mi.material_overlay == null:
			mi.material_overlay = mat
	var tween := node.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, seconds).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		for m in meshes:  # untyped: some may have been freed meanwhile
			if is_instance_valid(m) and (m as MeshInstance3D).material_overlay == mat:
				(m as MeshInstance3D).material_overlay = null)


## Soft rising motes around a combatant for `seconds` (healing over time).
static func heal_glow(on: Node3D, seconds: float, color := Color(0.4, 1.0, 0.5)) -> void:
	var old := on.get_node_or_null("HealGlow")
	if old:
		old.free()
	var p := CPUParticles3D.new()
	p.name = "HealGlow"
	p.amount = 24
	p.lifetime = 1.2
	p.local_coords = false
	p.mesh = _quad(0.12, color)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.5
	p.emission_ring_inner_radius = 0.3
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 10.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.1
	p.gravity = Vector3.ZERO
	p.color_ramp = _fade_ramp(color)
	p.position = Vector3.UP * 0.2
	on.add_child(p)
	var timer := on.get_tree().create_timer(seconds)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.emitting = false
			p.get_tree().create_timer(1.3).timeout.connect(p.queue_free))


## A glow held in the hand while casting. Free it when the cast ends.
static func hand_glow(color: Color) -> Node3D:
	var holder := Node3D.new()
	var p := CPUParticles3D.new()
	p.amount = 20
	p.lifetime = 0.4
	p.mesh = _quad(0.12, color)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.08
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.4
	p.gravity = Vector3.ZERO
	p.color_ramp = _fade_ramp(color)
	holder.add_child(p)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.5
	light.omni_range = 3.0
	holder.add_child(light)
	return holder


## Ring on the ground under the current target.
static func target_ring(color := Color(1.0, 0.25, 0.2)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "TargetRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.7
	torus.rings = 48
	torus.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = m
	mi.mesh = torus
	mi.scale = Vector3(1, 0.15, 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Brackets around a locked-on target's body (always faces the camera).
static func lock_marker(height := 2.1, width := 1.3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "LockMarker"
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/materials/lock_marker.gdshader")
	q.material = m
	mi.mesh = q
	mi.scale = Vector3(width, height, 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


const RIPPLE_SHADER := preload("res://assets/materials/ripple.gdshader")
static var _ripple_mesh: QuadMesh


## An expanding ring on a water surface (wading, swimming, landing in water).
static func ripple(parent: Node, at: Vector3, size := 1.0, seconds := 1.4) -> void:
	if _ripple_mesh == null:
		_ripple_mesh = QuadMesh.new()
		_ripple_mesh.size = Vector2(2, 2)
		_ripple_mesh.orientation = PlaneMesh.FACE_Y
		var m := ShaderMaterial.new()
		m.shader = RIPPLE_SHADER
		_ripple_mesh.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = _ripple_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * size * 0.3
	mi.set_instance_shader_parameter("age", 0.0)
	var t := mi.create_tween()
	t.set_parallel(true)
	t.tween_property(mi, "scale", Vector3.ONE * size * 1.6, seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_method(func(a: float) -> void: mi.set_instance_shader_parameter("age", a), 0.0, 1.0, seconds)
	t.chain().tween_callback(mi.queue_free)


## Water thrown up when something lands in water, plus rings.
static func splash(parent: Node, at: Vector3, size := 1.0) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.global_position = at
	var color := Color(0.85, 0.94, 1.0, 0.9)
	var p := CPUParticles3D.new()
	p.amount = int(40 * size)
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.9
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14) * clampf(size, 0.6, 1.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.mesh = q
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 2.0 * size
	p.initial_velocity_max = 4.5 * size
	p.gravity = Vector3(0, -9.8, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.35 * size
	p.emission_ring_inner_radius = 0.1
	p.emission_ring_height = 0.05
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color, 0.0))
	p.color_ramp = g
	holder.add_child(p)
	p.emitting = true
	ripple(parent, at + Vector3.UP * 0.02, size * 1.4, 1.6)
	ripple(parent, at + Vector3.UP * 0.02, size * 0.8, 1.1)
	holder.get_tree().create_timer(1.2).timeout.connect(holder.queue_free)
