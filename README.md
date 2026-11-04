# Titamas Online

A small-group (1–10 player) co-op 3D RPG set in the world of Titamas. Built in **Godot 4.6** with GDScript. Levels and characters are made in Blender.

## Running it

1. Pull with GitHub Desktop.
2. Open Godot 4.6, click **Import**, pick this folder's `project.godot`.
3. Press **F5** (Play). The test level loads.

**Controls (milestone 1):** WASD move · Shift sprint · Space jump · hold right mouse to look · mouse wheel zoom.

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
- Connections that aren't on the grid (cave mouths, building doors) use **connector empties** named `CONN_<name>`; matching names snap together.

## Milestones

1. Movement and camera ← **current**
2. Combat
3. Equipment
4. Co-op
5. Content tools
6. World
