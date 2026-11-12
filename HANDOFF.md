# Handoff (10 Nov 2026)

Where things stand, for picking the work up in a new chat. Technical notes for each system are in `CLAUDE.md`; this file is the to-do list and the agreements made in conversation.

## How we work
- The owner tests in the Godot editor on Windows and pulls with GitHub Desktop. Claude validates headless, then commits and pushes to `main`.
- Every new tunable goes in the data files and on the Database page.
- Close Godot (or its script tabs) before pulling: pressing Play saves open scripts and can write old copies over new ones.
- A red dot left of a line number in Godot's script editor is a breakpoint: it pauses the game there. Debug → Remove All Breakpoints clears them.
- Avoid "Revert this commit" in GitHub Desktop's History unless an update really should be undone.

## Next up, in order
1. **New region east of Monolith** (owner does the Blender part when home).
   - Monolith is chunks I −1..2, J 0..3. The new one: I 3..6, J 0..3.
   - Blender add-on: Export Folder = `assets/levels/overworld`, Chunk X 3, Chunk Y 0, 4 × 4, New Terrain, then Match Edges to Exported Chunks, sculpt/paint, Export Chunks (+ Export Prop Library for new props).
   - Claude then adds the regions.json entry (name, sky, music, weather, wildlife, random sounds). The M map picks the chunks up by itself.
2. **Face parts** (owner is drawing them now): separate objects in the body .glb.
   - Creator choices: `eyes_<name>`, `nose_<name>`, `mouth_<name>` → three new creator rows (new piece uses eyes / nose / mouth).
   - Shared by everyone, not in the creator: `eyes_closed`, `mouth_talk_1..3` (optional `eyes_half`, `eyes_hurt`, `mouth_shout`).
   - All in the same spot on the face; skin-coloured parts use a material with `skin` in the name; iris on its own `iris` material if eye colour should still tint it.
   - Claude adds: blinking every few seconds (player, NPCs, enemies) by swapping to `eyes_closed`; mouths cycling the talk meshes as dialogue types out.

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

## Backlog (agreed, not started)
- NPC idle animation per Database entry (sitting, leaning, sweeping…) for camps and inns.
- Icicles on branches in snow (needs a small icicle model or sprite).
- Wet rain look: more saturation, darker colours, drips from trees.
- Menu navigation sounds (hover, click, tab, open/close).
- Collectables: hidden cats to pet (Codex page "Cats found n/N", achievement), coin caches, XP shrines; counts on the region map.
- Campfires: heal nearby over time; burn out after x hours unless fed items with a "flame fuel" toggle + hours in the Database; "permanent flame" toggle; relighting a dead one = rest spot; Rested bonus (small speed / XP / damage boost).
- Tents: placeable if there's room; bedroll inside can be set as home and slept in; 5+ hours beside a campfire = Well Rested (better than Rested). Player houses much later (always Well Rested).
- Seat and lay/bed interactions.
- Mimic enemies disguised as treasure chests (use the loot animation).
- Rivers, streams, waterfalls from Blender planes named `_river`, `_stream`, `_waterfall`; need a way to mark flow direction; streams = shallow, walkable with splashes; rivers push the player (sprint-swim upstream); fish visible; fishing.
- Minimap (corner), separate from the M region map.
- Mage class: still "coming soon" in the creator; needs a starting kit and skill tree (its 75 % cast time is already in).
- Boss intro (arena entrance, music cue, name card).
- Stealth sneak-walk animation; paired finisher animations (Mixamo).
- Co-op: party list doesn't show other players; beasts sync roughly.
- Horses (needs a model + animations), then the train between cities (needs more than one city).
- Dragon / bat models from the owner: .glb, unrigged in named parts with origins at the joints (`wing_L`, `wing_R`, `jaw`, `neck_1..4`, `tail_1..8`) is the easy route.

## Loose ends
- Effect sprites on the ground are hidden by tall grass standing on them.
- Snow isn't in any region's weather list yet (owner's choice which regions get it).
- Cover map: roofs need collision to count (visual-only meshes don't keep rain out); tree canopies have none, so rain falls through trees (a small dry ring shows at each trunk). It reaches 24 m from the camera: covered floors further away than that look wet.
- Credits: the second Vincent Freelance hair collection ("FREE 21 Realtime man Hairstyles collection") has no link yet.
- The shield's bone name was fixed in the data (`mixamorig_LeftForeArm`); it needs **Rebuild** in Body Models to take effect.
- Blue Cloak is in the starting backpack for new characters only.
- Not checkable in Claude's test renderer (verify in the editor): decals (blood on slopes, leaves, cloud shadows), SSAO, the finisher kill-cam.

## Latest work (all pushed)
Batch V on 11 Nov: Base Character defaults, switch-gated props (ladder), Saturn-style skill trees, backpack in the Codex, hotbar drag fix, Esc cancels. Batch U on 11 Nov: multi-material pieces + max_side, chainmail belt/trim/skirt, rotated NPCs/enemies facing fix. Batch T on 11 Nov: per-part face placement (creator + Database). Batch S on 11 Nov: anime/cat eyes, anime noses/mouths/brows/extras, Database look preview, short hair sway off. Batch R on 11 Nov: bigger eyes, heterochromia, brows / noses / mouths / extras, looks + gear for enemies. Batch Q on 10 Nov: Halo-style nav marker, Database item groups + Saturn icons, hotbar defaults, Spells in the Codex, Hearthstone in the air, matte terrain. Batches L–P on 10 Nov: safe areas (SafeArea box, off switch), indoor weather (roof check, muffled sound, cover map: rain outside doors, dry floors), performance (smoother streaming, sleeping AI, prop ranges, occlusion, quality settings, F3 overlay), snow and blizzards, effect sprites for abilities, insect sprites and Swarm Spots, the pixel look for effects and icons, ants, the troll boss and player knockdowns. Batches E–K on 9–10 Nov: falling leaves, random ambience, statuses and icons, injured walk, rarity, stealth / Frost Edge / Burst Quake, finisher cam, bats and the dragon, hair and cape sway by material, threat and smarter companions (wait for the player, never steal kills, go down and take cover), recruitable archer / mage / healer, Tab targeting with lock-on, region map (M), fall damage, blood, rain splashes, colour picker, Body Models categories, night and dawn sounds.
