@tool
class_name SafeArea
extends Node3D
## A box you size in the editor (like MapEvent) that makes the space inside it safe,
## indoors, or both. The node sits at the bottom middle of the box.
##
## Safe: enemies don't notice anyone on the players' side in here, give up the chase
## when their target steps in, and neither side can hurt the other across the edge
## (so nobody can fight from safety either). Practice targets can still be hit.
## `off_switch`: while that switch is on (Database → Switches; events turn it on with
## the Switch command) the area is not safe: a town under attack.
##
## Indoors: rain and snow stop while the camera is in here, the puddle splashes stop
## while the player is, and the weather's sound is muffled (Database → Weather Settings
## → Indoors). Weather also checks for a roof over the camera by itself, so a box is only
## needed where there is no roof to find (a cave mouth, a tent, an open porch).
##
## Scene: scenes/world/safe_area.tscn (or add a Node3D with this script).

const COLOR_SAFE := Color(0.3, 0.9, 0.45)
const COLOR_INDOORS := Color(0.45, 0.65, 1.0)
const COLOR_BOTH := Color(0.3, 0.9, 0.85)
const COLOR_NOTHING := Color(0.6, 0.6, 0.6)

## The box (metres). The node is at its bottom middle.
@export var size := Vector3(20.0, 8.0, 20.0):
	set(value):
		size = value.max(Vector3(0.1, 0.1, 0.1))
		_update_editor_box()
## No enemy aggro and no damage between the two sides in here.
@export var safe := true:
	set(value):
		safe = value
		_update_editor_box()
## While this switch is on, the area is not safe (leave empty for always safe).
@export var off_switch := "":
	set(value):
		off_switch = value
		_update_editor_box()
## Under cover: no rain or snow in here and the weather sounds muffled.
@export var indoors := false:
	set(value):
		indoors = value
		_update_editor_box()

## Every area in the running level.
static var _areas: Array[SafeArea] = []
static var _watched_frame := -1
static var _watch_left := 0.0
## 1 = the player was in a safe area at the last look, 0 = wasn't, -1 = not looked yet.
static var _player_safe := -1

var _editor_box: MeshInstance3D
var _editor_label: Label3D


func _enter_tree() -> void:
	if not Engine.is_editor_hint() and not _areas.has(self):
		_areas.append(self)


func _exit_tree() -> void:
	_areas.erase(self)
	if _areas.is_empty():
		_player_safe = -1


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_editor_box()
		set_process(false)


## Safe right now (the off switch isn't on).
func is_active() -> bool:
	return safe and (off_switch.is_empty() or not EventState.get_switch(off_switch))


func contains(point: Vector3) -> bool:
	var p := to_local(point)
	return absf(p.x) <= size.x * 0.5 and absf(p.z) <= size.z * 0.5 and p.y >= 0.0 and p.y <= size.y


## `point` is inside an area that is safe right now.
static func safe_at(point: Vector3) -> bool:
	for a in _areas:
		if is_instance_valid(a) and a.is_inside_tree() and a.is_active() and a.contains(point):
			return true
	return false


## `point` is inside an indoors area.
static func indoors_at(point: Vector3) -> bool:
	for a in _areas:
		if is_instance_valid(a) and a.is_inside_tree() and a.indoors and a.contains(point):
			return true
	return false


## `node` is on the players' side (the player, companions, townsfolk, other players) and
## standing in an area that is safe right now: enemies leave it alone, and it can't
## hurt them from in there.
static func protects(node: Node) -> bool:
	if _areas.is_empty() or node == null or not is_instance_valid(node) or not node is Node3D or not node.is_inside_tree():
		return false
	var stats := node.get_node_or_null("Stats")
	if stats == null or int(stats.get("team")) != 0:  # Stats.Team.PLAYERS
		return false
	return safe_at((node as Node3D).global_position + Vector3.UP * 0.9)


# --- The player walking in and out ------------------------------------------------

func _process(delta: float) -> void:
	# One look per frame however many areas there are, a few times a second.
	var frame := Engine.get_process_frames()
	if frame == _watched_frame:
		return
	_watched_frame = frame
	_watch_left -= delta
	if _watch_left > 0.0:
		return
	_watch_left = 0.2
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var now := 1 if protects(player) else 0
	if now == _player_safe:
		return
	var first := _player_safe == -1
	_player_safe = now
	if first and now == 0:
		return  # starting outside: nothing to say
	var cfg := _settings()
	if not bool(cfg.get("notices", true)):
		return
	var text := String(cfg.get("enter_text", "You are safe here.")) if now == 1 else String(cfg.get("leave_text", "You are no longer safe."))
	var color := Color.from_string(String(cfg.get("enter_color", "#9be8a8")) if now == 1 else String(cfg.get("leave_color", "#f0c27a")), Color.WHITE)
	if not text.is_empty():
		get_tree().call_group("hud", "show_message", text, float(cfg.get("notice_seconds", 2.5)), color)


## player.json "safe_areas" (Database → Player → Safe areas).
static func _settings() -> Dictionary:
	var loop := Engine.get_main_loop() as SceneTree
	var db := loop.root.get_node_or_null("Database") if loop else null
	var player = db.get("player") if db else null
	var cfg = (player as Dictionary).get("safe_areas", {}) if player is Dictionary else {}
	return cfg if cfg is Dictionary else {}


# --- Editor ------------------------------------------------------------------------

## A see-through box with what the area does, only in the editor.
func _update_editor_box() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _editor_box == null:
		_editor_box = MeshInstance3D.new()
		_editor_box.mesh = BoxMesh.new()
		add_child(_editor_box)  # not owned: never saved into the scene
		_editor_label = Label3D.new()
		_editor_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_editor_label.pixel_size = 0.006
		_editor_label.font_size = 40
		_editor_label.outline_size = 12
		_editor_label.no_depth_test = true
		add_child(_editor_label)
	var color := COLOR_NOTHING
	var words := PackedStringArray()
	if safe and indoors:
		color = COLOR_BOTH
	elif safe:
		color = COLOR_SAFE
	elif indoors:
		color = COLOR_INDOORS
	if safe:
		words.append("Safe area" if off_switch.is_empty() else "Safe area (unless %s)" % off_switch)
	if indoors:
		words.append("Indoors")
	if words.is_empty():
		words.append("Area: tick Safe or Indoors")
	(_editor_box.mesh as BoxMesh).size = size
	_editor_box.position.y = size.y * 0.5
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color, 0.14)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_editor_box.material_override = mat
	_editor_label.position.y = size.y + 0.4
	_editor_label.modulate = color.lightened(0.4)
	_editor_label.text = "\n".join(words)


## The inspector offers the switch names in events.json for Off Switch.
func _validate_property(property: Dictionary) -> void:
	if property.name == "off_switch" and Engine.is_editor_hint():
		var ids := PackedStringArray()
		var d = DataFiles.read(DataFiles.EVENTS)
		if d is Dictionary:
			for s in d.get("switches", []):
				if s is Dictionary:
					ids.append(String(s.get("id", "")))
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ",".join(ids)
