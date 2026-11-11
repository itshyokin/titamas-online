class_name Codex
extends CanvasLayer
## The Codex (book button, top right; Esc / Start): one book with pages down the left —
## Character (a 3D view of you and your stats), Quests, Spells, Skills, Achievements, Lore
## and Settings — plus Save game / Quit to title. Quests, Spells and Skills are the quest
## log, spellbook and skill trees shown inside the book (L opens the quest log on its own;
## P and N open the book at Spells / Skills). Lore
## entries come from data/lore.json (Database → Lore) and appear once their conditions
## hold. Built by the HUD, which hands it the other windows.

const PANEL := Color(0.075, 0.068, 0.09, 0.97)
const PAGE := Color(0.12, 0.11, 0.14, 1.0)
const ACCENT := Color(1.0, 0.85, 0.45)
const PAGES := [["character", "Character"], ["quests", "Quests"], ["spells", "Spells"], ["skills", "Skills"],
	["achievements", "Achievements"], ["lore", "Lore"], ["settings", "Settings"]]

var settings: SettingsMenu
var quest_log: QuestLog
var skill_window: SkillWindow
var spellbook: Spellbook
var targeting: Node

var _window: PanelContainer
var _page: PanelContainer
var _nav := {}  # page id -> Button
var _current := ""
var _book: Button
var _preview: CharacterPreview
var _stats_text: RichTextLabel
var _lore_list: VBoxContainer
var _lore_text: RichTextLabel
var _ach_list: VBoxContainer
var _ach_total: Label
var _pages := {}  # page id -> Control (own pages)
var _embedded: Node = null  # the window shown inside right now (quest log / skills)
var _settings_tabs: Control


func _ready() -> void:
	layer = 20
	add_to_group("codex")
	_build_book_button()
	_build_window()
	_window.visible = false


func is_open() -> bool:
	return _window.visible


func open(page := "") -> void:
	if page == "":
		page = _current if _current != "" else "character"
	_window.visible = true
	GameSettings.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_page(page)


func close() -> void:
	_release_embedded()
	if settings:
		settings.call("_cancel_wait")
	_window.visible = false
	GameSettings.menu_open = false


func _unhandled_input(event: InputEvent) -> void:
	var esc: bool = event.is_action_pressed("menu") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE)
	if is_open():
		if esc:
			close()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("quest_log"):
			show_page("quests")
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("skills"):
			close() if _current == "skills" else show_page("skills")
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("spellbook"):
			close() if _current == "spells" else show_page("spells")
			get_viewport().set_input_as_handled()
		return
	if GameSettings.menu_open:
		return
	if event.is_action_pressed("skills"):
		open("skills")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("spellbook"):
		open("spells")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu"):
		open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("target_clear"):
		# Esc clears the target first (Targeting does that); with nothing targeted it opens the Codex.
		if targeting and (targeting.get("target") != null or targeting.get("locked")):
			return
		open()
		get_viewport().set_input_as_handled()


# --- Building ------------------------------------------------------------------

func _build_book_button() -> void:
	_book = Button.new()
	_book.flat = true
	_book.custom_minimum_size = Vector2(44, 44)
	_book.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_book.position = Vector2(-60, 16)
	_book.tooltip_text = "Codex (%s)" % GameSettings.binding_label("menu")
	_book.focus_mode = Control.FOCUS_NONE
	var icon := BookIcon.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(icon)
	_book.pressed.connect(func() -> void: close() if is_open() else open())
	add_child(_book)


func _build_window() -> void:
	_window = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = ACCENT.darkened(0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 14
	_window.add_theme_stylebox_override("panel", sb)
	_window.set_anchors_preset(Control.PRESET_CENTER)
	_window.custom_minimum_size = Vector2(1000, 620)
	_window.position = Vector2(-500, -310)
	add_child(_window)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	_window.add_child(h)
	# The page list.
	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(170, 0)
	nav.add_theme_constant_override("separation", 6)
	h.add_child(nav)
	var title := Label.new()
	title.text = "Codex"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", ACCENT)
	nav.add_child(title)
	nav.add_child(HSeparator.new())
	for p: Array in PAGES:
		var b := Button.new()
		b.text = p[1]
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 38)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(show_page.bind(String(p[0])))
		nav.add_child(b)
		_nav[p[0]] = b
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	if GameSession.active():
		var save := Button.new()
		save.text = "Save game"
		save.pressed.connect(func() -> void:
			GameSession.save_game()
			save.text = "Saved ✓"
			get_tree().create_timer(1.5).timeout.connect(_reset_save_label.bind(save)))
		nav.add_child(save)
		var leave := Button.new()
		leave.text = "Quit to title"
		leave.pressed.connect(func() -> void:
			close()
			GameSession.quit_to_title())
		nav.add_child(leave)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	nav.add_child(close_button)
	# The page.
	_page = PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = PAGE
	ps.border_color = ACCENT.darkened(0.55)
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(6)
	ps.set_content_margin_all(12)
	_page.add_theme_stylebox_override("panel", ps)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(_page)
	_pages["character"] = _character_page()
	_pages["achievements"] = _achievements_page()
	_pages["lore"] = _lore_page()
	for c: Control in _pages.values():
		c.visible = false
		_page.add_child(c)


func _reset_save_label(button: Button) -> void:
	if is_instance_valid(button):
		button.text = "Save game"


func show_page(id: String) -> void:
	_release_embedded()
	_current = id
	for k: String in _nav:
		(_nav[k] as Button).button_pressed = k == id
	for k: String in _pages:
		(_pages[k] as Control).visible = k == id
	if _settings_tabs:
		_settings_tabs.visible = id == "settings"
	match id:
		"character":
			_fill_character()
		"achievements":
			_fill_achievements()
		"lore":
			_fill_lore()
		"quests":
			_embed(quest_log)
		"skills":
			_embed(skill_window)
		"spells":
			_embed(spellbook)
		"settings":
			if settings and _settings_tabs == null:
				_settings_tabs = settings.call("take_tabs")
				_settings_tabs.reparent(_page, false)
				_settings_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
			if settings:
				settings.call("_refresh_bindings")
			if _settings_tabs:
				_settings_tabs.visible = true


## Shows another window (quest log / skills) inside the book.
func _embed(win: Node) -> void:
	if win == null:
		return
	var panel := win.get("_window") as Control
	win.set("embedded", true)
	panel.reparent(_page, false)
	panel.visible = true
	win.call("_fill")
	_embedded = win


func _release_embedded() -> void:
	if _embedded == null or not is_instance_valid(_embedded):
		_embedded = null
		return
	var panel := _embedded.get("_window") as Control
	panel.visible = false
	panel.reparent(_embedded, false)
	_embedded.set("embedded", false)
	_embedded = null


# --- Character -----------------------------------------------------------------

func _character_page() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	_preview = CharacterPreview.new(Vector2i(300, 540))
	h.add_child(_preview)
	_stats_text = RichTextLabel.new()
	_stats_text.bbcode_enabled = true
	_stats_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_text.add_theme_font_size_override("normal_font_size", 16)
	_stats_text.add_theme_font_size_override("bold_font_size", 16)
	h.add_child(_stats_text)
	return h


func _fill_character() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	_preview.show_player(player)
	var st := player.get_node_or_null("Stats") as Stats
	var progress := player.get_node_or_null("Progress")
	var inv := player.get_node_or_null("Inventory")
	var combat := player.get_node_or_null("PlayerCombat")
	var data: Dictionary = GameSession.data if GameSession.active() else {}
	var t := "[font_size=24][color=#ffd873]%s[/color][/font_size]\n" % String(data.get("name", "Adventurer"))
	var cls := Database.class_data(String(data.get("class", "")))
	var species: Dictionary = Database.call("species_of", data) if Database.has_method("species_of") else {}
	var who: Array[String] = []
	if not species.is_empty():
		who.append(String(species.get("name", "")))
	if not cls.is_empty():
		who.append(String(cls.get("name", "")))
	t += "%sLevel %d\n" % [(" ".join(who) + "  ·  ") if not who.is_empty() else "", st.level if st else 1]
	if progress and progress.has_method("needed"):
		t += "[color=#9a96a8]Experience %d / %d[/color]\n" % [int(progress.get("xp")), int(progress.call("needed"))]
	t += "\n"
	if st:
		var attrs: Dictionary = st.get("attributes") if st.get("attributes") is Dictionary else {}
		if not attrs.is_empty():
			t += "[b][color=#ffd873]Attributes[/color][/b]\n"
			for a: Array in Database.call("attribute_list") if Database.has_method("attribute_list") else []:
				t += "  %s  [b]%d[/b]\n" % [a[1], int(attrs.get(a[0], 0))]
			t += "\n"
		t += "[b][color=#ffd873]Stats[/color][/b]\n"
		t += "  Health  [b]%d / %d[/b]\n" % [ceili(st.health), roundi(st.max_health)]
		t += "  Mana  [b]%d / %d[/b]\n" % [ceili(st.mana), roundi(st.max_mana)]
		t += "  Stamina  [b]%d[/b]\n" % roundi(st.max_stamina)
		t += "  Attack  [b]+%d[/b]\n" % st.attack
		t += "  Spell power  [b]+%d[/b]\n" % st.spell_power
		t += "  Armour  [b]%d[/b]\n" % st.armor
		t += "  Block  [b]%d[/b]\n" % st.block
		t += "  Critical chance  [b]%d%%[/b]\n" % roundi((Combat.CRIT_CHANCE + st.crit_bonus) * 100.0)
	if combat and not (combat.get("weapon") as Dictionary).is_empty():
		t += "  Weapon DPS  [b]%.1f[/b]\n" % float(combat.call("dps_of", combat.get("weapon")))
	if inv:
		t += "\n[color=#ffd76a]Gold  [b]%d[/b][/color]\n" % int(inv.get("gold"))
	if GameSession.active():
		var secs := int(GameSession.data.get("play_time", 0.0))
		t += "[color=#9a96a8]Played %d h %02d min[/color]\n" % [secs / 3600, (secs / 60) % 60]
	_stats_text.text = t


# --- Achievements ----------------------------------------------------------------

func _achievements_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_ach_total = Label.new()
	_ach_total.add_theme_color_override("font_color", Color(0.75, 0.72, 0.67))
	v.add_child(_ach_total)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_ach_list = VBoxContainer.new()
	_ach_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ach_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_ach_list)
	return v


func _fill_achievements() -> void:
	for c in _ach_list.get_children():
		c.queue_free()
	var ach := get_node_or_null("/root/Achievements")
	if ach == null:
		return
	var got_count := 0
	var defs: Array = ach.call("all")
	for d: Dictionary in defs:
		var id := String(d.get("id", ""))
		var got := bool(ach.call("is_unlocked", id))
		got_count += 1 if got else 0
		var secret := bool(d.get("hidden", false)) and not got
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.05 if got else 0.025)
		sb.border_color = Color(1, 1, 1, 0.1)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(10)
		sb.set_content_margin_all(8)
		row.add_theme_stylebox_override("panel", sb)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)
		var badge := AchievementPopup.Trophy.new()
		badge.custom_minimum_size = Vector2(48, 48)
		badge.locked = not got
		badge.icon = AchievementPopup.icon_of(d)
		h.add_child(badge)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		var name_l := Label.new()
		name_l.text = "???" if secret else String(d.get("name", id))
		name_l.add_theme_font_size_override("font_size", 17)
		name_l.add_theme_color_override("font_color", Color(0.96, 0.92, 0.85) if got else Color(0.72, 0.74, 0.8))
		text.add_child(name_l)
		var desc := Label.new()
		desc.text = "Hidden achievement." if secret else String(d.get("description", ""))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_color_override("font_color", Color(0.7, 0.68, 0.66))
		text.add_child(desc)
		h.add_child(text)
		_ach_list.add_child(row)
	var pts: Vector2i = ach.call("points")
	_ach_total.text = "%d of %d earned  ·  %d / %d points" % [got_count, defs.size(), pts.x, pts.y]


# --- Lore --------------------------------------------------------------------------

func _lore_page() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(230, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	_lore_list = VBoxContainer.new()
	_lore_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_lore_list)
	_lore_text = RichTextLabel.new()
	_lore_text.bbcode_enabled = true
	_lore_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lore_text.add_theme_font_size_override("normal_font_size", 16)
	_lore_text.add_theme_font_size_override("bold_font_size", 16)
	_lore_text.add_theme_font_size_override("italics_font_size", 16)
	h.add_child(_lore_text)
	return h


func _fill_lore() -> void:
	for c in _lore_list.get_children():
		c.queue_free()
	var player := get_tree().get_first_node_in_group("player")
	var by_cat := {}
	for e in Database.get("lore") if Database.get("lore") is Array else []:
		if not e is Dictionary:
			continue
		if not EventState.test_all(e.get("conditions", []), "", player):
			continue
		var cat := String(e.get("category", "General"))
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(e)
	if by_cat.is_empty():
		_lore_text.text = "[color=#9a96a8]Nothing written here yet. Explore, talk to people and read what you find.[/color]"
		return
	var first: Dictionary = {}
	var cats := by_cat.keys()
	cats.sort()
	for cat: String in cats:
		var head := Label.new()
		head.text = cat
		head.add_theme_color_override("font_color", ACCENT)
		_lore_list.add_child(head)
		for e: Dictionary in by_cat[cat]:
			var b := Button.new()
			b.text = String(e.get("title", e.get("id", "")))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.flat = true
			b.pressed.connect(_show_lore.bind(e))
			_lore_list.add_child(b)
			if first.is_empty():
				first = e
	_show_lore(first)


func _show_lore(e: Dictionary) -> void:
	_lore_text.text = "[font_size=22][color=#ffd873]%s[/color][/font_size]\n\n%s" % [String(e.get("title", "")), String(e.get("text", ""))]


## The book drawn for the button.
class BookIcon:
	extends Control

	func _draw() -> void:
		var s := size
		var c := s * 0.5
		var w := s.x * 0.62
		var hgt := s.y * 0.5
		var cover := Color(0.55, 0.32, 0.18)
		var pages := Color(0.95, 0.9, 0.78)
		var r := Rect2(c.x - w * 0.5, c.y - hgt * 0.5, w, hgt)
		draw_rect(r.grow(2), Color(0, 0, 0, 0.6))
		draw_rect(r, cover)
		draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(w * 0.5 - 4, hgt - 6)), pages)
		draw_rect(Rect2(Vector2(c.x + 1, r.position.y + 3), Vector2(w * 0.5 - 4, hgt - 6)), pages)
		draw_line(Vector2(c.x, r.position.y + 2), Vector2(c.x, r.end.y - 2), cover.darkened(0.4), 2.0)
		for i in 3:
			var y := r.position.y + 7 + i * 4
			draw_line(Vector2(r.position.x + 6, y), Vector2(c.x - 4, y), Color(0.5, 0.45, 0.4), 1.0)
			draw_line(Vector2(c.x + 4, y), Vector2(r.end.x - 6, y), Color(0.5, 0.45, 0.4), 1.0)
		draw_rect(Rect2(Vector2(c.x - 3, r.end.y - 2), Vector2(6, 8)), Color(0.85, 0.2, 0.2))
