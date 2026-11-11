@tool
extends Node
## Renders a character look (NPC / enemy "look" + "equipment", same as the game) to two
## pictures for the Database page: the whole body and a face close-up. Used by the plugin
## (POST /api/preview) inside the editor, and by tests outside it.
##
## The editor has no Database autoload, so a private instance of scripts/core/database.gd
## reads the data files (appearance, Body Models pieces, items, species) for each picture.

const BODIES := "res://assets/models/characters/base_bodies.scn"
const MODEL_SCRIPT := "res://scripts/player/character_model.gd"
const SIZE_BODY := Vector2i(260, 420)
const SIZE_FACE := Vector2i(260, 260)

var _busy := false
var _queue: Array = []  # [look, equipment, Callable(result: Dictionary)]


## Calls done({body: PackedByteArray png, face: png}) or done({error}) after a few frames.
func render(look: Dictionary, equipment: Dictionary, done: Callable) -> void:
	_queue.append([look, equipment, done])
	if not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var job: Array = _queue.pop_front()
	var result := await _render(job[0], job[1])
	(job[2] as Callable).call(result)
	_next.call_deferred()


func _render(look: Dictionary, equipment: Dictionary) -> Dictionary:
	var db: Object = load("res://scripts/core/database.gd").new()
	for which in ["body_models", "appearance", "items", "species"]:
		db.call("_load", which)

	var vp_body := SubViewport.new()
	vp_body.size = SIZE_BODY
	vp_body.own_world_3d = true
	vp_body.msaa_3d = Viewport.MSAA_4X
	vp_body.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp_body)
	var root := Node3D.new()
	vp_body.add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.17, 0.18, 0.22)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.62, 0.68)
	env.environment.ambient_light_energy = 0.9
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 160, 0)  # from in front, a little to the side
	sun.light_energy = 1.1
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -30, 0)
	fill.light_energy = 0.35
	root.add_child(fill)

	var holder := Node3D.new()
	holder.rotation_degrees.y = 180.0 + 18.0  # face the camera (+Z), turned a little
	root.add_child(holder)
	var model: Node3D = (load(BODIES) as PackedScene).instantiate()
	model.set_script(load(MODEL_SCRIPT))
	holder.add_child(model)
	await get_tree().process_frame
	var resolved: Dictionary = db.call("resolve_appearance", look)
	model.call("apply_appearance", resolved)
	for slot in ["head", "shoulders", "chest", "hands", "legs", "feet", "off_hand"]:
		var item: Dictionary = db.call("item", String(equipment.get(slot, "")))
		if not item.is_empty():
			model.call("wear", item, slot)
	var main: Dictionary = db.call("item", String(equipment.get("primary", "")))
	if not main.is_empty():
		var fits: Array = main.get("fit", {}).get(String(model.call("body_key")), [])
		model.call("attach_fitted", fits[0] if not fits.is_empty() else {"bone": "mixamorig_RightHand", "grip": true}, String(main.get("model", "")))

	var h := float(resolved.get("height_scale", 1.0))
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp_body.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 1.0 * h, 4.4 * h), Vector3(0.0, 0.93 * h, 0.0))
	cam.current = true

	var vp_face := SubViewport.new()
	vp_face.size = SIZE_FACE
	vp_face.world_3d = vp_body.find_world_3d()
	vp_face.msaa_3d = Viewport.MSAA_4X
	vp_face.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp_face)
	var cam2 := Camera3D.new()
	cam2.fov = 30.0
	vp_face.add_child(cam2)
	cam2.look_at_from_position(Vector3(0.0, 1.72 * h, 0.75 * h), Vector3(0.0, 1.69 * h, 0.0))
	cam2.current = true

	for i in 3:
		await get_tree().process_frame
		if Engine.is_editor_hint():
			RenderingServer.force_draw(false)
	var out := {}
	var img_body := vp_body.get_texture().get_image()
	var img_face := vp_face.get_texture().get_image()
	if img_body == null or img_face == null:
		out = {"error": "Nothing rendered (no graphics?)"}
	else:
		out = {"body": img_body.save_png_to_buffer(), "face": img_face.save_png_to_buffer()}
	vp_face.queue_free()
	vp_body.queue_free()
	db.free()
	return out
