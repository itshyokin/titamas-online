class_name UpperBodyLayer
extends SkeletonModifier3D
## Plays an animation on the upper body only (the spine up: chest, arms, head) over
## whatever the legs are doing, so a character can walk while holding a bow draw, an aim
## or a heavy wind-up. The spine keeps the clip's facing relative to the body, not the
## hips, so the walk's hip sway doesn't swing the aim around.
## CharacterModel.play_upper() / stop_upper() drive it; it advances its own clock.

var animation: Animation
## Seconds into the clip, how fast it runs, and where it stops and holds (-1 = the end).
var time := 0.0
var speed := 1.0
var hold_at := -1.0

var _weight := 0.0
var _target_weight := 0.0
var _fade := 8.0
var _bones: Array = []  # [track, bone] for the upper body, spine first
var _hips := -1
var _hips_track := -1
var _spine := -1


func play(anim: Animation, from: float, play_speed: float, hold: float, blend: float) -> void:
	if anim != animation:
		animation = anim
		_map_tracks()
	time = from
	speed = play_speed
	hold_at = hold
	_target_weight = 1.0
	_fade = 1.0 / maxf(blend, 0.01)
	active = true


func stop(blend: float) -> void:
	_target_weight = 0.0
	_fade = 1.0 / maxf(blend, 0.01)


## Playing (or still fading out).
func is_playing() -> bool:
	return _target_weight > 0.0


func _map_tracks() -> void:
	_bones.clear()
	_hips_track = -1
	var skel := get_skeleton()
	if skel == null or animation == null:
		return
	_hips = skel.find_bone("mixamorig_Hips")
	_spine = skel.find_bone("mixamorig_Spine")
	if _spine < 0:
		return
	var upper := {}
	for b in skel.get_bone_count():
		var p := b
		while p >= 0:
			if p == _spine:
				upper[b] = true
				break
			p = skel.get_bone_parent(p)
	for t in animation.get_track_count():
		if animation.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := skel.find_bone(String(animation.track_get_path(t).get_concatenated_subnames()))
		if bone == _hips:
			_hips_track = t
		elif upper.has(bone):
			_bones.append([t, bone])
	# Spine first, so the rest follow it.
	_bones.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1] == _spine) > int(b[1] == _spine))


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or animation == null:
		return
	var delta := get_viewport().get_process_delta_time() if is_inside_tree() else 0.016
	_weight = move_toward(_weight, _target_weight, delta * _fade)
	if _weight <= 0.0:
		if _target_weight <= 0.0:
			active = false
		return
	var end := animation.length if hold_at < 0.0 else minf(hold_at, animation.length)
	time = clampf(time + delta * speed, 0.0, end)
	for entry: Array in _bones:
		var t: int = entry[0]
		var bone: int = entry[1]
		var rot := animation.rotation_track_interpolate(t, time)
		if bone == _spine and _hips >= 0 and _hips_track >= 0:
			# Keep the clip's chest facing relative to the character, whatever the hips do.
			var clip_hips := animation.rotation_track_interpolate(_hips_track, time)
			var hips_now := skel.get_bone_global_pose(_hips).basis.get_rotation_quaternion()
			rot = hips_now.inverse() * clip_hips * rot
		var now := skel.get_bone_pose_rotation(bone)
		skel.set_bone_pose_rotation(bone, now.slerp(rot, _weight))
