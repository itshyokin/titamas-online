class_name TrainingDummy
extends StaticBody3D
## A straw dummy on a post for trying out attacks and spells. It can't die: it heals
## back to full a few seconds after the last hit.

@export var display_name := "Training Dummy"
@export var level := 1
@export var max_health := 500.0
@export var reset_after := 4.0

var stats: Stats
var _since_hit := 0.0
var _body: Node3D
var _settled := false


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	add_to_group(Combat.GROUP)
	stats = Stats.new()
	stats.name = "Stats"
	stats.display_name = display_name
	stats.level = level
	stats.team = Stats.Team.ENEMIES
	stats.max_health = max_health
	stats.max_mana = 0.0
	stats.immortal = true
	add_child(stats)
	stats.damaged.connect(_on_damaged)
	_build()
	Combat.show_numbers(self)
	Nameplate.attach(self, 2.2)


func aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.3


func _physics_process(_delta: float) -> void:
	if _settled:
		return
	# Stand on the ground once it has loaded (terrain streams in).
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 60.0, global_position + Vector3.DOWN * 100.0, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position
		_settled = true


func _process(delta: float) -> void:
	_since_hit += delta
	if _since_hit > reset_after and stats.health < stats.max_health:
		stats.restore()


func _on_damaged(amount: float, _source: Node, _crit: bool) -> void:
	_since_hit = 0.0
	# Wobble.
	var t := create_tween()
	t.tween_property(_body, "rotation_degrees:x", -8.0 - minf(amount, 30.0) * 0.3, 0.06)
	t.tween_property(_body, "rotation_degrees:x", 4.0, 0.15)
	t.tween_property(_body, "rotation_degrees:x", 0.0, 0.2)


func _build() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.3, 0.18)
	wood.roughness = 0.9
	var straw := StandardMaterial3D.new()
	straw.albedo_color = Color(0.85, 0.72, 0.4)
	straw.roughness = 1.0
	var sack := StandardMaterial3D.new()
	sack.albedo_color = Color(0.7, 0.62, 0.48)
	sack.roughness = 1.0
	_body = Node3D.new()
	add_child(_body)
	_mesh(_body, _cyl(0.06, 1.0), Vector3(0, 0.5, 0), wood)
	_mesh(_body, _cyl(0.28, 0.75, 0.22), Vector3(0, 1.25, 0), straw)
	_mesh(_body, _box(Vector3(1.1, 0.08, 0.08)), Vector3(0, 1.45, 0), wood)
	var head := SphereMesh.new()
	head.radius = 0.17
	head.height = 0.34
	_mesh(_body, head, Vector3(0, 1.82, 0), sack)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 2.0
	shape.shape = cap
	shape.position = Vector3(0, 1.0, 0)
	add_child(shape)


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _cyl(radius: float, height: float, bottom := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius if bottom < 0.0 else bottom
	c.height = height
	c.radial_segments = 10
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
