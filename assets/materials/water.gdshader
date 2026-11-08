shader_type spatial;
// Stylised water for the ocean, pools and Blender water planes.
// Everything is in world space, so a plane that follows the player never "slides"
// and neighbouring water pieces line up.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.13, 0.36, 0.44, 0.78);
uniform vec4 deep_color : source_color = vec4(0.04, 0.15, 0.27, 0.93);
uniform float wave_height = 0.12;
uniform float wave_speed = 0.6;
// Distance at which the water reaches its deep colour (fades with view distance).
uniform float deep_distance = 140.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.15;
uniform float specular_value : hint_range(0.0, 1.0) = 0.35;
uniform float ripple_strength = 0.12;
// Shoreline: water gets darker and murkier where it's shallow, with a thin foam edge.
uniform vec4 shore_color : source_color = vec4(0.05, 0.12, 0.12, 0.92);
uniform float shore_width = 1.6;
uniform vec4 foam_color : source_color = vec4(0.92, 0.97, 1.0, 0.9);
uniform float foam_width = 0.35;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// Reflections of what's on screen (trees, cliffs, characters) traced across the water.
// The sky is reflected by the specular highlight on its own. Settings → Graphics.
global uniform float water_reflections;
uniform float reflection_strength : hint_range(0.0, 1.5) = 0.85;

varying vec3 world_pos;

// View-space depth (negative z) of the scene at a screen position.
float scene_z(vec2 uv, sampler2D depth_tex, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 ndc = vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
#else
	vec4 ndc = vec4(uv * 2.0 - 1.0, d, 1.0);
#endif
	vec4 v = inv_proj * ndc;
	return v.z / v.w;
}

// Four travelling waves in different directions so no regular grid pattern forms.
float waves(vec2 p, float t) {
	float h = 0.0;
	h += sin(dot(p, vec2(0.31, 0.12)) + t * 1.00) * 0.40;
	h += sin(dot(p, vec2(-0.17, 0.27)) + t * 1.31) * 0.30;
	h += sin(dot(p, vec2(0.23, -0.29)) + t * 0.83) * 0.20;
	h += sin(dot(p, vec2(-0.41, -0.07)) + t * 1.67) * 0.10;
	return h;
}

float hash(vec2 p) {
	// Sin-free hash: stays stable at large coordinates (sin-based hashes lose
	// precision on the GPU and produce hard-edged blocks).
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += waves(world_pos.xz, TIME * wave_speed) * wave_height;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = world_pos.xz;
	float e = 0.1;
	float h = waves(p, t);
	vec3 n = normalize(vec3(
		-(waves(p + vec2(e, 0.0), t) - h) / e * wave_height,
		1.0,
		-(waves(p + vec2(0.0, e), t) - h) / e * wave_height));
	// Irregular ripples from two drifting noise layers.
	vec2 q = p * 0.6;
	float r1 = noise(q + vec2(TIME * 0.3, TIME * 0.2));
	float r2 = noise(q * 1.7 - vec2(TIME * 0.25, -TIME * 0.35));
	n.xz += (vec2(r1, r2) - 0.5) * ripple_strength;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n), 0.0)).xyz);

	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec4 col = mix(shallow_color, deep_color, clamp(dist / deep_distance, 0.0, 1.0));
	// How much water lies in front of whatever is behind it, along the view ray.
	float depth = texture(depth_texture, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
#else
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
#endif
	vec4 behind = INV_PROJECTION_MATRIX * ndc;
	behind.xyz /= behind.w;
	float thickness = max(-behind.z - (-VERTEX.z), 0.0);
	float shore = 1.0 - smoothstep(0.0, shore_width, thickness);
	col = mix(col, shore_color, shore * 0.85);
	// Foam: a broken, shifting line right at the edge.
	float edge = 1.0 - smoothstep(0.0, foam_width * (0.6 + 0.8 * r1), thickness);
	float breakup = smoothstep(0.35, 0.65, noise(p * 2.3 + vec2(TIME * 0.4, -TIME * 0.3)));
	float foam = edge * (0.5 + 0.5 * breakup);
	col = mix(col, foam_color, foam * foam_color.a);
	// Screen-space reflection: march the mirrored view ray until it passes behind the scene.
	vec3 view_dir = normalize(VERTEX);
	float facing = max(dot(-view_dir, NORMAL), 0.0);
	float fresnel = 0.04 + 0.96 * pow(1.0 - facing, 5.0);
	if (water_reflections > 0.5) {
		vec3 r = reflect(view_dir, NORMAL);
		vec3 pos = VERTEX;
		// Screen y may run the other way from clip space (depends on the renderer):
		// compare this pixel's own projection with SCREEN_UV.
		vec4 c0 = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
		bool flip_y = abs((c0.y / c0.w * 0.5 + 0.5) - SCREEN_UV.y) > 0.02;
		float step_len = 0.4;
		for (int i = 0; i < 40; i++) {
			pos += r * step_len;
			step_len *= 1.1;
			vec4 clip = PROJECTION_MATRIX * vec4(pos, 1.0);
			if (clip.w <= 0.0) break;
			vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
			if (flip_y) uv.y = 1.0 - uv.y;
			if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;
			float z = scene_z(uv, depth_texture, INV_PROJECTION_MATRIX);
			if (pos.z < z && pos.z > z - (1.0 + step_len * 2.0)) {
				vec3 seen = textureLod(screen_texture, uv, 1.0).rgb;
				vec2 edge = smoothstep(vec2(0.0), vec2(0.12), uv) * smoothstep(vec2(1.0), vec2(0.88), uv);
				float k = (0.15 + fresnel) * edge.x * edge.y * reflection_strength * (1.0 - 0.5 * float(i) / 40.0) * (1.0 - foam);
				col.rgb = mix(col.rgb, seen * 0.9, clamp(k, 0.0, 0.85));
				break;
			}
		}
	}
	ALBEDO = col.rgb;
	ALPHA = col.a;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
}
