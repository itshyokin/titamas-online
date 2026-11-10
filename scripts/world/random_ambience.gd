class_name RandomAmbience
extends Node
## A region's "Random ambience" (regions.json `random_sounds`, Database → Regions, up to 5):
## one-off sounds played somewhere off in the distance around the player.
##   when "time"     at given hours of the game clock (e.g. "5, 17": a train at 5am and 5pm)
##   when "weather"  when the weather turns to a type (e.g. "clear": cicadas as the sun
##                   comes out after rain)
##   when "random"   now and then, between min_minutes and max_minutes apart
## Optional: only "day" / "night", volume_db, distance (m; 0 = not placed, plain stereo).
## Made by AtmosphereManager.

const MAX_SOUNDS := 8

var atmosphere: Node
var _file_time := -1
var _by_region := {}  # region id -> Array of entries
var _next := {}  # "region:index" -> seconds until a random sound may play
var _last_hour := -1.0
var _last_weather := ""
var _check := 0.0


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	_reload()
	var region = atmosphere.get("current") if atmosphere else null
	if region == null:
		return
	var region_id := String((region as Object).get_meta("id", ""))
	var entries: Array = _by_region.get(region_id, [])
	var cycle := get_tree().get_first_node_in_group("world_cycle") as WorldCycle
	var hour := cycle.hour if cycle else -1.0
	var weather = atmosphere.get("weather")
	var weather_now := String(weather.get("type_id")) if weather else ""
	var day := cycle.daylight if cycle else 1.0
	for i in mini(entries.size(), MAX_SOUNDS):
		var e: Dictionary = entries[i]
		var only := String(e.get("only", ""))
		if (only == "day" and day < 0.4) or (only == "night" and day > 0.3):
			continue
		match String(e.get("when", "random")):
			"time":
				if hour < 0.0 or _last_hour < 0.0:
					continue
				for h in String(e.get("hours", "")).split(",", false):
					var at := float(h)
					# The clock passed this hour since the last check (wrapping at midnight).
					if (_last_hour <= at and hour > at) or (_last_hour > hour and (at >= _last_hour or at < hour)):
						_play(e)
			"weather":
				var want := String(e.get("weather", "clear"))
				if _last_weather != "" and weather_now != _last_weather and weather_now == want:
					_play(e)
			_:
				var key := "%s:%d" % [region_id, i]
				if not _next.has(key):
					_next[key] = _random_gap(e)
				_next[key] -= 1.0
				if _next[key] <= 0.0:
					_next[key] = _random_gap(e)
					_play(e)
	_last_hour = hour
	_last_weather = weather_now


func _random_gap(e: Dictionary) -> float:
	var lo := float(e.get("min_minutes", 2.0))
	return randf_range(lo, maxf(float(e.get("max_minutes", 6.0)), lo)) * 60.0


func _reload() -> void:
	var path := "res://data/regions.json"
	var t := DataFiles.modified_time(path)
	if t == _file_time:
		return
	_file_time = t
	_by_region.clear()
	var d = DataFiles.read(path)
	if d is Dictionary:
		for r in d.get("regions", []):
			if r is Dictionary and r.get("random_sounds") is Array:
				_by_region[String(r.get("id", ""))] = r.random_sounds


func _play(e: Dictionary) -> void:
	var path := String(e.get("sound", ""))
	if path == "" or not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	var dist := float(e.get("distance", 60.0))
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var p: Node
	if dist > 0.0 and player:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.bus = &"Ambience"
		p3.volume_db = float(e.get("volume_db", 0.0)) + 12.0  # far away: make up for the distance
		p3.unit_size = dist * 0.5
		p3.max_distance = dist * 4.0
		p3.attenuation_filter_cutoff_hz = 6000.0
		add_child(p3)
		var a := randf() * TAU
		p3.global_position = player.global_position + Vector3(cos(a), 0.15, sin(a)) * dist
		p = p3
		p3.play()
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = stream
		p2.bus = &"Ambience"
		p2.volume_db = float(e.get("volume_db", 0.0))
		add_child(p2)
		p = p2
		p2.play()
	p.connect("finished", p.queue_free)


## For testing / events: plays a region entry now.
func play_now(region_id: String, index: int) -> void:
	_reload()
	var entries: Array = _by_region.get(region_id, [])
	if index < entries.size():
		_play(entries[index])
