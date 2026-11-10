class_name AbilityFX
extends RefCounted
## Sprites for spells and skills: pictures (built-in ones in assets/effects/builtin, your
## own in assets/effects/custom) shown when an ability is used, on top of its usual
## effects. Set per ability in abilities.json "fx" (Database → Abilities → Effect sprites):
##   cast        on the caster: while a spell with a cast time is being cast, or a flash
##               as an instant one goes off
##   projectile  flying with the bolt, facing the camera (replaces the glowing ball)
##   impact      where it lands: on whoever is hit / healed / buffed
##   ground      flat on the ground under them (a decal: rune circles, scorch marks)
## Each slot: {sprite (res:// png), size (m), seconds, frames (a strip of N frames side by
## side, 1 = a still picture), look "glow" (tinted with the ability's colour and added to
## the picture behind, so it shines) or "drawn" (exactly as painted)}.
## This script names no autoloads, so test scripts can name it.

const SLOTS := ["cast", "projectile", "impact", "ground"]

static var _textures := {}


## The ability's settings for a slot ({} when it has no sprite there).
static func slot(ab: Ability, slot_name: String) -> Dictionary:
	if ab == null or not ab.has_meta("data"):
		return {}
	var fx = (ab.get_meta("data") as Dictionary).get("fx", {})
	var cfg = (fx as Dictionary).get(slot_name, {}) if fx is Dictionary else {}
	if not cfg is Dictionary or String((cfg as Dictionary).get("sprite", "")).is_empty():
		return {}
	return cfg


static func has(ab: Ability, slot_name: String) -> bool:
	return not slot(ab, slot_name).is_empty()


## The picture at `path` (kept after the first use). A PNG the editor hasn't imported yet
## (just dropped into the folder) is read straight from the file.
static func texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(path)) == OK:
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		push_warning("AbilityFX: no picture at '%s'" % path)
	_textures[path] = tex
	return tex


## The colour sprites of this ability are tinted with (the "glow" look).
static func color_of(ab: Ability, slot_name: String) -> Color:
	return ab.projectile_color if slot_name == "projectile" or ab.delivery == Ability.Delivery.PROJECTILE else ab.color


## A one-shot sprite at a point, facing the camera: pops, plays its frames, fades.
static func burst(ab: Ability, slot_name: String, parent: Node, at: Vector3) -> FxSprite:
	var cfg := slot(ab, slot_name)
	if cfg.is_empty() or parent == null or not parent.is_inside_tree():
		return null
	var s := FxSprite.make(cfg, color_of(ab, slot_name), false, false)
	if s == null:
		return null
	parent.add_child(s)
	s.global_position = at
	return s


## A sprite that stays on `node` (a projectile, a caster mid-cast) and loops its frames
## until freed (it goes with the node; free it yourself to stop early).
static func attach(ab: Ability, slot_name: String, node: Node3D, offset := Vector3.ZERO) -> FxSprite:
	var cfg := slot(ab, slot_name)
	if cfg.is_empty() or node == null:
		return null
	var s := FxSprite.make(cfg, color_of(ab, slot_name), true, false)
	if s == null:
		return null
	node.add_child(s)
	s.position = offset
	return s


## A sprite laid flat on the ground under `at` (found with a ray down; follows the slope).
static func ground(ab: Ability, parent: Node, at: Vector3) -> FxSprite:
	var cfg := slot(ab, "ground")
	if cfg.is_empty() or parent == null or not parent.is_inside_tree() or not parent is Node3D:
		return null
	var s := FxSprite.make(cfg, color_of(ab, "ground"), false, true)
	if s == null:
		return null
	parent.add_child(s)
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 6.0, 1)
	var hit := (parent as Node3D).get_world_3d().direct_space_state.intersect_ray(q)
	var spot: Vector3 = hit.position if not hit.is_empty() else at
	var normal: Vector3 = hit.normal if not hit.is_empty() else Vector3.UP
	s.global_position = spot + normal * 0.04
	if absf(normal.dot(Vector3.UP)) < 0.999:
		s.global_basis = Basis(Quaternion(Vector3.UP, normal)) * s.global_basis
	return s


## The ability went off / landed on `who` (hit, healed or buffed): the impact sprite at
## their chest (or `at`) and the ground sprite under them.
static func landed(ab: Ability, who: Node3D, at = null) -> void:
	if ab == null or who == null or not is_instance_valid(who) or not who.is_inside_tree():
		return
	if not has(ab, "impact") and not has(ab, "ground"):
		return
	var root := _root(who)
	var point: Vector3 = at if at is Vector3 else (who.call("aim_point") if who.has_method("aim_point") else who.global_position + Vector3.UP * 1.2)
	burst(ab, "impact", root, point)
	ground(ab, root, who.global_position)


## An instant ability going off: the cast sprite as a flash on the caster.
static func cast_flash(ab: Ability, caster: Node3D) -> void:
	if ab == null or caster == null or not caster.is_inside_tree() or ab.cast_time > 0.0:
		return
	burst(ab, "cast", _root(caster), caster.global_position + Vector3.UP * 1.3)


static func _root(from: Node) -> Node:
	var tree := from.get_tree()
	return tree.current_scene if tree.current_scene else tree.root
