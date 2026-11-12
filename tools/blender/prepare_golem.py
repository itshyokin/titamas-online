"""Turns a high-poly, unrigged golem .glb (e.g. Pigcraft's "Stone Plant Golem", CC-BY 4.0)
into the game's golem model: joined, welded, decimated (RATIO, ~16k triangles), turned to
face the game's forward, HEIGHT m tall (3.6) with feet at 0, textures at most 1024 px, and
rigged with the bones the game's golem animation moves (body, torso, head, shoulder/elbow/
hand _L/_R, hip/knee _L/_R; weights from the distance to each bone).

    SRC=in.glb OUT=out.glb python3 -I prepare_golem.py          (pip "bpy" module)
    or in Blender: set the two environment variables and run this file in the Text Editor.

Writes OUT (unrigged) and OUT with _rigged before .glb: copy that one to
assets/models/creatures/stone_golem.glb. The joint positions in BONES are for this model;
another model needs its own (read them off front and side views, metres, Godot axes).
"""
import sys, os
if "BPYLIB" in os.environ:
	sys.path.insert(0, os.environ["BPYLIB"])
import bpy, bmesh
for o in list(bpy.data.objects): bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=os.environ["SRC"])
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in bpy.data.objects: o.select_set(o in meshes)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
obj = bpy.context.active_object
# Unparent keeping the world transform, then bake it.
mw = obj.matrix_world.copy()
obj.parent = None
obj.matrix_world = mw
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
	if o != obj: bpy.data.objects.remove(o)
import math, mathutils
# Face the game's forward (Blender +Y = Godot -Z), 3.6 m tall, feet on z = 0, centred.
obj.data.transform(mathutils.Matrix.Rotation(math.radians(90), 4, "Z"))
xs = [v.co for v in obj.data.vertices]
lo = mathutils.Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
hi = mathutils.Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
k = float(os.environ.get("HEIGHT", "3.6")) / (hi.z - lo.z)
obj.data.transform(mathutils.Matrix.Diagonal((k, k, k, 1.0)) @ mathutils.Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))
bm = bmesh.new(); bm.from_mesh(obj.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0004)
bm.to_mesh(obj.data); bm.free()
print("after weld", len(obj.data.polygons), len(obj.data.vertices))
mod = obj.modifiers.new("dec", "DECIMATE")
mod.ratio = float(os.environ.get("RATIO", "0.016"))
bpy.ops.object.modifier_apply(modifier="dec")
print("after decimate", len(obj.data.polygons))
for img in bpy.data.images:
	print("img", img.name, img.size[:])
	if img.size[0] > 1024:
		img.scale(1024, 1024)
obj.name = "golem"
bpy.ops.export_scene.gltf(filepath=os.environ["OUT"], export_format="GLB", export_image_format="JPEG", export_apply=True)
print("exported")


# --- Rig: bones at the joints the game's golem animation moves ----------------------
from mathutils import Vector
import numpy as np
def g(x, y, z):  # Godot model space (Y up, -Z forward) -> Blender (Z up, +Y forward)
	return Vector((x, -z, y))
BONES = [  # name, parent, head, tail (Godot coordinates, metres)
	("body", None, (0, 1.55, 0), (0, 1.75, 0)),
	("torso", "body", (0, 1.75, 0), (0, 2.75, 0)),
	("head", "torso", (-0.15, 2.95, -0.25), (-0.15, 3.5, -0.35)),
	("shoulder_L", "torso", (-0.85, 2.75, 0), (-1.25, 1.9, 0)),
	("elbow_L", "shoulder_L", (-1.25, 1.9, 0), (-1.4, 1.2, -0.05)),
	("hand_L", "elbow_L", (-1.4, 1.2, -0.05), (-1.45, 0.7, -0.05)),
	("shoulder_R", "torso", (0.85, 2.75, 0), (1.2, 1.9, 0)),
	("elbow_R", "shoulder_R", (1.2, 1.9, 0), (1.25, 1.15, -0.05)),
	("hand_R", "elbow_R", (1.25, 1.15, -0.05), (1.3, 0.7, -0.05)),
	("hip_L", "body", (-0.5, 1.5, 0), (-0.55, 0.75, 0)),
	("knee_L", "hip_L", (-0.55, 0.75, 0), (-0.55, 0.05, 0)),
	("hip_R", "body", (0.45, 1.5, 0), (0.45, 0.75, 0)),
	("knee_R", "hip_R", (0.45, 0.75, 0), (0.45, 0.05, 0)),
]
arm_data = bpy.data.armatures.new("golem_rig")
rig = bpy.data.objects.new("golem_rig", arm_data)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for name, parent, h, t in BONES:
	b = arm_data.edit_bones.new(name)
	b.head = g(*h)
	b.tail = g(*t)
	b.roll = 0.0
	if parent:
		b.parent = arm_data.edit_bones[parent]
bpy.ops.object.mode_set(mode="OBJECT")
# Weights: each vertex follows the bones nearest to it (distance to the bone's segment),
# blended over a short range so stone bends a little at the joints.
verts = np.array([v.co[:] for v in obj.data.vertices])
segs = [(np.array(g(*h)[:]), np.array(g(*t)[:])) for _, _, h, t in BONES]
dist = np.zeros((len(verts), len(BONES)))
for i, (a, b) in enumerate(segs):
	ab = b - a
	tt = np.clip(((verts - a) @ ab) / max(ab @ ab, 1e-9), 0, 1)
	dist[:, i] = np.linalg.norm(verts - (a + tt[:, None] * ab), axis=1)
# The pelvis is small: it shouldn't grab the legs or arms.
dist[:, 0] *= 1.6
order = np.argsort(dist, axis=1)
names = [b[0] for b in BONES]
# Blend only between bones that meet at a joint (parent / child): a vertex never follows
# a far-off bone, which would stretch it across the body when the limbs move.
neighbours = {i: {names.index(BONES[i][1])} if BONES[i][1] else set() for i in range(len(BONES))}
for i in range(len(BONES)):
	for j in neighbours[i].copy():
		neighbours[j].add(i)
# Faces bridging bones that don't meet at a joint (a fist touching a thigh, vines from an
# arm to the hip) would stretch across the body when the limbs move: cut them.
primary = order[:, 0]
bm = bmesh.new()
bm.from_mesh(obj.data)
bm.verts.ensure_lookup_table()
cut = [f for f in bm.faces if len({int(primary[v.index]) for v in f.verts}) > 1 and not all(
	int(primary[a.index]) == int(primary[b.index]) or int(primary[b.index]) in neighbours[int(primary[a.index])]
	for a in f.verts for b in f.verts)]
bmesh.ops.delete(bm, geom=cut, context="FACES_ONLY")
bm.to_mesh(obj.data)
bm.free()
print("cut bridging faces", len(cut))
for i, (name, _, _, _) in enumerate(BONES):
	obj.vertex_groups.new(name=name)
for vi in range(len(verts)):
	b0 = order[vi, 0]
	near = sorted(neighbours[b0], key=lambda j: dist[vi, j])
	b1 = near[0] if near else b0
	d0, d1 = dist[vi, b0], dist[vi, b1]
	w1 = np.clip(1.0 - (d1 - d0) / 0.18, 0.0, 1.0) * 0.5  # blend only near a joint
	obj.vertex_groups[BONES[b0][0]].add([vi], 1.0 - w1, "REPLACE")
	if w1 > 0.01 and b1 != b0:
		obj.vertex_groups[BONES[b1][0]].add([vi], w1, "REPLACE")
obj.parent = rig
mod = obj.modifiers.new("rig", "ARMATURE")
mod.object = rig
for o in bpy.data.objects: o.select_set(o in (obj, rig))
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=os.environ["OUT"].replace(".glb", "_rigged.glb"), export_format="GLB", export_image_format="JPEG",
	use_selection=True, export_skins=True, export_animations=False)
print("exported rigged")
