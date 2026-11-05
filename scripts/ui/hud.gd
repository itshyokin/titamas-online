extends CanvasLayer
## HUD: health, mana and stamina bars bound to a Stats node, the fatigue bar,
## short centre-screen messages, and the combat parts: target frame, cast bar and
## action bar (built in code below).

@export var stats_path: NodePath

@onready var health_bar: ProgressBar = %HealthBar
@onready var mana_bar: ProgressBar = %ManaBar
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var fatigue_bar: ProgressBar = %FatigueBar
@onready var message: Label = %Message

const RESPAWN_MESSAGES := {
	"drowned": "You were overcome by fatigue.",
	"fell": "You fell from the world.",
	"died": "You died.",
}

var _message_tween: Tween

# Combat HUD (built in _build_combat_hud).
var _combat: PlayerCombat
var _targeting: Targeting
var _target_frame: PanelContainer
var _target_name: Label
var _target_bar: ProgressBar
var _target_stats: Stats
var _cast_bar: ProgressBar
var _cast_label: Label
var _cast_time := 0.0
var _cast_total := 0.0
var _cast_id := 0
var _slots: Array = []  # [ability, panel, cooldown overlay, cooldown label]


func _ready() -> void:
	var stats := get_node_or_null(stats_path) as Stats
	if stats == null:
		push_warning("HUD: no Stats node at %s" % stats_path)
		return
	stats.health_changed.connect(_set_bar.bind(health_bar))
	stats.mana_changed.connect(_set_bar.bind(mana_bar))
	stats.stamina_changed.connect(_set_bar.bind(stamina_bar))
	stats.emit_all()
	var player := stats.get_parent() as PlayerController
	if player:
		player.fatigue_changed.connect(_on_fatigue_changed)
		player.respawned.connect(func(reason: String) -> void: show_message(RESPAWN_MESSAGES.get(reason, "")))
		_combat = player.get_node_or_null("PlayerCombat") as PlayerCombat
		_targeting = player.get_node_or_null("Targeting") as Targeting
		if _combat and _targeting:
			_build_combat_hud()


func show_message(text: String, seconds := 3.0) -> void:
	if text.is_empty():
		return
	message.text = text
	if _message_tween:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_property(message, "modulate:a", 1.0, 0.3)
	_message_tween.tween_interval(seconds)
	_message_tween.tween_property(message, "modulate:a", 0.0, 0.8)


func _on_fatigue_changed(current: float, maximum: float) -> void:
	fatigue_bar.visible = current > 0.0
	fatigue_bar.max_value = maximum
	fatigue_bar.value = current


func _set_bar(current: float, maximum: float, bar: ProgressBar) -> void:
	bar.max_value = maximum
	bar.value = current



# --- Combat HUD -----------------------------------------------------------------

func _bar_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	return sb


func _progress(color: Color, size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = size
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _bar_style(Color(0, 0, 0, 0.55)))
	bar.add_theme_stylebox_override("fill", _bar_style(color))
	return bar


func _label(text: String, size := 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _build_combat_hud() -> void:
	# Target frame, top centre (below the fatigue bar).
	_target_frame = PanelContainer.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0, 0, 0, 0.45)
	panel.set_content_margin_all(8)
	panel.set_corner_radius_all(4)
	_target_frame.add_theme_stylebox_override("panel", panel)
	_target_frame.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target_frame.position = Vector2(-150, 50)
	_target_frame.custom_minimum_size = Vector2(300, 0)
	var box := VBoxContainer.new()
	_target_name = _label("", 18)
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_bar = _progress(Color(0.75, 0.15, 0.15), Vector2(284, 14))
	box.add_child(_target_name)
	box.add_child(_target_bar)
	_target_frame.add_child(box)
	_target_frame.visible = false
	add_child(_target_frame)
	_targeting.target_changed.connect(_on_target_changed)

	# Action bar, bottom centre.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var entries := _combat.action_bar()
	entries.insert(2, ["Q", null])  # block
	var slot_w := 74.0
	bar.position = Vector2(-(slot_w + 6) * entries.size() * 0.5, -96)
	for e in entries:
		bar.add_child(_make_slot(e[0], e[1], slot_w))
	add_child(bar)

	# Cast bar, above the action bar.
	_cast_bar = _progress(Color(0.95, 0.7, 0.2), Vector2(300, 16))
	_cast_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_cast_bar.position = Vector2(-150, -140)
	_cast_bar.visible = false
	_cast_label = _label("", 14)
	_cast_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cast_bar.add_child(_cast_label)
	add_child(_cast_bar)
	_combat.cast_started.connect(_on_cast_started)
	_combat.cast_finished.connect(_on_cast_finished)
	_combat.notice.connect(func(text: String) -> void: show_message(text, 1.0))


func _make_slot(key: String, ab: Ability, w: float) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(w, 60)
	var sb := StyleBoxFlat.new()
	sb.bg_color = (ab.color if ab else Color(0.55, 0.6, 0.7)).darkened(0.55)
	sb.border_color = ab.color if ab else Color(0.55, 0.6, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	var name_label := _label(ab.display_name if ab else "Block", 13)
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	p.add_child(name_label)
	var key_label := _label(key, 12)
	key_label.position = Vector2(4, 1)
	key_label.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	p.add_child(key_label)
	var cover := ColorRect.new()
	cover.color = Color(0, 0, 0, 0.6)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.visible = false
	p.add_child(cover)
	var cd := _label("", 18)
	cd.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(cd)
	if ab:
		var tip := "%s\n%s" % [ab.display_name, ab.description]
		if ab.mana_cost > 0.0:
			tip += "\nMana: %d" % ab.mana_cost
		if ab.stamina_cost > 0.0:
			tip += "\nStamina: %d" % ab.stamina_cost
		p.tooltip_text = tip
	else:
		p.tooltip_text = "Block (hold)\nStops most damage from the front. Each blocked hit costs stamina."
	_slots.append([ab, p, cover, cd])
	return p


func _process(delta: float) -> void:
	if _combat == null:
		return
	for slot in _slots:
		var ab: Ability = slot[0]
		var p: Panel = slot[1]
		var cover: ColorRect = slot[2]
		var cd: Label = slot[3]
		if ab == null:
			p.modulate = Color(1.3, 1.3, 1.3) if _combat.is_blocking() else Color.WHITE
			continue
		var left := _combat.cooldown_left(ab)
		cover.visible = left > 0.0
		if cover.visible:
			var k := clampf(left / maxf(ab.cooldown, 0.01), 0.0, 1.0)
			cover.position = Vector2(0, p.size.y * (1.0 - k))
			cover.size = Vector2(p.size.x, p.size.y * k)
		cd.text = ("%.1f" % left) if left > 0.0 else ""
		p.modulate = Color.WHITE if _combat.can_afford(ab) else Color(0.55, 0.55, 0.8)
	if _cast_bar.visible:
		_cast_time += delta
		_cast_bar.value = clampf(_cast_time / maxf(_cast_total, 0.01), 0.0, 1.0) * 100.0
	if _target_stats:
		_target_bar.max_value = _target_stats.max_health
		_target_bar.value = _target_stats.health


func _on_target_changed(target: Node3D) -> void:
	_target_stats = Combat.stats_of(target)
	_target_frame.visible = _target_stats != null
	if _target_stats:
		_target_name.text = "%s   Level %d" % [_target_stats.display_name, _target_stats.level]
		var hostile := _target_stats.team == Stats.Team.ENEMIES
		_target_name.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if hostile else Color(0.6, 0.9, 1.0))


func _on_cast_started(ab: Ability, duration: float) -> void:
	_cast_id += 1
	_cast_time = 0.0
	_cast_total = duration
	_cast_label.text = ab.display_name
	_cast_bar.add_theme_stylebox_override("fill", _bar_style(Color(0.95, 0.7, 0.2)))
	_cast_bar.visible = true


func _on_cast_finished(_ab: Ability, ok: bool) -> void:
	var id := _cast_id
	if not ok:
		_cast_bar.add_theme_stylebox_override("fill", _bar_style(Color(0.8, 0.2, 0.2)))
		_cast_label.text = "Interrupted"
		await get_tree().create_timer(0.5).timeout
	if id == _cast_id:
		_cast_bar.visible = false
