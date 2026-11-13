class_name RetroFilter
extends CanvasLayer
## The retro look (Settings → Retro), drawn over the 3D picture and under every HUD and
## menu layer: chunky pixels, fewer colours + ordered dithering (PS1-style 15-bit colour),
## scanlines and a soft vignette, all scaled by one Intensity slider; plus wobbly terrain
## (global shader uniform `retro_snap`: terrain vertices snap to a coarse screen grid).
## Made by GameSettings under the root, so it covers the title screen too.

var _rect := ColorRect.new()
var _mat := ShaderMaterial.new()


func _ready() -> void:
	layer = -10  # first of the screen overlays (ScreenMood, underwater, talk veil come later)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat.shader = preload("res://assets/materials/retro.gdshader")
	_rect.material = _mat
	add_child(_rect)
	get_viewport().size_changed.connect(apply)
	apply()


## Reads GameSettings and sets the shader (call after any retro setting changes).
func apply() -> void:
	var g := get_node_or_null("/root/GameSettings")
	if g == null:
		return
	var k: float = clampf(float(g.get("retro_intensity")), 0.0, 1.0) if g.get("retro_on") else 0.0
	var h := float(get_viewport().get_visible_rect().size.y) if is_inside_tree() else 1080.0
	var pixels: bool = g.get("retro_pixelate") and k > 0.0
	var colors: bool = g.get("retro_colors") and k > 0.0
	# At full intensity the picture is about 240 game pixels tall (a PS1 screen).
	var block := maxf(1.0, round(lerpf(1.0, h / 240.0, k))) if pixels else 1.0
	_mat.set_shader_parameter("block", block)
	_mat.set_shader_parameter("levels", lerpf(48.0, 16.0, k) if colors else 256.0)  # 50 % = 32 steps, the PS1's 15-bit colour
	_mat.set_shader_parameter("dither", 1.0 if g.get("retro_dither") else 0.0)
	_mat.set_shader_parameter("scanlines", k if g.get("retro_scanlines") else 0.0)
	_mat.set_shader_parameter("vignette", k * 0.6 if g.get("retro_scanlines") else 0.0)
	_rect.visible = block > 1.0 or colors or bool(g.get("retro_scanlines")) and k > 0.0
	# Terrain wobble: rows of the snapping grid (fewer = wobblier); 0 = off.
	var snap := lerpf(400.0, 120.0, k) if g.get("retro_wobble") and k > 0.0 else 0.0
	RenderingServer.global_shader_parameter_set("retro_snap", snap)
