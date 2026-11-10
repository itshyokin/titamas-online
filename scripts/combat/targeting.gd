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

@export var tab_range := 35.0
## The target is dropped when further away than this.
@export var lose_range := 55.0
@export var enemy_mask := 4  # physics layer 3
## Lock-on breaks beyond this distance.
@export var lock_range := 40.0
## Swings turn to enemies this close even if they're behind you.
@export var snap_range := 2.5
## Keyboard and mouse: Tab picks the enemy you're looking at when nothing is targeted
## (1), or only clears the target (0; click enemies to target them).
@export var tab_selects := 1.0
## When the target dies, pick the next nearest enemy on screen after this many seconds.
@export var auto_next := 1.0  # 1 = yes
@export var auto_next_delay := 0.6
## Attacking with nothing targeted makes the enemy you swing at / shoot the target (1).
## 0: only clicking (or Tab / lock-on) picks targets.
@export var attack_selects := 0.0
## Clicking within this many pixels of an enemy on screen picks it.
@export var click_radius := 48.0

## Picking a target only reaches this far: set from the weapon in use (Weapon Types →
## Targeting range); tab_range when the weapon doesn't say.
var weapon_range := 0.0

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


## Target button: with nothing locked, picks the enemy you're looking at (nearest the
## centre of the screen, nearer ones preferred) and locks on; while locked, clears it.
func toggle_target() -> void:
	if is_locked():
		set_target(null)
		return
	var best := best_in_view()
	if best:
		set_target(best)
		set_locked(true)


## How far targets can be picked.
func pick_range() -> float:
	return weapon_range if weapon_range > 0.0 else tab_range


## Can be picked as a target: on screen and in front of the player (never behind them).
func selectable(n: Node3D) -> bool:
	var cam := get_viewport().get_camera_3d()
	var aim := Combat.aim_point(n)
	if cam == null:
		return true
	if not cam.is_position_in_frustum(aim) or cam.is_position_behind(aim):
		return false
	var to := aim - player.global_position
	to.y = 0.0
	var look := -cam.global_basis.z
	look.y = 0.0
	return to.length() < 1.0 or look.normalized().dot(to.normalized()) > 0.0


## The enemy closest to where the camera looks (within the weapon's range, on screen and
## in front of the player), weighing distance a little.
func best_in_view() -> Node3D:
	var cam := get_viewport().get_camera_3d()
	var best: Node3D = null
	var best_score := INF
	for n in Combat.enemies_near(player, player.global_position, pick_range()):
		if not selectable(n):
			continue
		var aim := Combat.aim_point(n)
		var dist := aim.distance_to(player.global_position)
		var score := dist
		if cam:
			var screen := cam.unproject_position(aim)
			var size := get_viewport().get_visible_rect().size
			var off := (screen - size * 0.5).length() / size.y  # 0 = centre, ~0.9 = corner
			score = off * 30.0 + dist * 0.4
		if score < best_score:
			best_score = score
			best = n
	return best


## The nearest living enemy on screen (within range), skipping `except`.
func nearest_on_screen(except: Node3D = null) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n in Combat.enemies_near(player, player.global_position, pick_range()):
		if n == except or not Combat.is_alive(n) or not selectable(n):
			continue
		var d := n.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


## Tab: targets the nearest enemy on screen; Tab again lets go.
func tab_target() -> void:
	if has_target():
		set_target(null)
		return
	var n := nearest_on_screen()
	if n:
		set_target(n)


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
	var candidates := Combat.enemies_near(player, player.global_position, pick_range()).filter(selectable)
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
	# A swing may snap to someone behind you, but they don't become the target.
	if best and select and (attack_selects > 0.5 or GameSettings.gamepad) and not has_target() and selectable(best):
		set_target(best)
	return best


## Selects the enemy under the mouse cursor, if any. Returns true if one was picked.
## Clicking an enemy (or near one on screen) makes it the target. Returns true if the
## click picked someone (the click is then only a selection, not an attack).
func click_select(screen_pos: Vector2) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var picked: Node3D = null
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 120.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | enemy_mask)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var node := hit.collider as Node
		while node and not node.is_in_group(Combat.GROUP):
			node = node.get_parent()
		if node and Combat.is_alive(node) and Combat.is_enemy_of(player, node):
			picked = node as Node3D
	if picked == null:
		# Near enough on screen: the line from its feet to its head passes close to the click.
		var best := click_radius
		for n in Combat.enemies_near(player, player.global_position, 120.0):
			var feet := n.global_position
			var head := Combat.aim_point(n) + Vector3.UP * 0.6
			if cam.is_position_behind(feet) or cam.is_position_behind(head):
				continue
			var a := cam.unproject_position(feet)
			var b := cam.unproject_position(head)
			var d := Geometry2D.get_closest_point_to_segment(screen_pos, a, b).distance_to(screen_pos)
			if d < best:
				best = d
				picked = n
	if picked == null or picked == target:
		return false
	set_target(picked)
	return true


## Tab is also the UI's "next focus" key: when a HUD button has focus (after a click) the
## GUI would eat it, so the keyboard Tab is taken here, before the GUI sees it.
func _input(event: InputEvent) -> void:
	if GameSettings.menu_open or not event is InputEventKey:
		return
	if event.is_action_pressed("target_next") and not (event as InputEventKey).shift_pressed and tab_selects >= 0.5:
		tab_target()
		get_viewport().gui_release_focus()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if GameSettings.menu_open:
		return
	if event.is_action_pressed("target_next"):
		if event is InputEventKey and (event as InputEventKey).shift_pressed:
			cycle_keeping_lock(-1)
		elif event is InputEventKey and tab_selects < 0.5:
			set_target(null)  # Tab only clears; click an enemy to target it
		elif event is InputEventKey:
			tab_target()
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
	# No longer an enemy (danger mode switched off): let go.
	if target and Combat.is_alive(target) and not Combat.is_enemy_of(player, target):
		set_target(null)
	if target and target.global_position.distance_to(player.global_position) > maxf(lose_range, pick_range() + 15.0):
		set_target(null)
	if locked and (not has_target() or target.global_position.distance_to(player.global_position) > maxf(lock_range, pick_range() + 5.0)):
		set_locked(false)
	_ring.visible = has_target()
	if _ring.visible:
		_ring.global_position = target.global_position + Vector3.UP * 0.05
	_marker.visible = is_locked()
	if _marker.visible:
		_marker.global_position = target.global_position + Vector3.UP * 1.0


func _on_target_died() -> void:
	# Leave the ring up for a moment so the kill registers, then move on to the next
	# nearest enemy on screen (keeping the lock if there was one).
	var dead := target
	var was_locked := locked
	await get_tree().create_timer(auto_next_delay).timeout
	if target != dead:
		return
	var next := nearest_on_screen(dead) if auto_next >= 0.5 else null
	set_target(next)
	if next and was_locked:
		set_locked(true)
