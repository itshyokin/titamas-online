@tool
extends EditorPlugin
## Database editor: a "Database" button in the editor toolbar (and Project → Tools →
## Open Database Editor) opens tools/database/index.html in your web browser. The page
## talks to a tiny web server this plugin runs on your own computer (127.0.0.1 only),
## which reads and saves data/*.json. A game running from the editor picks up saved
## changes within a second.

const PORTS := [8787, 8788, 8789, 8790]
const PAGE := "res://tools/database/index.html"
## Files the page may read and write (nothing else can be touched).
const FILES := {
	"abilities": "res://data/abilities.json",
	"enemies": "res://data/enemies.json",
	"player": "res://data/player.json",
	"regions": "res://data/regions.json",
	"world": "res://data/world.json",
	"items": "res://data/items.json",
	"classes": "res://data/classes.json",
	"skill_trees": "res://data/skill_trees.json",
	"quests": "res://data/quests.json",
	"lore": "res://data/lore.json",
	"shops": "res://data/shops.json",
	"species": "res://data/species.json",
	"statuses": "res://data/statuses.json",
	"ground": "res://data/ground.json",
	"weather": "res://data/weather.json",
	"harvest": "res://data/harvest.json",
	"wildlife": "res://data/wildlife.json",
	"body_models": "res://data/body_models.json",
	"npcs": "res://data/npcs.json",
	"weapon_types": "res://data/weapon_types.json",
	"animations": "res://data/animations.json",
	"appearance": "res://data/appearance.json",
	"events": "res://data/events.json",
	"achievements": "res://data/achievements.json",
}
const MAX_BODY := 4 * 1024 * 1024
## Effect sprites for abilities (builtin/ from tools/art/make_effect_sprites.py, custom/ yours).
const SPRITE_DIR := "res://assets/effects"
## Item icons: builtin Saturn pictures (items/, tools/art/export_saturn_icons.mjs) and yours (custom/).
const ICON_DIR := "res://assets/icons"

var _server: TCPServer
var _port := 0
var _clients: Array = []  # [StreamPeerTCP, PackedByteArray buffer, float age]
var _button: Button
var _fit_button: Button
const FITTER := "res://scenes/tools/armor_fitter.tscn"
const RETARGET := "res://tools/godot/retarget_mixamo.gd"
const BUILD_BODIES := ["res://tools/godot/build_bodies.gd", "res://tools/godot/make_appearance.gd"]

# Rebuilding animations (Database → Animations → Rebuild): the retarget tool runs in a
# separate headless Godot, on a thread so the editor stays responsive.
var _rebuild_thread: Thread
var _rebuild_log := ""
var _rebuild_ok := false
var _rebuild_done := false
var _rebuild_scripts: Array = []
var _rebuild_marker := ""


var _preview: Node  # look_preview.gd: NPC / enemy look pictures for the page


func _enter_tree() -> void:
	_preview = preload("res://addons/titamas_database/look_preview.gd").new()
	_preview.name = "LookPreview"
	add_child(_preview)
	_button = Button.new()
	_button.text = "Database"
	_button.tooltip_text = "Open the game database (abilities, items, enemies, player, classes, world, regions) in your browser."
	_button.flat = true
	_button.pressed.connect(open_editor)
	add_control_to_container(CONTAINER_TOOLBAR, _button)
	_fit_button = Button.new()
	_fit_button.text = "Fit Armor"
	_fit_button.tooltip_text = "Open the armour-fitting editor (masc and femme side by side)."
	_fit_button.flat = true
	_fit_button.pressed.connect(func() -> void: EditorInterface.play_custom_scene(FITTER))
	add_control_to_container(CONTAINER_TOOLBAR, _fit_button)
	add_tool_menu_item("Open Database Editor", open_editor)
	_start_server()


## Starts rebuilding masc.res / femme.res from the FBX files and data/animations.json
## (or, with the body scripts, the bodies and pieces from data/body_models.json).
func _start_rebuild(scripts: Array = [RETARGET], marker := "saved res://assets/animations/femme.res") -> bool:
	if _rebuild_thread and _rebuild_thread.is_alive():
		return false
	_rebuild_scripts = scripts
	_rebuild_marker = marker
	if _rebuild_thread:
		_rebuild_thread.wait_to_finish()
	_rebuild_log = "Rebuilding…"
	_rebuild_ok = false
	_rebuild_done = false
	_rebuild_thread = Thread.new()
	_rebuild_thread.start(_run_rebuild)
	return true


func _run_rebuild() -> void:
	var text := ""
	var code := 0
	for script: String in _rebuild_scripts:
		var out := []
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", script]
		code = maxi(code, OS.execute(OS.get_executable_path(), args, out, true))
		text += "\n".join(out) + "\n"
	# Keep the useful lines (clip list, errors), not the engine's start-up chatter.
	var lines := []
	for line in text.split("\n"):
		if line.strip_edges().is_empty() or line.begins_with("Godot Engine"):
			continue
		lines.append(line)
	_rebuild_ok = code == 0 and text.contains(_rebuild_marker)
	_rebuild_log = "\n".join(lines.slice(maxi(lines.size() - 400, 0)))
	_rebuild_done = true


func _check_rebuild() -> void:
	if _rebuild_done:
		_rebuild_done = false
		# Let the editor pick up the new libraries.
		for path in ["res://assets/animations/masc.res", "res://assets/animations/femme.res", "res://assets/models/characters/base_bodies.scn"]:
			EditorInterface.get_resource_filesystem().update_file(path)
		EditorInterface.get_resource_filesystem().scan()


func _exit_tree() -> void:
	if _preview:
		_preview.queue_free()
	if _rebuild_thread:
		_rebuild_thread.wait_to_finish()
	remove_control_from_container(CONTAINER_TOOLBAR, _button)
	_button.queue_free()
	remove_control_from_container(CONTAINER_TOOLBAR, _fit_button)
	_fit_button.queue_free()
	remove_tool_menu_item("Open Database Editor")
	for c in _clients:
		(c[0] as StreamPeerTCP).disconnect_from_host()
	_clients.clear()
	if _server:
		_server.stop()


func open_editor() -> void:
	if not _start_server():
		push_error("Database: couldn't start the local server (ports %s busy)." % str(PORTS))
		return
	OS.shell_open("http://127.0.0.1:%d/" % _port)


func _start_server() -> bool:
	if _server and _server.is_listening():
		return true
	_server = TCPServer.new()
	for port in PORTS:
		if _server.listen(port, "127.0.0.1") == OK:
			_port = port
			return true
	return false


func _process(delta: float) -> void:
	_check_rebuild()
	if _server == null or not _server.is_listening():
		return
	while _server.is_connection_available():
		_clients.append([_server.take_connection(), PackedByteArray(), 0.0])
	for i in range(_clients.size() - 1, -1, -1):
		var c: Array = _clients[i]
		var peer: StreamPeerTCP = c[0]
		peer.poll()
		c[2] += delta
		var status := peer.get_status()
		if status != StreamPeerTCP.STATUS_CONNECTED or c[2] > 10.0:
			peer.disconnect_from_host()
			_clients.remove_at(i)
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var got := peer.get_data(available)
			if got[0] == OK:
				c[1] = (c[1] as PackedByteArray) + (got[1] as PackedByteArray)
		var request := _parse(c[1])
		if request.is_empty():
			if (c[1] as PackedByteArray).size() > MAX_BODY:
				_send(peer, 413, "text/plain", "Too large".to_utf8_buffer())
				_clients.remove_at(i)
			continue
		_handle(peer, request)
		_clients.remove_at(i)


## {method, path, body} once the whole request has arrived, else {}.
func _parse(buffer: PackedByteArray) -> Dictionary:
	var text := buffer.get_string_from_utf8()
	var head_end := text.find("\r\n\r\n")
	if head_end < 0:
		return {}
	var head := text.substr(0, head_end)
	var lines := head.split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		return {"method": "BAD", "path": "", "body": ""}
	var length := 0
	for line in lines:
		if line.to_lower().begins_with("content-length:"):
			length = line.substr(15).strip_edges().to_int()
	# Body length is in bytes; find where the header ends in bytes too.
	var head_bytes := (head + "\r\n\r\n").to_utf8_buffer().size()
	if buffer.size() < head_bytes + length:
		return {}
	var body := buffer.slice(head_bytes, head_bytes + length).get_string_from_utf8()
	return {"method": first[0], "path": first[1].split("?")[0], "body": body}


func _handle(peer: StreamPeerTCP, req: Dictionary) -> void:
	# Effect sprite pictures for the page's previews: /sprite/assets/effects/…png
	if req.method == "GET" and String(req.path).begins_with("/sprite/"):
		var file := "res://" + String(req.path).trim_prefix("/sprite/").uri_decode()
		if (file.begins_with(SPRITE_DIR) or file.begins_with(ICON_DIR)) and not file.contains("..") and file.get_extension().to_lower() == "png" and FileAccess.file_exists(file):
			_send(peer, 200, "image/png", FileAccess.get_file_as_bytes(file))
		else:
			_send(peer, 404, "text/plain", "Not found".to_utf8_buffer())
		return
	match [req.method, req.path]:
		["GET", "/"], ["GET", "/index.html"]:
			var html := FileAccess.get_file_as_string(PAGE)
			_send(peer, 200, "text/html; charset=utf-8", html.to_utf8_buffer())
		["GET", "/api/data"]:
			var out := {}
			for key: String in FILES:
				var parsed = JSON.parse_string(FileAccess.get_file_as_string(FILES[key])) if FileAccess.file_exists(FILES[key]) else null
				out[key] = parsed
			_json(peer, 200, out)
		["GET", "/api/assets"]:
			var fbx := []
			for f in _files("res://assets/animations/mixamo", ["fbx"]):
				fbx.append(String(f).get_file().get_basename())
			var props := []
			for f in _files("res://assets/props", ["glb"]):
				props.append(String(f).get_file().get_basename())
			var levels := _files("res://scenes/levels", ["tscn"])
			_json(peer, 200, {"animations": _animations(), "sounds": _files("res://assets/audio", ["ogg", "wav", "mp3"]), "fbx": fbx,
				"props": props, "levels": levels, "markers": _markers(levels),
				"glbs": _files("res://assets/models/characters/src", ["glb"]), "glb_meshes": _glb_meshes(), "glb_bones": _glb_bones(),
				"pieces": _files("res://assets/characters/lowpoly", ["scn"]), "sprites": _files(SPRITE_DIR, ["png"]), "videos": _files("res://assets", ["ogv"]),
				"item_icons": _item_icon_groups(), "ground_textures": _files("res://assets/materials/terrain", ["jpg", "png", "webp"]), "creature_models": _files("res://assets/models/creatures", ["glb", "gltf"]), "custom_icons": _files(ICON_DIR.path_join("custom"), ["png"])})
		["POST", "/api/upload_sprite"]:
			# "Load PNG…" on an effect sprite field: {name, data (base64)} → assets/effects/custom/<name>.png
			var up = JSON.parse_string(req.body)
			var bytes := Marshalls.base64_to_raw(String(up.get("data", ""))) if up is Dictionary else PackedByteArray()
			var img := Image.new()
			if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
				_json(peer, 400, {"ok": false, "error": "That isn't a PNG picture"})
				return
			var clean := ""
			for ch in String(up.get("name", "sprite")).get_basename().to_lower():
				clean += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" else "_"
			if clean.is_empty():
				clean = "sprite"
			# folder "icons" = an item icon (assets/icons/custom), otherwise an effect sprite.
			var folder := (ICON_DIR if String(up.get("folder", "")) == "icons" else SPRITE_DIR).path_join("custom")
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
			var target := folder.path_join(clean + ".png")
			var out_file := FileAccess.open(target, FileAccess.WRITE)
			if out_file == null:
				_json(peer, 500, {"ok": false, "error": "Couldn't write %s" % target})
				return
			out_file.store_buffer(bytes)
			out_file.close()
			EditorInterface.get_resource_filesystem().scan()
			_json(peer, 200, {"ok": true, "path": target, "width": img.get_width(), "height": img.get_height()})
		["POST", "/api/preview"]:
			# {look, equipment} → {body, face} (base64 PNGs), rendered a few frames later.
			var want = JSON.parse_string(req.body)
			if not want is Dictionary:
				_json(peer, 400, {"ok": false, "error": "Bad request"})
				return
			var look = want.get("look", {})
			var eq = want.get("equipment", {})
			_preview.call("render", look if look is Dictionary else {}, eq if eq is Dictionary else {}, func(r: Dictionary) -> void:
				if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
					return
				if r.has("error"):
					_json(peer, 500, {"ok": false, "error": r.error})
				else:
					_json(peer, 200, {"ok": true, "body": Marshalls.raw_to_base64(r.body), "face": Marshalls.raw_to_base64(r.face)}))
		["POST", "/api/rebuild_animations"]:
			_json(peer, 200, {"ok": _start_rebuild()})
		["POST", "/api/rebuild_bodies"]:
			_json(peer, 200, {"ok": _start_rebuild(BUILD_BODIES, "saved res://assets/models/characters/base_bodies.scn err=0")})
		["GET", "/api/rebuild_status"]:
			_json(peer, 200, {"running": _rebuild_thread != null and _rebuild_thread.is_alive(), "log": _rebuild_log, "ok": _rebuild_ok})
		["POST", "/api/save"]:
			var data = JSON.parse_string(req.body)
			if not data is Dictionary or not FILES.has(String(data.get("file", ""))) or not data.has("data"):
				_json(peer, 400, {"ok": false, "error": "Unknown file"})
				return
			var path: String = FILES[data.file]
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				_json(peer, 500, {"ok": false, "error": "Couldn't write %s" % path})
				return
			f.store_string(JSON.stringify(data.data, "\t", false) + "\n")
			f.close()
			EditorInterface.get_resource_filesystem().update_file(path)
			_json(peer, 200, {"ok": true, "path": path})
		_:
			_send(peer, 404, "text/plain", "Not found".to_utf8_buffer())


## The meshes in the body .glb (data/body_models.json "source"): {name, materials, skinned},
## read from the file's glTF JSON so new Blender objects show up in Database → Body Models.
func _glb_meshes() -> Array:
	var settings = JSON.parse_string(FileAccess.get_file_as_string("res://data/body_models.json")) if FileAccess.file_exists("res://data/body_models.json") else {}
	var path := String(settings.get("source", "")) if settings is Dictionary else ""
	var f := FileAccess.open(path, FileAccess.READ) if path != "" else null
	if f == null:
		return []
	f.seek(12)
	var length := f.get_32()
	f.get_32()  # chunk type JSON
	var gltf = JSON.parse_string(f.get_buffer(length).get_string_from_utf8())
	if not gltf is Dictionary:
		return []
	var materials: Array = gltf.get("materials", [])
	var meshes: Array = gltf.get("meshes", [])
	var out := []
	for node: Dictionary in gltf.get("nodes", []):
		if not node.has("mesh"):
			continue
		var mats := []
		for prim: Dictionary in meshes[int(node.mesh)].get("primitives", []):
			if prim.has("material"):
				mats.append(String(materials[int(prim.material)].get("name", "")))
		out.append({"name": String(node.get("name", "")), "materials": mats, "skinned": node.has("skin")})
	return out


## The armature's bone names in the body .glb, as Godot names them (":" → "_"), for the
## Body Models bone dropdown of rigid pieces.
func _glb_bones() -> Array:
	var settings = JSON.parse_string(FileAccess.get_file_as_string("res://data/body_models.json")) if FileAccess.file_exists("res://data/body_models.json") else {}
	var path := String(settings.get("source", "")) if settings is Dictionary else ""
	var f := FileAccess.open(path, FileAccess.READ) if path != "" else null
	if f == null:
		return []
	f.seek(12)
	var length := f.get_32()
	f.get_32()
	var gltf = JSON.parse_string(f.get_buffer(length).get_string_from_utf8())
	if not gltf is Dictionary:
		return []
	var nodes: Array = gltf.get("nodes", [])
	var out := []
	for skin: Dictionary in gltf.get("skins", []):
		for j in skin.get("joints", []):
			var n := String((nodes[int(j)] as Dictionary).get("name", "")).replace(":", "_")
			if n != "" and not out.has(n):
				out.append(n)
	return out


func _json(peer: StreamPeerTCP, code: int, data: Variant) -> void:
	_send(peer, code, "application/json; charset=utf-8", JSON.stringify(data).to_utf8_buffer())


func _send(peer: StreamPeerTCP, code: int, type: String, body: PackedByteArray) -> void:
	var reason := {200: "OK", 400: "Bad Request", 404: "Not Found", 413: "Payload Too Large", 500: "Internal Server Error"}.get(code, "OK")
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [code, reason, type, body.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()


func _animations() -> Array:
	var lib := load("res://assets/animations/masc.res") as AnimationLibrary
	if lib == null:
		return []
	var names := []
	for n in lib.get_animation_list():
		names.append(String(n))
	names.sort()
	return names


## Marker3D names in each level (teleport destinations for events).
func _markers(levels: Array) -> Dictionary:
	var out := {}
	var rx := RegEx.create_from_string('\\[node name="([^"]+)" type="Marker3D"')
	for level in levels:
		var names := []
		for m in rx.search_all(FileAccess.get_file_as_string(level)):
			names.append(m.get_string(1))
		out[level] = names
	return out


func _files(dir: String, exts: Array) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		if FileAccess.file_exists(dir.path_join(sub).path_join(".gdignore")):
			continue
		out.append_array(_files(dir.path_join(sub), exts))
	for file in d.get_files():
		if file.get_extension().to_lower() in exts:
			out.append(dir.path_join(file))
	out.sort()
	return out


## The builtin item icons' picker groups: [[group, [[id, name], ...]], ...] from icons.json.
func _item_icon_groups() -> Array:
	var path := ICON_DIR.path_join("items/icons.json")
	if not FileAccess.file_exists(path):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d.get("groups", []) if d is Dictionary else []
