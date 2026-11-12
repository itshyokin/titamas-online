class_name MageSpells
extends RefCounted
## What the newer spell types do when they go off (PlayerCombat._land calls these):
##   CHAIN   lightning: hits the target, then jumps to the nearest enemy not hit yet within
##           chain.range, up to chain.jumps times, × chain.falloff each jump
##   HEAL    restores power (+ 1.5 × spell power) at once to a friend or yourself
##   CONE    a wave in front: everyone within reach and arc is hit as the wall reaches them
##   GROUND  on a clicked spot (PlayerCombat picks it): ground.kind "teleport" (Blink) or
##           "cloud" (Dark Cloud)
## Settings are the ability's abilities.json extras (Database → Abilities).
## In --script tests load() it (it uses Combat, which uses autoloads).


static func _play(pc: PlayerCombat, ab: Ability, at: Node3D, volume := -3.0) -> void:
	if ab.release_sound:
		Combat.play_sound(at, ab.release_sound, volume)
	elif ab.sounds.size() > 0:
		Combat.play_sound(at, ab.sounds.pick_random(), volume)


# --- Chain lightning ---------------------------------------------------------------

static func chain(pc: PlayerCombat, ab: Ability, power: float, first: Node3D, hand: Vector3) -> void:
	var player := pc.player
	var d: Dictionary = Ability.data_of(ab).get("chain", {})
	var jumps := int(d.get("jumps", 3))
	var reach := float(d.get("range", 8.0))
	var falloff := float(d.get("falloff", 0.75))
	var root := Combat.world_root(player)
	_play(pc, ab, player, -2.0)
	if first == null:
		# Nothing to hit: a crackle into the air in front.
		SpellFX.lightning(root, hand, hand - player.model.global_basis.z * 6.0 + Vector3.UP * 0.5, ab.projectile_color)
		return
	var hit: Array[Node3D] = [first]
	var from := hand
	var current := first
	var strength := power
	for i in jumps + 1:
		var target := current
		var start := from
		var amount := strength
		var delay := 0.09 * i
		var strike := func() -> void:
			if not is_instance_valid(target) or not is_instance_valid(player):
				return
			var to := Combat.aim_point(target)
			SpellFX.lightning(root, start, to, ab.projectile_color)
			Combat.hit(player, target, amount, ab.staggers, ab.knockback, Ability.applies_of(ab))
			AbilityFX.landed(ab, target)
			if i > 0 and ab.release_sound:
				Combat.play_sound(target, ab.release_sound, -9.0, randf_range(1.1, 1.3))
		if delay <= 0.0:
			strike.call()
		else:
			player.get_tree().create_timer(delay).timeout.connect(strike)
		if i == jumps:
			break
		# The next one: the nearest enemy not hit yet near this one.
		var next: Node3D = null
		var best := reach
		for n in Combat.enemies_near(player, current.global_position, reach):
			if n in hit:
				continue
			var dist := n.global_position.distance_to(current.global_position)
			if dist < best:
				best = dist
				next = n
		if next == null:
			break
		hit.append(next)
		from = Combat.aim_point(current)
		current = next
		strength *= falloff


# --- Heal ---------------------------------------------------------------------------

static func heal(pc: PlayerCombat, ab: Ability, power: float, who: Node3D) -> void:
	var s := Combat.stats_of(who)
	if s == null:
		return
	s.heal(power)
	Effects.heal_burst(who)
	Effects.heal_glow(who, 1.2)
	AbilityFX.landed(ab, who)
	Combat.heal_threat(pc.player, power)
	_play(pc, ab, who)


# --- Tidal wave ---------------------------------------------------------------------

static func wave(pc: PlayerCombat, ab: Ability, power: float) -> void:
	var player := pc.player
	var d: Dictionary = Ability.data_of(ab).get("wave", {})
	var seconds := float(d.get("seconds", 0.5))
	var fwd := -player.model.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var root := Combat.world_root(player)
	var at := player.global_position
	SpellFX.water_wave(root, at + fwd * 0.4, fwd, ab.reach, ab.arc, ab.projectile_color, seconds, float(d.get("height", 1.6)))
	AbilityFX.ground(ab, root, at)
	_play(pc, ab, player, -1.0)
	var cam := player.get_tree().get_first_node_in_group("player_camera")
	if cam:
		cam.call("shake", 0.3)
	for n in Combat.enemies_near(player, at, ab.reach + 2.0):
		var to := n.global_position - at
		if absf(to.y) > 3.0:
			continue
		to.y = 0.0
		var dist := maxf(to.length() - Combat.radius_of(n), 0.0)
		if dist > ab.reach:
			continue
		if to.length() > 0.6 and rad_to_deg(fwd.angle_to(to.normalized())) > ab.arc * 0.5:
			continue
		var target := n
		# Hit as the wall gets there.
		player.get_tree().create_timer(seconds * clampf(dist / maxf(ab.reach, 0.1), 0.05, 1.0)).timeout.connect(func() -> void:
			if not is_instance_valid(target) or not is_instance_valid(player):
				return
			if Combat.hit(player, target, power, ab.staggers, ab.knockback, Ability.applies_of(ab)) > 0.0:
				Effects.splash(root, target.global_position + Vector3.UP * 0.3, 1.2)
				AbilityFX.burst(ab, "impact", root, Combat.aim_point(target)))


# --- Ground spells -------------------------------------------------------------------

static func ground_data(ab: Ability) -> Dictionary:
	var g = Ability.data_of(ab).get("ground", {})
	return g if g is Dictionary else {}


static func ground_radius(ab: Ability) -> float:
	return float(ground_data(ab).get("radius", 1.0))


## Where a GROUND spell would land for the pointer at `screen`: {point, ok, why} ({} when
## the pointer isn't over anything). Blink needs walkable ground in sight with room to
## stand, not in water; the cloud goes on anything in range.
static func ground_point(pc: PlayerCombat, ab: Ability, screen: Vector2) -> Dictionary:
	var player := pc.player
	var cam := player.get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var space := player.get_world_3d().direct_space_state
	var origin := cam.project_ray_origin(screen)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + cam.project_ray_normal(screen) * 300.0, 1)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {}
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	var out := {"point": point, "ok": true, "why": ""}
	var flat := Vector2(point.x - player.global_position.x, point.z - player.global_position.z).length()
	if flat > ab.reach:
		return {"point": point, "ok": false, "why": "Too far (%d m at most)" % int(ab.reach)}
	if String(ground_data(ab).get("kind", "teleport")) != "teleport":
		return out
	if normal.y < 0.55:
		return {"point": point, "ok": false, "why": "Too steep to stand on"}
	var ocean := player.get_tree().get_first_node_in_group("ocean")
	if ocean and point.y < float(ocean.get("sea_level")):
		return {"point": point, "ok": false, "why": "Can't blink into water"}
	var wq := PhysicsPointQueryParameters3D.new()
	wq.position = point + Vector3.UP * 0.3
	wq.collide_with_areas = true
	wq.collide_with_bodies = false
	wq.collision_mask = 1 << 3  # WaterVolume (layer 4)
	if not space.intersect_point(wq, 1).is_empty():
		return {"point": point, "ok": false, "why": "Can't blink into water"}
	var up := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.15, point + Vector3.UP * 1.9, 1)
	if not space.intersect_ray(up).is_empty():
		return {"point": point, "ok": false, "why": "No room to stand there"}
	var eye := player.global_position + Vector3.UP * 1.6
	var los := PhysicsRayQueryParameters3D.create(eye, point + Vector3.UP * 0.6, 1)
	los.exclude = [player.get_rid()]
	if not space.intersect_ray(los).is_empty():
		return {"point": point, "ok": false, "why": "You can't see that spot"}
	return out


static func ground(pc: PlayerCombat, ab: Ability, point: Vector3) -> void:
	var g := ground_data(ab)
	match String(g.get("kind", "teleport")):
		"teleport":
			teleport(pc, ab, point, g)
		"cloud":
			var cloud := DarkCloud.new()
			cloud.caster = pc.player
			cloud.radius = float(g.get("radius", 5.0))
			cloud.seconds = float(g.get("seconds", 8.0))
			cloud.status = String(g.get("status", "darkness"))
			cloud.blinds_caster = bool(g.get("blinds_caster", false))
			cloud.blinds_allies = bool(g.get("blinds_allies", true))
			cloud.outlines = bool(g.get("outlines", true))
			cloud.color = ab.projectile_color
			Combat.world_root(pc.player).add_child(cloud)
			cloud.global_position = point
			_play(pc, ab, cloud, 0.0)
			AbilityFX.landed(ab, cloud)


static func teleport(pc: PlayerCombat, ab: Ability, point: Vector3, g: Dictionary) -> void:
	var player := pc.player
	var root := Combat.world_root(player)
	var col := ab.projectile_color
	var start := player.global_position
	Effects.burst(root, start + Vector3.UP * 1.0, col, 1.3)
	AbilityFX.burst(ab, "cast", root, start + Vector3.UP * 1.0)
	_play(pc, ab, player)
	SpellFX.lightning(root, start + Vector3.UP * 1.0, point + Vector3.UP * 1.0, col.lightened(0.2), 0.18)
	player.global_position = point + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	player.set("_air_peak", -INF)  # no fall damage from where it started
	var cam := player.get_tree().get_first_node_in_group("player_camera")
	if cam and cam.has_method("snap"):
		cam.call("snap")
	Effects.burst(root, point + Vector3.UP * 1.0, col, 1.5)
	AbilityFX.landed(ab, player)
	var arrive := String(g.get("arrive_sound", ""))
	if arrive != "" and ResourceLoader.exists(arrive):
		Combat.play_sound(player, load(arrive), -3.0)
	Effects.flash(player.model, col.lightened(0.4), 0.35, 0.8)
