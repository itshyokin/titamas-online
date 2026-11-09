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
| Attack: tap = quick, hold = charge (heavy blow, bow draw) | RT | Left mouse |
| Block (melee) / aim (ranged), hold | LT | Q |
| Swap primary / secondary weapon | Y | R |
| Primary / secondary weapon | (Y) | 1 / 2 |
| Hotbar boxes 3–10 (spells, potions…) | Hold D-pad up: ability wheel | 3–9, 0 (or keypad) |
| Jump | A | Space |
| Talk, loot, open, examine | A | E |
| Dodge / roll (with a direction; none = back-hop) | B | Double-tap W/A/S/D (or Alt + direction) |
| Sprint (controller: tap to toggle); stamina is hotbar box 11 | X | Shift (hold) |
| Character and backpack | Back | I or B |
| Spellbook | | P |
| Danger mode (lets you attack friendly NPCs) | | K |
| Target an enemy | RB (nearest the middle of the screen) | Left-click it (click another to switch) |
| Clear target | RB | Tab |
| Cycle targets | LB | Shift+Tab |
| Lock on (toggle) | R3 | Middle mouse |
| Camera | Right stick | Hold right mouse, wheel zoom |

Settings → **How to play** lists the controls as currently bound.

**Weapons:** you carry a primary and a secondary weapon (hotbar boxes 1 and 2; the one in use has the gold frame) and swap between them. Each weapon type plays differently (data/weapon_types.json, Database → **Weapon Types**): daggers are fast and light, greatswords, hammers and axes slow and heavy, bows draw (tap = quick shot, hold = harder), crossbows and flintlock pistols/rifles fire on the press and then reload (a "Reloading" bar). Melee: rapid taps chain the type's combo, hold for a heavy blow; swings turn to any enemy within 2.5 m. Hold block with a ranged weapon to aim over the shoulder. Ranged weapons auto-aim by default (shots home in on the target, no crosshair); untick **Auto-aim** on an item to aim it by hand with a crosshair (red = an enemy in range; hand-aimed arrows and bolts drop over distance, and locked on they arc onto the target). Arrows and bolts stick in the ground and in enemies; bullets fly fast and straight and leave holes in the ground and walls. Every class can use every weapon; the class's **proficient** types hit 15% harder and swing, shoot and reload 10% faster. A chest by the road near the start holds one of each weapon to try (once per character).

**Danger mode** (K): friendly NPCs that can fight become targets. One you hit gets angry and fights back (a follower stops following you); it calms down when it gives up the chase or you die. A red "DANGER MODE" shows under your bars while it's on. Other players in co-op are never targets.

**Looting:** what an enemy drops lies with its body (golden motes). Walk up and press Jump / A ("Space  Loot Bandit"): your character kneels (Mixamo Kneel, holding partway down while you look) and a small window opens over the body. Click an entry (or A / Space on it) to take it, **Take all** (R / Y), or close with Esc / B or by walking off; whatever you leave stays on the body. A body with loot left on it stays up to a minute (enemies.json `loot_time`) before sinking. Database → Animations: the kneel clip and where it pauses.

**Enemies** stay down for 12 seconds when they die (you can walk through them), sink away, and come back after 90 seconds (enemies.json `corpse_time`, `respawn_time`).

**NPCs** turn their heads to look at you when you're close (or at whoever they're fighting). While talking they nod along and gesture now and then (placeholder `talk_1`–`talk_3` clips; a Mixamo FBX with the same name replaces each), and your character looks at them.

**Levels and dying:** kills give experience (the purple bar above the hotbar; tougher enemies give more, much weaker ones little or nothing). Levels go up to 10, each adding health, mana, attack and spell power. Dying sends you home (where your hearthstone goes) and costs 10% of the gold you carry, and you're **Weakened** for 2 minutes (20% less damage and maximum health; shown under your bars). Numbers are in the Database's Player tab (Levels, Dying) and each enemy's "Experience for a kill". Falling out of the world still just puts you back on the last solid ground.

**Game log and chat:** bottom left. Experience, levels, loot, gold, deaths and who joined show there and fade after a while. Press Enter to chat (to everyone in co-op), Enter again to send, Esc to cancel.

**Spells and the hotbar:** spells are cast from the hotbar (boxes 3–10, keys 3–0): the cast bar fills, then it goes off. Moving cancels a cast, light hits knock the bar back, heavy hits interrupt it. Potions and other usable items go on the hotbar too (drag them from the backpack); drag spells from the spellbook (P). Drag boxes to rearrange them, or off the bar to clear them. On a controller, hold D-pad up for the ability wheel: point the right stick at a box and let go (you can keep walking). Locked on, the camera keeps the target in view and moving sideways circles it. Stamina is only used by sprinting; it's box 11 at the end of the hotbar (labelled with the sprint key), which empties while you sprint and fills back up. The experience bar above shows your level on the left and the next on the right. Health bars for you and your allies go from green through yellow and orange to red. The test level and the overworld each have a training dummy and two bandits.

**Moving while fighting:** drawing a bow, aiming, firing ranged weapons and holding a heavy blow play on the upper body only, so the legs keep walking (or sidestepping when locked on) underneath. A held heavy blow waits on the first frame of its swing (**Wind-up hold** on the ability). Sidestepping right is the left sidestep mirrored (Clips → "Another clip, mirrored left to right"). Double-tap a movement key to roll that way (Player tab → **Double-tap to roll within**; locked on you roll too, unless **Locked on: hop instead of roll** is 1). Targeting only picks enemies on screen and in front of you, within the weapon's **Targeting range** (Weapon Types tab; e.g. 12 m for swords, 35 m for bows).

**Traversal:** jump at a ledge to grab it (A/D shimmy, W or Space pull up, S or Ctrl drop) · jump at a climbable wall, or walk into a ladder, then W/S to climb (Space jumps off, Ctrl lets go) · swim in deep water, Space at an edge climbs out. The gray-box level (`scenes/levels/test_level.tscn`) has a test spot for each. · hold the middle mouse button to look · mouse wheel zoom.

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
- **Body file:** the masc body and its variants live in one .blend under one armature: `bare_body` (skin + a `leather` underwear surface), `head_human`, plus variants (`head_elf`, `face_default`, `hair_*`, `chainmail`, `leatherarmor`, `hat_tin`). Export the whole scene to `assets/models/characters/src/lowpoly_guy.glb` (Apply Modifiers on, Animation off), then run `tools/godot/build_bodies.gd`, `retarget_mixamo.gd`, `make_appearance.gd`. New variant meshes get a line in `PIECES` at the top of build_bodies.gd, then an item or appearance entry pointing at `assets/characters/lowpoly/<piece>_masc.scn`.
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

## Grass

Grass is tall clumps (crossed picture cards in the style of Saturn's tall grass) grown where the terrain is painted grass. Each clump takes its colour from the ground texture under it and is lit and shadowed like the ground. The picture is `assets/textures/grass_clump.png` (grey, light at the tips; `tools/art/make_grass.py` makes it, or paint your own). Per region (Database → Regions → Grass): clumps per m², height, how much it takes the ground's colour, and the root/tip colours.

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
- **Animations:** real Mixamo clips so far: sword-and-shield idle, slash and block; greatsword idle, slash and draw; sword, rifle and pistol draws; rifle and pistol idles; rifle aim; pistol shooting; gun reload; bow draw-and-shoot; spell casting loop, bolt release, heal, area cast and two one-handed casts (`cast_area`, `cast_1h_a`, `cast_1h_b`, ready for new spells); ledge shimmy (right = the left one reversed, `REVERSED` in the tool); flinch; dying; strafing. Also greatsword chop and leaping slam (greatswords and hammers: cleave → chop, hold for the slam), rifle firing (`gunplay`), left strafe and four talking clips (`talk_1`–`talk_4`; NPCs pick any `talk_N` there is). Every combat clip is now a real Mixamo one; the tool's posed stand-ins (`PLACEHOLDERS`) only fill in if a file goes missing. Put a Mixamo FBX with the same name in `assets/animations/mixamo/` and rebuild to replace one. Long downloads can feed several clips: `SUBCLIPS` at the top of `tools/godot/retarget_mixamo.gd` cuts named pieces out of a clip (e.g. `bow_aim` and `bow_release` from `bow_shot_full`). If a clip's timing changes, adjust the ability's **Hit Time** to match. Each weapon type picks its idle, draw, aim and reload clips (Database → Weapon Types → Animations); drawing plays when you draw or swap while standing still, and reloading when you reload standing still.

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

## Hearthstone and homes

- **Hearthstone:** every character carries one (older saves get one too) and it can't be thrown away. Use it from the backpack or the hotbar: an 8-second cast (moving, dodging or being hit stops it), then you're back home. It then needs 10 minutes to recharge, and the recharge is saved. Cast time and recharge are on the item in the Database's Items tab ("use_hearth" items).
- **Home:** starts as the spot the level first put the character. Walk up to a **home point** (an inn bed) and press **Jump / talk** → **Make this my home**. The hearthstone's description names your current home.
- **Placing home points:** drag `scenes/world/home_point.tscn` into a level and set **Home Name** (e.g. "the Riverside Inn") and the greeting. It builds a simple bed; turn **Build Bed** off and add your own model under it instead. Add a `Marker3D` named `Spawn` under it to choose exactly where players appear. The overworld has one by the spawn ("the village inn").

## Water

- **Reflections:** water mirrors whatever is on screen (trees, cliffs, characters) on top of the sky reflection; stronger at low angles. Settings → Graphics → **Water reflections** turns it off on slower PCs. Strength is `reflection_strength` on the water material.
- **Underwater:** when the camera dips below the surface it goes blue-green and wobbly, darker the deeper it is, with bubbles; sound effects, footsteps and ambience are muffled.
- **Sprint-swimming:** sprint while swimming to go faster (3.8 m/s instead of 2.2); it uses stamina. Speeds and cost are in the Database's Player tab.

## Co-op

- **Hosting:** Load Game → pick a character → **Host co-op**. The top of the screen shows the address friends join (your local network address) and how many have joined.
- **Joining:** Load Game → pick your character → **Join co-op…** → type the host's address → **Connect**. You appear next to the host in their world.
- **Over the internet:** the host's router has to let UDP port 24565 through (port forwarding), and friends use the host's public IP. An easier way for now is a free virtual-LAN app (Tailscale, ZeroTier or Radmin VPN) and the address it gives the host. Steam or Epic invites can come later without changing the game code.
- **Testing alone:** in the Godot editor, Debug → Customize Run Instances → run 2 instances. Host in one; join `127.0.0.1` in the other (needs a second saved character).
- **How it works:** the host's game runs the enemies. Everyone moves their own character, and its position, animation, health and gear are sent to the others. Your hits on enemies go to the host, which applies them; enemy hits on you are worked out on your own game (so your block, dodge and armour count). Loot is personal: each player gets their own drops. Hit-stop and slow motion are off in co-op. Each player's character saves to their own save as usual. If the host leaves, everyone else goes back to the title screen.
- **Not yet:** NPCs and followers aren't shared (each game runs its own), other players' arrows and spell bolts aren't shown (their animations and damage are), there's no chat, and enemies aren't yet scaled per player.

## NPCs

- **Placing one:** drag `scenes/npcs/npc.tscn` into a level and set **Npc Id** to an entry in the Database's **NPCs** tab. The overworld and the test level have a village guard, Katrina and a villager near the spawn.
- **The NPCs tab:** name and title, level and health, "can't die", behaviour (stand, wander or patrol), whether it fights, its attack, its look (the creator's options), what it wears and wields, and its lines.
- **Patrols:** add a `Node3D` named `Patrol` under the NPC with `Marker3D` children; it walks them in order.
- **Fighting:** NPCs that fight and hold a weapon (primary) take on enemies that come within their notice range, and enemies fight back. The rest shout "Help!" and run, then come home when it's safe. They ignore training dummies.
- **Followers:** NPCs with **Can follow the player** (Katrina) offer **Follow me** / **Wait here** after their lines. A follower stays beside you, runs to catch up, fights whatever is fighting you (or what you attack), waits at the edge while you swim or climb, and turns up behind you if you get far ahead or it gets stuck. Its health shows under yours. Out of a fight, NPCs heal back up. Followers are saved with your character.
- **Talking:** walk up to an NPC and press **Interact** (E, A). Each paragraph of its lines is one page; the same button shows the whole line, then the next. Esc or B closes. Lines can use `{player}` and the player's pronouns: `{they}`, `{them}`, `{their}`, `{theirs}`, `{themself}`.

## Events

Events work like Saturn's (and RPG Maker's): a box placed in a level, with pages of commands.

- **Placing one:** drag `scenes/world/map_event.tscn` into a level, size its **Size** box (it sits on the ground by itself) and pick its **Event Id** (the inspector suggests the ids from `data/events.json`). In the editor it shows as a see-through box in its trigger's colour (blue action, orange touch, purple autorun, red = no such event) with the event's name. Several placements can share one event; give them a **Self Key** if each should remember its own self switches.
- **Database → Events:** each event has pages. The page in use is the **last one whose conditions all hold**: switches, self switches (A–D), variables, carrying an item, gold, level, class. A page sets:
  - **Trigger:** Action (press Jump / talk next to it), Touch (step into the box), Leave (step out), Autorun (as soon as the page turns on; turn a self switch on at the end so it runs once), None (only by **Call event**).
  - **Shows:** nothing (an invisible area), a built-in stand-in (`builtin:chest`, `chest_open`, `sign`, `standing_stone`, `crate`, `barrel`, `orb`, `lever`, `lever_on`), a prop (`prop:rock2`), an NPC (`npc:villager`: talking to the NPC runs the page) or any `res://` scene.
  - **Blocks the way**, **Sparkles** (so it can be spotted), **Prompt** ("E  Examine"), **Speaker**, and whether the player waits while it runs.
  - **Commands**, in an RPG Maker-style list: Show text, Show choices (each choice gets a branch; pick what Esc does), Game log line, Conditional branch (with Else), Wait, Call event, Exit event, Erase event, Comment, Control switch / self switch / variable (set, add, subtract, multiply, random), Give / take item, Change gold, Give experience, Full recovery, Follower joins / leaves, Player animation, Teleport (to a Marker3D or x, y, z, in this level or another, with a fade), Set home, Fade out / in, Play sound, Sparkle effect. Select a line and use **+ Insert command** (it goes above the line; select a ◆ line to add at the end of a list or branch), ↑ ↓, Copy / Paste and Delete.
  - Text can use `{player}`, the pronoun tokens, `{var:id}`, `{item:id}` and `{gold}`. Texts in a row share one box; a choice right after a text shows under it. Giving an item that doesn't fit says so and stops the event (so a chest stays closed).
- **Database → Switches:** names for switches and variables. Their values (and self switches) are saved with the character.
- **NPCs** can run an event when talked to instead of their lines (NPCs tab → **Talking runs event**).
- The overworld has examples by the start: a standing stone (a choice and rewards, then a second page), a chest that opens once, a lever (a switch and a variable), a signpost that teleports you to `Events/LookoutPoint`, a walk-in welcome message, and a villager with a small quest (bring 3 bandit insignias).

## Equipment and backpack

- **Character window** (I, B or Back on a controller), bottom right so the hotbar and cast bar stay in view, always the same size: equipment and stats on the left, the 24-slot backpack on the right with tabs along its top (Weapons, Armour, Potions, Items, Keys). Point at an item to see it, compared with what it would replace: weapons show damage per second, armour the stat changes, green when better, red when worse, yellow when the same. Right-click or double-click equips or uses it; drag between slots to move or equip (or onto the hotbar); drag out of the window to throw it away (it asks first). On a controller: A equips/uses, Y picks up and places, X puts it on the hotbar, LB/RB switch tabs.
- **Gear shows on the body**, on both masc and femme. Armour adds armour (less damage taken), health and mana; weapons add attack or spell power (only the weapon in use counts); a shield adds block (not with a two-handed or ranged weapon).
- **Loot:** bandits drop a sack with gold and items. Walk over it to pick it up; anything that doesn't fit stays in the sack for a few minutes.
- **Items** are in the Database's **Items** tab: name, kind, slot, rarity, stats, what using it does, and its look. Potions and bandages take **Takes (s)** to use: a cast bar fills while the character drinks (the **Drinking** animation, Animations tab, or the item's own: it holds its first pose while the bar fills, then plays out to end with the bar; the hold frame and speed are on the Animations tab), and the effect comes at the end; moving, dodging or a hit stops it and the item is kept. 0 = at once. The Player tab has the **Starting kit**. Each character keeps its own backpack and gear in its save.
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
3. Database → **Clips**: settings per clip (loops, in place, travel handled by the game, face-forward turn, hip-height match), and clips made from others (a piece of a longer clip, or one played backwards). A new FBX with no entry comes in as a one-shot.
4. Database → **Animations** → **Rebuild animations** (or ask Claude, or run `godot --headless --path . --script res://tools/godot/retarget_mixamo.gd`). This writes `assets/animations/masc.res` and `femme.res`.
5. Database → **Animations**: which clip plays for each thing (idle, run, sidestep, hanging, climbing, swimming, block, flinch, dying, casting, talking gestures), plus head-turning and sidestep-speed settings. Weapon types pick their own idle / draw / aim / reload clips (Weapon Types → Animations), abilities their attack clips, enemies and NPCs their attack clips. Changing which clip plays needs no rebuild.

## Milestones

1. Movement and camera
2. Combat
3. Equipment, character creator, saves
4. Co-op ← **foundation in, being tested**
5. Content tools
6. World
