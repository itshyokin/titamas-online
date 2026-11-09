class_name Quests
extends RefCounted
## Quests: data/quests.json (Database → Quests), progress saved with the character
## (GameSession.data "quests": {id: {state: "active"/"done"/"failed", kills: {enemy: n}}};
## in memory when testing without a saved character).
##
## A quest: {id, name, giver (who gives it, shown in the log), description, rewards (text),
## giver_event / giver_npc (whose head shows "!" while it can be taken and "?" while it's
## ready to hand in), objectives: [{text, type, ..., count}]}. Objective types:
##   item      carry `count` of `item`
##   kill      defeat `count` of `enemy` ("" = any) after the quest starts
##   switch    switch `switch` is on
##   variable  variable `variable` >= count
## Events start / complete / fail quests (command "quest") and test them (condition
## "quest": not_started / active / ready / done / failed).

static var _unsaved := {}
## The tracker and markers listen to this (any quest changed state or progress).
static var revision := 0


static func all() -> Array:
	var db := _db()
	return db.get("quests") if db else []


static func get_quest(id: String) -> Dictionary:
	for q: Dictionary in all():
		if String(q.get("id", "")) == id:
			return q
	return {}


static func _store() -> Dictionary:
	var session := _session()
	if session and session.call("active"):
		var data: Dictionary = session.get("data")
		if not data.get("quests") is Dictionary:
			data["quests"] = {}
		return data["quests"]
	return _unsaved


static func _session() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("GameSession") if loop else null


static func _db() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("Database") if loop else null


static func _player() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.get_first_node_in_group("player") if loop else null


## "not_started", "active", "done" or "failed".
static func state(id: String) -> String:
	var e = _store().get(id)
	return String(e.get("state", "not_started")) if e is Dictionary else "not_started"


static func is_active(id: String) -> bool:
	return state(id) == "active"


static func start(id: String) -> void:
	var q := get_quest(id)
	if q.is_empty() or state(id) == "active":
		return
	_store()[id] = {"state": "active", "kills": {}}
	_changed()
	_announce("Quest accepted: %s" % q.get("name", id), Color(1.0, 0.85, 0.35))


static func complete(id: String) -> void:
	var q := get_quest(id)
	if q.is_empty() or state(id) == "done":
		return
	var e: Dictionary = _store().get(id, {})
	e["state"] = "done"
	_store()[id] = e
	_changed()
	_announce("Quest complete: %s" % q.get("name", id), Color(0.6, 1.0, 0.55))


static func fail(id: String) -> void:
	var q := get_quest(id)
	if q.is_empty() or state(id) != "active":
		return
	_store()[id]["state"] = "failed"
	_changed()
	_announce("Quest failed: %s" % q.get("name", id), Color(1.0, 0.5, 0.45))


## Forgets a quest (back to not started).
static func reset(id: String) -> void:
	_store().erase(id)
	_changed()


## An enemy the player fought died (PlayerProgress.credit_kill).
static func count_kill(enemy_id: String) -> void:
	var any := false
	for id: String in _store().keys():
		var e: Dictionary = _store()[id]
		if String(e.get("state", "")) != "active":
			continue
		var before := ready(id)
		var kills: Dictionary = e.get("kills", {})
		kills[enemy_id] = int(kills.get(enemy_id, 0)) + 1
		kills[""] = int(kills.get("", 0)) + 1
		e["kills"] = kills
		any = true
		if ready(id) and not before:
			_announce("%s: ready to hand in" % get_quest(id).get("name", id), Color(0.6, 1.0, 0.55))
	if any:
		_changed()


## Progress on one objective: [have, need].
static func progress(id: String, objective: Dictionary) -> Vector2i:
	var need := maxi(int(objective.get("count", 1)), 1)
	var have := 0
	match String(objective.get("type", "item")):
		"item":
			var inv := _player().get_node_or_null("Inventory") if _player() else null
			have = int(inv.call("count_of", String(objective.get("item", "")))) if inv else 0
		"kill":
			var e = _store().get(id, {})
			var kills: Dictionary = e.get("kills", {}) if e is Dictionary else {}
			have = int(kills.get(String(objective.get("enemy", "")), 0))
		"switch":
			need = 1
			have = 1 if EventState.get_switch(String(objective.get("switch", ""))) else 0
		"variable":
			have = int(EventState.get_var(String(objective.get("variable", ""))))
	if state(id) == "done":
		have = need
	return Vector2i(mini(have, need), need)


## Every objective met (an active quest ready to hand in).
static func ready(id: String) -> bool:
	if state(id) != "active":
		return false
	for o: Dictionary in get_quest(id).get("objectives", []):
		var p := progress(id, o)
		if p.x < p.y:
			return false
	return true


## Event condition {type: "quest", id, state: not_started/active/ready/done/failed}.
static func test(c: Dictionary) -> bool:
	var id := String(c.get("id", ""))
	match String(c.get("state", "active")):
		"ready":
			return ready(id)
		"active":
			return is_active(id)
		var s:
			return state(id) == s


## "!" (a quest to take), "?" (ready to hand in) or "" for an event / NPC.
static func marker_for(event_id: String, npc_id: String) -> String:
	var mark := ""
	for q: Dictionary in all():
		var mine := (event_id != "" and String(q.get("giver_event", "")) == event_id) \
			or (npc_id != "" and String(q.get("giver_npc", "")) == npc_id)
		if not mine:
			continue
		var id := String(q.get("id", ""))
		if ready(id):
			return "?"
		if state(id) == "not_started" and EventState.test_all(q.get("available", []), "", _player()):
			mark = "!"
	return mark


static func active_quests() -> Array:
	return all().filter(func(q: Dictionary) -> bool: return is_active(String(q.get("id", ""))))


static func _changed() -> void:
	revision += 1
	EventState.changed()


static func _announce(text: String, color: Color) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	var hud := loop.get_first_node_in_group("hud") if loop else null
	if hud:
		hud.call("show_message", text, 3.0, color)  # (not HUD.notify: the HUD uses this class)
	GameLog.post(text, color)
