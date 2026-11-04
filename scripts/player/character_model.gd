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
	_animator.play(current if not current.is_empty() else default_animation)


func _armature_name(type: BodyType) -> String:
	return "Armature_femme" if type == BodyType.FEMME else "Armature_masc"
