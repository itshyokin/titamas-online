class_name Stats
extends Node
## Health, mana and stamina for a character (player or enemy), plus who it is in a
## fight: name, level and team. Emits signals the HUD and nameplates listen to.
## Anything with a Stats child and in the "combatants" group can be targeted and hit.

signal health_changed(current: float, maximum: float)
signal mana_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal died
## A hit landed: `source` is the attacker (may be null).
signal damaged(amount: float, source: Node, crit: bool)
## Health spent in place of missing mana (spend_mana).
signal blood_paid(amount: float)
signal healed(amount: float)
signal level_changed(level: int)

enum Team { PLAYERS, ENEMIES }

@export var display_name := ""
@export var level := 1:
	set(v):
		if v != level:
			level = v
			level_changed.emit(level)
@export var team := Team.PLAYERS
## Can't drop below 1 health (training dummies).
@export var immortal := false

@export var max_health := 100.0
@export var max_mana := 100.0
@export var max_stamina := 100.0

## Stamina regained per second once the regen delay has passed.
@export var stamina_regen := 20.0
## Seconds after last stamina use before it starts regenerating.
@export var stamina_regen_delay := 1.0
@export var mana_regen := 2.0

var health := 0.0
var mana := 0.0
var stamina := 0.0

## From equipment (set_bonuses): flat damage added to weapon attacks and to spells,
## armour (each point takes a little off every hit), and extra share of damage blocked.
var attack := 0.0
var spell_power := 0.0
var armor := 0.0
var block := 0.0
## Damage this character deals is multiplied by this (Weakened after dying: 0.8).
var damage_scale := 1.0
var _base_health := -1.0
var _base_mana := -1.0
var _bonus := {}
var _base_stamina := -1.0
## Attribute values (strength, agility...) for display; their stat effects arrive in the
## skill bonus (PlayerProgress._apply_skills).
var attributes := {}
var _base_mana_regen := -1.0
var _skill_bonus := {}  # from skills (PlayerProgress): attack, armor, crit_chance (%), stamina...
## Extra chance to land a critical hit (0.05 = 5 points more), from skills.
var crit_bonus := 0.0
var _level_bonus := {}  # {health, mana, attack, spell_power} from levels (PlayerProgress)
var _max_health_scale := 1.0

var _stamina_idle_time := 0.0
var _hots: Array[Dictionary] = []  # {per_tick, ticks_left, interval, timer, source}
## Status ailments / buffs / debuffs (data/statuses.json): id -> {left, duration, source}.
var statuses := {}
signal statuses_changed


func _ready() -> void:
	health = max_health
	mana = max_mana
	stamina = max_stamina
	emit_all()
	# Rage glows, Frozen ices over, Ward puts a bubble round them (statuses.json "look").
	statuses_changed.connect(func() -> void: StatusLook.refresh(get_parent(), self))


func _process(delta: float) -> void:
	_update_hots(delta)
	_update_statuses(delta)
	_stamina_idle_time += delta
	if _stamina_idle_time >= stamina_regen_delay and stamina < max_stamina:
		stamina = minf(stamina + stamina_regen * delta, max_stamina)
		stamina_changed.emit(stamina, max_stamina)
	if mana_debt > 0.0:
		# Paid for with health: regeneration goes to the debt first, mana stays empty
		# (and the "drained" Weakened status stays on) until it's paid off.
		mana_debt = maxf(mana_debt - mana_regen * delta, 0.0)
		if has_status(DRAINED):
			if mana_debt <= 0.0:
				remove_status(DRAINED)
		elif mana_debt > 0.0:
			add_status(DRAINED, 3600.0)
	elif mana < max_mana:
		mana = minf(mana + mana_regen * delta, max_mana)
		mana_changed.emit(mana, max_mana)


## Gives a status (data/statuses.json id) for `seconds` (renews it if it's already on).
func add_status(id: String, seconds: float, source: Node = null) -> void:
	if is_dead() or seconds <= 0.0:
		return
	var d := status_data(id)
	if d.is_empty():
		push_warning("Stats: no status '%s' in data/statuses.json" % id)
		return
	var owner_node := get_parent()
	if owner_node and owner_node.has_method("resists_status") and owner_node.resists_status(id):
		return
	var had := statuses.has(id)
	var e: Dictionary = statuses.get(id, {"left": 0.0, "duration": 0.0})
	e.left = maxf(float(e.left), seconds)
	e.duration = maxf(float(e.duration), seconds) if had else seconds
	e.source = source
	statuses[id] = e
	statuses_changed.emit()
	if not had and is_inside_tree():
		FloatingText.spawn(get_parent() as Node3D, String(d.get("name", id)), Color.html(String(d.get("color", "#ffffff"))), 1.0)


## Clears every ailment and debuff (buffs stay). Returns how many went.
func cure_all() -> int:
	var gone := 0
	for id: String in statuses.keys():
		if String(status_data(id).get("kind", "ailment")) != "buff":
			statuses.erase(id)
			gone += 1
	if gone > 0:
		statuses_changed.emit()
	return gone


func remove_status(id: String) -> void:
	if statuses.erase(id):
		statuses_changed.emit()


func has_status(id: String) -> bool:
	return statuses.has(id)


## True if any active status has this flag (no_spells, confused, injured).
func status_flag(flag: String) -> bool:
	for id: String in statuses:
		if bool(status_data(id).get(flag, false)):
			return true
	return false


## The biggest value of a number field among active statuses (miss_chance...).
func status_value(field: String) -> float:
	var best := 0.0
	for id: String in statuses:
		best = maxf(best, float(status_data(id).get(field, 0.0)))
	return best


## Active statuses' number field multiplied together (move_scale...), 1 with none.
func status_product(field: String) -> float:
	var k := 1.0
	for id: String in statuses:
		k *= float(status_data(id).get(field, 1.0))
	return k


static func status_data(id: String) -> Dictionary:
	var loop := Engine.get_main_loop() as SceneTree
	var db := loop.root.get_node_or_null("Database") if loop else null
	var all = db.get("statuses") if db else null
	return all.get(id, {}) if all is Dictionary else {}


func _update_statuses(delta: float) -> void:
	if statuses.is_empty():
		return
	var gone := false
	for id: String in statuses.keys():
		var e: Dictionary = statuses[id]
		e.left = float(e.left) - delta
		var dps := float(status_data(id).get("damage_per_second", 0.0))
		if dps > 0.0 and not is_dead():
			take_damage(dps * delta, e.get("source") if is_instance_valid(e.get("source")) else null)
		elif dps < 0.0:
			heal(-dps * delta)
		if float(e.left) <= 0.0:
			statuses.erase(id)
			gone = true
	if gone:
		statuses_changed.emit()


func is_dead() -> bool:
	return health <= 0.0


func take_damage(amount: float, source: Node = null, crit := false) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 1.0 if immortal else 0.0)
	health_changed.emit(health, max_health)
	damaged.emit(amount, source, crit)
	if health <= 0.0:
		_hots.clear()
		statuses.clear()
		statuses_changed.emit()
		died.emit()


func heal(amount: float) -> void:
	if health <= 0.0:
		return
	var before := health
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)
	if health > before:
		healed.emit(health - before)


## The status that comes with running out of mana (data/statuses.json).
const DRAINED := "drained"
## Mana paid for with health that regeneration pays back before mana returns.
var mana_debt := 0.0


## Spends mana; what's missing comes out of health instead (`blood_price` health per
## point), and the character is Weakened (status "drained") until regeneration has paid
## it back. Returns false (and spends nothing) if that would take the last of its health.
func spend_mana(amount: float, blood_price := 1.0) -> bool:
	if amount <= 0.0:
		return true
	var from_mana := minf(mana, amount)
	var short := amount - from_mana
	var hp := short * blood_price
	if short > 0.0 and health - hp < 1.0:
		return false
	mana -= from_mana
	mana_changed.emit(mana, max_mana)
	if short > 0.0:
		mana = 0.0
		mana_debt += short
		health -= hp
		health_changed.emit(health, max_health)
		blood_paid.emit(hp)
		add_status(DRAINED, 3600.0)
	return true


## Whether spend_mana would go through.
func can_spend_mana(amount: float, blood_price := 1.0) -> bool:
	return amount <= mana or health - (amount - mana) * blood_price >= 1.0


## Spends mana. Returns false (and spends nothing) if there isn't enough.
func use_mana(amount: float) -> bool:
	if mana < amount:
		return false
	mana -= amount
	mana_changed.emit(mana, max_mana)
	return true


## Heal over time: `ticks` heals of `per_tick`, one every `interval` seconds.
## Re-applying from the same source refreshes it instead of stacking.
func add_heal_over_time(per_tick: float, ticks: int, interval: float, source: Object = null) -> void:
	for hot in _hots:
		if hot.source == source:
			_hots.erase(hot)
			break
	_hots.append({"per_tick": per_tick, "ticks_left": ticks, "interval": interval, "timer": interval, "source": source})


## Seconds left on the heal over time from `source` (0 if none).
func heal_over_time_left(source: Object) -> float:
	for hot in _hots:
		if hot.source == source:
			return hot.timer + (hot.ticks_left - 1) * hot.interval
	return 0.0


func _update_hots(delta: float) -> void:
	for i in range(_hots.size() - 1, -1, -1):
		var hot := _hots[i]
		hot.timer -= delta
		if hot.timer <= 0.0:
			hot.timer += hot.interval
			hot.ticks_left -= 1
			heal(hot.per_tick)
			if hot.ticks_left <= 0:
				_hots.remove_at(i)


## Back to full health, mana and stamina (respawning).
func restore() -> void:
	_hots.clear()
	health = max_health
	mana = max_mana
	mana_debt = 0.0
	if has_status(DRAINED):
		remove_status(DRAINED)
	stamina = max_stamina
	emit_all()


## Spends stamina. Returns false (and spends nothing) if there isn't enough.
func use_stamina(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if stamina < amount:
		return false
	stamina -= amount
	_stamina_idle_time = 0.0
	stamina_changed.emit(stamina, max_stamina)
	return true


## Drains stamina continuously (for sprinting). Returns false once empty.
func drain_stamina(amount: float) -> bool:
	_stamina_idle_time = 0.0
	stamina = maxf(stamina - amount, 0.0)
	stamina_changed.emit(stamina, max_stamina)
	return stamina > 0.0


## Base maximums before equipment (the Database sets these from the player's data).
func set_base(base_health: float, base_mana: float) -> void:
	_base_health = base_health
	_base_mana = base_mana
	_base_mana_regen = mana_regen
	set_bonuses(_bonus)


## Equipment totals: {attack, spell_power, armor, block, bonus_health, bonus_mana}.
func set_bonuses(bonus: Dictionary) -> void:
	if _base_health < 0.0:
		_base_health = max_health
		_base_mana = max_mana
	_bonus = bonus
	var sk := _skill_bonus
	attack = float(bonus.get("attack", 0.0)) + float(_level_bonus.get("attack", 0.0)) + float(sk.get("attack", 0.0))
	spell_power = float(bonus.get("spell_power", 0.0)) + float(_level_bonus.get("spell_power", 0.0)) + float(sk.get("spell_power", 0.0))
	armor = float(bonus.get("armor", 0.0)) + float(sk.get("armor", 0.0))
	block = float(bonus.get("block", 0.0)) + float(sk.get("block", 0.0))
	max_health = roundf((_base_health + float(bonus.get("bonus_health", 0.0)) + float(_level_bonus.get("health", 0.0)) + float(sk.get("bonus_health", 0.0))) * _max_health_scale)
	max_mana = _base_mana + float(bonus.get("bonus_mana", 0.0)) + float(_level_bonus.get("mana", 0.0)) + float(sk.get("bonus_mana", 0.0))
	crit_bonus = float(sk.get("crit_chance", 0.0)) / 100.0
	if _base_stamina < 0.0:
		_base_stamina = max_stamina
	max_stamina = _base_stamina + float(sk.get("stamina", 0.0))
	if _base_mana_regen < 0.0:
		_base_mana_regen = mana_regen
	mana_regen = _base_mana_regen + float(sk.get("mana_regen", 0.0))
	stamina = minf(stamina, max_stamina)
	health = minf(health, max_health)
	mana = minf(mana, max_mana)
	emit_all()


## Bonuses from skills (see _skill_bonus).
func set_skill_bonus(bonus: Dictionary) -> void:
	_skill_bonus = bonus
	set_bonuses(_bonus)


## Extra health, mana, attack and spell power from the character's level.
func set_level_bonus(bonus: Dictionary) -> void:
	_level_bonus = bonus
	set_bonuses(_bonus)


## Shrinks (or restores) maximum health, e.g. 0.8 while Weakened.
func set_max_health_scale(k: float) -> void:
	_max_health_scale = k
	set_bonuses(_bonus)


func restore_mana(amount: float) -> void:
	# A potion pays back what health covered first.
	var to_debt := minf(mana_debt, amount)
	mana_debt -= to_debt
	amount -= to_debt
	if mana_debt <= 0.0 and has_status(DRAINED):
		remove_status(DRAINED)
	mana = minf(mana + amount, max_mana)
	mana_changed.emit(mana, max_mana)


func emit_all() -> void:
	health_changed.emit(health, max_health)
	mana_changed.emit(mana, max_mana)
	stamina_changed.emit(stamina, max_stamina)
