# Titamas Online

A small-group (1–10 player) co-op 3D RPG set in the world of Titamas. Built in **Godot 4.6** with GDScript. Levels and characters are made in Blender.

## Running it

1. Pull with GitHub Desktop.
2. Open Godot 4.6, click **Import**, pick this folder's `project.godot`.
3. Press **F5** (Play). The title screen opens: **New Game** goes to the character creator, then class select, then the overworld. **Load Game** lists your characters.
4. To skip the menus while testing, open a level and press **F6** (`scenes/levels/overworld_test.tscn`, or the gray-box `scenes/levels/test_level.tscn`). That plays a default character with the starting kit and saves nothing.

**Controls** (all rebindable: gear icon top right, or Esc / Start → Settings):

| Action | Controller | Keyboard and mouse |
| --- | --- | --- |
| Attack: tap = quick, hold = charge, release to let go | RT | Left mouse |
| Switch melee / ranged / magic | Y | R |
| Block (hold) | LT | F |
| Jump | A | Space |
| Dodge (with a direction; none = back-hop) | B | Alt |
| Sprint (controller: tap to toggle) | X | Shift (hold) |
| Previous / next spell (switches to magic) | D-pad left / right | Q / E |
| Use quick item 1 / 2 | D-pad up / down | Z / C |
| Character and backpack | Back | I or B |
| Previous / next target | LB / RB | Tab |
| Lock on (toggle) | R3 | Middle mouse |
| Camera | Right stick | Hold right mouse, wheel zoom |

Melee: rapid taps chain a three-hit combo (Slash, Backslash, then a staggering Finishing Blow), hold for a heavy blow. Ranged: tap for a quick shot, hold to draw (harder the longer). Magic: press attack to start casting; the cast bar has to fill before the spell goes off (tap and it goes off when full; keep holding to charge it up to level 3). Moving cancels a cast, light hits knock the bar back, and heavy hits interrupt it. Locked on, the camera keeps the target in view and moving sideways circles it. Stamina is only used by sprinting. The test level and the overworld each have a training dummy and two bandits.

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

**Props (trees, rocks, …):** names decide behaviour: `ladder` in the name makes it a ladder; `climb`, `ivy`, `vine` or `trellis` a climbable wall; any prop with a flat top you can jump up to is a grabbable ledge automatically.  keep them in a collection named **Props** (sub-collections are fine). Place copies with Alt+D, or link existing copies with Ctrl+L → Link Object Data; the shared **mesh name** is the prop's name (e.g. `pine_tree`). **Export Chunks** also writes `chunk_I_J.props.json` (where each prop sits) — copy those with the .glb files. **Export Prop Library** writes each prop once as `<name>.glb` with its textures — copy those into `assets/props/`. Props are exported standing the way they stand in your scene (the rotation/scale of the alphabetically first copy is baked in and remembered), so re-run **Export Prop Library** and **Export Chunks** together after changing that. Props whose names contain tree/bush/grass/fern/flower/plant sway in the wind; trees get a trunk cylinder sized from the part whose material is called trunk/bark/wood, rocks and other solid props their exact shape, grass/flowers none.

**Editor preview:** the overworld scene shows every chunk, prop, the ocean and the region's sky/fog in the Godot editor. To tune a region's look, edit it in the **Database** editor (Regions tab) and save; the view updates within a second. `AtmosphereManager → Editor Preview Region` picks which region is shown (-1 = open sea). After copying in new exports, toggle `ChunkStreamer → Editor Preview` off and on to reload.

**Materials:** name them in Blender (e.g. `grass`, `cliff`); Godot swaps in `assets/materials/terrain/<name>.tres`. Leave **Include Textures** off so chunk files stay small. UVs are world-space (one repeat per 4 m by default), so textures line up across seams.

**World edge:** the sea level is −5 m. Past the last chunk is open ocean; swimming far out builds fatigue.

## Sound

Sounds live in `assets/audio/` (sources and licences in `assets/audio/CREDITS.md`). Buses: **SFX** (with **Footsteps** under it), **Ambience**, **Music**. Players set volumes in Settings → Sound.

- **Footsteps** (six variants per surface, `assets/audio/footsteps/<surface>_<n>.ogg`; add more files with the next number to get more variety) follow the animation's feet and match the ground: painted grass/dirt, rock on cliffs and steep slopes, water when wading. Props pick a sound from their name (rocks = stone; tree/log/plank/crate/bridge = wood; metal/iron = metal). Anything else can be tagged: select a node with collision, Inspector → **Add Metadata** → name `surface`, type String, value `wood`, `stone`, `grass`, `dirt`, `snow`, `metal` or `water`.
- **Ambience:** each region (Database → Regions) has a **Sound** section: an **Ambient Loop** (birds, forest, town…; crossfades at region borders), its volume, and how windy it is. Wind gets stronger the higher you climb. Waves are loudest at the coast and fade inland.
- Loops can be any .ogg/.wav/.mp3; they're set to loop automatically.

## World look

- **Day and night:** the sun crosses from east to west; dawn and dusk tint the sky and light, then the moon and stars come out. A clock sits by the settings gear. Day length, start hour, noon sun height and how bright nights are: Database → World. In the editor, select `WorldCycle` in the overworld scene and change **Preview Hour** to see any time of day.
- **Wind** wanders between calm and gusty (Database → World): trees, grass, clouds and the wind sound all follow it.
- **Grass** grows by itself wherever the terrain is painted grass (thicker where the paint is stronger), never on cliffs, steep slopes or under water. Each region sets how thick it is and its root/tip colours (Database → Regions → Grass). Players can lower it in Settings → Graphics. It moves with the wind and parts around the player.
- **God rays:** light shafts through the air, strength per region (Database → Regions → Light and colour); Settings → Graphics can turn them off.
- **Water:** darker near the shore with a foam edge; ripples around you when wading or swimming, and a splash when you land in it.

## Database editor

Game data lives in `data/*.json`: **abilities**, **enemies** (including gold and loot drops), **items**, the **player** (stats, movement, combat feel, loadout, starting kit), the **world** (day length, start hour, wind) and **regions** (sky, fog, light, colour, god rays, grass, sound). Edit it RPG Maker style instead of in Godot's Inspector:

1. In Godot, click **Database** in the toolbar at the top (or **Project → Tools → Open Database Editor**). Your browser opens the editor.
2. Pick a tab on the left, an entry in the list, and change its fields. **New / Copy / Delete** under the list. Changing an ability's ID updates the player's loadout to match.
3. **Save** (or Ctrl+S) writes the files. If the game is running from Godot, it picks up the change within a second; the editor's region preview updates too.

The page only works while Godot is open (Godot serves it, on your own computer only). If the button is missing: **Project → Project Settings → Plugins → Titamas Database → Enable**.

## Combat

- **Abilities are data:** each attack or spell is an entry in the Database (damage, costs, cooldown, charge time and power, reach, animation and its hit time, sounds). The Player tab's loadout picks the melee combo, heavy attack, bow and up to four spells. New spells of an existing kind (melee, bolt/arrow, heal over time) need no code.
- **Feel:** blows that land freeze the game for a split second (hit-stop), shake the camera (Settings → Graphics → Screen shake), flash the target white, throw sparks and knock it back (each ability's **Knockback**).
- **Skill moves:**
  - **Parry:** start blocking just before a hit lands (**Parry window**, Player tab). You take no damage, the attacker is staggered, and your next hit is a **counter** (×1.75 and staggers).
  - **Perfect dodge:** dodge at the last moment and time slows down, with a counter ready.
  - **Flourish:** a fully charged heavy attack hits harder, staggers and knocks back further.
  - **Flow:** a swing can be cancelled into a block or dodge once it has landed, and an attack tapped during a dodge comes out as soon as the dodge ends.
- **Interrupts:** heavy hits (and hits worth 15% of your health or more) interrupt casts, charges and swings that haven't landed yet; smaller hits push a cast back.
- **Enemies:** `scenes/enemies/bandit.tscn`. Every third bandit attack is a slow heavy one: it flashes orange and shows "!" first. Dodge it, or parry it for a long stagger (Enemies tab → **Heavy attack**).
- **Placing enemies:** `scenes/enemies/bandit.tscn`. Drop it into a level and set its **Enemy Id** to an entry from the Database's Enemies tab (name, level, health, skin colour, aggro range, leash, attack damage and timing, respawn time). Enemies wait for the ground to stream in, then stand on it.
- **Training dummy:** a `StaticBody3D` with `scripts/enemy/training_dummy.gd`; it never dies and resets a few seconds after the last hit.
- **Animations:** the attack, block, cast, flinch and death clips are stand-ins posed by the retarget tool. Put a Mixamo FBX with the same name in `assets/animations/mixamo/` (`attack_light_1`, `attack_light_2`, `attack_heavy`, `block`, `bow_aim`, `bow_release`, `cast_channel`, `cast_release`, `cast_heal`, `hit_react`, `death`, `idle_armed`) and rebuild; it replaces the stand-in. If a clip's timing changes, adjust the ability's **Hit Time** to match.

## Title screen, characters and saves

- **Title screen** (`scenes/ui/main_menu.tscn`, the main scene): New Game, Load Game, Achievements (later), Settings, Credits, Quit. The last character you played stands on the dais.
- **Character creator:** species (Human for now), body type, pronouns, skin colour, height, build, hair style and colour, facial hair and colour (both bodies), eyes and eye colour, and a name. Drag to turn the character, mouse wheel to zoom on the face, **Randomize** for ideas. All the choices are in `data/appearance.json` (colour lists, styles, heights, builds, where the eyes sit on each face).
- **Class select:** Fighter for now; Rogue, Mage and Druid show as "coming soon". The preview wears the class's starting gear. Classes are in the Database's **Classes** tab; a class can have its own starting kit (empty = the Player tab's). Skill trees and stats come later.
- **Saves:** one file per character in Godot's user folder (`user://saves/`; on Windows `%APPDATA%\Godot\app_userdata\Titamas Online\saves`). Saved when the backpack changes, every minute, from **Settings → Save game**, on **Quit to title**, and when you close the window. It keeps the look, class, gear, backpack, gold, level, where you are and play time. Load Game shows your characters (double-click or **Play**) and can delete them.
- **Credits** text is in `data/credits.json`.

**Your own art for the creator**
- **Eyes:** each style is `assets/characters/eyes/<id>.png` (the eye, outer corner on the right, iris drawn light grey) plus `<id>_iris.png` (white where the eye colour goes). Draw over the placeholders or add new ones and list them under `eyes` in `data/appearance.json`. If the eyes sit wrong on a face, adjust `eye_placement` there (height, apart, width, tall).
- **Hair and facial hair:** the placeholders are made from the head mesh by `tools/godot/make_appearance.gd`. Hair made in Blender, weight-painted to the same rig, replaces them: set the style's `fitted_masc` / `fitted_femme` to your file. Rigid extras (ponytail, bun, long hair) are `model` + `fit`, like items. Helmets hide the hair ("hair" under Hides in the Items tab).
- **Height and build:** height scales the whole character (Short 0.93, Tall 1.07). Thin and Heavy push the body in or out along its surface: most at the belly and hips, less on the limbs, a little on the face. Armour follows. If you add shape keys named `heavy` and `thin` to the body parts in Blender, those are used instead.

## Equipment and backpack

- **Character window** (I, B or Back on a controller): equipment slots on the left, stats and gold in the middle, a 24-slot backpack on the right. Click an item to see it. Right-click or double-click equips or uses it; drag between slots to move or equip; drag out of the window to throw it away (it asks first). On a controller: A equips/uses, Y picks up and places, X sets the item as a quick item.
- **Quick items:** two slots, used with D-pad up/down (Z/C). Set them from the window.
- **Gear shows on the body**, on both masc and femme. Armour adds armour (less damage taken), health and mana; weapons add attack or spell power; a shield adds block. The bow only works with a bow equipped in the Ranged slot.
- **Loot:** bandits drop a sack with gold and items. Walk over it to pick it up; anything that doesn't fit stays in the sack for a few minutes.
- **Items** are in the Database's **Items** tab: name, kind, slot, rarity, stats, what using it does, and its look. The Player tab has the **Starting kit**. Each character keeps its own backpack and gear in its save.
- **Fit Armor** (toolbar button) opens the armour-fitting editor with both bodies side by side. Pick an item and a body, then move, turn and scale each piece on its bone (arrow keys and Page Up/Down nudge, Shift for bigger steps, right-drag orbits the camera). **Save** writes `data/items.json`. "Copy to other body" gives you a starting point for the other body.
- **Your own models:** the current armour is placeholder, made from the body meshes. Rigid pieces (helms, pauldrons, weapons, shields): export a `.glb` and set the item's **Model**, then fit it. Skinned pieces (shirts, trousers, boots): skin them to the same Mixamo armature in Blender and set **Fitted (masc)/(femme)** to the scene; tick the body parts it covers under **Hides**. `tools/godot/make_placeholder_armor.gd` rebuilds the placeholders.

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
2. Combat
3. Equipment ← **done, being tested**
4. Co-op
5. Content tools
6. World
