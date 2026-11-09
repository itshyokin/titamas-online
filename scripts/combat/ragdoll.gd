class_name Ragdoll
extends SkeletonModifier3D
## A body going limp. Capsule rigid bodies are placed along the main bones (hips, chest,
## head, upper and lower arms and legs) from the pose the character is in, joined at the
## joints, and the skeleton follows them every frame. It falls, rolls with the hit that
## killed it and settles; then the capsules freeze in place (`settled` fires) and the
## body keeps that pose. The capsules only collide with the world.
##   Ragdoll.start(character_model, push)  /  Ragdoll.stop(character_model)
## Works in world metres whatever the skeleton's scale (the old bodies' bones are in cm).

signal settled

## [bone, child bone (its far end), parent ragdoll bone or "", radius (m), mass (kg)]
const BONES := [
	["mixamorig_Hips", "mixamorig_Spine1", "", 0.13, 10.0],
	["mixamorig_Spine1", "mixamorig_Neck", "mixamorig_Hips", 0.14, 10.0],
	["mixamorig_Head", "mixamorig_HeadTop_End", "mixamorig_Spine1", 0.1, 4.0],
	["mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_Spine1", 0.055, 2.0],
	["mixamorig_LeftForeArm", "mixamorig_LeftHand", "mixamorig_LeftArm", 0.045, 1.5],
	["mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_Spine1", 0.055, 2.0],
	["mixamorig_RightForeArm", "mixamorig_RightHand", "mixamorig_RightArm", 0.045, 1.5],
	["mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_Hips", 0.075, 6.0],
	["mixamorig_LeftLeg", "mixamorig_LeftFoot", "mixamorig_LeftUpLeg", 0.06, 4.0],
	["mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_Hips", 0.075, 6.0],
	["mixamorig_RightLeg", "mixamorig_RightFoot", "mixamorig_RightUpLeg", 0.06, 4.0],
]

## Still for this long (s) counts as settled; it settles anyway after max_time.
var still_time := 0.7
var max_time := 6.0

var _parts: Array = []  # [bone index, RigidBody3D, bone-from-body Transform3D, bone basis scale]
var _joints: Array[Node] = []
var _still := 0.0
var _age := 0.0
var _done := false


## Goes limp, pushed by `push` (m/s, world space). Returns the ragdoll, or null if the
## skeleton isn't a Mixamo one.
static func start(model: CharacterModel, push := Vector3.ZERO) -> Ragdoll:
	var skel := model.get_skeleton()
	if skel == null or skel.find_bone("mixamorig_Hips") < 0:
		return null
	var rag := skel.get_node_or_null("Ragdoll") as Ragdoll
	if rag == null:
		rag = Ragdoll.new()
		rag.name = "Ragdoll"
		skel.add_child(rag)
	rag._clear()
	model.set_speed(0.0)
	rag._build(skel, push)
	rag.active = true
	return rag


## Back to animation (respawning).
static func stop(model: CharacterModel) -> void:
	var skel := model.get_skeleton()
	var rag := skel.get_node_or_null("Ragdoll") as Ragdoll if skel else null
	if rag:
		rag._clear()
		rag.active = false


## Where a ragdolled body's hips are (null if it isn't ragdolling).
static func hips_of(model: CharacterModel) -> Variant:
	var skel := model.get_skeleton() if model else null
	var rag := skel.get_node_or_null("Ragdoll") as Ragdoll if skel else null
	if rag == null or rag._parts.is_empty() or not is_instance_valid(rag._parts[0][1]):
		return null
	return (rag._parts[0][1] as Node3D).global_position


func is_settled() -> bool:
	return _done


func _clear() -> void:
	for p: Array in _parts:
		if is_instance_valid(p[1]):
			(p[1] as Node).queue_free()
	for j in _joints:
		if is_instance_valid(j):
			j.queue_free()
	_parts.clear()
	_joints.clear()
	_still = 0.0
	_age = 0.0
	_done = false


func _build(skel: Skeleton3D, push: Vector3) -> void:
	var world := skel.get_tree().current_scene if skel.get_tree().current_scene else skel.get_tree().root
	var by_bone := {}
	for entry: Array in BONES:
		var bone := skel.find_bone(entry[0])
		var child := skel.find_bone(entry[1])
		if bone < 0 or child < 0:
			continue
		var bone_w := skel.global_transform * skel.get_bone_global_pose(bone)
		var tip := skel.global_transform * skel.get_bone_global_pose(child).origin
		var frame := Transform3D(bone_w.basis.orthonormalized(), bone_w.origin)
		var along := frame.affine_inverse() * tip  # the bone, in its own frame (metres)
		var length := along.length()
		if length < 0.02:
			continue
		var body := RigidBody3D.new()
		body.name = "Rag_" + String(entry[0]).trim_prefix("mixamorig_")
		body.collision_layer = 0
		body.collision_mask = 1
		body.mass = entry[4]
		body.linear_damp = 0.3
		body.angular_damp = 1.5
		body.continuous_cd = true
		var mat := PhysicsMaterial.new()
		mat.friction = 0.9
		mat.bounce = 0.05
		body.physics_material_override = mat
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = entry[3]
		capsule.height = maxf(length, capsule.radius * 2.0 + 0.01)
		shape.shape = capsule
		var dir := along.normalized()
		var align := Basis(Quaternion(Vector3.UP, dir)) if absf(dir.y) < 0.999 else (Basis.IDENTITY if dir.y > 0.0 else Basis(Vector3.RIGHT, PI))
		shape.transform = Transform3D(align, along * 0.5)
		body.add_child(shape)
		world.add_child(body)
		body.global_transform = frame
		body.linear_velocity = push * randf_range(0.85, 1.1)
		var scale := bone_w.basis.get_scale()
		_parts.append([bone, body, scale])
		by_bone[entry[0]] = body
		# Joined to its parent at the start of this bone.
		var parent_name := String(entry[2])
		if by_bone.has(parent_name):
			var joint := ConeTwistJoint3D.new()
			world.add_child(joint)
			joint.global_position = frame.origin
			# The twist axis (X) runs along the bone.
			joint.global_basis = frame.basis * (Basis(Quaternion(Vector3.RIGHT, dir)) if absf(dir.x) < 0.999 else Basis.IDENTITY)
			joint.node_a = joint.get_path_to(by_bone[parent_name])
			joint.node_b = joint.get_path_to(body)
			joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(55.0))
			joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(25.0))
			joint.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.9)
			_joints.append(joint)
		# The pieces of one body don't push each other apart.
		for p: Array in _parts:
			if p[1] != body:
				body.add_collision_exception_with(p[1])


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or _parts.is_empty():
		return
	var inv := skel.global_transform.affine_inverse()
	# Parents first (the list is in that order): each bone's pose from its capsule.
	for p: Array in _parts:
		var body := p[1] as RigidBody3D
		if not is_instance_valid(body):
			continue
		var xf := body.global_transform
		var s: Vector3 = p[2]
		var pose := inv * Transform3D(xf.basis.orthonormalized().scaled_local(s), xf.origin)
		skel.set_bone_global_pose(p[0], pose)


func _physics_process(delta: float) -> void:
	if _done or _parts.is_empty():
		return
	_age += delta
	var moving := false
	for p: Array in _parts:
		var body := p[1] as RigidBody3D
		if is_instance_valid(body) and not body.sleeping and (body.linear_velocity.length() > 0.25 or body.angular_velocity.length() > 1.5):
			moving = true
			break
	_still = 0.0 if moving else _still + delta
	if _still >= still_time or _age >= max_time:
		_done = true
		# Freeze where it lies: no more physics, no collision.
		for p: Array in _parts:
			var body := p[1] as RigidBody3D
			if is_instance_valid(body):
				body.freeze = true
				body.collision_mask = 0
		_snap_to_ground()
		settled.emit()


## A body that stopped above the ground (caught on something, or out of time while
## still falling) is lowered until its lowest part touches the ground below it.
func _snap_to_ground() -> void:
	var space := get_skeleton().get_world_3d().direct_space_state if get_skeleton() else null
	if space == null:
		return
	var gap := INF
	for p: Array in _parts:
		var body := p[1] as RigidBody3D
		if not is_instance_valid(body):
			continue
		var shape := body.get_child(0) as CollisionShape3D
		var r := (shape.shape as CapsuleShape3D).radius if shape else 0.05
		# Both ends of the capsule.
		var half := shape.transform.origin if shape else Vector3.ZERO
		for end in [body.global_transform * Vector3.ZERO, body.global_transform * (half * 2.0)]:
			var q := PhysicsRayQueryParameters3D.create(end + Vector3.UP * 0.05, end + Vector3.DOWN * 30.0, 1)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			gap = minf(gap, end.y - r - float((hit.position as Vector3).y))
	if gap == INF or gap < 0.12:
		return
	var drop := Vector3.DOWN * gap
	for p: Array in _parts:
		var body := p[1] as RigidBody3D
		if is_instance_valid(body):
			var t := body.create_tween()
			t.tween_property(body, "global_position", body.global_position + drop, clampf(gap * 0.25, 0.1, 0.4)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _exit_tree() -> void:
	_clear()
