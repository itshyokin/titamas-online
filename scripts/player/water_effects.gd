class_name WaterEffects
extends Node
## Ripples around the player while wading or swimming, and a splash when they land in
## water. Lives under Player.

## Seconds between ripples while moving through water (twice as long when still).
@export var ripple_interval := 0.32

@onready var player: PlayerController = get_parent()

var _timer := 0.0
var _was_in := false
var _fall_speed := 0.0


func _physics_process(delta: float) -> void:
	var feet := player.global_position
	var water = player._water_at(feet + Vector3.UP * 0.25)
	if water == null:
		_was_in = false
		_fall_speed = maxf(-player.velocity.y, 0.0)
		return
	var surface: float = water.surface_height()
	var at := Vector3(feet.x, surface + 0.03, feet.z)
	var root := Combat.world_root(player)
	if not _was_in:
		_was_in = true
		if _fall_speed > 2.5:
			Effects.splash(root, at, clampf(_fall_speed / 8.0, 0.6, 1.8))
		_timer = 0.0
		return
	var moving := Vector2(player.velocity.x, player.velocity.z).length() > 0.4
	_timer -= delta * (1.0 if moving else 0.5)
	if _timer <= 0.0 and surface - feet.y < 2.2:
		_timer = ripple_interval
		Effects.ripple(root, at, 0.9 if moving else 0.6)
