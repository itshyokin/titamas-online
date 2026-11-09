shader_type canvas_item;
// Whole-screen mood (ScreenMood): grayscale, saturation and a dark vignette.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float gray : hint_range(0.0, 1.0) = 0.0;       // 1 = black and white
uniform float saturation : hint_range(0.0, 1.5) = 1.0; // 1 = unchanged
uniform float vignette : hint_range(0.0, 1.0) = 0.0;   // dark edges
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = mix(c, vec3(l), gray);
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.25, 1.0);
	float v = smoothstep(0.32, 0.85, length(d)) * vignette;
	c = mix(c, vignette_color.rgb, clamp(v * 1.3, 0.0, 1.0));
	COLOR = vec4(c, 1.0);
}
