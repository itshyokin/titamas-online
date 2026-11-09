class_name WorldStrike
extends RefCounted
## A melee swing that meets the world instead of an enemy (a rock, a wall, a tree): the
## blade bounces off and the player is knocked back a little. Stone and metal throw
## sparks and clang; wood thunks and keeps a gash for a while.
## Settings: data/player.json "combat" (world_bounce, world_knockback, world_check,
## gash_time) — Database → Player → Combat.

const CLANGS := [preload("res://assets/audio/combat/clang_stone_1.ogg"), preload("res://assets/audio/combat/clang_stone_2.ogg")]
const THUNKS := [preload("res://assets/audio/combat/thunk_wood_1.ogg"), preload("res://assets/audio/combat/thunk_wood_2.ogg")]
const MAX_GASHES := 12

static var _gash_tex: Texture2D
static var _gashes: Array[Decal] = []


## Looks for something solid in the swing's path. Returns {position, normal, surface}
## or {} (nothing there, or only gentle ground underfoot).
static func find(player: Node3D, forward: Vector3, reach: float) -> Dictionary:
	var space := player.get_world_3d().direct_space_state
	var from := player.global_position + Vector3.UP * 1.15
	var flat := Vector3(forward.x, 0.0, forward.z).normalized()
	if flat == Vector3.ZERO:
		return {}
	for angle: float in [0.0, -0.35, 0.35]:
		for height: float in [0.0, -0.35]:
			var dir := flat.rotated(Vector3.UP, angle)
			var start := from + Vector3.UP * height
			var q := PhysicsRayQueryParameters3D.create(start, start + dir * reach, 1)
			q.exclude = [player.get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var normal: Vector3 = hit.normal
			if normal.y > 0.6:
				continue  # ground you could walk on: the swing passes over it
			return {"position": hit.position, "normal": normal, "surface": surface_of(hit.collider as Node, normal)}
	return {}


static func surface_of(node: Node, normal: Vector3) -> String:
	var walk := node
	for i in 4:
		if walk == null:
			break
		if walk.has_meta("surface"):
			return String(walk.get_meta("surface"))
		if walk.is_in_group("ladder"):
			return "wood"
		walk = walk.get_parent()
	return "stone"  # rock faces, walls, steep terrain


## The bounce: sound, sparks or a gash, the player knocked back and the camera jolted.
static func strike(player: Node3D, hit: Dictionary, settings: Dictionary) -> void:
	var at: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	var surface := String(hit.get("surface", "stone"))
	var root := Combat.world_root(player)
	match surface:
		"wood":
			Combat.play_sound(player, THUNKS.pick_random(), -2.0, randf_range(0.92, 1.08))
			_gash(root, at, normal, float(settings.get("gash_time", 25.0)))
			Effects.sparks(root, at, Color(0.55, 0.4, 0.25), 0.6, normal + Vector3.UP * 0.3)  # splinters
		"grass", "dirt":
			Combat.play_sound(player, THUNKS.pick_random(), -8.0, 0.8)
		_:
			Combat.play_sound(player, CLANGS.pick_random(), -1.0, randf_range(0.9, 1.1))
			Effects.strike_sparks(root, at, normal, float(settings.get("spark_size", 1.0)))
	var back := Vector3(normal.x, 0.0, normal.z)
	if back.length() < 0.1:
		back = player.global_position - at
		back.y = 0.0
	if player.has_method("apply_knockback"):
		player.call("apply_knockback", back.normalized() * float(settings.get("world_knockback", 3.0)))
	var cam := player.get_tree().get_first_node_in_group("player_camera")
	if cam:
		cam.call("shake", 0.12)


## A dark cut in the wood that fades after `seconds`.
static func _gash(root: Node, at: Vector3, normal: Vector3, seconds: float) -> void:
	var decal := Decal.new()
	decal.texture_albedo = _texture()
	decal.size = Vector3(0.42, 0.25, 0.16)
	decal.cull_mask = 1
	decal.upper_fade = 0.1
	decal.lower_fade = 0.1
	var up := normal.normalized()
	var side := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var z := side.cross(up).normalized()
	decal.top_level = true
	root.add_child(decal)
	# Decals project along their -Y: point it into the wood; the cut runs slanted.
	decal.global_transform = Transform3D(Basis(up.cross(z).normalized(), up, z).rotated(up, randf_range(-0.6, 0.6) + PI * 0.5), at)
	_gashes.append(decal)
	while _gashes.size() > MAX_GASHES:
		var old: Decal = _gashes.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var tween := decal.create_tween()
	tween.tween_interval(maxf(seconds - 2.0, 0.0))
	tween.tween_property(decal, "modulate:a", 0.0, 2.0)
	tween.tween_callback(decal.queue_free)


static func _texture() -> Texture2D:
	if _gash_tex:
		return _gash_tex
	var w := 64
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := (y + 0.5) / h * 2.0 - 1.0
			# A lens-shaped cut, darkest in the middle, with pale splintered lips.
			var half := 0.42 * (1.0 - u * u)
			var d := absf(v) / maxf(half, 0.001)
			var c := Color(0, 0, 0, 0)
			if d < 0.55:
				c = Color(0.12, 0.07, 0.04, 0.95)
			elif d < 1.0:
				var lip := (d - 0.55) / 0.45
				c = Color(0.62, 0.48, 0.32, 0.85 * (1.0 - lip))
			img.set_pixel(x, y, c)
	_gash_tex = ImageTexture.create_from_image(img)
	return _gash_tex
