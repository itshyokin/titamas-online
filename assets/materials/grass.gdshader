shader_type spatial;
// Grass clumps scattered over painted terrain (GrassField), in the style of Saturn's tall
// grass: crossed cards with a picture of a clump of blades (assets/textures/grass_clump.png,
// grey: light at the tips). Each clump takes its colour from the ground texture under it,
// mixed with the region's grass colours, and is lit like the ground (normals point up,
// and it receives shadows). Blades bend with the wind, part around the player and shrink
// away with distance.
render_mode cull_disabled, diffuse_lambert, specular_disabled;

global uniform float wind_strength;
global uniform vec3 player_position;
global uniform vec4 grass_base : source_color;
global uniform vec4 grass_tip : source_color;
// 0 = the region's colours only, 1 = the ground's colour only.
global uniform float grass_ground_match;
// Height of a clump (m) before each clump's own random size.
global uniform float grass_height;

uniform sampler2D clump_tex : source_color, filter_nearest_mipmap, repeat_disable;
// The terrain's grass texture and its size (set from the terrain material).
uniform sampler2D ground_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float ground_tile_size = 4.0;
uniform float fade_start = 26.0;
uniform float fade_end = 38.0;
uniform float sway = 0.16;
uniform float push_radius = 0.9;
uniform vec2 wind_direction = vec2(1.0, 0.35);

varying float tip;
varying vec3 root_world;
varying float shade;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	root_world = root;
	tip = 1.0 - UV.y;
	float bend = tip * tip;
	shade = 0.9 + 0.2 * hash(root.xz);
	VERTEX.y *= max(grass_height, 0.05);

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
		offset += normalize(away) * near * 0.5 * bend;
		offset.y -= near * 0.3 * bend;
	}
	world += offset;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	// Lit like the ground it grows from.
	NORMAL = normalize((inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	vec4 pic = texture(clump_tex, UV);
	ALPHA = pic.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 ground = textureLod(ground_tex, root_world.xz / ground_tile_size, 4.0).rgb;
	vec3 region = mix(grass_base.rgb, grass_tip.rgb, tip);
	vec3 base = mix(region, ground * mix(0.95, 1.2, tip), clamp(grass_ground_match, 0.0, 1.0));
	ALBEDO = base * pic.r * 1.15 * shade;
	// Up, on both sides of the card (a back face would otherwise be lit from below).
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.08) * tip;
}
