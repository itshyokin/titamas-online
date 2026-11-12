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
global uniform vec2 cloud_offset;

// Set by WorldCycle (day/night). Without one, the sun comes from the scene's light.
uniform bool use_cycle = false;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
uniform float night_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 moon_color : source_color = vec3(0.85, 0.9, 1.0);
global uniform float wind_strength;
// Region sky picture (equirectangular panorama), blended over the gradient sky.
uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform float panorama_strength : hint_range(0.0, 1.0) = 0.0;
// How many stars show at night (region "stars").
uniform float stars_amount : hint_range(0.0, 2.0) = 1.0;
// Weather: storm clouds darken, rain mutes the sky.
uniform float cloud_darken : hint_range(0.0, 1.0) = 0.0;

// The ringed giant in the north (data/world.json "sky" → planet, set by AtmosphereManager).
uniform bool planet_on = true;
uniform vec3 planet_dir = vec3(0.0, 0.42, -0.91);
uniform float planet_radius = 0.16;        // sine of its angular radius
uniform float planet_tilt = 0.32;          // rings tipped toward us (radians)
uniform float planet_roll = 0.22;
uniform vec3 planet_band_a : source_color = vec3(0.93, 0.84, 0.66);
uniform vec3 planet_band_b : source_color = vec3(0.74, 0.58, 0.40);
uniform vec3 ring_color : source_color = vec3(0.88, 0.82, 0.70);
uniform float planet_day : hint_range(0.0, 1.0) = 0.45;  // how strongly it shows by day
// The moon: an artificial sphere with azure lines ("sky" → moon).
uniform float moon_radius = 0.042;
uniform vec3 moon_hull : source_color = vec3(0.62, 0.64, 0.68);
uniform vec3 moon_line_color : source_color = vec3(0.25, 0.78, 1.0);
uniform float moon_line_glow = 1.6;
// Shooting stars per minute at night ("sky" → shooting_stars).
uniform float shooting_stars = 4.0;

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

// Ray from the eye along `d` against a sphere at `c` (distance 1) of radius `r`: the
// distance to the near side, or -1.
float sphere_hit(vec3 d, vec3 c, float r) {
	float b = dot(d, c);
	float disc = b * b - (dot(c, c) - r * r);
	if (disc < 0.0 || b < 0.0) return -1.0;
	return b - sqrt(disc);
}

// The ringed planet over the dir: rgb + coverage in a.
vec4 planet(vec3 d, vec3 light) {
	vec3 c = normalize(planet_dir);
	float r = planet_radius;
	vec3 up = normalize(vec3(0.0, 1.0, 0.0) - c * c.y);
	vec3 east = normalize(cross(c, up));
	vec3 axis = normalize(up * cos(planet_tilt) - c * sin(planet_tilt) + east * planet_roll);
	float tp = sphere_hit(d, c, r);
	vec4 body = vec4(0.0);
	if (tp > 0.0) {
		vec3 n = normalize(d * tp - c);
		float lat = dot(n, axis);
		float lon = atan(dot(n, east), dot(n, -c));
		float wob = noise(vec2(lon * 3.0, lat * 18.0)) * 0.6;
		float bands = 0.5 + 0.5 * sin(lat * 34.0 + wob * 2.0) * (0.6 + 0.4 * sin(lat * 9.0));
		vec3 surf = mix(planet_band_a, planet_band_b, bands);
		surf = mix(surf, planet_band_b * 0.8, smoothstep(0.82, 0.98, abs(lat)));  // darker poles
		float lit = clamp(dot(n, light), 0.0, 1.0);
		float rim = pow(1.0 - clamp(dot(n, -d), 0.0, 1.0), 3.0);
		// The rings' shadow across the planet.
		vec3 sp = n * r - light * dot(n * r, axis) / (dot(light, axis) + sign(dot(light, axis)) * 0.001);
		float sr = length(sp) / r;
		float ring_shadow = (sr > 1.25 && sr < 2.3 && dot(n, axis) * dot(light, axis) < 0.0) ? 0.45 : 1.0;
		body = vec4(surf * (0.07 + 0.95 * lit * ring_shadow) + vec3(0.6, 0.7, 0.9) * rim * 0.15 * lit, 1.0);
	}
	// The rings: a flat disc round it.
	float den = dot(d, axis);
	vec4 ring = vec4(0.0);
	float tr = abs(den) > 0.0001 ? dot(c, axis) / den : -1.0;
	if (tr > 0.0) {
		vec3 q = d * tr - c;
		float rr = length(q) / r;
		if (rr > 1.28 && rr < 2.35) {
			float band = hash(vec2(floor(rr * 46.0), 3.0));
			float dens = mix(0.35, 0.95, band) * smoothstep(1.28, 1.36, rr) * smoothstep(2.35, 2.25, rr);
			dens *= 1.0 - smoothstep(0.0, 0.015, 0.03 - abs(rr - 1.98));  // the big gap
			// In the planet's shadow?
			float along = dot(c - d * tr, light);
			float off = length((c - d * tr) - light * along);
			float shade = (along < 0.0 && off < r) ? 0.18 : 1.0;
			float lit = 0.25 + 0.75 * abs(dot(axis, light));
			ring = vec4(ring_color * (0.85 + 0.3 * band) * lit * shade, dens);
		}
	}
	// Whichever is nearer goes in front.
	if (body.a > 0.0 && ring.a > 0.0 && tr < tp) {
		return vec4(mix(body.rgb, ring.rgb, ring.a), 1.0);
	}
	if (body.a > 0.0) return body;
	return ring;
}

// The moon: a man-made sphere, grey panels crossed by glowing azure lines.
vec4 station(vec3 d, vec3 m, vec3 light, float time) {
	float t = sphere_hit(d, m, moon_radius);
	if (t < 0.0) return vec4(0.0);
	vec3 n = normalize(d * t - m);
	vec3 up = normalize(vec3(0.0, 1.0, 0.0) - m * m.y);
	vec3 east = normalize(cross(m, up));
	float lat = asin(clamp(dot(n, up), -1.0, 1.0));
	float lon = atan(dot(n, east), dot(n, -m));
	vec2 cell = floor(vec2(lon * 9.0, lat * 9.0));
	vec3 hull = moon_hull * (0.82 + 0.18 * hash(cell));
	float lines = 0.0;
	lines = max(lines, 1.0 - smoothstep(0.0, 0.03, abs(lat)));                                   // equator
	lines = max(lines, (1.0 - smoothstep(0.0, 0.018, abs(fract(lat / 0.42 + 0.5) - 0.5) * 0.42)) * 0.8);
	lines = max(lines, (1.0 - smoothstep(0.0, 0.018, abs(fract(lon / 0.6 + 0.5) - 0.5) * 0.6)) * 0.6 * step(abs(lat), 1.1));
	// A few short glowing runs inside panels.
	float run = step(0.86, hash(cell + 11.0)) * (1.0 - smoothstep(0.0, 0.012, abs(fract(lat * 9.0) - 0.5) * 0.11));
	lines = max(lines, run * 0.7);
	float lit = clamp(dot(n, light), 0.0, 1.0);
	vec3 c = hull * (0.12 + 0.88 * lit) + moon_line_color * lines * moon_line_glow * (0.85 + 0.15 * sin(time * 1.3));
	return vec4(c, 1.0);
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 col;
	if (dir.y >= 0.0) {
		col = mix(horizon_color, top_color, pow(dir.y, 0.6));
	} else {
		col = mix(horizon_color, ground_color, clamp(-dir.y * 6.0, 0.0, 1.0));
	}

	if (panorama_strength > 0.0) {
		vec2 puv = vec2(atan(dir.x, -dir.z) / (2.0 * PI) + 0.5, acos(clamp(dir.y, -1.0, 1.0)) / PI);
		col = mix(col, texture(panorama, puv).rgb, panorama_strength);
	}

	// Sun, moon and stars.
	if (use_cycle) {
		float d = dot(dir, normalize(sun_direction));
		float above = smoothstep(-0.08, 0.02, sun_direction.y);
		float disc = smoothstep(sun_size, sun_size + 0.0003, d);
		float glow = pow(max(d, 0.0), 64.0 / max(sun_glow, 0.01)) * 0.35;
		col += sun_color * (disc * 4.0 + glow) * above;
		if (dir.y > 0.0 && night_amount > 0.0 && !AT_CUBEMAP_PASS) {
			// Stars: one per cell of a grid on the sky, twinkling.
			vec2 sp = dir.xz / (dir.y + 1.0) * 220.0;
			vec2 cell = floor(sp);
			float h = hash(cell);
			vec2 at = cell + vec2(hash(cell + 7.1), hash(cell + 3.3));
			float star = smoothstep(1.0, 0.0, length(sp - at) * 3.5) * step(0.88, h);
			star *= 0.6 + 0.4 * sin(TIME * (1.5 + h * 3.0) + h * 40.0);
			col += vec3(star) * night_amount * smoothstep(0.0, 0.25, dir.y) * (0.6 + h) * stars_amount * (1.0 - cloud_coverage * 0.8);
		}
		if (dir.y > 0.0 && night_amount > 0.0 && !AT_CUBEMAP_PASS && shooting_stars > 0.0) {
			// Shooting stars: three channels, each now and then streaking across the upper sky.
			vec2 q = dir.xz / (dir.y + 1.0);
			for (int i = 0; i < 3; i++) {
				float period = 180.0 / shooting_stars;
				float tt = TIME / period + float(i) * 0.37;
				float slot = floor(tt);
				float ph = fract(tt) * period;
				vec2 seed = vec2(slot, float(i) * 13.1);
				if (ph < 0.8 && hash(seed + 9.0) < 0.75) {
					vec2 start = (vec2(hash(seed), hash(seed + 1.7)) * 2.0 - 1.0) * 0.55;
					float ang = hash(seed + 4.2) * 6.2832;
					vec2 dv = vec2(cos(ang), sin(ang));
					float k = ph / 0.8;
					vec2 head = start + dv * 0.3 * k;
					vec2 tail = head - dv * (0.06 + 0.06 * k);
					vec2 pa = q - tail;
					vec2 ba = head - tail;
					float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
					float dd = length(pa - ba * h);
					float bright = (1.0 - smoothstep(0.0, 0.0022, dd)) * h * h * sin(k * 3.14159);
					col += vec3(1.0, 0.96, 0.88) * bright * 2.0 * night_amount * (1.0 - cloud_coverage * 0.9);
				}
			}
		}
		vec3 light = normalize(sun_direction);
		if (planet_on && !AT_CUBEMAP_PASS) {
			// Lit from above even when the sun is down (so its bands show at night).
			vec3 plight = normalize(vec3(light.x, abs(light.y) + 0.25, light.z));
			vec4 p = planet(dir, plight);
			float vis = mix(planet_day, 1.0, night_amount) * smoothstep(-0.02, 0.04, dir.y);
			col = mix(col, p.rgb, p.a * vis);
		}
		vec3 mdir = normalize(moon_direction);
		float m = dot(dir, mdir);
		float moon_up = night_amount * smoothstep(-0.05, 0.05, moon_direction.y);
		vec3 mlight = normalize(light + vec3(0.0, 0.45, 0.0) + cross(mdir, vec3(0.0, 1.0, 0.0)) * 0.4);
		vec4 st = station(dir, mdir, mlight, TIME);
		float moon_glow = pow(max(m, 0.0), 160.0) * 0.18;
		col = mix(col, st.rgb, st.a * moon_up);
		col += moon_line_color * moon_glow * moon_up;
	} else if (LIGHT0_ENABLED) {
		float d = dot(dir, LIGHT0_DIRECTION);
		float disc = smoothstep(sun_size, sun_size + 0.0003, d);
		float glow = pow(max(d, 0.0), 64.0 / max(sun_glow, 0.01)) * 0.35;
		col += sun_color * (disc * 4.0 + glow) * LIGHT0_ENERGY;
		if (planet_on && !AT_CUBEMAP_PASS) {
			vec4 p = planet(dir, LIGHT0_DIRECTION);
			col = mix(col, p.rgb, p.a * planet_day * smoothstep(-0.02, 0.04, dir.y));
		}
	}

	// Clouds on a flat layer above, fading out towards the horizon.
	if (dir.y > 0.0 && !AT_CUBEMAP_PASS) {
		// With the day cycle, WorldCycle moves the clouds (always the same way, faster
		// in stronger wind); otherwise they drift at a fixed speed.
		vec2 drift = use_cycle ? cloud_offset : mod(vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4), 1000.0);
		vec2 uv = dir.xz / (dir.y + 0.15) * cloud_scale + drift;
		float n = fbm(uv * 2.0);
		float c = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.25, n);
		float shade = fbm(uv * 2.0 + vec2(0.08, 0.08));
		vec3 cloud = mix(cloud_color, cloud_shade, smoothstep(0.4, 0.8, shade));
		cloud = mix(cloud, cloud_shade * 0.45, cloud_darken);
		float fade = smoothstep(0.0, 0.25, dir.y);
		col = mix(col, cloud, c * fade * 0.9);
	}
	COLOR = col;
}
