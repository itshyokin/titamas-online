class_name HerbPatch
extends Node3D
## Makes a herb prop pickable (ChunkStreamer adds one to props whose data/harvest.json kind
## has "pick": red berry and blue leaf bushes, golden flowers, lavender). Interact picks it:
## the items go in the backpack, the "fruit" meshes (berries, flowers, blue leaves, lavender
## spikes) disappear and grow back after the kind's regrow_days game days of play
## (saved per character in GameSession.data "herbs": key -> play second it's ready).
## Names no autoloads (tests can load ChunkStreamer).

const PICK_SOUND := "res://assets/audio/sfx/pick_herb.ogg"

static var _unsaved := {}  # key -> msec ready (no game session)

var kind := ""
var data := {}
var key := ""
var _prompt: Label3D
var _check := 0.0
var _picked := false


static func make(kind_id: String, kind_data: Dictionary) -> HerbPatch:
	var h := HerbPatch.new()
	h.name = "HerbPatch"
	h.kind = kind_id
	h.data = kind_data
	return h


func _ready() -> void:
	add_to_group("talkable")
	var p := get_parent() as Node3D
	var at := p.global_position if p else global_position
	var scene := get_tree().current_scene
	key = "%s:%d,%d,%d" % [scene.scene_file_path.get_file().get_basename() if scene else "", roundi(at.x * 2.0), roundi(at.y * 2.0), roundi(at.z * 2.0)]
	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.pixel_size = 0.003
	_prompt.font_size = 36
	_prompt.outline_size = 10
	_prompt.no_depth_test = true
	_prompt.position = Vector3.UP * 1.1
	_prompt.visible = false
	add_child(_prompt)
	_refresh()


func _session() -> Node:
	var s := get_tree().root.get_node_or_null("GameSession")
	return s if s and bool(s.call("active")) else null


## Seconds until it has grown back (0 = ready to pick).
func regrow_left() -> float:
	var s := _session()
	if s:
		var herbs: Dictionary = s.get("data").get("herbs", {})
		return maxf(float(herbs.get(key, 0.0)) - float(s.call("play_seconds")), 0.0)
	return maxf(float(_unsaved.get(key, 0)) - Time.get_ticks_msec(), 0.0) / 1000.0


func can_talk() -> bool:
	return not _picked and is_visible_in_tree() and not bool(DialogueBox.is_open) and Time.get_ticks_msec() - DialogueBox.closed_at > 300


func talk(player: Node3D) -> void:
	if _picked:
		return
	var inv := player.get_node_or_null("Inventory")
	var db := get_tree().root.get_node_or_null("Database")
	var item := String(data.get("item", ""))
	if inv == null or item == "":
		return
	var count := randi_range(int(data.get("min", 1)), maxi(int(data.get("max", 1)), int(data.get("min", 1))))
	var left: int = inv.call("add_item", item, count)
	var hud := get_tree().get_first_node_in_group("hud")
	var item_name := String((db.call("item", item) as Dictionary).get("name", item)) if db else item
	if left >= count:
		if hud:
			hud.call("notify", self, "Backpack full", Color(1, 0.7, 0.6))
		return
	if hud:
		hud.call("notify", self, "+%d %s" % [count - left, item_name], Color(0.75, 1.0, 0.7))
	var progress := player.get_node_or_null("Progress")
	if progress and int(data.get("xp", 0)) > 0:
		progress.call("add_xp", int(data.xp))
	var path := String(data.get("sound", PICK_SOUND))
	if ResourceLoader.exists(path):
		var snd := AudioStreamPlayer3D.new()
		snd.stream = load(path)
		snd.bus = &"SFX"
		snd.volume_db = -4.0
		snd.pitch_scale = randf_range(0.9, 1.1)
		add_child(snd)
		snd.play()
		snd.finished.connect(snd.queue_free)
	if player.has_signal("action_animation"):
		player.emit_signal("action_animation", "loot", 0.0, 0.15, 1.8)
	_set_picked_until(float(data.get("regrow_days", 1.0)))
	_refresh()


func _set_picked_until(days: float) -> void:
	var cycle := get_tree().get_first_node_in_group("world_cycle")
	var day_seconds := float(cycle.get("day_length_minutes")) * 60.0 if cycle else 24.0 * 60.0
	var seconds := maxf(days, 0.0) * day_seconds
	var s := _session()
	if s:
		var d: Dictionary = s.get("data")
		var herbs: Dictionary = d.get("herbs", {})
		herbs[key] = float(s.call("play_seconds")) + seconds
		d["herbs"] = herbs
	else:
		_unsaved[key] = Time.get_ticks_msec() + int(seconds * 1000.0)


## Shows or hides the fruit (berries, flowers, leaves) to match.
func _refresh() -> void:
	_picked = regrow_left() > 0.0
	var p := get_parent()
	if p == null:
		return
	for mi in p.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).to_lower().contains("fruit"):
			(mi as MeshInstance3D).visible = not _picked


func _physics_process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 1.0
		if _picked and regrow_left() <= 0.0:
			_refresh()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var show: bool = player != null and not _picked and player.get("talk_focus") == self
	_prompt.visible = show
	if show:
		var gs := get_tree().root.get_node_or_null("GameSettings")
		var db := get_tree().root.get_node_or_null("Database")
		var item := String(data.get("item", ""))
		var label := String((db.call("item", item) as Dictionary).get("name", item)) if db else item
		_prompt.text = "%s  %s %s" % [String(gs.call("interact_label")) if gs else "E", String(data.get("name", "Pick")), label]
