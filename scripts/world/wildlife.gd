class_name Wildlife
extends Node3D
## Ambient creatures around the player (made by AtmosphereManager): squirrels near trees
## that scamper off when you come close, flocks of birds circling overhead, fireflies over
## the grass at night and mosquitos by the water. Swarms set to "only where placed" (flies)
## never appear by themselves: put a SwarmSpot node where they belong (a body left lying
## for the story, a rubbish heap, a stagnant pool).
## data/wildlife.json (Database → Wildlife): each type has a kind (critter / birds /
## swarm), how many at once, when (day / night / dusk / any), near what (trees / grass /
## water / corpses / any), colour and size. Spawns out of sight range-wise (beyond
## min_distance), removes them past despawn_radius or when their time of day is over.
## All built in code (no models needed).

const FILE := "res://data/wildlife.json"

var _data := {}
var _file_time := -1
var _check := 0.0
var _live := {}  # type id -> Array[Node3D]


func _ready() -> void:
	add_to_group("wildlife")


func _load() -> void:
	_file_time = DataFiles.modified_time(FILE)
	var d = DataFiles.read(FILE)
	_data = d if d is Dictionary else {}


func _process(delta: float) -> void:
	if DataFiles.modified_time(FILE) != _file_time:
		_load()
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not bool(_data.get("enabled", true)) or GameSettings.get("wildlife") == false:
		_clear_all()
		return
	for t: Dictionary in _data.get("types", []):
		_manage(t, player)


func _clear_all() -> void:
	for id in _live:
		for n in _live[id]:
			if is_instance_valid(n):
				n.queue_free()
	_live.clear()


func _time_ok(when: String) -> bool:
	var cycle := get_tree().get_first_node_in_group("world_cycle") as WorldCycle
	var day := cycle.daylight if cycle else 1.0
	match when:
		"day":
			return day > 0.5
		"night":
			return day < 0.25
		"dusk":
			return day > 0.1 and day < 0.75
		"evening":
			return day < 0.75  # dusk, night and dawn
	return true


func _manage(t: Dictionary, player: Node3D) -> void:
	var id := String(t.get("id", ""))
	var list: Array = _live.get(id, [])
	list = list.filter(func(n: Variant) -> bool: return is_instance_valid(n))
	var ok := _time_ok(String(t.get("when", "any")))
	var far := float(_data.get("despawn_radius", 70.0))
	for n: Node3D in list.duplicate():
		if not ok or n.global_position.distance_to(player.global_position) > far or n.get_meta("gone", false):
			list.erase(n)
			_fade_out(n)
	if String(t.get("near", "")) in ["placed", "corpses"]:
		_live[id] = list  # only at SwarmSpot nodes
		return
	if String(t.get("kind", "")) == "ants":
		if ok and list.size() < int(t.get("max", 3)) and randf() < 0.5:
			var path := _ant_path(t, player)
			if path.size() >= 4:
				var trail := AntTrail.new(t, path)
				add_child(trail)
				list.append(trail)
		_live[id] = list
		return
	if ok and list.size() < int(t.get("max", 3)) and randf() < 0.6:
		var spot := _find_spot(t, player)
		if spot != Vector3.INF:
			var n := _make(t, spot)
			if n:
				add_child(n)
				n.global_position = spot + Vector3.UP * float(t.get("hover", 0.0))
				list.append(n)
	_live[id] = list


func _fade_out(n: Node3D) -> void:
	if not is_instance_valid(n):
		return
	var t := n.create_tween()
	t.tween_property(n, "scale", Vector3.ONE * 0.01, 0.6)
	t.tween_callback(n.queue_free)


# --- Where --------------------------------------------------------------------------

func _ground(p: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 60.0, p + Vector3.DOWN * 80.0, 1)
	return get_world_3d().direct_space_state.intersect_ray(q)


func _find_spot(t: Dictionary, player: Node3D) -> Vector3:
	var near := String(t.get("near", "any"))
	var lo := float(_data.get("min_distance", 14.0))
	var hi := float(_data.get("radius", 45.0))
	if near == "trees":
		var trees := _trees_near(player.global_position, hi)
		trees = trees.filter(func(tr: Node3D) -> bool: return tr.global_position.distance_to(player.global_position) > lo)
		if trees.is_empty():
			return Vector3.INF
		var tree: Node3D = trees.pick_random()
		var a := randf() * TAU
		var g := _ground(tree.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(0.8, 2.5))
		return g.position if not g.is_empty() else Vector3.INF
	for attempt in 8:
		var a := randf() * TAU
		var r := randf_range(lo, hi)
		var p := player.global_position + Vector3(cos(a) * r, 0, sin(a) * r)
		var g := _ground(p)
		if g.is_empty() or (g.normal as Vector3).y < 0.7:
			continue
		var at: Vector3 = g.position
		var sea := -5.0
		var ocean := get_tree().get_first_node_in_group("ocean")
		if ocean and "sea_level" in ocean:
			sea = float(ocean.get("sea_level"))
		if at.y < sea + 0.2:
			continue  # under the sea
		match near:
			"water":
				if not _near_water(at, sea):
					continue
			"grass":
				var streamer := get_tree().get_first_node_in_group("chunk_streamer")
				if streamer:
					var paint: Vector2 = streamer.call("paint_at", at)
					if paint.x > 0.4 or paint.y > 0.3:
						continue
		if String(t.get("kind", "")) == "birds":
			at += Vector3.UP * float(t.get("height", 14.0))
		return at
	return Vector3.INF


func _near_water(at: Vector3, sea: float) -> bool:
	if at.y < sea + 1.5:
		return true
	var streamer := get_tree().get_first_node_in_group("chunk_streamer")
	if streamer == null:
		return false
	var rects: Dictionary = streamer.get("_water_rects")
	for cell in rects:
		for w: Array in rects[cell]:
			var r: Rect2 = (w[0] as Rect2).grow(5.0)
			if r.has_point(Vector2(at.x, at.z)) and absf(at.y - float(w[1])) < 3.0:
				return true
	return false


# --- Ants -----------------------------------------------------------------------------

## A trail for ants: points [position, surface normal] about 0.2 m apart, over the ground,
## across a rock (rays from above climb over it) or up a tree trunk. `near`: trees, rocks,
## rocks_trees (either) or anything else for open ground. Empty if no spot was found.
func _ant_path(t: Dictionary, player: Node3D) -> Array:
	var near := String(t.get("near", "rocks_trees"))
	var lo := float(t.get("spawn_min", 4.0))
	var hi := float(t.get("spawn_max", 16.0))
	var props: Array = []
	if near in ["trees", "rocks_trees"]:
		props.append_array(_trees_near(player.global_position, hi).filter(func(n: Node3D) -> bool:
			return true))
	if near in ["rocks", "rocks_trees"]:
		props.append_array(_rocks_near(player.global_position, hi))
	props = props.filter(func(n: Node3D) -> bool: return n.global_position.distance_to(player.global_position) > lo)
	var space := get_world_3d().direct_space_state
	if not props.is_empty():
		var prop: Node3D = props.pick_random()
		if String(prop.get_meta("prop_name", "")).contains("tree"):
			return _trunk_path(prop, space)
		return _over_path(prop.global_position, space, 6.0)
	if near in ["trees", "rocks", "rocks_trees"] and not bool(t.get("ground_too", true)):
		return []
	for attempt in 6:
		var a := randf() * TAU
		var r := randf_range(lo, hi)
		var start := player.global_position + Vector3(cos(a) * r, 0, sin(a) * r)
		var path := _over_path(start, space, 5.0)
		if path.size() >= 4:
			return path
	return []


## Across the ground (and over anything solid on it) through `centre`, wandering a little.
func _over_path(centre: Vector3, space: PhysicsDirectSpaceState3D, length: float) -> Array:
	var heading := randf() * TAU
	var at := centre - Vector3(cos(heading), 0, sin(heading)) * length * 0.5
	var out: Array = []
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	var top := centre.y + 6.0
	for i in int(length / 0.2):
		q.from = Vector3(at.x, top, at.z)
		q.to = Vector3(at.x, centre.y - 6.0, at.z)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var n: Vector3 = hit.normal
		if n.y < 0.25:
			break  # a sheer face: the trail ends
		out.append([hit.position, n])
		heading += randf_range(-0.25, 0.25)
		at += Vector3(cos(heading), 0, sin(heading)) * 0.2
	return out


## Over the ground to a tree, then straight up its trunk.
func _trunk_path(tree: Node3D, space: PhysicsDirectSpaceState3D) -> Array:
	var base := tree.global_position
	var side := randf() * TAU
	var out_dir := Vector3(cos(side), 0, sin(side))
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	# Where the trunk's side is (a ray in towards its middle).
	q.from = base + out_dir * 2.0 + Vector3.UP * 0.5
	q.to = base + Vector3.UP * 0.5
	var side_hit := space.intersect_ray(q)
	if side_hit.is_empty():
		return []
	var radius := Vector2(side_hit.position.x - base.x, side_hit.position.z - base.z).length()
	var out: Array = []
	# Along the ground towards it, 1.5 m.
	for i in 8:
		var p := base + out_dir * (radius + 1.6 - i * 0.2)
		q.from = p + Vector3.UP * 3.0
		q.to = p + Vector3.DOWN * 3.0
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit.normal as Vector3).y > 0.5:
			out.append([hit.position, hit.normal])
	var ground_y: float = out.back()[0].y if not out.is_empty() else base.y
	# Up the bark.
	for i in 10:
		var h := ground_y + 0.08 + i * 0.2
		q.from = Vector3(base.x, h, base.z) + out_dir * (radius + 1.0)
		q.to = Vector3(base.x, h, base.z)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		out.append([hit.position, hit.normal])
	return out


func _rocks_near(p: Vector3, radius: float) -> Array:
	var out := []
	var streamer := get_tree().get_first_node_in_group("chunk_streamer")
	if streamer == null:
		return out
	var loaded: Dictionary = streamer.get("_loaded")
	for cell in loaded:
		var chunk := loaded[cell] as Node3D
		var holder := chunk.get_node_or_null("Props") if is_instance_valid(chunk) else null
		if holder == null:
			continue
		for prop in holder.get_children():
			var n := prop as Node3D
			var prop_name := String(n.get_meta("prop_name", "")) if n else ""
			if n and n.visible and (prop_name.contains("rock") or prop_name.contains("stone") or prop_name.contains("boulder")) \
					and n.global_position.distance_to(p) < radius:
				out.append(n)
	return out


func _trees_near(p: Vector3, radius: float) -> Array:
	var out := []
	var streamer := get_tree().get_first_node_in_group("chunk_streamer")
	if streamer == null:
		return out
	var loaded: Dictionary = streamer.get("_loaded")
	for cell in loaded:
		var chunk := loaded[cell] as Node3D
		var holder := chunk.get_node_or_null("Props") if is_instance_valid(chunk) else null
		if holder == null:
			continue
		for prop in holder.get_children():
			var n := prop as Node3D
			if n and n.visible and String(n.get_meta("prop_name", "")).contains("tree") and n.global_position.distance_to(p) < radius:
				out.append(n)
	return out


# --- What ----------------------------------------------------------------------------

func _make(t: Dictionary, at: Vector3) -> Node3D:
	match String(t.get("kind", "")):
		"critter":
			return Critter.new(t)
		"birds":
			return Flock.new(t, at)
		"swarm":
			return Swarm.new(t)
	return null


## The entry for a type id in wildlife.json ({} if there is none).
func type_data(id: String) -> Dictionary:
	for t in _data.get("types", []):
		if t is Dictionary and String(t.get("id", "")) == id:
			return t
	return {}


## Whether a type's "when" (any / day / dusk / night) holds now.
func time_ok(when: String) -> bool:
	return _time_ok(when)


static func _mat(color: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 3.0
	return m


## A small ground animal: hops about near where it spawned, bolts away from the player.
class Critter:
	extends Node3D
	var cfg := {}
	var _home := Vector3.ZERO
	var _goal := Vector3.ZERO
	var _wait := 0.0
	var _hop := 0.0
	var _fleeing := false
	var _body: Node3D

	func _init(t: Dictionary) -> void:
		cfg = t

	func _ready() -> void:
		var col := Color.html(String(cfg.get("color", "#8a5a32")))
		var s := float(cfg.get("size", 1.0))
		_body = Node3D.new()
		add_child(_body)
		var fur := Wildlife._mat(col)
		var torso := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.06 * s
		cap.height = 0.22 * s
		torso.mesh = cap
		torso.rotation_degrees.x = 80  # lying along -Z, nose first
		torso.position = Vector3(0, 0.07 * s, 0)
		torso.material_override = fur
		_body.add_child(torso)
		var head := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.048 * s
		hs.height = 0.09 * s
		head.mesh = hs
		head.position = Vector3(0, 0.12 * s, -0.11 * s)
		head.material_override = fur
		_body.add_child(head)
		if bool(cfg.get("ears", false)):
			for side in [-1.0, 1.0]:
				var ear := MeshInstance3D.new()
				var em := CapsuleMesh.new()
				em.radius = 0.014 * s
				em.height = 0.1 * s
				ear.mesh = em
				ear.position = Vector3(side * 0.022 * s, 0.19 * s, -0.1 * s)
				ear.rotation_degrees = Vector3(-15, 0, side * 12)
				ear.material_override = fur
				_body.add_child(ear)
			var puff := MeshInstance3D.new()
			var pm := SphereMesh.new()
			pm.radius = 0.03 * s
			pm.height = 0.06 * s
			puff.mesh = pm
			puff.position = Vector3(0, 0.08 * s, 0.13 * s)
			puff.material_override = Wildlife._mat(Color(0.95, 0.94, 0.9))
			_body.add_child(puff)
		else:
			# A big bushy tail curling up behind.
			var tail := MeshInstance3D.new()
			var ts := CapsuleMesh.new()
			ts.radius = 0.05 * s
			ts.height = 0.24 * s
			tail.mesh = ts
			tail.rotation_degrees.x = -20
			tail.position = Vector3(0, 0.16 * s, 0.13 * s)
			tail.material_override = Wildlife._mat(col.lightened(0.12))
			_body.add_child(tail)
		_home = global_position
		_goal = _home
		_wait = randf_range(0.5, 2.0)

	func _process(delta: float) -> void:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		var speed := float(cfg.get("speed", 4.0))
		if player and not _fleeing and player.global_position.distance_to(global_position) < float(cfg.get("flee_distance", 7.0)):
			_fleeing = true
			var away := global_position - player.global_position
			away.y = 0
			_goal = global_position + away.normalized() * 25.0
		if not _fleeing:
			_wait -= delta
			if _wait <= 0.0 and global_position.distance_to(_goal) < 0.2:
				var a := randf() * TAU
				_goal = _home + Vector3(cos(a), 0, sin(a)) * randf_range(0.5, 3.0)
				_wait = randf_range(1.0, 4.0)
			speed *= 0.4
		var to := _goal - global_position
		to.y = 0
		if to.length() > 0.15:
			var step := to.normalized() * minf(speed * delta, to.length())
			global_position += step
			look_at(global_position + to, Vector3.UP)
			_hop += delta * (14.0 if _fleeing else 9.0)
			_body.position.y = absf(sin(_hop)) * 0.08
			var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 3.0, global_position + Vector3.DOWN * 6.0, 1)
			var g := get_world_3d().direct_space_state.intersect_ray(q)
			if not g.is_empty():
				global_position.y = (g.position as Vector3).y
		elif _fleeing:
			set_meta("gone", true)
		else:
			_body.position.y = 0.0


## A few birds circling together high up, wings flapping and gliding.
class Flock:
	extends Node3D
	var cfg := {}
	var _center := Vector3.ZERO
	var _birds: Array = []  # [Node3D, left wing, right wing, phase, radius, speed, height]
	var _drift := Vector3.ZERO

	func _init(t: Dictionary, at: Vector3) -> void:
		cfg = t
		_center = at
		_drift = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 0.8

	func _ready() -> void:
		var mat := Wildlife._mat(Color.html(String(cfg.get("color", "#2e2e34"))))
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var s := float(cfg.get("size", 1.0))
		for i in int(cfg.get("flock", 5)):
			var bird := Node3D.new()
			var body := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.08, 0.06, 0.3) * s
			body.mesh = bm
			body.material_override = mat
			bird.add_child(body)
			var wings := []
			for side in [-1.0, 1.0]:
				var pivot := Node3D.new()
				var w := MeshInstance3D.new()
				var wm := PlaneMesh.new()
				wm.size = Vector2(0.4, 0.16) * s
				w.mesh = wm
				w.position.x = side * 0.2 * s
				w.material_override = mat
				pivot.add_child(w)
				bird.add_child(pivot)
				wings.append(pivot)
			add_child(bird)
			_birds.append([bird, wings[0], wings[1], randf() * TAU, randf_range(4.0, 9.0), randf_range(0.35, 0.6) * (1 if randf() < 0.8 else -1), randf_range(-1.5, 1.5)])

	func _process(delta: float) -> void:
		_center += _drift * delta
		global_position = _center
		var t := Time.get_ticks_msec() / 1000.0
		for b: Array in _birds:
			b[3] += b[5] * delta
			var p := Vector3(cos(b[3]) * b[4], b[6] + sin(t * 0.7 + b[4]) * 0.6, sin(b[3]) * b[4])
			var bird := b[0] as Node3D
			var next := Vector3(cos(b[3] + 0.1 * signf(b[5])) * b[4], p.y, sin(b[3] + 0.1 * signf(b[5])) * b[4])
			bird.position = p
			bird.look_at(global_position + next, Vector3.UP)
			# Flap a while, then glide.
			var flap := sin(t * 14.0 + b[4]) * 0.8 if fmod(t + b[4], 4.0) < 2.2 else 0.15
			(b[1] as Node3D).rotation.z = flap
			(b[2] as Node3D).rotation.z = -flap


## A line of ants walking along a trail (see Wildlife._ant_path), one way, appearing at
## the start and slipping away at the end. Small flat pictures lying on the surface
## (assets/effects/builtin/ant_2.png or the type's `sprite`), drawn as one MultiMesh,
## only moved while the camera is near.
class AntTrail:
	extends MultiMeshInstance3D
	const SHADER := preload("res://assets/materials/ant.gdshader")
	const DEFAULT_SPRITE := "res://assets/effects/builtin/ant_2.png"
	var cfg := {}
	var points: Array = []  # [position, normal]
	var _along := PackedFloat32Array()  # distance at each point
	var _length := 0.0
	var _count := 12
	var _speed := 0.25
	var _size := 0.06
	var _offsets := PackedFloat32Array()
	var _time := 0.0

	func _init(t: Dictionary, path: Array) -> void:
		cfg = t
		points = path

	func _ready() -> void:
		top_level = true
		global_transform = Transform3D.IDENTITY
		_count = int(cfg.get("count", 12))
		_speed = float(cfg.get("speed", 0.25))
		_size = 0.06 * float(cfg.get("size", 1.0))
		_along.resize(points.size())
		for i in points.size():
			if i > 0:
				_length += (points[i][0] as Vector3).distance_to(points[i - 1][0])
			_along[i] = _length
		_offsets.resize(_count)
		for i in _count:
			_offsets[i] = _length * float(i) / _count + randf_range(-0.05, 0.05)
		var q := QuadMesh.new()
		q.orientation = PlaneMesh.FACE_Y
		var path := String(cfg.get("sprite", ""))
		var tex: Texture2D = AbilityFX.texture(path if not path.is_empty() else DEFAULT_SPRITE)
		var frames := maxi(int(cfg.get("frames", 2)), 1)
		var shape := (float(tex.get_width()) / frames) / maxf(float(tex.get_height()), 1.0) if tex else 1.0
		q.size = Vector2(_size * shape, _size)
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("tex", tex)
		mat.set_shader_parameter("frames", float(frames))
		mat.set_shader_parameter("tint", Color.html(String(cfg.get("color", "#1a120c"))))
		q.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = q
		mm.instance_count = _count
		multimesh = mm
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visibility_range_end = float(cfg.get("visible_within", 18.0))
		_place(0.0)

	## Where along the trail `d` metres in: [position, normal, forward].
	func _sample(d: float) -> Array:
		var i := 1
		while i < points.size() - 1 and _along[i] < d:
			i += 1
		var a: Vector3 = points[i - 1][0]
		var b: Vector3 = points[i][0]
		var seg := maxf(_along[i] - _along[i - 1], 0.0001)
		var k := clampf((d - _along[i - 1]) / seg, 0.0, 1.0)
		var n: Vector3 = (points[i - 1][1] as Vector3).lerp(points[i][1], k).normalized()
		return [a.lerp(b, k), n, (b - a).normalized()]

	func _place(delta: float) -> void:
		for i in _count:
			_offsets[i] = fmod(_offsets[i] + _speed * delta * (0.85 + 0.3 * float(i % 3) / 2.0), _length)
			var s := _sample(_offsets[i])
			var n: Vector3 = s[1]
			var fwd: Vector3 = s[2]
			fwd = (fwd - n * fwd.dot(n)).normalized()
			if fwd.length() < 0.1:
				fwd = n.cross(Vector3.RIGHT).normalized()
			# Small at the ends, so they seem to come out of the ground and go back in.
			var ends := clampf(minf(_offsets[i], _length - _offsets[i]) / 0.3, 0.0, 1.0)
			var wobble := sin(_time * 9.0 + i * 1.7) * 0.15
			var x := fwd.rotated(n, wobble)
			var basis := Basis(x, n, x.cross(n)).scaled(Vector3.ONE * maxf(ends, 0.001))
			multimesh.set_instance_transform(i, Transform3D(basis, (s[0] as Vector3) + n * 0.012))

	func _process(delta: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or points.is_empty() or cam.global_position.distance_to(points[0][0]) > visibility_range_end + 10.0:
			return
		_time += delta
		_place(delta)


## A cloud of small insects: fireflies (glowing, blinking), mosquitos, flies.
class Swarm:
	extends GPUParticles3D
	const DEFAULT_SPRITE := "res://assets/effects/builtin/insect_fly_2.png"
	var cfg := {}

	func _init(t: Dictionary) -> void:
		cfg = t

	func _ready() -> void:
		var glow := bool(cfg.get("glow", false))
		var col := Color.html(String(cfg.get("color", "#222222")))
		var spread := float(cfg.get("spread", 1.5))
		amount = int(cfg.get("count", 16))
		lifetime = float(cfg.get("lifetime", 3.0))
		preprocess = lifetime
		visibility_aabb = AABB(Vector3.ONE * -spread * 2.0, Vector3.ONE * spread * 4.0)
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = spread
		pm.gravity = Vector3.ZERO
		pm.direction = Vector3.UP
		pm.spread = 180.0
		pm.initial_velocity_min = 0.1
		pm.initial_velocity_max = float(cfg.get("speed", 0.6))
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 2.0
		pm.turbulence_noise_scale = 1.5
		pm.turbulence_influence_min = 0.2
		pm.turbulence_influence_max = 0.6
		var ramp := Gradient.new()
		if glow:
			# Blink: fade in, glow, fade out.
			ramp.set_color(0, Color(col, 0.0))
			ramp.set_color(1, Color(col, 0.0))
			ramp.add_point(0.3, Color(col, 1.0))
			ramp.add_point(0.6, Color(col, 0.9))
		else:
			ramp.set_color(0, Color(col, 0.0))
			ramp.set_color(1, Color(col, 0.0))
			ramp.add_point(0.1, Color(col, 1.0))
			ramp.add_point(0.9, Color(col, 1.0))
		var rt := GradientTexture1D.new()
		rt.gradient = ramp
		pm.color_ramp = rt
		process_material = pm
		var q := QuadMesh.new()
		var s := float(cfg.get("size", 1.0))
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		# Each insect is a picture (`sprite`; frames side by side flap as it flies), tinted
		# with the swarm's colour. Without one: a soft glowing dot, or the built-in fly.
		var path := String(cfg.get("sprite", ""))
		if path.is_empty() and not glow:
			path = DEFAULT_SPRITE
		var tex: Texture2D = AbilityFX.texture(path) if not path.is_empty() else null
		var frames := maxi(int(cfg.get("frames", 2 if path == DEFAULT_SPRITE else 1)), 1)
		if tex:
			m.albedo_texture = tex
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			m.particles_anim_h_frames = frames
			m.particles_anim_v_frames = 1
			m.particles_anim_loop = true
			# One run through the frames = one wing beat; the speed counts runs per lifetime.
			pm.anim_speed_min = float(cfg.get("flap_speed", 12.0)) * lifetime
			pm.anim_speed_max = pm.anim_speed_min * 1.3
			pm.anim_offset_max = 1.0
			var shape := (float(tex.get_width()) / frames) / maxf(float(tex.get_height()), 1.0)
			q.size = Vector2(shape, 1.0) * (0.09 if not glow else 0.12) * s
		else:
			q.size = Vector2.ONE * 0.06 * s
			m.albedo_texture = Effects._mote_texture(false)
		if glow:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		q.material = m
		draw_pass_1 = q
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if glow:
			var light := OmniLight3D.new()
			light.light_color = col
			light.light_energy = 0.6
			light.omni_range = spread * 2.5
			light.shadow_enabled = false
			add_child(light)
