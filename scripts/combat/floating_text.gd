class_name FloatingText
extends Label3D
## A number or word that pops up over a combatant, drifts up and fades.

var _velocity := Vector3.ZERO
var _life := 0.0
const LIFETIME := 1.1


static func spawn(over: Node3D, value: String, color: Color, size := 1.0) -> void:
	if over == null or not over.is_inside_tree():
		return
	var t := FloatingText.new()
	t.text = value
	t.modulate = color
	t.outline_modulate = Color(0, 0, 0, 0.85)
	t.font_size = int(64 * size)
	t.outline_size = 12
	t.pixel_size = 0.004
	t.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	t.no_depth_test = true
	t.fixed_size = false
	t.render_priority = 10
	Combat.world_root(over).add_child(t)
	t.global_position = Combat.aim_point(over) + Vector3(randf_range(-0.3, 0.3), 0.7, randf_range(-0.3, 0.3))
	t._velocity = Vector3(randf_range(-0.3, 0.3), 1.6, randf_range(-0.3, 0.3))


func _process(delta: float) -> void:
	_life += delta
	global_position += _velocity * delta
	_velocity.y = maxf(_velocity.y - 2.5 * delta, 0.2)
	var k := _life / LIFETIME
	modulate.a = 1.0 - smoothstep(0.6, 1.0, k)
	outline_modulate.a = modulate.a * 0.85
	scale = Vector3.ONE * (1.0 + 0.4 * (1.0 - smoothstep(0.0, 0.12, _life)))
	if _life >= LIFETIME:
		queue_free()
