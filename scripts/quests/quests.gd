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
## Rewards: reward_gold, reward_xp, reward_items [{item, count}] (given by complete();
## take_items = the carried "item" objectives are handed over first) and `rewards` (extra
## text). Events offer quests (command "quest" op "offer": the QuestOffer window with
## accepted / declined branches), start / complete / fail them and test them (condition
## "quest": not_started / active / ready / done / failed). start_sound / complete_sound
## (top of quests.json, Database → Quest Settings) play on accept and hand-in.

static var _unsaved := {}
## The tracker and markers listen to this (any quest changed state or progress).
static var revision := 0


static func all() -> Array:
	var db := _db()
	return db.get("quests") if db else []


## The top of quests.json (sounds).
static func settings() -> Dictionary:
	var db := _db()
	var s = db.get("quest_settings") if db else null
	return s if s is Dictionary else {}


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
	_play("start_sound")
	_announce("Quest accepted: %s" % q.get("name", id), Color(1.0, 0.85, 0.35))


## Hands the quest in: takes the carried quest items (take_items), gives gold, XP and
## items. Returns "" when done, or why not (no room in the backpack for the reward items).
static func complete(id: String) -> String:
	var q := get_quest(id)
	if q.is_empty() or state(id) == "done":
		return ""
	var player := _player()
	var inv := player.get_node_or_null("Inventory") if player else null
	var items := reward_items(q)
	var taken: Array = []
	if inv:
		if bool(q.get("take_items", false)):
			for o: Dictionary in q.get("objectives", []):
				if String(o.get("type", "item")) == "item":
					var item_id := String(o.get("item", ""))
					var n := mini(int(inv.call("count_of", item_id)), maxi(int(o.get("count", 1)), 1))
					if n > 0:
						inv.call("remove_item", item_id, n)
						taken.append({"item": item_id, "count": n})
		if not items.is_empty() and not bool(inv.call("has_room_for", items)):
			for t: Dictionary in taken:
				inv.call("add_item", t.item, t.count)
			var why := "Make room in your backpack for the reward first."
			_announce(why, Color(1.0, 0.75, 0.6))
			return why
	var e: Dictionary = _store().get(id, {})
	e["state"] = "done"
	_store()[id] = e
	_play("complete_sound")
	_announce("Quest complete: %s" % q.get("name", id), Color(0.6, 1.0, 0.55))
	if inv:
		var gold := int(q.get("reward_gold", 0))
		if gold > 0:
			inv.call("add_gold", gold)
			GameLog.post("You receive %d gold." % gold, Color(1.0, 0.85, 0.35))
		for r: Dictionary in items:
			inv.call("add_item", r.item, r.count)
			var name := String(_item(r.item).get("name", r.item))
			GameLog.post("Received %s." % (("%d x %s" % [r.count, name]) if int(r.count) > 1 else name), Color(0.75, 1.0, 0.6))
	var xp := int(q.get("reward_xp", 0))
	var progress := player.get_node_or_null("Progress") if player else null
	if xp > 0 and progress:
		progress.call("add_xp", xp, String(q.get("name", id)))
	_changed()
	return ""


## Reward items that exist: [{item, count}].
static func reward_items(q: Dictionary) -> Array:
	var out: Array = []
	for r in q.get("reward_items", []):
		if r is Dictionary and not _item(String(r.get("item", ""))).is_empty():
			out.append({"item": String(r.item), "count": maxi(int(r.get("count", 1)), 1)})
	return out


## "120 XP · 50 gold" plus the extra rewards text (items are listed separately).
static func rewards_line(q: Dictionary) -> String:
	var parts: Array[String] = []
	if int(q.get("reward_xp", 0)) > 0:
		parts.append("%d XP" % int(q.reward_xp))
	if int(q.get("reward_gold", 0)) > 0:
		parts.append("%d gold" % int(q.reward_gold))
	if String(q.get("rewards", "")) != "":
		parts.append(String(q.rewards))
	return "  ·  ".join(parts)


static func _item(id: String) -> Dictionary:
	var db := _db()
	return db.call("item", id) if db and id != "" else {}


static func _play(key: String) -> void:
	var path := String(settings().get(key, ""))
	var loop := Engine.get_main_loop() as SceneTree
	if path == "" or loop == null or not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.bus = &"SFX"
	p.volume_db = float(settings().get("sound_db", -4.0))
	loop.root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


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
