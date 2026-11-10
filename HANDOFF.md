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

## Backlog (agreed, not started)
- NPC idle animation per Database entry (sitting, leaning, sweeping…) for camps and inns.
- Snow weather (use `Weather.shelter` so it stops indoors like rain): snowfall, frost on grass in patches but not under trees, icicles on branches.
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
- Cover map: roofs need collision to count (visual-only meshes don't keep rain out); tree canopies have none, so rain falls through trees (a small dry ring shows at each trunk). It reaches 24 m from the camera: covered floors further away than that look wet.
- Credits: the second Vincent Freelance hair collection ("FREE 21 Realtime man Hairstyles collection") has no link yet.
- The shield's bone name was fixed in the data (`mixamorig_LeftForeArm`); it needs **Rebuild** in Body Models to take effect.
- Blue Cloak is in the starting backpack for new characters only.
- Not checkable in Claude's test renderer (verify in the editor): decals (blood on slopes, leaves, cloud shadows), SSAO, the finisher kill-cam.

## Latest work (all pushed)
Batch L on 10 Nov: safe areas (SafeArea box, off switch) and indoor weather (roof check, muffled sound). Batches E–K on 9–10 Nov: falling leaves, random ambience, statuses and icons, injured walk, rarity, stealth / Frost Edge / Burst Quake, finisher cam, bats and the dragon, hair and cape sway by material, threat and smarter companions (wait for the player, never steal kills, go down and take cover), recruitable archer / mage / healer, Tab targeting with lock-on, region map (M), fall damage, blood, rain splashes, colour picker, Body Models categories, night and dawn sounds.
