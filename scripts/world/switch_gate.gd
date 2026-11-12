class_name SwitchGate
extends Node
## Put under anything (a prop, a level object) to make it appear or vanish with an event
## switch: `show_switch` = there only once that switch is on (the quarry ladder after the
## troll is beaten), `hide_switch` = gone once that switch is on. While it's away its parent
## is hidden and every collision shape under it is off, so it can't be climbed or bumped.
##
## Props get one from their Blender custom properties (show_switch / hide_switch, written
## to chunk_I_J.props.json by the exporter). For an object in a level scene, add a Node
## with this script and set the switch names in the Inspector.
## Watches switches through EventState.changed() (group "event_watchers").

@export var show_switch := ""
@export var hide_switch := ""

var _shown := true


func _init(show_on := "", hide_on := "") -> void:
	show_switch = show_on
	hide_switch = hide_on


func _ready() -> void:
	add_to_group("event_watchers")
	refresh()


## Should the parent be there now?
func wanted() -> bool:
	var es := load("res://scripts/events/event_state.gd")
	if show_switch != "" and not es.get_switch(show_switch):
		return false
	if hide_switch != "" and es.get_switch(hide_switch):
		return false
	return true


func refresh() -> void:
	var p := get_parent()
	if p == null:
		return
	var want := wanted()
	if want == _shown and is_inside_tree() and _initialized:
		return
	_initialized = true
	_shown = want
	if p is Node3D:
		(p as Node3D).visible = want
	for shape in p.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).set_deferred("disabled", not want)
	for shape in p.find_children("*", "CollisionPolygon3D", true, false):
		(shape as CollisionPolygon3D).set_deferred("disabled", not want)
	if p is CollisionObject3D and not want:
		pass  # its shapes are off above


var _initialized := false
