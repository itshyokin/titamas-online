shader_type sky;
// Stylised sky: colour gradient, sun disc with glow, and drifting procedural clouds.
// Colours are driven per region by AtmosphereManager.

uniform vec3 top_color : source_color = vec3(0.24, 0.45, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.70, 0.80, 0.90);
uniform vec3 ground_color : source_color = vec3(0.32, 0.36, 0.40);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.75);
uniform float sun_size = 0.9995;
uniform float sun_glow = 6.0;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.70, 0.74, 0.82);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_scale = 0.6;
uniform float cloud_speed = 0.01;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 col;
	if (dir.y >= 0.0) {
		col = mix(horizon_color, top_color, pow(dir.y, 0.6));
	} else {
		col = mix(horizon_color, ground_color, clamp(-dir.y * 6.0, 0.0, 1.0));
	}

	// Sun.
	if (LIGHT0_ENABLED) {
		float d = dot(dir, LIGHT0_DIRECTION);
		float disc = smoothstep(sun_size, sun_size + 0.0003, d);
		float glow = pow(max(d, 0.0), 64.0 / max(sun_glow, 0.01)) * 0.35;
		col += sun_color * (disc * 4.0 + glow) * LIGHT0_ENERGY;
	}

	// Clouds on a flat layer above, fading out towards the horizon.
	if (dir.y > 0.0 && !AT_CUBEMAP_PASS) {
		vec2 uv = dir.xz / (dir.y + 0.15) * cloud_scale + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		float n = fbm(uv * 2.0);
		float c = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.25, n);
		float shade = fbm(uv * 2.0 + vec2(0.08, 0.08));
		vec3 cloud = mix(cloud_color, cloud_shade, smoothstep(0.4, 0.8, shade));
		float fade = smoothstep(0.0, 0.25, dir.y);
		col = mix(col, cloud, c * fade * 0.9);
	}
	COLOR = col;
}
