bl_info = {
	"name": "Titamas Terrain Chunks",
	"author": "Titamas Online",
	"version": (1, 0, 0),
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
# Export never changes your master terrain. It copies it, cuts the copy exactly on the grid
# lines, and saves each cell as chunk_I_J.glb with its origin at the cell centre (height 0)
# and scale applied. Both sides of every seam come from the same cut vertices, so they match.

import math
import os

import bmesh
import bpy
from bpy.props import BoolProperty, FloatProperty, IntProperty, PointerProperty, StringProperty

EPS = 1e-4


class TitamasTerrainSettings(bpy.types.PropertyGroup):
	chunk_size: FloatProperty(name="Chunk Size (m)", default=64.0, min=8.0)
	spacing: FloatProperty(name="Vertex Spacing (m)", default=2.0, min=0.25)
	columns: IntProperty(name="Chunks East (X)", default=2, min=1, max=64)
	rows: IntProperty(name="Chunks South (-Y)", default=1, min=1, max=64)
	start_i: IntProperty(name="First Chunk X", default=0, description="Grid X index of the north-west chunk")
	start_j: IntProperty(name="First Chunk Y", default=0, description="Grid Y index of the north-west chunk")
	lock_sculpt: BoolProperty(
		name="Lock Sculpt X/Y",
		default=True,
		description="Sculpt brushes only move vertices up and down, keeping the grid straight",
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


class TITAMAS_OT_new_terrain(bpy.types.Operator):
	bl_idname = "titamas.new_terrain"
	bl_label = "New Terrain"
	bl_description = "Add a flat master terrain covering whole chunks on the grid, ready to sculpt"
	bl_options = {"REGISTER", "UNDO"}

	def execute(self, context):
		s = context.scene.titamas_terrain
		size, step = s.chunk_size, s.spacing
		per_chunk = round(size / step)
		if abs(per_chunk * step - size) > EPS:
			self.report({"ERROR"}, "Chunk size must be a whole multiple of vertex spacing")
			return {"CANCELLED"}

		nx, ny = per_chunk * s.columns, per_chunk * s.rows
		half = size / 2.0
		x0 = s.start_i * size - half  # west edge
		y0 = -s.start_j * size + half  # north edge (Blender +Y)

		bm = bmesh.new()
		grid = []
		for r in range(ny + 1):
			row = [bm.verts.new((x0 + c * step, y0 - r * step, 0.0)) for c in range(nx + 1)]
			grid.append(row)
		for r in range(ny):
			for c in range(nx):
				# counter-clockwise seen from above so normals face up
				bm.faces.new((grid[r + 1][c], grid[r + 1][c + 1], grid[r][c + 1], grid[r][c]))

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

		self.report({"INFO"}, f"Terrain covers {s.columns} x {s.rows} chunks ({nx * ny * 2} triangles)")
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
		box.label(text="1. New terrain", icon="MESH_GRID")
		box.prop(s, "columns")
		box.prop(s, "rows")
		row = box.row(align=True)
		row.prop(s, "start_i")
		row.prop(s, "start_j")
		box.prop(s, "spacing")
		box.prop(s, "lock_sculpt")
		box.operator(TITAMAS_OT_new_terrain.bl_idname, icon="ADD")

		box = layout.box()
		box.label(text="2. Sculpt it, then export", icon="EXPORT")
		box.prop(s, "export_dir", text="")
		box.prop(s, "add_collision")
		box.operator(TITAMAS_OT_export_chunks.bl_idname, icon="EXPORT")

		layout.prop(s, "chunk_size")


classes = (TitamasTerrainSettings, TITAMAS_OT_new_terrain, TITAMAS_OT_export_chunks, TITAMAS_PT_terrain)


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
