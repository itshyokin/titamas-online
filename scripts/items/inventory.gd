class_name Inventory
extends Node
## The player's backpack (24 slots; consumables and materials stack to 64, gear to 1),
## equipped gear, gold and the hotbar. Lives under Player. Item details come from
## data/items.json (Database → Items). Saved with the character (GameSession) whenever
## it changes; a new character starts with its class's (or the player data's) starting kit.
##
## One weapon at a time (item slot "weapon" → equipment slot "primary"), changed in the
## character window. The hotbar: 10 entries (keys 1-0), each "ability:<id>",
## "item:<id>" (usable items: potions, bandages...) or ""; weapons never go on it.

signal changed
signal equipment_changed
signal gold_changed(gold: int)
## Something new went into the backpack (for pickup messages).
signal item_added(id: String, count: int)
signal hotbar_changed
## The weapon in use changed (primary/secondary).
signal weapon_swapped(slot: String)

const SIZE := 60  # 12 columns x 5 rows in the Codex backpack (was 24; old saves fill the start)
## Equipment slots, in the order the character window shows them.
const SLOTS := ["head", "shoulders", "chest", "hands", "legs", "feet", "primary", "off_hand"]
const SLOT_NAMES := {
	"head": "Head", "shoulders": "Shoulders", "chest": "Chest", "hands": "Hands", "legs": "Legs",
	"feet": "Feet", "primary": "Weapon", "off_hand": "Off hand",
}
const WEAPON_SLOTS := ["primary"]
const STAT_KEYS := ["attack", "spell_power", "armor", "block", "bonus_health", "bonus_mana"]
const HOTBAR_SIZE := 10
## Saves from before (8 entries after two weapon boxes).
const OLD_HOTBAR_SIZE := 8
## Older saves' slot names.
const OLD_SLOTS := {"main_hand": "primary", "ranged": "secondary"}
## Old saves' second weapon goes to the backpack.
const RETIRED_SLOTS := ["secondary"]

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


## Whether every {item, count} in `items` would fit in the backpack together.
func has_room_for(items: Array) -> bool:
	var sim: Array = []
	for s in bag:
		sim.append(s.duplicate() if s else null)
	for e: Dictionary in items:
		var id := String(e.get("item", ""))
		var left := maxi(int(e.get("count", 1)), 1)
		if item(id).is_empty():
			continue
		var cap := Database.stack_size(id)
		for i in SIZE:
			if left <= 0:
				break
			if sim[i] and sim[i].id == id and sim[i].count < cap:
				var n := mini(cap - int(sim[i].count), left)
				sim[i].count += n
				left -= n
		for i in SIZE:
			if left <= 0:
				break
			if sim[i] == null:
				var n := mini(cap, left)
				sim[i] = {"id": id, "count": n}
				left -= n
		if left > 0:
			return false
	return true


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


## Throws a stack out of the bag: it lands in front of the player as an ItemPickup they
## can walk over to take back (after a short delay).
func discard(index: int, drop := true) -> void:
	if not can_discard(index):
		return
	var s = bag[index]
	bag[index] = null
	_changed()
	var owner_node := get_parent() as Node3D
	if drop and s and owner_node:
		load("res://scripts/items/item_pickup.gd").call("drop", owner_node, String(s.id), int(s.count))


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
	play_equip_sound(s.id)
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
		play_equip_sound(other)
		return true
	if to < 0 or to >= SIZE:
		to = bag.find(null)
	if to < 0:
		return false
	bag[to] = {"id": id, "count": 1}
	equipped.erase(slot)
	_equipment_changed()
	play_equip_sound(id, -6.0)
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


## Gear going on (or off, quieter): the item's `equip_sound`, else its weapon type's swap
## sound, else player.json `equip_sounds` by `material` (cloth / leather / metal / jewelry;
## guessed from the id when not set).
func play_equip_sound(id: String, db := 0.0) -> void:
	var d := item(id)
	var path := String(d.get("equip_sound", ""))
	if path == "" and is_weapon(id):
		path = String(Database.weapon_type(String(d.get("weapon_type", ""))).get("swap_sound", ""))
	if path == "":
		var sounds: Dictionary = Database.player.get("equip_sounds", {})
		path = String(sounds.get(material_of(d), sounds.get("cloth", "")))
	if path == "" or not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.bus = &"SFX"
	p.volume_db = db + float(Database.player.get("equip_sounds", {}).get("volume_db", -6.0))
	p.pitch_scale = randf_range(0.95, 1.05)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## What gear is made of (for its sound): the item's `material`, else a guess from its id.
static func material_of(d: Dictionary) -> String:
	if String(d.get("material", "")) != "":
		return String(d.material)
	var id := String(d.get("id", "")).to_lower()
	for w in ["ring", "amulet", "necklace", "earring", "pendant", "charm"]:
		if id.contains(w):
			return "jewelry"
	for w in ["iron", "steel", "chain", "mail", "plate", "tin", "bronze", "silver", "gold", "helm"]:
		if id.contains(w):
			return "metal"
	for w in ["leather", "hide", "boots", "jerkin", "gloves", "belt", "wood", "shield"]:
		if id.contains(w):
			return "leather"
	return "cloth"


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
		or float(d.get("use_mana", 0.0)) > 0.0 or not (d.get("use_cures", []) as Array).is_empty()


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
	# Using something from the Codex backpack closes the book first, so you see it happen.
	var codex := get_tree().get_first_node_in_group("codex")
	if codex and codex.has_method("is_open") and codex.call("is_open"):
		codex.call("close")
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
		return combat.channel(String(d.get("name", id)), seconds, _apply_use.bind(id), anim, true)
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
		Effects.heal_burst(get_parent())
	if float(d.get("use_hot_per_tick", 0.0)) > 0.0:
		stats.add_heal_over_time(float(d.use_hot_per_tick), int(d.get("use_hot_ticks", 1)), 2.0, self)
		Effects.heal_glow(get_parent(), int(d.get("use_hot_ticks", 1)) * 2.0)
	if float(d.get("use_mana", 0.0)) > 0.0:
		stats.restore_mana(float(d.use_mana))
	for st in d.get("use_cures", []):
		stats.remove_status(String(st))
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
	var seconds := float(d.get("cast_time", 8.0))
	var loop := DataFiles.stream_from(d.get("hearth_sound", "")) if String(d.get("hearth_sound", "")) != "" else null
	var glow := Color.from_string(String(d.get("hearth_light", "#5fc8ff")), Color(0.37, 0.78, 1.0))
	var fade := Color.from_string(String(d.get("hearth_fade", "#e4f6ff")), Color(0.9, 0.97, 1.0))
	var started: bool = combat.channel("Hearthstone: %s" % home.get("name", "Home"), seconds, func() -> void:
		GameSession.data["hearth_ready_at"] = Time.get_unix_time_from_system() + float(d.get("cooldown", 600.0))
		Effects.burst(Combat.world_root(player), (player as Node3D).global_position + Vector3.UP, glow, 1.4)
		var boom := String(d.get("teleport_sound", ""))
		if boom != "":
			Combat.play_sound(player, DataFiles.stream_from(boom), 0.0)
		GameSession.travel_home(fade, float(d.get("hearth_fade_out", 0.7)), float(d.get("hearth_fade_in", 1.2))), "cast_channel", false, loop, true, true)  # in_air: works when stuck "falling"; in_water: while swimming
	if started:
		_hearth_glow(player as Node3D, combat, seconds, glow, float(d.get("hearth_light_energy", 3.0)))
	return started


## The azure light around the player while the hearthstone channels: it swells with the
## cast bar and goes out if the cast stops.
func _hearth_glow(player: Node3D, combat: Node, seconds: float, color: Color, energy: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.0
	light.omni_range = 4.5
	light.position = Vector3.UP * 1.1
	player.add_child(light)
	var swirl := Effects.hand_glow(color)
	var hand := (player.get_node_or_null("Model/Character") as CharacterModel)
	if hand:
		hand.attach_to_hand(swirl)
	var t := light.create_tween()
	t.tween_property(light, "light_energy", energy, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	var stop := func(_reason := "") -> void:
		if is_instance_valid(light):
			var out := light.create_tween()
			out.tween_property(light, "light_energy", 0.0, 0.25)
			out.tween_callback(light.queue_free)
		if is_instance_valid(swirl) and swirl.get_parent():
			swirl.get_parent().queue_free()
	combat.connect("cast_interrupted", stop, CONNECT_ONE_SHOT)
	# Done (or the level is reloading): it goes out with the bar.
	await get_tree().create_timer(seconds + 0.05).timeout
	if combat.is_connected("cast_interrupted", stop):
		combat.disconnect("cast_interrupted", stop)
	if is_instance_valid(light) and not combat.call("is_casting"):
		stop.call()


## Uses an item by id (from its first stack in the backpack), as the hotbar does.
func use_item(id: String) -> bool:
	if equipped.get("primary", "") == id:
		return true  # that weapon is already in hand
	for index in SIZE:
		if bag[index] and bag[index].id == id:
			return use_at(index)
	HUD.notify(self, "No %s left" % item(id).get("name", id), Color(1, 0.8, 0.6))
	return false


# --- Hotbar --------------------------------------------------------------------

func set_hotbar(i: int, entry: String) -> void:
	if i < 0 or i >= HOTBAR_SIZE or not hotbar_allows(entry):
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
	if hotbar.has(entry) or not hotbar_allows(entry):
		return
	var i := hotbar.find("")
	if i >= 0:
		set_hotbar(i, entry)


func _default_hotbar() -> void:
	hotbar.fill("")
	var d: Array = Database.player.get("hotbar", [])
	for i in mini(d.size(), HOTBAR_SIZE):
		hotbar[i] = String(d[i])
	_clean_hotbar()


## Abilities and usable items go on the hotbar; weapons don't (one weapon, in hand).
func hotbar_allows(entry: String) -> bool:
	return not (entry.begins_with("item:") and is_weapon(entry.trim_prefix("item:")))


## Takes weapons off the bar (saves from when weapons sat there) and closes the gaps.
func _clean_hotbar() -> void:
	var kept: Array = hotbar.filter(func(e: Variant) -> bool: return String(e) != "" and hotbar_allows(String(e)))
	if kept.size() == hotbar.filter(func(e: Variant) -> bool: return String(e) != "").size():
		return
	hotbar.fill("")
	for i in kept.size():
		hotbar[i] = kept[i]


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
	return {"bag": bag.duplicate(true), "equipped": equipped.duplicate(), "gold": gold, "hotbar": hotbar.duplicate(), "hotbar_version": 3,
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
	var retired: Array[String] = []
	for saved_slot: String in eq:
		var slot: String = OLD_SLOTS.get(saved_slot, saved_slot)
		if slot in SLOTS and fits(String(eq[saved_slot]), slot):
			equipped[slot] = String(eq[saved_slot])
		elif slot in RETIRED_SLOTS:
			retired.append(String(eq[saved_slot]))
	# The weapon that was in use stays in hand; the other goes to the backpack.
	if String(data.get("active_weapon", "primary")) == "secondary" and not retired.is_empty() and equipped.has("primary"):
		var was := String(equipped.primary)
		equipped.primary = retired[0]
		retired[0] = was
	for id in retired:
		var free := bag.find(null)
		if free >= 0:
			bag[free] = {"id": id, "count": 1}
	gold = int(data.get("gold", 0))
	active_weapon = String(data.get("active_weapon", "primary"))
	if not active_weapon in WEAPON_SLOTS:
		active_weapon = "primary"
	var hb = data.get("hotbar")
	if hb is Array and hb.size() == OLD_HOTBAR_SIZE:
		# Older save: boxes 1 and 2 were the two weapons. They become hotbar entries for
		# both weapons (press to switch), and the old entries keep their keys 3-0.
		hotbar.fill("")
		for i in OLD_HOTBAR_SIZE:
			hotbar[i] = String(hb[i])
	elif hb is Array:
		for i in mini(hb.size(), HOTBAR_SIZE):
			hotbar[i] = String(hb[i])
		if int(data.get("hotbar_version", 1)) < 2:
			# The old default bar put the potion and bandage in boxes 3 and 4; now items
			# are only on the bar when the player puts them there.
			if hotbar[2] == "item:minor_healing_potion" and hotbar[3] == "item:bandage":
				hotbar[2] = ""
				hotbar[3] = ""
		if int(data.get("hotbar_version", 1)) < 3:
			# The old default bar gave every class Firebolt and Mend in boxes 1 and 2; now
			# box 1 holds the class's starting skill (offered again by PlayerProgress).
			if hotbar[0] == "ability:firebolt" and hotbar[1] == "ability:mend":
				hotbar[0] = ""
				hotbar[1] = ""
				if GameSession.active():
					GameSession.data.erase("hotbar_offered")
	else:
		# Older save: the default bar, plus whatever was in the old quick slots.
		_default_hotbar()
		for id in data.get("quick", []):
			if not String(id).is_empty():
				add_to_hotbar("item:" + String(id))
	_clean_hotbar()
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
	var spare: Array[String] = []
	for kit_slot: String in eq:
		var slot: String = OLD_SLOTS.get(kit_slot, kit_slot)
		if fits(String(eq[kit_slot]), slot):
			equipped[slot] = String(eq[kit_slot])
		elif slot in RETIRED_SLOTS:
			spare.append(String(eq[kit_slot]))
	for entry in kit.get("backpack", []):
		add_item(String(entry[0]), int(entry[1]))
	for id in spare:
		add_item(id, 1)
	_default_hotbar()
	hotbar_changed.emit()
