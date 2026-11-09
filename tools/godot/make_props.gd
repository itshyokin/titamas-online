extends SceneTree
## Builds simple low-poly props into assets/props/*.glb (Z-up, like the Blender exports):
##   birch_tree, birch_tree_tall, birch_tree_small — white bark with dark marks, light
##     leaf clumps (materials "bark" and "leaves", so PropLibrary gives them a trunk
##     collider and the wind sway)
##   bush_round, bush_wide, bush_berry — leaf clumps (no collision: "bush" isn't solid)
##   stone_small_1..3 — little rocks (no collision: "small")
## Run: godot --headless --path . --script res://tools/godot/make_props.gd
## Re-running overwrites them (different random shapes only if SEED changes).

const OUT := "res://assets/props/"
const SEED := 7

var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	rng.seed = SEED
	var bark := _material("bark", _bark_texture(), Color(1, 1, 1))
	var leaves := _material("leaves", _noise_texture(Color(0.62, 0.78, 0.32), Color(0.42, 0.62, 0.2)), Color(1, 1, 1))
	var leaves_dark := _material("leaves", _noise_texture(Color(0.32, 0.52, 0.2), Color(0.2, 0.38, 0.14)), Color(1, 1, 1))
	var berries := _material("berries", null, Color(0.75, 0.12, 0.2))
	var stone := _material("stone", _noise_texture(Color(0.58, 0.57, 0.55), Color(0.42, 0.41, 0.4)), Color(1, 1, 1))
	_save("birch_tree", _birch(7.5, 0.16, 5, bark, leaves))
	_save("birch_tree_tall", _birch(10.0, 0.19, 7, bark, leaves))
	_save("birch_tree_small", _birch(4.5, 0.1, 3, bark, leaves))
	_save("bush_round", _bush(0.8, 4, leaves_dark, null))
	_save("bush_wide", _bush(1.2, 6, leaves_dark, null))
	_save("bush_berry", _bush(0.7, 4, leaves_dark, berries))
	for i in 3:
		_save("stone_small_%d" % (i + 1), _stone(0.25 + i * 0.12, stone))
	quit()


# --- Shapes (built Y-up, turned Z-up when saved) ------------------------------------

func _birch(height: float, radius: float, clumps: int, bark: Material, leaves: Material) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A slightly bent trunk of stacked 7-sided rings.
	var segs := 6
	var sides := 7
	var lean := Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))
	var rings: Array = []
	for i in segs + 1:
		var t := float(i) / segs
		var c := Vector3(lean.x * t * t, height * 0.82 * t, lean.y * t * t)
		var r := radius * lerpf(1.0, 0.45, t)
		var ring: Array[Vector3] = []
		for k in sides:
			var a := TAU * k / sides
			ring.append(c + Vector3(cos(a) * r, 0, sin(a) * r))
		rings.append(ring)
	for i in segs:
		for k in sides:
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i][(k + 1) % sides]
			var c2: Vector3 = rings[i + 1][(k + 1) % sides]
			var d: Vector3 = rings[i + 1][k]
			var u0 := float(k) / sides
			var u1 := float(k + 1) / sides
			var v0 := float(i) / segs * 3.0
			var v1 := float(i + 1) / segs * 3.0
			var mid := Vector3(lean.x * pow((i + 0.5) / segs, 2.0), height * 0.82 * (i + 0.5) / segs, lean.y * pow((i + 0.5) / segs, 2.0))
			_quad(st, a, b, c2, d, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1), mid)
	# A couple of short branches.
	for b in 3:
		var y := height * rng.randf_range(0.45, 0.75)
		var dir := Vector3(rng.randf_range(-1, 1), 0.9, rng.randf_range(-1, 1)).normalized()
		_cylinder(st, Vector3(lean.x * 0.3, y, lean.y * 0.3), Vector3(lean.x * 0.3, y, lean.y * 0.3) + dir * height * 0.18, radius * 0.35, radius * 0.15, 5)
	_add_mesh(root, st, bark)
	# Leaf clumps around the top half.
	var lst := SurfaceTool.new()
	lst.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Birches are airy: many small clumps hanging along the upper trunk.
	for i in clumps * 3:
		var t := rng.randf_range(0.0, 1.0)
		var around := rng.randf() * TAU
		var spread := height * 0.13 * (1.15 - t * 0.8)
		var y := height * (0.42 + t * 0.52)
		var k := y / (height * 0.82)
		var c := Vector3(lean.x * k * k + cos(around) * spread, y, lean.y * k * k + sin(around) * spread)
		var s := height * rng.randf_range(0.055, 0.085)
		_blob(lst, c, Vector3(s, s * 1.4, s))
	_add_mesh(root, lst, leaves)
	return root


func _bush(size: float, clumps: int, leaves: Material, berries: Material) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in clumps:
		var a := rng.randf() * TAU
		var r := size * rng.randf_range(0.0, 0.55)
		var s := size * rng.randf_range(0.45, 0.7)
		_blob(st, Vector3(cos(a) * r, s * 0.7, sin(a) * r), Vector3(s, s * 0.8, s))
	_add_mesh(root, st, leaves)
	if berries:
		var bst := SurfaceTool.new()
		bst.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 14:
			var a := rng.randf() * TAU
			var y := size * rng.randf_range(0.3, 1.0)
			var r := size * 0.75 * sin(acos(clampf((y - size * 0.6) / size, -1, 1)))
			_blob(bst, Vector3(cos(a) * r, y, sin(a) * r), Vector3.ONE * size * 0.06, 0)
		_add_mesh(root, bst, berries)
	return root


func _stone(size: float, mat: Material) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_blob(st, Vector3(0, size * 0.3, 0), Vector3(size, size * 0.6, size * rng.randf_range(0.7, 1.0)), 1, 0.3)
	_add_mesh(root, st, mat)
	return root


# --- Mesh helpers ---------------------------------------------------------------------

## A lumpy low-poly ball (icosphere, `detail` subdivisions) scaled to `radii`.
func _blob(st: SurfaceTool, center: Vector3, radii: Vector3, detail := 1, jitter := 0.18) -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for i in verts.size():
		verts[i] = verts[i].normalized()
	for d in detail:
		var mid := {}
		var nf := []
		var mp := func(a: int, b: int) -> int:
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not mid.has(key):
				verts.append(((verts[a] + verts[b]) * 0.5).normalized())
				mid[key] = verts.size() - 1
			return mid[key]
		for f: Array in faces:
			var ab: int = mp.call(f[0], f[1])
			var bc: int = mp.call(f[1], f[2])
			var ca: int = mp.call(f[2], f[0])
			nf.append_array([[f[0], ab, ca], [f[1], bc, ab], [f[2], ca, bc], [ab, bc, ca]])
		faces = nf
	var out: Array[Vector3] = []
	for v in verts:
		out.append(center + v * radii * (1.0 + rng.randf_range(-jitter, jitter)))
	for f: Array in faces:
		var a: Vector3 = out[f[0]]
		var b: Vector3 = out[f[1]]
		var c: Vector3 = out[f[2]]
		_tri(st, a, b, c, Vector2(a.x + a.z, a.y), Vector2(b.x + b.z, b.y), Vector2(c.x + c.z, c.y), center)


func _cylinder(st: SurfaceTool, from: Vector3, to: Vector3, r0: float, r1: float, sides: int) -> void:
	var axis := (to - from).normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := axis.cross(side)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p0 := from + (side * cos(a0) + up * sin(a0)) * r0
		var p1 := from + (side * cos(a1) + up * sin(a1)) * r0
		var q1 := to + (side * cos(a1) + up * sin(a1)) * r1
		var q0 := to + (side * cos(a0) + up * sin(a0)) * r1
		_quad(st, p0, p1, q1, q0, Vector2(0, 0), Vector2(0.2, 0), Vector2(0.2, 0.5), Vector2(0, 0.5), (from + to) * 0.5)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, inside := Vector3(INF, 0, 0)) -> void:
	_tri(st, a, c, b, ua, uc, ub, inside)
	_tri(st, a, d, c, ua, ud, uc, inside)


## One flat-shaded triangle facing away from `inside` (its own normal; Godot's front
## faces wind clockwise).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, inside := Vector3(INF, 0, 0)) -> void:
	var n := (b - a).cross(c - a).normalized()
	if inside.x != INF and n.dot((a + b + c) / 3.0 - inside) < 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
		n = -n
	for p: Array in [[a, ua], [c, uc], [b, ub]]:
		st.set_normal(n)
		st.set_uv(p[1])
		st.add_vertex(p[0])


func _add_mesh(root: Node3D, st: SurfaceTool, mat: Material) -> void:
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	mesh.surface_set_name(0, mat.resource_name)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = mat.resource_name
	root.add_child(mi)
	mi.owner = root


func _material(mat_name: String, tex: Texture2D, color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	m.albedo_color = color
	if tex:
		m.albedo_texture = tex
	m.roughness = 0.9
	return m


func _bark_texture() -> ImageTexture:
	var img := Image.create(32, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.93, 0.92, 0.88))
	for y in 64:
		for x in 32:
			if rng.randf() < 0.06:
				img.set_pixel(x, y, Color(0.82, 0.8, 0.76))
	# Dark horizontal marks (lenticels), the birch look.
	for i in 26:
		var y := rng.randi_range(0, 63)
		var x0 := rng.randi_range(0, 31)
		var w := rng.randi_range(2, 9)
		for x in w:
			img.set_pixel((x0 + x) % 32, y, Color(0.12, 0.11, 0.1))
			if rng.randf() < 0.5:
				img.set_pixel((x0 + x) % 32, mini(y + 1, 63), Color(0.2, 0.19, 0.17))
	return ImageTexture.create_from_image(img)


func _noise_texture(a: Color, b: Color) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		for x in 32:
			img.set_pixel(x, y, a.lerp(b, rng.randf() * rng.randf() * 1.6))
	return ImageTexture.create_from_image(img)


func _save(prop_name: String, root: Node3D) -> void:
	root.name = prop_name
	# Props are kept Z-up (like the level exports): turn the geometry so +Y becomes +Z.
	var holder := Node3D.new()
	holder.name = prop_name
	var z_up := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
	for c in root.get_children():
		var mi := c as MeshInstance3D
		var src := mi.mesh as ArrayMesh
		var out := ArrayMesh.new()
		for s in src.get_surface_count():
			var arrays := src.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in v.size():
				v[i] = z_up * v[i]
				n[i] = z_up * n[i]
			arrays[Mesh.ARRAY_VERTEX] = v
			arrays[Mesh.ARRAY_NORMAL] = n
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(s, src.surface_get_material(s))
			out.surface_set_name(s, src.surface_get_name(s))
		var copy := MeshInstance3D.new()
		copy.name = mi.name
		copy.mesh = out
		holder.add_child(copy)
		copy.owner = holder
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(holder, state)
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(OUT + prop_name + ".glb"))
	print("%s: %s" % [prop_name, error_string(err)])
	holder.free()
	root.free()
