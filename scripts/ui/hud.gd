extends CanvasLayer
## Milestone 1 HUD: health, mana and stamina bars bound to a Stats node.

@export var stats_path: NodePath

@onready var health_bar: ProgressBar = %HealthBar
@onready var mana_bar: ProgressBar = %ManaBar
@onready var stamina_bar: ProgressBar = %StaminaBar


func _ready() -> void:
	var stats := get_node_or_null(stats_path) as Stats
	if stats == null:
		push_warning("HUD: no Stats node at %s" % stats_path)
		return
	stats.health_changed.connect(_set_bar.bind(health_bar))
	stats.mana_changed.connect(_set_bar.bind(mana_bar))
	stats.stamina_changed.connect(_set_bar.bind(stamina_bar))
	stats.emit_all()


func _set_bar(current: float, maximum: float, bar: ProgressBar) -> void:
	bar.max_value = maximum
	bar.value = current
