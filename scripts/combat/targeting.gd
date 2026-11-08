class_name Targeting
extends Node
## The player's current target. Target (Tab / RB) picks the enemy nearest the centre of
## the screen and locks on; pressing it again clears the target. Cycle targets
## (Shift+Tab / LB) walks through the enemies in view, keeping the lock. Clicking an enemy
## selects it. Attacks pick the nearest enemy in front when nothing is selected, and swings
## snap to any enemy within `snap_range`, whichever way you face.
## Lock-on (Fable style): the camera keeps the target in view and the character faces
## it while moving, so moving sideways circles it. A ring marks the target; brackets
## round its body show the lock.

signal target_changed(target: Node3D)
signal lock_changed(locked: bool)

@export var tab_range := 40.0
## The target is dropped when further away than this.
@export var lose_range := 55.0
@export var enemy_mask := 4  # physics layer 3
## Lock-on breaks beyond this distance.
@export var lock_range := 30.0
## Swings turn to enemies this close even if they're behind you.
@export var snap_range := 2.5

@onready var player: PlayerController = get_parent()

var target: Node3D = null
var locked := false
var _ring: MeshInstance3D
var _marker: MeshInstance3D
var _cycle: Array[Node3D] = []


func _ready() -> void:
	_ring = Effects.target_ring()
	_ring.visible = false
	_ring.top_level = true
	add_child(_ring)
	_marker = Effects.lock_marker()
	_marker.visible = false
	_marker.top_level = true
	add_child(_marker)


func set_target(node: Node3D) -> void:
	if node == target:
		return
	if target and is_instance_valid(target):
		var old_stats := Combat.stats_of(target)
		if old_stats and old_stats.died.is_connected(_on_target_died):
			old_stats.died.disconnect(_on_target_died)
	_mark(target, false)
	target = node
	_mark(target, true)
	if target == null:
		set_locked(false)
	else:
		player.lock_target = target if locked else null
	if target:
		var s := Combat.stats_of(target)
		if s and not s.died.is_connected(_on_target_died):
			s.died.connect(_on_target_died)
	target_changed.emit(target)


func _mark(node: Node3D, on: bool) -> void:
	if node and is_instance_valid(node):
		var plate := node.get_node_or_null("Nameplate") as Nameplate
		if plate:
			plate.targeted = on


func is_locked() -> bool:
	return locked and has_target()


func set_locked(value: bool) -> void:
	if value and not has_target():
		value = false
	if value == locked:
		return
	locked = value
	player.lock_facing = locked
	player.lock_target = target if locked else null
	lock_changed.emit(locked)


## Lock-on button: locks onto the target (picking the nearest enemy in front if there's
## none), or releases the lock.
func toggle_lock() -> void:
	if locked:
		set_locked(false)
		return
	if not has_target():
		pick_for_attack(lock_range)
		if not has_target():
			cycle()
	set_locked(has_target())


## Target button: picks the enemy nearest the centre of the screen and locks on, or (with
## a target already) clears it.
func toggle_target() -> void:
	if has_target():
		set_target(null)
		return
	cycle(1)
	set_locked(has_target())


## Next enemy in view; stays locked if it was.
func cycle_keeping_lock(step: int) -> void:
	var was_locked := locked
	cycle(step)
	if was_locked or not has_target():
		set_locked(has_target())
	else:
		set_locked(true)


func has_target() -> bool:
	return target != null and is_instance_valid(target) and Combat.is_alive(target)


## Picks the next (or previous) enemy in view. Repeated presses walk through them in order.
func cycle(step := 1) -> void:
	var cam := get_viewport().get_camera_3d()
	var candidates := Combat.enemies_near(player, player.global_position, tab_range)
	if candidates.is_empty():
		set_target(null)
		return
	var cam_fwd := -cam.global_basis.z if cam else -player.model.global_basis.z
	var score := func(n: Node3D) -> float:
		var to := n.global_position - player.global_position
		var angle := cam_fwd.angle_to(to.normalized()) if to.length() > 0.01 else 0.0
		return angle * 10.0 + to.length() * 0.05
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool: return score.call(a) < score.call(b))
	# Keep the order stable between presses so Tab visits everyone.
	_cycle = _cycle.filter(func(n: Node3D) -> bool: return candidates.has(n))
	for c in candidates:
		if not _cycle.has(c):
			_cycle.append(c)
	if not has_target() or not _cycle.has(target):
		set_target(_cycle[0])
	else:
		set_target(_cycle[posmod(_cycle.find(target) + step, _cycle.size())])


## The enemy an attack should go for: the target if close enough, else the nearest
## enemy roughly in front (which then becomes the target).
func pick_for_attack(max_distance: float, select := true) -> Node3D:
	if has_target() and target.global_position.distance_to(player.global_position) <= max_distance:
		return target
	var fwd := -player.model.global_basis.z
	var best: Node3D = null
	var best_score := INF
	for n in Combat.enemies_near(player, player.global_position, max_distance):
		var to := n.global_position - player.global_position
		to.y = 0.0
		var facing := fwd.dot(to.normalized()) if to.length() > 0.01 else 1.0
		if facing < -0.2 and to.length() > snap_range:
			continue
		var s := to.length() * (2.0 - facing)
		if s < best_score:
			best_score = s
			best = n
	if best and select and not has_target():
		set_target(best)
	return best


## Selects the enemy under the mouse cursor, if any. Returns true if one was picked.
func click_select(screen_pos: Vector2) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 120.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | enemy_mask)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var node := hit.collider as Node
	while node and not node.is_in_group(Combat.GROUP):
		node = node.get_parent()
	if node and Combat.is_alive(node) and Combat.is_enemy_of(player, node):
		set_target(node as Node3D)
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if GameSettings.menu_open:
		return
	if event.is_action_pressed("target_next"):
		if event is InputEventKey and (event as InputEventKey).shift_pressed:
			cycle_keeping_lock(-1)
		else:
			toggle_target()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("target_prev"):
		cycle_keeping_lock(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("lock_on"):
		toggle_lock()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("target_clear") and (target != null or locked):
		set_target(null)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if target and not is_instance_valid(target):
		set_target(null)
	if target and target.global_position.distance_to(player.global_position) > lose_range:
		set_target(null)
	if locked and (not has_target() or target.global_position.distance_to(player.global_position) > lock_range):
		set_locked(false)
	_ring.visible = has_target()
	if _ring.visible:
		_ring.global_position = target.global_position + Vector3.UP * 0.05
	_marker.visible = is_locked()
	if _marker.visible:
		_marker.global_position = target.global_position + Vector3.UP * 1.0


func _on_target_died() -> void:
	# Leave the ring up for a moment so the kill registers, then clear.
	var dead := target
	await get_tree().create_timer(1.0).timeout
	if target == dead:
		set_target(null)
