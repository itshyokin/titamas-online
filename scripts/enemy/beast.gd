class_name Beast
extends Enemy
## A non-human enemy with a body built from shapes (BeastModel) instead of the humanoid
## rig: flying bats that hover out of sword reach and swoop to bite, and the dragon boss
## (bite, tail sweep, fire breath, fireballs, and flight phases where it circles overhead),
## and the troll boss: from afar it hurls rocks (a red ring marks where each will land:
## dodge it); up close it raises both fists and smashes the ground, knocking everyone near
## it off their feet. The wind-up is long: hit it a few times, then roll clear.
## Everything else (health, loot, respawn, co-op, xp) is Enemy's. Settings are the
## enemies.json entry's "beast" block (Database → Enemies → Beast).

const ROAR := preload("res://assets/audio/creatures/dragon_roar.ogg")
const FLAP := preload("res://assets/audio/creatures/wing_flap.ogg")
const BREATH := preload("res://assets/audio/creatures/fire_breath.ogg")
const SCREECH := preload("res://assets/audio/creatures/bat_screech.ogg")
const LAND := preload("res://assets/audio/creatures/dragon_land.ogg")
const TROLL_ROAR := preload("res://assets/audio/creatures/troll_roar.ogg")
const TROLL_GRUNT := preload("res://assets/audio/creatures/troll_grunt.ogg")
const SMASH := preload("res://assets/audio/creatures/ground_smash.ogg")
const WHOOSH := preload("res://assets/audio/creatures/rock_whoosh.ogg")
const RING := "res://assets/effects/builtin/ring.png"

var body: BeastModel
var cfg := {}
var big := false            # the dragon / troll: no knockback/knockdown, bigger hit radius
var troll := false
var flying := false         # always in the air (bats)
var airborne := false
var fly_height := 2.6
## Melee reaches this much further than its origin (its body's radius), see Combat.radius_of.
var body_radius := 0.3
## Flyers hide the disposition ring (it would float in the air under them).
var hide_disc := false

var _ground_y := 0.0
var _alt := 0.0
var _alt_goal := 0.0
var _plan := ""
var _att_len := 1.0
var _phase_left := 0.0
var _phases_done := 0
var _shoot := 0.0
var _roared := false
var _flap_t := 0.0
var _breath_fx: FireBreath = null
var _breath_tick := 0.0
var _spin_from := 0.0
var _net_pose_t := 0.0
var _fireball: Ability
var _throw_left := 0.0      # troll: seconds until it may throw again
var _smash_marker: MeshInstance3D
var _steps_heard := 0


func _ready() -> void:
	cfg = Database.enemy(enemy_id).get("beast", {})
	var kind := String(cfg.get("body", "bat"))
	troll = kind == "troll"
	big = kind == "dragon" or troll
	body = BeastModel.create(kind, DataFiles.color_from(cfg.get("color", "#4a3a34")), float(cfg.get("scale", 1.0)))
	model.add_child(body)
	flying = bool(cfg.get("flying", not big))
	fly_height = float(cfg.get("fly_height", 2.6))
	airborne = flying
	hide_disc = flying
	# Flyers only bump into the world: never land on (and stick to) heads.
	if flying:
		collision_mask = 1
	_alt = fly_height if airborne else 0.0
	_alt_goal = _alt
	body_radius = float(cfg.get("radius", (1.5 if troll else 2.2) if big else 0.3))
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape:
		var cap := CapsuleShape3D.new()
		cap.radius = body_radius
		cap.height = maxf(float(cfg.get("height", (5.2 if troll else 4.6) if big else 0.7)), body_radius * 2.0)
		shape.shape = cap
		shape.position = Vector3.UP * cap.height * 0.5
	body.position.y = 0.0 if big else 0.35
	_fireball = Ability.new()
	_fireball.id = "beast_fireball"
	_fireball.display_name = "Fireball"
	_fireball.delivery = Ability.Delivery.PROJECTILE
	_fireball.projectile_style = Ability.ProjectileStyle.BOLT
	_fireball.projectile_color = Color(1.0, 0.45, 0.1)
	_fireball.projectile_speed = float(cfg.get("fireball_speed", 15.0))
	_fireball.reach = 80.0
	_fireball.knockback = 5.0
	_fireball.color = Color(1.0, 0.45, 0.1)
	super._ready()
	if _plate:
		_plate.position.y = float(cfg.get("plate_height", 1.0 if not big else 6.0))
	var disc := get_node_or_null("DispositionDisc") as Node3D
	if disc:
		disc.scale = Vector3.ONE * (body_radius / 0.45 if big else 1.0)


func _equip() -> void:
	pass


func aim_point() -> Vector3:
	return global_position + Vector3.UP * float(cfg.get("aim_height", (3.2 if troll else 2.6) if big else 0.35))


# --- Movement ---------------------------------------------------------------------

func _ground_below(from: Vector3, up := 3.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * up, from + Vector3.DOWN * 120.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return INF if hit.is_empty() else float(hit.position.y)


func _physics_process(delta: float) -> void:
	_pose_tick(delta)
	if _is_puppet():
		_puppet_update(delta)
		_net_pose_t += delta
		return
	if not _settled:
		var g := _ground_below(global_position, 60.0)
		if g == INF:
			return
		_settled = true
		global_position.y = g + (fly_height if airborne else 0.05)
		_home = global_position
		_wander_to = _home
	_cooldown = maxf(_cooldown - delta, 0.0)
	var g := _ground_below(global_position)
	if g != INF:
		_ground_y = g
	_update_threat(delta)
	var move := _ai_move(delta)
	_walk.x = lerpf(_walk.x, move.x, 6.0 * delta)
	_walk.z = lerpf(_walk.z, move.z, 6.0 * delta)
	velocity.x = _walk.x + _push.x
	velocity.z = _walk.z + _push.z
	_push = _push.move_toward(Vector3.ZERO, 16.0 * delta)
	var falling := ai == AI.DEAD or ai == AI.DOWN
	if airborne and not falling:
		_alt = lerpf(_alt, _alt_goal, 1.0 - exp(-3.0 * delta))
		var want := _ground_y + _alt
		velocity.y = clampf((want - global_position.y) * 4.0, -12.0, 9.0)
	elif not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.5
	if move.length() > 0.1 and ai != AI.ATTACK:
		_face(global_position + move, delta)
	move_and_slide()
	_animate()


func _ai_move(delta: float) -> Vector3:
	if ai == AI.ATTACK:
		return _attack_move(delta)
	if ai == AI.IDLE and flying:
		# Bats flit about a little while they hover.
		_alt_goal = fly_height + sin(Time.get_ticks_msec() / 700.0 + get_instance_id() % 10) * 0.3
	return super._ai_move(delta)


func _chase(delta: float) -> Vector3:
	if not _target_valid() or global_position.distance_to(_home) > leash_distance:
		_give_up()
		return Vector3.ZERO
	var to := target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if troll:
		return _troll_chase(delta, to, d)
	if big:
		return _dragon_chase(delta, to, d)
	# Bats: hover over to the target, then swoop.
	_alt_goal = fly_height
	if d <= float(cfg.get("swoop_range", 3.5)) and _cooldown <= 0.0:
		_begin("swoop", 1.4)
		return Vector3.ZERO
	if d < 1.5:
		return -to.normalized() * walk_speed  # back off to swoop again
	return to.normalized() * run_speed


func _dragon_chase(delta: float, to: Vector3, d: float) -> Vector3:
	if not _roared:
		_roared = true
		_begin("roar", 2.2)
		return Vector3.ZERO
	# Flight phases at health thresholds.
	var at_raw = cfg.get("flight_at", [0.66, 0.33])
	var at: Array = []
	for v in (at_raw.split(",", false) if at_raw is String else at_raw):
		at.append(float(v))
	if not airborne and _phases_done < at.size() and stats.health / maxf(stats.max_health, 1.0) <= float(at[_phases_done]):
		_phases_done += 1
		_take_off()
	if airborne:
		return _circle(delta, to, d)
	var fwd := -model.global_basis.z
	fwd.y = 0.0
	var angle := rad_to_deg(fwd.angle_to(to.normalized())) if d > 0.1 else 0.0
	if _cooldown <= 0.0:
		var bite_range := float(cfg.get("bite_range", 4.5)) + body_radius
		if d <= bite_range and angle < 45.0:
			_begin("bite", 1.3)
			return Vector3.ZERO
		if d <= float(cfg.get("tail_range", 6.0)) + body_radius * 0.5 and angle > 100.0:
			_begin("tail", 1.7)
			return Vector3.ZERO
		if d <= float(cfg.get("breath_range", 11.0)) and angle < 40.0 and randf() < 0.02:
			_begin("breath", 3.0)
			return Vector3.ZERO
		if d > 16.0 and randf() < 0.02:
			_begin("fireball", 1.3)
			return Vector3.ZERO
	_face(target.global_position, delta * 0.5)
	if d > float(cfg.get("bite_range", 4.5)) + body_radius * 0.6:
		return to.normalized() * (run_speed if d > 10.0 else walk_speed)
	return Vector3.ZERO


## The troll: rocks from afar, the ground smash up close, lumbering in between.
func _troll_chase(delta: float, to: Vector3, d: float) -> Vector3:
	_throw_left = maxf(_throw_left - delta, 0.0)
	if not _roared:
		_roared = true
		_begin("roar", 2.0)
		return Vector3.ZERO
	var smash_reach := float(cfg.get("smash_range", 3.5)) + body_radius
	if _cooldown <= 0.0:
		if d <= smash_reach:
			_begin("smash", _smash_length())
			return Vector3.ZERO
		if d >= float(cfg.get("throw_min", 9.0)) and d <= float(cfg.get("throw_max", 40.0)) and _throw_left <= 0.0:
			_begin("throw", float(cfg.get("throw_time", 1.9)))
			return Vector3.ZERO
	_face(target.global_position, delta * 0.8)
	if d > smash_reach * 0.7:
		return to.normalized() * (run_speed if d > 16.0 else walk_speed)
	return Vector3.ZERO


func _smash_length() -> float:
	return float(cfg.get("smash_windup", 1.9)) + 0.3 + float(cfg.get("smash_recover", 1.3))


## Where the fists come down: in front of it.
func _smash_point() -> Vector3:
	var fwd := -model.global_basis.z
	fwd.y = 0.0
	return global_position + fwd.normalized() * (body_radius + 1.8)


## A red ring on the ground showing how far the smash reaches, filling in as it winds up.
func _show_smash_marker() -> void:
	_hide_smash_marker()
	var radius := float(cfg.get("smash_radius", 6.0))
	_smash_marker = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2.ONE * radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = AbilityFX.texture(RING)
	mat.albedo_color = Color(1.0, 0.3, 0.15, 0.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	PixelArt.crisp(mat)
	q.material = mat
	_smash_marker.mesh = q
	_smash_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Combat.world_root(self).add_child(_smash_marker)
	var at := _smash_point()
	var g := _ground_below(at)
	_smash_marker.global_position = Vector3(at.x, (g if g != INF else at.y) + 0.07, at.z)


func _hide_smash_marker() -> void:
	if is_instance_valid(_smash_marker):
		_smash_marker.queue_free()
	_smash_marker = null


## The fists hit the ground: everyone within the radius is hurt and knocked down.
func _smash() -> void:
	_hide_smash_marker()
	var at := _smash_point()
	var g := _ground_below(at)
	if g != INF:
		at.y = g
	var radius := float(cfg.get("smash_radius", 6.0))
	var down := float(cfg.get("smash_down", 1.6))
	for n in Combat.enemies_near(self, at, radius):
		if absf(n.global_position.y - at.y) > 3.0:
			continue
		Combat.hit(self, n, attack_power * float(cfg.get("smash_power", 2.0)), true, float(cfg.get("smash_knockback", 7.0)),
			[{"status": "knockdown", "chance": 1.0, "seconds": down}])
	var root := Combat.world_root(self)
	Effects.shockwave(root, at, radius, Color(0.75, 0.66, 0.5))
	for i in 10:
		var chip := TrollRock.Chip.new()
		chip.velocity = Vector3(randf_range(-5, 5), randf_range(4, 8), randf_range(-5, 5))
		root.add_child(chip)
		chip.global_position = at + Vector3.UP * 0.3
	Combat.play_sound(self, SMASH, 6.0, randf_range(0.9, 1.05))
	_shake(0.9)


func _throw_rock() -> void:
	if not _target_valid() or body.hand_r == null:
		return
	var from := body.hand_r.global_position
	var aim := target.global_position
	var flat := Vector2(aim.x - from.x, aim.z - from.z).length()
	var seconds := clampf(flat / maxf(float(cfg.get("throw_speed", 18.0)), 1.0), 0.7, 2.4)
	# Aims where you're heading, a little (throw_lead 1 = exactly where you'll be).
	if target is CharacterBody3D:
		var v := (target as CharacterBody3D).velocity
		aim += Vector3(v.x, 0.0, v.z) * seconds * float(cfg.get("throw_lead", 0.6))
	var g := _ground_below(aim)
	if g != INF:
		aim.y = g
	TrollRock.throw_at(from, aim + Vector3.UP * 0.3, seconds, self, attack_power * float(cfg.get("throw_power", 1.1)),
		float(cfg.get("throw_knockback", 6.0)), float(cfg.get("throw_splash", 1.8)))
	Combat.play_sound(self, WHOOSH, 2.0, randf_range(0.85, 1.0))
	_throw_left = float(cfg.get("throw_every", 3.5))


func _take_off() -> void:
	airborne = true
	_alt = 0.0
	_alt_goal = float(cfg.get("flight_height", 9.0))
	_phase_left = float(cfg.get("flight_seconds", 14.0))
	_shoot = 1.5
	Combat.play_sound(self, ROAR, 4.0, 1.1)
	FloatingText.spawn(self, "Takes to the sky!", Color(1.0, 0.7, 0.3), 1.6)


## In the air: circles the target, raining fireballs, then lands.
func _circle(delta: float, to: Vector3, d: float) -> Vector3:
	_phase_left -= delta
	if _phase_left <= 0.0:
		_alt_goal = 0.0
		if global_position.y - _ground_y < 0.6:
			airborne = false
			_alt = 0.0
			Combat.play_sound(self, LAND, 4.0)
			_shake(0.6)
		return Vector3.ZERO
	_shoot -= delta
	if _shoot <= 0.0:
		_shoot = float(cfg.get("flight_fire_every", 2.4))
		_begin("fireball", 1.0)
	_face(target.global_position, delta)
	return _circle_move(to, d)


func _circle_move(to: Vector3, d: float) -> Vector3:
	var radius := float(cfg.get("circle_radius", 12.0))
	var dir := to.normalized() if d > 0.1 else Vector3.FORWARD
	var tangent := dir.cross(Vector3.UP)
	return tangent * run_speed * 1.4 + dir * clampf(d - radius, -6.0, 6.0) * 0.8


# --- Attacks ----------------------------------------------------------------------

func _begin(plan: String, seconds: float) -> void:
	ai = AI.ATTACK
	_plan = plan
	_att_len = seconds
	_attack_time = 0.0
	_attack_hit = false
	_breath_tick = 0.0
	_spin_from = model.rotation.y
	if _target_valid() and not big:
		_face(target.global_position, 0.0)
	match plan:
		"roar":
			Combat.play_sound(self, TROLL_ROAR if troll else ROAR, 6.0)
		"smash":
			Effects.flash(model, Color(1.0, 0.55, 0.1), 0.6, 0.6)
			FloatingText.spawn(self, "!", Color(1.0, 0.6, 0.2), 1.6)
			Combat.play_sound(self, TROLL_GRUNT, 4.0, 0.8)
			_show_smash_marker()
			if _target_valid():
				_face(target.global_position, 0.0)
			body.slam_at = (float(cfg.get("smash_windup", 1.9)) + 0.15) / _att_len
		"throw":
			Combat.play_sound(self, TROLL_GRUNT, 2.0, 1.1)
			body.release_at = clampf(float(cfg.get("throw_release", 0.68)), 0.4, 0.85)
		"tail", "breath":
			# The tell, like a humanoid's heavy swing.
			Effects.flash(model, Color(1.0, 0.55, 0.1), 0.5, 0.6)
			FloatingText.spawn(self, "!", Color(1.0, 0.6, 0.2), 1.2)
		"swoop":
			Combat.play_sound(self, SCREECH, -4.0, randf_range(0.9, 1.15))
			Effects.flash(model, Color(1.0, 0.3, 0.2), 0.25, 0.5)


func _attack_move(delta: float) -> Vector3:
	_attack_time += delta
	var k := _attack_time / _att_len
	var move := Vector3.ZERO
	var power := attack_power
	match _plan:
		"roar":
			if _attack_time > 0.5 and _attack_time - delta <= 0.5:
				_shake(0.5)
		"throw":
			if _target_valid():
				_face(target.global_position, delta * 1.5)
			body.holding_rock = k > 0.3 and not _attack_hit
			if not _attack_hit and k >= body.release_at:
				_attack_hit = true
				body.holding_rock = false
				_throw_rock()
		"smash":
			var windup := float(cfg.get("smash_windup", 1.9))
			if is_instance_valid(_smash_marker):
				var m := (_smash_marker.mesh as QuadMesh).material as StandardMaterial3D
				var fill := clampf(_attack_time / windup, 0.0, 1.0)
				m.albedo_color.a = 0.25 + 0.6 * fill
				_smash_marker.scale = Vector3.ONE * lerpf(0.35, 1.0, fill)
			if not _attack_hit and _attack_time >= windup + 0.15:
				_attack_hit = true
				_smash()
		"bite":
			if not _attack_hit and _attack_time >= 0.7:
				_attack_hit = true
				_strike_arc(float(cfg.get("bite_range", 4.5)) + body_radius + 0.8, 80.0, power * float(cfg.get("bite_power", 1.4)), true, 7.0, [])
		"tail":
			# A full turn; the tail sweeps everything around it.
			var spin := smoothstep(0.25, 0.8, k) * TAU
			model.rotation.y = _spin_from + spin
			if not _attack_hit and k >= 0.5:
				_attack_hit = true
				_strike_arc(float(cfg.get("tail_range", 6.0)) + body_radius, 360.0, power * float(cfg.get("tail_power", 1.6)), true, 10.0,
					[{"status": "knockdown", "chance": 1.0, "seconds": 1.6}])
		"breath":
			if _target_valid():
				_face(target.global_position, delta * 0.6)  # sweeps slowly after you
			var on := _attack_time > 0.6 and _attack_time < _att_len - 0.4
			if on and _breath_fx == null:
				_breath_fx = FireBreath.new()
				_breath_fx.source = body.mouth
				Combat.world_root(self).add_child(_breath_fx)
				Combat.play_sound(self, BREATH, 4.0)
			if not on and _breath_fx:
				_breath_fx.stop()
				_breath_fx = null
			if on:
				_breath_tick -= delta
				if _breath_tick <= 0.0:
					_breath_tick = 0.25
					_breath_damage(power * float(cfg.get("breath_power", 0.5)))
		"fireball":
			if not _attack_hit and k >= 0.55:
				_attack_hit = true
				if _target_valid():
					var from := body.mouth.global_position
					var at := Combat.aim_point(target)
					Projectile.launch(from, self, null, _fireball, power * float(cfg.get("fireball_power", 1.2)), at - from)
					Combat.play_sound(self, BREATH, 0.0, 1.5)
			if _target_valid():
				_face(target.global_position, delta)
			if airborne and _target_valid():
				var flat := target.global_position - global_position
				flat.y = 0.0
				move = _circle_move(flat, flat.length()) * 0.6
		"swoop":
			if _target_valid():
				var aim := Combat.aim_point(target)
				if k < 0.25:
					_alt_goal = fly_height + 0.5  # rears up
					move = (global_position - aim) * Vector3(1, 0, 1)
					move = move.normalized() * 1.5 if move.length() > 0.1 else Vector3.ZERO
				elif k < 0.6:
					_alt_goal = maxf(aim.y - _ground_y - 0.35, 0.5)
					var to := aim - aim_point()
					to.y = 0.0
					move = to.normalized() * float(cfg.get("swoop_speed", 9.0)) if to.length() > 0.3 else -model.global_basis.z * 4.0
					_face(aim, delta * 2.0)
					if not _attack_hit and aim_point().distance_to(aim) < float(cfg.get("bite_reach", 1.3)):
						_attack_hit = true
						Combat.hit(self, target, power, false, knockback, Database.enemy(enemy_id).get("applies", []))
				else:
					_alt_goal = fly_height
					move = -model.global_basis.z * 4.0
	if _attack_time >= _att_len:
		_end_attack()
	return move


func _end_attack() -> void:
	_hide_smash_marker()
	if body:
		body.holding_rock = false
	if _breath_fx:
		_breath_fx.stop()
		_breath_fx = null
	_cooldown = attack_cooldown * randf_range(0.8, 1.2)
	_plan = ""
	if ai == AI.ATTACK:
		ai = AI.CHASE


## Hits everyone it's fighting within `reach` and the arc in front (360 = all round).
func _strike_arc(reach: float, arc: float, power: float, heavy: bool, push: float, applies: Array) -> void:
	var fwd := -model.global_basis.z
	fwd.y = 0.0
	for n in Combat.enemies_near(self, global_position, reach):
		var to := n.global_position - global_position
		to.y = 0.0
		if arc < 359.0 and to.length() > 0.5 and rad_to_deg(fwd.angle_to(to.normalized())) > arc * 0.5:
			continue
		if absf(n.global_position.y - global_position.y) > 4.0:
			continue
		Combat.hit(self, n, power, heavy, push, applies)
	_shake(0.35 if heavy else 0.15)


## Fire breath: everyone in the cone in front of the mouth burns.
func _breath_damage(power: float) -> void:
	var from := body.mouth.global_position
	var dir := -model.global_basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var reach := float(cfg.get("breath_range", 11.0))
	for n in Combat.enemies_near(self, from, reach + 1.0):
		var to := Combat.aim_point(n) - from
		var flat := Vector3(to.x, 0, to.z)
		if flat.length() < 0.5 or rad_to_deg(dir.angle_to(flat.normalized())) < float(cfg.get("breath_angle", 22.0)):
			Combat.hit(self, n, power, false, 1.0, [{"status": "burning", "chance": 0.35, "seconds": 4.0}])


func _shake(amount: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or player.global_position.distance_to(global_position) > 30.0:
		return
	var cam := get_tree().get_first_node_in_group("player_camera")
	if cam:
		cam.call("shake", amount)


# --- Reactions --------------------------------------------------------------------

func apply_knockback(push: Vector3) -> void:
	if big:
		return
	super.apply_knockback(push)


func knock_down(push: Vector3, seconds := 1.8) -> void:
	if big or ai == AI.DEAD or ai == AI.DOWN or _is_puppet():
		return
	# Flyers drop out of the air and flap about on the ground for a moment.
	ai = AI.DOWN
	_down_left = seconds
	_walk = Vector3.ZERO
	_push = push
	_end_breath()
	FloatingText.spawn(self, "Knocked down", Color(1.0, 0.75, 0.35), 0.9)


func _get_up() -> void:
	ai = AI.STAGGER
	_stagger = 0.4
	body.pose = ""


func stagger(seconds := 0.7) -> void:
	if ai == AI.DEAD or ai == AI.DOWN:
		return
	if big and ai == AI.ATTACK:
		return  # too big to interrupt mid-attack
	if ai == AI.ATTACK:
		_end_attack()
	ai = AI.STAGGER
	_stagger = seconds * (0.4 if big else 1.0)
	body.pose = "hurt"
	body.pose_t = 0.0
	FloatingText.spawn(self, "Staggered", Color(1.0, 0.8, 0.4), 0.8)


func _on_damaged(_amount: float, source: Node, _crit: bool) -> void:
	_note_damage(_amount, source)
	if source is Node3D:
		var away := global_position - (source as Node3D).global_position
		away.y = 0.0
		_killer_dir = away.normalized()
	if ai == AI.RETURN or ai == AI.DEAD:
		return
	if source is Node3D and target == null:
		_engage(source)


func _end_breath() -> void:
	if _breath_fx:
		_breath_fx.stop()
		_breath_fx = null


func _on_died() -> void:
	ai = AI.DEAD
	_end_breath()
	_hide_smash_marker()
	body.holding_rock = false
	_plan = ""
	_loot = LootBag.drop_for(Database.enemy(enemy_id), Combat.world_root(self), global_position, self)
	credit_kill()
	var forever := _record_death()
	target = null
	collision_layer = 0
	_walk = Vector3.ZERO
	if not death_sounds.is_empty():
		Combat.play_sound(self, death_sounds.pick_random(), 2.0, randf_range(0.92, 1.08) * (0.5 if big else 1.6))
	elif big:
		Combat.play_sound(self, TROLL_ROAR if troll else ROAR, 6.0, 0.75)
	body.pose = "dead"
	body.flapping = false
	airborne = false
	await get_tree().create_timer(corpse_time).timeout
	var waited := corpse_time
	while is_instance_valid(_loot) and (_loot.open or waited < loot_time):
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if is_instance_valid(_loot):
		_loot.queue_free()
	_loot = null
	await _fade_body(1.0)
	model.visible = false
	_fade_body(0.0, 0.0)
	if forever:
		_set_present(false)
		return
	await get_tree().create_timer(maxf(respawn_time - waited, 5.0)).timeout
	_respawn()


func _respawn() -> void:
	tagged_by_player = false
	global_position = _home
	velocity = Vector3.ZERO
	stats.restore()
	collision_layer = 4
	model.visible = true
	ai = AI.IDLE
	airborne = flying
	_alt = fly_height if airborne else 0.0
	_alt_goal = _alt
	_phases_done = 0
	_roared = false
	_throw_left = 0.0
	body.pose = ""
	_wait = randf_range(1.0, 3.0)


func _give_up() -> void:
	_end_breath()
	_hide_smash_marker()
	_plan = ""  # whatever it was in the middle of
	if body:
		body.holding_rock = false
	super._give_up()
	if big:
		_roared = false
		if airborne:
			_alt_goal = 0.0
			_phase_left = 0.0


func _return_home(delta: float) -> Vector3:
	if airborne and not flying and global_position.y - _ground_y < 0.6:
		airborne = false
	return super._return_home(delta)


# --- Co-op ------------------------------------------------------------------------

func net_state(path: NodePath) -> Array:
	var p := global_position
	return [path, p.x, p.y, p.z, model.rotation.y, body.pose, 1.0, stats.health, stats.max_health, ai, model.visible]


func apply_net_state(s: Array) -> void:
	_net_pos = Vector3(s[1], s[2], s[3])
	_net_yaw = s[4]
	if not _net_seen:
		_net_seen = true
		global_position = _net_pos
	var pose := String(s[5])
	if pose != _net_anim:
		_net_anim = pose
		_net_pose_t = 0.0
	var was_dead := stats.is_dead()
	stats.max_health = float(s[8])
	stats.health = float(s[7])
	stats.health_changed.emit(stats.health, stats.max_health)
	ai = int(s[9]) as AI
	model.visible = bool(s[10])
	collision_layer = 0 if ai == AI.DEAD else 4
	if not was_dead and stats.is_dead():
		target = null


# --- Animation --------------------------------------------------------------------

func _pose_tick(delta: float) -> void:
	if body == null:
		return
	if _is_puppet():
		body.pose = _net_anim
		body.pose_t = clampf(_net_pose_t / 1.5, 0.0, 1.0)
		body.flapping = ai != AI.DEAD and (flying or global_position.y - _ground_y > 0.8)
		return
	if ai == AI.DEAD:
		body.pose = "dead"
	elif ai == AI.ATTACK:
		body.pose = _plan
		body.pose_t = _attack_time / maxf(_att_len, 0.01)
	elif ai == AI.STAGGER and body.pose == "hurt":
		body.pose_t = minf(body.pose_t + delta * 2.0, 1.0)
	elif ai != AI.STAGGER:
		body.pose = ""
	body.flapping = ai != AI.DEAD and ai != AI.DOWN and (airborne or (big and _alt_goal > 0.1))
	hide_disc = flying or airborne
	body.flap_speed = 1.6 if _plan == "swoop" else 1.0
	# The troll's heavy footsteps: a thud and a little shake each stride.
	if troll and body.steps != _steps_heard:
		_steps_heard = body.steps
		Combat.play_sound(self, LAND, -4.0, randf_range(1.25, 1.45))
		_shake(0.06)
	# Wing beats are heard on the big one.
	if big and body.flapping:
		_flap_t -= delta
		if _flap_t <= 0.0:
			_flap_t = 1.0 / 0.55
			Combat.play_sound(self, FLAP, 2.0, randf_range(0.85, 1.0))


func _animate() -> void:
	if body == null:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	body.moving = clampf(speed / maxf(walk_speed, 0.1), 0.0, 1.0) if not airborne else 0.0
	body.look_point = Combat.aim_point(target) if target and is_instance_valid(target) else Vector3.INF


## Flames streaming from the mouth: hand-moved glowing blobs (shows in every renderer).
class FireBreath:
	extends Node3D
	var source: Node3D
	var _blobs: Array = []  # [mesh, velocity, age]
	var _spawn := 0.0
	var _stopping := false
	var _mat: StandardMaterial3D
	var _mesh: SphereMesh

	func _ready() -> void:
		top_level = true
		_mesh = SphereMesh.new()
		_mesh.radius = 0.3
		_mesh.height = 0.6
		_mesh.radial_segments = 8
		_mesh.rings = 4
		var light := OmniLight3D.new()
		light.name = "Light"
		light.light_color = Color(1.0, 0.55, 0.2)
		light.light_energy = 4.0
		light.omni_range = 10.0
		add_child(light)

	func stop() -> void:
		_stopping = true

	func _process(delta: float) -> void:
		var ok := source != null and is_instance_valid(source)
		if ok:
			global_position = source.global_position
		if not _stopping and ok:
			_spawn -= delta
			while _spawn <= 0.0:
				_spawn += 0.025
				var mi := MeshInstance3D.new()
				mi.mesh = _mesh
				var m := StandardMaterial3D.new()
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				m.albedo_color = Color(1.0, 0.7, 0.25, 0.9)
				mi.material_override = m
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				mi.top_level = true
				mi.global_position = source.global_position
				var dir := -source.global_basis.z
				dir.y = minf(dir.y, 0.0) - 0.25
				var spread := Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * 0.18
				_blobs.append([mi, (dir.normalized() + spread) * randf_range(11.0, 15.0), 0.0])
		for i in range(_blobs.size() - 1, -1, -1):
			var b: Array = _blobs[i]
			var mi: MeshInstance3D = b[0]
			b[2] = float(b[2]) + delta
			var age: float = b[2]
			b[1] = (b[1] as Vector3) * (1.0 - delta * 1.2) + Vector3.UP * delta * 2.5
			mi.global_position += (b[1] as Vector3) * delta
			mi.scale = Vector3.ONE * (0.4 + age * 3.2)
			var m := mi.material_override as StandardMaterial3D
			var life := clampf(age / 0.8, 0.0, 1.0)
			m.albedo_color = Color(1.0, lerpf(0.75, 0.25, life), lerpf(0.3, 0.05, life), (1.0 - life) * 0.85)
			if age >= 0.8:
				mi.queue_free()
				_blobs.remove_at(i)
		var light := get_node_or_null("Light") as OmniLight3D
		if light:
			light.light_energy = 0.0 if _stopping else 4.0 + randf() * 1.5
		if _stopping and _blobs.is_empty():
			queue_free()
