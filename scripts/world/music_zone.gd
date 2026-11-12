@tool
class_name MusicZone
extends Node3D
## A place with its own music (the Monolith, a shrine, a town square): inside `radius`
## (metres, flat distance) the region's music fades to this one. The smallest zone the
## player stands in wins; battle music still takes over in a fight (AtmosphereManager).

@export var radius := 25.0:
	set(value):
		radius = value
		update_gizmos()
@export var music: AudioStream
## Optional: plays instead after dark.
@export var music_night: AudioStream
@export_range(-40.0, 6.0) var volume_db := -12.0


func _ready() -> void:
	add_to_group("music_zones")


func contains(point: Vector3) -> bool:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length() <= radius
