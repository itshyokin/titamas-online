extends Node
## Autoload "GameSession": the character being played and its save file.
##
## Saves live in user://saves/<name>_<time>.json, one file per character:
##   {version, name, pronouns, class, look (see data/appearance.json "default"), level,
##    inventory {bag, equipped, gold, quick}, scene, position [x,y,z], play_time,
##    created, saved}
## The title screen makes or loads one, then start_game() opens its level with the
## player where they left off. While playing it saves on changes to the backpack,
## every minute, from Settings → Save game, and when the window is closed.
## Running a level straight from the editor (F6) has no character: nothing is saved.

signal saved

const SAVE_DIR := "user://saves"
const VERSION := 1
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const START_SCENE := "res://scenes/levels/overworld_test.tscn"
const AUTOSAVE_SECONDS := 60.0

## The current character's save data ({} when none, e.g. on the title screen).
var data := {}
## Its file.
var path := ""

var _since_save := 0.0
var _play_started := 0


func active() -> bool:
	return not data.is_empty()


## Every saved character, most recently played first. Each has its "path" added.
func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.get_extension() != "json":
			continue
		var p := SAVE_DIR.path_join(file)
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary and d.has("name"):
			d["path"] = p
			out.append(d)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("saved", 0)) > float(b.get("saved", 0)))
	return out


func new_character(char_name: String, pronouns: String, look: Dictionary, class_id: String) -> void:
	var now := Time.get_unix_time_from_system()
	data = {
		"version": VERSION, "name": char_name, "pronouns": pronouns, "class": class_id,
		"look": look.duplicate(), "level": 1, "inventory": {}, "scene": START_SCENE,
		"position": null, "play_time": 0.0, "created": now, "saved": now,
	}
	var slug := char_name.to_lower().replace(" ", "_").validate_filename()
	path = SAVE_DIR.path_join("%s_%d.json" % [slug, int(now)])
	_write()


func load_save(save_path: String) -> bool:
	var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not d is Dictionary or not d.has("name"):
		return false
	d.erase("path")
	data = d
	path = save_path
	return true


func delete_save(save_path: String) -> void:
	if save_path.begins_with(SAVE_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## Opens the character's level (the start scene for a new one) with the player placed
## where they were.
func start_game() -> void:
	var scene_path := String(data.get("scene", START_SCENE))
	if not ResourceLoader.exists(scene_path):
		scene_path = START_SCENE
	var level := (load(scene_path) as PackedScene).instantiate()
	var pos = data.get("position")
	var player := level.get_node_or_null("Player") as Node3D
	# Placed before the level enters the tree, so the terrain loads around this spot.
	if player and pos is Array and pos.size() == 3:
		player.position = Vector3(pos[0], pos[1], pos[2])
	_since_save = 0.0
	_play_started = Time.get_ticks_msec()
	_switch_to(level)


## Saves, forgets the character and goes back to the title screen.
func quit_to_title() -> void:
	save_game()
	data = {}
	path = ""
	GameSettings.menu_open = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


## Writes the save, taking the player's position, backpack and level from the game.
func save_game() -> void:
	if not active():
		return
	var inv := get_tree().get_first_node_in_group("player_inventory")
	if inv:
		data["inventory"] = inv.call("to_dict")
		var player := inv.get_parent() as Node3D
		if player and player.is_inside_tree():
			var p := player.global_position
			data["position"] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
			var scene := get_tree().current_scene
			if scene and not scene.scene_file_path.is_empty():
				data["scene"] = scene.scene_file_path
		var stats := player.get_node_or_null("Stats") if player else null
		if stats:
			data["level"] = int(stats.get("level"))
	if _play_started > 0:
		var now := Time.get_ticks_msec()
		data["play_time"] = float(data.get("play_time", 0.0)) + (now - _play_started) / 1000.0
		_play_started = now
	_since_save = 0.0
	_write()
	saved.emit()


func _write() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	data["saved"] = Time.get_unix_time_from_system()
	# Write to a temporary file first, so a crash mid-save can't ruin the old one.
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("GameSession: couldn't write %s" % tmp)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))


func _process(delta: float) -> void:
	if not active() or _play_started == 0:
		return
	_since_save += delta
	if _since_save >= AUTOSAVE_SECONDS:
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func _switch_to(level: Node) -> void:
	var tree := get_tree()
	var old := tree.current_scene
	if old:
		old.queue_free()
		await tree.process_frame
	tree.root.add_child(level)
	tree.current_scene = level


## "1 h 05 m" style play time.
static func format_time(seconds: float) -> String:
	var m := int(seconds / 60.0)
	return "%d h %02d m" % [m / 60, m % 60] if m >= 60 else "%d m" % m
