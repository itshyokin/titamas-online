class_name Harvest
extends RefCounted
## Chopping trees and smashing stones (data/harvest.json, Database → Harvesting).
## Something is harvestable when its prop name is listed under "props" (birch_tree: chop)
## or its node name (or a parent's, up to 4) contains "_chop" / "_smash" — so level
## objects from Blender work by name. Each kind lists the weapon types that work
## (axe / hammer), how many hits it takes, what it drops, the experience and how long it
## takes to grow back. A tree falls away from you and fades; a stone breaks into pieces.
## Hitting it with the wrong weapon bounces off as usual (with a hint now and then).

const FILE := "res://data/harvest.json"
const CHIPS := [preload("res://assets/audio/combat/thunk_wood_1.ogg"), preload("res://assets/audio/combat/thunk_wood_2.ogg")]
const CRACKS := [preload("res://assets/audio/combat/clang_stone_1.ogg"), preload("res://assets/audio/combat/clang_stone_2.ogg")]

static var _last_hint := 0


static func data() -> Dictionary:
	return PropLibrary.harvest_data()


## Whether a weapon type harvests anything (axe, hammer...).
static func is_harvest_tool(weapon_type: String) -> bool:
	for k: Dictionary in (data().get("kinds", {}) as Dictionary).values():
		if weapon_type in (k.get("weapon_types", []) as Array):
			return true
	return false


## "chop", "smash" or "" for a prop / object name.
static func kind_of_name(n: String) -> String:
	return PropLibrary.harvest_kind(n)


## The harvestable root a collider belongs to, and its kind: [Node3D, kind] or [].
static func find(collider: Node) -> Array:
	var walk := collider
	for i in 5:
		if walk == null or not walk is Node:
			break
		var n := String(walk.get_meta("prop_name", "")) if walk.has_meta("prop_name") else String(walk.name)
		var kind := kind_of_name(n)
		if kind != "" and walk is Node3D:
			# The prop's own root (the StaticBody sits inside it).
			var root := walk as Node3D
			if walk is StaticBody3D and walk.get_parent() is Node3D and walk.get_parent().has_meta("prop_name"):
				root = walk.get_parent()
			return [root, kind]
		walk = walk.get_parent()
	return []


## A swing landed on `collider` with weapon type `weapon_type`. True if it was harvested
## (chipped, felled or broken) — no bounce then.
static func hit(player: Node3D, collider: Node, weapon_type: String, at: Vector3, normal: Vector3) -> bool:
	var found := find(collider)
	if found.is_empty():
		return false
	var node: Node3D = found[0]
	var kind: String = found[1]
	if node.get_meta("harvest_down", false):
		return false
	var cfg: Dictionary = data().get("kinds", {}).get(kind, {})
	if not weapon_type in (cfg.get("weapon_types", []) as Array):
		if Time.get_ticks_msec() - _last_hint > 4000 and String(cfg.get("wrong_tool", "")) != "":
			_last_hint = Time.get_ticks_msec()
			HUD.notify(player, String(cfg.wrong_tool), Color(1, 0.85, 0.6))
		return false
	var hits := int(node.get_meta("harvest_hits", 0)) + 1
	node.set_meta("harvest_hits", hits)
	var root := Combat.world_root(player)
	if kind == "chop":
		Combat.play_sound(player, CHIPS.pick_random(), 0.0, randf_range(0.9, 1.05))
		Effects.sparks(root, at, Color(0.85, 0.75, 0.55), 0.8, normal + Vector3.UP * 0.4)  # wood chips
	else:
		Combat.play_sound(player, CRACKS.pick_random(), 0.0, randf_range(0.8, 0.95))
		Effects.strike_sparks(root, at, normal, 0.7, Color(0.85, 0.8, 0.7))
	_shake(node)
	if hits >= int(cfg.get("hits", 3)):
		node.set_meta("harvest_down", true)
		node.set_meta("harvest_hits", 0)
		if kind == "chop":
			_fell(player, node)
		else:
			_shatter(player, node)
		_reward(player, cfg)
		var respawn := float(cfg.get("respawn_seconds", 600.0))
		if respawn > 0.0:
			node.get_tree().create_timer(respawn).timeout.connect(_grow_back.bind(node))
	return true


static func _shake(node: Node3D) -> void:
	var base := node.position
	var t := node.create_tween()
	for i in 3:
		t.tween_property(node, "position", base + Vector3(randf_range(-0.04, 0.04), 0, randf_range(-0.04, 0.04)), 0.035)
	t.tween_property(node, "position", base, 0.04)


## The tree tips over away from the player, then sinks and fades.
static func _fell(player: Node3D, node: Node3D) -> void:
	_set_solid(node, false)
	node.set_meta("harvest_xform", node.transform)
	var away := node.global_position - player.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	var axis := Vector3.UP.cross(away).normalized()
	var start := node.global_transform
	var secs := float(data().get("fall_seconds", 1.6))
	var t := node.create_tween()
	t.tween_method(func(k: float) -> void:
		if is_instance_valid(node):
			node.global_transform = Transform3D(Basis(axis, k * PI * 0.48) * start.basis, start.origin), 0.0, 1.0, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		if is_instance_valid(node):
			Combat.play_sound(node, CHIPS[0], 4.0, 0.55)
			var cam := node.get_tree().get_first_node_in_group("player_camera")
			if cam and cam.global_position.distance_to(node.global_position) < 25.0:
				cam.call("shake", 0.25))
	t.tween_interval(0.6)
	t.tween_property(node, "position", node.position + Vector3.DOWN * 1.2, float(data().get("fade_seconds", 2.5)))
	t.tween_callback(func() -> void:
		if is_instance_valid(node):
			node.visible = false)


## The stone breaks into a few tumbling pieces that fade away.
static func _shatter(player: Node3D, node: Node3D) -> void:
	node.set_meta("harvest_xform", node.transform)
	var root := Combat.world_root(player)
	var center := node.global_position + Vector3.UP * 0.2
	var size := 0.25
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if not meshes.is_empty():
		var box := (meshes[0] as MeshInstance3D).get_aabb()
		size = clampf(box.get_longest_axis_size() * node.global_basis.get_scale().x * 0.3, 0.08, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.54, 0.52)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 7:
		var piece := RigidBody3D.new()
		piece.collision_layer = 0
		piece.collision_mask = 1
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		var s := size * randf_range(0.4, 0.8)
		b.size = Vector3.ONE * s
		shape.shape = b
		piece.add_child(shape)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(s, s * randf_range(0.6, 1.0), s * randf_range(0.7, 1.0))
		mi.mesh = bm
		mi.material_override = mat
		piece.add_child(mi)
		root.add_child(piece)
		piece.global_position = center + Vector3(randf_range(-0.2, 0.2), randf_range(0, 0.25), randf_range(-0.2, 0.2))
		piece.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		piece.linear_velocity = Vector3(randf_range(-2.5, 2.5), randf_range(2.0, 4.0), randf_range(-2.5, 2.5))
		piece.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		var t := piece.create_tween()
		t.tween_interval(2.0)
		t.tween_property(mat, "albedo_color:a", 0.0, 1.0)
		t.tween_callback(piece.queue_free)
	node.visible = false
	_set_solid(node, false)


## Grows back where it was (if its chunk is still loaded).
static func _grow_back(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	if node.has_meta("harvest_xform"):
		node.transform = node.get_meta("harvest_xform")
	node.visible = true
	_set_solid(node, true)
	node.set_meta("harvest_down", false)
	node.scale = node.scale * 0.01
	var full: Vector3 = (node.get_meta("harvest_xform") as Transform3D).basis.get_scale() if node.has_meta("harvest_xform") else Vector3.ONE
	node.create_tween().tween_property(node, "scale", full, 1.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func _set_solid(node: Node, on: bool) -> void:
	for b in node.find_children("*", "CollisionObject3D", true, false):
		(b as CollisionObject3D).collision_layer = 1 if on else 0
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 1 if on else 0


static func _reward(player: Node3D, cfg: Dictionary) -> void:
	var inv := player.get_node_or_null("Inventory")
	if inv:
		for d in cfg.get("drops", []):
			inv.call("add_item", String(d.get("item", "")), maxi(int(d.get("count", 1)), 1))
	var xp := int(cfg.get("xp", 0))
	var progress := player.get_node_or_null("Progress")
	if xp > 0 and progress:
		progress.call("add_xp", xp)
