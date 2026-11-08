class_name WeaponModels
extends RefCounted
## Simple stand-in models for weapons and rigid armour until real models are made in
## Blender. Weapons are built with the grip at the origin and the blade along +Y.
## Items refer to these as "builtin:<name>" (see build()).

const BUILTIN := ["sword", "bow", "shield", "helm", "pauldron_left", "pauldron_right"]


## An item model: "builtin:<name>" for the stand-ins here, or a .glb/.tscn/.scn path.
static func build(model: String) -> Node3D:
	if model.begins_with("builtin:"):
		match model.trim_prefix("builtin:"):
			"sword": return sword()
			"bow": return bow()
			"shield": return shield()
			"helm": return helm()
			"pauldron_left": return pauldron(true)
			"pauldron_right": return pauldron(false)
			"hair_long": return hair_long()
			"hair_ponytail": return hair_ponytail()
			"hair_bun": return hair_bun()
		push_warning("WeaponModels: no builtin model '%s'" % model)
		return null
	if model.is_empty() or not ResourceLoader.exists(model):
		return null
	var scene := load(model) as PackedScene
	return scene.instantiate() as Node3D if scene else null


static func sword() -> Node3D:
	var root := Node3D.new()
	root.name = "Sword"
	var steel := _material(Color(0.78, 0.8, 0.84), 0.75, 0.3)
	var leather := _material(Color(0.3, 0.18, 0.1), 0.0, 0.8)
	var brass := _material(Color(0.75, 0.6, 0.3), 0.8, 0.35)
	_box(root, Vector3(0.055, 0.78, 0.012), Vector3(0, 0.5, 0), steel)  # blade
	_box(root, Vector3(0.025, 0.06, 0.01), Vector3(0, 0.92, 0), steel, 45.0)  # tip
	_box(root, Vector3(0.2, 0.03, 0.04), Vector3(0, 0.1, 0), brass)  # crossguard
	_box(root, Vector3(0.032, 0.17, 0.032), Vector3(0, 0.0, 0), leather)  # grip
	_box(root, Vector3(0.05, 0.04, 0.05), Vector3(0, -0.1, 0), brass)  # pommel
	return root


## Longbow held at the grip: limbs along +/-Y, tips curving back toward the archer (-Z),
## string across the back. Hold it with +Z pointing at the target.
static func bow() -> Node3D:
	var root := Node3D.new()
	root.name = "Bow"
	var wood := _material(Color(0.45, 0.28, 0.14), 0.0, 0.7)
	var grip := _material(Color(0.25, 0.15, 0.08), 0.0, 0.9)
	var string_mat := _material(Color(0.9, 0.88, 0.8), 0.0, 1.0)
	_box(root, Vector3(0.035, 0.16, 0.04), Vector3.ZERO, grip)
	for side in [1.0, -1.0]:
		# Each limb in two straight pieces bending back towards the archer.
		_limb(root, Vector3(0, 0.08 * side, 0), Vector3(0, 0.4 * side, -0.06), 0.032, wood)
		_limb(root, Vector3(0, 0.4 * side, -0.06), Vector3(0, 0.68 * side, -0.17), 0.024, wood)
	_limb(root, Vector3(0, 0.68, -0.17), Vector3(0, -0.68, -0.17), 0.006, string_mat)
	return root


## Round wooden shield with an iron rim and boss, face towards +Z, origin at the back
## (where the arm goes).
static func shield() -> Node3D:
	var root := Node3D.new()
	root.name = "Shield"
	var wood := _material(Color(0.55, 0.33, 0.16), 0.0, 0.8)
	var iron := _material(Color(0.42, 0.44, 0.48), 0.7, 0.4)
	var paint := _material(Color(0.62, 0.14, 0.12), 0.0, 0.7)
	_disc(root, 0.3, 0.03, Vector3(0, 0, 0.05), wood)
	_disc(root, 0.31, 0.022, Vector3(0, 0, 0.05), iron, 0.27)  # rim ring
	_disc(root, 0.16, 0.034, Vector3(0, 0, 0.052), paint)
	_disc(root, 0.06, 0.06, Vector3(0, 0, 0.075), iron)  # boss
	return root


## Open-faced iron helm with a nose guard. Origin at the centre of the head.
static func helm() -> Node3D:
	var root := Node3D.new()
	root.name = "Helm"
	var iron := _material(Color(0.5, 0.52, 0.56), 0.75, 0.35)
	var band := _material(Color(0.62, 0.48, 0.24), 0.8, 0.35)
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.135
	sphere.height = 0.15
	sphere.is_hemisphere = true
	sphere.radial_segments = 12
	sphere.rings = 5
	sphere.material = iron
	dome.mesh = sphere
	dome.position = Vector3(0, 0.0, 0)
	root.add_child(dome)
	var rim := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.142
	cyl.height = 0.035
	cyl.radial_segments = 12
	cyl.material = band
	rim.mesh = cyl
	rim.position = Vector3(0, 0.01, 0)
	root.add_child(rim)
	_box(root, Vector3(0.025, 0.09, 0.02), Vector3(0, -0.03, -0.14), iron)  # nose guard
	_box(root, Vector3(0.02, 0.035, 0.24), Vector3(0, 0.135, 0), band)  # crest
	return root


# --- Hair pieces (rigid, on the head bone; tinted by the hair colour) ------------

## Long hair falling behind the head to the shoulders. Origin at the middle of the head;
## the back of the head is +Z.
static func hair_long() -> Node3D:
	var root := Node3D.new()
	root.name = "HairLong"
	var mat := _hair_material()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 16
	var rows := 6
	for i in segs:
		for j in rows:
			var quad := []
			for c: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var a := deg_to_rad(lerpf(-105.0, 105.0, float(i + c.x) / segs))
				var t := float(j + c.y) / rows
				var bottom := -0.31 - (0.035 if (i + c.x) % 2 == 1 else 0.0)  # ragged ends
				var y := lerpf(0.1, bottom, t)
				# Starts under the scalp, falls past the ears and spreads a little over the back.
				var r := lerpf(0.1, 0.122, sqrt(t))
				var back := 0.045 * t * t
				var narrow := lerpf(1.0, 0.82, t)
				quad.append(Vector3(sin(a) * r * narrow, y, cos(a) * r + back))
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(quad[k])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	root.add_child(mi)
	return root


## A ponytail: a band and a tapering tail. Origin where it leaves the back of the head.
static func hair_ponytail() -> Node3D:
	var root := Node3D.new()
	root.name = "HairPonytail"
	var mat := _hair_material()
	var points := [Vector3(0, 0, 0), Vector3(0, -0.02, 0.06), Vector3(0, -0.11, 0.09), Vector3(0, -0.22, 0.085), Vector3(0, -0.3, 0.07)]
	var radii := [0.03, 0.032, 0.027, 0.018, 0.006]
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var cyl := CylinderMesh.new()
		cyl.top_radius = radii[i]
		cyl.bottom_radius = radii[i + 1]
		cyl.height = a.distance_to(b)
		cyl.radial_segments = 8
		cyl.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = mat
		# Cylinder runs along Y; point its top at a, bottom at b.
		var dir := (a - b).normalized()
		var side := dir.cross(Vector3.RIGHT).normalized()
		mi.transform = Transform3D(Basis(dir.cross(side), dir, side).orthonormalized(), (a + b) * 0.5)
		root.add_child(mi)
	return root


## A bun on the back of the head. Origin at its centre.
static func hair_bun() -> Node3D:
	var root := Node3D.new()
	root.name = "HairBun"
	var sphere := SphereMesh.new()
	sphere.radius = 0.052
	sphere.height = 0.09
	sphere.radial_segments = 10
	sphere.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = _hair_material()
	mi.rotation_degrees.x = 60.0
	root.add_child(mi)
	return root


static func _hair_material() -> StandardMaterial3D:
	var m := _material(Color(0.35, 0.22, 0.12), 0.0, 0.9)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## One shoulder plate, origin at the top of the shoulder.
static func pauldron(left: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "PauldronL" if left else "PauldronR"
	var iron := _material(Color(0.48, 0.5, 0.54), 0.75, 0.35)
	var edge := _material(Color(0.62, 0.48, 0.24), 0.8, 0.35)
	var side := 1.0 if left else -1.0
	for i in 2:
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.1 - i * 0.012
		sphere.height = 0.1 - i * 0.012
		sphere.is_hemisphere = true
		sphere.radial_segments = 10
		sphere.rings = 4
		sphere.material = iron if i == 0 else edge
		mi.mesh = sphere
		mi.scale = Vector3(1.0, 0.55, 0.9)
		mi.position = Vector3(side * i * 0.045, -i * 0.035, 0)
		mi.rotation_degrees.z = side * (20.0 + i * 15.0)
		root.add_child(mi)
	return root


static func _disc(parent: Node3D, radius: float, thickness: float, pos: Vector3, mat: Material, inner := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var mesh: Mesh
	if inner > 0.0:
		var torus := TorusMesh.new()
		torus.inner_radius = inner
		torus.outer_radius = radius
		torus.rings = 24
		torus.ring_segments = 6
		torus.material = mat
		mesh = torus
		mi.scale = Vector3(1, thickness / (radius - inner), 1)
	else:
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = thickness
		cyl.radial_segments = 20
		cyl.material = mat
		mesh = cyl
	mi.mesh = mesh
	mi.rotation_degrees.x = 90.0  # flat side facing +Z
	mi.position = pos
	parent.add_child(mi)


## Arrow along -Z (tip at the front), 0.75 m long, origin at its middle.
static func arrow() -> Node3D:
	var root := Node3D.new()
	root.name = "Arrow"
	_box(root, Vector3(0.015, 0.015, 0.7), Vector3.ZERO, _material(Color(0.55, 0.4, 0.22), 0.0, 0.8))
	_box(root, Vector3(0.03, 0.012, 0.07), Vector3(0, 0, -0.37), _material(Color(0.6, 0.62, 0.66), 0.8, 0.3), 45.0)
	_box(root, Vector3(0.05, 0.004, 0.1), Vector3(0, 0, 0.3), _material(Color(0.85, 0.85, 0.8), 0.0, 1.0))
	_box(root, Vector3(0.004, 0.05, 0.1), Vector3(0, 0, 0.3), _material(Color(0.85, 0.85, 0.8), 0.0, 1.0))
	return root


## A box stretched between two points.
static func _limb(parent: Node3D, a: Vector3, b: Vector3, thickness: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, a.distance_to(b), thickness)
	mesh.material = mat
	mi.mesh = mesh
	var up := (b - a).normalized()
	var side := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var z := side.cross(up).normalized()
	mi.transform = Transform3D(Basis(up.cross(z).normalized(), up, z), (a + b) * 0.5)
	parent.add_child(mi)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, roll := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees.z = roll
	parent.add_child(mi)


static func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m
