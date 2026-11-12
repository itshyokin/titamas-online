class_name BeastModel
extends Node3D
## A creature body built from simple shapes and animated in code (no skeleton or clips):
## "bat" (a small flyer), "dragon" (a boss with neck, jaw, four legs, wings and tail) and
## "troll" (a hunched giant on two legs with long arms: throws rocks, smashes the ground)
## and "golem" (blocky stone with club hands, same joints and poses as the troll; `gold`:
## gilded with glowing veins and a pulsing light, "explode" pose = trembling, arms wide).
## Beast sets the animation inputs each frame: flapping, moving, pose, look_point.
## Faces -Z like the other models.

var kind := "bat"
var color := Color(0.35, 0.25, 0.22)

## Animation inputs.
var flapping := true
var flap_speed := 1.0
var moving := 0.0         # 0..1 how much the legs walk
var pose := ""            # "", "bite", "breath", "tail", "roar", "hurt", "dead", "swoop", "throw", "smash", "explode"
var pose_t := 0.0         # 0..1 through the pose
var look_point := Vector3.INF
## Troll: where in its pose (0..1) the rock leaves the hand / the fists hit the ground.
var release_at := 0.68
var slam_at := 0.55
## Troll: a rock in the right hand (picked up during "throw").
var holding_rock := false
## Troll: the right hand (where a thrown rock starts) and one stride each time `steps` goes up.
var hand_r: Node3D
var steps := 0

var mouth: Node3D          # where breath and fireballs come from
var head: Node3D
var _jaw: Node3D
var _wings: Array[Node3D] = []
var _tail: Array[Node3D] = []
var _neck: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _body: Node3D
var _t := 0.0
var _flap := 0.0
var _walk := 0.0
var _dead := 0.0
# Troll parts.
var _torso: Node3D
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _held: MeshInstance3D
var _last_step := 0
var _base_y := 2.2         # body height when standing (troll 2.2, golem 2.0)
# Golem: gilded variant's glow (veins) and light.
var gold := false
var _glow_mat: StandardMaterial3D
var _aura: OmniLight3D


static func create(body_kind: String, body_color: Color, body_scale := 1.0, gilded := false) -> BeastModel:
	var m := BeastModel.new()
	m.kind = body_kind
	m.color = body_color
	m.gold = gilded
	m.name = "BeastModel"
	m.scale = Vector3.ONE * body_scale
	if body_kind == "dragon":
		m._build_dragon()
	elif body_kind == "troll":
		m._build_troll()
	elif body_kind == "golem":
		m._build_golem()
	else:
		m._build_bat()
	return m


# --- Building -----------------------------------------------------------------------

func _mat(c: Color, glow := false, two_sided := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _pivot(parent: Node3D, pos: Vector3, n := "") -> Node3D:
	var p := Node3D.new()
	if n != "":
		p.name = n
	p.position = pos
	parent.add_child(p)
	return p


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = 12
	c.rings = 4
	return c


func _cone(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## A bat-like wing membrane in the pivot's space (+X outward, +Z back), `side` -1 mirrors it.
func _wing_mesh(span: float, depth: float, side: float) -> ArrayMesh:
	var o := Vector3.ZERO
	var e := Vector3(span * 0.45 * side, span * 0.08, -depth * 0.12)
	var t := Vector3(span * side, 0.0, depth * 0.25)
	var f1 := Vector3(span * 0.78 * side, -span * 0.02, depth * 0.8)
	var f2 := Vector3(span * 0.48 * side, 0.0, depth * 1.0)
	var r := Vector3(0.0, 0.0, depth * 0.95)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in [[o, e, f2], [e, t, f1], [e, f1, f2], [o, f2, r]]:
		for v: Vector3 in tri:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _add_wing(at: Vector3, span: float, depth: float, side: float, skin: Material, bone: Material) -> void:
	var p := _pivot(self, at, "Wing" + ("L" if side < 0.0 else "R"))
	_part(p, _wing_mesh(span, depth, side), Vector3.ZERO, skin)
	# Arm bones along the leading edge.
	var e := Vector3(span * 0.45 * side, span * 0.08, -depth * 0.12)
	var t := Vector3(span * side, 0.0, depth * 0.25)
	for seg in [[Vector3.ZERO, e], [e, t]]:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var bar := _part(p, _box(Vector3(span * 0.04, span * 0.04, a.distance_to(b))), (a + b) * 0.5, bone)
		bar.look_at_from_position(bar.position, b, Vector3.UP)
		bar.position = (a + b) * 0.5
	_wings.append(p)


func _build_bat() -> void:
	var fur := _mat(color)
	var skin := _mat(color.darkened(0.35), false, true)
	var eye := _mat(Color(1.0, 0.25, 0.15), true)
	_body = _pivot(self, Vector3.ZERO, "Body")
	_part(_body, _sphere(0.2), Vector3.ZERO, fur, Vector3.ZERO, Vector3(0.9, 0.85, 1.15))
	head = _pivot(_body, Vector3(0, 0.06, -0.24), "Head")
	_part(head, _sphere(0.13), Vector3.ZERO, fur)
	for s in [-1.0, 1.0]:
		_part(head, _cone(0.05, 0.16), Vector3(0.07 * s, 0.13, 0.02), fur, Vector3(0, 0, -0.35 * s))
		_part(head, _sphere(0.025), Vector3(0.05 * s, 0.03, -0.11), eye)
	_part(head, _cone(0.025, 0.05), Vector3(0.03, -0.06, -0.09), _mat(Color(0.95, 0.92, 0.85)), Vector3(PI, 0, 0))
	_part(head, _cone(0.025, 0.05), Vector3(-0.03, -0.06, -0.09), _mat(Color(0.95, 0.92, 0.85)), Vector3(PI, 0, 0))
	mouth = _pivot(head, Vector3(0, -0.03, -0.14), "Mouth")
	for s in [-1.0, 1.0]:
		_add_wing(Vector3(0.12 * s, 0.05, -0.05), 0.75, 0.4, s, skin, fur)
	for s in [-1.0, 1.0]:
		var leg := _pivot(_body, Vector3(0.07 * s, -0.12, 0.14))
		_part(leg, _box(Vector3(0.03, 0.14, 0.03)), Vector3(0, -0.07, 0), skin)
		_legs.append(leg)


func _build_dragon() -> void:
	var scale_mat := _mat(color)
	var belly := _mat(color.lightened(0.35).lerp(Color(0.85, 0.75, 0.5), 0.4))
	var skin := _mat(color.darkened(0.3), false, true)
	var horn := _mat(Color(0.88, 0.84, 0.72))
	var eye := _mat(Color(1.0, 0.8, 0.2), true)
	_body = _pivot(self, Vector3(0, 2.3, 0), "Body")
	_part(_body, _capsule(1.15, 4.6), Vector3.ZERO, scale_mat, Vector3(PI * 0.5, 0, 0), Vector3(1.0, 1.0, 0.9))
	_part(_body, _capsule(0.95, 3.6), Vector3(0, -0.4, -0.1), belly, Vector3(PI * 0.5, 0, 0), Vector3(1.0, 1.0, 0.8))
	# Back spikes.
	for i in 6:
		_part(_body, _cone(0.18, 0.55), Vector3(0, 1.1, -1.6 + i * 0.65), horn, Vector3(0.35, 0, 0))
	# Neck: a chain from the chest up and forward to the head.
	var parent := _body
	var at := Vector3(0, 0.55, -2.0)
	for i in 4:
		var n := _pivot(parent, at, "Neck%d" % i)
		var r := lerpf(0.7, 0.45, i / 3.0)
		_part(n, _sphere(r), Vector3(0, 0.25, -0.35), scale_mat, Vector3.ZERO, Vector3(1, 1, 1.3))
		_part(n, _cone(0.12, 0.4), Vector3(0, r + 0.25, -0.35), horn, Vector3(0.4, 0, 0))
		_neck.append(n)
		parent = n
		at = Vector3(0, 0.35, -0.7)
		n.rotation.x = [0.3, 0.05, -0.25, -0.35][i]
	head = _pivot(parent, Vector3(0, 0.45, -0.75), "Head")
	_part(head, _box(Vector3(0.95, 0.6, 1.3)), Vector3(0, 0.05, -0.35), scale_mat)
	_part(head, _box(Vector3(0.7, 0.35, 0.9)), Vector3(0, 0.0, -1.2), scale_mat)
	for s in [-1.0, 1.0]:
		_part(head, _cone(0.14, 1.0), Vector3(0.3 * s, 0.45, 0.25), horn, Vector3(-1.1, 0, -0.25 * s))
		_part(head, _sphere(0.09), Vector3(0.42 * s, 0.2, -0.55), eye)
		_part(head, _cone(0.06, 0.25), Vector3(0.22 * s, 0.25, -1.45), horn, Vector3(-0.4, 0, 0))
	_jaw = _pivot(head, Vector3(0, -0.22, 0.1), "Jaw")
	_part(_jaw, _box(Vector3(0.65, 0.2, 1.55)), Vector3(0, -0.08, -0.85), belly)
	for i in 4:
		for s in [-1.0, 1.0]:
			_part(_jaw, _cone(0.05, 0.16), Vector3(0.24 * s, 0.07, -1.5 + i * 0.25), horn)
	mouth = _pivot(head, Vector3(0, -0.15, -1.75), "Mouth")
	# Tail: a tapering chain out the back.
	parent = _body
	at = Vector3(0, -0.1, 2.2)
	for i in 8:
		var t := _pivot(parent, at, "Tail%d" % i)
		var r := lerpf(0.8, 0.15, i / 7.0)
		_part(t, _sphere(r), Vector3(0, 0, 0.45), scale_mat, Vector3.ZERO, Vector3(1, 0.9, 1.6))
		if i % 2 == 0:
			_part(t, _cone(r * 0.35, r * 0.9), Vector3(0, r * 0.95, 0.45), horn, Vector3(0.5, 0, 0))
		_tail.append(t)
		parent = t
		at = Vector3(0, -0.05 if i < 3 else 0.0, 0.85)
		t.rotation.x = -0.12 if i < 3 else 0.02
	_part(parent, _box(Vector3(0.9, 0.08, 0.6)), Vector3(0, 0, 0.8), horn, Vector3(0, PI * 0.25, 0))
	# Legs: hips, thighs, shins, feet with claws.
	for spot in [Vector3(-0.95, -0.4, -1.3), Vector3(0.95, -0.4, -1.3), Vector3(-0.95, -0.4, 1.3), Vector3(0.95, -0.4, 1.3)]:
		var hip := _pivot(_body, spot)
		_part(hip, _capsule(0.42, 1.4), Vector3(0, -0.5, 0), scale_mat)
		var knee := _pivot(hip, Vector3(0, -1.05, 0.1))
		_part(knee, _capsule(0.28, 1.0), Vector3(0, -0.35, 0), scale_mat)
		_part(knee, _box(Vector3(0.6, 0.18, 0.75)), Vector3(0, -0.8, -0.2), scale_mat)
		for c in 3:
			_part(knee, _cone(0.07, 0.3), Vector3(-0.2 + c * 0.2, -0.85, -0.65), horn, Vector3(-PI * 0.5, 0, 0))
		_legs.append(hip)
	# Wings.
	for s in [-1.0, 1.0]:
		_add_wing(Vector3(0.85 * s, 3.1, -0.9) - Vector3(0, 2.3, 0) + Vector3(0, 2.3, 0), 6.5, 3.8, s, skin, horn)


## A lumpy boulder (troll rocks): a low sphere squashed a little out of round.
static func rock_mesh(radius := 0.55) -> Mesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 1.7
	s.radial_segments = 7
	s.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.46, 0.43, 0.38)
	mat.roughness = 1.0
	s.material = mat
	return s


func _build_troll() -> void:
	var skin := _mat(color)
	var dark := _mat(color.darkened(0.3))
	var cloth := _mat(Color(0.36, 0.26, 0.17))
	var bone := _mat(Color(0.86, 0.82, 0.68))
	var eye := _mat(Color(1.0, 0.72, 0.2), true)
	_body = _pivot(self, Vector3(0, 2.2, 0), "Body")
	_part(_body, _sphere(0.9), Vector3.ZERO, skin, Vector3.ZERO, Vector3(1.15, 0.8, 0.95))
	_part(_body, _box(Vector3(1.5, 0.95, 0.12)), Vector3(0, -0.5, -0.82), cloth, Vector3(0.12, 0, 0))
	_part(_body, _box(Vector3(1.9, 0.22, 1.7)), Vector3(0, 0.1, 0), cloth)
	# Torso: hunched forward over the hips.
	_torso = _pivot(_body, Vector3(0, 0.45, 0), "Torso")
	_part(_torso, _sphere(1.15), Vector3(0, 0.7, -0.1), skin, Vector3.ZERO, Vector3(1.15, 1.0, 1.0))
	_part(_torso, _sphere(1.05), Vector3(0, 1.65, -0.2), skin, Vector3.ZERO, Vector3(1.35, 0.9, 1.0))
	for i in 3:
		_part(_torso, _cone(0.16, 0.45), Vector3(-0.3 + i * 0.3, 2.35, 0.45), dark, Vector3(0.9, 0, 0))
	# Head low between the shoulders, with a heavy brow, tusks and a big nose.
	head = _pivot(_torso, Vector3(0, 2.25, -0.75), "Head")
	_part(head, _sphere(0.55), Vector3.ZERO, skin, Vector3.ZERO, Vector3(1.05, 0.9, 1.0))
	_part(head, _box(Vector3(0.95, 0.2, 0.35)), Vector3(0, 0.25, -0.38), dark)
	_part(head, _cone(0.16, 0.45), Vector3(0, 0.0, -0.62), skin, Vector3(-PI * 0.5, 0, 0))
	for s in [-1.0, 1.0]:
		_part(head, _sphere(0.08), Vector3(0.22 * s, 0.12, -0.48), eye)
		_part(head, _cone(0.14, 0.5), Vector3(0.55 * s, 0.1, 0.0), skin, Vector3(0, 0, -1.3 * s))
	_jaw = _pivot(head, Vector3(0, -0.2, -0.15), "Jaw")
	_part(_jaw, _box(Vector3(0.85, 0.3, 0.6)), Vector3(0, -0.12, -0.25), skin)
	for s in [-1.0, 1.0]:
		_part(_jaw, _cone(0.07, 0.35), Vector3(0.28 * s, 0.12, -0.5), bone, Vector3(0, 0, 0.15 * s))
	mouth = _pivot(head, Vector3(0, -0.25, -0.6), "Mouth")
	# Long arms: knuckles nearly drag on the ground.
	for s in [-1.0, 1.0]:
		var sh := _pivot(_torso, Vector3(1.4 * s, 1.85, -0.15), "Shoulder" + ("L" if s < 0 else "R"))
		_part(sh, _sphere(0.55), Vector3.ZERO, skin)
		_part(sh, _capsule(0.42, 1.7), Vector3(0, -0.8, 0), skin)
		var el := _pivot(sh, Vector3(0, -1.6, 0))
		_part(el, _capsule(0.4, 1.6), Vector3(0, -0.75, 0), skin)
		_part(el, _box(Vector3(0.6, 0.3, 0.6)), Vector3(0, -0.4, 0), cloth)
		var hand := _pivot(el, Vector3(0, -1.6, 0), "Hand" + ("L" if s < 0 else "R"))
		_part(hand, _sphere(0.5), Vector3.ZERO, dark, Vector3.ZERO, Vector3(1.0, 0.9, 1.1))
		_shoulders.append(sh)
		_elbows.append(el)
		if s > 0.0:
			hand_r = hand
	_held = _part(hand_r, rock_mesh(), Vector3(0, -0.55, -0.2), null)
	_held.visible = false
	# Short, thick legs.
	for s in [-1.0, 1.0]:
		var hip := _pivot(_body, Vector3(0.62 * s, -0.3, 0))
		_part(hip, _capsule(0.52, 1.3), Vector3(0, -0.5, 0), skin)
		var knee := _pivot(hip, Vector3(0, -1.0, 0))
		_part(knee, _capsule(0.44, 0.9), Vector3(0, -0.4, 0), skin)
		_part(knee, _box(Vector3(0.8, 0.3, 1.15)), Vector3(0, -0.78, -0.2), dark)
		_legs.append(hip)
		_knees.append(knee)


## A stone golem: slabs and boulders, a small head sunk between the shoulders with a
## glowing slit, and huge club fists. Same joints as the troll so it shares its poses.
func _build_golem() -> void:
	_base_y = 2.0
	var stone := _mat(color)
	var dark := _mat(color.darkened(0.35))
	var light := _mat(color.lightened(0.15))
	_glow_mat = StandardMaterial3D.new()
	var glow_col := Color(1.0, 0.95, 0.62) if gold else Color(0.95, 0.42, 0.12)
	_glow_mat.albedo_color = glow_col
	_glow_mat.emission_enabled = true
	_glow_mat.emission = glow_col
	_glow_mat.emission_energy_multiplier = 3.0 if gold else 0.9
	if gold:
		stone.metallic = 0.6
		stone.roughness = 0.45
		light.metallic = 0.6
		light.roughness = 0.4
	_body = _pivot(self, Vector3(0, _base_y, 0), "Body")
	_part(_body, _box(Vector3(1.5, 0.7, 1.0)), Vector3(0, -0.1, 0), dark, Vector3(0, 0.1, 0))
	_torso = _pivot(_body, Vector3(0, 0.2, 0), "Torso")
	_part(_torso, _box(Vector3(1.7, 1.2, 1.2)), Vector3(0, 0.6, 0), stone, Vector3(0.05, 0, 0.04))
	_part(_torso, _box(Vector3(2.3, 1.1, 1.4)), Vector3(0, 1.55, -0.1), stone, Vector3(-0.08, 0.06, 0))
	_part(_torso, _box(Vector3(1.2, 0.8, 0.5)), Vector3(0.1, 1.6, 0.65), light, Vector3(0.2, -0.3, 0.1))
	for i in 4:  # rocks jutting from the back
		_part(_torso, _box(Vector3(0.5, 0.5, 0.5)), Vector3(-0.7 + i * 0.45, 2.15, 0.35 - (i % 2) * 0.3), dark, Vector3(0.6 * i, 0.8, 0.4))
	# Glowing seams: faint cracks on the stone one, gold veins over the gilded one.
	var veins := [[Vector3(0.3, 1.4, -0.81), Vector3(0.08, 0.9, 0.04), Vector3(0, 0, 0.5)],
		[Vector3(-0.4, 1.7, -0.81), Vector3(0.07, 0.7, 0.04), Vector3(0, 0, -0.8)],
		[Vector3(-0.1, 0.7, -0.61), Vector3(0.06, 0.6, 0.04), Vector3(0, 0, 0.3)],
		[Vector3(0.55, 0.55, -0.61), Vector3(0.5, 0.06, 0.04), Vector3(0, 0, 0.4)]]
	if gold:
		veins.append_array([[Vector3(-0.75, 1.3, -0.81), Vector3(0.6, 0.06, 0.04), Vector3(0, 0, -0.3)],
			[Vector3(0.9, 1.9, -0.81), Vector3(0.06, 0.6, 0.04), Vector3(0, 0, 0.9)],
			[Vector3(0, 2.05, -0.5), Vector3(1.4, 0.06, 0.04), Vector3(0.3, 0, 0.05)],
			[Vector3(1.16, 1.5, 0.0), Vector3(0.04, 0.7, 0.06), Vector3(0.5, 0, 0)],
			[Vector3(-1.16, 1.4, 0.1), Vector3(0.04, 0.8, 0.06), Vector3(-0.4, 0, 0)]])
	for v in veins:
		_part(_torso, _box(v[1]), v[0], _glow_mat, v[2])
	# Head: a small block low between the shoulders, a glowing slit for eyes.
	head = _pivot(_torso, Vector3(0, 2.05, -0.75), "Head")
	_part(head, _box(Vector3(0.7, 0.55, 0.65)), Vector3.ZERO, light, Vector3(0, 0.1, 0))
	_part(head, _box(Vector3(0.45, 0.07, 0.05)), Vector3(0, 0.05, -0.34), _glow_mat)
	_part(head, _box(Vector3(0.8, 0.18, 0.4)), Vector3(0, 0.3, -0.12), dark, Vector3(0.15, 0, 0))
	mouth = _pivot(head, Vector3(0, -0.1, -0.4), "Mouth")
	# Arms with club fists that hang near the ground.
	for s in [-1.0, 1.0]:
		var sh := _pivot(_torso, Vector3(1.45 * s, 1.75, -0.1), "Shoulder" + ("L" if s < 0 else "R"))
		_part(sh, _box(Vector3(0.95, 0.85, 0.95)), Vector3(0.1 * s, 0.05, 0), dark, Vector3(0.2, 0.3 * s, 0.2 * s))
		_part(sh, _box(Vector3(0.55, 1.2, 0.6)), Vector3(0, -0.75, 0), stone)
		var el := _pivot(sh, Vector3(0, -1.35, 0))
		_part(el, _sphere(0.36), Vector3.ZERO, dark)
		_part(el, _box(Vector3(0.6, 1.0, 0.65)), Vector3(0, -0.55, 0), stone, Vector3(0, 0.2 * s, 0))
		var hand := _pivot(el, Vector3(0, -1.25, 0), "Hand" + ("L" if s < 0 else "R"))
		# The club: a great knuckled block with stone knobs.
		_part(hand, _box(Vector3(1.0, 1.05, 1.0)), Vector3(0, -0.2, 0), light, Vector3(0.1, 0.35, 0.1))
		for k in 3:
			_part(hand, _box(Vector3(0.38, 0.38, 0.38)), Vector3(-0.32 + k * 0.32, -0.55, -0.42), dark, Vector3(0.5, 0.7 * k, 0.3))
		if gold:
			_part(hand, _box(Vector3(0.05, 0.9, 0.05)), Vector3(0.3 * s, -0.2, -0.51), _glow_mat, Vector3(0, 0, 0.4))
		_shoulders.append(sh)
		_elbows.append(el)
		if s > 0.0:
			hand_r = hand
	# The shard it's about to fling, held in the right fist.
	_held = _part(hand_r, GolemShard.needle_mesh(1.0, 0.13), Vector3(0, -0.85, -0.25), _mat(Color(0.7, 0.74, 0.8)), Vector3(-PI * 0.5, 0, 0))
	_held.visible = false
	# Stubby legs.
	for s in [-1.0, 1.0]:
		var hip := _pivot(_body, Vector3(0.55 * s, -0.35, 0))
		_part(hip, _box(Vector3(0.7, 1.0, 0.75)), Vector3(0, -0.45, 0), stone)
		var knee := _pivot(hip, Vector3(0, -0.85, 0))
		_part(knee, _box(Vector3(0.62, 0.7, 0.68)), Vector3(0, -0.3, 0), stone)
		_part(knee, _box(Vector3(0.85, 0.3, 1.05)), Vector3(0, -0.65, -0.15), dark)
		_legs.append(hip)
		_knees.append(knee)
	if gold:
		_aura = OmniLight3D.new()
		_aura.light_color = Color(1.0, 0.8, 0.3)
		_aura.light_energy = 1.6
		_aura.omni_range = 7.0
		_aura.position = Vector3(0, 3.2, -0.6)
		add_child(_aura)


## Eases `node`'s rotation toward `to` (x, y, z) at `rate`.
func _ease_rot(node: Node3D, to: Vector3, rate: float, delta: float) -> void:
	var k := 1.0 - exp(-rate * delta)
	node.rotation = node.rotation.lerp(to, k)


func _process_troll(delta: float) -> void:
	_walk += delta * moving * 1.3
	var phase := _walk * TAU
	var stride := int(floor(_walk * 2.0))
	if stride != _last_step:
		_last_step = stride
		if moving > 0.3:
			steps += 1
	var breathe := sin(_t * 1.4) * 0.03
	# Rest pose, walking.
	var torso := Vector3(-0.35 + breathe, 0, 0)
	var head_rot := Vector3(0.25, 0, 0)
	var body_y := _base_y + absf(sin(phase)) * 0.1 * moving + breathe
	var jaw := 0.05
	var sh := [Vector3(-sin(phase) * 0.35 * moving + 0.05, 0, -0.15), Vector3(sin(phase) * 0.35 * moving + 0.05, 0, 0.15)]
	var el := [Vector3(0.35, 0, 0), Vector3(0.35, 0, 0)]
	var legs := [Vector3(sin(phase) * 0.5 * moving, 0, 0), Vector3(-sin(phase) * 0.5 * moving, 0, 0)]
	var knees := [Vector3(maxf(0.0, -sin(phase)) * 0.7 * moving, 0, 0), Vector3(maxf(0.0, sin(phase)) * 0.7 * moving, 0, 0)]
	var rate := 8.0
	var k := pose_t
	match pose:
		"roar":
			var r := sin(clampf(k, 0.0, 1.0) * PI)
			torso.x = lerpf(torso.x, 0.15, r)
			head_rot.x = lerpf(head_rot.x, -0.35, r)
			sh[0] = Vector3(0.2, 0, -1.25 * r)
			sh[1] = Vector3(0.2, 0, 1.25 * r)
			el[0] = Vector3(0.9 * r, 0, 0)
			el[1] = Vector3(0.9 * r, 0, 0)
			jaw = 0.6 * r
		"throw":
			var rel := release_at
			if k < 0.35:
				# Stoops and reaches down for a rock.
				var a := smoothstep(0.0, 0.35, k)
				torso.x = lerpf(-0.35, -1.0, a)
				body_y -= 0.55 * a
				sh[1] = Vector3(lerpf(0.05, -0.9, a), 0, 0.2)
				el[1] = Vector3(0.15, 0, 0)
				knees[0].x = 0.5 * a
				knees[1].x = 0.5 * a
			elif k < rel:
				# Straightens up, rock raised behind the head.
				var a := smoothstep(0.35, rel, k)
				torso.x = lerpf(-1.0, 0.05, a)
				body_y -= 0.55 * (1.0 - a)
				sh[1] = Vector3(lerpf(-0.9, 3.5, a), 0, 0.25)
				el[1] = Vector3(lerpf(0.15, 0.9, a), 0, 0)
				sh[0] = Vector3(-0.6 * a, 0, -0.5 * a)
				head_rot.x = -0.1
			elif k < rel + 0.12:
				# Hurls it: the arm comes over the top.
				var a := smoothstep(rel, rel + 0.12, k)
				torso.x = lerpf(0.05, -0.75, a)
				sh[1] = Vector3(lerpf(3.5, -0.5, a), 0, 0.2)
				el[1] = Vector3(lerpf(0.9, 0.1, a), 0, 0)
				sh[0] = Vector3(-0.6 + 0.8 * a, 0, -0.5)
				rate = 30.0
			else:
				torso.x = -0.6
				sh[1] = Vector3(-0.4, 0, 0.2)
			jaw = 0.35 if k > rel - 0.1 and k < rel + 0.15 else 0.05
		"smash":
			var s := slam_at
			if k < s:
				# Both fists raised high, leaning back, trembling as it's about to come down.
				var a := smoothstep(0.0, s * 0.55, k)
				var shake := sin(_t * 40.0) * 0.05 * smoothstep(s * 0.6, s, k)
				torso.x = lerpf(-0.35, 0.18, a) + shake
				body_y += 0.25 * a
				sh[0] = Vector3(lerpf(0.05, 3.1, a), 0, lerpf(-0.15, -0.65, a))
				sh[1] = Vector3(lerpf(0.05, 3.1, a), 0, lerpf(0.15, 0.65, a))
				el[0] = Vector3(0.5 * a, 0, 0)
				el[1] = Vector3(0.5 * a, 0, 0)
				head_rot.x = -0.3 * a
				jaw = 0.45 * a
			else:
				# Down onto the ground in front, then slowly back up.
				var hold := 1.0 - smoothstep(0.85, 1.0, k)
				torso.x = lerpf(-0.35, -1.05, hold)
				body_y -= 0.7 * hold
				sh[0] = Vector3(lerpf(0.05, -1.05, hold), 0, -0.25)
				sh[1] = Vector3(lerpf(0.05, -1.05, hold), 0, 0.25)
				el[0] = Vector3(0.1, 0, 0)
				el[1] = Vector3(0.1, 0, 0)
				knees[0].x = 0.6 * hold
				knees[1].x = 0.6 * hold
				jaw = 0.3 * hold
				rate = 34.0 if k < s + 0.08 else 6.0
		"hurt":
			torso.x += sin(clampf(k, 0.0, 1.0) * PI) * 0.3
		"explode":
			# Rears back, arms flung wide, shaking harder and harder.
			var a := smoothstep(0.0, 0.3, k)
			var shake := sin(_t * 55.0) * 0.08 * k
			torso.x = lerpf(-0.35, 0.25, a) + shake
			body_y += 0.2 * a
			sh[0] = Vector3(0.3 * a, shake, -1.4 * a)
			sh[1] = Vector3(0.3 * a, -shake, 1.4 * a)
			el[0] = Vector3(0.4 * a, 0, 0)
			el[1] = Vector3(0.4 * a, 0, 0)
			head_rot.x = -0.4 * a + shake
			rate = 20.0
	# Looks toward what it's fighting.
	if look_point != Vector3.INF and head and _torso:
		var local := _torso.global_transform.affine_inverse() * look_point
		head_rot.y = clampf(atan2(-local.x, -local.z), -0.8, 0.8)
	_body.position.y = lerpf(_body.position.y, body_y, 1.0 - exp(-rate * delta))
	_ease_rot(_torso, torso, rate, delta)
	_ease_rot(head, head_rot, 8.0, delta)
	for i in 2:
		_ease_rot(_shoulders[i], sh[i], rate, delta)
		_ease_rot(_elbows[i], el[i], rate, delta)
		_ease_rot(_legs[i], legs[i], 10.0, delta)
		_ease_rot(_knees[i], knees[i], 10.0, delta)
	if _jaw:
		_jaw.rotation.x = lerp_angle(_jaw.rotation.x, jaw, 1.0 - exp(-14.0 * delta))
	_held.visible = holding_rock
	# The glow pulses; on the gilded golem faster and brighter as it's about to burst.
	if _glow_mat:
		var fuse := clampf(pose_t, 0.0, 1.0) if pose == "explode" else 0.0
		var pulse := 0.5 + 0.5 * sin(_t * lerpf(2.0, 22.0, fuse))
		var base := 3.0 if gold else 0.9
		_glow_mat.emission_energy_multiplier = 0.2 if pose == "dead" else base * (0.7 + 0.5 * pulse) + fuse * 6.0
		if _aura:
			_aura.light_energy = 0.0 if pose == "dead" else 1.2 + 0.8 * pulse + fuse * 5.0
	# Dead: topples forward onto its face.
	if pose == "dead":
		_dead = minf(_dead + delta * 0.9, 1.0)
	else:
		_dead = maxf(_dead - delta * 2.0, 0.0)
	rotation.x = -smoothstep(0.0, 1.0, _dead) * 1.35


# --- Animation ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if kind == "troll" or kind == "golem":
		_process_troll(delta)
		return
	var big := kind == "dragon"
	# Wings.
	if flapping:
		_flap += delta * flap_speed * TAU * (0.55 if big else 2.6)
	for i in _wings.size():
		var w := _wings[i]
		var side := -1.0 if i == 0 else 1.0
		var flap_z := 0.0
		var fold_y := 0.0
		if flapping and pose != "dead":
			flap_z = sin(_flap) * (0.75 if big else 0.95) + 0.1
			fold_y = 0.0
		else:
			flap_z = 0.85 if big else -1.2  # folded: raised and swept back / against the body
			fold_y = 1.15 if big else 0.6
		if pose == "roar" and big:
			flap_z = 0.7 + sin(_t * 6.0) * 0.1  # spread wide
			fold_y = 0.0
		w.rotation.z = lerp_angle(w.rotation.z, flap_z * side, 1.0 - exp(-14.0 * delta))
		w.rotation.y = lerp_angle(w.rotation.y, fold_y * -side, 1.0 - exp(-6.0 * delta))
	# Body bob while flying, breathing on the ground.
	if _body:
		var bob := sin(_flap) * (0.12 if big else 0.04) if flapping else sin(_t * 1.6) * 0.03
		var base_y := 2.3 if big else 0.0
		_body.position.y = base_y + bob
		var hurt := sin(pose_t * PI) * 0.25 if pose == "hurt" else 0.0
		_body.rotation.x = hurt + (-0.15 if pose == "swoop" else 0.0)
	# Legs.
	_walk += delta * moving * (2.2 if big else 0.0)
	for i in _legs.size():
		var phase := _walk * TAU + (PI if i in [1, 2] else 0.0)
		var tuck := 0.9 if flapping and big else 0.0
		_legs[i].rotation.x = sin(phase) * 0.45 * moving + tuck
	# Tail sways; the "tail" pose whips it round.
	for i in _tail.size():
		var sway := sin(_t * 1.3 - i * 0.55) * (0.06 + 0.05 * moving)
		if pose == "tail":
			sway += sin(pose_t * PI) * 0.22 * (1.0 + i * 0.1)
		_tail[i].rotation.y = sway
	# Neck and head: look toward look_point, lunge for a bite, rear up for breath.
	if big:
		var lunge := 0.0
		var rear := 0.0
		if pose == "bite":
			lunge = sin(clampf(pose_t * 1.4, 0.0, 1.0) * PI)
		elif pose == "breath":
			rear = sin(clampf(pose_t * 3.0, 0.0, 1.0) * PI * 0.5) * (1.0 - smoothstep(0.85, 1.0, pose_t))
		elif pose == "roar":
			rear = sin(pose_t * PI)
		var yaw := 0.0
		var pitch := 0.0
		if look_point != Vector3.INF and head:
			var local := _body.global_transform.affine_inverse() * look_point
			yaw = clampf(atan2(-local.x, -local.z), -1.0, 1.0)
			pitch = clampf(atan2(local.y - 2.0, Vector2(local.x, local.z).length()), -0.6, 0.4)
		var bases := [0.3, 0.05, -0.25, -0.35]
		for i in _neck.size():
			var n := _neck[i]
			var want_x: float = bases[i] - lunge * 0.35 + rear * (0.25 if i < 2 else -0.1) + pitch * 0.2
			n.rotation.x = lerp_angle(n.rotation.x, want_x, 1.0 - exp(-10.0 * delta))
			n.rotation.y = lerp_angle(n.rotation.y, yaw * 0.25, 1.0 - exp(-6.0 * delta))
		if _jaw:
			var open := 0.0
			match pose:
				"bite":
					open = 0.55 * (1.0 - smoothstep(0.45, 0.6, pose_t))
				"breath":
					open = 0.5 * (1.0 - smoothstep(0.9, 1.0, pose_t))
				"roar":
					open = 0.6 * sin(pose_t * PI)
				"dead":
					open = 0.3
			_jaw.rotation.x = lerp_angle(_jaw.rotation.x, open, 1.0 - exp(-14.0 * delta))
	elif head and pose == "swoop":
		head.rotation.x = -0.3
	# Dead: rolls onto its side.
	if pose == "dead":
		_dead = minf(_dead + delta * 1.2, 1.0)
	else:
		_dead = maxf(_dead - delta * 2.0, 0.0)
	rotation.z = smoothstep(0.0, 1.0, _dead) * (1.35 if big else 2.6)
	if big:
		position.y = -smoothstep(0.0, 1.0, _dead) * 1.0 * scale.y
