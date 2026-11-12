class_name StatusLook
extends RefCounted
## How statuses show on whoever has them (statuses.json "look" + "look_color"):
##   glow   a coloured rim light round the body (Rage)
##   ice    an icy coat (Frozen)
##   bubble a shimmering sphere round them (Ward)
## Also a shared stack of overlay materials on a body's meshes (`set_layer`), so hit flashes,
## status looks and the dark cloud's outlines sit on top of each other instead of one
## replacing the other. Layers go on the body's "Model" child when it has one. Meshes
## with meta "own_overlay" (enchanted weapons) or "no_overlay" are left alone.
## Names no autoloads (tests can use it).

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 color : source_color = vec4(1.0, 0.2, 0.1, 1.0);
uniform float strength = 1.0;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float pulse = 0.75 + 0.25 * sin(TIME * 7.0);
	ALBEDO = color.rgb;
	ALPHA = clamp((rim * 1.4 + 0.12) * pulse * strength, 0.0, 1.0);
}
"""

const ICE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
uniform vec4 color : source_color = vec4(0.75, 0.92, 1.0, 1.0);
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	vec3 p = floor(VERTEX * 9.0);
	float facet = fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	ALBEDO = mix(color.rgb * (0.82 + 0.18 * facet), vec3(1.0), rim * 0.7);
	ALPHA = 0.62 + rim * 0.3;
}
"""

const BUBBLE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(0.5, 0.75, 1.0, 1.0);
uniform float fade = 1.0;
void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	float bands = 0.5 + 0.5 * sin(UV.y * 60.0 + TIME * 3.0);
	ALBEDO = color.rgb;
	ALPHA = clamp(rim * 0.9 + bands * 0.06 + 0.04, 0.0, 1.0) * fade;
}
"""

static var _shaders := {}


static func shader(code: String) -> Shader:
	if not _shaders.has(code):
		var s := Shader.new()
		s.code = code
		_shaders[code] = s
	return _shaders[code]


static func body_of(node: Node) -> Node:
	if node == null:
		return null
	var m := node.get_node_or_null("Model")
	return m if m else node


## Puts `mat` on every mesh of `node`'s body under `key` (null takes it off). Layers draw in
## key order, each as the next pass of the one before.
static func set_layer(node: Node, key: String, mat: Material) -> void:
	var body := body_of(node)
	if body == null or not is_instance_valid(body):
		return
	var layers: Dictionary = body.get_meta("overlay_layers", {})
	if mat == null:
		if not layers.has(key):
			return
		layers.erase(key)
	else:
		layers[key] = mat
	body.set_meta("overlay_layers", layers)
	reapply(body)


static func has_layer(node: Node, key: String) -> bool:
	var body := body_of(node)
	return body != null and (body.get_meta("overlay_layers", {}) as Dictionary).has(key)


## Sets the body's meshes' overlays from its layers again (after gear was swapped).
static func reapply(body: Node) -> void:
	var layers: Dictionary = body.get_meta("overlay_layers", {})
	var keys := layers.keys()
	keys.sort()
	var first: Material = null
	var prev: Material = null
	for k in keys:
		var m: Material = layers[k]
		if not is_instance_valid(m):
			continue
		if prev:
			prev.next_pass = m
		else:
			first = m
		prev = m
	if prev:
		prev.next_pass = null
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("own_overlay") or mi.has_meta("no_overlay"):
			continue
		(mi as MeshInstance3D).material_overlay = first


static func _mat(code: String, color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(code)
	m.set_shader_parameter("color", color)
	return m


## Called when a combatant's statuses change (Stats): adds or removes each look.
static func refresh(owner: Node, stats: Stats) -> void:
	if owner == null or not is_instance_valid(owner) or not owner.is_inside_tree():
		return
	var want := {}  # look -> colour
	if not stats.is_dead():
		for id: String in stats.statuses:
			var d := Stats.status_data(id)
			var look := String(d.get("look", ""))
			if look != "":
				want[look] = Color.html(String(d.get("look_color", d.get("color", "#ffffff"))))
	for look: String in ["glow", "ice"]:
		var key := "status_" + look
		if want.has(look) and not has_layer(owner, key):
			set_layer(owner, key, _mat(GLOW_SHADER if look == "glow" else ICE_SHADER, want[look]))
		elif not want.has(look) and has_layer(owner, key):
			set_layer(owner, key, null)
	var bubble := owner.get_node_or_null("StatusBubble") as MeshInstance3D
	if want.has("bubble") and bubble == null:
		_add_bubble(owner as Node3D, want.bubble)
	elif not want.has("bubble") and bubble and not bubble.has_meta("popping"):
		_pop_bubble(bubble)


static func _add_bubble(owner: Node3D, color: Color) -> void:
	if owner == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "StatusBubble"
	mi.set_meta("no_overlay", true)
	var r := maxf(1.05, float(owner.get("body_radius")) + 0.4 if owner.get("body_radius") != null else 1.05)
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := _mat(BUBBLE_SHADER, color)
	mi.material_override = mat
	owner.add_child(mi)
	mi.position = Vector3.UP * 1.0
	mi.scale = Vector3.ONE * 0.3
	var t := mi.create_tween()
	t.tween_property(mi, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func _pop_bubble(bubble: MeshInstance3D) -> void:
	bubble.set_meta("popping", true)
	var mat := bubble.material_override as ShaderMaterial
	var t := bubble.create_tween().set_parallel()
	t.tween_property(bubble, "scale", Vector3.ONE * 1.25, 0.25)
	if mat:
		t.tween_method(func(v: float) -> void: mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.25)
	t.chain().tween_callback(bubble.queue_free)
