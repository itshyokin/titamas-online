class_name TimeFX
extends Node
## Game-feel time effects: hit-stop (a split-second freeze when a blow lands) and slow
## motion (perfect dodges). Sets Engine.time_scale from real time, so it never gets stuck.
## One lives under the scene tree root; use the static helpers.

const FREEZE_SCALE := 0.04
const SLOW_SCALE := 0.3

var _freeze_until := 0
var _slow_until := 0
var _slow_length := 1


static func _instance(from: Node) -> TimeFX:
	if from == null or not from.is_inside_tree():
		return null
	# Co-op: slowing the game would slow it for everyone.
	var net := from.get_tree().root.get_node_or_null("Net")
	if net and net.get("active"):
		return null
	var root := from.get_tree().root
	var fx := root.get_node_or_null("TimeFX") as TimeFX
	if fx == null:
		fx = TimeFX.new()
		fx.name = "TimeFX"
		fx.process_mode = Node.PROCESS_MODE_ALWAYS
		root.add_child.call_deferred(fx)
	return fx


## Freezes the game for `seconds` of real time.
static func hit_stop(from: Node, seconds: float) -> void:
	var fx := _instance(from)
	if fx and seconds > 0.0:
		fx._freeze_until = maxi(fx._freeze_until, Time.get_ticks_msec() + int(seconds * 1000.0))
		Engine.time_scale = FREEZE_SCALE


## Slow motion for `seconds` of real time, easing back to normal speed at the end.
static func slow_motion(from: Node, seconds: float) -> void:
	var fx := _instance(from)
	if fx and seconds > 0.0:
		fx._slow_length = int(seconds * 1000.0)
		fx._slow_until = Time.get_ticks_msec() + fx._slow_length
		Engine.time_scale = SLOW_SCALE


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now < _freeze_until:
		Engine.time_scale = FREEZE_SCALE
	elif now < _slow_until:
		# Hold the slow-down, then ease back over the last third.
		var left := float(_slow_until - now) / maxf(_slow_length, 1.0)
		Engine.time_scale = lerpf(1.0, SLOW_SCALE, clampf(left * 3.0, 0.0, 1.0))
	elif Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
