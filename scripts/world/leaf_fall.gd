class_name LeafFall
extends Node3D
## Leaves drifting down from the leafy trees near the player (maples, birches...), now and
## then: each spins and sways down, then lies on the ground (a decal) and fades. Hitting a
## tree shakes loose a shower of leaves and a few twigs and seeds. Made by
## AtmosphereManager; settings in data/wildlife.json "falling_leaves" (Database → Wildlife
## Settings): how often, how many, fall speed, how long they lie, and which trees drop which
## colour (prop name prefixes; dead trees drop nothing).

const FILE := "res://data/wildlife.json"
const MAX_PIECES := 160

var _cfg := {}
var _file_time := -1
var _timer := 3.0
var _last_drop := {}  # tree -> msec of its last drift
var _pieces: Array = []  # [MeshInstance3D, velocity, ground y, kind, spin]
var _tex := {}  # "leaf" / "maple" / "stick" / "seed" -> Texture2D
var _decals := false


func _ready() -> void:
	add_to_group("leaf_fall")
	_decals = String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")) != "gl_compatibility" \
		and RenderingServer.get_current_rendering_method() != "gl_compatibility"


func _settings() -> Dictionary:
	if DataFiles.modified_time(FILE) != _file_time:
		_file_time = DataFiles.modified_time(FILE)
		var d = DataFiles.read(FILE)
		_cfg = d.get("falling_leaves", {}) if d is Dictionary else {}
	return _cfg


func _process(delta: float) -> void:
	_move(delta)
	var cfg := _settings()
	if not bool(cfg.get("enabled", true)):
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = float(cfg.get("every_seconds", 6.0)) * randf_range(0.6, 1.4)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var trees := _leafy_trees(player.global_position, float(cfg.get("range", 30.0)))
	if trees.is_empty():
		return
	var gap_ms := float(cfg.get("per_tree_minutes", 3.0)) * 60000.0
	var now := Time.get_ticks_msec()
	trees.shuffle()
	for tree: Node3D in trees:
		if now - int(_last_drop.get(tree, -10000000)) < gap_ms:
			continue
		_last_drop[tree] = now
		var burst: Array = cfg.get("burst", [3, 6])
		for i in randi_range(int(burst[0]), int(burst[1])):
			_spawn(tree, "leaf", i * 0.6)
		return


## A tree was hit (by a swing): a shower of leaves, a few twigs and seeds.
func knock(collider: Node, _at := Vector3.ZERO) -> void:
	var tree := _tree_of(collider)
	if tree == null or _colour_of(tree) == Color(0, 0, 0, 0):
		return
	var k: Dictionary = _settings().get("knock", {})
	for i in int(k.get("leaves", 12)):
		_spawn(tree, "leaf", 0.0, true)
	for i in int(k.get("sticks", 2)):
		_spawn(tree, "stick", 0.0, true)
	for i in int(k.get("seeds", 2)):
		_spawn(tree, "seed", 0.0, true)


func _tree_of(collider: Node) -> Node3D:
	var walk := collider
	for i in 4:
		if walk == null:
			return null
		if walk.has_meta("prop_name") and walk is Node3D and not walk is StaticBody3D:
			return walk as Node3D
		walk = walk.get_parent()
	return null


## The leaf colour for a tree (transparent = drops no leaves).
func _colour_of(tree: Node3D) -> Color:
	var n := String(tree.get_meta("prop_name", ""))
	if n.contains("dead") or not tree.visible:
		return Color(0, 0, 0, 0)
	var trees: Dictionary = _settings().get("trees", {})
	var best := ""
	for prefix: String in trees:
		if n.begins_with(prefix) and prefix.length() > best.length():
			best = prefix
	if best == "":
		return Color(0, 0, 0, 0)
	return Color.html(String(trees[best]))


func _leafy_trees(at: Vector3, radius: float) -> Array:
	var out := []
	var streamer := get_tree().get_first_node_in_group("chunk_streamer")
	if streamer == null:
		return out
	var loaded: Dictionary = streamer.get("_loaded")
	for cell in loaded:
		var chunk := loaded[cell] as Node3D
		var holder := chunk.get_node_or_null("Props") if is_instance_valid(chunk) else null
		if holder == null:
			continue
		for prop in holder.get_children():
			var n := prop as Node3D
			if n and n.global_position.distance_to(at) < radius and _colour_of(n).a > 0.0:
				out.append(n)
	return out


## A random point among the tree's leaves (its "leaves" mesh), in world space.
func _crown_point(tree: Node3D) -> Vector3:
	for c in tree.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if String(mi.name).contains("lea") and mi.mesh:
			var box := mi.get_aabb()
			var local := box.position + Vector3(randf(), randf(), randf()) * box.size
			return mi.global_transform * local
	return tree.global_position + Vector3.UP * 4.0


func _spawn(tree: Node3D, kind: String, delay := 0.0, knocked := false) -> void:
	if _pieces.size() >= MAX_PIECES:
		return
	var cfg := _settings()
	var at := _crown_point(tree)
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 40.0, 1)
	# Not the tree's own trunk.
	var skip: Array[RID] = []
	for b in tree.find_children("*", "CollisionObject3D", true, false):
		skip.append((b as CollisionObject3D).get_rid())
	q.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var ground: float = (hit.position as Vector3).y + 0.02
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.9
	# Tiny and tumbling: lit evenly so their colour reads from both sides.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var size := 0.12
	match kind:
		"leaf":
			var maple := String(tree.get_meta("prop_name", "")).begins_with("maple")
			mat.albedo_texture = _texture("maple" if maple else "leaf")
			var c := _colour_of(tree)
			mat.albedo_color = c.lerp(c.darkened(0.3), randf() * 0.6).lerp(Color(0.8, 0.6, 0.2), randf() * 0.15)
			size = float(cfg.get("leaf_size", 0.14)) * randf_range(0.8, 1.2)
		"stick":
			mat.albedo_texture = _texture("stick")
			mat.albedo_color = Color(0.4, 0.28, 0.18)
			size = 0.22
		_:
			mat.albedo_texture = _texture("seed")
			mat.albedo_color = Color(0.5, 0.34, 0.18)
			size = 0.06
	quad.size = Vector2.ONE * size
	quad.material = mat
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = delay <= 0.0
	add_child(mi)
	mi.global_position = at
	mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	var v := Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
	if knocked:
		v += Vector3(randf_range(-1.2, 1.2), randf_range(0.2, 1.2), randf_range(-1.2, 1.2))
	_pieces.append({"node": mi, "v": v, "ground": ground, "kind": kind, "delay": delay, "phase": randf() * TAU,
		"spin": Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3)), "landed": false})


func _move(delta: float) -> void:
	var cfg := _settings()
	var fall := float(cfg.get("fall_speed", 0.7))
	var t := Time.get_ticks_msec() / 1000.0
	for p: Dictionary in _pieces.duplicate():
		var mi := p.node as MeshInstance3D
		if not is_instance_valid(mi):
			_pieces.erase(p)
			continue
		if p.landed:
			continue
		if p.delay > 0.0:
			p.delay -= delta
			mi.visible = p.delay <= 0.0
			continue
		var v: Vector3 = p.v
		if p.kind == "leaf":
			# Drift down, swaying side to side and tumbling.
			v.y = lerpf(v.y, -fall, delta * 2.0)
			v.x = lerpf(v.x, 0.0, delta * 0.5)
			v.z = lerpf(v.z, 0.0, delta * 0.5)
			var sway := Vector3(cos(t * 1.7 + p.phase), 0, sin(t * 1.3 + p.phase)) * 0.6
			mi.global_position += (v + sway) * delta
			mi.rotation += (p.spin as Vector3) * delta
		else:
			v.y -= 9.8 * delta
			mi.global_position += v * delta
			mi.rotation += (p.spin as Vector3) * delta * 2.0
		p.v = v
		if mi.global_position.y <= float(p.ground):
			_land(p)


func _land(p: Dictionary) -> void:
	p.landed = true
	var mi := p.node as MeshInstance3D
	var cfg := _settings()
	var lie := float(cfg.get("lie_seconds", 25.0)) * randf_range(0.7, 1.3)
	var fade := float(cfg.get("fade_seconds", 4.0))
	var mat := (mi.mesh as QuadMesh).material as StandardMaterial3D
	var at := Vector3(mi.global_position.x, float(p.ground), mi.global_position.z)
	var size := (mi.mesh as QuadMesh).size.x
	if _decals:
		# On the ground: a decal, so it follows the slope and bumps.
		var d := Decal.new()
		d.texture_albedo = mat.albedo_texture
		d.modulate = mat.albedo_color
		d.size = Vector3(size, 0.3, size)
		d.cull_mask = 1
		add_child(d)
		d.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU), at)
		mi.queue_free()
		_pieces.erase(p)
		var tw := d.create_tween()
		tw.tween_interval(lie)
		tw.tween_property(d, "modulate:a", 0.0, fade)
		tw.tween_callback(d.queue_free)
	else:
		# (Renderers without decals: lie flat.)
		mi.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, -PI * 0.5), at)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var tw := mi.create_tween()
		tw.tween_interval(lie)
		tw.tween_property(mat, "albedo_color:a", 0.0, fade)
		tw.tween_callback(func() -> void:
			_pieces.erase(p)
			mi.queue_free())


## Little textures drawn in code: a pointed leaf, a maple leaf, a twig, a seed.
func _texture(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var a := 0.0
			var shade := 1.0
			match kind:
				"leaf":
					# Pointed oval with a midrib.
					var w := 0.5 * (1.0 - v * v) * (1.0 - 0.3 * v)
					a = 1.0 if absf(u) < w and v > -0.95 else 0.0
					shade = 0.75 if absf(u) < 0.04 else 1.0 - absf(u) * 0.25
				"maple":
					# Five-lobed star.
					var ang := atan2(u, -v)
					var r := sqrt(u * u + v * v)
					var lobe := 0.55 + 0.4 * absf(cos(ang * 2.5))
					a = 1.0 if r < lobe and v < 0.85 else 0.0
					if absf(u) < 0.05 and v > 0.4:
						a = 1.0  # stem
					shade = 1.0 - r * 0.3
				"stick":
					var along := (u + v) * 0.7071
					var across := (u - v) * 0.7071
					a = 1.0 if absf(across) < 0.07 and absf(along) < 0.9 else 0.0
					if absf(along - 0.3) < 0.25 and absf(across - (along - 0.3) * 0.6) < 0.05:
						a = 1.0  # a little fork
					shade = 1.0 - absf(across) * 3.0
				_:
					a = 1.0 if (u * u) / 0.45 + (v * v) / 0.7 < 1.0 else 0.0
					shade = 1.0 if v > -0.4 else 0.6  # cap
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	var tex := ImageTexture.create_from_image(img)
	_tex[kind] = tex
	return tex
