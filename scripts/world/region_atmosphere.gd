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
## How dark shadows are: 1 = full, lower = softer (stylized, lighter shadows).
@export_range(0.0, 1.0) var shadow_strength := 0.6

## Light shafts through the air (god rays): 0 = none, 1 = strong.
@export_range(0.0, 1.0) var god_rays := 0.3

@export_group("Grass")
## Grass clumps per square metre where the ground is painted grass (0 = none).
@export var grass_density := 6.0
@export var grass_base := Color(0.16, 0.36, 0.12)
@export var grass_tip := Color(0.55, 0.78, 0.3)
## Height of the grass clumps (m).
@export var grass_height := 0.8
## 0 = grass takes the colours above; 1 = it takes the colour of the ground under it.
@export var grass_ground_match := 0.85

@export_group("Colour")
## 1 = unchanged. Above 1 = more saturated, punchier colours.
@export_range(0.0, 2.0) var saturation := 1.2
@export_range(0.5, 1.5) var contrast := 1.05
@export_range(0.5, 1.5) var brightness := 1.0

@export_group("Sound")
## Looping background sound for the region (birds, forest, town bustle...). Crossfades
## when crossing into another region.
@export var ambient_loop: AudioStream
@export_range(-40.0, 6.0) var ambient_volume_db := -8.0
## After dark (crickets); none = the same as by day.
@export var ambient_loop_night: AudioStream
## Music while here (by day / after dark; none at night = the day music).
@export var music: AudioStream
@export var music_night: AudioStream
@export_range(-40.0, 6.0) var music_volume_db := -12.0
## How windy it is here at ground level (dB); higher ground gets windier on top of this.
@export_range(-60.0, 6.0) var wind_volume_db := -20.0
