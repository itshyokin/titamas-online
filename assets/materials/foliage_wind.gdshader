shader_type spatial;
// Foliage with wind: trees, bushes, grass. Sway grows with height above the prop's base
// (the bottom stays planted), each plant gets its own phase from its position, and gusts
// roll across the world. Leaves can be alpha-cutout textures.
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_alpha_cutout = true;
uniform float alpha_cutout : hint_range(0.0, 1.0) = 0.5;

// Height (m, in the prop's own space) at which sway reaches full strength.
uniform float sway_height = 6.0;
uniform float sway_strength = 0.18;
uniform float sway_speed = 1.1;
// Small fast flutter on top of the slow sway (leaves, needles).
uniform float flutter_strength = 0.03;
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float gust_scale = 0.02;
uniform float gust_speed = 0.35;

void vertex() {
	vec3 origin = NODE_POSITION_WORLD;
	float h = clamp(VERTEX.y / max(sway_height, 0.01), 0.0, 1.0);
	float weight = h * h;  // stiff near the ground, loose at the tips
	vec2 dir = normalize(wind_direction);
	float phase = dot(origin.xz, vec2(0.37, 0.71));
	// Gusts: a slow wave travelling along the wind direction.
	float gust = 0.6 + 0.4 * sin(dot(origin.xz, dir) * gust_scale * 6.2831 - TIME * gust_speed * 6.2831);
	float sway = sin(TIME * sway_speed + phase) * 0.6 + sin(TIME * sway_speed * 2.3 + phase * 1.7) * 0.4;
	vec3 world_offset = vec3(dir.x, 0.0, dir.y) * (sway + 0.35) * sway_strength * gust * weight;
	float flutter = sin(TIME * 7.0 + dot(VERTEX, vec3(3.1, 2.3, 4.7))) * flutter_strength * weight;
	world_offset += vec3(flutter, flutter * 0.5, -flutter);
	// Offset is in world space; bring it into the model's space (handles rotated/scaled props).
	VERTEX += (inverse(MODEL_MATRIX) * vec4(world_offset, 0.0)).xyz;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV) * albedo_color;
	ALBEDO = tex.rgb;
	if (use_alpha_cutout) {
		ALPHA = tex.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_cutout;
	}
	ROUGHNESS = 1.0;
}
