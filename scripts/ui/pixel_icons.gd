class_name PixelIcons
extends Node
## Icons in the pixel look: an icon (AbilityIcon, ItemIcon, a status glyph) is drawn once
## at a small size (player.json hud.icon_pixels, 24 = a 24 x 24 grid) into an offscreen
## viewport, kept as a texture, and shown scaled up with nearest-pixel filtering, so its
## pixels are big and crisp like the grass. 0 = draw them smoothly at full size.
##
## Made on first use under the tree's root (named "PixelIcons"). The icon calls
## `PixelIcons.get_texture(key, make)` from its _draw: a cached texture comes back at
## once; otherwise null, and `make` (a Callable returning a Control that draws the icon
## at the size it's given) is drawn on the next frame and every icon is redrawn.

const DEFAULT_PIXELS := 24

static var _cache := {}  # key -> Texture2D
static var _pending := {}  # key -> true

var _queue: Array = []  # [key, Callable]
var _busy := false


## How many pixels across an icon is drawn with (0 = smooth, full size).
static func pixels() -> int:
	var loop := Engine.get_main_loop() as SceneTree
	var db := loop.root.get_node_or_null("Database") if loop else null
	var player = db.get("player") if db else null
	var hud = (player as Dictionary).get("hud", {}) if player is Dictionary else {}
	return int((hud as Dictionary).get("icon_pixels", DEFAULT_PIXELS)) if hud is Dictionary else DEFAULT_PIXELS


static func get_texture(key: String, make: Callable) -> Texture2D:
	var px := pixels()
	var full := "%s@%d" % [key, px]
	if _cache.has(full):
		return _cache[full]
	if not _pending.has(full):
		_pending[full] = true
		_instance().call_deferred("_request", full, make, px)
	return null


## Forgets every icon (colours or the pixel size changed in the Database).
static func clear() -> void:
	_cache.clear()
	_pending.clear()


static func _instance() -> PixelIcons:
	var loop := Engine.get_main_loop() as SceneTree
	var n := loop.root.get_node_or_null("PixelIcons") as PixelIcons
	if n == null:
		n = PixelIcons.new()
		n.name = "PixelIcons"
		loop.root.add_child(n)
	return n


func _request(key: String, make: Callable, px: int) -> void:
	_queue.append([key, make, px])
	if not _busy:
		_run()


## Draws every waiting icon in one offscreen viewport, side by side, then cuts them out.
func _run() -> void:
	_busy = true
	while not _queue.is_empty():
		var batch := _queue.duplicate()
		_queue.clear()
		var px: int = batch[0][2]
		var vp := SubViewport.new()
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.size = Vector2i(px * batch.size(), px)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		add_child(vp)
		var made := []
		for i in batch.size():
			var c: Control = (batch[i][1] as Callable).call()
			if c == null:
				made.append(null)
				continue
			c.position = Vector2(i * px, 0)
			c.size = Vector2(px, px)
			vp.add_child(c)
			made.append(c)
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		for i in batch.size():
			var key: String = batch[i][0]
			if made[i] != null:
				var cut := img.get_region(Rect2i(i * px, 0, px, px))
				PixelArt.step_image(cut)
				_cache[key] = ImageTexture.create_from_image(cut)
			_pending.erase(key)
		vp.queue_free()
	_busy = false
	get_tree().call_group("pixel_icons", "queue_redraw")
