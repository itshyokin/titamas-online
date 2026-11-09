extends Node
## Achievements (autoload "Achievements"): defined in data/achievements.json (Database →
## Achievements), unlocked for the player across every character (like Steam / Xbox),
## kept in user://achievements.cfg.
##
## Each one has an id (also its Steam API name), name, description (how it was earned,
## shown after the name in the pop-up), icon, points, hidden (??? until earned) and a rule:
##   {kind: "event"}                       only the event command "Unlock achievement"
##   {kind: "switch", switch}              that switch turns on
##   {kind: "defeat", enemy, count}        enemies defeated (one kind, or any when no enemy)
##   {kind: "level", level}                reach a level
##   {kind: "item", item, count}           carry an item
##   {kind: "gold", amount}                hold this much gold
## Steam: when a Steam singleton (GodotSteam) is present, unlocks are sent to it too.

signal unlocked(id: String)

const SAVE := "user://achievements.cfg"
const SOUND := preload("res://assets/audio/sfx/achievement.ogg")

var _cfg := ConfigFile.new()
var _check := 0.0
var _queue: Array[Dictionary] = []
var _popup: CanvasLayer


func _ready() -> void:
	_cfg.load(SAVE)


func all() -> Array:
	return Database.achievements


func get_def(id: String) -> Dictionary:
	for a: Dictionary in Database.achievements:
		if String(a.get("id", "")) == id:
			return a
	return {}


func is_unlocked(id: String) -> bool:
	return _cfg.has_section_key("unlocked", id)


## When it was earned (unix time), 0 if not.
func unlocked_at(id: String) -> int:
	return int(_cfg.get_value("unlocked", id, 0))


func points() -> Vector2i:
	var got := 0
	var total := 0
	for a: Dictionary in Database.achievements:
		total += int(a.get("points", 0))
		if is_unlocked(String(a.get("id", ""))):
			got += int(a.get("points", 0))
	return Vector2i(got, total)


## Earns it (once): saved, the pop-up shows, Steam is told.
func unlock(id: String) -> void:
	var def := get_def(id)
	if def.is_empty():
		push_warning("Achievements: no '%s' in data/achievements.json" % id)
		return
	if is_unlocked(id):
		return
	_cfg.set_value("unlocked", id, int(Time.get_unix_time_from_system()))
	_cfg.save(SAVE)
	if Engine.has_singleton("Steam"):
		var steam := Engine.get_singleton("Steam")
		steam.call("setAchievement", String(def.get("steam_id", id)) if String(def.get("steam_id", "")) != "" else id)
		steam.call("storeStats")
	unlocked.emit(id)
	_queue.append(def)
	if _popup == null or not is_instance_valid(_popup):
		_show_next()


## Testing: forget them all.
func reset_all() -> void:
	_cfg.erase_section("unlocked") if _cfg.has_section("unlocked") else null
	_cfg.erase_section("counts") if _cfg.has_section("counts") else null
	_cfg.save(SAVE)


## An enemy died to the player (PlayerProgress.credit_kill).
func count_kill(enemy_id: String) -> void:
	for key in ["any", enemy_id]:
		_cfg.set_value("counts", "kills_" + key, int(_cfg.get_value("counts", "kills_" + key, 0)) + 1)
	_cfg.save(SAVE)
	_check_rules()


func _process(delta: float) -> void:
	_check += delta
	if _check >= 1.0:
		_check = 0.0
		_check_rules()


func _check_rules() -> void:
	var player := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	for a: Dictionary in Database.achievements:
		var id := String(a.get("id", ""))
		if is_unlocked(id):
			continue
		var rule: Dictionary = a.get("rule", {})
		var ok := false
		match String(rule.get("kind", "event")):
			"switch":
				ok = EventState.get_switch(String(rule.get("switch", "")))
			"defeat":
				var key := String(rule.get("enemy", ""))
				ok = int(_cfg.get_value("counts", "kills_" + (key if key != "" else "any"), 0)) >= int(rule.get("count", 1))
			"level":
				var progress := player.get_node_or_null("Progress") if player else null
				ok = progress != null and int(progress.get("level")) >= int(rule.get("level", 2))
			"item":
				var inv := player.get_node_or_null("Inventory") if player else null
				ok = inv != null and int(inv.call("count_of", String(rule.get("item", "")))) >= int(rule.get("count", 1))
			"gold":
				var inv := player.get_node_or_null("Inventory") if player else null
				ok = inv != null and int(inv.get("gold")) >= int(rule.get("amount", 100))
		if ok:
			unlock(id)


func _show_next() -> void:
	if _queue.is_empty():
		return
	_popup = AchievementPopup.new()
	_popup.def = _queue.pop_front()
	_popup.sound = SOUND
	_popup.tree_exited.connect(_show_next.call_deferred)
	get_tree().root.add_child(_popup)
