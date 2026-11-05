class_name PlayerAudio
extends Node3D
## The player's own sounds: footsteps that match the ground (terrain paint, props, water),
## jumps and landings, dodges, ledge grabs, climbing and swimming.
## Lives under Player. Footfalls, strokes and climbing grabs are timed from the
## animations themselves (CharacterModel.bone_contacts), so they line up with the feet.

## Every sound this node plays (handy for debugging, and later for enemies hearing the player).
signal sound_played(sound: String, volume_db: float)

## Footstep sounds: assets/audio/footsteps/<surface>_<n>.ogg, any number per surface.
const FOOTSTEP_DIR := "res://assets/audio/footsteps"
const SURFACES := ["grass", "dirt", "stone", "wood", "water", "snow", "metal"]
const WHOOSH := preload("res://assets/audio/sfx/whoosh.ogg")
const SPLASH := preload("res://assets/audio/sfx/splash.ogg")
const STROKE := preload("res://assets/audio/sfx/swim_stroke.ogg")

const FEET := ["mixamorig_LeftFoot", "mixamorig_RightFoot"]
const HANDS := ["mixamorig_LeftHand", "mixamorig_RightHand"]
## Animation -> list of [bones, height fraction, event] for timed sounds.
const CONTACTS := {
	"walking": [[FEET, 0.2, "step"]],
	"running": [[FEET, 0.2, "step"]],
	"swimming": [[HANDS, 0.5, "stroke"], [FEET, 0.5, "kick"]],
	"treading_water": [[HANDS, 0.5, "tread"]],
	# Hands at the top of their reach = grabbing the next hold.
	"climbing_up_wall": [[["mixamorig_LeftHand"], 0.8, "grab"], [["mixamorig_RightHand"], 0.8, "grab"]],
	"climbing_down_wall": [[["mixamorig_LeftHand"], 0.8, "grab"], [["mixamorig_RightHand"], 0.8, "grab"]],
	"climbing_ladder": [[FEET, 0.3, "grab"]],
}

@export_group("Volume (dB)")
@export var walk_db := -11.0
@export var run_db := -5.0
@export var sprint_db := -2.0
@export var climb_db := -9.0
@export var swim_db := -6.0
@export var whoosh_db := -8.0
## Random spread on each sound so repeats don't sound identical.
@export var pitch_spread := 0.08
@export var volume_spread := 1.5

@onready var player: PlayerController = get_parent()
@onready var character: CharacterModel = get_node("../Model/Character")

var _feet: AudioStreamPlayer3D
var _body: AudioStreamPlayer3D
var _contacts := {}  # anim -> Array of [PackedFloat32Array times, event]
var _last_anim := ""
var _last_pos := 0.0
var _last_state := PlayerController.State.NORMAL
var _was_on_floor := true
var _fall_speed := 0.0
var _air_time := 0.0
var _streamer: ChunkStreamer
var _steps := {}  # surface -> Array of AudioStream
var _last_step := {}  # surface -> index played last (never twice in a row)


func _ready() -> void:
	_load_footsteps()
	_feet = _make_player("Feet", Vector3(0, 0.05, 0), &"Footsteps")
	_body = _make_player("Body", Vector3(0, 1.0, 0), &"SFX")
	player.jumped.connect(_on_jumped)
	player.dodged.connect(_on_dodged)
	player.action_animation.connect(_on_action_animation)
	_measure_contacts.call_deferred()


func _load_footsteps() -> void:
	for surface: String in SURFACES:
		_steps[surface] = []
	for file in ResourceLoader.list_directory(FOOTSTEP_DIR):
		if not file.ends_with(".ogg") and not file.ends_with(".wav"):
			continue
		var surface := file.get_basename().get_slice("_", 0)
		if _steps.has(surface):
			_steps[surface].append(load(FOOTSTEP_DIR.path_join(file)))


## A random footstep for a surface (not the same one twice in a row). Falls back to stone.
func _step(surface: String) -> AudioStream:
	var list: Array = _steps.get(surface, [])
	if list.is_empty():
		list = _steps.get("stone", [])
		if list.is_empty():
			return null
	var i := randi() % list.size()
	if list.size() > 1 and i == _last_step.get(surface, -1):
		i = (i + 1 + randi() % (list.size() - 1)) % list.size()
	_last_step[surface] = i
	return list[i]


func _make_player(node_name: String, offset: Vector3, bus: StringName) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.position = offset
	p.bus = bus
	p.max_polyphony = 4
	p.unit_size = 6.0
	p.max_distance = 50.0
	add_child(p)
	return p


func _measure_contacts() -> void:
	for anim: String in CONTACTS:
		_contacts[anim] = []
		for spec: Array in CONTACTS[anim]:
			_contacts[anim].append([character.bone_contacts(anim, PackedStringArray(spec[0]), spec[1]), spec[2]])


func _physics_process(delta: float) -> void:
	var state := player.state
	var on_floor := player.is_on_floor()

	# Animation-timed sounds: fire when the clip passes a contact time.
	var anim := character.current_animation()
	var pos := character.animation_position()
	if anim == _last_anim and _contacts.has(anim):
		for entry: Array in _contacts[anim]:
			for t: float in entry[0]:
				var crossed := (_last_pos < t and t <= pos) if pos >= _last_pos else (t > _last_pos or t <= pos)
				if crossed:
					_contact_event(entry[1], state, on_floor)
	_last_anim = anim
	_last_pos = pos

	# Landing after a fall.
	if state == PlayerController.State.NORMAL:
		if not on_floor:
			_air_time += delta
			_fall_speed = maxf(_fall_speed, -player.velocity.y)
		elif not _was_on_floor and _air_time > 0.2:
			_land(_fall_speed)
	if on_floor or state != PlayerController.State.NORMAL:
		# Hanging/climbing/swimming isn't falling; only count air time from here.
		_air_time = 0.0
		if on_floor:
			_fall_speed = 0.0
	_was_on_floor = on_floor

	# State changes.
	if state != _last_state:
		_on_state_changed(_last_state, state)
		_last_state = state


func _contact_event(event: String, state: int, on_floor: bool) -> void:
	match event:
		"step":
			if state != PlayerController.State.NORMAL or not on_floor:
				return
			var speed := Vector2(player.velocity.x, player.velocity.z).length()
			if speed < 0.4:
				return
			var db := walk_db
			if player.is_sprinting:
				db = sprint_db
			elif speed > player.walk_speed + 0.5:
				db = run_db
			_play(_feet, _step(ground_surface()), db)
		"stroke":
			_play(_body, STROKE, swim_db)
		"kick":
			_play(_body, STROKE, swim_db - 7.0, 0.85)
		"tread":
			_play(_body, STROKE, swim_db - 8.0, 0.8)
		"grab":
			if state == PlayerController.State.WALL_CLIMB or state == PlayerController.State.LADDER:
				var surface := "wood" if state == PlayerController.State.LADDER else _climb_surface()
				_play(_body, _step(surface), climb_db, 1.15)


func _on_state_changed(from: int, to: int) -> void:
	var S := PlayerController.State
	if to == S.SWIM:
		# Bigger splash for a bigger drop.
		var hard := clampf(_fall_speed / 12.0, 0.0, 1.0)
		_play(_body, SPLASH, lerpf(-10.0, 0.0, hard), lerpf(1.1, 0.9, hard))
	elif from == S.SWIM:
		_play(_feet, _step("water"), run_db)
	elif from == S.DODGE and to == S.NORMAL:
		_play(_feet, _step(ground_surface()), run_db, 0.9)
	elif from == S.LEDGE_CLIMB and to == S.NORMAL:
		_play(_feet, _step(ground_surface()), run_db)
	elif (to == S.WALL_CLIMB or to == S.LADDER) and from == S.NORMAL:
		var surface := "wood" if to == S.LADDER else _climb_surface()
		_play(_body, _step(surface), climb_db + 3.0, 1.1)
	if to != S.NORMAL:
		_fall_speed = 0.0


func _on_jumped() -> void:
	_play(_feet, _step(ground_surface()), run_db - 2.0, 1.05)


func _on_dodged(_anim: String, _start: float) -> void:
	_play(_body, WHOOSH, whoosh_db)
	_play(_feet, _step(ground_surface()), walk_db, 1.1)


func _on_action_animation(anim: String, _start: float, _blend: float, _speed: float) -> void:
	match anim:
		"hanging_idle":
			# Grabbing a ledge: a hand slap on the edge (not when settling after a shimmy).
			if _last_state != PlayerController.State.HANG:
				_play(_body, _step(_climb_surface()), climb_db + 2.0, 1.3)
		"hanging_hop_left", "hanging_hop_right":
			_play(_body, _step(_climb_surface()), climb_db, 1.25)
		"hanging_climb_up":
			_play(_body, WHOOSH, whoosh_db - 6.0, 0.8)


func _land(speed: float) -> void:
	var surface := ground_surface()
	var hard := clampf((speed - 3.0) / 9.0, 0.0, 1.0)
	var db := lerpf(walk_db, 0.0, hard)
	_play(_feet, _step(surface), db, lerpf(1.0, 0.85, hard))
	# Second foot a moment later.
	get_tree().create_timer(0.06).timeout.connect(
		func() -> void: _play(_feet, _step(surface), db - 3.0, lerpf(1.05, 0.9, hard)))


func _play(p: AudioStreamPlayer3D, stream: AudioStream, db: float, pitch := 1.0) -> void:
	if stream == null:
		return
	p.stream = stream
	p.volume_db = db + randf_range(-volume_spread, volume_spread)
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_spread, pitch_spread))
	p.play()
	sound_played.emit(stream.resource_path.get_file().get_basename() + ("@" + String(p.name)), p.volume_db)


# --- Surfaces -------------------------------------------------------------------

## What the player is standing on: grass, dirt, stone, wood, water, snow or metal.
func ground_surface() -> String:
	var feet := player.global_position
	if player._water_at(feet + Vector3.UP * 0.15) != null:
		return "water"
	var hit := _ray(feet + Vector3.UP * 0.3, feet + Vector3.DOWN * 0.8)
	if hit.is_empty():
		return "stone"
	return _surface_of_hit(hit)


## The surface of the wall or ledge in front of the player.
func _climb_surface() -> String:
	var forward := -player.model.global_basis.z
	var from := player.global_position + Vector3.UP * 1.2
	var hit := _ray(from, from + forward * 1.2)
	if hit.is_empty():
		hit = _ray(from + Vector3.UP * 0.8, from + Vector3.UP * 0.8 + forward * 1.2)
	return "stone" if hit.is_empty() else _surface_of_hit(hit)


func _surface_of_hit(hit: Dictionary) -> String:
	var node := hit.collider as Node
	# Tagged objects: a "surface" meta on the body or a parent (props get one automatically).
	var walk := node
	for i in 4:
		if walk == null:
			break
		if walk.has_meta("surface"):
			return String(walk.get_meta("surface"))
		if walk.is_in_group("ladder"):
			return "wood"
		walk = walk.get_parent()
	# Terrain: read the painted ground, with rock on steep slopes.
	var streamer := _get_streamer()
	if streamer and streamer.is_ancestor_of(node):
		var normal: Vector3 = hit.normal
		var paint := streamer.paint_at(hit.position)
		if paint.y > 0.5 or normal.y < 0.7:
			return "stone"
		if paint.x > 0.5:
			return "dirt"
		return "grass"
	return "stone"


func _get_streamer() -> ChunkStreamer:
	if _streamer == null or not is_instance_valid(_streamer):
		_streamer = get_tree().get_first_node_in_group("chunk_streamer") as ChunkStreamer
	return _streamer


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)
