@tool
class_name Ability
extends Resource
## One attack or spell, as data. Abilities live in data/abilities.json (edit them with the
## Database editor: Godot toolbar → Database); the Database autoload builds these from it.
## New abilities are new entries, not new code: pick how it's delivered and fill in the numbers.

enum Delivery {
	MELEE,           ## Swing hitting everything in an arc in front.
	PROJECTILE,      ## Flies to the target and hits it.
	HEAL_OVER_TIME,  ## Heals the target (an ally, or yourself) in ticks.
}

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var delivery := Delivery.MELEE
## Colour of its action bar button.
@export var color := Color(0.6, 0.6, 0.6)
## Hotbar icon drawn for it: slash, heavy, arrow, bullet, fire, heal, frost, shield (or "" for its initial).
@export var icon := ""

@export_group("Numbers")
## Damage per hit (MELEE, PROJECTILE) or healing per tick (HEAL_OVER_TIME), at level 1.
@export var power := 10.0
@export var mana_cost := 0.0
@export var stamina_cost := 0.0
## Seconds before it can be used again.
@export var cooldown := 0.0
## Reach (MELEE) or maximum distance to the target (others), in metres.
@export var reach := 2.4
## Width of a melee swing, in degrees.
@export var arc := 120.0
## Heavy hits interrupt an enemy's attack.
@export var staggers := false
## How hard a hit pushes the target back (m/s).
@export var knockback := 2.0
## Spells: seconds of casting before it can go off (the cast bar). 0 = instant.
@export var cast_time := 0.0

@export_group("Charging")
## Holding the attack button charges it. Melee/bows: seconds to full charge.
## Spells: seconds per charge level.
@export var charge_time := 1.0
## Extra power at full charge: 1.0 = double damage when fully charged.
@export var charge_power := 1.0
## Spells: highest charge level (skill tree ranks will raise this). Mana cost is per level.
@export var max_charge_level := 1

@export_group("Heal over time")
@export var ticks := 4
@export var tick_interval := 2.0

@export_group("Projectile")
@export var projectile_speed := 18.0
@export var projectile_color := Color(1.0, 0.5, 0.15)
enum ProjectileStyle { BOLT, ARROW, BULLET }
@export var projectile_style := ProjectileStyle.BOLT

@export_group("Animation")
## Clip played when it goes off (casts play "cast_channel" while casting first).
@export var animation := ""
@export var animation_speed := 1.0
## Seconds into the clip (at speed 1) when the hit lands or the spell is released.
@export var hit_time := 0.3
## Seconds into the clip when the next action can start (combo / recovery).
@export var recovery_time := 0.5
## How much the player can move during it (0 = rooted, 1 = full run speed).
@export_range(0.0, 1.0) var move_scale := 0.2

@export_group("Sound")
@export var sounds: Array[AudioStream] = []
@export var hit_sound: AudioStream
