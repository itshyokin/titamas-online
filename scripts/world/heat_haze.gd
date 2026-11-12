class_name HeatHaze
extends MeshInstance3D
## Hot air shimmering in the distance (deserts, lava fields). Made by AtmosphereManager;
## `strength` comes from the region's "heat_haze" (0–1), less at night. A full-screen
## quad (its shader places it on the screen), hidden while strength is 0.

const SHADER := preload("res://assets/materials/heat_haze.gdshader")

var strength := 0.0:
	set(value):
		strength = value
		if _mat:
			_mat.set_shader_parameter("strength", value)
		visible = value > 0.01

var _mat: ShaderMaterial


func _ready() -> void:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	# First of the see-through things: it redraws a copy of the solid scene, so anything
	# see-through drawn before it (nameplates, target rings, spell effects) would vanish.
	_mat.render_priority = Material.RENDER_PRIORITY_MIN
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	top_level = true
	strength = strength


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position - cam.global_basis.z
