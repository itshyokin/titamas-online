class_name SitPose
extends SkeletonModifier3D
## Sitting, made in code on top of whatever clip plays (there's no sitting clip): the hips
## drop onto the seat and back, thighs forward, shins down, then a resting activity for the
## arms and head. CharacterModel.sit_pose() adds it to the skeleton (before HeadLook).
## Set `sitting` (eases in and out), `forward` (world facing), `seat_drop` (how far the hips
## go down, m) and `activity`:
##   relax   hands on the knees            warm    hands held out to the fire
##   read    a book held up, head bowed    eat     bread raised to the mouth now and then
##   drink   a cup raised now and then     talk    relaxed, with the odd gesture
## `ground`: sitting on the ground (legs out in front, lower).

var sitting := false
var forward := Vector3.FORWARD
var seat_drop := 0.5
var seat_back := 0.38
var ground := false
var activity := "relax":
	set(value):
		if value != activity:
			activity = value
			_update_prop()

var _w := 0.0
var _t := 0.0
var _bones := {}
var _prop: Node3D

const NAMES := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg",
	"LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]


func _ready() -> void:
	var skel := get_skeleton()
	if skel:
		for n in NAMES:
			_bones[n] = skel.find_bone("mixamorig_" + n)


func is_seated() -> bool:
	return _w > 0.9


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or int(_bones.get("Hips", -1)) < 0:
		return
	var delta := get_viewport().get_process_delta_time() if is_inside_tree() else 0.016
	_t += delta
	_w = move_toward(_w, 1.0 if sitting else 0.0, delta * 2.2)
	if _prop:
		_prop.visible = _w > 0.6
	if _w <= 0.001:
		return
	var w := smoothstep(0.0, 1.0, _w)
	var fwd := Vector3(forward.x, 0.0, forward.z).normalized()
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	# Hips: down onto the seat and back over it.
	var hips: int = _bones.Hips
	var drop := (seat_drop + (0.25 if ground else 0.0)) * w
	var offset := Vector3.DOWN * drop - fwd * seat_back * w
	var gp := skel.get_bone_global_pose(hips)
	var to_skel := skel.global_transform.basis.inverse()
	var new_origin := gp.origin + to_skel * offset
	var parent := skel.get_bone_parent(hips)
	var parent_pose := skel.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	skel.set_bone_pose_position(hips, parent_pose.affine_inverse() * new_origin)
	# Legs.
	var thigh := 85.0 if not ground else 88.0
	var knee := -88.0 if not ground else -8.0
	for side in ["Left", "Right"]:
		_turn(skel, side + "UpLeg", right, thigh * w)
		_turn(skel, side + "Leg", right, knee * w)
	# Activity: arms, back, head.
	var lean := 0.0
	var head := 0.0
	var arms := {"LeftArm": 30.0, "LeftForeArm": 35.0, "RightArm": 30.0, "RightForeArm": 35.0}
	match activity:
		"warm":
			arms = {"LeftArm": 62.0, "LeftForeArm": 18.0, "RightArm": 62.0, "RightForeArm": 18.0}
			lean = -10.0 + sin(_t * 0.8) * 2.0
		"read":
			arms = {"LeftArm": 48.0, "LeftForeArm": 70.0, "RightArm": 48.0, "RightForeArm": 70.0}
			lean = -8.0
			head = -24.0
			# Turning a page every few seconds.
			var page := fposmod(_t, 7.0)
			if page < 0.8:
				arms.RightForeArm += sin(page / 0.8 * PI) * 25.0
		"eat", "drink":
			var cycle := fposmod(_t, 6.0)
			var up := smoothstep(0.0, 0.6, cycle) * (1.0 - smoothstep(2.0, 2.6, cycle))
			arms.RightArm = lerpf(30.0, 55.0, up)
			arms.RightForeArm = lerpf(35.0, 125.0, up)
			head = up * (8.0 if activity == "drink" else -4.0)
		"talk":
			var g := maxf(sin(_t * 0.9), 0.0) * maxf(sin(_t * 2.3), 0.0)
			arms.RightArm = 30.0 + g * 30.0
			arms.RightForeArm = 35.0 + g * 45.0
			head = sin(_t * 1.7) * 4.0
		_:
			lean = sin(_t * 0.5) * 1.5
	_turn(skel, "Spine", right, lean * 0.5 * w)
	_turn(skel, "Spine1", right, lean * 0.5 * w)
	for b: String in arms:
		_turn(skel, b, right, float(arms[b]) * w)
	if head != 0.0:
		_turn(skel, "Head", right, head * w)


## Turns a bone about a world axis by `degrees` (on top of its current pose).
func _turn(skel: Skeleton3D, bone_name: String, axis: Vector3, degrees: float) -> void:
	var bone: int = _bones.get(bone_name, -1)
	if bone < 0 or absf(degrees) < 0.01:
		return
	var skel_basis := skel.global_transform.basis.orthonormalized()
	var r := skel_basis.inverse() * Basis(axis, deg_to_rad(degrees)) * skel_basis
	var global_pose := skel.get_bone_global_pose(bone)
	var new_global := r * global_pose.basis
	var parent := skel.get_bone_parent(bone)
	var parent_basis := skel.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	skel.set_bone_pose_rotation(bone, (parent_basis.inverse() * new_global).orthonormalized().get_rotation_quaternion())


## A book, bread or a cup in hand for the activities that need one.
func _update_prop() -> void:
	if _prop and is_instance_valid(_prop):
		_prop.queue_free()
	_prop = null
	var skel := get_skeleton()
	if skel == null:
		return
	var mesh: Mesh = null
	var color := Color.WHITE
	var hand := "mixamorig_RightHand"
	var at := Vector3(0, 0.08, 0.03)
	match activity:
		"read":
			var b := BoxMesh.new()
			b.size = Vector3(0.2, 0.26, 0.04)
			mesh = b
			color = Color(0.45, 0.22, 0.15)
			hand = "mixamorig_LeftHand"
			at = Vector3(0, 0.1, 0.05)
		"eat":
			var s := SphereMesh.new()
			s.radius = 0.05
			s.height = 0.07
			mesh = s
			color = Color(0.78, 0.55, 0.3)
		"drink":
			var c := CylinderMesh.new()
			c.top_radius = 0.04
			c.bottom_radius = 0.035
			c.height = 0.1
			mesh = c
			color = Color(0.55, 0.4, 0.28)
	if mesh == null or skel.find_bone(hand) < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = hand
	skel.add_child(att)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	# Bone attachments carry the skeleton's scale: undo it so the prop is life-size.
	var sc := skel.global_transform.basis.get_scale()
	mi.scale = Vector3.ONE / maxf(sc.x, 0.0001) if skel.is_inside_tree() else Vector3.ONE
	mi.position = at / maxf(sc.x, 0.0001) if skel.is_inside_tree() else at
	att.add_child(mi)
	_prop = att
	_prop.visible = false


func _exit_tree() -> void:
	if _prop and is_instance_valid(_prop):
		_prop.queue_free()
