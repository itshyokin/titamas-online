@tool
class_name Seat
extends StaticBody3D
## Something to sit on: a chair, a stool, a log or a bench (built from simple shapes, or
## your own mesh as a child with `kind` "custom"). Interact sits the player down (move to
## get up); followers sit on free seats near a campfire or in a safe area and do their
## resting activity (npcs.json rest_activity: relax, warm, read, eat, drink, talk).
## Seats face their -Z (the way a sitter looks); spots run along local X.
## Names no autoloads.

@export_enum("chair", "stool", "log", "bench", "custom") var kind := "log":
	set(value):
		kind = value
		_build()
## Height of the sitting surface (m). Custom seats set it; built ones have their own.
@export var seat_height := 0.42
## How many can sit (spots spread along X, `spacing` apart). Built kinds pick their own.
@export var spots := 0
@export var spacing := 0.65

## At runtime, drops onto the ground under it (once the chunk there has loaded).
@export var snap_to_ground := true

var _taken := {}  # spot index -> node
var _settled := false
var _prompt: Label3D


func _ready() -> void:
	add_to_group("seats")
	add_to_group("talkable")
	_build()
	if not Engine.is_editor_hint():
		GrassField.clearings.append([Vector2(global_position.x, global_position.z), 0.9])


func _count() -> int:
	if spots > 0:
		return spots
	return {"chair": 1, "stool": 1, "log": 3, "bench": 2, "custom": 1}.get(kind, 1)


func _height() -> float:
	return {"chair": 0.46, "stool": 0.45, "log": 0.42, "bench": 0.45}.get(kind, seat_height)


# --- Building ----------------------------------------------------------------------

func _build() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		if c.has_meta("built"):
			c.free()
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.28, 0.17)
	wood.roughness = 0.9
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.3, 0.22, 0.15)
	bark.roughness = 1.0
	var h := _height()
	var width := maxf(_count() - 1, 0) * spacing + 0.6
	match kind:
		"chair", "stool":
			_box(Vector3(0.48, 0.05, 0.46), Vector3(0, h - 0.025, 0), wood)
			for x in [-0.2, 0.2]:
				for z in [-0.19, 0.19]:
					_box(Vector3(0.05, h - 0.05, 0.05), Vector3(x, (h - 0.05) * 0.5, z), wood)
			if kind == "chair":
				_box(Vector3(0.48, 0.5, 0.05), Vector3(0, h + 0.25, 0.21), wood)
			_shape(Vector3(0.5, h + (0.5 if kind == "chair" else 0.0), 0.48), Vector3(0, (h + (0.5 if kind == "chair" else 0.0)) * 0.5, 0))
		"log":
			var cyl := CylinderMesh.new()
			cyl.top_radius = h * 0.5
			cyl.bottom_radius = h * 0.52
			cyl.height = width
			cyl.radial_segments = 10
			_mesh(cyl, Vector3(0, h * 0.5, 0), bark, Vector3(0, 0, PI * 0.5))
			var ring := CylinderMesh.new()
			ring.top_radius = h * 0.46
			ring.bottom_radius = h * 0.46
			ring.height = 0.01
			for side in [-1.0, 1.0]:
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(0.72, 0.56, 0.36)
				_mesh(ring, Vector3(side * width * 0.5, h * 0.5, 0), m, Vector3(0, 0, PI * 0.5))
			_shape(Vector3(width, h, h), Vector3(0, h * 0.5, 0))
		"bench":
			_box(Vector3(width, 0.06, 0.4), Vector3(0, h - 0.03, 0), wood)
			for x in [-width * 0.5 + 0.1, width * 0.5 - 0.1]:
				_box(Vector3(0.08, h - 0.06, 0.34), Vector3(x, (h - 0.06) * 0.5, 0), wood)
			_shape(Vector3(width, h, 0.4), Vector3(0, h * 0.5, 0))
	if not Engine.is_editor_hint():
		_prompt = Label3D.new()
		_prompt.set_meta("built", true)
		_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_prompt.pixel_size = 0.003
		_prompt.font_size = 36
		_prompt.outline_size = 10
		_prompt.no_depth_test = true
		_prompt.position = Vector3.UP * (h + 0.9)
		_prompt.text = "Sit"
		_prompt.visible = false
		add_child(_prompt)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var b := BoxMesh.new()
	b.size = size
	_mesh(b, pos, mat)


func _mesh(mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.set_meta("built", true)
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)


func _shape(size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.set_meta("built", true)
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	add_child(cs)


# --- Spots ---------------------------------------------------------------------------

## Where a sitter's hips go (world) for spot i.
func spot_position(i: int) -> Vector3:
	var x := (i - (_count() - 1) * 0.5) * spacing
	return global_transform * Vector3(x, _height(), 0.0)


## The way a sitter faces (world).
func facing() -> Vector3:
	var f := -global_basis.z
	f.y = 0.0
	return f.normalized()


func height() -> float:
	return _height()


## A free spot nearest `from` (-1 when full). `who` may already hold one.
func free_spot(from: Vector3, who: Node = null) -> int:
	var best := -1
	var best_d := INF
	for i in _count():
		var holder = _taken.get(i)
		if holder != null and is_instance_valid(holder) and holder != who:
			continue
		var d := spot_position(i).distance_to(from)
		if d < best_d:
			best_d = d
			best = i
	return best


func take(i: int, who: Node) -> void:
	release(who)
	_taken[i] = who


func release(who: Node) -> void:
	for k in _taken.keys():
		if _taken[k] == who or not is_instance_valid(_taken[k]):
			_taken.erase(k)


## Feet position for someone sitting in spot i: in front of the seat, on the ground.
func feet_position(i: int) -> Vector3:
	var p := spot_position(i) + facing() * 0.38
	p.y = global_position.y
	return p


# --- The player ------------------------------------------------------------------------

func can_talk() -> bool:
	if Engine.is_editor_hint() or not is_visible_in_tree():
		return false
	var player := get_tree().get_first_node_in_group("player")
	if player and player.get("seat") != null:
		return false
	var box = load("res://scripts/ui/dialogue_box.gd")
	return not bool(box.get("is_open")) and free_spot(global_position) >= 0


func talk_distance(from: Vector3) -> float:
	var best := INF
	for i in _count():
		var p := spot_position(i)
		best = minf(best, Vector2(p.x - from.x, p.z - from.z).length())
	return maxf(best - 0.4, 0.0)


func talk(player: Node3D) -> void:
	var i := free_spot(player.global_position, player)
	if i >= 0 and player.has_method("sit_on"):
		player.call("sit_on", self, i)


func _physics_process(_delta: float) -> void:
	if _settled or Engine.is_editor_hint() or not snap_to_ground:
		return
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 20.0, global_position + Vector3.DOWN * 60.0, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_settled = true
		global_position = hit.position


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _prompt == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	_prompt.visible = player != null and player.get("talk_focus") == self
