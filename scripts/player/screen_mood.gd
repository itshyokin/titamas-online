class_name ScreenMood
extends CanvasLayer
## Tints the whole view to show how the player is doing (added by PlayerController):
##   - Fatigue (swimming far from land): the screen drains to grey and the edges darken
##     as fatigue builds and health runs out.
##   - Weakened (after dying): slightly washed out until it wears off.
## Settings: data/player.json "death" (Database → Player → Death).

var _rect: ColorRect
var _mat: ShaderMaterial
var _gray := 0.0
var _vignette := 0.0
var _saturation := 1.0


func _ready() -> void:
	layer = -2  # under the HUD and the underwater view
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://assets/materials/screen_mood.gdshader")
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


func _process(delta: float) -> void:
	var player := get_parent() as PlayerController
	if player == null:
		return
	var d: Dictionary = Database.player.get("death", {})
	# Fatigue: from `fatigue_fx_start` (share of the fatigue bar) to full, then deeper as
	# health drains away.
	var start := clampf(float(d.get("fatigue_fx_start", 0.5)), 0.0, 0.99)
	var f := clampf((player.fatigue / maxf(player.fatigue_max, 0.01) - start) / (1.0 - start), 0.0, 1.0)
	if player.fatigue >= player.fatigue_max and player.stats:
		f = clampf(0.55 + 0.45 * (1.0 - player.stats.health / maxf(player.stats.max_health, 1.0)), 0.0, 1.0)
	else:
		f *= 0.55
	var want_gray := f * float(d.get("fatigue_gray", 1.0))
	var want_vignette := f * float(d.get("fatigue_vignette", 0.85))
	var progress := player.get_node_or_null("Progress") as PlayerProgress
	var want_sat := float(d.get("weakened_saturation", 0.65)) if progress and progress.is_weakened() else 1.0
	var k := clampf(delta * 2.5, 0.0, 1.0)
	_gray = lerpf(_gray, want_gray, k)
	_vignette = lerpf(_vignette, want_vignette, k)
	_saturation = lerpf(_saturation, want_sat, clampf(delta * 1.5, 0.0, 1.0))
	var on := _gray > 0.005 or _vignette > 0.005 or absf(_saturation - 1.0) > 0.005
	_rect.visible = on
	if on:
		_mat.set_shader_parameter("gray", _gray)
		_mat.set_shader_parameter("vignette", _vignette)
		_mat.set_shader_parameter("saturation", _saturation)
