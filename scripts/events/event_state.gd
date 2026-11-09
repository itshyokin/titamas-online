class_name EventState
extends RefCounted
## What events remember: switches (on/off by id), variables (numbers by id) and each
## event's own self switches (A–D). Saved with the character (GameSession.data
## "switches", "variables", "self_switches"); kept in memory only when testing without
## a saved character (F6). Names for switches and variables are in data/events.json.
##
## Conditions (event pages, "if" commands) are dictionaries with a "type":
##   {type: "switch", id, is}            a switch is on (is: true) / off
##   {type: "self", letter, is}          the event's own A–D
##   {type: "variable", id, op, value}   op: >= <= == != > <
##   {type: "item", item, count}         carrying at least `count`
##   {type: "gold", value}               at least this much gold
##   {type: "level", value}              at least this level
##   {type: "class", id}                 playing this class
##   {type: "quest", id, state}          not_started / active / ready / done / failed (Quests)

const LETTERS := ["A", "B", "C", "D"]

static var _unsaved := {"switches": {}, "variables": {}, "self_switches": {}}


static func _store(which: String) -> Dictionary:
	var session := _session()
	if session and session.call("active"):
		var data: Dictionary = session.get("data")
		if not data.get(which) is Dictionary:
			data[which] = {}
		return data[which]
	return _unsaved[which]


static func _session() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("GameSession") if loop else null


static func get_switch(id: String) -> bool:
	return bool(_store("switches").get(id, false))


static func set_switch(id: String, on: bool) -> void:
	if id.is_empty():
		return
	_store("switches")[id] = on
	changed()


static func get_var(id: String) -> float:
	return float(_store("variables").get(id, 0.0))


static func set_var(id: String, value: float) -> void:
	if id.is_empty():
		return
	_store("variables")[id] = value
	changed()


static func get_self(key: String, letter: String) -> bool:
	return bool(_store("self_switches").get(key + ":" + letter, false))


static func set_self(key: String, letter: String, on: bool) -> void:
	if key.is_empty():
		return
	_store("self_switches")[key + ":" + letter] = on
	changed()


## Something changed: every event in the level picks its page again.
static func changed() -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop:
		loop.call_group("map_events", "refresh")


## Forgets everything (a new character while testing).
static func reset_unsaved() -> void:
	_unsaved = {"switches": {}, "variables": {}, "self_switches": {}}


## All of `conditions` hold (an empty list always does). `self_key`: whose A–D.
static func test_all(conditions: Array, self_key: String, player: Node) -> bool:
	for c in conditions:
		if c is Dictionary and not test(c, self_key, player):
			return false
	return true


static func test(c: Dictionary, self_key: String, player: Node) -> bool:
	var is_on := bool(c.get("is", true))
	match String(c.get("type", "")):
		"switch":
			return get_switch(String(c.get("id", ""))) == is_on
		"self":
			return get_self(self_key, String(c.get("letter", "A"))) == is_on
		"variable":
			return compare(get_var(String(c.get("id", ""))), String(c.get("op", ">=")), float(c.get("value", 0.0)))
		"item":
			var inv := _inventory(player)
			return inv != null and int(inv.call("count_of", String(c.get("item", "")))) >= int(c.get("count", 1))
		"gold":
			var inv := _inventory(player)
			return inv != null and int(inv.get("gold")) >= int(c.get("value", 0))
		"level":
			var progress := player.get_node_or_null("Progress") if player else null
			return progress != null and int(progress.get("level")) >= int(c.get("value", 1))
		"class":
			var session := _session()
			var data: Dictionary = session.get("data") if session else {}
			return String(data.get("class", "")) == String(c.get("id", ""))
		"quest":
			return Quests.test(c)
	return true


static func compare(a: float, op: String, b: float) -> bool:
	match op:
		">=": return a >= b
		"<=": return a <= b
		"==": return is_equal_approx(a, b)
		"!=": return not is_equal_approx(a, b)
		">": return a > b
		"<": return a < b
	return false


static func _inventory(player: Node) -> Node:
	return player.get_node_or_null("Inventory") if player else null
