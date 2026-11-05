shader_type spatial;
// Lock-on marker: four corner brackets around a target's body, facing the camera,
// gently pulsing. Drawn on a quad sized to the body.
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.35, 0.25, 1.0);
uniform float thickness = 0.035;
uniform float arm = 0.22;

void vertex() {
	// Billboard, keeping the quad's own size.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
}

void fragment() {
	float pulse = 0.04 * sin(TIME * 5.0);
	vec2 uv = (UV - 0.5) * (1.0 + pulse) + 0.5;
	vec2 d = min(uv, 1.0 - uv);  // distance to the nearest edges
	float t = thickness;
	bool near_x = d.x < t && d.y < arm;
	bool near_y = d.y < t && d.x < arm;
	if (!(near_x || near_y) || any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = color.a * (0.85 + 0.15 * sin(TIME * 5.0));
}
