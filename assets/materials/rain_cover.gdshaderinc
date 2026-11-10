// The cover map (RainCover, a child of Weather): for a square around the camera, the
// height of the highest solid thing at each spot (ground, roofs, overhangs, water, the
// tops of indoors boxes). Rain and snow only draw above it, and the ground only gets
// wet where nothing is over it. One texel per cell; the texture wraps, so the map
// scrolls with the camera without being redrawn. Red = solid cover (stops rain and snow);
// green = that or a tree's canopy, whichever is higher (frost doesn't settle under trees).
global uniform sampler2D rain_cover : filter_nearest, repeat_enable;
// Centre x, centre z, width of the square (m), 1 while the map is in use.
global uniform vec4 rain_cover_window;

// Snow lying on the ground (Weather field "frost"): 0 none, 1 nearly everywhere.
global uniform float snow_cover;

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

// The same, counting tree canopies as cover too.
float rain_cover_canopy(vec2 xz) {
	if (rain_cover_window.w < 0.5) {
		return RAIN_COVER_NONE * 2.0;
	}
	float cell = rain_cover_window.z / RAIN_COVER_CELLS;
	vec2 d = abs(xz - rain_cover_window.xy);
	if (max(d.x, d.y) > rain_cover_window.z * 0.5 - cell * 1.5) {
		return RAIN_COVER_NONE * 2.0;
	}
	return textureLod(rain_cover, xz / rain_cover_window.z, 0.0).g;
}

// 1 where the surface at `pos` is open to the sky, 0 where something is over it, with a
// soft edge about a cell wide. Looks a little way out along the surface's normal, so the
// inside of a wall counts as indoors and its outside (or a cliff face) as outdoors.
float rain_cover_open_of(vec3 pos, vec3 normal, bool canopy) {
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
		vec2 spot = (base + o + 0.5) * cell;
		float h = canopy ? rain_cover_canopy(spot) : rain_cover_height(spot);
		float w = (o.x > 0.5 ? f.x : 1.0 - f.x) * (o.y > 0.5 ? f.y : 1.0 - f.y);
		open += w * step(h - 1.2, pos.y);
	}
	return open;
}

float rain_cover_open(vec3 pos, vec3 normal) {
	return rain_cover_open_of(pos, normal, false);
}

float rc_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float rc_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(rc_hash(i), rc_hash(i + vec2(1.0, 0.0)), u.x),
		mix(rc_hash(i + vec2(0.0, 1.0)), rc_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// How much snow lies at `pos` (0-1): in drifting patches that join up as snow_cover
// rises, only on ground that faces up, and not under roofs or trees.
float snow_at(vec3 pos, vec3 normal) {
	if (snow_cover < 0.004) {
		return 0.0;
	}
	float n = rc_noise(pos.xz * 0.16) * 0.65 + rc_noise(pos.xz * 0.47 + 13.7) * 0.35;
	float patch = smoothstep(1.02 - snow_cover * 1.05, 1.16 - snow_cover * 0.95, n + 0.12);
	float flat_ground = smoothstep(0.55, 0.82, normal.y);
	return patch * flat_ground * rain_cover_open_of(pos, normal, true);
}
