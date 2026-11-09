class_name Inventory
extends Node
## The player's backpack (24 slots; consumables and materials stack to 64, gear to 1),
## equipped gear, gold and the hotbar. Lives under Player. Item details come from
## data/items.json (Database → Items). Saved with the character (GameSession) whenever
## it changes; a new character starts with its class's (or the player data's) starting kit.
##
## Weapons (item slot "weapon") go in the primary or secondary slot; one of them is in use
## (`active_weapon`, swapped by PlayerCombat). Only the weapon in use adds its stats.
## The hotbar: 8 entries after the two weapon boxes, each "ability:<id>", "item:<id>" or "".

signal changed
signal equipment_changed
signal gold_changed(gold: int)
## Something new went into the backpack (for pickup messages).
signal item_added(id: String, count: int)
signal hotbar_changed
## The weapon in use changed (primary/secondary).
signal weapon_swapped(slot: String)

const SIZE := 24
## Equipment slots, in the order the character window shows them.
const SLOTS := ["head", "shoulders", "chest", "hands", "legs", "feet", "primary", "secondary", "off_hand"]
const SLOT_NAMES := {
	"head": "Head", "shoulders": "Shoulders", "chest": "Chest", "hands": "Hands", "legs": "Legs",
	"feet": "Feet", "primary": "Primary", "secondary": "Secondary", "off_hand": "Off hand",
}
const WEAPON_SLOTS := ["primary", "secondary"]
const STAT_KEYS := ["attack", "spell_power", "armor", "block", "bonus_health", "bonus_mana"]
const HOTBAR_SIZE := 8
## Older saves' slot names.
const OLD_SLOTS := {"main_hand": "primary", "ranged": "secondary"}

## Backpack: SIZE entries, each null or {"id": String, "count": int}.
var bag: Array = []
## slot -> item id
var equipped := {}
var gold := 0
## "primary" or "secondary": the weapon in use.
var active_weapon := "primary"
## HOTBAR_SIZE entries: "ability:<id>", "item:<id>" or "".
var hotbar: Array = []

@onready var stats: Stats = get_node("../Stats")

var _save_queued := false


func _ready() -> void:
	add_to_group("player_inventory")
	bag.resize(SIZE)
	hotbar.resize(HOTBAR_SIZE)
	hotbar.fill("")
	if not load_character():
		_starting_kit()
	# Everyone has a hearthstone (older saves get one too).
	if count_of("hearthstone") == 0 and not item("hearthstone").is_empty():
		add_item("hearthstone", 1)
	_apply_bonuses()
	Database.changed.connect(func(which: String) -> void:
		if which == "items":
			_apply_bonuses()
			changed.emit()
			equipment_changed.emit())


static func item(id: String) -> Dictionary:
	return Database.item(id)


# --- Backpack ------------------------------------------------------------------

## Adds items, filling existing stacks first. Returns how many didn't fit.
func add_item(id: String, count := 1) -> int:
	if item(id).is_empty() or count <= 0:
		return count
	var left := count
	var cap := Database.stack_size(id)
	for i in SIZE:
		if left <= 0:
			break
		var s = bag[i]
		if s and s.id == id and s.count < cap:
			var n := mini(cap - s.count, left)
			s.count += n
			left -= n
	for i in SIZE:
		if left <= 0:
			break
		if bag[i] == null:
			var n := mini(cap, left)
			bag[i] = {"id": id, "count": n}
			left -= n
	if left < count:
		item_added.emit(id, count - left)
		_changed()
	return left


func count_of(id: String) -> int:
	var n := 0
	for s in bag:
		if s and s.id == id:
			n += s.count
	return n


func free_slots() -> int:
	return bag.count(null)


## Removes `count` of whatever is in slot `index`.
func remove_at(index: int, count := 1) -> void:
	var s = bag[index]
	if s == null:
		return
	s.count -= count
	if s.count <= 0:
		bag[index] = null
	_changed()


## Removes up to `count` of an item (from the last stacks first). Returns how many went.
func remove_item(id: String, count := 1) -> int:
	var removed := 0
	for i in range(SIZE - 1, -1, -1):
		if removed >= count:
			break
		var s = bag[i]
		if s and s.id == id:
			var n := mini(int(s.count), count - removed)
			s.count -= n
			removed += n
			if s.count <= 0:
				bag[i] = null
	if removed > 0:
		_changed()
	return removed


## Moves (or merges, or swaps) one backpack slot onto another.
func move(from: int, to: int) -> void:
	if from == to or from < 0 or to < 0 or from >= SIZE or to >= SIZE:
		return
	var a = bag[from]
	var b = bag[to]
	if a == null:
		return
	if b and b.id == a.id:
		var cap := Database.stack_size(a.id)
		var n := mini(cap - b.count, a.count)
		b.count += n
		a.count -= n
		if a.count <= 0:
			bag[from] = null
	else:
		bag[from] = b
		bag[to] = a
	_changed()


## Throws away the stack in a slot.
## Items marked "keep" (the hearthstone) can't be thrown away.
func can_discard(index: int) -> bool:
	return bag[index] != null and not bool(item(bag[index].id).get("keep", false))


func discard(index: int) -> void:
	if not can_discard(index):
		return
	bag[index] = null
	_changed()


# --- Equipment -----------------------------------------------------------------

func slot_of(id: String) -> String:
	return String(item(id).get("slot", ""))


func is_weapon(id: String) -> bool:
	return slot_of(id) == "weapon"


## Can this item go in this equipment slot?
func fits(id: String, slot: String) -> bool:
	if id.is_empty():
		return false
	var own := slot_of(id)
	return own == slot or (own == "weapon" and slot in WEAPON_SLOTS)


## The equipment slot an item would go to: weapons fill an empty weapon slot first, then
## replace the one in use.
func target_slot(id: String) -> String:
	var own := slot_of(id)
	if own != "weapon":
		return own
	for slot: String in WEAPON_SLOTS:
		if not equipped.has(slot):
			return slot
	return active_weapon


## Equips the item in a backpack slot (swapping out whatever was in its equipment slot).
func equip_from(index: int, slot := "") -> bool:
	var s = bag[index]
	if s == null:
		return false
	if slot.is_empty():
		slot = target_slot(s.id)
	if slot.is_empty() or not fits(s.id, slot):
		return false
	var old: String = equipped.get(slot, "")
	equipped[slot] = s.id
	bag[index] = {"id": old, "count": 1} if not old.is_empty() else null
	_equipment_changed()
	return true


## Puts an equipped item back in the backpack (first free slot, or `to` if given).
func unequip(slot: String, to := -1) -> bool:
	var id: String = equipped.get(slot, "")
	if id.is_empty():
		return false
	if to >= 0 and to < SIZE and bag[to] != null:
		# Dropped onto an occupied slot: swap if that item fits this equipment slot.
		var other: String = bag[to].id
		if not fits(other, slot):
			return false
		equipped[slot] = other
		bag[to] = {"id": id, "count": 1}
		_equipment_changed()
		return true
	if to < 0 or to >= SIZE:
		to = bag.find(null)
	if to < 0:
		return false
	bag[to] = {"id": id, "count": 1}
	equipped.erase(slot)
	_equipment_changed()
	return true


## Swaps the primary and secondary weapons.
func swap_weapon_slots() -> void:
	var a: String = equipped.get("primary", "")
	var b: String = equipped.get("secondary", "")
	equipped.erase("primary")
	equipped.erase("secondary")
	if not b.is_empty():
		equipped["primary"] = b
	if not a.is_empty():
		equipped["secondary"] = a
	_equipment_changed()


## Changes the weapon in use.
func set_active_weapon(slot: String) -> void:
	if not slot in WEAPON_SLOTS or slot == active_weapon:
		return
	active_weapon = slot
	_apply_bonuses()
	weapon_swapped.emit(slot)
	equipment_changed.emit()
	_queue_save()


## The weapon in use ({} if that slot is empty: fists).
func active_weapon_item() -> Dictionary:
	return equipped_item(active_weapon)


func equipped_item(slot: String) -> Dictionary:
	var id: String = equipped.get(slot, "")
	return item(id) if not id.is_empty() else {}


## Totals of the equipped items' stats.
func bonuses() -> Dictionary:
	var out := {}
	for key: String in STAT_KEYS:
		out[key] = 0.0
	var weapon := active_weapon_item()
	var two_handed := int(Database.weapon_type(String(weapon.get("weapon_type", ""))).get("hands", 1)) >= 2
	for slot: String in equipped:
		if slot in WEAPON_SLOTS and slot != active_weapon:
			continue  # only the weapon in use counts
		if slot == "off_hand" and two_handed:
			continue  # no shield with a two-handed weapon
		var d := item(equipped[slot])
		for key: String in STAT_KEYS:
			out[key] += float(d.get(key, 0.0))
	return out


func _apply_bonuses() -> void:
	if stats:
		stats.set_bonuses(bonuses())


# --- Using items ---------------------------------------------------------------

func is_usable(id: String) -> bool:
	var d := item(id)
	return bool(d.get("use_hearth", false)) or float(d.get("use_heal", 0.0)) > 0.0 or float(d.get("use_hot_per_tick", 0.0)) > 0.0 \
		or float(d.get("use_mana", 0.0)) > 0.0


## Uses (drinks, applies) the item in a backpack slot; equips gear instead.
func use_at(index: int) -> bool:
	var s = bag[index]
	if s == null:
		return false
	if not slot_of(s.id).is_empty():
		return equip_from(index)
	if not is_usable(s.id) or stats.is_dead():
		return false
	var d := item(s.id)
	if bool(d.get("use_hearth", false)):
		return _use_hearthstone(d)
	var id: String = s.id
	var seconds := float(d.get("use_time", 0.0))
	var anim := String(d.get("use_anim", ""))
	if anim.is_empty():
		anim = "drink"
	var player := get_parent() as PlayerController
	var combat := get_node_or_null("../PlayerCombat")
	if seconds > 0.0 and combat:
		# Drinking takes a moment (a cast bar; moving or a hit stops it and the potion is kept).
		return combat.channel(String(d.get("name", id)), seconds, _apply_use.bind(id), anim)
	if player and player.state == PlayerController.State.NORMAL:
		player.action_animation.emit(anim, 0.0, 0.15, 1.0)
	return _apply_use(id)


## The item's effect, then one is used up (from its first stack).
func _apply_use(id: String) -> bool:
	if stats.is_dead():
		return false
	var index := -1
	for i in SIZE:
		if bag[i] and bag[i].id == id:
			index = i
			break
	if index < 0:
		return false
	var d := item(id)
	if float(d.get("use_heal", 0.0)) > 0.0:
		stats.heal(float(d.use_heal))
	if float(d.get("use_hot_per_tick", 0.0)) > 0.0:
		stats.add_heal_over_time(float(d.use_hot_per_tick), int(d.get("use_hot_ticks", 1)), 2.0, self)
		Effects.heal_glow(get_parent(), int(d.get("use_hot_ticks", 1)) * 2.0)
	if float(d.get("use_mana", 0.0)) > 0.0:
		stats.restore_mana(float(d.use_mana))
	remove_at(index, 1)
	return true


## Hearthstone: a cast (moving or being hit stops it), then home. Not used up; it
## recharges (the time is saved with the character).
func _use_hearthstone(d: Dictionary) -> bool:
	var player := get_parent()
	var combat := player.get_node_or_null("PlayerCombat")
	var left := GameSession.hearth_cooldown_left()
	if left > 0.0:
		if combat:
			combat.notice.emit("Hearthstone recharging (%d min)" % ceili(left / 60.0))
		return false
	if not GameSession.active():
		if combat:
			combat.notice.emit("No home to go back to (testing without a saved character)")
		return false
	if combat == null:
		return false
	var home: Dictionary = GameSession.data.get("home", {})
	return combat.channel("Hearthstone: %s" % home.get("name", "Home"), float(d.get("cast_time", 8.0)), func() -> void:
		GameSession.data["hearth_ready_at"] = Time.get_unix_time_from_system() + float(d.get("cooldown", 600.0))
		Effects.burst(Combat.world_root(player), (player as Node3D).global_position + Vector3.UP, Color(0.45, 0.75, 1.0), 1.4)
		GameSession.travel_home())


## Uses an item by id (from its first stack in the backpack), as the hotbar does.
func use_item(id: String) -> bool:
	for index in SIZE:
		if bag[index] and bag[index].id == id:
			return use_at(index)
	FloatingText.spawn(get_parent(), "No %s left" % item(id).get("name", id), Color(1, 0.8, 0.6), 0.7)
	return false


# --- Hotbar --------------------------------------------------------------------

func set_hotbar(i: int, entry: String) -> void:
	if i < 0 or i >= HOTBAR_SIZE:
		return
	# An ability or item sits in one box only.
	if not entry.is_empty():
		var already := hotbar.find(entry)
		if already >= 0 and already != i:
			hotbar[already] = hotbar[i]
	hotbar[i] = entry
	hotbar_changed.emit()
	_queue_save()


func move_hotbar(from: int, to: int) -> void:
	if from == to or from < 0 or to < 0 or from >= HOTBAR_SIZE or to >= HOTBAR_SIZE:
		return
	var a: String = hotbar[from]
	hotbar[from] = hotbar[to]
	hotbar[to] = a
	hotbar_changed.emit()
	_queue_save()


## Puts an entry in the first empty box (if it isn't on the bar already).
func add_to_hotbar(entry: String) -> void:
	if hotbar.has(entry):
		return
	var i := hotbar.find("")
	if i >= 0:
		set_hotbar(i, entry)


func _default_hotbar() -> void:
	hotbar.fill("")
	var d: Array = Database.player.get("hotbar", [])
	for i in mini(d.size(), HOTBAR_SIZE):
		hotbar[i] = String(d[i])


# --- Gold ----------------------------------------------------------------------

func add_gold(amount: int) -> void:
	gold = maxi(gold + amount, 0)
	gold_changed.emit(gold)
	_queue_save()


# --- Save / load ---------------------------------------------------------------

func _changed() -> void:
	changed.emit()
	_queue_save()


func _equipment_changed() -> void:
	_apply_bonuses()
	changed.emit()
	equipment_changed.emit()
	_queue_save()


func _queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	(func() -> void:
		_save_queued = false
		save_character()).call_deferred()


func to_dict() -> Dictionary:
	return {"bag": bag.duplicate(true), "equipped": equipped.duplicate(), "gold": gold, "hotbar": hotbar.duplicate(),
		"active_weapon": active_weapon}


## Saves the character (GameSession writes the save file; nothing when there's none).
func save_character() -> void:
	GameSession.save_game()


## Loads the backpack and equipment from the current save. False if there's nothing yet.
func load_character() -> bool:
	var data = GameSession.data.get("inventory", {}) if GameSession.active() else {}
	if not data is Dictionary or data.is_empty():
		return false
	bag = []
	bag.resize(SIZE)
	var saved: Array = data.get("bag", [])
	for i in mini(saved.size(), SIZE):
		var s = saved[i]
		if s is Dictionary and not item(String(s.get("id", ""))).is_empty():
			bag[i] = {"id": String(s.id), "count": int(s.get("count", 1))}
	equipped = {}
	var eq: Dictionary = data.get("equipped", {})
	for saved_slot: String in eq:
		var slot: String = OLD_SLOTS.get(saved_slot, saved_slot)
		if slot in SLOTS and fits(String(eq[saved_slot]), slot):
			equipped[slot] = String(eq[saved_slot])
	gold = int(data.get("gold", 0))
	active_weapon = String(data.get("active_weapon", "primary"))
	if not active_weapon in WEAPON_SLOTS:
		active_weapon = "primary"
	var hb = data.get("hotbar")
	if hb is Array:
		for i in mini(hb.size(), HOTBAR_SIZE):
			hotbar[i] = String(hb[i])
	else:
		# Older save: the default bar, plus whatever was in the old quick slots.
		_default_hotbar()
		for id in data.get("quick", []):
			if not String(id).is_empty():
				add_to_hotbar("item:" + String(id))
	return true


## Empties everything and gives the starting kit again (Settings → Reset character).
func reset_character() -> void:
	bag = []
	bag.resize(SIZE)
	equipped = {}
	gold = 0
	active_weapon = "primary"
	_starting_kit()
	_equipment_changed()
	gold_changed.emit(gold)


## The class's starting kit if it has one, otherwise the player data's.
func _starting_kit() -> void:
	var kit: Dictionary = Database.player.get("starting_kit", {})
	if GameSession.active():
		var class_kit = Database.class_data(String(GameSession.data.get("class", ""))).get("starting_kit", {})
		if class_kit is Dictionary and (not class_kit.get("equipment", {}).is_empty() or not class_kit.get("backpack", []).is_empty()):
			kit = class_kit
	gold = int(kit.get("gold", 0))
	var eq: Dictionary = kit.get("equipment", {})
	for kit_slot: String in eq:
		var slot: String = OLD_SLOTS.get(kit_slot, kit_slot)
		if fits(String(eq[kit_slot]), slot):
			equipped[slot] = String(eq[kit_slot])
	for entry in kit.get("backpack", []):
		add_item(String(entry[0]), int(entry[1]))
	_default_hotbar()
	hotbar_changed.emit()
