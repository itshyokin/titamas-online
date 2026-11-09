class_name RewardItem
extends PanelContainer
## One reward item (quest offer / quest log): its icon and count; pointing at it shows the
## item's details compared with what you have equipped in that slot (green better, red worse).

const SIZE := Vector2(46, 46)

var item_id := ""
var count := 1


func _init(id: String, n := 1) -> void:
	item_id = id
	count = n
	custom_minimum_size = SIZE
	var d := Database.item(id)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.11, 0.14)
	sb.border_color = ItemIcon.rarity_color(d).darkened(0.2)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", sb)
	var icon := ItemIcon.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.show_item(d, n if n > 1 else 0)
	add_child(icon)
	tooltip_text = String(d.get("name", id))  # (non-empty so the custom tooltip shows)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _make_custom_tooltip(_for_text: String) -> Object:
	var d := Database.item(item_id)
	var player := get_tree().get_first_node_in_group("player")
	var inv := player.get_node_or_null("Inventory") as Inventory if player else null
	var combat := player.get_node_or_null("PlayerCombat") as PlayerCombat if player else null
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.055, 0.08, 0.97)
	sb.border_color = ItemIcon.rarity_color(d).darkened(0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size = Vector2(260, 0)
	text.text = CharacterWindow.describe(d, CharacterWindow.compare_text(d, inv, combat))
	panel.add_child(text)
	return panel
