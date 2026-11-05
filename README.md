# Titamas Online

A small-group (1–10 player) co-op 3D RPG set in the world of Titamas. Built in **Godot 4.6** with GDScript. Levels and characters are made in Blender.

## Running it

1. Pull with GitHub Desktop.
2. Open Godot 4.6, click **Import**, pick this folder's `project.godot`.
3. Press **F5** (Play). The overworld test loads your terrain chunks. The gray-box test level is `scenes/levels/test_level.tscn` (open it and press **F6**).

**Controls:** WASD move (runs by default) · hold Ctrl to walk · Shift sprint · Space jump · Alt dodge

**Combat:** left mouse attack (press again in time for the follow-up swing) · E heavy attack (stamina; staggers) · hold Q block (from the front; each blocked hit costs stamina) · 1 Firebolt (1.5 s cast, moving interrupts) · 2 Mend (heal over time on yourself) · Tab next target · Esc clear target · click an enemy to target it. Attacks pick the nearest enemy in front if nothing is targeted and lunge to close a short gap. Dodge through an enemy's swing to take no damage. The test level and the overworld each have a training dummy and two bandits.

**Traversal:** jump at a ledge to grab it (A/D shimmy, W or Space pull up, S or Ctrl drop) · jump at a climbable wall, or walk into a ladder, then W/S to climb (Space jumps off, Ctrl lets go) · swim in deep water, Space at an edge climbs out. The gray-box level (`scenes/levels/test_level.tscn`) has a test spot for each. · hold right mouse to look · mouse wheel zoom.

## Folder layout

| Folder | What goes there |
| --- | --- |
| `scenes/` | Godot scenes (`levels/`, `player/`, `ui/`) |
| `scripts/` | GDScript, mirroring `scenes/` |
| `assets/models/` | Exported `.glb` files Godot imports |
| `assets/levels/` | Exported level chunk `.glb` files |
| `assets/source/` | Source `.blend` files (not imported directly) |
| `data/` | Item, ability, quest and NPC data (later) |

## Blender conventions

- **Scale:** 1 unit = 1 metre. Characters about 1.8 m tall.
- **Export:** File → Export → glTF 2.0, format **glTF Binary (.glb)**, +Y Up on.
- **Characters:** Mixamo skeleton (`mixamorig:` bones), same names on masc and femme bodies.
- **Collision via name suffixes** (Godot reads these on import):
  - `-col` → visible mesh with matching collision
  - `-colonly` → invisible collision only (blockers, simplified terrain)
  - `-convcolonly` → invisible convex collision (cheap, for simple props)
  - `-noimp` → not imported (reference objects)

## Level chunks

- Chunks are square tiles on a fixed grid (64 m × 64 m for now), with the chunk's origin at its centre.
- No sky cube: the sky is Godot's `WorldEnvironment`. Model only ground and props.
- Terrain edges must line up with neighbours: border vertices sit exactly on the chunk edge at the same spacing (every 2 m), with matching heights.
- `chunk_I_J` is centred at Godot (I×64, 0, J×64), which is Blender (I×64, −J×64, 0). I grows east (+X), J grows south (Blender −Y).
- Connections that aren't on the grid (cave mouths, building doors) use **connector empties** named `CONN_<name>`; matching names snap together.

## Terrain add-on (Blender 4.1)

`tools/blender/titamas_terrain.py` makes and exports seamless chunks. Keep **one master terrain per region**; regions sit side by side on the same world grid.

1. Blender → Edit → Preferences → Add-ons → **Install…** → pick the file → tick **Titamas Terrain Chunks**. (To update: remove the old version first, then install the new file.)
2. In the 3D Viewport press **N** → **Titamas** tab.
3. **Start:** set Chunk X/Y and how many chunks east/south, press **New Terrain**.
4. **Grow it:** select the master terrain, set Chunk X/Y to where the new chunks go, press **Add Chunks to Terrain**. New chunks weld onto the existing edges.
5. **Next to another region:** point the Export Folder at the folder holding the neighbour's exported chunks and press **Match Edges to Exported Chunks**. Your border snaps to their heights and eases inward over the Blend Distance.
6. **Shape:** sculpt normally (locked to up/down so the grid stays straight), or use the **Set Height Brush** (Object Mode): drag to pull terrain toward the Height, Ctrl+click to sample a height, mouse wheel = radius, Shift+wheel = strength, Esc/right-click when done.
7. **Water:** add flat planes (any shape) to a collection named **Water**. They're exported with the chunks and become swimmable water in Godot.
8. Save the .blend, select the terrain, press **Export Chunks**. Copy the .glb files into `assets/levels/overworld/`.

**Ground painting:** select the terrain and press **Setup Terrain Painting** (once). It adds a `TerrainPaint` layer (red = grass, green = dirt, blue = cliff; exported to Godot through a second UV map), fills it from the grass/dirt/cliff materials you'd assigned, and switches the terrain to one `terrain` material. Then click **Grass / Dirt / Cliff** to paint that layer in Vertex Paint mode (Material Preview shading to see it). In Godot, `assets/materials/terrain/terrain.tres` mixes the textures with noisy edges and puts rock on steep slopes automatically (tune `auto_cliff`, `breakup`, `sharpness` there; swap textures by replacing `grass.jpg`, `dirt.png`, `cliff_stone.jpg`).

**Props (trees, rocks, …):** keep them in a collection named **Props** (sub-collections are fine). Place copies with Alt+D, or link existing copies with Ctrl+L → Link Object Data; the shared **mesh name** is the prop's name (e.g. `pine_tree`). **Export Chunks** also writes `chunk_I_J.props.json` (where each prop sits) — copy those with the .glb files. **Export Prop Library** writes each prop once as `<name>.glb` with its textures — copy those into `assets/props/`. Props are exported standing the way they stand in your scene (the rotation/scale of the alphabetically first copy is baked in and remembered), so re-run **Export Prop Library** and **Export Chunks** together after changing that. Props whose names contain tree/bush/grass/fern/flower/plant sway in the wind; trees get a trunk cylinder sized from the part whose material is called trunk/bark/wood, rocks and other solid props their exact shape, grass/flowers none.

**Editor preview:** the overworld scene shows every chunk, prop, the ocean and the region's sky/fog in the Godot editor. To tune a region's look, open its file in `assets/regions/` (e.g. `starting_region.tres`) and edit it; the view updates live. `AtmosphereManager → Editor Preview Region` picks which region is shown (-1 = open sea). After copying in new exports, toggle `ChunkStreamer → Editor Preview` off and on to reload.

**Materials:** name them in Blender (e.g. `grass`, `cliff`); Godot swaps in `assets/materials/terrain/<name>.tres`. Leave **Include Textures** off so chunk files stay small. UVs are world-space (one repeat per 4 m by default), so textures line up across seams.

**World edge:** the sea level is −5 m. Past the last chunk is open ocean; swimming far out builds fatigue.

## Sound

Sounds live in `assets/audio/` (sources and licences in `assets/audio/CREDITS.md`). Buses: **SFX**, **Ambience**, **Music** (Audio tab at the bottom of the editor).

- **Footsteps** follow the animation's feet and match the ground: painted grass/dirt, rock on cliffs and steep slopes, water when wading. Props pick a sound from their name (rocks = stone; tree/log/plank/crate/bridge = wood; metal/iron = metal). Anything else can be tagged: select a node with collision, Inspector → **Add Metadata** → name `surface`, type String, value `wood`, `stone`, `grass`, `dirt`, `snow`, `metal` or `water`.
- **Ambience:** each region file in `assets/regions/` has a **Sound** section: an **Ambient Loop** (birds, forest, town…; crossfades at region borders), its volume, and how windy it is. Wind gets stronger the higher you climb. Waves are loudest at the coast and fade inland.
- Loops can be any .ogg/.wav/.mp3; they're set to loop automatically.

## Combat

- **Abilities are data:** each attack or spell is a `.tres` file in `data/abilities/` (open it in the Inspector: damage, costs, cooldown, cast time, reach, animation and its hit time, sounds). `Player → PlayerCombat` lists which ones the player has. New spells of an existing kind (melee, bolt, heal over time) need no code.
- **Enemies:** `scenes/enemies/bandit.tscn`. Drop it into a level; its `Stats` child sets name, level and health, the root sets aggro range, leash, attack damage and timing, and respawn time. Enemies wait for the ground to stream in, then stand on it.
- **Training dummy:** a `StaticBody3D` with `scripts/enemy/training_dummy.gd`; it never dies and resets a few seconds after the last hit.
- **Animations:** the attack, block, cast, flinch and death clips are stand-ins posed by the retarget tool. Put a Mixamo FBX with the same name in `assets/animations/mixamo/` (`attack_light_1`, `attack_light_2`, `attack_heavy`, `block`, `cast_channel`, `cast_release`, `cast_heal`, `hit_react`, `death`, `idle_armed`) and rebuild; it replaces the stand-in. If a clip's timing changes, adjust the ability's **Hit Time** to match.

## Level markup

- **Climbable wall:** put the node in the `climbable` group (Node panel → Groups). Players jump onto it.
- **Ladder:** a thin box in the `ladder` group, with a platform at the top. Players walk into it.
- **Ledges:** any flat-topped edge 1.5–2.5 m above a jumping player can be grabbed; no markup needed.
- **Water:** add an `Area3D` with `scripts/world/water_volume.gd` and set its Size. The top of the box is the surface; water deeper than 1.3 m is swimmable.

## Animations

1. Download from Mixamo (same character as the base bodies): FBX, **Without Skin**, 30 fps. Tick **In Place** for looping movement.
2. Put the files in `assets/animations/mixamo/` with lowercase names (e.g. `running.fbx`).
3. New looping animations: add the name to `LOOPING` at the top of `tools/godot/retarget_mixamo.gd`.
4. Ask Claude to rebuild, or run `godot --headless --path . --script res://tools/godot/retarget_mixamo.gd`. This writes `assets/animations/masc.res` and `femme.res`.

## Milestones

1. Movement and camera
2. Combat ← **current**
3. Equipment
4. Co-op
5. Content tools
6. World
