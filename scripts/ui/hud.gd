extends CanvasLayer
## HUD: health, mana and stamina bars bound to a Stats node, the fatigue bar and
## short centre-screen messages.

@export var stats_path: NodePath

@onready var health_bar: ProgressBar = %HealthBar
@onready var mana_bar: ProgressBar = %ManaBar
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var fatigue_bar: ProgressBar = %FatigueBar
@onready var message: Label = %Message

const RESPAWN_MESSAGES := {
	"drowned": "You were overcome by fatigue.",
	"fell": "You fell from the world.",
	"died": "You died.",
}

var _message_tween: Tween


func _ready() -> void:
	var stats := get_node_or_null(stats_path) as Stats
	if stats == null:
		push_warning("HUD: no Stats node at %s" % stats_path)
		return
	stats.health_changed.connect(_set_bar.bind(health_bar))
	stats.mana_changed.connect(_set_bar.bind(mana_bar))
	stats.stamina_changed.connect(_set_bar.bind(stamina_bar))
	stats.emit_all()
	var player := stats.get_parent() as PlayerController
	if player:
		player.fatigue_changed.connect(_on_fatigue_changed)
		player.respawned.connect(func(reason: String) -> void: show_message(RESPAWN_MESSAGES.get(reason, "")))


func show_message(text: String, seconds := 3.0) -> void:
	if text.is_empty():
		return
	message.text = text
	if _message_tween:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_property(message, "modulate:a", 1.0, 0.3)
	_message_tween.tween_interval(seconds)
	_message_tween.tween_property(message, "modulate:a", 0.0, 0.8)


func _on_fatigue_changed(current: float, maximum: float) -> void:
	fatigue_bar.visible = current > 0.0
	fatigue_bar.max_value = maximum
	fatigue_bar.value = current


func _set_bar(current: float, maximum: float, bar: ProgressBar) -> void:
	bar.max_value = maximum
	bar.value = current
