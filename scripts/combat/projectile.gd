class_name Projectile
extends Node3D
## A spell bolt, arrow, crossbow bolt or bullet. With a target it homes in (spells,
## auto-aim weapons); without one it flies along `direction` (dropping with `gravity`)
## and hits the first enemy or wall in its path.
## Arrows stick in what they hit (ground or enemy) and fade after a while; bullets leave
## a hole in the ground and walls (not in enemies).

const BOLT_BURST_SOUND := preload("res://assets/audio/combat/fireball_hit.ogg")
const ARROW_HIT_SOUND := preload("res://assets/audio/combat/arrow_hit.ogg")
const MAX_RANGE := 60.0
## Seconds a stuck arrow stays before fading, and a bullet hole.
const ARROW_LINGER := 10.0
const HOLE_LINGER := 25.0
const MAX_HOLES := 40
const ENEMY_MASK := 4  # physics layer 3

static var _holes: Array[Decal] = []
static var _hole_texture: Texture2D

var source: Node3D
var target: Node3D
var ability: Ability
var power := 10.0
var direction := Vector3.FORWARD
var gravity := 0.0

var _velocity := Vector3.ZERO
var _last_aim := Vector3.ZERO
var _travelled := 0.0
var _style := Ability.ProjectileStyle.BOLT
var _model: Node3D


static func launch(from: Vector3, by: Node3D, at: Node3D, what: Ability, hit_power: float, dir := Vector3.ZERO, fall := 0.0) -> Projectile:
	var p := Projectile.new()
	p.source = by
	p.target = at
	p.ability = what
	p.power = hit_power
	p.gravity = fall
	if dir != Vector3.ZERO:
		p.direction = dir.normalized()
	Combat.world_root(by).add_child(p)
	p.global_position = from
	if at:
		p.direction = (Combat.aim_point(at) - from).normalized()
	p._velocity = p.direction * what.projectile_speed
	p._face()
	return p


## The direction to launch at `speed` so a shot falling at `g` lands on `to` (the low arc;
## straight at it when out of reach).
static func ballistic(from: Vector3, to: Vector3, speed: float, g: float) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var d := flat.length()
	if g <= 0.0 or d < 0.5:
		return (to - from).normalized()
	var h := to.y - from.y
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * d * d + 2.0 * h * v2)
	if disc < 0.0:
		return (flat.normalized() + Vector3.UP).normalized()  # 45°: as far as it goes
	var angle := atan((v2 - sqrt(disc)) / (g * d))
	return (flat.normalized() * cos(angle) + Vector3.UP * sin(angle)).normalized()


func _ready() -> void:
	_style = ability.projectile_style
	var color := ability.projectile_color
	match _style:
		Ability.ProjectileStyle.ARROW:
			_model = WeaponModels.arrow()
			add_child(_model)
		Ability.ProjectileStyle.BULLET:
			# A short glowing streak (a tracer), so fast shots can be seen.
			var streak := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.025, 0.025, 0.9)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(1.0, 0.85, 0.55)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.7, 0.3)
			mat.emission_energy_multiplier = 3.0
			box.material = mat
			streak.mesh = box
			streak.position.z = 0.45  # trails behind the ball
			streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(streak)
		_:
			var core := MeshInstance3D.new()
			core.visible = not AbilityFX.has(ability, "projectile")  # its own sprite instead
			var sphere := SphereMesh.new()
			sphere.radius = 0.14
			sphere.height = 0.28
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = color.lightened(0.5)
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 4.0
			sphere.material = mat
			core.mesh = sphere
			core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(core)
			var light := OmniLight3D.new()
			light.light_color = color
			light.light_energy = 2.0
			light.omni_range = 4.0
			add_child(light)
			add_child(Effects.trail(color))
	AbilityFX.attach(ability, "projectile", self)
	_last_aim = Combat.aim_point(target) if is_instance_valid(target) else global_position + direction * MAX_RANGE


func _face() -> void:
	var d := _velocity if _velocity.length() > 0.01 else direction
	if d.length() > 0.01 and absf(d.normalized().dot(Vector3.UP)) < 0.999:
		look_at(global_position + d, Vector3.UP)


func _max_range() -> float:
	return maxf(ability.reach * 1.6, MAX_RANGE)


func _physics_process(delta: float) -> void:
	if target != null:
		_home(delta)
		return
	# Free flight: falls with gravity; walls and enemies along the path stop it.
	_velocity.y -= gravity * delta
	var from := global_position
	var next := from + _velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, next, 1 | ENEMY_MASK)
	if is_instance_valid(source) and source is CollisionObject3D:
		query.exclude = [(source as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position
		var who := _combatant(hit.collider as Node)
		if who and is_instance_valid(source) and Combat.is_enemy_of(source, who):
			_hit(who)
		elif who:
			global_position = next  # a friend: fly on
		else:
			_hit_world(hit.position, hit.normal, hit.collider as Node)
		return
	# Spell bolts are forgiving: anything close to the path counts.
	if _style == Ability.ProjectileStyle.BOLT and is_instance_valid(source):
		for n in Combat.enemies_near(source, next, 0.9):
			if absf(Combat.aim_point(n).y - next.y) < 1.2:
				_hit(n)
				return
	global_position = next
	_face()
	_travelled += _velocity.length() * delta
	if _travelled > _max_range():
		queue_free()


## Homing on a target.
func _home(delta: float) -> void:
	var step := ability.projectile_speed * delta
	if is_instance_valid(target) and Combat.is_alive(target):
		_last_aim = Combat.aim_point(target)
	var to := _last_aim - global_position
	if to.length() <= step + 0.2:
		_hit(target if is_instance_valid(target) else null)
		return
	direction = to.normalized()
	_velocity = direction * ability.projectile_speed
	var from := global_position
	var next := from + direction * step
	var query := PhysicsRayQueryParameters3D.create(from, next, 1)
	var wall := get_world_3d().direct_space_state.intersect_ray(query)
	if not wall.is_empty():
		global_position = wall.position
		_hit_world(wall.position, wall.normal, wall.collider as Node)
		return
	global_position = next
	_face()
	_travelled += step
	if _travelled > _max_range() * 2.0:
		queue_free()


func _combatant(node: Node) -> Node3D:
	while node and not node.is_in_group(Combat.GROUP):
		node = node.get_parent()
	return node as Node3D


func _hit(who: Node3D) -> void:
	if who and Combat.is_alive(who) and is_instance_valid(source):
		Combat.hit(source, who, power, ability.staggers, ability.knockback, Ability.applies_of(ability))
	if who and is_instance_valid(who):
		AbilityFX.landed(ability, who, global_position)
	match _style:
		Ability.ProjectileStyle.ARROW:
			Combat.play_sound(self, ARROW_HIT_SOUND, -6.0)
			if who and is_instance_valid(who):
				_stick(who)
		Ability.ProjectileStyle.BULLET:
			Combat.play_sound(self, ARROW_HIT_SOUND, -8.0, 1.4)
		_:
			Effects.burst(Combat.world_root(self), global_position, ability.projectile_color)
			Combat.play_sound(self, BOLT_BURST_SOUND, -3.0)
	queue_free()


func _hit_world(at: Vector3, normal: Vector3, what: Node) -> void:
	AbilityFX.burst(ability, "impact", Combat.world_root(self), at + normal * 0.1)
	match _style:
		Ability.ProjectileStyle.ARROW:
			Combat.play_sound(self, ARROW_HIT_SOUND, -6.0)
			_stick(what as Node3D if what is Node3D else Combat.world_root(self) as Node3D)
		Ability.ProjectileStyle.BULLET:
			Combat.play_sound(self, ARROW_HIT_SOUND, -8.0, 1.4)
			Effects.sparks(Combat.world_root(self), at, Color(0.75, 0.65, 0.5), 0.6, normal)
			_bullet_hole(at, normal)
		_:
			Effects.burst(Combat.world_root(self), global_position, ability.projectile_color)
			Combat.play_sound(self, BOLT_BURST_SOUND, -3.0)
	queue_free()


## Leaves the arrow stuck in `into` (an enemy moves it along), tip buried a little; it
## fades after a while.
func _stick(into: Node3D) -> void:
	if _model == null or into == null or not is_instance_valid(into):
		return
	var t := global_transform
	remove_child(_model)
	var holder := Node3D.new()
	holder.name = "StuckArrow"
	holder.add_child(_model)
	into.add_child(holder)
	t.origin += -t.basis.z.normalized() * 0.18  # bury the tip
	holder.global_transform = t
	var tween := holder.create_tween()
	tween.tween_interval(ARROW_LINGER)
	tween.tween_property(holder, "scale", Vector3(0.01, 0.01, 0.01), 0.6)
	tween.tween_callback(holder.queue_free)
	_model = null


## A bullet hole on the ground or a wall (a small dark decal), fading after a while.
func _bullet_hole(at: Vector3, normal: Vector3) -> void:
	var decal := Decal.new()
	decal.texture_albedo = _hole()
	decal.size = Vector3(0.22, 0.3, 0.22)
	decal.cull_mask = 1
	var up := normal.normalized()
	var side := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var z := side.cross(up).normalized()
	decal.top_level = true
	Combat.world_root(self).add_child(decal)
	decal.global_transform = Transform3D(Basis(up.cross(z).normalized(), up, z).rotated(up, randf() * TAU), at)
	_holes.append(decal)
	while _holes.size() > MAX_HOLES:
		var old: Decal = _holes.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var tween := decal.create_tween()
	tween.tween_interval(HOLE_LINGER)
	tween.tween_property(decal, "modulate:a", 0.0, 2.0)
	tween.tween_callback(func() -> void:
		_holes.erase(decal)
		decal.queue_free())


static func _hole() -> Texture2D:
	if _hole_texture:
		return _hole_texture
	var size := 8  # a few big pixels
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (size * 0.5)
			var a := clampf(1.0 - smoothstep(0.25, 0.95, d), 0.0, 1.0)
			var dark := 0.04 if d < 0.35 else 0.18
			img.set_pixel(x, y, Color(dark, dark * 0.9, dark * 0.8, PixelArt.step_alpha(a)))
	_hole_texture = ImageTexture.create_from_image(img)
	return _hole_texture
