# Art sheets: draw over the game's pictures

These sheets hold the pictures that were made by code (Claude's scripts) so you can draw
your own over them. Each `<name>.png` is a grid of equal cells; `<name>_guide.png` is a big
labelled copy to look at (don't edit it); `<name>.json` says which game file each cell is.

1. Open a sheet (e.g. `mouths.png`) in your pixel editor and set the grid to the cell size
   written at the top of its guide (Aseprite: View > Grid Settings, or File > Import Sprite
   Sheet with that cell size).
2. Draw on a new layer over the old picture, hide or delete the old layer, flatten, and
   save over the same `.png` (keep transparency, don't resize the sheet).
3. In the project folder run `python3 tools/art/sheets.py split`. Only the cells you changed
   are written back; switch to Godot and it picks them up.

| Sheet | What | Cell |
| --- | --- | --- |
| eyes / eyes_iris | eyes, and the white mask where the eye colour goes (same order) | 32 × 24 |
| brows, noses, mouths, face_extras | face layers: grey 128 = skin/hair colour as it is, darker/lighter = shade it; `anime_*` are drawn as they are | 64 × 80 |
| effects | spell, weather and insect sprites: white on clear (the game colours them); `_2`/`_4` = frames side by side | 96 × 48 |
| item_icons | the 16 px item icons | 16 × 16 |
| icons | ability icons (`assets/icons/abilities/<ability id>`), status glyphs (white) and two old item glyphs | 24 × 24 |

A picture keeps its own size inside its cell (the yellow box in the guide); anything drawn
outside it is ignored. To make new sheets after adding pictures: `python3 tools/art/sheets.py make`
(it overwrites the sheets here, so split your work first).

Careful: the generator scripts (`tools/art/make_face_parts.py`, `make_anime_face.py`,
`make_eyes.py`, `make_effect_sprites.py`, `tools/art/export_saturn_icons.mjs`,
`tools/godot/export_icons.gd` with OVERWRITE=1) write over these game files. Once you've
drawn your own, don't run them.
