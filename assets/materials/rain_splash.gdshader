shader_type spatial;
// A ring of spray where a drop lands: laid flat on whatever is highest at that spot
// (ground, roof, water) from the cover map, so there are none on floors under a roof.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://assets/materials/rain_cover.gdshaderinc"

uniform sampler2D ring : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(0.85, 0.92, 1.0, 1.0);
// 0 = stay at the height the emitter put them (no cover map).
uniform float on_cover = 1.0;

varying float fade;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	float size = max(length(MODEL_MATRIX[1].xyz), 0.0001);
	float h = rain_cover_height(centre.xz);
	if (on_cover > 0.5 && h > RAIN_COVER_NONE) {
		// Only where the surface is near the emitter's height (not far up a cliff or down a pit).
		VERTEX.y += (h + 0.06 - centre.y) / size;
	}
	fade = COLOR.a;
}

void fragment() {
	vec4 t = texture(ring, UV);
	ALBEDO = tint.rgb * t.rgb;
	ALPHA = t.a * fade * tint.a;
}
