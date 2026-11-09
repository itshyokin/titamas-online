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
			(eye as Node3D).visible = int(_hidden_parts.get("eyes", 0)) <= 0


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


## Two flat eye quads laid on the face, following its shape, on the head bone.
func _build_eyes() -> void:
	var eyes: Dictionary = _look.get("eyes", {})
	var place: Dictionary = _look.get("eye_placement", {})
	var skel := get_skeleton()
	var head := skel.get_node_or_null(("f_" if body_type == BodyType.FEMME else "") + "head") as MeshInstance3D
	if eyes.is_empty() or place.is_empty() or head == null or not ResourceLoader.exists(String(eyes.get("texture", ""))):
		return
	var head_arrays := head.mesh.surface_get_arrays(0)
	var mat := ShaderMaterial.new()
	mat.shader = EYE_SHADER
	mat.set_shader_parameter("eye_texture", load(String(eyes.texture)))
	if ResourceLoader.exists(String(eyes.get("iris", ""))):
		mat.set_shader_parameter("iris_mask", load(String(eyes.iris)))
	mat.set_shader_parameter("eye_color", _look.get("eye_color", Color(0.3, 0.5, 0.8)))
	var y := float(place.height)
	var w := float(place.width) * 0.5
	var h := float(place.tall) * 0.5
	for side: float in [-1.0, 1.0]:
		var cx := side * float(place.apart)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Corners: inner-top, outer-top, outer-bottom, inner-bottom (the texture's outer corner is u = 1).
		var corners := [Vector2(-w, h), Vector2(w, h), Vector2(w, -h), Vector2(-w, -h)]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var pts: Array[Vector3] = []
		for c: Vector2 in corners:
			var px := cx + c.x * side
			var py := y + c.y
			pts.append(Vector3(px, py, _face_z(head_arrays, px, py, w * 0.7) - float(place.forward)))
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[k])
			st.add_vertex(pts[k])
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "Eye"
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var attach := attach_to_bone(mi, "mixamorig_Head", Transform3D.IDENTITY)
		if attach:
			attach.name = "Eye%s" % ("L" if side > 0.0 else "R")
			_eye_nodes.append(attach)
	_update_hidden_parts()


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
