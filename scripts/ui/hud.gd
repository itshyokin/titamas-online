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
@onready var controls_label: Label = $Controls

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
var _charge_bar: ProgressBar
var _charge_label: Label
var _mode_slots: Array = []   # [Slot] for melee, ranged, magic
var _spell_slots: Array = []  # [Slot] x4
var _item_slots: Array = []   # [Slot] x2
var _hint_labels := {}        # Label -> action name (button hints that follow rebinding)


var _settings: SettingsMenu
var _clock: Label


func _ready() -> void:
	_settings = SettingsMenu.new()
	add_child(_settings)
	# Time of day, top right beside the settings gear (only when the world has a day cycle).
	_clock = Label.new()
	_clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_clock.position = Vector2(-230, 26)
	_clock.size = Vector2(160, 24)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.add_theme_font_size_override("font_size", 16)
	_clock.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_clock.add_theme_constant_override("outline_size", 4)
	add_child(_clock)
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
		if _targeting:
			_settings.targeting = _targeting
		if _combat and _targeting:
			_build_combat_hud()
	# Control hints sit under the bars, out of the way of the bottom bar.
	controls_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	controls_label.position = Vector2(24, 100)
	controls_label.size = Vector2(380, 0)
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	controls_label.add_theme_font_size_override("font_size", 13)
	controls_label.modulate = Color(1, 1, 1, 0.75)


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
# Bottom bar, WoW look with Fable controls: the three attack modes (melee, ranged,
# magic), four spell slots and two quick-item slots. Button hints follow the device in
# use and any rebinding.

const SPELL_SLOTS := 4
const ITEM_SLOTS := 2


class Slot:
	var panel: Panel
	var style: StyleBoxFlat
	var title: Label
	var cover: ColorRect
	var timer: Label
	var ability: Ability
	var color := Color(0.55, 0.6, 0.7)


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
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _hint(action: String, size := 11) -> Label:
	var l := _label("", size)
	l.add_theme_color_override("font_color", Color(1, 0.88, 0.55))
	_hint_labels[l] = action
	return l


func _build_combat_hud() -> void:
	# Target frame, top centre.
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
	_targeting.target_changed.connect(func(_t: Node3D) -> void: _refresh_target())
	_targeting.lock_changed.connect(func(_l: bool) -> void: _refresh_target())

	# Bottom bar.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position = Vector2(0, -24)
	var modes := [["Melee", Color(0.75, 0.75, 0.8), _combat.light_combo[0] if not _combat.light_combo.is_empty() else null],
		["Ranged", Color(0.55, 0.75, 0.4), _combat.ranged_attack], ["Magic", Color(0.6, 0.45, 0.95), null]]
	var mode_box := _group("cycle_mode")
	for m in modes:
		var slot := _make_slot(m[0], m[1], 78.0)
		slot.ability = m[2]
		mode_box.get_child(1).add_child(slot.panel)
		_mode_slots.append(slot)
	bar.add_child(mode_box)
	bar.add_child(_spacer())
	var spell_box := _group("spell_prev", "spell_next")
	for i in SPELL_SLOTS:
		var ab: Ability = _combat.spells[i] if i < _combat.spells.size() else null
		var slot := _make_slot(ab.display_name if ab else "", ab.color if ab else Color(0.35, 0.35, 0.4), 64.0)
		slot.ability = ab
		spell_box.get_child(1).add_child(slot.panel)
		_spell_slots.append(slot)
	bar.add_child(spell_box)
	bar.add_child(_spacer())
	var item_box := _group("item_prev", "item_next")
	for i in ITEM_SLOTS:
		var slot := _make_slot("", Color(0.35, 0.35, 0.4), 56.0)
		slot.panel.tooltip_text = "Quick item slot (potions and bandages come with the backpack)."
		item_box.get_child(1).add_child(slot.panel)
		_item_slots.append(slot)
	bar.add_child(item_box)
	add_child(bar)
	# Centre the bar once its size is known.
	bar.resized.connect(func() -> void: bar.position.x = -bar.size.x * 0.5)

	# Charge bar, above the bottom bar.
	_charge_bar = _progress(Color(0.95, 0.7, 0.2), Vector2(300, 16))
	_charge_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_charge_bar.position = Vector2(-150, -150)
	_charge_bar.visible = false
	_charge_label = _label("", 14)
	_charge_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_charge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_charge_bar.add_child(_charge_label)
	add_child(_charge_bar)

	_combat.charge_started.connect(_on_charge_started)
	_combat.charge_progress.connect(_on_charge_progress)
	_combat.charge_ended.connect(func() -> void: _charge_bar.visible = false)
	_combat.notice.connect(func(text: String) -> void: show_message(text, 1.0))
	_combat.mode_changed.connect(func(_m: int) -> void: _refresh_slots())
	_combat.spell_changed.connect(func(_i: int) -> void: _refresh_slots())
	_combat.loadout_changed.connect(_refresh_slots)
	GameSettings.device_changed.connect(func(_g: bool) -> void: _refresh_hints())
	GameSettings.bindings_changed.connect(_refresh_hints)
	_refresh_slots()
	_refresh_hints()


## A titled group of slots: hint label(s) on top, the slots underneath.
func _group(action: String, action2 := "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(_hint(action))
	if not action2.is_empty():
		top.add_child(_label("/", 11))
		top.add_child(_hint(action2))
	v.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	v.add_child(row)
	return v


func _spacer() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(14, 0)
	return c


func _make_slot(title: String, color: Color, w: float) -> Slot:
	var slot := Slot.new()
	slot.color = color
	slot.panel = Panel.new()
	slot.panel.custom_minimum_size = Vector2(w, 56)
	slot.style = StyleBoxFlat.new()
	slot.style.set_border_width_all(2)
	slot.style.set_corner_radius_all(4)
	slot.panel.add_theme_stylebox_override("panel", slot.style)
	slot.title = _label(title, 13)
	slot.title.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.title.autowrap_mode = TextServer.AUTOWRAP_WORD
	slot.panel.add_child(slot.title)
	slot.cover = ColorRect.new()
	slot.cover.color = Color(0, 0, 0, 0.6)
	slot.cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.cover.visible = false
	slot.panel.add_child(slot.cover)
	slot.timer = _label("", 18)
	slot.timer.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.panel.add_child(slot.timer)
	return slot


func _paint_slot(slot: Slot, active: bool) -> void:
	slot.style.bg_color = slot.color.darkened(0.35 if active else 0.65)
	slot.style.border_color = Color(1.0, 0.85, 0.4) if active else slot.color.darkened(0.2)
	slot.style.set_border_width_all(3 if active else 2)
	slot.panel.modulate = Color.WHITE if active else Color(0.8, 0.8, 0.8)


func _refresh_slots() -> void:
	for i in _mode_slots.size():
		_paint_slot(_mode_slots[i], i == _combat.mode)
	var spell_tip := "Tap attack in magic mode to cast; hold to charge."
	_mode_slots[0].panel.tooltip_text = "Melee: tap attack to swing (tap again to combo), hold to charge a heavy blow."
	_mode_slots[1].panel.tooltip_text = "Ranged: tap attack for a quick shot, hold to draw and release to fire."
	_mode_slots[2].panel.tooltip_text = "Magic: " + spell_tip
	var spell := _combat.selected_spell()
	_mode_slots[2].title.text = spell.display_name if spell else "Magic"
	_mode_slots[2].ability = spell
	_mode_slots[0].ability = _combat.mode_ability(PlayerCombat.Mode.MELEE)
	_mode_slots[1].ability = _combat.ranged_attack
	for i in _spell_slots.size():
		var slot: Slot = _spell_slots[i]
		slot.ability = _combat.spells[i] if i < _combat.spells.size() else null
		slot.color = slot.ability.color if slot.ability else Color(0.35, 0.35, 0.4)
		slot.title.text = slot.ability.display_name if slot.ability else ""
		slot.panel.tooltip_text = ""
		_paint_slot(slot, i == _combat.spell_index and _combat.mode == PlayerCombat.Mode.MAGIC)
		if slot.ability:
			var ab := slot.ability
			var tip := "%s\n%s" % [ab.display_name, ab.description]
			if ab.mana_cost > 0.0:
				tip += "\nMana: %d per level" % ab.mana_cost if ab.max_charge_level > 1 else "\nMana: %d" % ab.mana_cost
			slot.panel.tooltip_text = tip
	for slot: Slot in _item_slots:
		_paint_slot(slot, false)


func _refresh_hints() -> void:
	for l: Label in _hint_labels:
		l.text = GameSettings.binding_label(_hint_labels[l])
	var g := GameSettings
	controls_label.text = "%s attack (hold to charge) · %s block · %s melee/ranged/magic · %s dodge · %s jump · %s sprint · %s lock on · %s next target · gear/Esc: settings" % [
		g.binding_label("attack"), g.binding_label("block"), g.binding_label("cycle_mode"), g.binding_label("dodge"),
		g.binding_label("jump"), g.binding_label("sprint"), g.binding_label("lock_on"), g.binding_label("target_next")]


func _process(_delta: float) -> void:
	var cycle := get_tree().get_first_node_in_group("world_cycle") as WorldCycle
	_clock.visible = cycle != null
	if cycle:
		_clock.text = cycle.clock_text()
	if _combat == null:
		return
	for slot: Slot in _mode_slots + _spell_slots:
		var ab := slot.ability
		if ab == null:
			continue
		var left := _combat.cooldown_left(ab)
		slot.cover.visible = left > 0.0
		if slot.cover.visible:
			var k := clampf(left / maxf(ab.cooldown, 0.01), 0.0, 1.0)
			slot.cover.position = Vector2(0, slot.panel.size.y * (1.0 - k))
			slot.cover.size = Vector2(slot.panel.size.x, slot.panel.size.y * k)
		slot.timer.text = ("%.1f" % left) if left > 0.0 else ""
		if not _combat.can_afford(ab):
			slot.panel.modulate = Color(0.55, 0.55, 0.85)
	if _target_stats:
		_target_bar.max_value = _target_stats.max_health
		_target_bar.value = _target_stats.health


func _refresh_target() -> void:
	var target := _targeting.target if _targeting.has_target() else null
	_target_stats = Combat.stats_of(target)
	_target_frame.visible = _target_stats != null
	if _target_stats:
		var lock := "  [locked]" if _targeting.is_locked() else ""
		_target_name.text = "%s   Level %d%s" % [_target_stats.display_name, _target_stats.level, lock]
		var hostile := _target_stats.team == Stats.Team.ENEMIES
		_target_name.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if hostile else Color(0.6, 0.9, 1.0))


func _on_charge_started(ab: Ability) -> void:
	_charge_label.text = ab.display_name
	_charge_bar.value = 0.0
	_charge_bar.visible = true


func _on_charge_progress(fraction: float, level: int) -> void:
	_charge_bar.value = fraction * 100.0
	var ab := _combat.selected_spell() if _combat.mode == PlayerCombat.Mode.MAGIC else null
	if ab and ab.max_charge_level > 1:
		_charge_label.text = "%s  —  level %d" % [ab.display_name, level]
	elif fraction >= 1.0:
		_charge_label.text = "Full power!"
