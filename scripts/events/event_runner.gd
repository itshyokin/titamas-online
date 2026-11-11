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
##   quest {id, op offer/start/complete/fail/reset} (Quests; offer shows QuestOffer and runs
##        its accepted[] or declined[] branch; complete stops the event if the backpack
##        has no room for the reward items)
##   weather {type, minutes}                 (Weather.force; 0 minutes = until the next change)
##   say {who event/player/npc, npc, name, text, sound, log, seconds, wait}
##        a line spoken out loud while play goes on (SpeechBubble over the speaker, voice
##        clip, game log line); wait = the event waits until it's been read
##   nav {op set/clear, id, target, label, color, reach}   HUD waypoint (NavPoints)
##   wait_for {conditions[], timeout}        waits (play goes on) until they all hold
##   shake {seconds, strength, sound}        camera shake + controller rumble (+ rumble sound)
##   toss {toward away/marker, marker, power, height, down}  the ground bursts under the
##        player, throwing them (knocked down) away from the event or toward a marker
##   video {video, skippable, pause}         full-screen .ogv; the event waits for it
##   camera {op move/back, marker, look, npc, seconds, wait}   cutscene camera glides
##   letterbox {on, seconds}                 black bars top and bottom
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
var _waiting_for: Dictionary = {}  # wait_for: {conditions, left}
var _bubble: Node  # say with wait: the bubble being read
var _video: Node


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
		if not _waiting_for.is_empty():
			_waiting_for.left = float(_waiting_for.left) - delta
			_waiting_for.check = float(_waiting_for.get("check", 0.0)) - delta
			if float(_waiting_for.check) > 0.0 and float(_waiting_for.left) > 0.0:
				return
			_waiting_for.check = 0.25
			if not EventState.test_all(_waiting_for.conditions, self_key, player) and float(_waiting_for.left) > 0.0:
				return
			_waiting_for = {}
		if is_instance_valid(_bubble) or is_instance_valid(_video):
			return
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
		"quest":
			match String(c.get("op", "start")):
				"offer":
					_choice = {"branches": [c.get("accepted", []), c.get("declined", [])]}
					_picked = -2
					QuestOffer.open(self, String(c.get("id", "")), func(accepted: bool) -> void: _picked = 0 if accepted else 1)
				"start": Quests.start(String(c.get("id", "")))
				"complete":
					var why := Quests.complete(String(c.get("id", "")))
					if why != "":
						_box = DialogueBox.open(self, "", "", [why], Callable())
						_stack.clear()
				"fail": Quests.fail(String(c.get("id", "")))
				"reset": Quests.reset(String(c.get("id", "")))
		"weather":
			var atmos := get_tree().get_first_node_in_group("atmosphere")
			var w: Weather = atmos.get("weather") if atmos else null
			if w:
				w.force(String(c.get("type", "clear")), float(c.get("minutes", 0.0)))
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
		"say":
			var who := _speaker_node(c)
			var who_name := String(c.get("name", ""))
			if who_name.is_empty():
				match String(c.get("who", "event")):
					"npc": who_name = String(Database.npc(String(c.get("npc", ""))).get("name", c.get("npc", "")))
					"player": who_name = String(GameSession.data.get("name", "You")) if GameSession.active() else "You"
					_: who_name = speaker
			var line := _format(String(c.get("text", "")))
			var voice: AudioStream = null
			var path := String(c.get("sound", ""))
			if path != "" and ResourceLoader.exists(path):
				voice = load(path)
			var b := SpeechBubble.say(self, who, who_name, line, float(c.get("seconds", 0.0)), voice)
			if bool(c.get("log", true)):
				GameLog.post(("%s: %s" % [who_name, line]) if who_name != "" else line, Color(0.95, 0.9, 0.75))
			if bool(c.get("wait", true)):
				_bubble = b
		"nav":
			if String(c.get("op", "set")) == "clear":
				NavPoints.clear(String(c.get("id", "")))
			else:
				NavPoints.set_point(String(c.get("id", "main")), String(c.get("target", "")), _format(String(c.get("label", ""))),
					String(c.get("color", NavPoints.DEFAULT_COLOR)), float(c.get("reach", 0.0)))
		"wait_for":
			var conds: Array = c.get("conditions", [])
			if not conds.is_empty():
				var timeout := float(c.get("timeout", 0.0))
				_waiting_for = {"conditions": conds, "left": timeout if timeout > 0.0 else INF, "check": 0.0}
		"shake":
			var snd: AudioStream = null
			var sp := String(c.get("sound", "rumble"))
			if sp == "rumble":
				snd = Cutscene.RUMBLE
			elif sp != "" and ResourceLoader.exists(sp):
				snd = load(sp)
			Cutscene.shake(self, float(c.get("seconds", 2.0)), float(c.get("strength", 0.4)), snd)
			if bool(c.get("wait", false)):
				_wait = float(c.get("seconds", 2.0))
		"toss":
			_toss(c)
		"video":
			_video = Cutscene.video(self, String(c.get("video", "")), bool(c.get("skippable", true)), bool(c.get("pause", true)))
			if _video:
				process_mode = Node.PROCESS_MODE_ALWAYS  # keep going once the video ends
				_video.tree_exited.connect(func() -> void: process_mode = Node.PROCESS_MODE_INHERIT)
		"camera":
			var seconds := float(c.get("seconds", 1.5))
			if String(c.get("op", "move")) == "back":
				Cutscene.camera_back(self, seconds)
			else:
				var scene := get_tree().current_scene
				var to := scene.find_child(String(c.get("marker", "")), true, false) as Node3D if scene else null
				if to == null:
					push_warning("Event camera: no node named '%s'" % c.get("marker", ""))
				else:
					Cutscene.camera_to(self, to, _look_node(c), seconds)
			if bool(c.get("wait", true)):
				_wait = seconds
		"letterbox":
			Cutscene.letterbox(self, bool(c.get("on", true)), float(c.get("seconds", 0.6)))
			_wait = float(c.get("seconds", 0.6))
		var other:
			push_warning("Event: unknown command '%s'" % other)


## Who a "say" line comes from: the event (its NPC / model), the player or an NPC by id.
func _speaker_node(c: Dictionary) -> Node3D:
	match String(c.get("who", "event")):
		"player":
			return player
		"npc":
			var id := String(c.get("npc", ""))
			for n in get_tree().get_nodes_in_group("npcs"):
				if String(n.get("npc_id")) == id:
					return n as Node3D
			return null
	if source and source.get("_visual") is Node3D and is_instance_valid(source.get("_visual")):
		return source.get("_visual")
	return source as Node3D if source is Node3D else null


## What the camera command turns to look at: "player", "event", "npc" or a node's name.
func _look_node(c: Dictionary) -> Node3D:
	var look := String(c.get("look", ""))
	match look:
		"":
			return null
		"player":
			return player
		"event":
			return _speaker_node({"who": "event"})
		"npc":
			return _speaker_node({"who": "npc", "npc": c.get("npc", "")})
	var scene := get_tree().current_scene
	return scene.find_child(look, true, false) as Node3D if scene else null


## The ground bursts under the player and throws them: away from the event (or toward a
## marker), knocked off their feet.
func _toss(c: Dictionary) -> void:
	var pc := player as PlayerController
	if pc == null:
		return
	var from_pos := (source as Node3D).global_position if source is Node3D else pc.global_position
	var dir := pc.global_position - from_pos
	if String(c.get("toward", "away")) == "marker":
		var scene := get_tree().current_scene
		var m := scene.find_child(String(c.get("marker", "")), true, false) as Node3D if scene else null
		if m:
			dir = m.global_position - pc.global_position
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = -pc.global_basis.z
	dir = dir.normalized()
	var power := float(c.get("power", 9.0))
	var root := Combat.world_root(pc)
	var feet := pc.global_position
	Effects.shockwave(root, feet, 3.5, Color(0.72, 0.62, 0.46))
	for i in 10:
		var chip := TrollRock.Chip.new()
		chip.velocity = Vector3(randf_range(-4, 4), randf_range(5, 9), randf_range(-4, 4))
		root.add_child(chip)
		chip.global_position = feet + Vector3.UP * 0.3
	Combat.play_sound(pc, preload("res://assets/audio/creatures/ground_smash.ogg"), 4.0, randf_range(1.0, 1.15))
	Cutscene.shake(self, 0.5, 0.5)
	pc.knock_down(dir * power + Vector3.UP * float(c.get("height", 5.0)), float(c.get("down", 1.4)))
	var hurt := float(c.get("damage", 0.0))
	if hurt > 0.0:
		var st := pc.get_node_or_null("Stats")
		if st:
			st.call("take_damage", hurt, source)


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
