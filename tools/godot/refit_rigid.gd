extends SceneTree
## Moves the rigid armour fits in data/items.json ("fit": {masc, femme} entries placed on a
## bone) from one set of base bodies to another, keeping each piece where it sat relative
## to its bone: the offset is turned with the bone's direction (an arm modelled in a
## T-pose vs an A-pose), helmets follow the head's size. A starting point after changing
## the bodies; fine-tune with Fit Armor.
##   godot --headless --path . --script res://tools/godot/refit_rigid.gd -- <old bodies scene>
##   python3 tools/godot/apply_refit.py
## Also moves the rigid hair / facial hair fits in data/appearance.json.

const NEW := "res://assets/models/characters/base_bodies.scn"
const ITEMS := "res://data/items.json"
const APPEARANCE := "res://data/appearance.json"
const OUT := "res://tools/godot/refit_out.json"
const CHILD := {
	"Arm": "ForeArm", "ForeArm": "Hand", "Hand": "HandIndex1", "Shoulder": "Arm",
	"UpLeg": "Leg", "Leg": "Foot", "Foot": "ToeBase",
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var old_path := args[0] if not args.is_empty() else "res://assets/models/characters/base_bodies.scn"
	var old_scene: Node = (load(old_path) as PackedScene).instantiate()
	var new_scene: Node = (load(NEW) as PackedScene).instantiate()
	var data = JSON.parse_string(FileAccess.get_file_as_string(ITEMS))
	var looks = JSON.parse_string(FileAccess.get_file_as_string(APPEARANCE))
	var moved := 0
	var entries: Array = data.items.duplicate()
	entries.append_array(looks.get("hair_styles", []))
	entries.append_array(looks.get("facial_hair", []))
	for item: Dictionary in entries:
		var fit = item.get("fit")
		if not fit is Dictionary:
			continue
		for body: String in ["masc", "femme"]:
			var arm := "Armature_" + body
			var old_sk: Skeleton3D = old_scene.get_node(arm + "/Skeleton3D")
			var new_sk: Skeleton3D = new_scene.get_node(arm + "/Skeleton3D")
			var prefix := "f_" if body == "femme" else ""
			for e: Dictionary in fit.get(body, []):
				if bool(e.get("grip", false)) or not e.has("bone"):
					continue
				var bone := String(e.bone)
				var pos := Vector3(e.position[0], e.position[1], e.position[2])
				var rot := Basis.from_euler(Vector3(e.rotation[0], e.rotation[1], e.rotation[2]) * PI / 180.0)
				var sc := float(e.get("scale", 1.0))
				if bone.ends_with("Head"):
					var ob := _bounds(old_sk.get_node(prefix + "head"), old_scene)
					var nb := _bounds(new_sk.get_node(prefix + "head"), new_scene)
					var k := (nb.size.x / ob.size.x)
					var rel := pos - (ob.position + ob.size * Vector3(0.5, 1.0, 0.5))
					pos = nb.position + nb.size * Vector3(0.5, 1.0, 0.5) + rel * k
					sc *= k
				else:
					var o := _global(old_sk, old_scene, bone)
					var n := _global(new_sk, new_scene, bone)
					var swing := Basis.IDENTITY
					var short := bone.trim_prefix("mixamorig_").replace("Left", "").replace("Right", "")
					if CHILD.has(short):
						var child := bone.replace(short, CHILD[short])
						var od := (_global(old_sk, old_scene, child).origin - o.origin).normalized()
						var nd := (_global(new_sk, new_scene, child).origin - n.origin).normalized()
						if od.dot(nd) < 0.9999:
							swing = Basis(Quaternion(od, nd))
					pos = n.origin + swing * (pos - o.origin)
					rot = swing * rot
				e.position = [snappedf(pos.x, 0.001), snappedf(pos.y, 0.001), snappedf(pos.z, 0.001)]
				var deg := rot.get_euler() * 180.0 / PI
				e.rotation = [snappedf(deg.x, 0.1), snappedf(deg.y, 0.1), snappedf(deg.z, 0.1)]
				e.scale = snappedf(sc, 0.01)
				moved += 1
				print("%s %s %s -> %s" % [item.id, body, bone, e.position])
	# Only the fits are written, to OUT ({id: fit}); tools/godot/apply_refit.py merges them
	# into items.json / appearance.json keeping those files' formatting.
	var fits := {}
	for item: Dictionary in entries:
		if item.get("fit") is Dictionary:
			fits[String(item.id)] = item.fit
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(fits, "\t"))
	f.close()
	print("moved %d fits" % moved)
	old_scene.free()
	new_scene.free()
	quit()


func _xform(node: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p := node
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## A bone's rest transform in the body's space (metres).
func _global(sk: Skeleton3D, root: Node, bone: String) -> Transform3D:
	var xf := _xform(sk, root) * sk.get_bone_global_rest(sk.find_bone(bone))
	return Transform3D(xf.basis.orthonormalized(), xf.origin)


## Rest-pose bounds of a body part mesh (its vertices are stored in the body's space).
func _bounds(mi: MeshInstance3D, _root: Node) -> AABB:
	var v: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var box := AABB(v[0], Vector3.ZERO)
	for p in v:
		box = box.expand(p)
	return box
