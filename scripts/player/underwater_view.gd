class_name UnderwaterView
extends CanvasLayer
## When the camera dips under water (the sea or a water volume): a blue-green wobbly
## view, bubbles drifting up, and muffled sound effects and ambience. Added by
## PlayerController.

const MUFFLED_BUSES := ["SFX", "Ambience", "Footsteps"]

var _rect: ColorRect
var _mat: ShaderMaterial
var _bubbles: CPUParticles3D
var _under := false
var _filters := {}  # bus index -> effect index


func _ready() -> void:
	layer = -1  # under the HUD
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://assets/materials/underwater.gdshader")
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)
	for bus_name: String in MUFFLED_BUSES:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus < 0:
			continue
		var found := -1
		for i in AudioServer.get_bus_effect_count(bus):
			if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
				found = i
		if found < 0:
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 700.0
			AudioServer.add_bus_effect(bus, lp)
			found = AudioServer.get_bus_effect_count(bus) - 1
		_filters[bus] = found
		AudioServer.set_bus_effect_enabled(bus, found, false)


func _exit_tree() -> void:
	_set_muffled(false)


func _process(_delta: float) -> void:
	var player := get_parent() as PlayerController
	var cam := get_viewport().get_camera_3d()
	if player == null or cam == null:
		return
	var at := cam.global_position
	var water = player._water_at(at)
	var under: bool = water != null and at.y < water.surface_height() - 0.05
	if under != _under:
		_under = under
		_rect.visible = under
		_set_muffled(under)
		_set_bubbles(under, cam)
	if under:
		_mat.set_shader_parameter("depth", water.surface_height() - at.y)
		var lava: bool = water is WaterVolume and water.lava
		_mat.set_shader_parameter("tint", Color(0.9, 0.3, 0.05) if lava else Color(0.12, 0.45, 0.5))


func _set_muffled(on: bool) -> void:
	for bus: int in _filters:
		if bus < AudioServer.bus_count and _filters[bus] < AudioServer.get_bus_effect_count(bus):
			AudioServer.set_bus_effect_enabled(bus, _filters[bus], on)


func _set_bubbles(on: bool, cam: Camera3D) -> void:
	if _bubbles == null and on:
		_bubbles = CPUParticles3D.new()
		_bubbles.amount = 24
		_bubbles.lifetime = 2.5
		_bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_bubbles.emission_box_extents = Vector3(2.0, 1.0, 1.5)
		_bubbles.direction = Vector3.UP
		_bubbles.spread = 15.0
		_bubbles.gravity = Vector3(0, 0.6, 0)
		_bubbles.initial_velocity_min = 0.3
		_bubbles.initial_velocity_max = 0.8
		_bubbles.scale_amount_min = 0.4
		_bubbles.scale_amount_max = 1.2
		var sphere := SphereMesh.new()
		sphere.radius = 0.025
		sphere.height = 0.05
		sphere.radial_segments = 6
		sphere.rings = 3
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.95, 1.0, 0.55)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sphere.material = m
		_bubbles.mesh = sphere
		cam.add_child(_bubbles)
		_bubbles.position = Vector3(0, -0.5, -2.5)
	if _bubbles:
		_bubbles.emitting = on
