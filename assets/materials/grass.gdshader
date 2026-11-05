shader_type spatial;
// Grass clumps scattered over painted terrain (GrassField). Blades bend with the wind
// (WorldCycle's wind_strength), part around the player, shrink away with distance, and
// take the region's grass colours (base -> tip).
render_mode cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;

global uniform float wind_strength;
global uniform vec3 player_position;
global uniform vec4 grass_base : source_color;
global uniform vec4 grass_tip : source_color;

uniform float fade_start = 26.0;
uniform float fade_end = 38.0;
uniform float sway = 0.14;
uniform float push_radius = 0.9;
uniform vec2 wind_direction = vec2(1.0, 0.35);

varying float tip;
varying float shade;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	tip = UV.y;
	float bend = tip * tip;
	shade = 0.8 + 0.4 * hash(root.xz);

	// Shrink away with distance (no pop).
	float dist = length(root - CAMERA_POSITION_WORLD);
	float keep = 1.0 - smoothstep(fade_start, fade_end, dist);
	VERTEX *= keep;

	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 dir = normalize(wind_direction);
	float w = max(wind_strength, 0.0);
	float phase = dot(root.xz, vec2(0.27, 0.41));
	float gust = 0.6 + 0.4 * sin(dot(root.xz, dir) * 0.08 - TIME * 1.8);
	float s = (sin(TIME * 2.1 + phase) * 0.5 + 0.6) * gust;
	vec3 offset = vec3(dir.x, 0.0, dir.y) * s * sway * w * bend;
	// Pushed aside by the player.
	vec3 away = root - player_position;
	away.y = 0.0;
	float near = 1.0 - smoothstep(0.0, push_radius, length(away));
	if (length(away) > 0.001) {
		offset += normalize(away) * near * 0.45 * bend;
		offset.y -= near * 0.25 * bend;
	}
	world += offset;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	vec3 col = mix(grass_base.rgb, grass_tip.rgb, tip) * shade;
	ALBEDO = col;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.25) * tip;
}
