@tool
class_name RegionAtmosphere
extends Resource
## Look of one region: fog, sky and light. AtmosphereManager blends between these as
## the player crosses region borders. Regions are rectangles on the chunk grid.

@export var region_name := ""
## Chunks covered: position = first chunk (I, J), size = how many chunks across/down.
@export var chunks := Rect2i(0, 0, 1, 1)

@export_group("Fog")
@export var fog_color := Color(0.72, 0.78, 0.85)
@export var fog_density := 0.004
## How much the fog colours the sky near the horizon.
@export_range(0.0, 1.0) var fog_sky_affect := 0.5

@export_group("Sky")
@export var sky_top := Color(0.24, 0.45, 0.78)
@export var sky_horizon := Color(0.70, 0.80, 0.90)
@export var sky_ground := Color(0.32, 0.36, 0.40)
@export var cloud_color := Color(1, 1, 1)
@export var cloud_shade := Color(0.70, 0.74, 0.82)
@export_range(0.0, 1.0) var cloud_coverage := 0.45

@export_group("Light")
@export var sun_color := Color(1.0, 0.95, 0.85)
@export var sun_energy := 1.1
@export var ambient_energy := 0.6

@export_group("Sound")
## Looping background sound for the region (birds, forest, town bustle...). Crossfades
## when crossing into another region.
@export var ambient_loop: AudioStream
@export_range(-40.0, 6.0) var ambient_volume_db := -8.0
## How windy it is here at ground level (dB); higher ground gets windier on top of this.
@export_range(-60.0, 6.0) var wind_volume_db := -20.0
