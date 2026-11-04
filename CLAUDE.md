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
