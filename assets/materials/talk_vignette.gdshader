shader_type canvas_item;
// Conversation mood: dark soft edges (TalkCamera). strength 0..1.
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.02, 0.01, 0.03, 1.0);

void fragment() {
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.25, 1.0);
	float v = smoothstep(0.28, 0.82, length(d));
	COLOR = vec4(tint.rgb, v * strength);
}
