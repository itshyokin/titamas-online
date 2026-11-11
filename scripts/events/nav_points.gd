class_name NavPoints
extends RefCounted
## Waypoints on the HUD (the "Nav point" event command): a marker over the place or thing
## with its distance in metres, at the screen edge when it's off-screen, and on the
## compass. Kept with the save (EventState.nav_store). Several can be shown at once,
## each under its own id.
##
## Targets: "marker:<node name>" (any node in the level, usually a Marker3D),
## "event:<event id>", "npc:<npc id>", "enemy:<node name>[,<node name>...]" (the nearest
## one still alive; the point goes away when all are dead), "player" (for tests) or
## "pos:x,y,z". `reach` > 0: the point goes away when the player gets that close.

const DEFAULT_COLOR := "#ffd35c"


static func set_point(id: String, target: String, label := "", color := DEFAULT_COLOR, reach := 0.0) -> void:
	EventState.nav_store()[id if not id.is_empty() else "main"] = {"target": target, "label": label, "color": color, "reach": reach}


static func clear(id := "") -> void:
	var store := EventState.nav_store()
	if id.is_empty() or id == "all":
		store.clear()
	else:
		store.erase(id)


## [{id, label, color, position}] of every point that can be found in this level right
## now; points whose enemies are all dead or that were reached are cleared.
static func resolve(tree: SceneTree) -> Array:
	var out := []
	var store := EventState.nav_store()
	var player := tree.get_first_node_in_group("player") as Node3D
	for id in store.keys():
		var p: Dictionary = store[id]
		var target := String(p.get("target", ""))
		var at = _find(tree, target, player)
		if at == null:
			if target.begins_with("enemy:") and _enemies_all_dead(tree, target):
				store.erase(id)
			continue
		var pos: Vector3 = at
		var reach := float(p.get("reach", 0.0))
		if reach > 0.0 and player and player.global_position.distance_to(pos) <= reach:
			store.erase(id)
			continue
		out.append({"id": id, "label": String(p.get("label", "")), "color": Color.from_string(String(p.get("color", DEFAULT_COLOR)), Color(1, 0.83, 0.36)), "position": pos})
	return out


static func _find(tree: SceneTree, target: String, player: Node3D):
	var scene := tree.current_scene
	if scene == null:
		return null
	var kind := target.get_slice(":", 0)
	var what := target.substr(kind.length() + 1)
	match kind:
		"marker", "node":
			var n := scene.find_child(what, true, false) as Node3D
			return n.global_position if n else null
		"event":
			for e in tree.get_nodes_in_group("map_events"):
				if String(e.get("event_id")) == what:
					var v = e.get("_visual")
					return (v as Node3D).global_position + Vector3.UP * 1.2 if v is Node3D and is_instance_valid(v) else (e as Node3D).global_position + Vector3.UP
			return null
		"npc":
			for n in tree.get_nodes_in_group("npcs"):
				if String(n.get("npc_id")) == what:
					return (n as Node3D).global_position + Vector3.UP * 2.1
			return null
		"enemy":
			var best = null
			var best_d := INF
			for name in what.split(",", false):
				var n := scene.find_child(name.strip_edges(), true, false) as Node3D
				if n == null or not n.is_in_group(Combat.GROUP) or not _alive(n):
					continue
				var d := n.global_position.distance_to(player.global_position) if player else 0.0
				if d < best_d:
					best_d = d
					best = (n.call("aim_point") as Vector3) + Vector3.UP * 1.0 if n.has_method("aim_point") else n.global_position + Vector3.UP * 2.0
			return best
		"player":
			return player.global_position + Vector3.UP * 2.0 if player else null
		"pos":
			var v := what.split(",")
			return Vector3(float(v[0]), float(v[1]), float(v[2])) if v.size() == 3 else null
	return null


static func _alive(n: Node) -> bool:
	var st := n.get_node_or_null("Stats")
	return st != null and not st.call("is_dead")


static func _enemies_all_dead(tree: SceneTree, target: String) -> bool:
	var scene := tree.current_scene
	for name in target.substr(6).split(",", false):
		var n := scene.find_child(name.strip_edges(), true, false) if scene else null
		if n and n.is_in_group(Combat.GROUP) and _alive(n):
			return false
		if n and not n.is_in_group(Combat.GROUP) and n.get("_present") == false and n.get("appear_switch") != "":
			return false  # not here yet (a boss that hasn't appeared)
	return true
