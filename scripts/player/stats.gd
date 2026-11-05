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
signal healed(amount: float)

enum Team { PLAYERS, ENEMIES }

@export var display_name := ""
@export var level := 1
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

var _stamina_idle_time := 0.0
var _hots: Array[Dictionary] = []  # {per_tick, ticks_left, interval, timer, source}


func _ready() -> void:
	health = max_health
	mana = max_mana
	stamina = max_stamina
	emit_all()


func _process(delta: float) -> void:
	_update_hots(delta)
	_stamina_idle_time += delta
	if _stamina_idle_time >= stamina_regen_delay and stamina < max_stamina:
		stamina = minf(stamina + stamina_regen * delta, max_stamina)
		stamina_changed.emit(stamina, max_stamina)
	if mana < max_mana:
		mana = minf(mana + mana_regen * delta, max_mana)
		mana_changed.emit(mana, max_mana)


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
		died.emit()


func heal(amount: float) -> void:
	if health <= 0.0:
		return
	var before := health
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)
	if health > before:
		healed.emit(health - before)


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
	stamina = max_stamina
	emit_all()


## Spends stamina. Returns false (and spends nothing) if there isn't enough.
func use_stamina(amount: float) -> bool:
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


func emit_all() -> void:
	health_changed.emit(health, max_health)
	mana_changed.emit(mana, max_mana)
	stamina_changed.emit(stamina, max_stamina)
