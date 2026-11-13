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
const COLUMNS := 5
const SIZE := Vector3(0.36, 0.42, 0.17)  # the main bag
## Where the bag's middle sits in the body's model space (rest pose): behind the upper back.
const CENTER := Vector3(0.0, 1.29, 0.285)
const PIN_RADIUS := 0.024
const PIN_STEP := Vector2(0.064, 0.058)

const LEATHER := Color(0.47, 0.31, 0.18)
const LEATHER_DARK := Color(0.36, 0.23, 0.13)
const STRAP := Color(0.27, 0.17, 0.1)
const BRASS := Color(0.86, 0.68, 0.3)
const WOOL := Color(0.42, 0.5, 0.38)

var _pins := Node3D.new()
var _pin_meshes := {}  # icon path → material (shared)


func _init() -> void:
	name = "Backpack"
	_build()
	_pins.name = "Pins"
	add_child(_pins)


## Puts these achievements (their entries: {id, icon, name…}) on as pins, first one top
## left, rows of five. More than 25: the first 25.
func set_pins(defs: Array) -> void:
	for c in _pins.get_children():
		c.queue_free()
	var face := SIZE.z * 0.5 + 0.004
	var top := SIZE.y * 0.5 - 0.125  # under the flap
	for i in mini(defs.size(), SLOTS):
		var d: Dictionary = defs[i]
		var col := i % COLUMNS
		var row := i / COLUMNS
		var at := Vector3((col - (COLUMNS - 1) * 0.5) * PIN_STEP.x, top - row * PIN_STEP.y, face)
		var pin := _pin(String(d.get("icon", "")))
		pin.position = at
		pin.name = "Pin_" + String(d.get("id", str(i)))
		pin.set_meta("achievement", String(d.get("id", "")))
		_pins.add_child(pin)


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


func _build() -> void:
	var h := SIZE * 0.5
	# The bag, slightly narrower at the top.
	_box(SIZE, Vector3.ZERO, LEATHER)
	_box(Vector3(SIZE.x - 0.03, 0.03, SIZE.z - 0.02), Vector3(0, h.y + 0.012, 0), LEATHER_DARK)
	# Top flap over the front (the side facing away from the body) with a strap + buckle.
	_box(Vector3(SIZE.x + 0.012, 0.012, SIZE.z + 0.01), Vector3(0, h.y + 0.03, 0.004), LEATHER_DARK)
	_box(Vector3(SIZE.x + 0.012, 0.1, 0.012), Vector3(0, h.y - 0.02, h.z + 0.006), LEATHER_DARK)
	_box(Vector3(0.03, 0.05, 0.006), Vector3(0, h.y - 0.06, h.z + 0.014), STRAP)
	_box(Vector3(0.036, 0.022, 0.008), Vector3(0, h.y - 0.075, h.z + 0.016), BRASS)
	# Side pockets.
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.05, 0.16, 0.11), Vector3(side * (h.x + 0.025), -0.08, 0.0), LEATHER_DARK)
		_box(Vector3(0.054, 0.035, 0.115), Vector3(side * (h.x + 0.025), 0.0, 0.0), LEATHER)
	# Shoulder straps: over the shoulders into the body (the front halves are hidden by it).
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.045, 0.012, 0.2), Vector3(side * 0.1, h.y + 0.02, -h.z - 0.06), STRAP)
	# Bedroll strapped underneath.
	var roll := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.055
	cyl.bottom_radius = 0.055
	cyl.height = SIZE.x + 0.06
	cyl.radial_segments = 10
	roll.mesh = cyl
	roll.material_override = _mat(WOOL, 0.95)
	roll.rotation = Vector3(0, 0, PI * 0.5)
	roll.position = Vector3(0, -h.y - 0.045, 0.015)
	add_child(roll)
	for side: float in [-1.0, 1.0]:
		var band := MeshInstance3D.new()
		var tor := CylinderMesh.new()
		tor.top_radius = 0.059
		tor.bottom_radius = 0.059
		tor.height = 0.018
		tor.radial_segments = 10
		band.mesh = tor
		band.material_override = _mat(STRAP)
		band.rotation = Vector3(0, 0, PI * 0.5)
		band.position = roll.position + Vector3(side * 0.12, 0, 0)
		add_child(band)
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
