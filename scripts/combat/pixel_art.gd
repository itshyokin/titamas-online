class_name PixelArt
extends RefCounted
## The game's pixel look for things drawn in code (effects, decals, icons), to match the
## grass and the pixel textures: few pixels, hard edges and a handful of see-through
## steps instead of smooth fades, always shown with nearest-pixel filtering.
## Names no autoloads, so test scripts can name it.

## See-through steps a soft edge is cut into (0 and 1 plus these).
const ALPHA_STEPS := [0.35, 0.7]


## `a` snapped to the steps: 0, 0.35, 0.7 or 1.
static func step_alpha(a: float) -> float:
	if a < 0.18:
		return 0.0
	if a < 0.5:
		return ALPHA_STEPS[0]
	if a < 0.85:
		return ALPHA_STEPS[1]
	return 1.0


## Cuts every pixel's see-through amount into the steps.
static func step_image(img: Image) -> Image:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			c.a = step_alpha(c.a)
			img.set_pixel(x, y, c)
	return img


## Nearest-pixel filtering on a material (no blur between texels).
static func crisp(mat: BaseMaterial3D) -> BaseMaterial3D:
	if mat:
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return mat
