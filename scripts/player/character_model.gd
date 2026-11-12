@tool
class_name CharacterModel
extends Node3D
## Shows one of the two base bodies from base_bodies.scn (built by tools/godot/build_bodies.gd), tints its skin and plays
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

## Which clip plays for each role the game asks for ("running", "hanging_idle", "death"...),
## from data/animations.json "roles" (Database → Animations). A role with no entry, or
## whose clip is missing, plays the clip of the same name.
static var roles := {}

var _upper_role := ""
var _current_role := ""
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


## The clip that plays for a role (see `roles`).
func clip_for(role: String) -> String:
	var clip := String(roles.get(role, role))
	if clip != role and _animator and not _animator.has_animation(clip):
		return role
	return clip


## Crossfades to an animation (a role name; see `roles`). Does nothing if it's already playing.
func play(role: String, blend := 0.2, speed := 1.0) -> void:
	var anim := clip_for(role)
	if _animator == null or not _animator.has_animation(anim):
		return
	_current_role = role
	_animator.speed_scale = speed
	if _animator.current_animation != anim:
		_animator.play(anim, blend)


## Stops animating and puts the skeleton in its rest pose (the armour fitter uses this).
func show_rest_pose() -> void:
	if _animator:
		_animator.stop()
	var skel := get_skeleton()
	if skel:
		skel.reset_bone_poses()


## Current playback speed (clip speed × speed scale).
func get_speed() -> float:
	return _animator.get_playing_speed() if _animator else 1.0


## Changes the playback speed of the current animation (0 holds the pose).
func set_speed(speed: float) -> void:
	if _animator:
		_animator.speed_scale = speed


## Plays an animation from a given time (restarts it even if already playing).
func play_from(role: String, time: float, blend := 0.15, speed := 1.0) -> void:
	var anim := clip_for(role)
	if _animator == null or not _animator.has_animation(anim):
		return
	_current_role = role
	_animator.speed_scale = speed
	_animator.play(anim, blend)
	_animator.seek(time, true)


## Horizontal travel baked out of a one-shot animation (see retarget_mixamo.gd),
## one character-local offset per frame at 30 fps. Empty if the animation has none.
func get_root_motion(role: String) -> PackedVector3Array:
	var anim := clip_for(role)
	if _animator == null or not _animator.has_animation(anim):
		return PackedVector3Array()
	return _animator.get_animation(anim).get_meta("root_motion", PackedVector3Array())


## Where the fingertips and toe tips are at `time` into `anim`, in the character's
## own space (feet origin, facing -Z): {"hands": Vector3, "toes": Vector3}.
## Used to line hands up with ledges and rungs. Measured on the actual body, cached.
func measure(role: String, time: float) -> Dictionary:
	var anim := clip_for(role)
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
func bone_contacts(role: String, bones: PackedStringArray, fraction := 0.2) -> PackedFloat32Array:
	var anim := clip_for(role)
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
	# The pinky side of the hand: the pinky, else the ring or middle finger (bodies differ).
	var pinky := -1
	for finger in ["Pinky1", "Ring1", "Middle1"]:
		if pinky < 0:
			pinky = skel.find_bone("mixamorig_%sHand%s" % [side, finger])
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


# --- Gear --------------------------------------------------------------------
# Items (data/items.json entries) worn on the body: fitted (skinned) pieces bend with
# the body and hide the bare parts under them; rigid pieces ride on a bone at the
# position the armour-fitting editor saved for this body type.

var _worn := {}  # tag -> {"nodes", "hides", "item", "with_rigid"}

## The body type changed (worn gear has been moved over; weapons need re-attaching).
signal body_changed
var _hidden_parts := {}  # part name -> how many worn items hide it


func body_key() -> String:
	return "femme" if body_type == BodyType.FEMME else "masc"


## Puts an item on. `tag` names it for take_off() (e.g. the equipment slot).
## `with_rigid` = false skips bone-attached parts (weapons the caller places itself).
func wear(item: Dictionary, tag: String, with_rigid := true) -> Array[Node]:
	take_off(tag)
	var nodes: Array[Node] = []
	var skel := get_skeleton()
	if skel == null or item.is_empty():
		return nodes
	var body := body_key()
	var fitted := String(item.get("fitted_" + body, ""))
	if not fitted.is_empty() and ResourceLoader.exists(fitted):
		var piece := (load(fitted) as PackedScene).instantiate()
		for child in piece.get_children():
			if child is MeshInstance3D:
				piece.remove_child(child)
				child.owner = null
				skel.add_child(child)
				(child as MeshInstance3D).skeleton = NodePath("..")
				nodes.append(child)
		piece.free()
		if weight != 0.0:
			_morph_group(nodes.duplicate())
	if with_rigid:
		var fits: Array = item.get("fit", {}).get(body, [])
		for att: Dictionary in fits:
			var node := attach_fitted(att, String(item.get("model", "")))
			if node:
				nodes.append(node)
	if item.has("tint"):
		_tint(nodes, item.tint)
	var sway := float(item.get("sway", 0.0))
	if sway > 0.0 and not Engine.is_editor_hint():
		_add_sway(nodes, sway, String(item.get("sway_anchors", SWAY_ANCHORS)))
	var hides: Array = _hides_of(item)
	for part in hides:
		_hidden_parts[part] = int(_hidden_parts.get(part, 0)) + 1
	_worn[tag] = {"nodes": nodes, "hides": hides, "item": item, "with_rigid": with_rigid}
	_update_hidden_parts()
	return nodes


## What an item hides: its "hides" list plus its head clipping ("head_clip"):
##   "none"  nothing extra (hats that sit clear of the hair)
##   "hat"   the hair's hat-clip parts (meshes with "hat_clip" in their name, from faces
##           given a "hat_clip" material in Blender); hair without any is hidden whole
##   "total" the whole head: head, face, eyes, hair and facial hair (masked helmets)
static func _hides_of(item: Dictionary) -> Array:
	var hides: Array = (item.get("hides", []) as Array).duplicate()
	match String(item.get("head_clip", "")):
		"hat":
			hides.append("hat_clip")
		"total":
			hides.append_array(["head", "face", "eyes", "hair", "facial_hair"])
	return hides


func take_off(tag: String) -> void:
	if not _worn.has(tag):
		return
	for node in _worn[tag].nodes:
		if is_instance_valid(node):
			node.queue_free()
	for part in _worn[tag].hides:
		_hidden_parts[part] = int(_hidden_parts.get(part, 1)) - 1
	_worn.erase(tag)
	_update_hidden_parts()


## Shows or hides a worn item's bone-attached parts (e.g. the shield while the bow is drawn).
func set_worn_visible(tag: String, on: bool) -> void:
	if not _worn.has(tag):
		return
	for node in _worn[tag].nodes:
		if is_instance_valid(node) and node is BoneAttachment3D:
			(node as Node3D).visible = on


func take_off_all() -> void:
	for tag in _worn.keys():
		take_off(tag)


## One rigid attachment from an item's fit: {model?, bone, grip?, position, rotation, scale}.
## Grip attachments sit in the hand's grip (position/rotation nudge it); others are placed
## at `position`/`rotation` (degrees) in this model's space at the rest pose.
func attach_fitted(att: Dictionary, default_model: String) -> BoneAttachment3D:
	var model := String(att.get("model", default_model))
	var item_node := WeaponModels.build(model)
	if item_node == null:
		return null
	var p: Array = att.get("position", [0, 0, 0])
	var r: Array = att.get("rotation", [0, 0, 0])
	var sc := float(att.get("scale", 1.0))
	var offset := Transform3D(Basis.from_euler(Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2]))).scaled(Vector3.ONE * sc),
		Vector3(p[0], p[1], p[2]))
	var bone := String(att.get("bone", "mixamorig_Hips"))
	if att.get("grip", false):
		var attach := attach_to_hand(item_node, bone.contains("Right"))
		if attach:
			item_node.transform = item_node.transform * offset
		return attach
	return attach_to_bone(item_node, bone, offset)


func _update_hidden_parts() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	var prefix := "f_" if body_type == BodyType.FEMME else ""
	for child in skel.get_children():
		if child is MeshInstance3D and child.owner != null:  # the body's own parts
			var part := String(child.name).trim_prefix(prefix)
			(child as MeshInstance3D).visible = int(_hidden_parts.get(part, 0)) <= 0
	# Helmets can hide the hair, its hat-clip parts, or the whole head (see _hides_of).
	for tag: String in ["hair", "facial_hair", "face", "head"]:
		if not _worn.has(tag):
			continue
		var nodes: Array = _worn[tag].nodes
		# A head variant hides the body's own head itself: only something else hides it.
		var own := 1 if tag == "head" and "head" in (_worn.head.hides as Array) else 0
		var whole := int(_hidden_parts.get(tag, 0)) > own
		var has_clip := nodes.any(func(n: Variant) -> bool: return is_instance_valid(n) and String((n as Node).name).contains("hat_clip"))
		var clip := tag == "hair" and int(_hidden_parts.get("hat_clip", 0)) > 0
		for node in nodes:
			if not is_instance_valid(node):
				continue
			var hide := whole
			if clip:
				hide = hide or not has_clip or String((node as Node).name).contains("hat_clip")
			(node as Node3D).visible = not hide
	for eye in _eye_nodes:
		if is_instance_valid(eye):
			(eye as Node3D).visible = int(_hidden_parts.get("eyes", 0)) <= 0 \
				and not (eye == _face_node and _face_mat and _face_mat.albedo_texture == null)


## Where a bone sits in the rest pose, in this model's space.
func bone_rest_position(bone_name: String) -> Vector3:
	var skel := get_skeleton()
	var bone := skel.find_bone(bone_name) if skel else -1
	if bone < 0:
		return Vector3.ZERO
	return (global_transform.affine_inverse() * skel.global_transform * skel.get_bone_global_rest(bone)).origin


func has_animation(role: String) -> bool:
	return _animator != null and _animator.has_animation(clip_for(role))


func get_animation_length(role: String) -> float:
	var anim := clip_for(role)
	if _animator == null or not _animator.has_animation(anim):
		return 0.0
	return _animator.get_animation(anim).length


## The role (or clip) playing now: the name it was started with.
func current_animation() -> String:
	if _animator == null:
		return ""
	var clip := String(_animator.current_animation)
	return _current_role if not _current_role.is_empty() and clip_for(_current_role) == clip else clip


func animation_position() -> float:
	return _animator.current_animation_position if _animator and _animator.is_playing() else 0.0


func get_skeleton() -> Skeleton3D:
	var armature := get_node_or_null(_armature_name(body_type))
	return armature.get_node("Skeleton3D") if armature else null


## The head-turning modifier on the current body's skeleton (made on first use; only
## in-game, so nothing is saved into scenes). Null in the editor.
## Plays `role` on the upper body only, over whatever the legs are doing (walking while
## drawing a bow, holding a wind-up). Holds at `hold_at` (-1 = the clip's end).
func play_upper(role: String, from := 0.0, speed := 1.0, hold_at := -1.0, blend := 0.12) -> void:
	var layer := _upper_layer()
	var anim := clip_for(role)
	if layer == null or _animator == null or not _animator.has_animation(anim):
		return
	_upper_role = role
	layer.play(_animator.get_animation(anim), from, speed, hold_at, blend)


## Lets the upper body follow the legs' animation again.
func stop_upper(blend := 0.15) -> void:
	_upper_role = ""
	var skel := get_skeleton()
	var layer := skel.get_node_or_null("UpperBodyLayer") as UpperBodyLayer if skel else null
	if layer:
		layer.stop(blend)


## The role playing on the upper body ("" if none).
func upper_role() -> String:
	return _upper_role


func _upper_layer() -> UpperBodyLayer:
	if Engine.is_editor_hint():
		return null
	var skel := get_skeleton()
	if skel == null:
		return null
	var layer := skel.get_node_or_null("UpperBodyLayer") as UpperBodyLayer
	if layer == null:
		layer = UpperBodyLayer.new()
		layer.name = "UpperBodyLayer"
		skel.add_child(layer)
		# Before HeadLook, so the head still turns on top of it.
		var look := skel.get_node_or_null("HeadLook")
		if look:
			skel.move_child(layer, look.get_index())
	return layer


## The sitting layer (SitPose) on this skeleton, made on first use, placed before HeadLook
## so the head still turns to look at things. In-game only.
func sit_pose() -> SitPose:
	if Engine.is_editor_hint():
		return null
	var skel := get_skeleton()
	if skel == null:
		return null
	var sp := skel.get_node_or_null("SitPose") as SitPose
	if sp == null:
		sp = SitPose.new()
		sp.name = "SitPose"
		skel.add_child(sp)
		var look := skel.get_node_or_null("HeadLook")
		if look:
			skel.move_child(sp, look.get_index())
	return sp


func head_look() -> HeadLook:
	if Engine.is_editor_hint():
		return null
	var skel := get_skeleton()
	if skel == null:
		return null
	var look := skel.get_node_or_null("HeadLook") as HeadLook
	if look == null:
		look = HeadLook.new()
		look.name = "HeadLook"
		var db := get_tree().root.get_node_or_null("Database") if is_inside_tree() else null
		var cfg: Dictionary = db.call("look_settings") if db else {}
		look.max_yaw = float(cfg.get("max_yaw", look.max_yaw))
		look.max_pitch = float(cfg.get("max_pitch", look.max_pitch))
		look.speed = float(cfg.get("speed", look.speed))
		look.neck_share = float(cfg.get("neck_share", look.neck_share))
		skel.add_child(look)
	return look


func _apply() -> void:
	if not is_inside_tree() or _batch:
		return
	_skin_material.albedo_color = skin_color
	for type in BodyType.values():
		var armature := get_node_or_null(_armature_name(type)) as Node3D
		if armature == null:
			continue
		armature.visible = type == body_type
		for mesh in armature.find_children("*", "MeshInstance3D", true, false):
			if mesh.owner != null and _is_skin(mesh as MeshInstance3D):  # the body's own skin, not worn gear
				(mesh as MeshInstance3D).material_override = _skin_material
	_apply_morph()
	_setup_animator()
	_rewear()
	_apply_look_parts()


## A body part drawn in skin (tinted); parts with their own textured material, like the
## low-poly body's `underwear`, keep it.
func _is_skin(mi: MeshInstance3D) -> bool:
	var mat := mi.mesh.surface_get_material(0) if mi.mesh and mi.mesh.get_surface_count() > 0 else null
	return mat == null or not (mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null)


## Puts everything worn back on (on the current body type).
func _rewear() -> void:
	for tag in LOOK_TAGS:
		take_off(tag)
	if _worn.is_empty():
		return
	var old := _worn.duplicate()
	for tag: String in old:
		take_off(tag)
	_hidden_parts.clear()
	for tag: String in old:
		wear(old[tag].item, tag, old[tag].with_rigid)
	body_changed.emit()


# --- Appearance (character creator) -------------------------------------------
# Database.resolve_appearance() turns a saved look into what's applied here:
# {body, skin, hair: style entry, hair_color, facial_hair: entry, facial_color,
#  eyes: entry, eye_color, eye_placement: {height, apart, width, tall, forward},
#  height_scale, weight}. Hair and facial hair are worn like gear (tags below).

const LOOK_TAGS := ["underwear", "head", "face", "hair", "facial_hair"]
const EYE_SHADER := preload("res://assets/materials/eye.gdshader")
## How far the "heavy" and "thin" builds push the body out / in (m, at the belly).
const HEAVY_PUSH := 0.032
const THIN_PULL := 0.013

## -1 thin, 0 medium, 1 heavy. Uses "thin"/"heavy" shape keys if the body has them,
## otherwise pushes the mesh in or out (more at the belly, less on the limbs).
var weight := 0.0
var _look := {}
var _eye_nodes: Array[Node] = []

## Face animation (in game only): blinking, a talking mouth while `talking` (dialogue,
## speech bubbles) and a `mood` (appearance.json "face_moods": happy, angry, sad, shy,
## surprised, smug, nervous) that swaps the mouth/brows, adds extras and narrows the eyes.
## Timings: appearance.json "face_motion". `face_library` = the merged appearance lists,
## set by Database.
static var face_library := {}
var talking := false:
	set(value):
		talking = value
		if not value:
			_set_talk_frame(-1)
var mood := "":
	set(value):
		if value != mood:
			mood = value
			_compose_face()
var _face_parts: Array = []  # [part ("" = extra), entry]
var _face_mat: StandardMaterial3D
var _face_node: Node3D
var _eye_mats: Array[ShaderMaterial] = []
var _blink_left := 2.5
var _blink_t := -1.0
var _lid := -1.0
var _talk_frame := -1
var _talk_left := 0.0
var _morph_cache := {}  # "body:weight" -> {part name: Mesh}
var _batch := false


func apply_appearance(look: Dictionary) -> void:
	_look = look
	_batch = true
	scale = Vector3.ONE * float(look.get("height_scale", 1.0))
	weight = float(look.get("weight", 0.0))
	body_type = BodyType.FEMME if String(look.get("body", "masc")) == "femme" else BodyType.MASC
	skin_color = look.get("skin", skin_color)
	_batch = false
	_apply()


func _apply_look_parts() -> void:
	for node in _eye_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_eye_nodes.clear()
	_eye_mats.clear()
	_face_parts.clear()
	_face_mat = null
	_face_node = null
	_lid = -1.0
	if _look.is_empty() or get_skeleton() == null:
		return
	for tag: String in LOOK_TAGS:
		var entry: Dictionary = _look.get(tag, {})
		if entry.has("fitted_masc") or entry.has("model"):
			var item := entry.duplicate()
			if tag in ["head", "face"]:
				pass  # their own materials (a head variant is skin: see below)
			elif tag == "underwear":
				item["tint"] = Color.html(String(entry.get("color", "#cbbd9f")))
			else:
				item["tint"] = _look.get("facial_color" if tag == "facial_hair" else "hair_color", Color(0.3, 0.2, 0.1))
				item["sway"] = float(entry.get("sway", 0.25 if tag == "hair" else 0.1))
				if entry.has("sway_anchors"):
					item["sway_anchors"] = entry.sway_anchors
			var nodes := wear(item, tag)
			if tag == "head":
				for n in nodes:
					if n is MeshInstance3D:
						(n as MeshInstance3D).material_override = _skin_material
	# A painted face (its own texture) replaces the eye quads.
	if not bool((_look.get("face", {}) as Dictionary).get("painted", false)) or not _worn.has("face"):
		_build_eyes()


func _tint(nodes: Array, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for node in nodes:
		var meshes: Array = (node as Node).find_children("*", "MeshInstance3D", true, false)
		if node is MeshInstance3D:
			meshes.append(node)
		for mi: MeshInstance3D in meshes:
			# A textured piece (hair painted in Blender) keeps its texture, multiplied by the
			# colour; plain pieces get the flat colour.
			var textured := false
			for i in (mi.mesh.get_surface_count() if mi.mesh else 0):
				var m := mi.get_active_material(i) as BaseMaterial3D
				if m and m.albedo_texture:
					var t := m.duplicate() as BaseMaterial3D
					t.albedo_color = color
					mi.set_surface_override_material(i, t)
					textured = true
			if not textured:
				mi.material_override = mat


## The face: two eye quads (each its own colour: heterochromia when the look's
## mirror_eyes is off) and one layer picture made of the chosen brows, nose, mouth and
## extras (appearance.json "face_area"), both laid on the head mesh's shape on the head bone.
func _build_eyes() -> void:
	var skel := get_skeleton()
	var head := skel.get_node_or_null(("f_" if body_type == BodyType.FEMME else "") + "head") as MeshInstance3D
	if head == null:
		return
	var head_arrays := head.mesh.surface_get_arrays(0)
	var eyes: Dictionary = _look.get("eyes", {})
	var place: Dictionary = _look.get("eye_placement", {})
	if not eyes.is_empty() and not place.is_empty() and ResourceLoader.exists(String(eyes.get("texture", ""))):
		# The look's own placement (creator "Customize placement"): spacing, height, size.
		var mine := part_placement(_look, "eyes")
		var y := float(place.height) + mine.y * EYE_SHIFT.y
		var w := float(place.width) * 0.5 * mine.z
		var h := float(place.tall) * 0.5 * mine.z
		var apart := float(place.apart) + mine.x * EYE_SHIFT.x
		for side: float in [-1.0, 1.0]:
			var mat := ShaderMaterial.new()
			mat.shader = EYE_SHADER
			mat.set_shader_parameter("eye_texture", load(String(eyes.texture)))
			if ResourceLoader.exists(String(eyes.get("iris", ""))):
				mat.set_shader_parameter("iris_mask", load(String(eyes.iris)))
			# +x is the character's right.
			var col: Color = _look.get("eye_color_right" if side > 0.0 else "eye_color", _look.get("eye_color", Color(0.3, 0.5, 0.8)))
			mat.set_shader_parameter("eye_color", col)
			mat.set_shader_parameter("lid_color", _look.get("skin", skin_color))
			_eye_mats.append(mat)
			var cx := side * apart
			# u = 0 at the inner corner, 1 at the outer one (the texture's outer corner is on the right).
			var mesh := _face_mesh(head_arrays, cx - side * w, cx + side * w, y + h, y - h, float(place.forward), 6, 4)
			_add_face_part(mesh, mat, "Eye%s" % ("R" if side > 0.0 else "L"))
	_build_face_layers(head_arrays)
	_update_hidden_parts()


## Brows, nose, mouth and extras stacked into one picture over the face area.
func _build_face_layers(head_arrays: Array) -> void:
	var area: Dictionary = _look.get("face_area", {})
	if area.is_empty():
		return
	var parts := [["brows", _look.get("brows", {})]]
	for e in (_look.get("extras", []) as Array):
		parts.append(["", e])
	parts.append(["nose", _look.get("nose", {})])
	parts.append(["mouth", _look.get("mouth", {})])
	_face_parts = parts.filter(func(p: Array) -> bool: return p[1] is Dictionary)
	var mat := StandardMaterial3D.new()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.roughness = _skin_material.roughness
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cy := float(area.get("height", 1.7))
	var hw := float(area.get("width", 0.15)) * 0.5
	var hh := float(area.get("tall", 0.2)) * 0.5
	# Pictures are drawn seen from the front: their left is the character's right (+x).
	var mesh := _face_mesh(head_arrays, hw, -hw, cy + hh, cy - hh, float(area.get("forward", 0.0015)), 24, 30)
	_face_mat = mat
	_face_node = _add_face_part(mesh, mat, "FaceLayers")
	_compose_face()


## The face picture for the current mood and talking frame (cached per combination).
func _compose_face() -> void:
	if _face_mat == null:
		return
	var anime := _is_anime_face()
	var m := _mood_data()
	var frames: Array = (face_library.get("face_motion", {}) as Dictionary).get("talk_frames_anime" if anime else "talk_frames", [])
	var layers: Array = []  # [entry, placement Vector3 (x, y, scale), split in two halves (brows)]
	for pair: Array in _face_parts:
		var part: String = pair[0]
		var o: Dictionary = pair[1]
		var place := part_placement(_look, part) if part != "" else Vector3(0, 0, 1)
		if part == "mouth":
			var id := ""
			if _talk_frame >= 0 and _talk_frame < frames.size():
				id = String(frames[_talk_frame])
			elif not m.is_empty():
				id = String(m.get("mouth_anime" if anime else "mouth", m.get("mouth", "")))
			var alt := _face_option("mouths", id)
			if not alt.is_empty():
				o = alt
		elif part == "brows" and not m.is_empty():
			var alt := _face_option("brows", String(m.get("brows_anime" if anime else "brows", m.get("brows", ""))))
			if not alt.is_empty():
				o = alt
			place.y = clampf(place.y + float(m.get("brows_y", 0.0)), -1.0, 1.0)
		if ResourceLoader.exists(String(o.get("texture", ""))):
			layers.append([o, place, part == "brows"])
		if part == "brows":
			# Mood extras (blush, tears, sweat...) go just above the brows.
			for eid in m.get("extras_anime" if anime else "extras", []):
				var e := _face_option("face_extras", String(eid))
				if ResourceLoader.exists(String(e.get("texture", ""))):
					layers.append([e, Vector3(0, 0, 1), false])
	var tex: Texture2D = _face_texture(layers, _look.get("skin", skin_color), _look.get("hair_color", Color(0.25, 0.15, 0.1))) if not layers.is_empty() else null
	_face_mat.albedo_texture = tex
	if is_instance_valid(_face_node):
		_face_node.visible = tex != null and int(_hidden_parts.get("eyes", 0)) <= 0


func _mood_data() -> Dictionary:
	if mood == "":
		return {}
	var d = (face_library.get("face_moods", {}) as Dictionary).get(mood, {})
	return d if d is Dictionary else {}


## Anime-style faces swap to anime mouths / brows for talking and moods.
func _is_anime_face() -> bool:
	for key in ["mouth", "eyes", "brows"]:
		var o = _look.get(key, {})
		if o is Dictionary and String(o.get("id", "")).begins_with("anime_"):
			return true
	return false


static func _face_option(list: String, id: String) -> Dictionary:
	if id == "":
		return {}
	for o in face_library.get(list, []):
		if o is Dictionary and String(o.get("id", "")) == id:
			return o
	return {}


func _set_talk_frame(f: int) -> void:
	if f != _talk_frame:
		_talk_frame = f
		_compose_face()


## Blinks now and then; flaps the mouth between talking frames while `talking`.
func _animate_face(delta: float) -> void:
	var fm: Dictionary = face_library.get("face_motion", {})
	if not _eye_mats.is_empty():
		_blink_left -= delta
		if _blink_left <= 0.0:
			_blink_left = randf_range(float(fm.get("blink_every_min", 2.0)), float(fm.get("blink_every_max", 5.5)))
			_blink_t = 0.0
		var b := 0.0
		if _blink_t >= 0.0:
			var length := maxf(float(fm.get("blink_seconds", 0.14)), 0.02)
			_blink_t += delta
			b = sin(clampf(_blink_t / length, 0.0, 1.0) * PI)
			if _blink_t >= length:
				_blink_t = -1.0
		var lid := maxf(b, float(_mood_data().get("squint", 0.0)))
		if absf(lid - _lid) > 0.01:
			_lid = lid
			for mat in _eye_mats:
				mat.set_shader_parameter("blink", lid)
	if talking and _face_mat:
		_talk_left -= delta
		if _talk_left <= 0.0:
			_talk_left = float(fm.get("talk_frame_seconds", 0.1)) * randf_range(0.8, 1.4)
			var count := ((fm.get("talk_frames_anime" if _is_anime_face() else "talk_frames", []) as Array).size())
			var next := randi_range(-1, count - 1)
			if next == _talk_frame:
				next = -1 if _talk_frame >= 0 else 0
			_set_talk_frame(mini(next, count - 1))


static var _face_cache := {}

## How far placement x / y = ±1 moves a part: eyes in metres (spacing, height); face
## layers in pixels of the 64 × 80 face picture (brows: spacing; nose, mouth: sideways).
const EYE_SHIFT := Vector2(0.012, 0.018)
const LAYER_SHIFT := Vector2(6.0, 8.0)
const PLACEMENT_PARTS := ["eyes", "brows", "nose", "mouth"]


## A look's placement for one part as (x, y, scale): x, y from -1 to 1 (left/right or
## spacing, down/up), scale 0.5–1.6. From look "placement" {part: {x, y, scale}}.
static func part_placement(look: Dictionary, part: String) -> Vector3:
	var all = look.get("placement", {})
	var p = all.get(part, {}) if all is Dictionary else {}
	if not p is Dictionary:
		return Vector3(0, 0, 1)
	return Vector3(clampf(float(p.get("x", 0.0)), -1.0, 1.0), clampf(float(p.get("y", 0.0)), -1.0, 1.0), clampf(float(p.get("scale", 1.0)), 0.5, 1.6))

## Stacks layer pictures (multipliers: 128 grey = the skin / hair colour as it is) into one
## coloured picture. Cached per combination.
static func _face_texture(layers: Array, skin: Color, hair: Color) -> Texture2D:
	var key := skin.to_html() + hair.to_html()
	for l: Array in layers:
		key += "|%s%s" % [String(l[0].texture), str(l[1])]
	if _face_cache.has(key):
		return _face_cache[key]
	var out: Image = null
	for l: Array in layers:
		var o: Dictionary = l[0]
		var img := (load(String(o.texture)) as Texture2D).get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		if out == null:
			out = Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		elif img.get_size() != out.get_size():
			img.resize(out.get_width(), out.get_height(), Image.INTERPOLATE_NEAREST)
		img = _placed(img, l[1], l[2])
		var tint := String(o.get("tint", "skin"))
		# "none" = drawn in real colours (anime mouths, tears...): copied as they are.
		var base := hair if tint == "hair" else (Color.WHITE if tint == "none" else skin)
		var k := 1.0 if tint == "none" else 255.0 / 128.0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a < 0.5:
					continue
				out.set_pixel(x, y, Color(minf(base.r * c.r * k, 1.0), minf(base.g * c.g * k, 1.0), minf(base.b * c.b * k, 1.0), 1.0))
	var tex: Texture2D = ImageTexture.create_from_image(out) if out else null
	_face_cache[key] = tex
	return tex


## A layer moved and scaled by its placement (x, y, scale): scaled around the middle of what's
## drawn on it; `halves` (brows) moves each half of the face apart / together instead of sideways.
static func _placed(img: Image, place: Vector3, halves: bool) -> Image:
	if place.is_equal_approx(Vector3(0, 0, 1)):
		return img
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var mid := w / 2
	var spans: Array = [[0, mid, -1.0], [mid, w, 1.0]] if halves else [[0, w, 1.0]]
	for span: Array in spans:
		var x0: int = span[0]
		var x1: int = span[1]
		# Middle of what's drawn in this span.
		var used := Rect2i()
		var any := false
		for y in h:
			for x in range(x0, x1):
				if img.get_pixel(x, y).a >= 0.5:
					used = Rect2i(x, y, 1, 1) if not any else used.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))
					any = true
		if not any:
			continue
		var c := Vector2(used.position) + Vector2(used.size) * 0.5
		var shift := Vector2(place.x * LAYER_SHIFT.x * float(span[2]), -place.y * LAYER_SHIFT.y)
		for y in h:
			for x in range(0, w):
				# Brows: each half only fills its own side.
				if halves and (x < mid) != (x0 == 0):
					continue
				var src := (Vector2(x + 0.5, y + 0.5) - c - shift) / place.z + c
				var sx := int(floor(src.x))
				var sy := int(floor(src.y))
				if sx < x0 or sx >= x1 or sy < 0 or sy >= h:
					continue
				var col := img.get_pixel(sx, sy)
				if col.a >= 0.5:
					out.set_pixel(x, y, col)
	return out


func _add_face_part(mesh: Mesh, mat: Material, node_name: String) -> Node3D:
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var attach := attach_to_bone(mi, "mixamorig_Head", Transform3D.IDENTITY)
	if attach:
		attach.name = node_name
		_eye_nodes.append(attach)
	return attach


## A grid over the face from x0 (u = 0) to x1 (u = 1) and y_top (v = 0) to y_bottom, each
## point pushed onto the head mesh's front (+ `forward` towards the viewer). Cells that
## miss the face or fold over its edge (big jumps in depth) are left out.
static func _face_mesh(arrays: Array, x0: float, x1: float, y_top: float, y_bottom: float, forward: float, nx: int, ny: int) -> Mesh:
	var z := PackedFloat32Array()
	var pts: Array[Vector3] = []
	for j in ny + 1:
		for i in nx + 1:
			var u := float(i) / nx
			var v := float(j) / ny
			var x := lerpf(x0, x1, u)
			var y := lerpf(y_top, y_bottom, v)
			var fz := _face_z(arrays, x, y, 0.0)
			z.append(fz)
			pts.append(Vector3(x, y, fz - forward))
	var cell := maxf(absf(x1 - x0) / nx, absf(y_top - y_bottom) / ny)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for j in ny:
		for i in nx:
			var ids := [j * (nx + 1) + i, j * (nx + 1) + i + 1, (j + 1) * (nx + 1) + i + 1, (j + 1) * (nx + 1) + i]
			var lo := INF
			var hi := -INF
			for k: int in ids:
				lo = minf(lo, z[k])
				hi = maxf(hi, z[k])
			# A miss reads 0 (the middle of the head); a fold reads a jump of several cells.
			if hi > -0.02 or hi - lo > cell * 3.0:
				continue
			any = true
			for k: int in [0, 1, 2, 0, 2, 3]:
				var idx: int = ids[k]
				st.set_uv(Vector2(float(idx % (nx + 1)) / nx, float(idx / (nx + 1)) / ny))
				st.add_vertex(pts[idx])
	if not any:
		return null
	st.generate_normals()
	return st.commit()


## Front of the face (smallest z) at (x, y): where a line along z meets the head mesh's
## triangles (low-poly heads have too few vertices to go by the nearest one).
static func _face_z(arrays: Array, x: float, y: float, _radius: float) -> float:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index = arrays[Mesh.ARRAY_INDEX]
	if index == null:
		index = PackedInt32Array(range(verts.size()))
	var best := INF
	var p := Vector2(x, y)
	for t in range(0, index.size(), 3):
		var a := verts[index[t]]
		var b := verts[index[t + 1]]
		var c := verts[index[t + 2]]
		# Barycentric coordinates of (x, y) in the triangle seen along z.
		var v0 := Vector2(b.x - a.x, b.y - a.y)
		var v1 := Vector2(c.x - a.x, c.y - a.y)
		var v2 := p - Vector2(a.x, a.y)
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 1e-10:
			continue
		var u := (v2.x * v1.y - v1.x * v2.y) / den
		var v := (v0.x * v2.y - v2.x * v0.y) / den
		if u < 0.0 or v < 0.0 or u + v > 1.0:
			continue
		best = minf(best, a.z + u * (b.z - a.z) + v * (c.z - a.z))
	return best if best != INF else 0.0


func _apply_morph() -> void:
	var armature := get_node_or_null(_armature_name(body_type))
	# Never in the editor: the stored base meshes would get saved into scenes.
	if armature == null or Engine.is_editor_hint():
		return
	var parts: Array = []
	for mi in armature.find_children("*", "MeshInstance3D", true, false):
		if mi.owner == null:
			continue
		if not mi.has_meta("base_mesh"):
			mi.set_meta("base_mesh", mi.mesh)
		parts.append(mi)
	# Shape keys from Blender win if the body has them.
	var keyed := false
	for mi: MeshInstance3D in parts:
		mi.mesh = mi.get_meta("base_mesh")
		var heavy := mi.find_blend_shape_by_name("heavy")
		var thin := mi.find_blend_shape_by_name("thin")
		if heavy >= 0 or thin >= 0:
			keyed = true
			if heavy >= 0:
				mi.set_blend_shape_value(heavy, maxf(weight, 0.0))
			if thin >= 0:
				mi.set_blend_shape_value(thin, maxf(-weight, 0.0))
	if keyed or weight == 0.0:
		return
	var key := "%d:%.2f" % [body_type, weight]
	if not _morph_cache.has(key):
		var morphed := _morph_meshes(parts.map(func(mi: MeshInstance3D) -> Mesh: return mi.get_meta("base_mesh")))
		var by_name := {}
		for i in parts.size():
			by_name[parts[i].name] = morphed[i]
		_morph_cache[key] = by_name
	for mi: MeshInstance3D in parts:
		mi.mesh = _morph_cache[key].get(mi.name, mi.mesh)


## Morphs worn skinned pieces in place (they were cut from the base bodies, so the same
## push keeps them on the body).
func _morph_group(meshes: Array) -> void:
	var morphed := _morph_meshes(meshes.map(func(mi: MeshInstance3D) -> Mesh: return mi.mesh))
	for i in meshes.size():
		(meshes[i] as MeshInstance3D).mesh = morphed[i]


## Pushes every vertex along its normal (averaged over all the meshes at that spot, so
## seams between body parts stay closed) by the build's amount for that part of the body.
func _morph_meshes(meshes: Array) -> Array:
	var pooled := {}
	var all_arrays := []
	for mesh: Mesh in meshes:
		var arrays := mesh.surface_get_arrays(0)
		all_arrays.append(arrays)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in v.size():
			var k := Vector3i((v[i] * 1000.0).round())
			pooled[k] = pooled.get(k, Vector3.ZERO) + n[i]
	var push := HEAVY_PUSH * weight if weight > 0.0 else THIN_PULL * weight
	var out := []
	for a in all_arrays.size():
		var arrays: Array = all_arrays[a]
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in v.size():
			var nrm: Vector3 = pooled[Vector3i((v[i] * 1000.0).round())].normalized()
			v[i] += nrm * push * _build_factor(v[i])
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_TANGENT] = null
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var src: Mesh = meshes[a]
		if src.get_surface_count() > 0 and src.surface_get_material(0):
			mesh.surface_set_material(0, src.surface_get_material(0))
		out.append(mesh)
	return out


## How much of the build's push a point gets (rest pose, metres): most on the belly and
## hips, less on the arms and legs, a little on the face, almost none on hands and feet.
static func _build_factor(p: Vector3) -> float:
	var ax := absf(p.x)
	var belly := 0.7 * smoothstep(0.02, -0.07, p.z) * smoothstep(0.92, 1.05, p.y) * smoothstep(1.38, 1.22, p.y)
	var torso := 1.0 + belly + 0.2 * smoothstep(1.0, 0.9, p.y)
	var leg := lerpf(0.3, 0.85, smoothstep(0.12, 0.88, p.y)) * lerpf(0.15, 1.0, smoothstep(0.05, 0.14, p.y))
	var f := lerpf(leg, torso, smoothstep(0.82, 0.98, p.y))
	f = lerpf(f, 0.12, smoothstep(1.52, 1.62, p.y) * smoothstep(0.2, 0.14, ax))
	var arm := lerpf(0.55, 0.25, smoothstep(0.3, 0.7, ax)) * lerpf(1.0, 0.12, smoothstep(0.69, 0.76, ax))
	return lerpf(f, arm, smoothstep(0.2, 0.3, ax) * smoothstep(1.2, 1.3, p.y))


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
	_animator.play(current if not current.is_empty() else clip_for(default_animation))


func _armature_name(type: BodyType) -> String:
	return "Armature_femme" if type == BodyType.FEMME else "Armature_masc"


# --- Hair and cape sway ------------------------------------------------------------------

const SWAY_SHADER := preload("res://assets/materials/cloth_sway.gdshader")

## Hair/cape sway tuning (animations.json "sway", set by Database): movement, max_swing,
## stiffness, damping, flutter.
static var sway_settings := {}

var _sway: Array = []  # [MeshInstance3D, [ShaderMaterial...]]
var _sway_last := Vector3.INF
var _sway_off := Vector3.ZERO  # world-space trail (spring)
var _sway_vel := Vector3.ZERO


## Materials that stay put when a piece sways (unless an item lists its own "sway_anchors"):
## hair clips (the part against the scalp) and metal fittings on capes.
const SWAY_ANCHORS := "hair_clip,hat_clip,gold,metal,anchor"


## Swaps worn meshes' materials for cloth_sway.gdshader (same colour/texture) so they
## swing with movement and flutter in the wind (items/looks with "sway" > 0). Surfaces whose
## material (or mesh) name contains one of `anchors` (comma list) stay still: a cape's metal
## pauldrons, a hair style's hair_clip. Each swaying surface hangs from its own top edge.
func _add_sway(nodes: Array, amount: float, anchors := SWAY_ANCHORS) -> void:
	var keys: Array[String] = []
	for k in anchors.split(",", false):
		if k.strip_edges() != "":
			keys.append(k.strip_edges().to_lower())
	for node in nodes:
		var meshes: Array = (node as Node).find_children("*", "MeshInstance3D", true, false)
		if node is MeshInstance3D:
			meshes.append(node)
		for mi: MeshInstance3D in meshes:
			if mi.mesh == null:
				continue
			var mats: Array = []
			for i in mi.mesh.get_surface_count():
				var own := mi.mesh.surface_get_material(i)
				var label := (String(own.resource_name) if own else "") + " " + String(mi.name)
				if _sway_anchor(label.to_lower(), keys):
					continue  # the anchor keeps its material and doesn't move
				var top := -INF
				var bottom := INF
				for v: Vector3 in mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
					top = maxf(top, v.y)
					bottom = minf(bottom, v.y)
				var src := mi.get_active_material(i)
				var sm := ShaderMaterial.new()
				sm.shader = SWAY_SHADER
				if src is BaseMaterial3D:
					var b := src as BaseMaterial3D
					sm.set_shader_parameter("albedo", b.albedo_color)
					sm.set_shader_parameter("roughness", b.roughness)
					if b.albedo_texture:
						sm.set_shader_parameter("albedo_tex", b.albedo_texture)
						sm.set_shader_parameter("use_tex", true)
					if b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
						sm.set_shader_parameter("alpha_cut", b.alpha_scissor_threshold)
				sm.set_shader_parameter("top", top)
				sm.set_shader_parameter("hang", maxf(top - bottom, 0.05))
				sm.set_shader_parameter("amount", amount)
				sm.set_shader_parameter("flutter", float(sway_settings.get("flutter", 0.012)))
				mats.append([i, sm])
			if mats.is_empty():
				continue
			# A tinted plain piece has one material_override for every surface: move it onto
			# the anchor surfaces so clearing it doesn't strip their colour.
			var shared := mi.material_override
			mi.material_override = null
			var swaying := {}
			for e in mats:
				swaying[e[0]] = true
				mi.set_surface_override_material(e[0], e[1])
			if shared:
				for i in mi.mesh.get_surface_count():
					if not swaying.has(i):
						mi.set_surface_override_material(i, shared)
			_sway.append([mi, mats.map(func(e: Array) -> ShaderMaterial: return e[1])])
	set_process(true)


static func _sway_anchor(label: String, keys: Array[String]) -> bool:
	# A material named *sway* (e.g. "chainmail_sway") always swings, even when another
	# keyword ("chainmail") would anchor it.
	if label.contains("sway"):
		return false
	for k in keys:
		if label.contains(k):
			return true
	return false


func _process(delta: float) -> void:
	if (_face_mat or not _eye_mats.is_empty()) and not Engine.is_editor_hint():
		_animate_face(delta)
	if _sway.is_empty() or delta <= 0.0:
		return
	# Trail behind the way the body moves (spring, so it overshoots and settles).
	var pos := global_position
	var vel := Vector3.ZERO if _sway_last == Vector3.INF else (pos - _sway_last) / delta
	_sway_last = pos
	if vel.length() > 30.0:
		vel = Vector3.ZERO  # teleports
	var goal := -vel * float(sway_settings.get("movement", 0.02))
	goal.y = clampf(-vel.y * 0.03, -0.15, 0.15) + minf(Vector2(vel.x, vel.z).length() * 0.012, 0.12)
	goal = goal.limit_length(float(sway_settings.get("max_swing", 0.18)))
	_sway_vel += ((goal - _sway_off) * float(sway_settings.get("stiffness", 110.0)) - _sway_vel * float(sway_settings.get("damping", 16.0))) * delta
	_sway_off += _sway_vel * delta
	for i in range(_sway.size() - 1, -1, -1):
		var e: Array = _sway[i]
		var mi = e[0]
		if not is_instance_valid(mi) or not (mi as Node).is_inside_tree():
			_sway.remove_at(i)
			continue
		var local := (mi as Node3D).global_basis.inverse() * _sway_off
		for sm: ShaderMaterial in e[1]:
			sm.set_shader_parameter("trail", local)
