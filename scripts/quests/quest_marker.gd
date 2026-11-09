class_name QuestMarker
extends Label3D
## The "!" (quest to take) or "?" (ready to hand in) over a quest giver's head (an NPC or
## a MapEvent named as giver_npc / giver_event in data/quests.json). Added by Npc and
## MapEvent; checks twice a second. Over a MapEvent whose page shows a model (an NPC that
## walks around), it follows that model.

var event_id := ""
var npc_id := ""
var _check := 0.0
var _seen := -1


func _init(for_event := "", for_npc := "") -> void:
	event_id = for_event
	npc_id = for_npc
	name = "QuestMarker"
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = false
	fixed_size = false
	pixel_size = 0.012
	font_size = 72
	outline_size = 18
	outline_modulate = Color(0.15, 0.08, 0.0)
	modulate = Color(1.0, 0.84, 0.25)
	visible = false
	top_level = true
	add_to_group("quest_markers")  # (the compass shows them)


func _process(delta: float) -> void:
	var anchor := get_parent() as Node3D
	var shown = anchor.get("_visual") if anchor else null
	if shown is Node3D and is_instance_valid(shown) and (shown as Node3D).is_inside_tree():
		anchor = shown
	if anchor:
		global_position = anchor.global_position + Vector3.UP * (2.45 + sin(Time.get_ticks_msec() / 300.0) * 0.06)
	_check -= delta
	if _check > 0.0 and _seen == Quests.revision:
		return
	_check = 0.5
	_seen = Quests.revision
	var mark := Quests.marker_for(event_id, npc_id)
	visible = mark != ""
	text = mark
	modulate = Color(1.0, 0.84, 0.25) if mark == "!" else Color(0.55, 0.85, 1.0)
