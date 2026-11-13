shader_type canvas_item;
// The retro look over the 3D picture (RetroFilter, Settings → Retro): chunky pixels,
// fewer colours with ordered dithering, scanlines. The HUD sits above it, untouched.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float block = 3.0;          // screen pixels per game pixel (1 = off)
uniform float levels = 32.0;        // colour steps per channel (256 = off)
uniform float dither = 1.0;         // 0..1
uniform float scanlines = 0.0;      // 0..1
uniform float vignette = 0.0;       // 0..1

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	// 4x4 Bayer matrix, 0..15
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0 - 0.5;
}

void fragment() {
	vec2 px = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 cell = floor(FRAGCOORD.xy / block);
	vec2 uv = (cell + 0.5) * block / px;
	vec3 c = texture(screen_tex, uv).rgb;
	if (levels < 255.0) {
		float steps = levels - 1.0;
		c += bayer4(cell) * dither / steps;
		c = floor(clamp(c, 0.0, 1.0) * steps + 0.5) / steps;
	}
	if (scanlines > 0.0) {
		float row = mod(cell.y, 2.0);
		c *= 1.0 - scanlines * 0.15 * row;
	}
	if (vignette > 0.0) {
		vec2 d = SCREEN_UV - 0.5;
		c *= 1.0 - vignette * smoothstep(0.35, 0.85, length(d * vec2(1.2, 1.0)));
	}
	COLOR = vec4(c, 1.0);
}
