class_name BeastModel
extends Node3D
## A creature body built from simple shapes and animated in code (no skeleton or clips):
## "bat" (a small flyer) and "dragon" (a boss with neck, jaw, four legs, wings and tail).
## Beast sets the animation inputs each frame: flapping, moving, pose, look_point.
## Faces -Z like the other models.

var kind := "bat"
var color := Color(0.35, 0.25, 0.22)

## Animation inputs.
var flapping := true
var flap_speed := 1.0
var moving := 0.0         # 0..1 how much the legs walk
var pose := ""            # "", "bite", "breath", "tail", "roar", "hurt", "dead", "swoop"
var pose_t := 0.0         # 0..1 through the pose
var look_point := Vector3.INF

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


static func create(body_kind: String, body_color: Color, body_scale := 1.0) -> BeastModel:
	var m := BeastModel.new()
	m.kind = body_kind
	m.color = body_color
	m.name = "BeastModel"
	m.scale = Vector3.ONE * body_scale
	if body_kind == "dragon":
		m._build_dragon()
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


# --- Animation ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
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
