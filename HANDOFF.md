# Handoff (13 Nov 2026)

Where things stand, for picking the work up in a new chat. Technical notes for each system are in `CLAUDE.md`; this file is the to-do list and the agreements made in conversation.

## How we work
- The owner tests in the Godot editor on Windows and pulls with GitHub Desktop. Claude validates headless, then commits and pushes to `main`.
- Every new tunable goes in the data files and on the Database page.
- Close Godot (or its script tabs) before pulling: pressing Play saves open scripts and can write old copies over new ones.
- A red dot left of a line number in Godot's script editor is a breakpoint: it pauses the game there. Debug → Remove All Breakpoints clears them.
- Avoid "Revert this commit" in GitHub Desktop's History unless an update really should be undone.

## Next up, in order
1. **Your own art over Claude's** (art_sheets/, see its README): eyes, brows, noses, mouths, face extras, effects, item icons, ability/status/Codex icons. Draw over a sheet, save, run `python3 tools/art/sheets.py split`. (The Singed Plains region is done.)
2. **Menus**: menu sounds and the Codex top tabs with icons are in (12 Nov). Keep checking every menu in the editor (title screen, creator, Codex pages, loot, dialogue, death choice, map) and list anything cramped or broken. Done 12 Nov: backpack 60 slots (12 × 5) + bigger doll; creator split into body/hair (left) and Face tabs Features / Eyes / Extras (right); Body Type 2 (reshaped body; tune in Database → Body Models). To check: class page attributes need scrolling to reach Vitality/Spirit; Body Type 2 with every outfit piece (gear cut from the body should follow; rigid pieces like the shield and hats don't move).

## To test in the editor (done 13 Nov night: Body Types 1 / 2 on the new rig)
- **Body Types 3 and 4 are shelved** (owner: they need more work). They're hidden from the creator and every character uses Body Type 1 / 2 again; their data and builds are kept. To bring them back: appearance.json `"bodies": ["masc", "masc_hq", "femme_hq"]`.
- **New rig for the low-poly body** (T-Pose12.fbx, saved as `src/lowpoly_rig.fbx`): one finger chain for the whole hand. The body and skeleton come from it; clothes, hair, heads and gloves still come from lowpoly_guy.glb and are attached to the new rig by bone name. Animations were rebuilt for it.
- To check: hands on thin / heavy builds and Body Type 2 (the odd index finger should be gone); the weapon sits right in the fist (the grip is now worked out from the thumb side); gloves; chainmail sleeves at the upper arm (a little skin showed through in one test render).
- When clothes are re-exported on the new rig, export them in one .glb with the body, set it as Source and clear "Re-rigged body" in Database → Body Models.

## To test in the editor (done 13 Nov evening: Body Types 3 and 4 from highpoly_bodies.glb)
- Both attachments were the same file (one .glb with all three bodies). It is now `assets/models/characters/src/highpoly_bodies.glb` and is the source of Body Types 3 and 4 (Database → Body Models → Body Type 3 / 4). Body Type 1 still builds from lowpoly_guy.glb.
- **Eyes, brows and mouth are drawn on your face surfaces** (eyes_male / brows_male / mouth_male and the female ones): whatever eyes, brows and mouth a character picks show there, with blinking, talking mouths, moods and the creator's placement sliders. Nose and extras (freckles, scars…) are laid over the same face area.
- **Hair**: every `.001` hair is used as that style's fit on Types 3 and 4 (same style list as Body Type 1). **Beards**: Short beard, Regal beard, Long beard, Mustache are new choices only on Types 3 / 4 (the old Body Type 1 beards are still listed there, borrowed). **Ears**: human ears are their own part; the Elf head swaps them for your elf ears. The hairline painted on the scalp takes the hair colour.
- **To fix in Blender (Type 4)**: brows_female, mouth_female and the four `_f` beards / mustache are still attached to the male armature (Armature modifier → Armature instead of Armature.001) and rest about 8 cm inside the female head. The build moves them forward onto the face, and the mouth up 1.6 cm onto the lips (Database → Body Type 4 → "Move mouth up"), but the `_f` beards sit a little low and proud. Re-fit them on the female and point their Armature modifier at Armature.001; then set "Move mouth up" back to 0.
- Clothes on Types 3 / 4 are still borrowed from Body Type 1 (no refitted clothes in this file yet).
- Not in the game yet from this file: head_catfolk, ears_catfolk, tail_catfolk, hair_short.001 / hair_balding.001 on Body Type 1, clothes_test_shared.

## To test in the editor (done 13 Nov: Body Types 3 and 4)
- **Body Types 3 and 4** (your two T-pose bodies) are in the creator's Body type row next to 1 and 2, and in Database looks (Body). Body Types 1 and 2 are unchanged. Each new body has its own animations (made from the same Mixamo clips) and its own underclothes and beards.
- Until you refit them, clothes, hair and hats are **borrowed** from Body Type 1, moved bone by bone (hair/hats scaled onto the new head: Database → Body Models → Body Type 3 / 4 → Borrowed hair size/raise/back). Body Type 4 wears them fairly well; Body Type 3 badly (twisted shirt, pointed boots).
- **Bringing in refitted clothes**: in Blender, put the refitted meshes on that body's armature (same Mixamo bone names) and export a .glb (body + clothes) into assets/models/characters/src. Database → Body Models → Body Type 3 (or 4): pick it as Source, Save, reload the page, tick the body mesh(es), add a piece per refitted mesh with the **same piece id as the Body Type 1 piece** (leather_tunic, dark_leggings, leather_boots, hair_short…), Save, Rebuild. Items then use the refitted version on that body by themselves.
- If an arm clips the thighs in animations: Database → Animations → Arm spread, Body Type 3 / 4, then Rebuild animations.

## To test in the editor (done 13 Nov: region sub-scenes)
- **The level is split by region**: overworld_test now holds the world machinery (sun, sky, streamer, player, ocean, atmosphere) plus **Regions → StartingRegion / SingedPlains**. Everything placed (enemies, NPCs, events, areas, campfires, chests, the inn bed) moved into `scenes/levels/regions/starting_region.tscn` and `singed_plains.tscn`, in the same spots. Open a region's scene (double-click it in FileSystem, or the clapperboard icon beside it in the level's tree) to work on just that region: the terrain shows there as a preview that isn't saved into it. Pressing Play still runs the whole level.
- **Placing new things**: put them in the region's scene. Anything you drop straight into the level instead can be sorted later: `godot --headless --path . --script res://tools/godot/split_regions.gd` (Claude can run it), which moves it into the right region by where it stands.
- **Events list grouped by region** (Database → Events: a bar with All / Monolith / Singed Plains / No region). Each event has a Region field; new events get the group you're looking at.
- Old saves: an enemy you'd already beaten for good (the Troll) stays beaten.
- Avoid "Editable Children" on a region in the level (changes would be kept in the level instead of the region's scene).

## To test in the editor (done 13 Nov, batch AD)
- **Shop**: the Trader stands east of the watchtower by the ladder (NPCs/TowerTrader). Talk → "Let me see your wares" → Buy / Sell (click = one, Shift-click = five). Stock and prices: Database → Shops (count 0 = never runs out; price 0 = the item's value × buy rate; limited stock comes back after the restock hours of play). His look and lines: Database → NPCs → Trader (tower_merchant) and Events → Watchtower trader. More shops: add one in Database → Shops and an event with the "Open shop" command.
- **Fade from the title screen**: the menu fades to black, "Loading…", then the level fades in (Database → Player → Menu sounds → menu fade times). Quit to title fades out too.
- **Time-of-day enemies**: Database → Enemies → Death → "Spawns at" (dawn, morning, day, dusk, night, twilight; none = always). Bats are set to dusk/night/dawn. When its hour ends an enemy fades away (after any fight it's in) and fades back in at home when it starts. One placed enemy can override it (Inspector → Story → Spawn times here).
- **Hair second colour**: creator → "Second hair colour" (tips, roots, streaks, front) + its colour; NPC looks have it too (Database look → Hair dye).
- **Eyes look around**: pupils follow whoever a character is looking at, and glance about when idle (appearance.json face_motion gaze_x / gaze_y set how far).
- **Troll/golem smash** anyone near it (companions too), not only the player.

## To test in the editor (done 12–13 Nov: sky, retro, elements, ladders, backpack, calendar, Emitter)
- **Retro look**: Settings → Retro (intensity, pixelate, colours, dither, scanlines, terrain wobble, fog, narrow FOV, pixel font, texture pixels). Fog distance per region: Database → Regions → Fog (retro fog start/end); the editor shows the real hard-edged fog, the test renders can't. Turning Retro off used to white-out the screen (fixed).
- **Sky**: the ringed planet is bigger and drawn as chunky pixels (Database → World → Sky: size, pixels, colour steps); shooting stars; the moon station shows the **real moon phase** (hover the clock for it).
- **Calendar**: the HUD shows the real date (12/24 h clock in Settings → Graphics); holidays in Database → World → Calendar & holidays show beside the date; events can check Holiday / Moon phase / Date between.
- **Elements**: water/frost hurt golems more ("Effective!"), shock less ("Resisted"); dragon/troll have their own (Database → Enemies → Elements).
- **Damage numbers** arc out to the sides (Remnant 2 style); words stack above the name bar.
- **Ladders**: the watchtower rope ladder is a real ladder now (climb all the way and step off at the top); letting go near the bottom no longer drops you through the ground; falling under the map puts you back on solid ground.
- **Hearthstone in water** (stand still while swimming). **Enemies alert** idle friends within 14 m. **Bandits switch to a bow** when you're out of reach (on a rock).
- **Flung bodies**: ragdolls are capped; loot from a body that ends up out of reach becomes a sack where it died.
- **Backpack + pins**: every player wears a rounded pack; each achievement earned puts a pin on it (scattered spots, 25 max). Codex → Character: Show backpack / Show helmet (hidden helmet keeps its stats); creator has a Backpack box. One-handed swords hang at the hip while the pack is on.
- **Achievements**: 25 (21 are placeholders to rewrite or delete), icons in assets/icons/achievements (32 px; sheet "achievements").
- **Golems**: no name/health bar until they burst out; name bars are bigger.
- **Emitter** (TitanTech revolver) in the weapon chest by the road (new characters; the chest opens once). Guns cost mana per shot (pistol 8, rifle 14, Emitter 5; Database → Items / Weapon Types). **Out of mana**: spells and shots take health instead (never below 1) and you're Weakened until regeneration pays it back; a mana potion clears it.
- Also 12 Nov: elements, weapon auto-stow after 15 s, sitting hands (lap / warming at the fire), hands keep their size on thin/heavy builds, quest banner + objective pop-ups, still portraits, heat-haze fix (name bars in the desert), golem bounce crash fix.

## To test in the editor (done 12 Nov: classes and mage spells)
- Each class starts with one skill from its tree's starting node (free, in hotbar box 1; hearthstone in 0): Fighter **Rage** (glows red 10 s, double damage), Rogue **Stealth** (now 10 s), Mage **Firebolt**. The Mage can now be chosen. Old saves: the old Firebolt/Mend boxes are cleared and the class skill goes in box 1. The other skill trees and nodes were removed (Frost Edge, Burst Quake, Cleave and Riposte are still in the game; add them back as nodes when you want them).
- New spells, all in the Mage's Spellbook for testing (Database → Classes → Mage → "Also knows"; drag them onto the hotbar): Chain Lightning (needs a target, jumps to 3 more), Frost Bolt (slows; 20 % chance to freeze 3 s; bosses/big beasts/golems can't be frozen), Tidal Wave (cone in front, knocks back/down), Burst Quake, Ward (no damage 4 s, bubble), Blink (click the ground within 20 m, then the cast bar; red marker = can't go there: too far, steep, water, no room, out of sight; Esc cancels), Heal (instant chunk), Dark Cloud (click a spot: 8 s, blinds everyone inside incl. companions (toggle "Blinds friends too"); you see red/grey/green outlines of whoever is inside).
- To check: the lightning, wave and cloud look in Forward+, the outlines through the cloud, frozen enemies' ice coat, Rage's glow, the sounds (assets/audio/spells, `tools/audio/make_spell_sounds.py`).
- The new ability/status icons are pictures in assets/icons/abilities and statuses but not on the art sheet yet: if you haven't started drawing on art_sheets/icons.png, run `python3 tools/art/sheets.py make` to add them (it rewrites every sheet from the game's pictures).

## To test in the editor (done 10 Nov, batch L: safe areas + indoor weather)
- Test level: the village is a safe area (green box `Areas/VillageSafeArea`). Lead the bats or bandits to it: they should give up at the edge and walk home; "You are safe here." / "You are no longer safe." show on the way in and out; blows either way do nothing while you stand inside (the training dummy still takes hits).
- Its off switch is `village_attacked`: an event with Switch → village_attacked ON makes the village unsafe until it's turned off again.
- `Areas/InnIndoors` (blue box at the inn bed) is indoors: in rain, the streaks stop and the rain sound dulls when the camera is inside; the splashes stop when the character is.
- Roofs: once a building or cave exists (anything with collision), rain stops under it without any box, and from inside you still see it falling outside doors and windows. Splashes land on roofs and ground, not on covered floors. Wet ground only shows under open sky (soft edge about 0.75 m at doorways). Rain is hidden by what is above it, not by walls, so any door or window opening shows it.
- Per material: terrain materials have **Wet Look** (0–1) in the inspector; a copy of terrain.tres with Wet Look 0 never looks wet (name it after the Blender material so chunks pick it up).
- New nodes: instance `scenes/world/safe_area.tscn`, set Size, tick Safe and/or Indoors, pick an Off Switch if wanted.
- Tunables: Database → Player → Safe areas; Database → Weather Settings → Indoors (sound, roof check, cover map).

## To test in the editor (done 10 Nov, batch M: performance)
- **F3** shows frame times (average and worst of the last second), draw calls, triangles, enemies/NPCs awake vs asleep, chunks and props still loading. Note the numbers standing still, walking across chunk borders and in rain, and say where it's worst.
- Hiccups while walking: chunks now go in one per frame and their props a few per frame, with prop models loaded in the background. Trees and rocks of a new chunk pop in over a moment at the far edge.
- Far-off enemies and NPCs (90 m+, idle) stand frozen until you come within about 78 m. The dragon never sleeps.
- Props fade out by size (small things sooner); every prop in the test level is big, so nothing changes there yet. Hills hide what's behind them (watch for anything vanishing that shouldn't: Database → World → Performance → "Hills hide what's behind them" turns it off).
- Settings → Graphics: View distance, Shadows, Render scale, Frame limit, VSync.
- Not done: shader warm-up (the very first spark / blood / rain of a session can still hitch while the graphics card compiles it), batching props into shared draws, cheaper far-away characters.

## To test in the editor (done 10 Nov, batch N: snow + effect sprites)
- Snow: two new weather types, **Snow** and **Blizzard** (an event's Weather command, or add them to a region's weather list in Database → Regions). Flakes drift and none fall under roofs; snow lies in patches on open ground and frosts the grass, not under roofs or trees; a quiet wind loop plays. Check the look of the flakes and the white patches in Forward+.
- Effect sprites: Database → Abilities → **Effect sprites**. Four places per ability (on the caster, with the projectile, where it lands, on the ground), each a built-in picture, one of yours, or **Load PNG…**. Examples are set on Firebolt (flame + burst), Mend (rune circle on the ground), Frost Edge (snowflake) and Burst Quake (ring on the ground).
- Your own pictures: drop PNGs in `assets/effects/custom/` or use Load PNG…; frames side by side in one row for animation. See the README in that folder.
- Insects are sprites now (Database → Wildlife → a swarm → Picture of one insect, with frames for the wing beat). Flies no longer appear over enemies you kill: place a **Swarm Spot** (`scenes/world/swarm_spot.tscn`) where a body is left lying for the story, a rubbish heap and so on (one is by the road in the test level). Mosquitos hang about water at any time of day.

## To test in the editor (done 10 Nov, batch O: pixel look, wildlife, the troll)
- Pixel look: effect sprites, heal motes, blood, leaves, rain rings, bullet holes and the hotbar / backpack / spellbook / status icons are all chunky pixels now. Icon grid size: Database → Player → HUD → "Icon pixel grid" (24; 32 finer; 0 = smooth). Decals use nearest pixels too, which also makes cloud shadows a little blocky: say if that bothers you.
- Mosquitos by water at dusk, night and dawn (new "Dusk, night and dawn" time choice). Fireflies have a little lit-tail sprite.
- Ants: trails up tree trunks, over rocks and along the ground near you in daytime (Database → Wildlife → Ants). They're small: look down near trees and rocks.
- **Troll boss** (Old Mossback) stands where the dragon was. From afar it stoops, picks up a rock and hurls it; a red ring marks where it will land. Close in, it raises both fists (red ring on the ground fills in): hit it, then roll clear before the slam, or get knocked off your feet. All timings and damage under Database → Enemies → troll → Beast.
- You can be knocked down now (troll smash, dragon tail): you flop, then get up; no attacking or dodging while down.
- The dragon is saved as `scenes/enemies/dragon.tscn` (and the troll as `troll.tscn`): drop it in any level.

## To test in the editor (done 10 Nov, batch P: story events + the Monolith tutorial)
- Database page: forms scroll to the bottom again (the window's grid row now fits the window).
- New event commands (Database → Events → Insert command): **Say** (Message: a line over an NPC / the event / the player while you keep playing, optional voice clip, also in the log), **Wait until…** (Flow: waits on conditions while play goes on), **Nav point** (Progress: HUD waypoint with metres; marker / event / NPC / enemies by node name / player; goes away when reached or when its enemies are dead), and a **Cutscene** group: Screen shake (with earth rumble + controller rumble), Throw the player (ground bursts), Cutscene camera (glide to a Marker3D, look at someone, back), Letterbox, Play video (.ogv only: Godot plays Theora; convert with e.g. `ffmpeg -i in.mp4 -c:v libtheora -q:v 7 -c:a libvorbis out.ogv`, put it anywhere under assets/).
- Enemy inspector → Story (events): Appear Switch, Emerge, Defeat Switch, Defeat Variable, Stays Dead. Training dummies: Hit Variable. New **ClimbLock** box (scenes/world/climb_lock.tscn): nothing inside can be climbed until its switch is on.
- The Monolith tutorial is wired up in the test level (Events/Tutorial): wake at the player start → nav to Katrina (now standing by the dummies) → she gives an iron longsword, joins, sends you to hit the dummies 5 times → she talks you onto the three bandits → nav to the quarry → walk-in rumble, cutscene camera, the troll bursts out of the ground (Old Mossback) → the vines throw you back until he's dead → victory line, vines unlock, nav to climb out. **Move the pieces onto the real map**: Katrina + dummies across the pond, TutRumble, Troll, TrollArena/TrollCam markers, QuarryVines + VinesLock onto your vines. The vines themselves still need to be climbable (named `_climb` or in group `climbable`).
- Not done: NPCs walking to markers in cutscenes (camera only for now), a voice-blip option per NPC.

## To test in the editor (done 10 Nov, batch Q: nav marker, item icons, hotbar, Codex, terrain)
- **Nav marker** now stays on screen Halo-style: a small pixel arrow over the target with the metres under it (name only when you look toward it); off-screen or behind you it slides along the screen edge and points the way. (It was stuck in the top-left because the HUD control had no size.)
- **Database → Items** list is split into Consumables / Weapons / Armour / Key items / Misc (bar above the list filters one group; New makes an item of the group shown). Every item picker (events, loot, quests, rewards) is grouped the same way. Kind "Food" added (counts as a consumable).
- **Item icons** are the Saturn engine's 16 px icons (259, in folding groups in the Icon field) with an optional Icon tint; Load PNG… adds your own (assets/icons/custom). The old drawn glyphs still work (flintlocks keep the gun one). Re-export after Saturn gets new icons: `node tools/art/export_saturn_icons.mjs <path to hd2dengine>`.
- **Hotbar**: potion and bandage are no longer on it by default (an old save loses them from boxes 3–4 once); the Hearthstone moved to box 0. New abilities (skill tree, racial) drop into the first free box once each.
- **Spells** are a Codex page now (P opens the Codex there; N opens Skills in the Codex). The separate spellbook window is gone.
- **Hearthstone works while falling** (stuck in the air on geometry): stand still and it channels as usual.
- **Terrain shine**: dry ground was already matte; the shine came from the Fog weather setting the ground 30 % wet. Fog is dry now, light damp only darkens, and soaked ground is less glossy (terrain.gdshader `wet_roughness` 0.65 / `wet_specular` 0.25).
- Exporter: Export Chunks now refuses a prop/water object or anything smaller than half a chunk (that's what wrote the vines over chunk_0_0; I restored the old terrain). Re-export with the terrain active. I also deleted `chunk_-2_1.glb`, a stray pine-leaves piece from an older mis-export.

## To test in the editor (done 11 Nov, batch R: faces)
- **Eyes** are twice the size and wrap around the face. **Same colour for both eyes** can be switched off in the creator (Right eye colour appears) — heterochromia. Species have a new **Heterochromia** box (Database → Species): ticked, the creator locks the eyes to two colours and NPCs of that species get two too. (There's no half-elf species yet: add one and tick it.)
- New face parts (pixel art, `tools/art/make_face_parts.py`, assets/characters/face): **Brows** (hair-coloured), **Nose**, **Mouth** steppers and **Extras** toggles (freckles, rosy cheeks, wrinkles, tired eyes, three scars, beauty mark, chin dimple, five o'clock shadow). They're drawn as multipliers of the skin, so they work on every skin tone. They show on the **Detailed** face (now the default; the old blob face is "Painted" — existing saves keep Painted until you switch).
- **NPCs and enemies** (Database → NPCs / Enemies → Look) have all the same choices. Enemies also got **Gear** (worn pieces + the weapon in hand; looks only, no armour stats). The Bandit now has a look (stubble, cheek scar, angry brows) and leather jerkin / trousers / boots / rusty sword. Katrina has almond eyes, arched brows.
- Fixed: the Database page never loaded appearance.json, so look dropdowns showed "(missing)" for eyes, heights, builds...
- Empty look choices now mean "the default" (before, an NPC with Eyes (none) had no eyes).

## To test in the editor (done 11 Nov, batch S: anime faces + Database preview)
- **Anime face parts** (original pixel drawings, `tools/art/make_anime_face.py`): eyes Anime bright / soft / sharp / upturned / droopy / sleepy / sparkle (star highlights) / small iris, **Cat: slit** and **Cat: round slit** (vertical pupils), and expression eyes Closed happy (^ ^), Closed calm, Dots, Dizzy spirals. Noses: dot, hook, shadow. Mouths: small smile, cat :3, open grin, fang, oh, tongue out, wavy (nervous), shout. Brows: soft, raised, angry, sad, dots. Extras: anime blush lines, sweat drop, tears, anger mark, whisker marks. Mouths and the coloured extras are drawn in real colours (appearance.json `"tint": "none"`).
- **Database preview**: NPCs and Enemies → Look starts with a picture of the whole body (with gear) and a face close-up, rendered by Godot; it redraws a moment after any change (Refresh preview forces it). It's the A-pose, since animations only play in the game.
- Short hair no longer sways (Body Models → hair_short → sway 0).
- Idea for later: expressions in dialogue (swap eyes/brows/mouth per line, e.g. an event command "expression").

## To test in the editor (done 11 Nov, batch T: face placement)
- Creator: **Customize placement…** under Eyes, Brows, Nose and Mouth opens three sliders: Spacing (eyes, brows) or Left / right (nose, mouth), Up / down and Size (0.5–1.6×), plus Reset. Randomize resets them.
- Database → NPCs / Enemies → Look → **Placement**: the same sliders for all four parts (the preview follows).
- Saved as look `placement` {eyes|brows|nose|mouth: {x, y, scale}}. Extras stay where they're drawn.
- Next (owner): import new beards / facial hair.

## To test in the editor (done 11 Nov evening, batch U: chainmail + facing fix)
- **Chainmail**: a Body Models piece can now take several materials (click them in the piece's material list; none = all). The chainmail shirt is two rows with the same id: chainmail + chainmail_sway, and leather above 0.6 m within 0.35 m of the middle (belt + neck trim; that leaves out the leather gloves/boots in the same mesh). New "within side" number per piece (max_side). Rebuilt chainmail_shirt_masc.scn.
- Sway: a material named *sway* always swings even if an anchor word matches it (chainmail_sway vs anchor "chainmail"). Chainmail anchors chainmail + leather, sway 0.4 (was 1.0).
- **Katrina walking sideways**: she's turned 90° in the level, and facing only set the model's own yaw. NPCs and enemies now move a level rotation onto their model when they start, so turning them in the editor is fine.

## To test in the editor (done 11 Nov evening, batch V)
- **Base Character** (Database → NPCs → Base Character, id `base_character`, not placed in any level): new characters start from its look (eyes, brows, nose, mouth, placement…), Randomize and Reset placement go back to it, and any NPC/enemy look choice left on (none) uses it too. Seeded from Katrina + the Village Guard (upturned anime eyes at 0.75, shadow nose, brows a little wider and bigger, mouth a touch higher): tweak it to taste.
- **Switch-gated props**: in Blender give a prop the custom property `show_switch` (e.g. `troll_defeated`) and it's only there (visible + solid) once that switch is on; `hide_switch` makes it vanish once the switch is on. The exporter writes them to props.json. The quarry ladder is already set to `troll_defeated` in chunk_1_2.props.json, but add the custom property in Blender too or the next export drops it. A `SwitchGate` node does the same for anything placed in a level scene (add it as a child, set the switches in the Inspector).
- **Skill trees, Saturn-style**: Codex → Skills is a constellation per tree (tabs in the tree colours, row 0 at the bottom, lines to what each skill needs, rank pips) with the chosen skill's details on the right; click a skill, click again (or Learn) and once more to confirm; arrows / Enter / [ ]. A skill now needs one rank (not full rank) in each skill it's linked from. Database → Skill Trees: the same constellation, click to edit, drag to move (half steps), + Skill; tree Rows/Columns fields are gone.
- **Backpack in the Codex**: the inventory key (and anything that opened the backpack) opens Codex → Backpack; press it again to close.
- Hotbar boxes fire on release, and not at all when the press turned into a drag.
- **Esc cancels** casts, channels (drinking, the Hearthstone), charges / bow draws and aiming, before it clears targets or opens the Codex.
- Next: the new region (needs your Blender export).

## To test in the editor (done 11 Nov night, batch W: east region ground)
- Blender: select the new terrain → Paint ground → Ground Set `desert` → (optional preview pictures) → Setup / Update Terrain Painting; paint buttons become Sand / Desert Stone / Cliff; export → chunks use material `terrain_desert`.
- In game: sand + desert stone + the old cliff texture, no grass, footsteps dirt/stone. Database → Ground Sets edits show live. Region map colours.
- Still to do for the east region: regions.json entry (chunk rect [3,0,4,4]?) once exported.

## To test in the editor (done 11 Nov night, batch X: grass patches, lava, golems)
- Blender: reinstall the add-on; "Grass 2 (black paint)" paints layer 4 (grass in the desert set; Database → Ground Sets → Layer 4). Existing paint is unchanged.
- Lava: a plane in the water collection named "...lava..." (or with a material named lava) exports as lava: glow, embers, very slow swimming, burning. Tunables Database → Player → movement lava_*.
- Golems: Enemies/Golem (16, 2, 160) and Enemies/GildedGolem (2, 2, 172) in overworld_test: walk within 7 m. Move them / use scenes/enemies/golem.tscn and gold_golem.tscn in the east region.
- The ladder's show_switch was lost when chunk_1_2 props were re-exported: set the custom property `show_switch` = `troll_defeated` on the ladder object in Blender so it survives exports.

## To test in the editor (done 11 Nov late, batch Y)
- Talk to Katrina: camera glides over your shoulder; her mouth moves while text types; she blinks. Events: Show text → "Speaker's face" (mood); Show choices → Loop + "these answers move on".
- Fall from a height that hurts: limping (Sprained) for 5 s.
- Singed Plains: desert wind/night loops, hawk/sand/lava sounds, heat haze in the distance (Database → Regions → Heat haze), its own music. Battle music when enemies fight you, boss music for the Troll; Monolith music near the start (Areas/MonolithMusic: move it onto the real Monolith).
- Music is synthesised (tools/audio/make_music.py) — ask for changes per track (tempo, instruments, mood).
- Herbs: import assets/props/herb_*.glb into Blender, paint them with the new Paint Props brush; press E to pick; they regrow (berries 1 game day, lavender 3).
- Blender: Paint Props box (select props, press Paint Props, drag; Shift+drag erases).

## Notes (11 Nov late)
- The Troll boss (Old Mossback) is back to the shape-built troll: the vine golem model was removed (12 Nov: it was AI-generated from copyrighted material, not usable commercially). Golems are human-sized stone-carapace undead of the Singed Plains: they now use Phons' animated "Drugdör" model (assets/models/creatures/desert_golem.glb, CC-BY, credited).

## To test in the editor (done 12 Nov, batch Z)
- Backpack: click an item, then move to Use / To hotbar / Throw away (hover only previews). Throw away drops a spinning icon in front of you; walk over it after 1.5 s to take it back; it vanishes after 5 min or 150 m (Database → Player → Thrown-away items).
- Potions used from the Codex close it first. The hearthstone keeps the time of day (the clock is saved with the character).
- Tab with nothing on screen targets the nearest enemy anywhere in reach. Ladder going down: no growl. Maple/birch trunks: collision fits the trunk.
- Z draws / puts away the weapon (no auto put-away: Database → Player → Combat "Weapon put away after" 0). Followers copy it. Followers climb ladders after you.
- HUD: gold level badge at the end of the bars; portraits (Settings → Graphics → Portraits).
- Talking: dark edges + blur behind the speaker (blur needs Forward+); enemies and missiles freeze until it ends (Database → Player → dialogue).
- Golems (Singed Plains): lie as scattered stones, roll together and stand up when you come within 7 m, smash / throw shards, raise a guard that deflects your blows (sparks, clang, the swing bounces; a charged heavy blow breaks it), fall apart when they die. Database → Enemies → Beast "Animated" fields + "Golem guard".
- Rivers: in Blender, a plane in the Water collection named river/stream/falls (or with such a material) exports as running water. It flows toward the plane's UV up (+V): a plain plane flows along its own +Y; for a winding strip, UV → Follow Active Quads. Steep faces become waterfalls (white water, roar, mist). Swimmers are carried along. Reinstall the add-on.
- Monolith (Events/Monolith in front of it): Interact → hand raised, light-blue flash, blue sparks around you and followers, full health/mana, ailments cured. New event commands: Full recovery (party, cure), Sparkles, Fade out colour.
- Campfires (Campfires/VillageCampfire near the start, PlainsCampfire in the Singed Plains; scenes/world/campfire.tscn): Interact = it becomes where you wake, and rest 2/4/6/8 h (6+ rested and cured, 8+ Well rested buff, less = Tired). Dying: "Wait for help" (a follower comes and revives you) or "Return to camp". Companions now finish enemies except the one you've targeted. Database → Player → Campfires and falling; statuses well_rested / tired.
- Seats: scenes/world/seat_chair / seat_stool / seat_log / seat_bench (three placed round the village campfire). Interact to sit; move to stand. Followers sit near a lit fire or in a safe area after you stand still 4 s and do their Database "Resting in camp" activity (Katrina eats, Orrin reads, Maelis drinks, Wren warms her hands).

## Waiting on the owner's decision
- **Rename the Hearthstone** (Blizzard's trademark). Owner picks the new name; then Claude renames the item, its Database fields, messages and the `use_hearth` wording, keeping old saves working (item id mapped).

## Backlog (agreed, not started)
- **From the owner's notes (13 Nov):**
  - Enemies that drop on the player from the trees.
  - Enemies standing on tree branches attacking from range (archers, spellcasters).
  - Shield enemies that crouch behind their shield and block from the front (beat them with burst/area damage, or hit them as they swing).
  - Spellcasters with a magic aura shield: knocks attacks back with an electric effect until a spell breaks it; an area burst spell pops it for a few seconds.
- **Sheaths/scabbards**: big weapons (greatswords, axes) on the back, blades in a scabbard at the hip (the bare sword at the hip looks odd). Just an idea so far.
- The index finger still looks claw-like on some builds (hands).
- Enemies and companions still just stop casting when out of mana (only the player pays with health).
- Achievements: the owner writes the real set (21 are placeholders; keep the 25-pin layout).
- (See Next up 1.) Owner may replace Claude-made art with their own: effect sprites (`tools/art/make_effect_sprites.py`), item/status/ability glyph icons (drawn in code), face parts and anime faces (`tools/art/make_face_parts.py`, `make_anime_face.py`), eyes, grass card; and the synthesised sounds/music. Same file names = drop-in replacements. Until then, list them on Steam's AI disclosure to be safe.
- NPC idle animation per Database entry (sitting, leaning, sweeping…) for camps and inns.
- Icicles on branches in snow (needs a small icicle model or sprite).
- Wet rain look: more saturation, darker colours, drips from trees.
- Collectables: hidden cats to pet (Codex page "Cats found n/N", achievement), coin caches, XP shrines; counts on the region map.
- Campfires: heal nearby over time; burn out after x hours unless fed items with a "flame fuel" toggle + hours in the Database; "permanent flame" toggle; relighting a dead one. (Checkpoint + rest + rested/tired are done.)
- Player houses much later (always Well Rested). Lying in beds.
- Mimic enemies disguised as treasure chests (use the loot animation).
- Rivers: splashes when wading through shallow streams; fish visible; fishing.
- Minimap (corner), separate from the M region map: build it from every chunk's terrain (like the region map) centred on the player, so it runs on across region borders with no hard edge.
- Quaternius Universal Animation Library: owner tries the free pack; Claude needs the files to map its bones onto the Mixamo rig.
- Mage: a staff weapon, robes (owner modelling), and turning the test spells into skill-tree nodes.
- Boss intro (arena entrance, music cue, name card).
- Stealth sneak-walk animation; paired finisher animations (Mixamo).
- Co-op: party list doesn't show other players; beasts sync roughly.
- Horses (needs a model + animations), then the train between cities (needs more than one city).
- Dragon / bat models from the owner: .glb, unrigged in named parts with origins at the joints (`wing_L`, `wing_R`, `jaw`, `neck_1..4`, `tail_1..8`) is the easy route.

## Loose ends
- Effect sprites on the ground are hidden by tall grass standing on them.
- Snow isn't in any region's weather list yet (owner's choice which regions get it).
- Cover map: roofs need collision to count (visual-only meshes don't keep rain out); tree canopies have none, so rain falls through trees (a small dry ring shows at each trunk). It reaches 24 m from the camera: covered floors further away than that look wet.
- Credits: the second Vincent Freelance hair collection ("FREE 21 Realtime man Hairstyles collection", same creator, Sketchfab) has no link yet: owner to find it (Sketchfab downloads / likes) and check it says CC-BY.
- The shield's bone name was fixed in the data (`mixamorig_LeftForeArm`); it needs **Rebuild** in Body Models to take effect.
- Blue Cloak is in the starting backpack for new characters only.
- Not checkable in Claude's test renderer (verify in the editor): decals (blood on slopes, leaves, cloud shadows), SSAO, the finisher kill-cam.

## Latest work (all pushed)
13 Nov: Body Types 3 and 4 (new bodies, borrowed gear until refitted); level split into region sub-scenes + Events grouped by region; shop + tower trader, menu fades, time-of-day enemies, hair second colour, moving pupils, troll smashes anyone near; retro-fog fix, ladders/under-map recovery, hearthstone in water, enemy alerts + bandit bows, backpack with pins + look toggles, 25 achievements, real calendar/moon/holidays, retro planet, golem nameplates, rounder pack, Remnant-style numbers, 12/24 h clock, Emitter, mana-from-health. 12 Nov: classes + mage spells, sky extras, elements, retro look.
Batch Z on 12 Nov: inventory click-to-pick + dropped items, Z draw/stow, follower ladders, HUD badges/portraits, talk vignette/blur/freeze, animated desert golems with a guard, rivers and waterfalls, Monolith healing, campfires (checkpoint, rest, death choice, revive), seats and camp resting. Batch V on 11 Nov: Base Character defaults, switch-gated props (ladder), Saturn-style skill trees, backpack in the Codex, hotbar drag fix, Esc cancels. Batch U on 11 Nov: multi-material pieces + max_side, chainmail belt/trim/skirt, rotated NPCs/enemies facing fix. Batch T on 11 Nov: per-part face placement (creator + Database). Batch S on 11 Nov: anime/cat eyes, anime noses/mouths/brows/extras, Database look preview, short hair sway off. Batch R on 11 Nov: bigger eyes, heterochromia, brows / noses / mouths / extras, looks + gear for enemies. Batch Q on 10 Nov: Halo-style nav marker, Database item groups + Saturn icons, hotbar defaults, Spells in the Codex, Hearthstone in the air, matte terrain. Batches L–P on 10 Nov: safe areas (SafeArea box, off switch), indoor weather (roof check, muffled sound, cover map: rain outside doors, dry floors), performance (smoother streaming, sleeping AI, prop ranges, occlusion, quality settings, F3 overlay), snow and blizzards, effect sprites for abilities, insect sprites and Swarm Spots, the pixel look for effects and icons, ants, the troll boss and player knockdowns. Batches E–K on 9–10 Nov: falling leaves, random ambience, statuses and icons, injured walk, rarity, stealth / Frost Edge / Burst Quake, finisher cam, bats and the dragon, hair and cape sway by material, threat and smarter companions (wait for the player, never steal kills, go down and take cover), recruitable archer / mage / healer, Tab targeting with lock-on, region map (M), fall damage, blood, rain splashes, colour picker, Body Models categories, night and dawn sounds.
