class_name CharacterPreview
extends SubViewportContainer
## A little 3D view of a character (its own world: camera, lights, the body with a look
## and gear), idling. Drag with the left mouse button to turn it. Used by the paper doll
## in the character window and the Codex's Character page.
##   show_player(player)          the player's look and what they're wearing
##   show_look(look, equipment)   any look (appearance.json choices) and {slot: item id}

var _viewport: SubViewport
var _model: CharacterModel
var _pivot: Node3D
var _camera: Camera3D
var _dragging := false
var _yaw := PI  # models face -Z; turn them to the camera
## How much of the body the camera frames (1 = head to toe).
var framing := 1.0
## Portrait (HUD frames): head and shoulders, no dragging, a still picture.
var portrait := false
var _redraw := 0.0


func _init(view_size := Vector2i(160, 230)) -> void:
	stretch = true
	custom_minimum_size = view_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.size = view_size
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.68)
	e.ambient_light_energy = 0.9
	env.environment = e
	_viewport.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.2
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.7, 0.8, 1.0)
	_viewport.add_child(rim)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	var body := (load("res://assets/models/characters/base_bodies.scn") as PackedScene).instantiate()
	body.set_script(load("res://scripts/player/character_model.gd"))
	_pivot.add_child(body)
	_model = body as CharacterModel
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_viewport.add_child(_camera)
	_camera.current = true


func _ready() -> void:
	if portrait:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_yaw = PI - 0.35  # a little three-quarter turn
	_pivot.rotation.y = _yaw
	_frame()
	if _model.has_method("play"):
		_model.call_deferred("play", "idle")
	if portrait:
		_snapshot()


## Portraits are still pictures: drawn for a moment (until the idle pose has settled),
## then the view stops redrawing and the model stops animating. Redrawn when the look
## or gear changes.
func _snapshot() -> void:
	_redraw = 0.35
	_model.process_mode = Node.PROCESS_MODE_INHERIT
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _process(delta: float) -> void:
	if not portrait or _redraw <= 0.0:
		return
	_redraw -= delta
	if _redraw <= 0.0:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE  # this last frame stays
		_model.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)


func _frame() -> void:
	var h := 1.86 * _pivot.scale.y
	if portrait:
		var head := _head_height()
		_camera.fov = 26.0
		_camera.position = Vector3(0, head - 0.02, 0.95)
		_camera.look_at(Vector3(0, head - 0.06, 0))
		return
	var aim_y := h * (0.52 if framing >= 1.0 else 1.0 - framing * 0.5)
	var dist := h * framing * 2.15
	_camera.position = Vector3(0, aim_y + 0.05, dist)
	_camera.look_at(Vector3(0, aim_y, 0))


## The player's look (from the saved character) and their equipped gear.
func show_player(player: Node) -> void:
	var look := {}
	var session := get_tree().root.get_node_or_null("GameSession") if is_inside_tree() else null
	if session and session.call("active"):
		look = session.get("data").get("look", {})
	var inv := player.get_node_or_null("Inventory") if player else null
	show_look(look, inv.get("equipped") if inv else {})


func show_look(look: Dictionary, equipment: Dictionary) -> void:
	var a := Database.resolve_appearance(look)
	_model.take_off_all()
	_model.apply_appearance(a)
	# The model node's scale is the character's height; frame it.
	_pivot.scale = Vector3.ONE
	for slot in ["head", "shoulders", "chest", "hands", "legs", "feet", "off_hand"]:
		var item := Database.item(String(equipment.get(slot, "")))
		if not item.is_empty():
			_model.wear(item, slot)
	_frame()
	if portrait and is_inside_tree():
		_snapshot()


## Height of the head (model space), from the head bone when there is one.
func _head_height() -> float:
	var sk := _model.find_children("*", "Skeleton3D", true, false)
	if not sk.is_empty() and is_inside_tree():
		var skel := sk[0] as Skeleton3D
		var b := skel.find_bone("mixamorig_Head")
		if b >= 0:
			var p := _pivot.global_transform.affine_inverse() * (skel.global_transform * skel.get_bone_global_rest(b)).origin
			return p.y + 0.1
	return 1.62 * _model.scale.y


func _gui_input(event: InputEvent) -> void:
	if portrait:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_yaw += event.relative.x * 0.012
		_pivot.rotation.y = _yaw
		accept_event()
