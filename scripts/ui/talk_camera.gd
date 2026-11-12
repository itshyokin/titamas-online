class_name TalkCamera
extends Camera3D
## Conversation camera: while someone talks to the player (DialogueBox with a speaker who
## has a character model), the view glides in over the player's shoulder: the player on
## the left, the speaker on the right, facing the camera. When the talk ends it glides
## back to the game camera. Boxes opened one after another (an event's texts and choices)
## keep the same shot. Settings: player.json "dialogue" camera, camera_back, camera_side,
## camera_height, camera_aim, camera_fov, camera_range, camera_glide (Database → Player).
## The shot also darkens the screen's edges (`vignette`) and blurs what's behind the
## speaker (`dof`, `dof_amount`, `dof_behind`; depth of field needs Forward+).

static var _cam: TalkCamera

var player: Node3D
var speaker: Node3D
var cfg := {}
var _from: Camera3D  # the game camera to hand back to
var _blend := 0.0     # 0 = at the game camera, 1 = at the talk shot
var _leaving := false
var _leave_at := 0
var _veil: CanvasLayer
var _veil_mat: ShaderMaterial
var _attrs: CameraAttributesPractical


## Starts (or re-aims) the talk shot. Does nothing while another camera (a cutscene) is in
## charge, when the speaker is the player or too far away.
static func engage(who: Node3D, talker: Node3D, settings: Dictionary) -> void:
	if not bool(settings.get("camera", true)) or who == null or talker == null or who == talker:
		return
	if who.global_position.distance_to(talker.global_position) > float(settings.get("camera_range", 7.0)):
		return
	if is_instance_valid(_cam):
		_cam.player = who
		_cam.speaker = talker
		_cam.cfg = settings
		_cam._leaving = false
		return
	var current := who.get_viewport().get_camera_3d()
	var rig := who.get_tree().get_first_node_in_group("player_camera")
	if current == null or rig == null or not rig.is_ancestor_of(current):
		return  # a cutscene camera is in charge
	var c := TalkCamera.new()
	c.player = who
	c.speaker = talker
	c.cfg = settings
	c._from = current
	c.fov = current.fov
	who.get_tree().root.add_child(c)
	c.global_transform = current.global_transform
	c.current = true
	c._build_mood()
	_cam = c
	# The player turns to face whoever they're talking to.
	var model = who.get("model")
	if model is Node3D:
		var to := talker.global_position - who.global_position
		if Vector2(to.x, to.z).length() > 0.1:
			(model as Node3D).rotation.y = atan2(-to.x, -to.z)


## The conversation box closed: glide back unless another box opens straight away.
static func release() -> void:
	if is_instance_valid(_cam):
		_cam._leaving = true
		_cam._leave_at = Time.get_ticks_msec() + 200


func _process(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(speaker) or not is_instance_valid(_from):
		_hand_back()
		return
	var glide := maxf(float(cfg.get("camera_glide", 0.45)), 0.05)
	var leaving := _leaving and Time.get_ticks_msec() >= _leave_at and not DialogueBox.is_open
	_blend = clampf(_blend + (delta / glide) * (-1.0 if leaving else 1.0), 0.0, 1.0)
	if leaving and _blend <= 0.0:
		_hand_back()
		return
	var shot := _shot()
	var k := smoothstep(0.0, 1.0, _blend)
	global_transform = _from.global_transform.interpolate_with(shot, k)
	fov = lerpf(_from.fov, float(cfg.get("camera_fov", 45.0)), k)
	_update_mood(k)


## Vignette overlay + depth of field on this camera.
func _build_mood() -> void:
	_veil = CanvasLayer.new()
	_veil.layer = 0  # over the world, under the HUD and speech bubbles
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil_mat = ShaderMaterial.new()
	_veil_mat.shader = load("res://assets/materials/talk_vignette.gdshader")
	rect.material = _veil_mat
	_veil.add_child(rect)
	get_tree().root.add_child(_veil)
	var base := _from.attributes if _from else null
	_attrs = (base.duplicate() as CameraAttributesPractical) if base is CameraAttributesPractical else CameraAttributesPractical.new()
	attributes = _attrs


func _update_mood(k: float) -> void:
	if _veil_mat:
		_veil_mat.set_shader_parameter("strength", float(cfg.get("vignette", 0.6)) * k)
	if _attrs and is_instance_valid(speaker):
		var on := bool(cfg.get("dof", true))
		_attrs.dof_blur_far_enabled = on and k > 0.01
		_attrs.dof_blur_far_distance = global_position.distance_to(speaker.global_position) + float(cfg.get("dof_behind", 1.5))
		_attrs.dof_blur_far_transition = 3.0
		_attrs.dof_blur_amount = float(cfg.get("dof_amount", 0.12)) * k


## Behind and beside the player's head, aimed so the speaker sits right of centre.
func _shot() -> Transform3D:
	var a := DialogueBox._head_top(player) - Vector3.UP * 0.35
	var b := DialogueBox._head_top(speaker) - Vector3.UP * 0.4
	var d := b - a
	d.y = 0.0
	var dist := maxf(d.length(), 0.5)
	d /= dist
	var right := d.cross(Vector3.UP)
	var pos := a - d * float(cfg.get("camera_back", 1.3)) + right * float(cfg.get("camera_side", 0.75)) \
		+ Vector3.UP * float(cfg.get("camera_height", 0.1))
	var aim := b - right * dist * float(cfg.get("camera_aim", 0.22))
	return Transform3D(Basis.looking_at(aim - pos, Vector3.UP), pos)


func _exit_tree() -> void:
	if is_instance_valid(_veil):
		_veil.queue_free()


func _hand_back() -> void:
	if is_instance_valid(_from):
		_from.current = true
	if _cam == self:
		_cam = null
	queue_free()
