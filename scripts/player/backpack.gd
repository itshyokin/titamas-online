class_name Backpack
extends Node3D
## The adventurer's backpack, worn by every player character (look "show_backpack",
## default on). Its back panel holds up to 25 round pins, one per achievement earned
## (Achievements.earned(), oldest first, each showing that achievement's icon), so other
## players can see what you've done.
##
## Built in code: leather pack, top flap with a buckle, side pockets, a bedroll under it.
## CharacterModel.set_backpack(on, pins) wears it on the upper spine.
## Names no autoloads (tests can use it): pins are given as achievement entries.

const SLOTS := 25
## The main bag is a rounded sack: an ellipsoid with these half-sizes (x across, y up,
## z out from the back).
const RADII := Vector3(0.19, 0.23, 0.12)
const SIZE := RADII * 2.0
## Where the bag's middle sits in the body's model space (rest pose): behind the upper back.
const CENTER := Vector3(0.0, 1.27, 0.28)
const PIN_RADIUS := 0.02

const LEATHER := Color(0.47, 0.31, 0.18)
const LEATHER_DARK := Color(0.36, 0.23, 0.13)
const STRAP := Color(0.27, 0.17, 0.1)
const BRASS := Color(0.86, 0.68, 0.3)
const WOOL := Color(0.42, 0.5, 0.38)

## The 25 pin spots, scattered over the bag's curved back (same for everyone, so a pin
## always sits in the same place): [position, normal, twist].
static var _spots: Array = []

var _pins := Node3D.new()
var _pin_meshes := {}  # icon path → material (shared)


func _init() -> void:
	name = "Backpack"
	_build()
	_pins.name = "Pins"
	add_child(_pins)


## Puts these achievements (their entries: {id, icon, name…}) on as pins, scattered
## over the back of the bag. More than 25: the first 25.
func set_pins(defs: Array) -> void:
	for c in _pins.get_children():
		c.queue_free()
	var spots := pin_spots()
	for i in mini(defs.size(), SLOTS):
		var d: Dictionary = defs[i]
		var spot: Array = spots[i]
		var pin := _pin(String(d.get("icon", "")))
		var n: Vector3 = spot[1]
		var up := Vector3.UP - n * n.y
		var basis := Basis(up.cross(n).normalized(), up.normalized(), n) * Basis(Vector3.BACK, float(spot[2]))
		pin.transform = Transform3D(basis, spot[0])
		pin.name = "Pin_" + String(d.get("id", str(i)))
		pin.set_meta("achievement", String(d.get("id", "")))
		_pins.add_child(pin)


## Point on the bag's outer surface for (u, v) in -1..1 across its back, and the normal.
static func surface(u: float, v: float) -> Array:
	var x := u * RADII.x
	var y := v * RADII.y
	var k := 1.0 - u * u - v * v
	var z := RADII.z * sqrt(maxf(k, 0.0))
	var p := Vector3(x, y, z)
	var n := Vector3(x / (RADII.x * RADII.x), y / (RADII.y * RADII.y), z / (RADII.z * RADII.z)).normalized()
	return [p + n * 0.004, n]


## Scattered, never touching: random spots (fixed seed) on the back, kept off the flap
## strap and the edges, each a little twisted.
static func pin_spots() -> Array:
	if _spots.size() == SLOTS:
		return _spots
	_spots.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7351
	var gap := PIN_RADIUS * 2.25
	var tries := 0
	var reach := 0.76
	while _spots.size() < SLOTS and tries < 20000:
		tries += 1
		if tries % 4000 == 0:
			gap *= 0.94  # crowded: allow them a little closer
		var u := rng.randf_range(-reach, reach)
		var v := rng.randf_range(-reach, 0.62)
		if u * u + v * v > reach * reach:
			continue
		if absf(u) < 0.16 and v > 0.3:
			continue  # the flap's strap and buckle
		var s: Array = surface(u, v)
		var p: Vector3 = s[0]
		var ok := true
		for o: Array in _spots:
			if (o[0] as Vector3).distance_to(p) < gap:
				ok = false
				break
		if ok:
			_spots.append([p, s[1], rng.randf_range(-0.45, 0.45)])
	# Order them so the first few pins already spread over the bag (each next spot is the
	# one furthest from those taken), starting near the middle.
	var left := _spots.duplicate()
	var ordered: Array = []
	var start := 0
	for i in left.size():
		if (left[i][0] as Vector3).length_squared() < (left[start][0] as Vector3).length_squared():
			start = i
	ordered.append(left.pop_at(start))
	while not left.is_empty():
		var best := 0
		var best_d := -1.0
		for i in left.size():
			var d := INF
			for o: Array in ordered:
				d = minf(d, (o[0] as Vector3).distance_to(left[i][0]))
			if d > best_d:
				best_d = d
				best = i
		ordered.append(left.pop_at(best))
	_spots = ordered
	return _spots


## The entries for these achievement ids, in order, skipping ids no longer defined.
static func pins_of(ids: Array, defs: Array) -> Array:
	var by_id := {}
	for d in defs:
		if d is Dictionary:
			by_id[String(d.get("id", ""))] = d
	var out: Array = []
	for id in ids:
		if by_id.has(String(id)):
			out.append(by_id[String(id)])
	return out


func pin_count() -> int:
	return _pins.get_child_count()


# --- Building ------------------------------------------------------------------------

static func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(size: Vector3, at: Vector3, c: Color, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(c)
	mi.position = at
	parent.add_child(mi)
	return mi


func _ellipsoid(radii: Vector3, at: Vector3, c: Color, rough := 0.85) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	sp.radial_segments = 20
	sp.rings = 12
	mi.mesh = sp
	mi.scale = radii
	mi.material_override = _mat(c, rough)
	mi.position = at
	add_child(mi)
	return mi


func _cylinder(radius: float, length: float, at: Vector3, c: Color, rot := Vector3(0, 0, PI * 0.5)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 12
	mi.mesh = cyl
	mi.material_override = _mat(c, 0.9)
	mi.rotation = rot
	mi.position = at
	add_child(mi)
	return mi


## A basis with +Y along `up` and +Z out along `out` (made square to each other).
static func _facing(up: Vector3, out: Vector3) -> Basis:
	var z := (out - up * up.dot(out)).normalized()
	return Basis(up.cross(z).normalized(), up.normalized(), z)


func _build() -> void:
	var r := RADII
	# The rounded sack, and a slightly flatter panel against the back so it sits close.
	_ellipsoid(r, Vector3.ZERO, LEATHER)
	# Drawstring neck and the rounded top flap folded over it.
	_cylinder(r.x * 0.62, 0.05, Vector3(0, r.y * 0.9, 0), LEATHER_DARK, Vector3.ZERO)
	_ellipsoid(Vector3(r.x * 0.9, 0.06, r.z * 1.02), Vector3(0, r.y * 0.86, 0.008), LEATHER_DARK)
	# The flap's strap down the back to a brass buckle.
	var strap_top: Array = surface(0.0, 0.78)
	var strap_low: Array = surface(0.0, 0.42)
	var mid: Vector3 = ((strap_top[0] as Vector3) + (strap_low[0] as Vector3)) * 0.5
	var along := ((strap_top[0] as Vector3) - (strap_low[0] as Vector3)).normalized()
	var out := (((strap_top[1] as Vector3) + (strap_low[1] as Vector3)) * 0.5).normalized()
	var strap := _box(Vector3(0.03, (strap_top[0] as Vector3).distance_to(strap_low[0]) + 0.02, 0.006), mid + out * 0.01, STRAP)
	strap.basis = _facing(along, out)
	var buckle := _box(Vector3(0.036, 0.024, 0.01), (strap_low[0] as Vector3) + (strap_low[1] as Vector3) * 0.012, BRASS)
	buckle.basis = _facing(Vector3.UP, strap_low[1])
	# Round side pockets.
	for side: float in [-1.0, 1.0]:
		_ellipsoid(Vector3(0.045, 0.09, 0.07), Vector3(side * (r.x - 0.005), -0.05, 0.0), LEATHER_DARK)
	# Shoulder straps: over the shoulders into the body (the front halves are hidden by it).
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.045, 0.012, 0.2), Vector3(side * 0.1, r.y * 0.85, -r.z - 0.05), STRAP)
	# Bedroll strapped underneath.
	_cylinder(0.055, r.x * 2.0 + 0.06, Vector3(0, -r.y - 0.02, 0.0), WOOL)
	for side: float in [-1.0, 1.0]:
		_cylinder(0.059, 0.018, Vector3(side * 0.12, -r.y - 0.02, 0.0), STRAP)
	for c in get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## One pin: a brass rim, a disc and the icon on it (pixel-crisp).
func _pin(icon: String) -> Node3D:
	var pin := Node3D.new()
	var rim := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = PIN_RADIUS
	cyl.bottom_radius = PIN_RADIUS
	cyl.height = 0.006
	cyl.radial_segments = 16
	rim.mesh = cyl
	var brass := _mat(BRASS, 0.35)
	brass.metallic = 0.6
	rim.material_override = brass
	rim.rotation = Vector3(PI * 0.5, 0, 0)
	pin.add_child(rim)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * PIN_RADIUS * 1.7
	face.mesh = q
	face.position = Vector3(0, 0, 0.0035)
	face.material_override = _icon_material(icon)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pin.add_child(face)
	return pin


func _icon_material(icon: String) -> StandardMaterial3D:
	if _pin_meshes.has(icon):
		return _pin_meshes[icon]
	var m := StandardMaterial3D.new()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.6
	# A little glow so the pictures read in shade.
	m.emission_enabled = true
	m.emission_energy_multiplier = 0.25
	var tex: Texture2D = null
	if icon != "" and ResourceLoader.exists(icon):
		tex = load(icon) as Texture2D
	if tex:
		m.albedo_texture = tex
		m.emission_texture = tex
	else:
		m.albedo_color = Color(0.3, 0.62, 0.25)
		m.emission = Color(0.3, 0.62, 0.25)
	_pin_meshes[icon] = m
	return m
