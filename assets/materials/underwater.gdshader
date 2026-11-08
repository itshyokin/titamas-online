shader_type canvas_item;
// Full-screen look while the camera is under water: wobble, blur, blue-green tint,
// darker with depth and towards the edges.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.12, 0.45, 0.5);
uniform float depth = 0.0; // metres below the surface

void fragment() {
	vec2 uv = SCREEN_UV;
	uv += vec2(sin(uv.y * 28.0 + TIME * 1.9), cos(uv.x * 23.0 + TIME * 1.6)) * 0.0045;
	vec3 c = textureLod(screen, uv, 1.6).rgb;
	float murk = clamp(0.55 + depth * 0.04, 0.55, 0.85);
	vec3 water = tint * (1.0 - clamp(depth * 0.03, 0.0, 0.6));
	c = mix(c * vec3(0.55, 0.9, 1.0), water, murk * 0.6);
	// Light from above: brighter at the top of the screen.
	c *= 0.75 + 0.35 * (1.0 - SCREEN_UV.y);
	float vignette = smoothstep(1.2, 0.35, length(SCREEN_UV - 0.5) * 1.6);
	COLOR = vec4(c * mix(0.55, 1.0, vignette), 1.0);
}
