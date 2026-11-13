extends Node
## Autoload "GameSession": the character being played and its save file.
##
## Saves live in user://saves/<name>_<time>.json, one file per character:
##   {version, name, pronouns, class, look (see data/appearance.json "default"), level,
##    inventory {bag, equipped, gold, hotbar, active_weapon}, opened_chests, home, scene, position [x,y,z], play_time,
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
## Shown on the title screen after coming back to it (e.g. "The host left the game.").
var last_message := ""

var _since_save := 0.0
var _play_started := 0


func _ready() -> void:
	(func() -> void:
		Net.host_left.connect(func() -> void:
			if active():
				last_message = "The host left the game."
				quit_to_title())).call_deferred()


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
## `fade_in` > 0: the screen is black (the title faded out) and fades in once the
## level has had a moment to stream in around the player.
func start_game(fade_in := 0.0) -> void:
	var scene_path := String(data.get("scene", START_SCENE))
	if not ResourceLoader.exists(scene_path):
		scene_path = START_SCENE
	var level := (load(scene_path) as PackedScene).instantiate()
	var pos = data.get("position")
	var player := level.get_node_or_null("Player") as Node3D
	# A new character's home is where the level starts them (until they rest somewhere).
	if player and not data.has("home"):
		var p := player.position
		data["home"] = {"scene": scene_path, "position": [p.x, p.y, p.z], "name": "the starting point"}
	# Placed before the level enters the tree, so the terrain loads around this spot.
	if player and pos is Array and pos.size() == 3:
		player.position = Vector3(pos[0], pos[1], pos[2])
	_since_save = 0.0
	_play_started = Time.get_ticks_msec()
	if fade_in > 0.0:
		ScreenFade.cover(self)
	await _switch_to(level)
	if fade_in > 0.0:
		for i in 4:
			await get_tree().process_frame
		await get_tree().create_timer(0.35).timeout
		ScreenFade.clear(self, fade_in)


## Makes a spot the character's home (where the hearthstone takes them).
func set_home(scene_path: String, at: Vector3, home_name: String) -> void:
	data["home"] = {"scene": scene_path, "position": [at.x, at.y, at.z], "name": home_name}
	save_game()


func home_name() -> String:
	return String(data.get("home", {}).get("name", "home"))


## Seconds until the hearthstone can be used again.
func hearth_cooldown_left() -> float:
	return maxf(float(data.get("hearth_ready_at", 0.0)) - Time.get_unix_time_from_system(), 0.0)


## Hearthstone / death: reload at home (its level, its spot). With `fade_out` > 0 the
## screen first fades to `color`; the new level fades in from it over `fade_in`.
func travel_home(color := Color.BLACK, fade_out := 0.0, fade_in := 0.0, which := "home") -> void:
	var home: Dictionary = data.get(which, {})
	if home.is_empty():
		return
	var tree := get_tree()
	if fade_out > 0.0:
		ScreenFade.to_black(self, fade_out, color)
		await tree.create_timer(fade_out + 0.05).timeout
	elif fade_in > 0.0:
		ScreenFade.cover(self, color)
	_go_home(home)
	if fade_in > 0.0:
		await tree.process_frame
		await tree.process_frame
		await tree.create_timer(0.25).timeout
		ScreenFade.clear(self, fade_in)


func _go_home(home: Dictionary) -> void:
	save_game()
	data["scene"] = home.get("scene", START_SCENE)
	data["position"] = home.get("position")
	_write()
	start_game()


## Moves the player to another level (or elsewhere in this one when `scene_path` is empty
## or the current level): to the node called `marker` there (a Marker3D, or anything),
## else to `at` ([x, y, z]), else where the level puts them. Events' teleports.
func travel_to(scene_path: String, marker := "", at: Variant = null, fade := true) -> void:
	var tree := get_tree()
	var current := tree.current_scene
	if fade:
		ScreenFade.to_black(self, 0.35)
		await tree.create_timer(0.4).timeout
	if scene_path.is_empty() or (current and current.scene_file_path == scene_path):
		var player := tree.get_first_node_in_group("player") as Node3D
		var spot = _spot_in(current, marker, at)
		if player and spot != null:
			player.global_position = spot
			if player is CharacterBody3D:
				(player as CharacterBody3D).velocity = Vector3.ZERO
	elif ResourceLoader.exists(scene_path):
		save_game()
		var level := (load(scene_path) as PackedScene).instantiate()
		var player := level.get_node_or_null("Player") as Node3D
		var spot = _spot_in(level, marker, at)
		if player and spot != null:
			player.position = spot
		if active():
			data["scene"] = scene_path
			if spot != null:
				data["position"] = [spot.x, spot.y, spot.z]
		_switch_to(level)
		await tree.process_frame
		await tree.process_frame
	else:
		push_warning("GameSession: no level %s" % scene_path)
	if fade:
		await tree.create_timer(0.15).timeout
		ScreenFade.clear(self, 0.5)


## Where `marker` (a node's name) is in `level`, or `at` ([x, y, z]); null for neither.
func _spot_in(level: Node, marker: String, at: Variant) -> Variant:
	if level and not marker.is_empty():
		var n := level.find_child(marker, true, false) as Node3D
		if n:
			if n.is_inside_tree():
				return n.global_position
			var t := Transform3D()
			var p: Node = n
			while p and p != level:
				if p is Node3D:
					t = (p as Node3D).transform * t
				p = p.get_parent()
			return t.origin
		push_warning("GameSession: no '%s' in %s" % [marker, level.scene_file_path])
	if at is Array and at.size() == 3:
		return Vector3(float(at[0]), float(at[1]), float(at[2]))
	return null


## Saves, forgets the character and goes back to the title screen.
func quit_to_title() -> void:
	save_game()
	# Fade to black first; the title screen fades in from it (FrontEnd._ready).
	var fade := float(Database.player.get("menu_fade", {}).get("out", 0.6))
	if fade > 0.0 and is_inside_tree():
		get_tree().paused = false
		ScreenFade.to_black(self, fade)
		await get_tree().create_timer(fade + 0.05, true).timeout
	Net.leave()
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
	remember_clock()
	if _play_started > 0:
		var now := Time.get_ticks_msec()
		data["play_time"] = float(data.get("play_time", 0.0)) + (now - _play_started) / 1000.0
		_play_started = now
	_since_save = 0.0
	_write()
	saved.emit()


## Keeps the world's day and hour in the save, so loading, the hearthstone and travel
## carry on the same time of day (WorldCycle reads it back when a level starts).
func remember_clock() -> void:
	var cycle := get_tree().get_first_node_in_group("world_cycle") if is_inside_tree() else null
	if cycle and not Engine.is_editor_hint():
		data["clock"] = {"day": int(cycle.get("day")), "hour": float(cycle.get("hour"))}


## Seconds this character has been played, counting the time since the last save.
func play_seconds() -> float:
	var t := float(data.get("play_time", 0.0))
	if _play_started > 0:
		t += (Time.get_ticks_msec() - _play_started) / 1000.0
	return t


func _write() -> void:
	if path.is_empty():
		return  # no save file (a test run, or a co-op guest)
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
