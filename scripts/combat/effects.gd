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
	return PixelArt.crisp(m)


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
	# On top of any status look (StatusLook layers), not instead of it.
	StatusLook.set_layer(node, "flash", mat)
	var tween := node.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, seconds).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		if is_instance_valid(node) and (StatusLook.body_of(node).get_meta("overlay_layers", {}) as Dictionary).get("flash") == mat:
			StatusLook.set_layer(node, "flash", null))


## Rising golden motes (soft circles and little diamonds) around a combatant for
## `seconds` (healing, potions). Colour: player.json combat `heal_color` unless given.
static func heal_glow(on: Node3D, seconds: float, color := Color(0, 0, 0, 0)) -> void:
	if color.a == 0.0:
		color = _heal_color()
	for old_name in ["HealGlow", "HealGlowDiamonds"]:
		var old := on.get_node_or_null(old_name)
		if old:
			old.free()
	var parts: Array[CPUParticles3D] = []
	for diamond in [false, true]:
		var p := CPUParticles3D.new()
		p.name = "HealGlowDiamonds" if diamond else "HealGlow"
		p.amount = 10 if diamond else 22
		p.lifetime = 1.3
		p.local_coords = false
		var q := QuadMesh.new()
		q.size = Vector2.ONE * (0.15 if diamond else 0.13)
		var m := _particle_material(color, 2.5)
		m.albedo_texture = _mote_texture(diamond)
		q.material = m
		p.mesh = q
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_axis = Vector3.UP
		p.emission_ring_radius = 0.55
		p.emission_ring_inner_radius = 0.25
		p.emission_ring_height = 0.6 if diamond else 0.2
		p.direction = Vector3.UP
		p.spread = 12.0
		p.initial_velocity_min = 0.5
		p.initial_velocity_max = 1.0
		p.gravity = Vector3.ZERO
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.2
		p.color_ramp = _fade_ramp(color)
		p.position = Vector3.UP * (0.6 if diamond else 0.2)
		on.add_child(p)
		parts.append(p)
	var timer := on.get_tree().create_timer(maxf(seconds, 0.6))
	timer.timeout.connect(func() -> void:
		for p in parts:
			if is_instance_valid(p):
				p.emitting = false
				p.get_tree().create_timer(1.4).timeout.connect(p.queue_free))


## A quick ring of golden motes rising around someone (an instant heal).
static func heal_burst(on: Node3D) -> void:
	heal_glow(on, 0.7)


static func _heal_color() -> Color:
	var loop := Engine.get_main_loop() as SceneTree
	var db := loop.root.get_node_or_null("Database") if loop else null
	var c = (db.get("player") as Dictionary).get("combat", {}).get("heal_color", "") if db else ""
	return Color.html(String(c)) if String(c) != "" and Color.html_is_valid(String(c)) else Color(1.0, 0.86, 0.32)


static var _motes := {}

## White round dot / diamond on transparent (tinted by the particle colour), in the pixel
## look: a few big pixels with stepped edges.
static func _mote_texture(diamond: bool) -> Texture2D:
	if _motes.has(diamond):
		return _motes[diamond]
	var n := 9 if diamond else 8
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var d := (absf(u) + absf(v) * 0.75) if diamond else sqrt(u * u + v * v)
			var a := clampf((1.0 - d) * (6.0 if diamond else 3.0), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, PixelArt.step_alpha(a)))
	var tex := ImageTexture.create_from_image(img)
	_motes[diamond] = tex
	return tex


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


## A ring of force spreading over the ground (Burst Quake): an expanding flat ring, dust
## and a flash of light.
static func shockwave(parent: Node, at: Vector3, radius: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 4
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, 0.85)
	mat.emission_enabled = true
	mat.emission = color
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = at + Vector3.UP * 0.15
	ring.scale = Vector3(0.3, 0.6, 0.3)
	var t := ring.create_tween().set_parallel()
	t.tween_property(ring, "scale", Vector3(radius, 0.25, radius), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	t.chain().tween_callback(ring.queue_free)
	# Dust kicked up around the edge.
	var dust := SparkBurst.new()
	dust.count = 40
	dust.speed = radius * 1.6
	dust.out = Vector3.UP
	dust.color = Color(0.7, 0.62, 0.5)
	dust.life = 0.6
	parent.add_child(dust)
	dust.global_position = at + Vector3.UP * 0.1
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 5.0
	light.omni_range = radius * 1.2
	parent.add_child(light)
	light.global_position = at + Vector3.UP * 0.5
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.4)
	lt.tween_callback(light.queue_free)


## A weapon enchant's look: a coloured sheen over the weapon and wisps trailing off it.
## Returns the node to free when it ends.
static func enchant_glow(weapon: Node3D, color: Color) -> Node3D:
	var holder := Node3D.new()
	holder.name = "EnchantGlow"
	weapon.add_child(holder)
	var sheen := StandardMaterial3D.new()
	sheen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sheen.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sheen.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sheen.albedo_color = Color(color, 0.45)
	var meshes: Array = weapon.find_children("*", "MeshInstance3D", true, false)
	for mi: MeshInstance3D in meshes:
		mi.material_overlay = sheen
		mi.set_meta("own_overlay", true)  # body looks (StatusLook) leave it alone
	holder.tree_exiting.connect(func() -> void:
		for mi in meshes:
			if is_instance_valid(mi) and (mi as MeshInstance3D).material_overlay == sheen:
				(mi as MeshInstance3D).material_overlay = null
				(mi as MeshInstance3D).remove_meta("own_overlay"))
	var wisps := GPUParticles3D.new()
	wisps.amount = 28
	wisps.lifetime = 0.8
	wisps.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.03, 0.45, 0.03)
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3(0, 0.3, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color, 0.0))
	ramp.add_point(0.2, Color(color.lightened(0.4), 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(color, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	wisps.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	var m := _particle_material(color, 2.0)
	m.albedo_texture = _mote_texture(false)
	q.material = m
	wisps.draw_pass_1 = q
	wisps.position = Vector3.UP * 0.5
	holder.add_child(wisps)
	return holder


# --- Blood -----------------------------------------------------------------------------

const MAX_SPLATTERS := 60
static var _splatters: Array = []
static var _splatter_tex := {}  # seed -> Texture2D


## A spray of blood from a hit: drops fly out, fall, and leave splatters where they land
## (on the ground, a wall or a prop). `color` is the creature's blood (oil for machines).
static func blood(parent: Node, at: Vector3, away: Vector3, color: Color, size := 1.0) -> void:
	if parent == null or color.a <= 0.0:
		return
	var spray := BloodSpray.new()
	spray.count = clampi(int(9 * size), 4, 22)
	spray.out = away.normalized() if away.length() > 0.01 else Vector3.UP
	spray.color = color
	spray.size = size
	parent.add_child(spray)
	spray.global_position = at


## One splatter on a surface, fading after a while.
static func blood_splatter(parent: Node, at: Vector3, normal: Vector3, color: Color, size := 0.5) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var up := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var decals := String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")) != "gl_compatibility" \
		and RenderingServer.get_current_rendering_method() != "gl_compatibility"
	var tex := _splatter_texture(randi() % 4)
	var node: Node3D
	if decals:
		var d := Decal.new()
		d.texture_albedo = tex
		d.modulate = color
		d.size = Vector3(size, 0.4, size)
		d.cull_mask = 1
		node = d
	else:
		# (Renderers without decals: a flat quad just off the surface.)
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.albedo_color = color
		PixelArt.crisp(m)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material = m
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node = mi
	node.top_level = true
	parent.add_child(node)
	var side := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var z := side.cross(up).normalized()
	var basis := Basis(up.cross(z).normalized(), up, z).rotated(up, randf() * TAU)
	if node is MeshInstance3D:
		basis = basis * Basis(Vector3.RIGHT, -PI * 0.5)  # the quad faces +Z, a decal points down -Y
	node.global_transform = Transform3D(basis, at + up * 0.02)
	_splatters.append(node)
	while _splatters.size() > MAX_SPLATTERS:
		var old = _splatters.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var seconds := float(Database.player.get("combat", {}).get("blood_seconds", 30.0))
	var tween := node.create_tween()
	tween.tween_interval(seconds * randf_range(0.7, 1.3))
	tween.tween_property(node, "modulate:a" if node is Decal else "mesh:material:albedo_color:a", 0.0, 4.0)
	tween.tween_callback(func() -> void:
		_splatters.erase(node)
		node.queue_free())


## A few blobs of blood, drawn in code: each one a big spot with smaller specks round it.
static func _splatter_texture(variant: int) -> Texture2D:
	if _splatter_tex.has(variant):
		return _splatter_tex[variant]
	var n := 20  # big pixels, like the grass
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant
	var blobs: Array = [[Vector2(0.5, 0.5), 0.2 + rng.randf() * 0.08]]
	for i in 7:
		var a := rng.randf() * TAU
		var r := 0.18 + rng.randf() * 0.26
		blobs.append([Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * r, 0.03 + rng.randf() * 0.07])
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n
			var a := 0.0
			for b: Array in blobs:
				var d: float = p.distance_to(b[0]) / float(b[1])
				a = maxf(a, clampf(1.0 - d * d * d, 0.0, 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if a > 0.45 else 0.0))
	var tex := ImageTexture.create_from_image(img)
	_splatter_tex[variant] = tex
	return tex


## Drops of blood flying out, moved by hand so they show in every renderer; each one
## leaves a splatter where it meets the world.
class BloodSpray:
	extends Node3D
	var count := 9
	var out := Vector3.UP
	var color := Color(0.55, 0.05, 0.07)
	var size := 1.0
	var _drops: Array = []  # [MeshInstance3D, velocity, age]
	var _age := 0.0

	func _ready() -> void:
		top_level = true
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.35
		mat.metallic = 0.1
		var mesh := SphereMesh.new()
		mesh.radius = 0.035 * size
		mesh.height = 0.07 * size
		mesh.radial_segments = 6
		mesh.rings = 3
		mesh.material = mat
		var side := out.cross(Vector3.UP if absf(out.y) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(out).normalized()
		for i in count:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.scale = Vector3.ONE * randf_range(0.6, 1.5)
			add_child(mi)
			var a := randf() * TAU
			var spread := randf() * 0.9
			var dir := (out + (side * cos(a) + up * sin(a)) * spread + Vector3.UP * 0.45).normalized()
			_drops.append([mi, dir * randf_range(2.0, 5.5) * size, 0.0])

	func _process(delta: float) -> void:
		_age += delta
		var space := get_world_3d().direct_space_state
		for i in range(_drops.size() - 1, -1, -1):
			var d: Array = _drops[i]
			var mi: MeshInstance3D = d[0]
			var v: Vector3 = d[1]
			v.y -= 14.0 * delta
			var step := v * delta
			var from := mi.global_position
			var q := PhysicsRayQueryParameters3D.create(from, from + step, 1)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				Effects.blood_splatter(get_parent(), hit.position, hit.normal, color, randf_range(0.25, 0.7) * size)
				mi.queue_free()
				_drops.remove_at(i)
				continue
			mi.global_position = from + step
			d[1] = v
			d[2] = float(d[2]) + delta
			if float(d[2]) > 2.5:
				mi.queue_free()
				_drops.remove_at(i)
		if _drops.is_empty() or _age > 3.0:
			queue_free()


## Glittering motes that drift down around `who` in slow spirals (blessings, the Monolith).
static func sparkle_down(who: Node3D, color: Color, seconds := 2.5, count := 28) -> void:
	if who == null or not who.is_inside_tree():
		return
	var fx := SparkleDown.new()
	fx.color = color
	fx.seconds = seconds
	fx.count = count
	fx.who = who
	Combat.world_root(who).add_child(fx)
	fx.global_position = who.global_position


## Moved by hand (so it shows in every renderer): each mote starts above the head and
## twirls down round the body, twinkling, then fades.
class SparkleDown extends Node3D:
	var color := Color(0.5, 0.8, 1.0)
	var seconds := 2.5
	var count := 28
	var who: Node3D
	var _motes: Array = []  # [MeshInstance3D, delay, angle, radius, speed]
	var _t := 0.0
	var _light: OmniLight3D

	func _ready() -> void:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.albedo_texture = Effects._mote_texture(true)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		for i in count:
			var q := QuadMesh.new()
			q.size = Vector2.ONE * randf_range(0.09, 0.17)
			var m := MeshInstance3D.new()
			m.mesh = q
			m.material_override = mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(m)
			_motes.append([m, randf_range(0.0, seconds * 0.45), randf() * TAU, randf_range(0.35, 0.8), randf_range(0.8, 1.4)])
		_light = OmniLight3D.new()
		_light.light_color = color
		_light.light_energy = 0.0
		_light.omni_range = 4.0
		_light.position = Vector3.UP * 1.2
		add_child(_light)

	func _process(delta: float) -> void:
		_t += delta
		if is_instance_valid(who):
			global_position = who.global_position
		var life := seconds * 0.6
		for e: Array in _motes:
			var m: MeshInstance3D = e[0]
			var k := (_t - float(e[1])) / life
			m.visible = k > 0.0 and k < 1.0
			if not m.visible:
				continue
			var a := float(e[2]) + k * TAU * 1.2 * float(e[4])
			var r := float(e[3]) * (1.0 - k * 0.4)
			m.position = Vector3(cos(a) * r, lerpf(2.4, 0.1, k), sin(a) * r)
			var twinkle := 0.6 + 0.4 * sin(_t * 18.0 + float(e[2]) * 5.0)
			m.scale = Vector3.ONE * twinkle * (1.0 - k * 0.5)
		_light.light_energy = sin(clampf(_t / seconds, 0.0, 1.0) * PI) * 1.6
		if _t > seconds:
			queue_free()
