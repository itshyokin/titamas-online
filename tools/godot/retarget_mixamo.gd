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
const BODY_SCENE := "res://assets/models/characters/base_bodies.scn"
const ROOT_BONE := "mixamorig_Hips"
## Limb bones whose rest direction is matched to Mixamo's T-pose, and the child bone
## (first one found) that gives each one's direction.
const LIMB_CHILD := {
	"Shoulder": ["Arm"], "Arm": ["ForeArm"], "ForeArm": ["Hand"], "Hand": ["HandMiddle1", "HandIndex1"],
	"UpLeg": ["Leg"], "Leg": ["Foot"], "Foot": ["ToeBase"],
}
const FPS := 30.0
## Per-clip settings come from data/animations.json (Database → Animations), read by
## _load_settings() into these:
const SETTINGS := "res://data/animations.json"
## Animations that loop. Everything else plays once.
var LOOPING: Array = []
## Looping animations whose hips should not drift horizontally (in-place).
var IN_PLACE: Array = []
## One-shot animations that travel: their horizontal hip movement is stripped from the
## pose and stored as metadata "root_motion" (PackedVector3Array, one offset per frame at
## FPS, in the character's local space, facing -Z) so the game can move the body itself.
var ROOT_MOTION: Array = []
## Clips made by playing another backwards (with its root motion reversed).
var REVERSED := {}
## Clips mirrored left/right from another clip: name -> source clip.
var MIRRORED := {}
## Clips cut out of longer ones: name -> [source clip, start s, end s].
var SUBCLIPS := {}
## Animations whose hips may dip but not rise; the physics jump provides the height.
var NO_HIP_RISE: Array = []
## Clips authored facing the other way: extra turn (degrees) so they face forward.
var YAW_FIX := {}
## Clips whose average hip height should match another clip's.
var HEIGHT_MATCH := {}
## Extra outward angle (degrees) for each body's arms (our bodies are broader than the
## Mixamo skeleton, so without this the hands sink into the thighs).
var ARM_SPREAD := {"masc": 18.0, "femme": 14.0}
## Clips that keep the original arm angles (hands must land on walls, ledges and rungs).
var NO_ARM_SPREAD_PREFIXES: Array = ["climbing_", "hanging_"]


func _load_settings() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	if not d is Dictionary:
		push_warning("couldn't read %s; using no per-clip settings" % SETTINGS)
		return
	ARM_SPREAD = d.get("arm_spread", ARM_SPREAD)
	NO_ARM_SPREAD_PREFIXES = d.get("no_arm_spread_prefixes", NO_ARM_SPREAD_PREFIXES)
	for c: Dictionary in d.get("clips", []):
		var clip_name := String(c.get("name", ""))
		if clip_name.is_empty():
			continue
		if bool(c.get("loop", false)):
			LOOPING.append(clip_name)
		if bool(c.get("in_place", false)):
			IN_PLACE.append(clip_name)
		if bool(c.get("root_motion", false)):
			ROOT_MOTION.append(clip_name)
		if bool(c.get("no_hip_rise", false)):
			NO_HIP_RISE.append(clip_name)
		if float(c.get("yaw_fix", 0.0)) != 0.0:
			YAW_FIX[clip_name] = float(c.yaw_fix)
		if not String(c.get("height_match", "")).is_empty():
			HEIGHT_MATCH[clip_name] = String(c.height_match)
		match String(c.get("kind", "file")):
			"cut":
				SUBCLIPS[clip_name] = [String(c.get("from", "")), float(c.get("start", 0.0)), float(c.get("end", 0.0))]
			"reversed":
				REVERSED[clip_name] = String(c.get("from", ""))
			"mirrored":
				MIRRORED[clip_name] = String(c.get("from", ""))


## Stand-in combat clips, posed from the idle clip by rotating bones. Any of these is
## replaced automatically by a Mixamo FBX with the same name in SOURCE_DIR.
## Each clip: length, loop, and keys [time, [ops]]. Directions and axes are in the
## character's space: x = right, y = up, z = forward. Ops:
##   ["aim", bone, dir]          point the bone (towards its first child) along dir
##   ["turn", bone, axis, deg]   rotate the bone and everything below it
##                               (axis y: + turns left; axis x: + leans back; axis z: + leans right)
##   ["hips", offset]            move the hips (metres)
## A key with no ops is the idle pose. A key "same" repeats the previous key's ops.
const ARM_R := "mixamorig_RightArm"
const FORE_R := "mixamorig_RightForeArm"
const ARM_L := "mixamorig_LeftArm"
const FORE_L := "mixamorig_LeftForeArm"
const SPINE := "mixamorig_Spine1"
const PLACEHOLDERS := {
	# Ready stance with a weapon drawn: forearm forward so the blade points up and ahead.
	"idle_armed": {"length": 2.0, "loop": true, "keys": [
		[0.0, [["turn", SPINE, Vector3.UP, -8.0], ["aim", ARM_R, Vector3(0.3, -0.85, 0.3)], ["aim", FORE_R, Vector3(0.05, -0.1, 1.0)],
			["aim", ARM_L, Vector3(-0.35, -0.85, 0.2)]]],
		[1.0, [["turn", SPINE, Vector3.UP, -8.0], ["turn", SPINE, Vector3.RIGHT, 2.0], ["aim", ARM_R, Vector3(0.3, -0.83, 0.32)],
			["aim", FORE_R, Vector3(0.05, -0.05, 1.0)], ["aim", ARM_L, Vector3(-0.35, -0.83, 0.22)]]],
		[2.0, [["turn", SPINE, Vector3.UP, -8.0], ["aim", ARM_R, Vector3(0.3, -0.85, 0.3)], ["aim", FORE_R, Vector3(0.05, -0.1, 1.0)],
			["aim", ARM_L, Vector3(-0.35, -0.85, 0.2)]]],
	]},
	# Forehand diagonal slash, high right to low left. Hit at ~0.32 s.
	"attack_light_1": {"length": 0.8, "keys": [
		[0.0, []],
		[0.18, [["turn", SPINE, Vector3.UP, -30.0], ["aim", ARM_R, Vector3(0.7, 0.7, -0.1)], ["aim", FORE_R, Vector3(0.2, 0.9, -0.4)],
			["aim", ARM_L, Vector3(-0.3, -0.8, 0.4)]]],
		[0.32, [["turn", SPINE, Vector3.UP, 25.0], ["turn", SPINE, Vector3.RIGHT, -10.0], ["aim", ARM_R, Vector3(-0.3, -0.1, 1.0)],
			["aim", FORE_R, Vector3(-0.6, -0.3, 0.75)], ["aim", ARM_L, Vector3(-0.6, -0.6, -0.3)]]],
		[0.48, [["turn", SPINE, Vector3.UP, 30.0], ["turn", SPINE, Vector3.RIGHT, -8.0], ["aim", ARM_R, Vector3(-0.6, -0.6, 0.5)],
			["aim", FORE_R, Vector3(-0.6, -0.8, 0.2)], ["aim", ARM_L, Vector3(-0.6, -0.6, -0.3)]]],
		[0.8, []],
	]},
	# Backhand sweep, left to right. Hit at ~0.3 s.
	"attack_light_2": {"length": 0.75, "keys": [
		[0.0, []],
		[0.15, [["turn", SPINE, Vector3.UP, 35.0], ["aim", ARM_R, Vector3(-0.8, 0.1, 0.5)], ["aim", FORE_R, Vector3(-0.6, 0.3, -0.5)]]],
		[0.3, [["turn", SPINE, Vector3.UP, -20.0], ["aim", ARM_R, Vector3(0.5, 0.1, 0.85)], ["aim", FORE_R, Vector3(0.9, 0.1, 0.4)],
			["aim", ARM_L, Vector3(-0.5, -0.7, -0.2)]]],
		[0.45, [["turn", SPINE, Vector3.UP, -35.0], ["aim", ARM_R, Vector3(0.9, -0.1, 0.3)], ["aim", FORE_R, Vector3(0.9, -0.3, -0.2)],
			["aim", ARM_L, Vector3(-0.5, -0.7, -0.2)]]],
		[0.75, []],
	]},
	# Two-handed overhead chop. Hit at ~0.7 s.
	"attack_heavy": {"length": 1.3, "keys": [
		[0.0, []],
		[0.45, [["hips", Vector3(0, -0.04, 0)], ["turn", SPINE, Vector3.RIGHT, 15.0],
			["aim", ARM_R, Vector3(0.15, 0.95, -0.2)], ["aim", FORE_R, Vector3(-0.1, 0.5, -0.85)],
			["aim", ARM_L, Vector3(-0.15, 0.95, -0.2)], ["aim", FORE_L, Vector3(0.1, 0.5, -0.85)]]],
		[0.68, [["hips", Vector3(0, -0.14, 0.08)], ["turn", SPINE, Vector3.RIGHT, -28.0],
			["aim", ARM_R, Vector3(0.05, -0.3, 0.95)], ["aim", FORE_R, Vector3(-0.05, -0.65, 0.75)],
			["aim", ARM_L, Vector3(-0.05, -0.3, 0.95)], ["aim", FORE_L, Vector3(0.05, -0.65, 0.75)]]],
		[0.9, "same"],
		[1.3, []],
	]},
	# Guard: weapon held across the body. Holds its last pose while blocking.
	"block": {"length": 0.25, "keys": [
		[0.0, []],
		[0.18, [["turn", SPINE, Vector3.UP, -10.0], ["aim", ARM_R, Vector3(0.45, -0.3, 0.85)], ["aim", FORE_R, Vector3(-0.5, 0.55, 0.65)],
			["aim", ARM_L, Vector3(-0.4, -0.5, 0.6)], ["aim", FORE_L, Vector3(0.3, 0.3, 0.9)]]],
		[0.25, "same"],
	]},
	# Bow drawn and aimed forward (holds while the attack button is held).
	"bow_aim": {"length": 0.3, "keys": [
		[0.0, []],
		[0.25, [["turn", SPINE, Vector3.UP, 40.0], ["aim", ARM_L, Vector3(0.05, 0.12, 1.0)], ["aim", FORE_L, Vector3(0.0, 0.12, 1.0)],
			["aim", ARM_R, Vector3(0.55, 0.2, -0.35)], ["aim", FORE_R, Vector3(-0.75, 0.15, 0.6)]]],
		[0.3, "same"],
	]},
	# Letting the arrow go: the drawing hand flicks back. Arrow leaves at the start.
	"bow_release": {"length": 0.55, "keys": [
		[0.0, [["turn", SPINE, Vector3.UP, 40.0], ["aim", ARM_L, Vector3(0.05, 0.12, 1.0)], ["aim", FORE_L, Vector3(0.0, 0.12, 1.0)],
			["aim", ARM_R, Vector3(0.55, 0.2, -0.35)], ["aim", FORE_R, Vector3(-0.75, 0.15, 0.6)]]],
		[0.07, [["turn", SPINE, Vector3.UP, 42.0], ["aim", ARM_L, Vector3(0.05, 0.14, 1.0)], ["aim", FORE_L, Vector3(0.0, 0.14, 1.0)],
			["aim", ARM_R, Vector3(0.65, 0.3, -0.6)], ["aim", FORE_R, Vector3(0.4, 0.25, -0.85)]]],
		[0.25, "same"],
		[0.55, []],
	]},
	# Gathering a spell (loops while casting).
	"cast_channel": {"length": 1.2, "loop": true, "keys": [
		[0.0, [["aim", ARM_R, Vector3(0.35, 0.2, 0.9)], ["aim", FORE_R, Vector3(0.0, 0.6, 0.8)],
			["aim", ARM_L, Vector3(-0.35, 0.0, 0.9)], ["aim", FORE_L, Vector3(0.1, 0.35, 0.95)]]],
		[0.6, [["aim", ARM_R, Vector3(0.35, 0.3, 0.9)], ["aim", FORE_R, Vector3(0.0, 0.7, 0.7)],
			["aim", ARM_L, Vector3(-0.35, 0.05, 0.9)], ["aim", FORE_L, Vector3(0.1, 0.45, 0.9)]]],
		[1.2, [["aim", ARM_R, Vector3(0.35, 0.2, 0.9)], ["aim", FORE_R, Vector3(0.0, 0.6, 0.8)],
			["aim", ARM_L, Vector3(-0.35, 0.0, 0.9)], ["aim", FORE_L, Vector3(0.1, 0.35, 0.95)]]],
	]},
	# Throwing the spell forward. Release at ~0.12 s.
	"cast_release": {"length": 0.6, "keys": [
		[0.0, [["aim", ARM_R, Vector3(0.35, 0.2, 0.9)], ["aim", FORE_R, Vector3(0.0, 0.6, 0.8)]]],
		[0.12, [["turn", SPINE, Vector3.UP, 12.0], ["aim", ARM_R, Vector3(0.1, 0.15, 1.0)], ["aim", FORE_R, Vector3(0.0, 0.1, 1.0)],
			["aim", ARM_L, Vector3(-0.4, -0.7, -0.2)]]],
		[0.3, "same"],
		[0.6, []],
	]},
	# Healing: both hands raised, palms up. Effect at ~0.4 s.
	"cast_heal": {"length": 1.0, "keys": [
		[0.0, []],
		[0.35, [["turn", SPINE, Vector3.RIGHT, 8.0], ["aim", ARM_R, Vector3(0.4, 0.4, 0.8)], ["aim", FORE_R, Vector3(0.1, 0.85, 0.5)],
			["aim", ARM_L, Vector3(-0.4, 0.4, 0.8)], ["aim", FORE_L, Vector3(-0.1, 0.85, 0.5)]]],
		[0.7, "same"],
		[1.0, []],
	]},
	"hit_react": {"length": 0.45, "keys": [
		[0.0, []],
		[0.08, [["turn", SPINE, Vector3.RIGHT, 18.0], ["turn", SPINE, Vector3.UP, 10.0],
			["aim", ARM_R, Vector3(0.5, -0.7, 0.3)], ["aim", ARM_L, Vector3(-0.5, -0.7, 0.3)]]],
		[0.45, []],
	]},
	# Talking gestures (NPCs play one now and then while they speak). Each starts and ends
	# in the idle pose. A Mixamo "talk_1".."talk_3" FBX replaces them.
	"talk_1": {"length": 2.2, "keys": [
		[0.0, []],
		[0.45, [["aim", ARM_R, Vector3(0.42, -0.6, 0.5)], ["aim", FORE_R, Vector3(0.05, 0.3, 0.95)], ["turn", SPINE, Vector3.UP, 4.0]]],
		[1.2, [["aim", ARM_R, Vector3(0.5, -0.58, 0.48)], ["aim", FORE_R, Vector3(0.4, 0.25, 0.88)], ["turn", SPINE, Vector3.UP, 6.0]]],
		[1.9, []],
		[2.2, []],
	]},
	"talk_2": {"length": 2.4, "keys": [
		[0.0, []],
		[0.5, [["aim", ARM_R, Vector3(0.48, -0.62, 0.45)], ["aim", FORE_R, Vector3(0.45, 0.12, 0.88)],
			["aim", ARM_L, Vector3(-0.48, -0.62, 0.45)], ["aim", FORE_L, Vector3(-0.45, 0.12, 0.88)], ["turn", SPINE, Vector3.RIGHT, 3.0]]],
		[1.3, [["aim", ARM_R, Vector3(0.55, -0.6, 0.4)], ["aim", FORE_R, Vector3(0.65, 0.15, 0.75)],
			["aim", ARM_L, Vector3(-0.55, -0.6, 0.4)], ["aim", FORE_L, Vector3(-0.65, 0.15, 0.75)], ["turn", SPINE, Vector3.RIGHT, 4.0]]],
		[2.0, []],
		[2.4, []],
	]},
	"talk_3": {"length": 2.0, "keys": [
		[0.0, []],
		[0.4, [["turn", SPINE, Vector3.UP, -8.0], ["aim", ARM_L, Vector3(-0.4, -0.55, 0.6)], ["aim", FORE_L, Vector3(-0.15, 0.35, 0.92)]]],
		[0.9, [["turn", SPINE, Vector3.UP, -6.0], ["aim", ARM_L, Vector3(-0.42, -0.5, 0.62)], ["aim", FORE_L, Vector3(-0.1, 0.5, 0.85)]]],
		[1.4, [["turn", SPINE, Vector3.UP, -8.0], ["aim", ARM_L, Vector3(-0.4, -0.55, 0.6)], ["aim", FORE_L, Vector3(-0.15, 0.35, 0.92)]]],
		[2.0, []],
	]},
	# Falls backwards and stays down.
	"death": {"length": 1.4, "keys": [
		[0.0, []],
		[0.3, [["hips", Vector3(0, -0.12, -0.1)], ["turn", "mixamorig_Hips", Vector3.RIGHT, 12.0], ["turn", SPINE, Vector3.RIGHT, 15.0],
			["aim", ARM_R, Vector3(0.6, 0.3, 0.4)], ["aim", ARM_L, Vector3(-0.6, 0.3, 0.4)]]],
		[0.85, [["hips", Vector3(0, -0.86, -0.55)], ["turn", "mixamorig_Hips", Vector3.RIGHT, 84.0],
			["aim", ARM_R, Vector3(0.8, 0.0, -0.6)], ["aim", ARM_L, Vector3(-0.8, 0.0, -0.6)]]],
		[1.0, [["hips", Vector3(0, -0.82, -0.58)], ["turn", "mixamorig_Hips", Vector3.RIGHT, 82.0],
			["aim", ARM_R, Vector3(0.85, 0.05, -0.5)], ["aim", ARM_L, Vector3(-0.85, 0.05, -0.5)]]],
		[1.4, [["hips", Vector3(0, -0.86, -0.6)], ["turn", "mixamorig_Hips", Vector3.RIGHT, 85.0],
			["aim", ARM_R, Vector3(0.85, 0.0, -0.5)], ["aim", ARM_L, Vector3(-0.85, 0.0, -0.5)]]],
	]},
}


func _init() -> void:
	_load_settings()
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
		for cut_name in SUBCLIPS:
			var c: Array = SUBCLIPS[cut_name]
			if lib.has_animation(c[0]):
				if lib.has_animation(cut_name):
					lib.remove_animation(cut_name)
				lib.add_animation(cut_name, _cut(lib.get_animation(c[0]), float(c[1]), float(c[2]), cut_name in LOOPING))
				print("  %-20s %5.2fs  cut from %s" % [cut_name, float(c[2]) - float(c[1]), c[0]])
		for rev_name in REVERSED:
			if lib.has_animation(REVERSED[rev_name]) and not lib.has_animation(rev_name):
				lib.add_animation(rev_name, _reversed(lib.get_animation(REVERSED[rev_name])))
				print("  %-20s reversed from %s" % [rev_name, REVERSED[rev_name]])
		for mir_name in MIRRORED:
			if lib.has_animation(MIRRORED[mir_name]) and not lib.has_animation(mir_name):
				lib.add_animation(mir_name, _mirrored(lib.get_animation(MIRRORED[mir_name]), target, mir_name in LOOPING))
				print("  %-20s mirrored from %s" % [mir_name, MIRRORED[mir_name]])
		_add_placeholders(lib, target)
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


## A copy of part of a clip (resampled at FPS), starting at 0.
func _cut(src: Animation, start: float, end: float, loop: bool) -> Animation:
	var out := Animation.new()
	end = minf(end, src.length)
	out.length = end - start
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for t in src.get_track_count():
		var type := src.track_get_type(t)
		if not type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var nt := out.add_track(type)
		out.track_set_path(nt, src.track_get_path(t))
		var time := start
		while time <= end + 0.0001:
			var at := minf(time, end)
			match type:
				Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(nt, at - start, src.position_track_interpolate(t, at))
				Animation.TYPE_ROTATION_3D:
					out.rotation_track_insert_key(nt, at - start, src.rotation_track_interpolate(t, at))
				Animation.TYPE_SCALE_3D:
					out.scale_track_insert_key(nt, at - start, src.scale_track_interpolate(t, at))
			time += 1.0 / FPS
	return out


## A clip played backwards (root motion too: offsets from the new start).
func _reversed(src: Animation) -> Animation:
	var out := _cut(src, 0.0, src.length, src.loop_mode != Animation.LOOP_NONE)
	var flipped := Animation.new()
	flipped.length = out.length
	flipped.loop_mode = out.loop_mode
	for t in out.get_track_count():
		var type := out.track_get_type(t)
		var nt := flipped.add_track(type)
		flipped.track_set_path(nt, out.track_get_path(t))
		for k in range(out.track_get_key_count(t) - 1, -1, -1):
			var time := out.length - out.track_get_key_time(t, k)
			match type:
				Animation.TYPE_POSITION_3D:
					flipped.position_track_insert_key(nt, time, out.track_get_key_value(t, k))
				Animation.TYPE_ROTATION_3D:
					flipped.rotation_track_insert_key(nt, time, out.track_get_key_value(t, k))
				Animation.TYPE_SCALE_3D:
					flipped.scale_track_insert_key(nt, time, out.track_get_key_value(t, k))
	if src.has_meta("root_motion"):
		var m: PackedVector3Array = src.get_meta("root_motion")
		var r := PackedVector3Array()
		if not m.is_empty():
			var last := m[m.size() - 1]
			for i in range(m.size() - 1, -1, -1):
				r.append(m[i] - last)
		flipped.set_meta("root_motion", r)
	return flipped


## A clip mirrored left to right (a sidestep left becomes one to the right): every frame
## is posed in the skeleton's space, reflected across its middle, left and right bones
## swapped, and turned back into bone rotations. Needs a symmetric skeleton.
func _mirrored(src: Animation, skel: Skeleton3D, loop: bool) -> Animation:
	var n := skel.get_bone_count()
	var rest := _rest_globals(skel)
	# The side-to-side axis: from the left hip to the right hip.
	var l := skel.find_bone("mixamorig_LeftUpLeg")
	var r := skel.find_bone("mixamorig_RightUpLeg")
	var side := (rest[r].origin - rest[l].origin).normalized() if l >= 0 and r >= 0 else Vector3.RIGHT
	var m := Basis(Vector3.RIGHT - 2.0 * side.x * side, Vector3.UP - 2.0 * side.y * side, Vector3.BACK - 2.0 * side.z * side)
	var swap := PackedInt32Array()
	swap.resize(n)
	for b in n:
		var bone_name := skel.get_bone_name(b)
		var other := bone_name.replace("Left", "#").replace("Right", "Left").replace("#", "Right")
		var o := skel.find_bone(other)
		swap[b] = o if o >= 0 else b
	var fix: Array[Basis] = []
	fix.resize(n)
	for b in n:
		fix[b] = (m * rest[b].basis).inverse() * rest[swap[b]].basis
	# Which bones the clip moves.
	var rot_track := {}
	var pos_track := {}
	for t in src.get_track_count():
		var bone := skel.find_bone(String(src.track_get_path(t).get_concatenated_subnames()))
		if bone < 0:
			continue
		match src.track_get_type(t):
			Animation.TYPE_ROTATION_3D:
				rot_track[bone] = t
			Animation.TYPE_POSITION_3D:
				pos_track[bone] = t
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var new_rot := {}
	var new_pos := {}
	for b in rot_track:
		var nt := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(nt, NodePath("%s:%s" % [src.track_get_path(rot_track[b]).get_concatenated_names(), skel.get_bone_name(swap[b])]))
		new_rot[swap[b]] = nt
	for b in pos_track:
		var nt := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(nt, NodePath("%s:%s" % [src.track_get_path(pos_track[b]).get_concatenated_names(), skel.get_bone_name(swap[b])]))
		new_pos[swap[b]] = nt
	var time := 0.0
	while time <= src.length + 0.0001:
		var at := minf(time, src.length)
		var globals: Array[Transform3D] = []
		globals.resize(n)
		for b in n:
			var local := skel.get_bone_rest(b)
			if rot_track.has(b):
				local.basis = Basis(src.rotation_track_interpolate(rot_track[b], at)).scaled(local.basis.get_scale())
			if pos_track.has(b):
				local.origin = src.position_track_interpolate(pos_track[b], at)
			var p := skel.get_bone_parent(b)
			globals[b] = local if p < 0 else globals[p] * local
		var mirrored: Array[Transform3D] = []
		mirrored.resize(n)
		for b in n:
			# Reflected, then each bone's own axes put back the way the opposite bone's are.
			mirrored[swap[b]] = Transform3D(m * globals[b].basis * fix[b], m * globals[b].origin)
		for b in n:
			if not new_rot.has(b) and not new_pos.has(b):
				continue
			var p := skel.get_bone_parent(b)
			var local := mirrored[b] if p < 0 else mirrored[p].affine_inverse() * mirrored[b]
			if new_rot.has(b):
				out.rotation_track_insert_key(new_rot[b], at, local.basis.get_rotation_quaternion())
			if new_pos.has(b):
				out.position_track_insert_key(new_pos[b], at, local.origin)
		time += 1.0 / FPS
	if src.has_meta("root_motion"):
		var mo := PackedVector3Array()
		for v: Vector3 in src.get_meta("root_motion"):
			mo.append(Vector3(-v.x, v.y, v.z))
		out.set_meta("root_motion", mo)
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

	# Rest-pose fix: a body modelled in an A-pose (arms down, feet apart) has limbs that
	# point differently from Mixamo's T-pose. Per limb bone, the swing that turns the
	# body's rest direction onto the source's, so the deltas start from a matching pose.
	var rest_fix := {}
	for limb in LIMB_CHILD:
		for side in ["Left", "Right"]:
			var bname := "mixamorig_%s%s" % [side, limb]
			var child_name := ""
			for c: String in LIMB_CHILD[limb]:
				if child_name.is_empty() and dst.find_bone("mixamorig_%s%s" % [side, c]) >= 0 and src.find_bone("mixamorig_%s%s" % [side, c]) >= 0:
					child_name = "mixamorig_%s%s" % [side, c]
			var db := dst.find_bone(bname)
			var sb := src.find_bone(bname)
			if child_name.is_empty() or db < 0 or sb < 0:
				continue
			var d_dir := (dst_skel_xf.basis * (dst_rest[dst.find_bone(child_name)].origin - dst_rest[db].origin)).normalized()
			var s_dir := align * (src_skel_xf.basis * (src_rest[src.find_bone(child_name)].origin - src_rest[sb].origin)).normalized()
			if d_dir.length() > 0.5 and s_dir.length() > 0.5 and d_dir.dot(s_dir) < 0.9999:
				rest_fix[bname] = Quaternion(d_dir, s_dir)

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
				world = turn * align * delta * align.inverse() * rest_fix.get(name, Quaternion.IDENTITY) * dst_rest_w[name]
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



## Adds each PLACEHOLDERS clip the library doesn't already have from an FBX.
func _add_placeholders(lib: AnimationLibrary, dst: Skeleton3D) -> void:
	if not lib.has_animation("idle"):
		push_warning("no idle clip; skipping placeholder combat clips")
		return
	var idle := lib.get_animation("idle")
	var skel_xf := _scene_xform(dst)
	var skel_rot := skel_xf.basis.orthonormalized().get_rotation_quaternion()
	var rest := _rest_globals(dst)
	var fwd := _facing(dst, skel_xf, rest)
	var right := fwd.cross(Vector3.UP).normalized()
	var to_world := func(v: Vector3) -> Vector3: return (right * v.x + Vector3.UP * v.y + fwd * v.z)

	# Idle pose at its first frame: local rotations and the hip position.
	var base_local := {}
	var tracks := []  # bone names with rotation tracks
	for i in dst.get_bone_count():
		base_local[i] = dst.get_bone_rest(i).basis.orthonormalized().get_rotation_quaternion()
	for t in idle.get_track_count():
		var bone := String(idle.track_get_path(t).get_concatenated_subnames())
		var i := dst.find_bone(bone)
		if i < 0:
			continue
		if idle.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			base_local[i] = idle.rotation_track_interpolate(t, 0.0)
			tracks.append(bone)
	var hip_track := idle.find_track(NodePath("Skeleton3D:" + ROOT_BONE), Animation.TYPE_POSITION_3D)
	var base_hip: Vector3 = idle.position_track_interpolate(hip_track, 0.0) if hip_track >= 0 else rest[dst.find_bone(ROOT_BONE)].origin

	for anim_name: String in PLACEHOLDERS:
		if lib.has_animation(anim_name):
			continue
		var spec: Dictionary = PLACEHOLDERS[anim_name]
		var anim := Animation.new()
		anim.length = spec.length
		anim.loop_mode = Animation.LOOP_LINEAR if spec.get("loop", false) else Animation.LOOP_NONE
		var out_rot := {}
		for bone: String in tracks:
			var t := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(t, NodePath("Skeleton3D:" + bone))
			out_rot[bone] = t
		var out_pos := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(out_pos, NodePath("Skeleton3D:" + ROOT_BONE))
		var prev_ops: Array = []
		for key: Array in spec.keys:
			var ops: Array = prev_ops if key[1] is String else key[1]
			prev_ops = ops
			# World rotations of the idle pose, parents first.
			var world := {}
			for i in dst.get_bone_count():
				var p := dst.get_bone_parent(i)
				world[i] = (skel_rot if p < 0 else world[p]) * base_local[i]
			var hip_offset := Vector3.ZERO
			for op: Array in ops:
				match op[0]:
					"hips":
						hip_offset += to_world.call(op[1])
					"turn":
						var q := Quaternion(to_world.call(op[2]).normalized(), deg_to_rad(op[3]))
						for i in _subtree(dst, dst.find_bone(op[1])):
							world[i] = q * world[i]
					"aim":
						var i := dst.find_bone(op[1])
						var child := dst.get_bone_children(i)[0]
						var now: Vector3 = ((world[i] as Quaternion) * dst.get_bone_rest(child).origin).normalized()
						var want: Vector3 = (to_world.call(op[2]) as Vector3).normalized()
						var q := Quaternion(now, want)
						for j in _subtree(dst, i):
							world[j] = q * world[j]
			for bone: String in tracks:
				var i := dst.find_bone(bone)
				var p := dst.get_bone_parent(i)
				var parent_w: Quaternion = skel_rot if p < 0 else world[p]
				anim.rotation_track_insert_key(out_rot[bone], key[0], (parent_w.inverse() * world[i]).normalized())
			var hip_w := skel_xf * base_hip + hip_offset
			anim.position_track_insert_key(out_pos, key[0], skel_xf.affine_inverse() * hip_w)
		lib.add_animation(anim_name, anim)
		print("  %-20s %5.2fs  placeholder" % [anim_name, anim.length])
