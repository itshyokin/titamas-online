@tool
class_name LootChest
extends StaticBody3D
## A chest (or weapon rack) the player opens once: walk up and press Interact (E, A)
## (Space, A) to take what's inside. Each character can open it once; which chests they've
## opened is saved with them (GameSession.data.opened_chests, by `chest_id`).
##
## Drop scenes/world/loot_chest.tscn into a level, give it a unique Chest Id and list
## the item ids inside ("id" or "id:count").

@export var chest_id := "chest"
@export var title := "Chest"
@export var items: Array[String] = []
@export var gold := 0
@export_multiline var greeting := "A sturdy chest."
@export var build_model := true:
	set(value):
		build_model = value
		if is_inside_tree():
			_build()

const TALK_RANGE := 2.4

## Opened chests when there's no saved character (testing with F6).
static var _opened_unsaved := {}

var _prompt: Label3D
var _model: Node3D
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
	_prompt.position = Vector3.UP * 1.2
	_prompt.visible = false
	add_child(_prompt)


func _build() -> void:
	if _model and is_instance_valid(_model):
		_model.queue_free()
		_model = null
	for c in get_children():
		if c is CollisionShape3D and c.name == "ChestShape":
			c.queue_free()
	if not build_model:
		return
	_model = Node3D.new()
	_model.name = "Chest"
	add_child(_model)  # not owned: never saved into the scene
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.3, 0.16)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.75, 0.62, 0.3)
	metal.metallic = 0.8
	metal.roughness = 0.35
	var parts := [
		[Vector3(1.0, 0.5, 0.6), Vector3(0, 0.25, 0), wood],
		[Vector3(1.02, 0.18, 0.62), Vector3(0, 0.59, 0), wood],
		[Vector3(1.04, 0.06, 0.64), Vector3(0, 0.5, 0), metal],
		[Vector3(0.12, 0.14, 0.04), Vector3(0, 0.46, 0.31), metal],
	]
	for part: Array in parts:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		mi.mesh = box
		mi.position = part[1]
		mi.material_override = part[2]
		_model.add_child(mi)
	var shape := CollisionShape3D.new()
	shape.name = "ChestShape"
	var b := BoxShape3D.new()
	b.size = Vector3(1.0, 0.7, 0.6)
	shape.shape = b
	shape.position = Vector3(0, 0.35, 0)
	add_child(shape)


func is_opened() -> bool:
	if GameSession.active():
		return chest_id in GameSession.data.get("opened_chests", [])
	return _opened_unsaved.has(chest_id)


func can_talk() -> bool:
	return not Engine.is_editor_hint() and not DialogueBox.is_open and Time.get_ticks_msec() - DialogueBox.closed_at > 300


func talk(player: Node3D) -> void:
	if is_opened():
		DialogueBox.open(self, title, "", ["It's empty now."], Callable())
		return
	var inventory := player.get_node_or_null("Inventory") as Inventory
	if inventory == null:
		return
	var names: Array[String] = []
	for entry in items:
		var parts := entry.split(":")
		var id := parts[0].strip_edges()
		var count := int(parts[1]) if parts.size() > 1 else 1
		var left := inventory.add_item(id, count)
		if left < count:
			names.append(String(Database.item(id).get("name", id)) + ((" x%d" % (count - left)) if count - left > 1 else ""))
		if left > 0:
			FloatingText.spawn(player, "Backpack full", Color(1, 0.7, 0.6), 0.8)
	if gold > 0:
		inventory.add_gold(gold)
		names.append("%d gold" % gold)
	if GameSession.active():
		var opened: Array = GameSession.data.get("opened_chests", [])
		opened.append(chest_id)
		GameSession.data["opened_chests"] = opened
		GameSession.save_game()
	else:
		_opened_unsaved[chest_id] = true
	Combat.play_sound(self, load("res://assets/audio/weapons/swap_sword.ogg"), -6.0)
	DialogueBox.open(self, title, "", [greeting, "You take: %s." % ", ".join(names) if not names.is_empty() else "There's nothing you can carry."], Callable())


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
		var key := GameSettings.interact_label()
		_prompt.text = "%s  %s" % [key, "Open" if not is_opened() else title]
