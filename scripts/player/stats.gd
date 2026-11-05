class_name Stats
extends Node
## Health, mana and stamina for a character. Emits signals the HUD listens to.

signal health_changed(current: float, maximum: float)
signal mana_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal died

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


func _ready() -> void:
	health = max_health
	mana = max_mana
	stamina = max_stamina
	emit_all()


func _process(delta: float) -> void:
	_stamina_idle_time += delta
	if _stamina_idle_time >= stamina_regen_delay and stamina < max_stamina:
		stamina = minf(stamina + stamina_regen * delta, max_stamina)
		stamina_changed.emit(stamina, max_stamina)
	if mana < max_mana:
		mana = minf(mana + mana_regen * delta, max_mana)
		mana_changed.emit(mana, max_mana)


func take_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)


## Back to full health, mana and stamina (respawning).
func restore() -> void:
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
