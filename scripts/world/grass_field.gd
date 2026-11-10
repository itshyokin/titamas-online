class_name GrassField
extends Node3D
## Grass for one terrain chunk: clumps of tall grass (crossed picture cards) scattered where the ground is
## painted grass (thicker where the paint is stronger), never on cliffs, steep slopes or
## under water. Split into 16 m tiles so distant tiles are culled. Built by ChunkStreamer
## for the chunks around the player.

const TILE := 16.0
const MATERIAL := preload("res://assets/materials/grass.gdshader")
const CLUMP_TEXTURE := preload("res://assets/textures/grass_clump.png")
const TERRAIN_MATERIAL := "res://assets/materials/terrain/terrain.tres"

static var _mesh: ArrayMesh
static var _material: ShaderMaterial


var _cell: Vector2i
var _chunk_size := 64.0
var _spacing := 2.0
var _heights: PackedFloat32Array
var _paint: PackedVector2Array
var _water: Array
var _sea_level := -INF
var _density := 0.0
var _next_tile := 0


## Sets up the grass for a chunk; tiles are then grown by build_next(). `heights` and
## `paint` are the chunk's terrain grids (n x n samples, `spacing` metres apart, starting
## at the chunk's corner); `water` is a list of [Rect2 in world XZ, surface height];
## `density` is clumps per square metre.
static func create(cell: Vector2i, chunk_size: float, spacing: float, heights: PackedFloat32Array,
		paint: PackedVector2Array, water: Array, sea_level: float, density: float) -> GrassField:
	var field := GrassField.new()
	field.name = "Grass"
	field._cell = cell
	field._chunk_size = chunk_size
	field._spacing = spacing
	field._heights = heights
	field._paint = paint
	field._water = water
	field._sea_level = sea_level
	field._density = density if not heights.is_empty() else 0.0
	return field


func is_done() -> bool:
	return _density <= 0.0 or _next_tile >= int(_chunk_size / TILE) * int(_chunk_size / TILE)


## Grows the next 16 m tile. Returns false once every tile is done.
func build_next() -> bool:
	if is_done():
		return false
	var tiles := int(_chunk_size / TILE)
	var tx := _next_tile % tiles
	var ty := _next_tile / tiles
	_next_tile += 1
	var mmi := _build_tile(tx, ty)
	if mmi:
		add_child(mmi)
	return true


func _build_tile(tx: int, ty: int) -> MultiMeshInstance3D:
	var cell := _cell
	var chunk_size := _chunk_size
	var spacing := _spacing
	var heights := _heights
	var paint := _paint
	var water := _water
	var sea_level := _sea_level
	var density := _density
	var n := int(round(chunk_size / spacing)) + 1
	var corner := Vector2(cell.x * chunk_size - chunk_size * 0.5, cell.y * chunk_size - chunk_size * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, ty * 64 + tx))
	if true:
		if true:
			var xforms: Array[Transform3D] = []
			var count := int(TILE * TILE * density)
			for i in count:
				var lx := (tx + rng.randf()) * TILE
				var lz := (ty + rng.randf()) * TILE
				var gx := lx / spacing
				var gz := lz / spacing
				var ix := clampi(int(gx), 0, n - 2)
				var iz := clampi(int(gz), 0, n - 2)
				var fx := gx - ix
				var fz := gz - iz
				var h00 := heights[iz * n + ix]
				var h10 := heights[iz * n + ix + 1]
				var h01 := heights[(iz + 1) * n + ix]
				var h11 := heights[(iz + 1) * n + ix + 1]
				var h := lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)
				# Steepness from the grid.
				var dx := (lerpf(h10, h11, fz) - lerpf(h00, h01, fz)) / spacing
				var dz := (lerpf(h01, h11, fx) - lerpf(h00, h10, fx)) / spacing
				if dx * dx + dz * dz > 0.5:  # steeper than ~35 degrees
					continue
				var pv := Vector2.ZERO
				if not paint.is_empty():
					var p00 := paint[iz * n + ix]
					var p10 := paint[iz * n + ix + 1]
					var p01 := paint[(iz + 1) * n + ix]
					var p11 := paint[(iz + 1) * n + ix + 1]
					pv = p00.lerp(p10, fx).lerp(p01.lerp(p11, fx), fz)
				var grass := clampf(1.0 - pv.x - pv.y, 0.0, 1.0)
				if rng.randf() > grass * grass:  # thins out where grass blends into dirt or rock
					continue
				var world := Vector3(corner.x + lx, h, corner.y + lz)
				if h < sea_level + 0.2 or _under_water(world, water):
					continue
				var scale := rng.randf_range(0.7, 1.3) * lerpf(0.75, 1.0, grass)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale * rng.randf_range(0.8, 1.25), scale))
				xforms.append(Transform3D(basis, world - Vector3(cell.x * chunk_size, 0, cell.y * chunk_size)))
			if xforms.is_empty():
				return null
			return _tile(xforms)
	return null


static func _under_water(p: Vector3, water: Array) -> bool:
	for w: Array in water:
		if (w[0] as Rect2).has_point(Vector2(p.x, p.z)) and p.y < float(w[1]) + 0.1:
			return true
	return false


static func _tile(xforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _clump_mesh()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _shared_material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = WorldPerf.grass_range()
	return mmi


static func _shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = MATERIAL
		_material.set_shader_parameter("clump_tex", CLUMP_TEXTURE)
		# The ground colour comes from the terrain's own grass texture.
		if ResourceLoader.exists(TERRAIN_MATERIAL):
			var terrain := load(TERRAIN_MATERIAL) as ShaderMaterial
			if terrain:
				_material.set_shader_parameter("ground_tex", terrain.get_shader_parameter("tex_r"))
				var tile = terrain.get_shader_parameter("tile_size")
				_material.set_shader_parameter("ground_tile_size", float(tile) if tile != null else 4.0)
	return _material


## A clump: three rows of card pairs crossing in shallow V's (Saturn's "thicket"), so it
## looks full from every side. 1 m tall (the shader scales it to the region's grass
## height). UV.y = 0 at the top of the picture.
static func _clump_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.9
	var d := 0.6
	var rows := [[-0.33, -0.06, 0.9], [0.0, 0.05, 1.0], [0.33, -0.02, 0.84]]
	for i in rows.size():
		var r: Array = rows[i]
		for yaw: float in [0.44, -0.44]:
			var k: float = r[2] * (1.0 if yaw > 0.0 else 0.94)
			var mirror := (i + (0 if yaw > 0.0 else 1)) % 2 == 1
			_card(st, Vector3(r[1] * w, 0.0, r[0] * d), yaw, w * k, k, mirror)
	st.generate_normals()
	_mesh = st.commit()
	return _mesh


static func _card(st: SurfaceTool, center: Vector3, yaw: float, width: float, height: float, mirror: bool) -> void:
	var side := Vector3(cos(yaw), 0.0, -sin(yaw)) * width * 0.5
	var bl := center - side
	var br := center + side
	var tl := bl + Vector3.UP * height
	var tr := br + Vector3.UP * height
	var u0 := 1.0 if mirror else 0.0
	var u1 := 1.0 - u0
	for v in [[bl, Vector2(u0, 1)], [br, Vector2(u1, 1)], [tr, Vector2(u1, 0)], [bl, Vector2(u0, 1)], [tr, Vector2(u1, 0)], [tl, Vector2(u0, 0)]]:
		st.set_uv(v[1])
		st.add_vertex(v[0])
