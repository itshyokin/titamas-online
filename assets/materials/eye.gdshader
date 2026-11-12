shader_type spatial;
// Character eyes: a flat eye texture laid on the face (see tools/art/make_eyes.py).
// The iris mask marks where the chosen eye colour tints the texture.
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D eye_texture : source_color, filter_nearest;
uniform sampler2D iris_mask : hint_default_black, filter_nearest;
uniform vec3 eye_color : source_color = vec3(0.3, 0.5, 0.8);
// Eyelids (CharacterModel: blinking, squinting moods): 0 open, 1 shut. The upper lid comes
// down further than the lower one comes up; a dark lash line runs along their edges.
uniform float blink : hint_range(0.0, 1.0) = 0.0;
uniform vec3 lid_color : source_color = vec3(0.85, 0.66, 0.55);

void fragment() {
	vec4 base = texture(eye_texture, UV);
	float m = texture(iris_mask, UV).r;
	ALBEDO = base.rgb * mix(vec3(1.0), eye_color * 1.25, m);
	if (blink > 0.001) {
		float upper = blink * 0.62;
		float lower = 1.0 - blink * 0.4;
		if (UV.y < upper || UV.y > lower) {
			ALBEDO = lid_color;
		}
		if (abs(UV.y - upper) < 0.09 || (blink > 0.95 && abs(UV.y - 0.6) < 0.1)) {
			ALBEDO = lid_color * 0.25;
		}
	}
	ALPHA = base.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
}
