shader_type spatial;
// Character eyes: a flat eye texture laid on the face (see tools/art/make_eyes.py).
// The iris mask marks where the chosen eye colour tints the texture.
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D eye_texture : source_color, filter_nearest;
uniform sampler2D iris_mask : hint_default_black, filter_nearest;
uniform vec3 eye_color : source_color = vec3(0.3, 0.5, 0.8);

void fragment() {
	vec4 base = texture(eye_texture, UV);
	float m = texture(iris_mask, UV).r;
	ALBEDO = base.rgb * mix(vec3(1.0), eye_color * 1.25, m);
	ALPHA = base.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
}
