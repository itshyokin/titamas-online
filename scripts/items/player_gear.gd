class_name PlayerGear
extends Node
## Gives the player their look from the character creator, and shows their equipped armour
## on their body (weapons are handled by PlayerCombat,
## which draws and sheathes them). Lives under Player, next to Inventory.

const ARMOR_SLOTS := ["head", "shoulders", "chest", "hands", "legs", "feet", "off_hand"]

@onready var inventory: Inventory = get_node("../Inventory")
@onready var character: CharacterModel = get_node("../Model/Character")

var _showing := {}  # slot -> item id currently worn
var _force := false


func _ready() -> void:
	_apply_look()
	inventory.equipment_changed.connect(refresh)
	Achievements.unlocked.connect(func(_id: String) -> void: _wear_backpack())
	refresh.call_deferred()
	# Item data edited in the Database (e.g. a new fit): put everything on again.
	Database.changed.connect(func(which: String) -> void:
		if which == "items":
			_force = true
			refresh()
			_force = false
		elif which == "appearance":
			_apply_look())


## The character's look and name from the save (character creator); the default look
## when playing a level straight from the editor.
func _apply_look() -> void:
	character.apply_appearance(Database.resolve_appearance(GameSession.data.get("look", {})))
	_wear_backpack()
	if not GameSession.active():
		return
	var stats := get_node_or_null("../Stats")
	if stats:
		stats.set("display_name", String(GameSession.data.get("name", "Adventurer")))


## Look toggles (customisation): "show_backpack" and "show_helmet" (both default on).
static func look_flag(look: Dictionary, key: String) -> bool:
	return bool(look.get(key, true))


func _look() -> Dictionary:
	var look = GameSession.data.get("look", {})
	return look if look is Dictionary else {}


## The backpack with a pin for every achievement earned on this account.
func _wear_backpack() -> void:
	var on := look_flag(_look(), "show_backpack")
	character.set_backpack(on, Backpack.pins_of(Achievements.earned(), Database.achievements))
	var combat := get_node_or_null("../PlayerCombat")
	if combat and combat.has_method("_equip_weapons") and combat.get("inventory") != null:
		combat.call("_equip_weapons")  # sheathed weapons sit differently with a pack on


## The look changed in the customisation (Codex): backpack and helmet again.
func look_changed() -> void:
	_apply_look()
	_force = true
	refresh()
	_force = false


func refresh() -> void:
	var helmet := look_flag(_look(), "show_helmet")
	for slot: String in ARMOR_SLOTS:
		var id: String = inventory.equipped.get(slot, "")
		if slot == "head" and not helmet:
			id = ""  # still worn (its stats count), just not shown
		if _showing.has(slot) and _showing[slot] == id and not _force:
			continue
		if id.is_empty():
			character.take_off(slot)
			_showing.erase(slot)
		else:
			character.wear(Database.item(id), slot)
			_showing[slot] = id
	var combat := get_node_or_null("../PlayerCombat")
	if combat:
		combat.call("_show_weapons")
