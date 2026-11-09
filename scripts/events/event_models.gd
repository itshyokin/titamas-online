class_name EventModels
extends RefCounted
## Stand-in models for events ("builtin:<name>" as a page's model) until there's art:
## chest, chest_open, sign, standing_stone, crate, barrel, orb, lever, lever_on.

const NAMES := ["chest", "chest_open", "sign", "standing_stone", "crate", "barrel", "orb", "lever", "lever_on"]


static func make(model_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var wood := _mat(Color(0.5, 0.3, 0.16), 0.9)
	var dark_wood := _mat(Color(0.32, 0.2, 0.11), 0.9)
	var metal := _mat(Color(0.75, 0.62, 0.3), 0.35, 0.8)
	var stone := _mat(Color(0.48, 0.5, 0.52), 1.0)
	match model_name:
		"chest", "chest_open":
			_box(root, Vector3(1.0, 0.5, 0.6), Vector3(0, 0.25, 0), wood)
			_box(root, Vector3(1.04, 0.06, 0.64), Vector3(0, 0.5, 0), metal)
			var lid := Node3D.new()
			lid.position = Vector3(0, 0.5, -0.3)
			root.add_child(lid)
			_box(lid, Vector3(1.02, 0.18, 0.62), Vector3(0, 0.09, 0.31), wood)
			_box(lid, Vector3(0.12, 0.14, 0.04), Vector3(0, -0.04, 0.62), metal)
			if model_name == "chest_open":
				lid.rotation.x = -deg_to_rad(105.0)
		"sign":
			_box(root, Vector3(0.12, 1.3, 0.12), Vector3(0, 0.65, 0), dark_wood)
			_box(root, Vector3(0.9, 0.5, 0.06), Vector3(0, 1.1, 0.07), wood)
		"standing_stone":
			var s := _box(root, Vector3(0.7, 2.0, 0.45), Vector3(0, 1.0, 0), stone)
			s.rotation.z = deg_to_rad(3.0)
			var rune := _box(root, Vector3(0.25, 0.4, 0.02), Vector3(0.03, 1.2, 0.235), _glow(Color(0.4, 0.8, 1.0)))
			rune.rotation.z = s.rotation.z
		"crate":
			_box(root, Vector3(0.8, 0.8, 0.8), Vector3(0, 0.4, 0), wood)
			_box(root, Vector3(0.84, 0.1, 0.84), Vector3(0, 0.75, 0), dark_wood)
			_box(root, Vector3(0.84, 0.1, 0.84), Vector3(0, 0.05, 0), dark_wood)
		"barrel":
			var mi := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.33
			cyl.bottom_radius = 0.33
			cyl.height = 0.95
			cyl.radial_segments = 14
			mi.mesh = cyl
			mi.material_override = wood
			mi.position.y = 0.475
			root.add_child(mi)
			for y in [0.15, 0.8]:
				var band := MeshInstance3D.new()
				var c := CylinderMesh.new()
				c.top_radius = 0.345
				c.bottom_radius = 0.345
				c.height = 0.06
				c.radial_segments = 14
				band.mesh = c
				band.material_override = dark_wood
				band.position.y = y
				root.add_child(band)
		"orb":
			_box(root, Vector3(0.4, 0.8, 0.4), Vector3(0, 0.4, 0), stone)
			var mi := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.25
			sphere.height = 0.5
			mi.mesh = sphere
			mi.material_override = _glow(Color(0.5, 0.75, 1.0))
			mi.position.y = 1.1
			root.add_child(mi)
			var light := OmniLight3D.new()
			light.light_color = Color(0.5, 0.75, 1.0)
			light.light_energy = 0.8
			light.omni_range = 3.0
			light.position.y = 1.1
			root.add_child(light)
		"lever", "lever_on":
			_box(root, Vector3(0.5, 0.25, 0.3), Vector3(0, 0.125, 0), stone)
			var arm := Node3D.new()
			arm.position = Vector3(0, 0.25, 0)
			arm.rotation.x = deg_to_rad(35.0 if model_name == "lever" else -35.0)
			root.add_child(arm)
			_box(arm, Vector3(0.06, 0.6, 0.06), Vector3(0, 0.3, 0), dark_wood)
			_box(arm, Vector3(0.12, 0.12, 0.12), Vector3(0, 0.6, 0), metal)
		_:
			push_warning("EventModels: no built-in '%s' (%s)" % [model_name, ", ".join(NAMES)])
			root.free()
			return null
	return root


static func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = at
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _mat(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


static func _glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.0
	return m
