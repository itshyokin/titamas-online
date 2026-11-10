// The cover map (RainCover, a child of Weather): for a square around the camera, the
// height of the highest solid thing at each spot (ground, roofs, overhangs, water, the
// tops of indoors boxes). Rain and snow only draw above it, and the ground only gets
// wet where nothing is over it. One texel per cell; the texture wraps, so the map
// scrolls with the camera without being redrawn.
global uniform sampler2D rain_cover : filter_nearest, repeat_enable;
// Centre x, centre z, width of the square (m), 1 while the map is in use.
global uniform vec4 rain_cover_window;

const float RAIN_COVER_CELLS = 64.0;
const float RAIN_COVER_NONE = -50000.0;

// World height of the cover over `xz` (very low where unknown or outside the map).
float rain_cover_height(vec2 xz) {
	if (rain_cover_window.w < 0.5) {
		return RAIN_COVER_NONE * 2.0;
	}
	float cell = rain_cover_window.z / RAIN_COVER_CELLS;
	vec2 d = abs(xz - rain_cover_window.xy);
	if (max(d.x, d.y) > rain_cover_window.z * 0.5 - cell * 1.5) {
		return RAIN_COVER_NONE * 2.0;
	}
	return textureLod(rain_cover, xz / rain_cover_window.z, 0.0).r;
}

// 1 where the surface at `pos` is open to the sky, 0 where something is over it, with a
// soft edge about a cell wide. Looks a little way out along the surface's normal, so the
// inside of a wall counts as indoors and its outside (or a cliff face) as outdoors.
float rain_cover_open(vec3 pos, vec3 normal) {
	if (rain_cover_window.w < 0.5) {
		return 1.0;
	}
	float cell = rain_cover_window.z / RAIN_COVER_CELLS;
	vec2 at = pos.xz + normal.xz * cell * 1.5;
	vec2 g = at / cell - 0.5;
	vec2 base = floor(g);
	vec2 f = g - base;
	float open = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 o = vec2(float(i & 1), float(i >> 1));
		float h = rain_cover_height((base + o + 0.5) * cell);
		float w = (o.x > 0.5 ? f.x : 1.0 - f.x) * (o.y > 0.5 ? f.y : 1.0 - f.y);
		open += w * step(h - 1.2, pos.y);
	}
	return open;
}
