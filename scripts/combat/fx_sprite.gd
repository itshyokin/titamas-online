class_name FxSprite
extends MeshInstance3D
## One effect sprite (see AbilityFX): a textured quad that faces the camera, or lies flat
## (`flat`, for the ground), plays a strip of frames and either fades out and frees itself
## or loops until its parent goes.

var seconds := 0.5
var frames := 1
var looping := false
var flat := false
var _age := 0.0
var _mat: StandardMaterial3D
var _alpha := 1.0


static func make(cfg: Dictionary, color: Color, loop: bool, on_ground: bool) -> FxSprite:
	var tex := AbilityFX.texture(String(cfg.get("sprite", "")))
	if tex == null:
		return null
	var s := FxSprite.new()
	s.frames = maxi(int(cfg.get("frames", 1)), 1)
	s.seconds = maxf(float(cfg.get("seconds", 0.5)), 0.05)
	s.looping = loop
	s.flat = on_ground
	var size := maxf(float(cfg.get("size", 1.0)), 0.01)
	var glow := String(cfg.get("look", "glow")) != "drawn"
	# A frame's shape: wide strips aren't stretched.
	var frame_w := float(tex.get_width()) / s.frames
	var aspect := frame_w / maxf(float(tex.get_height()), 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(size * minf(aspect, 1.0) if aspect < 1.0 else size, size / aspect if aspect > 1.0 else size)
	if on_ground:
		quad.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if glow else BaseMaterial3D.BLEND_MODE_MIX
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_color = Color(color.r, color.g, color.b, 1.0) if glow else Color.WHITE
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.uv1_scale = Vector3(1.0 / s.frames, 1.0, 1.0)
	if not on_ground:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
	# Glows show through walls a little less harshly than no depth test at all would.
	mat.disable_receive_shadows = true
	quad.material = mat
	s.mesh = quad
	s._mat = mat
	s._alpha = 1.0
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s


func _process(delta: float) -> void:
	_age += delta
	var t := _age / seconds
	if looping:
		_set_frame(int(fmod(t, 1.0) * frames))
		return
	if t >= 1.0:
		queue_free()
		return
	_set_frame(mini(int(t * frames), frames - 1))
	# Pops out fast, then fades over the last third (the ground ones just fade in and out).
	if flat:
		_fade(minf(t / 0.12, 1.0) * (1.0 - smoothstep(0.65, 1.0, t)))
	else:
		scale = Vector3.ONE * lerpf(0.7, 1.0, 1.0 - pow(1.0 - minf(t / 0.25, 1.0), 2.0))
		_fade(1.0 - smoothstep(0.6, 1.0, t))


func _set_frame(i: int) -> void:
	if frames > 1:
		_mat.uv1_offset.x = float(i) / frames


func _fade(a: float) -> void:
	var c := _mat.albedo_color
	c.a = a * _alpha
	_mat.albedo_color = c
