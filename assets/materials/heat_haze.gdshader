shader_type spatial;
// Heat haze (HeatHaze, region "heat_haze"): a full-screen quad that wobbles what's behind
// it, more with distance, rising like hot air. Near things and the sky (far plane) stay
// still-ish; the shimmer starts at `start` m and is full by `full` m.
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float strength = 0.0;
uniform float start = 18.0;
uniform float full = 110.0;
uniform float speed = 1.6;

float scene_z(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 ndc = vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
#else
	vec4 ndc = vec4(uv * 2.0 - 1.0, d, 1.0);
#endif
	vec4 v = inv_proj * ndc;
	return v.z / v.w;
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float dist = -scene_z(uv, INV_PROJECTION_MATRIX);
	// The sky reads as very far: shimmer it a little less than the hot ground near the horizon.
	float far = smoothstep(start, full, dist) * (dist > 4000.0 ? 0.5 : 1.0);
	float t = TIME * speed;
	vec2 p = uv * vec2(70.0, 38.0) + vec2(0.0, t * 2.5);
	vec2 wobble = vec2(vnoise(p) - 0.5, vnoise(p + 17.3 - vec2(0.0, t)) - 0.5);
	vec2 off = wobble * strength * far * 0.006;
	ALBEDO = textureLod(screen_tex, uv + off, 0.0).rgb;
}
