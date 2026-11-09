shader_type spatial;
render_mode cull_disabled;
// Hair and capes swinging with movement and fluttering in the wind (CharacterModel._add_sway).
// Vertices hang from `top` (mesh space): the further below it, the more they move.

global uniform float wind_strength;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, hint_default_white;
uniform bool use_tex = false;
uniform float roughness = 0.9;
uniform float alpha_cut = 0.0;
uniform float top = 1.8;
uniform float hang = 0.6;
uniform float amount = 1.0;
// Movement trail, in mesh space (set each frame by CharacterModel, spring-smoothed).
uniform vec3 trail = vec3(0.0);
uniform float flutter = 0.03;

void vertex() {
	float w = clamp((top - VERTEX.y) / max(hang, 0.01), 0.0, 1.0);
	w = w * w;
	float t = TIME * (2.0 + wind_strength * 2.0) + VERTEX.y * 4.0 + VERTEX.x * 3.0;
	vec3 wave = vec3(sin(t) * 0.6, sin(t * 0.7) * 0.2, sin(t * 1.3 + 1.7)) * flutter * (0.35 + wind_strength);
	VERTEX += (trail + wave) * w * amount;
}

void fragment() {
	vec4 c = albedo;
	if (use_tex) {
		c *= texture(albedo_tex, UV);
	}
	if (alpha_cut > 0.0 && c.a < alpha_cut) {
		discard;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = roughness;
}
