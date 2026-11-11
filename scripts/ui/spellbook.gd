class_name Spellbook
extends CanvasLayer
## Spellbook: the spells this character knows, shown as the Codex's Spells page (P opens
## the Codex there). Drag one onto the hotbar, or press "Add to bar" (controller: A) to
## put it in the first free box. Built by the HUD, embedded by the Codex.

const PANEL := Color(0.08, 0.075, 0.1, 0.95)

var combat: PlayerCombat
var inventory: Inventory
var _window: PanelContainer
var _list: VBoxContainer
var _head: Control
## Shown inside the Codex right now (the Codex handles keys and closing).
var embedded := false


func _init(player_combat: PlayerCombat, inv: Inventory) -> void:
	combat = player_combat
	inventory = inv


func _ready() -> void:
	layer = 15
	_window = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = CharacterWindow.ACCENT.darkened(0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	_window.add_theme_stylebox_override("panel", sb)
	_window.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_window.position = Vector2(24, -220)
	_window.custom_minimum_size = Vector2(340, 0)
	_window.visible = false
	add_child(_window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_window.add_child(v)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "Spellbook"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", CharacterWindow.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	head.add_child(close_button)
	v.add_child(head)
	_head = head
	var hint := Label.new()
	hint.text = "Drag a spell onto the hotbar (boxes 1–10)."
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.add_theme_font_size_override("font_size", 12)
	v.add_child(hint)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	v.add_child(_list)
	combat.loadout_changed.connect(_fill)
	_fill()


func is_open() -> bool:
	return _window.visible


## Opens the Codex at the Spells page.
func open() -> void:
	get_tree().call_group("codex", "open", "spells")


func close() -> void:
	if embedded:
		get_tree().call_group("codex", "close")
		return
	_window.visible = false


func _fill() -> void:
	_head.visible = not embedded
	_window.set_anchors_preset(Control.PRESET_TOP_LEFT if embedded else Control.PRESET_CENTER_LEFT)
	if embedded:
		_window.position = Vector2.ZERO
		_window.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	for c in _list.get_children():
		c.queue_free()
	for ab in combat.spells:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var tile := _SpellTile.new()
		tile.ability = ab
		row.add_child(tile)
		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.fit_content = true
		text.scroll_active = false
		text.custom_minimum_size = Vector2(190, 0)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cost := ("  ·  %d mana" % ab.mana_cost) if ab.mana_cost > 0.0 else ""
		var cast := ("  ·  %.1f s cast" % ab.cast_time) if ab.cast_time > 0.0 else "  ·  instant"
		text.text = "[b]%s[/b][font_size=12][color=#aaaaaa]%s%s[/color]\n%s[/font_size]" % [ab.display_name, cost, cast, ab.description]
		row.add_child(text)
		var add := Button.new()
		add.text = "On bar" if inventory.hotbar.has("ability:" + ab.id) else "Add to bar"
		add.disabled = inventory.hotbar.has("ability:" + ab.id)
		add.pressed.connect(func() -> void:
			inventory.add_to_hotbar("ability:" + ab.id)
			_fill())
		row.add_child(add)
		_list.add_child(row)
	if combat.spells.is_empty():
		var none := Label.new()
		none.text = "You don't know any spells yet."
		_list.add_child(none)


## A draggable spell icon.
class _SpellTile extends Control:
	var ability: Ability

	func _ready() -> void:
		custom_minimum_size = Vector2(48, 48)
		var icon := AbilityIcon.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.show_ability(ability)
		add_child(icon)
		tooltip_text = "Drag onto the hotbar"

	func _get_drag_data(_at: Vector2) -> Variant:
		var preview := AbilityIcon.new()
		preview.size = Vector2(44, 44)
		preview.show_ability(ability)
		var holder := Control.new()
		holder.add_child(preview)
		preview.position = -preview.size * 0.5
		set_drag_preview(holder)
		return {"where": "spellbook", "key": ability.id}
