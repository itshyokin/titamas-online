@tool
class_name RegionContent
extends Node3D
## Root of a region's sub-scene (scenes/levels/regions/<id>.tscn, made by
## tools/godot/split_regions.gd): the enemies, NPCs, events, areas and campfires placed in
## one region, instanced under the level's "Regions" node. In the game it's only a folder.
##
## Opened on its own in the editor it shows the terrain (an unsaved ChunkStreamer preview),
## a sun and a sky, so things can be placed on the ground. Nothing of that is saved.

## The regions.json id (also kept as meta "region").
@export var region_id := ""

## Level whose ChunkStreamer settings the preview copies (chunk folder, size, materials).
@export_file("*.tscn") var preview_level := "res://scenes/levels/overworld_test.tscn"

var _preview: Array[Node] = []


func _ready() -> void:
	if region_id == "":
		region_id = String(get_meta("region", ""))
	if not Engine.is_editor_hint():
		return
	# Only when this scene itself is open (not while it sits inside the level).
	if get_tree().edited_scene_root != self:
		return
	_build_preview.call_deferred()


func _exit_tree() -> void:
	for n in _preview:
		if is_instance_valid(n):
			n.queue_free()
	_preview.clear()


func _build_preview() -> void:
	var streamer: Node3D = null
	if ResourceLoader.exists(preview_level):
		var level: Node = (load(preview_level) as PackedScene).instantiate()
		var from := level.get_node_or_null("ChunkStreamer")
		if from:
			streamer = from.duplicate() as Node3D
		for n in ["WorldEnvironment", "Sun"]:
			var light := level.get_node_or_null(n)
			if light:
				_add(light.duplicate())
		level.free()
	if streamer == null:
		streamer = load("res://scripts/world/chunk_streamer.gd").new()
	streamer.set("target_path", NodePath())
	_add(streamer)


func _add(n: Node) -> void:
	n.name = "_Preview" + String(n.name)
	add_child(n, false, Node.INTERNAL_MODE_BACK)  # internal + unowned: never saved
	_preview.append(n)
