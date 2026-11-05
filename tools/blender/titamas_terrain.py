bl_info = {
	"name": "Titamas Terrain Chunks",
	"author": "Titamas Online",
	"version": (1, 4, 0),
	"blender": (4, 1, 0),
	"location": "3D Viewport > Sidebar (N) > Titamas",
	"description": "Create a sculptable master terrain on the 64 m chunk grid and export it as seamless chunk .glb files",
	"category": "Import-Export",
}

# How it works
# ------------
# Chunk grid (matches the Godot project): chunk_I_J has its centre at Godot (I*64, 0, J*64).
# Godot +Z is Blender -Y, so in Blender that centre is (I*64, -J*64, 0).
# Each chunk covers +/- 32 m around its centre. chunk_0_0 is centred on the world origin;
# I grows east (+X), J grows south (Blender -Y).
#
# Keep ONE master terrain object and grow it with "Add Chunks to Terrain": new chunks share
# the existing border vertices, so they're welded to what you've already sculpted.
#
# Export never changes your master terrain. It copies it, cuts the copy exactly on the grid
# lines, and saves each cell as chunk_I_J.glb with its origin at the cell centre (height 0)
# and scale applied. Both sides of every seam come from the same cut vertices, so they match.
# UVs are generated from world position, so tiling textures line up across seams too.
#
# Water: flat mesh planes in a collection named "Water" are cut per chunk too and exported
# as "<name>-water"; Godot turns them into swimmable water with the water shader.
#
# Match Edges: when starting a region next to one that's already exported, snaps this
# terrain's border to the neighbour's exported edge heights (and blends inward).
#
# Set Height brush: Object Mode tool that pulls terrain toward a chosen height.
#
# Props: objects in the "Props" collection (any sub-collections) are written per chunk to
# chunk_I_J.props.json (prop name + transform). The prop name is the shared mesh name for
# linked duplicates (Alt+D / Ctrl+L), otherwise the object name without ".001". Each prop
# model is exported once by "Export Prop Library" as <name>.glb, textures included.
#
# Terrain painting: a colour attribute "TerrainPaint" (red = grass, green = dirt, blue =
# cliff, alpha = optional 4th layer) painted in Vertex Paint mode. Godot's terrain shader
# mixes the textures by it. Chunks use a single material called "terrain". On export the
# paint is written into a second UV map ("TerrainPaintUV": U = dirt, V = cliff, grass =
# the rest), because UV maps survive every glTF exporter version; vertex colours don't.

import json
import math
import os
import re
import struct

import bmesh
import bpy
import gpu
from bpy_extras import view3d_utils
from gpu_extras.batch import batch_for_shader
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree
from bpy.props import BoolProperty, FloatProperty, IntProperty, PointerProperty, StringProperty

EPS = 1e-4
PAINT_ATTR = "TerrainPaint"
# Which paint channel each of the old per-face materials becomes (matched by name).
LAYER_KEYWORDS = (("grass", 0), ("dirt", 1), ("path", 1), ("cliff", 2), ("rock", 2), ("stone", 2))
LAYER_NAMES = ("grass", "dirt", "cliff")


class TitamasTerrainSettings(bpy.types.PropertyGroup):
	chunk_size: FloatProperty(name="Chunk Size (m)", default=64.0, min=8.0)
	spacing: FloatProperty(name="Vertex Spacing (m)", default=2.0, min=0.25)
	columns: IntProperty(name="Chunks East (X)", default=1, min=1, max=64)
	rows: IntProperty(name="Chunks South (-Y)", default=1, min=1, max=64)
	start_i: IntProperty(name="Chunk X", default=0, description="Grid X index of the north-west chunk to create (east is +)")
	start_j: IntProperty(name="Chunk Y", default=0, description="Grid Y index of the north-west chunk to create (south is +)")
	lock_sculpt: BoolProperty(
		name="Lock Sculpt X/Y",
		default=True,
		description="Sculpt brushes only move vertices up and down, keeping the grid straight",
	)
	uv_tile: FloatProperty(
		name="Texture Tile (m)",
		default=4.0,
		min=0.25,
		description="World-space size of one texture repeat",
	)
	export_dir: StringProperty(name="Export Folder", default="//chunks/", subtype="DIR_PATH")
	add_collision: BoolProperty(
		name="Add Collision (-col)",
		default=True,
		description="Name each chunk with the -col suffix so Godot builds matching collision on import",
	)
	include_textures: BoolProperty(
		name="Include Textures",
		default=False,
		description="Embed texture images in every chunk file. Off: Godot uses its shared materials by name, and files stay small",
	)
	water_collection: StringProperty(
		name="Water Collection",
		default="Water",
		description="Flat mesh planes in this collection are exported with the chunks as water",
	)
	props_collection: StringProperty(
		name="Props Collection",
		default="Props",
		description="Objects in this collection (and its sub-collections) are placed as props",
	)
	props_dir: StringProperty(
		name="Prop Library Folder",
		default="//props/",
		subtype="DIR_PATH",
		description="Where Export Prop Library writes one .glb per prop",
	)
	blend_distance: FloatProperty(
		name="Blend Distance (m)",
		default=8.0,
		min=0.0,
		description="How far inward Match Edges eases the terrain toward the neighbour's edge",
	)
	brush_height: FloatProperty(name="Height (m)", default=0.0, description="Target height for the Set Height brush (Ctrl+click terrain to sample)")
	brush_radius: FloatProperty(name="Radius (m)", default=6.0, min=0.5, max=200.0)
	brush_strength: FloatProperty(name="Strength", default=0.3, min=0.01, max=1.0)


def _cell_range(lo: float, hi: float, size: float) -> tuple[int, int]:
	"""Grid cells (centred on multiples of size) overlapped by [lo, hi]."""
	half = size / 2.0
	first = math.floor((lo + half) / size + EPS)
	last = math.floor((hi + half) / size - EPS)
	return first, last


def _key(x: float, y: float) -> tuple[int, int]:
	return (round(x * 1000), round(y * 1000))


def _world_uvs(bm, tile: float) -> None:
	"""Planar UVs from world X/Y so textures tile seamlessly across chunks."""
	uv = bm.loops.layers.uv.verify()
	for face in bm.faces:
		for loop in face.loops:
			loop[uv].uv = (loop.vert.co.x / tile, loop.vert.co.y / tile)


def _add_grid(bm, s) -> tuple[int, int]:
	"""Adds the chunks described by the settings to bm (world-space coordinates).
	Vertices that already exist at a grid position are reused, so new chunks weld
	onto existing ones and keep their sculpted heights. Returns (new faces, skipped faces)."""
	size, step = s.chunk_size, s.spacing
	per_chunk = round(size / step)
	nx, ny = per_chunk * s.columns, per_chunk * s.rows
	half = size / 2.0
	x0 = s.start_i * size - half  # west edge
	y0 = -s.start_j * size + half  # north edge (Blender +Y)

	existing = {_key(v.co.x, v.co.y): v for v in bm.verts}
	grid = []
	for r in range(ny + 1):
		row = []
		for c in range(nx + 1):
			x, y = x0 + c * step, y0 - r * step
			v = existing.get(_key(x, y))
			if v is None:
				v = bm.verts.new((x, y, 0.0))
			row.append(v)
		grid.append(row)

	added = skipped = 0
	for r in range(ny):
		for c in range(nx):
			# counter-clockwise seen from above so normals face up
			quad = (grid[r + 1][c], grid[r + 1][c + 1], grid[r][c + 1], grid[r][c])
			if bm.faces.get(quad) is not None:
				skipped += 1
				continue
			bm.faces.new(quad)
			added += 1
	return added, skipped


def _check_spacing(op, s) -> bool:
	if abs(round(s.chunk_size / s.spacing) * s.spacing - s.chunk_size) > EPS:
		op.report({"ERROR"}, "Chunk size must be a whole multiple of vertex spacing")
		return False
	return True


class TITAMAS_OT_new_terrain(bpy.types.Operator):
	bl_idname = "titamas.new_terrain"
	bl_label = "New Terrain"
	bl_description = "Add a new flat master terrain covering the chosen chunks"
	bl_options = {"REGISTER", "UNDO"}

	def execute(self, context):
		s = context.scene.titamas_terrain
		if not _check_spacing(self, s):
			return {"CANCELLED"}
		bm = bmesh.new()
		added, _ = _add_grid(bm, s)
		_world_uvs(bm, s.uv_tile)
		mesh = bpy.data.meshes.new("TerrainMaster")
		bm.to_mesh(mesh)
		bm.free()
		obj = bpy.data.objects.new("TerrainMaster", mesh)
		context.collection.objects.link(obj)
		for o in context.selected_objects:
			o.select_set(False)
		obj.select_set(True)
		context.view_layer.objects.active = obj

		if s.lock_sculpt:
			sculpt = context.scene.tool_settings.sculpt
			for attr in ("lock_x", "lock_y"):
				if hasattr(sculpt, attr):
					setattr(sculpt, attr, True)

		self.report({"INFO"}, f"New terrain: {s.columns} x {s.rows} chunks ({added * 2} triangles)")
		return {"FINISHED"}


class TITAMAS_OT_extend_terrain(bpy.types.Operator):
	bl_idname = "titamas.extend_terrain"
	bl_label = "Add Chunks to Terrain"
	bl_description = "Grow the selected master terrain with the chosen chunks, welded to its existing edges"
	bl_options = {"REGISTER", "UNDO"}

	@classmethod
	def poll(cls, context):
		obj = context.active_object
		return obj is not None and obj.type == "MESH"

	def execute(self, context):
		s = context.scene.titamas_terrain
		obj = context.active_object
		if not _check_spacing(self, s):
			return {"CANCELLED"}
		if obj.matrix_world != Matrix.Identity(4):
			self.report({"ERROR"}, "Apply the terrain's transforms first (Ctrl+A > All Transforms)")
			return {"CANCELLED"}
		if obj.mode != "OBJECT":
			bpy.ops.object.mode_set(mode="OBJECT")

		bm = bmesh.new()
		bm.from_mesh(obj.data)
		added, skipped = _add_grid(bm, s)
		_world_uvs(bm, s.uv_tile)
		bm.to_mesh(obj.data)
		bm.free()
		obj.data.update()

		if added == 0:
			self.report({"WARNING"}, "Those chunks already exist on this terrain")
		else:
			msg = f"Added {added * 2} triangles"
			if skipped:
				msg += f" (skipped {skipped} faces that already existed)"
			self.report({"INFO"}, msg)
		return {"FINISHED"}


class TITAMAS_OT_export_chunks(bpy.types.Operator):
	bl_idname = "titamas.export_chunks"
	bl_label = "Export Chunks"
	bl_description = "Cut a copy of the active terrain on the chunk grid and export each chunk as a .glb"

	@classmethod
	def poll(cls, context):
		obj = context.active_object
		return obj is not None and obj.type == "MESH"

	def execute(self, context):
		s = context.scene.titamas_terrain
		master = context.active_object
		size = s.chunk_size
		half = size / 2.0

		if s.export_dir.startswith("//") and not bpy.data.filepath:
			self.report({"ERROR"}, "Save the .blend first (the export folder is relative to it)")
			return {"CANCELLED"}
		out_dir = bpy.path.abspath(s.export_dir)
		os.makedirs(out_dir, exist_ok=True)

		if master.mode != "OBJECT":
			bpy.ops.object.mode_set(mode="OBJECT")  # commits sculpt/edit changes

		# World-space copy of the terrain, modifiers included.
		depsgraph = context.evaluated_depsgraph_get()
		src = bmesh.new()
		src.from_object(master.evaluated_get(depsgraph), depsgraph)
		src.transform(master.matrix_world)

		xs = [v.co.x for v in src.verts]
		ys = [v.co.y for v in src.verts]
		i_first, i_last = _cell_range(min(xs), max(xs), size)
		k_first, k_last = _cell_range(min(ys), max(ys), size)  # k = Blender Y cell, J = -k

		# Cut exactly on every grid line so no face crosses a chunk border.
		for i in range(i_first, i_last + 2):
			geom = src.verts[:] + src.edges[:] + src.faces[:]
			bmesh.ops.bisect_plane(src, geom=geom, dist=EPS, plane_co=(i * size - half, 0, 0), plane_no=(1, 0, 0))
		for k in range(k_first, k_last + 2):
			geom = src.verts[:] + src.edges[:] + src.faces[:]
			bmesh.ops.bisect_plane(src, geom=geom, dist=EPS, plane_co=(0, k * size - half, 0), plane_no=(0, 1, 0))

		# Water planes, cut on the same grid.
		water_src = []
		water_coll = bpy.data.collections.get(s.water_collection)
		if water_coll:
			for wobj in water_coll.all_objects:
				if wobj.type != "MESH":
					continue
				wbm = bmesh.new()
				wbm.from_object(wobj.evaluated_get(depsgraph), depsgraph)
				wbm.transform(wobj.matrix_world)
				for i in range(i_first, i_last + 2):
					geom = wbm.verts[:] + wbm.edges[:] + wbm.faces[:]
					bmesh.ops.bisect_plane(wbm, geom=geom, dist=EPS, plane_co=(i * size - half, 0, 0), plane_no=(1, 0, 0))
				for k in range(k_first, k_last + 2):
					geom = wbm.verts[:] + wbm.edges[:] + wbm.faces[:]
					bmesh.ops.bisect_plane(wbm, geom=geom, dist=EPS, plane_co=(0, k * size - half, 0), plane_no=(0, 1, 0))
				water_src.append((wobj.name, wbm, list(wobj.data.materials)))

		# Props, grouped by the chunk their origin sits in.
		props_by_cell = {}
		for pobj in _prop_objects(s):
			loc = pobj.matrix_world.translation
			i, k = round(loc.x / size), round(loc.y / size)
			props_by_cell.setdefault((i, -k), []).append(_prop_entry(pobj, i, k, size))
		prop_count = 0

		prev_selected = list(context.selected_objects)
		exported, partial = [], []
		water_pieces = 0

		for i in range(i_first, i_last + 1):
			for k in range(k_first, k_last + 1):
				cx, cy = i * size, k * size
				j = -k
				cell = src.copy()
				outside = [
					f for f in cell.faces
					if not (abs(f.calc_center_median().x - cx) < half and abs(f.calc_center_median().y - cy) < half)
				]
				bmesh.ops.delete(cell, geom=outside, context="FACES")
				if not cell.faces:
					cell.free()
					continue
				_world_uvs(cell, s.uv_tile)  # before moving, so UVs stay world-aligned
				_paint_to_uv(cell)
				bmesh.ops.translate(cell, verts=cell.verts, vec=(-cx, -cy, 0.0))

				w = max(v.co.x for v in cell.verts) - min(v.co.x for v in cell.verts)
				h = max(v.co.y for v in cell.verts) - min(v.co.y for v in cell.verts)
				name = f"chunk_{i}_{j}"
				if w < size - 0.01 or h < size - 0.01:
					partial.append(name)

				mesh = bpy.data.meshes.new(name)
				cell.to_mesh(mesh)
				cell.free()
				_activate_paint(mesh)
				for mat in master.data.materials:
					mesh.materials.append(mat)
				obj = bpy.data.objects.new(name + ("-col" if s.add_collision else ""), mesh)
				context.scene.collection.objects.link(obj)
				temp = [obj]

				# This cell's piece of each water plane.
				for wname, wbm, wmats in water_src:
					piece = wbm.copy()
					out = [
						f for f in piece.faces
						if not (abs(f.calc_center_median().x - cx) < half and abs(f.calc_center_median().y - cy) < half)
					]
					bmesh.ops.delete(piece, geom=out, context="FACES")
					if not piece.faces:
						piece.free()
						continue
					bmesh.ops.translate(piece, verts=piece.verts, vec=(-cx, -cy, 0.0))
					wmesh = bpy.data.meshes.new(f"{wname}-water")
					piece.to_mesh(wmesh)
					piece.free()
					for mat in wmats:
						wmesh.materials.append(mat)
					wo = bpy.data.objects.new(f"{wname}-water", wmesh)
					context.scene.collection.objects.link(wo)
					temp.append(wo)
					water_pieces += 1

				for o in context.selected_objects:
					o.select_set(False)
				for o in temp:
					o.select_set(True)
				context.view_layer.objects.active = obj
				_export_glb(os.path.join(out_dir, name + ".glb"), s.include_textures)
				props_path = os.path.join(out_dir, name + ".props.json")
				placed = props_by_cell.get((i, j), [])
				if placed:
					with open(props_path, "w") as fh:
						json.dump({"props": placed}, fh, indent=0)
					prop_count += len(placed)
				elif os.path.exists(props_path):
					os.remove(props_path)  # props were removed from this chunk
				for o in temp:
					m = o.data
					bpy.data.objects.remove(o)
					bpy.data.meshes.remove(m)
				exported.append(name)

		src.free()
		for _, wbm, _ in water_src:
			wbm.free()
		for o in context.selected_objects:
			o.select_set(False)
		for o in prev_selected:
			if o.name in bpy.data.objects:
				o.select_set(True)
		context.view_layer.objects.active = master

		msg = f"Exported {len(exported)} chunks to {out_dir}"
		if water_pieces:
			msg += f", {water_pieces} water pieces"
		if prop_count:
			msg += f", {prop_count} props"
		if partial:
			msg += f" | Partial (terrain doesn't fill the cell): {', '.join(partial)}"
			self.report({"WARNING"}, msg)
		else:
			self.report({"INFO"}, msg)
		return {"FINISHED"}


def _paint_to_uv(bm) -> None:
	"""Copy the TerrainPaint weights into a second UV map: U = dirt, V = cliff (stored as
	1 - cliff because glTF flips V, so Godot reads UV2 = (dirt, cliff); missing data reads
	as all grass). Weights are normalised so grass = 1 - dirt - cliff."""
	vert_layer = bm.verts.layers.float_color.get(PAINT_ATTR) or bm.verts.layers.color.get(PAINT_ATTR)
	loop_layer = bm.loops.layers.float_color.get(PAINT_ATTR) or bm.loops.layers.color.get(PAINT_ATTR)
	if vert_layer is None and loop_layer is None:
		return
	uv = bm.loops.layers.uv.get("TerrainPaintUV") or bm.loops.layers.uv.new("TerrainPaintUV")
	for face in bm.faces:
		for loop in face.loops:
			c = loop[loop_layer] if loop_layer is not None else loop.vert[vert_layer]
			r, g, b = max(c[0], 0.0), max(c[1], 0.0), max(c[2], 0.0)
			total = r + g + b
			if total < 1e-6:
				r, g, b, total = 1.0, 0.0, 0.0, 1.0
			loop[uv].uv = (g / total, 1.0 - b / total)


# Blender (Z up) -> Godot (Y up): x -> x, z -> y, y -> -z
_TO_GODOT = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))


def prop_name(obj) -> str:
	"""Prop identifier: the shared mesh name for linked duplicates, otherwise the object's
	name without Blender's .001 suffix. Lowercase, filesystem-safe."""
	base = obj.data.name if obj.data.users > 1 else re.sub(r"\.\d+$", "", obj.name)
	return re.sub(r"[^a-z0-9_]+", "_", base.lower()).strip("_") or "prop"


def _prop_objects(s) -> list:
	coll = bpy.data.collections.get(s.props_collection)
	if coll is None:
		return []
	return [o for o in coll.all_objects if o.type == "MESH"]


def _prop_entry(obj, i: int, k: int, size: float) -> dict:
	"""Placement in Godot chunk space: position relative to the chunk centre, and the
	3x3 basis as three column vectors (rotation and scale)."""
	m = obj.matrix_world
	loc = m.translation
	pos = (loc.x - i * size, loc.z, -(loc.y - k * size))
	basis = _TO_GODOT @ m.to_3x3() @ _TO_GODOT.transposed()
	cols = [[round(basis[r][c], 5) for r in range(3)] for c in range(3)]
	return {"name": prop_name(obj), "pos": [round(v, 4) for v in pos], "basis": cols}


def _activate_paint(mesh) -> None:
	"""Make the paint layer the mesh's active/render colours so the glTF exporter writes it."""
	attrs = mesh.color_attributes
	if PAINT_ATTR not in attrs:
		return
	for i, a in enumerate(attrs):
		if a.name == PAINT_ATTR:
			try:
				attrs.active_color_index = i
				attrs.render_color_index = i
			except AttributeError:
				attrs.active_color = a


def _export_glb(path: str, include_textures: bool) -> None:
	kwargs = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
	# Options whose names differ between Blender versions; unknown ones are dropped.
	extras = {"export_colors": True, "export_vertex_color": "ACTIVE"}
	if not include_textures:
		extras["export_image_format"] = "NONE"
	while True:
		try:
			bpy.ops.export_scene.gltf(**kwargs, **extras)
			return
		except TypeError as err:
			bad = next((k for k in extras if f'"{k}"' in str(err) or k in str(err)), None)
			if bad is None:
				raise
			del extras[bad]


def _first_image(material):
	if material and material.use_nodes:
		for node in material.node_tree.nodes:
			if node.type == "TEX_IMAGE" and node.image:
				return node.image
	return None


def _build_preview_material():
	"""A Blender material that previews the painted mix (Godot uses its own shader)."""
	mat = bpy.data.materials.get("terrain") or bpy.data.materials.new("terrain")
	mat.use_nodes = True
	nt = mat.node_tree
	nt.nodes.clear()
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	out.location = (900, 0)
	bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
	bsdf.location = (600, 0)
	bsdf.inputs["Roughness"].default_value = 1.0
	nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

	paint = nt.nodes.new("ShaderNodeVertexColor")
	paint.layer_name = PAINT_ATTR
	paint.location = (-600, -300)
	sep = nt.nodes.new("ShaderNodeSeparateColor")
	sep.location = (-400, -300)
	nt.links.new(paint.outputs["Color"], sep.inputs["Color"])

	texs = []
	for i, name in enumerate(LAYER_NAMES):
		tex = nt.nodes.new("ShaderNodeTexImage")
		tex.location = (-400, 300 - i * 260)
		tex.interpolation = "Closest"
		tex.image = _first_image(bpy.data.materials.get(name))
		tex.label = name
		texs.append(tex)

	def math(op, a, b, loc):
		n = nt.nodes.new("ShaderNodeMath")
		n.operation = op
		n.location = loc
		for sock, val in ((n.inputs[0], a), (n.inputs[1], b)):
			if isinstance(val, float):
				sock.default_value = val
			else:
				nt.links.new(val, sock)
		return n.outputs[0]

	r, g, b = sep.outputs[0], sep.outputs[1], sep.outputs[2]
	rg = math("ADD", r, g, (-200, -400))
	rgb = math("ADD", rg, b, (-200, -520))
	f1 = math("DIVIDE", g, math("ADD", rg, 0.0001, (0, -400)), (150, -400))
	f2 = math("DIVIDE", b, math("ADD", rgb, 0.0001, (0, -520)), (150, -520))

	def mix(fac, a, b2, loc):
		n = nt.nodes.new("ShaderNodeMixRGB")
		n.location = loc
		nt.links.new(fac, n.inputs["Fac"])
		nt.links.new(a, n.inputs["Color1"])
		nt.links.new(b2, n.inputs["Color2"])
		return n.outputs["Color"]

	grass_dirt = mix(f1, texs[0].outputs["Color"], texs[1].outputs["Color"], (300, 200))
	final = mix(f2, grass_dirt, texs[2].outputs["Color"], (450, 100))
	nt.links.new(final, bsdf.inputs["Base Color"])
	return mat


class TITAMAS_OT_setup_painting(bpy.types.Operator):
	bl_idname = "titamas.setup_painting"
	bl_label = "Setup Terrain Painting"
	bl_description = (
		"Add the TerrainPaint layer (red = grass, green = dirt, blue = cliff), fill it from the "
		"materials already on the terrain, and switch the terrain to one 'terrain' material"
	)
	bl_options = {"REGISTER", "UNDO"}

	@classmethod
	def poll(cls, context):
		obj = context.active_object
		return obj is not None and obj.type == "MESH"

	def execute(self, context):
		obj = context.active_object
		if obj.mode != "OBJECT":
			bpy.ops.object.mode_set(mode="OBJECT")
		mesh = obj.data
		created = PAINT_ATTR not in mesh.color_attributes
		if created:
			attr = mesh.color_attributes.new(PAINT_ATTR, "FLOAT_COLOR", "POINT")
			# Convert the per-face materials into paint: each vertex takes the share of
			# its surrounding faces that used grass / dirt / cliff.
			slot_layer = []
			for slot in obj.material_slots:
				name = (slot.material.name if slot.material else "").lower()
				slot_layer.append(next((ch for key, ch in LAYER_KEYWORDS if key in name), 0))
			acc = [[0.0, 0.0, 0.0] for _ in mesh.vertices]
			for poly in mesh.polygons:
				ch = slot_layer[poly.material_index] if poly.material_index < len(slot_layer) else 0
				for vi in poly.vertices:
					acc[vi][ch] += 1.0
			for vi, w in enumerate(acc):
				total = sum(w) or 1.0
				attr.data[vi].color = (w[0] / total, w[1] / total, w[2] / total, 1.0)
		_activate_paint(mesh)

		# Keep the old materials in the file (they hold the textures the preview uses).
		for slot in obj.material_slots:
			if slot.material:
				slot.material.use_fake_user = True
		preview = _build_preview_material()
		mesh.materials.clear()
		mesh.materials.append(preview)
		self.report({"INFO"}, ("Created and filled" if created else "Kept existing") + " TerrainPaint layer; terrain now uses the 'terrain' material")
		return {"FINISHED"}


class TITAMAS_OT_paint_layer(bpy.types.Operator):
	bl_idname = "titamas.paint_layer"
	bl_label = "Paint Layer"
	bl_description = "Switch to Vertex Paint with the brush set to this ground layer"
	bl_options = {"REGISTER"}

	layer: IntProperty(default=0)

	@classmethod
	def poll(cls, context):
		obj = context.active_object
		return obj is not None and obj.type == "MESH" and PAINT_ATTR in obj.data.color_attributes

	def execute(self, context):
		obj = context.active_object
		_activate_paint(obj.data)
		if obj.mode != "VERTEX_PAINT":
			bpy.ops.object.mode_set(mode="VERTEX_PAINT")
		color = [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)][self.layer]
		ts = context.tool_settings
		try:
			ts.unified_paint_settings.color = color
		except AttributeError:
			pass
		brush = ts.vertex_paint.brush if ts.vertex_paint else None
		if brush:
			brush.color = color
		self.report({"INFO"}, f"Painting {LAYER_NAMES[self.layer]}")
		return {"FINISHED"}


# --- Reading exported chunks (no Blender import needed) ------------------------

CHUNK_NAME = re.compile(r"^chunk_(-?\d+)_(-?\d+)\.glb$")


def read_glb_triangles(path: str) -> list:
	"""Triangles [(p0, p1, p2), ...] of every mesh in a .glb, positions in glTF space
	(Y up, node transforms applied for translation and scale)."""
	with open(path, "rb") as f:
		data = f.read()
	json_len = struct.unpack_from("<I", data, 12)[0]
	doc = json.loads(data[20:20 + json_len])
	bin_start = 20 + json_len + 8
	binary = data[bin_start:]

	def accessor(index):
		acc = doc["accessors"][index]
		view = doc["bufferViews"][acc["bufferView"]]
		offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
		comp = {5126: ("f", 4), 5123: ("H", 2), 5125: ("I", 4), 5121: ("B", 1)}[acc["componentType"]]
		count_per = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
		stride = view.get("byteStride", comp[1] * count_per)
		fmt = "<" + comp[0] * count_per
		return [struct.unpack_from(fmt, binary, offset + i * stride) for i in range(acc["count"])]

	tris = []
	for node in doc.get("nodes", []):
		if "mesh" not in node:
			continue
		t = node.get("translation", [0, 0, 0])
		sc = node.get("scale", [1, 1, 1])
		for prim in doc["meshes"][node["mesh"]]["primitives"]:
			pos = [(p[0] * sc[0] + t[0], p[1] * sc[1] + t[1], p[2] * sc[2] + t[2]) for p in accessor(prim["attributes"]["POSITION"])]
			idx = [i[0] for i in accessor(prim["indices"])] if "indices" in prim else list(range(len(pos)))
			for k in range(0, len(idx) - 2, 3):
				tris.append((pos[idx[k]], pos[idx[k + 1]], pos[idx[k + 2]]))
	return tris


def exported_cells(folder: str) -> dict:
	"""{(I, J): path} for chunk files in a folder."""
	out = {}
	if os.path.isdir(folder):
		for name in os.listdir(folder):
			m = CHUNK_NAME.match(name)
			if m:
				out[(int(m.group(1)), int(m.group(2)))] = os.path.join(folder, name)
	return out


def border_profile(tris: list, cell: tuple, side: str, size: float) -> list:
	"""Height profile along one side of an exported chunk, in Blender world coordinates.
	side: "west" / "east" (line X = const, parameter = world Y) or "north" / "south"
	(line Y = const, parameter = world X). Returns sorted segments [(s0, h0, s1, h1)]."""
	half = size / 2.0
	ci, cj = cell
	segs = []
	for tri in tris:
		for a, b in ((tri[0], tri[1]), (tri[1], tri[2]), (tri[2], tri[0])):
			# glTF chunk space -> Blender world: X = x + I*size, Y = -(z + J*size), Z = y
			if side in ("west", "east"):
				line = -half if side == "west" else half
				if abs(a[0] - line) > 1e-3 or abs(b[0] - line) > 1e-3:
					continue
				pa, pb = -(a[2] + cj * size), -(b[2] + cj * size)
			else:
				line = -half if side == "north" else half  # north = smaller glTF z
				if abs(a[2] - line) > 1e-3 or abs(b[2] - line) > 1e-3:
					continue
				pa, pb = a[0] + ci * size, b[0] + ci * size
			if abs(pa - pb) < 1e-6:
				continue
			if pa < pb:
				segs.append((pa, a[1], pb, b[1]))
			else:
				segs.append((pb, b[1], pa, a[1]))
	segs.sort()
	return segs


def profile_height(segs: list, s: float):
	for s0, h0, s1, h1 in segs:
		if s0 - 1e-4 <= s <= s1 + 1e-4:
			return h0 + (h1 - h0) * (s - s0) / (s1 - s0)
	return None


class TITAMAS_OT_match_edges(bpy.types.Operator):
	bl_idname = "titamas.match_edges"
	bl_label = "Match Edges to Exported Chunks"
	bl_description = (
		"Snap this terrain's borders to the heights of already-exported neighbouring chunks "
		"(from another region) and ease the terrain toward them"
	)
	bl_options = {"REGISTER", "UNDO"}

	@classmethod
	def poll(cls, context):
		obj = context.active_object
		return obj is not None and obj.type == "MESH"

	def execute(self, context):
		s = context.scene.titamas_terrain
		obj = context.active_object
		size = s.chunk_size
		half = size / 2.0
		if obj.matrix_world != Matrix.Identity(4):
			self.report({"ERROR"}, "Apply the terrain's transforms first (Ctrl+A > All Transforms)")
			return {"CANCELLED"}
		if obj.mode != "OBJECT":
			bpy.ops.object.mode_set(mode="OBJECT")
		folder = bpy.path.abspath(s.export_dir)
		files = exported_cells(folder)
		if not files:
			self.report({"ERROR"}, f"No exported chunks found in {folder}")
			return {"CANCELLED"}

		bm = bmesh.new()
		bm.from_mesh(obj.data)
		# Cells this terrain covers (by face centres). k = Blender Y cell, J = -k.
		mine = set()
		for f in bm.faces:
			c = f.calc_center_median()
			mine.add((round(c.x / size), -round(c.y / size)))

		# Neighbouring exported cells that aren't part of this terrain.
		# For each: which line we share, and the neighbour's side along it.
		edges = []  # (axis, line, s_min, s_max, profile)
		for (i, j) in mine:
			for di, dj, my_side, their_side in ((1, 0, "east", "west"), (-1, 0, "west", "east"), (0, 1, "south", "north"), (0, -1, "north", "south")):
				n = (i + di, j + dj)
				if n in mine or n not in files:
					continue
				prof = border_profile(read_glb_triangles(files[n]), n, their_side, size)
				if not prof:
					continue
				if my_side in ("east", "west"):
					line = i * size + (half if my_side == "east" else -half)
					smid = -j * size
					edges.append(("x", line, smid - half, smid + half, prof))
				else:
					line = -j * size + (-half if my_side == "south" else half)
					smid = i * size
					edges.append(("y", line, smid - half, smid + half, prof))
		if not edges:
			bm.free()
			self.report({"WARNING"}, "No exported neighbours next to this terrain's chunks")
			return {"CANCELLED"}

		# Snap border vertices, then ease the inside toward the correction.
		moved = 0
		blend = max(s.blend_distance, 0.0)
		for axis, line, smin, smax, prof in edges:
			corrections = []  # (s, delta) along this edge
			for v in bm.verts:
				on_line = v.co.x if axis == "x" else v.co.y
				along = v.co.y if axis == "x" else v.co.x
				if abs(on_line - line) < 1e-3 and smin - 1e-3 <= along <= smax + 1e-3:
					h = profile_height(prof, along)
					if h is not None:
						corrections.append((along, h - v.co.z))
						v.co.z = h
						moved += 1
			if blend <= 0.0 or not corrections:
				continue
			corrections.sort()
			for v in bm.verts:
				on_line = v.co.x if axis == "x" else v.co.y
				along = v.co.y if axis == "x" else v.co.x
				d = abs(on_line - line)
				if d < 1e-3 or d >= blend or not (smin <= along <= smax):
					continue
				# Correction at this point along the edge (linear between border vertices).
				delta = corrections[0][1]
				for (s0, d0), (s1, d1) in zip(corrections, corrections[1:]):
					if s0 <= along <= s1 and s1 > s0:
						delta = d0 + (d1 - d0) * (along - s0) / (s1 - s0)
						break
				else:
					if along > corrections[-1][0]:
						delta = corrections[-1][1]
				w = 1.0 - d / blend
				v.co.z += delta * w * w * (3.0 - 2.0 * w)  # smoothstep falloff

		bm.to_mesh(obj.data)
		bm.free()
		obj.data.update()
		self.report({"INFO"}, f"Matched {moved} border vertices along {len(edges)} edges")
		return {"FINISHED"}


class TITAMAS_OT_set_height_brush(bpy.types.Operator):
	bl_idname = "titamas.set_height_brush"
	bl_label = "Set Height Brush"
	bl_description = (
		"Paint the terrain toward a set height. Ctrl+click samples a height, Wheel = radius, "
		"Shift+Wheel = strength, Esc / Right-click / Enter = done"
	)
	bl_options = {"REGISTER", "UNDO"}

	@classmethod
	def poll(cls, context):
		obj = context.active_object
		return obj is not None and obj.type == "MESH" and context.area and context.area.type == "VIEW_3D"

	def invoke(self, context, event):
		obj = context.active_object
		if obj.matrix_world != Matrix.Identity(4):
			self.report({"ERROR"}, "Apply the terrain's transforms first (Ctrl+A > All Transforms)")
			return {"CANCELLED"}
		if obj.mode != "OBJECT":
			bpy.ops.object.mode_set(mode="OBJECT")
		self.obj = obj
		self.mesh = obj.data
		n = len(self.mesh.vertices)
		self.kd = KDTree(n)
		for i, v in enumerate(self.mesh.vertices):
			self.kd.insert((v.co.x, v.co.y, 0.0), i)
		self.kd.balance()
		self.hit = None
		self.painting = False
		self._handle = bpy.types.SpaceView3D.draw_handler_add(self._draw, (context,), "WINDOW", "POST_VIEW")
		context.window_manager.modal_handler_add(self)
		self._update_header(context)
		return {"RUNNING_MODAL"}

	def modal(self, context, event):
		s = context.scene.titamas_terrain
		context.area.tag_redraw()
		if event.type == "MOUSEMOVE":
			self.hit = self._raycast(context, event)
			if self.painting and self.hit:
				self._dab(s)
			return {"RUNNING_MODAL"}
		if event.type == "LEFTMOUSE":
			if event.value == "PRESS":
				self.hit = self._raycast(context, event)
				if self.hit is None:
					return {"RUNNING_MODAL"}
				if event.ctrl:
					s.brush_height = round(self.hit.z, 2)
					self._update_header(context)
				else:
					self.painting = True
					self._dab(s)
			elif event.value == "RELEASE" and self.painting:
				self.painting = False
				bpy.ops.ed.undo_push(message="Set Height stroke")
			return {"RUNNING_MODAL"}
		if event.type in {"WHEELUPMOUSE", "WHEELDOWNMOUSE"} and not event.ctrl:
			up = event.type == "WHEELUPMOUSE"
			if event.shift:
				s.brush_strength = min(max(s.brush_strength + (0.05 if up else -0.05), 0.01), 1.0)
			else:
				s.brush_radius = min(max(s.brush_radius * (1.1 if up else 1 / 1.1), 0.5), 200.0)
			self._update_header(context)
			return {"RUNNING_MODAL"}
		if event.type in {"ESC", "RIGHTMOUSE", "RET", "NUMPAD_ENTER"} and event.value == "PRESS":
			self._finish(context)
			return {"FINISHED"}
		return {"PASS_THROUGH"}  # let the view be orbited, panned and zoomed

	def _finish(self, context):
		if self._handle:
			bpy.types.SpaceView3D.draw_handler_remove(self._handle, "WINDOW")
			self._handle = None
		context.area.header_text_set(None)
		context.area.tag_redraw()

	def _update_header(self, context):
		s = context.scene.titamas_terrain
		context.area.header_text_set(
			f"Set Height {s.brush_height:.2f} m   Radius {s.brush_radius:.1f} m   Strength {s.brush_strength:.2f}"
			"   |   Drag: paint   Ctrl+click: sample height   Wheel: radius   Shift+Wheel: strength   Esc: done"
		)

	def _height_at(self, x, y):
		_, index, _ = self.kd.find((x, y, 0.0))
		return self.mesh.vertices[index].co.z

	def _raycast(self, context, event):
		"""Where the mouse ray meets the terrain. The terrain is a height field, so step
		along the ray and refine where it drops below the surface."""
		region, rv3d = context.region, context.region_data
		coord = (event.mouse_region_x, event.mouse_region_y)
		origin = view3d_utils.region_2d_to_origin_3d(region, rv3d, coord)
		direction = view3d_utils.region_2d_to_vector_3d(region, rv3d, coord).normalized()
		if direction.z >= -1e-4:
			return None  # looking at the sky
		step = max(self.obj.dimensions.x, self.obj.dimensions.y) / 400.0
		step = max(step, 0.25)
		t = 0.0
		prev = origin.copy()
		for _ in range(4000):
			t += step
			p = origin + direction * t
			if p.z <= self._height_at(p.x, p.y):
				lo, hi = prev, p
				for _ in range(16):
					mid = (lo + hi) * 0.5
					if mid.z <= self._height_at(mid.x, mid.y):
						hi = mid
					else:
						lo = mid
				return hi
			prev = p
		return None

	def _dab(self, s):
		target = s.brush_height
		radius = s.brush_radius
		for _, index, dist in self.kd.find_range((self.hit.x, self.hit.y, 0.0), radius):
			f = 1.0 - (dist / radius) ** 2
			f = f * f
			v = self.mesh.vertices[index]
			v.co.z += (target - v.co.z) * s.brush_strength * f
		self.mesh.update()

	def _draw(self, context):
		if self.hit is None:
			return
		s = context.scene.titamas_terrain
		pts = []
		for k in range(49):
			a = k / 48.0 * math.tau
			x = self.hit.x + math.cos(a) * s.brush_radius
			y = self.hit.y + math.sin(a) * s.brush_radius
			pts.append((x, y, self._height_at(x, y) + 0.1))
		ring = [(self.hit.x + math.cos(k / 24.0 * math.tau) * 0.3, self.hit.y + math.sin(k / 24.0 * math.tau) * 0.3, s.brush_height) for k in range(25)]
		shader = gpu.shader.from_builtin("UNIFORM_COLOR")
		gpu.state.line_width_set(2.0)
		gpu.state.depth_test_set("NONE")
		shader.uniform_float("color", (1.0, 0.8, 0.2, 1.0))
		batch_for_shader(shader, "LINE_STRIP", {"pos": pts}).draw(shader)
		# Small ring at the target height above/below the cursor.
		shader.uniform_float("color", (0.3, 0.8, 1.0, 1.0))
		batch_for_shader(shader, "LINE_STRIP", {"pos": ring}).draw(shader)
		gpu.state.line_width_set(1.0)


class TITAMAS_OT_export_props(bpy.types.Operator):
	bl_idname = "titamas.export_props"
	bl_label = "Export Prop Library"
	bl_description = "Export each distinct prop in the Props collection once, as <name>.glb with its textures"

	def execute(self, context):
		s = context.scene.titamas_terrain
		if s.props_dir.startswith("//") and not bpy.data.filepath:
			self.report({"ERROR"}, "Save the .blend first (the folder is relative to it)")
			return {"CANCELLED"}
		out_dir = bpy.path.abspath(s.props_dir)
		os.makedirs(out_dir, exist_ok=True)
		if context.active_object and context.active_object.mode != "OBJECT":
			bpy.ops.object.mode_set(mode="OBJECT")

		# One representative object per prop name.
		reps = {}
		for obj in _prop_objects(s):
			reps.setdefault(prop_name(obj), obj)
		if not reps:
			self.report({"WARNING"}, f"No mesh objects in the '{s.props_collection}' collection")
			return {"CANCELLED"}

		prev_selected = list(context.selected_objects)
		prev_active = context.view_layer.objects.active
		for name, src in reps.items():
			# A temporary object with the same mesh at the origin, unrotated, unscaled.
			tmp = bpy.data.objects.new(name, src.data)
			context.scene.collection.objects.link(tmp)
			for o in context.selected_objects:
				o.select_set(False)
			tmp.select_set(True)
			context.view_layer.objects.active = tmp
			_export_glb(os.path.join(out_dir, name + ".glb"), include_textures=True)
			bpy.data.objects.remove(tmp)

		for o in context.selected_objects:
			o.select_set(False)
		for o in prev_selected:
			if o.name in bpy.data.objects:
				o.select_set(True)
		context.view_layer.objects.active = prev_active
		self.report({"INFO"}, f"Exported {len(reps)} props to {out_dir}: {', '.join(sorted(reps))}")
		return {"FINISHED"}


class TITAMAS_PT_terrain(bpy.types.Panel):
	bl_label = "Terrain Chunks"
	bl_idname = "TITAMAS_PT_terrain"
	bl_space_type = "VIEW_3D"
	bl_region_type = "UI"
	bl_category = "Titamas"

	def draw(self, context):
		s = context.scene.titamas_terrain
		layout = self.layout

		box = layout.box()
		box.label(text="1. Choose chunks", icon="MESH_GRID")
		row = box.row(align=True)
		row.prop(s, "start_i")
		row.prop(s, "start_j")
		box.prop(s, "columns")
		box.prop(s, "rows")
		box.operator(TITAMAS_OT_extend_terrain.bl_idname, icon="ADD")
		box.operator(TITAMAS_OT_new_terrain.bl_idname, icon="MESH_PLANE")
		box.prop(s, "lock_sculpt")

		box = layout.box()
		box.label(text="2. Shape", icon="SCULPTMODE_HLT")
		box.prop(s, "brush_height")
		row = box.row(align=True)
		row.prop(s, "brush_radius")
		row.prop(s, "brush_strength")
		box.operator(TITAMAS_OT_set_height_brush.bl_idname, icon="BRUSH_DATA")
		box.prop(s, "blend_distance")
		box.operator(TITAMAS_OT_match_edges.bl_idname, icon="SNAP_EDGE")

		box = layout.box()
		box.label(text="Paint ground", icon="BRUSH_DATA")
		box.operator(TITAMAS_OT_setup_painting.bl_idname, icon="VPAINT_HLT")
		row = box.row(align=True)
		for i, name in enumerate(LAYER_NAMES):
			row.operator(TITAMAS_OT_paint_layer.bl_idname, text=name.title()).layer = i

		box = layout.box()
		box.label(text="3. Export", icon="EXPORT")
		box.prop(s, "export_dir", text="")
		box.prop(s, "add_collision")
		box.prop(s, "include_textures")
		box.prop_search(s, "water_collection", bpy.data, "collections")
		box.prop_search(s, "props_collection", bpy.data, "collections")
		box.operator(TITAMAS_OT_export_chunks.bl_idname, icon="EXPORT")
		box.prop(s, "props_dir", text="")
		box.operator(TITAMAS_OT_export_props.bl_idname, icon="OUTLINER_COLLECTION")

		col = layout.column()
		col.prop(s, "uv_tile")
		col.prop(s, "spacing")
		col.prop(s, "chunk_size")


classes = (
	TitamasTerrainSettings,
	TITAMAS_OT_new_terrain,
	TITAMAS_OT_extend_terrain,
	TITAMAS_OT_export_chunks,
	TITAMAS_OT_match_edges,
	TITAMAS_OT_set_height_brush,
	TITAMAS_OT_setup_painting,
	TITAMAS_OT_paint_layer,
	TITAMAS_OT_export_props,
	TITAMAS_PT_terrain,
)


def register():
	for cls in classes:
		bpy.utils.register_class(cls)
	bpy.types.Scene.titamas_terrain = PointerProperty(type=TitamasTerrainSettings)


def unregister():
	del bpy.types.Scene.titamas_terrain
	for cls in reversed(classes):
		bpy.utils.unregister_class(cls)


if __name__ == "__main__":
	register()
