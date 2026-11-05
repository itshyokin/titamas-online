shader_type spatial;
// One expanding ring on a water surface; `age` goes 0 -> 1 over its life (Effects.ripple).
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

instance uniform float age = 0.0;
uniform vec4 color : source_color = vec4(0.9, 0.96, 1.0, 0.75);

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float ring = smoothstep(0.78, 0.9, r) * (1.0 - smoothstep(0.9, 1.0, r));
	float inner = smoothstep(0.45, 0.6, r) * (1.0 - smoothstep(0.6, 0.7, r)) * 0.35;
	ALBEDO = color.rgb;
	ALPHA = (ring + inner) * color.a * (1.0 - age) * (1.0 - age);
}
