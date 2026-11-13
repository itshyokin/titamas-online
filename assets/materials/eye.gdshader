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
// Where the eye looks (CharacterModel: toward what the head is looking at, plus idle
// glances): the iris (the mask's part of the picture) slides by this much of the eye's
// width / height; what it uncovers is filled with the white of the eye.
uniform vec2 gaze = vec2(0.0);
uniform vec3 sclera_color : source_color = vec3(0.94, 0.93, 0.9);

void fragment() {
	vec4 base = texture(eye_texture, UV);
	float m = texture(iris_mask, UV).r;
	ALBEDO = base.rgb * mix(vec3(1.0), eye_color * 1.25, m);
	if (abs(gaze.x) + abs(gaze.y) > 0.001) {
		vec2 from = UV - gaze;
		float moved = texture(iris_mask, from).r;
		// The iris only shows over the eye's own white or iris (never over its outline or
		// lashes), so it stays inside the eye.
		bool open = m > 0.5 || dot(base.rgb, vec3(0.333)) > 0.55;
		if (moved > 0.5 && open && from.x > 0.0 && from.x < 1.0 && from.y > 0.0 && from.y < 1.0) {
			ALBEDO = texture(eye_texture, from).rgb * eye_color * 1.25;
		} else if (m > 0.5) {
			ALBEDO = sclera_color;
		}
	}
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
