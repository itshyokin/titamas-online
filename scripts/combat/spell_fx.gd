class_name SpellFX
extends RefCounted
## Looks for the mage spells, built in code: lightning arcs, the tidal wave's wall of water
## and the ground marker for spells cast on a spot. Names no autoloads (tests can use it).

const MARKER_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(0.7, 0.6, 1.0, 1.0);
uniform float locked = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	// Pixel steps (a 32-texel grid across the circle), like the rest of the effects.
	vec2 q = floor(UV * 32.0) / 32.0 * 2.0 - 1.0;
	float rq = length(q);
	float ring = step(0.84, rq) * step(rq, 0.97);
	float a = atan(q.y, q.x) + TIME * (0.8 + locked * 2.5);
	float ticks = step(0.62, rq) * step(rq, 0.72) * step(0.5, fract(a * 6.0 / 6.2832));
	float fill = 0.12 + 0.1 * locked * (0.5 + 0.5 * sin(TIME * 8.0));
	ALBEDO = color.rgb;
	ALPHA = max(max(ring, ticks * 0.8), fill) * color.a;
}
"""

const WAVE_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(0.25, 0.55, 0.95, 1.0);
uniform float fade = 1.0;
void fragment() {
	// UV.x along the arc, UV.y from the ground (0) to the crest (1).
	float stripes = step(0.5, fract(UV.x * 18.0 + UV.y * 2.0 - TIME * 3.0));
	float foam = step(0.78, UV.y + stripes * 0.06);
	vec3 deep = color.rgb * (0.7 + 0.3 * UV.y);
	ALBEDO = mix(deep, vec3(0.92, 0.97, 1.0), foam);
	EMISSION = ALBEDO * 0.25;
	ROUGHNESS = 0.2;
	float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x);
	ALPHA = (0.75 + foam * 0.2) * edge * fade;
}
"""


# --- Ground marker -------------------------------------------------------------------

static func ground_marker(radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "SpellMarker"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * maxf(radius, 0.5) * 2.0
	mi.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = StatusLook.shader(MARKER_SHADER)
	mat.render_priority = 2
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	return mi


static func tint_marker(marker: MeshInstance3D, color: Color) -> void:
	var mat := marker.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("color", Color(color, 0.9))


## The spot is chosen: the marker spins faster and pulses until the spell goes off.
static func lock_marker(marker: MeshInstance3D) -> void:
	var mat := marker.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("locked", 1.0)


# --- Lightning -----------------------------------------------------------------------

## A jagged arc of lightning from `from` to `to` that flickers (re-forms) a few times and
## fades, with a flash of light.
static func lightning(parent: Node, from: Vector3, to: Vector3, color: Color, seconds := 0.3) -> void:
	var bolt := LightningArc.new()
	bolt.from = from
	bolt.to = to
	bolt.color = color
	bolt.life = seconds
	parent.add_child(bolt)


class LightningArc extends Node3D:
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	var color := Color(0.7, 0.8, 1.0)
	var life := 0.3
	var _age := 0.0
	var _next := 0.0
	var _mesh := ImmediateMesh.new()
	var _core := StandardMaterial3D.new()
	var _light := OmniLight3D.new()

	func _ready() -> void:
		top_level = true
		global_position = Vector3.ZERO
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_core.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_core.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_core.vertex_color_use_as_albedo = true
		_core.cull_mode = BaseMaterial3D.CULL_DISABLED
		_core.no_depth_test = false
		_light.light_color = color
		_light.light_energy = 4.0
		_light.omni_range = from.distance_to(to) * 0.6 + 3.0
		add_child(_light)
		_light.global_position = (from + to) * 0.5
		_build()

	func _process(delta: float) -> void:
		_age += delta
		_next -= delta
		if _age >= life:
			queue_free()
			return
		if _next <= 0.0:
			_build()
		var k := 1.0 - _age / life
		_light.light_energy = 4.0 * k

	func _build() -> void:
		_next = 0.07
		_mesh.clear_surfaces()
		var k := clampf(1.0 - _age / life, 0.0, 1.0)
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _core)
		var path := _jagged(from, to, 0.35)
		_ribbon(path, 0.34, Color(color, 0.28 * k))
		_ribbon(path, 0.1, Color(color.lightened(0.6), 0.95 * k))
		# A couple of short forks.
		for i in 2:
			var at := path[randi_range(1, maxi(path.size() - 2, 1))]
			var dir := (to - from).normalized() + Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * 0.9
			var fork := _jagged(at, at + dir.normalized() * from.distance_to(to) * randf_range(0.12, 0.25), 0.18)
			_ribbon(fork, 0.06, Color(color.lightened(0.4), 0.7 * k))
		_mesh.surface_end()

	func _jagged(a: Vector3, b: Vector3, rough: float) -> PackedVector3Array:
		var pts := PackedVector3Array()
		var length := a.distance_to(b)
		var n := clampi(int(length / 0.5), 3, 40)
		var along := (b - a).normalized()
		var side := along.cross(Vector3.UP)
		if side.length() < 0.1:
			side = along.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(along).normalized()
		for i in n + 1:
			var t := float(i) / n
			var p := a.lerp(b, t)
			if i > 0 and i < n:
				var amp := rough * sqrt(length) * 0.35 * sin(t * PI)
				p += side * randf_range(-amp, amp) + up * randf_range(-amp, amp)
			pts.append(p)
		return pts

	## Two crossed strips along the path, so it reads from any side.
	func _ribbon(pts: PackedVector3Array, width: float, c: Color) -> void:
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var along := (b - a).normalized()
			var s1 := along.cross(Vector3.UP)
			if s1.length() < 0.1:
				s1 = along.cross(Vector3.RIGHT)
			s1 = s1.normalized() * width * 0.5
			var s2 := along.cross(s1).normalized() * width * 0.5
			for s in [s1, s2]:
				_quad(a - s, a + s, b + s, b - s, c)

	func _quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, c: Color) -> void:
		for p in [p0, p1, p2, p0, p2, p3]:
			_mesh.surface_set_color(c)
			_mesh.surface_add_vertex(p)


# --- Tidal wave ----------------------------------------------------------------------

## A curved wall of water rushing out from `at` along `forward` to `reach` metres over
## `seconds`, `arc` degrees wide, spraying as it goes.
static func water_wave(parent: Node, at: Vector3, forward: Vector3, reach: float, arc: float, color: Color, seconds := 0.5, height := 1.6) -> Node3D:
	var w := WaterWave.new()
	w.reach = reach
	w.arc = arc
	w.color = color
	w.seconds = seconds
	w.height = height
	parent.add_child(w)
	w.global_position = at
	forward.y = 0.0
	if forward.length() > 0.01:
		w.look_at(at + forward.normalized(), Vector3.UP)
	return w


class WaterWave extends Node3D:
	var reach := 8.0
	var arc := 100.0
	var color := Color(0.25, 0.55, 0.95)
	var seconds := 0.5
	var height := 1.6
	var _age := 0.0
	var _spray := 0.0
	var _wall := MeshInstance3D.new()
	var _mat := ShaderMaterial.new()

	func _ready() -> void:
		_wall.mesh = _arc_mesh(arc)
		_mat.shader = StatusLook.shader(WAVE_SHADER)
		_mat.set_shader_parameter("color", color)
		_wall.material_override = _mat
		_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_wall)
		_set_size(0.6, 0.3)

	func _process(delta: float) -> void:
		_age += delta
		var k := clampf(_age / seconds, 0.0, 1.0)
		var r := lerpf(0.6, reach, 1.0 - pow(1.0 - k, 1.6))
		var h := height * sqrt(sin(clampf(k * 0.9 + 0.1, 0.0, 1.0) * PI))
		if _age > seconds:
			# Collapses into foam at the far edge.
			var c := clampf((_age - seconds) / 0.35, 0.0, 1.0)
			h = height * 0.35 * (1.0 - c)
			_mat.set_shader_parameter("fade", 1.0 - c)
			if c >= 1.0:
				queue_free()
				return
		_set_size(r, maxf(h, 0.05))
		_spray -= delta
		if _spray <= 0.0 and _age < seconds:
			_spray = 0.08
			var a := deg_to_rad(randf_range(-arc * 0.45, arc * 0.45))
			var p := global_transform * (Vector3(sin(a), 0.0, -cos(a)) * r)
			Effects.splash(get_parent(), p, randf_range(0.6, 1.0))

	func _set_size(r: float, h: float) -> void:
		_wall.scale = Vector3(r, h, r)

	## Wall along an arc of the unit circle in front (-Z), leaning out at the top.
	static func _arc_mesh(degrees: float) -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := 24
		var rows := 4
		for i in n:
			for j in rows:
				var quad := []
				for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
					var u := float(c[0]) / n
					var v := float(c[1]) / rows
					var a := deg_to_rad(lerpf(-degrees * 0.5, degrees * 0.5, u))
					var lean := 1.0 + 0.18 * v * v  # the crest curls forward
					quad.append([Vector3(sin(a) * lean, v, -cos(a) * lean), Vector2(u, v)])
				for idx in [0, 1, 2, 0, 2, 3]:
					st.set_uv(quad[idx][1])
					st.add_vertex(quad[idx][0])
		st.generate_normals()
		return st.commit()
