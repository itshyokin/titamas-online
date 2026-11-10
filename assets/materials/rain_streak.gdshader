shader_type spatial;
// A falling streak (rain; snow can use it with a square mesh): turned to the camera
// around the direction it falls, and not drawn under cover (rain_cover.gdshaderinc), so
// from indoors the rain is still falling outside the door.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://assets/materials/rain_cover.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.75, 0.82, 0.95, 0.35);
// Which way is "up" along the streak (the opposite of where it falls: leans with the wind).
uniform vec3 streak_up = vec3(0.0, 1.0, 0.0);
// 0 = the whole quad (a rain streak), 1 = a soft round dot (a snowflake).
uniform float round_dot : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 up = normalize(streak_up);
	vec3 to_cam = CAMERA_POSITION_WORLD - centre;
	vec3 right = cross(up, to_cam);
	right = length(right) > 0.0001 ? normalize(right) : vec3(1.0, 0.0, 0.0);
	// Under a roof (or below the ground / water): nothing to draw.
	float show = step(rain_cover_height(centre.xz), centre.y - 0.2);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * show, 0.0), vec4(up * show, 0.0), vec4(cross(right, up) * show, 0.0), vec4(centre, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a * mix(1.0, smoothstep(0.5, 0.28, length(UV - vec2(0.5))), round_dot);
}
