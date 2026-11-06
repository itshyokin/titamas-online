class_name LootBag
extends Node3D
## A small sack an enemy drops: walk up to it to pick up the gold and items inside.
## Whatever doesn't fit in the backpack stays in the bag. Disappears after a while.

const PICKUP_SOUND := preload("res://assets/audio/sfx/pickup.ogg")
const COIN_SOUND := preload("res://assets/audio/sfx/coins.ogg")

## Picked up from this close (m).
@export var reach := 1.6
@export var lifetime := 180.0

var gold := 0
var items: Array = []  # [id, count]
var _age := 0.0
var _full_warned := false
var _sack: Node3D


## Rolls an enemy's loot table and drops a bag at `at` (nothing if it rolled nothing).
static func drop_for(enemy_data: Dictionary, parent: Node, at: Vector3) -> LootBag:
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
	parent.add_child(bag)
	bag.global_position = at
	return bag


func _ready() -> void:
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
	# A soft glow so it can be spotted.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.85, 0.4)
	glow.light_energy = 0.8
	glow.omni_range = 2.0
	glow.position.y = 0.4
	add_child(glow)
	add_child(Effects.target_ring(Color(1.0, 0.85, 0.35, 0.8)))


func _physics_process(delta: float) -> void:
	_age += delta
	_sack.rotation.y += delta * 0.8
	_sack.position.y = 0.04 * sin(_age * 2.5)
	if _age > lifetime:
		queue_free()
		return
	for player in get_tree().get_nodes_in_group(Combat.GROUP):
		var inv := (player as Node).get_node_or_null("Inventory") as Inventory
		if inv and (player as Node3D).global_position.distance_to(global_position) < reach and Combat.is_alive(player):
			_give(inv)
			return


func _give(inv: Inventory) -> void:
	var took := false
	if gold > 0:
		inv.add_gold(gold)
		FloatingText.spawn(inv.get_parent(), "+%d gold" % gold, Color(1.0, 0.85, 0.35), 0.9)
		Combat.play_sound(self, COIN_SOUND, -4.0)
		gold = 0
		took = true
	var left: Array = []
	for entry: Array in items:
		var rest := inv.add_item(entry[0], entry[1])
		if rest < entry[1]:
			took = true
		if rest > 0:
			left.append([entry[0], rest])
	items = left
	if took:
		Combat.play_sound(self, PICKUP_SOUND, -6.0)
	if items.is_empty():
		queue_free()
	elif not _full_warned:
		_full_warned = true
		FloatingText.spawn(inv.get_parent(), "Backpack full", Color(1.0, 0.6, 0.5), 0.8)
