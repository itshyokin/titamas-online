class_name HUD
extends CanvasLayer
## HUD: the player frame (name, level, health, mana and stamina), the fatigue bar,
## short messages above the hotbar (HUD.notify), and the combat parts: target frame, cast bar, crosshair
## and the hotbar with the experience bar (built in code below). Also builds the
## character window, spellbook, ability wheel and settings menu.

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
var _stats: Stats
var _target_frame: PanelContainer
var _target_name: Label
var _target_bar: ProgressBar
var _target_stats: Stats
var _cast_bar: ProgressBar
var _cast_label: Label
var _cast_flash := 0.0  # seconds "Interrupted" stays up
var _crosshair: Crosshair
var _hotbar: Hotbar
var _wheel: AbilityWheel
var _spellbook: Spellbook
var _name_label: Label
var _bar_values := {}  # ProgressBar -> Label with "85 / 100"
var _weakened: Label
var _danger: Label
var _weakened_progress: PlayerProgress

var _settings: SettingsMenu
var _codex: Codex
var _clock: Label
var _inventory: Inventory
var _character_window: CharacterWindow
var _gold: Label
var _pickups: VBoxContainer
var _compass: Compass
var _enemy_bars: EnemyBars


func _ready() -> void:
	add_to_group("hud")
	# Messages (not dialogue): bottom centre, just above the hotbar.
	message.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	message.offset_left = -360.0
	message.offset_right = 360.0
	message.offset_top = -200.0
	message.offset_bottom = -166.0
	message.add_theme_font_size_override("font_size", 21)
	message.add_theme_constant_override("outline_size", 6)
	message.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_settings = SettingsMenu.new()
	_settings.embedded = true
	add_child(_settings)
	_codex = Codex.new()
	_codex.settings = _settings
	add_child(_codex)
	add_child(RegionMap.new())
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
	_compass = Compass.new()
	add_child(_compass)
	var stats := get_node_or_null(stats_path) as Stats
	if stats == null:
		push_warning("HUD: no Stats node at %s" % stats_path)
		return
	_stats = stats
	_style_player_frame()
	stats.health_changed.connect(_set_bar.bind(health_bar))
	stats.mana_changed.connect(_set_bar.bind(mana_bar))
	stats.stamina_changed.connect(_set_bar.bind(stamina_bar))
	stats.emit_all()
	_build_party()
	var player := stats.get_parent() as PlayerController
	if player:
		player.fatigue_changed.connect(_on_fatigue_changed)
		player.respawned.connect(func(reason: String) -> void: show_message(RESPAWN_MESSAGES.get(reason, "")))
		_combat = player.get_node_or_null("PlayerCombat") as PlayerCombat
		_targeting = player.get_node_or_null("Targeting") as Targeting
		if _targeting:
			_settings.targeting = _targeting
			_codex.targeting = _targeting
		if _combat and _targeting:
			_build_combat_hud()
		_inventory = player.get_node_or_null("Inventory") as Inventory
		if _inventory:
			_build_inventory_hud(stats)
			if _combat:
				_build_hotbar()


## A short message for the player (not dialogue), shown above the hotbar. Static so
## anything can call it: HUD.notify(node, "Backpack full").
static func notify(from: Node, text: String, color := Color(1, 0.95, 0.85), seconds := 2.0) -> void:
	var hud := from.get_tree().get_first_node_in_group("hud") if from and from.is_inside_tree() else null
	if hud:
		hud.call("show_message", text, seconds, color)


func show_message(text: String, seconds := 3.0, color := Color(1, 0.95, 0.85)) -> void:
	if text.is_empty():
		return
	message.text = text
	message.add_theme_color_override("font_color", color)
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
	if bar == health_bar:
		_tint_fill(bar, HealthColors.of(current / maxf(maximum, 1.0)))
	var l: Label = _bar_values.get(bar)
	if l:
		l.text = "%d / %d" % [ceili(current), roundi(maximum)]


## Recolours a bar's fill (and its lighter rim).
func _tint_fill(bar: ProgressBar, col: Color) -> void:
	var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill == null:
		return
	if not bar.has_meta("own_fill"):
		fill = fill.duplicate()
		bar.add_theme_stylebox_override("fill", fill)
		bar.set_meta("own_fill", true)
	fill.bg_color = col
	fill.border_color = col.lightened(0.4)


## Top left: name and level over rounded, framed health / mana / stamina bars with values.
func _style_player_frame() -> void:
	var bars := health_bar.get_parent() as VBoxContainer
	bars.add_theme_constant_override("separation", 4)
	_name_label = _label("", 17)
	bars.add_child(_name_label)
	bars.move_child(_name_label, 0)
	_refresh_name()
	_stats.level_changed.connect(func(_l: int) -> void: _refresh_name())
	var looks := [[health_bar, Color(0.86, 0.2, 0.18), 22.0], [mana_bar, Color(0.25, 0.45, 0.95), 16.0],
		[stamina_bar, Color(0.92, 0.72, 0.18), 12.0]]
	for entry in looks:
		var bar := entry[0] as ProgressBar
		var col := entry[1] as Color
		bar.custom_minimum_size = Vector2(280, entry[2])
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.045, 0.06, 0.82)
		bg.border_color = Color(0.0, 0.0, 0.0, 0.9)
		bg.set_border_width_all(2)
		bg.set_corner_radius_all(6)
		bg.shadow_color = Color(0, 0, 0, 0.35)
		bg.shadow_size = 3
		var fill := StyleBoxFlat.new()
		fill.bg_color = col
		fill.set_corner_radius_all(5)
		fill.border_color = col.lightened(0.45)
		fill.border_width_top = 2
		fill.border_width_bottom = 2
		fill.border_color = col.lightened(0.4)
		fill.expand_margin_top = -1
		fill.expand_margin_bottom = -1
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fill)
		if bar != stamina_bar:
			var value := _label("", 12 if bar == health_bar else 11)
			value.set_anchors_preset(Control.PRESET_FULL_RECT)
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			bar.add_child(value)
			_bar_values[bar] = value


func _refresh_name() -> void:
	var char_name := String(GameSession.data.get("name", _stats.display_name)) if GameSession.active() else _stats.display_name
	_name_label.text = "%s   [Level %d]" % [char_name, _stats.level]



# --- Inventory HUD ----------------------------------------------------------------

func _build_inventory_hud(stats: Stats) -> void:
	_character_window = CharacterWindow.new(_inventory, stats, _combat)
	add_child(_character_window)
	# Gold, under the clock.
	_gold = _label("", 16)
	_gold.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_gold.position = Vector2(-230, 50)
	_gold.size = Vector2(160, 24)
	_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	add_child(_gold)
	# Pickup log, right side.
	_pickups = VBoxContainer.new()
	_pickups.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_pickups.position = Vector2(-300, 40)
	_pickups.custom_minimum_size = Vector2(280, 0)
	_pickups.alignment = BoxContainer.ALIGNMENT_END
	_pickups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pickups)
	_inventory.gold_changed.connect(func(g: int) -> void: _gold.text = "%d gold" % g)
	_inventory.item_added.connect(func(id: String, count: int) -> void:
		var d := Database.item(id)
		var text := "%s%s" % [d.get("name", id), (" x%d" % count) if count > 1 else ""]
		_log_pickup("+ " + text, ItemIcon.rarity_color(d))
		GameLog.post("You receive: %s." % text, ItemIcon.rarity_color(d)))
	_gold.text = "%d gold" % _inventory.gold
	var last_gold := [_inventory.gold]
	_inventory.gold_changed.connect(func(g: int) -> void:
		if g > last_gold[0]:
			GameLog.post("You get %d gold." % (g - last_gold[0]), Color(1.0, 0.85, 0.4))
		last_gold[0] = g)


func _log_pickup(text: String, color: Color) -> void:
	var l := _label(text, 15)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pickups.add_child(l)
	var t := l.create_tween()
	t.tween_interval(2.5)
	t.tween_property(l, "modulate:a", 0.0, 0.8)
	t.tween_callback(l.queue_free)


func _progress(color: Color, size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = size
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.045, 0.06, 0.82)
	bg.border_color = Color(0, 0, 0, 0.9)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	fill.border_color = color.lightened(0.4)
	fill.border_width_top = 2
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


func _label(text: String, size := 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# --- Combat HUD -----------------------------------------------------------------

func _build_combat_hud() -> void:
	_enemy_bars = EnemyBars.new()
	_enemy_bars.targeting = _targeting
	add_child(_enemy_bars)
	# Target frame, top centre.
	_target_frame = PanelContainer.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.05, 0.045, 0.06, 0.7)
	panel.border_color = Color(0, 0, 0, 0.9)
	panel.set_border_width_all(2)
	panel.set_content_margin_all(8)
	panel.set_corner_radius_all(6)
	_target_frame.add_theme_stylebox_override("panel", panel)
	_target_frame.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target_frame.position = Vector2(-150, 50)
	_target_frame.custom_minimum_size = Vector2(300, 0)
	_target_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	_target_name = _label("", 17)
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_bar = _progress(Color(0.8, 0.18, 0.16), Vector2(284, 16))
	box.add_child(_target_name)
	box.add_child(_target_bar)
	_target_frame.add_child(box)
	_target_frame.visible = false
	add_child(_target_frame)
	_targeting.target_changed.connect(func(_t: Node3D) -> void: _refresh_target())
	_targeting.lock_changed.connect(func(_l: bool) -> void: _refresh_target())

	# Cast bar, above the hotbar.
	_cast_bar = _progress(Color(0.55, 0.6, 1.0), Vector2(300, 18))
	_cast_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_cast_bar.position = Vector2(-150, -170)
	_cast_bar.visible = false
	_cast_label = _label("", 13)
	_cast_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cast_bar.add_child(_cast_label)
	add_child(_cast_bar)

	_crosshair = Crosshair.new()
	add_child(_crosshair)
	_danger = _label("⚠ DANGER MODE", 14)
	_danger.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	_danger.tooltip_text = "Friendly NPCs can be targeted and attacked (%s to turn off)." % GameSettings.binding_label("danger_mode")
	_danger.visible = false
	health_bar.get_parent().add_child(_danger)

	_combat.cast_interrupted.connect(_on_cast_interrupted)
	_combat.notice.connect(func(text: String) -> void: show_message(text, 1.0))


func _build_hotbar() -> void:
	var game_log := GameLog.new()
	add_child(game_log)
	_hotbar = Hotbar.new(_inventory, _combat)
	stamina_bar.visible = false  # stamina is box 11 on the hotbar
	_hotbar.anchor_left = 0.5
	_hotbar.anchor_right = 0.5
	_hotbar.anchor_top = 1.0
	_hotbar.anchor_bottom = 1.0
	add_child(_hotbar)
	# Bottom centre once its size is known.
	_hotbar.resized.connect(func() -> void:
		var view := get_viewport().get_visible_rect().size
		_hotbar.position = Vector2(view.x * 0.5 - _hotbar.size.x * 0.5, view.y - _hotbar.size.y - 16)
		# The game log sits just above the hotbar and XP bar when they'd overlap.
		var lift := 52.0
		if game_log.offset_right > _hotbar.position.x:
			lift = _hotbar.size.y + 16.0 + 12.0
		game_log.offset_bottom = -lift
		game_log.offset_top = -lift - GameLog.HEIGHT)
	get_viewport().size_changed.connect(func() -> void: _hotbar.resized.emit())
	_wheel = AbilityWheel.new(_hotbar)
	add_child(_wheel)
	_spellbook = Spellbook.new(_combat, _inventory)
	add_child(_spellbook)
	var quest_log := QuestLog.new()
	add_child(quest_log)
	_codex.quest_log = quest_log
	add_child(QuestTracker.new())
	# Experience bar and the Weakened marker.
	var progress := _combat.player.get_node_or_null("Progress") as PlayerProgress
	if progress:
		progress.xp_changed.connect(set_xp)
		set_xp(progress.xp, progress.needed(), progress.level, progress.is_max_level())
		_weakened_progress = progress
		var skills := SkillWindow.new(progress)
		add_child(skills)
		_codex.skill_window = skills
		# Round status icons (ailments, buffs, healing, Weakened) under the bars.
		var icons := StatusIcons.new(_stats, progress)
		health_bar.get_parent().add_child(icons)


## The hotbar's experience bar (set by the levelling code).
func set_xp(current: int, needed: int, level: int, max_level: bool) -> void:
	if _hotbar:
		_hotbar.set_xp(current, needed, level, max_level)


func _process(delta: float) -> void:
	_process_party(delta)
	var cycle := get_tree().get_first_node_in_group("world_cycle") as WorldCycle
	_clock.visible = cycle != null
	if cycle:
		_clock.text = cycle.clock_text()
	if _combat == null:
		return
	if _target_stats:
		_target_bar.max_value = _target_stats.max_health
		_target_bar.value = _target_stats.health
		# Hostile targets get a big bar at the top instead; others sit below the bars.
		_target_frame.visible = _target_frame_on() and not _enemy_bars.shows(_targeting.target)
		_target_frame.position.y = _enemy_bars.position.y + (_enemy_bars.size.y if _enemy_bars.visible else 0.0) + 6.0
	# Cast / charge / reload bar.
	if _cast_flash > 0.0:
		_cast_flash -= delta
		if _cast_flash <= 0.0:
			_cast_bar.visible = false
	else:
		var b := _combat.bar_state()
		_cast_bar.visible = not b.is_empty()
		if not b.is_empty():
			_cast_bar.value = float(b.fraction) * 100.0
			match String(b.kind):
				"cast":
					_tint_bar(Color(0.55, 0.6, 1.0))
					_cast_label.text = String(b.name)
				"reload":
					_tint_bar(Color(0.7, 0.7, 0.72))
					_cast_label.text = String(b.name)
				_:
					_tint_bar(Color(0.95, 0.7, 0.2))
					_cast_label.text = "Full power!" if float(b.fraction) >= 1.0 else String(b.name)
	_crosshair.state = _combat.crosshair()
	_danger.visible = Combat.danger_mode
	if _weakened:
		var left := _weakened_progress.weakened_left()
		_weakened.visible = left > 0.0
		if left > 0.0:
			_weakened.text = "Weakened  %d:%02d" % [int(left) / 60, int(left) % 60]


## The target frame at the top (off by default: targets have their bar over their heads).
func _target_frame_on() -> bool:
	return bool(Database.player.get("hud", {}).get("target_frame", false))


func _refresh_target() -> void:
	var target := _targeting.target if _targeting.has_target() else null
	_target_stats = Combat.stats_of(target)
	_target_frame.visible = _target_stats != null and _target_frame_on()
	if _target_stats:
		var lock := "  [locked]" if _targeting.is_locked() else ""
		_target_name.text = "%s   Level %d%s" % [_target_stats.display_name, _target_stats.level, lock]
		var hostile := _target_stats.team == Stats.Team.ENEMIES
		_target_name.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if hostile else Color(0.6, 0.9, 1.0))


## Shows "Interrupted" / "Cancelled" on the cast bar for a moment.
func _on_cast_interrupted(reason: String) -> void:
	_cast_bar.visible = true
	_cast_bar.value = 100.0
	_tint_bar(Color(0.9, 0.3, 0.25))
	_cast_label.text = reason
	_cast_flash = 0.7


func _tint_bar(color: Color) -> void:
	var fill := _cast_bar.get_theme_stylebox("fill")
	if fill is StyleBoxFlat and (fill as StyleBoxFlat).bg_color != color:
		var sb := (fill as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.bg_color = color
		sb.border_color = color.lightened(0.4)
		_cast_bar.add_theme_stylebox_override("fill", sb)


## Screen-centre aim mark for hand-aimed ranged weapons: white, red on an enemy in range,
## tighter while aiming.
class Crosshair extends Control:
	var state := {}:
		set(v):
			if v != state:
				state = v
				queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if not state.get("visible", false):
			return
		var c := get_viewport_rect().size * 0.5 - global_position
		var col := Color(1.0, 0.3, 0.25) if state.get("red", false) else Color(1, 1, 1, 0.9)
		var gap := 5.0 if state.get("aiming", false) else 9.0
		var length := 8.0
		for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + d * gap, c + d * (gap + length), Color(0, 0, 0, 0.7), 4.0)
			draw_line(c + d * gap, c + d * (gap + length), col, 2.0)
		draw_circle(c, 2.0, col)


# --- Party (followers now; other players in co-op later) ------------------------------

var _party: VBoxContainer
var _party_rows := {}  # node -> [Label, ProgressBar]
var _party_refresh := 0.0
var _coop_label: Label


func _build_party() -> void:
	_party = VBoxContainer.new()
	_party.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_party.position = Vector2(24, 150)
	_party.add_theme_constant_override("separation", 6)
	add_child(_party)
	_coop_label = _label("", 13)
	_coop_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_coop_label.position = Vector2(-300, 8)
	_coop_label.size = Vector2(600, 20)
	_coop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coop_label.modulate = Color(1, 1, 1, 0.8)
	add_child(_coop_label)


func _process_party(delta: float) -> void:
	_party_refresh -= delta
	if _party == null or _party_refresh > 0.0:
		return
	_party_refresh = 0.2
	if Net.active:
		var count := Net.peers.size()
		if Net.is_host:
			var lan := Net.local_addresses()
			_coop_label.text = "Hosting co-op · friends join at %s (port %d) · %d joined" % [
				", ".join(lan) if not lan.is_empty() else "your IP address", Net.DEFAULT_PORT, count]
		else:
			_coop_label.text = "Co-op · %d other player%s" % [count, "" if count == 1 else "s"]
	else:
		_coop_label.text = ""
	var members := get_tree().get_nodes_in_group("party_members") + get_tree().get_nodes_in_group("followers")
	for node in _party_rows.keys():
		if not is_instance_valid(node) or not node in members:
			(_party_rows[node][0] as Control).get_parent().queue_free()
			_party_rows.erase(node)
	for node in members:
		var s := Combat.stats_of(node)
		if s == null:
			continue
		if not _party_rows.has(node):
			# Click a row to target that companion (heals then go to them).
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 2)
			row.mouse_filter = Control.MOUSE_FILTER_STOP
			row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			row.tooltip_text = "Click to target (heals go to them)"
			var who: Node3D = node
			row.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and _targeting:
					if _targeting.target == who:
						_targeting.set_target(null)
					else:
						_targeting.select_friend(who)
					row.accept_event())
			var name_label := _label(s.display_name, 14)
			name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(name_label)
			var bar := _progress(Color(0.3, 0.8, 0.35), Vector2(160, 10))
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(bar)
			_party.add_child(row)
			_party_rows[node] = [name_label, bar]
		var bar := _party_rows[node][1] as ProgressBar
		bar.value = s.health / maxf(s.max_health, 1.0) * 100.0
		_tint_fill(bar, HealthColors.of(s.health / maxf(s.max_health, 1.0)))
		var downed: bool = s.is_dead() or (node.has_method("is_downed") and node.is_downed())
		var picked: bool = _targeting != null and _targeting.target == node
		var label := _party_rows[node][0] as Label
		label.text = ("▶ " if picked else "") + s.display_name + ("  (down)" if downed else "")
		label.modulate = Color(1.0, 0.85, 0.4) if picked else (Color(1.0, 0.55, 0.5) if downed else Color.WHITE)


var _perf: PerfOverlay

## F9: show what ambient occlusion is doing (the AO buffer: white = none, dark = shaded),
## then back to normal. A quick check that it's on and how strong it is.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		# F3: frame times and what is being drawn.
		if _perf == null:
			_perf = PerfOverlay.new()
			add_child(_perf)
		_perf.toggle()
		return
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F9:
		var vp := get_viewport()
		var showing := vp.debug_draw == Viewport.DEBUG_DRAW_SSAO
		vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED if showing else Viewport.DEBUG_DRAW_SSAO
		GameLog.post("Ambient occlusion view %s (F9)" % ("off" if showing else "on: white = none, dark = occluded"), Color(0.7, 0.85, 1.0))
