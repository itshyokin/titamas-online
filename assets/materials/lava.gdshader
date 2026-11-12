shader_type spatial;
// Lava (chunk meshes named *-lava, WaterVolume.lava): slow flowing glowing crust, opaque,
// pixel-stepped to match the rest. The light it casts comes from OmniLights ChunkStreamer adds.
render_mode diffuse_lambert, specular_disabled;

uniform vec3 hot_color : source_color = vec3(0.95, 0.32, 0.04);
uniform vec3 bright_color : source_color = vec3(1.0, 0.72, 0.22);
uniform vec3 crust_color : source_color = vec3(0.2, 0.08, 0.05);
uniform float scale = 0.22;
uniform float flow_speed = 0.06;
uniform float glow : hint_range(0.0, 8.0) = 1.3;
uniform float crust : hint_range(0.0, 1.0) = 0.56;
uniform float wave_height = 0.06;
// Pixel steps per metre (0 = smooth).
uniform float pixels_per_metre = 6.0;
uniform float tones = 5.0;

varying vec3 world_pos;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * a;
		p = p * 2.1 + 3.7;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += (vnoise(world_pos.xz * 0.5 + TIME * 0.15) - 0.5) * wave_height;
}

void fragment() {
	vec2 p = world_pos.xz;
	if (pixels_per_metre > 0.0) {
		p = floor(p * pixels_per_metre) / pixels_per_metre;
	}
	float t = TIME * flow_speed;
	vec2 q = p * scale;
	// Domain-warped noise drifting two ways: crust plates over a hot flow.
	vec2 warp = vec2(fbm(q + vec2(t, -t * 0.7)), fbm(q + vec2(-t * 0.6, t) + 9.2));
	float n = fbm(q * 1.7 + warp * 1.8 + vec2(t * 0.5, t * 0.3));
	float cracks = smoothstep(crust - 0.08, crust + 0.12, n);  // 0 crust, 1 molten
	float heat = clamp(cracks * (0.6 + 0.6 * fbm(q * 3.0 - t)), 0.0, 1.0);
	if (tones > 1.0) {
		heat = floor(heat * tones + 0.5) / tones;
	}
	vec3 molten = mix(hot_color, bright_color, smoothstep(0.55, 1.0, heat));
	// Crust: dark rock with a little grain, glowing faintly near the cracks.
	float grain = vnoise(p * 3.1) * 0.5 + 0.5;
	vec3 rock = crust_color * (0.7 + 0.5 * grain);
	vec3 col = mix(rock, molten, heat);
	ALBEDO = col * 0.5;
	EMISSION = molten * heat * glow + hot_color * smoothstep(crust - 0.2, crust, n) * 0.25;
	ROUGHNESS = mix(1.0, 0.6, heat);
}
