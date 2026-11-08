@tool
class_name HomePoint
extends StaticBody3D
## A place the player can make their home: an inn bed, a camp bedroll, a house. Walk up
## and press Jump / talk (Space, A); choosing "Make this my home" sets where the
## hearthstone takes them. The spot is a "Spawn" Marker3D child if there is one,
## otherwise just in front of it.
##
## Drop scenes/world/home_point.tscn into a level and give it a name. It builds a simple
## bed to show it; turn Build Bed off and add your own model as a child instead.

## What it's called in the hearthstone's description ("the Riverside Inn").
@export var home_name := "the inn":
	set(value):
		home_name = value
@export var build_bed := true:
	set(value):
		build_bed = value
		if is_inside_tree():
			_build()
## What it says when you walk up.
@export_multiline var greeting := "A soft bed and a warm blanket. You could rest here."

const TALK_RANGE := 2.6

var _prompt: Label3D
var _bed: Node3D
var _settled := false


func _ready() -> void:
	_build()
	if Engine.is_editor_hint():
		return
	add_to_group("talkable")
	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.pixel_size = 0.003
	_prompt.font_size = 36
	_prompt.outline_size = 10
	_prompt.no_depth_test = true
	_prompt.position = Vector3.UP * 1.3
	_prompt.visible = false
	add_child(_prompt)


func _build() -> void:
	if _bed and is_instance_valid(_bed):
		_bed.queue_free()
		_bed = null
	for c in get_children():
		if c is CollisionShape3D and c.name == "BedShape":
			c.queue_free()
	if not build_bed:
		return
	_bed = Node3D.new()
	_bed.name = "Bed"
	add_child(_bed)  # not owned: never saved into the scene
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.28, 0.16)
	var sheet := StandardMaterial3D.new()
	sheet.albedo_color = Color(0.82, 0.78, 0.68)
	var blanket := StandardMaterial3D.new()
	blanket.albedo_color = Color(0.55, 0.18, 0.16)
	var parts := [
		[Vector3(1.0, 0.3, 2.1), Vector3(0, 0.25, 0), wood],  # frame
		[Vector3(0.92, 0.14, 2.0), Vector3(0, 0.45, 0), sheet],  # mattress
		[Vector3(0.94, 0.06, 1.3), Vector3(0, 0.53, 0.32), blanket],  # blanket
		[Vector3(0.6, 0.12, 0.35), Vector3(0, 0.56, -0.75), sheet],  # pillow
		[Vector3(1.0, 0.75, 0.08), Vector3(0, 0.45, -1.05), wood],  # headboard
	]
	for part: Array in parts:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		mi.mesh = box
		mi.position = part[1]
		mi.material_override = part[2]
		_bed.add_child(mi)
	var shape := CollisionShape3D.new()
	shape.name = "BedShape"
	var b := BoxShape3D.new()
	b.size = Vector3(1.0, 0.6, 2.1)
	shape.shape = b
	shape.position = Vector3(0, 0.3, 0)
	add_child(shape)


## Where the player stands when they come home.
func spawn_point() -> Vector3:
	var marker := get_node_or_null("Spawn") as Node3D
	if marker:
		return marker.global_position
	return global_position + global_basis.x * 1.2 + Vector3.UP * 0.3


func _is_home() -> bool:
	var home: Dictionary = GameSession.data.get("home", {})
	var p: Array = home.get("position", [])
	return p.size() == 3 and Vector3(p[0], p[1], p[2]).distance_to(spawn_point()) < 1.0


func can_talk() -> bool:
	return not Engine.is_editor_hint() and not DialogueBox.is_open and Time.get_ticks_msec() - DialogueBox.closed_at > 300


func talk(_player: Node3D) -> void:
	var title := home_name.capitalize() if home_name.begins_with("the ") == false else home_name.substr(4).capitalize()
	if not GameSession.active():
		DialogueBox.open(self, title, "", [greeting, "(Playing without a saved character: homes can't be set.)"], Callable())
		return
	if _is_home():
		DialogueBox.open(self, title, "", ["This is your home. Your hearthstone brings you back here."], Callable())
		return
	var scene := get_tree().current_scene
	DialogueBox.open(self, title, "", [greeting], Callable(), [
		["Make this my home", func() -> String:
			GameSession.set_home(scene.scene_file_path if scene else GameSession.START_SCENE, spawn_point(), home_name)
			return "Your home is now %s. Your hearthstone will bring you back here." % home_name],
		["Not now", func() -> String: return ""],
	])


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _settled:
		# Sit on the ground once the terrain under it has loaded.
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 30.0, global_position + Vector3.DOWN * 60.0, 1)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return
		_settled = true
		global_position = hit.position
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var show := player != null and can_talk() and player.global_position.distance_to(global_position) <= TALK_RANGE
	_prompt.visible = show
	if show:
		var keys := GameSettings.events_for("jump", GameSettings.gamepad)
		var key := GameSettings.event_name(keys[0]) if not keys.is_empty() else "Jump"
		_prompt.text = "%s  Rest" % key
