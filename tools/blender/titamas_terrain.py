bl_info = {
	"name": "Titamas Terrain Chunks",
	"author": "Titamas Online",
	"version": (1, 1, 0),
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

import math
import os

import bmesh
import bpy
from mathutils import Matrix
from bpy.props import BoolProperty, FloatProperty, IntProperty, PointerProperty, StringProperty

EPS = 1e-4


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

		prev_selected = list(context.selected_objects)
		exported, partial = [], []

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
				bmesh.ops.translate(cell, verts=cell.verts, vec=(-cx, -cy, 0.0))

				w = max(v.co.x for v in cell.verts) - min(v.co.x for v in cell.verts)
				h = max(v.co.y for v in cell.verts) - min(v.co.y for v in cell.verts)
				name = f"chunk_{i}_{j}"
				if w < size - 0.01 or h < size - 0.01:
					partial.append(name)

				mesh = bpy.data.meshes.new(name)
				cell.to_mesh(mesh)
				cell.free()
				for mat in master.data.materials:
					mesh.materials.append(mat)
				obj = bpy.data.objects.new(name + ("-col" if s.add_collision else ""), mesh)
				context.scene.collection.objects.link(obj)

				for o in context.selected_objects:
					o.select_set(False)
				obj.select_set(True)
				context.view_layer.objects.active = obj
				bpy.ops.export_scene.gltf(
					filepath=os.path.join(out_dir, name + ".glb"),
					export_format="GLB",
					use_selection=True,
					export_apply=True,
					export_yup=True,
				)
				bpy.data.objects.remove(obj)
				bpy.data.meshes.remove(mesh)
				exported.append(name)

		src.free()
		for o in context.selected_objects:
			o.select_set(False)
		for o in prev_selected:
			if o.name in bpy.data.objects:
				o.select_set(True)
		context.view_layer.objects.active = master

		msg = f"Exported {len(exported)} chunks to {out_dir}"
		if partial:
			msg += f" | Partial (terrain doesn't fill the cell): {', '.join(partial)}"
			self.report({"WARNING"}, msg)
		else:
			self.report({"INFO"}, msg)
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
		box.label(text="2. Sculpt, then export", icon="EXPORT")
		box.prop(s, "export_dir", text="")
		box.prop(s, "add_collision")
		box.operator(TITAMAS_OT_export_chunks.bl_idname, icon="EXPORT")

		col = layout.column()
		col.prop(s, "uv_tile")
		col.prop(s, "spacing")
		col.prop(s, "chunk_size")


classes = (
	TitamasTerrainSettings,
	TITAMAS_OT_new_terrain,
	TITAMAS_OT_extend_terrain,
	TITAMAS_OT_export_chunks,
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
