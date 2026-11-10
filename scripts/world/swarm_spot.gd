@tool
class_name SwarmSpot
extends Node3D
## A cloud of insects at a spot you choose: flies over a body left lying for the story,
## over a rubbish heap or a carcass, midges over a stagnant pool. Place the node where
## the cloud's middle should be (a little above the ground).
##
## `swarm` is a Wildlife type of kind "swarm" (Database → Wildlife: its picture, colour,
## how many, cloud size, and when it shows: any time, day, dusk or night). The cloud is
## only there while the player is within `show_within` metres.
##
## Scene: scenes/world/swarm_spot.tscn (or add a Node3D with this script).

const FILE := "res://data/wildlife.json"

## Which swarm (a Wildlife type id).
@export var swarm := "flies":
	set(value):
		swarm = value
		_update_editor()
## Cloud size compared with the type's own (1 = as set in the Database).
@export var size_scale := 1.0
## The cloud appears when the player comes this close (m).
@export var show_within := 45.0

var _cloud: Node3D
var _check := 0.0
var _editor_label: Label3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_editor()
		set_process(false)


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	var wildlife := get_tree().get_first_node_in_group("wildlife")
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var cfg: Dictionary = wildlife.call("type_data", swarm) if wildlife else {}
	var want: bool = player != null and not cfg.is_empty() and String(cfg.get("kind", "")) == "swarm" \
		and bool(wildlife.call("time_ok", String(cfg.get("when", "any")))) \
		and player.global_position.distance_to(global_position) < show_within
	if want and _cloud == null:
		var scaled := cfg.duplicate()
		scaled["spread"] = float(cfg.get("spread", 1.0)) * size_scale
		_cloud = Wildlife.Swarm.new(scaled)
		add_child(_cloud)
	elif not want and _cloud != null:
		_cloud.queue_free()
		_cloud = null


# --- Editor -------------------------------------------------------------------------

func _update_editor() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _editor_label == null:
		_editor_label = Label3D.new()
		_editor_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_editor_label.pixel_size = 0.004
		_editor_label.font_size = 36
		_editor_label.outline_size = 10
		_editor_label.no_depth_test = true
		_editor_label.modulate = Color(0.85, 0.9, 0.6)
		add_child(_editor_label)  # not owned: never saved into the scene
	_editor_label.text = "Swarm: %s" % swarm


## The inspector offers the swarm types in wildlife.json.
func _validate_property(property: Dictionary) -> void:
	if property.name == "swarm" and Engine.is_editor_hint():
		var ids := PackedStringArray()
		var d = DataFiles.read(FILE)
		if d is Dictionary:
			for t in d.get("types", []):
				if t is Dictionary and String(t.get("kind", "")) == "swarm":
					ids.append(String(t.get("id", "")))
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ",".join(ids)
