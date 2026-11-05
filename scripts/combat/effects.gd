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
