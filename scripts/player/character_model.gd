@tool
class_name CharacterModel
extends Node3D
## Shows one of the two base bodies from base_bodies.glb and tints its skin.
## Lives under Player/Model. The imported body faces -Z (the game's forward),
## so it needs no extra rotation.

enum BodyType { MASC, FEMME }

@export var body_type: BodyType = BodyType.MASC:
	set(value):
		body_type = value
		_apply()

@export var skin_color := Color(0.87, 0.72, 0.6):
	set(value):
		skin_color = value
		_apply()

var _skin_material := StandardMaterial3D.new()


func _ready() -> void:
	_skin_material.roughness = 0.85
	_apply()


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


func _armature_name(type: BodyType) -> String:
	return "Armature_femme" if type == BodyType.FEMME else "Armature_masc"
