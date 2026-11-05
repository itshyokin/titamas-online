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
