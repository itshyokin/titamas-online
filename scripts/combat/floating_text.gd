class_name FloatingText
extends Label3D
## A number or word that pops up over a combatant.
##
## Numbers (damage, heals: text starting with a digit, + or -) burst out from the hit
## and arc away to the side, alternating left and right of the camera and fanning out
## when several land close together, then fall and fade (like Remnant 2's damage
## numbers): a flurry of hits spreads out instead of piling up in one spot.
## Words ("Effective!", "Resisted", "Parried"…) rise straight up above the head in their
## own lane, each new one stacked over the last.

const LIFETIME := 1.1
const WORD_LIFETIME := 1.3
const GRAVITY := 6.5

var _velocity := Vector3.ZERO
var _life := 0.0
var _word := false
var _lifetime := LIFETIME
var _size := 1.0
var _owner: Node3D


static func _is_number(value: String) -> bool:
	if value.is_empty():
		return false
	var c := value.substr(0, 1)
	return c.is_valid_int() or c == "+" or c == "-"


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
	t._size = size
	t._owner = over
	t._word = not _is_number(value)
	Combat.world_root(over).add_child(t)
	var cam := over.get_viewport().get_camera_3d()
	var right := cam.global_basis.x if cam else Vector3.RIGHT
	right.y = 0.0
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var head := Combat.aim_point(over)
	var now := Time.get_ticks_msec()
	if t._word:
		# Stacked over the head: each word still showing pushes the new one up a step.
		t._lifetime = WORD_LIFETIME
		var lane := 0
		var words: Array = over.get_meta("ft_words", [])
		var alive: Array = []
		for w in words:
			if is_instance_valid(w):
				alive.append(w)
		lane = alive.size()
		alive.append(t)
		over.set_meta("ft_words", alive)
		t.global_position = head + Vector3.UP * (1.3 + 0.32 * lane)  # over the nameplate
		t._velocity = Vector3.UP * 0.45
		return
	# Numbers: alternate sides, and fan out further the more land in quick succession.
	var burst := int(over.get_meta("ft_burst", 0))
	if now - int(over.get_meta("ft_burst_at", 0)) > 600:
		burst = 0
	over.set_meta("ft_burst", burst + 1)
	over.set_meta("ft_burst_at", now)
	var side := 1.0 if burst % 2 == 0 else -1.0
	var spread := 1.0 + minf(burst, 6) * 0.22
	# Each one in a burst takes a different arc height too, so they don't land together.
	var up := (2.3 + float(burst / 2 % 3) * 0.6 + randf_range(-0.15, 0.15)) * (1.1 if size > 1.1 else 1.0)
	t.global_position = head + Vector3.UP * 0.35 + right * side * 0.15
	t._velocity = right * side * randf_range(1.0, 1.5) * spread + Vector3.UP * up


func _process(delta: float) -> void:
	_life += delta
	global_position += _velocity * delta
	if _word:
		_velocity.y = maxf(_velocity.y - 0.6 * delta, 0.1)
	else:
		# An arc: up and out, then falling as it slows sideways.
		_velocity.y -= GRAVITY * delta
		_velocity.x *= 1.0 - 1.6 * delta
		_velocity.z *= 1.0 - 1.6 * delta
	var k := _life / _lifetime
	modulate.a = 1.0 - smoothstep(0.55, 1.0, k)
	outline_modulate.a = modulate.a * 0.85
	# A quick pop as it appears (bigger for crits), settling to its size.
	var pop := 0.55 if _size > 1.1 else 0.35
	scale = Vector3.ONE * (1.0 + pop * (1.0 - smoothstep(0.0, 0.14, _life)))
	if _life >= _lifetime:
		queue_free()
