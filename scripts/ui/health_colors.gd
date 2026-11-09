class_name HealthColors
extends RefCounted
## Health bar colour for players and allies: green when healthy, then yellow, orange and
## red as health drops (Database → Player → HUD). Enemies keep their red bars.

const DEFAULTS := {"health_full": "#3fbf4a", "health_half": "#e6d23a", "health_low": "#ee8a2a", "health_critical": "#d8332a"}


static func of(fraction: float) -> Color:
	var cfg: Dictionary = {}
	var loop := Engine.get_main_loop() as SceneTree
	var db := loop.root.get_node_or_null("Database") if loop else null
	if db:
		cfg = (db.get("player") as Dictionary).get("hud", {})
	var col := func(key: String) -> Color: return Color.from_string(String(cfg.get(key, DEFAULTS[key])), Color.from_string(DEFAULTS[key], Color.WHITE))
	var f := clampf(fraction, 0.0, 1.0)
	# 100–60 %: full; 60–35 %: to yellow; 35–15 %: to orange; below: to red.
	if f >= 0.6:
		return col.call("health_full")
	if f >= 0.35:
		return (col.call("health_half") as Color).lerp(col.call("health_full"), (f - 0.35) / 0.25)
	if f >= 0.15:
		return (col.call("health_low") as Color).lerp(col.call("health_half"), (f - 0.15) / 0.2)
	return (col.call("health_critical") as Color).lerp(col.call("health_low"), f / 0.15)
