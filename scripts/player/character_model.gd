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
