shader_type spatial;
// Campfire flame card: a flickering tongue of fire (noise rising through a teardrop),
// pixel-stepped like the rest of the game's effects. Unshaded, additive.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 core : source_color = vec4(1.0, 0.9, 0.5, 1.0);
uniform vec4 edge : source_color = vec4(1.0, 0.35, 0.05, 1.0);
uniform float speed = 1.6;
uniform float pixels = 20.0;
uniform float seed = 0.0;
uniform float strength = 1.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = floor(UV * pixels) / pixels;
	float y = 1.0 - uv.y;  // 0 at the bottom
	float t = TIME * speed + seed;
	float n = noise(vec2(uv.x * 4.0 + seed, y * 3.0 - t * 2.2)) * 0.6 + noise(vec2(uv.x * 9.0, y * 6.0 - t * 3.5)) * 0.4;
	float width = (1.0 - y) * 0.45 + 0.05;
	float wobble = (noise(vec2(y * 2.0, t)) - 0.5) * 0.25 * y;
	float d = abs(uv.x - 0.5 - wobble) / width;
	float shape = (1.0 - d) * (1.0 - y * 0.9) + (n - 0.5) * 0.9;
	float a = smoothstep(0.05, 0.35, shape);
	a = floor(a * 3.0 + 0.5) / 3.0;
	vec3 col = mix(edge.rgb, core.rgb, smoothstep(0.3, 0.8, shape));
	ALBEDO = col * a * strength;
	ALPHA = a;
}
