class_name WeaponModels
extends RefCounted
## Simple stand-in weapon meshes until real models are made in Blender.
## Each is built with the grip at the origin and the blade along +Y.


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
