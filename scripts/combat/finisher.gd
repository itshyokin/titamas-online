class_name Finisher
extends Node3D
## A killing blow played as a finisher (Skyrim's kill-cam): time slows, a camera swings
## round the player and the falling enemy, then play goes back to the normal camera.
## PlayerCombat calls Finisher.play() now and then on a kill (player.json combat
## finisher_chance, finisher_seconds; heavy blows are likelier).

static var playing := false

var _cam: Camera3D
var _old: Camera3D
var _player: Node3D
var _enemy: Node3D
var _t := 0.0
var _length := 1.4
var _side := 1.0


static func play(player: Node3D, enemy: Node3D, seconds := 1.4) -> void:
	if playing or player == null or enemy == null:
		return
	var f := Finisher.new()
	f._player = player
	f._enemy = enemy
	f._length = seconds
	f._side = 1.0 if randf() < 0.5 else -1.0
	player.get_tree().root.add_child(f)


func _ready() -> void:
	playing = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_old = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	if _old:
		_cam.global_transform = _old.global_transform
	_cam.current = true
	TimeFX.slow_motion(_player, _length * 0.6)
	_place(0.0)


func _process(delta: float) -> void:
	# Real seconds, whatever the time scale.
	_t += delta / maxf(Engine.time_scale, 0.05)
	if _t >= _length or not is_instance_valid(_player):
		_end()
		return
	_place(_t / _length)


## Swings from beside the player round to the far side of the enemy, low and close.
func _place(k: float) -> void:
	var p := _player.global_position + Vector3.UP * 1.2
	var e := (_enemy.global_position if is_instance_valid(_enemy) else p) + Vector3.UP * 1.0
	var mid := (p + e) * 0.5
	var across := e - p
	across.y = 0.0
	if across.length() < 0.1:
		across = -_player.global_basis.z
	across = across.normalized()
	var side := across.cross(Vector3.UP) * _side
	var angle := lerpf(-0.6, 0.9, smoothstep(0.0, 1.0, k))
	var offset := (side * cos(angle) + across * sin(angle)) * 3.2 + Vector3.UP * lerpf(0.3, 0.9, k)
	var goal := mid + offset
	if k <= 0.0:
		_cam.global_position = goal
	else:
		_cam.global_position = _cam.global_position.lerp(goal, 0.25)
	_cam.look_at(mid, Vector3.UP)


func _end() -> void:
	playing = false
	if _old and is_instance_valid(_old):
		_old.current = true
	queue_free()
