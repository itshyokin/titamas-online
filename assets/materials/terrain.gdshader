shader_type spatial;
// Painted terrain: mixes ground textures using the paint from Blender's TerrainPaint layer,
// which the add-on exports in the second UV map: UV2.x = layer G (dirt), UV2.y = layer B
// (cliff), layer R (grass) = the rest. Chunks without paint read as all grass.
// Edges are broken up with noise so painted borders look natural, steep slopes can
// turn to the B layer (rock) automatically, and the B layer is projected from three
// sides so cliffs don't stretch.
render_mode diffuse_lambert, specular_disabled;

#include "res://assets/materials/pixel_sample.gdshaderinc"

uniform sampler2D tex_r : source_color, filter_nearest_mipmap, repeat_enable; // grass
uniform sampler2D tex_g : source_color, filter_nearest_mipmap, repeat_enable; // dirt
uniform sampler2D tex_b : source_color, filter_nearest_mipmap, repeat_enable; // cliff / rock

// World metres per texture repeat.
uniform float tile_size = 4.0;
uniform float tile_size_b = 6.0;
// How much noise breaks up painted borders (0 = smooth fades).
uniform float breakup : hint_range(0.0, 1.0) = 0.55;
// Higher = crisper borders between layers.
uniform float sharpness : hint_range(1.0, 8.0) = 3.0;
uniform float noise_scale = 0.35;
// Rock on steep ground: slope is 0 for flat, 1 for vertical.
uniform float auto_cliff : hint_range(0.0, 1.0) = 1.0;
uniform float cliff_slope_start : hint_range(0.0, 1.0) = 0.35;
uniform float cliff_slope_end : hint_range(0.0, 1.0) = 0.55;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	// Sin-free hash: stays stable at large coordinates (sin-based hashes lose
	// precision on the GPU and produce hard-edged blocks).
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.6 + vnoise(p * 2.3 + 7.1) * 0.3 + vnoise(p * 5.1 + 3.7) * 0.1;
}

vec3 triplanar(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 b = pow(abs(n), vec3(4.0));
	b /= (b.x + b.y + b.z);
	vec3 x = px_sample(tex, p.zy / scale).rgb;
	vec3 y = px_sample(tex, p.xz / scale).rgb;
	vec3 z = px_sample(tex, p.xy / scale).rgb;
	return x * b.x + y * b.y + z * b.z;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = world_pos.xz / tile_size;
	vec3 col_r = px_sample(tex_r, uv).rgb;
	vec3 col_g = px_sample(tex_g, uv).rgb;
	vec3 col_b = triplanar(tex_b, world_pos, world_normal, tile_size_b);

	vec2 paint = clamp(UV2, 0.0, 1.0);
	vec4 w = vec4(max(1.0 - paint.x - paint.y, 0.0), paint.x, paint.y, 0.0);
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	w.b += smoothstep(cliff_slope_start, cliff_slope_end, slope) * auto_cliff * 2.0;

	// Noise per layer, then sharpen: borders become irregular patches, not straight fades.
	vec2 q = world_pos.xz * noise_scale;
	vec4 nz = vec4(fbm(q), fbm(q + 17.3), fbm(q + 41.7), fbm(q + 5.1));
	w *= mix(vec4(1.0), nz * 2.0, breakup);
	w = pow(max(w, vec4(0.0001)), vec4(sharpness));
	w /= max(w.r + w.g + w.b, 0.0001);

	ALBEDO = col_r * w.r + col_g * w.g + col_b * w.b;
	ROUGHNESS = 1.0;
}
