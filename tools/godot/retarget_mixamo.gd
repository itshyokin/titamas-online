extends SceneTree
## Converts Mixamo FBX animations (assets/animations/mixamo/*.fbx) into one
## AnimationLibrary per base body (assets/animations/<body>.res).
##
## Run from the project folder:
##   godot --headless --path . --script res://tools/godot/retarget_mixamo.gd
##
## Why: the bodies in base_bodies.glb went through Blender, so their bone rest
## orientations, facing and units differ from Mixamo's FBX skeleton. Each frame is
## re-expressed as a world-space rotation relative to the source rest pose, then
## applied on top of the target body's own rest pose. Hip movement is scaled by
## hip height, so it works for both body proportions.

const SOURCE_DIR := "res://assets/animations/mixamo"
const BODIES := {"masc": "Armature_masc", "femme": "Armature_femme"}
const BODY_SCENE := "res://assets/models/characters/base_bodies.glb"
const ROOT_BONE := "mixamorig_Hips"
const FPS := 30.0
## Animations that loop. Everything else plays once.
const LOOPING := [
	"idle", "walking", "running", "falling_loop", "hanging_idle",
	"swimming", "treading_water", "climbing_up_wall", "climbing_down_wall", "climbing_ladder",
]
## Looping animations whose hips should not drift horizontally (in-place).
const IN_PLACE := LOOPING
## One-shot animations that travel: their horizontal hip movement is stripped from the
## pose and stored as metadata "root_motion" (PackedVector3Array, one offset per frame at
## FPS, in the character's local space, facing -Z) so the game can move the body itself.
const ROOT_MOTION := ["dodge_left", "dodge_right", "dodge_back", "hanging_hop_left", "hanging_hop_right"]
## Animations whose hips may dip but not rise; the physics jump provides the height.
const NO_HIP_RISE := ["jumping"]
## Clips authored facing the other way: extra turn (degrees) so they face forward.
const YAW_FIX := {"climbing_ladder": 180.0}
## Clips whose average hip height should match another clip's (Mixamo places some
## in-place climbing clips at a different height).
const HEIGHT_MATCH := {"climbing_down_wall": "climbing_up_wall"}
## Extra outward angle (degrees) for each body's arms. Our bodies are broader than the
## Mixamo skeleton the clips were made on, so without this the hands sink into the thighs.
## Applied to the upper arm and everything below it, in every animation.
const ARM_SPREAD := {"masc": 18.0, "femme": 14.0}
## Clips that keep the original arm angles (hands must land on walls, ledges and rungs).
const NO_ARM_SPREAD_PREFIXES := ["climbing_", "hanging_"]


func _init() -> void:
	var body_scene: Node = (load(BODY_SCENE) as PackedScene).instantiate()
	var sources := _load_sources()
	for body in BODIES:
		var armature: Node3D = body_scene.get_node(BODIES[body])
		var target: Skeleton3D = armature.get_node("Skeleton3D")
		var lib := AnimationLibrary.new()
		for anim_name in sources:
			var src: Dictionary = sources[anim_name]
			var spread := 0.0 if NO_ARM_SPREAD_PREFIXES.any(func(p: String) -> bool: return anim_name.begins_with(p)) else _spread(body)
			var anim := _retarget(src.skeleton, src.animation, target, anim_name, spread)
			lib.add_animation(anim_name, anim)
		for anim_name in HEIGHT_MATCH:
			if lib.has_animation(anim_name) and lib.has_animation(HEIGHT_MATCH[anim_name]):
				_match_height(lib.get_animation(anim_name), lib.get_animation(HEIGHT_MATCH[anim_name]), target)
		var path := "res://assets/animations/%s.res" % body
		var err := ResourceSaver.save(lib, path)
		print("saved %s (%d animations) err=%d" % [path, lib.get_animation_list().size(), err])
	body_scene.free()
	quit()


func _load_sources() -> Dictionary:
	var out := {}
	for file in ResourceLoader.list_directory(SOURCE_DIR):
		if not file.ends_with(".fbx"):
			continue
		var scene: Node = (load(SOURCE_DIR.path_join(file)) as PackedScene).instantiate()
		var skel: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
		var player: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		var anim: Animation = null
		for a in player.get_animation_list():
			if a != "RESET":
				anim = player.get_animation(a)
				break
		out[file.get_basename()] = {"skeleton": skel, "animation": anim, "scene": scene}
	return out


## Transform of a node relative to the scene root (includes import scale).
func _scene_xform(node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n := node
	while n != null and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _rest_globals(skel: Skeleton3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(skel.get_bone_count())
	for i in skel.get_bone_count():
		var p := skel.get_bone_parent(i)
		out[i] = skel.get_bone_rest(i) if p < 0 else out[p] * skel.get_bone_rest(i)
	return out


## Horizontal direction the character faces in its rest pose (world space).
func _facing(skel: Skeleton3D, skel_xf: Transform3D, rest: Array[Transform3D]) -> Vector3:
	var left := skel_xf * rest[skel.find_bone("mixamorig_LeftUpLeg")].origin
	var right := skel_xf * rest[skel.find_bone("mixamorig_RightUpLeg")].origin
	var fwd := Vector3.UP.cross(right - left)
	fwd.y = 0.0
	return fwd.normalized()


## Shifts `anim`'s hip track so its average hip height equals `reference`'s.
func _match_height(anim: Animation, reference: Animation, skel: Skeleton3D) -> void:
	var xf := _scene_xform(skel)
	var mean := func(a: Animation) -> float:
		var t := a.find_track(NodePath("Skeleton3D:" + ROOT_BONE), Animation.TYPE_POSITION_3D)
		var total := 0.0
		for k in a.track_get_key_count(t):
			total += (xf * (a.track_get_key_value(t, k) as Vector3)).y
		return total / maxi(a.track_get_key_count(t), 1)
	var shift_world := Vector3(0, mean.call(reference) - mean.call(anim), 0)
	var shift_local := xf.basis.inverse() * shift_world
	var track := anim.find_track(NodePath("Skeleton3D:" + ROOT_BONE), Animation.TYPE_POSITION_3D)
	for k in anim.track_get_key_count(track):
		anim.track_set_key_value(track, k, (anim.track_get_key_value(track, k) as Vector3) + shift_local)
	print("  height-matched clip by %.2f m" % shift_world.y)


func _spread(body: String) -> float:
	var override := OS.get_environment("ARM_SPREAD")  # for quick previews
	return float(override) if not override.is_empty() else float(ARM_SPREAD[body])


## Bone indices of a bone and all its descendants.
func _subtree(skel: Skeleton3D, bone: int) -> Dictionary:
	var out := {bone: true}
	for child in skel.get_bone_children(bone):
		out.merge(_subtree(skel, child))
	return out


func _retarget(src: Skeleton3D, src_anim: Animation, dst: Skeleton3D, anim_name: String, arm_spread := 0.0) -> Animation:
	var src_skel_xf := _scene_xform(src)
	var dst_skel_xf := _scene_xform(dst)
	var src_skel_rot := src_skel_xf.basis.orthonormalized().get_rotation_quaternion()
	var dst_skel_rot := dst_skel_xf.basis.orthonormalized().get_rotation_quaternion()
	var src_rest := _rest_globals(src)
	var dst_rest := _rest_globals(dst)

	# World-space rest rotations per bone.
	var src_rest_w := {}
	var dst_rest_w := {}
	for i in src.get_bone_count():
		src_rest_w[src.get_bone_name(i)] = src_skel_rot * src_rest[i].basis.orthonormalized().get_rotation_quaternion()
	for i in dst.get_bone_count():
		dst_rest_w[dst.get_bone_name(i)] = dst_skel_rot * dst_rest[i].basis.orthonormalized().get_rotation_quaternion()

	# Rotation (about up) taking the source character's facing onto the target's.
	# Facing comes from anatomy, not bone axes: Blender and Mixamo orient bones differently.
	var src_fwd := _facing(src, src_skel_xf, src_rest)
	var dst_fwd := _facing(dst, dst_skel_xf, dst_rest)
	var align := Quaternion(Vector3.UP, atan2(src_fwd.x, src_fwd.z) * -1.0 + atan2(dst_fwd.x, dst_fwd.z))
	# Whole-body turn for clips authored facing the other way.
	var turn := Quaternion(Vector3.UP, deg_to_rad(YAW_FIX.get(anim_name, 0.0)))

	# Arm spread: swing each whole arm outward about the character's forward axis.
	var left_dir := Vector3.UP.cross(dst_fwd)
	var spread_left := Quaternion(Vector3.DOWN.cross(left_dir).normalized(), deg_to_rad(arm_spread))
	var spread_right := Quaternion(Vector3.DOWN.cross(-left_dir).normalized(), deg_to_rad(arm_spread))
	var left_arm := _subtree(dst, dst.find_bone("mixamorig_LeftArm"))
	var right_arm := _subtree(dst, dst.find_bone("mixamorig_RightArm"))

	# Hip height ratio converts source hip movement (cm, Mixamo size) to target metres.
	var src_root := src.find_bone(ROOT_BONE)
	var dst_root := dst.find_bone(ROOT_BONE)
	var src_hip_w := src_skel_xf * src_rest[src_root].origin
	var dst_hip_w := dst_skel_xf * dst_rest[dst_root].origin
	var scale := dst_hip_w.y / src_hip_w.y

	# Source tracks by bone.
	var rot_track := {}
	var pos_track := -1
	for t in src_anim.get_track_count():
		var bone := String(src_anim.track_get_path(t).get_concatenated_subnames())
		match src_anim.track_get_type(t):
			Animation.TYPE_ROTATION_3D:
				rot_track[bone] = t
			Animation.TYPE_POSITION_3D:
				if bone == ROOT_BONE:
					pos_track = t

	var out := Animation.new()
	out.length = src_anim.length
	out.loop_mode = Animation.LOOP_LINEAR if anim_name in LOOPING else Animation.LOOP_NONE

	# Target bones in hierarchy order (parents before children).
	var bones: Array[int] = []
	for i in dst.get_bone_count():
		bones.append(i)

	var out_rot := {}
	for i in bones:
		var name := dst.get_bone_name(i)
		if rot_track.has(name):
			var t := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(t, NodePath("Skeleton3D:" + name))
			out_rot[name] = t
	var out_pos := -1
	if pos_track >= 0:
		out_pos = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(out_pos, NodePath("Skeleton3D:" + ROOT_BONE))

	var frames := int(round(src_anim.length * FPS))
	var root_motion := PackedVector3Array()
	var first_offset := Vector3.ZERO
	var last_offset := Vector3.ZERO
	for f in frames + 1:
		var time := minf(f / FPS, src_anim.length)

		# Source pose, world space.
		var src_pose_w := {}
		for i in src.get_bone_count():
			var name := src.get_bone_name(i)
			var local: Quaternion = src.get_bone_rest(i).basis.orthonormalized().get_rotation_quaternion()
			if rot_track.has(name):
				local = src_anim.rotation_track_interpolate(rot_track[name], time)
			var p := src.get_bone_parent(i)
			src_pose_w[name] = (src_skel_rot if p < 0 else src_pose_w[src.get_bone_name(p)]) * local

		# Target pose, world space, then back to each bone's local space.
		var dst_pose_w := {}
		for i in bones:
			var name := dst.get_bone_name(i)
			var world: Quaternion
			if src_pose_w.has(name):
				var delta: Quaternion = src_pose_w[name] * src_rest_w[name].inverse()
				world = turn * align * delta * align.inverse() * dst_rest_w[name]
				if left_arm.has(i):
					world = spread_left * world
				elif right_arm.has(i):
					world = spread_right * world
			else:
				var p := dst.get_bone_parent(i)
				var parent_w: Quaternion = dst_skel_rot if p < 0 else dst_pose_w[dst.get_bone_name(p)]
				world = parent_w * dst.get_bone_rest(i).basis.orthonormalized().get_rotation_quaternion()
			dst_pose_w[name] = world
			if out_rot.has(name):
				var p := dst.get_bone_parent(i)
				var parent_w: Quaternion = dst_skel_rot if p < 0 else dst_pose_w[dst.get_bone_name(p)]
				out.rotation_track_insert_key(out_rot[name], time, (parent_w.inverse() * world).normalized())

		if out_pos >= 0:
			var src_pos: Vector3 = src_anim.position_track_interpolate(pos_track, time)
			# Hip movement in source world space, rescaled by hip height and turned to the target's facing.
			var offset_w := turn * align * (src_skel_xf.basis.orthonormalized() * (src_pos - src_rest[src_root].origin) * scale)
			if f == 0:
				first_offset = offset_w
			last_offset = offset_w
			if anim_name in ROOT_MOTION:
				root_motion.append(Vector3(offset_w.x, 0.0, offset_w.z) - Vector3(first_offset.x, 0.0, first_offset.z))
			if anim_name in IN_PLACE or anim_name in ROOT_MOTION:
				offset_w.x = 0.0
				offset_w.z = 0.0
			if anim_name in NO_HIP_RISE:
				offset_w.y = minf(offset_w.y, 0.0)
			var target_w := dst_hip_w + offset_w
			out.position_track_insert_key(out_pos, time, dst_skel_xf.affine_inverse() * target_w)

	if anim_name == "idle":
		print("  facing: source %s  target %s" % [src_fwd.snapped(Vector3.ONE * 0.01), dst_fwd.snapped(Vector3.ONE * 0.01)])
	if not root_motion.is_empty():
		out.set_meta("root_motion", root_motion)
		var total := root_motion[root_motion.size() - 1].length()
		var done := 0
		while done < root_motion.size() and root_motion[done].length() < total * 0.95:
			done += 1
		print("  %-20s root motion %.2f m, 95%% done at %.2fs" % [anim_name, total, done / FPS])
	var travel := last_offset - first_offset
	print("  %-20s %5.2fs  hips travel x=%.2f y=%.2f z=%.2f m" % [anim_name, src_anim.length, travel.x, travel.y, travel.z])
	return out
