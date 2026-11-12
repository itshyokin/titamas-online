class_name ItemPickup
extends Node3D
## An item thrown out of the backpack: its icon spins and bobs on the ground. The player
## takes it back by walking over it, once `pickup_delay` has passed (so it doesn't jump
## straight back into the bag). It vanishes after `despawn_seconds`, or when the player is
## `despawn_distance` away (left the area). Settings: player.json "drops" (Database → Player).
## Names no autoloads at parse time (reads Database through the tree).

static var _all: Array[ItemPickup] = []

var item_id := ""
var count := 1
var _age := 0.0
var _sprite: Sprite3D
var _base_y := 0.0
var _cfg := {}
var _flight := 0.0   # toss arc time left
var _from := Vector3.ZERO
var _to := Vector3.ZERO
const FLIGHT := 0.45


## Drops `count` of `id` a little in front of `who` (tossed in an arc onto the ground).
static func drop(who: Node3D, id: String, amount: int) -> ItemPickup:
	if who == null or not who.is_inside_tree() or amount <= 0:
		return null
	var p := ItemPickup.new()
	p.item_id = id
	p.count = amount
	var level := who.get_tree().current_scene if who.get_tree().current_scene else who.get_parent()
	level.add_child(p)
	var fwd := -who.global_basis.z
	var model = who.get("model")
	if model is Node3D:
		fwd = -(model as Node3D).global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	p._from = who.global_position + Vector3.UP * 1.1
	p._to = _ground(who, who.global_position + fwd * 1.3 + fwd.cross(Vector3.UP) * randf_range(-0.3, 0.3))
	p.global_position = p._from
	p._flight = FLIGHT
	return p


static func _ground(who: Node3D, at: Vector3) -> Vector3:
	var space := who.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 6.0, 1)
	var hit := space.intersect_ray(q)
	return (hit.position as Vector3) if not hit.is_empty() else at


func _ready() -> void:
	_all.append(self)
	var db := get_tree().root.get_node_or_null("Database")
	var player_data = db.get("player") if db else {}
	_cfg = (player_data as Dictionary).get("drops", {}) if player_data is Dictionary else {}
	var d: Dictionary = db.call("item", item_id) if db else {}
	_sprite = Sprite3D.new()
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.double_sided = true
	_sprite.shaded = false
	_sprite.texture = _icon_texture(d)
	var px := maxf(float(_sprite.texture.get_width()) if _sprite.texture else 48.0, 1.0)
	_sprite.pixel_size = float(_cfg.get("size", 0.45)) / px
	add_child(_sprite)
	# A soft glow under it so it can be found in grass.
	var light := OmniLight3D.new()
	light.light_color = ItemIcon.rarity_color(d) if not d.is_empty() else Color.WHITE
	light.light_energy = 0.5
	light.omni_range = 1.2
	light.position.y = 0.4
	add_child(light)


func _exit_tree() -> void:
	_all.erase(self)


## The item's icon as a texture: builtin/custom pictures directly, drawn glyphs through a
## small SubViewport holding an ItemIcon.
func _icon_texture(d: Dictionary) -> Texture2D:
	var pic := ItemIcon.picture(String(d.get("icon", "")), String(d.get("icon_tint", "")))
	if pic:
		return pic
	var vp := SubViewport.new()
	vp.size = Vector2i(48, 48)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var icon := ItemIcon.new()
	icon.size = Vector2(48, 48)
	icon.raw = true
	icon.show_item(d)
	vp.add_child(icon)
	add_child(vp)
	return vp.get_texture()


func _process(delta: float) -> void:
	_age += delta
	if _flight > 0.0:
		_flight = maxf(_flight - delta, 0.0)
		var t := 1.0 - _flight / FLIGHT
		global_position = _from.lerp(_to, t) + Vector3.UP * sin(t * PI) * 0.6
		_base_y = _to.y
	else:
		global_position.y = _base_y + 0.45 + sin(_age * 2.4) * 0.08
	_sprite.rotation.y += delta * float(_cfg.get("spin", 2.2))
	if _age > float(_cfg.get("despawn_seconds", 300.0)):
		queue_free()
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var dist := player.global_position.distance_to(global_position)
	if dist > float(_cfg.get("despawn_distance", 150.0)):
		queue_free()
		return
	if _flight <= 0.0 and _age >= float(_cfg.get("pickup_delay", 1.5)) and dist < float(_cfg.get("pickup_radius", 1.1)):
		_take(player)


func _take(player: Node3D) -> void:
	var inv := player.get_tree().get_first_node_in_group("player_inventory")
	if inv == null:
		return
	var left := int(inv.call("add_item", item_id, count))
	if left == count:
		return  # bag full: stays where it is
	count = left
	var snd := String(_cfg.get("pickup_sound", ""))
	if snd != "" and ResourceLoader.exists(snd):
		var p := AudioStreamPlayer3D.new()
		p.stream = load(snd)
		p.bus = "SFX"
		get_parent().add_child(p)
		p.global_position = global_position
		p.play()
		p.finished.connect(p.queue_free)
	if count <= 0:
		queue_free()


## Every dropped item in the world (tests, saving later).
static func all() -> Array[ItemPickup]:
	return _all
