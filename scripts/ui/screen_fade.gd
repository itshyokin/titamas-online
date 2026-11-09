class_name ScreenFade
extends CanvasLayer
## A black (or coloured) screen fading in or out over everything (events' fades and teleports). It lives
## under the root, so it stays while the level changes underneath.

static var _instance: ScreenFade

var _rect: ColorRect
var _tween: Tween


static func _layer(from: Node) -> ScreenFade:
	if _instance == null or not is_instance_valid(_instance):
		_instance = ScreenFade.new()
		from.get_tree().root.add_child(_instance)
	return _instance


## Fades to black (or `color`) over `seconds`.
static func to_black(from: Node, seconds := 0.6, color := Color.BLACK) -> void:
	var l := _layer(from)
	if l._rect.color.a < 0.01:
		l._rect.color = Color(color, 0.0)
	else:
		l._rect.color = Color(color, l._rect.color.a)
	l._fade(1.0, seconds)


## Covers the screen with `color` at once (to fade in from it with clear()).
static func cover(from: Node, color := Color.BLACK) -> void:
	var l := _layer(from)
	if l._tween:
		l._tween.kill()
	l._rect.color = Color(color, 1.0)


## Fades back in over `seconds`.
static func clear(from: Node, seconds := 0.6) -> void:
	if _instance and is_instance_valid(_instance):
		_instance._fade(0.0, seconds)


static func is_black() -> bool:
	return _instance != null and is_instance_valid(_instance) and _instance._rect.color.a > 0.99


func _init() -> void:
	layer = 60
	name = "ScreenFade"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func _fade(to: float, seconds: float) -> void:
	if _tween:
		_tween.kill()
	if seconds <= 0.0:
		_rect.color.a = to
		return
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", to, seconds)
