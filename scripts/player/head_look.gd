class_name HeadLook
extends SkeletonModifier3D
## Turns a character's neck and head towards a point (on top of whatever animation is
## playing), within natural limits, easing in and out. Add as a child of the Skeleton3D
## (CharacterModel.head_look() does it) and set `target_position` / `looking` each frame.
## While `talking`, adds small nods and tilts so a speaker looks alive.

## How far the head may turn sideways and up/down (degrees).
@export var max_yaw := 65.0
@export var max_pitch := 30.0
## How quickly it follows (higher = snappier).
@export var speed := 5.0
## Share of the turn done by the neck; the head does the rest.
@export_range(0.0, 1.0) var neck_share := 0.35

## Where to look (world space).
var target_position := Vector3.ZERO
## Looking at all? (eases back to the animation's own pose when false)
var looking := false
## Talking: adds gentle nods.
var talking := false
## The body's forward direction in world space (where the head faces with no turn).
var forward := Vector3.FORWARD

var _neck := -1
var _head := -1
var _weight := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _time := 0.0


func _ready() -> void:
	var skel := get_skeleton()
	if skel:
		_neck = skel.find_bone("mixamorig_Neck")
		_head = skel.find_bone("mixamorig_Head")


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or _head < 0:
		return
	var delta := get_viewport().get_process_delta_time() if is_inside_tree() else 0.016
	_time += delta
	var want_yaw := 0.0
	var want_pitch := 0.0
	var head_world := skel.global_transform * skel.get_bone_global_pose(_head).origin
	if looking:
		var to := target_position - head_world
		var fwd := Vector3(forward.x, 0.0, forward.z).normalized()
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() > 0.05 and fwd.length() > 0.01:
			want_yaw = fwd.signed_angle_to(flat.normalized(), Vector3.UP)
			want_pitch = atan2(to.y, flat.length())
			# Behind them: don't twist round, just look ahead.
			if absf(rad_to_deg(want_yaw)) > max_yaw + 40.0:
				want_yaw = 0.0
				want_pitch = 0.0
	var k := clampf(speed * delta, 0.0, 1.0)
	_weight = lerpf(_weight, 1.0 if looking else 0.0, k)
	_yaw = lerpf(_yaw, clampf(want_yaw, -deg_to_rad(max_yaw), deg_to_rad(max_yaw)), k)
	_pitch = lerpf(_pitch, clampf(want_pitch, -deg_to_rad(max_pitch), deg_to_rad(max_pitch)), k)
	var nod := 0.0
	var tilt := 0.0
	if talking:
		nod = sin(_time * 3.1) * 0.05 + sin(_time * 7.3) * 0.02
		tilt = sin(_time * 1.3) * 0.06
	if _weight < 0.001 and not talking:
		return
	var yaw := _yaw * _weight
	var pitch := _pitch * _weight + nod
	# Rotations in world space: yaw about up, pitch about the body's right axis.
	var fwd_flat := Vector3(forward.x, 0.0, forward.z).normalized()
	if fwd_flat.length() < 0.01:
		fwd_flat = Vector3.FORWARD
	var right := fwd_flat.cross(Vector3.UP).normalized()
	var turned_right := right.rotated(Vector3.UP, yaw)
	var full := Basis(fwd_flat.rotated(Vector3.UP, yaw), tilt) * Basis(turned_right, pitch) * Basis(Vector3.UP, yaw)
	var bones := [[_neck, neck_share], [_head, 1.0 - neck_share]] if _neck >= 0 else [[_head, 1.0]]
	for entry in bones:
		var bone: int = entry[0]
		var share: float = entry[1]
		var q := Quaternion.IDENTITY.slerp(full.get_rotation_quaternion(), share)
		_rotate_bone_world(skel, bone, Basis(q))


## Adds a world-space rotation to a bone's current pose.
func _rotate_bone_world(skel: Skeleton3D, bone: int, rot: Basis) -> void:
	var skel_basis := skel.global_transform.basis.orthonormalized()
	var global_pose := skel.get_bone_global_pose(bone)
	# The rotation, expressed in skeleton space.
	var r := skel_basis.inverse() * rot * skel_basis
	var new_global := Basis(r) * global_pose.basis
	var parent := skel.get_bone_parent(bone)
	var parent_basis := skel.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	var local := (parent_basis.inverse() * new_global).orthonormalized()
	skel.set_bone_pose_rotation(bone, local.get_rotation_quaternion())
