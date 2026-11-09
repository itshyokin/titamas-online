class_name LootBag
extends Node3D
## What an enemy drops: gold and items, lying with its body. Walk up and press Jump /
## interact (E, A) to kneel and look through it (LootWindow): take things one by one or
## all at once; whatever you leave stays until the body is gone. A drop without a body
## (or once it's gone) shows as a small sack.

const PICKUP_SOUND := preload("res://assets/audio/sfx/pickup.ogg")
const COIN_SOUND := preload("res://assets/audio/sfx/coins.ogg")
const TALK_RANGE := 2.6

## Disappears after this long without a body to lie with (s).
@export var lifetime := 180.0

var gold := 0
var items: Array = []  # [id, count]
## The body it lies with (an Enemy); null = a plain sack on the ground.
var corpse: Node3D = null
## Shown as the loot window's title.
var title := "Loot"
## Someone is looking through it right now.
var open := false

var _age := 0.0
var _sack: Node3D
var _prompt: Label3D
var _sparkle: CPUParticles3D


## Rolls an enemy's loot table and drops it at `at`, lying with `body` if given
## (nothing if it rolled nothing).
static func drop_for(enemy_data: Dictionary, parent: Node, at: Vector3, body: Node3D = null) -> LootBag:
	var bag := LootBag.new()
	bag.gold = randi_range(int(enemy_data.get("gold_min", 0)), int(enemy_data.get("gold_max", 0)))
	for entry: Dictionary in enemy_data.get("loot", []):
		if randf() < float(entry.get("chance", 0.0)):
			var n := randi_range(int(entry.get("min", 1)), maxi(int(entry.get("max", 1)), int(entry.get("min", 1))))
			if n > 0 and not Database.item(String(entry.get("item", ""))).is_empty():
				bag.items.append([String(entry.item), n])
	if bag.gold <= 0 and bag.items.is_empty():
		bag.free()
		return null
	bag.corpse = body
	var s := Combat.stats_of(body) if body else null
	bag.title = s.display_name if s else String(enemy_data.get("name", "Loot"))
	parent.add_child(bag)
	bag.global_position = at
	return bag


func is_empty() -> bool:
	return gold <= 0 and items.is_empty()


func _ready() -> void:
	add_to_group("talkable")
	_sack = Node3D.new()
	add_child(_sack)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.55, 0.4, 0.22)
	cloth.roughness = 1.0
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.34
	sphere.radial_segments = 8
	sphere.rings = 5
	sphere.material = cloth
	body.mesh = sphere
	body.position.y = 0.17
	_sack.add_child(body)
	var neck := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.05
	cyl.height = 0.12
	cyl.radial_segments = 8
	cyl.material = cloth
	neck.mesh = cyl
	neck.position.y = 0.38
	_sack.add_child(neck)
	# Golden motes rising from whatever has loot on it, so it can be spotted.
	_sparkle = CPUParticles3D.new()
	_sparkle.amount = 10
	_sparkle.lifetime = 1.4
	_sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparkle.emission_sphere_radius = 0.35
	_sparkle.direction = Vector3.UP
	_sparkle.spread = 15.0
	_sparkle.gravity = Vector3(0, 0.6, 0)
	_sparkle.initial_velocity_min = 0.1
	_sparkle.initial_velocity_max = 0.3
	_sparkle.scale_amount_min = 0.5
	var mote := SphereMesh.new()
	mote.radius = 0.025
	mote.height = 0.05
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.85, 0.4)
	mote.material = glow
	_sparkle.mesh = mote
	_sparkle.position.y = 0.3
	add_child(_sparkle)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.4)
	light.light_energy = 0.6
	light.omni_range = 2.0
	light.position.y = 0.4
	add_child(light)
	add_child(Effects.target_ring(Color(1.0, 0.85, 0.35, 0.8)))
	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.pixel_size = 0.003
	_prompt.font_size = 36
	_prompt.outline_size = 10
	_prompt.no_depth_test = true
	_prompt.position = Vector3.UP * 1.0
	_prompt.visible = false
	add_child(_prompt)


func _physics_process(delta: float) -> void:
	_age += delta
	var has_body := corpse != null and is_instance_valid(corpse)
	if has_body:
		var model := corpse.get_node_or_null("Model") as Node3D
		if model and not model.visible:
			queue_free()  # the body is gone, and the loot with it
			return
		global_position = _body_spot()
	elif _age > lifetime:
		queue_free()
		return
	_sack.visible = not has_body
	if _sack.visible:
		_sack.rotation.y += delta * 0.8
		_sack.position.y = 0.04 * sin(_age * 2.5)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var show := player != null and can_talk() and player.global_position.distance_to(global_position) <= TALK_RANGE
	_prompt.visible = show
	if show:
		var key := GameSettings.interact_label()
		_prompt.text = "%s  Loot %s" % [key, title]


## Where the body lies: under its hips (death clips move them away from the origin).
func _body_spot() -> Vector3:
	var cm := corpse.get_node_or_null("Model/Character") as CharacterModel
	var limp = Ragdoll.hips_of(cm)
	if limp != null:
		return Vector3(limp.x, (limp as Vector3).y - 0.1, limp.z)
	var skel := cm.get_skeleton() if cm else null
	var bone := skel.find_bone("mixamorig_Hips") if skel else -1
	if bone < 0:
		return corpse.global_position
	var hips := skel.global_transform * skel.get_bone_global_pose(bone).origin
	return Vector3(hips.x, corpse.global_position.y + 0.05, hips.z)


# --- Talkable -------------------------------------------------------------------

func can_talk() -> bool:
	return not open and not is_empty() and not DialogueBox.is_open and Time.get_ticks_msec() - DialogueBox.closed_at > 300


## Interact next to it: kneel and open the loot window.
func talk(player: Node3D) -> void:
	if can_talk():
		LootWindow.open_for(self, player)


# --- Taking things --------------------------------------------------------------

## Takes the gold into `inv`.
func take_gold(inv: Inventory) -> void:
	if gold <= 0:
		return
	inv.add_gold(gold)
	FloatingText.spawn(inv.get_parent(), "+%d gold" % gold, Color(1.0, 0.85, 0.35), 0.9)
	Combat.play_sound(self, COIN_SOUND, -4.0)
	gold = 0


## Takes item entry `i` (as much as fits). Returns false if none fit.
func take_item(inv: Inventory, i: int) -> bool:
	if i < 0 or i >= items.size():
		return false
	var entry: Array = items[i]
	var rest := inv.add_item(entry[0], entry[1])
	if rest >= int(entry[1]):
		HUD.notify(inv, "Backpack full", Color(1.0, 0.6, 0.5))
		return false
	Combat.play_sound(self, PICKUP_SOUND, -6.0)
	if rest > 0:
		items[i] = [entry[0], rest]
	else:
		items.remove_at(i)
	return true


## Takes everything that fits.
func take_all(inv: Inventory) -> void:
	take_gold(inv)
	for i in range(items.size() - 1, -1, -1):
		take_item(inv, i)
