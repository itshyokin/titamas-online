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
	if not GameSession.active():
		return
	var stats := get_node_or_null("../Stats")
	if stats:
		stats.set("display_name", String(GameSession.data.get("name", "Adventurer")))


func refresh() -> void:
	for slot: String in ARMOR_SLOTS:
		var id: String = inventory.equipped.get(slot, "")
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
