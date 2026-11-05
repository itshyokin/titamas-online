# Notes for Claude

- Godot 4.6.2, GDScript, Forward+ renderer. PC only.
- The owner tests in the Godot editor; Claude can't see the game. Validate changes headless before pushing:
  `godot --headless --path . --import` then run a smoke-test `SceneTree` script.
- Prefer generating complex `.tscn` files with a headless build script over hand-writing them.
- Typed GDScript (`:=`, typed params), tabs for indentation, `class_name` on reusable scripts.
- Physics layers: 1 world, 2 players, 3 enemies.
- Character rig: Mixamo (`mixamorig:` bones), shared by masc and femme bodies. Femme body parts are prefixed `f_`.
- Design doc lives as a Claude doc ("Titamas Online — Design Doc"); README has Blender and level-chunk conventions.
- Visual checks: `xvfb-run -a godot --path . --rendering-driver opengl3 --script <shot.gd>` renders screenshots (software GL).
- `base_bodies.glb` holds both bodies; its import uses `root_scale=0.01` because the Mixamo bones come through in centimetres. Keep that setting if the file is re-exported the same way.
- When building scenes by script, never set `owner` on nodes inside an instanced scene (causes duplicate-node load errors).
- Animations: Mixamo FBX (Without Skin) go in `assets/animations/mixamo/`; run `godot --headless --path . --script res://tools/godot/retarget_mixamo.gd` to rebuild `masc.res`/`femme.res`. Looping/in-place lists live at the top of that script. Facing is derived from hip anatomy, not bone axes.
- `PlayerAnimator` picks animations from movement; `CharacterModel.play()/play_from()` crossfade. Animations only run in-game (not in the editor) so bone poses never get saved into scenes.
- Player states (PlayerController.State): NORMAL, DODGE, HANG, LEDGE_CLIMB, WALL_CLIMB, LADDER, SWIM. Groups `climbable`/`ladder` mark surfaces; `WaterVolume` (physics layer 4) marks water. One-shot moves emit `action_animation`; continuous states call `character.play()` directly.
- Converter extras: `ROOT_MOTION` (travel baked to metadata), `YAW_FIX` (clips facing backwards), `HEIGHT_MATCH`, `ARM_SPREAD`.
- World: `Ocean` (group "ocean", sea level −5 m) follows the player; `_water_at()` treats anything below sea level as water. Fatigue builds when swimming >48 m from the nearest chunk; kill floor at −80 m; both respawn at the last dry ground. `AtmosphereManager` blends `RegionAtmosphere` resources (assets/regions/, chunk rectangles) and shows the zone name.
- Chunk materials are swapped by name for `assets/materials/terrain/<name>.tres`; chunk meshes named `*-water` become water (shader + swimmable `WaterVolume`).
- Props: `chunk_I_J.props.json` beside each chunk lists {name, pos, basis columns} in chunk space; `PropLibrary` loads `assets/props/<name>.glb`, applies `foliage_wind.gdshader` to foliage names and adds collision (tree trunk cylinder / convex hull / none). JSON files must be included when exporting the game (Export → Resources → filters: `*.json`).
