class_name EnemyBars
extends Control
## Souls-style health bars across the top of the screen (under the compass) for the
## enemies fighting you and your current hostile target: the name above, no window behind,
## a bar whose width shows how tough the enemy is (enemies.json `bar_width` = % of the
## screen, else from max health between hud.enemy_bars min_width .. max_width, reaching the
## max at hp_at_max). It drains right to left, with a pale chunk showing the last hit that
## catches up after a moment. Built by the HUD; settings in player.json hud.enemy_bars.

const BAR_HEIGHT := 9.0
const ROW := 38.0

var targeting: Targeting
## enemy -> {shown: float (trailing health), hold: float}
var _trail := {}
var _list: Array[Node3D] = []


var bosses_only := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _cfg() -> Dictionary:
	var h = Database.player.get("hud", {})
	var c = h.get("enemy_bars", {}) if h is Dictionary else {}
	return c if c is Dictionary else {}


## Whether this enemy has a bar up (the target frame skips those).
func shows(node: Node) -> bool:
	return visible and _list.has(node)


func _process(delta: float) -> void:
	var cfg := _cfg()
	visible = bool(cfg.get("enabled", true))
	if not visible:
		return
	bosses_only = bool(cfg.get("bosses_only", true))
	_list = _engaged(int(cfg.get("max_bars", 3)))
	var view := get_viewport_rect().size
	position = Vector2(0, float(cfg.get("top", 50.0)))
	size = Vector2(view.x, ROW * _list.size() + 4)
	for e in _trail.keys():
		if not is_instance_valid(e) or not _list.has(e):
			_trail.erase(e)
	for e in _list:
		var st := Combat.stats_of(e)
		var t: Dictionary = _trail.get(e, {"shown": st.health, "hold": 0.0, "last": st.health})
		if st.health < float(t.last):
			t.hold = 0.6  # a hit: the chunk waits, then drains
		t.last = st.health
		if t.hold > 0.0:
			t.hold -= delta
		else:
			t.shown = maxf(st.health, float(t.shown) - st.max_health * delta * 0.6)
		t.shown = maxf(float(t.shown), st.health)
		_trail[e] = t
	queue_redraw()


static func _is_boss(e: Node) -> bool:
	var id = e.get("enemy_id")
	if id == null or String(id) == "":
		return false
	return bool(Database.enemy(String(id)).get("boss", false))


## Enemies fighting the player (or a follower), plus the hostile target, toughest first.
func _engaged(limit: int) -> Array[Node3D]:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var out: Array[Node3D] = []
	if player == null:
		return out
	var target: Node3D = targeting.target if targeting and targeting.has_target() else null
	for n in get_tree().get_nodes_in_group(Combat.GROUP):
		var e := n as Node3D
		var st := Combat.stats_of(e)
		if e == null or st == null or st.is_dead() or not Combat.is_enemy_of(player, e):
			continue
		# Ordinary enemies only have the bar over their heads; bosses get the big one.
		if bosses_only and not _is_boss(e):
			continue
		var fighting: bool = e.get("target") == player or (e.get("target") is Node and (e.get("target") as Node).is_in_group("followers"))
		if fighting or e == target:
			out.append(e)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		if a == target or b == target:
			return a == target
		return Combat.stats_of(a).max_health > Combat.stats_of(b).max_health)
	return out.slice(0, limit)


func _width_of(e: Node3D, view_w: float) -> float:
	var cfg := _cfg()
	var pct := -1.0
	var d = e.get("data")
	if not d is Dictionary and e.get("enemy_id") != null:
		d = Database.enemy(String(e.get("enemy_id")))
	if d is Dictionary and float(d.get("bar_width", 0.0)) > 0.0:
		pct = float(d.bar_width)
	if pct <= 0.0:
		var lo := float(cfg.get("min_width", 25.0))
		var hi := float(cfg.get("max_width", 80.0))
		var k := clampf(Combat.stats_of(e).max_health / maxf(float(cfg.get("hp_at_max", 2000.0)), 1.0), 0.0, 1.0)
		pct = lerpf(lo, hi, k)
	return view_w * clampf(pct, 5.0, 100.0) / 100.0


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var cfg := _cfg()
	var fill := Color.html(String(cfg.get("color", "#b3241e")))
	var chunk := Color.html(String(cfg.get("damage_color", "#e8c46a")))
	var y := 0.0
	var target: Node3D = targeting.target if targeting and targeting.has_target() else null
	for e in _list:
		var st := Combat.stats_of(e)
		var w := _width_of(e, size.x)
		var x := (size.x - w) * 0.5
		var name_text := st.display_name if st.display_name != "" else String(e.name)
		var fs := 17
		var tw := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var name_col := Color(1, 0.92, 0.85) if e != target else Color(1.0, 0.85, 0.45)
		draw_string_outline(font, Vector2(x, y + 16), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(x, y + 16), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, name_col)
		var lvl := "Lv %d" % st.level
		var lw := font.get_string_size(lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string_outline(font, Vector2(x + w - lw, y + 16), lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(x + w - lw, y + 16), lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.82, 0.78))
		var by := y + 22
		var frac := clampf(st.health / maxf(st.max_health, 1.0), 0.0, 1.0)
		var shown := clampf(float(_trail.get(e, {}).get("shown", st.health)) / maxf(st.max_health, 1.0), 0.0, 1.0)
		draw_rect(Rect2(x - 1, by - 1, w + 2, BAR_HEIGHT + 2), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(x, by, w, BAR_HEIGHT), Color(0.12, 0.05, 0.05, 0.7))
		if shown > frac:
			draw_rect(Rect2(x + w * frac, by, w * (shown - frac), BAR_HEIGHT), chunk)
		draw_rect(Rect2(x, by, w * frac, BAR_HEIGHT), fill)
		draw_rect(Rect2(x, by, w * frac, 2), fill.lightened(0.3))
		y += ROW
