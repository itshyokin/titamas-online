class_name EventRunner
extends Node
## Runs an event page's commands one at a time (like RPG Maker's / Saturn's interpreter):
## a stack of command lists, so choices and "if" branches simply push their list.
## Messages go through DialogueBox (texts in a row share one box; a choice right after a
## text shows under it). The player stands still while an event runs, unless the page
## says otherwise ("freeze": false).
##
## Commands are dictionaries with "cmd" (see data/events.json and the Database Events tab):
##   text {speaker, text}                    choice {options[], branches[[...]], cancel}
##   if {conditions[], then[], else[]}       switch {id, value}      self_switch {letter, value}
##   variable {id, op set/add/sub/mul/random, value, max}
##   give_item {item, count, silent}         take_item {item, count}  gold {op add/take/set, value, silent}
##   xp {value}   heal {}   wait {seconds}   sound {sound}   log {text, color}
##   animation {role, wait}                  effect {color}
##   teleport {scene, marker, position, fade}   set_home {name}   fade_out / fade_in {seconds}
##   follower {npc, op join/leave}           call {event}   erase {}   stop {}
##   achievement {id}                        (Achievements.unlock)
## Text can use {player} and pronouns (DialogueBox), {var:id}, {gold} and {item:id} (its name).

signal finished

var source: Node  # the event (MapEvent) or NPC running this
var self_key := ""
var player: Node3D
var speaker := ""
var freeze := true

var _stack: Array = []  # [{list, i}]
var _wait := 0.0
var _box: DialogueBox
var _choice: Dictionary = {}
var _picked := -2
var _done := false


## Starts `commands`. `self_key`: whose self switches (A–D) they use.
static func run(commands: Array, from: Node, key: String, who: Node3D, default_speaker := "", stand_still := true) -> EventRunner:
	var r := EventRunner.new()
	r.source = from
	r.self_key = key
	r.player = who
	r.speaker = default_speaker
	r.freeze = stand_still
	r._stack = [{"list": commands, "i": 0}]
	r.name = "EventRunner"
	from.add_child(r)
	return r


func _ready() -> void:
	if freeze:
		GameSettings.menu_open = true
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity.x = 0.0
			(player as CharacterBody3D).velocity.z = 0.0
	_step(0.0)


func _process(delta: float) -> void:
	if not _done:
		_step(delta)


func _step(delta: float) -> void:
	for _guard in 500:
		if _done:
			return
		if freeze:
			GameSettings.menu_open = true
		if _wait > 0.0:
			_wait -= delta
			if _wait > 0.0:
				return
			_wait = 0.0
		if is_instance_valid(_box):
			return
		if not _choice.is_empty():
			if _picked == -2:
				return
			var branches: Array = _choice.get("branches", [])
			var i := _picked
			_choice = {}
			_picked = -2
			if i >= 0 and i < branches.size() and branches[i] is Array and not (branches[i] as Array).is_empty():
				_stack.append({"list": branches[i], "i": 0})
			continue
		if _stack.is_empty():
			_finish()
			return
		var top: Dictionary = _stack.back()
		var list: Array = top.list
		if int(top.i) >= list.size():
			_stack.pop_back()
			continue
		var c = list[top.i]
		top.i = int(top.i) + 1
		if c is Dictionary:
			_execute(c, list, top)


func _execute(c: Dictionary, list: Array, top: Dictionary) -> void:
	var inv := _inventory()
	match String(c.get("cmd", "")):
		"text":
			# This text and the ones straight after it (same speaker) in one box; a choice
			# right after shows under the last line.
			var who := String(c.get("speaker", ""))
			var lines := [_format(String(c.get("text", "")))]
			while int(top.i) < list.size() and list[top.i] is Dictionary and String(list[top.i].get("cmd", "")) == "text" \
					and String(list[top.i].get("speaker", "")) == who:
				lines.append(_format(String(list[top.i].get("text", ""))))
				top.i = int(top.i) + 1
			var next = list[top.i] if int(top.i) < list.size() else null
			if next is Dictionary and String(next.get("cmd", "")) == "choice":
				top.i = int(top.i) + 1
				_open_choice(next, lines, who)
			else:
				_box = DialogueBox.open(self, who if who != "" else speaker, String(c.get("title", "")), lines, Callable())
		"choice":
			_open_choice(c, [], "")
		"if":
			var ok := EventState.test_all(c.get("conditions", []), self_key, player)
			var branch = c.get("then", []) if ok else c.get("else", [])
			if branch is Array and not branch.is_empty():
				_stack.append({"list": branch, "i": 0})
		"switch":
			EventState.set_switch(String(c.get("id", "")), bool(c.get("value", true)))
		"self_switch":
			EventState.set_self(self_key, String(c.get("letter", "A")), bool(c.get("value", true)))
		"variable":
			var id := String(c.get("id", ""))
			var v := float(c.get("value", 0.0))
			var now := EventState.get_var(id)
			match String(c.get("op", "set")):
				"add": now += v
				"sub": now -= v
				"mul": now *= v
				"random": now = float(randi_range(int(v), int(c.get("max", v))))
				_: now = v
			EventState.set_var(id, now)
		"give_item":
			if inv == null:
				return
			var id := String(c.get("item", ""))
			var count := maxi(int(c.get("count", 1)), 1)
			if Database.item(id).is_empty():
				push_warning("Event: no item '%s'" % id)
				return
			var left := inv.add_item(id, count)
			if left > 0:
				# Not enough room: take back what went in, say so and stop, so a chest stays
				# closed to try again later.
				if left < count:
					inv.call("remove_item", id, count - left)
				_box = DialogueBox.open(self, "", "", ["Not enough room in your backpack for %s." % _item_text(id, count)], Callable())
				_stack.clear()
			elif not bool(c.get("silent", false)):
				_announce("Received %s" % _item_text(id, count), Color(0.75, 1.0, 0.6))
			EventState.changed()
		"take_item":
			if inv:
				inv.call("remove_item", String(c.get("item", "")), maxi(int(c.get("count", 1)), 1))
				EventState.changed()
		"gold":
			if inv == null:
				return
			var v := int(c.get("value", 0))
			match String(c.get("op", "add")):
				"take": inv.add_gold(-v)
				"set": inv.add_gold(v - int(inv.gold))
				_:
					inv.add_gold(v)
					if v > 0 and not bool(c.get("silent", false)):
						_announce("Received %d gold" % v, Color(1.0, 0.85, 0.35))
			EventState.changed()
		"xp":
			var progress := player.get_node_or_null("Progress") if player else null
			if progress:
				progress.call("add_xp", int(c.get("value", 0)), "")
		"heal":
			var stats := player.get_node_or_null("Stats") if player else null
			if stats:
				stats.call("restore")
				Effects.heal_glow(player, 1.5)
		"wait":
			_wait = float(c.get("seconds", 1.0))
		"sound":
			var path := String(c.get("sound", ""))
			if ResourceLoader.exists(path) and player:
				Combat.play_sound(player, load(path), float(c.get("volume_db", 0.0)))
		"log":
			GameLog.post(_format(String(c.get("text", ""))), Color.from_string(String(c.get("color", "#e6e6e0")), Color(0.9, 0.9, 0.88)))
		"animation":
			var pc := player as PlayerController
			var role := String(c.get("role", ""))
			if pc and role != "" and pc.state == PlayerController.State.NORMAL:
				pc.action_animation.emit(role, 0.0, 0.15, 1.0)
				if bool(c.get("wait", false)):
					var model := pc.get_node_or_null("Model/Character") as CharacterModel
					_wait = model.get_animation_length(role) if model else 1.0
		"effect":
			var at := source as Node3D if source is Node3D else player
			if c.get("on", "event") == "player":
				at = player
			if at:
				Effects.burst(Combat.world_root(at), at.global_position + Vector3.UP, Color.from_string(String(c.get("color", "#ffd76a")), Color.WHITE), float(c.get("size", 1.0)))
		"achievement":
			var ach := get_node_or_null("/root/Achievements")
			if ach:
				ach.call("unlock", String(c.get("id", "")))
		"fade_out":
			ScreenFade.to_black(self, float(c.get("seconds", 0.6)))
			_wait = float(c.get("seconds", 0.6))
		"fade_in":
			ScreenFade.clear(self, float(c.get("seconds", 0.6)))
			_wait = float(c.get("seconds", 0.6))
		"teleport":
			# Ends the event: the level may be about to go away.
			_stack.clear()
			var at = c.get("position", null)
			var scene := String(c.get("scene", ""))
			var marker := String(c.get("marker", ""))
			var fade := bool(c.get("fade", true))
			_finish()
			GameSession.travel_to(scene, marker, at, fade)
		"set_home":
			if player and GameSession.active():
				var scene := get_tree().current_scene
				var where := player.global_position
				GameSession.set_home(scene.scene_file_path if scene else "", where, String(c.get("name", "here")))
				_announce("Home set: %s" % String(c.get("name", "here")), Color(0.6, 0.85, 1.0))
		"follower":
			var npc_id := String(c.get("npc", ""))
			for n in get_tree().get_nodes_in_group("npcs"):
				if String(n.get("npc_id")) == npc_id and n.has_method("follow"):
					n.call("follow", player if String(c.get("op", "join")) == "join" else null)
		"call":
			var ev := Database.event(String(c.get("event", "")))
			var page := MapEvent.active_page(ev, String(ev.get("id", "")), player)
			if not page.is_empty():
				_stack.append({"list": page.get("commands", []), "i": 0})
		"erase":
			if source and source.has_method("erase"):
				source.call("erase")
		"stop":
			_stack.clear()
		"note":
			pass
		var other:
			push_warning("Event: unknown command '%s'" % other)


func _open_choice(c: Dictionary, lines: Array, who: String) -> void:
	_choice = c
	_picked = -2
	var choices := []
	var options: Array = c.get("options", [])
	for i in options.size():
		choices.append([_format(String(options[i])), _choose.bind(i)])
	var cancel := int(c.get("cancel", -1))
	_box = DialogueBox.open(self, who if who != "" else speaker, "", lines, _box_closed.bind(cancel), choices)


func _choose(i: int) -> String:
	_picked = i
	return ""


## Closed without choosing (Esc / B): the cancel branch (-1 = none).
func _box_closed(cancel: int) -> void:
	if _picked == -2:
		_picked = cancel


func _finish() -> void:
	if _done:
		return
	_done = true
	if freeze and not DialogueBox.is_open:
		GameSettings.menu_open = false
	finished.emit()
	queue_free()


func _inventory() -> Inventory:
	return player.get_node_or_null("Inventory") as Inventory if player else null


func _item_text(id: String, count: int) -> String:
	var n := String(Database.item(id).get("name", id))
	return ("%d x %s" % [count, n]) if count > 1 else n


func _announce(text: String, color: Color) -> void:
	GameLog.post(text, color)
	HUD.notify(self, text, color, 2.5)


func _format(text: String) -> String:
	var inv := _inventory()
	if inv:
		text = text.replace("{gold}", str(inv.gold))
	var rx := RegEx.create_from_string("\\{(var|item):([a-z0-9_]+)\\}")
	for m in rx.search_all(text):
		var value := ""
		if m.get_string(1) == "var":
			var v := EventState.get_var(m.get_string(2))
			value = str(int(v)) if is_equal_approx(v, roundf(v)) else str(v)
		else:
			value = String(Database.item(m.get_string(2)).get("name", m.get_string(2)))
		text = text.replace(m.get_string(), value)
	return text
