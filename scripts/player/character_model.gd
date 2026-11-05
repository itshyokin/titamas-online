@tool
class_name CharacterModel
extends Node3D
## Shows one of the two base bodies from base_bodies.glb, tints its skin and plays
## its animations. Lives under Player/Model. The imported body faces -Z (the game's
## forward), so it needs no extra rotation.
##
## Animations come from assets/animations/<body>.res, built from the Mixamo FBX files
## by tools/godot/retarget_mixamo.gd.

enum BodyType { MASC, FEMME }

const LIBRARIES := {
	BodyType.MASC: "res://assets/animations/masc.res",
	BodyType.FEMME: "res://assets/animations/femme.res",
}

@export var body_type: BodyType = BodyType.MASC:
	set(value):
		body_type = value
		_apply()

@export var skin_color := Color(0.87, 0.72, 0.6):
	set(value):
		skin_color = value
		_apply()

## Where a held item's grip sits between the wrist (0) and the finger bases (1).
@export_range(0.0, 1.0) var grip_depth := 0.6

## Animation played when nothing else is asked for (also previews in the editor).
@export var default_animation := "idle"

var _skin_material := StandardMaterial3D.new()
var _animator: AnimationPlayer
var _measure_cache := {}


func _ready() -> void:
	_skin_material.roughness = 0.85
	# Only animate in the running game; posing bones in the editor could get saved into scenes.
	if not Engine.is_editor_hint():
		_animator = AnimationPlayer.new()
		_animator.name = "Animator"
		add_child(_animator)
	_apply()


## Crossfades to an animation. Does nothing if it's already playing.
func play(anim: String, blend := 0.2, speed := 1.0) -> void:
	if _animator == null or not _animator.has_animation(anim):
		return
	_animator.speed_scale = speed
	if _animator.current_animation != anim:
		_animator.play(anim, blend)


## Plays an animation from a given time (restarts it even if already playing).
func play_from(anim: String, time: float, blend := 0.15, speed := 1.0) -> void:
	if _animator == null or not _animator.has_animation(anim):
		return
	_animator.speed_scale = speed
	_animator.play(anim, blend)
	_animator.seek(time, true)


## Horizontal travel baked out of a one-shot animation (see retarget_mixamo.gd),
## one character-local offset per frame at 30 fps. Empty if the animation has none.
func get_root_motion(anim: String) -> PackedVector3Array:
	if _animator == null or not _animator.has_animation(anim):
		return PackedVector3Array()
	return _animator.get_animation(anim).get_meta("root_motion", PackedVector3Array())


## Where the fingertips and toe tips are at `time` into `anim`, in the character's
## own space (feet origin, facing -Z): {"hands": Vector3, "toes": Vector3}.
## Used to line hands up with ledges and rungs. Measured on the actual body, cached.
func measure(anim: String, time: float) -> Dictionary:
	var key := "%s@%.3f" % [anim, time]
	if _measure_cache.has(key):
		return _measure_cache[key]
	if _animator == null or not _animator.has_animation(anim):
		return {}
	var prev := _animator.current_animation
	var prev_pos := animation_position()
	var prev_speed := _animator.speed_scale
	_animator.speed_scale = 1.0
	_animator.play(anim, 0.0)
	_animator.seek(time, true)
	var skel := get_skeleton()
	# Measure in the parent's space: this node may carry the import's root scale.
	var to_local := (get_parent() as Node3D).global_transform.affine_inverse() * skel.global_transform
	var bone := func(n: String) -> Vector3: return to_local * skel.get_bone_global_pose(skel.find_bone(n)).origin
	var result := {
		"hands": (bone.call("mixamorig_LeftHandIndex4") + bone.call("mixamorig_RightHandIndex4")) * 0.5,
		"toes": (bone.call("mixamorig_LeftToe_End") + bone.call("mixamorig_RightToe_End")) * 0.5,
	}
	_animator.speed_scale = prev_speed
	if not prev.is_empty():
		_animator.play(prev, 0.0)
		_animator.seek(prev_pos, true)
	_measure_cache[key] = result
	return result


## Times (seconds into `anim`) when each of `bones` comes down: its height drops below
## `fraction` of its range (0 = lowest point, 1 = highest). With the feet this gives the
## footfalls of a walk/run cycle; with the hands, the strokes of a swim. Cached.
func bone_contacts(anim: String, bones: PackedStringArray, fraction := 0.2) -> PackedFloat32Array:
	var key := "contacts:%s:%s:%.2f" % [anim, ",".join(bones), fraction]
	if _measure_cache.has(key):
		return _measure_cache[key]
	var result := PackedFloat32Array()
	if _animator == null or not _animator.has_animation(anim):
		return result
	var length := _animator.get_animation(anim).length
	var steps := maxi(int(length * 60.0), 8)
	var prev := _animator.current_animation
	var prev_pos := animation_position()
	var prev_speed := _animator.speed_scale
	_animator.speed_scale = 1.0
	_animator.play(anim, 0.0)
	var skel := get_skeleton()
	var heights := []  # per bone: PackedFloat32Array of heights over the clip
	for b in bones:
		heights.append(PackedFloat32Array())
	for i in steps:
		_animator.seek(length * i / steps, true)
		for j in bones.size():
			heights[j].append(skel.get_bone_global_pose(skel.find_bone(bones[j])).origin.y)
	for j in bones.size():
		var h: PackedFloat32Array = heights[j]
		var lo := INF
		var hi := -INF
		for v in h:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		var line := lo + (hi - lo) * fraction
		for i in steps:
			# The clip loops, so compare with the previous sample wrapping round.
			if h[i] <= line and h[(i - 1 + steps) % steps] > line:
				result.append(length * i / steps)
	result.sort()
	# A wobbling bone can cross the line twice in a row; keep the first of close pairs
	# (including across the loop point).
	var min_gap := maxf(0.15, length * 0.06)
	var kept := PackedFloat32Array()
	for t in result:
		if kept.is_empty() or t - kept[kept.size() - 1] >= min_gap:
			kept.append(t)
	if kept.size() > 1 and kept[0] + length - kept[kept.size() - 1] < min_gap:
		kept.remove_at(kept.size() - 1)
	result = kept
	_animator.speed_scale = prev_speed
	if not prev.is_empty():
		_animator.play(prev, 0.0)
		_animator.seek(prev_pos, true)
	_measure_cache[key] = result
	return result


## Puts a held item (grip at its origin, blade/shaft along +Y) in the right or left hand.
## The grip is worked out from the finger bones, so it fits both bodies.
## Returns the attachment node (free it to remove the item).
func attach_to_hand(item: Node3D, right := true) -> BoneAttachment3D:
	var skel := get_skeleton()
	if skel == null:
		return null
	var side := "Right" if right else "Left"
	var hand := skel.find_bone("mixamorig_%sHand" % side)
	var index := skel.find_bone("mixamorig_%sHandIndex1" % side)
	# The bodies have three-chain hands (thumb, index, ring): the ring stands in for the pinky side.
	var pinky := skel.find_bone("mixamorig_%sHandRing1" % side)
	if hand < 0 or index < 0 or pinky < 0:
		push_warning("CharacterModel: hand bones not found")
		return null
	var attach := BoneAttachment3D.new()
	attach.name = "%sHandItem" % side
	attach.bone_name = skel.get_bone_name(hand)
	skel.add_child(attach)
	# Hand-local frame from the rest pose: the blade leaves the fist on the thumb side
	# (pinky -> index), the fingers wrap round the grip.
	var hand_rest := skel.get_bone_global_rest(hand)
	var to_hand := hand_rest.affine_inverse()
	var p_index := to_hand * skel.get_bone_global_rest(index).origin
	var p_pinky := to_hand * skel.get_bone_global_rest(pinky).origin
	var p_middle := (p_index + p_pinky) * 0.5
	var blade := (p_index - p_pinky).normalized()
	var fingers := p_middle.normalized()
	var side_axis := fingers.cross(blade).normalized()
	fingers = blade.cross(side_axis).normalized()
	var grip := p_middle * grip_depth
	# The skeleton may be scaled (import root scale); keep the item at its real size.
	var s := skel.global_transform.basis.get_scale().x * hand_rest.basis.get_scale().x
	var item_basis := Basis(side_axis, blade, fingers).scaled(Vector3.ONE / maxf(s, 0.0001))
	item.transform = Transform3D(item_basis, grip)
	attach.add_child(item)
	return attach


## Attaches an item to a bone so it sits at `placement` (in this model's own space: feet
## at the origin, facing -Z) when the body is in its rest pose, then follows the bone.
## Used for things worn on the body, like a sheathed sword on the back.
func attach_to_bone(item: Node3D, bone_name: String, placement: Transform3D) -> BoneAttachment3D:
	var skel := get_skeleton()
	var bone := skel.find_bone(bone_name) if skel else -1
	if bone < 0:
		push_warning("CharacterModel: no bone %s" % bone_name)
		return null
	var attach := BoneAttachment3D.new()
	attach.name = bone_name.trim_prefix("mixamorig_") + "Item"
	attach.bone_name = bone_name
	skel.add_child(attach)
	var to_model := global_transform.affine_inverse() * skel.global_transform
	var bone_in_model := to_model * skel.get_bone_global_rest(bone)
	item.transform = bone_in_model.affine_inverse() * placement
	attach.add_child(item)
	return attach


## Where a bone sits in the rest pose, in this model's space.
func bone_rest_position(bone_name: String) -> Vector3:
	var skel := get_skeleton()
	var bone := skel.find_bone(bone_name) if skel else -1
	if bone < 0:
		return Vector3.ZERO
	return (global_transform.affine_inverse() * skel.global_transform * skel.get_bone_global_rest(bone)).origin


func get_animation_length(anim: String) -> float:
	if _animator == null or not _animator.has_animation(anim):
		return 0.0
	return _animator.get_animation(anim).length


func current_animation() -> String:
	return _animator.current_animation if _animator else ""


func animation_position() -> float:
	return _animator.current_animation_position if _animator and _animator.is_playing() else 0.0


func get_skeleton() -> Skeleton3D:
	var armature := get_node_or_null(_armature_name(body_type))
	return armature.get_node("Skeleton3D") if armature else null


func _apply() -> void:
	if not is_inside_tree():
		return
	_skin_material.albedo_color = skin_color
	for type in BodyType.values():
		var armature := get_node_or_null(_armature_name(type)) as Node3D
		if armature == null:
			continue
		armature.visible = type == body_type
		for mesh in armature.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_override = _skin_material
	_setup_animator()


func _setup_animator() -> void:
	if _animator == null:
		return
	var current := _animator.current_animation
	_animator.stop()
	if _animator.has_animation_library(""):
		_animator.remove_animation_library("")
	var lib := load(LIBRARIES[body_type]) as AnimationLibrary
	if lib == null:
		return
	# Tracks are "Skeleton3D:<bone>", relative to the visible armature.
	_animator.root_node = _animator.get_path_to(get_node(_armature_name(body_type)))
	_animator.add_animation_library("", lib)
	_measure_cache.clear()
	_animator.play(current if not current.is_empty() else default_animation)


func _armature_name(type: BodyType) -> String:
	return "Armature_femme" if type == BodyType.FEMME else "Armature_masc"
