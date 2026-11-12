shader_type spatial;
// Retextures a creature model with our rock: the model's own picture only gives the light
// and dark of its carving (luminance, around `detail_mid`), our rock texture gives colour
// and grain through the model's UVs. Gilded golems tint it gold and metallic.
// Emissive surfaces (glowing cracks) use `glow_color` × `glow`.

uniform sampler2D rock : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail : source_color, filter_linear_mipmap;
uniform float rock_uv_scale = 3.0;
uniform float detail_mid = 0.4;
uniform float detail_amount = 0.85;
uniform vec4 tint : source_color = vec4(1.0);
uniform float metal = 0.0;
uniform float rough = 0.92;
uniform bool glowing = false;
uniform vec4 glow_color : source_color = vec4(1.0, 0.6, 0.25, 1.0);
uniform float glow = 2.0;

void fragment() {
	vec3 d = texture(detail, UV).rgb;
	float lum = dot(d, vec3(0.3, 0.55, 0.15));
	float shade = mix(1.0, clamp(lum / max(detail_mid, 0.01), 0.25, 1.8), detail_amount);
	vec3 r = texture(rock, UV * rock_uv_scale).rgb;
	ALBEDO = r * shade * tint.rgb;
	METALLIC = metal;
	ROUGHNESS = rough;
	if (glowing) {
		ALBEDO = glow_color.rgb * 0.4;
		EMISSION = glow_color.rgb * glow * (0.5 + lum);
	}
}
