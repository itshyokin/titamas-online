class_name Cutscene
extends RefCounted
## In-engine cutscene pieces the event commands use: screen shake (with controller
## rumble), letterbox bars, a cutscene camera that glides between markers, and full-screen
## video. Each is a small node; the static functions make and find them.

const RUMBLE := preload("res://assets/audio/events/rumble_loop.ogg")


## Shakes the camera for `seconds` (strength 0–1) with controller rumble; `sound`: the
## rumble loop (or another stream) plays meanwhile, fading out at the end.
static func shake(from: Node, seconds: float, strength := 0.4, sound: AudioStream = null) -> void:
	var s := Shaker.new()
	s.seconds = maxf(seconds, 0.05)
	s.strength = clampf(strength, 0.0, 1.0)
	s.sound = sound
	from.get_tree().root.add_child(s)


static func letterbox(from: Node, on: bool, seconds := 0.6) -> void:
	var tree := from.get_tree()
	var bars := tree.root.get_node_or_null("Letterbox") as Letterbox
	if bars == null:
		if not on:
			return
		bars = Letterbox.new()
		bars.name = "Letterbox"
		tree.root.add_child(bars)
	bars.show_bars(on, seconds)


## Moves the view to `to` (a node, usually a Marker3D: its position and facing) over
## `seconds`, turning to look at `look` if given. The first move takes over from the
## game camera; `camera_back` hands it back.
static func camera_to(from: Node, to: Node3D, look: Node3D, seconds: float) -> CutsceneCamera:
	var tree := from.get_tree()
	var cam := tree.root.get_node_or_null("CutsceneCamera") as CutsceneCamera
	if cam == null:
		var game_cam := from.get_viewport().get_camera_3d()
		cam = CutsceneCamera.new()
		cam.name = "CutsceneCamera"
		cam.game_camera = game_cam
		tree.root.add_child(cam)
		if game_cam:
			cam.global_transform = game_cam.global_transform
			cam.fov = game_cam.fov
		cam.make_current()
	var goal := to.global_transform
	if look:
		var at := look.global_position + Vector3.UP * (1.4 if look is CharacterBody3D else 0.0)
		if goal.origin.distance_to(at) > 0.01:
			goal = goal.looking_at(at, Vector3.UP)
	cam.glide(goal, seconds)
	return cam


## Back to the game camera (gliding to where it is over `seconds`).
static func camera_back(from: Node, seconds: float) -> void:
	var cam := from.get_tree().root.get_node_or_null("CutsceneCamera") as CutsceneCamera
	if cam:
		cam.go_back(seconds)


static func video(from: Node, path: String, skippable := true, pause_game := true) -> VideoScreen:
	var stream := load(path) as VideoStream if ResourceLoader.exists(path) else null
	if stream == null:
		push_warning("Cutscene: no video at '%s' (Godot plays .ogv Theora videos)" % path)
		return null
	var v := VideoScreen.new()
	v.stream = stream
	v.skippable = skippable
	v.pause_game = pause_game
	from.get_tree().root.add_child(v)
	return v


class Shaker:
	extends Node
	var seconds := 1.0
	var strength := 0.4
	var sound: AudioStream
	var _age := 0.0
	var _player: AudioStreamPlayer

	func _ready() -> void:
		var cam := get_tree().get_first_node_in_group("player_camera")
		if cam:
			cam.call("shake", strength)
		Input.start_joy_vibration(0, strength * 0.6, strength, seconds)
		if sound:
			_player = AudioStreamPlayer.new()
			_player.stream = sound
			_player.bus = &"SFX"
			_player.volume_db = linear_to_db(clampf(0.4 + strength, 0.1, 1.2))
			add_child(_player)
			_player.play()

	func _process(delta: float) -> void:
		_age += delta
		var left := seconds - _age
		var cam := get_tree().get_first_node_in_group("player_camera")
		if cam and left > 0.0:
			# Keeps the shake topped up (it fades by about 2.2 a second on its own).
			cam.call("shake", delta * 2.2 * minf(1.0, left * 2.0))
		if _player:
			_player.volume_db = linear_to_db(clampf(0.4 + strength, 0.1, 1.2) * clampf(left / 0.6 + 0.0, 0.0, 1.0) + 0.0001)
		if left <= 0.0:
			queue_free()


class Letterbox:
	extends CanvasLayer
	var _top: ColorRect
	var _bottom: ColorRect
	var _tween: Tween

	func _init() -> void:
		layer = 90
		_top = ColorRect.new()
		_bottom = ColorRect.new()
		for r in [_top, _bottom]:
			r.color = Color.BLACK
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(r)
		_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_top.offset_bottom = 0.0
		_bottom.offset_top = 0.0

	func show_bars(on: bool, seconds: float) -> void:
		# The HUD steps aside while the bars are up.
		for hud in get_tree().get_nodes_in_group("hud"):
			if "visible" in hud:
				hud.visible = not on
		var h := get_viewport().get_visible_rect().size.y * 0.11 if on else 0.0
		if _tween:
			_tween.kill()
		_tween = create_tween().set_parallel()
		_tween.tween_property(_bottom, "offset_top", -h, seconds)
		_tween.tween_property(_top, "offset_bottom", h, seconds)
		if not on:
			_tween.chain().tween_callback(queue_free)


class CutsceneCamera:
	extends Camera3D
	var game_camera: Camera3D
	var _tween: Tween

	func glide(goal: Transform3D, seconds: float) -> void:
		if _tween:
			_tween.kill()
		if seconds <= 0.0:
			global_transform = goal
			return
		_tween = create_tween()
		_tween.tween_method(_blend.bind(global_transform, goal), 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	func _blend(k: float, a: Transform3D, b: Transform3D) -> void:
		global_transform = a.interpolate_with(b, k)

	func go_back(seconds: float) -> void:
		if not is_instance_valid(game_camera):
			queue_free()
			return
		if _tween:
			_tween.kill()
		_tween = create_tween()
		var start := global_transform
		_tween.tween_method(func(k: float) -> void: global_transform = start.interpolate_with(game_camera.global_transform, k), 0.0, 1.0, maxf(seconds, 0.01)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_callback(func() -> void:
			game_camera.make_current()
			queue_free())


## A full-screen video (an .ogv) over everything; the game waits (pauses) under it.
## Esc, Interact, Attack or a click skip it when it's skippable.
class VideoScreen:
	extends CanvasLayer
	signal done
	var stream: VideoStream
	var skippable := true
	var pause_game := true
	var _video: VideoStreamPlayer
	var _hint: Label
	var _was_paused := false
	var _ended := false

	func _ready() -> void:
		layer = 120
		process_mode = Node.PROCESS_MODE_ALWAYS
		var back := ColorRect.new()
		back.color = Color.BLACK
		back.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(back)
		_video = VideoStreamPlayer.new()
		_video.stream = stream
		_video.expand = true
		_video.bus = &"Music"
		add_child(_video)
		_video.finished.connect(_end)
		if skippable:
			_hint = Label.new()
			_hint.text = "Skip: Esc"
			_hint.modulate = Color(1, 1, 1, 0.5)
			add_child(_hint)
			_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			_hint.offset_left = -120.0
			_hint.offset_top = -44.0
			_hint.add_theme_color_override("font_outline_color", Color.BLACK)
			_hint.add_theme_constant_override("outline_size", 4)
		_was_paused = get_tree().paused
		if pause_game:
			get_tree().paused = true
		_video.play()
		_fit()

	func _process(_delta: float) -> void:
		_fit()

	## Keeps the picture's shape, as big as fits.
	func _fit() -> void:
		var screen := get_viewport().get_visible_rect().size
		var tex := _video.get_video_texture()
		var shape := float(tex.get_width()) / maxf(float(tex.get_height()), 1.0) if tex and tex.get_height() > 0 else 16.0 / 9.0
		var w := minf(screen.x, screen.y * shape)
		var h := w / shape
		_video.size = Vector2(w, h)
		_video.position = (screen - Vector2(w, h)) * 0.5

	func _input(event: InputEvent) -> void:
		if not skippable or _ended:
			return
		var click := event is InputEventMouseButton and (event as InputEventMouseButton).pressed
		if click or event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact") or event.is_action_pressed("attack"):
			get_viewport().set_input_as_handled()
			_end()

	func _end() -> void:
		if _ended:
			return
		_ended = true
		_video.stop()
		if pause_game:
			get_tree().paused = _was_paused
		done.emit()
		queue_free()
