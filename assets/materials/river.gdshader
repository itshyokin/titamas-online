shader_type spatial;
// Running water: rivers, streams and waterfalls (Blender planes in the Water collection
// named or textured "river" / "stream" / "falls", exported as "<name>-river").
// Downstream = the mesh's UV "up" (+V in Blender: unwrap a strip with Follow Active Quads,
// or a plain plane flows along its own +Y). Steep parts flow straight down and turn white.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.16, 0.42, 0.48, 0.72);
uniform vec4 deep_color : source_color = vec4(0.06, 0.2, 0.3, 0.9);
uniform vec4 foam_color : source_color = vec4(0.92, 0.97, 1.0, 0.92);
uniform vec4 shore_color : source_color = vec4(0.07, 0.15, 0.15, 0.9);
uniform float flow_speed = 1.6;      // m/s on the flat
uniform float fall_speed = 6.0;      // m/s down a waterfall
uniform float streak_scale = 0.55;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.35;
uniform float shore_width = 1.0;
uniform float foam_width = 0.4;
uniform float deep_distance = 120.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.12;
uniform float specular_value : hint_range(0.0, 1.0) = 0.4;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 world_pos;
varying vec3 flow_dir;
varying vec3 side_dir;

float hash(vec2 p) {
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
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (n.y < 0.0) n = -n;
	vec3 f = (MODEL_MATRIX * vec4(BINORMAL, 0.0)).xyz;
	f = length(f) > 0.001 ? normalize(f) : vec3(0.0, 0.0, -1.0);
	flow_dir = f;
	side_dir = normalize(cross(n, f));
}

void fragment() {
	// The face's own slope (smooth shading would blend a waterfall's edge into the flat).
	vec3 wn = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
	if (wn.y < 0.0) wn = -wn;
	float steep = 1.0 - smoothstep(0.45, 0.8, wn.y);
	vec3 f = normalize(flow_dir);
	vec3 down = vec3(0.0, -1.0, 0.0) - wn * dot(wn, vec3(0.0, -1.0, 0.0));
	if (length(down) > 0.05) {
		f = normalize(mix(f, normalize(down), steep));
	}
	vec3 s = normalize(cross(wn, f));
	float speed = mix(flow_speed, fall_speed, steep);
	// Coordinates across (x) and along (y) the current; the pattern slides downstream.
	vec2 q = vec2(dot(world_pos, s), dot(world_pos, f)) * streak_scale;
	float t = TIME * speed * streak_scale;
	float a = noise(vec2(q.x * 1.6, (q.y - t) * 0.45));
	float b = noise(vec2(q.x * 3.1 + 7.0, (q.y - t * 1.35) * 0.9));
	float c = noise(vec2(q.x * 0.7 - 3.0, (q.y - t * 0.8) * 0.3));
	// Ripples run across the current: tilt the normal along the flow.
	float ridge = (a - 0.5) * 0.5 + (b - 0.5) * 0.3;
	vec3 n = normalize(vec3(0.0, 1.0, 0.0) + f * ridge * 0.6 + s * (c - 0.5) * 0.25);
	if (steep > 0.5) {
		n = normalize(wn + s * (a - 0.5) * 0.4);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec4 col = mix(shallow_color, deep_color, clamp(dist / deep_distance, 0.0, 1.0));
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
	col = mix(col, shore_color, shore * 0.7 * (1.0 - steep));
	// White water: streaks on the current, foam along the banks, all over a waterfall.
	float streaks = smoothstep(0.62, 0.86, a * 0.6 + b * 0.55) * foam_amount;
	float edge = (1.0 - smoothstep(0.0, foam_width * (0.6 + 0.8 * c), thickness)) * (0.5 + 0.5 * b);
	float fall = steep * smoothstep(0.25, 0.75, a * 0.5 + b * 0.5 + 0.2);
	float foam = clamp(max(max(streaks, edge), fall), 0.0, 1.0);
	col = mix(col, foam_color, foam * foam_color.a);
	col.a = mix(col.a, 0.95, steep);
	ALBEDO = col.rgb;
	// White water glows a little so a waterfall in its own shadow still reads white.
	EMISSION = foam_color.rgb * foam * mix(0.08, 0.45, steep);
	ALPHA = col.a;
	ROUGHNESS = mix(roughness_value, 0.6, foam);
	SPECULAR = specular_value;
}
