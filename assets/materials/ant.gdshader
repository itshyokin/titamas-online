shader_type spatial;
// Ants walking along a trail (Wildlife "ants"): each is a small flat picture lying on the
// surface (a MultiMesh instance), its legs swapping between the frames of the strip.
render_mode cull_disabled, specular_disabled;

uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(0.08, 0.06, 0.05, 1.0);
uniform float frames = 2.0;
uniform float steps_per_second = 9.0;

varying flat float frame;

void vertex() {
	frame = floor(mod(TIME * steps_per_second + float(INSTANCE_ID) * 0.37, frames));
}

void fragment() {
	vec4 t = texture(tex, vec2((UV.x + frame) / frames, UV.y));
	ALBEDO = tint.rgb * mix(0.8, 1.0, t.r);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
