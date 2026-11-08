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
}
const MAX_BODY := 4 * 1024 * 1024

var _server: TCPServer
var _port := 0
var _clients: Array = []  # [StreamPeerTCP, PackedByteArray buffer, float age]
var _button: Button
var _fit_button: Button
const FITTER := "res://scenes/tools/armor_fitter.tscn"


func _enter_tree() -> void:
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


func _exit_tree() -> void:
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
			_json(peer, 200, {"animations": _animations(), "sounds": _files("res://assets/audio", ["ogg", "wav", "mp3"])})
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
