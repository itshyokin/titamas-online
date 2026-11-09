@tool
class_name MapEvent
extends Area3D
## An event placed in a level (like Saturn's / RPG Maker's map events): a box you size in
## the editor, linked to an entry in data/events.json (Database → Events) by `event_id`.
##
## The entry has pages. The active page is the last one whose conditions all hold
## (switches, self switches A–D, variables, items, gold, level, class); it decides what
## shows here (nothing, a built-in model, a prop, a scene or an NPC), whether it blocks
## the way, and when its commands run:
##   action  walk up and press Jump / talk (Space, A)
##   touch   step into the box          leave  step out of it
##   auto    as soon as the page becomes active (use a self switch to run it once)
##   none    never by itself (other events can "call" it)
## Self switches are this event's own (by event id, or `self_key` when one event is
## placed more than once and each should remember for itself).
##
## Scenes: scenes/world/map_event.tscn (or add a node with this script).

const TALK_RANGE := 2.4
const TRIGGER_COLORS := {
	"action": Color(0.3, 0.7, 1.0), "touch": Color(1.0, 0.75, 0.25), "leave": Color(1.0, 0.5, 0.2),
	"auto": Color(0.7, 0.4, 1.0), "none": Color(0.6, 0.6, 0.6),
}

## The event's id in data/events.json.
@export var event_id := "":
	set(value):
		event_id = value
		_update_editor_box()
## The box (metres): touch/leave area, what blocks when the page is solid, and where you
## can examine it from. The node sits at the bottom middle.
@export var size := Vector3(1.5, 2.0, 1.5):
	set(value):
		size = value.max(Vector3(0.1, 0.1, 0.1))
		_update_shape()
		_update_editor_box()
## Whose self switches (A–D). Empty = the event id.
@export var self_key := ""
## Sits on the ground once the terrain under it has loaded (off: stays where placed).
@export var snap_to_ground := true

var page: Dictionary = {}
var page_index := -2

var _shape: CollisionShape3D
var _editor_box: MeshInstance3D
var _editor_label: Label3D
var _visual: Node3D
var _visual_key := "~"
var _blocker: StaticBody3D
var _prompt: Label3D
var _sparkle: Node3D
var _runner: EventRunner
var _auto_done := false
var _erased := false
var _player_inside := false
var _settled := false


## The page of `ev` that's active now ({} if none).
static func active_page(ev: Dictionary, key: String, player: Node) -> Dictionary:
	var pages: Array = ev.get("pages", [])
	for i in range(pages.size() - 1, -1, -1):
		var p = pages[i]
		if p is Dictionary and EventState.test_all(p.get("conditions", []), key, player):
			return p
	return {}


## Runs event `id`'s active page from somewhere that isn't a placed MapEvent (an NPC
## whose data names an event). Returns the runner, or null if no page is active.
static func run_event(id: String, from: Node, player: Node3D, default_speaker := "") -> EventRunner:
	var ev := Database.event(id)
	var p := active_page(ev, id, player)
	if p.is_empty():
		return null
	var who := String(p.get("speaker", ""))
	return EventRunner.run(p.get("commands", []), from, id, player, who if who != "" else default_speaker, bool(p.get("freeze", true)))


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # players
	monitorable = false
	_update_shape()
	if Engine.is_editor_hint():
		_update_editor_box()
		return
	add_to_group("map_events")
	add_to_group("talkable")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.pixel_size = 0.003
	_prompt.font_size = 36
	_prompt.outline_size = 10
	_prompt.no_depth_test = true
	_prompt.visible = false
	add_child(_prompt)
	refresh.call_deferred()


func key() -> String:
	return self_key if self_key != "" else event_id


func _data() -> Dictionary:
	if Engine.is_editor_hint():
		for e in _editor_events():
			if String(e.get("id", "")) == event_id:
				return e
		return {}
	return Database.event(event_id)


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null


## Picks the active page again (switches changed); rebuilds what shows if it changed.
func refresh() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	var ev := _data()
	var pages: Array = ev.get("pages", [])
	var p := active_page(ev, key(), _player())
	var index := pages.find(p) if not p.is_empty() else -1
	if index == page_index:
		return
	page_index = index
	page = p
	_auto_done = false
	_build_look()
	if trigger() == "auto":
		_run_auto.call_deferred()


## The data file changed (editing in the Database while the game runs).
func reload() -> void:
	page_index = -2
	_visual_key = "~"
	refresh()


func trigger() -> String:
	if page.is_empty() or _erased:
		return ""
	return String(page.get("trigger", "action"))


func is_running() -> bool:
	return _runner != null and is_instance_valid(_runner)


## Runs the active page's commands (`npc`: the NPC showing this page, if any).
func start(player: Node3D, npc: Node = null) -> EventRunner:
	if is_running() or page.is_empty() or _erased:
		return null
	var who := String(page.get("speaker", ""))
	if who.is_empty():
		who = String(npc.get("data").get("name", "")) if npc else String(_data().get("name", ""))
	_runner = EventRunner.run(page.get("commands", []), self, key(), player, who, bool(page.get("freeze", true)))
	return _runner


## Hidden and inactive until the level is loaded again (the "erase" command).
func erase() -> void:
	_erased = true
	if _visual:
		_visual.queue_free()
		_visual = null
	_visual_key = "~"
	if _blocker:
		_blocker.queue_free()
		_blocker = null
	if _sparkle:
		_sparkle.visible = false


func _run_auto() -> void:
	if trigger() == "auto" and not _auto_done and not is_running():
		var player := _player()
		if player:
			_auto_done = true
			start(player)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		if trigger() == "touch":
			start(body as Node3D)


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		if trigger() == "leave":
			start(body as Node3D)


func _physics_process(_delta: float) -> void:
	if _settled or Engine.is_editor_hint():
		return
	if not snap_to_ground:
		_settled = true
		return
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 30.0, global_position + Vector3.DOWN * 60.0, 1)
	var skip: Array[RID] = []
	for c in find_children("*", "CollisionObject3D", true, false):
		skip.append((c as CollisionObject3D).get_rid())
	q.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_settled = true
		global_position = hit.position


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var player := _player()
	var show := player != null and can_talk() and talk_distance(player.global_position) <= TALK_RANGE
	_prompt.visible = show
	if show:
		var keys := GameSettings.events_for("jump", GameSettings.gamepad)
		var k := GameSettings.event_name(keys[0]) if not keys.is_empty() else "Jump"
		_prompt.text = "%s  %s" % [k, String(page.get("prompt", "Examine"))]
		_prompt.position = Vector3.UP * (size.y + 0.3) if _visual == null or not String(page.get("model", "")).begins_with("npc:") else Vector3.UP * 2.3


# --- Talkable --------------------------------------------------------------------

func can_talk() -> bool:
	if trigger() != "action" or is_running() or String(page.get("model", "")).begins_with("npc:"):
		return false
	return not DialogueBox.is_open and Time.get_ticks_msec() - DialogueBox.closed_at > 300 and not GameSettings.menu_open


func talk(player: Node3D) -> void:
	if can_talk():
		if player.has_method("face_toward"):
			player.call("face_toward", global_position)
		start(player)


## How far `from` is from the box (sideways; 0 inside it).
func talk_distance(from: Vector3) -> float:
	var local := to_local(from)
	return Vector2(maxf(absf(local.x) - size.x * 0.5, 0.0), maxf(absf(local.z) - size.z * 0.5, 0.0)).length()


# --- Looks -----------------------------------------------------------------------

func _build_look() -> void:
	var model := String(page.get("model", "")) if not _erased else ""
	if model != _visual_key:
		_visual_key = model
		if _visual:
			_visual.queue_free()
			_visual = null
		_visual = _make_model(model)
		if _visual:
			add_child(_visual)
	var solid := bool(page.get("solid", false)) and not _erased and not model.begins_with("npc:") and not model.begins_with("prop:")
	if solid and _blocker == null:
		_blocker = StaticBody3D.new()
		_blocker.collision_layer = 1
		_blocker.collision_mask = 0
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		col.shape = box
		col.position.y = size.y * 0.5
		_blocker.add_child(col)
		add_child(_blocker)
	elif not solid and _blocker:
		_blocker.queue_free()
		_blocker = null
	var marker := bool(page.get("marker", false)) and not _erased
	if marker and _sparkle == null:
		_sparkle = _make_sparkle()
		add_child(_sparkle)
	if _sparkle:
		_sparkle.visible = marker


func _make_model(model: String) -> Node3D:
	if model.is_empty():
		return null
	if model.begins_with("builtin:"):
		return EventModels.make(model.trim_prefix("builtin:"))
	if model.begins_with("prop:"):
		return PropLibrary.new().instantiate(model.trim_prefix("prop:"))
	if model.begins_with("npc:"):
		var npc := (load("res://scenes/npcs/npc.tscn") as PackedScene).instantiate()
		npc.set("npc_id", model.trim_prefix("npc:"))
		npc.set("event_owner", self)
		return npc as Node3D
	if ResourceLoader.exists(model):
		var res := load(model)
		if res is PackedScene:
			return (res as PackedScene).instantiate() as Node3D
	push_warning("MapEvent %s: can't show '%s'" % [event_id, model])
	return null


func _make_sparkle() -> Node3D:
	var root := Node3D.new()
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(size.x * 0.4, 0.1, size.z * 0.4)
	p.direction = Vector3.UP
	p.spread = 15.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.3
	var mote := SphereMesh.new()
	mote.radius = 0.025
	mote.height = 0.05
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.85, 0.4)
	mote.material = glow
	p.mesh = mote
	p.position.y = 0.3
	root.add_child(p)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.4)
	light.light_energy = 0.5
	light.omni_range = 2.0
	light.position.y = 0.5
	root.add_child(light)
	return root


# --- Editor --------------------------------------------------------------------

func _update_shape() -> void:
	if not is_inside_tree() and _shape == null:
		return
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.shape = BoxShape3D.new()
		add_child(_shape)  # not owned: never saved into the scene
	(_shape.shape as BoxShape3D).size = size
	_shape.position.y = size.y * 0.5


## A see-through box with the event's name, only in the editor.
func _update_editor_box() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _editor_box == null:
		_editor_box = MeshInstance3D.new()
		_editor_box.mesh = BoxMesh.new()
		add_child(_editor_box)
		_editor_label = Label3D.new()
		_editor_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_editor_label.pixel_size = 0.004
		_editor_label.font_size = 40
		_editor_label.outline_size = 12
		_editor_label.no_depth_test = true
		add_child(_editor_label)
	var ev := _data()
	var pages: Array = ev.get("pages", [])
	var first: Dictionary = pages[0] if not pages.is_empty() and pages[0] is Dictionary else {}
	var color: Color = TRIGGER_COLORS.get(String(first.get("trigger", "action")), Color.GRAY)
	if ev.is_empty():
		color = Color(1, 0.2, 0.2)
	(_editor_box.mesh as BoxMesh).size = size
	_editor_box.position.y = size.y * 0.5
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color, 0.25)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_editor_box.material_override = mat
	_editor_label.position.y = size.y + 0.3
	_editor_label.modulate = color.lightened(0.4)
	if ev.is_empty():
		_editor_label.text = "Event: (set Event Id)" if event_id.is_empty() else "Event: %s (not in events.json)" % event_id
	else:
		_editor_label.text = "%s\n%d page%s" % [ev.get("name", event_id), pages.size(), "" if pages.size() == 1 else "s"]


static func _editor_events() -> Array:
	var d = DataFiles.read(DataFiles.EVENTS)
	return d.get("events", []) if d is Dictionary else []


## The inspector offers the ids in events.json for Event Id.
func _validate_property(property: Dictionary) -> void:
	if property.name == "event_id" and Engine.is_editor_hint():
		var ids := PackedStringArray()
		for e in _editor_events():
			ids.append(String(e.get("id", "")))
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ",".join(ids)
