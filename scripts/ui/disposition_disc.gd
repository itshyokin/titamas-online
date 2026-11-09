class_name DispositionDisc
extends MeshInstance3D
## A flat ring under a character's feet saying how they feel about the player:
## red hostile, grey neutral, green friendly (colours, size and opacity in player.json
## "discs", Database → Player → Discs). Hostile = Combat.is_enemy_of the player (enemies,
## angry NPCs, NPCs in danger mode); otherwise an NPC's `disposition` (npcs.json; default
## by kind: villagers neutral, others friendly). Hidden when dead.

var _owner: Node3D
var _mat: StandardMaterial3D
var _check := 0.0


static func attach(to: Node3D) -> DispositionDisc:
	var d := DispositionDisc.new()
	d.name = "DispositionDisc"
	d._owner = to
	to.add_child(d)
	return d


func _ready() -> void:
	var cfg := _cfg()
	var size := float(cfg.get("size", 1.0))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42 * size
	ring.outer_radius = 0.5 * size
	ring.rings = 32
	ring.ring_segments = 4
	mesh = ring
	scale = Vector3(1.0, 0.04, 1.0)
	position = Vector3.UP * 0.03
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.no_depth_test = false
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_update()


func _cfg() -> Dictionary:
	var c = Database.player.get("discs", {})
	return c if c is Dictionary else {}


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 0.4
		_update()


func _update() -> void:
	var cfg := _cfg()
	var st := Combat.stats_of(_owner)
	if not bool(cfg.get("enabled", true)) or (st and st.is_dead()) or not _owner.is_visible_in_tree():
		visible = false
		return
	visible = true
	var mood := disposition()
	var c := Color.html(String(cfg.get(mood, {"hostile": "#d8332a", "neutral": "#9a9a9a", "friendly": "#3fbf4a"}[mood])))
	c.a = float(cfg.get("opacity", 0.75))
	_mat.albedo_color = c


## "hostile", "neutral" or "friendly" towards the player.
func disposition() -> String:
	var player := get_tree().get_first_node_in_group("player")
	if player and Combat.is_enemy_of(player, _owner):
		return "hostile"
	var d := String(_owner.get("data").get("disposition", "")) if _owner.get("data") is Dictionary else ""
	if d != "":
		return d
	if _owner.is_in_group("npcs"):
		var kind := String(_owner.get("data").get("kind", "")) if _owner.get("data") is Dictionary else ""
		return "neutral" if kind == "villager" or kind == "" else "friendly"
	return "neutral"
