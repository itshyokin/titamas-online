class_name Inventory
extends Node
## The player's backpack (24 slots; consumables and materials stack to 64, gear to 1),
## equipped gear, gold and the two quick-item slots. Lives under Player. Item details come
## from data/items.json (Database → Items). Saved to user://character.json whenever it
## changes; a new character starts with the player data's starting kit.

signal changed
signal equipment_changed
signal gold_changed(gold: int)
## Something new went into the backpack (for pickup messages).
signal item_added(id: String, count: int)

const SIZE := 24
const SAVE_PATH := "user://character.json"
## Equipment slots, in the order the character window shows them.
const SLOTS := ["head", "shoulders", "chest", "hands", "legs", "feet", "main_hand", "off_hand", "ranged"]
const SLOT_NAMES := {
	"head": "Head", "shoulders": "Shoulders", "chest": "Chest", "hands": "Hands", "legs": "Legs",
	"feet": "Feet", "main_hand": "Main hand", "off_hand": "Off hand", "ranged": "Ranged",
}
const STAT_KEYS := ["attack", "spell_power", "armor", "block", "bonus_health", "bonus_mana"]
const QUICK_SLOTS := 2

## Backpack: SIZE entries, each null or {"id": String, "count": int}.
var bag: Array = []
## slot -> item id
var equipped := {}
var gold := 0
## Item ids assigned to the quick slots ("" = empty).
var quick: Array = ["", ""]

@onready var stats: Stats = get_node("../Stats")

var _save_queued := false


func _ready() -> void:
	add_to_group("player_inventory")
	bag.resize(SIZE)
	if not load_character():
		_starting_kit()
	_apply_bonuses()
	Database.changed.connect(func(which: String) -> void:
		if which == "items":
			_apply_bonuses()
			changed.emit()
			equipment_changed.emit())


func _unhandled_input(event: InputEvent) -> void:
	if GameSettings.menu_open:
		return
	if event.is_action_pressed("item_prev"):
		_use_quick_with_feedback(0)
	elif event.is_action_pressed("item_next"):
		_use_quick_with_feedback(1)


func _use_quick_with_feedback(i: int) -> void:
	var id: String = quick[i]
	if id.is_empty():
		return
	if count_of(id) == 0:
		FloatingText.spawn(get_parent(), "No %s left" % item(id).get("name", id), Color(1, 0.8, 0.6), 0.7)
		return
	use_quick(i)


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
func discard(index: int) -> void:
	bag[index] = null
	_changed()


# --- Equipment -----------------------------------------------------------------

func slot_of(id: String) -> String:
	return String(item(id).get("slot", ""))


## Equips the item in a backpack slot (swapping out whatever was in its equipment slot).
func equip_from(index: int) -> bool:
	var s = bag[index]
	if s == null:
		return false
	var slot := slot_of(s.id)
	if slot.is_empty():
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
		if slot_of(other) != slot:
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


func equipped_item(slot: String) -> Dictionary:
	var id: String = equipped.get(slot, "")
	return item(id) if not id.is_empty() else {}


## Totals of the equipped items' stats.
func bonuses() -> Dictionary:
	var out := {}
	for key: String in STAT_KEYS:
		out[key] = 0.0
	for slot: String in equipped:
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
	return float(d.get("use_heal", 0.0)) > 0.0 or float(d.get("use_hot_per_tick", 0.0)) > 0.0 \
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
	if float(d.get("use_heal", 0.0)) > 0.0:
		stats.heal(float(d.use_heal))
	if float(d.get("use_hot_per_tick", 0.0)) > 0.0:
		stats.add_heal_over_time(float(d.use_hot_per_tick), int(d.get("use_hot_ticks", 1)), 2.0, self)
		Effects.heal_glow(get_parent(), int(d.get("use_hot_ticks", 1)) * 2.0)
	if float(d.get("use_mana", 0.0)) > 0.0:
		stats.restore_mana(float(d.use_mana))
	remove_at(index, 1)
	return true


## Uses the item assigned to quick slot `i` (from the first stack of it in the backpack).
func use_quick(i: int) -> bool:
	var id: String = quick[i] if i < quick.size() else ""
	if id.is_empty():
		return false
	for index in SIZE:
		if bag[index] and bag[index].id == id:
			return use_at(index)
	return false


func set_quick(i: int, id: String) -> void:
	if i < 0 or i >= QUICK_SLOTS:
		return
	quick[i] = id
	_changed()


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


func save_character() -> void:
	var data := {"bag": bag, "equipped": equipped, "gold": gold, "quick": quick}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func load_character() -> bool:
	var data = DataFiles.read(SAVE_PATH)
	if not data is Dictionary:
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
	for slot: String in eq:
		if slot in SLOTS and not item(String(eq[slot])).is_empty():
			equipped[slot] = String(eq[slot])
	gold = int(data.get("gold", 0))
	quick = ["", ""]
	var q: Array = data.get("quick", [])
	for i in mini(q.size(), QUICK_SLOTS):
		quick[i] = String(q[i])
	return true


## Empties everything and gives the starting kit again (Settings → Reset character).
func reset_character() -> void:
	bag = []
	bag.resize(SIZE)
	equipped = {}
	gold = 0
	quick = ["", ""]
	_starting_kit()
	_equipment_changed()
	gold_changed.emit(gold)


func _starting_kit() -> void:
	var kit: Dictionary = Database.player.get("starting_kit", {})
	gold = int(kit.get("gold", 0))
	var eq: Dictionary = kit.get("equipment", {})
	for slot: String in eq:
		if not item(String(eq[slot])).is_empty():
			equipped[slot] = String(eq[slot])
	for entry in kit.get("backpack", []):
		add_item(String(entry[0]), int(entry[1]))
	var q: Array = kit.get("quick", [])
	for i in mini(q.size(), QUICK_SLOTS):
		quick[i] = String(q[i])
