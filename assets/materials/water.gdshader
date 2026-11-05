shader_type spatial;
// Stylised water for the ocean, pools and Blender water planes.
// Everything is in world space, so a plane that follows the player never "slides"
// and neighbouring water pieces line up.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.13, 0.36, 0.44, 0.78);
uniform vec4 deep_color : source_color = vec4(0.04, 0.15, 0.27, 0.93);
uniform float wave_height = 0.12;
uniform float wave_speed = 0.6;
// Distance at which the water reaches its deep colour (fades with view distance).
uniform float deep_distance = 140.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.15;
uniform float specular_value : hint_range(0.0, 1.0) = 0.35;
uniform float ripple_strength = 0.12;

varying vec3 world_pos;

// Four travelling waves in different directions so no regular grid pattern forms.
float waves(vec2 p, float t) {
	float h = 0.0;
	h += sin(dot(p, vec2(0.31, 0.12)) + t * 1.00) * 0.40;
	h += sin(dot(p, vec2(-0.17, 0.27)) + t * 1.31) * 0.30;
	h += sin(dot(p, vec2(0.23, -0.29)) + t * 0.83) * 0.20;
	h += sin(dot(p, vec2(-0.41, -0.07)) + t * 1.67) * 0.10;
	return h;
}

float hash(vec2 p) {
	// Sin-free hash: stays stable at large coordinates (sin-based hashes lose
	// precision on the GPU and produce hard-edged blocks).
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += waves(world_pos.xz, TIME * wave_speed) * wave_height;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = world_pos.xz;
	float e = 0.1;
	float h = waves(p, t);
	vec3 n = normalize(vec3(
		-(waves(p + vec2(e, 0.0), t) - h) / e * wave_height,
		1.0,
		-(waves(p + vec2(0.0, e), t) - h) / e * wave_height));
	// Irregular ripples from two drifting noise layers.
	vec2 q = p * 0.6;
	float r1 = noise(q + vec2(TIME * 0.3, TIME * 0.2));
	float r2 = noise(q * 1.7 - vec2(TIME * 0.25, -TIME * 0.35));
	n.xz += (vec2(r1, r2) - 0.5) * ripple_strength;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n), 0.0)).xyz);

	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec4 col = mix(shallow_color, deep_color, clamp(dist / deep_distance, 0.0, 1.0));
	ALBEDO = col.rgb;
	ALPHA = col.a;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
}
