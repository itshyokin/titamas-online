@tool
class_name ClimbLock
extends Node3D
## A box (sized like SafeArea) where nothing can be climbed until a switch is on: vines,
## ledges and ladders inside it can't be grabbed (a way out that opens once the boss is
## beaten). Leave Unlock Switch empty for "never climbable".
## Scene: scenes/world/climb_lock.tscn (or add a Node3D with this script).

const COLOR := Color(0.95, 0.45, 0.25)

## The box (metres). The node is at its bottom middle.
@export var size := Vector3(8.0, 12.0, 4.0):
	set(value):
		size = value.max(Vector3(0.1, 0.1, 0.1))
		_update_editor_box()
## Climbable once this switch is on.
@export var unlock_switch := "":
	set(value):
		unlock_switch = value
		_update_editor_box()
## Shown when trying to climb while it's locked (empty = say nothing).
@export var message := "It won't hold your weight... not while that thing is still about."

static var _locks: Array[ClimbLock] = []
static var _told_at := -100000

var _editor_box: MeshInstance3D
var _editor_label: Label3D


func _enter_tree() -> void:
	if not Engine.is_editor_hint() and not _locks.has(self):
		_locks.append(self)


func _exit_tree() -> void:
	_locks.erase(self)


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_editor_box()


func is_locked() -> bool:
	return unlock_switch.is_empty() or not EventState.get_switch(unlock_switch)


func contains(point: Vector3) -> bool:
	var p := to_local(point)
	return absf(p.x) <= size.x * 0.5 and absf(p.z) <= size.z * 0.5 and p.y >= 0.0 and p.y <= size.y


## Climbing at `point` isn't allowed right now. `tell`: say why (at most every few seconds).
static func blocked_at(point: Vector3, tell := false) -> bool:
	for l in _locks:
		if is_instance_valid(l) and l.is_inside_tree() and l.contains(point) and l.is_locked():
			if tell and not l.message.is_empty() and Time.get_ticks_msec() - _told_at > 4000:
				_told_at = Time.get_ticks_msec()
				l.get_tree().call_group("hud", "show_message", l.message, 2.5, Color(0.95, 0.85, 0.7))
			return true
	return false


func _update_editor_box() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _editor_box == null:
		_editor_box = MeshInstance3D.new()
		_editor_box.mesh = BoxMesh.new()
		add_child(_editor_box)
		_editor_label = Label3D.new()
		_editor_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_editor_label.pixel_size = 0.006
		_editor_label.font_size = 40
		_editor_label.outline_size = 12
		_editor_label.no_depth_test = true
		add_child(_editor_label)
	(_editor_box.mesh as BoxMesh).size = size
	_editor_box.position.y = size.y * 0.5
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(COLOR, 0.14)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_editor_box.material_override = mat
	_editor_label.position.y = size.y + 0.4
	_editor_label.modulate = COLOR.lightened(0.4)
	_editor_label.text = "No climbing" + (" until %s" % unlock_switch if not unlock_switch.is_empty() else "")


func _validate_property(property: Dictionary) -> void:
	if property.name == "unlock_switch" and Engine.is_editor_hint():
		var ids := PackedStringArray()
		var d = DataFiles.read(DataFiles.EVENTS)
		if d is Dictionary:
			for s in d.get("switches", []):
				if s is Dictionary:
					ids.append(String(s.get("id", "")))
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ",".join(ids)
